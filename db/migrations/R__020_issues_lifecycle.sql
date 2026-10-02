-- [issues 모듈] 호 상태 전이 / 상태 변경 함수 / 진행상태 뷰
-- Flyway 반복 마이그레이션: 내용이 바뀌면 다음 migrate 때 자동 재적용된다. 파일명 번호 순서로 적용된다.
-- 소유 테이블/의존 방향은 docs/architecture.md 와 db/tests/architecture.sql 참고.

-- 호 진행상태: 전이 규칙 / 상태 변경 함수 / 직접 변경 차단 / 조회 뷰
-- 조회 API(api_progress.md)는 v_issue_progress 를 그대로 읽는다.

-- =========================================================
-- 1. 허용된 상태 전이
-- =========================================================
DELETE FROM issue_status_transition;
INSERT INTO issue_status_transition (from_status, to_status, note) VALUES
    ('collecting', 'closing',    '마감: 선별 + 자동 조판 시작'),
    ('collecting', 'skipped',    '수집량 미달 등으로 이번 달 미발행'),
    ('closing',    'review',     '조판 완료, 미리보기·재조판 요청 기간(review_window_hours) 시작'),
    ('closing',    'collecting', '마감 취소(재오픈) - 새 close_at 필요'),
    ('review',     'closing',    '재조판 요청으로 다시 조판'),
    ('review',     'printing',   '검토 기간(review_window_hours) 경과 - 자동 전환, 승인 절차 없음 (advance_reviewed_issues)'),
    ('printing',   'printed',    '인쇄 완료/출고'),
    ('printing',   'review',     '프리플라이트 실패 등으로 복귀 (재조판 요청 가능하도록)'),
    ('printed',    'archived',   '보관'),
    ('skipped',    'closing',    '관리자 강제 발행 (사진이 부족해도 조판)'),
    ('skipped',    'collecting', '재오픈 - 새 close_at 필요'),
    ('skipped',    'archived',   '보관');

-- =========================================================
-- 2. 상태 변경 (전이 검증 + 사전조건 + 이력 기록)
--    issue.status 는 이 함수로만 바꿀 수 있다 (아래 트리거가 직접 UPDATE 를 막음).
--    사전조건
--      collecting 으로 되돌릴 때 : p_close_at 이 미래여야 함 (안 그러면 배치가 곧바로 다시 닫음)
--      review   : 완료(done)된 조판이 있어야 함
--      printing : review 에서 전이표를 통해서만 들어옴 (승인 절차 없음, advance_reviewed_issues 가 자동 호출)
--      printed  : 최신 조판+최신 수정 번호와 일치하는 ready 인쇄 작업이 있어야 함
--    closing 으로 들어가거나 closing 에서 재오픈하면 이전 조판 실행은 superseded 처리
-- =========================================================
DROP FUNCTION IF EXISTS change_issue_status(uuid, text, uuid, text);

CREATE OR REPLACE FUNCTION change_issue_status(
    p_issue uuid, p_to text, p_by uuid DEFAULT NULL, p_note text DEFAULT NULL,
    p_close_at timestamptz DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    v_from text;
    v_run  uuid;
BEGIN
    SELECT status INTO v_from FROM issue WHERE id = p_issue FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'issue % not found', p_issue;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM issue_status_transition
                    WHERE from_status = v_from AND to_status = p_to) THEN
        RAISE EXCEPTION 'invalid transition: % -> %', v_from, p_to
            USING ERRCODE = 'check_violation';
    END IF;

    -- ---- 사전조건 ----
    IF p_to = 'collecting' AND (p_close_at IS NULL OR p_close_at <= now()) THEN
        RAISE EXCEPTION 'reopening requires a future close_at'
            USING ERRCODE = 'check_violation';
    END IF;

    IF p_to = 'review' AND NOT EXISTS (
            SELECT 1 FROM layout_run WHERE issue_id = p_issue AND status = 'done') THEN
        RAISE EXCEPTION 'cannot enter review: no completed layout run'
            USING ERRCODE = 'check_violation';
    END IF;

    IF p_to = 'printed' THEN
        SELECT id INTO v_run FROM layout_run
         WHERE issue_id = p_issue AND status = 'done'
         ORDER BY seq DESC LIMIT 1;
        IF NOT EXISTS (
                SELECT 1 FROM print_job j
                 WHERE j.issue_id = p_issue AND j.status = 'ready' AND j.run_id = v_run
                   AND j.override_seq >= COALESCE(
                         (SELECT max(o.seq) FROM override o WHERE o.run_id = j.run_id), 0)) THEN
            RAISE EXCEPTION 'cannot enter printed: no ready print job for the latest version'
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- ---- 이전 조판 무효화 (실패 기록 포함: 새 마감 주기는 실패 횟수를 0부터 센다) ----
    IF p_to = 'closing' OR (v_from = 'closing' AND p_to = 'collecting') THEN
        UPDATE layout_run SET status = 'superseded'
         WHERE issue_id = p_issue AND status IN ('queued', 'running', 'done', 'failed');
    END IF;

    PERFORM set_config('app.status_via_fn', 'on', true);
    UPDATE issue
       SET status = p_to,
           status_changed_at = now(),
           closed_at = CASE WHEN p_to = 'closing'    THEN now()
                            WHEN p_to = 'collecting' THEN NULL
                            ELSE closed_at END,
           close_at  = CASE WHEN p_to = 'collecting' THEN p_close_at ELSE close_at END,
           close_attempts = CASE WHEN p_to IN ('collecting','closing','skipped') THEN 0 ELSE close_attempts END,
           close_error    = CASE WHEN p_to IN ('collecting','closing','skipped') THEN NULL ELSE close_error END
     WHERE id = p_issue;
    PERFORM set_config('app.status_via_fn', 'off', true);

    INSERT INTO issue_status_history (issue_id, from_status, to_status, changed_by, note)
    VALUES (p_issue, v_from, p_to, p_by, p_note);

    RETURN p_to;
END $$;

-- =========================================================
-- 3. issue.status 직접 UPDATE 차단 (실수 방지용 가드레일, 보안 장치는 아님)
-- =========================================================
CREATE OR REPLACE FUNCTION issue_status_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status
       AND COALESCE(current_setting('app.status_via_fn', true), 'off') <> 'on' THEN
        RAISE EXCEPTION 'issue.status must be changed via change_issue_status()'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_issue_status_guard ON issue;
CREATE TRIGGER trg_issue_status_guard
    BEFORE UPDATE OF status ON issue
    FOR EACH ROW EXECUTE FUNCTION issue_status_guard();

-- =========================================================
-- 4. 진행상태 조회 뷰
--    current_step : 사용자에게 보여줄 세부 단계 (status 보다 세분화)
--    progress_pct : 0~100 (대략적인 진행률, UI 진행바용)
--    review_deadline / can_request_relayout : 승인 절차가 없으므로 "언제까지 미리보기·재조판 요청이 가능한지"를
--      그룹의 review_window_hours 로 계산해 둔다. 지나면 advance_reviewed_issues() 가 자동으로 printing 전환한다.
--    마감 자동 재시도 상한(5)은 batch.sql 과 같은 값
-- =========================================================
DROP VIEW IF EXISTS v_issue_progress;

CREATE VIEW v_issue_progress AS
SELECT
    i.id                AS issue_id,
    i.group_id,
    i.title,
    i.period_start,
    i.period_end,
    i.status,
    i.status_changed_at,
    i.close_at,
    i.closed_at,
    i.close_attempts,
    i.close_error,
    (i.status = 'collecting' AND now() > i.close_at)          AS is_overdue,

    mem.total_members,
    mem.submitted_members,

    md.total_media,
    md.selected_media,
    md.excluded_media,
    i.min_photos,
    i.max_photos,

    lr.run_id           AS latest_run_id,
    lr.run_status       AS latest_run_status,
    COALESCE(pgs.total_pages, 0)              AS total_pages,

    i.status_changed_at + make_interval(hours => g.review_window_hours) AS review_deadline,
    (i.status = 'review'
        AND now() < i.status_changed_at + make_interval(hours => g.review_window_hours)
    ) AS can_request_relayout,

    pj.print_job_status,
    po.print_order_status,

    step.current_step,

    COALESCE(CASE step.current_step
        WHEN 'collecting'       THEN round(20.0 * mem.submitted_members / NULLIF(mem.total_members, 0))
        WHEN 'close_failed'     THEN 20
        WHEN 'selecting'        THEN 30
        WHEN 'composing'        THEN 40
        WHEN 'compose_failed'   THEN 40
        WHEN 'reviewing'        THEN 70
        WHEN 'printing'         THEN 90
        WHEN 'preflight_failed' THEN 88
        WHEN 'shipping'         THEN 95
        WHEN 'order_cancelled'  THEN 90
        WHEN 'delivered'        THEN 100
        WHEN 'skipped'          THEN 100
        WHEN 'archived'         THEN 100
    END, 0)::int AS progress_pct
FROM issue i
JOIN family_group g ON g.id = i.group_id
LEFT JOIN LATERAL (
    -- 구성원 = 이 그룹에서 활동 중인 사람, 제출 = 이 호의 기간에 글을 올린 사람
    SELECT count(*)::int AS total_members,
           count(*) FILTER (WHERE EXISTS (
               SELECT 1 FROM post po
                WHERE po.group_id = fm.group_id AND po.author_id = fm.user_id AND po.deleted_at IS NULL
                  AND (po.posted_at AT TIME ZONE g.timezone)::date BETWEEN i.period_start AND i.period_end))::int AS submitted_members
      FROM family_member fm
     WHERE fm.group_id = i.group_id AND fm.left_at IS NULL
) mem ON true
LEFT JOIN LATERAL (
    SELECT count(*)::int AS total_media,
           count(*) FILTER (WHERE selection_status = 'selected')::int AS selected_media,
           count(*) FILTER (WHERE selection_status IN ('excluded_auto','excluded_manual'))::int AS excluded_media
      FROM issue_media WHERE issue_id = i.id
) md ON true
LEFT JOIN LATERAL (
    SELECT id AS run_id, status AS run_status
      FROM layout_run WHERE issue_id = i.id AND status <> 'superseded'
     ORDER BY seq DESC LIMIT 1
) lr ON true
LEFT JOIN LATERAL (
    SELECT count(*)::int AS total_pages
      FROM page pg
     WHERE pg.run_id = lr.run_id
) pgs ON true
LEFT JOIN LATERAL (
    SELECT status AS print_job_status
      FROM print_job WHERE issue_id = i.id ORDER BY seq DESC LIMIT 1
) pj ON true
LEFT JOIN LATERAL (
    SELECT o.status AS print_order_status
      FROM print_order o JOIN print_job j ON j.id = o.print_job_id
     WHERE j.issue_id = i.id ORDER BY o.seq DESC LIMIT 1
) po ON true
CROSS JOIN LATERAL (
    SELECT CASE i.status
        WHEN 'collecting' THEN
            CASE WHEN i.close_attempts >= 5 THEN 'close_failed' ELSE 'collecting' END
        WHEN 'closing' THEN
            CASE WHEN lr.run_status = 'failed'                  THEN 'compose_failed'
                 WHEN lr.run_id IS NULL AND md.selected_media = 0 THEN 'selecting'
                 ELSE 'composing' END
        WHEN 'review'   THEN 'reviewing'
        WHEN 'printing' THEN
            CASE WHEN pj.print_job_status IN ('preflight_failed','failed') THEN 'preflight_failed'
                 ELSE 'printing' END
        WHEN 'printed'  THEN
            CASE po.print_order_status
                WHEN 'delivered' THEN 'delivered'
                WHEN 'cancelled' THEN 'order_cancelled'
                ELSE 'shipping' END
        WHEN 'skipped'  THEN 'skipped'
        WHEN 'archived' THEN 'archived'
    END AS current_step
) step;
