-- [review 모듈] 수정(override) 가드
-- Flyway 반복 마이그레이션: 내용이 바뀌면 다음 migrate 때 자동 재적용된다. 파일명 번호 순서로 적용된다.
-- 소유 테이블/의존 방향은 docs/architecture.md 와 db/tests/architecture.sql 참고.
--
-- 승인 절차가 없으므로(가족의 미리보기·재조판 요청 없음, V-17 - review 단계는 운영자만 조판 검수),
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
-- 5. 정합성 가드: 수정(override)의 작성자가 가족(author_id)이면 그 호의 그룹에서 활동 중인
--    구성원이어야 한다. 운영자(operator_id)는 가족 소속이 아니므로 이 검사를 건너뛴다
--    (Admin 접근 자체가 별도 인증이라는 전제, TODO.md "DB 권한 분리" 참고).
-- =========================================================
CREATE OR REPLACE FUNCTION guard_review_author() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_group uuid;
BEGIN
    IF NEW.author_id IS NULL THEN
        RETURN NEW;  -- 운영자가 만든 수정
    END IF;
    SELECT group_id INTO v_group FROM issue WHERE id = NEW.issue_id;
    IF NOT is_active_member(v_group, NEW.author_id) THEN
        RAISE EXCEPTION '%: user % is not an active member of the group of issue %', TG_TABLE_NAME, NEW.author_id, NEW.issue_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_override_author ON override;
CREATE TRIGGER trg_override_author BEFORE INSERT ON override
    FOR EACH ROW EXECUTE FUNCTION guard_review_author();
