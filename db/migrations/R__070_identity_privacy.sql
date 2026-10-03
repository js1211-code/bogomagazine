-- [identity 모듈] 회원 탈퇴 익명화
-- Flyway 반복 마이그레이션: 내용이 바뀌면 다음 migrate 때 자동 재적용된다. 파일명 번호 순서로 적용된다.
-- 소유 테이블/의존 방향은 docs/architecture.md 와 db/tests/architecture.sql 참고.


-- 회원 탈퇴: 사용자 행을 지우지 않고 익명화한다.
-- (사용자를 참조하는 외래키가 많아 삭제하면 가족의 글/기록이 깨지거나 삭제 자체가 막힌다.)
--
-- 이 함수가 하는 일
--   * app_user       : 이메일/이름 제거, deleted_at 기록 (id 는 유지)
--   * auth_identity  : 전부 삭제 -> 같은 카카오/애플 계정으로 더 이상 로그인되지 않음
--   * family_member  : 행은 남기고 left_at 만 채움 (그 사람이 쓴 글의 작성자 정보를 유지하려고)
--   * page_lock      : 제거
--   * post/media     : 모집 중(status='collecting')인 호의 기간에 속한 글은 지운다(사진/댓글은 CASCADE).
--     마감 이후(선별·조판이 이미 진행됨)인 호의 글은 그대로 유지 - "마감 후 탈퇴는 이번 호에 실려서 발송"(ACC-05)
--   * 호출자에게 돌려줌 : 외부 시크릿 저장소에서 폐기해야 할 토큰 참조 목록 (DB 밖이라 DB 가 지울 수 없다)
-- 이 함수가 하지 않는 일 (정책 결정이 필요 — TODO.md)
--   * 이미 인쇄/발행된 호의 내용 변경
--   * 방장 처리: 방장은 먼저 방장을 넘겨야 한다 (아니면 예외)
-- 여러 번 호출해도 안전(멱등).

CREATE OR REPLACE FUNCTION anonymize_user(p_user uuid)
RETURNS TABLE (o_kind text, o_ref text)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM 1 FROM app_user WHERE id = p_user FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'user % not found', p_user;
    END IF;

    IF EXISTS (SELECT 1 FROM family_group WHERE owner_id = p_user) THEN
        RAISE EXCEPTION 'user % is the owner of a family group: transfer ownership first', p_user
            USING ERRCODE = 'check_violation';
    END IF;

    -- 삭제 전에 폐기 대상 시크릿 참조를 수집해 돌려준다
    RETURN QUERY
    SELECT 'auth_token'::text, refresh_token_ref FROM auth_identity
     WHERE user_id = p_user AND refresh_token_ref IS NOT NULL;

    DELETE FROM auth_identity WHERE user_id = p_user;
    UPDATE family_member SET left_at = now() WHERE user_id = p_user AND left_at IS NULL;
    DELETE FROM page_lock WHERE user_id = p_user;

    -- 모집 중인 호의 글은 삭제, 마감 이후인 호의 글은 유지 (ACC-05)
    DELETE FROM post po
     WHERE po.author_id = p_user
       AND EXISTS (
           SELECT 1 FROM issue i JOIN family_group g ON g.id = i.group_id
            WHERE i.group_id = po.group_id AND i.status = 'collecting'
              AND (po.posted_at AT TIME ZONE g.timezone)::date BETWEEN i.period_start AND i.period_end);

    UPDATE app_user
       SET email = NULL, name = '탈퇴한 사용자', photo_key = NULL, deleted_at = COALESCE(deleted_at, now())
     WHERE id = p_user;
END $$;
