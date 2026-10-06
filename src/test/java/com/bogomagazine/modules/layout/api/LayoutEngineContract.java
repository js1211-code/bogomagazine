package com.bogomagazine.modules.layout.api;

import static com.bogomagazine.modules.layout.api.ComposeOutput.ElementType.*;
import static com.bogomagazine.modules.layout.api.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

import com.bogomagazine.modules.layout.api.ComposeInput.*;
import com.bogomagazine.modules.layout.api.ComposeOutput.*;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.stream.IntStream;
import java.util.stream.Stream;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * 어떤 {@link LayoutEngine} 구현이든 지켜야 하는 계약 (docs/composition-engine-api.md 4~5장, 9장).
 * 실제 엔진을 붙일 때는 이 클래스를 상속해 {@link #engine()}만 구현한다.
 *
 * <p>"무엇이 어디에 놓이는가"는 알고리즘마다 다르므로 여기서 단정하지 않는다. 단정하는 것은
 * 어떤 배치든 참이어야 하는 불변 조건과, 입력 → 결과의 약속(순서·재현성·실패 코드·미배치 기록)이다.
 */
abstract class LayoutEngineContract {

    protected abstract LayoutEngine engine();

    private ComposeOutput compose(ComposeInput in) {
        return engine().compose(in);
    }

    private static void assertClean(ComposeInput in, ComposeOutput out) {
        var violations = OutputInvariants.check(in, out);
        assertTrue(violations.isEmpty(), () -> "불변 조건 위반:\n" + String.join("\n", violations.stream().map(Object::toString).toList()));
    }

    private static List<Element> elements(ComposeOutput out, ComposeOutput.ElementType type) {
        return out.pages().stream().flatMap(p -> p.elements().stream()).filter(e -> e.type() == type).toList();
    }

    /** 경과 시간은 실행마다 달라지므로 재현성 비교에서 뺀다. */
    private static ComposeOutput withoutElapsed(ComposeOutput o) {
        return new ComposeOutput(o.schemaVersion(), o.inputHash(), o.algorithmVersion(), o.seed(), o.score(),
                o.pages(), o.unplaced(), o.warnings(), new Stats(o.stats().pageCount(), o.stats().elements(), 0));
    }

    // --- 불변 조건 -------------------------------------------------------------------------

    @Test
    void 작은_호는_불변_조건을_모두_지킨다() {
        var in = small();
        var out = compose(in);
        assertClean(in, out);
        assertTrue(out.unplaced().isEmpty(), "작은 호는 전부 들어가야 한다: " + out.unplaced());
    }

    @ParameterizedTest(name = "소식 {0}개")
    @ValueSource(ints = {1, 2, 5, 12, 25, 60, 150})
    void 소식_수와_상관없이_불변_조건을_지킨다(int n) {
        var in = manyPosts(n);
        assertClean(in, compose(in));
    }

    @ParameterizedTest(name = "seed {0}")
    @ValueSource(longs = {0, 1, 42, 1894467310L, Long.MAX_VALUE, -7})
    void seed가_달라도_불변_조건을_지킨다(long seed) {
        var in = with(small(), b -> b.seed(seed));
        var out = compose(in);
        assertClean(in, out);
        assertEquals(seed, out.seed());
    }

    // --- 재현성·순서 -----------------------------------------------------------------------

    @Test
    void 같은_입력과_seed는_같은_결과다() {
        var in = small();
        assertEquals(withoutElapsed(compose(in)), withoutElapsed(compose(in)));
    }

    @Test
    void 입력이_다르면_input_hash도_다르다() {
        var a = small();
        var b = with(small(), x -> x.posts(
                List.of(post("p1", 0, Visibility.ALL, GRANDDAUGHTER, "다른 글", photo("m1")))));
        assertEquals(compose(a).inputHash(), compose(a).inputHash());
        assertNotEquals(compose(a).inputHash(), compose(b).inputHash());
    }

    @Test
    void 소식은_입력_순서대로_놓인다() {
        var in = manyPosts(10);
        var out = compose(in);
        var placedOrder = new ArrayList<String>();
        out.pages().forEach(pg -> pg.elements().stream().filter(e -> e.type() == POST_TEXT)
                .sorted(Comparator.comparingDouble(Element::y)).forEach(e -> placedOrder.add(e.ref().id())));
        var inputOrder = in.posts().stream().map(Post::id).filter(placedOrder::contains).toList();
        assertEquals(inputOrder, placedOrder, "엔진이 입력의 정렬(posted_at 오름차순)을 바꾸면 안 된다");
    }

    @Test
    void 질문_코너는_코너_순서대로_놓인다() {
        var base = small();
        var second = corner(3, "q3", "가족 이야기", "우리 가족의 자랑거리는?",
                answer("a3", 50, Visibility.ALL, DAUGHTER, "다 같이 모이는 명절이요", List.of(), List.of()));
        var in = with(base, b -> b.corners(List.of(base.questionCorners().get(0), second)));
        var out = compose(in);
        assertClean(in, out);
        var order = new ArrayList<String>();
        out.pages().forEach(pg -> pg.elements().stream().filter(e -> e.type() == CORNER_TITLE)
                .sorted(Comparator.comparingDouble(Element::y)).forEach(e -> order.add(e.ref().id())));
        assertEquals(List.of("q1", "q3"), order);
    }

    // --- 개별 약속 -------------------------------------------------------------------------

    @Test
    void 할머니께만_글은_지면에_싣고_표시한다() {
        var in = small();
        var out = compose(in);
        var p2Text = elements(out, POST_TEXT).stream().filter(e -> e.ref().id().equals("p2")).findFirst().orElseThrow();
        var p2Photos = elements(out, POST_PHOTO).stream().filter(e -> e.ref().id().equals("m2") || e.ref().id().equals("m3")).toList();
        var p1Text = elements(out, POST_TEXT).stream().filter(e -> e.ref().id().equals("p1")).findFirst().orElseThrow();
        assertTrue(p2Text.recipientOnly());
        assertEquals(2, p2Photos.size());
        assertTrue(p2Photos.stream().allMatch(Element::recipientOnly));
        assertFalse(p1Text.recipientOnly());
    }

    @Test
    void 해상도가_모자란_사진도_자동으로_빼지_않고_경고한다() {
        var tiny = photo("small", 600, 450); // 약 180mm 슬롯에서 150dpi 안팎
        var in = with(small(), b -> b.posts(List.of(
                post("p1", 0, Visibility.ALL, GRANDDAUGHTER, "작은 사진", tiny),
                post("p2", 5, Visibility.ALL, DAUGHTER, "큰 사진", photo("big")))));
        var out = compose(in);
        assertClean(in, out);
        assertTrue(out.warnings().stream().anyMatch(w -> w.code().equals(Codes.LOW_RES) && "small".equals(w.refId())));
        assertTrue(out.warnings().stream().noneMatch(w -> w.code().equals(Codes.LOW_RES) && "big".equals(w.refId())));
        assertTrue(elements(out, POST_PHOTO).stream().anyMatch(e -> e.ref().id().equals("small")));
    }

    @Test
    void 내용이_적어도_쪽수를_4배수와_최소_쪽수로_채운다() {
        var in = with(small(), b -> b.posts(List.of(post("p1", 0, Visibility.ALL, SON, "한 줄"))).corners(List.of()));
        var out = compose(in);
        assertClean(in, out);
        assertEquals(4, out.pages().size());
        assertEquals(3, out.warnings().stream().filter(w -> w.code().equals(Codes.PAGE_PADDED)).count());

        var in8 = with(in, b -> b.layout(new Layout(210, 297, 15, 3, 12, 300, 4, 8, 16)));
        assertEquals(8, compose(in8).pages().size());
    }

    @Test
    void 넘치면_최대_쪽수에서_멈추고_못_넣은_것은_사유와_함께_남긴다() {
        var in = manyPosts(150);
        var out = compose(in);
        assertClean(in, out);
        assertEquals(16, out.pages().size());
        assertFalse(out.unplaced().isEmpty());
        assertTrue(out.unplaced().stream().allMatch(u -> u.reason().equals(Codes.PAGE_LIMIT)));
        assertTrue(out.unplaced().stream().anyMatch(u -> u.refType().equals("post")));
        assertTrue(out.score().total() < 1, "못 넣은 게 있으면 점수가 1일 수 없다");
    }

    @Test
    void 한_면보다_큰_소식은_미배치로_남기고_나머지는_계속_놓는다() {
        var photos = IntStream.range(0, 12).mapToObj(i -> photo("big" + i)).toArray(Media[]::new);
        var in = with(small(), b -> b.posts(List.of(
                post("p1", 0, Visibility.ALL, GRANDDAUGHTER, "정상 글"),
                post("huge", 5, Visibility.ALL, DAUGHTER, "사진이 너무 많은 글", photos),
                post("p3", 9, Visibility.ALL, SON, "그 다음 글"))).corners(List.of()));
        var out = compose(in);
        assertClean(in, out);
        assertEquals(13, out.unplaced().size(), "글 1개와 사진 12장");
        assertTrue(out.unplaced().stream().allMatch(u -> u.reason().equals(Codes.NO_SLOT_FIT)));
        assertTrue(elements(out, POST_TEXT).stream().anyMatch(e -> e.ref().id().equals("p3")));
    }

    @Test
    void 답변이_없는_질문은_코너를_만들지_않는다() {
        var in = small();
        var out = compose(in);
        assertTrue(elements(out, CORNER_TITLE).stream().noneMatch(e -> e.ref().id().equals("q2")));
        assertTrue(elements(out, QUESTION_TEXT).stream().noneMatch(e -> e.ref().id().equals("q2")));
    }

    @Test
    void 제호는_신문_제호를_쓴다() {
        var in = small();
        var heading = elements(compose(in), MASTHEAD);
        assertEquals(1, heading.size());
        assertEquals(in.newspaper().title(), heading.get(0).text());
    }

    @Test
    void 생일_안내_입력은_받아도_실패하지_않는다() {
        var in = with(small(), b -> b.birthdays(List.of(new BirthdayNotice("손자 민준", "c02", 10, 21))));
        assertClean(in, compose(in));
    }

    // --- 샘플 입력 파일 ---------------------------------------------------------------------

    /**
     * src/test/resources/layout/samples/*.json (커밋되는 가짜 데이터)과 testdata/private/*.json
     * (로컬 전용, 커밋 금지, 없으면 건너뜀)를 읽어 파일마다 불변 조건을 검사한다.
     * 실패 메시지에는 파일 이름과 요소 id만 나오고 본문·이름은 찍지 않는다.
     */
    @TestFactory
    Stream<DynamicTest> 샘플_입력_파일은_불변_조건을_지킨다() throws Exception {
        var files = new ArrayList<Path>();
        files.addAll(jsonFiles(Path.of(getClass().getResource("/layout/samples").toURI())));
        files.addAll(jsonFiles(Path.of("testdata", "private")));
        return files.stream().map(f -> DynamicTest.dynamicTest(f.getFileName().toString(), () -> {
            var in = InputJson.read(f);
            assertClean(in, compose(in));
        }));
    }

    private static List<Path> jsonFiles(Path dir) throws IOException {
        if (!Files.isDirectory(dir)) return List.of();
        try (var s = Files.list(dir)) {
            return s.filter(p -> p.toString().endsWith(".json")).sorted().toList();
        }
    }

    // --- 실패 ------------------------------------------------------------------------------

    @Test
    void 내용이_하나도_없으면_no_content로_실패한다() {
        var empty = with(small(), b -> b.posts(List.of()).corners(List.of(
                corner(1, "q2", "요즘 이야기", "요즘 즐겨 드시는 간식은?"))));
        var e = assertThrows(ComposeException.class, () -> compose(empty));
        assertEquals(ComposeException.NO_CONTENT, e.code());
        assertTrue(e.getMessage().startsWith("no_content"), "p_error 앞 단어가 코드여야 한다");
    }

    @Test
    void 스키마_버전이_다르면_input_invalid로_실패한다() {
        var e = assertThrows(ComposeException.class, () -> compose(with(small(), b -> b.schemaVersion(1))));
        assertEquals(ComposeException.INPUT_INVALID, e.code());
    }

    @Test
    void 캐릭터가_없는_작성자는_input_invalid로_실패한다() {
        var bad = with(small(), b -> b.posts(List.of(
                post("p1", 0, Visibility.ALL, new Person("손녀 보민", null), "글"))));
        assertEquals(ComposeException.INPUT_INVALID,
                assertThrows(ComposeException.class, () -> compose(bad)).code());
    }

    @Test
    void 크기가_0인_사진은_input_invalid로_실패한다() {
        var bad = with(small(), b -> b.posts(List.of(
                post("p1", 0, Visibility.ALL, SON, "글", photo("m1", 0, 3024)))));
        assertEquals(ComposeException.INPUT_INVALID,
                assertThrows(ComposeException.class, () -> compose(bad)).code());
    }
}
