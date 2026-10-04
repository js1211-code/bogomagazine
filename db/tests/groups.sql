-- groups 모듈 테스트 (그룹 만들기, 초대, 방장 권한, 배송지). 전체 실행: ./scripts/db.sh test
-- 각 테스트는 BEGIN..ROLLBACK 으로 격리되어 시드 데이터를 바꾸지 않는다. 하나라도 실패하면 즉시 중단.
\echo == groups

\echo T04b 구성원의 수신자 관계(relationship)는 호칭 대응표 8개 값뿐이다 (PRF-02)
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
        r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['손녀', '손자', '딸', '아들', '며느리', '사위', '손주며느리', '손주사위'] LOOP
    UPDATE family_member SET relationship = r WHERE group_id = g AND user_id = u2;
    ASSERT (SELECT relationship FROM family_member WHERE group_id = g AND user_id = u2) = r, 'T04b ' || r;
  END LOOP;
  BEGIN
    UPDATE family_member SET relationship = '조카' WHERE group_id = g AND user_id = u2;
    RAISE EXCEPTION 'T04b failed: 제외된 관계(조카)가 허용됨';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;

\echo T05 family_member PK 중복 거부
BEGIN;
DO $$ BEGIN
  BEGIN
    INSERT INTO family_member (group_id, user_id)
    VALUES ('00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'T05 failed: 거부되지 않음';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;
ROLLBACK;

\echo T20 그룹 만들기: 방장이 구성원으로 함께 들어가고, 구성원 없이 그룹만 넣으면 커밋 시점에 거부
BEGIN;
DO $$
DECLARE u3 constant uuid := '00000000-0000-0000-0000-000000000003'; g uuid;
BEGIN
  INSERT INTO app_user (id, name) VALUES (u3, '셋째');
  g := create_family_group('이씨네', u3, '막내');
  ASSERT (SELECT owner_id = u3 FROM family_group WHERE id = g), 'T20 방장';
  ASSERT is_active_member(g, u3), 'T20 방장이 구성원이 아님';
END $$;
ROLLBACK;

BEGIN;
INSERT INTO app_user (id, name) VALUES ('00000000-0000-0000-0000-000000000003', '셋째');
INSERT INTO family_group (name, owner_id) VALUES ('유령방', '00000000-0000-0000-0000-000000000003');
DO $$ BEGIN
  BEGIN
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'T20 failed: 방장이 구성원이 아닌 그룹이 허용됨';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
END $$;
ROLLBACK;

\echo T21 초대: 방장만 만들 수 있다 (일반 구성원/외부인 거부), 가족마다 고정 코드 1개(FAM-05, 1004 결정)
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u1 constant uuid := '00000000-0000-0000-0000-000000000001';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
        v1 family_invite%ROWTYPE; v2 family_invite%ROWTYPE;
BEGIN
  INSERT INTO family_invite (group_id, created_by, token_hash)
  VALUES (g, u1, repeat('a', 64));
  BEGIN
    INSERT INTO family_invite (group_id, created_by, token_hash)
    VALUES (g, u2, repeat('b', 64));
    RAISE EXCEPTION 'T21 failed: 일반 구성원이 초대를 만듦';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO family_invite (group_id, created_by, token_hash)
    VALUES (g, u1, 'short');
    RAISE EXCEPTION 'T21 failed: 짧은 해시 허용';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- 같은 그룹에 방장이 직접 두 번째 링크를 만들어도 거부된다 (가족마다 1개)
  BEGIN
    INSERT INTO family_invite (group_id, created_by, token_hash)
    VALUES (g, u1, repeat('c', 64));
    RAISE EXCEPTION 'T21 failed: 같은 그룹에 두 번째 초대 링크가 만들어짐';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- get_or_create_family_invite()는 이미 있으면 그걸 그대로 돌려주고, 없으면 만든다
  SELECT * INTO v1 FROM get_or_create_family_invite(g, u1, repeat('d', 64));
  ASSERT v1.token_hash = repeat('a', 64), 'T21 이미 있는 링크를 그대로 돌려줘야 함';
  SELECT * INTO v1 FROM get_or_create_family_invite(g, u1, repeat('d', 64));
  ASSERT v1.token_hash = repeat('a', 64), 'T21 두 번째 호출도 같은 링크여야 함';
  ASSERT (SELECT count(*) FROM family_invite WHERE group_id = g) = 1, 'T21 get_or_create 호출로 링크가 늘어나면 안 됨';
END $$;
ROLLBACK;

\echo T22 초대 수락: 합류, 두 번 눌러도 안전(멱등), 일반 구성원으로 합류, 유효기간·횟수 제한 없음(FAM-05, V-23)
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u1 constant uuid := '00000000-0000-0000-0000-000000000001';
        u3 constant uuid := '00000000-0000-0000-0000-000000000003';
        r uuid;
BEGIN
  INSERT INTO app_user (id, name) VALUES (u3, '셋째');
  INSERT INTO family_invite (group_id, created_by, token_hash)
  VALUES (g, u1, repeat('a', 64));

  r := accept_family_invite(repeat('a', 64), u3);
  ASSERT r = g, 'T22 그룹 id 반환';
  ASSERT is_active_member(g, u3), 'T22 합류 안 됨';
  ASSERT (SELECT owner_id <> u3 FROM family_group WHERE id = g), 'T22 합류자가 방장이 됨';

  r := accept_family_invite(repeat('a', 64), u3);
  ASSERT is_active_member(g, u3), 'T22 두 번 눌러도 안전';
END $$;
ROLLBACK;

\echo T23 초대 수락 거부: 없는 링크, 탈퇴한 사용자 (만료·취소·횟수 제한은 스펙에 없어 삭제함)
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u1 constant uuid := '00000000-0000-0000-0000-000000000001';
        u3 constant uuid := '00000000-0000-0000-0000-000000000003';
        u5 constant uuid := '00000000-0000-0000-0000-000000000005';
BEGIN
  INSERT INTO app_user (id, name) VALUES (u3, '셋째');
  INSERT INTO app_user (id, name, deleted_at) VALUES (u5, '탈퇴', now());
  INSERT INTO family_invite (group_id, created_by, token_hash)
  VALUES (g, u1, repeat('a', 64));

  BEGIN PERFORM accept_family_invite(repeat('z', 64), u3); RAISE EXCEPTION 'T23 failed: 없는 링크';
  EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM LIKE '%not found%', 'T23 메시지: ' || SQLERRM; END;

  BEGIN PERFORM accept_family_invite(repeat('a', 64), u5); RAISE EXCEPTION 'T23 failed: 탈퇴한 사용자';
  EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM LIKE '%not found or deleted%', 'T23 메시지: ' || SQLERRM; END;
END $$;
ROLLBACK;

\echo T24 내보내기: 방장만 할 수 있다, 방장은 못 내보냄, 행은 남고 left_at 만 채워짐, 차단 해제 후 재합류 가능 (그룹만 나가고 계정 유지는 없음, V-36)
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u1 constant uuid := '00000000-0000-0000-0000-000000000001';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
        u3 constant uuid := '00000000-0000-0000-0000-000000000003';
BEGIN
  INSERT INTO app_user (id, name) VALUES (u3, '셋째');
  INSERT INTO family_member (group_id, user_id) VALUES (g, u3);

  BEGIN PERFORM remove_family_member(g, u2, u3); RAISE EXCEPTION 'T24 failed: 일반 구성원이 남을 내보냄';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;

  BEGIN PERFORM remove_family_member(g, u1, u1); RAISE EXCEPTION 'T24 failed: 방장을 내보냄';
  EXCEPTION WHEN check_violation THEN NULL; END;

  BEGIN PERFORM remove_family_member(g, gen_random_uuid(), u3); RAISE EXCEPTION 'T24 failed: 외부인이 내보냄';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;

  PERFORM remove_family_member(g, u1, u3);                 -- 방장이 내보냄
  ASSERT NOT is_active_member(g, u3), 'T24 내보내기 안 됨';
  ASSERT (SELECT count(*) FROM family_member WHERE group_id = g AND user_id = u3) = 1, 'T24 행은 남아야 함';
  ASSERT (SELECT count(*) FROM family_block WHERE group_id = g AND user_id = u3) = 1, 'T24 내보내면 차단 목록에 등록(FAM-09)';

  -- family_block 은 테이블에 직접 넣어도(함수를 거치지 않아도) 방장만 등록 가능해야 한다
  BEGIN
    INSERT INTO family_block (group_id, user_id, created_by) VALUES (g, u2, u2);
    RAISE EXCEPTION 'T24 failed: 방장이 아닌 사람이 직접 차단 등록함';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;

  BEGIN PERFORM remove_family_member(g, u1, u3); RAISE EXCEPTION 'T24 failed: 이미 나간 사람';
  EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM LIKE '%already left%', 'T24 메시지: ' || SQLERRM; END;

  -- 차단된 사람은 옛 링크로 재합류 불가, 방장이 차단 해제하면 가능(FAM-10)
  INSERT INTO family_invite (group_id, created_by, token_hash)
  VALUES (g, u1, repeat('a', 64));
  BEGIN
    PERFORM accept_family_invite(repeat('a', 64), u3);
    RAISE EXCEPTION 'T24 failed: 차단된 사람이 재합류함';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;

  BEGIN PERFORM unblock_family_member(g, u2, u3); RAISE EXCEPTION 'T24 failed: 방장이 아닌 사람이 차단 해제함';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM unblock_family_member(g, u1, u3);
  ASSERT (SELECT count(*) FROM family_block WHERE group_id = g AND user_id = u3) = 0, 'T24 차단 해제';
  PERFORM accept_family_invite(repeat('a', 64), u3);
  ASSERT is_active_member(g, u3), 'T24 차단 해제 후 재합류';
END $$;
ROLLBACK;

\echo T26 배송지: 활동 중인 구성원만 등록, 나간 사람/외부인 거부, 주소 지워도 주문 기록은 그대로(T55 참고)
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u1 constant uuid := '00000000-0000-0000-0000-000000000001';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO delivery_address (group_id, label, recipient_name, recipient_gender, postal_code, address_line1, created_by)
  VALUES (g, '고모 댁', '김가상', 'female', '00002', pgp_sym_encrypt('대전광역시 가상구 1', 'dev-only-change-me'), u2);

  BEGIN
    INSERT INTO delivery_address (group_id, label, recipient_name, recipient_gender, postal_code, address_line1, created_by)
    VALUES (g, '외부', '누구', 'female', '00003', pgp_sym_encrypt('어딘가', 'dev-only-change-me'), gen_random_uuid());
    RAISE EXCEPTION 'T26 failed: 외부인이 배송지를 등록함';
  EXCEPTION WHEN check_violation THEN NULL; END;

  PERFORM remove_family_member(g, u1, u2);
  BEGIN
    INSERT INTO delivery_address (group_id, label, recipient_name, recipient_gender, postal_code, address_line1, created_by)
    VALUES (g, '나간 사람', '누구', 'female', '00003', pgp_sym_encrypt('어딘가', 'dev-only-change-me'), u2);
    RAISE EXCEPTION 'T26 failed: 나간 구성원이 배송지를 등록함';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;

\echo T26b 수신자(RCV-01): 1인 수신자는 성별 필수, 부부 수신은 성별 없이도 등록 가능, 잘못된 성별 값은 거부
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
BEGIN
  BEGIN
    INSERT INTO delivery_address (group_id, label, recipient_name, postal_code, address_line1, created_by)
    VALUES (g, '할머니 댁', '김가상', '00005', pgp_sym_encrypt('성별 없음', 'dev-only-change-me'), u2);
    RAISE EXCEPTION 'T26b failed: 1인 수신자가 성별 없이 등록됨';
  EXCEPTION WHEN check_violation THEN NULL; END;

  INSERT INTO delivery_address (group_id, label, recipient_name, recipient_gender, postal_code, address_line1, created_by)
  VALUES (g, '할머니 댁', '김가상', 'female', '00005', pgp_sym_encrypt('성별 있음', 'dev-only-change-me'), u2);

  -- 부부 수신은 성별 없이도 등록 가능
  INSERT INTO delivery_address (group_id, label, recipient_name, recipient_type, postal_code, address_line1, created_by)
  VALUES (g, '할머니·할아버지 댁', '김가상', 'couple', '00006', pgp_sym_encrypt('부부', 'dev-only-change-me'), u2);

  BEGIN
    INSERT INTO delivery_address (group_id, label, recipient_name, recipient_gender, postal_code, address_line1, created_by)
    VALUES (g, '댁', '이름', '제3성별', '00007', pgp_sym_encrypt('잘못된 성별', 'dev-only-change-me'), u2);
    RAISE EXCEPTION 'T26b failed: 잘못된 성별 값이 허용됨';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;

\echo T27 그룹 삭제: 호가 없는 그룹은 구성원/초대/배송지가 함께 지워지고, 호가 있으면 거부
BEGIN;
DO $$
DECLARE u3 constant uuid := '00000000-0000-0000-0000-000000000003'; g uuid;
BEGIN
  INSERT INTO app_user (id, name) VALUES (u3, '셋째');
  g := create_family_group('임시', u3);
  INSERT INTO family_invite (group_id, created_by, token_hash) VALUES (g, u3, repeat('a', 64));
  INSERT INTO delivery_address (group_id, label, recipient_name, recipient_gender, postal_code, address_line1, created_by)
  VALUES (g, '댁', '이름', 'female', '00004', pgp_sym_encrypt('주소', 'dev-only-change-me'), u3);
  DELETE FROM family_group WHERE id = g;
  ASSERT (SELECT count(*) FROM family_member WHERE group_id = g) = 0
     AND (SELECT count(*) FROM family_invite WHERE group_id = g) = 0
     AND (SELECT count(*) FROM delivery_address WHERE group_id = g) = 0, 'T27 하위 행이 남음';
  SET CONSTRAINTS ALL IMMEDIATE;
  BEGIN
    DELETE FROM family_group WHERE id = '00000000-0000-0000-0000-0000000000d1';
    RAISE EXCEPTION 'T27 failed: 호가 있는 그룹이 삭제됨';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
ROLLBACK;
