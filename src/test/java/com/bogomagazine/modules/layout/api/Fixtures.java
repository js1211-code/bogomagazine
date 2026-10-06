package com.bogomagazine.modules.layout.api;

import com.bogomagazine.modules.layout.api.ComposeInput.*;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.function.UnaryOperator;

/** 테스트 입력 조립. 값은 composition-engine-api.md 4장 예시와 13장 확정 값(A4, 15mm 여백, 4~16쪽)을 따른다. */
public final class Fixtures {
    private Fixtures() {}

    public static final Person GRANDDAUGHTER = new Person("손녀 보민", "c03");
    public static final Person DAUGHTER = new Person("딸 은정", "c05");
    public static final Person SON = new Person("아들 민수", "c11");

    public static final Layout A4 = new Layout(210, 297, 15, 3, 12, 300, 4, 4, 16);

    private static final OffsetDateTime T0 = OffsetDateTime.parse("2026-10-07T19:30:00+09:00");

    public static OffsetDateTime at(int minutesAfterStart) {
        return T0.plusMinutes(minutesAfterStart);
    }

    /** 12MP 사진. 초점은 위쪽 중앙, 중요 영역은 가운데 위쪽이라 어떤 슬롯 비율로도 보통은 잘리지 않는다. */
    public static Media photo(String id) {
        return photo(id, 4032, 3024);
    }

    public static Media photo(String id, int w, int h) {
        return new Media(id, "posts/" + id + "/original.jpg", w, h,
                new Point(0.5, 0.4), List.of(new Rect(0.3, 0.2, 0.4, 0.5)));
    }

    public static Post post(String id, int minute, Visibility vis, Person author, String body, Media... media) {
        return new Post(id, at(minute), vis, author, body, List.of(media));
    }

    public static Answer answer(String id, int minute, Visibility vis, Person author, String body,
                                List<Media> media, List<Comment> comments) {
        return new Answer(id, at(minute), vis, author, null, body, media, comments);
    }

    public static Comment comment(String id, int minute, Person author, String body) {
        return new Comment(id, at(minute), author, body);
    }

    public static QuestionCorner corner(int order, String qid, String name, String text, Answer... answers) {
        return new QuestionCorner(order, new Question(qid, name, text), List.of(answers));
    }

    public static ComposeInput input(List<Post> posts, List<QuestionCorner> corners) {
        return new ComposeInput(
                ComposeInput.SCHEMA_VERSION, "0.1.0", 1894467310L,
                new Issue("issue-2", 2, LocalDate.parse("2026-10-05"), LocalDate.parse("2026-10-18")),
                new Newspaper("보고잡지", new Recipient("홍판서", "SINGLE", "c07")),
                A4, posts, corners, List.of(), List.of());
    }

    public static ComposeInput with(ComposeInput in, UnaryOperator<ComposeInputBuilder> f) {
        return f.apply(new ComposeInputBuilder(in)).build();
    }

    /** 소식 3개(전체 공개 1, "할머니께만" 1, 글만 1) + 질문 코너 1개(답변 2, 댓글 1) + 답변 없는 질문 1개 */
    public static ComposeInput small() {
        var posts = List.of(
                post("p1", 0, Visibility.ALL, GRANDDAUGHTER, "오늘 할머니 생신 케이크 앞에서 한 컷!", photo("m1")),
                post("p2", 10, Visibility.RECIPIENT_ONLY, DAUGHTER, "엄마, 사실은 병원에 다녀왔어요.", photo("m2"), photo("m3")),
                post("p3", 20, Visibility.ALL, SON, "다음 주말에 내려갈게요."));
        var corners = List.of(
                corner(1, "q1", "어린 시절 이야기", "할머니께서 어릴 적 즐겨 하신 놀이는 무엇인가요?",
                        answer("a1", 30, Visibility.ALL, GRANDDAUGHTER, "공기놀이요", List.of(),
                                List.of(comment("c1", 40, DAUGHTER, "저도 궁금했어요"))),
                        answer("a2", 35, Visibility.RECIPIENT_ONLY, SON, "고무줄놀이도 하셨대요", List.of(photo("m4")), List.of())),
                corner(2, "q2", "요즘 이야기", "요즘 즐겨 드시는 간식은?"));
        return input(posts, corners);
    }

    /** 글 약 120자짜리 소식 n개, 소식마다 사진 1장 */
    public static ComposeInput manyPosts(int n) {
        var posts = new ArrayList<Post>();
        for (int i = 0; i < n; i++)
            posts.add(post("p" + i, i, Visibility.ALL, i % 2 == 0 ? GRANDDAUGHTER : DAUGHTER,
                    "가".repeat(120), photo("m" + i)));
        return input(posts, List.of());
    }

    /** ComposeInput은 record라 일부만 바꾸기 위한 작은 도우미 */
    public static final class ComposeInputBuilder {
        private ComposeInput in;

        ComposeInputBuilder(ComposeInput in) {
            this.in = in;
        }

        public ComposeInputBuilder schemaVersion(int v) {
            in = new ComposeInput(v, in.algorithmVersion(), in.seed(), in.issue(), in.newspaper(), in.layout(),
                    in.posts(), in.questionCorners(), in.birthdayNotices(), in.exclusions());
            return this;
        }

        public ComposeInputBuilder seed(long seed) {
            in = new ComposeInput(in.schemaVersion(), in.algorithmVersion(), seed, in.issue(), in.newspaper(),
                    in.layout(), in.posts(), in.questionCorners(), in.birthdayNotices(), in.exclusions());
            return this;
        }

        public ComposeInputBuilder layout(Layout l) {
            in = new ComposeInput(in.schemaVersion(), in.algorithmVersion(), in.seed(), in.issue(), in.newspaper(),
                    l, in.posts(), in.questionCorners(), in.birthdayNotices(), in.exclusions());
            return this;
        }

        public ComposeInputBuilder posts(List<Post> posts) {
            in = new ComposeInput(in.schemaVersion(), in.algorithmVersion(), in.seed(), in.issue(), in.newspaper(),
                    in.layout(), posts, in.questionCorners(), in.birthdayNotices(), in.exclusions());
            return this;
        }

        public ComposeInputBuilder corners(List<QuestionCorner> corners) {
            in = new ComposeInput(in.schemaVersion(), in.algorithmVersion(), in.seed(), in.issue(), in.newspaper(),
                    in.layout(), in.posts(), corners, in.birthdayNotices(), in.exclusions());
            return this;
        }

        public ComposeInputBuilder birthdays(List<BirthdayNotice> b) {
            in = new ComposeInput(in.schemaVersion(), in.algorithmVersion(), in.seed(), in.issue(), in.newspaper(),
                    in.layout(), in.posts(), in.questionCorners(), b, in.exclusions());
            return this;
        }

        ComposeInput build() {
            return in;
        }
    }
}
