# API 명세서 (초안)

> 기준 문서: 기능명세서 `기능명세_1005.pdf`(2026-10-05 결정, 이하 "1005 명세"), 유저 플로우(`User Flow.pdf`), 와이어프레임(`와이어프레임.pdf`).
> 개발 기준은 1005 명세로 정했다. 유저 플로우·와이어프레임이 1005 명세와 다른 곳은 1005 명세를 따르고, 해당 화면은 수정이 필요하다 ([부록 F](#부록-f-확인이-필요한-항목)). 1004에서 바뀐 큰 항목: 사진 대신 캐릭터(PRF-05), 가족방 이름과 신문 제호 분리(FAM-02·03), 가족 만들기 3단계와 실패 처리(FAM-01), 답변 현황 공개(QST-05), 대기 신청 노출 조건(WAIT-01), 생일 안내(NEWS-07).
> 항목에 붙은 `FAM-05` 같은 ID는 기능명세서의 기능 ID이고, `WF-`는 와이어프레임 화면 이름이다.
> 용어와 호 상태 대응은 [glossary.md](glossary.md)를 기준으로 한다.
> "현재 DB"는 upstream/main(`36a76f2`, 2026-10-06 확인)의 DB를 읽기 전용으로 기준 삼은 것이다. 아직 구현 전 기획 단계라 API를 설계하면서 DB 구조는 더 효율적인 쪽으로 바뀔 수 있다.
> 앱 코드가 아직 없어서 설계 문서다. DB 스키마가 이 문서와 다른 곳은 `DB 반영 필요`로 표시했다.
> 명세와 DB의 차이, 컬럼 검토는 [api-spec-review.md](api-spec-review.md)에 정리했다.

앱 구조 (HOME-04): 하단 탭 `소식 | 질문 | 가족`과 우상단 `설정`으로 구성한다. 소식·질문카드 탭의 공유 헤더에는 가족·호 선택(HOME-05), 상태 줄(HOME-02), 알림 목록(종 아이콘, NOTI-06)이 있고 가족 탭 헤더에는 알림 목록이 없다. 선택된 가족과 선택된 호는 앱 전체가 공유한다.

---

## 0. 공통

- Base URL
    - 개발: `http://localhost:8080` (운영 주소·도메인은 팀이 정해야 함)
    - 모든 API는 `/api/v1` 아래, 운영자(Admin) API는 `/api/v1/admin` 아래에 둔다.
- 인증
    - JWT Bearer 토큰 방식을 사용한다.
    - 로그인 성공 시 발급된 토큰을 `Authorization: Bearer {accessToken}` 헤더에 포함한다.
    - 가족(앱)은 카카오/애플 로그인만 쓴다 (ACC-01, ACC-02). 아이디·비밀번호 가입은 없다.
    - 운영자(Admin)는 팀 계정만 접근하고 토큰은 앱과 별도로 발급한다 (ADM-01). 앱 토큰으로 `/admin`을 호출하면 `403`이다.
    - 토큰 구성 (제안, [ADR-0003](adr/0003-auth-token.md)): 액세스 토큰은 JWT(만료 10~15분, `sub`는 내부 사용자 UUID, 가족·역할은 넣지 않음), 리프레시 토큰은 불투명 값을 기기별로 발급하고 사용할 때마다 교체한다. `401`을 받으면 앱이 `POST /auth/refresh`를 한 번 시도하고 실패하면 로그인 화면으로 이동한다.
- 공통 요청 헤더

| 헤더 | 필수 | 설명 |
| --- | --- | --- |
| `Authorization` | 로그인 필요 API | `Bearer {accessToken}` |
| `Idempotency-Key` | 생성 `POST`(글, 답변, 댓글, 가족 만들기, 신고) | 앱이 요청마다 만든 UUID. 같은 키로 재시도하면 처음 결과를 돌려주고 중복 생성하지 않는다. 모바일 네트워크 끊김 후 재시도에 대비한다. 보관 기간 24시간 |
| `X-App-Version` | 모든 요청 | 앱 버전. 서버가 최소 지원 버전보다 낮으면 `426`과 업데이트 안내를 돌려준다 |

- 멱등 키 저장은 DB 반영이 필요하다 (`idempotency_key` 테이블 또는 `post.client_request_id` 유니크 컬럼).
- 시간: 모든 일정은 한국 시간(KST) 기준이다 (NFR-21). 일시는 `2026-10-04T10:00:00+09:00`, 날짜는 `2026-10-04` 형식이다.
- 역할

| 역할 | 설명 | 판정 기준 |
| --- | --- | --- |
| `PUBLIC` | 로그인 불필요 | - |
| `USER` | 로그인한 앱 사용자 | 유효한 앱 토큰 |
| `MEMBER` | 해당 가족의 활동 중인 구성원 | `family_member.left_at IS NULL` |
| `OWNER` | 해당 가족의 방장 | `family_group.owner_id` |
| `작성자` | 해당 소식·답변·댓글을 쓴 구성원 | `author_id`가 토큰의 사용자. 방장도 남의 글은 수정·삭제할 수 없다 (POST-06) |
| `OPERATOR` | 운영자 | 운영자 토큰 |

- 조회 권한: 사진·게시물은 같은 가족 구성원만 조회한다 (NFR-08). 다른 가족의 리소스는 존재 여부를 알리지 않기 위해 `404`로 응답한다.
- 용어: 문서의 화면 용어와 URL·DB 이름의 대응(가족방 = `groups`, `family_group`, 받는 분 = `recipient` 등), 호 상태 대응표, 권한 표는 [glossary.md](glossary.md)가 기준이다.
- 공통 응답 형식

```json
{
  "success": true,
  "status": 200,
  "message": "요청이 성공적으로 처리되었습니다.",
  "data": { }
}
```

- 공통 에러 응답 형식

```json
{
  "success": false,
  "status": 400,
  "code": "VALIDATION_FAILED",
  "message": "에러 메시지",
  "errors": [
    {
      "field": "필드명",
      "message": "필드별 에러 메시지"
    }
  ]
}
```

- 에러 코드 (`code`, 앱이 분기하는 값. 초기 목록이고 구현하며 추가한다)

| `code` | status | 언제 |
| --- | --- | --- |
| `VALIDATION_FAILED` | 400 | 형식·유효성 오류 (`errors`에 필드별 사유) |
| `UNAUTHORIZED` | 401 | 토큰 없음·만료·위조 |
| `APP_UPDATE_REQUIRED` | 426 | 최소 지원 앱 버전 미만 |
| `RATE_LIMITED` | 429 | 호출 횟수 초과 |
| `NOT_MEMBER` | 403 | 해당 가족방의 활동 중인 구성원이 아님 |
| `NOT_OWNER` | 403 | 방장 전용 기능 |
| `NOT_AUTHOR` | 403 | 본인이 쓴 글이 아님 |
| `BLOCKED_FROM_GROUP` | 403 | 내보낸 구성원이라 합류할 수 없음 |
| `NOT_FOUND` | 404 | 대상 없음 또는 내 가족방의 것이 아님 |
| `INVALID_INVITE` | 404 | "링크를 확인할 수 없어요" |
| `BEFORE_FIRST_ISSUE` | 409 | "아직 글을 쓸 수 없어요" |
| `ISSUE_CLOSED` | 409 | "이번 신문은 마감됐어요" |
| `UPLOAD_NOT_READY` | 409 | 업로드가 완료되지 않았거나 만료됨 |
| `IDEMPOTENCY_CONFLICT` | 409 | 같은 `Idempotency-Key`로 다른 내용을 보냄 |
| `NOT_IN_REVIEW` | 409 | 운영자 작업이 `IN_REVIEW`일 때만 가능 |
| `NOT_SENT` | 409 | 발송 완료 전에는 신문을 열람할 수 없음 |
| `SHIP_BLOCKED` | 409 | 발송 완료 필수 점검 실패 (`blockers` 포함) |
| `CONFIRMATION_REQUIRED` | 422 | 발송 완료 `confirmed` 누락 |
| `BANNED_WORD` | 422 | 금칙어 포함 (SAFE-03) |

- 페이지네이션 응답 형식 (운영자 목록. `?page=0&size=20`, `size` 최대 100)

```json
{
  "success": true,
  "status": 200,
  "message": "요청이 성공적으로 처리되었습니다.",
  "data": {
    "content": [ ],
    "totalElements": 100,
    "totalPages": 10,
    "size": 10,
    "number": 0
  }
}
```

- 커서 페이지네이션 응답 형식 (피드, 댓글, 알림 목록. `?cursor={이전 응답의 nextCursor}&size=20`). 새 항목이 계속 추가되는 목록에서 `page` 방식은 페이지 경계에서 중복·누락이 생길 수 있어 커서 방식을 쓴다.

```json
{
  "success": true,
  "status": 200,
  "message": "요청이 성공적으로 처리되었습니다.",
  "data": {
    "content": [ ],
    "nextCursor": "eyJwIjoiMjAyNi4uLiJ9",
    "hasNext": true
  }
}
```

- 가족방 목록, 구성원, 호 목록, 내보낸 구성원, 내가 차단한 사람처럼 규모가 작은 목록은 페이지 없이 전체를 돌려준다.
- 공통 에러 상태 코드

| status | 언제 |
| --- | --- |
| 400 | 형식·유효성 오류 (`errors`에 필드별 사유) |
| 401 | 토큰 없음, 만료, 위조 |
| 403 | 권한 없음 (방장 전용, 운영자 전용, 활동 중인 구성원이 아님, 다른 사람의 글 수정, 차단된 계정) |
| 404 | 대상 없음 또는 내 가족의 것이 아님 |
| 409 | 현재 상태와 충돌 (마감됨, 허용되지 않는 상태 전이 등) |
| 422 | 형식은 맞지만 규칙 위반 (금칙어 포함 등) |
| 426 | 앱 버전이 최소 지원 버전보다 낮음 (업데이트 안내) |
| 429 | 호출 횟수 초과 (로그인, 토큰 갱신, 초대 코드 확인 등. 응답에 `Retry-After` 헤더) |

- 작성 가능 시간 (POST-07, HOME-06)
    - 첫 호가 시작하기 전(가입 후 1주차 월 07:00 전)에는 게시물·답변을 작성할 수 없다. `409`, `message`는 "아직 글을 쓸 수 없어요"이다. 가족 탭(초대)은 정상 사용한다.
    - 마감된 호에 게시물·답변·댓글을 올리거나 수정하거나 삭제하면 `409`, `message`는 "이번 신문은 마감됐어요"이다. 테스트는 1호뿐이라 다음 호로 넘어가지 않는다.
    - 마감 경계(서버 시각, KST): 사진이 없는 글(게시물·답변·댓글)은 마감 시각(`closeAt`, 예: 23:59:59) 이후 바로 등록할 수 없다. 마감 시각 전에 사진 업로드를 시작한 게시물·답변은 마감 후 14분(다음 날 00:14)까지 등록되면 이번 호에 포함한다. 화면 안내는 23:59 그대로이다. 이를 위해 서버가 업로드 시작 시각을 기록한다 ([4-1](#4-1-업로드-presigned-url)). 자동 조판은 00:15 이후에 시작한다 (NEWS-01).

---

## 1. Auth / User

### 1-1. 인증

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| POST | `/api/v1/auth/kakao` | 카카오 로그인 (신규면 가입, ACC-01) | PUBLIC |
| POST | `/api/v1/auth/apple` | 애플 로그인 (신규면 가입, ACC-02) | PUBLIC |
| POST | `/api/v1/auth/refresh` | 토큰 재발급 | PUBLIC (Refresh Token) |
| POST | `/api/v1/auth/logout` | 로그아웃 (ACC-04) | USER |
| DELETE | `/api/v1/me` | 탈퇴 (ACC-05) | USER |

#### 로그인 / 가입 (ACC-01~03, WF-1)

| **메서드** | **요청 URL** |
| --- | --- |
| POST | `/api/v1/auth/kakao` |
| POST | `/api/v1/auth/apple` |

제공자 토큰을 서버가 검증하고 `(provider, provider_uid)`로 사용자를 찾는다. 없으면 가입시킨다. 카카오는 최초 로그인 때 카카오 프로필(닉네임·프로필 사진)을 스냅샷으로 받아 저장하고, 이후 조회는 서버 DB에서 한다. 이름은 카카오 프로필이 기본값이고 가입자 정보 화면에서 수정할 수 있다. 애플은 이름·이메일을 주지 않아도 가입되며, 이름은 가입자 정보 화면에서 입력한다. 가입 중에는 사진을 받지 않는다 (PRF-01, [1-2](#1-2-내-프로필)).

Request Body

| 필드 | 타입 | 필수 | 유효성 | 설명 |
| --- | --- | --- | --- | --- |
| `accessToken` | String | 카카오는 Y | - | `/auth/kakao`만. 카카오 액세스 토큰 |
| `identityToken` | String | 애플은 Y | - | `/auth/apple`만. 애플 신원 토큰(JWT) |
| `authorizationCode` | String | 애플은 Y | - | `/auth/apple`만. 탈퇴 시 토큰 해지(revoke)를 위해 서버가 교환·보관한다 |
| `fullName` | String | N | 최대 50자 | `/auth/apple`만. 애플이 최초 로그인 때만 이름을 주므로 그때 함께 보낸다 |
| `consents` | Object | 신규 가입 시 Y | - | 가입 동의 (기존 사용자는 무시) |
| `consents.privacy` | Boolean | Y | `true`만 허용 | 개인정보 수집·이용 동의 |
| `consents.terms` | Boolean | Y | `true`만 허용 | 이용약관 동의 |
| `consents.ageOver14` | Boolean | Y | `true`만 허용 | 만 14세 이상 확인 (미만은 가입 불가) |
| `consents.research` | Boolean | N | - | 연구·발표 활용 동의(선택). 거부해도 핵심 기능을 사용할 수 있다 |

```json
{
  "accessToken": "kakao-access-token...",
  "consents": { "privacy": true, "terms": true, "ageOver14": true, "research": false }
}
```

Response `200` (기존 사용자) / `201` (신규 가입)

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| accessToken | String | JWT Access Token |
| refreshToken | String | Refresh Token |
| isNewUser | Boolean | 이번 요청으로 가입했는지 |
| user | Object | `userId`, `name`(카카오는 닉네임이 미리 채워지고 애플은 `null`일 수 있음), `character`(가족에 합류할 때 배정되므로 가입 직후에는 `null`) |
| groups | Array | 속한 가족 `[{groupId, name}]` |

```json
{
  "success": true,
  "status": 201,
  "message": "가입이 완료되었습니다.",
  "data": {
    "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "isNewUser": true,
    "user": { "userId": "550e8400-e29b-41d4-a716-446655440000", "name": "보민", "character": null },
    "groups": []
  }
}
```

- 신규 가입인데 필수 동의가 없으면 `400`, 탈퇴한 계정이면 `403`이다.
- 앱 이동 (ACC-01, FAM-06): `groups`가 비어 있고 초대 링크로 들어온 것이 아니면 "가족 없음" 화면으로 이동한다. 이 화면에서 가족 만들기(FAM-01)를 하거나 "초대받았다면 받은 링크를 다시 눌러주세요" 안내를 본다. 초대 링크로 들어왔으면 가족 확인 화면으로 이동한다.
- 이메일은 받지 않고 저장하지 않는다. 기능명세서의 카카오 동의항목은 닉네임·프로필 사진이다. DB 반영 필요: `app_user.email`
- 와이어프레임의 로그인 화면에는 개인정보 동의 체크박스 하나만 있고 애플 로그인 버튼이 없다. 기능명세서(ACC-02, ACC-03)와 차이가 있다 ([부록 F](#부록-f-확인이-필요한-항목)).
- 사진·카메라·푸시 권한은 필요한 순간에 목적을 설명하고 요청한다 (ACC-06). 거부해도 핵심 기능은 사용할 수 있다. 서버 API는 없다.

#### 토큰 재발급

| **메서드** | **요청 URL** |
| --- | --- |
| POST | `/api/v1/auth/refresh` |

Request Header

| 파라미터 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `X-Refresh-Token` | String | Y | 로그인 시 발급받은 Refresh Token |

Response `200`: `accessToken`, `refreshToken` (새로 발급되며 이전 리프레시 토큰은 폐기된다)

- 이미 사용된 리프레시 토큰이 다시 오면 `401`이고 해당 계정의 리프레시 토큰을 모두 폐기한다 (탈취 감지).
- 로그인 엔드포인트는 제공자별로 나눈다 (확정). 요청 필드가 다르고(카카오는 `accessToken`, 애플은 `identityToken`·`authorizationCode`·`fullName`) 응답과 에러 형식은 같다. 아래 응답 설명은 두 엔드포인트에 공통이다.

#### 로그아웃

Request Body (선택): `deviceId` — 있으면 해당 기기의 푸시 토큰도 해지한다. Response `200`, `data: null`

#### 탈퇴 (ACC-05, NFR-09, 설정 > 탈퇴)

| **메서드** | **요청 URL** |
| --- | --- |
| DELETE | `/api/v1/me` |

앱의 계정 삭제 확인 화면에서 안내를 보여 주고 사용자가 동의한 뒤 호출한다. 여러 가족에 속해 있으면 가족마다 아래 규칙을 각각 적용한다. 개인정보는 지체 없이 파기한다 (NFR-09).

| 상황 | 처리 |
| --- | --- |
| 모집 중(`COLLECTING`)에 탈퇴 | 탈퇴한 사람의 게시물·답변·댓글을 삭제한다 |
| 마감 후(모집 마감·신문 만드는 중)에 탈퇴 | 이번 호에는 실려서 발송된다. 앱 데이터는 삭제한다 (안내 문구: "이미 마감된 이번 신문에는 실려서 발송돼요") |
| 이미 발송된 신문 PDF | 그대로 유지한다 (안내 문구: "이미 발송된 신문에는 남아 있어요") |
| 방장이 탈퇴 | 가장 먼저 합류한 활동 중인 구성원에게 방장을 자동 이전한다 (FAM-11) |
| 마지막 구성원이 탈퇴 | 가족방과 모든 기록을 삭제한다(복구 불가). 진행 중인 호는 발송하지 않는다 |
| 소셜 연동 | 애플은 토큰 해지(revoke), 카카오는 연결 끊기(unlink) |

Request Body

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `acknowledged` | Boolean | Y | `true`만 허용. 위 안내에 동의했는지 |

Response `200`

```json
{
  "success": true,
  "status": 200,
  "message": "탈퇴가 완료되었습니다.",
  "data": {
    "groups": [
      { "groupId": "7c9e6679-7425-40de-944b-e07fc1f90ae7", "result": "LEFT" },
      { "groupId": "1d3f6a82-9c44-4b0e-a1d5-6f7e8d9c0b1a", "result": "OWNER_TRANSFERRED" },
      { "groupId": "b2c4d6e8-0a1b-4c3d-8e5f-7a9b1c3d5e7f", "result": "GROUP_DELETED" }
    ]
  }
}
```

`result`: `LEFT`(나감), `OWNER_TRANSFERRED`(방장 이전 후 나감), `GROUP_DELETED`(마지막 구성원이라 가족 삭제)

- DB 반영 필요: 현재 `anonymize_user()`는 글·사진을 삭제하지 않고, 가족방에 혼자 남은 방장의 탈퇴를 거부한다. 호가 있는 가족방은 삭제할 수 없는 구조이기도 하다 ([review §2-2](api-spec-review.md)).
- 방장이 내보낸 사람의 게시물은 마감 전 글을 이번 호에 유지하고 이후에는 작성할 수 없다 (제안 확정, 기획·법무 확인 필요, O-17). 탈퇴한 사람은 차단하지 않는다.

### 1-2. 내 프로필

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/me` | 내 정보 조회 | USER |
| PATCH | `/api/v1/me` | 프로필 수정 (PRF-01, 설정 > 프로필) | USER |

#### 내 정보 조회

Response `200`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| userId | UUID | 사용자 ID |
| name | String | 이름 (카카오 프로필이 기본값, 애플은 없을 수 있음) |
| character | String | 앱 아바타와 지면 표기에 쓰는 캐릭터. 합류할 때 배정되고 같은 사람은 모든 화면과 지면에서 같은 캐릭터다 (PRF-05). 프로필 사진은 받지 않는다 (PRF-01) |
| birthMonth / birthDay | Integer | 생일 월·일 (선택 입력) |
| researchConsented | Boolean | 연구 활용 동의 여부 |
| groups | Array | `[{groupId, name, isOwner, relationship}]` (가족 전환 목록) |

#### 프로필 수정

Request Body (보낸 필드만 수정)

| 필드 | 타입 | 필수 | 유효성 | 설명 |
| --- | --- | --- | --- | --- |
| `name` | String | N | 최대 50자 | 이름 |
| `birthMonth` | Integer | N | 1~12 | 생일 월 |
| `birthDay` | Integer | N | 1~31 | 생일 일 |
| `researchConsent` | Boolean | N | - | 연구 활용 동의 변경 |

- 프로필 사진은 받지 않는다 (PRF-01, 1005). 앱 아바타와 지면 표기는 캐릭터다 (PRF-05). 가입 중 이름 확인 화면에서 이름을 확인·수정하고, 설정 > 프로필에서도 수정할 수 있다. 이름 확인 화면에서 뒤로 가면 입력한 내용이 있을 때 확인창을 보이고 입력 내용은 저장하지 않는다.
- 신문 표기는 "관계 + 이름" + 글쓴이 캐릭터다. 캐릭터는 모든 구성원에게 있으므로 항상 함께 표기한다 (PRF-03). 캐릭터 크기·위치는 지면 설계에서 정한다 (O-32). 배정 규칙: 가족방 안에서 색 + 머리·소품이 겹치지 않게 하고(색만으로 구분하지 않음), 얼굴 모양은 동그라미 하나로 통일하며 표정은 기본 미소로 고정한다. 받는 분 캐릭터는 가족방을 만들 때 배정한다 (O-35·O-36·O-38).
- 와이어프레임의 프로필 수정 화면에는 "받는 분과 나의 관계"가 함께 있다. 관계는 가족마다 따로 저장되므로 [2-2](#2-2-구성원)의 API로 수정한다. 클라이언트는 두 API를 함께 호출한다.
- 생일은 월·일만 받고 선택 입력이다 (PRF-01). 와이어프레임 입력란은 `YYYY-MM-DD` 형식이다 ([부록 F](#부록-f-확인이-필요한-항목)). 생일의 사용처는 정해지지 않았고 신문 지면에도 쓰지 않는다 (O-15).
- 생일은 월·일만 선택 입력하고(건너뛰기 가능), 사용처는 신문의 생일 안내다 (NEWS-07). 입력 이유를 앱 문구로 알린다.

---

## 2. Group (가족방)

### 2-1. 가족

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| POST | `/api/v1/groups` | 가족 만들기 (FAM-01, WF-1~5) | USER |
| GET | `/api/v1/groups` | 내 가족 목록 (가족 전환, FAM-04) | USER |
| GET | `/api/v1/groups/{groupId}` | 가족 상세 | MEMBER |
| PATCH | `/api/v1/groups/{groupId}` | 가족방 이름·신문 제호 변경 (FAM-02, FAM-03, FAM-08) | OWNER |
| GET | `/api/v1/groups/{groupId}/recipient` | 받는 분 정보·배송지 조회 (FAM-08) | OWNER |
| PUT | `/api/v1/groups/{groupId}/recipient` | 받는 분 정보·배송지 수정 (FAM-08) | OWNER |

#### 가족 만들기 (FAM-01~03, RCV-01~03)

| **메서드** | **요청 URL** |
| --- | --- |
| POST | `/api/v1/groups` |

가입 후 가족 만들기는 "가족방 없음" 화면의 [가족방 만들기]로 들어간다 (FAM-01). 화면은 3단계이고 한 화면에 한 질문이다: 1/3 받는 분(1명/부부, 이름, 성별, 내 관계, 제3자 정보 동의) → 2/3 배송지(우편번호·주소 찾기, 상세 주소) → 3/3 이름 짓기(가족방 이름·신문 이름, 미리보기 없음) → [가족방 만들기]. 받는 분이 두 분이면 1/3에서 두 분을 카드로 오가며 이름·성별을 입력하고 관계는 카드 밖에서 한 번만 고른다 (PRF-02). 입력 확인 화면은 없다. 입력값은 앱에 임시로 보관하고 마지막 "가족방 만들기"에서 한 번에 서버에 등록한다. 서버는 한 트랜잭션에서 가족방, 방장 구성원, 받는 분 정보, 배송지, 초대 링크를 만들고 하나라도 실패하면 아무것도 만들지 않는다.

사진은 이 요청에 포함하지 않는다. 가족 만들기 중에 고른 받는 분 사진은 기기에 두었다가 가족 생성 후에 업로드한다 (RCV-01). 받는 분 사진은 선택 입력이고 방장이 나중에 추가할 수 있다. 마감 때까지 사진이 없으면 사진 없는 지면으로 배치한다 (O-16 결정).

Request Body

| 필드 | 타입 | 필수 | 유효성 | 설명 |
| --- | --- | --- | --- | --- |
| `name` | String | Y | 최대 50자 | 가족방 이름 (예: 미자 여사네). 앱에서 가족을 부르는 이름이고 **신문에는 실리지 않는다**. 기본값 자동 제안은 없다 (FAM-02) |
| `newsletterTitle` | String | N | 최대 30자 | 신문 제호. 없으면 기본값 `보고잡지` (FAM-03, P1, O-14) |
| `myRelationship` | String | Y | 8개 값 ([부록 A](#부록-a-enum-대응)) | 받는 분과 나의 관계 (PRF-02) |
| `profile` | Object | N | - | 가입자 정보 (WF-2). 보낸 값으로 내 프로필을 갱신한다. 이미 가입한 사용자가 새 가족을 만들 때는 생략할 수 있다 |
| `profile.name` | String | N | 최대 50자 | 이름 |
| `profile.birthMonth` / `profile.birthDay` | Integer | N | 1~12 / 1~31 | 생일 월·일 (선택) |
| `recipient` | Object | Y | - | 받는 분(조부모) 정보 (RCV-01, WF-3) |
| `recipient.type` | String | Y | `SINGLE` \| `COUPLE` | 1명 / 부부 |
| `recipient.name` | String | Y | 최대 50자 | 이름 |
| `recipient.gender` | String | `SINGLE`이면 Y | `FEMALE` \| `MALE` | 호칭 결정에 필요하다. `COUPLE`이면 사용하지 않는다 |
| `address` | Object | Y | - | 받는 분 거주 주소 (RCV-02, WF-4) |
| `address.postalCode` | String | Y | 5자리 숫자 | 우편번호 (우편번호 검색은 클라이언트가 수행) |
| `address.line1` | String | Y | 최대 200자 | 기본 주소 (암호화 저장) |
| `address.line2` | String | N | 최대 200자 | 상세 주소 (암호화 저장) |
| `thirdPartyConsent` | Boolean | Y | `true`만 허용 | 받는 분(제3자) 정보 입력에 대한 동의 (RCV-03) |

```json
{
  "name": "홍씨네 가족",
  "myRelationship": "손녀",
  "profile": { "name": "보민", "birthMonth": 5, "birthDay": 20 },
  "recipient": { "type": "SINGLE", "name": "홍판서", "gender": "FEMALE" },
  "address": { "postalCode": "06236", "line1": "서울특별시 강남구 테헤란로 1", "line2": "101동 1001호" },
  "thirdPartyConsent": true
}
```

Response `201`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| groupId | UUID | 가족 ID |
| name | String | 가족방 이름 |
| ownerId | UUID | 방장 사용자 ID |
| inviteUrl | String | 초대 링크 (WF-5 "가족을 초대해요"에 표시) |
| createdAt | String | 생성일시 |

```json
{
  "success": true,
  "status": 201,
  "message": "가족이 만들어졌습니다.",
  "data": {
    "groupId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
    "name": "홍씨네 가족",
    "ownerId": "550e8400-e29b-41d4-a716-446655440000",
    "inviteUrl": "https://bogo.app/i/Ab12",
    "createdAt": "2026-10-04T10:00:00+09:00"
  }
}
```

- 가족을 만든 사람이 방장이다. 초대 링크 공유(카카오톡으로 보내기·복사)는 클라이언트가 수행하고, "나중에 할게요"로 건너뛸 수 있다. 건너뛴 뒤에는 가족 탭의 초대에서 다시 공유한다 ([2-3](#2-3-초대-링크)).
- 받는 분은 앱에 로그인하지 않고 신문만 받는다. 받는 분 정보는 구성원이 대신 입력한다.
- 호칭은 `myRelationship`과 받는 분 `gender`·`type`으로 정해진다 ([부록 C](#부록-c-관계--호칭-대응표)). 호칭을 직접 입력하는 기능은 없다 (V-29).
- 배송지·받는 분 정보는 방장만 조회·수정하고 암호화해 저장한다 (NFR-07).
- 와이어프레임의 받는 분 정보 화면에는 생일 입력란이 있고 성별 입력란이 없다. 기능명세서는 받는 분 생일을 받지 않고(D-09) 성별을 필수로 둔다 ([부록 F](#부록-f-확인이-필요한-항목)). 이 문서의 API는 기능명세서 기준으로 `recipient.gender`를 받고 받는 분 생일은 받지 않는다.
- DB 반영 필요: `delivery_address`는 현재 가족방당 여러 개, 구성원 누구나 등록, `recipient_phone`·`label`·`memo` 컬럼 포함이다. 제3자 동의를 저장할 컬럼도 없다.
- 받는 분은 사용자(`app_user`)와 **따로 저장**된다. 가족방에 속한 `delivery_address` 한 테이블에 받는 분 이름·성별·유형과 배송지가 함께 있고, `app_user`와 연결된 컬럼은 없다 (받는 분은 로그인하지 않는다). 이 구조로는 부부의 두 분 이름·성별·캐릭터를 저장할 수 없다: 이름 컬럼이 하나이고 부부일 때 성별은 비운다 ([부록 G](#부록-g-db-반영-필요-항목-모음) 4번).
- 가족방 이름과 신문 제호는 별개다 (FAM-02, FAM-03). 제호 기본값은 서비스명 `보고잡지`이고 가족방 만들기 3/3에서 바로 수정할 수 있다. 설명 문구는 "{호칭}께 가는 신문 표지에 인쇄돼요"이다. 신문 제호는 방장만 바꿀 수 있다 (제안 확정, 기획 확인 필요, O-14). DB의 `family_group.newsletter_title`을 그대로 쓴다.
- 가족 만들기 실패 처리 (FAM-01, 프로토타입): ① 보내는 동안 [가족방 만들기]를 비활성화한다 ② 중복 생성 방지: 같은 사람이 방금 같은 내용으로 만든 가족방이 있으면 새로 만들지 않고 그 가족방을 돌려준다(`Idempotency-Key`로 처리하고 같은 키의 재전송은 처음 결과를 돌려준다) ③ 실패해도 입력값은 앱이 유지한다. 실패 화면 문구는 "가족방을 만들지 못했어요 · 입력한 내용은 그대로예요. 인터넷 연결을 확인하고 다시 시도해 주세요."와 [다시 시도] 하나다. 입력값 오류(필수 칸·주소·글자 수)는 앱에서 미리 막는다. 이후 단계(정식)는 원인별로 나누어 처리한다.

#### 가족 목록 / 상세

Response `200` (상세)

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| groupId | UUID | 가족 ID |
| name | String | 가족방 이름 |
| ownerId | UUID | 방장 |
| recipient | Object | `name`, `character`. 구성원 누구나 받는 분의 이름·캐릭터를 볼 수 있다 (FAM-08). 성별·유형·주소는 포함하지 않는다 |
| recipientTitle | String | 보는 사람의 관계 기준 받는 분 호칭 ([부록 C](#부록-c-관계--호칭-대응표)). "할머니께만" 라벨, 프로필, 안내 문구에 쓴다 (TTL-01). 관계가 없으면 `null` |
| myRelationship | String | 내 관계 |
| memberCount | Integer | 활동 중인 구성원 수 |
| currentIssueId | UUID | 이번 호 ID (없으면 `null`) |

목록은 `data`가 위 객체의 배열이다. 가족 전환은 공유 헤더의 가족 이름에서 열고(HOME-05) "새 가족 만들기"가 함께 표시된다. 앱을 열면 마지막에 본 가족을 보여 주고(FAM-04), 알림·질문카드·마감은 가족별로 따로 동작한다 (NOTI-05).

#### 가족방 이름·신문 제호 변경 (FAM-02, FAM-03, FAM-08)

Request Body (보낸 필드만 수정): `name`(가족방 이름, 최대 50자, 방장만), `newsletterTitle`(신문 제호, 최대 30자, 방장만, 제안 확정 O-14). 가족방 이름을 바꿔도 신문 제호는 바뀌지 않는다.

#### 받는 분 정보·배송지 (FAM-08, RCV-01~02, 가족 탭 > 가족 설정)

방장 기능은 가족 탭의 "가족 설정"에 모은다 (FAM-08). 방장만 받는 분 정보를 수정하고 배송지를 조회·수정한다.

- `GET`은 방장에게 입력한 값을 그대로 보여 준다. `PUT`은 가족 만들기와 같은 `recipient`, `address` 구조를 교체하고, 추가로 `recipient.photoUploadId`(업로드 ID)로 받는 분 사진을 등록·변경한다.
- 이번 호 발송지는 마감 시점의 주소로 고정된다 (RCV-02). 마감 후에 수정해도 이미 마감된 호의 발송지는 바뀌지 않는다. DB 반영 필요: 마감 시점 스냅샷이 없고, 현재는 인쇄 주문을 만들 때 복사하는 구조다.
- 전화번호와 배송 메모는 기능명세서에 없어서 받지 않는다.

### 2-2. 구성원

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/groups/{groupId}/members` | 구성원 목록 (FAM-13, 가족 탭) | MEMBER |
| PATCH | `/api/v1/groups/{groupId}/members/me` | 내 받는 분 관계 수정 (PRF-02) | MEMBER |
| DELETE | `/api/v1/groups/{groupId}/members/{userId}` | 구성원 내보내기 (FAM-09) | OWNER |

- 구성원 목록은 모든 구성원이 볼 수 있다. 참여 범위는 가족(배우자의 가족 포함)이다 (FAM-12).
- 가족방만 나가고 계정은 유지하는 "스스로 나가기"는 없다 (V-36). 탈퇴만 제공한다.
- 방장을 수동으로 넘기는 기능은 없다 (V-14). 방장이 탈퇴하면 자동 이전된다.

#### 구성원 목록

Response `200`: `[{userId, name, character, relationship, isOwner, joinedAt}]`

관계는 가족 소속 단위로 저장된다. 합류 후 수정할 수 있다. 목록에는 이름·사진·관계만 포함하고 생일은 포함하지 않는다 (사용처 미정, O-15). 가족 탭의 구성원 목록 또는 홈 상단 구성원 목록에서 구성원을 누르면 그 사람의 글만 본다 ([3-2](#3-2-피드구성원별-글)).

#### 내 관계 수정

Request Body: `relationship` — `손녀`/`손자`/`딸`/`아들`/`며느리`/`사위`/`손주며느리`/`손주사위`. 선택지는 가족(배우자의 가족 포함)으로 한정하고 직접 입력은 없다. 친구·이웃·돌봄·비혈연 선택지는 없다 (V-30).

- 신문 표기명은 "관계 + 이름"(예: 손녀 보민, PRF-03)으로 서버가 만든다.
- 기능명세서에 가족 안 별도 호칭(닉네임) 항목이 없어서 받지 않는다. DB 반영 필요: `family_member.nickname`

#### 구성원 내보내기 (FAM-09, 가족 설정)

내보낸 계정은 "내보낸 구성원" 목록에 등록되고 같은 초대 링크로 재합류할 수 없다 (FAM-07). 탈퇴한 사람은 이 목록에 넣지 않는다. 방장 본인은 내보낼 수 없다 (`409`). 내보낸 사람의 게시물은 마감 전 글을 이번 호에 유지한다 (O-17). 내보낸 사람에게 보내는 알림은 정의되어 있지 않다.

### 2-3. 초대 링크

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/groups/{groupId}/invite-link` | 초대 링크 조회·재공유 (FAM-05, WF-5) | MEMBER |
| GET | `/api/v1/invites/{token}/check` | 링크 유효성 확인 | PUBLIC |
| GET | `/api/v1/invites/{token}` | 합류 전 가족 확인 (FAM-07) | USER |
| POST | `/api/v1/invites/{token}/accept` | 참여하기 | USER |

- 초대는 카카오톡 링크만 쓴다 (가족 코드·문자·이메일 초대 없음, V-23). 구성원 누구나 공유할 수 있다 (FAM-05, FAM-08). 가족 탭에서 초대를 연다.
- 링크 원칙 (FAM-05): 가족마다 고정 초대 코드 1개(추측하기 어려운 문자열)이고 형태는 `https://{도메인}/i/{코드}`이다. 유효기간과 재발급이 없다. 그래서 `POST`로 새로 만들지 않고 `GET`으로 같은 링크를 돌려준다. 가족 만들기 응답의 `inviteUrl`과 같은 값이다. 세부 형식은 개발에서 정한다.
- DB 반영 필요: 현재는 토큰의 해시만 저장하고 방장만 만들 수 있어서, 다른 구성원이 링크를 다시 공유할 수 없다 ([review §2-1](api-spec-review.md)).
- 앱 열기 (FAM-06): iOS 유니버설 링크 / Android 앱 링크로 앱을 열고 합류 확인(FAM-07)으로 이동한다. 앱이 없으면 스토어로 이동하고 설치 후 초대 링크를 다시 누르도록 안내한다 (설치 후 자동 합류 없음, V-38). 로그인·동의를 거치는 동안 초대 코드는 앱이 기기에 보관하고, 합류하거나 취소하면 삭제한다. 로그인을 취소하거나 실패해도 초대 정보는 유지한다. 서버가 보관하는 값은 없다.

#### 링크 유효성 확인 (유저 플로우 "링크 확인")

링크를 열면 로그인 전에 먼저 호출한다. 로그인 이후 단계는 이 확인을 통과한 경우에만 진행된다.

Response `200`: `{ "valid": true }`

존재하지 않거나 유효하지 않은 링크는 `404`이고 `message`는 "링크를 확인할 수 없어요"이다 (FAM-06). 오류 화면의 버튼은 로그인 전 [처음 화면으로], 로그인 후 [내 가족방으로 가기](가족방이 없으면 가족방 없음 화면)이다. 설치 후 링크를 다시 누르지 않고 앱을 열면 가족방 없음 화면의 초대 안내로 이끈다.

- 1005 명세는 링크에 유효기간과 재발급이 없고(FAM-05) 오류는 "초대 코드를 확인할 수 없는 경우"로 정의한다. 유저 플로우·와이어프레임의 "만료" 표현과 "방장에게 새 링크 요청" 안내는 문구를 맞춰야 한다 ([부록 F](#부록-f-확인이-필요한-항목)).

#### 합류 전 가족 확인 (FAM-07, WF-초대받은 사람: 가족 확인)

로그인 후 호출한다. 받는 분 사진·이름과 이미 참여한 가족 프로필을 보여 주는 화면용이다.

Response `200`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| groupId | UUID | 가족 ID |
| groupName | String | 가족방 이름 |
| recipientName | String | 받는 분 이름 (로그인 전 화면에서는 호칭 대신 이름으로 표시한다, TTL-01) |
| recipientCharacter | String | 받는 분 캐릭터 |
| members | Array | 참여 중인 가족 `[{name, character}]` (관계 선택은 이 화면에서 하지 않는다) |
| state | String | `JOINABLE` \| `ALREADY_MEMBER` \| `BLOCKED` |

- `ALREADY_MEMBER`: 이미 소속된 가족의 링크이면 해당 가족으로 바로 이동한다 (FAM-07 정책). 유저 플로우에는 "이미 참여 중이에요" 안내 후 이동으로 그려져 있다.
- `BLOCKED`: 내보낸 구성원이면 "이 가족에는 참여할 수 없어요"를 보여 주고 합류할 수 없다. 소속된 가족이 없으면 가족 없음 화면(ACC-01)으로 이동한다.
- 이미 가입한 사람이 다른 가족의 링크를 누르면 "OO 가족에 합류할까요?" 확인 후 추가한다 (FAM-04).

#### 참여하기

| **메서드** | **요청 URL** |
| --- | --- |
| POST | `/api/v1/invites/{token}/accept` |

Request Body

| 필드 | 타입 | 필수 | 유효성 | 설명 |
| --- | --- | --- | --- | --- |
| `relationship` | String | Y | 8개 값 | 받는 분과 나의 관계. 초대받은 사람은 로그인 후 합류 직전 화면에서 고르고, 방장은 가족방 만들기 1/3에서 고른다 (PRF-02, O-29). 받는 분이 두 분이어도 한 번만 고른다. 처음엔 빈 상태이고 고르기 전에는 다음으로 갈 수 없다 |
| `profile` | Object | N | - | 내 정보 (이름·생일). 처음 가입한 사용자는 이 화면에서 입력하고, 기존 회원은 "관계만 입력"하므로 생략한다. 사진은 받지 않는다 (PRF-01) |
| `profile.name` / `birthMonth` / `birthDay` | - | N | 프로필 수정과 같음 | |

Response `200`: `{ groupId, joinedAt }`

- 이미 소속된 가족이면 오류 없이 같은 `groupId`를 돌려준다.
- 차단된 계정이면 `403`이다 (FAM-07). 탈퇴한 사람은 차단 대상이 아니라서 다시 합류할 수 있다.
- 합류하는 사람은 항상 일반 구성원이다. 합류한 가족은 가족 전환 목록에 추가되고 홈으로 이동한다.
- 잘못 합류한 경우는 내보내기가 아니라 팀 문의로 처리한다 (SET-02).

### 2-4. 내보낸 구성원 (FAM-10)

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/groups/{groupId}/removed-members` | 내보낸 구성원 목록 | OWNER |
| POST | `/api/v1/groups/{groupId}/removed-members/{userId}/allow-rejoin` | 재합류 허용 | OWNER |

재합류를 허용하면 그 계정이 같은 초대 링크로 다시 합류할 수 있다. 허용만으로 자동 합류하지는 않는다. 초대 링크는 재발급하지 않는다 (FAM-05). 1002 명세에서는 "차단 해제"라는 이름이었다.

---

## 3. Feed (홈·소식·질문)

게시물과 답변은 등록 시점 기준으로 해당 호에 자동 배정된다 (POST-07). 게시 날짜는 서버가 기록하고 수정할 수 없다 (POST-03, V-22). 공개 범위는 "가족 전체"와 "할머니께만"(받는 분 호칭 표시) 두 가지다 (POST-02).

### 3-1. 공유 헤더 (가족·호 선택, 상태 줄)

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/groups/{groupId}/home` | 공유 헤더 정보: 선택된 호, 상태 줄 (HOME-02, HOME-05) | MEMBER |

소식·질문카드 탭이 공통으로 쓰는 헤더 값을 한 응답으로 준다. 모인 콘텐츠 수와 참여율은 포함하지 않는다 (D-28, V-35). 홈 상단에 질문 카드를 고정하지 않으므로 질문은 이 응답에 포함하지 않는다 (HOME-01).

| 파라미터 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `issueId` | UUID | N | 헤더에서 고른 호. 없으면 이번 호 |

Response `200`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| group | Object | `groupId`, `name`, `memberCount` |
| issue | Object | 선택된 호. `issueId`, `issueNo`(제 N호), `displayState`([부록 B](#부록-b-호-상태)), `startAt`, `closeAt`, `isCurrent`(이번 호인지), 호가 아직 없으면 `null` |
| displayState | String | 상태 줄 표시: `BEFORE_START`(시작 전) \| `COLLECTING`(모집 중) \| `PRODUCING`(신문 만드는 중) \| `SENT`(발송 완료) |
| dDay | Integer | 날짜 기준(KST) D-n 값. `BEFORE_START`는 시작일까지, `COLLECTING`은 마감일까지 남은 일수이고 마감 당일은 `0`(앱 표시 "D-day"). 그 외 상태는 `null` |
| waitlistVisible | Boolean | 대기 신청 노출 조건(다음 회차 구독이 없는 가족방의 마지막 호가 발송 완료)을 충족하는지 (WAIT-01) |
| waitlistApplied | Boolean | 정식 출시 대기 신청 여부. `SENT`일 때 앱이 "다음 호 신청" 또는 "신청했어요"를 표시한다 (WAIT-01) |
| hasUnseenNotification | Boolean | 알림 목록을 아직 열지 않은 새 알림이 있는지 (종 아이콘 점) |
| canPost | Boolean | 지금 게시·답변·댓글이 가능한지 (선택된 호가 `COLLECTING`이고 이번 호일 때 `true`) |

상태 줄 규칙 (HOME-02, HOME-06)

- 상태 줄은 `BEFORE_START`(작성 가능 시작일) / `COLLECTING`(마감 D-day) / `PRODUCING`(신문 만드는 중) / `SENT`(신문 보기·다음 호 신청) 4가지다. 모집 마감은 자동으로 "신문 만드는 중"이 되므로 `CLOSED`와 `PRODUCING`을 함께 `PRODUCING`으로 표시한다.
- `BEFORE_START`는 호 상태값이 아니라 앱 화면 상태다. 가입 후 첫 호 시작(1주차 월 07:00) 전에는 소식·질문카드 탭이 시작 시점을 안내하는 빈 상태로 표시되고 게시물·답변은 작성할 수 없다. 가족 탭(초대)은 정상 사용한다.
- 안내 문구에는 서비스명 "보고잡지"를 쓰고 가족 제호와 관계없이 고정한다 (예: "D-3 · 10월 13일(월)부터 보고잡지에 글을 쓸 수 있어요"). 문구는 앱이 만든다.
- 호 선택 (HOME-05): 헤더의 호 이름을 누르면 호 목록이 하단 시트로 열리고(가족 전환과 같은 방식), 호(행)를 고르면 소식·질문카드 탭이 함께 그 호로 바뀐다. 호 목록에는 신문 보기 버튼을 두지 않는다. 호가 1개뿐이어도 호 이름을 누르면 같은 목록이 열리고 이번 호만 표시한다(필드 테스트 포함). 호를 넘기는 스와이프·화살표는 없다. 지난 호는 읽기 전용이고, 지난 호를 보는 동안에는 소식 쓰기 버튼을 숨긴다(이번 호 마감 후 비활성과 구분). 지난 호가 아직 "신문 만드는 중"이면 신문 만드는 중 안내 안에 이번 호로만 돌아가는 경로를 표시한다. 지난 호를 보는 동안에는 지난 호임을 알리는 안내와 이번 호로 한 번에 돌아가는 경로를 모든 탭에 표시한다. 앱을 다시 열거나 가족을 바꾸면 그 가족의 이번 호로 시작하고, 알림으로 들어오면 알림이 가리키는 호로 이동한다.
- 유저 플로우의 홈에는 "이번 호 모인 수"가 적혀 있다. 1005 명세(HOME-02)는 모인 콘텐츠 수를 표시하지 않는다 (D-28). 이 문서의 API는 수를 주지 않는다.
- `issueNo`는 해당 가족의 호를 기간 순으로 센 번호이고 DB에 컬럼은 없다 ([review §2-6](api-spec-review.md)).

### 3-2. 피드·구성원별 글

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/groups/{groupId}/posts` | 피드 조회 (HOME-02) | MEMBER |
| GET | `/api/v1/groups/{groupId}/members/{userId}/posts` | 구성원별 글 (WF-프로필 화면) | MEMBER |

#### 피드 조회 (HOME-02)

| 파라미터 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `issueId` | UUID | N | 헤더에서 선택된 호. 없으면 이번 호. 지난 호는 읽기 전용으로 조회한다 (HOME-03) |
| `cursor`, `size` | - | N | 커서 페이지네이션 (시간순, 최신 우선) |

피드에 나오지 않는 항목

| 대상 | 이유 |
| --- | --- |
| 다른 구성원이 올린 "할머니께만" 게시물 | 다른 구성원에게 보이지 않고 신문에만 실린다 (POST-02). 작성자 본인에게는 보인다 |
| 내가 개인 차단한 사람의 글 | SAFE-02 |
| 운영자가 숨긴 글 | ADM-05 |
| 질문 답변 | 질문카드 탭에서 본다 ([3-4](#3-4-질문-qst-0108-질문카드-탭)). 피드는 자유 게시물이다 |

게시물이 없으면 빈 `content`를 돌려주고 앱이 안내 문구를 표시한다. 자유 게시물에는 상호작용이 없다 (댓글·좋아요·이모지 없음, V-31). 댓글은 질문 답변에만 있다.

항목: `postId`, `author{userId, name, character, relationship}`, `body`, `visibility`, `media[{mediaId, thumbUrl, width, height}]`, `postedAt`, `isMine`

#### 구성원별 글 (WF-가족 N명, WF-프로필 화면)

홈 상단 구성원 목록에서 구성원을 누르면 "그 사람의 글만" 본다. 응답 항목과 제외 규칙은 피드 조회와 같고 대상 작성자만 한정한다. 질문 답변은 포함하지 않는다.

### 3-3. 게시물 (POST-01~07, WF-소식 쓰기)

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| POST | `/api/v1/groups/{groupId}/posts` | 게시물 올리기 | MEMBER |
| GET | `/api/v1/posts/{postId}` | 게시물 상세 | MEMBER |
| PATCH | `/api/v1/posts/{postId}` | 글·공개 범위 수정 | 작성자 |
| DELETE | `/api/v1/posts/{postId}` | 게시물 삭제 | 작성자 |
| POST | `/api/v1/posts/{postId}/media` | 사진 추가 | 작성자 |
| DELETE | `/api/v1/media/{mediaId}` | 사진 삭제 | 작성자 |

#### 게시물 올리기

| **메서드** | **요청 URL** |
| --- | --- |
| POST | `/api/v1/groups/{groupId}/posts` |

Request Body

| 필드 | 타입 | 필수 | 유효성 | 설명 |
| --- | --- | --- | --- | --- |
| `body` | String | N | 최대 180자(확정), 금칙어 불가 | 짧은 글. `body`와 `mediaUploadIds` 중 하나는 있어야 한다 |
| `mediaUploadIds` | Array\<UUID\> | N | 게시물당 최대 10장(확정) | 업로드 ID ([4-1](#4-1-업로드-presigned-url)). 앨범 선택·카메라 촬영만 가능하고 편집(자르기·회전)과 영상은 없다 |
| `visibility` | String | N | `ALL` \| `RECIPIENT_ONLY` | 기본 `ALL`. `RECIPIENT_ONLY`는 "할머니께만"이고 다른 구성원에게 보이지 않고 신문에만 실린다. 신문 제외 옵션은 없다 |

작성자는 토큰의 사용자이고 게시 시각은 서버 현재 시각이다.

```json
{
  "body": "오늘 할머니 생신 케이크 앞에서 한 컷!",
  "mediaUploadIds": ["3f2504e0-4f89-11d3-9a0c-0305e82c3301"],
  "visibility": "ALL"
}
```

Response `201`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| postId | UUID | 게시물 ID |
| author | Object | `userId`, `name`, `character`, `relationship` |
| body | String | 글 |
| visibility | String | 공개 범위 |
| media | Array | `[{mediaId, thumbUrl, width, height}]` |
| postedAt | String | 게시 일시 |

에러

| status | 사유 |
| --- | --- |
| 400 | `body`와 사진이 모두 없음, 180자 초과 |
| 403 | 해당 가족의 활동 중인 구성원이 아님 |
| 409 | 첫 호 시작 전 ("아직 글을 쓸 수 없어요") / 마감됨 ("이번 신문은 마감됐어요") |
| 422 | 금칙어 포함 (SAFE-03, 금칙어 목록은 팀이 작성) |

마감 경계 (POST-07): 사진이 있는 요청은 `mediaUploadIds`의 업로드 시작 시각이 모두 `closeAt` 이전이면 `closeAt` + 14분까지 이번 호에 등록한다. 사진이 없는 요청은 `closeAt`까지만 가능하다. 앱의 글쓰기 버튼은 마감 즉시 비활성화한다.

#### 수정 / 삭제 / 사진 (POST-06)

- 수정: `PATCH`로 `body`, `visibility`를 바꾼다. 본인 게시물만, 마감 전까지만 가능하다. 마감 후에는 잠기고 `409`이다.
- 삭제: 본인 게시물만, 마감 전까지만 가능하다. 원본 사진은 소프트 삭제로 보관한다 (NFR-11).
- 사진 추가: Body `mediaUploadIds`. 사진 삭제: `DELETE /media/{mediaId}`.
- 저해상도 사진은 경고만 표시하고 올릴지는 올리는 사람이 고른다. 인쇄에서 자동 제외하지 않는다 (POST-04). 경고 기준은 **짧은 변이 1200px 미만**이다 (확정). 지면 반폭 약 100mm × 300dpi ≈ 1181px에서 계산한 값이다. 와이어프레임의 "저해상도 사진이 있어요" 배너가 이에 해당하며 해상도 검사는 클라이언트가 한다. 서버는 인쇄용 원본을 보관한다.

### 3-4. 질문 (QST-01~08, 질문카드 탭)

질문은 매주 월요일 07:00에 하나씩 공개되고 한 호에 두 개다 (1주차 1개, 2주차 2개째 공개). 가족의 모든 구성원에게 같은 질문이 간다. 질문 풀은 팀이 작성한 고정 데이터이고 질문 바꾸기는 없다 (V-28). 풀 관리 API는 없다. 지난주 질문도 호 마감 전까지 답변할 수 있고, 미답변을 강조하거나 독촉하지 않는다 (QST-01).

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/groups/{groupId}/questions` | 선택된 호의 질문 목록 (HOME-01) | MEMBER |
| PUT | `/api/v1/groups/{groupId}/questions/{questionId}/answer` | 답변 작성·수정 (WF-답변 쓰기) | MEMBER |
| DELETE | `/api/v1/groups/{groupId}/questions/{questionId}/answer` | 답변 삭제 | 작성자 |
| GET | `/api/v1/groups/{groupId}/questions/{questionId}/answers` | 답변 모아보기 (QST-05, WF-답변 모아보기) | MEMBER |

#### 질문 목록 (WF-질문카드 탭)

Query: `issueId`(N, 없으면 이번 호)

Response `200`: 선택된 호에 공개된 질문의 배열이다 (최대 2개, 공개 순서). 아직 공개된 질문이 없으면 빈 배열이다. 질문카드 탭에서 질문을 눌러 답변하고, 답변하면 가족 답변 보기(QST-05)로 전환된다.

질문 항목

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| questionId | UUID | 질문 ID |
| issueId | UUID | 소속 호 |
| kind | String | `BINARY`(양자택일) \| `BALANCE`(밸런스게임) \| `MULTIPLE_CHOICE`(객관식) \| `SHORT_ANSWER`(한 줄 주관식) |
| body | String | 앱 문구. 받는 분 자리에 호칭이 자동으로 들어간다 (TTL-01~04) |
| options | Array | 선택지. 주관식은 `null` |
| publishedAt | String | 공개 일시 |
| myAnswered | Boolean | 내가 답변했는지 |
| answeredCount | Integer | "가족 N명이 답했어요"의 N. 내가 차단한 구성원(SAFE-02)의 답변은 수에서 제외한다 (QST-05) |

- 지면용 문구와 코너명은 앱에 내보내지 않는다.
- 질문 소재는 발신자·받는 분·우리(관계)를 돌아가며 출제한다. 부부 수신이면 받는 분 질문을 한 주씩 번갈아 출제해서(이번 주 할머니, 다음 주 할아버지) 한 호에 두 분의 질문이 하나씩 실린다 (QST-08, 첫 주 여성·둘째 주 남성으로 제안 확정, O-09). 호칭은 질문은 모두 같고 호칭만 보내는 사람마다 다르게 표시한다 (TTL-01).
- 질문 소재 데이터셋·금지어·형태는 팀이 작성하는 고정 데이터라 서버에 별도 알고리즘은 없다 (QST-02, V-08).

#### 답변 작성·수정 (QST-03, QST-04)

멱등 `PUT`이다. 구성원당 질문당 답변은 하나이고, 마감 전까지 수정·삭제할 수 있다.

Request Body

| 필드 | 타입 | 필수 | 유효성 | 설명 |
| --- | --- | --- | --- | --- |
| `option` | String | 선택형이면 Y | `options` 중 하나 | 선택지를 한 번 누르면 답변이 완료된다. 필수 입력은 선택지 하나(주관식은 한 줄)다 |
| `body` | String | 주관식이면 Y | 최대 180자(확정), 금칙어 불가 | 주관식 답, 또는 선택형에 한 줄 덧붙이기(선택) |
| `mediaUploadIds` | Array\<UUID\> | N | - | 사진 첨부(선택) |
| `visibility` | String | N | `ALL` \| `RECIPIENT_ONLY` | 기본 `ALL` |

Response `200`(수정) / `201`(최초): `{ answerId, ... }` (게시물 객체와 같은 형태에 `questionId`, `option` 추가)

와이어프레임의 답변 쓰기 화면은 글 입력(0/180)만 있고 선택지 UI가 없다. 선택형 질문의 화면 구성은 와이어프레임에 없다 ([부록 F](#부록-f-확인이-필요한-항목)).

#### 답변 모아보기 (QST-05)

- 질문은 모든 구성원이 열람할 수 있다. 내가 답변하기 전에는 다른 구성원의 답변 내용을 숨기고, **누가 답변했는지와 아직 답변하지 않은 구성원을 캐릭터로 함께 표시한다** (QST-05, 1005 변경). 내가 답변한 뒤에 답변 내용을 본다. 따라서 답변 전에도 `403`이 아니라 `200`으로 `members`(`[{userId, name, character, answered}]`)만 돌려주고 `answers`는 비운다. 지난 주차 질문도 같은 규칙을 적용한다 (제안 확정).
- "할머니께만" 답변은 공개 대상에서 제외한다. 내가 차단한 사람의 답변과 운영자가 숨긴 답변도 제외한다.

항목: `answerId`, `author{userId, name, character, relationship}`, `option`, `body`, `media`, `commentCount`, `postedAt`, `isMine`

### 3-5. 답변 댓글 (QST-06, WF-답변 모아보기·댓글)

질문 답변에만 댓글을 달 수 있다. 1뎁스(댓글에 댓글 없음)이고 신문에 전재된다. 댓글 알림은 없다.

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/answers/{answerId}/comments` | 댓글 목록 (커서) | MEMBER |
| POST | `/api/v1/answers/{answerId}/comments` | 댓글 달기 | MEMBER |
| PATCH | `/api/v1/comments/{commentId}` | 댓글 수정 | 작성자 |
| DELETE | `/api/v1/comments/{commentId}` | 댓글 삭제 | 작성자 |

Request Body (달기/수정): `body` — 1~180자(확정), 금칙어 불가.

- 마감 후에는 추가·수정이 모두 불가하다 (`409`). 금칙어는 `422`이다.
- "할머니께만" 답변에는 댓글을 달 수 없다 (다른 구성원에게 보이지 않으므로, 확정). 신문에 전재하는 댓글은 답변당 최대 5개이고(확정) 앱에서는 개수를 제한하지 않는다. 지면 전재 개수는 지면 설계 후 조정한다 (O-11).

---

## 4. 업로드 · 신문

### 4-1. 업로드 (presigned URL)

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| POST | `/api/v1/uploads/presign` | 업로드용 URL 발급 (POST-05, NFR-03) | USER |
| POST | `/api/v1/uploads/{uploadId}/complete` | 업로드 완료 확인 | USER (업로드한 본인) |

Request Body

| 필드 | 타입 | 필수 | 유효성 | 설명 |
| --- | --- | --- | --- | --- |
| `purpose` | String | Y | `POST_MEDIA` | 용도. 프로필·받는 분 사진은 받지 않으므로 게시물·답변 사진만 업로드한다 (1005) |
| `contentType` | String | Y | `image/jpeg`, `image/png` | 앱이 HEIC를 JPEG로 변환해 올리고 서버는 JPEG·PNG만 받는다 (확정, O-08) |
| `size` | Long | Y | 최대 20MB(확정) | 바이트 수 |
| `groupId` | UUID | Y | 내 가족 | 대상 가족 |

Response `200`

```json
{
  "success": true,
  "status": 200,
  "message": "요청이 성공적으로 처리되었습니다.",
  "data": {
    "uploadId": "8d5e7f9a-1b2c-4d3e-8f4a-5b6c7d8e9f0a",
    "uploadUrl": "https://storage.example.com/...?signature=...",
    "expiresAt": "2026-10-04T10:10:00+09:00"
  }
}
```

- 업로드 시점 (제안): 사용자가 "올리기"를 누를 때 시작한다. 흐름은 `presign`(서버가 업로드 시작 시각 기록) → 스토리지로 `PUT` → `POST /uploads/{uploadId}/complete` → 게시물·프로필 API에 `uploadId`를 넘긴다. 글을 먼저 만들지 않으므로 앱을 나가도 빈 글이 남지 않는다. 사진을 고르는 즉시 올리는 방식은 서버 구조가 같아서 나중에 앱만 바꿔 도입할 수 있다.
- 업로드 완료 확인: `POST /api/v1/uploads/{uploadId}/complete` (USER, 업로드한 본인). 서버가 스토리지의 파일을 확인하고 가로·세로·해시를 산출해 `UPLOADED` 상태로 바꾼다. 파일이 없으면 `409`이다. 응답: `{ uploadId, status: "UPLOADED", width, height }`.
- 게시물 등록 시 서버가 검증하는 것: 본인이 올린 업로드인지, 같은 가족 대상인지, `UPLOADED` 상태인지, 만료되지 않았는지. 게시물에 연결되지 않은 업로드는 24시간 후 정리한다.
- DB 반영 필요: 임시 업로드 테이블 `media_upload`(`id`, `user_id`, `group_id`, `purpose`, `storage_key`, `status`, `initiated_at`, `expires_at`). 현재 `media.post_id`는 필수라 글보다 먼저 업로드할 수 없다.
- 가로·세로·해시는 서버가 업로드된 파일에서 직접 구한다. 클라이언트가 보낸 값은 틀리거나 변조될 수 있고 요청 필드도 늘어나기 때문이다.
- 피드용 썸네일은 서버가 만든다 (NFR-02). 사진·게시물은 같은 가족 구성원만 볼 수 있고 URL은 만료되는 서명 URL이다 (NFR-08).
- 업로드 시작 시각: presigned URL을 발급하는 시점을 서버가 업로드 시작 시각(`initiatedAt`)으로 기록한다. 마감 시각 전에 시작한 업로드로 만든 게시물·답변은 마감 후 14분까지 등록할 수 있다 ([0. 공통](#0-공통), POST-07). DB 반영 필요: 업로드 시작 시각을 저장하는 컬럼이 없다 (TODO 1과 같은 항목이다).
- 업로드만 하고 게시물에 연결하지 않은 파일은 정리 대상이다. 게시물 등록 전에 앱을 나가면 작성 중이던 글의 본문은 기기에 임시 저장하고 사진은 다시 선택한다 (제안 확정, [부록 F-3](#부록-f-확인이-필요한-항목)).

### 4-2. 신문 보기 (PUB-01, PUB-02, WF-신문 보기·보관함·미리보기)

사용자 API는 호의 **표시 상태 `displayState`**만 내려준다: `COLLECTING`(모집 중) / `PRODUCING`(신문 만드는 중) / `SENT`(발송 완료)와 앱 화면 상태 `BEFORE_START`(첫 호 시작 전). 내부 진행 상태(`phase`)는 운영자 API에만 있고 앱은 내부 이름을 알 필요가 없다 ([부록 B](#부록-b-호-상태), [glossary.md](glossary.md)). 신문은 발송 완료 후에만 열람할 수 있다 (V-17, V-34).

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/groups/{groupId}/issues` | 호 목록 / 보관함 | MEMBER |
| GET | `/api/v1/issues/{issueId}` | 호 상태 | MEMBER |
| GET | `/api/v1/issues/{issueId}/newsletter` | 발송된 신문 열람 (PUB-02) | MEMBER |

#### 상태별 안내

공유 헤더 응답([3-1](#3-1-공유-헤더-가족호-선택-상태-줄))의 `displayState`로 "신문 보기" 화면이 안내를 고른다. `SENT`가 아니면 "아직 신문이 만들어지지 않았어요. 제 N호는 M/D에 마감돼요"를 보여 준다 (WF-신문 보기 안내). 문구에 쓰는 값은 `issueNo`와 `closeAt`이다.

#### 호 목록 / 보관함 (HOME-05, WF-신문 보관함)

호 목록은 공유 헤더의 호 이동(HOME-05)에서 제공한다. PDF만 모아 보는 별도 화면은 없다. `GET /api/v1/groups/{groupId}/issues`로 가져오고 `?displayState=SENT`로 발송 완료된 호만 가져온다.

Response `200`: `[{issueId, issueNo, status, startAt, closeAt, publishedAt}]` — `publishedAt`은 발송 완료로 전환된 일시이고 "11/17 발행"으로 표시한다(`SENT`가 아니면 `null`). 발송 완료된 호가 없으면 앱이 "아직 발행된 신문이 없어요"를 표시한다.

#### 호 상태

Response `200`: `issueId`, `issueNo`, `title`, `periodStart`, `periodEnd`, `displayState`, `closeAt`

진행률, 사진 수, 구성원 참여 수, 상태 변경 타임라인, 인쇄 주문은 가족용 API에 포함하지 않는다. 콘텐츠 수는 표시하지 않기로 했고(D-28), 인쇄·발송은 팀이 직접 처리한다 (PUB-03). 운영자 화면에서만 확인한다 ([6-2](#6-2-호-운영)).

#### 신문 열람 (PUB-02, M-12, WF-완성본 미리보기)

발송 완료 전에는 열람할 수 없다 (`409`). 호출할 때마다 열람 기록이 남고 이 기록이 M-12 지표(신문 열람 구성원 수)의 재료가 된다.

Response `200`

```json
{
  "success": true,
  "status": 200,
  "message": "요청이 성공적으로 처리되었습니다.",
  "data": {
    "issueId": "c9bf9e57-1685-4c89-bafb-ff5af830be8a",
    "pageCount": 4,
    "pages": [
      { "pageNo": 1, "imageUrl": "https://cdn.example.com/newsletter/p1.jpg?signature=..." }
    ],
    "expiresAt": "2026-11-18T10:10:00+09:00"
  }
}
```

- 열람 방식 (PUB-02, 1005 명세): 앱에서 책처럼 한 면씩 넘겨 본다. 서버가 만든 열람용 페이지 이미지를 가로로 넘기고(한 번 누르면 메뉴 표시/숨김, 두 번 누르거나 벌리면 확대), 마지막 면 다음 장에 대기 신청 카드를 보여 준다 ([5-5](#5-5-정식-출시-대기-신청-wait-01)). 글자를 화면에 맞게 다시 배치하는 방식(리플로우)은 쓰지 않고 종이 지면과 같은 모양을 보여 준다.
- 다운로드·공유는 없다. 인쇄용 PDF는 앱에 내려보내지 않는다. 열람용 이미지는 "할머니께만" 블러를 서버에서 입힌 것만 제공하고(작성자 본인에게도 블러, 안내 메시지 표시), URL은 만료되는 서명 URL이다 (NFR-08).
- 열람용 페이지 이미지(면마다 1장)는 자동 조판과 같은 작업에서 생성한다 (NEWS-01). 화면 이름은 "완성본 미리보기"이지만 발송 완료된 호만 열 수 있어서 "발행 전 미리보기 없음"과 충돌하지 않는다.
- DB 반영 필요: 열람용 페이지 이미지를 저장하는 곳이 필요하다. `preview` 테이블(`run_id`, `page_no`, `storage_key`)이 이 용도에 해당할 수 있다 ([review §3](api-spec-review.md)).

---

## 5. Safety · 알림 · 기타

### 5-1. 콘텐츠 신고 (SAFE-01)

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| POST | `/api/v1/reports` | 게시물·답변·댓글 신고 | USER |

Request Body

| 필드 | 타입 | 필수 | 유효성 | 설명 |
| --- | --- | --- | --- | --- |
| `targetType` | String | Y | `POST` \| `ANSWER` \| `COMMENT` | 신고 대상 |
| `targetId` | UUID | Y | - | 대상 ID |
| `reason` | String | Y | `INAPPROPRIATE`(부적절한 내용) \| `PERSONAL_INFO`(개인정보 노출) \| `SPAM`(광고·스팸) \| `OTHER`(기타) (제안 확정, O-24) | 사유는 선택지에서 고른다 |

Response `201`: `{ reportId, status: "PENDING" }`

- 신고한 사람의 화면에서는 즉시 숨긴다. 신문 지면에는 영향이 없고 지면 제외는 운영자 검수로 처리한다.
- 접수되면 팀에 메일이 간다 (ADM-08). 운영자는 24시간 안에 대응한다 (ADM-05).
- 신고 기능은 어느 탭에서나 열 수 있는 공통 기능이다 (와이어프레임 질문카드 탭 하단 표기). 방장의 내보내기(FAM-09)와는 별개다.

### 5-2. 개인 차단 (SAFE-02)

내 화면에서 그 사람의 콘텐츠를 숨기고 팀에 자동 신고한다. 방장의 내보내기와는 별개다.

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/me/blocks` | 내가 차단한 사용자 | USER |
| POST | `/api/v1/users/{userId}/block` | 차단 | USER |
| DELETE | `/api/v1/users/{userId}/block` | 차단 해제 | USER |

자기 자신을 차단하면 `400`이고, 이미 차단한 사용자를 다시 차단하면 `200`(멱등)이다. 해제해도 신고는 취소되지 않는다. 차단은 게시물·답변·댓글의 "…" 메뉴에서 하고 상대에게 알림이 가지 않는다. 해제는 설정의 "내가 차단한 사람"에서 한다 (SAFE-02). 신문 지면에는 영향이 없고 지면 제외는 운영자 검수로 처리한다.

### 5-3. 푸시 기기

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| POST | `/api/v1/me/devices` | 푸시 토큰 등록 | USER |
| DELETE | `/api/v1/me/devices/{deviceId}` | 푸시 토큰 해지 | USER |

Request Body (등록): `platform`(`IOS`\|`ANDROID`), `pushToken`(Expo 푸시 토큰). 푸시는 앱 푸시만 쓴다. 카카오 알림톡은 쓰지 않는다 (V-32). 알림 on/off는 기기 알림 설정으로 대신하므로 앱 안 알림 설정 API는 없다 (V-21).

서버가 보내는 푸시 (클라이언트가 호출하는 API는 없음)

| 알림 | 시점 | 대상 |
| --- | --- | --- |
| 질문 공개 (NOTI-01) | 매주 월 07:00 | 가족의 구성원 |
| 마감 전 미참여 (NOTI-02) | 2주차 토요일 15:00 | 이번 호에 게시물·답변이 아직 없는 구성원. "질문 하나만 답해도 이번 호에 실려요" + 이번 주 질문, 누르면 질문 답변 화면 |
| 발송 완료 (NOTI-03, P1) | 운영자가 발송 완료로 전환할 때 | 가족 전원 |

- 구성원당 주 2회 이하로 마감 리마인더와 질문 알림을 합쳐 보낸다 (NOTI-04). 가족별로 따로 동작한다 (NOTI-05).
- 연속 답변 기록(streak)·미답변 표시·추가 독촉은 없다. 댓글 알림은 없다 (QST-06).
- 방장이 바뀌면 새 방장에게는 푸시 없이 알림 목록에만 "이제 OO님이 방장이에요"를 남긴다 (FAM-11).
- 1002 명세에서는 미참여 알림 시각이 토요일 15:00과 19:00으로 달랐고, 1005 명세는 15:00이다.
- 푸시 권한을 거부해도 알림 목록에는 기록한다 (NOTI-06).

### 5-4. 알림 목록 (NOTI-06, WF-알림 목록)

소식·질문카드 탭 공유 헤더의 종 아이콘(설정 왼쪽)에서 여는 알림 목록이다. 가족 탭에는 없다 (HOME-04). 소속된 모든 가족의 알림을 가족 이름과 함께 시간순으로 보여 주고, 누르면 그 가족·화면으로 이동한다(푸시를 누른 것과 같은 동작).

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/me/notifications` | 알림 목록 (커서) | USER |
| POST | `/api/v1/me/notifications/seen` | 목록 열람 기록 (종 아이콘 점 제거) | USER |
| POST | `/api/v1/me/notifications/{notificationId}/read` | 읽음 처리 | USER |

#### 알림 목록

Query: `cursor`, `size`

항목

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| notificationId | Long | 알림 ID |
| kind | String | 알림 종류 (아래 표) |
| groupId / groupName | UUID / String | 가족 (가족 이름과 함께 표시) |
| issueId | UUID | 이동할 호 (없으면 `null`) |
| questionId | UUID | 관련 질문 (`QUESTION_PUBLISHED`일 때) |
| title | String | 표시 문구 |
| createdAt | String | 발생 일시. 앱이 "오늘", "어제", "11/17"로 표시한다 |
| read | Boolean | 읽음 여부. 읽지 않은 항목은 배경색으로 구분한다 |

| kind | 발생 | 명세 |
| --- | --- | --- |
| `QUESTION_PUBLISHED` | 질문 공개 | NOTI-01 |
| `DEADLINE_REMINDER` | 마감 리마인더 | NOTI-02 |
| `ISSUE_SENT` | 발송 완료 | NOTI-03 |
| `OWNER_CHANGED` | 방장 변경 ("이제 OO님이 방장이에요") | FAM-11 |

- 보기·읽음 규칙: 새 알림이 있으면 종 아이콘에 점을 표시한다(`GET /home`의 `hasUnseenNotification`). 목록을 열면 점이 사라진다(`POST /notifications/seen`). 목록의 안 읽은 항목은 배경색으로 구분하고, 그 항목이나 같은 내용의 푸시를 누르면 읽음 처리한다(`POST .../read`). "모두 읽음" 버튼은 없다.
- 보관: 받은 날부터 60일이고 지나면 자동 삭제한다 (O-33 결정). 푸시 권한을 거부해도 목록에는 기록한다.
- 와이어프레임에 있는 "새 소식을 올렸어요", "배송 중이에요", "마감 3일 전" 항목은 1005 명세의 알림 항목(NOTI-01~03, FAM-11)에 없다. 이 문서의 `kind`는 1005 명세 기준이다 ([부록 F](#부록-f-확인이-필요한-항목)).
- DB 반영 필요: `notification_log`에 읽음·열람 상태 컬럼이 없고, `kind`는 3종(`question_published`, `deadline_reminder`, `published`)만 허용한다. 방장 변경 알림은 종류가 없다. 60일 삭제 규칙도 필요하다.

### 5-5. 정식 출시 대기 신청 (WAIT-01)

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| POST | `/api/v1/waitlist` | 대기 신청 | USER |

"대기 신청" 버튼을 누르면 신청 기록을 저장하고 "정식 출시 때 알려드릴게요"를 안내한다. 화면에 "월 1회 발송, 월 16,900원"(잠정 가격)을 표시하고 결제·외부 링크는 없다 (D-02, 10/4 결정). Body 없음. 이미 신청했으면 `200`으로 멱등 처리한다. 신청 후에는 "신청했어요"를 표시하고 앱 실행 팝업·추가 푸시는 없다.

- 노출 조건 (1005): **다음 회차 구독이 없는 가족방의 마지막 호가 발송 완료된 때부터** 일괄 노출한다. 유저 테스트 전용이 아니다. 다음 호가 이어지면 그 호는 지난 호가 되므로 노출하지 않는다. 진입 경로는 세 가지다: ① 신문 보기의 마지막 면 다음 장(책의 뒷장처럼) ② 공유 헤더 상태 줄("다음 호 신청") ③ 마감 후 글쓰기 버튼 안내 속 링크. 신청 여부는 `GET /home`의 `waitlistApplied`로 확인한다. 노출 조건 판단은 서버가 하고 `home` 응답에 `waitlistVisible`로 내려준다.
- 유저 플로우·와이어프레임의 "시범 종료 선택"(유료로 계속 / 무료로만 / 그만 쓰기)은 1005 명세의 WAIT-01(버튼 하나)과 다르다. 이 문서는 1005 명세 기준이다 ([부록 F](#부록-f-확인이-필요한-항목)).

### 5-6. 설정 화면

설정은 우상단 아이콘에서 연다 (HOME-04). 구성은 프로필, 내가 차단한 사람, 정책 링크·문의, 로그아웃, 탈퇴이다. 개인정보 처리방침·이용약관 링크(SET-01)와 팀 문의 이메일 텍스트(SET-02)는 앱에 고정된 값이라 API가 없다. 앱 안 문의하기·FAQ는 없다 (V-24).

---

## 6. Admin (운영자)

운영자 Admin의 v1 범위는 팀 논의 중이다 (O-23, V-27). 아래는 기능명세서의 ADM-01~08 기준이고, 범위가 정해지면 이 장을 조정한다. 유저 플로우와 와이어프레임에는 Admin 화면이 없다.

모든 `/api/v1/admin/**`는 운영자 토큰이 필요하다 (ADM-01). 운영자가 호 상태를 바꾸면 토큰의 운영자 ID가 이력에 남는다.

### 6-1. 인증

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| POST | `/api/v1/admin/auth/login` | 운영자 로그인 | PUBLIC (이메일 + 비밀번호, 제안 확정) |
| GET | `/api/v1/admin/me` | 내 정보 | OPERATOR |

### 6-2. 호 운영

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| POST | `/api/v1/admin/issues/open` | 이번 호 시작 (전 가족 일괄) | OPERATOR |
| GET | `/api/v1/admin/issues` | 가족별 호 상태 보기 (ADM-02) | OPERATOR |
| GET | `/api/v1/admin/issues/{issueId}` | 호 상세 + 조판·인쇄 현황 | OPERATOR |
| PATCH | `/api/v1/admin/issues/{issueId}/markers` | 검수 마커 표시 (진행 추적용) | OPERATOR |
| GET | `/api/v1/admin/issues/{issueId}/ship-check` | 발송 완료 사전 점검 | OPERATOR |
| POST | `/api/v1/admin/issues/{issueId}/ship` | 발송 완료로 전환 (ADM-02) | OPERATOR |

#### 이번 호 시작

모든 가족이 같은 일정을 쓴다 (시작일 전까지 가입 완료). 테스트는 2주 × 1호이고 다음 호는 만들지 않는다 (POST-07).

Request Body

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `startAt` | String | Y | 호 시작 (예: 1주차 월 07:00) |
| `closeAt` | String | Y | 마감 (예: 2주차 일 23:59). 시작보다 뒤여야 한다 |
| `title` | String | N | 호 제목 |

Response `201`: `{ "createdCount": 10 }`. 같은 시작일의 호가 이미 있는 가족은 건너뛰고 건수에 넣지 않는다 (멱등).

DB 반영 필요: 현재는 가족방별 마감일(`close_day`)·타임존과 매월 자동 생성 배치라서 2주 × 1호 일정과 구조가 다르다 ([review §1-4](api-spec-review.md)). 와이어프레임에는 제1·2·3호가 보이는데 이는 화면 예시이고, 기능명세서는 테스트를 1호로 정한다.

#### 호 목록

Query: `phase`(내부 상태, [부록 B](#부록-b-호-상태)), `displayState`, `reviewed`(검수 마커), `groupId`, `page`, `size`.

항목: `issueId`, `groupId`, `groupName`, `issueNo`, `phase`(내부 상태), `displayState`, `reviewed`, `printDownloaded`, `closeAt`

#### 호 상세

목록 항목에 더해 `members`(`total`, `participated`), `posts`·`answers` 수, `latestRun`(`status`, `attempts`, `report`), `printJob`(`status`, `preflightReport`), 마커(`reviewedBy`, `reviewedAt`, `printDownloadedAt`)를 준다.

#### 검수 마커 (진행 추적용)

| **메서드** | **요청 URL** |
| --- | --- |
| PATCH | `/api/v1/admin/issues/{issueId}/markers` |

운영자 4명이 가족방 여러 개를 나눠 처리할 때 "누가 어디까지 했는지" 보려는 **표시용 값**이다. 호 상태를 바꾸지 않고 발송 완료 전환의 필수 조건도 아니다 (수동 전환은 발송 완료 하나, PUB-01·ADM-02).

Request Body

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `reviewed` | Boolean | Y | 검수 완료 표시. `true`면 표시한 운영자와 시각을 기록한다 |

Response `200`: `{ reviewed, reviewedBy, reviewedAt, printDownloaded, printDownloadedAt }`

- `printDownloaded`는 입력 값이 아니다. 해당 호가 포함된 **인쇄용 PDF 일괄 다운로드**([6-4](#6-4-인쇄발송-자료-adm-04-pub-03))를 하면 서버가 기록한다.
- 호가 `IN_REVIEW`가 아니면 `409`이다.
- **재조판하면 `reviewed`는 초기화**된다. 새 조판 결과를 다시 검수해야 하기 때문이다.
- 마커는 사용자 API에 노출하지 않는다.

#### 발송 완료 사전 점검

| **메서드** | **요청 URL** |
| --- | --- |
| GET | `/api/v1/admin/issues/{issueId}/ship-check` |

Response `200`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| canShip | Boolean | 필수 점검을 모두 통과했는지 (`blockers`가 비었는지) |
| notifyCount | Integer | 전환하면 푸시를 받을 구성원 수 |
| blockers | Array | 전환을 막는 항목 `[{code, message}]` |
| warnings | Array | 확인 후 전환할 수 있는 항목 `[{code, message}]` |

| 점검 | 성격 | `code` |
| --- | --- | --- |
| 호가 `IN_REVIEW`임 (`COMPOSING`·`COMPOSE_FAILED` 등이 아님) | 필수 | `NOT_IN_REVIEW` |
| 최신 조판이 `done`이고 인쇄용 PDF가 `READY`임 | 필수 | `NO_READY_PDF` |
| 내용 없는 호가 아님 | 필수 | `NO_CONTENT` |
| 검수 마커(`reviewed`)가 켜져 있음 | 경고 | `NOT_REVIEWED` |
| 인쇄용 PDF를 내려받은 기록이 있음 | 경고 | `PDF_NOT_DOWNLOADED` |

#### 발송 완료로 전환 (ADM-02, NOTI-03)

| **메서드** | **요청 URL** |
| --- | --- |
| POST | `/api/v1/admin/issues/{issueId}/ship` |

운영자가 수동으로 바꾸는 상태는 '발송 완료'뿐이다. 마감 → 조판 → 검수 대기까지는 자동 전환이다 (PUB-01, ADM-02). 우편 발송을 마친 뒤에 호출한다. **한 번 전환하면 되돌릴 수 없다.** 푸시가 이미 나가기 때문이다.

Request Body

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `confirmed` | Boolean | Y | `true`여야 한다. 앱이 "N명에게 푸시가 나갑니다" 확인 화면을 거친 뒤 보낸다 |
| `note` | String | N | 메모 |

Response `200`

```json
{
  "success": true,
  "status": 200,
  "message": "발송 완료로 전환되었습니다. 가족에게 알림이 발송됩니다.",
  "data": {
    "issueId": "c9bf9e57-1685-4c89-bafb-ff5af830be8a",
    "phase": "SENT",
    "displayState": "SENT",
    "changedAt": "2026-11-17T14:00:00+09:00"
  }
}
```

| status | 사유 |
| --- | --- |
| 409 | 필수 점검 실패(`blockers`를 응답에 포함), 이미 `SENT` |
| 422 | `confirmed`가 없거나 `false` (사전 점검 결과를 함께 돌려줌) |

- 전환하면 해당 가족방 구성원 전원에게 푸시(NOTI-03)가 가고 신문 보관함에 호가 추가된다.
- 경고(`warnings`)가 있어도 `confirmed: true`면 전환된다.
- DB 반영 필요: 현재 상태는 7개이고 `review → printing`도 수동 전환이다. 호 내부 상태를 [부록 B](#부록-b-호-상태)의 6개로 바꾸고 `reviewed_at`, `reviewed_by` 컬럼과 인쇄용 PDF 다운로드 기록이 필요하다 ([review §6](api-spec-review.md)).

### 6-3. 조판 검수 (ADM-03, NEWS-01, NEWS-06)

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/admin/issues/{issueId}/pdf` | 가족별 신문 PDF 확인 | OPERATOR |
| POST | `/api/v1/admin/issues/{issueId}/recompose` | 게시물을 '이번 호에서 제외'하고 다시 만들기 | OPERATOR |
| POST | `/api/v1/admin/issues/{issueId}/compose/retry` | 조판 실패 재시도 | OPERATOR |

- 검수는 PDF를 확인하고 게시물을 이번 호에서 제외한 뒤 다시 만드는 것이다. 페이지·배치 단위 수정은 기능명세서에 없다.
- 조판은 마감 유예(00:14)가 끝난 00:15 이후 자동으로 시작하고(가족 승인 없음, 규칙 기반 템플릿 선택), 비동기로 60초 이내에 끝난다 (NEWS-01, NFR-04). 같은 작업에서 앱 열람용 페이지 이미지(면마다 1장, "할머니께만" 블러 적용)도 만든다 (PUB-02). 실패하면 최대 3회 재시도한 뒤 운영자에게 알린다 (NEWS-06, NFR-10).

#### PDF 확인

Response `200`: `{ "pdfUrl": "...", "expiresAt": "...", "runNo": 2, "status": "DONE" }`. 조판 중이면 `409`이다.

#### 다시 만들기

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `excludePostIds` | Array\<UUID\> | Y | 이번 호에서 뺄 게시물·답변 (1개 이상) |
| `note` | String | N | 사유 |

Response `200`: `{ "issueId": "...", "phase": "COMPOSING", "excludedCount": 2 }`. 조판은 비동기로 진행되므로 응답은 즉시 돌려주고, 운영자는 호 상세(`GET /admin/issues/{id}`)로 진행을 확인한다.

- 제외는 해당 호의 신문에서만 적용된다. 가족 피드의 원본 게시물은 그대로 남는다.
- 호가 `IN_REVIEW`(검수 중)가 아니면 `409`이다. 다시 만들면 호는 `COMPOSING`으로 돌아가고 이전 조판 결과는 무효가 되며 `reviewed` 마커는 초기화된다. 사용자에게는 계속 "신문 만드는 중"으로 보인다.

#### 조판 실패 재시도

실패 기록을 초기화하고 다시 큐에 넣는다. Response `200`: `{ "resetCount": 3 }`. 실패한 호는 호 목록의 `phase=COMPOSE_FAILED`로 모아서 본다. 사용자에게는 실패 중에도 "신문 만드는 중"으로 보이므로 운영 알림(ADM-08)이 유일한 신호다.

### 6-4. 인쇄·발송 자료 (ADM-04, PUB-03)

인쇄와 우편 발송은 팀이 직접 처리한다 (택배 API 연동 없음, 결제 없음). 가족이 주문하는 API는 없다.

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| POST | `/api/v1/admin/print/pdf-exports` | 인쇄용 PDF 일괄 다운로드 | OPERATOR |
| GET | `/api/v1/admin/print/addresses.xlsx` | 배송지 목록 엑셀 다운로드 | OPERATOR |
| GET | `/api/v1/admin/groups/{groupId}/recipient` | 한 가족의 받는 분·배송지 열람 | OPERATOR |

#### 인쇄용 PDF 일괄 다운로드

Request Body: `issueIds`(Array\<UUID\>, `READY` PDF가 있는 호). Response `200`: `{ "downloadUrl": "...(zip)", "expiresAt": "...", "count": 10 }` — 운영팀이 내려받아 검수·출력에 쓰는 압축 파일이다. 판형·출력 형식·인쇄 사양은 미결이다 (O-06).

#### 배송지 목록 엑셀

Query: `issueIds`. 마감 시점 주소로 만든다 (RCV-02). 컬럼은 받는 사람 이름, 우편번호, 주소, 상세주소이다.

#### 열람 기록 (ADM-01)

배송지는 Admin에서만 열람하고, 열람·다운로드할 때마다 기록이 남는다. 위 두 배송지 API가 기록 대상이다. 기록은 응답을 내려 주기 전에 남긴다. 인쇄용 PDF 일괄 다운로드도 호별로 기록해서 `printDownloaded` 마커의 근거로 쓴다 (DB 반영 필요: 현재 다운로드 기록은 배송지에만 있다).

### 6-5. 신고 처리 (ADM-05, SAFE-01~02)

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/admin/reports` | 신고 목록 | OPERATOR |
| GET | `/api/v1/admin/user-blocks` | 개인 차단 목록 | OPERATOR |
| PATCH | `/api/v1/admin/reports/{reportId}/resolve` | 신고 처리 (숨김 포함) | OPERATOR |

- 신고·차단 목록을 확인하고 신고된 게시물·답변·댓글을 숨긴다. 24시간 안에 대응하고, 처리 기준은 미결이다 (O-24).
- 개인 차단은 자동 신고(`target USER`)로도 들어온다.

Request Body (신고 처리)

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `action` | String | Y | `HIDE`(대상 콘텐츠를 모든 가족에게서 숨김) \| `DISMISS`(조치 없음) |
| `note` | String | N | 처리 메모 |

Response `200`: `{ reportId, status: "RESOLVED", action, resolvedAt }`. 숨김은 가족 피드·질문 답변·댓글에서 사라지게 하고, 신문 지면에서 빼는 일은 6-3의 다시 만들기로 처리한다. DB 반영 필요: `post`·`comment`에 숨김 컬럼이 없다.

### 6-6. 지표 · 대기 신청 · 운영 알림

| Method | URL | 기능 | 권한 |
| --- | --- | --- | --- |
| GET | `/api/v1/admin/metrics` | 평가 지표 (ADM-06, M-01~M-13) | OPERATOR |
| GET | `/api/v1/admin/metrics.xlsx` | 평가 지표 엑셀 내보내기 | OPERATOR |
| GET | `/api/v1/admin/waitlist` | 대기 신청 목록·신청 수 (ADM-07) | OPERATOR |
| GET | `/api/v1/admin/alerts` | 운영 알림 목록 (ADM-08) | OPERATOR |

#### 평가 지표 (ADM-06)

Query: `issueId`(없으면 전체). 집계는 마감 시점 기준이다 (M-12·M-13은 수시).

| 필드 | 지표 | 정의 |
| --- | --- | --- |
| members | M-01 | 마감 시점에 가족에 남아 있는 구성원 수 (방장 포함, 마감 후 탈퇴자 포함) |
| posts | M-02 | 이번 호 게시물 수 ("할머니께만" 포함, 마감 전 삭제분 제외) |
| answersByQuestion | M-03 | 질문 1·2별 답변 구성원 수 |
| participants / participationRate | M-04, M-05 | 게시물·답변을 1건 이상 남긴 구성원 수 / ÷ M-01 |
| comments | M-06 | 답변 댓글 수 |
| answerRateByQuestion | M-07 | 질문별 답변율 |
| questionOnlyMembers | M-08 | 답변만 있고 게시물은 0건인 구성원 수 |
| recipientOnlyRate | M-09 | "할머니께만" 게시물·답변 ÷ 전체 |
| reminderConverted | M-10 | 리마인더를 받은 구성원 중 발송 이후 마감 사이에 참여한 수 |
| dailyPosts | M-11 | 날짜별(KST) 등록 수 (전체) |
| newsletterViewers | M-12 | 발송 후 신문을 한 번이라도 연 구성원 수 |
| waitlistRate | M-13 | 대기 신청(WAIT-01)한 구성원 ÷ M-01 |

`families`(가족별)와 `total`(전체)을 함께 준다.

#### 대기 신청 목록 (ADM-07)

`[{userId, name, groupId, groupName, appliedAt}]`와 `totalCount`.

#### 운영 알림

조판 실패(3회 재시도 후)·신고 접수 시 팀 메일 발송 기록. 항목: `kind`(`LAYOUT_FAILED`\|`REPORT_RECEIVED`), `refType`, `refId`, `sentAt`.

---

## 부록 A. enum 대응

| API | DB | 대상 |
| --- | --- | --- |
| `KAKAO`, `APPLE` | `kakao`, `apple` | 로그인 제공자 |
| `ALL`, `RECIPIENT_ONLY` | `all`, `recipient_only` | 공개 범위 (가족 전체 / 할머니께만) |
| `BINARY` `BALANCE` `MULTIPLE_CHOICE` `SHORT_ANSWER` | 소문자 | 질문 종류 |
| `SINGLE`, `COUPLE` / `FEMALE`, `MALE` | 소문자 | 받는 분 유형·성별 |
| `손녀` `손자` `딸` `아들` `며느리` `사위` `손주며느리` `손주사위` | 그대로 | 받는 분과의 관계 (8개) |
| `POST` `ANSWER` `COMMENT` (`USER`는 자동 신고용) | `post` `comment` `user` | 신고 대상. `ANSWER`는 `question_id`가 있는 `post`이다 |
| `PENDING`, `RESOLVED` | 소문자 | 신고 상태 |
| `HIDE`, `DISMISS` | 없음 (DB 반영 필요) | 신고 처리 |
| `BEFORE_START` `COLLECTING` `PRODUCING` `SENT` | (파생값) | 표시 상태 `displayState` ([부록 B](#부록-b-호-상태)) |
| `COLLECTING` `CLOSED` `COMPOSING` `COMPOSE_FAILED` `IN_REVIEW` `SENT` | `issue.status` 값 변경 필요 | 호 내부 상태 `phase` (운영자 API만) |
| `QUESTION_PUBLISHED` `DEADLINE_REMINDER` `ISSUE_SENT` `OWNER_CHANGED` | `kind`는 3종만 있음 (DB 반영 필요) | 알림 종류 |

## 부록 B. 호 상태

호 상태는 **내부 상태(`phase`)** 하나를 원천으로 두고, 사용자에게 보이는 **표시 상태(`displayState`)**는 서버가 매핑해서 만든다. 표시가 명세에 따라 바뀌어도 내부 상태는 흔들리지 않게 하려는 구조다. 이 표가 단일 출처이고 [glossary.md](glossary.md)에도 같은 표가 있다.

### 내부 상태 `phase` (운영자 API, 6개)

| `phase` | 의미 | 전환 | `displayState` | 현재 DB `issue.status` |
| --- | --- | --- | --- | --- |
| `COLLECTING` | 모집 중 | 호 시작 | `COLLECTING` | `collecting` |
| `CLOSED` | 마감 시각이 지남. 사진 있는 글은 +14분까지 등록 가능, +15분부터 조판 대기 | 자동 (마감 시각) | `PRODUCING` | `closing` |
| `COMPOSING` | 조판 큐 대기·실행·재시도 대기. 재조판도 여기로 돌아옴 | 자동 | `PRODUCING` | `closing` (+ `layout_run` 진행 중) |
| `COMPOSE_FAILED` | 3회 실패, 운영자 조치 필요 | 자동 | `PRODUCING` | `closing` (+ `layout_run` 실패 3회) |
| `IN_REVIEW` | 운영자 검수 | 자동 (조판 완료) | `PRODUCING` | `review` |
| `SENT` | 발송 완료 | **운영자 수동** (`/ship`) | `SENT` | `printed`, `archived` |

허용 전이: `COLLECTING → CLOSED → COMPOSING → IN_REVIEW → SENT`, `COMPOSING → COMPOSE_FAILED`, `COMPOSE_FAILED → COMPOSING`(재시도), `IN_REVIEW → COMPOSING`(재조판). **`SENT`는 되돌릴 수 없다.** 전이 규칙은 코드 상수로 두고 전이표 테이블은 쓰지 않는다.

- DB 반영 필요: `issue.status`를 위 6개로 바꾸고 `skipped`, `archived`, `printing`을 없앤다. `COMPOSING`·`COMPOSE_FAILED`는 `layout_run` 상태에서 파생하거나 값으로 둔다 ([review §6](api-spec-review.md)).
- 이전 초안의 `step` 값 중 `CLOSE_FAILED`(마감 배치 실패)는 사진 선별이 없어져 불필요해졌고, `PREFLIGHT_FAILED`는 조판 작업 안에서 인쇄 파일까지 만들므로 `COMPOSE_FAILED`(사유 `render_failed`)에 포함한다.
- 호 시작 전과 내용 없는 호는 호 상태가 아니다. 앞의 것은 앱 화면 상태(`BEFORE_START`), 뒤의 것은 `COMPOSE_FAILED` 또는 운영 표시(`no_content`)다.

### 표시 상태 `displayState` (사용자 API)

| `displayState` | 대응하는 `phase` | 상태 줄 표시 (HOME-02) |
| --- | --- | --- |
| `BEFORE_START` | 호가 없거나 시작 시각 이전 (앱 화면 상태) | 작성 가능 시작일 |
| `COLLECTING` | `COLLECTING` | 마감 D-day |
| `PRODUCING` | `CLOSED`, `COMPOSING`, `COMPOSE_FAILED`, `IN_REVIEW` | 신문 만드는 중 (마감, 조판, 실패, 검수, 재조판이 모두 한 표시) |
| `SENT` | `SENT` | 신문 보기 · 다음 호 신청 |

조판이 실패해도 사용자에게는 계속 "신문 만드는 중"으로 보인다. 그래서 `COMPOSE_FAILED`는 운영 알림(ADM-08)이 유일한 신호이고, 지연 기준(예: 마감 후 몇 시간)은 정해야 한다.

### 운영 마커 (표시용)

| 마커 | 값 | 비고 |
| --- | --- | --- |
| `reviewed` | 운영자가 "검수 완료" 표시 | 재조판하면 초기화. 발송 완료 전환의 필수 조건 아님 |
| `printDownloaded` | 인쇄용 PDF 일괄 다운로드 기록에서 파생 | 입력 값 아님 |

## 부록 C. 관계 → 호칭 대응표

서버가 `myRelationship`과 받는 분 성별·유형으로 호칭을 정해 질문 문구의 받는 분 자리에 넣는다 (TTL-01~04). 신문 지면에는 호칭을 쓰지 않는다 (답변 속 작성자 표기로만 드러남). 외가 구분은 없다 (V-25).

| 관계 | 여성 받는 분 | 남성 받는 분 | 부부 수신 | 신문 표기 예 |
| --- | --- | --- | --- | --- |
| 손녀 / 손자 | 할머니 | 할아버지 | 할머니·할아버지 | 손녀 지유 |
| 딸 / 아들 | 엄마 | 아빠 | 엄마·아빠 | 딸 은정 |
| 며느리 | 어머님 | 아버님 | 어머님·아버님 | 며느리 수진 |
| 사위 | 장모님 | 장인어른 | 장모님·장인어른 | 사위 민호 |
| 손주며느리 / 손주사위 | 할머니 | 할아버지 | 할머니·할아버지 | 손주며느리 하나 |

호칭 뒤 조사(이/가, 은/는, 을/를)는 받침 유무에 맞게 자동으로 선택한다 (TTL-03).

## 부록 D. 화면별 API

1005 명세의 앱 구조(HOME-04)와 와이어프레임 화면 기준이다. 와이어프레임은 하단 탭이 홈·질문·마이로 그려져 있고 1005 명세는 소식·질문·가족 + 설정이다. 아래 표는 1005 명세의 탭 이름을 쓴다.

| 화면 | 호출하는 API |
| --- | --- |
| 로그인 | `POST /auth/kakao`, `POST /auth/apple` |
| 이름 확인 ~ 가족방 만들기 1/3·2/3·3/3 | 호출 없음 (앱에 임시 보관) |
| 가족 만들기 (마지막 단계) | `POST /groups` → 응답의 `inviteUrl` |
| 가족 생성 후 받는 분 사진 | `POST /uploads/presign` → `PUT /groups/{id}/recipient` |
| 초대 공유 | 응답의 `inviteUrl` 사용 (카카오톡 전송·복사는 클라이언트) |
| 가족 없음 화면 | 호출 없음 (`groups`가 빈 로그인 응답) |
| 초대 링크 열기 | `GET /invites/{token}/check` → (로그인) → `GET /invites/{token}` |
| 합류 확인 → 참여하기 | `POST /invites/{token}/accept` |
| 초대 링크 오류 | `/check`의 `404` |
| 공유 헤더 (가족·호 선택, 상태 줄) | `GET /groups`, `GET /groups/{id}/home`, `GET /groups/{id}/issues` |
| 소식 탭 | `GET /groups/{id}/posts` (선택된 `issueId`) |
| 소식 쓰기 | `POST /uploads/presign` → (스토리지 업로드) → `POST /uploads/{id}/complete` → `POST /groups/{id}/posts` |
| 구성원 프로필 (그 사람의 글만) | `GET /groups/{id}/members/{userId}/posts` |
| 질문카드 탭 | `GET /groups/{id}/questions` (선택된 `issueId`) |
| 답변 쓰기 | `PUT /groups/{id}/questions/{qid}/answer` |
| 답변 모아보기·댓글 | `GET .../answers`, `GET/POST /answers/{id}/comments` |
| 신고 (게시물·답변·댓글의 … 메뉴) | `POST /reports` |
| 구성원 차단 (… 메뉴) | `POST /users/{id}/block` |
| 알림 목록 (종 아이콘) | `GET /notifications`, `POST /notifications/seen`, `POST /notifications/{id}/read` |
| 신문 보기 (완성 전 안내) | 공유 헤더의 `displayState` 사용 |
| 신문 보관함 / 호 목록 | `GET /groups/{id}/issues?displayState=SENT` |
| 완성본 보기 (페이지 넘기기) | `GET /issues/{id}/newsletter` |
| 대기 신청 (마지막 면 다음 장, 상태 줄, 마감 후 안내) | `POST /waitlist` |
| 가족 탭 | `GET /groups/{id}`, `GET /groups/{id}/members`, `GET /groups/{id}/invite-link`, `PATCH /groups/{id}/members/me` |
| 가족 설정 (방장 전용) | `PATCH /groups/{id}`, `GET/PUT /groups/{id}/recipient`, `DELETE .../members/{userId}`, `GET .../removed-members`, `POST .../allow-rejoin` |
| 가족 전환 · 새 가족 만들기 | `GET /groups`, `POST /groups` |
| 설정 > 프로필 | `GET/PATCH /me`, `POST /uploads/presign` |
| 설정 > 내가 차단한 사람 | `GET /me/blocks`, `DELETE /users/{id}/block` |
| 설정 > 정책 링크·문의 | 호출 없음 (앱 고정 값) |
| 로그아웃 | `POST /auth/logout` |
| 탈퇴 | `DELETE /me` |

## 부록 E. 기능명세 ID ↔ API

| 기능명세 | API | 비고 |
| --- | --- | --- |
| ACC-01~06 | 1-1 | ACC-06 권한 요청은 앱 |
| PRF-01~04, TTL-01~04 | 1-2, 2-2, 부록 C | PRF-04(지면 얼굴 사진 안내)는 앱 |
| FAM-01~04 | 2-1 | 마지막에 본 가족은 앱이 기기에 기록 |
| FAM-05~07 | 2-3 | 초대는 구성원 누구나 |
| FAM-08~13 | 2-1, 2-2, 2-4 | FAM-10은 "재합류 허용" |
| RCV-01~03 | 2-1 | 사진은 가족 생성 후 업로드 |
| HOME-01~06 | 3-1, 3-2, 3-4 | HOME-04 탭 구성·HOME-06 시작 전 화면은 앱 |
| POST-01~07 | 3-3, 4-1 | 마감 경계 14분 |
| QST-01~06, 08 | 3-4, 3-5, 5-3 | 질문 풀·출제 스케줄은 데이터 |
| NEWS-01~06 | 6-3 | 조판은 00:15 이후 서버 비동기 작업 |
| PUB-01~03 | 4-2, 6-2, 6-4 | |
| NOTI-01~06 | 5-3, 5-4 | |
| SAFE-01~03 | 5-1, 5-2, 3-3 | |
| SET-01~02 | 5-6 | |
| WAIT-01 | 5-5 | |
| ADM-01~08 | 6-1~6-6 | |
| M-01~13 | 6-6 | M-10(알림 이력)·M-12(열람 기록)는 DB에 이미 있음 |

## 부록 F. 확인이 필요한 항목

### F-1. 1005 명세 기준으로 유저 플로우·와이어프레임 수정이 필요한 항목

개발 기준은 1005 명세다. 유저 플로우와 와이어프레임이 아래와 같이 다른 곳은 화면 수정이 필요하다. 이 문서의 API는 1005 명세를 따랐다.

| 항목 | 1005 명세 | 유저 플로우·와이어프레임 |
| --- | --- | --- |
| 하단 탭 | 소식 · 질문카드 · 가족 + 우상단 설정, 하단 탭은 플로팅 바 (HOME-04) | 홈 · 질문 · 마이 |
| 알림 목록 위치 | 소식·질문 헤더의 종 아이콘, 가족 탭에는 없음 (NOTI-06) | 홈 헤더 |
| 프로필 사진 | 받지 않음. 캐릭터 자동 배정 (PRF-01, PRF-05) | 가입자 정보에 사진 |
| 받는 분 사진 | 받지 않음. 받는 분 캐릭터 (RCV-01) | 받는 분 정보에 사진 |
| 가족방 이름과 신문 제호 | 별개. 가족방 이름은 신문에 실리지 않고 제호 기본값은 `보고잡지` (FAM-02, FAM-03) | 입력 하나 ("신문 제호로도 쓰여요") |
| 가족 만들기 | 한 화면에 한 질문인 3단계 (받는 분 → 배송지 → 이름 짓기), 입력 확인 화면 없음, 실패 처리 규칙 (FAM-01) | 가입 1~4단계 |
| 가입 시 이름 확인 | 이름 확인 화면 후 초대가 있으면 합류 분기, 없으면 가족방 없음 화면 (ACC-01, PRF-01) | 가입자 정보 화면 |
| 시범 종료 선택 | "대기 신청" 버튼 하나, 다음 회차 구독이 없는 가족방의 마지막 호가 발송 완료되면 일괄 노출 (WAIT-01) | 유료 / 무료 / 그만 3지선다 |
| 알림 항목 | 질문 공개, 마감 리마인더, 발송 완료, 방장 변경 (NOTI-06) | "새 소식", "배송 중", "마감 3일 전" 포함 |
| 호 선택 | 호가 1개여도 호 목록이 열리고 이번 호만 표시, 호 목록에 신문 보기 버튼 없음 (HOME-05) | 호 선택 화면 없음 |
| 신문 보기 진입 | 공유 헤더 상태 줄과 발송 완료 알림 (PUB-02) | 신문 보관함에서 호 목록 |
| 질문 답변 현황 | 답변 전에도 누가 답했는지와 아직 답하지 않은 구성원을 캐릭터로 표시 (QST-05) | 반영 없음 |
| 로그인 | 카카오 + 애플. 외부 로그인이 있어 애플 로그인 제공 필수 (ACC-02, App Store 심사 지침 4.8) | 카카오만 |
| 동의 | 요약 동의 + [보기] 웹 페이지(개인정보 처리방침, 이용약관), 법적 문구는 O-40 (ACC-03) | 체크박스 하나 |
| 초대 오류 | "링크를 확인할 수 없어요"(초대 코드를 확인할 수 없는 경우) (FAM-06) | "만료" 오류 화면, "방장에게 새 링크 요청" |
| 생일 | 월·일만 선택 입력, 사용처는 신문의 생일 안내 (PRF-01, NEWS-07) | `YYYY-MM-DD` 입력란 |
| 받는 분 정보 | 성별 필수, 생일 받지 않음 (RCV-01) | 성별 입력란 없음, 생일 입력란 있음 |
| 호칭 표시 | 관계를 고르기 전 화면(로그인 전 우리 가족 확인 등)은 호칭 대신 받는 분 이름 (TTL-01) | 호칭 표시 |

### F-2. 1005 명세에서도 확인이 필요한 항목

| 항목 | 내용 |
| --- | --- |
| 호 번호 | 1005 명세는 테스트를 1호로 정함(POST-07). 와이어프레임은 제1·2·3호. API는 `issueNo`를 파생값으로 제공 |
| 선택형 답변 화면 | 1005 명세는 선택형 위주(QST-02), 와이어프레임은 글 입력 화면만 있음 |
| 관계 선택 위치 | 초대받은 사람은 합류 직전 화면, 방장은 가족방 만들기 1/3 (O-29 결정). 유저 플로우의 위치와 맞추기 |
| 법적 문구 | 개인정보 동의 요약, 받는 분 정보 동의 문구 (O-40) |

### F-3. 확정한 값과 남은 확인 (2026-10-05 23:45 KST, 작업 PC 시계 기준)

팀이 제안안을 그대로 확정했다. 외부 확인이 남은 항목은 `확인 필요`로 표시했다.

| 항목 | 확정 값 | 확인 필요 |
| --- | --- | --- |
| 글자 수·사진 수·파일 크기 (O-05) | 글 180자, 게시물당 사진 10장, 파일 20MB | |
| 저해상도 경고 기준 (O-08) | 짧은 변 1200px 미만 | |
| HEIC | 앱이 JPEG로 변환, 서버는 JPEG·PNG만 | |
| 제호 변경 권한 (O-14) | 방장만 | 기획 |
| 내보낸 사람의 게시물 (O-17) | 마감 전 글은 이번 호에 유지, 이후 작성 불가 | 기획·법무 |
| "할머니께만" 댓글, 신문 댓글 개수 (O-11) | 댓글 불가, 지면 전재는 답변당 최대 5개 | 기획 |
| 신고 사유 (O-24) | 부적절한 내용 / 개인정보 노출 / 광고·스팸 / 기타 | |
| 부부 수신 질문 순서 (O-09) | 첫 주 여성, 둘째 주 남성 | |
| 운영자 인증 (O-23) | 이메일 + 비밀번호, 별도 토큰, IP 제한, 로그인 횟수 제한 | |
| 토큰 | 액세스 15분, 리프레시 30일, 기기당 1개 | |
| 에러 응답 | `code` 문자열 필드 추가 | |
| 마지막에 본 가족 | 기기에만 기록 | |
| 앱을 나갔을 때 작성 중인 글 | 본문만 기기에 임시 저장, 사진은 다시 선택 | |
| 지난 주차 질문 열람 | 이번 주와 같은 규칙 (내가 답한 뒤에 내용 열람) | |
| 업로드 구조 | 업로드 먼저 + 임시 업로드 테이블, "올리기" 누를 때 시작 | |
| 로그인 엔드포인트 | `/auth/kakao`, `/auth/apple` 분리 | |
| 대기 신청 노출 판단 | 다음 호가 없는 가족방의 마지막 호가 발송 완료되면 노출 | |
| 서버 주소 | 미정 | 팀 |

조판 관련 확정 값(판형, 쪽수, 렌더링, 재시도 등)은 [composition-engine-api.md](composition-engine-api.md) 13장에 있다.

## 부록 G. DB 반영 필요 항목 모음

이 문서에서 `DB 반영 필요`로 표시한 항목을 한곳에 모았다. 테이블을 늘리기 전에 이 목록으로 범위를 확인한다. 기준 DB는 upstream/main(`36a76f2`)이고, 그 뒤에 반영된 항목은 표 아래의 반영 현황에 정리했다. DB 구조는 API 설계 중에 바뀔 수 있다. 순서는 [review §3-4](api-spec-review.md)의 반영 순서와 별개이고, 번호는 설명용이다.

| # | 변경 | 근거 (문서 위치) |
| --- | --- | --- |
| 1 | `app_user.email`, `auth_identity`의 이메일 관련 컬럼 제거 | 1-1 로그인 |
| 2 | 탈퇴 처리 함수(가족방별 규칙), 가족방 삭제 경로, 스토리지 파일 삭제 큐 | 1-1 탈퇴 |
| 3 | 캐릭터 저장과 배정 (구성원, 받는 분). 사진 컬럼은 쓰지 않음 | 1-2, 3-3, 조판 입력 |
| 4 | 받는 분을 별도 행으로 분리: `recipient`(가족방당 1~2행: 이름, 성별, 캐릭터)와 `delivery_address`(가족방당 1행, 방장만 등록, `label`·`recipient_phone`·`memo` 제거), 제3자 동의 저장 | 2-1 |
| 5 | 마감 시점 배송지 스냅샷, `print_order` 제거 | 2-1, 6-4 |
| 6 | `family_member.nickname` 제거 | 2-2 |
| 7 | 초대 코드: 가족방당 1개를 다시 보여줄 수 있게 저장, `family_invite`와 방장 전용 트리거 정리 | 2-3 |
| 8 | `media_upload`(업로드 시작 시각 포함), `media_job`(파생본 큐), 삭제 큐, `media_rendition` 크기 기준 | 4-1, [composition-engine-api.md 14장](composition-engine-api.md) |
| 9 | 열람용 페이지 이미지 저장 (`preview` 활용) | 4-2 |
| 10 | `notification_log`: 읽음·열람 상태, `kind`에 방장 변경, 60일 삭제 | 5-4 |
| 11 | 대기 신청: `waitlist_signup.code` 제거, 노출 조건 판단 값 | 5-5 |
| 12 | 호 시작을 운영자 지정(시작·마감 시각)으로: `close_day`·`timezone`·월 자동 생성 배치 정리 | 6-2 |
| 13 | `issue.status`를 6개 내부 상태로 변경, `skipped`·`archived`·`printing` 제거, 전이표 제거, `reviewed_at`·`reviewed_by` | 부록 B, 6-2 |
| 14 | 인쇄용 PDF 일괄 다운로드 기록 (호별) | 6-4 |
| 15 | `post`·`comment` 숨김 컬럼, 신고 처리 `action`, 신고 사유 코드 | 6-5, 5-1 |
| 16 | 멱등 키 저장 (`Idempotency-Key`, 24시간) | 0장 |
| 17 | `refresh_token` 테이블, `operator`의 인증 값 | [ADR-0003](adr/0003-auth-token.md) |
| 18 | `layout_run.retry_after`, 섀도 실행 표시, `placement`가 가리킬 수 있는 요소 종류(제호·캐릭터·질문 코너) 확장 | [composition-engine-api.md 12장](composition-engine-api.md) |

### upstream/main(`36a76f2`) 반영 현황

upstream이 이미 반영한 항목과, 이 설계와 다른 점이다 (2026-10-06 확인, 병합하지 않고 읽기 전용으로 비교).

| 위 번호 | upstream 상태 | 이 설계와의 차이 |
| --- | --- | --- |
| 10 알림 | `notification_log`에 `group_id`, `read_at`, `kind = owner_changed` 추가, 60일 삭제 함수 | 반영됨. 남은 것: 알림 목록을 연 시각(종 아이콘 점 제거용 `seen`)을 저장할 곳이 없음 |
| 8 업로드 | `media.initiated_at` 추가, 마감 후 14분 유예를 `assert_period_open`에 구현 | 부분 반영. **차이**: `initiated_at`을 클라이언트가 보내는 값으로 두어 조작하면 유예를 늘릴 수 있다. 이 설계는 서버가 presign 발급 시각을 기록(`media_upload`)한다. 글보다 먼저 업로드하는 구조도 아님(`media.post_id` 필수) |
| 7 초대 코드 | `family_invite.group_id`가 UNIQUE, `get_or_create_family_invite()` | 부분 반영. **남은 것**: 코드 원문을 저장하지 않아(해시만) 이미 만든 링크를 구성원이 다시 얻을 수 없음 |
| 4 받는 분 | 변경 없음. 사진 컬럼은 선택 입력(1004)으로 유지 | 1005의 캐릭터 대체와 부부 두 분 저장이 반영되지 않음 |
| 13 호 상태 | 변경 없음 (7개 상태, `review → printing` 수동 전환) | 6개 내부 상태 변경은 미반영 |
| 그 외 | 변경 없음 | 1~3, 5~6, 9, 11~12, 14~18번은 모두 미반영 |


## 부록 H. 팀 OpenAPI와의 차이

기준: `docs/openapi.yaml` 0.1.0 (`upstream/api-spec`과 같음, 2026-10-07 재대조). 경로는 기본 경로 `/api/v1`을 뺀 형태다. 이름 규칙은 A안(팀의 `/me/*`를 기준으로 하고 예외를 둠, 2026-10-06 확정)이다. 이전 판에 있던 OpenAPI 항목 중 현재 OpenAPI에 없는 것(overrides, pages/lock, print-orders, newsletter/view, `/media/{id}/upload-url`, `/groups/{id}/blocks`, `PATCH /admin/issues/{id}/status`, `POST /groups/{id}/answers`, `POST /posts/{id}/comments`)은 삭제했다.

### H-1. 이름이 같은 것
`/me`(GET·PATCH·DELETE), `/me/blocks`, `/me/devices`, `/me/devices/{id}`, `/me/notifications`, `/me/notifications/{id}/read`, `/groups/{id}/issues`, `/issues/{id}`, `/issues/{id}/newsletter`, 질문·답변 경로, `/admin/*` 대부분.

### H-2. 이 문서에만 있는 엔드포인트 (OpenAPI에 추가 필요)

| 이 문서 | 필요한 이유 |
| --- | --- |
| `POST /auth/refresh` | OpenAPI에 토큰 재발급이 없다. 없으면 10~15분마다 로그아웃된다 ([ADR-0003](adr/0003-auth-token.md)) |
| `POST /uploads/{uploadId}/complete` | OpenAPI에는 `presign`만 있다. 완료 확인이 없으면 업로드 완료 시각을 서버가 알 수 없어 마감 후 14분 유예를 판단할 수 없다 (G-8) |
| `POST /me/notifications/seen` | 종 아이콘 점 제거. DB에 저장할 곳도 아직 없다 (G-10) |
| `POST /admin/issues/open` | 이번 호 시작을 운영자가 지정한다 (G-12) |
| `GET /admin/user-blocks` | 개인 차단 시 팀에 자동 신고하는 SAFE-02 때문. 필요 없으면 신고 목록 필터로 대체 |
| `GET /groups/{id}/members/{userId}/posts` | 구성원별 글 화면 (WF-프로필) |
| `GET /answers/{id}/comments` | OpenAPI에는 댓글 `POST`만 있고 목록 `GET`이 없다 |

### H-3. OpenAPI에만 있는 엔드포인트 (결정 필요)

| OpenAPI | 판단 |
| --- | --- |
| `GET /groups/{id}/waitlist-status` | 대기 신청 노출 조건(WAIT-01)을 서버가 계산해 준다. 클라이언트 계산을 막을 수 있어 **채택 권장**, 5-5에 추가할 것 |
| `GET /groups/{id}/issues/current` | 이 문서의 `home`과 겹친다. `home`이 호 정보를 포함하면 생략 가능 |
| `GET /groups/{id}/recipients` | 구성원에게 받는 분 이름만 준다 (아래 H-4) |

### H-4. 이름만 다른 것 (하나로 정해야 함)

| 이 문서 | OpenAPI | 제안 |
| --- | --- | --- |
| `GET·PUT /groups/{id}/recipient` (방장) | `GET·PUT /groups/{id}/delivery-address` (방장) + `GET /groups/{id}/recipients` (구성원) | 받는 분과 배송지가 별도 행이 되면(G-4) OpenAPI처럼 둘로 나누는 쪽이 맞다. OpenAPI 이름으로 맞춘다 |
| `GET /admin/groups/{id}/recipient` | `GET /admin/delivery-addresses/{groupId}` | 위 결정을 따라 OpenAPI 이름 |
| `GET /groups/{id}/posts` (조회) | `GET /groups/{id}/feed` | 조회는 `feed`로 맞춘다. 작성 `POST /groups/{id}/posts`는 이미 같다 |
| `GET /invites/{token}/check` + `GET /invites/{token}` | `GET /invites/{token}` 하나 | 응답이 겹치면 하나로 합친다 |
| `PATCH /admin/reports/{id}/resolve` | `PATCH /admin/reports/{id}` | OpenAPI 이름 |
| `GET /admin/metrics.xlsx` | `GET /admin/metrics/export` | OpenAPI 이름 (확장자 대신 `/export`) |
| `GET /admin/print/addresses.xlsx` | 같음 | 위 `metrics`와 규칙이 다르다. `/admin/print/addresses/export`로 통일할지 정한다 |

### H-5. 계약(규칙) 불일치 — 엔드포인트보다 먼저 정해야 함

| 항목 | 이 문서 | OpenAPI | 영향 |
| --- | --- | --- | --- |
| 응답 래퍼 | `{success, status, message, data}` | 래퍼 없이 본문 그대로 | 앱 파싱 코드 전체에 영향. 하나로 정한다 |
| 에러 형식 | `{success:false, status, code, message, errors[]}` | `{code, message}` | 필드별 오류(`errors`)가 OpenAPI에 없다 |
| 목록 응답 | 운영자 `content/totalElements`, 앱 커서 | `{items, nextCursor}` | 운영자 목록 형식 |
| 시각·날짜 | KST(`+09:00`) | UTC(`Z`) | 마감 경계(14분 유예)와 "N월호" 표시가 어긋날 수 있다. NFR-21은 KST |
| 삭제 응답 | `200` + 래퍼 | `204` | 래퍼 결정에 따른다 |
| 공통 헤더 | `Idempotency-Key`, `X-App-Version` | 없음 | OpenAPI에 추가하거나 문서에서 뺀다 |
| 에러 코드 | 19개 표 (0장) | `PERIOD_CLOSED` 등 예시만 | `ISSUE_CLOSED`와 `PERIOD_CLOSED`가 같은 상황이면 이름을 맞춘다 |

### H-6. ERD(DB)와 걸리는 곳

기준: 작업 트리의 `db/migrations`(V001 + R__ 파일). 부록 G의 항목 대부분이 아직 DB에 없다. 구현 전에 API와 DB가 어긋나 막히는 곳은 다음이다.

| API | DB 현재 | 문제 |
| --- | --- | --- |
| `recipients` / `delivery-address` | `delivery_address.recipients`(jsonb, 이름·성별), 전화·주소는 암호화 | 구성원에게 이름만 주는 `recipients`는 jsonb에서 이름만 뽑아 지금도 가능하다. 캐릭터 저장 컬럼은 없다 (G-3) |
| `phase` 6개 상태 | `issue.status` 5개(`collecting, closing, review, sent, skipped`) | 6개 상태는 `layout_run.status`와 합쳐 서버가 계산하는 파생 값으로 두면 DB 변경이 적다. G-13을 컬럼 변경 대신 파생 규칙으로 바꿀지 정한다 |
| `Idempotency-Key` | 저장할 곳 없음 | 테이블이 필요하다 (G-16) |
| `uploads/presign`, `complete` | `media.initiated_at`만 있다 | 서버 발급 시각을 기록할 `media_upload`가 없다 (G-8) |
| `POST /auth/refresh` | `auth_identity.refresh_token_ref`는 카카오·애플 쪽 토큰 참조 | 앱 자체 리프레시 토큰(기기별, 사용 시 교체) 테이블이 없다 (G-17) |
| 초대 링크 재조회 | 코드 해시만 저장 | 링크를 다시 보여줄 수 없다 (G-7) |

본문 표와 요청·응답 예시는 H-4 결정 전이라 이름을 바꾸지 않았다. 이 부록만 갱신했다.
