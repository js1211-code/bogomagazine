# TODO

## 1순위: ERD 초안 — 마감 12시 (오늘 자정으로 가정함, 시각 확인 필요)

- [x] 스키마에서 자동 생성되는 ERD 초안 → [docs/erd.md](docs/erd.md) (모듈 의존도, 전체 관계, 모듈별 상세, 테이블 목록)
  - 검증: Mermaid 엔진으로 10개 다이어그램 모두 렌더링 확인(10/10), 스키마와 어긋나면 CI 실패(`db.sh erd --check`)
  - 한계: 전체 관계도는 테이블 27개라 가로로 넓다. 읽기 좋은 것은 모듈별 상세
- [ ] 초안 검토: 모듈 경계, 테이블/컬럼 이름, 관계선 확인. 특히 `issues`가 조정자 역할을 하는 결합 ([architecture.md](docs/architecture.md)의 "알려진 예외")
- [ ] 아래 보류 항목이 확정되면 ERD가 바뀐다 (확정 → 새 `V###` 마이그레이션 → `./scripts/db.sh erd`):

| 보류 항목 | ERD 변경 예정 |
|---|---|
| 마감 시각 강제 + 유예 | `media.initiated_at`, `media.upload_status`, `family_group.upload_grace` (글/사진이 마감 후에 완료되는 경우) |
| DB 권한 분리 | 테이블 변경 없음 (권한/함수) |
| 다중 승인 정책 | **폐기**. 기능명세서_최종_1002(V-17)로 승인 절차 자체가 없어짐 — review 단계는 운영자만 조판 검수(ADM-03), 가족 승인 없음 |
| 마감 임박 알림 | 발송 **이력**은 `notification_log`(module:issues)로 반영함. 발송 대기열/워커(누구에게 언제 보낼지 계산하는 로직)는 아직 없음 — 앱/배치가 만들어야 함 |
| 탈퇴 시 콘텐츠 처리 | 정책에 따라 `post`/`media`의 삭제 표시 컬럼 가능성 |
| 배송지 개인정보 보호 | `recipient_phone`/`address_line1`/`address_line2`를 Admin 추가 작업에서 pgcrypto로 암호화함(`delivery_address`/`print_order` 둘 다). `postal_code`/`recipient_name`은 평문 유지 |

## 기능명세서_최종_1002 반영 현황

팀의 최종 기능명세서(기능명세/평가 지표/호 운영 흐름 시트) 기준으로 스키마를 크게 다시 맞췄다. 핵심 변화:
**가족의 발행 전 미리보기·재조판 요청은 없다(V-17)** — `review_window_hours`/`can_request_relayout`/`advance_reviewed_issues()`를 전부
제거하고, review(조판 검수) → printing → printed 전환은 운영자가 `change_issue_status(..., p_operator)`로 수동으로만 한다(ADM-02/03).
`override`(수정 로그)도 가족(`author_id`) 또는 운영자(`operator_id`) 중 하나만 채워진다.

새로 반영한 것: `delivery_address`의 수신자 정보(성별·1인/부부·사진, RCV-01), `family_member.relationship`(호칭용, PRF-02),
`post.visibility`(공개 범위, POST-02), `question`/`issue_question`/`post.question_id`(질문카드, QST-01~07),
`comment`(답변 댓글, QST-06), `family_block`/`user_block`/`report`(차단·신고, FAM-09/10·SAFE-01/02),
`waitlist_signup`(대기 신청, WAIT-01), `notification_log`/`newsletter_view_log`(알림·열람 기록, NOTI/M-10/M-12),
`delivery_address_access_log`(ADM-01, 한 번 뺐다가 최종 스펙에 다시 있어서 복원함).

**그 다음에 추가로 반영한 것** (위 "아직 반영 안 한 것"으로 적었던 항목들, 전부 처리함):
- **ACC-03 가입 동의**: `app_user.privacy_consented_at`/`terms_consented_at`/`age_over_14_confirmed_at`(필수, 기본값 now())/`research_consented_at`(선택, NULL 허용)
- **PRF-01 프로필**: `app_user.photo_key`/`birth_month`/`birth_day` 추가. 탈퇴 익명화 때 `photo_key`도 지움
- **ACC-05 탈퇴 시 콘텐츠 처리**: `anonymize_user()`가 모집 중(status='collecting')인 호의 글만 지우고, 마감 이후 호의 글은 유지하도록 분기 (identity.sql T80)
- **SAFE-03 금칙어 필터**: `banned_word` 테이블 + `post`/`comment` 등록 시 본문에 포함되어 있으면 거부(`assert_no_banned_word()`, feed.sql T125)
- **NOTI 발송 로직**: `enqueue_question_published_notifications()`/`enqueue_deadline_reminders()`/`enqueue_published_notifications()` 추가.
  마지막 건 `change_issue_status()`가 'printed' 진입 시 자동 호출(issues.sql T125). 중복 발송은 `notification_log`의 부분 유니크 인덱스로 방지
- **ADM-08 운영 알림**: `operator_alert_log` 추가. 신고 등록 시 트리거로 즉시, 조판 실패는 3번째 실패에서만 쌓음(admin.sql T205)

**여전히 DB에서 강제 안 하는 것** (의도적으로 보류, 위에서 이미 결정함):
- `operator.role`별 접근 제한은 DB가 강제하지 않는다. `dev` 계정이 Postgres superuser라 RLS가 안 먹혀서 — Admin API(앱 레이어)가 생기면 거기서 한다

## 보류 중 (설계안까지 있고 구현만 남음)

### 1. 마감 시각 강제 + 업로드 유예
- 지금: DB는 `close_at` 시각 자체를 강제하지 않는다. 배치가 호를 닫기 전까지 업로드를 받는다 (앱이 먼저 확인해야 함).
- 안: `media`에 `initiated_at`(업로드 시작)과 `upload_status`(pending/complete)를 추가한다. 시작은 `close_at`까지, 완료는 `close_at + 유예`까지 허용한다.
  대용량 업로드가 마감 직전에 시작해 직후에 끝나도 버려지지 않게 하려는 것이다. 마감 배치도 `close_at + 유예` 이후에 처리한다.
- 같이: `family_group.upload_grace`(기본 10분), 현재 시각을 `app_now()`로 감싸 테스트에서 고정 가능하게.
- 정할 것: 유예 시간, 업로드를 "시작/완료"로 나눌지.

### 2. DB 권한 분리
- 지금: `issue.status` 직접 변경 차단은 세션 플래그라 우회 가능한 가드레일이다.
- 안: 앱 접속 역할에서 `issue.status` 컬럼 `UPDATE` 권한을 회수하고 `change_issue_status()`를 `SECURITY DEFINER`(+`search_path` 고정)로 만든다.
  역할: 앱(읽기/쓰기), 마감 배치, 조판 워커, 조회 API(뷰만 읽기). 필요하면 조회 역할에 행 수준 보안(RLS)으로 가족 그룹 간 격리.
- 정할 것: 배포 환경과 역할 구성. (환경이 정해진 뒤에 한다)

### 4. 마감 임박 알림
- 안: `notification` 발송 대기열 테이블(`UNIQUE (user_id, issue_id, kind)`로 중복 방지). 마감 배치가 `enqueue_deadline_reminders()`로 "3일 전/1일 전" 알림을 넣고, 발송 워커가 `SKIP LOCKED`로 처리한다.
  푸시 토큰(`device`)과 수신 설정도 필요하다. 대상은 이번 달 기간에 아직 글을 올리지 않은 활동 중인 구성원(`v_issue_progress`의 제출 기준과 같은 조건).
- 정할 것: 채널(푸시/이메일 등), 시점.

## 결정 대기 (정책)

- **삭제 정책**: 지금은 인쇄 작업이 있는 호(`print_job` → `issue`), 호가 있는 가족 그룹, 조판에 배치된 사진을 가진 글(앱은 `deleted_at`으로 숨김), 데이터가 있는 사용자는 **삭제할 수 없다.** 의도한 보호지만
  "인쇄된 호의 삭제 요청", "그룹 해체", "보관 기간 후 삭제"를 어떻게 할지는 정하지 않았다. 탈퇴 시 콘텐츠 처리와 함께 결정한다.
- **탈퇴 시 콘텐츠 처리**: 지금 `anonymize_user()`는 신원/인증 정보를 지우고 구성원에서 나간 것으로 표시할 뿐, 올린 글·사진·본문은 남긴다.
  삭제할지, 이미 인쇄된 호는 어떻게 할지 정해야 한다. 법적 검토가 필요하다 (가족 사진에는 미성년자와 타인의 얼굴이 있다).

## 구현 예정

- [ ] **Admin v1 스키마 반영 후속 작업**: `operator` 테이블과 `issue_status_history.operator_id`는 추가됐지만, `change_issue_status()`가 아직 운영자(operator) 액터를 받지 못한다 (지금은 `changed_by`=app_user만 호출 가능). Admin API 만들 때 운영자용 오버로드나 파라미터 추가 필요.
  질문 풀 관리·호 진행 현황 한눈에 보기·배송지 열람 기록 등 v2 전용 기능은 이번에 반영 안 함 (팀 논의 기준 v1 범위 아님. 배송지 열람 기록은 처음에 테이블까지 만들었다가 불필요 판단으로 되돌림).
- [ ] **운영자 역할(`operator.role`)별 접근 제한은 아직 DB에서 강제 안 됨**: `staff_write`/`staff_read`/`printshop_read`는 지금 데이터일 뿐이다.
  **RLS로 시도하지 말 것** — 앱/마이그레이션/테스트가 전부 `dev` 계정(Postgres superuser, `rolsuper=t`)으로 접속하는데, superuser는 `FORCE ROW LEVEL SECURITY`를 걸어도 무조건 통과한다 (실제로 막혔다 다시 확인함). RLS가 먹히려면 superuser가 아닌 별도 앱 전용 DB 계정이 먼저 있어야 하는데, 그건 "DB 권한 분리"(위 보류 항목)와 똑같은 선결 작업이다.
  → 실제 강제는 Admin API(Spring Security 등 앱 레이어)가 생기면 거기서 한다. DB 쪽은 `db/tests/admin.sql`(T200~T202)에서 role CHECK 제약과 `issue_status_history`의 changed_by/operator_id 상호배타만 확인.
- [ ] **글 본문 -> 호의 텍스트 조각(`text_block`) 변환**: 피드 글(`post.body`)을 호의 캡션/본문으로 옮기는 단계가 아직 없다 (마감 때 만들지, 조판 입력을 만들 때 만들지 결정 필요. 지금 `text_block`은 테이블과 가드만 있다)
- [ ] 앱 언어/프레임워크 확정 확인 (`Dockerfile` 기준 Java 21 + Gradle) → `src/` 구조와 모듈 경계 검사(ArchUnit) 도입 ([architecture.md](docs/architecture.md))
- [ ] 조판 알고리즘 v0.1 + 조판 워커 ([algorithm-io.md](docs/algorithm-io.md)의 계약대로)
- [ ] 운영 DB 마이그레이션 절차 (백업, 승인, 적용 시점)
- [ ] 원격 저장소 생성, `main` 브랜치 보호, `CODEOWNERS` ([workflow.md](docs/workflow.md) 끝부분)
- [ ] 이미지 분석/PDF 렌더 워커
- [ ] `verify-guards.sh`(변이 검사, 59항목)를 CI에 정기(주 1회/수동) 실행으로 추가 — 항목마다 DB를 새로 만들어 몇 분 걸림, 테스트가 통과만 하는 가짜가 되는 것을 막는다 ([verification.md](docs/verification.md))
- [ ] CI에 `shellcheck` + `actionlint` 추가 (지금 저장소에서 둘 다 통과 확인됨. 비용 작고 사고를 일찍 잡는다)
- [ ] 첫 운영 데이터가 생기면 CI에 `squawk`(PostgreSQL 마이그레이션 안전성 린터)를 **새로 추가된 V 파일에만** 적용. baseline에는 소음 118건, 규칙 조정 필요
- [ ] 앱 코드가 생기면 모듈 경계 검사(ArchUnit 등가물)를 CI 필수 검사로 추가 ([architecture.md](docs/architecture.md))
- [ ] **plpgsql 정적 검사(`plpgsql_check` 등) 도입 검토**: 함수 본문은 PostgreSQL이 검사·추적하지 않아, 컬럼 이름을 바꿔도 마이그레이션은 성공하고 테스트에서만 걸린다(재현 확인). 기본 postgres 이미지에는 없어 별도 이미지가 필요하다 (미검증)
- [ ] 함수 수준 모듈 의존 분석(`scripts/analysis/fn-deps.py`)을 CI 검사로: 새 역방향 의존이 생기면 실패하게 (지금은 사람이 실행)
- [ ] 함수 분기 커버리지 측정 (지금은 "호출됐는가"만 확인: 38개 중 37개 호출 횟수로 확인, 나머지 1개는 변이 검사로 확인)
- [ ] CD 설계 — **앱 언어와 호스팅이 정해진 뒤.** 착수 전에 이미 정해진 원칙: forward-only 마이그레이션, 앱 배포와 별개 단계로 마이그레이션 실행(+백업, 운영은 수동 승인),
      운영에도 `FLYWAY_POSTGRESQL_TRANSACTIONAL_LOCK=false` 적용([ADR-0002](docs/adr/0002-db-migrations.md)), 배포 중 구버전/신버전 앱이 같은 DB를 함께 쓸 수 있게 변경(컬럼 추가 → 앱 전환 → 옛 컬럼 제거)

## 정합성 점검에서 남은 것 (일부러 미룬 것)

- [x] ~~수정(override) 작성자가 그 그룹의 활동 중인 구성원인지 검사~~ — 적용함(가족이면 T105, 운영자면 통과). 승인 절차 자체가 없어져서(V-17) 더 정할 게 없음.
- [x] ~~방장이 그 그룹의 구성원인지 검사~~ — 적용함(지연 검사 복합 외래키, T20)
- [ ] **인쇄 주문 권한**: 지금은 활동 중인 구성원 누구나 주문할 수 있다. 비용이 드는 행동이라 방장만으로 좁힐지 정한다 (결제 설계와 함께).
- [ ] **초대 취소/방장 전용 쓰기를 DB가 강제하지 못하는 부분**: 초대 취소(`revoked_at` 갱신)와 `p_actor`를 믿는 함수들은 앱이 정직하다는 전제다. DB 롤 분리(위 "DB 권한 분리") 때 직접 UPDATE/DELETE 권한을 회수해야 완성된다.
- [ ] **초대 링크 운영 규칙**: 만료 기간과 최대 사용 횟수의 기본값, 방장이 내보낸 사람이 옛 링크로 돌아오는 문제(내보낼 때 링크를 자동 취소할지), 카카오톡 링크 공유 형식(토큰 원문은 링크에만 있고 DB에는 sha256만 있다)
- [ ] 배치 `slot_id`가 템플릿 마스터에 있는지는 DB가 못 보므로 조판 알고리즘 출력 검증으로 (알고리즘 구현 시)

## 결정 기록 (일부러 하지 않기로 한 것)

| 항목 | 이유 |
|---|---|
| `sqlfluff` 도입 | 위반 248건이 거의 전부 들여쓰기/줄 길이/대소문자 스타일이고, 함수 본문(`$$ ... $$`)은 아예 검사하지 않는다 (본문에 쓰레기 코드를 넣어도 통과함을 확인). 소음은 큰데 우리 로직은 못 본다 |
| 앱/CD 파이프라인을 지금 만들기 | 앱 코드, 언어, 호스팅이 없다. 대신 CD에 영향을 주는 원칙만 위 "구현 예정"에 먼저 기록했다 |
| 내용 없는 자리표시용 CI 작업 | "검사하고 있다"는 거짓 안심을 준다. 앱 코드가 생기면 실제 검사를 붙인다 |
| 정규화를 더 진행해 중복 컬럼 제거 | `override.issue_id` 같은 중복 컬럼은 조회·잠금·연쇄 삭제 경로에 쓰인다. 지우는 대신 **복합 외래키로 어긋나지 못하게** 했다 |
| 조판의 `template_id` ↔ 호의 `template_id` 일치 강제 | 조판이 "그 시점에 쓴 템플릿"을 기록하는 것이라 달라도 된다고 판단 (T112) |
| 수정로그 `target_id` 외래키(다형 참조) | 조판이 재생성되면 대상이 사라지는 것이 정상이다. 로그는 추가만 한다 (T113) |
| 서비스(마이크로서비스) 분리 | [ADR-0001](docs/adr/0001-modular-monolith.md) 참고 |

## 알려진 한계

- 비밀 스캔(gitleaks)은 패턴 기반이라 완벽한 보증이 아니다. 로컬 pre-commit은 Docker가 꺼져 있으면 경고만 하고 통과하며(CI가 다시 검사), `--no-verify`로 우회할 수 있다.
- **Flyway `CREATE INDEX CONCURRENTLY` 함정**: `FLYWAY_POSTGRESQL_TRANSACTIONAL_LOCK=false`가 없으면 배포가 무한 정지한다. `docker-compose.dbtest.yml`에는 적용했지만 **운영 배포 설정에는 따로 넣어야 한다** ([ADR-0002](docs/adr/0002-db-migrations.md)).

- GitHub Actions 워크플로(`.github/workflows/ci.yml`)는 아직 한 번도 원격에서 실행해 보지 못했다. 같은 명령(`scripts/db.sh test`, `scripts/check-migrations.sh`)은 로컬에서 검증했다.
- 모듈 간 **함수/뷰 수준 결합**은 자동 검사가 없다 ([architecture.md](docs/architecture.md)의 "알려진 예외").
- 사용자/템플릿/스타일/폰트를 참조하는 외래키 13개에는 인덱스가 없다. 사용자를 실제로 삭제하지 않고 익명화하므로 일부러 뺐다.
- 같은 트랜잭션에서 만든 행의 `created_at`은 같다. "최신" 판정은 `seq`로 하므로 영향이 없지만, 시각 정렬에 의존하는 새 코드를 쓰면 안 된다.
