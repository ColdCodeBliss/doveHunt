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

# Native art resolution of the companion app's home screen background.
# Keep in sync with `AppArt` in doveHunt/AppPixelArt.swift.
APP_BACKGROUND_SIZE = (90, 196)

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

    phase = rng.uniform(0, 6.28)
    for x in range(w):
        top = gy - 5 - 3 * (0.6 * math.sin(x * 0.08 + phase) + 0.4 * math.sin(x * 0.21 + phase * 2))
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


def hunter():
    """Vintage hunter in a blaze-orange cap and red plaid jacket, shotgun angled at the sky."""
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

    # Boots (toes point right, the way he faces).
    for x0 in (6, 12):
        for y in range(41, 45):
            for x in range(x0, x0 + 5 + (1 if y >= 43 else 0)):
                put(x, y, boot_dark if y == 44 else boot)

    # Legs with a gap between them.
    for x0 in (7, 12):
        for y in range(30, 41):
            for x in range(x0, x0 + 4):
                put(x, y, pants_shade if x == x0 + 3 else pants)

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

    # Rear arm (behind the gun) from shoulder down to the grip.
    def sleeve(x0, y0, x1, y1):
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for i in range(steps + 1):
            t = i / steps
            x, y = round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t)
            put(x, y, plaid_at(x, y))
            put(x, y + 1, plaid_at(x, y + 1))
            put(x, y + 2, plaid_dark)

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

    w, h = APP_BACKGROUND_SIZE
    write_imageset("app_background", app_background(w, h, random.Random("app-background")).px, APP_OUTPUT_DIR)
    write_imageset("hunter", hunter().px, APP_OUTPUT_DIR)
    write_app_icon()

    print(f"Pixel art written to {WIDGET_OUTPUT_DIR} and {APP_OUTPUT_DIR}")


if __name__ == "__main__":
    sys.exit(main())
