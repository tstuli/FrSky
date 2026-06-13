import math
import os
import struct
import zlib


OUT_DIR = (
    "/Users/taruntuli/Documents/Ethos Simulator/26.1.0-RC4/"
    "persist/X20PROAW/scripts/aesii"
)

SIZE = 192
RPM_W = 175
RPM_H = 90
RPM_DIGIT_W = 24
RPM_DIGIT_H = 42
SCALE = 4
W = SIZE * SCALE
H = SIZE * SCALE
CENTER_X = 96 * SCALE
CENTER_Y = 113 * SCALE
RADIUS = 77 * SCALE
THICKNESS = 14 * SCALE
START_DEG = 195
END_DEG = 335

GREEN = (20, 220, 115, 255)
YELLOW = (255, 210, 0, 255)
RED = (250, 55, 55, 255)
GREY = (120, 130, 140, 255)
CYAN = (0, 190, 225, 255)
DARK = (8, 10, 14, 255)
BOX = (17, 21, 28, 255)
DIM = (42, 49, 58, 255)


def color_for_pos(pos, zones):
    color = zones[-1][2]

    for start, end, zone_color in zones:
        if start <= pos <= end:
            color = zone_color
            break

    return color


def blend_over(dst, src, alpha):
    sr, sg, sb, _ = src
    dr, dg, db, da = dst
    sa = int(255 * alpha + 0.5)

    if sa <= 0:
        return dst

    out_a = sa + da * (255 - sa) // 255

    if out_a <= 0:
        return (0, 0, 0, 0)

    return (
        (sr * sa + dr * da * (255 - sa) // 255) // out_a,
        (sg * sa + dg * da * (255 - sa) // 255) // out_a,
        (sb * sa + db * da * (255 - sa) // 255) // out_a,
        out_a,
    )


def draw_arc_band(img, inner, outer, zones):
    sweep = END_DEG - START_DEG
    samples = 4
    sample_count = samples * samples

    for y in range(H):
        for x in range(W):
            coverage = 0
            rs = gs = bs = 0

            for sy in range(samples):
                for sx in range(samples):
                    dx = x + (sx + 0.5) / samples - CENTER_X
                    dy = y + (sy + 0.5) / samples - CENTER_Y
                    distance = math.sqrt(dx * dx + dy * dy)

                    if distance < inner or distance > outer:
                        continue

                    angle = math.degrees(math.atan2(dy, dx))

                    if angle < 0:
                        angle = angle + 360

                    if angle < START_DEG or angle > END_DEG:
                        continue

                    pos = (angle - START_DEG) / sweep
                    r, g, b, _ = color_for_pos(pos, zones)
                    coverage += 1
                    rs += r
                    gs += g
                    bs += b

            if coverage > 0:
                color = (
                    int(rs / coverage + 0.5),
                    int(gs / coverage + 0.5),
                    int(bs / coverage + 0.5),
                    255,
                )
                img[y][x] = blend_over(
                    img[y][x],
                    color,
                    coverage / sample_count,
                )


def draw_arc(img, zones):
    draw_arc_band(
        img,
        RADIUS - THICKNESS - 4 * SCALE,
        RADIUS + 2 * SCALE,
        [(0.0, 1.0, GREY)],
    )

    draw_arc_band(
        img,
        RADIUS - THICKNESS,
        RADIUS,
        zones,
    )


def downsample(img, out_w, out_h):
    out = []
    for y in range(out_h):
        row = []
        for x in range(out_w):
            rs = gs = bs = alphas = 0
            for yy in range(SCALE):
                for xx in range(SCALE):
                    r, g, b, a = img[y * SCALE + yy][x * SCALE + xx]
                    rs += r * a
                    gs += g * a
                    bs += b * a
                    alphas += a

            count = SCALE * SCALE
            a = int(alphas / count + 0.5)
            if alphas:
                row.append((
                    int(rs / alphas + 0.5),
                    int(gs / alphas + 0.5),
                    int(bs / alphas + 0.5),
                    a,
                ))
            else:
                row.append((0, 0, 0, 0))
        out.append(row)
    return out


def write_png(path, img):
    height = len(img)
    width = len(img[0]) if height else 0
    raw = bytearray()
    for row in img:
        raw.append(0)
        for px in row:
            raw.extend(px)

    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
    png.extend(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
    png.extend(chunk(b"IEND", b""))

    with open(path, "wb") as handle:
        handle.write(png)


def make(path, zones):
    img = [[(0, 0, 0, 0) for _ in range(W)] for _ in range(H)]
    draw_arc(img, zones)
    write_png(path, downsample(img, SIZE, SIZE))


def fill_rect(img, x, y, w, h, color):
    height = len(img)
    width = len(img[0]) if height else 0

    for yy in range(max(0, y), min(height, y + h)):
        for xx in range(max(0, x), min(width, x + w)):
            img[yy][xx] = color


def stroke_rect(img, x, y, w, h, color, thickness=1):
    fill_rect(img, x, y, w, thickness, color)
    fill_rect(img, x, y + h - thickness, w, thickness, color)
    fill_rect(img, x, y, thickness, h, color)
    fill_rect(img, x + w - thickness, y, thickness, h, color)


def make_rpm_base(path):
    width = RPM_W * SCALE
    height = RPM_H * SCALE
    img = [[(0, 0, 0, 0) for _ in range(width)] for _ in range(height)]

    fill_rect(img, 0, 0, width, height, BOX)
    stroke_rect(img, 0, 0, width, height, CYAN, 2 * SCALE)
    stroke_rect(img, 4 * SCALE, 4 * SCALE, width - 8 * SCALE, height - 8 * SCALE, (0, 92, 112, 255), SCALE)

    fill_rect(img, 12 * SCALE, 26 * SCALE, width - 24 * SCALE, 38 * SCALE, DARK)
    stroke_rect(img, 12 * SCALE, 26 * SCALE, width - 24 * SCALE, 38 * SCALE, (20, 34, 44, 255), SCALE)

    fill_rect(img, 14 * SCALE, 72 * SCALE, width - 28 * SCALE, 5 * SCALE, DIM)
    fill_rect(img, 14 * SCALE, 80 * SCALE, width - 28 * SCALE, SCALE, (2, 125, 160, 255))

    write_png(path, downsample(img, RPM_W, RPM_H))


SEGMENTS = {
    "0": (True, True, True, True, True, True, False),
    "1": (False, True, True, False, False, False, False),
    "2": (True, True, False, True, True, False, True),
    "3": (True, True, True, True, False, False, True),
    "4": (False, True, True, False, False, True, True),
    "5": (True, False, True, True, False, True, True),
    "6": (True, False, True, True, True, True, True),
    "7": (True, True, True, False, False, False, False),
    "8": (True, True, True, True, True, True, True),
    "9": (True, True, True, True, False, True, True),
    "-": (False, False, False, False, False, False, True),
}


def point_in_poly(px, py, points):
    inside = False
    j = len(points) - 1

    for i, point in enumerate(points):
        xi, yi = point
        xj, yj = points[j]

        if ((yi > py) != (yj > py)) and (
            px < (xj - xi) * (py - yi) / (yj - yi) + xi
        ):
            inside = not inside

        j = i

    return inside


def fill_poly_aa(img, points, color):
    samples = 4
    sample_count = samples * samples
    min_x = max(0, int(math.floor(min(p[0] for p in points))))
    max_x = min(len(img[0]) - 1, int(math.ceil(max(p[0] for p in points))))
    min_y = max(0, int(math.floor(min(p[1] for p in points))))
    max_y = min(len(img) - 1, int(math.ceil(max(p[1] for p in points))))

    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            coverage = 0

            for sy in range(samples):
                for sx in range(samples):
                    if point_in_poly(
                        x + (sx + 0.5) / samples,
                        y + (sy + 0.5) / samples,
                        points,
                    ):
                        coverage += 1

            if coverage:
                img[y][x] = blend_over(
                    img[y][x],
                    color,
                    coverage / sample_count,
                )


def draw_segment(img, name, color):
    w = RPM_DIGIT_W * SCALE
    h = RPM_DIGIT_H * SCALE
    t = 6 * SCALE
    inset = 3 * SCALE
    slant = 3 * SCALE
    mid = h / 2

    segments = {
        "a": [
            (inset + slant, inset),
            (w - inset - slant, inset),
            (w - inset - 2 * slant, inset + t),
            (inset + 2 * slant, inset + t),
        ],
        "b": [
            (w - inset - t, inset + slant),
            (w - inset, inset + 2 * slant),
            (w - inset, mid - slant),
            (w - inset - t, mid - t / 2),
        ],
        "c": [
            (w - inset - t, mid + t / 2),
            (w - inset, mid + slant),
            (w - inset, h - inset - 2 * slant),
            (w - inset - t, h - inset - slant),
        ],
        "d": [
            (inset + 2 * slant, h - inset - t),
            (w - inset - 2 * slant, h - inset - t),
            (w - inset - slant, h - inset),
            (inset + slant, h - inset),
        ],
        "e": [
            (inset, mid + slant),
            (inset + t, mid + t / 2),
            (inset + t, h - inset - slant),
            (inset, h - inset - 2 * slant),
        ],
        "f": [
            (inset, inset + 2 * slant),
            (inset + t, inset + slant),
            (inset + t, mid - t / 2),
            (inset, mid - slant),
        ],
        "g": [
            (inset + 2 * slant, mid - t / 2),
            (w - inset - 2 * slant, mid - t / 2),
            (w - inset - slant, mid),
            (w - inset - 2 * slant, mid + t / 2),
            (inset + 2 * slant, mid + t / 2),
            (inset + slant, mid),
        ],
    }

    fill_poly_aa(img, segments[name], color)


def make_rpm_digit(path, char):
    width = RPM_DIGIT_W * SCALE
    height = RPM_DIGIT_H * SCALE
    img = [[(0, 0, 0, 0) for _ in range(width)] for _ in range(height)]
    active = SEGMENTS[char]

    for enabled, name in zip(active, ("a", "b", "c", "d", "e", "f", "g")):
        if enabled:
            draw_segment(img, name, RED)

    write_png(path, downsample(img, RPM_DIGIT_W, RPM_DIGIT_H))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    make(
        os.path.join(OUT_DIR, "arc_temp.png"),
        [
            (0.00, (90 - 10) / (150 - 10), GREEN),
            ((90 - 10) / (150 - 10), (100 - 10) / (150 - 10), YELLOW),
            ((100 - 10) / (150 - 10), 1.00, RED),
        ],
    )
    make(
        os.path.join(OUT_DIR, "arc_batt.png"),
        [
            (0.00, (7.2 - 6.0) / (8.4 - 6.0), RED),
            ((7.2 - 6.0) / (8.4 - 6.0), (7.6 - 6.0) / (8.4 - 6.0), YELLOW),
            ((7.6 - 6.0) / (8.4 - 6.0), 1.00, GREEN),
        ],
    )
    make_rpm_base(os.path.join(OUT_DIR, "rpm_base.png"))

    for char in "0123456789-":
        suffix = "dash" if char == "-" else char
        make_rpm_digit(os.path.join(OUT_DIR, "rpm_" + suffix + ".png"), char)


if __name__ == "__main__":
    main()
