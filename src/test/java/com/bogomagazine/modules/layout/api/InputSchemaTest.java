package com.bogomagazine.modules.layout.api;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.function.Consumer;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestFactory;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

/** input.json 규격 검사기({@link InputSchema})의 검사. 샘플은 통과하고, 규칙을 하나씩 어긴 입력은 해당 경로로 잡힌다. */
class InputSchemaTest {
    private static final ObjectMapper M = new ObjectMapper();

    private static ObjectNode small() throws IOException {
        try (var in = InputSchemaTest.class.getResourceAsStream("/layout/samples/small.json")) {
            return (ObjectNode) M.readTree(in);
        }
    }

    @TestFactory
    Stream<DynamicTest> 샘플_파일은_규격에_맞는다() throws Exception {
        var dir = Path.of(getClass().getResource("/layout/samples").toURI());
        try (var s = Files.list(dir)) {
            return s.filter(p -> p.toString().endsWith(".json")).sorted().toList().stream()
                    .map(f -> DynamicTest.dynamicTest(f.getFileName().toString(),
                            () -> assertEquals(List.of(), InputSchema.validate(M.readTree(f.toFile())))));
        }
    }

    /** 문서 4장의 예시 JSON이 자기 규격과 맞는지. 문서가 없는 체크아웃에서는 건너뛴다. */
    @Test
    void 문서_4장_예시는_규격에_맞는다() throws IOException {
        var doc = Path.of("docs", "composition-engine-api.md");
        assumeTrue(Files.exists(doc), "docs/composition-engine-api.md 없음");
        var text = Files.readString(doc);
        int sec = text.indexOf("## 4. 입력 계약");
        assumeTrue(sec >= 0, "4장을 찾지 못함");
        var m = Pattern.compile("```json\\n(.*?)```", Pattern.DOTALL).matcher(text);
        assertTrue(m.find(sec), "4장에 json 블록이 없음");
        // 예시의 id는 전부 자리표시자 "uuid"라 겹치므로 서로 다른 값으로 바꾼 뒤 검사한다
        var n = new int[] {0};
        var unique = Pattern.compile("\"id\": \"uuid\"").matcher(m.group(1)).replaceAll(r -> "\"id\": \"id" + (n[0]++) + "\"");
        JsonNode example = M.readTree(unique);
        assertEquals(List.of(), InputSchema.validate(example));
    }

    record Case(String name, String expectedPath, Consumer<ObjectNode> mutate) {
        @Override
        public String toString() {
            return name + " → " + expectedPath;
        }
    }

    static Stream<Arguments> 규칙을_어긴_입력() {
        return Stream.<Case>of(
                new Case("스키마 버전 1", "$.schema_version", r -> r.put("schema_version", 1)),
                new Case("알고리즘 버전 형식 오류", "$.algorithm_version", r -> r.put("algorithm_version", "v1")),
                new Case("seed가 음수", "$.seed", r -> r.put("seed", -1)),
                new Case("알 수 없는 최상위 필드", "$.family_room_name", r -> r.put("family_room_name", "우리집")),
                new Case("필수 필드 누락(posts)", "$.posts", r -> r.remove("posts")),
                new Case("받는 분에 주소(개인정보)", "$.newspaper.recipient.address",
                        r -> ((ObjectNode) r.at("/newspaper/recipient")).put("address", "서울")),
                new Case("받는 분 성별", "$.newspaper.recipient.gender",
                        r -> ((ObjectNode) r.at("/newspaper/recipient")).put("gender", "F")),
                new Case("제호 30자 초과", "$.newspaper.title", r -> ((ObjectNode) r.get("newspaper")).put("title", "가".repeat(31))),
                new Case("본문 글자 최소가 11pt", "$.layout.min_body_pt", r -> ((ObjectNode) r.get("layout")).put("min_body_pt", 11)),
                new Case("쪽수 범위가 4의 배수 아님", "$.layout.page_range",
                        r -> ((ObjectNode) r.get("layout")).putArray("page_range").add(4).add(18)),
                new Case("여백이 판형보다 큼", "$.layout.margin_mm", r -> ((ObjectNode) r.get("layout")).put("margin_mm", 120)),
                new Case("작성자 캐릭터가 비어 있음", "$.posts[0].author.character",
                        r -> ((ObjectNode) r.at("/posts/0/author")).put("character", "")),
                new Case("작성자에 프로필 사진", "$.posts[0].author.photo",
                        r -> ((ObjectNode) r.at("/posts/0/author")).put("photo", "x.jpg")),
                new Case("공개 범위 값 오류", "$.posts[0].visibility", r -> ((ObjectNode) r.get("posts").get(0)).put("visibility", "PRIVATE")),
                new Case("시간대 없는 시각", "$.posts[0].posted_at",
                        r -> ((ObjectNode) r.get("posts").get(0)).put("posted_at", "2026-10-07T19:30:00")),
                new Case("posts가 시간 역순", "$.posts[1].posted_at", r -> {
                    ((ObjectNode) r.get("posts").get(1)).put("posted_at", "2026-10-07T18:00:00+09:00");
                }),
                new Case("id 중복", "$.posts[1].id", r -> ((ObjectNode) r.get("posts").get(1)).put("id", "p1")),
                new Case("사진 크기 0", "$.posts[0].media[0].width", r -> ((ObjectNode) r.at("/posts/0/media/0")).put("width", 0)),
                new Case("초점이 0~1 밖", "$.posts[0].media[0].focal_point.x",
                        r -> ((ObjectNode) r.at("/posts/0/media/0/focal_point")).put("x", 1.5)),
                new Case("중요 영역이 사진 밖", "$.posts[0].media[0].saliency[0]",
                        r -> ((ObjectNode) r.at("/posts/0/media/0/saliency/0")).put("x", 0.9)),
                new Case("답변 없는 코너", "$.question_corners[0].answers",
                        r -> ((ObjectNode) r.get("question_corners").get(0)).putArray("answers")),
                new Case("코너 order가 1 미만", "$.question_corners[0].order",
                        r -> ((ObjectNode) r.get("question_corners").get(0)).put("order", 0)),
                new Case("댓글 필드 누락", "$.question_corners[0].answers[0].comments[0].body",
                        r -> ((ObjectNode) r.at("/question_corners/0/answers/0/comments/0")).remove("body")),
                new Case("없는 날짜의 생일", "$.birthday_notices[0]", r -> r.putArray("birthday_notices").addObject()
                        .put("label", "손자 가상").put("character", "c04").put("month", 2).put("day", 30)),
                new Case("제외 대상 종류 오류", "$.exclusions[0].ref_type",
                        r -> r.putArray("exclusions").addObject().put("ref_type", "media").put("ref_id", "m1"))
        ).map(Arguments::of);
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("규칙을_어긴_입력")
    void 규칙을_어기면_해당_경로로_잡는다(Case c) throws IOException {
        var root = small();
        c.mutate().accept(root);
        var errors = InputSchema.validate(root);
        assertTrue(errors.stream().anyMatch(e -> e.startsWith(c.expectedPath() + ":")),
                () -> c.expectedPath() + " 위반을 못 잡음. 잡은 것: " + errors);
    }
}
