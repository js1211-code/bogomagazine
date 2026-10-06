package com.bogomagazine.modules.layout.tools;

import com.bogomagazine.modules.layout.api.InputSchema;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Stream;
import javax.imageio.ImageIO;

/**
 * 사진 폴더에서 조판 엔진 입력(input.json, schema_version 2)을 만드는 개발용 도구.
 * 사진 파일은 읽기만 하고 복사·수정하지 않는다. 픽셀 크기(EXIF 회전 반영)와 촬영 시각만 쓰며, 사진 내용은 보지 않는다.
 *
 * <pre>
 * 폴더 구조 → 소식(post)
 *   photos/a.jpg            파일 하나 = 소식 하나 (옆에 a.txt가 있으면 그 내용이 본문)
 *   photos/여행/1.jpg, 2.jpg   하위 폴더 하나 = 소식 하나, 사진 여러 장 (post.txt가 있으면 본문)
 * </pre>
 *
 * 초점은 사진 중앙(0.5, 0.5), 중요 영역은 비어 있다 (자동 감지는 하지 않는다). 파일 이름은 출력에 넣지 않는다.
 * 실행: {@code ./gradlew photoInput --args="<사진 폴더> [옵션]"}. 옵션은 {@link #USAGE}.
 */
public final class InputFromPhotos {
    private InputFromPhotos() {}

    public static final String USAGE = """
            사용법: photoInput --args="<사진 폴더> [옵션]"
              --out <파일>            기본 testdata/private/input.json (이 폴더는 .gitignore 대상)
              --force                 기존 출력 파일 덮어쓰기
              --title <제호>          신문 제호 (기본 보고잡지)
              --seed <정수>           기본 1
              --authors "라벨:캐릭터,..."  작성자를 소식 순서대로 돌려가며 배정 (기본 "가상 가족 1:c03,가상 가족 2:c05")
              --recipient-only 1,3    해당 번호(1부터, 시간순)의 소식을 "할머니께만"으로
            """;

    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    private static final Set<String> READABLE = Set.of("jpg", "jpeg", "png", "gif", "bmp");
    private static final ObjectMapper MAPPER = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT);

    public record Options(Path photos, Path out, boolean force, String title, long seed,
                          List<String[]> authors, Set<Integer> recipientOnly) {}

    public record Result(Path out, int posts, int photos, List<String> skipped, List<String> schemaErrors) {}

    public static void main(String[] args) throws IOException {
        Options o;
        try {
            o = parse(args);
        } catch (IllegalArgumentException e) {
            System.err.println(e.getMessage());
            System.err.println(USAGE);
            System.exit(2);
            return;
        }
        Result r;
        try {
            r = run(o);
        } catch (IllegalArgumentException e) {
            System.err.println(e.getMessage());
            System.exit(1);
            return;
        }
        System.out.printf("소식 %d개, 사진 %d장 → %s%n", r.posts(), r.photos(), r.out());
        for (String s : r.skipped()) System.out.println("건너뜀: " + s);
        if (!r.out().toAbsolutePath().normalize().startsWith(Path.of("testdata", "private").toAbsolutePath().normalize()))
            System.out.println("[주의] testdata/private/ 밖에 썼습니다. 실제 가족 사진 정보라면 커밋하지 마세요.");
        if (!r.schemaErrors().isEmpty()) {
            System.err.println("규격 위반 (생성은 했지만 엔진 입력으로 쓸 수 없음):");
            r.schemaErrors().forEach(e -> System.err.println("  " + e));
            System.exit(1);
        }
        System.out.println("규격 검사 통과. 다음: ./gradlew test (testdata/private/*.json을 자동으로 검사합니다)");
    }

    static Options parse(String[] args) {
        if (args.length == 0 || args[0].startsWith("--")) throw new IllegalArgumentException("사진 폴더가 필요합니다.");
        Path out = Path.of("testdata", "private", "input.json");
        boolean force = false;
        String title = "보고잡지";
        long seed = 1;
        var authors = new ArrayList<String[]>();
        var ro = new HashSet<Integer>();
        for (int i = 1; i < args.length; i++) {
            switch (args[i]) {
                case "--force" -> force = true;
                case "--out" -> out = Path.of(value(args, ++i));
                case "--title" -> title = value(args, ++i);
                case "--seed" -> seed = Long.parseLong(value(args, ++i));
                case "--authors" -> {
                    for (String a : value(args, ++i).split(",")) {
                        int c = a.lastIndexOf(':');
                        if (c <= 0 || c == a.length() - 1) throw new IllegalArgumentException("--authors는 라벨:캐릭터 형식: " + a);
                        authors.add(new String[] {a.substring(0, c).trim(), a.substring(c + 1).trim()});
                    }
                }
                case "--recipient-only" -> {
                    for (String n : value(args, ++i).split(",")) ro.add(Integer.parseInt(n.trim()));
                }
                default -> throw new IllegalArgumentException("알 수 없는 옵션: " + args[i]);
            }
        }
        if (authors.isEmpty()) authors.addAll(List.of(new String[] {"가상 가족 1", "c03"}, new String[] {"가상 가족 2", "c05"}));
        return new Options(Path.of(args[0]), out, force, title, seed, authors, ro);
    }

    private static String value(String[] args, int i) {
        if (i >= args.length) throw new IllegalArgumentException(args[i - 1] + " 값이 없습니다.");
        return args[i];
    }

    // --- 본체 -------------------------------------------------------------------------------

    private record Photo(Path file, int width, int height, LocalDateTime taken) {}

    private record Group(List<Photo> photos, String body, LocalDateTime time) {}

    public static Result run(Options o) throws IOException {
        if (!Files.isDirectory(o.photos())) throw new IllegalArgumentException("폴더가 아닙니다: " + o.photos());
        if (Files.exists(o.out()) && !o.force())
            throw new IllegalArgumentException("이미 있습니다. 덮어쓰려면 --force: " + o.out());

        var skipped = new ArrayList<String>();
        var groups = new ArrayList<Group>();
        try (Stream<Path> s = Files.list(o.photos())) {
            for (Path p : s.sorted().toList()) {
                if (Files.isDirectory(p)) {
                    var photos = readAll(p, skipped);
                    if (!photos.isEmpty()) groups.add(group(photos, p.resolve("post.txt")));
                } else if (isImage(p)) {
                    var ph = read(p, skipped);
                    if (ph != null) groups.add(group(List.of(ph), sibling(p, ".txt")));
                } else if (!p.getFileName().toString().endsWith(".txt")) {
                    skipped.add(p.getFileName() + " (지원하지 않는 형식: jpg, png, gif, bmp만 읽음. HEIC는 JPEG로 변환 필요)");
                }
            }
        }
        if (groups.isEmpty()) throw new IllegalArgumentException("읽을 수 있는 사진이 없습니다: " + o.photos());
        groups.sort(Comparator.comparing(Group::time));

        var root = MAPPER.createObjectNode();
        root.put("schema_version", 2).put("algorithm_version", "0.1.0").put("seed", o.seed());
        var first = groups.get(0).time().toLocalDate();
        var issue = root.putObject("issue");
        issue.put("id", "local-issue").put("number", 1);
        issue.putObject("period").put("start", first.toString()).put("end", first.plusDays(13).toString());
        var np = root.putObject("newspaper");
        np.put("title", o.title());
        np.putObject("recipient").put("name", "받는 분").put("type", "SINGLE").put("character", "c07");
        var layout = root.putObject("layout");
        layout.putArray("trim_mm").add(210).add(297);
        layout.put("margin_mm", 15).put("bleed_mm", 3).put("min_body_pt", 12).put("target_dpi", 300).put("page_multiple", 4);
        layout.putArray("page_range").add(4).add(16);
        layout.putArray("fonts");

        var posts = root.putArray("posts");
        int mediaNo = 0, photoCount = 0;
        for (int i = 0; i < groups.size(); i++) {
            var g = groups.get(i);
            var post = posts.addObject();
            post.put("id", "p" + (i + 1));
            post.put("posted_at", OffsetDateTime.of(g.time(), KST.getRules().getOffset(g.time())).toString());
            post.put("visibility", o.recipientOnly().contains(i + 1) ? "RECIPIENT_ONLY" : "ALL");
            var a = o.authors().get(i % o.authors().size());
            post.putObject("author").put("label", a[0]).put("character", a[1]);
            post.put("body", g.body());
            ArrayNode media = post.putArray("media");
            for (Photo ph : g.photos()) {
                mediaNo++;
                photoCount++;
                var m = media.addObject();
                m.put("id", "m" + mediaNo).put("key", "local/p" + (i + 1) + "/m" + mediaNo + "/original");
                m.put("width", ph.width()).put("height", ph.height());
                m.putObject("focal_point").put("x", 0.5).put("y", 0.5);
                m.putArray("saliency");
            }
        }
        root.putArray("question_corners");
        root.putArray("birthday_notices");
        root.putArray("exclusions");

        var errors = InputSchema.validate(root);
        if (o.out().getParent() != null) Files.createDirectories(o.out().getParent());
        Files.writeString(o.out(), MAPPER.writeValueAsString(root) + "\n", StandardCharsets.UTF_8);
        return new Result(o.out(), groups.size(), photoCount, skipped, errors);
    }

    private static Group group(List<Photo> photos, Path bodyFile) throws IOException {
        var sorted = new ArrayList<>(photos);
        sorted.sort(Comparator.comparing(Photo::taken).thenComparing(p -> p.file().getFileName().toString()));
        String body = Files.isRegularFile(bodyFile) ? Files.readString(bodyFile, StandardCharsets.UTF_8).strip() : "";
        if (body.isEmpty()) body = "(설명 없음)";
        return new Group(sorted, body, sorted.get(0).taken());
    }

    private static Path sibling(Path photo, String ext) {
        String n = photo.getFileName().toString();
        return photo.resolveSibling(n.substring(0, n.lastIndexOf('.')) + ext);
    }

    private static List<Photo> readAll(Path dir, List<String> skipped) throws IOException {
        var out = new ArrayList<Photo>();
        try (Stream<Path> s = Files.list(dir)) {
            for (Path p : s.sorted().toList()) {
                if (Files.isRegularFile(p) && isImage(p)) {
                    var ph = read(p, skipped);
                    if (ph != null) out.add(ph);
                } else if (Files.isRegularFile(p) && !p.getFileName().toString().equals("post.txt")) {
                    skipped.add(dir.getFileName() + "/" + p.getFileName() + " (지원하지 않는 형식)");
                }
            }
        }
        return out;
    }

    private static boolean isImage(Path p) {
        String n = p.getFileName().toString().toLowerCase();
        int dot = n.lastIndexOf('.');
        return dot > 0 && READABLE.contains(n.substring(dot + 1));
    }

    /** 헤더만 읽어 크기를 얻는다 (사진 전체를 디코딩하지 않으므로 메모리를 쓰지 않는다). */
    private static Photo read(Path p, List<String> skipped) throws IOException {
        try (var iis = ImageIO.createImageInputStream(p.toFile())) {
            var readers = iis == null ? null : ImageIO.getImageReaders(iis);
            if (readers == null || !readers.hasNext()) {
                skipped.add(p.getFileName() + " (이미지로 읽을 수 없음)");
                return null;
            }
            var reader = readers.next();
            try {
                reader.setInput(iis);
                int w = reader.getWidth(0), h = reader.getHeight(0);
                var exif = Exif.read(p);
                if (exif.orientation >= 5 && exif.orientation <= 8) { // 90도/270도 회전: 보이는 크기는 가로세로가 바뀐다
                    int t = w;
                    w = h;
                    h = t;
                }
                LocalDateTime taken = exif.taken != null ? exif.taken
                        : LocalDateTime.ofInstant(Instant.ofEpochMilli(Files.getLastModifiedTime(p).toMillis()), KST);
                return new Photo(p, w, h, taken.withNano(0));
            } finally {
                reader.dispose();
            }
        } catch (IOException | RuntimeException e) {
            skipped.add(p.getFileName() + " (읽기 실패: " + e.getClass().getSimpleName() + ")");
            return null;
        }
    }

    /** JPEG의 EXIF에서 회전(0x0112)과 촬영 시각(0x9003)만 읽는다. 없거나 깨졌으면 기본값. */
    static final class Exif {
        final int orientation;
        final LocalDateTime taken;
        private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy:MM:dd HH:mm:ss");

        private Exif(int orientation, LocalDateTime taken) {
            this.orientation = orientation;
            this.taken = taken;
        }

        static Exif read(Path f) {
            try (var in = new DataInputStream(new BufferedInputStream(Files.newInputStream(f)))) {
                if (in.readUnsignedShort() != 0xFFD8) return new Exif(1, null);
                while (true) {
                    int marker = in.readUnsignedShort();
                    if ((marker & 0xFF00) != 0xFF00 || marker == 0xFFDA || marker == 0xFFD9) return new Exif(1, null);
                    int len = in.readUnsignedShort() - 2;
                    if (len < 0) return new Exif(1, null);
                    if (marker == 0xFFE1 && len >= 6) {
                        byte[] seg = in.readNBytes(len);
                        if (seg.length >= 6 && new String(seg, 0, 4, StandardCharsets.US_ASCII).equals("Exif"))
                            return tiff(Arrays.copyOfRange(seg, 6, seg.length));
                    } else {
                        in.skipNBytes(len);
                    }
                }
            } catch (IOException | RuntimeException e) {
                return new Exif(1, null);
            }
        }

        private static Exif tiff(byte[] t) {
            var b = ByteBuffer.wrap(t);
            b.order(t[0] == 'I' ? ByteOrder.LITTLE_ENDIAN : ByteOrder.BIG_ENDIAN);
            int[] orientation = {1};
            LocalDateTime[] taken = {null};
            ifd(b, b.getInt(4), orientation, taken, 0);
            return new Exif(orientation[0], taken[0]);
        }

        private static void ifd(ByteBuffer b, int off, int[] orientation, LocalDateTime[] taken, int depth) {
            if (depth > 2 || off <= 0 || off + 2 > b.limit()) return;
            int n = b.getShort(off) & 0xFFFF;
            for (int i = 0; i < n; i++) {
                int e = off + 2 + 12 * i;
                if (e + 12 > b.limit()) return;
                int tag = b.getShort(e) & 0xFFFF;
                if (tag == 0x0112) orientation[0] = b.getShort(e + 8) & 0xFFFF;
                else if (tag == 0x8769) ifd(b, b.getInt(e + 8), orientation, taken, depth + 1);
                else if (tag == 0x9003) {
                    int vo = b.getInt(e + 8);
                    if (vo > 0 && vo + 19 <= b.limit()) {
                        byte[] s = new byte[19];
                        b.get(vo, s);
                        try {
                            taken[0] = LocalDateTime.parse(new String(s, StandardCharsets.US_ASCII), FMT);
                        } catch (RuntimeException ignored) {
                            // 촬영 시각을 못 읽으면 파일 수정 시각을 쓴다
                        }
                    }
                }
            }
        }
    }

}
