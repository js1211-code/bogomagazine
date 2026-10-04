-- identity 모듈 테스트 (로그인 수단, 탈퇴 익명화). 전체 실행: ./scripts/db.sh test
-- 각 테스트는 BEGIN..ROLLBACK 으로 격리되어 시드 데이터를 바꾸지 않는다. 하나라도 실패하면 즉시 중단.
\echo == identity

\echo T80 익명화: 신원/인증 제거, 시크릿 목록 반환, 모집 중인 호의 글은 삭제·마감 이후 호의 글은 유지(ACC-05), 멱등, 탈퇴 후 글 작성 불가, 같은 계정으로 재가입 가능
BEGIN;
DO $$
DECLARE u3 constant uuid := '00000000-0000-0000-0000-000000000003';
        g  constant uuid := '00000000-0000-0000-0000-0000000000d1';
        a  constant uuid := '00000000-0000-0000-0000-0000000000c1';
        v_post_old uuid; v_post_new uuid; v_issue_new uuid; refs text; v_deleted_at timestamptz;
BEGIN
  INSERT INTO app_user (id, email, name) VALUES (u3, 'k3@x.com', '셋째');
  INSERT INTO auth_identity (user_id, provider, provider_uid, email, refresh_token_ref)
  VALUES (u3, 'kakao', 'k-3', 'k3@x.com', 'sec/auth/3');
  INSERT INTO family_member (group_id, user_id, nickname) VALUES (g, u3, '막내');

  -- 마감 이후(모집 중 아님)인 호의 글: 유지되어야 함
  INSERT INTO post (group_id, author_id, body, posted_at) VALUES (g, u3, '막내의 글', '2026-09-20 12:00+09') RETURNING id INTO v_post_old;
  INSERT INTO media (post_id, group_id, storage_key, sha256, width, height) VALUES (v_post_old, g, 'u3.jpg', 'u3sha', 4000, 3000);
  PERFORM change_issue_status(a, 'closing');

  -- 아직 모집 중인(다음 달) 호의 글: 삭제되어야 함
  SELECT o_issue_id INTO v_issue_new FROM open_monthly_issues('2026-10-02 12:00+09');
  INSERT INTO post (group_id, author_id, body, posted_at) VALUES (g, u3, '다음 호 글', '2026-10-05 12:00+09') RETURNING id INTO v_post_new;

  SELECT string_agg(o_kind || ':' || o_ref, ',' ORDER BY o_kind) INTO refs FROM anonymize_user(u3);
  ASSERT refs = 'auth_token:sec/auth/3', 'T80 폐기할 시크릿 목록: ' || COALESCE(refs, 'NULL');

  ASSERT (SELECT email IS NULL AND name = '탈퇴한 사용자' AND deleted_at IS NOT NULL FROM app_user WHERE id = u3), 'T80 사용자 익명화';
  ASSERT (SELECT count(*) FROM auth_identity WHERE user_id = u3) = 0, 'T80 로그인 수단이 남음';
  ASSERT (SELECT left_at IS NOT NULL FROM family_member WHERE group_id = g AND user_id = u3), 'T80 구성원 행은 남고 left_at 이 채워짐';
  ASSERT (SELECT count(*) FROM post WHERE id = v_post_old) = 1 AND (SELECT count(*) FROM media WHERE post_id = v_post_old) = 1,
         'T80 마감 이후 호의 글/사진은 유지';
  ASSERT (SELECT count(*) FROM post WHERE id = v_post_new) = 0, 'T80 모집 중인 호의 글은 삭제';

  SELECT deleted_at INTO v_deleted_at FROM app_user WHERE id = u3;
  ASSERT (SELECT count(*) FROM anonymize_user(u3)) = 0, 'T80 재호출이 시크릿을 또 반환';
  ASSERT (SELECT deleted_at FROM app_user WHERE id = u3) = v_deleted_at, 'T80 재호출이 deleted_at 을 덮어씀';

  BEGIN
    INSERT INTO post (group_id, author_id, body, posted_at) VALUES (g, u3, '탈퇴 후 글', '2026-09-21 12:00+09');
    RAISE EXCEPTION 'T80 failed: 탈퇴한 사용자가 글을 올림';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- 같은 카카오 계정으로 다시 가입 가능 (옛 연결이 완전히 해제됨)
  INSERT INTO app_user (id, name) VALUES ('00000000-0000-0000-0000-000000000004', '재가입');
  INSERT INTO auth_identity (user_id, provider, provider_uid) VALUES ('00000000-0000-0000-0000-000000000004', 'kakao', 'k-3');
END $$;
ROLLBACK;

\echo T81 익명화: 방장이 탈퇴하면 가장 먼저 합류한 구성원에게 자동으로 방장이 넘어감(FAM-11), 혼자뿐이면 거부, 없는 사용자는 예외
BEGIN;
DO $$
DECLARE u1 constant uuid := '00000000-0000-0000-0000-000000000001';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
        g  constant uuid := '00000000-0000-0000-0000-0000000000d1';
        solo uuid := gen_random_uuid();
        g_solo uuid;
BEGIN
  PERFORM * FROM anonymize_user(u1);
  ASSERT (SELECT name = '탈퇴한 사용자' FROM app_user WHERE id = u1), 'T81 방장 탈퇴 시 익명화되어야 함';
  ASSERT (SELECT owner_id = u2 FROM family_group WHERE id = g), 'T81 방장이 가장 먼저 합류한 구성원(u2)에게 자동 이전되어야 함';
  ASSERT EXISTS (SELECT 1 FROM notification_log WHERE user_id = u2 AND group_id = g AND kind = 'owner_changed'),
         'T81 새 방장에게 알림 목록(NOTI-06)에 owner_changed 가 남아야 함';

  -- 혼자뿐인 그룹의 방장은 거부한다(마지막 구성원 탈퇴 정책은 아직 결정 전, TODO.md)
  INSERT INTO app_user (id, name) VALUES (solo, '혼자');
  g_solo := create_family_group('혼자네', solo);
  BEGIN
    PERFORM * FROM anonymize_user(solo);
    RAISE EXCEPTION 'T81 failed: 혼자뿐인 방장이 익명화됨';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    PERFORM * FROM anonymize_user(gen_random_uuid());
    RAISE EXCEPTION 'T81 failed: 없는 사용자';
  EXCEPTION WHEN raise_exception THEN
    ASSERT SQLERRM LIKE '%not found%', 'T81 메시지: ' || SQLERRM;
  END;
END $$;
ROLLBACK;

\echo T82 로그인 수단은 카카오와 애플뿐이다
BEGIN;
DO $$
DECLARE p text;
BEGIN
  INSERT INTO auth_identity (user_id, provider, provider_uid) VALUES ('00000000-0000-0000-0000-000000000001', 'kakao', 'kk-1');
  INSERT INTO auth_identity (user_id, provider, provider_uid, is_private_relay) VALUES ('00000000-0000-0000-0000-000000000001', 'apple', 'ap-1', true);
  FOREACH p IN ARRAY ARRAY['google', 'password', 'naver'] LOOP
    BEGIN
      INSERT INTO auth_identity (user_id, provider, provider_uid) VALUES ('00000000-0000-0000-0000-000000000001', p, 'x-' || p);
      RAISE EXCEPTION 'T82 failed: % 로그인 수단이 허용됨', p;
    EXCEPTION WHEN check_violation THEN NULL;
    END;
  END LOOP;
END $$;
ROLLBACK;

\echo T83 개인 차단(SAFE-02): 자기 자신은 차단 못 함, 같은 쌍 중복 거부, 양방향은 별개 행, 차단하면 자동으로 팀에 신고됨
BEGIN;
DO $$
DECLARE u1 constant uuid := '00000000-0000-0000-0000-000000000001';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
BEGIN
  BEGIN
    INSERT INTO user_block (blocker_id, blocked_id) VALUES (u1, u1);
    RAISE EXCEPTION 'T83 failed: 자기 자신을 차단함';
  EXCEPTION WHEN check_violation THEN NULL; END;

  INSERT INTO user_block (blocker_id, blocked_id) VALUES (u1, u2);
  BEGIN
    INSERT INTO user_block (blocker_id, blocked_id) VALUES (u1, u2);
    RAISE EXCEPTION 'T83 failed: 같은 쌍이 중복 저장됨';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  ASSERT (SELECT count(*) FROM report WHERE target_type = 'user' AND reporter_id = u1 AND target_id = u2) = 1,
         'T83 차단하면 자동으로 신고가 쌓여야 함(SAFE-02)';

  INSERT INTO user_block (blocker_id, blocked_id) VALUES (u2, u1);  -- 맞차단은 별개 행
  ASSERT (SELECT count(*) FROM user_block WHERE blocker_id IN (u1, u2)) = 2, 'T83 양방향 차단은 별개 행';
  ASSERT (SELECT count(*) FROM operator_alert_log WHERE kind = 'report_received' AND ref_id IN
            (SELECT id FROM report WHERE target_type = 'user' AND reporter_id IN (u1, u2))) = 2,
         'T83 자동 신고도 운영 알림(ADM-08)으로 이어져야 함';
END $$;
ROLLBACK;

\echo T85 가입 동의(ACC-03)/프로필(PRF-01): 필수 동의는 기본값으로 채워지고, 생일은 월1~12/일1~31 범위만
BEGIN;
DO $$
DECLARE u uuid;
BEGIN
  INSERT INTO app_user (name) VALUES ('신규가입') RETURNING id INTO u;
  ASSERT (SELECT privacy_consented_at IS NOT NULL AND terms_consented_at IS NOT NULL
            AND age_over_14_confirmed_at IS NOT NULL AND research_consented_at IS NULL
           FROM app_user WHERE id = u),
         'T85 필수 동의는 기본값, 연구활용(선택)은 NULL이어야 함';

  UPDATE app_user SET birth_month = 2, birth_day = 29 WHERE id = u;  -- 월/일만이라 2/29 자체는 막지 않음
  BEGIN
    UPDATE app_user SET birth_month = 13 WHERE id = u;
    RAISE EXCEPTION 'T85 failed: 13월이 허용됨';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    UPDATE app_user SET birth_day = 32 WHERE id = u;
    RAISE EXCEPTION 'T85 failed: 32일이 허용됨';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;

\echo T84 정식 출시 대기 신청(WAIT-01): 같은 사용자가 같은 코드로 중복 신청 못 함
BEGIN;
DO $$
DECLARE u1 constant uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO waitlist_signup (user_id) VALUES (u1);
  BEGIN
    INSERT INTO waitlist_signup (user_id) VALUES (u1);
    RAISE EXCEPTION 'T84 failed: 같은 코드로 중복 신청됨';
  EXCEPTION WHEN unique_violation THEN NULL; END;
END $$;
ROLLBACK;
