import argparse
import math
import os
import struct
import zlib

from PIL import Image, ImageDraw, ImageFont


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "aesii"))
IMAGE_DIR = os.path.join(OUT_DIR, "images")

SIZE = 216
FUEL_W = 210
FUEL_H = 70
FUEL_REMAINING_W = 182
FUEL_REMAINING_H = 70
FUEL_FLOW_W = 182
FUEL_FLOW_H = 70
RPM_W = 205
RPM_H = 70
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
SHADOW_LIGHT = (92, 98, 106, 255)
CYAN = (0, 190, 225, 255)
DARK = (8, 10, 14, 255)
BOX = (17, 21, 28, 255)
DIM = (42, 49, 58, 255)
LABEL = (155, 172, 186, 255)
WHITE = (255, 255, 255, 255)

FONT_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ./- "
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
FONT_GENERATION = {
    "small": {
        "chars": FONT_CHARS,
        "variants": ("label", "green", "yellow"),
    },
}
LABEL_ASSETS = (
    ("ign_label", "IGN", "small", "label"),
    ("ign_green", "IGN", "small", "green"),
    ("off_label", "OFF", "small", "label"),
    ("gyro_yellow", "GYRO", "small", "yellow"),
    ("stab_green", "STAB", "small", "green"),
)
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


def draw_arc_shadow(img, inner, outer):
    sweep = END_DEG - START_DEG
    samples = 4
    sample_count = samples * samples
    bayer = (
        (0, 48, 12, 60, 3, 51, 15, 63),
        (32, 16, 44, 28, 35, 19, 47, 31),
        (8, 56, 4, 52, 11, 59, 7, 55),
        (40, 24, 36, 20, 43, 27, 39, 23),
        (2, 50, 14, 62, 1, 49, 13, 61),
        (34, 18, 46, 30, 33, 17, 45, 29),
        (10, 58, 6, 54, 9, 57, 5, 53),
        (42, 26, 38, 22, 41, 25, 37, 21),
    )

    for y in range(H):
        for x in range(W):
            coverage = 0
            radial_total = 0.0

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

                    coverage += 1
                    radial_total += (distance - inner) / (outer - inner)

            if coverage <= 0:
                continue

            radial = radial_total / coverage
            shaped = radial * radial
            alpha = 0.16 + shaped * 0.68
            threshold = (bayer[y % 8][x % 8] + 0.5) / 64.0

            if threshold > alpha:
                continue

            color = lerp_color(
                (30, 35, 42, 255),
                (128, 138, 150, 255),
                shaped,
            )

            img[y][x] = blend_over(
                img[y][x],
                color,
                coverage / sample_count,
            )


def lerp_color(a, b, t):
    return (
        int(a[0] + (b[0] - a[0]) * t + 0.5),
        int(a[1] + (b[1] - a[1]) * t + 0.5),
        int(a[2] + (b[2] - a[2]) * t + 0.5),
        255,
    )


def draw_arc_end_line(img, angle_deg, outer_radius, inner_radius):
    angle = math.radians(angle_deg)
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    tangent_x = -sin_a
    tangent_y = cos_a
    x1 = CENTER_X + cos_a * inner_radius
    y1 = CENTER_Y + sin_a * inner_radius
    x2 = CENTER_X + cos_a * outer_radius
    y2 = CENTER_Y + sin_a * outer_radius

    steps = max(1, int(math.hypot(x2 - x1, y2 - y1) * 2))

    for step in range(steps + 1):
        t = step / steps
        x = int(x1 + (x2 - x1) * t + 0.5)
        y = int(y1 + (y2 - y1) * t + 0.5)

        for ox, oy in ((0, 0), (int(round(tangent_x)), int(round(tangent_y)))):
            px = x + ox
            py = y + oy

            if 0 <= px < W and 0 <= py < H:
                img[py][px] = blend_over(img[py][px], WHITE, 1.0)


def draw_arc(img, zones):
    shadow_outer = RADIUS - 6 * SCALE
    color_thickness = max(6 * SCALE, math.floor(THICKNESS * 0.098))
    shadow_depth = max(28 * SCALE, THICKNESS + 22 * SCALE)

    draw_arc_shadow(
        img,
        shadow_outer - shadow_depth,
        shadow_outer,
    )

    draw_arc_band(
        img,
        RADIUS - color_thickness,
        RADIUS,
        zones,
    )

    line_inner = shadow_outer - shadow_depth + 1
    for angle in (START_DEG, END_DEG):
        draw_arc_end_line(
            img,
            angle,
            RADIUS,
            line_inner,
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


def rgba_rows_to_image(img):
    height = len(img)
    width = len(img[0]) if height else 0
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    pixels = image.load()

    for y, row in enumerate(img):
        for x, px in enumerate(row):
            pixels[x, y] = px

    return image


def crop_transparent_image(image, padding=1):
    bbox = image.getbbox()

    if bbox is None:
        return image, 0, 0

    left, top, right, bottom = bbox
    left = max(0, left - padding)
    top = max(0, top - padding)
    right = min(image.width, right + padding)
    bottom = min(image.height, bottom + padding)

    return image.crop((left, top, right, bottom)), left, top


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
    downsampled = downsample(img, SIZE, SIZE)
    image = rgba_rows_to_image(downsampled)
    cropped, _, _ = crop_transparent_image(image, padding=1)
    cropped.save(path)


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


def draw_label(draw, font, text, x, y, color):
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    draw.text(
        (x - text_w // 2 - bbox[0], y - text_h // 2 - bbox[1]),
        text,
        font=font,
        fill=color,
    )


def make_fuel_remaining_base(path):
    width = FUEL_REMAINING_W * SCALE
    height = FUEL_REMAINING_H * SCALE
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    font = get_font(16 * SCALE)

    line_x = 9 * SCALE
    line_y = 35 * SCALE
    line_w = 170 * SCALE
    line_h = 3 * SCALE
    red_w = 6 * SCALE
    quarter = line_w / 4
    shadow = (46, 52, 60, 200)

    draw.rectangle(
        [line_x, line_y, line_x + red_w, line_y + line_h],
        fill=RED,
    )
    draw.rectangle(
        [line_x + red_w, line_y, line_x + line_w, line_y + line_h],
        fill=(238, 242, 244, 255),
    )
    draw.rectangle(
        [line_x, line_y + 2 * SCALE, line_x + line_w, line_y + line_h + 2 * SCALE],
        fill=shadow,
    )

    for fraction in (0.25, 0.50, 0.75):
        marker_x = int(line_x + quarter * fraction * 4 + 0.5)
        draw.rectangle(
            [marker_x - SCALE // 2 + SCALE, line_y - 6 * SCALE + SCALE, marker_x + SCALE // 2 + SCALE, line_y + 8 * SCALE + SCALE],
            fill=shadow,
        )
        draw.rectangle(
            [marker_x - SCALE // 2, line_y - 6 * SCALE, marker_x + SCALE // 2, line_y + 8 * SCALE],
            fill=(238, 242, 244, 255),
        )

    draw.rectangle([line_x + SCALE, line_y - 7 * SCALE + SCALE, line_x + 3 * SCALE + SCALE, line_y + 9 * SCALE + SCALE], fill=shadow)
    draw.rectangle([line_x, line_y - 7 * SCALE, line_x + 3 * SCALE, line_y + 9 * SCALE], fill=RED)
    draw.rectangle([line_x + int(quarter) + SCALE, line_y - 5 * SCALE + SCALE, line_x + int(quarter) + 2 * SCALE + SCALE, line_y + 7 * SCALE + SCALE], fill=shadow)
    draw.rectangle([line_x + int(quarter), line_y - 5 * SCALE, line_x + int(quarter) + 2 * SCALE, line_y + 7 * SCALE], fill=(238, 242, 244, 255))
    draw.rectangle([line_x + int(quarter * 2) + SCALE, line_y - 5 * SCALE + SCALE, line_x + int(quarter * 2) + 2 * SCALE + SCALE, line_y + 7 * SCALE + SCALE], fill=shadow)
    draw.rectangle([line_x + int(quarter * 2), line_y - 5 * SCALE, line_x + int(quarter * 2) + 2 * SCALE, line_y + 7 * SCALE], fill=(238, 242, 244, 255))
    draw.rectangle([line_x + int(quarter * 3) + SCALE, line_y - 5 * SCALE + SCALE, line_x + int(quarter * 3) + 2 * SCALE + SCALE, line_y + 7 * SCALE + SCALE], fill=shadow)
    draw.rectangle([line_x + int(quarter * 3), line_y - 5 * SCALE, line_x + int(quarter * 3) + 2 * SCALE, line_y + 7 * SCALE], fill=(238, 242, 244, 255))
    draw.rectangle([line_x + line_w - 3 * SCALE + SCALE, line_y - 7 * SCALE + SCALE, line_x + line_w + SCALE, line_y + 9 * SCALE + SCALE], fill=shadow)
    draw.rectangle([line_x + line_w - 3 * SCALE, line_y - 7 * SCALE, line_x + line_w, line_y + 9 * SCALE], fill=GREEN)

    draw_label(draw, font, "FUEL QTY", width // 2 - 45 * SCALE, 12 * SCALE, LABEL)
    draw_label(draw, font, "0", line_x, 58 * SCALE, LABEL)
    draw_label(draw, font, "25", line_x + quarter, 58 * SCALE, LABEL)
    draw_label(draw, font, "50", line_x + quarter * 2, 58 * SCALE, LABEL)
    draw_label(draw, font, "75", line_x + quarter * 3, 58 * SCALE, LABEL)
    draw_label(draw, font, "F", line_x + line_w, 58 * SCALE, LABEL)

    img = img.resize(
        (FUEL_REMAINING_W, FUEL_REMAINING_H),
        Image.Resampling.LANCZOS,
    )
    img.save(path)


def make_fuel_flow_base(path):
    width = FUEL_FLOW_W * SCALE
    height = FUEL_FLOW_H * SCALE
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    font = get_font(16 * SCALE)

    line_x = 9 * SCALE
    line_y = 35 * SCALE
    line_w = 170 * SCALE
    line_h = 3 * SCALE
    red_w = 6 * SCALE
    yellow_start = int(line_x + line_w * 0.80)
    shadow = (46, 52, 60, 200)

    draw.rectangle(
        [line_x, line_y, line_x + red_w, line_y + line_h],
        fill=WHITE,
    )
    draw.rectangle(
        [line_x + red_w, line_y, yellow_start, line_y + line_h],
        fill=(238, 242, 244, 255),
    )
    draw.rectangle(
        [yellow_start, line_y, line_x + line_w, line_y + line_h],
        fill=WHITE,
    )
    draw.rectangle(
        [line_x, line_y + 2 * SCALE, line_x + line_w, line_y + line_h + 2 * SCALE],
        fill=shadow,
    )

    draw_label(draw, font, "FF ML/MIN", width // 2 - 45 * SCALE, 12 * SCALE, LABEL)
    draw.rectangle(
        [line_x, line_y - 7 * SCALE, line_x + 2 * SCALE, line_y + 9 * SCALE],
        fill=WHITE,
    )
    draw.rectangle(
        [line_x + line_w - 2 * SCALE, line_y - 7 * SCALE, line_x + line_w, line_y + 9 * SCALE],
        fill=WHITE,
    )

    img = img.resize(
        (FUEL_FLOW_W, FUEL_FLOW_H),
        Image.Resampling.LANCZOS,
    )
    img.save(path)


def make_rpm_base(path):
    width = RPM_W * SCALE
    height = RPM_H * SCALE
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    font = get_font(16 * SCALE)
    shadow = (46, 52, 60, 200)

    line_x = 20 * SCALE
    line_y = 37 * SCALE
    line_w = 170 * SCALE
    line_h = 3 * SCALE

    draw_label(draw, font, "RPM", 36 * SCALE, 10 * SCALE, LABEL)

    draw.rectangle(
        [line_x, line_y, line_x + line_w, line_y + line_h],
        fill=(238, 242, 244, 255),
    )
    draw.rectangle(
        [line_x, line_y + 2 * SCALE, line_x + line_w, line_y + line_h + 2 * SCALE],
        fill=shadow,
    )
    draw.rectangle(
        [line_x, line_y - 7 * SCALE, line_x + 2 * SCALE, line_y + 9 * SCALE],
        fill=WHITE,
    )
    draw.rectangle(
        [line_x + line_w - 2 * SCALE, line_y - 7 * SCALE, line_x + line_w, line_y + 9 * SCALE],
        fill=WHITE,
    )

    img = img.resize((RPM_W, RPM_H), Image.Resampling.LANCZOS)
    img.save(path)


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
        generation = FONT_GENERATION.get(font_name)

        if generation is None:
            continue

        scale = FONT_RENDER_SCALE
        font = get_font(spec["size"] * scale)

        for variant_name in generation["variants"]:
            color = FONT_VARIANTS[variant_name]

            for char in generation["chars"]:
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
                image.save(os.path.join(IMAGE_DIR, filename))


def render_text_asset(path, text, font_name, variant_name):
    spec = FONT_SPECS[font_name]
    scale = FONT_RENDER_SCALE
    font = get_font(spec["size"] * scale)
    color = FONT_VARIANTS[variant_name]
    spacing = 1 * scale
    glyph_w = spec["w"] * scale
    glyph_h = spec["h"] * scale
    width = len(text) * glyph_w + max(0, len(text) - 1) * spacing
    image = Image.new("RGBA", (width, glyph_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    for index, char in enumerate(text):
        if char == " ":
            continue

        bbox = draw.textbbox((0, 0), char, font=font)
        text_w = bbox[2] - bbox[0]
        text_h = bbox[3] - bbox[1]
        cell_x = index * (glyph_w + spacing)
        text_x = cell_x + (glyph_w - text_w) // 2 - bbox[0]
        text_y = (glyph_h - text_h) // 2 - bbox[1] + spec["y"] * scale

        draw.text(
            (text_x, text_y),
            char,
            font=font,
            fill=color,
        )

    image = image.resize(
        (max(1, width // scale), spec["h"]),
        Image.Resampling.LANCZOS,
    )
    image.save(path)


def make_label_assets():
    for name, text, font_name, variant_name in LABEL_ASSETS:
        render_text_asset(
            os.path.join(IMAGE_DIR, "label_" + name + ".png"),
            text,
            font_name,
            variant_name,
        )


def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate AES-II dashboard PNG assets."
    )
    parser.add_argument("--all", action="store_true", help="Regenerate every asset.")
    parser.add_argument("--arc-temp", action="store_true", help="Regenerate arc_temp.png.")
    parser.add_argument("--arc-batt", action="store_true", help="Regenerate arc_batt.png.")
    parser.add_argument("--fuel-remaining", action="store_true", help="Regenerate fuel_remaining.png.")
    parser.add_argument("--fuel-flow", action="store_true", help="Regenerate fuel_flow.png.")
    parser.add_argument("--rpm-base", action="store_true", help="Regenerate rpm_base.png.")
    parser.add_argument("--labels", action="store_true", help="Regenerate label PNGs.")
    parser.add_argument("--fonts", action="store_true", help="Regenerate font glyph PNGs.")
    return parser.parse_args()


def main():
    args = parse_args()
    selected = any(
        [
            args.all,
            args.arc_temp,
            args.arc_batt,
            args.fuel_remaining,
            args.fuel_flow,
            args.rpm_base,
            args.labels,
            args.fonts,
        ]
    )

    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(IMAGE_DIR, exist_ok=True)
    if not selected or args.all or args.arc_temp:
        make(
            os.path.join(IMAGE_DIR, "arc_temp.png"),
            [
                (0.00, (90 - 10) / (150 - 10), GREEN),
                ((90 - 10) / (150 - 10), (100 - 10) / (150 - 10), YELLOW),
                ((100 - 10) / (150 - 10), 1.00, RED),
            ],
        )
    if not selected or args.all or args.arc_batt:
        make(
            os.path.join(IMAGE_DIR, "arc_batt.png"),
            [
                (0.00, (7.2 - 6.0) / (8.4 - 6.0), RED),
                ((7.2 - 6.0) / (8.4 - 6.0), (7.6 - 6.0) / (8.4 - 6.0), YELLOW),
                ((7.6 - 6.0) / (8.4 - 6.0), 1.00, GREEN),
            ],
        )
    if not selected or args.all or args.fuel_remaining:
        make_fuel_remaining_base(os.path.join(IMAGE_DIR, "fuel_remaining.png"))
    if not selected or args.all or args.fuel_flow:
        make_fuel_flow_base(os.path.join(IMAGE_DIR, "fuel_flow.png"))
    if not selected or args.all or args.rpm_base:
        make_rpm_base(os.path.join(IMAGE_DIR, "rpm_base.png"))

    if not selected or args.all or args.labels:
        make_label_assets()
    if not selected or args.all or args.fonts:
        make_font_glyphs()


if __name__ == "__main__":
    main()
