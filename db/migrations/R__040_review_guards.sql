-- [review 모듈] 수정(override) 가드
-- Flyway 반복 마이그레이션: 내용이 바뀌면 다음 migrate 때 자동 재적용된다. 파일명 번호 순서로 적용된다.
-- 소유 테이블/의존 방향은 docs/architecture.md 와 db/tests/architecture.sql 참고.
--
-- 승인 절차가 없으므로(review_window_hours 안 자유 재조판 요청 -> 시간 경과 시 자동 printing 전환),
-- approval 테이블과 승인 버전 기록 트리거는 존재하지 않는다. 남은 건 수정(override) 가드뿐.

-- =========================================================
-- 4. 수정(override) 가드
--    - review    : 허용
--    - 그 외     : 거부 (인쇄 진행 중/완료 후에는 수정 불가 - review 로 돌아와야 재조판 요청 가능)
--    - superseded 조판 실행에 대한 수정은 거부
-- =========================================================
CREATE OR REPLACE FUNCTION override_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
    v_run_status text;
BEGIN
    SELECT status INTO v_status FROM issue WHERE id = NEW.issue_id FOR UPDATE;
    SELECT status INTO v_run_status FROM layout_run WHERE id = NEW.run_id;

    IF v_run_status = 'superseded' THEN
        RAISE EXCEPTION 'override: run % is superseded', NEW.run_id USING ERRCODE = 'check_violation';
    END IF;

    IF v_status IS DISTINCT FROM 'review' THEN
        RAISE EXCEPTION 'override not allowed while issue status is %', v_status
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_override_guard ON override;
CREATE TRIGGER trg_override_guard BEFORE INSERT ON override
    FOR EACH ROW EXECUTE FUNCTION override_guard();

-- =========================================================
-- 5. 정합성 가드: 수정(override)의 작성자는 그 호의 그룹에서 활동 중인 구성원이어야 한다
--    TG_ARGV[0] = 작성자 컬럼 이름 (override: author_id)
-- =========================================================
CREATE OR REPLACE FUNCTION guard_review_author() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_group uuid;
    v_user  uuid := (to_jsonb(NEW) ->> TG_ARGV[0])::uuid;
BEGIN
    SELECT group_id INTO v_group FROM issue WHERE id = NEW.issue_id;
    IF NOT is_active_member(v_group, v_user) THEN
        RAISE EXCEPTION '%: user % is not an active member of the group of issue %', TG_TABLE_NAME, v_user, NEW.issue_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_override_author ON override;
CREATE TRIGGER trg_override_author BEFORE INSERT ON override
    FOR EACH ROW EXECUTE FUNCTION guard_review_author('author_id');
