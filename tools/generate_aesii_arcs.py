import math
import os
import struct
import zlib

from PIL import Image, ImageDraw, ImageFont


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "aesii"))

SIZE = 216
RPM_W = 205
RPM_H = 90
FUEL_W = 210
FUEL_H = 70
RPM_DIGIT_W = 24
RPM_DIGIT_H = 42
SCALE = 4
W = SIZE * SCALE
H = SIZE * SCALE
CENTER_X = 108 * SCALE
CENTER_Y = 127 * SCALE
RADIUS = 88 * SCALE
THICKNESS = 16 * SCALE
START_DEG = 180
END_DEG = 300

GREEN = (20, 220, 115, 255)
YELLOW = (255, 210, 0, 255)
RED = (250, 55, 55, 255)
GREY = (120, 130, 140, 255)
CYAN = (0, 190, 225, 255)
DARK = (8, 10, 14, 255)
BOX = (17, 21, 28, 255)
DIM = (42, 49, 58, 255)
LABEL = (155, 172, 186, 255)
WHITE = (255, 255, 255, 255)

FONT_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz./- "
FONT_VARIANTS = {
    "label": LABEL,
    "white": WHITE,
    "green": GREEN,
    "yellow": YELLOW,
    "red": RED,
}
FONT_SPECS = {
    "small": {"size": 17, "w": 11, "h": 20, "y": -1},
    "value": {"size": 24, "w": 17, "h": 28, "y": -2},
    "rpm": {"size": 31, "w": 20, "h": 35, "y": -3},
}
FONT_PATHS = (
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Avenir Next.ttc",
    "/System/Library/Fonts/Avenir.ttc",
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/SFCompact.ttf",
)
FONT_RENDER_SCALE = 4


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

    fill_rect(img, 15 * SCALE, 25 * SCALE, width - 30 * SCALE, 39 * SCALE, (2, 4, 6, 245))
    stroke_rect(img, 15 * SCALE, 25 * SCALE, width - 30 * SCALE, 39 * SCALE, (30, 40, 48, 255), SCALE)

    fill_rect(img, 16 * SCALE, 74 * SCALE, width - 32 * SCALE, SCALE, (238, 242, 244, 255))

    write_png(path, downsample(img, RPM_W, RPM_H))


def make_fuel_base(path):
    width = FUEL_W * SCALE
    height = FUEL_H * SCALE
    img = [[(0, 0, 0, 0) for _ in range(width)] for _ in range(height)]

    line_y = 43 * SCALE
    line_x = 10 * SCALE
    line_w = 130 * SCALE
    fill_rect(img, line_x, line_y, line_w, 2 * SCALE, (238, 242, 244, 255))
    fill_rect(img, line_x, line_y - 8 * SCALE, 2 * SCALE, 16 * SCALE, RED)
    fill_rect(img, line_x + line_w - 2 * SCALE, line_y - 2 * SCALE, 2 * SCALE, 4 * SCALE, (238, 242, 244, 255))

    write_png(path, downsample(img, FUEL_W, FUEL_H))


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


def draw_segment(img, name, color):
    w = RPM_DIGIT_W * SCALE
    h = RPM_DIGIT_H * SCALE
    t = 5 * SCALE
    inset = 4 * SCALE
    mid = h // 2

    segments = {
        "a": (inset + t, inset, w - 2 * (inset + t), t),
        "b": (w - inset - t, inset + t, t, mid - inset - t),
        "c": (w - inset - t, mid + t, t, h - mid - inset - 2 * t),
        "d": (inset + t, h - inset - t, w - 2 * (inset + t), t),
        "e": (inset, mid + t, t, h - mid - inset - 2 * t),
        "f": (inset, inset + t, t, mid - inset - t),
        "g": (inset + t, mid, w - 2 * (inset + t), t),
    }

    fill_rect(img, *segments[name], color)


def make_rpm_digit(path, char):
    width = RPM_DIGIT_W * SCALE
    height = RPM_DIGIT_H * SCALE
    img = [[(0, 0, 0, 0) for _ in range(width)] for _ in range(height)]
    active = SEGMENTS[char]

    for enabled, name in zip(active, ("a", "b", "c", "d", "e", "f", "g")):
        if enabled:
            draw_segment(img, name, RED)

    write_png(path, downsample(img, RPM_DIGIT_W, RPM_DIGIT_H))


def get_font(size):
    for path in FONT_PATHS:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                pass

    return ImageFont.load_default()


def make_font_glyphs():
    for font_name, spec in FONT_SPECS.items():
        scale = FONT_RENDER_SCALE
        font = get_font(spec["size"] * scale)

        for variant_name, color in FONT_VARIANTS.items():
            for char in FONT_CHARS:
                if char == " ":
                    continue

                image = Image.new(
                    "RGBA",
                    (spec["w"] * scale, spec["h"] * scale),
                    (0, 0, 0, 0),
                )
                draw = ImageDraw.Draw(image)
                bbox = draw.textbbox((0, 0), char, font=font)
                text_w = bbox[2] - bbox[0]
                text_h = bbox[3] - bbox[1]
                text_x = (spec["w"] * scale - text_w) // 2 - bbox[0]
                text_y = (
                    (spec["h"] * scale - text_h) // 2 -
                    bbox[1] +
                    spec["y"] * scale
                )

                draw.text(
                    (text_x, text_y),
                    char,
                    font=font,
                    fill=color,
                )

                image = image.resize(
                    (spec["w"], spec["h"]),
                    Image.Resampling.LANCZOS,
                )

                filename = "font_%s_%s_%04x.png" % (
                    font_name,
                    variant_name,
                    ord(char),
                )
                image.save(os.path.join(OUT_DIR, filename))


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
    make_fuel_base(os.path.join(OUT_DIR, "fuel_base.png"))

    for char in "0123456789-":
        suffix = "dash" if char == "-" else char
        make_rpm_digit(os.path.join(OUT_DIR, "rpm_" + suffix + ".png"), char)

    make_font_glyphs()


if __name__ == "__main__":
    main()
