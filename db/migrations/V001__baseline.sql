-- V001 baseline: 초기 스키마 전체. 아직 어디에도 배포되지 않았으므로 설계가 바뀌면 이 파일에 직접 반영한다.
-- main 에 합쳐지고 어떤 DB 에 적용된 뒤에는 수정하지 않는다 (체크섬이 깨짐). 그때부터는 새 V0xx__설명.sql 을 추가한다.
-- 함수/뷰/트리거는 R__*.sql 에서 관리한다.
--
-- 서비스: 가족 그룹(방장 + 구성원)이 앱 안 피드에 사진/글을 올리면, 매월(필드 테스트는 2주) 그 기간의 글을 모아
--         신문으로 자동 조판한다. 가족에게는 발행 전 미리보기가 없다(V-17) — 운영자(Admin)가 조판 결과를 검수하고
--         필요하면 게시물을 이번 호에서 제외한 뒤 다시 조판시키며, 검수가 끝나면 운영자가 "발송 완료"로 수동 전환한다.
--         로그인은 카카오/애플만. 조부모님(수신자)은 앱 사용자가 아니다.
-- 흐름: 피드 게시 -> (마감) 선별 -> 자동 조판 -> 운영자 조판 검수(제외/재조판은 운영자가) -> 운영자가 발송 완료로 전환 -> 인쇄 -> 배송
--
-- 무결성 원칙: 같은 사실이 두 곳에 있으면(예: 사진의 그룹 = 게시물의 그룹) 복합 외래키로 서로 어긋나지 못하게 한다.
--   복합 외래키는 컬럼 중 하나가 NULL 이면 검사를 건너뛴다 (호 전체 승인, 게시물이 지워진 텍스트 등이 이에 해당).
--   외래키로 표현할 수 없는 것(배치 <-> 선별된 사진, 작성자 <-> 활동 중인 구성원 등)은 R__*.sql 의 트리거가 지킨다.

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid()

-- =========================================================
-- 0. 사용자 / 로그인 (카카오, 애플)
-- =========================================================
CREATE TABLE app_user (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email       text,                  -- 카카오: 동의 안 하면 NULL / 애플: 릴레이 주소일 수 있음
    name        text,                  -- 애플은 최초 로그인 때만 제공 -> 없을 수 있음
    -- 프로필(PRF-01). 사진은 받지 않는다(1005 결정) - 앱 아바타·지면 표기는 캐릭터(PRF-05)로 대체 예정이나
    -- 설계가 아직 확정 전이라 컬럼은 없다(확정되면 추가).
    -- 생일은 월·일만, 선택 입력. 지면 생일 안내(NEWS-07, 마감일부터 30일 이내)에 쓴다
    birth_month int CHECK (birth_month BETWEEN 1 AND 12),
    birth_day   int CHECK (birth_day BETWEEN 1 AND 31),
    -- 가입 동의(ACC-03). 개인정보/약관은 가입 시 필수, 연구활용은 선택이라 NULL 허용.
    -- 가입 폼이 모두 한 번에 제출되므로 기본값(now())으로 둬도 안전 - "동의 안 하면 가입을 안 보낸다"가 전제
    privacy_consented_at     timestamptz NOT NULL DEFAULT now(),
    terms_consented_at       timestamptz NOT NULL DEFAULT now(),
    age_over_14_confirmed_at timestamptz NOT NULL DEFAULT now(),  -- 만 14세 미만이면 앱이 가입 자체를 막는다
    research_consented_at    timestamptz,                         -- 연구·발표 활용 동의(선택)
    created_at  timestamptz NOT NULL DEFAULT now(),
    deleted_at  timestamptz
);
-- 이메일은 있을 때만 유일 (대소문자 무시)
CREATE UNIQUE INDEX ux_app_user_email ON app_user (lower(email)) WHERE email IS NOT NULL;

-- 로그인 수단 (한 사용자가 카카오와 애플을 모두 연결할 수 있다)
CREATE TABLE auth_identity (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    provider      text NOT NULL CHECK (provider IN ('kakao','apple')),
    provider_uid  text NOT NULL,       -- 카카오 회원번호 / 애플 sub (이메일 말고 이것으로 식별)
    email         text,                -- 해당 제공자가 준 이메일 (참고용)
    email_verified boolean NOT NULL DEFAULT false,
    is_private_relay boolean NOT NULL DEFAULT false,   -- 애플 릴레이 이메일 여부
    refresh_token_ref text,            -- 시크릿 저장소 참조 (원문 저장 금지)
    last_login_at timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_uid)
);
CREATE INDEX ix_auth_identity_user ON auth_identity (user_id);

-- 푸시 알림용 디바이스 토큰(Expo). 발행완료, 마감 임박 등에 쓴다. 한 사용자가 여러 기기를 가질 수 있다
CREATE TABLE device (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    platform      text NOT NULL CHECK (platform IN ('ios', 'android')),
    push_token    text NOT NULL,
    last_seen_at  timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    revoked_at    timestamptz
);
CREATE UNIQUE INDEX ux_device_push_token ON device (push_token) WHERE revoked_at IS NULL;
CREATE INDEX ix_device_user ON device (user_id) WHERE revoked_at IS NULL;

-- 정식 출시 대기 신청(WAIT-01). 결제 의향 확인용(M-13). 결제·외부 링크 없음
CREATE TABLE waitlist_signup (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES app_user(id),
    code       text NOT NULL DEFAULT 'WAIT-01',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, code)
);

-- 개인 차단(SAFE-02). 차단하면 내 화면에서 그 사람 콘텐츠를 숨긴다(앱). 팀 신고(report)는 앱이 같이 만든다
CREATE TABLE user_block (
    blocker_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);

-- =========================================================
-- 0-1. 운영자 계정 (Admin) — 가족(app_user)과는 별도의 운영 주체.
--      개발자의 DB 직접 접근은 여기 없다(권한 분리는 TODO.md "DB 권한 분리" 참고).
--      지금은 운영자 4명이 동일한 권한으로 Admin 페이지를 같이 쓴다(ADM-01, 역할 구분/퇴사 처리 없음).
--      바닥 모듈(admin): 다른 모듈을 참조하지 않고, groups/issues 가 이 모듈을 참조한다.
-- =========================================================
CREATE TABLE operator (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    email       text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_operator_email ON operator (lower(email));

-- 운영 알림(ADM-08): 조판 실패(3회) · 신고 접수 시 팀 메일 발송 대상. 특정 운영자가 아니라 팀 전체로 가므로 operator_id 가 없다
CREATE TABLE operator_alert_log (
    id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    kind     text NOT NULL CHECK (kind IN ('layout_failed', 'report_received')),
    ref_type text NOT NULL CHECK (ref_type IN ('issue', 'report')),
    ref_id   uuid NOT NULL,
    sent_at  timestamptz NOT NULL DEFAULT now()
);

-- =========================================================
-- 1. 템플릿 (불변 버전)
-- =========================================================
CREATE TABLE template (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    version     int  NOT NULL,
    -- 판형, 단 수, 그리드, 여백, 블리드, 안전영역
    spec        jsonb NOT NULL,
    -- 규모 제약 (호 생성 시 issue 로 복사되어 호별로 조정 가능)
    min_photos           int NOT NULL DEFAULT 15,
    max_photos           int NOT NULL DEFAULT 250,
    min_pages            int NOT NULL DEFAULT 8,
    max_pages            int NOT NULL DEFAULT 80,
    page_multiple        int NOT NULL DEFAULT 4,   -- 중철 4, 무선철 등은 별도
    photos_per_page_min  int NOT NULL DEFAULT 1,
    photos_per_page_max  int NOT NULL DEFAULT 6,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (name, version)
);

CREATE TABLE page_master (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id  uuid NOT NULL REFERENCES template(id) ON DELETE CASCADE,
    name         text NOT NULL,
    grid         jsonb NOT NULL,
    -- 슬롯 목록: [{slot_id, kind: photo|text, x,y,w,h, aspect_min, aspect_max}]
    slots        jsonb NOT NULL,
    UNIQUE (template_id, name)
);

CREATE TABLE style (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id  uuid NOT NULL REFERENCES template(id) ON DELETE CASCADE,
    kind         text NOT NULL CHECK (kind IN ('paragraph','character','caption','frame')),
    name         text NOT NULL,
    based_on     uuid REFERENCES style(id),   -- 상속: 오버라이드 값만 props 에 저장
    props        jsonb NOT NULL DEFAULT '{}',
    UNIQUE (template_id, kind, name)
);

-- =========================================================
-- 2. 가족 그룹 (방장 + 구성원), 초대, 배송지
-- =========================================================
-- 방장은 owner_id 하나로 표현한다 (구성원의 역할 컬럼을 따로 두지 않는다: 같은 사실이 두 곳에 있으면 어긋난다).
-- 방장만 멤버 관리(초대, 내보내기, 방장 넘기기) 권한을 가진다 -> R__005_groups_membership.sql 의 함수와 트리거
CREATE TABLE family_group (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    newsletter_title text NOT NULL DEFAULT '보고잡지',   -- 신문 제호(FAM-03). name(그룹 이름)과는 다른 값. 변경 권한은 미결(O-14)
    owner_id    uuid NOT NULL REFERENCES app_user(id),   -- 방장
    close_day   int  NOT NULL DEFAULT 1 CHECK (close_day BETWEEN 1 AND 28),  -- 다음 달 며칠 00:00 에 마감
    timezone    text NOT NULL DEFAULT 'Asia/Seoul',
    -- true: 선별 가능한 사진이 min_photos 미만이면 자동 미발행(skipped)
    -- false: 부족해도 마감하고 조판이 큰 사진/여백으로 채움
    auto_skip_below_min boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- 구성원. 나가거나 내보내도 행은 지우지 않고 left_at 을 채운다 (그 사람이 쓴 글/기록의 작성자 정보를 유지하려고).
CREATE TABLE family_member (
    group_id     uuid NOT NULL REFERENCES family_group(id) ON DELETE CASCADE,
    user_id      uuid NOT NULL REFERENCES app_user(id),
    nickname     text,                    -- 가족 안에서의 호칭 (엄마, 아빠 ...)
    -- 수신자(조부모)와의 관계 (PRF-02). 가족 소속 단위로 저장 - 같은 사용자도 가족마다 다를 수 있다.
    -- 호칭 대응표(TTL-01~04) 8개 값. 합류 후 선택/수정하므로 처음엔 NULL 일 수 있다
    relationship text CHECK (relationship IN ('손녀', '손자', '딸', '아들', '며느리', '사위', '손주며느리', '손주사위')),
    joined_at    timestamptz NOT NULL DEFAULT now(),
    left_at      timestamptz,             -- NULL = 활동 중
    PRIMARY KEY (group_id, user_id),
    CHECK (left_at IS NULL OR left_at >= joined_at)
);

-- 방장은 반드시 그 그룹의 구성원이어야 한다. 그룹과 구성원이 서로를 참조하므로 커밋 시점에 검사한다
-- (그룹을 만들 때는 한 트랜잭션에서 그룹과 방장 구성원을 함께 넣는다: create_family_group()).
ALTER TABLE family_group
    ADD CONSTRAINT family_group_owner_member_fkey
    FOREIGN KEY (id, owner_id) REFERENCES family_member (group_id, user_id) DEFERRABLE INITIALLY DEFERRED;

-- 카카오톡으로 보내는 초대 링크. 링크의 토큰 원문은 저장하지 않고 해시만 저장한다.
-- 애플은 이메일을 숨길 수 있으므로 이메일이 아니라 링크 토큰으로 합류시킨다. 합류하는 사람은 항상 일반 구성원이다.
-- 카톡 공유 링크는 유효기간·사용 횟수 제한·취소가 없다(FAM-05, V-23) — 한 번 만들면 계속 쓰는 영구 링크.
CREATE TABLE family_invite (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id    uuid NOT NULL UNIQUE REFERENCES family_group(id) ON DELETE CASCADE,  -- 가족마다 고정 코드 1개(FAM-05, 1004 결정)
    created_by  uuid NOT NULL,              -- 방장 (R__005 트리거가 검사)
    token_hash  text NOT NULL UNIQUE CHECK (length(token_hash) = 64),   -- sha256 hex
    created_at  timestamptz NOT NULL DEFAULT now(),
    -- 커밋 시점 검사: 그룹을 지우면 구성원과 초대가 같은 문장에서 함께 지워지기 때문
    FOREIGN KEY (group_id, created_by) REFERENCES family_member (group_id, user_id) DEFERRABLE INITIALLY DEFERRED
);

-- 방장이 내보낸 계정 차단 목록(FAM-09/10). 같은 초대 링크로 재합류 불가, 방장이 해제하면 다시 가능
CREATE TABLE family_block (
    group_id    uuid NOT NULL REFERENCES family_group(id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES app_user(id),
    created_by  uuid NOT NULL,              -- 방장 (R__005 트리거가 검사)
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (group_id, user_id),
    FOREIGN KEY (group_id, created_by) REFERENCES family_member (group_id, user_id) DEFERRABLE INITIALLY DEFERRED
);

-- 조부모님 배송지. 조부모님은 앱에 로그인하지 않고 신문으로 받으시므로 주소만 저장한다.
-- 수신자(사람) 정보는 recipient 테이블에 1~2행으로 따로 둔다(1005 결정, 부부는 두 분을 각자 입력받음 - RCV-01/FAM-01).
-- 주문(print_order)에는 주문 시점의 주소를 복사해 두므로, 여기서 주소를 고치거나 지워도 이미 보낸 주문의 기록은 바뀌지 않는다.
CREATE TABLE delivery_address (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id        uuid NOT NULL REFERENCES family_group(id) ON DELETE CASCADE,
    label           text NOT NULL,          -- 예: 친할머니·친할아버지 댁
    recipient_phone bytea,                  -- pgcrypto pgp_sym_encrypt() 로 암호화. 키는 앱이 관리(DELIVERY_PII_KEY), DB 에는 없음
    recipient_type  text NOT NULL DEFAULT 'single' CHECK (recipient_type IN ('single', 'couple')),  -- recipient 행 수(1 또는 2)와 맞아야 한다 (R__005 트리거)
    postal_code     text NOT NULL,
    address_line1   bytea NOT NULL,          -- 암호화 (recipient_phone 과 같은 방식)
    address_line2   bytea,
    memo            text,                   -- 배송 메모 (예: 경비실에 맡겨 주세요)
    created_by      uuid NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (group_id, created_by) REFERENCES family_member (group_id, user_id) DEFERRABLE INITIALLY DEFERRED
);

-- 수신자(조부모) 한 명 (RCV-01). 1인이면 1행(display_order=1), 부부면 2행. 성별은 호칭 결정에 필수(기술 필수).
-- 사진은 받지 않는다(O-16, 1004에서 "선택 입력"으로 뒀다가 1005에서 다시 "안 받음"으로 바뀜) - 캐릭터(PRF-05)로 대체 예정이나 설계 미확정이라 컬럼 없음
CREATE TABLE recipient (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_address_id  uuid NOT NULL REFERENCES delivery_address(id) ON DELETE CASCADE,
    display_order        int NOT NULL CHECK (display_order IN (1, 2)),
    name                 text NOT NULL,
    gender               text NOT NULL CHECK (gender IN ('female', 'male')),
    UNIQUE (delivery_address_id, display_order)
);

-- 배송지 열람/다운로드 기록. 운영자(operator)가 Admin 페이지에서 봤을 때만 남는다 (ADM-01: 배송지는 Admin에서만 열람)
CREATE TABLE delivery_address_access_log (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    delivery_address_id uuid NOT NULL REFERENCES delivery_address(id) ON DELETE CASCADE,
    operator_id         uuid NOT NULL REFERENCES operator(id),
    action              text NOT NULL CHECK (action IN ('view', 'download')),
    accessed_at         timestamptz NOT NULL DEFAULT now()
);

-- =========================================================
-- 3. 월간 호
-- =========================================================
CREATE TABLE issue (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id        uuid NOT NULL REFERENCES family_group(id),
    title           text NOT NULL,
    period_start    date NOT NULL,          -- 이 호에 실리는 게시물의 기간 (그룹 타임존 기준 날짜)
    period_end      date NOT NULL,
    -- 상태 흐름은 아래 issue_status_transition 과 R__020_issues_lifecycle.sql 참고
    --   collecting(수집) -> closing(마감 처리: 선별+조판) -> review(운영자 조판 검수, 가족 미리보기 없음 V-17)
    --   -> printing(인쇄 제작, 운영자가 수동 전환) -> printed(인쇄 완료/배송, 운영자가 수동 전환) -> archived
    --   수집량 미달 시 collecting -> skipped(이번 호 미발행) -> archived
    status          text NOT NULL DEFAULT 'collecting'
        CHECK (status IN ('collecting','closing','review','printing',
                          'printed','skipped','archived')),
    status_changed_at timestamptz NOT NULL DEFAULT now(),
    close_at        timestamptz NOT NULL,     -- 수집 마감 예정 시각
    closed_at       timestamptz,              -- 실제로 수집을 닫은 시각 (closing 진입 시)
    -- 마감 배치 실패 기록: 5회 이상 실패한 호는 자동 재시도 대상에서 빠지고 사람이 확인한다
    close_attempts  int NOT NULL DEFAULT 0,
    close_error     text,
    template_id     uuid NOT NULL REFERENCES template(id),
    -- 템플릿 값을 복사해 호별로 조정 가능하게 둠
    min_photos      int NOT NULL,
    max_photos      int NOT NULL,
    min_pages       int NOT NULL,
    max_pages       int NOT NULL,
    page_multiple   int NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CHECK (period_end >= period_start),
    CHECK (min_photos <= max_photos),
    CHECK (min_pages <= max_pages),
    UNIQUE (group_id, period_start),          -- 그룹당 같은 기간의 호는 하나
    UNIQUE (id, group_id)                     -- 복합 외래키(issue_media/text_block 이 같은 그룹만 참조)의 대상
);

-- 상태 변경 이력 (진행 타임라인 조회용)
CREATE TABLE issue_status_history (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    issue_id     uuid NOT NULL REFERENCES issue(id) ON DELETE CASCADE,
    from_status  text,
    to_status    text NOT NULL,
    changed_by   uuid REFERENCES app_user(id),      -- 가족(방장 등)이 바꾼 경우
    operator_id  uuid REFERENCES operator(id),      -- 운영자가 Admin 페이지에서 바꾼 경우
    note         text,
    changed_at   timestamptz NOT NULL DEFAULT now(),
    -- 둘 다 NULL = 배치가 자동으로 바꿈(예: 리뷰 기간 경과 자동 인쇄 전환). 둘 다 채워질 일은 없다
    CHECK (NOT (changed_by IS NOT NULL AND operator_id IS NOT NULL))
);
CREATE INDEX ix_issue_status_history ON issue_status_history (issue_id, changed_at);
CREATE INDEX ix_issue_status_history_operator ON issue_status_history (operator_id) WHERE operator_id IS NOT NULL;

-- 허용된 상태 전이 표 (행 데이터는 R__020_issues_lifecycle.sql 이 관리한다)
CREATE TABLE issue_status_transition (
    from_status  text NOT NULL,
    to_status    text NOT NULL,
    note         text,
    PRIMARY KEY (from_status, to_status)
);

-- =========================================================
-- 4. 피드 (앱 안에서 가족이 올리는 사진/글)와 호별 선별
--    게시물은 호와 독립이다. 호는 "그 달(period_start~period_end)의 게시물을 모아 만든 결과물"이다.
-- =========================================================
-- 질문카드(QST-01~07): 주 1개씩 공개, 호당 2개. MVP는 팀이 작성한 고정 풀(질문 풀 관리 UI는 v2, O-23 아님)
-- 금칙어 목록(SAFE-03). 팀이 직접 관리(운영 CRUD는 범위 밖, 지금은 DB에 직접 넣고 뺀다)
CREATE TABLE banned_word (
    word text PRIMARY KEY
);

CREATE TABLE question (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    app_body      text NOT NULL,        -- 앱 문구. 수신자 자리에 호칭이 자동 삽입된다(TTL-01)
    print_body    text NOT NULL,        -- 지면용 문구. 호칭 없이 대상을 바꿔 쓴다
    corner_name   text NOT NULL,        -- 지면 코너명 (주제형, NEWS-03)
    kind          text NOT NULL CHECK (kind IN ('binary', 'balance', 'multiple_choice', 'short_answer')),
    options       jsonb,                -- 선택형 질문의 선택지. 주관식은 NULL
    target        text NOT NULL CHECK (target IN ('sender', 'recipient', 'us')),  -- 질문 소재(QST-01)
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CHECK (kind = 'short_answer' OR options IS NOT NULL)
);

-- 호에 공개된 질문 (display_order = 질문 1 / 질문 2). 발행(published_at)은 NOTI-01 이 참조
CREATE TABLE issue_question (
    issue_id      uuid NOT NULL REFERENCES issue(id) ON DELETE CASCADE,
    question_id   uuid NOT NULL REFERENCES question(id),
    display_order int NOT NULL CHECK (display_order > 0),
    published_at  timestamptz,
    PRIMARY KEY (issue_id, question_id),
    UNIQUE (issue_id, display_order)
);

-- 알림 발송 이력(NOTI-01~06, M-10). 질문 공개/마감 리마인더/발송완료/방장 변경 푸시를 보낼 때마다 한 행.
-- 알림 목록(NOTI-06, 1004 결정): 종 아이콘으로 지난 알림을 가족별로 묶어 보여주고, read_at 으로 읽음 표시. 60일 보관(O-33) 후 자동 삭제(delete_old_notifications())
CREATE TABLE notification_log (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     uuid NOT NULL REFERENCES app_user(id),
    group_id    uuid NOT NULL REFERENCES family_group(id),  -- 모든 알림은 가족 하나에 속한다(목록에서 가족 이름과 함께 묶어 보여줌)
    issue_id    uuid,            -- FK는 아래 복합 외래키 하나로만 건다(issue_id 단독 FK를 따로 두지 않음 - 중복)
    question_id uuid REFERENCES question(id),  -- kind='question_published' 일 때만 채움 (호당 질문 2개라 issue_id 만으론 중복 방지가 안 됨)
    kind        text NOT NULL CHECK (kind IN ('question_published', 'deadline_reminder', 'published', 'owner_changed')),
    read_at     timestamptz,     -- 알림 목록 읽음 표시(NOTI-06). NULL = 안 읽음
    sent_at     timestamptz NOT NULL DEFAULT now(),
    -- issue_id 가 있으면 그 호가 반드시 이 group_id 소속이어야 한다. group_id는 NOT NULL이라 issue_id가 NULL일 때만(owner_changed 등) 검사를 건너뛴다
    FOREIGN KEY (issue_id, group_id) REFERENCES issue (id, group_id)
);
-- 중복 발송 방지: question_published는 (user, question) 단위, 나머지는 (user, issue) 단위로 한 번만
CREATE UNIQUE INDEX ux_notification_log_question  ON notification_log (user_id, question_id) WHERE kind = 'question_published';
CREATE UNIQUE INDEX ux_notification_log_reminder   ON notification_log (user_id, issue_id)    WHERE kind = 'deadline_reminder';
CREATE UNIQUE INDEX ux_notification_log_published  ON notification_log (user_id, issue_id)    WHERE kind = 'published';

CREATE TABLE post (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id    uuid NOT NULL REFERENCES family_group(id) ON DELETE CASCADE,
    author_id   uuid NOT NULL,
    body        text,                       -- 글 (사진만 올릴 수도 있다). 질문 답변의 "한 줄 덧붙이기"/주관식 답도 여기
    question_id uuid REFERENCES question(id),  -- NULL = 자유 게시물, NOT NULL = 질문 답변(QST-03)
    question_option text,                    -- 선택형 질문에서 고른 선택지 (주관식/자유 게시물은 NULL)
    visibility  text NOT NULL DEFAULT 'all' CHECK (visibility IN ('all', 'recipient_only')),  -- POST-02/QST-03
    posted_at   timestamptz NOT NULL DEFAULT now(),   -- 어느 호에 실릴지를 정한다 (그룹 타임존 기준 날짜)
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    deleted_at  timestamptz,                -- 삭제한 글. 이미 마감된 호의 내용은 바뀌지 않는다
    UNIQUE (id, group_id),                  -- 복합 외래키(사진/텍스트가 같은 그룹만 참조)의 대상
    CHECK (question_id IS NOT NULL OR question_option IS NULL),
    -- 작성자는 그 그룹의 구성원이어야 한다 (활동 중인지는 R__030 트리거가 검사)
    FOREIGN KEY (group_id, author_id) REFERENCES family_member (group_id, user_id) DEFERRABLE INITIALLY DEFERRED
);
-- 한 질문에는 1명당 답변 1개(삭제되지 않은 것만, M-03)
CREATE UNIQUE INDEX ux_post_question_author ON post (group_id, question_id, author_id) WHERE deleted_at IS NULL AND question_id IS NOT NULL;

CREATE TABLE media (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id           uuid NOT NULL,
    group_id          uuid NOT NULL,        -- 게시물의 그룹 (복합 외래키로 일치를 보장. issue_media 가 같은 그룹만 묶게 하려고 둠)
    storage_key       text NOT NULL,
    sha256            text NOT NULL,
    width             int  NOT NULL,
    height            int  NOT NULL,
    exif              jsonb,
    taken_at          timestamptz,
    initiated_at      timestamptz NOT NULL DEFAULT now(),  -- 업로드 시작 시각(POST-07 마감 유예, 1004 결정). 클라이언트가 보낸다
    color_profile     text,
    -- 이미지 분석 결과
    focal_point       jsonb,                -- {x,y} 0..1
    saliency          jsonb,                -- 주요 피사체/얼굴 영역
    quality_score     real,
    phash             bigint,               -- 유사 사진 묶기
    rights_ok         boolean NOT NULL DEFAULT true,    -- false 면 선별에서 제외 (신고 등으로 쓸 수 없는 사진)
    -- 사용자의 의도 (호와 무관하게 사진에 붙는 선택). 선별 결과는 issue_media 에 따로 둔다.
    pinned            boolean NOT NULL DEFAULT false,   -- "꼭 넣기"
    excluded          boolean NOT NULL DEFAULT false,   -- "이번 호에서 빼기"
    created_at        timestamptz NOT NULL DEFAULT now(),
    deleted_at        timestamptz,          -- 소프트 삭제(NFR-11). 글을 지우면 사진도 같이 지워지지만, 사진만 따로 뺄 수도 있다
    UNIQUE (post_id, sha256),
    UNIQUE (id, group_id),                  -- 복합 외래키(issue_media)의 대상
    FOREIGN KEY (post_id, group_id) REFERENCES post (id, group_id) ON DELETE CASCADE
);
CREATE INDEX ix_media_phash ON media (phash);

CREATE TABLE media_rendition (
    media_id     uuid NOT NULL REFERENCES media(id) ON DELETE CASCADE,
    purpose      text NOT NULL CHECK (purpose IN ('thumb','preview','print')),
    storage_key  text NOT NULL,
    width        int NOT NULL,
    height       int NOT NULL,
    PRIMARY KEY (media_id, purpose)
);

-- 호별 사진 선별 결과. 사진 자체(media)와 "이 호에서 어떻게 되었나"를 분리한다 (파생 데이터, 마감할 때 만들어진다).
CREATE TABLE issue_media (
    issue_id          uuid NOT NULL,
    media_id          uuid NOT NULL,
    group_id          uuid NOT NULL,        -- 호의 그룹 = 사진의 그룹 (복합 외래키 두 개로 보장)
    selection_status  text NOT NULL DEFAULT 'candidate'
        CHECK (selection_status IN ('candidate','selected','excluded_auto','excluded_manual')),
    selection_score   real,
    created_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (issue_id, media_id),
    FOREIGN KEY (issue_id, group_id) REFERENCES issue (id, group_id) ON DELETE CASCADE,
    FOREIGN KEY (media_id, group_id) REFERENCES media (id, group_id) ON DELETE CASCADE
);
CREATE INDEX ix_issue_media_sel ON issue_media (issue_id, selection_status);

-- 호에 들어가는 글 조각(제목, 캡션, 인용, 본문). 게시물 글에서 만들어지거나 조판 중에 만들어진다.
CREATE TABLE text_block (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id         uuid NOT NULL,
    group_id         uuid NOT NULL,
    post_id          uuid,                  -- 원본 게시물 (제목처럼 만들어진 글은 NULL)
    kind             text NOT NULL CHECK (kind IN ('title','caption','quote','body')),
    body             text NOT NULL,
    runs             jsonb,                 -- 인라인 서식 span 배열
    created_by       uuid REFERENCES app_user(id),
    created_at       timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (issue_id, group_id) REFERENCES issue (id, group_id) ON DELETE CASCADE,
    FOREIGN KEY (post_id, group_id)  REFERENCES post (id, group_id) ON DELETE SET NULL (post_id)
);

-- 질문카드 답변 댓글(QST-06). 답변(post.question_id IS NOT NULL) 단위, 1뎁스(댓글에 댓글 없음 - 자기참조 컬럼이 없어 구조적으로 막힘)
CREATE TABLE comment (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    uuid NOT NULL REFERENCES post(id) ON DELETE CASCADE,
    author_id  uuid NOT NULL,
    body       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

-- 콘텐츠 신고(SAFE-01). target_id 는 다형 참조라 FK 를 걸지 않는다(override.target_id 와 같은 이유, 신고 뒤
-- 대상이 지워져도 신고 기록은 남아야 한다). ADM-05: 운영자가 24시간 안 확인·조치
CREATE TABLE report (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id uuid NOT NULL REFERENCES app_user(id),
    target_type text NOT NULL CHECK (target_type IN ('post', 'comment', 'user')),  -- 'user' = 개인 차단 시 자동 신고(SAFE-02)
    target_id   uuid NOT NULL,
    reason      text NOT NULL,
    status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'resolved')),
    resolved_by uuid REFERENCES operator(id),
    resolved_at timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CHECK (status = 'pending' OR (resolved_by IS NOT NULL AND resolved_at IS NOT NULL))
);

-- =========================================================
-- 5. 자동 조판 결과 (파생물, 재생성 가능)
-- =========================================================
CREATE TABLE layout_run (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    -- "최신"은 created_at 이 아니라 seq 로 판정한다 (같은 트랜잭션에서 만든 행은 created_at 이 같다)
    seq                  bigint GENERATED ALWAYS AS IDENTITY,
    -- 호별 조판 회차 (1부터). R__060_layout_worker.sql 의 트리거가 자동 부여한다.
    run_no               int NOT NULL,
    issue_id             uuid NOT NULL REFERENCES issue(id) ON DELETE CASCADE,
    template_id          uuid NOT NULL REFERENCES template(id),
    algorithm_version    text NOT NULL,
    params               jsonb NOT NULL DEFAULT '{}',
    seed                 bigint NOT NULL,
    input_snapshot_hash  text NOT NULL,   -- 입력이 바뀌었는지 판단
    -- superseded: 재오픈/재조판으로 더 이상 유효하지 않은 실행 (워커는 저장 전에 이 상태인지 확인할 것)
    status               text NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued','running','done','failed','superseded')),
    score                real,
    report               jsonb,          -- 조판 결과 보고: {warnings, unplaced, stats}
    log                  text,
    started_at           timestamptz,
    finished_at          timestamptz,
    -- 워커 임대(lease): R__060_layout_worker.sql 의 claim/heartbeat/complete/fail/reap 함수가 관리
    locked_by            text,
    locked_at            timestamptz,
    heartbeat_at         timestamptz,    -- running 인데 오래 갱신이 없으면 워커가 죽은 것으로 보고 failed 처리
    attempts             int NOT NULL DEFAULT 0,   -- 이 호의 몇 번째 시도인지 (실패 횟수 + 1)
    input_ref            text,           -- 조판 입력 JSON 의 저장 위치 (재현용)
    created_at           timestamptz NOT NULL DEFAULT now(),
    UNIQUE (issue_id, run_no),
    -- 복합 외래키(승인/수정/인쇄작업의 호와 조판의 호가 같음을 보장)의 대상
    UNIQUE (id, issue_id)
);
CREATE INDEX ix_layout_run_issue ON layout_run (issue_id, seq DESC);
CREATE INDEX ix_layout_run_running ON layout_run (heartbeat_at) WHERE status = 'running';

CREATE TABLE page (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id     uuid NOT NULL REFERENCES layout_run(id) ON DELETE CASCADE,
    page_no    int  NOT NULL,
    master_id  uuid REFERENCES page_master(id),
    UNIQUE (run_id, page_no),
    UNIQUE (id, run_id)       -- 복합 외래키(승인의 페이지와 조판이 같음을 보장)의 대상
);

CREATE TABLE placement (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    page_id   uuid NOT NULL REFERENCES page(id) ON DELETE CASCADE,
    slot_id   text,
    ref_type  text NOT NULL CHECK (ref_type IN ('media','text_block')),
    -- 배치에 쓰인 사진/텍스트는 따로 지울 수 없다. 사진은 호와 독립이라 호를 지워도 남으므로 즉시 검사한다.
    -- 텍스트는 호를 지우면 text_block 과 placement 가 같은 문장에서 지워지고 순서가 보장되지 않으므로 커밋 시점에 검사한다.
    -- 이 호에서 선별된 사진/같은 호의 텍스트인지는 R__060_layout_worker.sql 의 트리거가 지킨다.
    media_id       uuid REFERENCES media(id),
    text_block_id  uuid REFERENCES text_block(id) DEFERRABLE INITIALLY DEFERRED,
    -- 단위: mm
    x numeric(8,2) NOT NULL,
    y numeric(8,2) NOT NULL,
    w numeric(8,2) NOT NULL,
    h numeric(8,2) NOT NULL,
    z int NOT NULL DEFAULT 0,
    crop      jsonb,                    -- 원본 기준 크롭 사각형 (0..1)
    style_id  uuid REFERENCES style(id),
    CHECK (
        (ref_type = 'media'      AND media_id      IS NOT NULL AND text_block_id IS NULL) OR
        (ref_type = 'text_block' AND text_block_id IS NOT NULL AND media_id      IS NULL)
    )
);
CREATE INDEX ix_placement_page  ON placement (page_id);
CREATE INDEX ix_placement_media ON placement (media_id);
CREATE INDEX ix_placement_text_block ON placement (text_block_id);

-- =========================================================
-- 6. 협업: 수동 보정 / 락
--    승인 절차는 없다. review 단계의 수정(override)은 운영자의 조판 검수(ADM-03)에서만 쓴다 - 가족은 쓰지 않음
-- =========================================================
CREATE TABLE override (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id     uuid NOT NULL REFERENCES issue(id) ON DELETE CASCADE,
    run_id       uuid NOT NULL,
    seq          bigint GENERATED ALWAYS AS IDENTITY,   -- 변경 순서
    target_type  text NOT NULL CHECK (target_type IN ('page','placement','media')),
    target_id    uuid NOT NULL,
    op           jsonb NOT NULL,   -- move/resize/swap/crop/pin/exclude ...
    author_id    uuid REFERENCES app_user(id),      -- 가족이 만든 수정
    operator_id  uuid REFERENCES operator(id),      -- 운영자가 조판 검수(ADM-03)에서 만든 수정
    created_at   timestamptz NOT NULL DEFAULT now(),
    -- 작성자는 가족 또는 운영자 중 정확히 하나 (배치가 자동으로 만드는 수정은 없다)
    CHECK ((author_id IS NOT NULL) <> (operator_id IS NOT NULL)),
    -- 수정이 가리키는 조판이 이 호의 조판이어야 한다
    FOREIGN KEY (run_id, issue_id) REFERENCES layout_run (id, issue_id) ON DELETE CASCADE
);
CREATE INDEX ix_override_run_seq ON override (run_id, seq);

CREATE TABLE page_lock (
    page_id     uuid PRIMARY KEY REFERENCES page(id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES app_user(id),
    expires_at  timestamptz NOT NULL
);

-- =========================================================
-- 7. 미리보기 / 인쇄 / 배송
-- =========================================================
CREATE TABLE preview (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id        uuid NOT NULL,
    override_seq  bigint NOT NULL DEFAULT 0,   -- 이 시점까지의 수정 반영
    page_no       int NOT NULL,
    storage_key   text,
    status        text NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued','done','failed')),
    UNIQUE (run_id, override_seq, page_no),
    -- 존재하는 페이지의 미리보기만 둘 수 있다 (page 가 지워지면 함께 지워짐)
    FOREIGN KEY (run_id, page_no) REFERENCES page (run_id, page_no) ON DELETE CASCADE
);

CREATE TABLE print_job (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    seq               bigint GENERATED ALWAYS AS IDENTITY,   -- 최신 판정 기준 (created_at 아님)
    issue_id          uuid NOT NULL REFERENCES issue(id),
    run_id            uuid NOT NULL,
    override_seq      bigint NOT NULL,        -- 확정본 고정
    pdf_key           text,
    pdf_profile       text NOT NULL DEFAULT 'PDF/X-1a',
    color_mode        text NOT NULL DEFAULT 'CMYK' CHECK (color_mode IN ('CMYK','RGB')),
    bleed_mm          numeric(4,1) NOT NULL DEFAULT 3.0,
    crop_marks        boolean NOT NULL DEFAULT true,
    preflight_report  jsonb,                  -- 해상도 부족, 폰트 누락, 안전영역 침범
    status            text NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued','rendering','preflight_failed','ready','failed')),
    created_at        timestamptz NOT NULL DEFAULT now(),
    -- 인쇄할 조판이 이 호의 조판이어야 한다
    FOREIGN KEY (run_id, issue_id) REFERENCES layout_run (id, issue_id)
);

-- 신문 PDF 열람 기록(M-12, PUB-02). 발송 완료 후 가족이 앱에서 PDF 를 열 때마다 한 행
CREATE TABLE newsletter_view_log (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    print_job_id uuid NOT NULL REFERENCES print_job(id),
    user_id      uuid NOT NULL REFERENCES app_user(id),
    viewed_at    timestamptz NOT NULL DEFAULT now()
);

-- 인쇄 주문 1건 = 배송지 1곳. 같은 인쇄 작업(PDF)으로 조부모님 댁마다 주문을 하나씩 만든다.
-- 받는 사람/주소는 주문 시점의 값을 복사해 둔다 (배송지를 나중에 고치거나 지워도 이미 보낸 주문의 기록이 바뀌지 않게).
-- R__080_printing_guards.sql 의 트리거가 "같은 그룹의 배송지", "활동 중인 구성원의 주문"을 검사한다.
CREATE TABLE print_order (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    seq                 bigint GENERATED ALWAYS AS IDENTITY,   -- 최신 판정 기준 (created_at 아님)
    print_job_id        uuid NOT NULL REFERENCES print_job(id),
    delivery_address_id uuid REFERENCES delivery_address(id) ON DELETE SET NULL,   -- 어느 배송지에서 복사했는지 (참고용)
    ordered_by          uuid NOT NULL REFERENCES app_user(id),
    recipient_name      text NOT NULL,       -- 배송지의 recipient(1~2명)를 합친 문자열로 앱이 채운다 (예: "김가상·김가상2")
    recipient_phone     bytea,                  -- delivery_address 와 같은 방식(pgcrypto)으로 암호화해서 복사
    postal_code         text NOT NULL,
    address_line1       bytea NOT NULL,          -- delivery_address 와 같은 방식(pgcrypto)으로 암호화해서 복사
    address_line2       bytea,
    vendor              text,
    quantity            int NOT NULL DEFAULT 1 CHECK (quantity > 0),
    price               numeric(12,2),
    status              text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','confirmed','printing','shipped','delivered','cancelled')),
    tracking            text,
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- =========================================================
-- 8. 폰트
-- =========================================================
CREATE TABLE font (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    family       text NOT NULL,
    weight       int  NOT NULL DEFAULT 400,
    italic       boolean NOT NULL DEFAULT false,
    storage_key  text NOT NULL,
    sha256       text NOT NULL,
    license      text,
    fallback     uuid REFERENCES font(id),
    UNIQUE (family, weight, italic)
);

-- =========================================================
-- 9. 추가 인덱스 (조회 경로 + 부모 삭제 시 연쇄 삭제 속도)
-- =========================================================
-- 마감 배치가 찾는 "수집 중이고 마감이 지난 호"
CREATE INDEX ix_issue_collecting_close ON issue (close_at) WHERE status = 'collecting';
-- 사용자 기준 조회 ("내가 속한 그룹"): 기본키가 (group_id, user_id)라서 user_id 만으로는 못 탄다
CREATE INDEX ix_family_member_user   ON family_member (user_id);
CREATE INDEX ix_family_invite_group  ON family_invite (group_id);
CREATE INDEX ix_delivery_address_group ON delivery_address (group_id);
-- 피드: 그룹의 기간별 게시물 (월 마감 때 모으는 경로), 작성자별 (복합 외래키/탈퇴 처리)
CREATE INDEX ix_post_group_time      ON post (group_id, posted_at);
CREATE INDEX ix_post_group_author    ON post (group_id, author_id);
CREATE INDEX ix_media_post           ON media (post_id);
CREATE INDEX ix_issue_media_media    ON issue_media (media_id);
CREATE INDEX ix_text_block_issue     ON text_block (issue_id);
CREATE INDEX ix_text_block_post      ON text_block (post_id);
CREATE INDEX ix_comment_post         ON comment (post_id);
CREATE INDEX ix_post_question        ON post (question_id) WHERE question_id IS NOT NULL;
CREATE INDEX ix_report_status        ON report (status) WHERE status = 'pending';
CREATE INDEX ix_notification_log_issue ON notification_log (issue_id);
CREATE INDEX ix_notification_log_group ON notification_log (group_id);
-- 알림 목록(NOTI-06) 조회 경로: 사용자 기준 최신순
CREATE INDEX ix_notification_log_user  ON notification_log (user_id, sent_at DESC);
CREATE INDEX ix_newsletter_view_log_job ON newsletter_view_log (print_job_id);
-- 진행 뷰가 페이지/호/인쇄 단위로 "가장 최근 1건"을 찾는 경로
CREATE INDEX ix_override_issue       ON override (issue_id);
CREATE INDEX ix_print_job_issue      ON print_job (issue_id, seq DESC);
CREATE INDEX ix_print_job_run        ON print_job (run_id);
CREATE INDEX ix_print_order_job      ON print_order (print_job_id, seq DESC);
CREATE INDEX ix_print_order_address  ON print_order (delivery_address_id);
CREATE INDEX ix_delivery_address_access_log ON delivery_address_access_log (delivery_address_id, accessed_at);

-- =========================================================
-- 10. 테이블 소유 모듈 + 설명 (소유권의 단일 기준)
--     형식: 'module:<모듈> | <설명>'. db/tests/architecture.sql 이 형식을 검사하고
--     docs/erd.md 생성기(scripts/gen_erd.py)가 이 코멘트로 모듈별로 묶는다.
-- =========================================================
COMMENT ON TABLE app_user                IS 'module:identity | 사용자. 프로필(사진·생일)과 가입 동의 기록(ACC-03) 포함. 탈퇴하면 익명화하고 행은 유지한다';
COMMENT ON TABLE auth_identity           IS 'module:identity | 로그인 수단(카카오/애플). (provider, provider_uid)로 식별';
COMMENT ON TABLE device                  IS 'module:identity | 푸시 알림용 디바이스 토큰(Expo). 발행완료/마감 임박 등에 쓴다';
COMMENT ON TABLE waitlist_signup          IS 'module:identity | 정식 출시 대기 신청(WAIT-01). 결제 의향 확인용(M-13)';
COMMENT ON TABLE user_block               IS 'module:identity | 개인 차단(SAFE-02). 차단한 사람의 콘텐츠를 숨긴다';
COMMENT ON TABLE operator                IS 'module:admin | 운영자 계정(Admin 페이지). 가족(app_user)과 분리된 로그인, 역할 구분 없이 동일 권한(ADM-01)';
COMMENT ON TABLE operator_alert_log      IS 'module:admin | 조판 실패(3회)·신고 접수 시 팀 메일 발송 대상(ADM-08)';
COMMENT ON TABLE family_group            IS 'module:groups | 가족 그룹. 방장(owner_id), 신문 제호(newsletter_title, FAM-03)와 마감 정책(마감일, 타임존, 미달 시 자동 미발행)';
COMMENT ON TABLE family_member           IS 'module:groups | 그룹 구성원. 수신자와의 관계(호칭용)를 가족 단위로 저장. 나가도 행은 남기고 left_at 만 채운다';
COMMENT ON TABLE family_invite           IS 'module:groups | 카카오톡 초대 링크(토큰 해시). 영구 링크, 가족마다 1개, 방장만 만든다(FAM-05, 1004 결정)';
COMMENT ON TABLE family_block            IS 'module:groups | 방장이 내보낸 계정 차단 목록(FAM-09/10). 같은 링크로 재합류 불가';
COMMENT ON TABLE delivery_address        IS 'module:groups | 조부모님 배송지(우편 주소, 암호화). 수신자 정보는 recipient 테이블. 주문에는 복사본을 남긴다';
COMMENT ON TABLE recipient               IS 'module:groups | 배송지의 수신자 1~2명(1인/부부, RCV-01). 이름·성별만(사진은 안 받음, 1005 결정)';
COMMENT ON TABLE delivery_address_access_log IS 'module:groups | 배송지 열람/다운로드 기록. 운영자(operator)가 봤을 때만 남는다 (ADM-01)';
COMMENT ON TABLE template                IS 'module:templates | 불변 버전의 판형 템플릿과 규모 제약(사진/페이지 수)';
COMMENT ON TABLE page_master             IS 'module:templates | 페이지 마스터(슬롯 배치 정의)';
COMMENT ON TABLE style                   IS 'module:templates | 문단/글자 스타일(상속 구조)';
COMMENT ON TABLE font                    IS 'module:templates | 폰트 메타데이터';
COMMENT ON TABLE issue                   IS 'module:issues | 월간 호. 그 달의 게시물을 모아 만든 결과물. 상태는 change_issue_status()로만 바꾼다';
COMMENT ON TABLE issue_status_history    IS 'module:issues | 호 상태 변경 이력. changed_by(가족) 또는 operator_id(운영자) 중 하나만 채워짐, 둘 다 NULL이면 배치가 자동 변경';
COMMENT ON TABLE issue_status_transition IS 'module:issues | 허용된 상태 전이 표';
COMMENT ON TABLE notification_log        IS 'module:feed | 알림 발송 이력 + 읽음 표시(NOTI-01~06, M-10). 60일 보관 후 자동 삭제(O-33). question 을 참조해서 issues 가 아니라 feed 소속';
COMMENT ON TABLE banned_word              IS 'module:feed | 금칙어 목록(SAFE-03). 게시물·답변·댓글 등록을 막는 기준';
COMMENT ON TABLE question                IS 'module:feed | 질문카드 풀. MVP는 팀이 작성한 고정 풀(QST-02)';
COMMENT ON TABLE issue_question          IS 'module:feed | 호에 공개된 질문(호당 2개, display_order). 공개 시각은 NOTI-01 이 참조';
COMMENT ON TABLE post                    IS 'module:feed | 피드 게시물(글) 또는 질문 답변(question_id). 호와 독립이고 posted_at 으로 어느 호에 실릴지 정해진다';
COMMENT ON TABLE comment                 IS 'module:feed | 질문 답변 댓글(QST-06), 1뎁스';
COMMENT ON TABLE report                  IS 'module:feed | 콘텐츠 신고(SAFE-01). 운영자가 확인·조치(ADM-05)';
COMMENT ON TABLE media                   IS 'module:feed | 게시물의 사진. 이미지 분석 결과와 사용자의 의도(꼭 넣기/빼기). initiated_at(업로드 시작)은 마감 유예(POST-07)에 쓴다';
COMMENT ON TABLE media_rendition         IS 'module:feed | 사진의 파생본(썸네일/미리보기/인쇄용)';
COMMENT ON TABLE issue_media             IS 'module:feed | 호별 사진 선별 결과(후보/선택/제외와 점수). 마감할 때 만들어진다';
COMMENT ON TABLE text_block              IS 'module:feed | 호에 들어가는 글 조각(제목/캡션/인용/본문)';
COMMENT ON TABLE layout_run              IS 'module:layout | 자동 조판 실행 1회(seed, 알고리즘 버전, 워커 임대 정보)';
COMMENT ON TABLE page                    IS 'module:layout | 조판 결과의 페이지';
COMMENT ON TABLE placement               IS 'module:layout | 페이지 위 요소 배치(mm 단위)';
COMMENT ON TABLE preview                 IS 'module:layout | 페이지 미리보기 렌더 결과';
COMMENT ON TABLE override                IS 'module:review | 사람의 수정 로그(seq 순서). 가족(author_id) 또는 운영자(operator_id)가 조판 검수 때 만든다';
COMMENT ON TABLE page_lock               IS 'module:review | 페이지 편집 락';
COMMENT ON TABLE print_job               IS 'module:printing | PDF 생성/프리플라이트 작업';
COMMENT ON TABLE newsletter_view_log     IS 'module:printing | 신문 PDF 열람 기록(M-12, PUB-02)';
COMMENT ON TABLE print_order             IS 'module:printing | 인쇄 주문 1건 = 배송지 1곳. 받는 사람/주소는 주문 시점의 복사본';
