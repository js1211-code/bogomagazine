package com.bogomagazine.modules.layout.api;

import java.util.List;
import java.util.Map;

/** 조판 엔진 출력 (output.json, schema_version 2). docs/composition-engine-api.md 5장. 단위는 mm. */
public record ComposeOutput(
        int schemaVersion,
        String inputHash,
        String algorithmVersion,
        long seed,
        Score score,
        List<Page> pages,
        List<Unplaced> unplaced,
        List<Warning> warnings,
        Stats stats) {

    public enum ElementType {
        MASTHEAD, RECIPIENT_CHARACTER, POST_PHOTO, POST_TEXT, AUTHOR_LABEL, AUTHOR_CHARACTER,
        BIRTHDAY_NOTICE, POST_DATE, CORNER_TITLE, QUESTION_TEXT, ANSWER_TEXT, ANSWER_PHOTO, COMMENT_TEXT
    }

    public record Score(double total, Map<String, Double> parts) {}

    public record Page(int pageNo, List<Element> elements) {}

    /** ref.type: post, media, answer, comment, question, recipient. 제호는 ref가 없다. */
    public record Ref(String type, String id) {}

    public record Font(double sizePt, double leadingPt) {}

    public record Crop(double x, double y, double w, double h) {}

    public record Element(
            String id, ElementType type, Ref ref, String text, String character,
            double x, double y, double w, double h, int z,
            Font font, Crop crop, boolean recipientOnly) {}

    public record Unplaced(String refType, String refId, String reason) {}

    public record Warning(String code, String refId, Integer pageNo, Map<String, Object> detail) {}

    public record Stats(int pageCount, int elements, long elapsedMs) {}
}
