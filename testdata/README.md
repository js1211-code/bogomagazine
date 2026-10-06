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

## 사진 폴더에서 input.json 만들기

```bash
./gradlew photoInput --args="<사진 폴더>"
```

기본 출력은 `testdata/private/input.json`(커밋되지 않는 위치)이다. 옵션은 `--args="<폴더> --title 제호 --seed 7 --recipient-only 2,5 --authors '손녀 보민:c03,딸 은정:c05'"` 처럼 덧붙인다.
`--out`으로 다른 파일을 지정할 수 있고, 이미 있으면 `--force`가 필요하다.

| 폴더 구조 | 결과 |
| --- | --- |
| `photos/a.jpg` | 소식 1개 (옆에 `a.txt`가 있으면 그 내용이 본문, 없으면 "(설명 없음)") |
| `photos/여행/1.jpg, 2.jpg` | 소식 1개에 사진 2장 (`여행/post.txt`가 본문) |

- 소식은 촬영 시각(EXIF `DateTimeOriginal`, 없으면 파일 수정 시각) 순으로 정렬한다. EXIF 회전은 반영해 가로·세로를 기록한다.
- 읽는 형식은 jpg, png, gif, bmp. **HEIC는 건너뛰므로 JPEG로 변환해서** 넣는다. 건너뛴 파일은 실행 결과에 나온다.
- 초점은 사진 중앙 `(0.5, 0.5)`, 중요 영역(`saliency`)은 빈 목록이다. 얼굴·피사체 자동 감지는 없으므로 `crop_cuts_saliency` 경고는 실제 사진에서는 나오지 않는다. 필요하면 JSON을 직접 고친다.
- 사진 파일은 읽기만 하고 복사하지 않으며, 파일 이름은 JSON에 넣지 않는다 (`key`는 `local/p1/m1/original` 같은 가짜 값).
- 만든 직후 규격 검사(`InputSchema`)를 돌려 위반이 있으면 목록을 출력하고 실패한다.
- Windows에서 한글 경로가 깨지면 영문 경로로 옮기거나 Docker로 실행한다.

규격: `InputSchema`가 문서 4장의 필드 규칙을 검사한다. 허용되지 않는 필드(받는 분의 주소·성별, 작성자의 프로필 사진 등)도 오류로 잡는다.
