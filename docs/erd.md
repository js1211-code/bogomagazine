# ERD (자동 생성)

> **이 파일은 DB 스키마에서 자동 생성됩니다. 직접 수정하지 마세요.**
> 갱신: `./scripts/db.sh erd` · CI(`./scripts/db.sh test`)가 스키마와 일치하는지 검사하고, 어긋나면 실패합니다.
> 모듈 경계와 규칙은 [architecture.md](architecture.md) 참고. 소유 모듈은 각 테이블의 코멘트(`module:<모듈>`)가 기준입니다.

범례: `PK` 기본키 · `FK` 외래키 · `UK` 유일 · 관계선 `||--o{` 은 "부모 1 : 자식 0..N", `|o` 는 부모가 선택(NULL 가능), `o|` 는 자식이 최대 1(1:1). 라벨은 외래키 컬럼이며 괄호는 부모 삭제 시 동작입니다.

## 0. 모듈 구성과 의존 방향

화살표는 "참조한다(의존한다)"는 뜻이고 숫자는 모듈 간 외래키 개수입니다.

```mermaid
flowchart LR
    identity["identity<br/>5 tables"]
    templates["templates<br/>4 tables"]
    groups["groups<br/>6 tables"]
    issues["issues<br/>3 tables"]
    feed["feed<br/>11 tables"]
    layout["layout<br/>4 tables"]
    review["review<br/>2 tables"]
    printing["printing<br/>3 tables"]
    admin["admin<br/>2 tables"]
    groups -->|"3 FK"| identity
    groups -->|"1 FK"| admin
    issues -->|"1 FK"| identity
    issues -->|"1 FK"| templates
    issues -->|"1 FK"| groups
    issues -->|"1 FK"| admin
    feed -->|"3 FK"| identity
    feed -->|"3 FK"| groups
    feed -->|"5 FK"| issues
    feed -->|"1 FK"| admin
    layout -->|"3 FK"| templates
    layout -->|"1 FK"| issues
    layout -->|"2 FK"| feed
    review -->|"2 FK"| identity
    review -->|"1 FK"| issues
    review -->|"2 FK"| layout
    review -->|"1 FK"| admin
    printing -->|"2 FK"| identity
    printing -->|"1 FK"| groups
    printing -->|"1 FK"| issues
    printing -->|"1 FK"| layout
```

## 1. 전체 관계 (컬럼 생략)

```mermaid
erDiagram
    "app_user" ||--o{ "auth_identity" : "user_id (cascade)"
    "post" ||--o{ "comment" : "post_id (cascade)"
    "family_group" ||--o{ "delivery_address" : "group_id (cascade)"
    "family_member" ||--o{ "delivery_address" : "group_id, created_by"
    "delivery_address" ||--o{ "delivery_address_access_log" : "delivery_address_id (cascade)"
    "operator" ||--o{ "delivery_address_access_log" : "operator_id"
    "app_user" ||--o{ "device" : "user_id (cascade)"
    "family_group" ||--o{ "family_block" : "group_id (cascade)"
    "family_member" ||--o{ "family_block" : "group_id, created_by"
    "app_user" ||--o{ "family_block" : "user_id"
    "family_member" ||--o{ "family_group" : "id, owner_id"
    "app_user" ||--o{ "family_group" : "owner_id"
    "family_group" ||--o{ "family_invite" : "group_id (cascade)"
    "family_member" ||--o{ "family_invite" : "group_id, created_by"
    "family_group" ||--o{ "family_member" : "group_id (cascade)"
    "app_user" ||--o{ "family_member" : "user_id"
    "font" |o--o{ "font" : "fallback"
    "family_group" ||--o{ "issue" : "group_id"
    "template" ||--o{ "issue" : "template_id"
    "issue" ||--o{ "issue_media" : "issue_id, group_id (cascade)"
    "media" ||--o{ "issue_media" : "media_id, group_id (cascade)"
    "issue" ||--o{ "issue_question" : "issue_id (cascade)"
    "question" ||--o{ "issue_question" : "question_id"
    "app_user" |o--o{ "issue_status_history" : "changed_by"
    "issue" ||--o{ "issue_status_history" : "issue_id (cascade)"
    "operator" |o--o{ "issue_status_history" : "operator_id"
    "issue" ||--o{ "layout_run" : "issue_id (cascade)"
    "template" ||--o{ "layout_run" : "template_id"
    "post" ||--o{ "media" : "post_id, group_id (cascade)"
    "media" ||--o{ "media_rendition" : "media_id (cascade)"
    "print_job" ||--o{ "newsletter_view_log" : "print_job_id"
    "app_user" ||--o{ "newsletter_view_log" : "user_id"
    "family_group" |o--o{ "notification_log" : "group_id"
    "issue" |o--o{ "notification_log" : "issue_id"
    "issue" |o--o{ "notification_log" : "issue_id, group_id"
    "question" |o--o{ "notification_log" : "question_id"
    "app_user" ||--o{ "notification_log" : "user_id"
    "app_user" |o--o{ "override" : "author_id"
    "issue" ||--o{ "override" : "issue_id (cascade)"
    "operator" |o--o{ "override" : "operator_id"
    "layout_run" ||--o{ "override" : "run_id, issue_id (cascade)"
    "page_master" |o--o{ "page" : "master_id"
    "layout_run" ||--o{ "page" : "run_id (cascade)"
    "page" ||--o| "page_lock" : "page_id (cascade)"
    "app_user" ||--o{ "page_lock" : "user_id"
    "template" ||--o{ "page_master" : "template_id (cascade)"
    "media" |o--o{ "placement" : "media_id"
    "page" ||--o{ "placement" : "page_id (cascade)"
    "style" |o--o{ "placement" : "style_id"
    "text_block" |o--o{ "placement" : "text_block_id"
    "family_group" ||--o{ "post" : "group_id (cascade)"
    "family_member" ||--o{ "post" : "group_id, author_id"
    "question" |o--o{ "post" : "question_id"
    "page" ||--o{ "preview" : "run_id, page_no (cascade)"
    "issue" ||--o{ "print_job" : "issue_id"
    "layout_run" ||--o{ "print_job" : "run_id, issue_id"
    "delivery_address" |o--o{ "print_order" : "delivery_address_id (set null)"
    "app_user" ||--o{ "print_order" : "ordered_by"
    "print_job" ||--o{ "print_order" : "print_job_id"
    "app_user" ||--o{ "report" : "reporter_id"
    "operator" |o--o{ "report" : "resolved_by"
    "style" |o--o{ "style" : "based_on"
    "template" ||--o{ "style" : "template_id (cascade)"
    "app_user" |o--o{ "text_block" : "created_by"
    "issue" ||--o{ "text_block" : "issue_id, group_id (cascade)"
    "post" |o--o{ "text_block" : "post_id, group_id (set null)"
    "app_user" ||--o{ "user_block" : "blocked_id (cascade)"
    "app_user" ||--o{ "user_block" : "blocker_id (cascade)"
    "app_user" ||--o{ "waitlist_signup" : "user_id"
    "banned_word"
    "issue_status_transition"
    "operator_alert_log"
```

## 2. 모듈별 상세

해당 모듈의 테이블은 컬럼까지 보여 주고, 다른 모듈의 테이블은 연결에 필요한 컬럼만 보여 줍니다.

### identity

- 참조하는 모듈: 없음 (바닥 모듈)
- 이 모듈을 참조하는 모듈: groups, issues, feed, review, printing

```mermaid
erDiagram
    "app_user" ||--o{ "auth_identity" : "user_id (cascade)"
    "app_user" ||--o{ "device" : "user_id (cascade)"
    "app_user" ||--o{ "family_block" : "user_id"
    "app_user" ||--o{ "family_group" : "owner_id"
    "app_user" ||--o{ "family_member" : "user_id"
    "app_user" |o--o{ "issue_status_history" : "changed_by"
    "app_user" ||--o{ "newsletter_view_log" : "user_id"
    "app_user" ||--o{ "notification_log" : "user_id"
    "app_user" |o--o{ "override" : "author_id"
    "app_user" ||--o{ "page_lock" : "user_id"
    "app_user" ||--o{ "print_order" : "ordered_by"
    "app_user" ||--o{ "report" : "reporter_id"
    "app_user" |o--o{ "text_block" : "created_by"
    "app_user" ||--o{ "user_block" : "blocked_id (cascade)"
    "app_user" ||--o{ "user_block" : "blocker_id (cascade)"
    "app_user" ||--o{ "waitlist_signup" : "user_id"
    "app_user" {
        uuid id PK
        text email
        text name
        text photo_key
        int birth_month
        int birth_day
        timestamptz privacy_consented_at
        timestamptz terms_consented_at
        timestamptz age_over_14_confirmed_at
        timestamptz research_consented_at
        timestamptz created_at
        timestamptz deleted_at
    }
    "auth_identity" {
        uuid id PK
        uuid user_id FK
        text provider
        text provider_uid
        text email
        bool email_verified
        bool is_private_relay
        text refresh_token_ref
        timestamptz last_login_at
        timestamptz created_at
    }
    "device" {
        uuid id PK
        uuid user_id FK
        text platform
        text push_token
        timestamptz last_seen_at
        timestamptz created_at
        timestamptz revoked_at
    }
    "user_block" {
        uuid blocker_id PK, FK
        uuid blocked_id PK, FK
        timestamptz created_at
    }
    "waitlist_signup" {
        uuid id PK
        uuid user_id FK
        text code
        timestamptz created_at
    }
    "family_block" {
        uuid group_id PK, FK
        uuid user_id PK, FK
    }
    "family_group" {
        uuid id PK, FK
        uuid owner_id FK
    }
    "family_member" {
        uuid group_id PK, FK
        uuid user_id PK, FK
    }
    "issue_status_history" {
        bigint id PK
        uuid changed_by FK
    }
    "newsletter_view_log" {
        bigint id PK
        uuid user_id FK
    }
    "notification_log" {
        bigint id PK
        uuid user_id FK
    }
    "override" {
        uuid id PK
        uuid author_id FK
    }
    "page_lock" {
        uuid page_id PK, FK
        uuid user_id FK
    }
    "print_order" {
        uuid id PK
        uuid ordered_by FK
    }
    "report" {
        uuid id PK
        uuid reporter_id FK
    }
    "text_block" {
        uuid id PK
        uuid created_by FK
    }
```

### templates

- 참조하는 모듈: 없음 (바닥 모듈)
- 이 모듈을 참조하는 모듈: issues, layout

```mermaid
erDiagram
    "font" |o--o{ "font" : "fallback"
    "template" ||--o{ "issue" : "template_id"
    "template" ||--o{ "layout_run" : "template_id"
    "page_master" |o--o{ "page" : "master_id"
    "template" ||--o{ "page_master" : "template_id (cascade)"
    "style" |o--o{ "placement" : "style_id"
    "style" |o--o{ "style" : "based_on"
    "template" ||--o{ "style" : "template_id (cascade)"
    "font" {
        uuid id PK
        text family
        int weight
        bool italic
        text storage_key
        text sha256
        text license
        uuid fallback FK
    }
    "page_master" {
        uuid id PK
        uuid template_id FK
        text name
        jsonb grid
        jsonb slots
    }
    "style" {
        uuid id PK
        uuid template_id FK
        text kind
        text name
        uuid based_on FK
        jsonb props
    }
    "template" {
        uuid id PK
        text name
        int version
        jsonb spec
        int min_photos
        int max_photos
        int min_pages
        int max_pages
        int page_multiple
        int photos_per_page_min
        int photos_per_page_max
        timestamptz created_at
    }
    "issue" {
        uuid id PK
        uuid template_id FK
    }
    "layout_run" {
        uuid id PK
        uuid template_id FK
    }
    "page" {
        uuid id PK
        uuid master_id FK
    }
    "placement" {
        uuid id PK
        uuid style_id FK
    }
```

### groups

- 참조하는 모듈: identity, admin
- 이 모듈을 참조하는 모듈: issues, feed, printing

```mermaid
erDiagram
    "family_group" ||--o{ "delivery_address" : "group_id (cascade)"
    "family_member" ||--o{ "delivery_address" : "group_id, created_by"
    "delivery_address" ||--o{ "delivery_address_access_log" : "delivery_address_id (cascade)"
    "operator" ||--o{ "delivery_address_access_log" : "operator_id"
    "family_group" ||--o{ "family_block" : "group_id (cascade)"
    "family_member" ||--o{ "family_block" : "group_id, created_by"
    "app_user" ||--o{ "family_block" : "user_id"
    "family_member" ||--o{ "family_group" : "id, owner_id"
    "app_user" ||--o{ "family_group" : "owner_id"
    "family_group" ||--o{ "family_invite" : "group_id (cascade)"
    "family_member" ||--o{ "family_invite" : "group_id, created_by"
    "family_group" ||--o{ "family_member" : "group_id (cascade)"
    "app_user" ||--o{ "family_member" : "user_id"
    "family_group" ||--o{ "issue" : "group_id"
    "family_group" |o--o{ "notification_log" : "group_id"
    "family_group" ||--o{ "post" : "group_id (cascade)"
    "family_member" ||--o{ "post" : "group_id, author_id"
    "delivery_address" |o--o{ "print_order" : "delivery_address_id (set null)"
    "delivery_address" {
        uuid id PK
        uuid group_id FK
        text label
        text recipient_name
        bytea recipient_phone
        text recipient_type
        text recipient_gender
        text recipient_photo_key
        text postal_code
        bytea address_line1
        bytea address_line2
        text memo
        uuid created_by FK
        timestamptz created_at
        timestamptz updated_at
    }
    "delivery_address_access_log" {
        bigint id PK
        uuid delivery_address_id FK
        uuid operator_id FK
        text action
        timestamptz accessed_at
    }
    "family_block" {
        uuid group_id PK, FK
        uuid user_id PK, FK
        uuid created_by FK
        timestamptz created_at
    }
    "family_group" {
        uuid id PK, FK
        text name
        text newsletter_title
        uuid owner_id FK
        int close_day
        text timezone
        bool auto_skip_below_min
        timestamptz created_at
    }
    "family_invite" {
        uuid id PK
        uuid group_id FK, UK
        uuid created_by FK
        text token_hash UK
        timestamptz created_at
    }
    "family_member" {
        uuid group_id PK, FK
        uuid user_id PK, FK
        text nickname
        text relationship
        timestamptz joined_at
        timestamptz left_at
    }
    "app_user" {
        uuid id PK
    }
    "issue" {
        uuid id PK
        uuid group_id FK
    }
    "notification_log" {
        bigint id PK
        uuid group_id FK
    }
    "operator" {
        uuid id PK
    }
    "post" {
        uuid id PK
        uuid group_id FK
        uuid author_id FK
    }
    "print_order" {
        uuid id PK
        uuid delivery_address_id FK
    }
```

### issues

- 참조하는 모듈: identity, templates, groups, admin
- 이 모듈을 참조하는 모듈: feed, layout, review, printing

```mermaid
erDiagram
    "family_group" ||--o{ "issue" : "group_id"
    "template" ||--o{ "issue" : "template_id"
    "issue" ||--o{ "issue_media" : "issue_id, group_id (cascade)"
    "issue" ||--o{ "issue_question" : "issue_id (cascade)"
    "app_user" |o--o{ "issue_status_history" : "changed_by"
    "issue" ||--o{ "issue_status_history" : "issue_id (cascade)"
    "operator" |o--o{ "issue_status_history" : "operator_id"
    "issue" ||--o{ "layout_run" : "issue_id (cascade)"
    "issue" |o--o{ "notification_log" : "issue_id"
    "issue" |o--o{ "notification_log" : "issue_id, group_id"
    "issue" ||--o{ "override" : "issue_id (cascade)"
    "issue" ||--o{ "print_job" : "issue_id"
    "issue" ||--o{ "text_block" : "issue_id, group_id (cascade)"
    "issue" {
        uuid id PK
        uuid group_id FK
        text title
        date period_start
        date period_end
        text status
        timestamptz status_changed_at
        timestamptz close_at
        timestamptz closed_at
        int close_attempts
        text close_error
        uuid template_id FK
        int min_photos
        int max_photos
        int min_pages
        int max_pages
        int page_multiple
        timestamptz created_at
    }
    "issue_status_history" {
        bigint id PK
        uuid issue_id FK
        text from_status
        text to_status
        uuid changed_by FK
        uuid operator_id FK
        text note
        timestamptz changed_at
    }
    "issue_status_transition" {
        text from_status PK
        text to_status PK
        text note
    }
    "app_user" {
        uuid id PK
    }
    "family_group" {
        uuid id PK, FK
    }
    "issue_media" {
        uuid issue_id PK, FK
        uuid media_id PK, FK
        uuid group_id FK
    }
    "issue_question" {
        uuid issue_id PK, FK
        uuid question_id PK, FK
    }
    "layout_run" {
        uuid id PK
        uuid issue_id FK
    }
    "notification_log" {
        bigint id PK
        uuid group_id FK
        uuid issue_id FK
    }
    "operator" {
        uuid id PK
    }
    "override" {
        uuid id PK
        uuid issue_id FK
    }
    "print_job" {
        uuid id PK
        uuid issue_id FK
    }
    "template" {
        uuid id PK
    }
    "text_block" {
        uuid id PK
        uuid issue_id FK
        uuid group_id FK
    }
```

### feed

- 참조하는 모듈: identity, groups, issues, admin
- 이 모듈을 참조하는 모듈: layout

```mermaid
erDiagram
    "post" ||--o{ "comment" : "post_id (cascade)"
    "issue" ||--o{ "issue_media" : "issue_id, group_id (cascade)"
    "media" ||--o{ "issue_media" : "media_id, group_id (cascade)"
    "issue" ||--o{ "issue_question" : "issue_id (cascade)"
    "question" ||--o{ "issue_question" : "question_id"
    "post" ||--o{ "media" : "post_id, group_id (cascade)"
    "media" ||--o{ "media_rendition" : "media_id (cascade)"
    "family_group" |o--o{ "notification_log" : "group_id"
    "issue" |o--o{ "notification_log" : "issue_id"
    "issue" |o--o{ "notification_log" : "issue_id, group_id"
    "question" |o--o{ "notification_log" : "question_id"
    "app_user" ||--o{ "notification_log" : "user_id"
    "media" |o--o{ "placement" : "media_id"
    "text_block" |o--o{ "placement" : "text_block_id"
    "family_group" ||--o{ "post" : "group_id (cascade)"
    "family_member" ||--o{ "post" : "group_id, author_id"
    "question" |o--o{ "post" : "question_id"
    "app_user" ||--o{ "report" : "reporter_id"
    "operator" |o--o{ "report" : "resolved_by"
    "app_user" |o--o{ "text_block" : "created_by"
    "issue" ||--o{ "text_block" : "issue_id, group_id (cascade)"
    "post" |o--o{ "text_block" : "post_id, group_id (set null)"
    "banned_word" {
        text word PK
    }
    "comment" {
        uuid id PK
        uuid post_id FK
        uuid author_id
        text body
        timestamptz created_at
        timestamptz deleted_at
    }
    "issue_media" {
        uuid issue_id PK, FK
        uuid media_id PK, FK
        uuid group_id FK
        text selection_status
        real selection_score
        timestamptz created_at
    }
    "issue_question" {
        uuid issue_id PK, FK
        uuid question_id PK, FK
        int display_order
        timestamptz published_at
    }
    "media" {
        uuid id PK
        uuid post_id FK
        uuid group_id FK
        text storage_key
        text sha256
        int width
        int height
        jsonb exif
        timestamptz taken_at
        timestamptz initiated_at
        text color_profile
        jsonb focal_point
        jsonb saliency
        real quality_score
        bigint phash
        bool rights_ok
        bool pinned
        bool excluded
        timestamptz created_at
        timestamptz deleted_at
    }
    "media_rendition" {
        uuid media_id PK, FK
        text purpose PK
        text storage_key
        int width
        int height
    }
    "notification_log" {
        bigint id PK
        uuid user_id FK
        uuid group_id FK
        uuid issue_id FK
        uuid question_id FK
        text kind
        timestamptz read_at
        timestamptz sent_at
    }
    "post" {
        uuid id PK
        uuid group_id FK
        uuid author_id FK
        text body
        uuid question_id FK
        text question_option
        text visibility
        timestamptz posted_at
        timestamptz created_at
        timestamptz updated_at
        timestamptz deleted_at
    }
    "question" {
        uuid id PK
        text app_body
        text print_body
        text corner_name
        text kind
        jsonb options
        text target
        bool is_active
        timestamptz created_at
    }
    "report" {
        uuid id PK
        uuid reporter_id FK
        text target_type
        uuid target_id
        text reason
        text status
        uuid resolved_by FK
        timestamptz resolved_at
        timestamptz created_at
    }
    "text_block" {
        uuid id PK
        uuid issue_id FK
        uuid group_id FK
        uuid post_id FK
        text kind
        text body
        jsonb runs
        uuid created_by FK
        timestamptz created_at
    }
    "app_user" {
        uuid id PK
    }
    "family_group" {
        uuid id PK, FK
    }
    "family_member" {
        uuid group_id PK, FK
        uuid user_id PK, FK
    }
    "issue" {
        uuid id PK
    }
    "operator" {
        uuid id PK
    }
    "placement" {
        uuid id PK
        uuid media_id FK
        uuid text_block_id FK
    }
```

### layout

- 참조하는 모듈: templates, issues, feed
- 이 모듈을 참조하는 모듈: review, printing

```mermaid
erDiagram
    "issue" ||--o{ "layout_run" : "issue_id (cascade)"
    "template" ||--o{ "layout_run" : "template_id"
    "layout_run" ||--o{ "override" : "run_id, issue_id (cascade)"
    "page_master" |o--o{ "page" : "master_id"
    "layout_run" ||--o{ "page" : "run_id (cascade)"
    "page" ||--o| "page_lock" : "page_id (cascade)"
    "media" |o--o{ "placement" : "media_id"
    "page" ||--o{ "placement" : "page_id (cascade)"
    "style" |o--o{ "placement" : "style_id"
    "text_block" |o--o{ "placement" : "text_block_id"
    "page" ||--o{ "preview" : "run_id, page_no (cascade)"
    "layout_run" ||--o{ "print_job" : "run_id, issue_id"
    "layout_run" {
        uuid id PK
        bigint seq
        int run_no
        uuid issue_id FK
        uuid template_id FK
        text algorithm_version
        jsonb params
        bigint seed
        text input_snapshot_hash
        text status
        real score
        jsonb report
        text log
        timestamptz started_at
        timestamptz finished_at
        text locked_by
        timestamptz locked_at
        timestamptz heartbeat_at
        int attempts
        text input_ref
        timestamptz created_at
    }
    "page" {
        uuid id PK
        uuid run_id FK
        int page_no
        uuid master_id FK
    }
    "placement" {
        uuid id PK
        uuid page_id FK
        text slot_id
        text ref_type
        uuid media_id FK
        uuid text_block_id FK
        numeric x
        numeric y
        numeric w
        numeric h
        int z
        jsonb crop
        uuid style_id FK
    }
    "preview" {
        uuid id PK
        uuid run_id FK
        bigint override_seq
        int page_no FK
        text storage_key
        text status
    }
    "issue" {
        uuid id PK
    }
    "media" {
        uuid id PK
    }
    "override" {
        uuid id PK
        uuid issue_id FK
        uuid run_id FK
    }
    "page_lock" {
        uuid page_id PK, FK
    }
    "page_master" {
        uuid id PK
    }
    "print_job" {
        uuid id PK
        uuid issue_id FK
        uuid run_id FK
    }
    "style" {
        uuid id PK
    }
    "template" {
        uuid id PK
    }
    "text_block" {
        uuid id PK
    }
```

### review

- 참조하는 모듈: identity, issues, layout, admin
- 이 모듈을 참조하는 모듈: 없음

```mermaid
erDiagram
    "app_user" |o--o{ "override" : "author_id"
    "issue" ||--o{ "override" : "issue_id (cascade)"
    "operator" |o--o{ "override" : "operator_id"
    "layout_run" ||--o{ "override" : "run_id, issue_id (cascade)"
    "page" ||--o| "page_lock" : "page_id (cascade)"
    "app_user" ||--o{ "page_lock" : "user_id"
    "override" {
        uuid id PK
        uuid issue_id FK
        uuid run_id FK
        bigint seq
        text target_type
        uuid target_id
        jsonb op
        uuid author_id FK
        uuid operator_id FK
        timestamptz created_at
    }
    "page_lock" {
        uuid page_id PK, FK
        uuid user_id FK
        timestamptz expires_at
    }
    "app_user" {
        uuid id PK
    }
    "issue" {
        uuid id PK
    }
    "layout_run" {
        uuid id PK
    }
    "operator" {
        uuid id PK
    }
    "page" {
        uuid id PK
    }
```

### printing

- 참조하는 모듈: identity, groups, issues, layout
- 이 모듈을 참조하는 모듈: 없음

```mermaid
erDiagram
    "print_job" ||--o{ "newsletter_view_log" : "print_job_id"
    "app_user" ||--o{ "newsletter_view_log" : "user_id"
    "issue" ||--o{ "print_job" : "issue_id"
    "layout_run" ||--o{ "print_job" : "run_id, issue_id"
    "delivery_address" |o--o{ "print_order" : "delivery_address_id (set null)"
    "app_user" ||--o{ "print_order" : "ordered_by"
    "print_job" ||--o{ "print_order" : "print_job_id"
    "newsletter_view_log" {
        bigint id PK
        uuid print_job_id FK
        uuid user_id FK
        timestamptz viewed_at
    }
    "print_job" {
        uuid id PK
        bigint seq
        uuid issue_id FK
        uuid run_id FK
        bigint override_seq
        text pdf_key
        text pdf_profile
        text color_mode
        numeric bleed_mm
        bool crop_marks
        jsonb preflight_report
        text status
        timestamptz created_at
    }
    "print_order" {
        uuid id PK
        bigint seq
        uuid print_job_id FK
        uuid delivery_address_id FK
        uuid ordered_by FK
        text recipient_name
        bytea recipient_phone
        text postal_code
        bytea address_line1
        bytea address_line2
        text vendor
        int quantity
        numeric price
        text status
        text tracking
        timestamptz created_at
    }
    "app_user" {
        uuid id PK
    }
    "delivery_address" {
        uuid id PK
    }
    "issue" {
        uuid id PK
    }
    "layout_run" {
        uuid id PK
    }
```

### admin

- 참조하는 모듈: 없음 (바닥 모듈)
- 이 모듈을 참조하는 모듈: groups, issues, feed, review

```mermaid
erDiagram
    "operator" ||--o{ "delivery_address_access_log" : "operator_id"
    "operator" |o--o{ "issue_status_history" : "operator_id"
    "operator" |o--o{ "override" : "operator_id"
    "operator" |o--o{ "report" : "resolved_by"
    "operator" {
        uuid id PK
        text name
        text email
        timestamptz created_at
    }
    "operator_alert_log" {
        bigint id PK
        text kind
        text ref_type
        uuid ref_id
        timestamptz sent_at
    }
    "delivery_address_access_log" {
        bigint id PK
        uuid operator_id FK
    }
    "issue_status_history" {
        bigint id PK
        uuid operator_id FK
    }
    "override" {
        uuid id PK
        uuid operator_id FK
    }
    "report" {
        uuid id PK
        uuid resolved_by FK
    }
```

## 3. 테이블 목록

| 모듈 | 테이블 | 컬럼 수 | 설명 |
|---|---|---|---|
| identity | `app_user` | 12 | 사용자. 프로필(사진·생일)과 가입 동의 기록(ACC-03) 포함. 탈퇴하면 익명화하고 행은 유지한다 |
| identity | `auth_identity` | 10 | 로그인 수단(카카오/애플). (provider, provider_uid)로 식별 |
| identity | `device` | 7 | 푸시 알림용 디바이스 토큰(Expo). 발행완료/마감 임박 등에 쓴다 |
| identity | `user_block` | 3 | 개인 차단(SAFE-02). 차단한 사람의 콘텐츠를 숨긴다 |
| identity | `waitlist_signup` | 4 | 정식 출시 대기 신청(WAIT-01). 결제 의향 확인용(M-13) |
| templates | `font` | 8 | 폰트 메타데이터 |
| templates | `page_master` | 5 | 페이지 마스터(슬롯 배치 정의) |
| templates | `style` | 6 | 문단/글자 스타일(상속 구조) |
| templates | `template` | 12 | 불변 버전의 판형 템플릿과 규모 제약(사진/페이지 수) |
| groups | `delivery_address` | 15 | 조부모님 배송지 + 수신자(성별·사진·1인/부부) 정보. 주문에는 복사본을 남긴다 |
| groups | `delivery_address_access_log` | 5 | 배송지 열람/다운로드 기록. 운영자(operator)가 봤을 때만 남는다 (ADM-01) |
| groups | `family_block` | 4 | 방장이 내보낸 계정 차단 목록(FAM-09/10). 같은 링크로 재합류 불가 |
| groups | `family_group` | 8 | 가족 그룹. 방장(owner_id), 신문 제호(newsletter_title, FAM-03)와 마감 정책(마감일, 타임존, 미달 시 자동 미발행) |
| groups | `family_invite` | 5 | 카카오톡 초대 링크(토큰 해시). 영구 링크, 가족마다 1개, 방장만 만든다(FAM-05, 1004 결정) |
| groups | `family_member` | 6 | 그룹 구성원. 수신자와의 관계(호칭용)를 가족 단위로 저장. 나가도 행은 남기고 left_at 만 채운다 |
| issues | `issue` | 18 | 월간 호. 그 달의 게시물을 모아 만든 결과물. 상태는 change_issue_status()로만 바꾼다 |
| issues | `issue_status_history` | 8 | 호 상태 변경 이력. changed_by(가족) 또는 operator_id(운영자) 중 하나만 채워짐, 둘 다 NULL이면 배치가 자동 변경 |
| issues | `issue_status_transition` | 3 | 허용된 상태 전이 표 |
| feed | `banned_word` | 1 | 금칙어 목록(SAFE-03). 게시물·답변·댓글 등록을 막는 기준 |
| feed | `comment` | 6 | 질문 답변 댓글(QST-06), 1뎁스 |
| feed | `issue_media` | 6 | 호별 사진 선별 결과(후보/선택/제외와 점수). 마감할 때 만들어진다 |
| feed | `issue_question` | 4 | 호에 공개된 질문(호당 2개, display_order). 공개 시각은 NOTI-01 이 참조 |
| feed | `media` | 20 | 게시물의 사진. 이미지 분석 결과와 사용자의 의도(꼭 넣기/빼기). initiated_at(업로드 시작)은 마감 유예(POST-07)에 쓴다 |
| feed | `media_rendition` | 5 | 사진의 파생본(썸네일/미리보기/인쇄용) |
| feed | `notification_log` | 8 | 알림 발송 이력 + 읽음 표시(NOTI-01~06, M-10). 60일 보관 후 자동 삭제(O-33). question 을 참조해서 issues 가 아니라 feed 소속 |
| feed | `post` | 11 | 피드 게시물(글) 또는 질문 답변(question_id). 호와 독립이고 posted_at 으로 어느 호에 실릴지 정해진다 |
| feed | `question` | 9 | 질문카드 풀. MVP는 팀이 작성한 고정 풀(QST-02) |
| feed | `report` | 9 | 콘텐츠 신고(SAFE-01). 운영자가 확인·조치(ADM-05) |
| feed | `text_block` | 9 | 호에 들어가는 글 조각(제목/캡션/인용/본문) |
| layout | `layout_run` | 21 | 자동 조판 실행 1회(seed, 알고리즘 버전, 워커 임대 정보) |
| layout | `page` | 4 | 조판 결과의 페이지 |
| layout | `placement` | 13 | 페이지 위 요소 배치(mm 단위) |
| layout | `preview` | 6 | 페이지 미리보기 렌더 결과 |
| review | `override` | 10 | 사람의 수정 로그(seq 순서). 가족(author_id) 또는 운영자(operator_id)가 조판 검수 때 만든다 |
| review | `page_lock` | 3 | 페이지 편집 락 |
| printing | `newsletter_view_log` | 4 | 신문 PDF 열람 기록(M-12, PUB-02) |
| printing | `print_job` | 13 | PDF 생성/프리플라이트 작업 |
| printing | `print_order` | 16 | 인쇄 주문 1건 = 배송지 1곳. 받는 사람/주소는 주문 시점의 복사본 |
| admin | `operator` | 4 | 운영자 계정(Admin 페이지). 가족(app_user)과 분리된 로그인, 역할 구분 없이 동일 권한(ADM-01) |
| admin | `operator_alert_log` | 5 | 조판 실패(3회)·신고 접수 시 팀 메일 발송 대상(ADM-08) |
