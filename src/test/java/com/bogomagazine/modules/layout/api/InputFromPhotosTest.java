package com.bogomagazine.modules.layout.api;

import static org.junit.jupiter.api.Assertions.*;

import com.bogomagazine.modules.layout.tools.InputFromPhotos;
import com.bogomagazine.modules.layout.tools.InputFromPhotos.Options;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.FileTime;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/** 사진 폴더 → input.json 도구. 실제 사진 대신 테스트가 만든 작은 이미지(EXIF 회전·촬영 시각 포함)를 쓴다. */
class InputFromPhotosTest {
    private static final ObjectMapper M = new ObjectMapper();

    @TempDir Path tmp;

    /** 단색 이미지. exifOrientation > 0이면 JPEG에 EXIF(회전, 촬영 시각)를 끼워 넣는다. */
    private static void image(Path f, String fmt, int w, int h, int exifOrientation, String exifDate) throws IOException {
        var bos = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB), fmt, bos);
        byte[] img = bos.toByteArray();
        if (exifOrientation > 0) img = withExif(img, exifOrientation, exifDate);
        Files.write(f, img);
    }

    private static byte[] withExif(byte[] jpeg, int orientation, String date) {
        var t = ByteBuffer.allocate(76); // 빅엔디언 TIFF: IFD0(회전, ExifIFD 포인터) → ExifIFD(촬영 시각) → 문자열
        t.put((byte) 'M').put((byte) 'M').putShort((short) 0x2A).putInt(8);
        t.putShort((short) 2);
        t.putShort((short) 0x0112).putShort((short) 3).putInt(1).putShort((short) orientation).putShort((short) 0);
        t.putShort((short) 0x8769).putShort((short) 4).putInt(1).putInt(38);
        t.putInt(0);
        t.putShort((short) 1);
        t.putShort((short) 0x9003).putShort((short) 2).putInt(20).putInt(56);
        t.putInt(0);
        t.put(date.getBytes(StandardCharsets.US_ASCII)).put((byte) 0);
        var seg = ByteBuffer.allocate(2 + 2 + 6 + 76);
        seg.putShort((short) 0xFFE1).putShort((short) (2 + 6 + 76));
        seg.put("Exif\0\0".getBytes(StandardCharsets.US_ASCII)).put(t.array());
        var out = new ByteArrayOutputStream();
        out.write(jpeg, 0, 2); // SOI
        out.writeBytes(seg.array());
        out.write(jpeg, 2, jpeg.length - 2);
        return out.toByteArray();
    }

    private static void mtime(Path f, String iso) throws IOException {
        Files.setLastModifiedTime(f, FileTime.from(Instant.parse(iso)));
    }

    private Path folder() throws IOException {
        var dir = Files.createDirectory(tmp.resolve("photos"));
        image(dir.resolve("a.jpg"), "jpg", 400, 300, 6, "2026:10:07 19:30:00"); // 세로로 찍힌 사진: 보이는 크기 300x400
        image(dir.resolve("b.jpg"), "jpg", 400, 300, 0, null);
        mtime(dir.resolve("b.jpg"), "2026-10-08T03:00:00Z");
        Files.writeString(dir.resolve("b.txt"), "두번째 글", StandardCharsets.UTF_8);
        var trip = Files.createDirectory(dir.resolve("trip"));
        image(trip.resolve("1.png"), "png", 200, 200, 0, null);
        image(trip.resolve("2.png"), "png", 200, 100, 0, null);
        mtime(trip.resolve("1.png"), "2026-10-06T03:00:00Z");
        mtime(trip.resolve("2.png"), "2026-10-06T04:00:00Z");
        Files.writeString(trip.resolve("post.txt"), "여행 다녀왔어요", StandardCharsets.UTF_8);
        Files.writeString(dir.resolve("note.heic"), "not an image");
        return dir;
    }

    private Options options(Path photos, Set<Integer> ro) {
        return new Options(photos, tmp.resolve("out.json"), false, "보고잡지", 1,
                List.of(new String[] {"가상 가족 1", "c03"}, new String[] {"가상 가족 2", "c05"}), ro);
    }

    @Test
    void 폴더를_규격에_맞는_입력으로_바꾼다() throws Exception {
        var r = InputFromPhotos.run(options(folder(), Set.of()));
        assertEquals(List.of(), r.schemaErrors());
        assertEquals(3, r.posts());
        assertEquals(4, r.photos());
        assertTrue(r.skipped().stream().anyMatch(s -> s.startsWith("note.heic")), "HEIC는 건너뛰고 알려야 한다: " + r.skipped());

        var root = M.readTree(r.out().toFile());
        var posts = root.get("posts");
        // 시간순: 여행 폴더(10/6) → a.jpg(EXIF 10/7) → b.jpg(수정 시각 10/8)
        assertEquals("여행 다녀왔어요", posts.get(0).get("body").asText());
        assertEquals(2, posts.get(0).get("media").size());
        assertEquals("(설명 없음)", posts.get(1).get("body").asText());
        assertEquals("두번째 글", posts.get(2).get("body").asText());
        // EXIF 회전 6: 400x300 파일이 세로(300x400)로 기록된다
        var a = posts.get(1).get("media").get(0);
        assertEquals(300, a.get("width").asInt());
        assertEquals(400, a.get("height").asInt());
        // 파일 이름은 출력에 남지 않는다
        var text = Files.readString(r.out());
        for (String name : List.of("a.jpg", "b.jpg", "1.png", "trip", "note.heic")) assertFalse(text.contains(name), name + " 노출");
    }

    @Test
    void 만든_입력으로_조판해도_불변_조건을_지킨다() throws Exception {
        var r = InputFromPhotos.run(options(folder(), Set.of()));
        var in = InputJson.read(r.out());
        var out = new ReferenceLayoutEngine().compose(in);
        assertEquals(List.of(), OutputInvariants.check(in, out));
    }

    @Test
    void recipient_only_옵션은_해당_번호의_소식만_바꾼다() throws Exception {
        var r = InputFromPhotos.run(options(folder(), Set.of(2)));
        var posts = M.readTree(r.out().toFile()).get("posts");
        assertEquals("ALL", posts.get(0).get("visibility").asText());
        assertEquals("RECIPIENT_ONLY", posts.get(1).get("visibility").asText());
        assertEquals("ALL", posts.get(2).get("visibility").asText());
    }

    @Test
    void 이미_있는_출력은_force_없이는_덮어쓰지_않는다() throws Exception {
        var dir = folder();
        InputFromPhotos.run(options(dir, Set.of()));
        assertThrows(IllegalArgumentException.class, () -> InputFromPhotos.run(options(dir, Set.of())));
        var o = options(dir, Set.of());
        InputFromPhotos.run(new Options(o.photos(), o.out(), true, o.title(), o.seed(), o.authors(), o.recipientOnly()));
    }

    @Test
    void 읽을_사진이_없으면_실패한다() throws Exception {
        var empty = Files.createDirectory(tmp.resolve("empty"));
        Files.writeString(empty.resolve("x.heic"), "x");
        assertThrows(IllegalArgumentException.class, () -> InputFromPhotos.run(options(empty, Set.of())));
    }
}
