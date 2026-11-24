#!/usr/bin/env python3
"""
Dove Hunt pixel-art generator.

Produces every sprite and landscape used by the widget and the companion app as
native-resolution PNGs (1 PNG pixel = 1 art pixel) and writes them into each
target's asset catalog.
SwiftUI scales them up with `.interpolation(.none)` so pixels stay razor sharp.

Usage (from the repo root):
    python3 -I Tools/generate_pixel_art.py

Pure standard library: no Pillow required.
"""

import json
import math
import os
import random
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WIDGET_OUTPUT_DIR = os.path.join(ROOT, "DoveHuntWidget", "Assets.xcassets", "PixelArt")
APP_OUTPUT_DIR = os.path.join(ROOT, "doveHunt", "Assets.xcassets", "PixelArt")

# Native art resolutions of the companion app's home screen background, one per screen shape
# (phone portrait, tablet/foldable portrait, open-Duo/iPad landscape, phone landscape). All share
# the same height and ground line, so the hunter stands on the same row in every variant.
# Keep in sync with `AppArt.backgrounds` in doveHunt/AppPixelArt.swift.
APP_BACKGROUND_SIZES = [(90, 196), (140, 196), (280, 196), (420, 196)]

# Native art resolution of the console screen for each widget family.
# Keep in sync with `ArtSpec` in DoveHuntWidget/PixelArt.swift.
SCREEN_SIZES = {
    "small": (64, 64),
    "medium": (144, 60),
    "large": (144, 152),
}

TRANSPARENT = (0, 0, 0, 0)


# MARK: - PNG + asset catalog output

def hex_color(value, alpha=255):
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


def write_png(path, pixels):
    height = len(pixels)
    width = len(pixels[0])
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in pixels)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def write_imageset(name, pixels, output_dir):
    folder = os.path.join(output_dir, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    write_png(os.path.join(folder, f"{name}.png"), pixels)
    contents = {
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)


def write_group_contents(output_dir):
    os.makedirs(output_dir, exist_ok=True)
    with open(os.path.join(output_dir, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)


# MARK: - Canvas helpers

class Canvas:
    def __init__(self, width, height, fill=TRANSPARENT):
        self.w = width
        self.h = height
        self.px = [[fill for _ in range(width)] for _ in range(height)]

    def set(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = color

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return None

    def rect(self, x0, y0, x1, y1, color):
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                self.px[y][x] = color

    def stamp(self, sprite_rows, palette, ox, oy, flip=False):
        for sy, row in enumerate(sprite_rows):
            chars = row[::-1] if flip else row
            for sx, ch in enumerate(chars):
                if ch in palette:
                    self.set(ox + sx, oy + sy, palette[ch])


# 4x4 ordered (Bayer) dither matrix, normalized to 0..1, for retro gradients.
BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def bayer(x, y):
    return (BAYER4[y % 4][x % 4] + 0.5) / 16.0


def dithered_gradient(canvas, colors, y0, y1):
    """Fill rows y0..y1 with an ordered-dither blend through `colors` (top to bottom)."""
    span = max(1, y1 - y0 - 1)
    for y in range(y0, y1):
        t = (y - y0) / span
        v = t * (len(colors) - 1)
        base = min(int(v), len(colors) - 2)
        frac = v - base
        for x in range(canvas.w):
            color = colors[base + 1] if bayer(x, y) < frac else colors[base]
            canvas.set(x, y, color)


def blob_mask(circles, width, height):
    """Union of circles -> set of (x, y). `circles` = [(cx, cy, r), ...]."""
    mask = set()
    for cx, cy, r in circles:
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r and 0 <= x < width and 0 <= y < height:
                    mask.add((x, y))
    return mask


def shade_blob(canvas, circles, outline, dark, mid, light):
    """Draws a rounded foliage/cloud blob lit from the upper-left, with a 1px outline."""
    mask = blob_mask(circles, canvas.w, canvas.h)
    for (x, y) in mask:
        edge = any((x + dx, y + dy) not in mask for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if edge and outline is not None:
            canvas.set(x, y, outline)
            continue
        # Light direction from the circle that "owns" this pixel most strongly.
        best = max(circles, key=lambda c: c[2] - math.hypot(x - c[0], y - c[1]))
        cx, cy, r = best
        lightness = -((x - cx) + (y - cy)) / (r * 1.4)
        if lightness > 0.35 + (bayer(x, y) - 0.5) * 0.25:
            canvas.set(x, y, light)
        elif lightness < -0.25 + (bayer(x, y) - 0.5) * 0.25:
            canvas.set(x, y, dark)
        else:
            canvas.set(x, y, mid)
    return mask


def ground_line(w, h):
    return h - max(12, round(h * 0.22))


# MARK: - Landscape: Sunny Meadow

def meadow(w, h, rng):
    c = Canvas(w, h)
    gy = ground_line(w, h)
    sky = [hex_color(v) for v in ("#3E8FE0", "#5AA9EC", "#7DC0F3", "#A6D8F8", "#C9E9FB")]
    dithered_gradient(c, sky, 0, gy)

    # Fluffy clouds.
    cloud_count = 2 if w < 100 else 3
    for i in range(cloud_count):
        cx = w * (0.2 + 0.6 * i / max(1, cloud_count - 1)) + rng.uniform(-6, 6)
        cy = gy * rng.uniform(0.18, 0.4)
        size = rng.uniform(3.0, 4.5)
        circles = [(cx, cy, size), (cx - size * 1.2, cy + 1.5, size * 0.75), (cx + size * 1.3, cy + 1.2, size * 0.8)]
        shade_blob(c, circles, None, hex_color("#BFDDF2"), hex_color("#F4FAFF"), hex_color("#FFFFFF"))

    # Rolling far hills (two layers).
    phase = rng.uniform(0, 6.28)
    for layer, (color, amp, base) in enumerate(((hex_color("#8FD07A"), 4.0, 7), (hex_color("#6DBA5C"), 2.5, 3))):
        for x in range(w):
            top = gy - base - amp * (0.6 * math.sin(x * 0.07 + phase + layer) + 0.4 * math.sin(x * 0.19 + phase * 2))
            for y in range(int(top), gy):
                c.set(x, y, color)

    # Ground: grass with texture, tufts, and flowers.
    grass, grass_dark, grass_light = hex_color("#4C9F3C"), hex_color("#3D8731"), hex_color("#66B852")
    c.rect(0, gy, w, h, grass)
    for y in range(gy, h):
        for x in range(w):
            r = rng.random()
            if r < 0.10:
                c.set(x, y, grass_dark)
            elif r < 0.16:
                c.set(x, y, grass_light)
    for x in range(w):
        c.set(x, gy, grass_light)
        if rng.random() < 0.35:
            c.set(x, gy - 1, grass)
    for _ in range(max(3, w // 16)):
        fx, fy = rng.randrange(w), rng.randrange(gy + 2, h)
        c.set(fx, fy, hex_color(rng.choice(["#FFFFFF", "#FFE066", "#FF8FB1"])))

    # Big tree on the left.
    tree_x = round(w * 0.12) if w > 100 else round(w * 0.16)
    canopy_r = max(8, round(min(h * 0.16, w * 0.1)))
    trunk_h = max(8, round(min(h, w * 0.6) * 0.18))
    trunk_top = gy - trunk_h
    for y in range(trunk_top, gy + 2):
        for x in range(tree_x - 2, tree_x + 3):
            if x == tree_x - 2 or x == tree_x + 2:
                c.set(x, y, hex_color("#3A2212"))
            elif x == tree_x - 1:
                c.set(x, y, hex_color("#8A5A34"))
            elif x == tree_x + 1:
                c.set(x, y, hex_color("#4A2C18"))
            else:
                c.set(x, y, hex_color("#6B4226"))
    ccy = trunk_top - canopy_r * 0.55
    circles = [
        (tree_x, ccy, canopy_r),
        (tree_x - canopy_r * 0.85, ccy + canopy_r * 0.45, canopy_r * 0.7),
        (tree_x + canopy_r * 0.9, ccy + canopy_r * 0.4, canopy_r * 0.72),
        (tree_x + canopy_r * 0.2, ccy - canopy_r * 0.6, canopy_r * 0.65),
    ]
    shade_blob(c, circles, hex_color("#1F4F22"), hex_color("#2E7D32"), hex_color("#43A047"), hex_color("#7CC85E"))

    # Bush on the right.
    bx = round(w * 0.86)
    br = max(4, round(min(h * 0.07, w * 0.05)))
    shade_blob(c, [(bx, gy - br * 0.4, br), (bx + br, gy - br * 0.1, br * 0.75), (bx - br, gy, br * 0.7)],
               hex_color("#1F4F22"), hex_color("#2E7D32"), hex_color("#43A047"), hex_color("#7CC85E"))
    return c


# MARK: - Landscape: Night Woods (grey & yellow)

def pine(c, x, base_y, height, color, rng):
    """Tiered pine silhouette."""
    tiers = 3 if height < 18 else 4
    tier_h = height / tiers
    for y in range(int(base_y - height), base_y):
        depth = y - (base_y - height)
        in_tier = depth % tier_h
        half = int(1 + depth * 0.22 + in_tier * 0.45)
        for dx in range(-half, half + 1):
            c.set(x + dx, y, color)
    c.rect(x - 1, base_y, x + 1, base_y + 2, color)


def night_woods(w, h, rng):
    c = Canvas(w, h)
    gy = ground_line(w, h)
    sky = [hex_color(v) for v in ("#23262F", "#2D313C", "#3A3F4C", "#4B505E", "#5E6372")]
    dithered_gradient(c, sky, 0, gy)

    # Stars.
    star, star_dim = hex_color("#F6E9A8"), hex_color("#9C9A86")
    for _ in range(w * gy // 70):
        sx, sy = rng.randrange(w), rng.randrange(int(gy * 0.75))
        c.set(sx, sy, star if rng.random() < 0.4 else star_dim)
    for _ in range(2 if w < 100 else 4):
        sx, sy = rng.randrange(4, w - 4), rng.randrange(3, int(gy * 0.5))
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            c.set(sx + dx, sy + dy, star)

    # Crescent moon with soft dithered glow.
    mx, my = round(w * 0.28), round(gy * 0.28)
    mr = max(4, round(h * 0.08))
    glow = hex_color("#565B66")
    for y in range(my - mr - 4, my + mr + 5):
        for x in range(mx - mr - 4, mx + mr + 5):
            d = math.hypot(x - mx, y - my)
            if mr < d <= mr + 3 and bayer(x, y) < (1 - (d - mr) / 3) * 0.6:
                c.set(x, y, glow)
    for y in range(my - mr, my + mr + 1):
        for x in range(mx - mr, mx + mr + 1):
            inside = math.hypot(x - mx, y - my) <= mr
            bite = math.hypot(x - (mx + mr * 0.55), y - (my - mr * 0.3)) <= mr * 0.85
            if inside and not bite:
                shade = math.hypot(x - mx, y - my) > mr - 1.2
                c.set(x, y, hex_color("#D8B54A") if shade else hex_color("#F4D35E"))

    # Far pine line, then darker near pines framing the edges.
    far, near = hex_color("#3D4250"), hex_color("#24272F")
    x = -2
    while x < w + 2:
        pine(c, x, gy, rng.randint(int(h * 0.12), int(h * 0.22)), far, rng)
        x += rng.randint(4, 7)
    tall = int(h * 0.45)
    pine(c, 3, gy, tall, near, rng)
    pine(c, w - 4, gy, int(tall * 0.9), near, rng)
    if w > 100:
        pine(c, 12, gy, int(tall * 0.7), near, rng)
        pine(c, w - 14, gy, int(tall * 0.65), near, rng)

    # Dry yellow field.
    base, dark, light = hex_color("#B8973A"), hex_color("#8C722A"), hex_color("#D6B957")
    c.rect(0, gy, w, h, base)
    for y in range(gy, h):
        for x in range(w):
            r = rng.random()
            if r < 0.12:
                c.set(x, y, dark)
            elif r < 0.18:
                c.set(x, y, light)
    for x in range(w):
        c.set(x, gy, light)
        if rng.random() < 0.4:
            c.set(x, gy - 1, base)
            if rng.random() < 0.3:
                c.set(x, gy - 2, dark)

    # Fireflies near the treeline.
    for _ in range(3 if w < 100 else 6):
        c.set(rng.randrange(w), rng.randrange(int(gy * 0.6), gy - 2), hex_color("#FFF3A0"))
    return c


# MARK: - Landscape: Sunset Marsh

def sunset_marsh(w, h, rng):
    c = Canvas(w, h)
    gy = ground_line(w, h)
    horizon = gy - max(6, round(h * 0.12))
    sky = [hex_color(v) for v in ("#4E3A73", "#83498A", "#C85F86", "#EE8278", "#FFB070", "#FFD58A")]
    dithered_gradient(c, sky, 0, horizon)

    # Retro striped sun sitting on the horizon.
    sx, sr = round(w * 0.64), max(6, round(h * 0.15))
    for y in range(horizon - sr, horizon):
        stripe_gap = (horizon - y) <= sr * 0.5 and (horizon - y) % 3 == 0
        for x in range(sx - sr, sx + sr + 1):
            if math.hypot(x - sx, y - horizon) <= sr and not stripe_gap:
                c.set(x, y, hex_color("#FFF0B0") if y < horizon - sr * 0.6 else hex_color("#FFD57A"))

    # Distant treeline silhouette.
    for x in range(w):
        top = horizon - 1 - int(1.5 + 1.5 * math.sin(x * 0.3) + (2 if rng.random() < 0.15 else 0))
        for y in range(top, horizon):
            c.set(x, y, hex_color("#5A3A5E"))

    # Water with sun reflections.
    water = [hex_color("#6B5A8C"), hex_color("#4F5F8C")]
    dithered_gradient_rows = gy - horizon
    for y in range(horizon, gy):
        t = (y - horizon) / max(1, dithered_gradient_rows - 1)
        for x in range(w):
            c.set(x, y, water[1] if bayer(x, y) < t else water[0])
    for y in range(horizon + 1, gy, 2):
        spread = sr - (y - horizon)
        for x in range(sx - spread, sx + spread + 1):
            if rng.random() < 0.55:
                c.set(x, y, hex_color("#FFC27A"))
        for _ in range(w // 12):
            lx = rng.randrange(w)
            c.set(lx, y, hex_color("#8C88B4"))
            c.set(lx + 1, y, hex_color("#8C88B4"))

    # Muddy bank.
    c.rect(0, gy, w, h, hex_color("#4D4A2C"))
    for y in range(gy, h):
        for x in range(w):
            r = rng.random()
            if r < 0.12:
                c.set(x, y, hex_color("#3A3720"))
            elif r < 0.2:
                c.set(x, y, hex_color("#625E38"))
    for x in range(w):
        c.set(x, gy, hex_color("#6E6A3E"))

    # Reeds and cattails clustered at both edges.
    def reed(x, height):
        for y in range(gy - height, gy + 1):
            c.set(x, y, hex_color("#2F2D1C"))
        if rng.random() < 0.6:
            c.rect(x, gy - height - 3, x + 1, gy - height, hex_color("#6B4527"))
            c.set(x, gy - height - 4, hex_color("#2F2D1C"))

    for x in list(range(0, max(8, w // 6), 2)) + list(range(w - max(8, w // 6), w, 2)):
        reed(x + rng.randint(0, 1), rng.randint(int(h * 0.08), int(h * 0.2)))
    return c


LANDSCAPES = {
    "meadow": meadow,
    "nightWoods": night_woods,
    "sunsetMarsh": sunset_marsh,
}


# MARK: - Sprites

SPRITE_PALETTE = {
    "K": hex_color("#26263A"),  # outline
    "W": hex_color("#FFFFFF"),  # feather white
    "G": hex_color("#DDE1EB"),  # feather light grey
    "S": hex_color("#A9B0C2"),  # feather shade
    "O": hex_color("#F2A33A"),  # beak
    "E": hex_color("#101018"),  # eye
    "P": hex_color("#F4B6C2"),  # blush
}

DOVE_WINGS_UP = [
    "..KK............",
    "..KWK...........",
    "..KWGK..........",
    "...KWGK.........",
    "...KWWGK...KKK..",
    "....KWWGK.KWWWK.",
    "KKK.KWWWGWWWWEOO",
    "KWWKKWWWWWWWPWK.",
    ".KWWWGGWWWWWWK..",
    "..KWSSGGGWWWK...",
    "...KKSSSSSKK....",
    ".....KKKKK......",
    "................",
    "................",
]

DOVE_WINGS_DOWN = [
    "................",
    "................",
    "................",
    "................",
    "...........KKK..",
    "..........KWWWK.",
    "KKK..KKKKKWWWEOO",
    "KWWKKWWWWWWWPWK.",
    ".KWWWGGWWWWWWK..",
    "..KWWGGGGWWWK...",
    "...KKWGGSKKK....",
    "....KWGSK.......",
    ".....KSK........",
    "......K.........",
]

FEATHER_POOF = [
    "......K.........",
    ".....KWK....K...",
    "..K...KGK..KWK..",
    ".KWK...K....KGK.",
    "..KGK...KKK..K..",
    "...K...KWWWK....",
    "......KWWGWWK..K",
    "K....KWWGGGWWKKW",
    "WK....KWWGWWK.K.",
    ".K.....KWWWK....",
    "...K....KKK..K..",
    "..KWK.......KWK.",
    "...KGK.......KK.",
    "....K...........",
]

GUN_PALETTE = {
    "K": hex_color("#1E1E28"),  # outline
    "L": hex_color("#A3ADBF"),  # steel highlight
    "M": hex_color("#5C6475"),  # steel
    "B": hex_color("#8B5A2B"),  # walnut
    "D": hex_color("#5E3A1A"),  # walnut shade
    "H": hex_color("#B98049"),  # walnut highlight
    "Y": hex_color("#FFE45C"),  # flash yellow
    "O": hex_color("#FF8F2E"),  # flash orange
    "F": hex_color("#FFFFFF"),  # flash core
}

GUN_BODY = [
    "...KKK...",
    "..KLMLK..",
    "..KLMLK..",
    "..KLMLK..",
    "..KLMLK..",
    "..KLMLK..",
    "..KLMLK..",
    "..KLMLK..",
    ".KKKKKKK.",
    ".KHBBBDK.",
    ".KHBBBDK.",
    ".KKKKKKK.",
    "..KLMMK..",
    "..KMMMK..",
    ".KHBBBDK.",
    "KHBBBBBDK",
    "KHBBBBBDK",
    "KKKKKKKKK",
]

MUZZLE_FLASH = [
    "..O...O..",
    "...OYO...",
    ".OYYFYYO.",
    "...YFY...",
    "....Y....",
]

DIGITS = {
    "0": ["###", "#.#", "#.#", "#.#", "###"],
    "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "###", "#..", "###"],
    "3": ["###", "..#", ".##", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"],
    "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"],
    "7": ["###", "..#", "..#", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"],
    "9": ["###", "#.#", "###", "..#", "###"],
}


def sprite(rows, palette):
    c = Canvas(len(rows[0]), len(rows))
    c.stamp(rows, palette, 0, 0)
    return c


def shotgun(firing):
    c = Canvas(9, 24)
    if firing:
        c.stamp(MUZZLE_FLASH, GUN_PALETTE, 0, 0)
    c.stamp(GUN_BODY, GUN_PALETTE, 0, 6)
    return c


# The aimed shotgun leans this many pixels sideways per row of height (~27 degrees),
# pivoting on the bottom of the stock so the gun stays planted at bottom-center.
GUN_AIM_SHEAR = 0.5


def shotgun_aimed(firing, direction):
    """The shotgun tilted toward `direction` ('left' or 'right') by shearing the upright sprite.

    Each row shifts sideways in proportion to its height above the stock, which gives a
    clean stair-stepped pixel diagonal instead of a blurry rotation.
    """
    upright = shotgun(firing)
    pivot = upright.h - 1
    shifts = [int(math.floor((pivot - y) * GUN_AIM_SHEAR + 0.5)) for y in range(upright.h)]
    out = Canvas(upright.w + max(shifts), upright.h)
    for y in range(upright.h):
        for x in range(upright.w):
            p = upright.px[y][x]
            if p[3]:
                out.set(x + shifts[y], y, p)
    if direction == "left":
        out.px = [row[::-1] for row in out.px]
    return out


def digit(ch):
    """3x5 glyph in cream with a 1px drop shadow -> 4x6 sprite."""
    c = Canvas(4, 6)
    shadow, ink = hex_color("#26263A"), hex_color("#FFF6D5")
    for y, row in enumerate(DIGITS[ch]):
        for x, v in enumerate(row):
            if v == "#":
                c.set(x + 1, y + 1, shadow)
    for y, row in enumerate(DIGITS[ch]):
        for x, v in enumerate(row):
            if v == "#":
                c.set(x, y, ink)
    return c


# MARK: - Companion app art

def app_background(w, h, rng):
    """Simple blue pixel sky with drifting clouds and a grassy strip for the hunter."""
    c = Canvas(w, h)
    gy = h - 26
    sky = [hex_color(v) for v in ("#153A86", "#1F55A8", "#2F72C4", "#4C93DC", "#74B4EC", "#A2D4F7")]
    dithered_gradient(c, sky, 0, gy)

    # A few scattered "pixel sparkles" high in the deep blue.
    for _ in range(14):
        c.set(rng.randrange(w), rng.randrange(int(gy * 0.3)), hex_color("#5C86C8"))

    for fx, fy, size in ((0.18, 0.27, 4.0), (0.77, 0.18, 4.5), (0.58, 0.46, 3.2), (0.15, 0.65, 3.6), (0.83, 0.73, 3.0)):
        cx, cy = w * fx, h * fy
        circles = [(cx, cy, size), (cx - size * 1.2, cy + 1.5, size * 0.75), (cx + size * 1.3, cy + 1.2, size * 0.8)]
        shade_blob(c, circles, None, hex_color("#BFDDF2"), hex_color("#F4FAFF"), hex_color("#FFFFFF"))

    # Hills use whole numbers of waves across the width, so the art tiles seamlessly into one
    # continuous panorama for the side-scrolling adventure.
    phase = rng.uniform(0, 6.28)
    k1, k2 = max(1, round(w / 80)), max(2, round(w / 30))
    for x in range(w):
        t = 2 * math.pi * x / w
        top = gy - 5 - 3 * (0.6 * math.sin(k1 * t + phase) + 0.4 * math.sin(k2 * t + phase * 2))
        for y in range(int(top), gy):
            c.set(x, y, hex_color("#7FC46C"))

    grass, grass_dark, grass_light = hex_color("#4C9F3C"), hex_color("#3D8731"), hex_color("#66B852")
    c.rect(0, gy, w, h, grass)
    for y in range(gy, h):
        for x in range(w):
            r = rng.random()
            if r < 0.10:
                c.set(x, y, grass_dark)
            elif r < 0.16:
                c.set(x, y, grass_light)
    for x in range(w):
        c.set(x, gy, grass_light)
        if rng.random() < 0.35:
            c.set(x, gy - 1, grass)
    for _ in range(8):
        c.set(rng.randrange(w), rng.randrange(gy + 2, h), hex_color(rng.choice(["#FFFFFF", "#FFE066", "#FF8FB1"])))
    return c


def outlined(canvas, outline):
    """Adds a 1px outline around every opaque region (outer silhouette only)."""
    out = Canvas(canvas.w, canvas.h)
    for y in range(canvas.h):
        for x in range(canvas.w):
            p = canvas.px[y][x]
            if p[3]:
                out.px[y][x] = p
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = canvas.get(x + dx, y + dy)
                if n is not None and n[3]:
                    out.px[y][x] = outline
                    break
    return out


def hunter(pose="stand"):
    """Vintage hunter in a blaze-orange cap and red plaid jacket, shotgun angled at the sky.

    `pose` is "stand", or a walk-cycle stride: "a" (legs apart) or "b" (legs passing).
    Only the lower legs and boots move, so the frames line up perfectly.
    """
    # Without his shotgun (taken aboard the UFO): "unarmed", "unarmed_a"/"unarmed_b" strides,
    # "unarmed_shocked", and "stomach" (clutching his belly, wide-eyed).
    unarmed = pose.startswith("unarmed") or pose == "stomach"
    scratch = pose == "scratch"
    aim = pose == "aim"
    stomach = pose == "stomach"
    base = {"unarmed": "stand", "unarmed_a": "a", "unarmed_b": "b", "unarmed_shocked": "shocked", "stomach": "shocked",
            "scratch": "stand", "aim": "stand"}.get(pose, pose)
    look_up = base == "look_up"
    shocked = base == "shocked"
    back_dx, front_dx = {"stand": (0, 0), "look_up": (0, 0), "shocked": (0, 0), "a": (-2, 2), "b": (1, -1)}[base]
    c = Canvas(38, 48)
    ox, oy = 2, 1

    def put(x, y, color):
        c.set(ox + x, oy + y, color)

    skin, skin_shade = hex_color("#F2C29B"), hex_color("#D69A72")
    cap, cap_shade, cap_band = hex_color("#F28C28"), hex_color("#C8641A"), hex_color("#9A4A12")
    plaid, plaid_dark, plaid_check = hex_color("#C8382E"), hex_color("#8E2420"), hex_color("#2B1F24")
    pants, pants_shade = hex_color("#B89B62"), hex_color("#8C7346")
    boot, boot_dark = hex_color("#6B4226"), hex_color("#4A2C18")
    brow = hex_color("#5A3A22")
    eye = hex_color("#101018")
    steel_light, steel, steel_dark = hex_color("#A3ADBF"), hex_color("#5C6475"), hex_color("#3A404C")
    wood_light, wood, wood_dark = hex_color("#B98049"), hex_color("#8B5A2B"), hex_color("#5E3A1A")

    def plaid_at(x, y):
        on_x, on_y = x % 4 == 1, y % 4 == 1
        if on_x and on_y:
            return plaid_check
        if on_x or on_y:
            return plaid_dark
        return plaid

    # Boots (toes point right, the way he faces); they follow the lower legs.
    for x0, dx in ((6, back_dx), (12, front_dx)):
        for y in range(41, 45):
            for x in range(x0 + dx, x0 + dx + 5 + (1 if y >= 43 else 0)):
                put(x, y, boot_dark if y == 44 else boot)

    # Legs: thighs stay put, shins swing for the walk cycle.
    for x0, dx in ((7, back_dx), (12, front_dx)):
        for y in range(30, 41):
            shift = dx if y >= 35 else (dx // 2 if y >= 33 else 0)
            for x in range(x0 + shift, x0 + shift + 4):
                put(x, y, pants_shade if x == x0 + shift + 3 else pants)

    # Plaid jacket with rounded shoulders and a belt.
    for y in range(15, 31):
        if y == 15:
            xs = range(8, 15)
        elif y == 16:
            xs = range(6, 17)
        else:
            xs = range(5, 18)
        for x in xs:
            put(x, y, plaid_at(x, y))
    for x in range(5, 18):
        put(x, 29, wood_dark)
    put(11, 29, hex_color("#E8C547"))

    # Head.
    for y in range(6, 15):
        x_start, x_end = (9, 15) if y >= 13 else (8, 16)
        for x in range(x_start, x_end):
            put(x, y, skin)
    put(9, 10, skin_shade)
    put(9, 11, skin_shade)
    put(16, 10, skin)
    put(16, 11, skin)
    for x in range(12, 15):
        put(x, 8, brow)
    put(13, 9, eye)
    for x in range(12, 17):
        put(x, 12, brow)

    # Blaze-orange cap: dome, band, forward brim, and an ear flap.
    for y, (x_start, x_end) in {1: (10, 14), 2: (9, 15), 3: (8, 16), 4: (8, 16), 5: (8, 16)}.items():
        for x in range(x_start, x_end):
            put(x, y, cap)
        put(x_start, y, cap_shade)
    for x in range(8, 16):
        put(x, 5, cap_band)
    for x in range(8, 20):
        put(x, 6, cap_shade if x >= 16 else cap)
    for y in range(7, 12):
        put(8, y, cap)
        put(9, y, cap_shade if y > 7 else cap)

    if shocked:
        # Wide, startled eyes under a raised brow, and a dropped jaw.
        for x in range(12, 15):
            put(x, 8, hex_color("#FFFFFF"))
            put(x, 9, hex_color("#FFFFFF"))
            put(x, 7, brow)
        put(13, 8, eye)
        put(13, 9, eye)
        put(14, 13, hex_color("#5A1E1E"))
        put(15, 13, hex_color("#5A1E1E"))

    if look_up:
        # Head tilted back to the sky: brow and eye raised, chin and moustache forward,
        # and the cap brim tipped up.
        for x in range(12, 15):
            put(x, 8, skin)
            put(x, 7, brow)
        put(13, 9, skin)
        put(14, 8, eye)
        for x in range(12, 17):
            put(x, 12, skin)
        for x in range(13, 18):
            put(x, 11, brow)
        put(16, 12, skin)
        for x in range(16, 20):
            put(x, 6, TRANSPARENT)
        for x in range(16, 19):
            put(x, 5, cap_shade)
        put(19, 4, cap_shade)
        # Tip the top of the head back a pixel so the tilt reads at a glance.
        for y in range(oy + 0, oy + 9):
            row = [c.get(x, y) for x in range(c.w)]
            for x in range(ox + 6, ox + 21):
                c.set(x - 1, y, row[x])
            c.set(ox + 20, y, TRANSPARENT)

    # Rear arm (behind the gun) from shoulder down to the grip.
    def sleeve(x0, y0, x1, y1):
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for i in range(steps + 1):
            t = i / steps
            x, y = round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t)
            put(x, y, plaid_at(x, y))
            put(x, y + 1, plaid_at(x, y + 1))
            put(x, y + 2, plaid_dark)

    if aim:
        # Aiming: the shotgun shouldered and level, sighting straight ahead.
        for x in range(5, 36):
            if x < 12:
                put(x, 17, wood_light)
                put(x, 18, wood)
                put(x, 19, wood_dark)
            elif x < 15:
                put(x, 17, steel)
                put(x, 18, steel_dark)
                put(x, 19, steel_dark)
            elif x < 20:
                put(x, 17, wood_light)
                put(x, 18, wood_dark)
            else:
                put(x, 17, steel_light)
                put(x, 18, steel)
        sleeve(8, 16, 12, 18)                                                   # rear arm to the grip
        sleeve(15, 16, 19, 16)                                                  # front arm to the forend
        for hx, hy in ((12, 19), (19, 18)):
            put(hx, hy, skin)
            put(hx + 1, hy, skin)
        put(14, 9, eye)                                                         # squinting down the barrel
        return outlined(c, hex_color("#26263A"))

    if scratch:
        # Puzzled: shotgun hanging from his rear hand, muzzle down, while his front hand
        # scratches under the cap.
        for k in range(23):
            x, y = 3 + k * 0.12, 18 + k
            put(round(x), round(y), steel if k > 9 else wood)
            put(round(x) + 1, round(y), steel_dark if k > 9 else wood_dark)
        for y in range(16, 26):
            for x in range(2, 5):
                put(x, y, plaid_dark if x == 4 else plaid_at(x, y))
        for (hx, hy) in ((2, 26), (3, 26), (2, 27), (3, 27)):
            put(hx, hy, skin)
        sleeve(16, 16, 18, 11)                                                  # upper arm up
        sleeve(18, 10, 16, 6)                                                   # forearm to the head
        for (hx, hy) in ((15, 5), (16, 5), (15, 6), (16, 6)):
            put(hx, hy, skin)
        return outlined(c, hex_color("#26263A"))


    if unarmed:
        # Arms at his sides, or one clutching his stomach.
        def arm(x0, y0, y1):
            for y in range(y0, y1):
                for x in range(x0, x0 + 3):
                    put(x, y, plaid_dark if x == x0 + 2 else plaid_at(x, y))
        arm(2, 16, 27)
        for hx, hy in ((2, 27), (3, 27), (2, 28), (3, 28)):
            put(hx, hy, skin)
        if stomach:
            arm(17, 16, 21)
            for k in range(8):                                                  # forearm across the belly
                put(18 - k, 21 + k // 4, plaid_at(18 - k, 21))
                put(18 - k, 22 + k // 4, plaid_dark)
            for hx, hy in ((9, 22), (10, 22), (9, 23), (10, 23)):
                put(hx, hy, skin)
        else:
            arm(17, 16, 27)
            for hx, hy in ((18, 27), (19, 27), (18, 28), (19, 28)):
                put(hx, hy, skin)
        return outlined(c, hex_color("#26263A"))

    sleeve(7, 17, 12, 21)

    # Shotgun from the hip up toward the doves.
    bx, by, mx, my = 3, 27, 33, 7
    steps = 72
    for i in range(steps + 1):
        t = i / steps
        x, y = round(bx + (mx - bx) * t), round(by + (my - by) * t)
        if t < 0.26:
            put(x, y, wood_light)
            put(x, y + 1, wood)
            put(x, y + 2, wood_dark)
        elif t < 0.34:
            put(x, y, steel)
            put(x, y + 1, steel_dark)
            put(x, y + 2, steel_dark)
        elif t < 0.47:
            put(x, y, wood_light)
            put(x, y + 1, wood_dark)
        else:
            put(x, y, steel_light)
            put(x, y + 1, steel)

    # Front arm reaching out to the forend.
    sleeve(15, 16, 18, 16)

    # Hands on the grip and the forend.
    for hx, hy in ((12, 21), (19, 16)):
        put(hx, hy, skin)
        put(hx + 1, hy, skin)
        put(hx, hy + 1, skin_shade)
        put(hx + 1, hy + 1, skin)

    return outlined(c, hex_color("#26263A"))


# MARK: - Adventure props (companion app side-scroller)

def prop_tree():
    """A leafy tree like the meadow's, on a transparent canvas; trunk base at the bottom row."""
    c = Canvas(34, 46)
    tx, base = 17, 45
    for y in range(26, base + 1):
        for x in range(tx - 2, tx + 3):
            if x in (tx - 2, tx + 2):
                c.set(x, y, hex_color("#3A2212"))
            elif x == tx - 1:
                c.set(x, y, hex_color("#8A5A34"))
            elif x == tx + 1:
                c.set(x, y, hex_color("#4A2C18"))
            else:
                c.set(x, y, hex_color("#6B4226"))
    r = 11
    circles = [(tx, 14, r), (tx - 9, 19, r * 0.7), (tx + 9, 18, r * 0.72), (tx + 2, 7, r * 0.62)]
    shade_blob(c, circles, hex_color("#1F4F22"), hex_color("#2E7D32"), hex_color("#43A047"), hex_color("#7CC85E"))
    return c


def prop_bush():
    c = Canvas(22, 11)
    shade_blob(c, [(8, 6, 5), (14, 6.5, 4.5), (4, 8, 3.2), (18, 8, 3.2)],
               hex_color("#1F4F22"), hex_color("#2E7D32"), hex_color("#43A047"), hex_color("#7CC85E"))
    return c


CABIN_SIZE = (70, 80)          # keep in sync with AppArt.cabin
CABIN_DOOR = (13, 30, 31, 80)  # x0, y0, x1, y1 of the doorway (y1 = ground)


def cabin(door_open):
    """Brown log cabin with a shingled roof, stone chimney, lit window, and a door."""
    w, h = CABIN_SIZE
    c = Canvas(w, h)
    log, log_light, log_dark, log_end = (hex_color("#7A4B2A"), hex_color("#9A6A3F"),
                                         hex_color("#4F2F17"), hex_color("#B07F4E"))
    roof, roof_dark, roof_light = hex_color("#5A2E22"), hex_color("#3E1F17"), hex_color("#7A4030")
    stone, stone_dark, mortar = hex_color("#8C8C94"), hex_color("#5E5E66"), hex_color("#B4B4BA")

    # Chimney (behind the roof).
    for y in range(2, 20):
        for x in range(48, 56):
            c.set(x, y, mortar if (y % 4 == 0 or (x + (y // 4) * 3) % 5 == 0) else (stone if (x + y) % 3 else stone_dark))

    # Log walls: 5-pixel logs with a highlight on top and shadow underneath, round log ends.
    wall_top = 24
    for y in range(wall_top, h):
        row = (y - wall_top) % 5
        for x in range(5, w - 5):
            c.set(x, y, log_light if row == 0 else (log_dark if row == 4 else log))
        for x in (3, 4, w - 5, w - 4):
            c.set(x, y, log_end if row in (1, 2, 3) else log_dark)

    # Shingled roof with an overhang.
    apex = w // 2
    for y in range(4, wall_top + 2):
        half = int((y - 4) * 1.6) + 3
        for x in range(apex - half, apex + half + 1):
            shingle = (y % 3 == 0) or ((x + (y // 3) * 2) % 6 == 0)
            c.set(x, y, roof_dark if shingle else (roof_light if x < apex - half + 3 else roof))

    # Window with a warm glow and a cross frame.
    wx0, wy0, wx1, wy1 = 42, 36, 58, 52
    for y in range(wy0, wy1):
        for x in range(wx0, wx1):
            edge = x in (wx0, wx1 - 1) or y in (wy0, wy1 - 1)
            cross = x == (wx0 + wx1) // 2 or y == (wy0 + wy1) // 2
            if edge or cross:
                c.set(x, y, hex_color("#3A2212"))
            else:
                c.set(x, y, hex_color("#FFF0A8") if (x - wx0) < 4 and (y - wy0) < 5 else hex_color("#F4C94E"))

    # Door: plank door when closed, dark interior with the door swung inward when open.
    dx0, dy0, dx1, dy1 = CABIN_DOOR
    for y in range(dy0, dy1):
        for x in range(dx0, dx1):
            frame = x in (dx0, dx1 - 1) or y == dy0
            if frame:
                c.set(x, y, hex_color("#3A2212"))
            elif door_open:
                c.set(x, y, hex_color("#B08850") if x <= dx0 + 2 else hex_color("#160D08"))
            else:
                c.set(x, y, hex_color("#5A3519") if (x - dx0) % 4 == 0 else hex_color("#7E5230"))
    if not door_open:
        c.set(dx1 - 4, (dy0 + dy1) // 2, hex_color("#E8C547"))
        c.set(dx1 - 4, (dy0 + dy1) // 2 + 1, hex_color("#B8952F"))

    return outlined(c, hex_color("#26263A"))


# MARK: - Cabin interior (companion app cut-scene)

INTERIOR_SIZE = (240, 130)     # keep in sync with AppArt.interior
INTERIOR_FEET = 118            # characters' feet line (AppArt.interiorFeet)
INTERIOR_TV_SCREEN = (32, 69, 48, 85)    # x0, y0, x1, y1 (AppArt.interiorTVScreen)
INTERIOR_BACK_DOOR = (214, 50, 234, 113)  # x0, y0, x1, y1 (AppArt.interiorBackDoor)


def cabin_interior(back_door_open):
    """The cabin's living room and kitchen: plank walls, floorboards, TV, couch, table and
    chairs, fridge, kitchen island, and the kitchen's back door."""
    w, h = INTERIOR_SIZE
    c = Canvas(w, h)
    rng = random.Random("cabin-interior")
    H = hex_color

    # Plank walls with seams and a little grain.
    for y in range(0, 108):
        for x in range(w):
            plank = x // 7
            base = (H("#8A5A34"), H("#7E522F"), H("#94623A"))[plank % 3]
            if x % 7 == 0:
                base = H("#5A3519")
            elif (x * 7 + y * 3 + plank * 11) % 23 == 0:
                base = H("#6E4626")
            c.set(x, y, base)
    c.rect(0, 0, w, 6, H("#4A2C18"))                      # ceiling beam
    c.rect(0, 6, w, 7, H("#3A2212"))
    c.rect(0, 108, w, 113, H("#4A2C18"))                  # baseboard
    c.rect(0, 108, w, 109, H("#6B4226"))
    # Floorboards.
    for y in range(113, h):
        for x in range(w):
            row = (y - 113) // 4
            seam = (y - 113) % 4 == 3 or (x + row * 17) % 31 == 0
            c.set(x, y, H("#6E4826") if seam else (H("#A87848") if row % 2 == 0 else H("#9A6C40")))

    def frame_rect(x0, y0, x1, y1, color):
        for x in range(x0, x1):
            c.set(x, y0, color)
            c.set(x, y1 - 1, color)
        for y in range(y0, y1):
            c.set(x0, y, color)
            c.set(x1 - 1, y, color)

    # Front doorway on the left, open to the sunny meadow outside.
    for y in range(50, 113):
        t = (y - 50) / 63
        for x in range(3, 20):
            if y > 100:
                c.set(x, y, H("#4C9F3C") if (x + y) % 5 else H("#66B852"))
            else:
                c.set(x, y, H("#A6D8F8") if t < 0.55 else H("#74B4EC") if t < 0.75 else H("#7FC46C"))
    frame_rect(2, 49, 21, 114, H("#3A2212"))
    c.rect(21, 50, 24, 113, H("#7E5230"))                 # the door, swung open against the wall
    c.rect(23, 50, 24, 113, H("#5A3519"))

    # Framed painting (a tiny meadow).
    for y in range(41, 57):
        for x in range(73, 95):
            c.set(x, y, H("#74B4EC") if y < 50 else H("#5DB04A"))
    c.rect(86, 44, 90, 47, H("#FFFFFF"))
    frame_rect(72, 40, 96, 58, H("#C9A24A"))
    frame_rect(71, 39, 97, 59, H("#8A6A2A"))

    # Window with gingham curtains.
    for y in range(29, 52):
        for x in range(113, 137):
            c.set(x, y, H("#A6D8F8") if y < 44 else H("#7FC46C"))
    frame_rect(112, 28, 137, 53, H("#3A2212"))
    c.rect(124, 28, 125, 53, H("#3A2212"))
    c.rect(112, 40, 137, 41, H("#3A2212"))
    for x0 in (108, 134):
        for y in range(26, 58):
            for x in range(x0, x0 + 6):
                check = ((x // 2) + (y // 2)) % 2
                c.set(x, y, H("#C8382E") if check else H("#F2E6E0"))
    c.rect(106, 25, 145, 27, H("#5A3519"))                # curtain rod

    # Old box TV with rabbit ears on a wooden stand.
    c.rect(28, 90, 59, 113, H("#5A3519"))
    c.rect(29, 91, 58, 112, H("#6B4226"))
    c.rect(29, 100, 58, 101, H("#4A2C18"))
    c.rect(42, 95, 46, 96, H("#C9A24A"))
    c.rect(42, 105, 46, 106, H("#C9A24A"))
    c.rect(30, 66, 57, 90, H("#6E4A2C"))                  # wood-grain cabinet
    for y in range(66, 90, 3):
        c.rect(30, y, 57, y + 1, H("#5E3E24"))
    sx0, sy0, sx1, sy1 = INTERIOR_TV_SCREEN
    c.rect(sx0 - 2, sy0 - 2, sx1 + 2, sy1 + 2, H("#3A3A40"))   # bezel
    c.rect(sx0, sy0, sx1, sy1, H("#101018"))
    for ky in (70, 76):
        c.rect(51, ky, 55, ky + 3, H("#C0C0C8"))
        c.set(52, ky + 1, H("#7C7C86"))
    for gy in range(82, 88, 2):
        c.rect(50, gy, 56, gy + 1, H("#3A2A1C"))
    for (tx, ty) in ((35, 52), (51, 53)):
        steps = 24
        for i in range(steps + 1):
            t = i / steps
            c.set(round(43 + (tx - 43) * t), round(66 + (ty - 66) * t), H("#2A2A30"))
        c.set(tx, ty, H("#C0C0C8"))
    c.rect(41, 64, 46, 66, H("#2A2A30"))

    # Couch.
    red, red_dark, red_light = H("#8E3B2E"), H("#6A2A20"), H("#B0543F")
    for y in range(82, 97):
        for x in range(66, 106):
            c.set(x, y, red_light if y < 85 else red)
    c.rect(64, 88, 71, 109, red_dark)                     # arms
    c.rect(101, 88, 108, 109, red_dark)
    c.rect(64, 88, 71, 90, red_light)
    c.rect(101, 88, 108, 90, red_light)
    c.rect(71, 96, 101, 104, red_light)                   # seat cushions
    c.rect(86, 96, 87, 104, red_dark)
    c.rect(66, 104, 106, 110, red)
    c.rect(66, 109, 106, 110, red_dark)
    for fx in (67, 104):
        c.rect(fx, 110, fx + 2, 113, H("#3A2212"))

    # Small wooden table and two chairs.
    wood, wood_dark, wood_light = H("#8B5A2B"), H("#5E3A1A"), H("#B98049")
    c.rect(126, 92, 151, 94, wood_light)
    c.rect(126, 94, 151, 96, wood_dark)
    for lx in (128, 148):
        c.rect(lx, 96, lx + 2, 113, wood)
    for cx0, back_left in ((114, True), (153, False)):
        post = cx0 if back_left else cx0 + 8
        c.rect(post, 78, post + 2, 113, wood_dark)        # back post / back leg
        for sy in (81, 85):
            c.rect(min(post, cx0 + 1), sy, max(post + 2, cx0 + 9), sy + 2, wood)
        c.rect(cx0, 99, cx0 + 10, 102, wood_light)        # seat
        front = cx0 + 8 if back_left else cx0
        c.rect(front, 102, front + 2, 113, wood_dark)     # front leg

    # Small white fridge.
    white, white_shade, edge = H("#F2F2EE"), H("#CFCFCA"), H("#8C8C94")
    c.rect(164, 66, 182, 113, white)
    c.rect(180, 67, 182, 113, white_shade)
    frame_rect(164, 66, 182, 113, edge)
    c.rect(165, 81, 181, 82, edge)
    c.rect(178, 71, 180, 77, H("#5C6475"))
    c.rect(178, 85, 180, 94, H("#5C6475"))
    c.rect(165, 66, 166, 67, white)                       # rounded corners
    c.rect(180, 66, 181, 67, white)

    # Kitchen island with a butcher-block top.
    c.rect(186, 92, 211, 95, H("#C49A62"))
    c.rect(186, 94, 211, 95, H("#A87848"))
    c.rect(187, 95, 210, 113, H("#7E5230"))
    frame_rect(189, 98, 198, 110, H("#5A3519"))
    frame_rect(199, 98, 208, 110, H("#5A3519"))

    # Kitchen back door.
    dx0, dy0, dx1, dy1 = INTERIOR_BACK_DOOR
    for y in range(dy0, dy1):
        for x in range(dx0, dx1):
            if x in (dx0, dx1 - 1) or y == dy0:
                c.set(x, y, H("#3A2212"))
            elif back_door_open:
                c.set(x, y, H("#B08850") if x >= dx1 - 3 else H("#160D08"))
            else:
                c.set(x, y, H("#5A3519") if (x - dx0) % 4 == 0 else H("#7E5230"))
    if not back_door_open:
        c.set(dx0 + 3, (dy0 + dy1) // 2, H("#E8C547"))
        c.set(dx0 + 3, (dy0 + dy1) // 2 + 1, H("#B8952F"))

    return c


def anna(pose="stand"):
    """Anna: blue raggedy overalls with patches, a white apron, and a white bonnet. Faces right."""
    c = Canvas(26, 48)
    ox, oy = 2, 1

    def put(x, y, color):
        c.set(ox + x, oy + y, color)

    H = hex_color
    skin, skin_shade, blush = H("#F2C29B"), H("#D69A72"), H("#F09A9A")
    bonnet, bonnet_shade = H("#F4F1E8"), H("#CFCABB")
    hair = H("#6A4426")
    blue, blue_dark, blue_fray = H("#3F5FA8"), H("#2C4580"), H("#6B86C8")
    patch, patch_stitch = H("#C79A52"), H("#7A5A2A")
    apron, apron_shade = H("#FAFAF6"), H("#D8D8D2")
    boot, boot_dark = H("#5E3A1A"), H("#3A2212")
    eye = H("#101018")
    back_dx, front_dx = {"stand": (0, 0), "a": (-2, 2), "b": (1, -1)}[pose]

    # Boots and legs (overall legs end in a frayed hem).
    for x0, dx in ((5, back_dx), (10, front_dx)):
        for y in range(41, 45):
            for x in range(x0 + dx, x0 + dx + 5 + (1 if y >= 43 else 0)):
                put(x, y, boot_dark if y == 44 else boot)
        for y in range(31, 41):
            shift = dx if y >= 35 else (dx // 2 if y >= 33 else 0)
            for x in range(x0 + shift, x0 + shift + 5):
                frayed = y == 40 and (x + y) % 2 == 0
                put(x, y, blue_fray if frayed else (blue_dark if x == x0 + shift + 4 else blue))
    # Patch on the back leg.
    for y in range(34, 37):
        for x in range(6 + back_dx, 9 + back_dx):
            put(x, y, patch)
    put(6 + back_dx, 34, patch_stitch)
    put(8 + back_dx, 36, patch_stitch)

    # Overall body and bib with straps.
    for y in range(17, 32):
        x_start, x_end = (6, 15) if y >= 22 else (8, 14)
        for x in range(x_start, x_end):
            put(x, y, blue)
        put(x_start, y, blue_dark)
    for y in range(15, 18):
        put(8, y, blue_dark)
        put(12, y, blue_dark)
    put(10, 24, patch)
    put(11, 24, patch)
    put(10, 25, patch_stitch)
    # Shirt sleeve and hand at the front.
    for y in range(15, 18):
        for x in range(7, 15):
            if not (x in (8, 12)):
                put(x, y, apron_shade)
    for y in range(17, 27):
        put(13, y, apron)
        put(14, y, apron_shade)
    for y in range(27, 29):
        put(13, y, skin)
        put(14, y, skin_shade)
    # Apron on the front, tied at the waist.
    for y in range(19, 34):
        for x in range(11, 16):
            put(x, y, apron if x < 15 else apron_shade)
    for x in range(5, 11):
        put(x, 23, apron_shade)
    put(4, 23, apron)
    put(4, 24, apron_shade)

    # Head: hair bun at the back, face, eye, blush.
    for y in range(6, 15):
        for x in range(8, 16):
            put(x, y, skin)
    put(16, 10, skin)
    put(16, 11, skin_shade)
    put(13, 9, eye)
    put(14, 12, blush)
    for y in range(7, 13):
        put(7, y, hair)
        put(8, y, hair)
    for y in range(8, 12):
        put(5, y, hair)
        put(6, y, hair)
    # Bonnet with a forward brim and ties.
    for y, (x_start, x_end) in {0: (8, 13), 1: (7, 15), 2: (6, 16), 3: (6, 16), 4: (6, 16), 5: (6, 16), 6: (6, 10)}.items():
        for x in range(x_start, x_end):
            put(x, y, bonnet if x > x_start else bonnet_shade)
    for x in range(12, 19):
        put(x, 6, bonnet_shade if x >= 17 else bonnet)
    for y in range(13, 16):
        put(9, y, bonnet_shade)

    return outlined(c, H("#26263A"))


# MARK: - Pond scene (companion app)

POND_SIZE = (52, 15)            # keep in sync with AppArt.pond
POND_SMALL_SIZE = (34, 12)      # AppArt.pondSmall (narrow screens)
POND_LARGE_SIZE = (88, 24)      # AppArt.pondLarge (landscape phones and other wide screens)
ROD_SIZE = (34, 30)             # AppArt.fishingRod; grip at (1, 28), tip at (32, 1)
ROD_SHORT_SIZE = (20, 22)       # AppArt.fishingRodShort; grip at (1, 20), tip at (18, 1)


def pond(size=POND_SIZE, roundness=2.0):
    """A small pond set into the grass: dark banks, rippling water, lily pads, reeds.
    `roundness` above 2 fills out the ends into a fuller oval (a superellipse)."""
    w, h = size
    c = Canvas(w, h)
    H = hex_color
    cx, cy, rx, ry = (w - 1) / 2, h / 2, w / 2 - 1, h / 2 - 1
    for y in range(h):
        for x in range(w):
            d = abs((x - cx) / rx) ** roundness + abs((y - cy) / ry) ** roundness
            if d <= 1:
                if d > 0.78:
                    c.set(x, y, H("#3D6B3A") if y < cy else H("#4A3A24"))      # bank / mud edge
                else:
                    depth = y / h
                    c.set(x, y, H("#4C93DC") if depth < 0.45 else H("#2F72C4"))
    k = w / 52
    for (x0, y0, length) in ((10, 5, 6), (24, 9, 8), (34, 4, 5)):
        for x in range(int(x0 * k), int(x0 * k) + max(3, int(length * k))):
            c.set(x, min(h - 3, int(y0 * h / 15)), H("#A6D8F8"))                # ripples
    for (px, py) in ((15, 9), (37, 8)):
        px, py = int(px * k), min(h - 4, int(py * h / 15))
        c.rect(px, py, px + 3, py + 2, H("#5DB04A"))                            # lily pads
        c.set(px + 1, py, H("#2F72C4"))
    for rx0 in (1, 3, w - 5, w - 3):
        for y in range(0, 6):
            c.set(rx0, y, H("#3A5A28"))
        c.set(rx0, 0, H("#6B4527"))
    return c


def fishing_rod(short=False):
    """A fishing rod from the grip (bottom-left) to the tip (top-right), with a reel."""
    w, h = ROD_SHORT_SIZE if short else ROD_SIZE
    c = Canvas(w, h)
    H = hex_color
    gx, gy, tx, ty = (1, 20, 18, 1) if short else (1, 28, 32, 1)
    steps = 64
    for i in range(steps + 1):
        t = i / steps
        x, y = round(gx + (tx - gx) * t), round(gy + (ty - gy) * t)
        c.set(x, y, H("#5E3A1A") if t < 0.22 else H("#2A2A30"))
        if t < 0.22:
            c.set(x, y + 1, H("#3A2212"))
    rx, ry = (3, 15) if short else (4, 22)
    c.rect(rx, ry, rx + 3, ry + 3, H("#A3ADBF"))                                # reel
    c.set(rx + 1, ry + 1, H("#5C6475"))
    return c


def fisherman(pose="stand"):
    """A fisherman in olive rubber chest waders with suspenders, a khaki shirt, a bucket hat,
    and a scruffy beard. Faces right. "stand" holds his arms forward for the rod;
    "a"/"b" are running strides."""
    c = Canvas(28, 48)
    ox, oy = 2, 1

    def put(x, y, color):
        c.set(ox + x, oy + y, color)

    H = hex_color
    skin, skin_shade = H("#E8B48C"), H("#C98E68")
    beard = H("#7A5E48")
    hat, hat_shade, hat_band = H("#BFA878"), H("#9A8458"), H("#5E4A2A")
    shirt, shirt_shade = H("#C9B48A"), H("#A8936A")
    wader, wader_dark, wader_light = H("#55603A"), H("#3B4428"), H("#6F7B4C")
    boot = H("#2E3420")
    strap = H("#2E2E24")
    eye = H("#101018")
    # "shocked" is the standing pose (still holding the rod) with wide eyes and a dropped jaw.
    shocked = pose == "shocked"
    running = pose not in ("stand", "shocked")
    back_dx, front_dx = {"stand": (0, 0), "shocked": (0, 0), "a": (-3, 3), "b": (2, -2)}[pose]

    # Wader legs and boots.
    for x0, dx in ((6, back_dx), (11, front_dx)):
        for y in range(30, 45):
            shift = dx if y >= 36 else (dx // 2 if y >= 33 else 0)
            for x in range(x0 + shift, x0 + shift + 5 + (1 if y >= 43 else 0)):
                put(x, y, boot if y >= 42 else (wader_dark if x == x0 + shift + 4 else wader))
    # Wader chest and suspenders over the shirt.
    for y in range(15, 31):
        for x in range(6, 17):
            put(x, y, wader if y >= 20 else shirt)
        put(6, y, wader_dark if y >= 20 else shirt_shade)
    for x in range(7, 16):
        put(x, 20, wader_light)
    for y in range(15, 21):
        put(9, y, strap)
        put(13, y, strap)
    put(11, 24, wader_light)
    # Arms: forward for the rod when standing, swinging when running.
    if running:
        arm = [(14, y) for y in range(17, 26)] if pose == "a" else [(15 + (y - 17) // 3, y) for y in range(17, 25)]
    else:
        arm = [(14 + (y - 17), y) for y in range(17, 21)] + [(17, 21), (18, 21)]
    for (x, y) in arm:
        put(x, y, shirt)
        put(x, y + 1, shirt_shade)
    hx, hy = arm[-1]
    put(hx + 1, hy, skin)
    put(hx + 1, hy + 1, skin_shade)
    # Head with a scruffy beard, under a bucket hat.
    for y in range(6, 15):
        for x in range(8, 16):
            put(x, y, skin)
    put(16, 9, skin)
    put(16, 10, skin_shade)
    put(13, 8, eye)
    for y in range(11, 15):
        for x in range(9, 16):
            if (x + y) % 3 or y > 12:
                put(x, y, beard)
    for y, (x0, x1) in {1: (9, 15), 2: (8, 16), 3: (8, 16), 4: (8, 16)}.items():
        for x in range(x0, x1):
            put(x, y, hat)
    for x in range(8, 16):
        put(x, 5, hat_band)
    for x in range(6, 19):
        put(x, 6, hat_shade)
    if shocked:
        for x in range(12, 15):
            put(x, 7, beard)                                                    # raised brow
            put(x, 8, H("#FFFFFF"))
            put(x, 9, H("#FFFFFF"))
        put(13, 8, eye)
        put(13, 9, eye)
        put(13, 12, H("#5A1E1E"))                                               # mouth agape in the beard
        put(14, 12, H("#5A1E1E"))
        put(13, 13, H("#5A1E1E"))
        put(14, 13, H("#5A1E1E"))
    return outlined(c, H("#26263A"))


def dog(pose="sit"):
    """Max: a big brown dog with floppy ears and a red collar. Faces right.
    Poses: "sit", "stand", and running strides "a"/"b"."""
    c = Canvas(30, 24)
    H = hex_color
    fur, fur_dark, fur_light = H("#8B5A2B"), H("#5E3A1A"), H("#B07A44")
    nose, eye, collar, tongue = H("#1E1410"), H("#101018"), H("#C8382E"), H("#E07A8A")

    def body(x0, x1, y0, y1):
        for y in range(y0, y1):
            for x in range(x0, x1):
                c.set(x, y, fur_light if y == y0 else (fur_dark if y == y1 - 1 else fur))

    def head(hx, hy):
        for y in range(hy, hy + 7):
            for x in range(hx, hx + 8):
                c.set(x, y, fur if y > hy else fur_light)
        for y in range(hy + 3, hy + 6):                # snout
            for x in range(hx + 8, hx + 11):
                c.set(x, y, fur_light)
        c.set(hx + 10, hy + 3, nose)
        c.set(hx + 6, hy + 2, eye)
        for y in range(hy + 1, hy + 7):                # floppy ear
            c.set(hx + 2, y, fur_dark)
            c.set(hx + 3, y, fur_dark)
        c.rect(hx + 1, hy + 7, hx + 8, hy + 8, collar)

    def leg(x, y0, y1, dx=0):
        for y in range(y0, y1):
            shift = dx if y >= (y0 + y1) // 2 else 0
            c.set(x + shift, y, fur)
            c.set(x + shift + 1, y, fur_dark)
        c.set(x + dx, y1 - 1, fur_dark)
        c.set(x + dx + 1, y1 - 1, fur_dark)

    if pose == "sit":
        body(6, 18, 10, 21)                            # upright haunches
        c.rect(4, 17, 9, 22, fur)                      # folded hind leg
        c.rect(4, 21, 10, 22, fur_dark)
        leg(14, 15, 22)                                # straight front legs
        leg(16, 15, 22)
        head(12, 2)
        for i, (x, y) in enumerate(((5, 19), (4, 18), (3, 17), (2, 17))):   # tail on the ground
            c.set(x, y + 3, fur_dark)
        c.set(21, 7, tongue)
    else:
        running = pose in ("a", "b")
        stride = {"stand": 0, "a": 2, "b": -2}[pose]
        body(4, 21, 9, 16)                             # long body on four legs
        leg(5, 15, 22, -stride)
        leg(8, 15, 22, stride)
        leg(16, 15, 22, stride)
        leg(19, 15, 22, -stride)
        head(19, 3 if not running else 4)
        for i in range(4):                             # tail up
            c.set(3 - i // 2, 9 - i, fur_dark)
        if running:
            c.set(30 - 1, 8, tongue) if False else c.set(29, 9, tongue)
    return outlined(c, H("#26263A"))


# MARK: - Mallard and more scenery (companion app)

MALLARD_PALETTE = {
    "K": hex_color("#26263A"),   # outline
    "G": hex_color("#1F7A3A"),   # green head
    "g": hex_color("#2E9E4E"),   # head highlight
    "W": hex_color("#FFFFFF"),   # neck ring
    "C": hex_color("#8A4A2A"),   # chestnut chest
    "S": hex_color("#B8BCC6"),   # grey body
    "s": hex_color("#8E929C"),   # body shade
    "B": hex_color("#4A5ACC"),   # blue wing speculum
    "Y": hex_color("#F2C232"),   # bill
    "E": hex_color("#101018"),   # eye
    "D": hex_color("#5A4A3A"),   # tail / dark wing
}

MALLARD_WINGS_UP = [
    "....KK............",
    "...KSSK...........",
    "...KSSsK..........",
    "....KSSsK.........",
    "....KSBBsK...KKK..",
    ".....KSBBsK.KGGGK.",
    "KKK..KSSSsKKGgEGKYY",
    "KDDKKSSSSSKWWGGKY.",
    ".KDDSSSSSSCCCWK...",
    "..KDsSSSSSCCCK....",
    "...KKssssKKKK.....",
    ".....KKKKK........",
    "..................",
    "..................",
]

MALLARD_WINGS_DOWN = [
    "..................",
    "..................",
    "..................",
    "..................",
    ".............KKK..",
    "............KGGGK.",
    "KKK..KKKKKKKGgEGKYY",
    "KDDKKSSSSSKWWGGKY.",
    ".KDDSSSSSSCCCWK...",
    "..KDsSBBSSCCCK....",
    "...KKSBBsKKKK.....",
    "....KSSsK.........",
    ".....KsK..........",
    "......K...........",
]

# The first hit: feathers ruffled, eye squeezed shut, tumbling.
MALLARD_HIT = [
    "..K...K...........",
    "...KSK.K..K.......",
    "..KSSSK..KSK......",
    "...KSSsK..K.......",
    "....KSBBsK...KKK..",
    ".....KSBBsK.KGGGK.",
    "KKK..KSSSsKKGgKGKYY",
    "KDDKKSSSSSKWWGGKYY",
    ".KDDSSSSSSCCCWK...",
    "..KDsSSSSSCCCK..K.",
    "...KKssssKKKK..KSK",
    ".....KKKKK......K.",
    "...K.........K....",
    "..KSK.......KSK...",
]


def bird_sprite(rows, palette):
    width = max(len(r) for r in rows)
    padded = [r.ljust(width, ".") for r in rows]
    return sprite(padded, palette)


def prop_pine():
    """A tall green pine tree for scenery variety."""
    c = Canvas(26, 50)
    H = hex_color
    dark, mid, light, trunk = H("#1F5A2E"), H("#2E7D42"), H("#4FA35E"), H("#5A3519")
    c.rect(11, 42, 15, 50, trunk)
    c.rect(11, 42, 12, 50, H("#7A4E2C"))
    tiers = [(2, 14, 8), (10, 26, 10), (18, 40, 12)]
    for top, bottom, half_max in tiers:
        for y in range(top, bottom):
            half = int(1 + (y - top) / (bottom - top) * half_max)
            for x in range(13 - half, 13 + half + 1):
                if 0 <= x < 26:
                    edge = x <= 13 - half + 1
                    c.set(x, y, light if edge else (dark if x > 13 + half // 2 else mid))
    return outlined(c, H("#163A20"))


def tackle_box():
    """The fisherman's green tackle box: a carry handle, a hinged lid with a silver latch,
    and a red-and-white lure hooked on the side."""
    c = Canvas(16, 12)
    H = hex_color
    handle, lid, lid_light, body, body_dark = H("#9AA3B2"), H("#3F9A4E"), H("#66C06C"), H("#2E7D42"), H("#22603A")
    for x in range(5, 11):
        c.set(x, 0, handle)                                                     # handle bar
    c.set(5, 1, handle)
    c.set(10, 1, handle)
    c.rect(1, 2, 15, 5, lid)
    c.rect(1, 2, 15, 3, lid_light)                                              # lid highlight
    c.rect(1, 5, 15, 6, body_dark)                                              # lid seam
    c.rect(1, 6, 15, 11, body)
    c.rect(1, 10, 15, 11, body_dark)
    c.rect(7, 4, 9, 7, H("#D8DDE6"))                                            # latch
    c.set(13, 7, H("#D9342B"))                                                  # lure
    c.set(13, 8, H("#F4F4F4"))
    c.set(13, 9, H("#D9342B"))
    return outlined(c, H("#15301C"))


def arrow_down():
    """A chunky orange arrow pointing down, for "tap this"."""
    c = Canvas(9, 10)
    H = hex_color
    orange, light = H("#F08A24"), H("#FFC66B")
    c.rect(3, 1, 6, 5, orange)
    c.rect(3, 1, 4, 5, light)
    for row, half in enumerate((3, 2, 1, 0)):
        c.rect(4 - half, 5 + row, 5 + half, 6 + row, orange)
    return outlined(c, H("#2A1A0C"))


def crate_icon():
    """A small wooden supply crate: planks in a frame with a diagonal brace (inventory button)."""
    c = Canvas(16, 16)
    H = hex_color
    plank, plank_dark, frame, brace = H("#C08A48"), H("#8E5E2C"), H("#6B4527"), H("#D9A562")
    c.rect(1, 1, 15, 15, plank)
    for y in (5, 10):
        c.rect(3, y, 13, y + 1, plank_dark)                                     # plank seams
    c.rect(1, 1, 15, 3, frame)
    c.rect(1, 13, 15, 15, frame)
    c.rect(1, 1, 3, 15, frame)
    c.rect(13, 1, 15, 15, frame)
    for i in range(10):
        c.set(3 + i, 12 - i, brace)                                             # diagonal brace
        c.set(3 + i, 11 - i, brace)
    for (x, y) in ((2, 2), (13, 2), (2, 13), (13, 13)):
        c.set(x, y, H("#C9CED8"))                                               # nails
    return outlined(c, H("#2A1A0C"))


MALLARD_FLOAT = [
    "............KKK....",
    "...........KGGGK...",
    "...........KGgEGKYY",
    "...........KWWGGKY.",
    "KKK.KKKKKKKKCCCWK..",
    "KDDKSSSSSSSSCCCK...",
    ".KDsSSSBBBSSCCK....",
    "..KsssSSSSsssK.....",
    "...KKKKKKKKKK......",
]


def fill_ellipse(c, cx, cy, rx, ry, color):
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            if rx > 0 and ry > 0 and ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1:
                c.set(x, y, color)


def thick_line(c, x0, y0, x1, y1, width, color):
    steps = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) * 2))
    for i in range(steps + 1):
        t = i / steps
        x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        for dy in range(width):
            for dx in range(width):
                c.set(int(round(x - width / 2 + dx)), int(round(y - width / 2 + dy)), color)


def poop_drop():
    """A falling white dropping."""
    c = Canvas(3, 4)
    W, w = hex_color("#F6F6EE"), hex_color("#C9CCBE")
    for (x, y, col) in ((1, 0, w), (0, 1, w), (1, 1, W), (2, 1, w), (0, 2, w), (1, 2, W), (2, 2, w), (1, 3, w)):
        c.set(x, y, col)
    return c


def poop_splat():
    """A bird-dropping splat on the hunter's clothes."""
    rows = [
        "..W...",
        ".WWW.W",
        "WWWWW.",
        ".WgWW.",
        "..W.W.",
    ]
    return sprite(rows, {"W": hex_color("#F6F6EE"), "g": hex_color("#B4BCA2")})


BEAR_FUR, BEAR_DARK, BEAR_LIGHT = "#6B4423", "#4A2E17", "#8A5A30"
BEAR_SNOUT, BEAR_NOSE = "#A57B52", "#1A1010"


def bear_four(pose="stand"):
    """A big brown bear on all fours, facing right. Poses: "stand", "roar" (mouth open,
    head raised), and running strides "a"/"b"."""
    c = Canvas(54, 32)
    H = hex_color
    fur, dark, light = H(BEAR_FUR), H(BEAR_DARK), H(BEAR_LIGHT)
    stride = {"stand": 0, "roar": 0, "a": 3, "b": -3}[pose]
    lift = 1 if pose in ("a", "b") else 0
    # Legs first so the body overlaps their tops.
    for x, sign in ((8, -1), (15, 1), (31, 1), (38, -1)):
        for y in range(19 - lift, 30):
            shift = stride * sign if y >= 25 else 0
            c.rect(x + shift, y, x + shift + 5, y + 1, dark if x in (8, 31) else fur)
        c.rect(x + stride * sign, 29, x + stride * sign + 6, 31, dark)          # paws
    fill_ellipse(c, 24, 16 - lift, 19, 9, fur)
    fill_ellipse(c, 33, 10 - lift, 9, 5, fur)                                   # shoulder hump
    for x in range(6, 42):                                                      # back highlight
        for y in range(0, 32):
            if c.get(x, y) == fur:
                c.set(x, y, light)
                break
    head_y = (11 if pose == "roar" else 14) - lift
    fill_ellipse(c, 44, head_y, 7, 6, fur)
    fill_ellipse(c, 41, head_y - 6, 2, 2, dark)                                 # ears
    fill_ellipse(c, 47, head_y - 6, 2, 2, dark)
    c.rect(48, head_y, 54, head_y + 5, H(BEAR_SNOUT))                           # snout
    c.rect(52, head_y, 54, head_y + 2, H(BEAR_NOSE))
    c.set(46, head_y - 2, H("#0E0E14"))                                         # eye
    if pose == "roar":
        c.rect(47, head_y + 5, 54, head_y + 9, H("#7E1A1A"))                    # open jaw
        for x in (48, 50, 52):
            c.set(x, head_y + 5, H("#F4F4EE"))                                  # teeth
        c.rect(48, head_y + 9, 54, head_y + 10, H(BEAR_SNOUT))                  # lower jaw
    return outlined(c, H("#22140A"))


def bear_standing():
    """The bear reared up on its hind legs, arms raised, facing right."""
    c = Canvas(36, 58)
    H = hex_color
    fur, dark, light = H(BEAR_FUR), H(BEAR_DARK), H(BEAR_LIGHT)
    for x0 in (9, 17):                                                          # hind legs
        c.rect(x0, 44, x0 + 7, 55, fur)
        c.rect(x0, 54, x0 + 9, 57, dark)                                        # feet
    thick_line(c, 11, 25, 5, 13, 4, dark)                                       # back arm, raised
    fill_ellipse(c, 16, 33, 11, 14, fur)
    fill_ellipse(c, 18, 36, 6, 9, light)                                        # belly
    thick_line(c, 22, 25, 30, 12, 4, fur)                                       # front arm, raised
    for (x, y) in ((30, 9), (32, 10), (33, 12)):
        c.set(x, y, H("#E8E4D8"))                                               # claws
    for (x, y) in ((4, 10), (6, 9)):
        c.set(x, y, H("#E8E4D8"))
    fill_ellipse(c, 19, 12, 7, 6, fur)
    fill_ellipse(c, 14, 6, 2, 2, dark)                                          # ears
    fill_ellipse(c, 21, 5, 2, 2, dark)
    c.rect(24, 11, 31, 16, H(BEAR_SNOUT))
    c.rect(29, 11, 31, 13, H(BEAR_NOSE))
    c.set(22, 9, H("#0E0E14"))
    return outlined(c, H("#22140A"))


def deer(pose="stand", fawn=False):
    """A deer facing right. The fawn is a smaller copy with white spots.
    Poses: "drink" (head down to the water), "stand" (alert), and leaping strides "a"/"b"."""
    s = 0.68 if fawn else 1.0
    w, h = (30, 28) if fawn else (44, 40)
    c = Canvas(w, h)
    H = hex_color
    fur, dark, belly, white, hoof = H("#A0643A"), H("#7A4A26"), H("#D9B08A"), H("#F4EFE6"), H("#2A1A10")
    S = lambda v: v * s

    def line(x0, y0, x1, y1, width, color):
        thick_line(c, S(x0), S(y0), S(x1), S(y1), max(1, round(width * s)), color)

    lift = {"a": 4, "b": 2}.get(pose, 0)
    # Legs.
    if pose == "a":                                   # stretched out mid-leap
        legs = (((12, 25), (3, 32)), ((15, 25), (6, 33)), ((27, 25), (37, 31)), ((31, 25), (41, 30)))
    elif pose == "b":                                 # gathered under the body
        legs = (((12, 26), (17, 37)), ((15, 26), (20, 37)), ((27, 26), (23, 37)), ((31, 26), (27, 37)))
    else:
        legs = (((11, 25), (11, 38)), ((15, 25), (15, 38)), ((27, 25), (27, 38)), ((31, 25), (31, 38)))
    for (x0, y0), (x1, y1) in legs:
        line(x0, y0 - lift, x1, y1 - lift, 2, dark)
        line(x1, y1 - lift, x1, y1 - lift + 1, 2, hoof)
    fill_ellipse(c, S(20), S(21 - lift), S(12), S(6), fur)
    fill_ellipse(c, S(20), S(24 - lift), S(8), S(2.5), belly)
    # Neck and head.
    if pose == "drink":
        line(29, 19, 36, 31, 4, fur)
        fill_ellipse(c, S(38), S(33), S(4), S(3), fur)
        line(39, 34, 41, 37, 2, fur)
        c.set(int(S(41)), int(S(37)), hoof)                                     # nose
        c.set(int(S(37)), int(S(32)), hoof)                                     # eye
        line(34, 29, 33, 26, 2, dark)                                           # ear
    else:
        line(29, 19 - lift, 34, 9 - lift, 4, fur)
        fill_ellipse(c, S(36), S(7 - lift), S(4), S(3), fur)
        line(38, 7 - lift, 41, 8 - lift, 2, fur)
        c.set(int(S(41)), int(S(8 - lift)), hoof)
        c.set(int(S(37)), int(S(6 - lift)), hoof)
        line(33, 4 - lift, 32, 1 - lift, 2, dark)                               # ears
        line(35, 4 - lift, 36, 1 - lift, 2, dark)
    # White tail, flagged up when running.
    if pose in ("a", "b"):
        line(8, 17 - lift, 6, 13 - lift, 2, white)
    else:
        line(8, 17, 7, 20, 2, white)
    if fawn:
        for (x, y) in ((14, 19), (19, 18), (24, 19), (17, 22), (22, 22), (12, 22)):
            c.set(int(S(x)), int(S(y - lift)), white)
    return outlined(c, H("#2A1A10"))


def prop_stream(size=(150, 18)):
    """A long, winding stream set into the grass, with tapered ends and a few reeds."""
    w, h = size
    c = Canvas(w, h)
    H = hex_color
    for x in range(w):
        taper = min(1.0, min(x, w - 1 - x) / 14)
        top = 2 + 1.5 * math.sin(x * 0.08) + (1 - taper) * 5
        bottom = h - 3 + 1.5 * math.sin(x * 0.06 + 1) - (1 - taper) * 5
        if bottom - top < 2:
            continue
        for y in range(int(top), int(bottom) + 1):
            if y <= top + 1:
                color = H("#3D6B3A")                                            # far bank
            elif y >= bottom - 1:
                color = H("#4A3A24")                                            # near mud bank
            else:
                color = H("#4C93DC") if y < (top + bottom) / 2 else H("#2F72C4")
            c.set(x, y, color)
    for (x0, y0, length) in ((24, 7, 9), (60, 10, 12), (98, 6, 8), (126, 11, 7)):
        for x in range(x0, x0 + length):
            if c.get(x, y0) and c.get(x, y0)[3]:
                c.set(x, y0, H("#A6D8F8"))                                      # ripples
    for rx0 in (10, 12, w - 13, w - 11):
        for y in range(0, 6):
            c.set(rx0, y, H("#3A5A28"))
        c.set(rx0, 0, H("#6B4527"))
    return c


def chain_fence(open_gate=False):
    """A chain-link fence (98x40: the gate plus three panels), closed or swung open."""
    w, h = 98, 40
    c = Canvas(w, h)
    H = hex_color
    mesh, post, post_dark, rail = H("#A9B1BC", 210), H("#8C939E"), H("#5C6370"), H("#9AA2AE")
    gate_w = 26
    for y in range(2, h - 1):
        for x in range(0, w):
            if x < gate_w and open_gate:
                continue
            if (x + y) % 4 == 0 or (x - y) % 4 == 0:
                c.set(x, y, mesh)
    c.rect(0 if not open_gate else gate_w, 0, w, 2, rail)                       # top rail
    for x0 in list(range(gate_w, w, 24)) + [w - 2]:
        c.rect(x0, 0, x0 + 2, h, post)                                          # posts
        c.set(x0 + 1, 0, post_dark)
    c.rect(0, 0, 2, h, post)                                                    # latch post
    if open_gate:
        # The gate swung toward us on its hinges: a narrow, foreshortened panel by the hinge post.
        for y in range(3, h - 2):
            for x in range(gate_w - 7, gate_w - 1):
                if (x + y) % 3 == 0:
                    c.set(x, y, mesh)
        c.rect(gate_w - 8, 3, gate_w - 7, h - 2, post)
        c.rect(gate_w - 8, 3, gate_w - 1, 4, post)
        c.rect(gate_w - 8, h - 3, gate_w - 1, h - 2, post)
        c.rect(2, h - 2, gate_w - 8, h, H("#8A6A44"))                           # the trail beyond
    else:
        c.rect(2, 3, gate_w, 4, post)                                           # gate frame
        c.rect(2, h - 3, gate_w, h - 2, post)
        c.rect(3, 3, 4, h - 2, post)
        for i in range(gate_w - 6):
            c.set(4 + i, h - 4 - int(i * (h - 8) / (gate_w - 6)), post_dark)    # diagonal brace
    return outlined(c, H("#3A404C"))


def far_mountain():
    """A lone, hazy mountain far behind the restricted gate, with a dirt trail that starts at
    the bottom (right behind the gate) and switchbacks up its face. Flat bottom on the horizon."""
    w, h = 130, 76
    c = Canvas(w, h)
    H = hex_color
    peak_x, peak_y = 74, 2
    for x in range(w):
        # The right flank is steeper so the whole slope reaches the ground inside the sprite.
        slope = 1.0 if x <= peak_x else (h - peak_y) / (w - 2 - peak_x)
        top = peak_y + abs(x - peak_x) * slope
        lit = x <= peak_x
        for y in range(max(int(top), 0), h):
            if y - top < 4 and top < 16:
                color = H("#F4F8FF") if lit else H("#D6E0EE")                  # snowcap
            else:
                color = H("#9AA8C4") if lit else H("#7C8AA6")                  # lit / shaded face
            c.set(x, y, color)
    # The trail: from the bottom-left (x 14, right behind the gate) along the foothills, then
    # up the face in switchbacks toward the peak.
    dirt, dirt_light = H("#8A6238"), H("#D2AA70")
    points = [(14, h - 1), (34, 70), (84, 62), (62, 50), (90, 40), (68, 30), (82, 20), (76, 12)]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        steps = max(abs(x1 - x0), abs(y1 - y0)) * 2
        for i in range(steps + 1):
            t = i / steps
            x, y = round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t)
            c.set(x, y, dirt_light)
            c.set(x, y + 1, dirt)
    return c


def ufo(frame=0):
    """A classic flying saucer: glass dome, silver disc, blinking rim lights, green glow underneath."""
    w, h = 40, 18
    c = Canvas(w, h)
    H = hex_color
    fill_ellipse(c, 19.5, 10, 19, 4.2, H("#B8C0CC"))                           # disc
    for x in range(w):
        for y in range(0, 10):
            if c.get(x, y) and c.get(x, y)[3]:
                c.set(x, y, H("#D8DEE6"))                                       # lit top of the disc
    c.rect(1, 10, w - 1, 11, H("#6E7684"))                                      # rim band
    for y in range(1, 8):                                                       # glass dome
        for x in range(12, 28):
            if ((x - 19.5) / 7.5) ** 2 + ((y - 7.5) / 6.5) ** 2 <= 1:
                c.set(x, y, H("#8FE3E8"))
    c.set(16, 3, H("#E8FFFF"))
    c.set(17, 3, H("#E8FFFF"))
    c.set(16, 4, H("#E8FFFF"))
    colors = (H("#FFE14A"), H("#FF5A4A")) if frame == 0 else (H("#FF5A4A"), H("#FFE14A"))
    for i, x in enumerate(range(5, 36, 6)):                                     # rim lights
        c.set(x, 10, colors[i % 2])
        c.set(x + 1, 10, colors[i % 2])
    fill_ellipse(c, 19.5, 14.5, 6, 1.8, H("#7CFF7C"))                           # tractor glow
    return outlined(c, H("#2A2E38"))


def beam_ring():
    """One green tractor-beam ring (an ellipse outline)."""
    w, h = 24, 6
    c = Canvas(w, h)
    green, light = hex_color("#7CFF7C"), hex_color("#D8FFD0")
    for x in range(w):
        for y in range(h):
            d = ((x - 11.5) / 11.5) ** 2 + ((y - 2.5) / 2.5) ** 2
            if 0.55 <= d <= 1.05:
                c.set(x, y, light if y <= 1 else green)
    return c


def dirt_path():
    """A tileable strip of dirt trail (64x10) with pebbles and ragged edges."""
    w, h = 64, 10
    c = Canvas(w, h)
    H = hex_color
    rng = random.Random("dirt-path")
    base, dark, light = H("#8A6A44"), H("#6E5232"), H("#A88458")
    for x in range(w):
        for y in range(h):
            edge = y == 0 or y == h - 1
            if edge and rng.random() < 0.45:
                continue                                                        # ragged edges
            roll = rng.random()
            c.set(x, y, dark if roll < 0.12 else (light if roll < 0.2 else base))
    return c


def alien(pose="stand", coat=False, clipboard=False, scared=False, angry=False, carry=False):
    """A little green alien in a silver suit, facing right: a big head with a huge black eye.
    Poses: "stand", and walking strides "a"/"b". `coat` puts it in a white lab coat, `clipboard`
    has it holding one, and `scared` gives it wide, white-rimmed eyes and a screaming mouth."""
    c = Canvas(22, 36)
    H = hex_color
    skin, skin_dark, suit, suit_dark = H("#6BD66B"), H("#3FA04A"), H("#B8C0CC"), H("#8A93A2")
    if coat:
        suit, suit_dark = H("#F2F4F8"), H("#C9CED8")
    stride = {"stand": 0, "a": 2, "b": -2}[pose]
    # Legs (suit), striding.
    for x0, sign in ((8, 1), (12, -1)):
        for y in range(28, 35):
            shift = stride * sign if y >= 31 else 0
            c.rect(x0 + shift, y, x0 + shift + 2, y + 1, suit_dark if x0 == 8 else suit)
        c.rect(x0 + stride * sign, 34, x0 + stride * sign + 3, 36, H("#4A505C"))           # boots
    c.rect(7, 18, 15, 29, suit)                                                 # body
    c.rect(7, 18, 8, 29, suit_dark)
    c.rect(10, 16, 12, 19, skin_dark)                                           # neck
    fill_ellipse(c, 11, 9, 8, 8, skin)                                          # big head
    for y in range(2, 17):
        for x in range(4, 8):
            if c.get(x, y) == skin:
                c.set(x, y, skin_dark)                                          # shade at the back
    if scared:
        # Wide, white-rimmed eyes and a screaming "O" mouth.
        fill_ellipse(c, 15.5, 8, 3.8, 3.4, H("#FFFFFF"))
        fill_ellipse(c, 16, 8, 1.6, 1.6, H("#101018"))
        c.rect(15, 12, 18, 15, H("#2A0E18"))
        c.set(16, 13, H("#C8384A"))
    else:
        for y, (x0, x1) in {6: (15, 17), 7: (13, 18), 8: (13, 19), 9: (14, 19), 10: (15, 18)}.items():
            for x in range(x0, x1):
                c.set(x, y, H("#101018"))                                       # big slanted almond eye
        c.set(16, 7, H("#5A5A70"))                                              # glint
        c.set(17, 13, skin_dark)                                                # mouth
    if angry:
        # A scowl: the top of the eye cut off by a heavy, slanted brow, and a frown.
        for x in range(12, 20):
            c.set(x, 6, skin)
        for (x, y) in ((12, 5), (13, 5), (14, 6), (15, 6), (16, 7), (17, 7), (18, 7)):
            c.set(x, y, H("#163A1C"))
        c.set(17, 13, skin)
        for (x, y) in ((15, 14), (16, 13), (17, 13), (18, 14)):
            c.set(x, y, skin_dark)
    if coat:
        c.rect(7, 28, 15, 31, suit)                                             # coat tails
        c.set(11, 20, suit_dark)                                                # lapels
        c.set(11, 22, suit_dark)
        c.set(11, 24, suit_dark)
    if carry:
        thick_line(c, 13, 20, 15, 13, 2, skin)                                  # both arms up, carrying
        thick_line(c, 8, 20, 6, 13, 2, skin_dark)
        c.rect(14, 11, 17, 13, skin)
        c.rect(5, 11, 8, 13, skin_dark)
    elif clipboard:
        thick_line(c, 13, 20, 15, 23, 2, skin)                                  # arm bent, holding it up
        c.rect(15, 19, 21, 27, H("#8B5A2B"))                                    # clipboard
        c.rect(16, 21, 20, 26, H("#F4F4EE"))
        c.rect(17, 19, 19, 21, H("#9AA2AE"))                                    # clip
        for y in (22, 24):
            c.rect(16, y, 20, y + 1, H("#9AA2AE"))
    else:
        thick_line(c, 13, 20, 16, 27, 2, skin)                                  # arm
        c.set(16, 28, skin)
        c.set(17, 28, skin)
    return outlined(c, H("#163A1C"))


def metal_table():
    """A metal lab table with a thick top and braced legs."""
    c = Canvas(46, 22)
    H = hex_color
    top, top_light, leg, leg_dark = H("#9AA2AE"), H("#C9CED8"), H("#6E7684"), H("#4A505C")
    c.rect(0, 0, 46, 4, top)
    c.rect(0, 0, 46, 1, top_light)
    for x0 in (3, 39):
        c.rect(x0, 4, x0 + 4, 22, leg)
        c.rect(x0 + 3, 4, x0 + 4, 22, leg_dark)
    c.rect(7, 14, 39, 16, leg_dark)                                             # crossbar
    return outlined(c, H("#2A2E38"))


def shotgun_item():
    """The hunter's shotgun lying flat, stock on the left."""
    c = Canvas(36, 7)
    H = hex_color
    wood_light, wood, wood_dark = H("#B98049"), H("#8B5A2B"), H("#5E3A1A")
    steel_light, steel, steel_dark = H("#A3ADBF"), H("#5C6475"), H("#3A404C")
    c.rect(1, 2, 10, 6, wood)                                                   # stock
    c.rect(1, 2, 10, 3, wood_light)
    c.rect(1, 5, 4, 6, wood_dark)
    c.rect(10, 2, 15, 5, steel)                                                 # receiver
    c.rect(10, 4, 15, 5, steel_dark)
    c.rect(15, 3, 21, 5, wood_dark)                                             # forend
    c.rect(15, 2, 35, 3, steel_light)                                           # barrel
    c.rect(21, 3, 35, 4, steel)
    return outlined(c, H("#26263A"))


def gas_puff():
    """A small, sickly green-yellow puff of gas: three overlapping blobs with a shaded underside."""
    c = Canvas(14, 10)
    H = hex_color
    light, mid = H("#C9E07A"), H("#9DBE52")
    for (cx, cy, r) in ((4.5, 5.5, 3.6), (8.5, 4.0, 3.8), (10.0, 6.5, 2.8)):
        fill_ellipse(c, cx, cy, r, r * 0.9, light)
    for x in range(14):
        for y in range(6, 10):
            if c.get(x, y) == light:
                c.set(x, y, mid)                                                # shaded underside
    c.set(7, 2, H("#F0F8C8"))
    c.set(8, 2, H("#F0F8C8"))
    return outlined(c, H("#6E8A3A"))


def vat(part="back"):
    """A tall glass specimen vat on a metal base (26x48).
    "back": the base, cap, and the glowing green liquid inside (drawn behind the floating bird).
    "front": the glass itself, a translucent green tint and highlights (drawn over the bird).
    "broken": the base with jagged glass shards; the liquid is gone."""
    w, h = 26, 48
    c = Canvas(w, h)
    H = hex_color
    metal, metal_light, metal_dark = H("#8C939E"), H("#C9CED8"), H("#4A505C")
    if part in ("back", "broken"):
        c.rect(0, 38, w, h, H("#5C6370"))                                       # base
        c.rect(0, 38, w, 39, metal_light)
        c.rect(0, h - 2, w, h, metal_dark)
        c.rect(2, 36, w - 2, 38, metal)                                         # bottom ring
    if part in ("back", "broken"):
        # The metal frame (cap and two side posts) survives the shot, so the alarm stays mounted.
        c.rect(1, 0, w - 1, 4, metal)                                           # cap
        c.rect(1, 0, w - 1, 1, metal_light)
        c.rect(1, 4, 3, 36, metal_dark)                                         # side posts
        c.rect(w - 3, 4, w - 1, 36, metal_dark)
    if part == "back":
        c.rect(3, 4, w - 3, 36, H("#10201A", 200))                              # dark interior
        c.rect(3, 9, w - 3, 36, H("#3FBF5A", 215))                              # the liquid
        c.rect(3, 9, w - 3, 10, H("#8CF09A", 230))                              # its surface
        for (x, y) in ((7, 30), (18, 25), (10, 19), (15, 33), (19, 14)):
            c.set(x, y, H("#B8FFC0", 230))                                      # bubbles
        return outlined(c, H("#26263A"))
    if part == "front":
        c.rect(3, 9, w - 3, 36, H("#3FBF5A", 70))                               # liquid tint over the bird
        c.rect(3, 4, 4, 36, H("#E8F4FF", 150))                                  # glass edges
        c.rect(w - 4, 4, w - 3, 36, H("#E8F4FF", 110))
        c.rect(6, 6, 7, 34, H("#FFFFFF", 120))                                  # highlight streaks
        c.rect(8, 8, 9, 20, H("#FFFFFF", 60))
        return c
    # Broken: jagged shards rising from the bottom ring and hanging from the cap.
    shard = H("#D8ECF4", 190)
    for x0, height in ((4, 7), (7, 3), (10, 5), (13, 2), (16, 6), (19, 3), (21, 6)):
        for k in range(height):
            c.set(x0 + (k % 2), 35 - k, shard)
    for x0, height in ((4, 5), (8, 2), (12, 4), (17, 3), (20, 6)):
        for k in range(height):
            c.set(x0 + (k % 2), 4 + k, shard)
    return outlined(c, H("#26263A"))


def bird_skeleton(kind="dove", reach=False, stride=0, coat=False):
    """A risen bird skeleton standing upright like a little zombie, facing right.
    `reach` stretches its wing bones out in front; `stride` shuffles its legs."""
    s = 1.0 if kind == "dove" else 1.25
    w, h = (18, 24) if kind == "dove" else (22, 30)
    c = Canvas(w, h)
    H = hex_color
    bone, bone_dark, socket = H("#EDE6D2"), H("#B9AF96"), H("#1A1414")
    S = lambda v: v * s

    def line(x0, y0, x1, y1, width=1, color=bone):
        thick_line(c, S(x0), S(y0), S(x1), S(y1), width, color)

    fill_ellipse(c, S(9), S(4.5), S(3.6), S(3.2), bone)                         # skull
    c.set(int(S(10)), int(S(4)), socket)                                        # eye socket
    c.set(int(S(11)), int(S(4)), socket)
    if kind == "dove":
        line(12.5, 4.5, 15, 5.5, 1, H("#E8C56A"))                               # little beak
    else:
        line(12.5, 5.5, 16.5, 6, 2, H("#E8C56A"))                               # flat duck bill
    line(8, 8, 8, 16)                                                           # spine
    for y in (9.5, 11.5, 13.5):
        line(6, y, 10.5, y, 1, bone_dark if y > 12 else bone)                   # ribs
    line(6, 16, 10, 16, 2)                                                      # pelvis
    if reach:
        line(9, 9, 16, 9)                                                       # wing bones out front
        line(9, 10, 16, 11)
        for x in (14, 16):
            line(x, 9, x + 1, 7, 1, bone_dark)                                  # feather-bone "fingers"
    else:
        line(8, 9, 5, 15)
        line(9, 9, 11, 15)
    if coat:
        # A lab coat over the ribs, and a clipboard held up in front.
        c.rect(int(S(5)), int(S(8)), int(S(12)) + 1, int(S(18)) + 1, H("#F2F4F8"))
        c.rect(int(S(5)), int(S(8)), int(S(6)), int(S(18)) + 1, H("#C9CED8"))
        c.set(int(S(9)), int(S(10)), H("#C9CED8"))
        c.set(int(S(9)), int(S(13)), H("#C9CED8"))
        c.rect(int(S(11)), int(S(9)), int(S(15)) + 1, int(S(15)) + 1, H("#8B5A2B"))
        c.rect(int(S(12)), int(S(10)), int(S(14)) + 1, int(S(14)) + 1, H("#F4F4EE"))
        line(10, 12, 12, 11, 1, bone)                                           # bony hand on it
    line(7, 16, 6 + stride, 22)                                                 # legs
    line(9, 16, 10 - stride, 22)
    line(6 + stride, 22, 8 + stride, 22)                                        # feet
    line(10 - stride, 22, 12 - stride, 22)
    return outlined(c, H("#3A3428"))


def clipboard():
    """The scientist's clipboard: a brown board, a metal clip, and a page of alien notes."""
    c = Canvas(12, 15)
    H = hex_color
    c.rect(1, 2, 11, 15, H("#8B5A2B"))
    c.rect(2, 4, 10, 14, H("#F4F4EE"))
    c.rect(4, 1, 8, 4, H("#9AA2AE"))
    c.set(5, 1, H("#C9CED8"))
    for y in (6, 8, 10, 12):
        c.rect(3, y, 9 if y != 12 else 6, y + 1, H("#6FBF6F"))                  # squiggly alien notes
    return outlined(c, H("#2A1A0C"))


def tent():
    """The hunter's A-frame tent: olive canvas, a darker door flap tied open, guy lines, pegs."""
    w, h = 56, 36
    c = Canvas(w, h)
    H = hex_color
    canvas_light, canvas_mid, canvas_dark = H("#8A9A5B"), H("#6E7E44"), H("#4E5A30")
    for y in range(2, h - 1):
        half = int((y - 2) / (h - 3) * 24) + 2
        for x in range(28 - half, 28 + half):
            c.set(x, y, canvas_light if x < 28 else canvas_mid)
    for y in range(12, h - 1):                                                  # open door, dark inside
        half = int((y - 12) / (h - 13) * 8) + 1
        for x in range(28 - half, 28 + half):
            c.set(x, y, H("#1A1A14"))
    for y in range(12, h - 1):                                                  # tied-back flaps
        half = int((y - 12) / (h - 13) * 8) + 1
        c.set(28 - half - 1, y, canvas_dark)
        c.set(28 + half, y, canvas_dark)
    thick_line(c, 28, 0, 28, 3, 1, H("#5A3519"))                                # pole tip
    for (x0, x1) in ((5, 0), (51, 55)):                                         # guy lines and pegs
        thick_line(c, x0, 14, x1, h - 2, 1, H("#C9C2A8"))
    c.rect(0, h - 3, 2, h, H("#8C939E"))
    c.rect(w - 2, h - 3, w, h, H("#8C939E"))
    return outlined(c, H("#2A2E1A"))


def firepit_unlit():
    """A ring of stones around a few unlit logs."""
    c = Canvas(18, 9)
    H = hex_color
    thick_line(c, 4, 6, 13, 4, 2, H("#6B4527"))
    thick_line(c, 4, 4, 13, 6, 2, H("#5A3519"))
    for x in range(0, 18, 3):
        c.rect(x, 6, x + 2, 9, H("#8C939E") if x % 2 else H("#6E7684"))
    c.set(8, 5, H("#3A3A3A"))                                                   # old ash
    c.set(9, 5, H("#4A4A4A"))
    return outlined(c, H("#22222C"))


def camp_chair():
    """An empty folding camp chair (blue canvas, crossed legs), facing right."""
    c = Canvas(18, 18)
    H = hex_color
    chair, chair_dark = H("#2F6E9E"), H("#1F4A6E")
    c.rect(2, 0, 5, 10, chair_dark)                                             # backrest
    c.rect(3, 8, 15, 11, chair)                                                 # seat
    thick_line(c, 4, 11, 14, 17, 1, chair_dark)
    thick_line(c, 14, 11, 4, 17, 1, chair_dark)
    c.rect(13, 6, 16, 7, chair_dark)                                            # armrest
    return outlined(c, H("#141E2A"))


def folding_table():
    """A little fold-out camp table with a lantern, a mug, and a couple of cans on top."""
    c = Canvas(28, 20)
    H = hex_color
    top, leg = H("#C9CED8"), H("#6E7684")
    c.rect(1, 8, 27, 10, top)
    thick_line(c, 4, 10, 10, 19, 1, leg)
    thick_line(c, 10, 10, 4, 19, 1, leg)
    thick_line(c, 18, 10, 24, 19, 1, leg)
    thick_line(c, 24, 10, 18, 19, 1, leg)
    c.rect(4, 2, 9, 8, H("#3A3F4E"))                                            # lantern
    c.rect(5, 3, 8, 7, H("#FFE27A"))
    c.rect(5, 0, 8, 2, H("#3A3F4E"))
    c.rect(13, 5, 16, 8, H("#C8382E"))                                          # mug
    c.set(16, 6, H("#C8382E"))
    c.rect(19, 4, 21, 8, H("#9AA2AE"))                                          # cans
    c.rect(22, 5, 24, 8, H("#D9A562"))
    return outlined(c, H("#22222C"))


def backpack():
    """A green hiking backpack with a rolled sleeping mat on top."""
    c = Canvas(12, 15)
    H = hex_color
    c.rect(1, 4, 11, 15, H("#4E7A3A"))
    c.rect(3, 8, 9, 12, H("#3E6230"))                                           # front pocket
    c.rect(1, 1, 11, 4, H("#C8641A"))                                           # sleeping mat
    c.rect(2, 1, 3, 4, H("#9A4A12"))
    return outlined(c, H("#1E2A16"))


def cooler():
    """A red-and-white camp cooler."""
    c = Canvas(16, 11)
    H = hex_color
    c.rect(1, 3, 15, 11, H("#C8382E"))
    c.rect(1, 1, 15, 4, H("#F4F4EE"))                                           # lid
    c.rect(6, 0, 10, 1, H("#9AA2AE"))                                           # handle
    return outlined(c, H("#2A1414"))


def padlock(glow=False):
    """A small black padlock (glow=True adds a bright yellow rim for the "shoot me" flash)."""
    c = Canvas(9, 10)
    H = hex_color
    shackle, body, key = H("#5C6370"), H("#16161C"), H("#8C939E")
    for (x, y) in ((3, 1), (4, 1), (5, 1), (2, 2), (6, 2), (2, 3), (6, 3)):
        c.set(x, y, shackle)
    c.rect(1, 4, 8, 9, body)
    c.set(4, 6, key)
    c.set(4, 7, key)
    return outlined(c, H("#FFD84A") if glow else H("#0A0A0E"))


def alien_logo():
    """A little green alien head for the "Restricted Access" sign."""
    rows = [
        "..GGGGG..",
        ".GGGGGGG.",
        "GGGGGGGGG",
        "GKKGGGKKG",
        "GKKKGKKKG",
        ".GGGGGGG.",
        "..GGGGG..",
        "...GGG...",
        "....G....",
    ]
    return sprite(rows, {"G": hex_color("#5BD15B"), "K": hex_color("#101018")})


def sign_post():
    """A plain wooden post for the campground sign."""
    c = Canvas(4, 34)
    H = hex_color
    c.rect(0, 0, 4, 34, H("#7A4E2C"))
    c.rect(0, 0, 1, 34, H("#9A6A3C"))
    c.rect(3, 0, 4, 34, H("#5A3519"))
    return c


def rv():
    """A boxy vintage camper (RV), facing left, with a striped side and a door."""
    w, h = 76, 40
    c = Canvas(w, h)
    H = hex_color
    body, body_shade, stripe, stripe2 = H("#F1EBDD"), H("#CFC6B2"), H("#D9642B"), H("#E8A43A")
    glass, tire, hub = H("#5E8FB8"), H("#1C1C22"), H("#9AA2AE")
    c.rect(2, 4, w - 2, 32, body)                                               # box
    c.rect(2, 26, w - 2, 32, body_shade)
    c.rect(2, 16, w - 2, 19, stripe)                                            # stripes
    c.rect(2, 19, w - 2, 21, stripe2)
    c.rect(4, 2, 24, 4, body)                                                   # cab-over roof
    c.rect(0, 10, 3, 26, body_shade)                                            # front bumper
    c.rect(4, 7, 16, 14, glass)                                                 # windshield
    c.rect(26, 7, 38, 14, glass)                                                # side windows
    c.rect(44, 7, 56, 14, glass)
    c.rect(60, 6, 70, 30, H("#B8B0A0"))                                         # door
    c.rect(61, 17, 63, 19, H("#5C6370"))                                        # handle
    for x0 in (10, 52):                                                         # wheels
        fill_ellipse(c, x0 + 5, 33, 5, 5, tire)
        fill_ellipse(c, x0 + 5, 33, 2, 2, hub)
    return outlined(c, H("#2A2A34"))


def campfire(frame=0):
    """A small campfire: crossed logs, stones, and flickering flames (two frames)."""
    c = Canvas(16, 15)
    H = hex_color
    for x in range(1, 15, 3):
        c.rect(x, 12, x + 2, 15, H("#8C939E"))                                  # stones
    thick_line(c, 2, 13, 13, 10, 2, H("#6B4527"))                               # logs
    thick_line(c, 2, 10, 13, 13, 2, H("#5A3519"))
    flames = [(7, 1, 3, 10), (4, 4, 2, 9), (10, 3, 2, 9)] if frame == 0 else [(8, 2, 3, 10), (4, 3, 2, 9), (11, 5, 2, 9)]
    for (x, top, half, bottom) in flames:
        for y in range(top, bottom + 1):
            spread = int(half * (y - top) / max(1, bottom - top) + 0.5)
            for dx in range(-spread, spread + 1):
                inner = abs(dx) < spread and y > top + 2
                c.set(x + dx, y, H("#FFE27A") if inner else H("#F28C28"))
    return c


def camper(kid=False):
    """A camper sitting in a folding camp chair, facing right, roasting a marshmallow on a stick.
    The kid is smaller, in a blue hoodie; dad wears a red cap."""
    base_w, base_h = 38, 32
    s = 0.72 if kid else 1.0
    w, h = int(base_w * s) + 1, int(base_h * s) + 1
    c = Canvas(w, h)
    H = hex_color
    S = lambda v: int(round(v * s))
    shirt = H("#3A6FC4") if kid else H("#4E7A3A")
    pants, skin = H("#3A3F5A"), H("#F2C29B")
    hair = H("#C88A3A") if kid else H("#5A3A22")
    chair, chair_dark = H("#2F6E9E"), H("#1F4A6E")
    # Chair: seat, back, and crossed legs.
    c.rect(S(4), S(20), S(20), S(23), chair)
    c.rect(S(3), S(9), S(6), S(23), chair_dark)
    thick_line(c, S(5), S(23), S(17), S(31), 1, chair_dark)
    thick_line(c, S(17), S(23), S(5), S(31), 1, chair_dark)
    # Body: torso, lap, and shins down to the ground.
    c.rect(S(6), S(9), S(14), S(21), shirt)
    c.rect(S(8), S(19), S(20), S(23), pants)
    c.rect(S(17), S(22), S(21), S(31), pants)
    c.rect(S(17), S(30), S(23), S(32), H("#4A2C18"))                            # shoes
    # Head.
    c.rect(S(7), S(1), S(14), S(9), skin)
    c.rect(S(6), S(0), S(14), S(3), hair)
    c.set(S(12), S(4), H("#101018"))                                            # eye
    if not kid:
        c.rect(6, 0, 15, 2, H("#8E2420"))                                       # dad's cap
        c.rect(13, 1, 17, 2, H("#8E2420"))
    # Arm holding the roasting stick out over the fire, with a marshmallow on the end.
    c.rect(S(11), S(12), S(18), S(15), shirt)
    c.rect(S(18), S(12), S(20), S(14), skin)
    thick_line(c, S(19), S(13), w - 3, S(8), 1, H("#8B5A2B"))
    c.rect(w - 4, S(6), w - 1, S(9) + 1, H("#FFF6E6"))                           # marshmallow
    return outlined(c, H("#22222C"))


def arrow_right():
    """A chunky orange arrow pointing right ("proceed")."""
    c = Canvas(11, 9)
    H = hex_color
    orange, light = H("#F08A24"), H("#FFC66B")
    c.rect(1, 3, 6, 6, orange)
    c.rect(1, 3, 6, 4, light)
    for col, half in enumerate((3, 2, 1, 0)):
        c.rect(6 + col, 4 - half, 7 + col, 5 + half, orange)
    return outlined(c, H("#2A1A0C"))


def prop_mountains():
    """A distant, hazy blue-grey mountain range with snowcaps; flat bottom sits on the horizon."""
    w, h = 120, 34
    c = Canvas(w, h)
    H = hex_color
    peaks = [(14, 8), (38, 2), (62, 12), (84, 4), (108, 10)]
    for x in range(w):
        # The peak that forms the silhouette here decides which face (lit or shaded) we're on.
        owner = min(peaks, key=lambda pk: pk[1] + abs(x - pk[0]) * 0.9)
        top = int(owner[1] + abs(x - owner[0]) * 0.9)
        lit = x <= owner[0]
        for y in range(max(top, 0), h):
            depth = y - top
            if depth < 3 and top < 14:
                color = H("#F4F8FF") if lit else H("#D6E0EE")          # snowcap
            else:
                color = H("#9AA8C4") if lit else H("#7C8AA6")          # lit / shaded face
            c.set(x, y, color)
    # Fade the base into the haze above the hills.
    for y in range(h - 5, h):
        for x in range(w):
            if c.px[y][x][3] and bayer(x, y) < (y - (h - 5)) / 5:
                c.set(x, y, H("#A6C4DE"))
    return c


# MARK: - App icon

APP_ICON_DIR = os.path.join(ROOT, "doveHunt", "Assets.xcassets", "AppIcon.appiconset")
ICON_ART_SIZE = 32       # native icon art is 32x32...
ICON_UPSCALE = 32        # ...scaled 32x with nearest-neighbor to 1024x1024


def app_icon(variant):
    """A dove in the crosshairs over a pixel sky. Variants: 'light', 'dark', 'tinted'."""
    n = ICON_ART_SIZE
    c = Canvas(n, n)
    gy = 25

    if variant == "light":
        sky = [hex_color(v) for v in ("#1F55A8", "#2F72C4", "#4C93DC", "#74B4EC", "#A2D4F7")]
        dithered_gradient(c, sky, 0, gy)
        shade_blob(c, [(5.5, 5.5, 2.2), (3.5, 6.5, 1.6), (7.8, 6.3, 1.7)], None,
                   hex_color("#BFDDF2"), hex_color("#F4FAFF"), hex_color("#FFFFFF"))
        ground = (hex_color("#4C9F3C"), hex_color("#3D8731"), hex_color("#66B852"))
        reticle = hex_color("#F0502E")
    elif variant == "dark":
        sky = [hex_color(v) for v in ("#14161D", "#23262F", "#2D313C", "#3A3F4C")]
        dithered_gradient(c, sky, 0, gy)
        for sx, sy in ((3, 3), (27, 5), (6, 12), (25, 19), (13, 2), (29, 13)):
            c.set(sx, sy, hex_color("#F6E9A8"))
        ground = (hex_color("#8C722A"), hex_color("#6E5A1C"), hex_color("#B8973A"))
        reticle = hex_color("#F4D35E")
    else:  # tinted: grayscale artwork on black; the system applies the tint
        c.rect(0, 0, n, n, hex_color("#000000"))
        ground = (hex_color("#3A3A3A"), hex_color("#2A2A2A"), hex_color("#4A4A4A"))
        reticle = hex_color("#D0D0D0")

    # Ground strip with a grassy top edge.
    base, dark, light = ground
    rng = random.Random(f"icon-{variant}")
    c.rect(0, gy, n, n, base)
    for y in range(gy, n):
        for x in range(n):
            if rng.random() < 0.14:
                c.set(x, y, dark)
    for x in range(n):
        c.set(x, gy, light)
        if rng.random() < 0.35:
            c.set(x, gy - 1, base)

    # The dove, centered.
    palette = dict(SPRITE_PALETTE)
    if variant == "tinted":
        palette = {k: (lambda r, g, b, a: (int(0.3 * r + 0.59 * g + 0.11 * b),) * 3 + (a,))(*v)
                   for k, v in palette.items()}
    c.stamp(DOVE_WINGS_UP, palette, 8, 8)

    # Crosshair: a continuous midpoint-circle ring with gaps on the axes and inward ticks.
    cx, cy, r = 16, 15, 11
    ring = set()
    x, y, err = r, 0, 1 - r
    while x >= y:
        for px, py in ((x, y), (y, x), (-y, x), (-x, y), (-x, -y), (-y, -x), (y, -x), (x, -y)):
            ring.add((px, py))
        y += 1
        if err < 0:
            err += 2 * y + 1
        else:
            x -= 1
            err += 2 * (y - x) + 1
    for px, py in ring:
        if abs(px) > 1 and abs(py) > 1:
            c.set(cx + px, cy + py, reticle)
    for i in range(3):
        c.set(cx, cy - r + i, reticle)   # top tick
        c.set(cx, cy + r - i, reticle)   # bottom tick
        c.set(cx - r + i, cy, reticle)   # left tick
        c.set(cx + r - i, cy, reticle)   # right tick
    return c


def upscale(canvas, factor):
    return [[canvas.px[y // factor][x // factor] for x in range(canvas.w * factor)]
            for y in range(canvas.h * factor)]


def write_app_icon():
    files = {"light": "AppIcon.png", "dark": "AppIcon-Dark.png", "tinted": "AppIcon-Tinted.png"}
    for variant, filename in files.items():
        write_png(os.path.join(APP_ICON_DIR, filename), upscale(app_icon(variant), ICON_UPSCALE))
    contents = {
        "images": [
            {"filename": files["light"], "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}],
             "filename": files["dark"], "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "tinted"}],
             "filename": files["tinted"], "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(APP_ICON_DIR, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)


# MARK: - Main

def main():
    write_group_contents(WIDGET_OUTPUT_DIR)
    write_group_contents(APP_OUTPUT_DIR)

    for name, painter in LANDSCAPES.items():
        for family, (w, h) in SCREEN_SIZES.items():
            # Seeded per landscape+family so output is stable between runs.
            rng = random.Random(f"{name}-{family}")
            write_imageset(f"{name}_{family}", painter(w, h, rng).px, WIDGET_OUTPUT_DIR)

    shared_sprites = {
        "dove_wings_up": sprite(DOVE_WINGS_UP, SPRITE_PALETTE),
        "dove_wings_down": sprite(DOVE_WINGS_DOWN, SPRITE_PALETTE),
    }
    for name, art in shared_sprites.items():
        write_imageset(name, art.px, WIDGET_OUTPUT_DIR)
        write_imageset(name, art.px, APP_OUTPUT_DIR)

    write_imageset("feather_poof", sprite(FEATHER_POOF, SPRITE_PALETTE).px, WIDGET_OUTPUT_DIR)
    write_imageset("shotgun_idle", shotgun(False).px, WIDGET_OUTPUT_DIR)
    write_imageset("shotgun_fire", shotgun(True).px, WIDGET_OUTPUT_DIR)
    for direction in ("left", "right"):
        write_imageset(f"shotgun_{direction}_idle", shotgun_aimed(False, direction).px, WIDGET_OUTPUT_DIR)
        write_imageset(f"shotgun_{direction}_fire", shotgun_aimed(True, direction).px, WIDGET_OUTPUT_DIR)
    for ch in DIGITS:
        write_imageset(f"digit_{ch}", digit(ch).px, WIDGET_OUTPUT_DIR)

    for w, h in APP_BACKGROUND_SIZES:
        art = app_background(w, h, random.Random(f"app-background-{w}"))
        write_imageset(f"app_background_{w}", art.px, APP_OUTPUT_DIR)
    write_imageset("hunter", hunter().px, APP_OUTPUT_DIR)
    write_imageset("hunter_walk_a", hunter("a").px, APP_OUTPUT_DIR)
    write_imageset("hunter_walk_b", hunter("b").px, APP_OUTPUT_DIR)
    write_imageset("hunter_look_up", hunter("look_up").px, APP_OUTPUT_DIR)
    write_imageset("hunter_shocked", hunter("shocked").px, APP_OUTPUT_DIR)
    write_imageset("hunter_unarmed", hunter("unarmed").px, APP_OUTPUT_DIR)
    write_imageset("hunter_unarmed_walk_a", hunter("unarmed_a").px, APP_OUTPUT_DIR)
    write_imageset("hunter_unarmed_walk_b", hunter("unarmed_b").px, APP_OUTPUT_DIR)
    write_imageset("hunter_unarmed_shocked", hunter("unarmed_shocked").px, APP_OUTPUT_DIR)
    write_imageset("hunter_stomach", hunter("stomach").px, APP_OUTPUT_DIR)
    write_imageset("feather_poof", sprite(FEATHER_POOF, SPRITE_PALETTE).px, APP_OUTPUT_DIR)
    flash = Canvas(9, 5)
    flash.stamp(MUZZLE_FLASH, GUN_PALETTE, 0, 0)
    write_imageset("muzzle_flash", flash.px, APP_OUTPUT_DIR)
    write_imageset("prop_tree", prop_tree().px, APP_OUTPUT_DIR)
    write_imageset("prop_bush", prop_bush().px, APP_OUTPUT_DIR)
    write_imageset("cabin_closed", cabin(False).px, APP_OUTPUT_DIR)
    write_imageset("cabin_open", cabin(True).px, APP_OUTPUT_DIR)
    write_imageset("interior_door_closed", cabin_interior(False).px, APP_OUTPUT_DIR)
    write_imageset("interior_door_open", cabin_interior(True).px, APP_OUTPUT_DIR)
    write_imageset("anna", anna().px, APP_OUTPUT_DIR)
    write_imageset("anna_walk_a", anna("a").px, APP_OUTPUT_DIR)
    write_imageset("anna_walk_b", anna("b").px, APP_OUTPUT_DIR)
    write_imageset("mallard_wings_up", bird_sprite(MALLARD_WINGS_UP, MALLARD_PALETTE).px, APP_OUTPUT_DIR)
    write_imageset("mallard_wings_down", bird_sprite(MALLARD_WINGS_DOWN, MALLARD_PALETTE).px, APP_OUTPUT_DIR)
    write_imageset("mallard_hit", bird_sprite(MALLARD_HIT, MALLARD_PALETTE).px, APP_OUTPUT_DIR)
    write_imageset("prop_pine", prop_pine().px, APP_OUTPUT_DIR)
    write_imageset("prop_mountains", prop_mountains().px, APP_OUTPUT_DIR)
    write_imageset("prop_pond", pond().px, APP_OUTPUT_DIR)
    write_imageset("fishing_rod", fishing_rod().px, APP_OUTPUT_DIR)
    write_imageset("fishing_rod_short", fishing_rod(short=True).px, APP_OUTPUT_DIR)
    write_imageset("prop_pond_small", pond(POND_SMALL_SIZE).px, APP_OUTPUT_DIR)
    write_imageset("prop_pond_large", pond(POND_LARGE_SIZE, roundness=2.4).px, APP_OUTPUT_DIR)
    write_imageset("tackle_box", tackle_box().px, APP_OUTPUT_DIR)
    write_imageset("poop_drop", poop_drop().px, APP_OUTPUT_DIR)
    write_imageset("poop_splat", poop_splat().px, APP_OUTPUT_DIR)
    write_imageset("bear_standing", bear_standing().px, APP_OUTPUT_DIR)
    for pose, name in (("stand", "bear_four"), ("roar", "bear_roar"), ("a", "bear_run_a"), ("b", "bear_run_b")):
        write_imageset(name, bear_four(pose).px, APP_OUTPUT_DIR)
    for pose in ("drink", "stand", "a", "b"):
        write_imageset(f"deer_{pose}", deer(pose).px, APP_OUTPUT_DIR)
        write_imageset(f"fawn_{pose}", deer(pose, fawn=True).px, APP_OUTPUT_DIR)
    write_imageset("mallard_float", bird_sprite(MALLARD_FLOAT, MALLARD_PALETTE).px, APP_OUTPUT_DIR)
    write_imageset("prop_stream", prop_stream().px, APP_OUTPUT_DIR)
    write_imageset("fence_closed", chain_fence().px, APP_OUTPUT_DIR)
    write_imageset("fence_open", chain_fence(open_gate=True).px, APP_OUTPUT_DIR)
    write_imageset("prop_far_mountain", far_mountain().px, APP_OUTPUT_DIR)
    write_imageset("padlock", padlock().px, APP_OUTPUT_DIR)
    for pose, name in (("stand", "alien"), ("a", "alien_walk_a"), ("b", "alien_walk_b")):
        write_imageset(name, alien(pose).px, APP_OUTPUT_DIR)
    write_imageset("metal_table", metal_table().px, APP_OUTPUT_DIR)
    write_imageset("shotgun_item", shotgun_item().px, APP_OUTPUT_DIR)
    write_imageset("gas_puff", gas_puff().px, APP_OUTPUT_DIR)
    for part in ("back", "front", "broken"):
        write_imageset(f"vat_{part}", vat(part).px, APP_OUTPUT_DIR)
    for kind in ("dove", "mallard"):
        write_imageset(f"skeleton_{kind}", bird_skeleton(kind).px, APP_OUTPUT_DIR)
        write_imageset(f"skeleton_{kind}_reach_a", bird_skeleton(kind, reach=True, stride=1).px, APP_OUTPUT_DIR)
        write_imageset(f"skeleton_{kind}_reach_b", bird_skeleton(kind, reach=True, stride=-1).px, APP_OUTPUT_DIR)
    write_imageset("clipboard", clipboard().px, APP_OUTPUT_DIR)
    for kind in ("dove", "mallard"):
        write_imageset(f"skeleton_{kind}_coat", bird_skeleton(kind, coat=True).px, APP_OUTPUT_DIR)
    write_imageset("scientist_bare", alien("stand", coat=True).px, APP_OUTPUT_DIR)
    write_imageset("alien_angry", alien("stand", angry=True).px, APP_OUTPUT_DIR)
    for pose, suffix in (("stand", ""), ("a", "_a"), ("b", "_b")):
        write_imageset(f"alien_carry{suffix}", alien(pose, angry=True, carry=True).px, APP_OUTPUT_DIR)
    write_imageset("hunter_scratch", hunter("scratch").px, APP_OUTPUT_DIR)
    write_imageset("hunter_aim", hunter("aim").px, APP_OUTPUT_DIR)
    write_imageset("tent", tent().px, APP_OUTPUT_DIR)
    write_imageset("firepit_unlit", firepit_unlit().px, APP_OUTPUT_DIR)
    write_imageset("camp_chair", camp_chair().px, APP_OUTPUT_DIR)
    write_imageset("folding_table", folding_table().px, APP_OUTPUT_DIR)
    write_imageset("backpack", backpack().px, APP_OUTPUT_DIR)
    write_imageset("cooler", cooler().px, APP_OUTPUT_DIR)
    for pose, suffix in (("stand", ""), ("a", "_walk_a"), ("b", "_walk_b")):
        write_imageset(f"scientist{suffix}", alien(pose, coat=True, clipboard=True).px, APP_OUTPUT_DIR)
        write_imageset(f"scientist_scared{suffix}", alien(pose, coat=True, scared=True).px, APP_OUTPUT_DIR)
    write_imageset("ufo_a", ufo(0).px, APP_OUTPUT_DIR)
    write_imageset("ufo_b", ufo(1).px, APP_OUTPUT_DIR)
    write_imageset("beam_ring", beam_ring().px, APP_OUTPUT_DIR)
    write_imageset("prop_dirt_path", dirt_path().px, APP_OUTPUT_DIR)
    write_imageset("padlock_glow", padlock(glow=True).px, APP_OUTPUT_DIR)
    write_imageset("alien_logo", alien_logo().px, APP_OUTPUT_DIR)
    write_imageset("sign_post", sign_post().px, APP_OUTPUT_DIR)
    write_imageset("rv", rv().px, APP_OUTPUT_DIR)
    write_imageset("campfire_a", campfire(0).px, APP_OUTPUT_DIR)
    write_imageset("campfire_b", campfire(1).px, APP_OUTPUT_DIR)
    write_imageset("camper_dad", camper().px, APP_OUTPUT_DIR)
    write_imageset("camper_kid", camper(kid=True).px, APP_OUTPUT_DIR)
    write_imageset("arrow_right", arrow_right().px, APP_OUTPUT_DIR)
    write_imageset("arrow_down", arrow_down().px, APP_OUTPUT_DIR)
    write_imageset("crate_icon", crate_icon().px, APP_OUTPUT_DIR)
    for pose, name in (("stand", "fisherman"), ("shocked", "fisherman_shocked"), ("a", "fisherman_run_a"), ("b", "fisherman_run_b")):
        write_imageset(name, fisherman(pose).px, APP_OUTPUT_DIR)
    for pose, name in (("sit", "dog_sit"), ("stand", "dog_stand"), ("a", "dog_run_a"), ("b", "dog_run_b")):
        write_imageset(name, dog(pose).px, APP_OUTPUT_DIR)
    write_app_icon()

    print(f"Pixel art written to {WIDGET_OUTPUT_DIR} and {APP_OUTPUT_DIR}")


if __name__ == "__main__":
    sys.exit(main())
