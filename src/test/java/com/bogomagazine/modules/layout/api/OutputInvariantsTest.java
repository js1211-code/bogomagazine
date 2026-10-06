package com.bogomagazine.modules.layout.api;

import static com.bogomagazine.modules.layout.api.ComposeOutput.ElementType.*;
import static com.bogomagazine.modules.layout.api.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

import com.bogomagazine.modules.layout.api.ComposeOutput.*;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.function.UnaryOperator;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

/**
 * 검사기 자체의 검사. 올바른 출력은 통과시키고, 규칙 하나씩을 일부러 어긴 출력은 그 규칙 이름으로 잡아내야 한다.
 * (검사기가 항상 "문제 없음"을 돌려주는 가짜가 되는 것을 막는다.)
 */
class OutputInvariantsTest {

    private static final ComposeInput IN = small();
    private static final ComposeOutput GOOD = new ReferenceLayoutEngine().compose(IN);

    @Test
    void 올바른_출력은_위반이_없다() {
        assertEquals(List.of(), OutputInvariants.check(IN, GOOD));
    }

    record Case(String name, String expectedRule, Function<ComposeOutput, ComposeOutput> mutate) {
        @Override
        public String toString() {
            return name + " → " + expectedRule;
        }
    }

    static Stream<Arguments> 규칙을_어긴_출력() {
        return Stream.of(
                new Case("마지막 면을 지워 쪽수가 4의 배수가 아님", "PAGE_COUNT",
                        o -> restat(pages(o, ps -> ps.subList(0, ps.size() - 1)))),
                new Case("쪽 번호가 건너뜀", "PAGE_NUMBERING",
                        o -> pages(o, ps -> { var c = new ArrayList<>(ps); c.set(1, new Page(7, ps.get(1).elements())); return c; })),
                new Case("제호 문구가 다름", "MASTHEAD",
                        o -> mapEl(o, is(MASTHEAD), e -> text(e, "우리집 가족방"))),
                new Case("받는 분 캐릭터가 사라짐", "MASTHEAD",
                        o -> restat(removeEl(o, is(RECIPIENT_CHARACTER)))),
                new Case("요소가 재단선 밖", "BOUNDS",
                        o -> mapEl(o, firstOf(POST_TEXT), e -> box(e, 300, e.y(), e.w(), e.h()))),
                new Case("글이 안전 여백을 침범", "SAFE_AREA",
                        o -> mapEl(o, firstOf(POST_TEXT), e -> box(e, 5, e.y(), e.w(), e.h()))),
                new Case("같은 z끼리 겹침", "OVERLAP",
                        o -> mapEl(o, firstOf(POST_PHOTO), e -> box(e, 15, 15, 100, 100))),
                new Case("본문 글자가 11pt", "MIN_FONT",
                        o -> mapEl(o, firstOf(POST_TEXT), e -> font(e, 11, 18))),
                new Case("소식 글이 사라졌는데 미배치에도 없음", "CONSERVATION",
                        o -> restat(removeEl(o, e -> e.type() == POST_TEXT && e.ref().id().equals("p3")))),
                new Case("사진이 지면과 미배치 양쪽에 있음", "CONSERVATION",
                        o -> unplaced(o, new Unplaced("media", "m1", "page_limit"))),
                new Case("입력에 없는 소식을 참조", "UNKNOWN_REF",
                        o -> unplaced(o, new Unplaced("post", "ghost", "page_limit"))),
                new Case("미배치에 사유가 없음", "UNPLACED_REASON",
                        o -> unplaced(o, new Unplaced("post", "p1", " "))),
                new Case("작성자 캐릭터가 사라짐", "AUTHOR_PAIR",
                        o -> restat(removeEl(o, e -> e.type() == AUTHOR_CHARACTER && e.ref().id().equals("p1")))),
                new Case("작성자 표기가 다른 사람", "AUTHOR_PAIR",
                        o -> mapEl(o, e -> e.type() == AUTHOR_LABEL && e.ref().id().equals("p1"), e -> text(e, "남편 영수"))),
                new Case("할머니께만 글의 표시가 빠짐", "RECIPIENT_ONLY",
                        o -> mapEl(o, e -> e.type() == POST_TEXT && e.ref().id().equals("p2"), e -> recipientOnly(e, false))),
                new Case("전체 공개 글에 표시가 붙음", "RECIPIENT_ONLY",
                        o -> mapEl(o, e -> e.type() == POST_TEXT && e.ref().id().equals("p1"), e -> recipientOnly(e, true))),
                new Case("사진 crop이 범위를 벗어남", "CROP_RANGE",
                        o -> mapEl(o, firstOf(POST_PHOTO), e -> crop(e, new Crop(0.5, 0, 1, 1)))),
                new Case("사진이 늘어남(crop 비율 ≠ 슬롯 비율)", "CROP_ASPECT",
                        o -> mapEl(o, firstOf(POST_PHOTO), e -> crop(e, new Crop(0, 0, 1, 1)))),
                new Case("저해상도 경고가 불필요하게 붙음", "LOW_RES",
                        o -> warn(o, new Warning(Codes.LOW_RES, "m1", 1, Map.of()))),
                new Case("중요 영역이 잘리는데 경고 없음", "CROP_SALIENCY",
                        o -> mapEl(o, firstOf(POST_PHOTO), e -> crop(e, new Crop(0, 0.7, 0.3, 0.2)))), // 비율은 슬롯과 같지만 중요 영역(0.3,0.2,0.4,0.5)을 벗어남
                new Case("빈 면에 경고가 없음", "EMPTY_PAGE",
                        o -> new ComposeOutput(o.schemaVersion(), o.inputHash(), o.algorithmVersion(), o.seed(), o.score(),
                                o.pages(), o.unplaced(),
                                o.warnings().stream().filter(w -> !w.code().equals(Codes.PAGE_PADDED)).toList(), o.stats())),
                new Case("정의되지 않은 경고 코드", "WARNING_CODE",
                        o -> warn(o, new Warning("something_new", null, null, Map.of()))),
                new Case("stats.page_count 불일치", "STATS",
                        o -> new ComposeOutput(o.schemaVersion(), o.inputHash(), o.algorithmVersion(), o.seed(), o.score(),
                                o.pages(), o.unplaced(), o.warnings(), new Stats(99, o.stats().elements(), 0))),
                new Case("seed가 입력과 다름", "ECHO",
                        o -> new ComposeOutput(o.schemaVersion(), o.inputHash(), o.algorithmVersion(), o.seed() + 1, o.score(),
                                o.pages(), o.unplaced(), o.warnings(), o.stats())),
                new Case("점수가 1을 넘음", "SCORE",
                        o -> new ComposeOutput(o.schemaVersion(), o.inputHash(), o.algorithmVersion(), o.seed(),
                                new Score(1.5, o.score().parts()), o.pages(), o.unplaced(), o.warnings(), o.stats())),
                new Case("답변 없는 질문의 코너가 만들어짐", "CORNER",
                        o -> mapPage(o, 1, els -> {
                            var c = new ArrayList<>(els);
                            c.add(new Element("x1", CORNER_TITLE, new Ref("question", "q2"), "요즘 이야기", null,
                                    15, 280, 180, 8, 0, new Font(14, 20), null, false));
                            return c;
                        }))
        ).map(Arguments::of);
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("규칙을_어긴_출력")
    void 규칙을_어기면_해당_규칙으로_잡는다(Case c) {
        var violations = OutputInvariants.check(IN, c.mutate().apply(GOOD));
        assertTrue(violations.stream().anyMatch(v -> v.rule().equals(c.expectedRule())),
                () -> c.expectedRule() + " 위반을 못 잡음. 잡은 것: " + violations);
    }

    // --- 출력을 조금씩 바꾸는 도우미 ---------------------------------------------------------

    private static Predicate<Element> is(ComposeOutput.ElementType t) {
        return e -> e.type() == t;
    }

    /** GOOD에서 해당 종류의 첫 요소만 고르는 조건 (id로 구분) */
    private static Predicate<Element> firstOf(ComposeOutput.ElementType t) {
        String id = GOOD.pages().stream().flatMap(p -> p.elements().stream())
                .filter(e -> e.type() == t).findFirst().orElseThrow().id();
        return e -> e.id().equals(id);
    }

    private static ComposeOutput pages(ComposeOutput o, UnaryOperator<List<Page>> f) {
        return new ComposeOutput(o.schemaVersion(), o.inputHash(), o.algorithmVersion(), o.seed(), o.score(),
                f.apply(o.pages()), o.unplaced(), o.warnings(), o.stats());
    }

    private static ComposeOutput mapPage(ComposeOutput o, int pageNo, UnaryOperator<List<Element>> f) {
        return restat(pages(o, ps -> ps.stream()
                .map(p -> p.pageNo() == pageNo ? new Page(p.pageNo(), f.apply(p.elements())) : p).toList()));
    }

    private static ComposeOutput mapEl(ComposeOutput o, Predicate<Element> which, UnaryOperator<Element> f) {
        return pages(o, ps -> ps.stream().map(p -> new Page(p.pageNo(),
                p.elements().stream().map(e -> which.test(e) ? f.apply(e) : e).toList())).toList());
    }

    private static ComposeOutput removeEl(ComposeOutput o, Predicate<Element> which) {
        return pages(o, ps -> ps.stream().map(p -> new Page(p.pageNo(),
                p.elements().stream().filter(e -> !which.test(e)).toList())).toList());
    }

    /** 요소 수·쪽수가 바뀐 뒤 stats를 맞춰, 의도한 규칙 하나만 어긋나게 한다. */
    private static ComposeOutput restat(ComposeOutput o) {
        int n = o.pages().stream().mapToInt(p -> p.elements().size()).sum();
        return new ComposeOutput(o.schemaVersion(), o.inputHash(), o.algorithmVersion(), o.seed(), o.score(),
                o.pages(), o.unplaced(), o.warnings(), new Stats(o.pages().size(), n, 0));
    }

    private static ComposeOutput unplaced(ComposeOutput o, Unplaced u) {
        var list = new ArrayList<>(o.unplaced());
        list.add(u);
        return new ComposeOutput(o.schemaVersion(), o.inputHash(), o.algorithmVersion(), o.seed(), o.score(),
                o.pages(), list, o.warnings(), o.stats());
    }

    private static ComposeOutput warn(ComposeOutput o, Warning w) {
        var list = new ArrayList<>(o.warnings());
        list.add(w);
        return new ComposeOutput(o.schemaVersion(), o.inputHash(), o.algorithmVersion(), o.seed(), o.score(),
                o.pages(), o.unplaced(), list, o.stats());
    }

    private static Element text(Element e, String t) {
        return new Element(e.id(), e.type(), e.ref(), t, e.character(), e.x(), e.y(), e.w(), e.h(), e.z(), e.font(), e.crop(), e.recipientOnly());
    }

    private static Element box(Element e, double x, double y, double w, double h) {
        return new Element(e.id(), e.type(), e.ref(), e.text(), e.character(), x, y, w, h, e.z(), e.font(), e.crop(), e.recipientOnly());
    }

    private static Element font(Element e, double size, double leading) {
        return new Element(e.id(), e.type(), e.ref(), e.text(), e.character(), e.x(), e.y(), e.w(), e.h(), e.z(), new Font(size, leading), e.crop(), e.recipientOnly());
    }

    private static Element crop(Element e, Crop c) {
        return new Element(e.id(), e.type(), e.ref(), e.text(), e.character(), e.x(), e.y(), e.w(), e.h(), e.z(), e.font(), c, e.recipientOnly());
    }

    private static Element recipientOnly(Element e, boolean ro) {
        return new Element(e.id(), e.type(), e.ref(), e.text(), e.character(), e.x(), e.y(), e.w(), e.h(), e.z(), e.font(), e.crop(), ro);
    }
}
