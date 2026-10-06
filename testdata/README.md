# 테스트 데이터

| 위치 | 커밋 | 내용 |
| --- | --- | --- |
| `src/test/resources/layout/samples/*.json` | O | 엔진 입력(`input.json`, schema_version 2) 샘플. **이름·캐릭터·본문은 전부 가짜**, 사진은 크기·초점 메타데이터만 있고 파일은 없다 |
| `testdata/private/*.json` | **X** (`.gitignore`) | 실제 사진·가족 데이터로 로컬에서만 돌려 보는 입력 |

`./gradlew test`(또는 Docker)가 두 위치의 `*.json`을 모두 읽어 파일마다 불변 조건을 검사한다. `testdata/private/`가 없으면 건너뛴다.

## 실제 사진으로 테스트할 때

1. 사진 파일 자체는 엔진 입력에 들어가지 않는다. 엔진은 가로·세로 픽셀, 초점(`focal_point`), 중요 영역(`saliency`)만 쓴다.
   `testdata/private/my.json`에 `small.json`과 같은 모양으로 `media[]`를 채운다 (`key`는 아무 문자열).
2. 실행: `./gradlew test` 또는 `docker compose -f docker-compose.enginetest.yml run --rm test`.
3. **커밋하지 않는다.** 사진(`*.jpg` 등)과 실제 이름·본문이 든 JSON은 `testdata/private/`에만 둔다.
   커밋 전에 `git status`로 이 폴더가 목록에 없는지 확인하고, 훅(gitleaks)이 막지 못하는 개인정보는 사람이 확인한다.
