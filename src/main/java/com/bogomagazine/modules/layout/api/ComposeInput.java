package com.bogomagazine.modules.layout.api;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

/**
 * 조판 엔진 입력 (input.json, schema_version 2). docs/composition-engine-api.md 4장.
 * 단위는 mm, 사진의 focal_point/saliency는 원본 기준 0~1 비율이다.
 * 폰트 목록(fonts)은 렌더러가 쓰므로 여기에는 두지 않는다.
 */
public record ComposeInput(
        int schemaVersion,
        String algorithmVersion,
        long seed,
        Issue issue,
        Newspaper newspaper,
        Layout layout,
        List<Post> posts,
        List<QuestionCorner> questionCorners,
        List<BirthdayNotice> birthdayNotices,
        List<Exclusion> exclusions) {

    public static final int SCHEMA_VERSION = 2;

    public enum Visibility { ALL, RECIPIENT_ONLY }

    public record Issue(String id, int number, LocalDate periodStart, LocalDate periodEnd) {}

    public record Recipient(String name, String type, String character) {}

    public record Newspaper(String title, Recipient recipient) {}

    /** page_range는 [minPages, maxPages]. */
    public record Layout(
            double trimWidthMm, double trimHeightMm, double marginMm, double bleedMm,
            double minBodyPt, int targetDpi, int pageMultiple, int minPages, int maxPages) {}

    /** label은 서버가 만든 "관계 + 이름", character는 항상 값이 있다 (PRF-05). */
    public record Person(String label, String character) {}

    public record Point(double x, double y) {}

    public record Rect(double x, double y, double w, double h) {}

    public record Media(String id, String key, int width, int height, Point focalPoint, List<Rect> saliency) {}

    public record Post(
            String id, OffsetDateTime postedAt, Visibility visibility,
            Person author, String body, List<Media> media) {}

    public record Comment(String id, OffsetDateTime postedAt, Person author, String body) {}

    public record Answer(
            String id, OffsetDateTime postedAt, Visibility visibility, Person author,
            String option, String body, List<Media> media, List<Comment> comments) {}

    public record Question(String id, String cornerName, String printBody) {}

    public record QuestionCorner(int order, Question question, List<Answer> answers) {}

    public record BirthdayNotice(String label, String character, int month, int day) {}

    public record Exclusion(String refType, String refId) {}
}
