# SPDX-License-Identifier: GPL-3.0-or-later
#
# AES-II image asset generator
# Copyright (C) 2026 AES-II contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

"""Generate PNG assets for the AES-II Ethos widget."""

import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFont


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "aesii"))
IMAGE_DIR = os.path.join(OUT_DIR, "images")

GAUGE_CANVAS_SIZE = 216
FUEL_STRIP_W = 182
FUEL_STRIP_H = 70
RPM_FACE_W = 205
RPM_FACE_H = 70
GAUGE_BITMAP_W = 135
GAUGE_BITMAP_H = 91
GAUGE_BITMAP_CENTER_X = 89
GAUGE_BITMAP_CENTER_Y = 89
SCALE = 4
CANVAS_W = GAUGE_CANVAS_SIZE * SCALE
CANVAS_H = GAUGE_CANVAS_SIZE * SCALE
CENTER_X = 108 * SCALE
CENTER_Y = 127 * SCALE
RADIUS = 88 * SCALE
THICKNESS = 16 * SCALE
GAUGE_START_DEG = 180
GAUGE_END_DEG = 300
GAUGE_STEP_DEG = 5

GREEN = (20, 220, 115, 255)
YELLOW = (255, 210, 0, 255)
RED = (250, 55, 55, 255)
LABEL = (155, 172, 186, 255)
WHITE = (255, 255, 255, 255)
TRACK_WHITE = (238, 242, 244, 255)
TRACK_SHADOW = (46, 52, 60, 200)

FONT_VARIANTS = {
    "label": LABEL,
    "green": GREEN,
    "yellow": YELLOW,
}
FONT_SPECS = {
    "small": {"size": 17, "w": 11, "h": 20, "y": -1},
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


def color_for_position(pos, zones):
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


def draw_gauge_color_band(img, inner, outer, zones):
    sweep = GAUGE_END_DEG - GAUGE_START_DEG
    samples = 4
    sample_count = samples * samples
    min_x = max(0, int(CENTER_X - outer - 2))
    max_x = min(CANVAS_W - 1, int(CENTER_X + outer + 2))
    min_y = max(0, int(CENTER_Y - outer - 2))
    max_y = min(CANVAS_H - 1, int(CENTER_Y + outer + 2))

    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
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

                    if angle < GAUGE_START_DEG or angle > GAUGE_END_DEG:
                        continue

                    pos = (angle - GAUGE_START_DEG) / sweep
                    r, g, b, _ = color_for_position(pos, zones)
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


def draw_gauge_shadow(img, inner, outer, shadow_end_deg):
    samples = 4
    sample_count = samples * samples
    min_x = max(0, int(CENTER_X - outer - 2))
    max_x = min(CANVAS_W - 1, int(CENTER_X + outer + 2))
    min_y = max(0, int(CENTER_Y - outer - 2))
    max_y = min(CANVAS_H - 1, int(CENTER_Y + outer + 2))
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

    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
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

                    if angle < GAUGE_START_DEG or angle > shadow_end_deg:
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


def draw_gauge_end_line(img, angle_deg, outer_radius, inner_radius):
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

            if 0 <= px < CANVAS_W and 0 <= py < CANVAS_H:
                img[py][px] = blend_over(img[py][px], WHITE, 1.0)


def draw_gauge_face(img, zones, shadow_end_deg=GAUGE_END_DEG):
    shadow_outer = RADIUS - 6 * SCALE
    color_thickness = max(6 * SCALE, math.floor(THICKNESS * 0.098))
    shadow_depth = max(28 * SCALE, THICKNESS + 22 * SCALE)

    draw_gauge_shadow(
        img,
        shadow_outer - shadow_depth,
        shadow_outer,
        shadow_end_deg,
    )

    draw_gauge_color_band(
        img,
        RADIUS - color_thickness,
        RADIUS,
        zones,
    )

    line_inner = shadow_outer - shadow_depth + 1
    for angle in (GAUGE_START_DEG, GAUGE_END_DEG):
        draw_gauge_end_line(
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


def make_gauge_face_image(zones, shadow_end_deg=GAUGE_END_DEG):
    img = [[(0, 0, 0, 0) for _ in range(CANVAS_W)] for _ in range(CANVAS_H)]
    draw_gauge_face(img, zones, shadow_end_deg)
    downsampled = downsample(img, GAUGE_CANVAS_SIZE, GAUGE_CANVAS_SIZE)
    image = rgba_rows_to_image(downsampled)
    cropped, _, _ = crop_transparent_image(image, padding=1)
    return cropped


def make_gauge_series(prefix, zones, include_needle=False):
    make_gauge_face_image(zones, GAUGE_END_DEG).save(
        os.path.join(IMAGE_DIR, prefix + ".png")
    )

    for angle in range(GAUGE_START_DEG, GAUGE_END_DEG + 1, GAUGE_STEP_DEG):
        image = make_gauge_face_image(zones, angle)

        if include_needle:
            image = Image.alpha_composite(image, make_gauge_needle_image(angle))

        image.save(os.path.join(IMAGE_DIR, "%s_%03d.png" % (prefix, angle)))


def draw_centered_text(draw, font, text, x, y, color):
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    draw.text(
        (x - text_w // 2 - bbox[0], y - text_h // 2 - bbox[1]),
        text,
        font=font,
        fill=color,
    )


def draw_shadowed_rectangle(draw, bounds, fill, shadow=TRACK_SHADOW):
    x1, y1, x2, y2 = bounds

    draw.rectangle(
        [x1 + SCALE, y1 + SCALE, x2 + SCALE, y2 + SCALE],
        fill=shadow,
    )
    draw.rectangle(bounds, fill=fill)


def gauge_needle_triangle(center_x, center_y, radius, angle_deg):
    thickness = max(8, min(12, int(radius * 0.131)))
    tip_radius = radius - math.floor(thickness / 2)
    base_radius = tip_radius - math.floor(radius * 0.27)
    half_width = max(5, min(10, int(radius * 0.082)))
    angle = math.radians(angle_deg)
    tip_x = center_x + math.cos(angle) * tip_radius
    tip_y = center_y + math.sin(angle) * tip_radius
    base_center_x = center_x + math.cos(angle) * base_radius
    base_center_y = center_y + math.sin(angle) * base_radius
    normal_x = -math.sin(angle)
    normal_y = math.cos(angle)
    base_a = (
        base_center_x + normal_x * half_width,
        base_center_y + normal_y * half_width,
    )
    base_b = (
        base_center_x - normal_x * half_width,
        base_center_y - normal_y * half_width,
    )
    return [(tip_x, tip_y), base_a, base_b]


def make_gauge_needle_image(angle_deg):
    upscale = 4
    large = Image.new(
        "RGBA",
        (GAUGE_BITMAP_W * upscale, GAUGE_BITMAP_H * upscale),
        (0, 0, 0, 0),
    )
    draw = ImageDraw.Draw(large)
    center_x = GAUGE_BITMAP_CENTER_X * upscale
    center_y = GAUGE_BITMAP_CENTER_Y * upscale
    points = gauge_needle_triangle(center_x, center_y, 88 * upscale, angle_deg)
    shadow_points = [
        (x + 4, y + 4)
        for x, y in points
    ]

    draw.polygon(shadow_points, fill=(10, 12, 16, 95))
    draw.polygon(points, fill=WHITE)

    return large.resize(
        (GAUGE_BITMAP_W, GAUGE_BITMAP_H),
        Image.Resampling.LANCZOS,
    )


def make_fuel_remaining_asset(path):
    width = FUEL_STRIP_W * SCALE
    height = FUEL_STRIP_H * SCALE
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    font = get_font(16 * SCALE)

    line_x = 9 * SCALE
    line_y = 35 * SCALE
    line_w = 170 * SCALE
    line_h = 3 * SCALE
    red_w = 6 * SCALE
    quarter = line_w / 4

    draw.rectangle(
        [line_x, line_y, line_x + red_w, line_y + line_h],
        fill=RED,
    )
    draw.rectangle(
        [line_x + red_w, line_y, line_x + line_w, line_y + line_h],
        fill=TRACK_WHITE,
    )
    draw.rectangle(
        [
            line_x,
            line_y + 2 * SCALE,
            line_x + line_w,
            line_y + line_h + 2 * SCALE,
        ],
        fill=TRACK_SHADOW,
    )

    for marker_index in (1, 2, 3):
        marker_x = int(line_x + quarter * marker_index + 0.5)
        draw_shadowed_rectangle(
            draw,
            [
                marker_x - SCALE // 2,
                line_y - 6 * SCALE,
                marker_x + SCALE // 2,
                line_y + 8 * SCALE,
            ],
            TRACK_WHITE,
        )

    draw_shadowed_rectangle(
        draw,
        [line_x, line_y - 7 * SCALE, line_x + 3 * SCALE, line_y + 9 * SCALE],
        RED,
    )

    for marker_index in (1, 2, 3):
        marker_x = line_x + int(quarter * marker_index)
        draw_shadowed_rectangle(
            draw,
            [
                marker_x,
                line_y - 5 * SCALE,
                marker_x + 2 * SCALE,
                line_y + 7 * SCALE,
            ],
            TRACK_WHITE,
        )

    draw_shadowed_rectangle(
        draw,
        [
            line_x + line_w - 3 * SCALE,
            line_y - 7 * SCALE,
            line_x + line_w,
            line_y + 9 * SCALE,
        ],
        GREEN,
    )

    draw_centered_text(
        draw,
        font,
        "FUEL QTY",
        width // 2 - 45 * SCALE,
        12 * SCALE,
        LABEL,
    )
    draw_centered_text(draw, font, "0", line_x, 58 * SCALE, LABEL)
    draw_centered_text(draw, font, "25", line_x + quarter, 58 * SCALE, LABEL)
    draw_centered_text(draw, font, "50", line_x + quarter * 2, 58 * SCALE, LABEL)
    draw_centered_text(draw, font, "75", line_x + quarter * 3, 58 * SCALE, LABEL)
    draw_centered_text(draw, font, "F", line_x + line_w, 58 * SCALE, LABEL)

    img = img.resize(
        (FUEL_STRIP_W, FUEL_STRIP_H),
        Image.Resampling.LANCZOS,
    )
    img.save(path)


def make_fuel_flow_asset(path):
    width = FUEL_STRIP_W * SCALE
    height = FUEL_STRIP_H * SCALE
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    font = get_font(16 * SCALE)

    line_x = 9 * SCALE
    line_y = 35 * SCALE
    line_w = 170 * SCALE
    line_h = 3 * SCALE
    red_w = 6 * SCALE
    yellow_start = int(line_x + line_w * 0.80)

    draw.rectangle(
        [line_x, line_y, line_x + red_w, line_y + line_h],
        fill=WHITE,
    )
    draw.rectangle(
        [line_x + red_w, line_y, yellow_start, line_y + line_h],
        fill=TRACK_WHITE,
    )
    draw.rectangle(
        [yellow_start, line_y, line_x + line_w, line_y + line_h],
        fill=WHITE,
    )
    draw.rectangle(
        [
            line_x,
            line_y + 2 * SCALE,
            line_x + line_w,
            line_y + line_h + 2 * SCALE,
        ],
        fill=TRACK_SHADOW,
    )

    draw_centered_text(
        draw,
        font,
        "FF ML/MIN",
        width // 2 - 45 * SCALE,
        12 * SCALE,
        LABEL,
    )
    draw.rectangle(
        [line_x, line_y - 7 * SCALE, line_x + 2 * SCALE, line_y + 9 * SCALE],
        fill=WHITE,
    )
    draw.rectangle(
        [
            line_x + line_w - 2 * SCALE,
            line_y - 7 * SCALE,
            line_x + line_w,
            line_y + 9 * SCALE,
        ],
        fill=WHITE,
    )

    img = img.resize(
        (FUEL_STRIP_W, FUEL_STRIP_H),
        Image.Resampling.LANCZOS,
    )
    img.save(path)


def make_rpm_asset(path):
    width = RPM_FACE_W * SCALE
    height = RPM_FACE_H * SCALE
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    font = get_font(16 * SCALE)

    line_x = 20 * SCALE
    line_y = 37 * SCALE
    line_w = 170 * SCALE
    line_h = 3 * SCALE

    draw_centered_text(draw, font, "RPM", 36 * SCALE, 10 * SCALE, LABEL)

    draw.rectangle(
        [line_x, line_y, line_x + line_w, line_y + line_h],
        fill=TRACK_WHITE,
    )
    draw.rectangle(
        [
            line_x,
            line_y + 2 * SCALE,
            line_x + line_w,
            line_y + line_h + 2 * SCALE,
        ],
        fill=TRACK_SHADOW,
    )
    draw.rectangle(
        [line_x, line_y - 7 * SCALE, line_x + 2 * SCALE, line_y + 9 * SCALE],
        fill=WHITE,
    )
    draw.rectangle(
        [
            line_x + line_w - 2 * SCALE,
            line_y - 7 * SCALE,
            line_x + line_w,
            line_y + 9 * SCALE,
        ],
        fill=WHITE,
    )

    img = img.resize((RPM_FACE_W, RPM_FACE_H), Image.Resampling.LANCZOS)
    img.save(path)


def get_font(size):
    for path in FONT_PATHS:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                pass

    return ImageFont.load_default()


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
        ]
    )

    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(IMAGE_DIR, exist_ok=True)
    if not selected or args.all or args.arc_temp:
        make_gauge_series(
            "arc_temp",
            [
                (0.00, (90 - 10) / (150 - 10), GREEN),
                ((90 - 10) / (150 - 10), (100 - 10) / (150 - 10), YELLOW),
                ((100 - 10) / (150 - 10), 1.00, RED),
            ],
            True,
        )
    if not selected or args.all or args.arc_batt:
        make_gauge_series(
            "arc_batt",
            [
                (0.00, (7.2 - 6.0) / (8.4 - 6.0), RED),
                ((7.2 - 6.0) / (8.4 - 6.0), (7.6 - 6.0) / (8.4 - 6.0), YELLOW),
                ((7.6 - 6.0) / (8.4 - 6.0), 1.00, GREEN),
            ],
            True,
        )
    if not selected or args.all or args.fuel_remaining:
        make_fuel_remaining_asset(os.path.join(IMAGE_DIR, "fuel_remaining.png"))
    if not selected or args.all or args.fuel_flow:
        make_fuel_flow_asset(os.path.join(IMAGE_DIR, "fuel_flow.png"))
    if not selected or args.all or args.rpm_base:
        make_rpm_asset(os.path.join(IMAGE_DIR, "rpm_base.png"))

    if not selected or args.all or args.labels:
        make_label_assets()


if __name__ == "__main__":
    main()
