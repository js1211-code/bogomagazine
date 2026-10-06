-- [groups 모듈] 구성원 확인, 그룹 만들기, 초대 수락, 멤버 관리(방장 전용), 배송지 가드
-- Flyway 반복 마이그레이션: 내용이 바뀌면 다음 migrate 때 자동 재적용된다. 파일명 번호 순서로 적용된다.
-- 소유 테이블/의존 방향은 docs/architecture.md 와 db/tests/architecture.sql 참고.


-- 권한 규칙: 방장만 멤버를 관리한다 (초대 링크 만들기, 다른 사람 내보내기, 방장 넘기기). 구성원은 누구나 스스로 나갈 수 있다.
-- 아래 함수들은 "행위자(p_actor)"를 인자로 받아 규칙을 검사한다. 앱은 로그인한 사용자를 그대로 넘겨야 한다.
-- 앱이 테이블을 직접 UPDATE/DELETE 하면 이 검사를 우회할 수 있으므로, 운영에서는 DB 권한 분리(TODO.md)로 막는다.

-- 활동 중인 구성원인가 (나간 구성원은 false)
CREATE OR REPLACE FUNCTION is_active_member(p_group uuid, p_user uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM family_member
                    WHERE group_id = p_group AND user_id = p_user AND left_at IS NULL)
$$;

-- 그룹 만들기: 그룹과 방장 구성원을 한 트랜잭션에서 함께 넣는다
-- (그룹과 방장 구성원이 서로를 참조하는 외래키는 커밋 시점에 검사되므로 반드시 같은 트랜잭션이어야 한다)
CREATE OR REPLACE FUNCTION create_family_group(p_name text, p_owner uuid, p_nickname text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
    v_id uuid;
BEGIN
    INSERT INTO family_group (name, owner_id) VALUES (p_name, p_owner) RETURNING id INTO v_id;
    INSERT INTO family_member (group_id, user_id, nickname) VALUES (v_id, p_owner, p_nickname);
    RETURN v_id;
END $$;

-- 초대 링크는 방장(활동 중)만 만들 수 있다
CREATE OR REPLACE FUNCTION guard_invite_creator() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM family_group g
                    WHERE g.id = NEW.group_id AND g.owner_id = NEW.created_by
                      AND is_active_member(g.id, g.owner_id)) THEN
        RAISE EXCEPTION 'family_invite: only the owner of group % can create invites', NEW.group_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_invite_creator ON family_invite;
CREATE TRIGGER trg_invite_creator BEFORE INSERT ON family_invite
    FOR EACH ROW EXECUTE FUNCTION guard_invite_creator();

-- 가족마다 고정 초대 코드 1개(FAM-05, 1004 결정): 이미 있으면 그 링크를 그대로 돌려주고 새로 만들지 않는다.
CREATE OR REPLACE FUNCTION get_or_create_family_invite(p_group uuid, p_actor uuid, p_token_hash text)
RETURNS family_invite
LANGUAGE plpgsql AS $$
DECLARE v family_invite%ROWTYPE;
BEGIN
    SELECT * INTO v FROM family_invite WHERE group_id = p_group;
    IF FOUND THEN RETURN v; END IF;
    INSERT INTO family_invite (group_id, created_by, token_hash) VALUES (p_group, p_actor, p_token_hash)
    RETURNING * INTO v;
    RETURN v;
END $$;

-- 차단 목록(family_block)도 방장만 등록할 수 있다 (FAM-09/10)
CREATE OR REPLACE FUNCTION guard_family_block_creator() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM family_group g WHERE g.id = NEW.group_id AND g.owner_id = NEW.created_by) THEN
        RAISE EXCEPTION 'family_block: only the owner of group % can block members', NEW.group_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_family_block_creator ON family_block;
CREATE TRIGGER trg_family_block_creator BEFORE INSERT ON family_block
    FOR EACH ROW EXECUTE FUNCTION guard_family_block_creator();

-- 배송지는 그 그룹의 활동 중인 구성원이 등록한다
CREATE OR REPLACE FUNCTION guard_address_creator() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_active_member(NEW.group_id, NEW.created_by) THEN
        RAISE EXCEPTION 'delivery_address: user % is not an active member of group %', NEW.created_by, NEW.group_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_address_creator ON delivery_address;
CREATE TRIGGER trg_address_creator BEFORE INSERT ON delivery_address
    FOR EACH ROW EXECUTE FUNCTION guard_address_creator();

-- 수신자(recipient) 인원수는 배송지의 recipient_type과 맞아야 한다(1인=1행, 부부=2행, RCV-01/1005 결정).
-- 두 테이블에 나뉜 같은 사실이 어긋나지 않게 커밋 시점에 검사한다 (배송지 생성 -> 수신자 insert가 같은 트랜잭션의 여러 문장이라 즉시 검사하면 안 됨).
CREATE OR REPLACE FUNCTION assert_recipient_count(p_addr uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_type     text;
    v_expected int;
    v_count    int;
BEGIN
    SELECT recipient_type INTO v_type FROM delivery_address WHERE id = p_addr;
    IF NOT FOUND THEN RETURN; END IF;  -- 배송지 자체가 지워지는 중(CASCADE로 recipient도 함께 지워짐)
    v_expected := CASE v_type WHEN 'single' THEN 1 ELSE 2 END;
    SELECT count(*) INTO v_count FROM recipient WHERE delivery_address_id = p_addr;
    IF v_count <> v_expected THEN
        RAISE EXCEPTION 'delivery_address %: recipient_type=%(%명 기대)인데 수신자가 %명 등록됨', p_addr, v_type, v_expected, v_count
            USING ERRCODE = 'check_violation';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION trg_recipient_count_on_recipient() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM assert_recipient_count(COALESCE(NEW.delivery_address_id, OLD.delivery_address_id));
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_recipient_count ON recipient;
CREATE CONSTRAINT TRIGGER trg_recipient_count
    AFTER INSERT OR UPDATE OR DELETE ON recipient
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trg_recipient_count_on_recipient();

CREATE OR REPLACE FUNCTION trg_recipient_count_on_address() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM assert_recipient_count(NEW.id);
    RETURN NULL;
END $$;

-- AFTER INSERT 도 검사 대상 : 배송지만 만들고 수신자를 하나도 안 넣는 경우를 잡기 위해(그러면 recipient 트리거 자체가 안 일어남)
DROP TRIGGER IF EXISTS trg_address_recipient_count ON delivery_address;
CREATE CONSTRAINT TRIGGER trg_address_recipient_count
    AFTER INSERT OR UPDATE OF recipient_type ON delivery_address
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trg_recipient_count_on_address();

-- 초대 수락: 로그인(카카오/애플)을 마친 사용자가 링크로 들어와 그룹에 합류한다.
--   p_token_hash 는 링크 토큰의 sha256 hex (토큰 원문은 DB 에 없다). 합류하는 사람은 항상 일반 구성원이다.
--   링크는 유효기간·횟수 제한·취소가 없는 영구 링크다(FAM-05, V-23).
--   - 이미 활동 중인 구성원이면 그대로 그룹 id 만 돌려준다 (링크를 두 번 눌러도 안전)
--   - 나갔던 구성원이면 다시 활동 중으로 돌아온다. 방장이 내보낸 사람은 family_block 이 재합류를 막는다(FAM-09/10)
CREATE OR REPLACE FUNCTION accept_family_invite(p_token_hash text, p_user uuid, p_now timestamptz DEFAULT now())
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
    v family_invite%ROWTYPE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM app_user WHERE id = p_user AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'accept_family_invite: user % not found or deleted', p_user;
    END IF;

    SELECT * INTO v FROM family_invite WHERE token_hash = p_token_hash FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'invite not found'; END IF;

    IF is_active_member(v.group_id, p_user) THEN
        RETURN v.group_id;
    END IF;
    IF EXISTS (SELECT 1 FROM family_block WHERE group_id = v.group_id AND user_id = p_user) THEN
        RAISE EXCEPTION 'user % is blocked from group %', p_user, v.group_id USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO family_member (group_id, user_id, joined_at) VALUES (v.group_id, p_user, p_now)
    ON CONFLICT (group_id, user_id) DO UPDATE SET left_at = NULL, joined_at = EXCLUDED.joined_at;
    RETURN v.group_id;
END $$;

-- 내보내기: 방장만 할 수 있다. 행을 지우지 않고 left_at 을 채운다 (그 사람이 쓴 글의 작성자 정보 유지)
-- 그룹만 나가고 계정은 유지하는 "스스로 나가기"는 없다(V-36) — 나가려면 탈퇴(anonymize_user)를 쓴다.
-- 방장은 내보낼 수 없다 (탈퇴하면 자동으로 다른 구성원에게 넘어간다, FAM-11)
CREATE OR REPLACE FUNCTION remove_family_member(p_group uuid, p_actor uuid, p_target uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_owner uuid;
BEGIN
    SELECT owner_id INTO v_owner FROM family_group WHERE id = p_group FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'family group % not found', p_group; END IF;

    IF p_actor <> v_owner THEN
        RAISE EXCEPTION 'only the owner can remove members' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF p_target = v_owner THEN
        RAISE EXCEPTION 'the owner cannot be removed: withdraw instead' USING ERRCODE = 'check_violation';
    END IF;

    UPDATE family_member SET left_at = now()
     WHERE group_id = p_group AND user_id = p_target AND left_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'member % not found or already left', p_target; END IF;

    -- 내보낸 계정은 차단 목록에 등록한다(FAM-09)
    INSERT INTO family_block (group_id, user_id, created_by) VALUES (p_group, p_target, p_actor)
    ON CONFLICT (group_id, user_id) DO NOTHING;
END $$;

-- 차단 해제: 방장만 할 수 있다. 해제하면 같은 초대 링크로 다시 합류 가능 (FAM-10)
CREATE OR REPLACE FUNCTION unblock_family_member(p_group uuid, p_actor uuid, p_target uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_owner uuid;
BEGIN
    SELECT owner_id INTO v_owner FROM family_group WHERE id = p_group;
    IF NOT FOUND THEN RAISE EXCEPTION 'family group % not found', p_group; END IF;
    IF p_actor <> v_owner THEN
        RAISE EXCEPTION 'only the owner can unblock' USING ERRCODE = 'insufficient_privilege';
    END IF;
    DELETE FROM family_block WHERE group_id = p_group AND user_id = p_target;
END $$;

-- 방장 넘기기(수동)는 스펙에 없다(FAM-11, V-14) — 방장이 탈퇴할 때만 자동으로 넘어간다(anonymize_user() 참고).
DROP FUNCTION IF EXISTS transfer_family_owner(uuid, uuid, uuid);
