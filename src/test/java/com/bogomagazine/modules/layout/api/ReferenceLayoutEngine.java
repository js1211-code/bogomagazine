package com.bogomagazine.modules.layout.api;

import static com.bogomagazine.modules.layout.api.ComposeOutput.ElementType.*;

import com.bogomagazine.modules.layout.api.ComposeInput.*;
import com.bogomagazine.modules.layout.api.ComposeOutput.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.function.BiFunction;

/**
 * 테스트용 기준 엔진: 세로로 차곡차곡 쌓는 가장 단순한 조판. 실제 알고리즘(v0.1)이 아니다.
 *
 * <p>두 가지 용도다. (1) {@link OutputInvariants} 검사기가 "어떤 올바른 엔진의 출력"을 통과시키고
 * 일부러 망가뜨린 출력은 잡아내는지 확인하는 기준선. (2) 실제 엔진이 생기면 {@link LayoutEngineContract}를
 * 상속한 테스트 한 줄로 같은 검사를 붙이기 위한 자리. 점수 최적화, 사진 배치 요령, 글 줄바꿈의 정확도는
 * 다루지 않는다 (글자 수로 줄 수를 어림한다).
 */
final class ReferenceLayoutEngine implements LayoutEngine {
    private static final double MM_PER_PT = 25.4 / 72;
    private static final double GAP = 4;

    @Override
    public ComposeOutput compose(ComposeInput in) {
        long t0 = System.nanoTime();
        validate(in);
        return new Run(in).compose(t0);
    }

    private static void validate(ComposeInput in) {
        if (in.schemaVersion() != ComposeInput.SCHEMA_VERSION)
            throw new ComposeException(ComposeException.INPUT_INVALID, "schema_version " + in.schemaVersion());
        var l = in.layout();
        if (l.trimWidthMm() <= 0 || l.trimHeightMm() <= 0 || l.marginMm() < 0 || l.pageMultiple() <= 0
                || l.minPages() <= 0 || l.maxPages() < l.minPages() || l.minPages() % l.pageMultiple() != 0)
            throw new ComposeException(ComposeException.INPUT_INVALID, "layout 값이 올바르지 않음");
        boolean any = !in.posts().isEmpty();
        for (Post p : in.posts()) {
            person(p.author());
            p.media().forEach(ReferenceLayoutEngine::media);
        }
        for (QuestionCorner qc : in.questionCorners())
            for (Answer a : qc.answers()) {
                any = true;
                person(a.author());
                a.media().forEach(ReferenceLayoutEngine::media);
                a.comments().forEach(c -> person(c.author()));
            }
        if (!any) throw new ComposeException(ComposeException.NO_CONTENT, "게시물과 답변이 하나도 없음");
    }

    private static void person(Person p) {
        if (p == null || p.label() == null || p.label().isBlank() || p.character() == null || p.character().isBlank())
            throw new ComposeException(ComposeException.INPUT_INVALID, "작성자 표기와 캐릭터는 항상 있어야 함");
    }

    private static void media(Media m) {
        if (m.width() <= 0 || m.height() <= 0)
            throw new ComposeException(ComposeException.INPUT_INVALID, "사진 크기가 0 이하: " + m.id());
    }

    // --- 실행 ---------------------------------------------------------------------------------

    private record Built(List<Element> elements, double height, List<Warning> warnings) {}

    /** 한 번에 같은 면에 놓이는 덩어리. refs는 못 넣었을 때 unplaced로 남길 대상이다. */
    private record Card(List<Ref> refs, BiFunction<Integer, Double, Built> build) {}

    private static final class Run {
        final ComposeInput in;
        final Layout l;
        final double left, width, top, bottom;
        final List<List<Element>> pages = new ArrayList<>();
        final List<Unplaced> unplaced = new ArrayList<>();
        final List<Warning> warnings = new ArrayList<>();
        int seq, totalRefs, rejectedRefs;
        double cursor;
        boolean limitHit;

        Run(ComposeInput in) {
            this.in = in;
            this.l = in.layout();
            this.left = l.marginMm();
            this.width = l.trimWidthMm() - 2 * l.marginMm();
            this.top = l.marginMm();
            this.bottom = l.trimHeightMm() - l.marginMm();
        }

        ComposeOutput compose(long t0) {
            newPage();
            var first = pages.get(0);
            first.add(el("", MASTHEAD, null, in.newspaper().title(), null,
                    left, top, width, 25, 0, new Font(36, 44), null, false));
            first.add(el("", RECIPIENT_CHARACTER, null, null, in.newspaper().recipient().character(),
                    left + width - 30, top, 30, 30, 1, null, null, false));
            cursor = top + 30 + GAP + 1;
            seqIds(first);

            for (Post p : in.posts()) add(postCard(p));
            for (QuestionCorner qc : in.questionCorners()) {
                if (qc.answers().isEmpty()) continue; // 답변이 없는 질문은 코너를 만들지 않는다 (NEWS-03)
                add(titleCard(qc.question()));
                for (Answer a : qc.answers()) {
                    add(answerCard(a));
                    boolean ro = a.visibility() == Visibility.RECIPIENT_ONLY;
                    for (Comment c : a.comments()) add(commentCard(c, ro));
                }
            }
            pad();

            var outPages = new ArrayList<Page>();
            int elements = 0;
            for (int i = 0; i < pages.size(); i++) {
                outPages.add(new Page(i + 1, List.copyOf(pages.get(i))));
                elements += pages.get(i).size();
            }
            double placedRatio = totalRefs == 0 ? 1 : (double) (totalRefs - rejectedRefs) / totalRefs;
            return new ComposeOutput(
                    ComposeInput.SCHEMA_VERSION, hash(in), in.algorithmVersion(), in.seed(),
                    new Score(placedRatio, Map.of("placed", placedRatio, "order", 1.0)),
                    outPages, List.copyOf(unplaced), List.copyOf(warnings),
                    new Stats(outPages.size(), elements, (System.nanoTime() - t0) / 1_000_000));
        }

        // 배치 ----------------------------------------------------------------------------

        void add(Card c) {
            totalRefs += c.refs().size();
            if (limitHit) {
                reject(c, Codes.PAGE_LIMIT);
                return;
            }
            Built probe = c.build().apply(1, 0.0);
            if (probe.height() > bottom - top) {
                reject(c, Codes.NO_SLOT_FIT);
                return;
            }
            if (cursor + probe.height() > bottom + 1e-9) {
                if (pages.size() >= l.maxPages()) {
                    limitHit = true;
                    reject(c, Codes.PAGE_LIMIT);
                    return;
                }
                newPage();
                cursor = top;
            }
            Built b = c.build().apply(pages.size(), cursor);
            var page = pages.get(pages.size() - 1);
            page.addAll(b.elements());
            seqIds(page);
            warnings.addAll(b.warnings());
            cursor += b.height() + GAP;
        }

        void reject(Card c, String reason) {
            for (Ref r : c.refs()) unplaced.add(new Unplaced(r.type(), r.id(), reason));
            rejectedRefs += c.refs().size();
        }

        void newPage() {
            pages.add(new ArrayList<>());
        }

        /** 아직 id가 없는("") 요소에 순번 id를 붙인다. */
        void seqIds(List<Element> page) {
            for (int i = 0; i < page.size(); i++) {
                Element e = page.get(i);
                if (e.id().isEmpty())
                    page.set(i, new Element("e" + (++seq), e.type(), e.ref(), e.text(), e.character(),
                            e.x(), e.y(), e.w(), e.h(), e.z(), e.font(), e.crop(), e.recipientOnly()));
            }
        }

        /** 쪽수를 page_multiple의 배수, 최소 쪽수 이상으로 맞춘다. 채운 면마다 page_padded 경고. */
        void pad() {
            int mult = l.pageMultiple();
            int cap = l.maxPages() / mult * mult;
            int target = Math.min(cap, Math.max(l.minPages(), (pages.size() + mult - 1) / mult * mult));
            while (pages.size() < target) {
                newPage();
                warnings.add(new Warning(Codes.PAGE_PADDED, null, pages.size(), Map.of()));
            }
        }

        // 덩어리 만들기 --------------------------------------------------------------------

        Card postCard(Post p) {
            var refs = new ArrayList<Ref>(List.of(new Ref("post", p.id())));
            p.media().forEach(m -> refs.add(new Ref("media", m.id())));
            boolean ro = p.visibility() == Visibility.RECIPIENT_ONLY;
            return new Card(refs, (page, y) -> content(page, y, new Ref("post", p.id()), p.author(),
                    POST_PHOTO, POST_TEXT, p.media(), p.body(), ro));
        }

        Card answerCard(Answer a) {
            var refs = new ArrayList<Ref>(List.of(new Ref("answer", a.id())));
            a.media().forEach(m -> refs.add(new Ref("media", m.id())));
            boolean ro = a.visibility() == Visibility.RECIPIENT_ONLY;
            String text = (a.option() == null ? "" : "[" + a.option() + "] ") + a.body();
            return new Card(refs, (page, y) -> content(page, y, new Ref("answer", a.id()), a.author(),
                    ANSWER_PHOTO, ANSWER_TEXT, a.media(), text, ro));
        }

        Card commentCard(Comment c, boolean ro) {
            return new Card(List.of(new Ref("comment", c.id())), (page, y) -> content(page, y,
                    new Ref("comment", c.id()), c.author(), null, COMMENT_TEXT, List.of(), c.body(), ro));
        }

        Card titleCard(Question q) {
            Ref ref = new Ref("question", q.id());
            return new Card(List.of(), (page, y) -> {
                var els = new ArrayList<Element>();
                els.add(el("", CORNER_TITLE, ref, q.cornerName(), null, left, y, width, 8, 0, new Font(14, 20), null, false));
                double h = textHeight(q.printBody());
                els.add(el("", QUESTION_TEXT, ref, q.printBody(), null, left, y + 9, width, h, 0, new Font(12, 18), null, false));
                return new Built(els, 9 + h, List.of());
            });
        }

        /** 작성자 줄(캐릭터 12mm + 표기) → 사진 → 글. 사진 종류가 null이면 사진 없음. */
        Built content(int page, double y0, Ref ref, Person author, ComposeOutput.ElementType photoType,
                      ComposeOutput.ElementType textType, List<Media> media, String text, boolean ro) {
            var els = new ArrayList<Element>();
            var warns = new ArrayList<Warning>();
            double y = y0;
            els.add(el("", AUTHOR_CHARACTER, ref, null, author.character(), left, y, 12, 12, 0, null, null, false));
            els.add(el("", AUTHOR_LABEL, ref, author.label(), null, left + 14, y + 3, width - 14, 6, 0,
                    new Font(10, 14), null, false));
            y += 14;
            if (!media.isEmpty()) {
                int n = media.size(), cols = n == 1 ? 1 : 2;
                double cw = (width - (cols - 1) * 2) / cols, ch = n == 1 ? width * 0.5 : cw * 0.75;
                for (int i = 0; i < n; i++) {
                    double x = left + (i % cols) * (cw + 2), yy = y + (i / cols) * (ch + 2);
                    Media m = media.get(i);
                    Crop crop = crop(m, cw, ch);
                    els.add(el("", photoType, new Ref("media", m.id()), null, null, x, yy, cw, ch, 0, null, crop, ro));
                    photoWarnings(m, crop, cw, ch, page, warns);
                }
                int rows = (n + cols - 1) / cols;
                y += rows * (ch + 2);
            }
            double h = textHeight(text);
            els.add(el("", textType, ref, text, null, left, y, width, h, 0, new Font(12, 18), null, ro));
            y += h;
            return new Built(els, y - y0, warns);
        }

        double textHeight(String text) {
            int perLine = (int) Math.floor(width / (12 * MM_PER_PT));
            int lines = Math.max(1, (text.length() + perLine - 1) / perLine);
            return lines * 18 * MM_PER_PT;
        }

        /** 슬롯 비율로 자르되 focal_point를 중심에 둔다. 사진이 늘어나지 않도록 crop 비율 = 슬롯 비율. */
        Crop crop(Media m, double boxW, double boxH) {
            double box = boxW / boxH, img = (double) m.width() / m.height();
            double cw = 1, ch = 1;
            if (img > box) cw = box / img;
            else ch = img / box;
            double x = clamp(m.focalPoint().x() - cw / 2, 0, 1 - cw);
            double y = clamp(m.focalPoint().y() - ch / 2, 0, 1 - ch);
            return new Crop(x, y, cw, ch);
        }

        void photoWarnings(Media m, Crop k, double boxW, double boxH, int page, List<Warning> out) {
            double dpi = Math.min(m.width() * k.w() / (boxW / 25.4), m.height() * k.h() / (boxH / 25.4));
            if (dpi < l.targetDpi())
                out.add(new Warning(Codes.LOW_RES, m.id(), page,
                        Map.of("effective_dpi", (int) Math.round(dpi), "required", l.targetDpi())));
            boolean cuts = m.saliency().stream().anyMatch(r -> r.x() < k.x() - 1e-9 || r.y() < k.y() - 1e-9
                    || r.x() + r.w() > k.x() + k.w() + 1e-9 || r.y() + r.h() > k.y() + k.h() + 1e-9);
            if (cuts) out.add(new Warning(Codes.CROP_CUTS_SALIENCY, m.id(), page, Map.of()));
        }
    }

    private static double clamp(double v, double lo, double hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    private static Element el(String id, ComposeOutput.ElementType type, Ref ref, String text, String character,
                              double x, double y, double w, double h, int z, Font font, Crop crop, boolean ro) {
        return new Element(id, type, ref, text, character, x, y, w, h, z, font, crop, ro);
    }

    /** 실제 엔진은 정규화한 JSON의 SHA-256. 여기서는 record의 toString으로 대신한다 (같은 입력 → 같은 값). */
    private static String hash(ComposeInput in) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-256").digest(in.toString().getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(d);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
