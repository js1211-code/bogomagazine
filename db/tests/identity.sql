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

\echo T81 익명화: 방장은 방장을 넘기기 전에는 거부, 넘긴 뒤에는 가능, 없는 사용자는 예외
BEGIN;
DO $$
DECLARE u1 constant uuid := '00000000-0000-0000-0000-000000000001';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
        g  constant uuid := '00000000-0000-0000-0000-0000000000d1';
BEGIN
  BEGIN
    PERFORM * FROM anonymize_user(u1);
    RAISE EXCEPTION 'T81 failed: 방장이 익명화됨';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  ASSERT (SELECT email IS NULL AND name = '엄마' FROM app_user WHERE id = u1), 'T81 거부했는데 바뀜';

  PERFORM transfer_family_owner(g, u1, u2);
  PERFORM * FROM anonymize_user(u1);
  ASSERT (SELECT name = '탈퇴한 사용자' FROM app_user WHERE id = u1), 'T81 방장을 넘긴 뒤에는 익명화되어야 함';

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

\echo T83 개인 차단(SAFE-02): 자기 자신은 차단 못 함, 같은 쌍 중복 거부, 양방향은 별개 행
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

  INSERT INTO user_block (blocker_id, blocked_id) VALUES (u2, u1);  -- 맞차단은 별개 행
  ASSERT (SELECT count(*) FROM user_block WHERE blocker_id IN (u1, u2)) = 2, 'T83 양방향 차단은 별개 행';
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
