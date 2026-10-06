package com.bogomagazine.modules.layout.api;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.DateTimeException;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * input.json(schema_version 2) 규격 검사. docs/composition-engine-api.md 4장 "필드 규칙"과
 * "build_input이 지켜야 하는 것"(정렬 고정, 답변 없는 코너 제외, 개인정보 최소화)을 코드로 옮겼다.
 * 위반을 모두 모아 "$.경로: 설명" 목록으로 돌려준다. 비어 있으면 규격에 맞다.
 *
 * <p>정해지지 않은 값(호당 사진 상한 O-07, 댓글 최대 개수 O-11)은 검사하지 않는다.
 */
public final class InputSchema {
    private InputSchema() {}

    private static final Pattern SEMVER = Pattern.compile("\\d+\\.\\d+\\.\\d+");
    private static final Set<String> VISIBILITY = Set.of("ALL", "RECIPIENT_ONLY");

    public static List<String> validate(JsonNode root) {
        var c = new Ctx();
        c.object(root, "$", Set.of("schema_version", "algorithm_version", "seed", "issue", "newspaper",
                "layout", "posts", "question_corners", "birthday_notices", "exclusions"),
                Set.of("schema_version", "algorithm_version", "seed", "issue", "newspaper", "layout",
                        "posts", "question_corners", "birthday_notices", "exclusions"));
        if (!root.isObject()) return c.errors;

        if (!root.path("schema_version").isInt() || root.get("schema_version").asInt() != ComposeInput.SCHEMA_VERSION)
            c.err("$.schema_version", "2여야 함");
        if (!root.path("algorithm_version").isTextual() || !SEMVER.matcher(root.get("algorithm_version").asText()).matches())
            c.err("$.algorithm_version", "x.y.z 형식이어야 함");
        if (!root.path("seed").isIntegralNumber() || root.get("seed").asLong() < 0)
            c.err("$.seed", "0 이상의 정수여야 함");

        issue(c, root.get("issue"));
        newspaper(c, root.get("newspaper"));
        layout(c, root.get("layout"));
        posts(c, root.get("posts"));
        corners(c, root.get("question_corners"));
        birthdays(c, root.get("birthday_notices"));
        exclusions(c, root.get("exclusions"));
        return c.errors;
    }

    // --- 영역별 -----------------------------------------------------------------------------

    private static void issue(Ctx c, JsonNode n) {
        if (n == null || !c.object(n, "$.issue", Set.of("id", "number", "period"), Set.of("id", "number", "period"))) return;
        c.text(n, "$.issue", "id");
        if (!n.get("number").isInt() || n.get("number").asInt() < 1) c.err("$.issue.number", "1 이상의 정수여야 함");
        var p = n.get("period");
        if (!c.object(p, "$.issue.period", Set.of("start", "end"), Set.of("start", "end"))) return;
        var s = c.date(p, "$.issue.period", "start");
        var e = c.date(p, "$.issue.period", "end");
        if (s != null && e != null && e.isBefore(s)) c.err("$.issue.period", "end가 start보다 앞섬");
    }

    private static void newspaper(Ctx c, JsonNode n) {
        if (n == null || !c.object(n, "$.newspaper", Set.of("title", "recipient"), Set.of("title", "recipient"))) return;
        // 제호는 가족방 이름과 별개다 (FAM-02, FAM-03). 최대 30자는 api-spec.md의 제호 제한.
        if (c.text(n, "$.newspaper", "title") && n.get("title").asText().length() > 30)
            c.err("$.newspaper.title", "30자를 넘음");
        var r = n.get("recipient");
        // 이름·유형·캐릭터만 받는다. 사진·성별·주소·전화번호는 넣지 않는다 (RCV-01, 10장).
        if (!c.object(r, "$.newspaper.recipient", Set.of("name", "type", "character"), Set.of("name", "type", "character"))) return;
        c.text(r, "$.newspaper.recipient", "name");
        c.text(r, "$.newspaper.recipient", "type");
        c.text(r, "$.newspaper.recipient", "character");
    }

    private static void layout(Ctx c, JsonNode n) {
        var keys = Set.of("trim_mm", "margin_mm", "bleed_mm", "min_body_pt", "target_dpi", "page_multiple", "page_range", "fonts");
        if (n == null || !c.object(n, "$.layout", keys, Set.of("trim_mm", "margin_mm", "bleed_mm", "min_body_pt", "target_dpi", "page_multiple", "page_range"))) return;
        var trim = n.get("trim_mm");
        double minSide = 0;
        if (!trim.isArray() || trim.size() != 2 || !trim.get(0).isNumber() || !trim.get(1).isNumber()
                || trim.get(0).asDouble() <= 0 || trim.get(1).asDouble() <= 0)
            c.err("$.layout.trim_mm", "[가로, 세로] 양수 두 개여야 함");
        else minSide = Math.min(trim.get(0).asDouble(), trim.get(1).asDouble());
        if (!n.get("margin_mm").isNumber() || n.get("margin_mm").asDouble() < 0
                || (minSide > 0 && n.get("margin_mm").asDouble() * 2 >= minSide))
            c.err("$.layout.margin_mm", "0 이상이고 판형의 절반 미만이어야 함");
        if (!n.get("bleed_mm").isNumber() || n.get("bleed_mm").asDouble() < 0) c.err("$.layout.bleed_mm", "0 이상이어야 함");
        // 본문 글자는 12pt 이상 (NEWS-02)
        if (!n.get("min_body_pt").isNumber() || n.get("min_body_pt").asDouble() < 12) c.err("$.layout.min_body_pt", "12 이상이어야 함 (NEWS-02)");
        if (!n.get("target_dpi").isInt() || n.get("target_dpi").asInt() <= 0) c.err("$.layout.target_dpi", "양의 정수여야 함");
        int mult = n.get("page_multiple").isInt() ? n.get("page_multiple").asInt() : 0;
        if (mult <= 0) c.err("$.layout.page_multiple", "양의 정수여야 함");
        var range = n.get("page_range");
        if (!range.isArray() || range.size() != 2 || !range.get(0).isInt() || !range.get(1).isInt())
            c.err("$.layout.page_range", "[최소, 최대] 정수 두 개여야 함");
        else {
            int lo = range.get(0).asInt(), hi = range.get(1).asInt();
            if (lo < 1 || lo > hi) c.err("$.layout.page_range", "1 ≤ 최소 ≤ 최대여야 함");
            if (mult > 0 && (lo % mult != 0 || hi % mult != 0)) c.err("$.layout.page_range", "page_multiple의 배수여야 함");
        }
        var fonts = n.get("fonts");
        if (fonts != null) {
            if (!fonts.isArray()) c.err("$.layout.fonts", "배열이어야 함");
            else for (int i = 0; i < fonts.size(); i++)
                c.object(fonts.get(i), "$.layout.fonts[" + i + "]", Set.of("family", "weight", "key"), Set.of("family", "weight", "key"));
        }
    }

    private static void posts(Ctx c, JsonNode arr) {
        if (arr == null || !c.array(arr, "$.posts")) return;
        OffsetDateTime prev = null;
        for (int i = 0; i < arr.size(); i++) {
            String p = "$.posts[" + i + "]";
            var n = arr.get(i);
            var keys = Set.of("id", "posted_at", "visibility", "author", "body", "media");
            if (!c.object(n, p, keys, keys)) continue;
            c.id(n, p);
            prev = c.ordered(n, p, prev, "posts는 posted_at 오름차순이어야 함");
            c.visibility(n, p);
            c.person(n.get("author"), p + ".author");
            c.text(n, p, "body");
            media(c, n.get("media"), p + ".media");
        }
    }

    private static void corners(Ctx c, JsonNode arr) {
        if (arr == null || !c.array(arr, "$.question_corners")) return;
        int prevOrder = 0;
        for (int i = 0; i < arr.size(); i++) {
            String p = "$.question_corners[" + i + "]";
            var n = arr.get(i);
            var keys = Set.of("order", "question", "answers");
            if (!c.object(n, p, keys, keys)) continue;
            if (!n.get("order").isInt() || n.get("order").asInt() <= prevOrder) c.err(p + ".order", "1 이상이고 앞 코너보다 커야 함");
            else prevOrder = n.get("order").asInt();
            var q = n.get("question");
            if (c.object(q, p + ".question", Set.of("id", "corner_name", "print_body"), Set.of("id", "corner_name", "print_body"))) {
                c.id(q, p + ".question");
                c.text(q, p + ".question", "corner_name");
                c.text(q, p + ".question", "print_body");
            }
            var answers = n.get("answers");
            if (!c.array(answers, p + ".answers")) continue;
            // 답변한 구성원이 없는 질문의 코너는 build_input이 넣지 않는다 (NEWS-03)
            if (answers.size() == 0) c.err(p + ".answers", "비어 있음: 답변 없는 질문은 코너를 넣지 않는다 (NEWS-03)");
            OffsetDateTime prev = null;
            for (int j = 0; j < answers.size(); j++) {
                String ap = p + ".answers[" + j + "]";
                var a = answers.get(j);
                var ak = Set.of("id", "posted_at", "visibility", "author", "option", "body", "media", "comments");
                if (!c.object(a, ap, ak, ak)) continue;
                c.id(a, ap);
                prev = c.ordered(a, ap, prev, "answers는 posted_at 오름차순이어야 함");
                c.visibility(a, ap);
                c.person(a.get("author"), ap + ".author");
                var opt = a.get("option");
                if (!opt.isNull() && (!opt.isTextual() || opt.asText().isBlank())) c.err(ap + ".option", "null 또는 비어 있지 않은 문자열이어야 함");
                if (!a.get("body").isTextual() || (opt.isNull() && a.get("body").asText().isBlank()))
                    c.err(ap + ".body", "문자열이어야 하고, 선택형이 아니면 비어 있을 수 없음");
                media(c, a.get("media"), ap + ".media");
                var comments = a.get("comments");
                if (!c.array(comments, ap + ".comments")) continue;
                OffsetDateTime cprev = null;
                for (int k = 0; k < comments.size(); k++) {
                    String cp = ap + ".comments[" + k + "]";
                    var cm = comments.get(k);
                    var ck = Set.of("id", "posted_at", "author", "body");
                    if (!c.object(cm, cp, ck, ck)) continue;
                    c.id(cm, cp);
                    cprev = c.ordered(cm, cp, cprev, "comments는 posted_at 오름차순이어야 함");
                    c.person(cm.get("author"), cp + ".author");
                    c.text(cm, cp, "body");
                }
            }
        }
    }

    private static void media(Ctx c, JsonNode arr, String path) {
        if (!c.array(arr, path)) return;
        for (int i = 0; i < arr.size(); i++) {
            String p = path + "[" + i + "]";
            var m = arr.get(i);
            var keys = Set.of("id", "key", "width", "height", "focal_point", "saliency");
            if (!c.object(m, p, keys, keys)) continue;
            c.id(m, p);
            c.text(m, p, "key");
            for (String f : List.of("width", "height"))
                if (!m.get(f).isInt() || m.get(f).asInt() <= 0) c.err(p + "." + f, "양의 정수(픽셀)여야 함");
            var fp = m.get("focal_point");
            if (c.object(fp, p + ".focal_point", Set.of("x", "y"), Set.of("x", "y"))) {
                c.unit(fp, p + ".focal_point", "x");
                c.unit(fp, p + ".focal_point", "y");
            }
            var sal = m.get("saliency");
            if (!c.array(sal, p + ".saliency")) continue;
            for (int k = 0; k < sal.size(); k++) {
                String sp = p + ".saliency[" + k + "]";
                var r = sal.get(k);
                var rk = Set.of("x", "y", "w", "h");
                if (!c.object(r, sp, rk, rk)) continue;
                boolean ok = true;
                for (String f : List.of("x", "y", "w", "h")) ok &= c.unit(r, sp, f);
                if (ok && (r.get("w").asDouble() <= 0 || r.get("h").asDouble() <= 0
                        || r.get("x").asDouble() + r.get("w").asDouble() > 1 + 1e-9
                        || r.get("y").asDouble() + r.get("h").asDouble() > 1 + 1e-9))
                    c.err(sp, "영역이 사진(0~1) 밖이거나 크기가 0");
            }
        }
    }

    private static void birthdays(Ctx c, JsonNode arr) {
        if (arr == null || !c.array(arr, "$.birthday_notices")) return;
        for (int i = 0; i < arr.size(); i++) {
            String p = "$.birthday_notices[" + i + "]";
            var n = arr.get(i);
            var keys = Set.of("label", "character", "month", "day");
            if (!c.object(n, p, keys, keys)) continue;
            c.text(n, p, "label");
            c.text(n, p, "character");
            if (n.get("month").isInt() && n.get("day").isInt()) {
                try {
                    LocalDate.of(2000, n.get("month").asInt(), n.get("day").asInt()); // 윤년 기준으로 2/29 허용
                } catch (DateTimeException e) {
                    c.err(p, "존재하지 않는 월/일");
                }
            } else c.err(p, "month, day는 정수여야 함");
        }
    }

    private static void exclusions(Ctx c, JsonNode arr) {
        if (arr == null || !c.array(arr, "$.exclusions")) return;
        for (int i = 0; i < arr.size(); i++) {
            String p = "$.exclusions[" + i + "]";
            var n = arr.get(i);
            if (!c.object(n, p, Set.of("ref_type", "ref_id"), Set.of("ref_type", "ref_id"))) continue;
            if (!n.get("ref_type").isTextual() || !Set.of("post", "answer").contains(n.get("ref_type").asText()))
                c.err(p + ".ref_type", "post 또는 answer여야 함");
            c.text(n, p, "ref_id");
        }
    }

    // --- 공통 검사 도구 ---------------------------------------------------------------------

    private static final class Ctx {
        final List<String> errors = new ArrayList<>();
        final Set<String> ids = new HashSet<>();

        void err(String path, String msg) {
            errors.add(path + ": " + msg);
        }

        /** 객체이고, 필수 필드가 다 있고, 허용되지 않은 필드가 없을 때만 true */
        boolean object(JsonNode n, String path, Set<String> allowed, Set<String> required) {
            if (n == null || !n.isObject()) {
                err(path, "객체여야 함");
                return false;
            }
            boolean ok = true;
            for (String r : required)
                if (!n.has(r)) {
                    err(path + "." + r, "필수 필드 없음");
                    ok = false;
                }
            for (var it = n.fieldNames(); it.hasNext(); ) {
                String f = it.next();
                if (!allowed.contains(f)) err(path + "." + f, "허용되지 않는 필드 (스키마에 없음)");
            }
            return ok;
        }

        boolean array(JsonNode n, String path) {
            if (n == null || !n.isArray()) {
                err(path, "배열이어야 함");
                return false;
            }
            return true;
        }

        boolean text(JsonNode n, String path, String f) {
            var v = n.get(f);
            if (v == null || !v.isTextual() || v.asText().isBlank()) {
                err(path + "." + f, "비어 있지 않은 문자열이어야 함");
                return false;
            }
            return true;
        }

        /** 입력 안에서 id는 겹치지 않는다 */
        void id(JsonNode n, String path) {
            if (text(n, path, "id") && !ids.add(n.get("id").asText()))
                err(path + ".id", "중복된 id: " + n.get("id").asText());
        }

        void visibility(JsonNode n, String path) {
            var v = n.get("visibility");
            if (v == null || !v.isTextual() || !VISIBILITY.contains(v.asText()))
                err(path + ".visibility", "ALL 또는 RECIPIENT_ONLY여야 함");
        }

        /** 작성자: 표기와 캐릭터는 항상 값이 있다 (PRF-03, PRF-05). 프로필 사진은 받지 않는다. */
        void person(JsonNode n, String path) {
            if (object(n, path, Set.of("label", "character"), Set.of("label", "character"))) {
                text(n, path, "label");
                text(n, path, "character");
            }
        }

        LocalDate date(JsonNode n, String path, String f) {
            try {
                return LocalDate.parse(n.get(f).asText());
            } catch (Exception e) {
                err(path + "." + f, "YYYY-MM-DD 형식이어야 함");
                return null;
            }
        }

        boolean unit(JsonNode n, String path, String f) {
            var v = n.get(f);
            if (v == null || !v.isNumber() || v.asDouble() < 0 || v.asDouble() > 1) {
                err(path + "." + f, "0~1 사이 숫자여야 함");
                return false;
            }
            return true;
        }

        /** posted_at이 시간대 포함 ISO 형식이고 앞 항목보다 같거나 늦은지 본다. 파싱된 값을 돌려준다. */
        OffsetDateTime ordered(JsonNode n, String path, OffsetDateTime prev, String orderMsg) {
            var v = n.get("posted_at");
            try {
                var t = OffsetDateTime.parse(v.asText());
                if (prev != null && t.isBefore(prev)) err(path + ".posted_at", orderMsg);
                return t;
            } catch (Exception e) {
                err(path + ".posted_at", "시간대가 포함된 ISO 8601 형식이어야 함 (예: 2026-10-07T19:30:00+09:00)");
                return prev;
            }
        }
    }
}
