-- admin 모듈 테스트 (운영자 계정, 운영자가 바꾼 호 상태 이력). 전체 실행: ./scripts/db.sh test
-- 각 테스트는 BEGIN..ROLLBACK 으로 격리되어 시드 데이터를 바꾸지 않는다. 하나라도 실패하면 즉시 중단.
-- 운영자는 전부 동일 권한이다(ADM-01) — 역할 구분/퇴사 처리는 없음.
\echo == admin

\echo T201 운영자 이메일: 대소문자 무시하고 유일
BEGIN;
DO $$
BEGIN
  INSERT INTO operator (name, email) VALUES ('운영자A', 'dup@x.com');
  BEGIN
    INSERT INTO operator (name, email) VALUES ('운영자A2', 'DUP@x.com');
    RAISE EXCEPTION 'T201 failed: 대소문자만 다른 중복 이메일이 등록됨';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;
ROLLBACK;

\echo T202 호 상태 이력: 가족이 바꾼 건 changed_by만, 운영자가 바꾼 건 operator_id만 채워진다 (둘 다는 거부)
BEGIN;
DO $$
DECLARE a constant uuid := '00000000-0000-0000-0000-0000000000c1';
         u1 constant uuid := '00000000-0000-0000-0000-000000000001';
         op uuid;
BEGIN
  INSERT INTO operator (name, email) VALUES ('운영자A', 'opD@x.com') RETURNING id INTO op;

  INSERT INTO issue_status_history (issue_id, to_status, changed_by) VALUES (a, 'closing', u1);
  INSERT INTO issue_status_history (issue_id, to_status, operator_id) VALUES (a, 'printing', op);
  INSERT INTO issue_status_history (issue_id, to_status) VALUES (a, 'printed');  -- 배치 자동전환: 둘 다 NULL

  BEGIN
    INSERT INTO issue_status_history (issue_id, to_status, changed_by, operator_id) VALUES (a, 'archived', u1, op);
    RAISE EXCEPTION 'T202 failed: changed_by 와 operator_id 가 동시에 채워짐';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
ROLLBACK;

\echo T203 배송지 열람/다운로드 기록 (ADM-01): 운영자만 남기고, 배송지가 지워지면 기록도 함께 지워진다
BEGIN;
DO $$
DECLARE e1 constant uuid := '00000000-0000-0000-0000-0000000000e1';
        op uuid;
BEGIN
  INSERT INTO operator (name, email) VALUES ('운영자E', 'opE@x.com') RETURNING id INTO op;
  INSERT INTO delivery_address_access_log (delivery_address_id, operator_id, action) VALUES (e1, op, 'view');
  INSERT INTO delivery_address_access_log (delivery_address_id, operator_id, action) VALUES (e1, op, 'download');
  ASSERT (SELECT count(*) FROM delivery_address_access_log WHERE delivery_address_id = e1) = 2, 'T203 기록 저장';

  BEGIN
    INSERT INTO delivery_address_access_log (delivery_address_id, operator_id, action) VALUES (e1, op, 'edit');
    RAISE EXCEPTION 'T203 failed: 알 수 없는 action 이 허용됨';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  DELETE FROM delivery_address WHERE id = e1;
  ASSERT (SELECT count(*) FROM delivery_address_access_log WHERE delivery_address_id = e1) = 0,
         'T203 배송지 삭제 시 열람 기록도 함께 삭제되어야 함';
END $$;
ROLLBACK;

\echo T204 콘텐츠 신고(SAFE-01/ADM-05): pending 으로 시작, 운영자가 처리하면 resolved_by/resolved_at 둘 다 채워야 한다
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u1 constant uuid := '00000000-0000-0000-0000-000000000001';
        op uuid; v_post uuid; v_report uuid;
BEGIN
  INSERT INTO operator (name, email) VALUES ('신고처리자', 'opF@x.com') RETURNING id INTO op;
  INSERT INTO post (group_id, author_id, body, posted_at) VALUES (g, u1, '부적절한 글', now()) RETURNING id INTO v_post;
  INSERT INTO report (reporter_id, target_type, target_id, reason) VALUES (u1, 'post', v_post, '부적절함') RETURNING id INTO v_report;
  ASSERT (SELECT status FROM report WHERE id = v_report) = 'pending', 'T204 초기 상태는 pending';

  BEGIN
    UPDATE report SET status = 'resolved' WHERE id = v_report;
    RAISE EXCEPTION 'T204 failed: resolved_by/resolved_at 없이 resolved 처리됨';
  EXCEPTION WHEN check_violation THEN NULL; END;

  UPDATE report SET status = 'resolved', resolved_by = op, resolved_at = now() WHERE id = v_report;
END $$;
ROLLBACK;

\echo T205 운영 알림(ADM-08): 신고 접수는 즉시, 조판 실패는 3번째 실패에서만 쌓인다
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        a constant uuid := '00000000-0000-0000-0000-0000000000c1';
        u1 constant uuid := '00000000-0000-0000-0000-000000000001';
        v_post uuid; v_report uuid; r record; v_before int;
BEGIN
  INSERT INTO post (group_id, author_id, body, posted_at) VALUES (g, u1, '글', now()) RETURNING id INTO v_post;
  INSERT INTO report (reporter_id, target_type, target_id, reason) VALUES (u1, 'post', v_post, '사유') RETURNING id INTO v_report;
  ASSERT (SELECT count(*) FROM operator_alert_log WHERE kind = 'report_received' AND ref_id = v_report) = 1,
         'T205 신고 접수 즉시 운영 알림';

  SELECT count(*) INTO v_before FROM operator_alert_log WHERE kind = 'layout_failed' AND ref_id = a;
  PERFORM change_issue_status(a, 'closing');
  FOR i IN 1..3 LOOP
    SELECT * INTO r FROM claim_compose_job('w1', '0.1.0');
    PERFORM fail_compose_job(r.o_run_id, 'w1', '실패 ' || i);
    IF i < 3 THEN
      ASSERT (SELECT count(*) FROM operator_alert_log WHERE kind = 'layout_failed' AND ref_id = a) = v_before,
             format('T205 %s번째 실패에서는 아직 알림이 없어야 함', i);
    END IF;
  END LOOP;
  ASSERT (SELECT count(*) FROM operator_alert_log WHERE kind = 'layout_failed' AND ref_id = a) = v_before + 1,
         'T205 3번째 실패에서 운영 알림';
END $$;
ROLLBACK;
