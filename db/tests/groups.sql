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
  -- 방장이 아직 아무 링크도 안 만든 상태에서 먼저 검사해야 한다: 방장이 먼저 만들면 가족당 1개 제약과
  -- 동시에 걸려서(unique_violation), 생성자 확인(trg_invite_creator)이 빠져도 다른 이유로 거부된 것처럼 보인다
  BEGIN
    INSERT INTO family_invite (group_id, created_by, token_hash)
    VALUES (g, u2, repeat('b', 64));
    RAISE EXCEPTION 'T21 failed: 일반 구성원이 초대를 만듦';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO family_invite (group_id, created_by, token_hash)
  VALUES (g, u1, repeat('a', 64));
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
        v_addr uuid;
BEGIN
  INSERT INTO delivery_address (group_id, label, postal_code, address_line1, created_by)
  VALUES (g, '고모 댁', '00002', pgp_sym_encrypt('대전광역시 가상구 1', 'dev-only-change-me'), u2) RETURNING id INTO v_addr;
  INSERT INTO recipient (delivery_address_id, display_order, name, gender) VALUES (v_addr, 1, '김가상', 'female');

  BEGIN
    INSERT INTO delivery_address (group_id, label, postal_code, address_line1, created_by)
    VALUES (g, '외부', '00003', pgp_sym_encrypt('어딘가', 'dev-only-change-me'), gen_random_uuid());
    RAISE EXCEPTION 'T26 failed: 외부인이 배송지를 등록함';
  EXCEPTION WHEN check_violation THEN NULL; END;

  PERFORM remove_family_member(g, u1, u2);
  BEGIN
    INSERT INTO delivery_address (group_id, label, postal_code, address_line1, created_by)
    VALUES (g, '나간 사람', '00003', pgp_sym_encrypt('어딘가', 'dev-only-change-me'), u2);
    RAISE EXCEPTION 'T26 failed: 나간 구성원이 배송지를 등록함';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;

\echo T26b 수신자(RCV-01, 1005 결정): 1인/부부 모두 성별 필수, 잘못된 성별 값 거부, 인원수가 recipient_type과 다르면 커밋 시점에 거부
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
        v_addr uuid;
BEGIN
  -- 1인 수신자: 정상
  INSERT INTO delivery_address (group_id, label, postal_code, address_line1, created_by)
  VALUES (g, '할머니 댁', '00005', pgp_sym_encrypt('성별 있음', 'dev-only-change-me'), u2) RETURNING id INTO v_addr;
  INSERT INTO recipient (delivery_address_id, display_order, name, gender) VALUES (v_addr, 1, '김가상', 'female');

  BEGIN
    INSERT INTO recipient (delivery_address_id, display_order, name, gender) VALUES (v_addr, 2, '잘못된 성별', '제3성별');
    RAISE EXCEPTION 'T26b failed: 잘못된 성별 값이 허용됨';
  EXCEPTION WHEN check_violation THEN NULL; END;

  -- 부부 수신: 두 분 다 입력해야 정상
  INSERT INTO delivery_address (group_id, label, recipient_type, postal_code, address_line1, created_by)
  VALUES (g, '할머니·할아버지 댁', 'couple', '00006', pgp_sym_encrypt('부부', 'dev-only-change-me'), u2) RETURNING id INTO v_addr;
  INSERT INTO recipient (delivery_address_id, display_order, name, gender) VALUES (v_addr, 1, '김가상', 'female');
  INSERT INTO recipient (delivery_address_id, display_order, name, gender) VALUES (v_addr, 2, '김가상2', 'male');
END $$;
ROLLBACK;

\echo T26c 수신자 인원수(1005 결정): 부부인데 한 분만 등록되면 거부, 1인인데 두 분 등록돼도 거부, 아예 하나도 안 넣어도 거부
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
        v_addr uuid;
BEGIN
  INSERT INTO delivery_address (group_id, label, recipient_type, postal_code, address_line1, created_by)
  VALUES (g, '할머니·할아버지 댁', 'couple', '00006', pgp_sym_encrypt('부부', 'dev-only-change-me'), u2) RETURNING id INTO v_addr;
  INSERT INTO recipient (delivery_address_id, display_order, name, gender) VALUES (v_addr, 1, '김가상', 'female');
  BEGIN
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'T26c failed: 부부인데 한 명만 등록됐는데 허용됨';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;

BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
        v_addr uuid;
BEGIN
  INSERT INTO delivery_address (group_id, label, postal_code, address_line1, created_by)
  VALUES (g, '할머니 댁', '00005', pgp_sym_encrypt('1인', 'dev-only-change-me'), u2) RETURNING id INTO v_addr;
  INSERT INTO recipient (delivery_address_id, display_order, name, gender) VALUES (v_addr, 1, '김가상', 'female');
  INSERT INTO recipient (delivery_address_id, display_order, name, gender) VALUES (v_addr, 2, '김가상2', 'male');
  BEGIN
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'T26c failed: 1인 수신자인데 두 명이 등록됐는데 허용됨';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;

BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO delivery_address (group_id, label, postal_code, address_line1, created_by)
  VALUES (g, '할머니 댁', '00005', pgp_sym_encrypt('수신자 없음', 'dev-only-change-me'), u2);
  BEGIN
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'T26c failed: 수신자를 하나도 안 넣었는데 허용됨';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;

-- 아래 두 케이스는 위와 달리 "이미 정상 상태인 배송지"를 나중에 건드리는 시나리오라, 두 트리거 중
-- 하나만 켜져 있어도 걸러지는 게 아니라 각 트리거가 담당하는 경로를 따로 검증한다.
-- SET CONSTRAINTS ALL IMMEDIATE로 "지금까지는 정상"임을 먼저 확정한 뒤(여기서 안 걸림), 그 다음
-- 한 문장만 바꿔서 그 문장을 책임지는 트리거만 단독으로 잡아내는지 확인한다 (COMMIT은 쓰지 않음 - 롤백으로 격리 유지).
\echo T26d 기존 배송지의 recipient_type만 바꾸고 수신자 수를 안 맞추면 거부 (delivery_address 쪽 트리거)
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
        v_addr uuid;
BEGIN
  INSERT INTO delivery_address (group_id, label, postal_code, address_line1, created_by)
  VALUES (g, '할머니 댁', '00005', pgp_sym_encrypt('1인', 'dev-only-change-me'), u2) RETURNING id INTO v_addr;
  INSERT INTO recipient (delivery_address_id, display_order, name, gender) VALUES (v_addr, 1, '김가상', 'female');
  SET CONSTRAINTS ALL IMMEDIATE;  -- 지금까지는 정상(1인에 1명) - 여기서 예외 없어야 함. 이후 검사는 이 트랜잭션 끝까지 즉시 수행됨

  BEGIN
    UPDATE delivery_address SET recipient_type = 'couple' WHERE id = v_addr;  -- recipient는 여전히 1행뿐 -> 트리거가 즉시 발동
    RAISE EXCEPTION 'T26d failed: 타입만 부부로 바꿨는데 허용됨';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;

\echo T26e 기존 부부 배송지에서 수신자 한 명을 지우면 거부 (recipient 쪽 트리거)
BEGIN;
DO $$
DECLARE g constant uuid := '00000000-0000-0000-0000-0000000000d1';
        u2 constant uuid := '00000000-0000-0000-0000-000000000002';
        v_addr uuid;
BEGIN
  INSERT INTO delivery_address (group_id, label, recipient_type, postal_code, address_line1, created_by)
  VALUES (g, '할머니·할아버지 댁(e)', 'couple', '00006', pgp_sym_encrypt('부부', 'dev-only-change-me'), u2) RETURNING id INTO v_addr;
  INSERT INTO recipient (delivery_address_id, display_order, name, gender) VALUES (v_addr, 1, '김가상', 'female');
  INSERT INTO recipient (delivery_address_id, display_order, name, gender) VALUES (v_addr, 2, '김가상2', 'male');
  SET CONSTRAINTS ALL IMMEDIATE;  -- 지금까지는 정상(부부에 2명) - 여기서 예외 없어야 함

  BEGIN
    DELETE FROM recipient WHERE delivery_address_id = v_addr AND display_order = 2;  -- recipient_type은 여전히 couple -> 트리거가 즉시 발동
    RAISE EXCEPTION 'T26e failed: 부부인데 한 명을 지웠는데 허용됨';
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
  INSERT INTO delivery_address (group_id, label, postal_code, address_line1, created_by)
  VALUES (g, '댁', '00004', pgp_sym_encrypt('주소', 'dev-only-change-me'), u3);
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
