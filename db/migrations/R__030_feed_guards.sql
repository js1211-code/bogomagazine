-- [feed 모듈] 게시 가드 (마감된 기간에는 글/사진을 넣을 수 없고, 작성자는 활동 중인 구성원이어야 한다)
-- Flyway 반복 마이그레이션: 내용이 바뀌면 다음 migrate 때 자동 재적용된다. 파일명 번호 순서로 적용된다.
-- 소유 테이블/의존 방향은 docs/architecture.md 와 db/tests/architecture.sql 참고.


-- 이미 마감된(수집 중이 아닌) 호의 기간에 속하는 글/사진은 넣을 수 없다.
-- 호 행을 FOR SHARE 로 잠가 마감 배치(FOR UPDATE)와 직렬화한다.
--   - 배치가 먼저 잠그면: 게시는 배치가 끝날 때까지 기다린 뒤 closing 을 보고 거부됨
--   - 게시가 먼저면: 배치는 그 호를 건너뛰고(SKIP LOCKED) 다음 호출에서 처리
--   => 선별이 끝난 뒤에 들어온 글/사진이 조용히 누락되는 일이 없다.
-- 기간에 해당하는 호가 아직 만들어지지 않았으면(이번 달 배치가 돌기 전) 허용한다.
-- 마감 시각(close_at) 자체는 DB 가 강제하지 않는다. 배치가 호를 닫기 전까지는 받는다.
-- 사진 업로드 유예(POST-07, 1004 결정): p_upload_started_at(사진의 initiated_at)이 마감 전이면
-- 마감 후 14분까지는 받는다(23:59 전 시작 -> 다음날 00:14까지, close_at=00:00 기준 14분). 사진이 없는 글/답변/댓글은 유예가 없다(호출자가 생략하면 하드컷).
CREATE OR REPLACE FUNCTION assert_period_open(p_group uuid, p_ts timestamptz, p_upload_started_at timestamptz DEFAULT NULL) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_status   text;
    v_close_at timestamptz;
BEGIN
    SELECT i.status, i.close_at INTO v_status, v_close_at
      FROM issue i JOIN family_group g ON g.id = i.group_id
     WHERE i.group_id = p_group
       AND (p_ts AT TIME ZONE g.timezone)::date BETWEEN i.period_start AND i.period_end
       FOR SHARE OF i;
    IF NOT FOUND OR v_status = 'collecting' THEN
        RETURN;
    END IF;
    IF p_upload_started_at IS NOT NULL AND p_upload_started_at <= v_close_at AND now() <= v_close_at + interval '14 minutes' THEN
        RETURN;
    END IF;
    RAISE EXCEPTION 'the issue for this period is not collecting (status=%): posting not allowed', v_status
        USING ERRCODE = 'check_violation';
END $$;

-- 금칙어(SAFE-03): 등록 시점에 본문에 포함되어 있으면 거부. 목록은 팀이 직접 관리(banned_word)
CREATE OR REPLACE FUNCTION assert_no_banned_word(p_body text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF p_body IS NULL THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM banned_word WHERE p_body ILIKE '%' || word || '%') THEN
        RAISE EXCEPTION 'content contains a banned word' USING ERRCODE = 'check_violation';
    END IF;
END $$;

-- 글: 작성자는 그 그룹에서 활동 중인 구성원이어야 하고, 마감된 기간에는 올릴 수 없고, 금칙어를 포함할 수 없다
CREATE OR REPLACE FUNCTION guard_post_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM assert_period_open(NEW.group_id, NEW.posted_at);
    PERFORM assert_no_banned_word(NEW.body);
    IF NOT is_active_member(NEW.group_id, NEW.author_id) THEN
        RAISE EXCEPTION 'post: user % is not an active member of group %', NEW.author_id, NEW.group_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_post_insert ON post;
CREATE TRIGGER trg_post_insert BEFORE INSERT ON post
    FOR EACH ROW EXECUTE FUNCTION guard_post_insert();

-- 글의 날짜를 마감된 기간으로 옮길 수 없다 (날짜를 거슬러 올라가 마감된 호에 끼워 넣는 것을 막는다)
CREATE OR REPLACE FUNCTION guard_post_period_update() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM assert_period_open(NEW.group_id, NEW.posted_at);
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_post_period_update ON post;
CREATE TRIGGER trg_post_period_update BEFORE UPDATE OF posted_at, group_id ON post
    FOR EACH ROW EXECUTE FUNCTION guard_post_period_update();

-- 사진: 글이 속한 기간이 마감되었으면 붙일 수 없다
CREATE OR REPLACE FUNCTION guard_media_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_group uuid;
    v_ts    timestamptz;
BEGIN
    SELECT group_id, posted_at INTO v_group, v_ts FROM post WHERE id = NEW.post_id;
    IF FOUND THEN
        PERFORM assert_period_open(v_group, v_ts, NEW.initiated_at);
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_media_insert ON media;
CREATE TRIGGER trg_media_insert BEFORE INSERT ON media
    FOR EACH ROW EXECUTE FUNCTION guard_media_insert();

-- 댓글(QST-06): 질문 답변에만 달 수 있고, 작성자는 활동 중인 구성원, 마감된 기간에는 불가
CREATE OR REPLACE FUNCTION guard_comment_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_group uuid; v_ts timestamptz; v_qid uuid;
BEGIN
    SELECT group_id, posted_at, question_id INTO v_group, v_ts, v_qid FROM post WHERE id = NEW.post_id;
    IF v_qid IS NULL THEN
        RAISE EXCEPTION 'comment: post % is not a question answer', NEW.post_id
            USING ERRCODE = 'check_violation';
    END IF;
    PERFORM assert_period_open(v_group, v_ts);
    PERFORM assert_no_banned_word(NEW.body);
    IF NOT is_active_member(v_group, NEW.author_id) THEN
        RAISE EXCEPTION 'comment: user % is not an active member of group %', NEW.author_id, v_group
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_comment_insert ON comment;
CREATE TRIGGER trg_comment_insert BEFORE INSERT ON comment
    FOR EACH ROW EXECUTE FUNCTION guard_comment_insert();

-- 신고가 들어오면 운영 알림 대상에 올린다(ADM-08, SAFE-01). FK 가 아니라 함수 수준 결합이다
-- (admin 모듈 테이블에 쓴다 - docs/architecture.md "알려진 예외" 참고)
CREATE OR REPLACE FUNCTION alert_on_report() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO operator_alert_log (kind, ref_type, ref_id) VALUES ('report_received', 'report', NEW.id);
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_alert_on_report ON report;
CREATE TRIGGER trg_alert_on_report AFTER INSERT ON report
    FOR EACH ROW EXECUTE FUNCTION alert_on_report();

-- =========================================================
-- 글/사진/댓글 수정·삭제(POST-06, QST-04/06): 본인만, 마감 전까지만.
-- 앱은 테이블을 직접 UPDATE/DELETE 하지 않고 이 함수들을 거쳐야 한다(다른 actor 확인 함수들과 같은 방식).
-- 삭제는 모두 소프트 삭제(deleted_at)다 - 물리 삭제 아님.
-- =========================================================
CREATE OR REPLACE FUNCTION update_post(p_post uuid, p_actor uuid, p_body text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_author uuid; v_group uuid; v_ts timestamptz; v_deleted timestamptz;
BEGIN
    SELECT author_id, group_id, posted_at, deleted_at INTO v_author, v_group, v_ts, v_deleted
      FROM post WHERE id = p_post FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'post % not found', p_post; END IF;
    IF v_deleted IS NOT NULL THEN
        RAISE EXCEPTION 'post % is deleted' , p_post USING ERRCODE = 'check_violation';
    END IF;
    IF p_actor <> v_author THEN
        RAISE EXCEPTION 'only the author can edit this post' USING ERRCODE = 'insufficient_privilege';
    END IF;
    PERFORM assert_period_open(v_group, v_ts);
    PERFORM assert_no_banned_word(p_body);
    UPDATE post SET body = p_body, updated_at = now() WHERE id = p_post;
END $$;

CREATE OR REPLACE FUNCTION delete_post(p_post uuid, p_actor uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_author uuid; v_group uuid; v_ts timestamptz; v_deleted timestamptz;
BEGIN
    SELECT author_id, group_id, posted_at, deleted_at INTO v_author, v_group, v_ts, v_deleted
      FROM post WHERE id = p_post FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'post % not found', p_post; END IF;
    IF v_deleted IS NOT NULL THEN RETURN; END IF;  -- 이미 지워짐: 멱등
    IF p_actor <> v_author THEN
        RAISE EXCEPTION 'only the author can delete this post' USING ERRCODE = 'insufficient_privilege';
    END IF;
    PERFORM assert_period_open(v_group, v_ts);
    UPDATE post SET deleted_at = now() WHERE id = p_post;
END $$;

-- 사진 삭제(소프트, NFR-11): 그 글의 작성자만, 마감 전까지만
CREATE OR REPLACE FUNCTION delete_media(p_media uuid, p_actor uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_author uuid; v_group uuid; v_ts timestamptz; v_deleted timestamptz;
BEGIN
    SELECT p.author_id, p.group_id, p.posted_at, m.deleted_at
      INTO v_author, v_group, v_ts, v_deleted
      FROM media m JOIN post p ON p.id = m.post_id
     WHERE m.id = p_media FOR UPDATE OF m;
    IF NOT FOUND THEN RAISE EXCEPTION 'media % not found', p_media; END IF;
    IF v_deleted IS NOT NULL THEN RETURN; END IF;  -- 이미 지워짐: 멱등
    IF p_actor <> v_author THEN
        RAISE EXCEPTION 'only the post author can delete this photo' USING ERRCODE = 'insufficient_privilege';
    END IF;
    PERFORM assert_period_open(v_group, v_ts);
    UPDATE media SET deleted_at = now() WHERE id = p_media;
END $$;

CREATE OR REPLACE FUNCTION update_comment(p_comment uuid, p_actor uuid, p_body text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_author uuid; v_group uuid; v_ts timestamptz; v_deleted timestamptz;
BEGIN
    SELECT c.author_id, p.group_id, p.posted_at, c.deleted_at
      INTO v_author, v_group, v_ts, v_deleted
      FROM comment c JOIN post p ON p.id = c.post_id
     WHERE c.id = p_comment FOR UPDATE OF c;
    IF NOT FOUND THEN RAISE EXCEPTION 'comment % not found', p_comment; END IF;
    IF v_deleted IS NOT NULL THEN
        RAISE EXCEPTION 'comment % is deleted', p_comment USING ERRCODE = 'check_violation';
    END IF;
    IF p_actor <> v_author THEN
        RAISE EXCEPTION 'only the author can edit this comment' USING ERRCODE = 'insufficient_privilege';
    END IF;
    PERFORM assert_period_open(v_group, v_ts);
    PERFORM assert_no_banned_word(p_body);
    UPDATE comment SET body = p_body WHERE id = p_comment;
END $$;

CREATE OR REPLACE FUNCTION delete_comment(p_comment uuid, p_actor uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_author uuid; v_group uuid; v_ts timestamptz; v_deleted timestamptz;
BEGIN
    SELECT c.author_id, p.group_id, p.posted_at, c.deleted_at
      INTO v_author, v_group, v_ts, v_deleted
      FROM comment c JOIN post p ON p.id = c.post_id
     WHERE c.id = p_comment FOR UPDATE OF c;
    IF NOT FOUND THEN RAISE EXCEPTION 'comment % not found', p_comment; END IF;
    IF v_deleted IS NOT NULL THEN RETURN; END IF;  -- 이미 지워짐: 멱등
    IF p_actor <> v_author THEN
        RAISE EXCEPTION 'only the author can delete this comment' USING ERRCODE = 'insufficient_privilege';
    END IF;
    PERFORM assert_period_open(v_group, v_ts);
    UPDATE comment SET deleted_at = now() WHERE id = p_comment;
END $$;
