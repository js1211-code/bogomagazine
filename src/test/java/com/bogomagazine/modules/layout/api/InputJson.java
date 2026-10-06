package com.bogomagazine.modules.layout.api;

import com.bogomagazine.modules.layout.api.ComposeInput.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.Path;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * input.json(schema_version 2, docs/composition-engine-api.md 4장)을 {@link ComposeInput}으로 읽는다.
 * 문서의 JSON 모양 그대로(snake_case, trim_mm 배열, period 객체)를 받으므로, 샘플 파일이 곧 스키마 검증이다.
 * fonts는 렌더러가 쓰므로 읽지 않는다.
 */
final class InputJson {
    private InputJson() {}

    private static final ObjectMapper MAPPER = new ObjectMapper();

    static ComposeInput read(Path file) throws IOException {
        return read(MAPPER.readTree(file.toFile()));
    }

    static ComposeInput read(JsonNode n) {
        var issue = req(n, "issue");
        var period = req(issue, "period");
        var np = req(n, "newspaper");
        var rc = req(np, "recipient");
        var layout = req(n, "layout");
        var trim = req(layout, "trim_mm");
        var range = req(layout, "page_range");

        return new ComposeInput(
                req(n, "schema_version").asInt(),
                req(n, "algorithm_version").asText(),
                req(n, "seed").asLong(),
                new Issue(req(issue, "id").asText(), req(issue, "number").asInt(),
                        LocalDate.parse(req(period, "start").asText()), LocalDate.parse(req(period, "end").asText())),
                new Newspaper(req(np, "title").asText(),
                        new Recipient(req(rc, "name").asText(), req(rc, "type").asText(), req(rc, "character").asText())),
                new Layout(trim.get(0).asDouble(), trim.get(1).asDouble(), req(layout, "margin_mm").asDouble(),
                        req(layout, "bleed_mm").asDouble(), req(layout, "min_body_pt").asDouble(),
                        req(layout, "target_dpi").asInt(), req(layout, "page_multiple").asInt(),
                        range.get(0).asInt(), range.get(1).asInt()),
                list(req(n, "posts"), InputJson::post),
                list(req(n, "question_corners"), InputJson::corner),
                list(req(n, "birthday_notices"), b -> new BirthdayNotice(req(b, "label").asText(),
                        req(b, "character").asText(), req(b, "month").asInt(), req(b, "day").asInt())),
                list(req(n, "exclusions"), e -> new Exclusion(req(e, "ref_type").asText(), req(e, "ref_id").asText())));
    }

    private static Post post(JsonNode p) {
        return new Post(req(p, "id").asText(), OffsetDateTime.parse(req(p, "posted_at").asText()),
                Visibility.valueOf(req(p, "visibility").asText()), person(req(p, "author")),
                req(p, "body").asText(), list(req(p, "media"), InputJson::media));
    }

    private static QuestionCorner corner(JsonNode c) {
        var q = req(c, "question");
        return new QuestionCorner(req(c, "order").asInt(),
                new Question(req(q, "id").asText(), req(q, "corner_name").asText(), req(q, "print_body").asText()),
                list(req(c, "answers"), InputJson::answer));
    }

    private static Answer answer(JsonNode a) {
        var option = a.get("option");
        return new Answer(req(a, "id").asText(), OffsetDateTime.parse(req(a, "posted_at").asText()),
                Visibility.valueOf(req(a, "visibility").asText()), person(req(a, "author")),
                option == null || option.isNull() ? null : option.asText(), req(a, "body").asText(),
                list(req(a, "media"), InputJson::media),
                list(req(a, "comments"), c -> new Comment(req(c, "id").asText(),
                        OffsetDateTime.parse(req(c, "posted_at").asText()), person(req(c, "author")),
                        req(c, "body").asText())));
    }

    private static Media media(JsonNode m) {
        var fp = req(m, "focal_point");
        return new Media(req(m, "id").asText(), req(m, "key").asText(), req(m, "width").asInt(),
                req(m, "height").asInt(), new Point(req(fp, "x").asDouble(), req(fp, "y").asDouble()),
                list(req(m, "saliency"), r -> new Rect(req(r, "x").asDouble(), req(r, "y").asDouble(),
                        req(r, "w").asDouble(), req(r, "h").asDouble())));
    }

    private static Person person(JsonNode p) {
        return new Person(req(p, "label").asText(), req(p, "character").asText());
    }

    private static JsonNode req(JsonNode n, String field) {
        var v = n.get(field);
        if (v == null) throw new IllegalArgumentException("필수 필드 없음: " + field);
        return v;
    }

    private static <T> List<T> list(JsonNode arr, java.util.function.Function<JsonNode, T> f) {
        var out = new ArrayList<T>();
        arr.forEach(x -> out.add(f.apply(x)));
        return List.copyOf(out);
    }
}
