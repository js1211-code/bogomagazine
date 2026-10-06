package com.bogomagazine.modules.layout.api;

import static com.bogomagazine.modules.layout.api.ComposeOutput.ElementType.*;

import com.bogomagazine.modules.layout.api.ComposeInput.*;
import com.bogomagazine.modules.layout.api.ComposeOutput.*;
import java.util.*;
import java.util.stream.Collectors;

/**
 * output이 input에 대해 지켜야 하는 불변 조건 검사기 (docs/composition-engine-api.md 5장 "규칙").
 * 실제 알고리즘과 무관하게 어떤 엔진 구현이든 같은 검사를 통과해야 한다.
 * 위반이 없으면 빈 목록을 돌려준다.
 */
public final class OutputInvariants {
    private OutputInvariants() {}

    public record Violation(String rule, String detail) {
        @Override
        public String toString() {
            return rule + ": " + detail;
        }
    }

    private static final double EPS = 1e-6;
    private static final double MM_PER_INCH = 25.4;
    private static final Set<ComposeOutput.ElementType> PHOTOS = EnumSet.of(POST_PHOTO, ANSWER_PHOTO);
    private static final Set<ComposeOutput.ElementType> BODY_TEXTS =
            EnumSet.of(POST_TEXT, ANSWER_TEXT, COMMENT_TEXT, QUESTION_TEXT);

    public static List<Violation> check(ComposeInput in, ComposeOutput out) {
        var v = new ArrayList<Violation>();
        var elements = out.pages().stream()
                .flatMap(p -> p.elements().stream().map(e -> new Placed(p.pageNo(), e))).toList();
        var content = Content.index(in);

        echo(in, out, v);
        pages(in, out, v);
        masthead(in, elements, v);
        geometry(in, elements, v);
        fonts(in, elements, v);
        conservation(content, out, elements, v);
        corners(in, elements, v);
        authors(content, elements, v);
        recipientOnly(content, elements, v);
        photos(in, content, out, elements, v);
        emptyPages(out, v);
        stats(out, elements, v);
        return v;
    }

    private record Placed(int pageNo, Element e) {}

    // --- 입력 색인 ---------------------------------------------------------------------------

    /** 지면에 놓여야 하는 내용(소식·답변·댓글·사진)과 그 속성 */
    private record Content(
            Map<String, Post> posts, Map<String, Answer> answers, Map<String, Comment> comments,
            Map<String, Media> media, Map<String, Boolean> mediaRecipientOnly, Set<String> questions) {

        static Content index(ComposeInput in) {
            var c = new Content(new HashMap<>(), new HashMap<>(), new HashMap<>(), new HashMap<>(),
                    new HashMap<>(), new HashSet<>());
            for (Post p : in.posts()) {
                c.posts.put(p.id(), p);
                for (Media m : p.media()) {
                    c.media.put(m.id(), m);
                    c.mediaRecipientOnly.put(m.id(), p.visibility() == Visibility.RECIPIENT_ONLY);
                }
            }
            for (QuestionCorner qc : in.questionCorners()) {
                c.questions.add(qc.question().id());
                for (Answer a : qc.answers()) {
                    c.answers.put(a.id(), a);
                    for (Media m : a.media()) {
                        c.media.put(m.id(), m);
                        c.mediaRecipientOnly.put(m.id(), a.visibility() == Visibility.RECIPIENT_ONLY);
                    }
                    for (Comment cm : a.comments()) c.comments.put(cm.id(), cm);
                }
            }
            return c;
        }
    }

    // --- 규칙 --------------------------------------------------------------------------------

    private static void echo(ComposeInput in, ComposeOutput out, List<Violation> v) {
        if (out.schemaVersion() != ComposeInput.SCHEMA_VERSION)
            v.add(new Violation("ECHO", "schema_version " + out.schemaVersion()));
        if (!Objects.equals(out.algorithmVersion(), in.algorithmVersion()))
            v.add(new Violation("ECHO", "algorithm_version 불일치"));
        if (out.seed() != in.seed()) v.add(new Violation("ECHO", "seed 불일치"));
        if (out.inputHash() == null || out.inputHash().isBlank())
            v.add(new Violation("ECHO", "input_hash 없음"));
        var s = out.score();
        if (s == null || s.total() < 0 || s.total() > 1
                || s.parts().values().stream().anyMatch(x -> x < 0 || x > 1))
            v.add(new Violation("SCORE", "점수는 0~1이어야 한다"));
    }

    /** 쪽수는 page_multiple의 배수이고 page_range 안이며, 쪽 번호는 1부터 빠짐없이 이어진다. */
    private static void pages(ComposeInput in, ComposeOutput out, List<Violation> v) {
        var l = in.layout();
        int n = out.pages().size();
        if (n % l.pageMultiple() != 0)
            v.add(new Violation("PAGE_COUNT", n + "쪽은 " + l.pageMultiple() + "의 배수가 아님"));
        if (n < l.minPages() || n > l.maxPages())
            v.add(new Violation("PAGE_COUNT", n + "쪽은 범위 " + l.minPages() + "~" + l.maxPages() + " 밖"));
        for (int i = 0; i < n; i++)
            if (out.pages().get(i).pageNo() != i + 1)
                v.add(new Violation("PAGE_NUMBERING", "index " + i + "의 page_no=" + out.pages().get(i).pageNo()));
    }

    /** 제호와 받는 분 캐릭터는 1면에 하나씩. 제호는 가족방 이름이 아니라 newspaper.title. */
    private static void masthead(ComposeInput in, List<Placed> els, List<Violation> v) {
        var mast = els.stream().filter(p -> p.e().type() == MASTHEAD).toList();
        if (mast.size() != 1 || mast.get(0).pageNo() != 1)
            v.add(new Violation("MASTHEAD", "제호는 1면에 정확히 하나여야 함 (" + mast.size() + "개)"));
        else if (!Objects.equals(mast.get(0).e().text(), in.newspaper().title()))
            v.add(new Violation("MASTHEAD", "제호 문구가 newspaper.title과 다름"));
        var rc = els.stream().filter(p -> p.e().type() == RECIPIENT_CHARACTER).toList();
        if (rc.size() != 1 || rc.get(0).pageNo() != 1)
            v.add(new Violation("MASTHEAD", "받는 분 캐릭터는 1면에 정확히 하나여야 함 (" + rc.size() + "개)"));
        else if (!Objects.equals(rc.get(0).e().character(), in.newspaper().recipient().character()))
            v.add(new Violation("MASTHEAD", "받는 분 캐릭터가 입력과 다름"));
    }

    /** 모든 요소는 재단선 안, 사진 외 요소는 안전 여백 안. 같은 z끼리는 겹치지 않는다. */
    private static void geometry(ComposeInput in, List<Placed> els, List<Violation> v) {
        var l = in.layout();
        for (Placed p : els) {
            Element e = p.e();
            boolean inTrim = e.x() >= -EPS && e.y() >= -EPS && e.w() > 0 && e.h() > 0
                    && e.x() + e.w() <= l.trimWidthMm() + EPS && e.y() + e.h() <= l.trimHeightMm() + EPS;
            if (!inTrim) v.add(new Violation("BOUNDS", p.pageNo() + "면 " + e.id() + " 가 재단선 밖/크기 0"));
            else if (!PHOTOS.contains(e.type())) {
                double m = l.marginMm();
                if (e.x() < m - EPS || e.y() < m - EPS || e.x() + e.w() > l.trimWidthMm() - m + EPS
                        || e.y() + e.h() > l.trimHeightMm() - m + EPS)
                    v.add(new Violation("SAFE_AREA", p.pageNo() + "면 " + e.id() + " 가 안전 여백 침범"));
            }
        }
        for (int i = 0; i < els.size(); i++)
            for (int j = i + 1; j < els.size(); j++) {
                Placed a = els.get(i), b = els.get(j);
                if (a.pageNo() == b.pageNo() && a.e().z() == b.e().z() && overlaps(a.e(), b.e()))
                    v.add(new Violation("OVERLAP", a.pageNo() + "면 " + a.e().id() + " 와 " + b.e().id()));
            }
    }

    private static boolean overlaps(Element a, Element b) {
        return a.x() < b.x() + b.w() - EPS && b.x() < a.x() + a.w() - EPS
                && a.y() < b.y() + b.h() - EPS && b.y() < a.y() + a.h() - EPS;
    }

    /** 본문 글자는 min_body_pt 이상 (NEWS-02). 줄 간격은 글자 크기보다 작을 수 없다. */
    private static void fonts(ComposeInput in, List<Placed> els, List<Violation> v) {
        for (Placed p : els) {
            if (!BODY_TEXTS.contains(p.e().type())) continue;
            Font f = p.e().font();
            if (f == null || f.sizePt() < in.layout().minBodyPt() - EPS)
                v.add(new Violation("MIN_FONT", p.e().id() + " 글자 크기 " + (f == null ? "없음" : f.sizePt() + "pt")));
            else if (f.leadingPt() < f.sizePt())
                v.add(new Violation("MIN_FONT", p.e().id() + " 줄 간격이 글자 크기보다 작음"));
        }
    }

    /** 소식·답변·댓글·사진은 정확히 한 번, 지면 또는 unplaced 중 한 곳에만 나온다 (조용히 버리지 않는다). */
    private static void conservation(Content c, ComposeOutput out, List<Placed> els, List<Violation> v) {
        var placed = new HashMap<String, Integer>(); // "type:id" -> 횟수
        for (Placed p : els) {
            Element e = p.e();
            if (e.ref() == null) continue;
            String key = e.ref().type() + ":" + e.ref().id();
            switch (e.type()) {
                case POST_TEXT, ANSWER_TEXT, COMMENT_TEXT, POST_PHOTO, ANSWER_PHOTO -> placed.merge(key, 1, Integer::sum);
                default -> { }
            }
            if (!known(c, e.ref().type(), e.ref().id()))
                v.add(new Violation("UNKNOWN_REF", e.id() + " 가 입력에 없는 " + key + " 를 참조"));
        }
        var unplaced = new HashMap<String, Integer>();
        for (Unplaced u : out.unplaced()) {
            String key = u.refType() + ":" + u.refId();
            unplaced.merge(key, 1, Integer::sum);
            if (u.reason() == null || u.reason().isBlank())
                v.add(new Violation("UNPLACED_REASON", key + " 사유 없음"));
            if (!known(c, u.refType(), u.refId()))
                v.add(new Violation("UNKNOWN_REF", "unplaced에 입력에 없는 " + key));
        }
        var required = new ArrayList<String>();
        c.posts().keySet().forEach(id -> required.add("post:" + id));
        c.answers().keySet().forEach(id -> required.add("answer:" + id));
        c.comments().keySet().forEach(id -> required.add("comment:" + id));
        c.media().keySet().forEach(id -> required.add("media:" + id));
        for (String key : required) {
            int a = placed.getOrDefault(key, 0), b = unplaced.getOrDefault(key, 0);
            if (a + b != 1)
                v.add(new Violation("CONSERVATION", key + " 배치 " + a + "회, 미배치 " + b + "회 (합이 1이어야 함)"));
        }
    }

    private static boolean known(Content c, String type, String id) {
        return switch (type) {
            case "post" -> c.posts().containsKey(id);
            case "answer" -> c.answers().containsKey(id);
            case "comment" -> c.comments().containsKey(id);
            case "media" -> c.media().containsKey(id);
            case "question" -> c.questions().contains(id);
            case "recipient" -> true;
            default -> false;
        };
    }

    /** 코너: 답변이 없는 질문은 코너를 만들지 않고, 답변이 하나라도 놓이면 코너명과 질문이 한 번씩 있다 (NEWS-03). */
    private static void corners(ComposeInput in, List<Placed> els, List<Violation> v) {
        var placedAnswers = els.stream().filter(p -> p.e().type() == ANSWER_TEXT)
                .map(p -> p.e().ref().id()).collect(Collectors.toSet());
        for (QuestionCorner qc : in.questionCorners()) {
            String qid = qc.question().id();
            long titles = count(els, CORNER_TITLE, qid), questions = count(els, QUESTION_TEXT, qid);
            boolean anyPlaced = qc.answers().stream().anyMatch(a -> placedAnswers.contains(a.id()));
            if (qc.answers().isEmpty() && (titles > 0 || questions > 0))
                v.add(new Violation("CORNER", "답변 없는 질문 " + qid + " 의 코너가 만들어짐"));
            if (titles > 1 || questions > 1)
                v.add(new Violation("CORNER", "질문 " + qid + " 의 코너가 둘 이상으로 나뉨"));
            if (anyPlaced && (titles != 1 || questions != 1))
                v.add(new Violation("CORNER", "답변이 놓인 질문 " + qid + " 에 코너명/질문이 한 번씩 있어야 함"));
        }
    }

    private static long count(List<Placed> els, ComposeOutput.ElementType t, String refId) {
        return els.stream().filter(p -> p.e().type() == t && p.e().ref() != null
                && refId.equals(p.e().ref().id())).count();
    }

    /** 놓인 소식·답변·댓글마다 작성자 표기와 캐릭터가 한 쌍씩 있고 입력 값과 같다 (PRF-03, PRF-05). */
    private static void authors(Content c, List<Placed> els, List<Violation> v) {
        for (Placed p : els) {
            Element e = p.e();
            Person author = switch (e.type()) {
                case POST_TEXT -> c.posts().get(e.ref().id()).author();
                case ANSWER_TEXT -> c.answers().get(e.ref().id()).author();
                case COMMENT_TEXT -> c.comments().get(e.ref().id()).author();
                default -> null;
            };
            if (author == null) continue;
            var labels = els.stream().filter(q -> q.e().type() == AUTHOR_LABEL && e.ref().equals(q.e().ref())).toList();
            var chars = els.stream().filter(q -> q.e().type() == AUTHOR_CHARACTER && e.ref().equals(q.e().ref())).toList();
            if (labels.size() != 1 || chars.size() != 1)
                v.add(new Violation("AUTHOR_PAIR", e.ref() + " 작성자 표기 " + labels.size() + "개, 캐릭터 " + chars.size() + "개"));
            else {
                if (!Objects.equals(labels.get(0).e().text(), author.label()))
                    v.add(new Violation("AUTHOR_PAIR", e.ref() + " 작성자 표기가 입력과 다름"));
                if (!Objects.equals(chars.get(0).e().character(), author.character()))
                    v.add(new Violation("AUTHOR_PAIR", e.ref() + " 캐릭터가 입력과 다름"));
            }
        }
    }

    /** "할머니께만" 소식·답변의 글과 사진은 지면에 싣되 recipient_only를 표시하고, 그 외에는 표시하지 않는다. */
    private static void recipientOnly(Content c, List<Placed> els, List<Violation> v) {
        for (Placed p : els) {
            Element e = p.e();
            Boolean expected = switch (e.type()) {
                case POST_TEXT -> c.posts().get(e.ref().id()).visibility() == Visibility.RECIPIENT_ONLY;
                case ANSWER_TEXT -> c.answers().get(e.ref().id()).visibility() == Visibility.RECIPIENT_ONLY;
                case POST_PHOTO, ANSWER_PHOTO -> c.mediaRecipientOnly().get(e.ref().id());
                default -> null;
            };
            if (expected != null && e.recipientOnly() != expected)
                v.add(new Violation("RECIPIENT_ONLY", e.id() + " recipient_only=" + e.recipientOnly() + ", 기대값 " + expected));
        }
    }

    /** 사진: 비율 보존 crop, 해상도 경고(low_res), 중요 영역 잘림 경고(crop_cuts_saliency)가 사실과 맞다. */
    private static void photos(ComposeInput in, Content c, ComposeOutput out, List<Placed> els, List<Violation> v) {
        for (Placed p : els) {
            Element e = p.e();
            if (!PHOTOS.contains(e.type())) continue;
            Media m = c.media().get(e.ref().id());
            Crop k = e.crop();
            if (m == null) continue; // UNKNOWN_REF로 이미 보고됨
            if (k == null || k.x() < -EPS || k.y() < -EPS || k.w() <= 0 || k.h() <= 0
                    || k.x() + k.w() > 1 + EPS || k.y() + k.h() > 1 + EPS) {
                v.add(new Violation("CROP_RANGE", e.id() + " crop이 없거나 0~1 범위 밖"));
                continue;
            }
            double cropAspect = (k.w() * m.width()) / (k.h() * m.height());
            if (Math.abs(cropAspect / (e.w() / e.h()) - 1) > 0.01)
                v.add(new Violation("CROP_ASPECT", e.id() + " crop 비율이 슬롯 비율과 다름 (사진이 늘어남)"));

            double dpi = Math.min(
                    m.width() * k.w() / (e.w() / MM_PER_INCH), m.height() * k.h() / (e.h() / MM_PER_INCH));
            boolean low = dpi < in.layout().targetDpi();
            if (low != hasWarning(out, Codes.LOW_RES, m.id()))
                v.add(new Violation("LOW_RES", m.id() + " 유효 " + Math.round(dpi) + "dpi, low_res 경고 " + (low ? "누락" : "불필요")));

            boolean cuts = m.saliency() != null && m.saliency().stream().anyMatch(r -> !inside(r, k));
            if (cuts != hasWarning(out, Codes.CROP_CUTS_SALIENCY, m.id()))
                v.add(new Violation("CROP_SALIENCY", m.id() + " 중요 영역 " + (cuts ? "잘리는데 경고 없음" : "안 잘리는데 경고 있음")));
        }
    }

    private static boolean inside(Rect r, Crop k) {
        return r.x() >= k.x() - EPS && r.y() >= k.y() - EPS
                && r.x() + r.w() <= k.x() + k.w() + EPS && r.y() + r.h() <= k.y() + k.h() + EPS;
    }

    private static boolean hasWarning(ComposeOutput out, String code, String refId) {
        return out.warnings().stream().anyMatch(w -> w.code().equals(code) && refId.equals(w.refId()));
    }

    /** 빈 면은 이유(page_padded 또는 empty_page)를 경고로 남긴다. 경고 코드는 정의된 것만 쓴다. */
    private static void emptyPages(ComposeOutput out, List<Violation> v) {
        for (Page pg : out.pages()) {
            if (!pg.elements().isEmpty()) continue;
            boolean explained = out.warnings().stream().anyMatch(w -> Objects.equals(w.pageNo(), pg.pageNo())
                    && (w.code().equals(Codes.PAGE_PADDED) || w.code().equals(Codes.EMPTY_PAGE)));
            if (!explained) v.add(new Violation("EMPTY_PAGE", pg.pageNo() + "면이 비었는데 경고 없음"));
        }
        for (Warning w : out.warnings())
            if (!Codes.WARNINGS.contains(w.code())) v.add(new Violation("WARNING_CODE", "정의되지 않은 경고 " + w.code()));
    }

    private static void stats(ComposeOutput out, List<Placed> els, List<Violation> v) {
        if (out.stats().pageCount() != out.pages().size())
            v.add(new Violation("STATS", "stats.page_count != pages 개수"));
        if (out.stats().elements() != els.size()) v.add(new Violation("STATS", "stats.elements != 요소 개수"));
    }
}
