-- review 모듈 테스트. 전체 실행: ./scripts/db.sh test
-- 각 테스트는 BEGIN..ROLLBACK 으로 격리되어 시드 데이터를 바꾸지 않는다. 하나라도 실패하면 즉시 중단.
--
-- 승인 절차는 없다. review 상태에서만 수정(override, 운영자의 조판 검수용 세부 수정 로그)을 허용하고,
-- review -> printing/printed 전환은 운영자가 수동으로만 한다(issues.sql T32, admin.sql 참고). 가족의 미리보기는 없다(V-17).
\echo == review

\echo T54 수정(override, 운영자의 조판 검수): review 상태에서만 허용, 그 외 상태/무효화된 조판에는 거부
BEGIN;
DO $$
DECLARE v constant uuid := '00000000-0000-0000-0000-0000000000c1';
        v_run uuid; v_p1 uuid; v_op uuid;
BEGIN
  INSERT INTO operator (name, email, role) VALUES ('검수자', 'reviewer-t54@x.com', 'staff_write') RETURNING id INTO v_op;

  PERFORM change_issue_status(v, 'closing');
  INSERT INTO layout_run (issue_id, template_id, algorithm_version, seed, input_snapshot_hash, status)
  VALUES (v, '00000000-0000-0000-0000-0000000000a1', '0.1.0', 1, 'h', 'done') RETURNING id INTO v_run;
  INSERT INTO page (run_id, page_no) VALUES (v_run, 1) RETURNING id INTO v_p1;

  -- closing 상태(아직 review 아님)에는 거부
  BEGIN
    INSERT INTO override (issue_id, run_id, target_type, target_id, op, operator_id)
    VALUES (v, v_run, 'page', v_p1, '{"op":"move"}', v_op);
    RAISE EXCEPTION 'T54 failed: closing 상태에서 수정이 허용됨';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  PERFORM change_issue_status(v, 'review');
  INSERT INTO override (issue_id, run_id, target_type, target_id, op, operator_id)
  VALUES (v, v_run, 'page', v_p1, '{"op":"move"}', v_op);
  ASSERT (SELECT count(*) FROM override WHERE run_id = v_run) = 1, 'T54 review 상태에서는 수정이 허용되어야 함';

  -- printing 으로 넘어가면 다시 거부 (다시 수정하려면 review 로 돌아와야 함)
  PERFORM change_issue_status(v, 'printing', NULL, NULL, NULL, v_op);
  BEGIN
    INSERT INTO override (issue_id, run_id, target_type, target_id, op, operator_id)
    VALUES (v, v_run, 'page', v_p1, '{"op":"resize"}', v_op);
    RAISE EXCEPTION 'T54 failed: printing 중 수정이 허용됨';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- 프리플라이트 실패 등으로 review 복귀하면 다시 허용
  PERFORM change_issue_status(v, 'review', NULL, NULL, NULL, v_op);
  INSERT INTO override (issue_id, run_id, target_type, target_id, op, operator_id)
  VALUES (v, v_run, 'page', v_p1, '{"op":"resize"}', v_op);
  ASSERT (SELECT count(*) FROM override WHERE run_id = v_run) = 2, 'T54 review 로 복귀하면 다시 허용되어야 함';
END $$;
ROLLBACK;

\echo T54b 수정(override) 작성자는 가족 또는 운영자 중 정확히 하나 (둘 다 NULL/둘 다 채움은 거부)
BEGIN;
DO $$
DECLARE v constant uuid := '00000000-0000-0000-0000-0000000000c1';
        u1 constant uuid := '00000000-0000-0000-0000-000000000001';
        v_run uuid; v_p1 uuid; v_op uuid;
BEGIN
  INSERT INTO operator (name, email, role) VALUES ('검수자', 'reviewer-t54b@x.com', 'staff_write') RETURNING id INTO v_op;
  PERFORM change_issue_status(v, 'closing');
  INSERT INTO layout_run (issue_id, template_id, algorithm_version, seed, input_snapshot_hash, status)
  VALUES (v, '00000000-0000-0000-0000-0000000000a1', '0.1.0', 1, 'h', 'done') RETURNING id INTO v_run;
  INSERT INTO page (run_id, page_no) VALUES (v_run, 1) RETURNING id INTO v_p1;
  PERFORM change_issue_status(v, 'review');

  BEGIN
    INSERT INTO override (issue_id, run_id, target_type, target_id, op) VALUES (v, v_run, 'page', v_p1, '{}');
    RAISE EXCEPTION 'T54b failed: 작성자 없이 수정이 저장됨';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO override (issue_id, run_id, target_type, target_id, op, author_id, operator_id)
    VALUES (v, v_run, 'page', v_p1, '{}', u1, v_op);
    RAISE EXCEPTION 'T54b failed: 가족과 운영자가 동시에 작성자로 저장됨';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
ROLLBACK;

\echo T62 무효가 된(superseded) 조판에는 review 상태여도 수정 불가
BEGIN;
DO $$
DECLARE v constant uuid := '00000000-0000-0000-0000-0000000000c1';
        v_run uuid; v_p1 uuid; v_op uuid;
BEGIN
  INSERT INTO operator (name, email, role) VALUES ('검수자', 'reviewer-t62@x.com', 'staff_write') RETURNING id INTO v_op;
  PERFORM change_issue_status(v, 'closing');
  INSERT INTO layout_run (issue_id, template_id, algorithm_version, seed, input_snapshot_hash, status)
  VALUES (v, '00000000-0000-0000-0000-0000000000a1', '0.1.0', 1, 'h', 'done') RETURNING id INTO v_run;
  INSERT INTO page (run_id, page_no) VALUES (v_run, 1) RETURNING id INTO v_p1;
  PERFORM change_issue_status(v, 'review');
  PERFORM change_issue_status(v, 'closing', NULL, NULL, NULL, v_op);  -- 운영자 조판 검수: 재조판, 이전 실행은 superseded
  ASSERT (SELECT status FROM layout_run WHERE id = v_run) = 'superseded', 'T62 precondition';

  -- superseded 된 run_id 를 가리키는 수정은 (issue 상태와 별개로) 항상 거부된다
  BEGIN
    INSERT INTO override (issue_id, run_id, target_type, target_id, op, operator_id)
    VALUES (v, v_run, 'page', v_p1, '{"op":"move"}', v_op);
    RAISE EXCEPTION 'T62 failed: 무효(superseded) 조판에 수정됨';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
ROLLBACK;
