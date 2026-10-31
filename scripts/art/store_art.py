#!/usr/bin/env python3
"""Renders the Roblox store art (icon and thumbnails) for LIDAR.

Everything is drawn the way the game draws: a scanner fires rays into a dark set, and only the
points it hits are shown. White dots are terrain, green are friends, red are threats, gold is
the way out. Nothing is hand-painted, so the art stays on-brand and can be re-rendered.

    python3 scripts/art/store_art.py            # writes PNGs into docs/store/

Needs numpy and Pillow. Output sizes follow Roblox's upload rules: icon 512x512 (also
written at 1024), thumbnails 1920x1080 (16:9).
"""

import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "store")

WHITE = np.array([226, 232, 245], dtype=np.float32)
GREEN = np.array([96, 240, 140], dtype=np.float32)
RED = np.array([255, 84, 84], dtype=np.float32)
GOLD = np.array([255, 214, 110], dtype=np.float32)
COLORS = {"wall": WHITE, "green": GREEN, "red": RED, "gold": GOLD}

FONT_BOLD = "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Bold.ttf"
FONT_REG = "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Regular.ttf"


class Box:
    def __init__(self, cx, cy, cz, sx, sy, sz, kind="wall"):
        self.lo = np.array([cx - sx / 2, cy - sy / 2, cz - sz / 2], dtype=np.float32)
        self.hi = np.array([cx + sx / 2, cy + sy / 2, cz + sz / 2], dtype=np.float32)
        self.kind = kind


PROJECTION = {}
KINDS = ["wall", "green", "red", "gold"]
CELL = 10.0
WALL_HEIGHT = 9.0


def figure(x, z, height, kind, wide=1.0):
    """A thin humanoid from boxes. The game never shows a monster as a silhouette; a few dots
    on a stretched body is all the picture needs to say 'someone is there'."""
    return [
        Box(x, height * 0.55, z, 1.1 * wide, height * 0.6, 0.7 * wide, kind),
        Box(x, height * 0.93, z, 0.8 * wide, 0.8 * wide, 0.8 * wide, kind),
        Box(x - 0.85 * wide, height * 0.5, z, 0.3, height * 0.55, 0.3, kind),
        Box(x + 0.85 * wide, height * 0.5, z, 0.3, height * 0.55, 0.3, kind),
        Box(x - 0.3 * wide, height * 0.12, z, 0.4, height * 0.24, 0.4, kind),
        Box(x + 0.3 * wide, height * 0.12, z, 0.4, height * 0.24, 0.4, kind),
    ]


def maze(rows):
    """Turns a character map into boxes. # is a wall block, S the scanner, G a friend, R a
    threat, E the exit. Returns (boxes, scanner position, extras)."""
    boxes, scanner = [], None
    for zi, row in enumerate(rows):
        for xi, ch in enumerate(row):
            x, z = (xi + 0.5) * CELL, (zi + 0.5) * CELL
            if ch == "#":
                boxes.append(Box(x, WALL_HEIGHT / 2, z, CELL, WALL_HEIGHT, CELL))
            elif ch == "S":
                scanner = (x, z)
            elif ch == "G":
                boxes += figure(x, z, 3.4, "green")
            elif ch == "g":
                boxes += figure(x, z, 3.4, "green")
            elif ch == "R":
                boxes += figure(x, z, 9.4, "red", 1.15)
            elif ch == "E":
                boxes.append(Box(x, 4.4, z, CELL * 0.7, 8.8, 0.8, "gold"))
                boxes.append(Box(x - 3.2, 4.8, z, 0.9, 9.6, 1.0, "gold"))
                boxes.append(Box(x + 3.2, 4.8, z, 0.9, 9.6, 1.0, "gold"))
    return boxes, scanner


def cast(origin, dirs, boxes, max_range):
    """Nearest hit along each ray: boxes, or the floor (y = 0). Returns t, kind index."""
    inv = 1.0 / np.where(np.abs(dirs) < 1e-6, 1e-6, dirs)
    down = dirs[:, 1] < -1e-4
    t_floor = np.where(down, -origin[1] / np.where(down, dirs[:, 1], -1), np.inf)
    best = np.minimum(t_floor, max_range + 1)
    kind = np.zeros(len(dirs), dtype=np.int8)
    on_floor = best == t_floor
    surface = np.where(on_floor, 0, 0)  # 0 floor, 1 wall-ish (boxes)
    for box in boxes:
        a = (box.lo - origin) * inv
        b = (box.hi - origin) * inv
        near = np.max(np.minimum(a, b), axis=1)
        far = np.min(np.maximum(a, b), axis=1)
        hit = (far >= near) & (near > 0.05) & (near < best)
        best = np.where(hit, near, best)
        kind = np.where(hit, KINDS.index(box.kind), kind)
        surface = np.where(hit, 1, surface)
    return best, kind, surface


def look_at(eye, target, up=(0, 1, 0)):
    eye, target, up = (np.array(v, dtype=np.float64) for v in (eye, target, up))
    forward = target - eye
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, up)
    right /= np.linalg.norm(right)
    true_up = np.cross(right, forward)
    return eye, right, true_up, forward


def dirs_beam(cone, heading):
    """Unit vector of the beam: (yaw offset, pitch offset, width) in degrees from the heading."""
    yaw, pitch = np.radians(cone[0]) + heading, np.radians(cone[1])
    return np.array(
        [np.sin(yaw) * np.cos(pitch) * -1, np.sin(pitch), -np.cos(yaw) * np.cos(pitch)],
        dtype=np.float32,
    )


def render(
    size,
    boxes,
    scanner,
    heading,
    eye,
    target,
    fov=40.0,
    count=520_000,
    rings=120,
    max_range=75.0,
    wedge=75.0,
    seed=1,
    dot=1.0,
    height_of_scanner=4.6,
    background=(2, 3, 5),
    first_person=None,
    first_person_cone=(0.0, 0.0, 22.0),
    lines=(),
    lamps=(),
    floor_tint=(0.72, 0.86, 1.0),
    line_level=0.62,
    wall_tint=(1.0, 1.0, 1.0),
    dot_tint=(1.0, 1.0, 1.0),
):
    """Scans from `scanner` (all round, with a brighter wedge in front for the fresh sweep) and
    draws the hit points from a separate viewer camera, the way the game's dots show through
    walls. Points the scanner never reached stay dark: that darkness is the picture."""
    rng = np.random.default_rng(seed)
    width, height = size
    origin = np.array([scanner[0], height_of_scanner, scanner[1]], dtype=np.float32)

    if first_person:
        # Rays fill the view (random, not ringed: a camera-centred ring pattern is flat).
        half_h, half_v = first_person
        el = np.radians(rng.uniform(-half_v, half_v * 0.8, count))
        az = np.radians(rng.uniform(-half_h, half_h, count))
    else:
        elev = np.radians(np.linspace(-62, 24, rings))
        ring = rng.integers(0, rings, count)
        el = elev[ring] + rng.normal(0, np.radians(0.05), count)
        az = rng.uniform(-np.pi, np.pi, count)
    dirs = np.stack([np.sin(az) * np.cos(el), np.sin(el), -np.cos(az) * np.cos(el)], axis=1)
    # rotate by heading (radians about Y; 0 faces -Z)
    c, s_ = np.cos(heading), np.sin(heading)
    rot = np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]], dtype=np.float32)
    dirs = (dirs @ rot.T).astype(np.float32)
    rel_az = np.degrees(az)  # relative to heading
    in_wedge = np.abs(rel_az) < wedge
    strong = np.zeros(len(dirs), dtype=bool)
    if first_person and lines:
        # Earlier vertical sweeps: thin bright columns whose curved profile shows the shape of
        # the corridor, the way a scan line wraps over floor, wall and ceiling.
        half_h, half_v = first_person
        parts = []
        for line_az in lines:
            n = 26000
            laz = np.radians(line_az + rng.normal(0, 0.12, n))
            lel = np.radians(rng.uniform(-half_v, half_v, n))
            d = np.stack([np.sin(laz) * np.cos(lel), np.sin(lel), -np.cos(laz) * np.cos(lel)], axis=1)
            parts.append(d)
        extra = np.concatenate(parts)
        c, s_ = np.cos(heading), np.sin(heading)
        rot2 = np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]], dtype=np.float32)
        extra = (extra @ rot2.T).astype(np.float32)
        dirs = np.concatenate([dirs, extra])
        in_wedge = np.concatenate([in_wedge, np.ones(len(extra), dtype=bool)])
        az = np.concatenate([az, np.zeros(len(extra))])
        strong = np.concatenate([strong, np.ones(len(extra), dtype=bool)])
    if lamps:
        parts = []
        for pos, radius in lamps:
            n = 90000
            target_pts = np.array(pos, dtype=np.float32) + rng.normal(0, 1, (n, 3)) * radius * 0.55
            d = target_pts - origin
            d /= np.linalg.norm(d, axis=1, keepdims=True)
            parts.append(d.astype(np.float32))
        extra = np.concatenate(parts)
        dirs = np.concatenate([dirs, extra])
        in_wedge = np.concatenate([in_wedge, np.ones(len(extra), dtype=bool)])
        az = np.concatenate([az, np.zeros(len(extra))])
        strong = np.concatenate([strong, np.zeros(len(extra), dtype=bool)])
    # Things of note (friends, threats, the exit) get extra rays aimed at them: the scanner
    # lingers on what matters, and it keeps small figures readable.
    aimed = []
    for box in boxes:
        if box.kind == "wall":
            continue
        centre = (box.lo + box.hi) / 2
        sigma = np.maximum(box.hi - box.lo, 0.5) * 0.55
        n = 6000
        target_pts = centre + rng.normal(0, 1, (n, 3)) * sigma
        d = target_pts - origin
        d /= np.linalg.norm(d, axis=1, keepdims=True)
        aimed.append(d.astype(np.float32))
    if aimed:
        extra = np.concatenate(aimed)
        dirs = np.concatenate([dirs, extra])
        in_wedge = np.concatenate([in_wedge, np.ones(len(extra), dtype=bool)])
        az = np.concatenate([az, np.zeros(len(extra))])
        strong = np.concatenate([strong, np.zeros(len(extra), dtype=bool)])

    t, kind, surface = cast(origin, dirs, boxes, max_range)
    ok = t <= max_range
    pts = origin + dirs * t[:, None]
    heat = np.zeros(len(t), dtype=np.float32)
    for pos, radius in lamps:
        dist = np.linalg.norm(pts - np.array(pos, dtype=np.float32), axis=1)
        heat = np.maximum(heat, np.clip(1.0 - dist / radius, 0.0, 1.0))
    # The wedge in front is the fresh scan (kept in full); behind it only older, patchier dots.
    keep = np.where(in_wedge, 1.0, 0.22)
    if first_person:
        # Near surfaces sparse, far ones dense: the far end of a corridor fills in and glows.
        beam = dirs_beam(first_person_cone, heading)
        off = np.degrees(np.arccos(np.clip(dirs @ beam, -1, 1)))
        cone = first_person_cone[2]
        keep = np.clip((t / 70.0) ** 0.75, 0.035, 1.0) * 0.34
        keep = keep * (0.05 + np.exp(-((off / cone) ** 2)))
        in_wedge = off < cone * 1.1
        keep = np.where(strong, np.clip((t / 40.0) ** 0.5, 0.25, 1.0), keep)
    if not first_person:
        keep = np.where((surface == 1) & (kind == 0), keep * 0.32, keep)
    # Fewer dots close in, where the rings crowd together; the far floor keeps its rows.
    if not first_person:
        keep = np.where(surface == 0, keep * np.clip((t / 22.0) ** 0.9, 0.12, 1.0), keep)
    keep = np.where(kind > 0, 0.4 if first_person else 1.0, keep)
    keep = np.where(heat > 0, np.maximum(keep, 0.15 + 0.85 * heat), keep)
    ok &= rng.uniform(0, 1, len(t)) < keep
    pts, t, kind, surface, in_wedge, strong, heat = (
        a[ok] for a in (pts, t, kind, surface, in_wedge, strong, heat)
    )

    # Viewer camera.
    veye, right, up, forward = look_at(eye, target)
    f = 0.5 * height / np.tan(np.radians(fov) / 2)

    def project_point(point):
        rel_p = np.array(point, dtype=np.float64) - veye
        zz = rel_p @ forward
        return (width / 2 + f * (rel_p @ right) / zz, height / 2 - f * (rel_p @ up) / zz)

    PROJECTION["fn"] = project_point
    rel = pts - veye
    x = rel @ right
    y = rel @ up
    z = rel @ forward
    vis = z > 1
    px = width / 2 + f * x[vis] / z[vis]
    py = height / 2 - f * y[vis] / z[vis]
    z = z[vis]
    kind, surface, t, in_wedge, strong, heat = (
        a[vis] for a in (kind, surface, t, in_wedge, strong, heat)
    )
    inside = (px > -3) & (px < width + 3) & (py > -3) & (py < height + 3)
    px, py, z, kind, surface, t, in_wedge, strong, heat = (
        a[inside] for a in (px, py, z, kind, surface, t, in_wedge, strong, heat)
    )

    palette = np.stack([WHITE, GREEN, RED, GOLD])
    colors = palette[kind].copy()
    falloff = np.clip(1.0 - t / (max_range * 1.05), 0.0, 1.0) ** 1.1
    bright = np.where(surface == 1, 0.5 + 0.7 * falloff, 0.12 + 0.72 * falloff)
    bright = np.where(kind > 0, 1.0 + 0.5 * falloff, bright)  # things of note burn brighter
    bright = np.where(in_wedge, bright, bright * 0.6)
    bright = np.where(strong, np.maximum(bright, line_level), bright)
    bright = np.where(heat > 0, np.maximum(bright, 0.35 + 0.9 * heat), bright)
    bright = np.where(kind > 0, np.minimum(bright, 1.15), bright)
    # Floor dots lean blue, walls white, so planes read apart.
    cool = np.where((surface == 0) & (kind == 0), 1, 0)[:, None]
    colors = np.where(cool == 1, colors * np.array(floor_tint, dtype=np.float32), colors)
    colors = np.where((cool == 0) & ((kind == 0)[:, None]), colors * np.array(wall_tint, dtype=np.float32), colors)
    colors = np.where((kind == 0)[:, None], colors * np.array(dot_tint, dtype=np.float32), colors)
    warm = np.array([255, 176, 84], dtype=np.float32)
    mix = np.clip(heat * 1.4, 0, 1)[:, None]
    colors = np.where((kind == 0)[:, None], colors * (1 - mix) + warm * mix, colors)
    radius = np.clip(dot * (0.5 + 62.0 / (z + 28.0) * 0.5), 0.7, 3.1 * dot)

    scale = 2
    dots = np.zeros((height * scale, width * scale, 3), dtype=np.float32)
    cs_all = colors * bright[:, None]
    for r in np.unique(np.round(radius * 3) / 3):
        sel = np.round(radius * 3) / 3 == r
        rr = max(int(np.ceil(r * scale)), 1)
        yy, xx = np.mgrid[-rr : rr + 1, -rr : rr + 1]
        disc = np.clip(1.0 - np.sqrt(xx**2 + yy**2) / (r * scale + 0.6), 0, 1) ** 0.7
        xs = np.round(px[sel] * scale).astype(int)
        ys = np.round(py[sel] * scale).astype(int)
        cs = cs_all[sel]
        for dy in range(-rr, rr + 1):
            for dx in range(-rr, rr + 1):
                w = disc[dy + rr, dx + rr]
                if w <= 0:
                    continue
                x2, y2 = xs + dx, ys + dy
                m = (x2 >= 0) & (x2 < width * scale) & (y2 >= 0) & (y2 < height * scale)
                np.maximum.at(dots, (y2[m], x2[m]), cs[m] * w)
    img = Image.fromarray(np.clip(dots, 0, 255).astype(np.uint8)).resize(
        (width, height), Image.LANCZOS
    )
    glow = img.filter(ImageFilter.GaussianBlur(radius=max(width, height) / 400))
    glow2 = img.filter(ImageFilter.GaussianBlur(radius=max(width, height) / 90))
    base = np.asarray(Image.new("RGB", (width, height), background), dtype=np.float32)
    out = base + np.asarray(img, dtype=np.float32)
    out += np.asarray(glow, dtype=np.float32) * 0.8
    out += np.asarray(glow2, dtype=np.float32) * 0.9
    # Soft highlight roll-off, so the crowded dots near the scanner glow instead of clipping.
    peak = np.maximum(out.max(axis=2, keepdims=True), 1e-3)
    out = out / peak * (255.0 * (1.0 - np.exp(-peak / 150.0)) * 1.04)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def vignette(img, strength=0.78):
    width, height = img.size
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    d = np.sqrt(((xx - width / 2) / (width / 2)) ** 2 + ((yy - height / 2) / (height / 2)) ** 2)
    mask = 1.0 - strength * np.clip(d - 0.35, 0, 1) ** 1.6
    arr = np.asarray(img, dtype=np.float32) * mask[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def dot_text(img, text, xy, size, color=(226, 232, 245), pitch=None, anchor="la", alpha=1.0):
    """Writes text as a grid of round dots, like letters being scanned out of the dark."""
    font = ImageFont.truetype(FONT_BOLD, size)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text(xy, text, font=font, fill=255, anchor=anchor)
    pitch = pitch or max(size // 14, 3)
    arr = np.asarray(mask)
    layer = Image.new("RGB", img.size, (0, 0, 0))
    draw = ImageDraw.Draw(layer)
    r = pitch * 0.36
    rng = np.random.default_rng(7)
    ys, xs = np.nonzero(arr[::pitch, ::pitch] > 128)
    for yi, xi in zip(ys, xs):
        x, y = xi * pitch + pitch / 2, yi * pitch + pitch / 2
        j = rng.uniform(0.82, 1.0)
        c = tuple(int(v * j * alpha) for v in color)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=c)
    glow = layer.filter(ImageFilter.GaussianBlur(radius=pitch * 0.9))
    out = np.asarray(img, dtype=np.float32) + np.asarray(layer, dtype=np.float32)
    out += np.asarray(glow, dtype=np.float32) * 0.8
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def plain_text(img, text, xy, size, color=(132, 142, 158), anchor="la", bold=False, spacing=0):
    font = ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size)
    draw = ImageDraw.Draw(img)
    if spacing:
        x, y = xy
        total = sum(font.getlength(ch) + spacing for ch in text) - spacing
        if anchor[0] == "m":
            x -= total / 2
        elif anchor[0] == "r":
            x -= total
        for ch in text:
            draw.text((x, y), ch, font=font, fill=color, anchor="l" + anchor[1])
            x += font.getlength(ch) + spacing
    else:
        draw.text(xy, text, font=font, fill=color, anchor=anchor)
    return img


def legend(img, x, y, size, entries):
    """Coloured dot + word, one per entry, left to right."""
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT_BOLD, size)
    for color, word in entries:
        r = size * 0.32
        draw.ellipse((x, y - r, x + 2 * r, y + r), fill=tuple(int(v) for v in color))
        x += 2 * r + size * 0.55
        draw.text((x, y), word, font=font, fill=(200, 206, 220), anchor="lm")
        x += font.getlength(word) + size * 1.4
    return img



def corridor_scene(length=130, half=9, height=11, red_at=None, friends=(), extras=(), exit_door=True):
    """A long first-person corridor: side walls, ceiling, pillars, an arch, a crate, the exit
    at the far end, with optional red and green figures (x, z)."""
    t = 1.0
    boxes = [
        Box(-half - t / 2, height / 2, -length / 2, t, height, length),
        Box(half + t / 2, height / 2, -length / 2, t, height, length),
        Box(0, height + t / 2, -length / 2, half * 2 + 2 * t, t, length),
        Box(0, height / 2, -length - t / 2, half * 2, height, t),
    ]
    for index in range(1, 6):
        z = -10 - index * 20
        boxes.append(Box(-half + 3, height / 2, z, 2, height, 2))
        boxes.append(Box(half - 3, height / 2, z - 10, 2, height, 2))
    boxes.append(Box(0, height - 1, -50, half * 2, 2, 1.6))
    boxes.append(Box(half - 2.5, 1.5, -26, 3, 3, 3))
    boxes.append(Box(half - 2.8, 4.1, -26.4, 2.2, 2.2, 2.2))
    boxes.append(Box(-half + 2, 1.2, -70, 3.5, 2.4, 3))
    if exit_door:
        boxes.append(Box(0, 4.2, -length + 0.8, 5, 8.4, 0.5, "gold"))
        boxes.append(Box(-2.9, 4.6, -length + 0.9, 0.8, 9.2, 0.9, "gold"))
        boxes.append(Box(2.9, 4.6, -length + 0.9, 0.8, 9.2, 0.9, "gold"))
    if red_at:
        boxes += figure(red_at[0], red_at[1], 8.6, "red", 1.1)
    for fx, fz in friends:
        boxes += figure(fx, fz, 3.4, "green")
    return boxes + list(extras)


# ----------------------------------------------------------------------------------------
# The pieces

LEVEL = [
    "#########E##########",
    "#..................#",
    "#..##.....R....##..#",
    "#..................#",
    "#.....##......##...#",
    "#..................#",
    "#...##.......##....#",
    "#.....S....G.......#",
    "#..................#",
    "####################",
]
LEVEL = [row.ljust(20, "#")[:20] for row in LEVEL]


# ----------------------------------------------------------------------------------------
# 2D helpers for the graphic pieces (lore wall, looks and upgrades, icons)


def soft_dot_layer(size, items, scale=2):
    """items: (x, y, radius, (r, g, b)). Returns a supersampled-then-reduced RGB float layer of
    round dots, so 2D pieces have the same soft round dots as the scanned ones."""
    width, height = size
    layer = Image.new("RGB", (width * scale, height * scale), (0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for x, y, r, color in items:
        draw.ellipse(
            ((x - r) * scale, (y - r) * scale, (x + r) * scale, (y + r) * scale),
            fill=tuple(int(c) for c in color),
        )
    return layer.resize(size, Image.LANCZOS)


def glow_compose(base, layer, glow=1.0):
    """Adds a dot layer to `base` with the same two-radius glow and highlight roll-off."""
    width, height = base.size
    tight = layer.filter(ImageFilter.GaussianBlur(radius=max(width, height) / 500))
    wide = layer.filter(ImageFilter.GaussianBlur(radius=max(width, height) / 110))
    out = np.asarray(base, dtype=np.float32) + np.asarray(layer, dtype=np.float32)
    out += np.asarray(tight, dtype=np.float32) * 0.8 * glow
    out += np.asarray(wide, dtype=np.float32) * 1.0 * glow
    peak = np.maximum(out.max(axis=2, keepdims=True), 1e-3)
    out = out / peak * (255.0 * (1.0 - np.exp(-peak / 170.0)) * 1.05)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def text_dots(text, xy, size, pitch, anchor="la", lit=None, color=(226, 232, 245), seed=1, bold=True):
    """Dot-matrix text as dot items. `lit` is (x, y, radius): dots near it are bright and full,
    dots far from it are dim and patchy, so text looks half-scanned out of the dark."""
    font = ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size)
    probe = Image.new("L", (1920, 1080), 0)
    ImageDraw.Draw(probe).text(xy, text, font=font, fill=255, anchor=anchor)
    arr = np.asarray(probe)
    rng = np.random.default_rng(seed)
    items = []
    ys, xs = np.nonzero(arr[::pitch, ::pitch] > 128)
    for yi, xi in zip(ys, xs):
        x, y = xi * pitch + pitch / 2, yi * pitch + pitch / 2
        level = 1.0
        if lit is not None:
            d = np.hypot(x - lit[0], y - lit[1]) / lit[2]
            level = float(np.clip(1.25 - d * d, 0.0, 1.0))
            if rng.uniform() > 0.62 + 0.38 * level:
                continue
        shade = (0.45 + 0.55 * level) * rng.uniform(0.85, 1.0)
        items.append((x, y, pitch * 0.34, tuple(c * shade for c in color)))
    return items


BEAT = [(0, 0), (0.08, 0.12), (0.14, 0), (0.22, 0), (0.25, -0.2), (0.3, 1.0), (0.35, -0.5), (0.4, 0), (0.5, 0), (0.6, 0.28), (0.7, 0), (1, 0)]


def ecg(items, y, x0, x1, color, pitch=7, amp=170):
    """A heartbeat trace made of dots: a flat line with two beats, fading out at the ends."""
    xs_shape = [p[0] for p in BEAT]
    ys_shape = [p[1] for p in BEAT]
    beats = [(0.30, 0.2), (0.68, 0.2)]
    for x in np.arange(x0, x1, pitch / 7):
        t = (x - x0) / (x1 - x0)
        v = 0.0
        for start, width in beats:
            u = (t - start) / width
            if 0 <= u <= 1:
                v += float(np.interp(u, xs_shape, ys_shape))
        fade = float(np.clip(1.0 - abs(t - 0.5) * 1.3, 0.2, 1.0))
        items.append((x, y - v * amp, 2.0, tuple(c * fade for c in color)))
    return items


def figure_dots(items, cx, cy, height, color, rng, count=1400, width=0.34):
    """A standing figure as scattered dots (top of head at cy - height). Used on 2D pieces."""
    for _ in range(count):
        part = rng.uniform()
        if part < 0.12:  # head
            ang = rng.uniform(0, 2 * np.pi)
            rad = rng.uniform(0, 1) ** 0.5 * height * 0.075
            x, y = cx + np.cos(ang) * rad, cy - height * 0.93 + np.sin(ang) * rad
        elif part < 0.62:  # torso
            x = cx + rng.uniform(-1, 1) * height * width * 0.5
            y = cy - rng.uniform(0.42, 0.84) * height
        elif part < 0.78:  # arms
            side = rng.choice([-1, 1])
            x = cx + side * height * (width * 0.5 + 0.03 + rng.uniform(0, 0.03))
            y = cy - rng.uniform(0.38, 0.8) * height
        else:  # legs
            side = rng.choice([-1, 1])
            x = cx + side * height * 0.09 + rng.uniform(-0.03, 0.03) * height
            y = cy - rng.uniform(0.0, 0.42) * height
        items.append((x, y, rng.uniform(1.6, 2.6), color))
    return items


# ----------------------------------------------------------------------------------------
# The pieces


def fp(size, boxes, seed, count=1_300_000, **overrides):
    """A first-person scan of a corridor-like set, seen from just behind the scanner so that
    the vertical scan lines wrap over floor, walls and ceiling and show the shape."""
    options = dict(
        heading=0.0,
        eye=(1.6, 6.0, 4.0),
        target=(0.0, 4.2, -60.0),
        fov=80,
        max_range=130,
        wedge=180,
        dot=1.0,
        height_of_scanner=5.0,
        first_person=(78, 56),
        first_person_cone=(6.0, -3.0, 30.0),
        lines=(-44, -30, -18, -8, 2, 12, 24, 38),
    )
    options.update(overrides)
    scanner = options.pop("scanner", (0.0, -2.0))
    heading = options.pop("heading")
    eye = options.pop("eye")
    target = options.pop("target")
    return render(size, boxes, scanner, heading, eye, target, count=count, seed=seed, **options)


def tint_edges(img, color, strength=0.7, start=0.45):
    """A coloured glow creeping in from the screen edges (the red aura of a nearby monster)."""
    width, height = img.size
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    d = np.sqrt(((xx - width / 2) / (width / 2)) ** 2 + ((yy - height / 2) / (height / 2)) ** 2)
    glow = np.clip((d - start) / (1.2 - start), 0, 1) ** 1.8 * strength
    arr = np.asarray(img, dtype=np.float32)
    arr = arr + glow[..., None] * np.array(color, dtype=np.float32)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def caption(img, text, sub=None, y=960, color=(226, 232, 245)):
    plain_text(img, text, (960, y), 54, color, anchor="ma", bold=True, spacing=6)
    if sub:
        plain_text(img, sub, (960, y + 76), 30, (150, 160, 178), anchor="ma", bold=True, spacing=5)
    return img


def hero(path):
    """Thumbnail 1: the search thumbnail. A scanned corridor, something tall waiting at the end
    of it, and a line that makes you want to know what it is."""
    size = (1920, 1080)
    boxes = corridor_scene(
        red_at=(2.2, -40), exit_door=False
    )
    img = fp(
        size, boxes, seed=3, count=1_500_000, lines=(-44, -30, -18, -6, 6, 18, 32, 46),
        first_person_cone=(4.0, -3.0, 26.0), line_level=0.5,
    )
    img = tint_edges(vignette(img, 0.85), (255, 30, 30), 0.28, 0.6)
    img = dot_text(img, "LIDAR", (80, 60), 150, pitch=9, anchor="la")
    plain_text(img, "THE DARK IS FULL.", (960, 905), 76, (226, 232, 245), anchor="ma", bold=True, spacing=8)
    plain_text(img, "YOUR SCANNER IS ALL YOU HAVE.", (960, 1000), 38, (255, 110, 110), anchor="ma", bold=True, spacing=7)
    img.save(path)


def scan_view(path):
    """Thumbnail 2: what you can see, and what is there. A scanned room, and red presences in
    the dark just outside it, felt as auras rather than shown."""
    size = (1920, 1080)
    boxes, scanner = maze(LEVEL)
    haunts = [(150, 25), (35, 55), (165, 80), (115, 85), (45, 25)]
    for hx, hz in haunts:
        boxes += figure(hx, hz, 9.0, "red", 1.15)
    img = render(
        size, boxes, scanner, heading=np.radians(8), eye=(100, 108, 142), target=(95, 0, 28),
        fov=52, count=1_500_000, rings=170, max_range=76, wedge=70, seed=4, dot=1.3,
    )
    project = PROJECTION["fn"]
    glow = Image.new("RGB", size, (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for hx, hz in haunts:
        px, py = project((hx, 4.5, hz))
        for radius, alpha in ((150, 26), (95, 44), (50, 70)):
            gd.ellipse((px - radius, py - radius, px + radius, py + radius), fill=(alpha, 0, 0))
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    arr = np.asarray(img, dtype=np.float32) + np.asarray(glow, dtype=np.float32) * 1.4
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    img = vignette(img, 0.75)
    img = dot_text(img, "YOU ARE NOT ALONE", (110, 90), 120, pitch=8, color=(255, 120, 120))
    plain_text(img, "WHITE IS WALL.  GREEN IS FRIEND.  RED IS WHAT FOUND YOU.", (116, 255), 28, (200, 206, 220), bold=True, spacing=3)
    img.save(path)


def ecg_line(img, y, color=(255, 70, 70), x0=140, x1=1780):
    items = ecg([], y, x0, x1, color)
    return glow_compose(img, soft_dot_layer(img.size, items), 1.1)


def aura(path):
    """Thumbnail 3: the screen edge glowing red, a heartbeat, something behind the wall."""
    boxes = corridor_scene(
        red_at=(5.6, -30), exit_door=False, extras=[Box(2.6, 5.5, -28, 1.2, 11, 6)]
    )
    img = fp(
        (1920, 1080), boxes, seed=8, lines=(-30, -14, 2, 18, 34), first_person_cone=(10.0, -3.0, 26.0),
        eye=(1.2, 6.0, 5.0),
    )
    img = tint_edges(vignette(img, 0.85), (255, 30, 30), 0.62, 0.42)
    img = ecg_line(img, 905)
    img = dot_text(img, "LISTEN.", (960, 55), 150, pitch=9, anchor="ma", color=(255, 100, 100))
    plain_text(img, "THE EDGES GO RED BEFORE YOU SEE IT", (960, 975), 32, (230, 150, 150), anchor="ma", bold=True, spacing=6)
    img.save(path)


def together(path):
    """Thumbnail 4: four scanners, one dark. Each friend's scan is a different green layer over
    the water, and what they find, you find."""
    size = (1920, 1080)
    friends = [(-5.5, -22), (3.4, -34), (-2.0, -48)]
    boxes = corridor_scene(friends=friends, exit_door=False, red_at=(0.5, -105))
    common = dict(
        floor_tint=(0.2, 0.52, 1.0), line_level=0.6, lines=(-40, -24, -9, 6, 21, 36),
        first_person_cone=(0.0, -4.0, 34.0),
    )
    base = fp(size, boxes, seed=12, **common)
    layers = [base]
    for index, (fx, fz) in enumerate(friends):
        layers.append(
            fp(
                size, boxes, seed=40 + index, count=700_000, scanner=(fx, fz - 1.5), dot_tint=(0.35, 1.0, 0.55),
                floor_tint=(0.25, 0.9, 0.55), line_level=0.85, lines=(-20, -8, 4, 16, 28),
                first_person_cone=(float(8 - index * 7), -4.0, 22.0),
            )
        )
    img = layers[0]
    for extra in layers[1:]:
        img = ImageChops.screen(img, extra)
    img = vignette(img, 0.8)
    img = dot_text(img, "SCAN TOGETHER", (960, 40), 112, pitch=8, anchor="ma")
    plain_text(img, "1 TO 4 PLAYERS  /  WHAT THEY FIND, YOU FIND", (960, 960), 36, (140, 240, 170), anchor="ma", bold=True, spacing=6)
    img.save(path)


def camp(path):
    """Thumbnail 5: a lit surveyor camp in the dark, a warm lamp on a dotted room."""
    lamp = (5.0, 3.0, -30.0)
    boxes = corridor_scene(
        exit_door=False,
        extras=[
            Box(5.0, 1.0, -30.0, 5.0, 2.0, 3.0),
            Box(5.0, 2.3, -30.0, 0.7, 0.9, 0.7, "gold"),
            Box(-4.5, 0.5, -26.0, 4.0, 1.0, 7.0),
            Box(-5.0, 0.5, -34.0, 3.4, 1.0, 6.0),
            Box(8.0, 1.3, -33.0, 1.6, 2.6, 1.6),
        ],
    )
    img = fp(
        (1920, 1080), boxes, seed=14, lamps=[(lamp, 15.0)], lines=(-30, -14, 2, 18, 34),
        first_person_cone=(8.0, -4.0, 20.0), wall_tint=(0.85, 0.88, 1.0),
    )
    img = caption(vignette(img, 0.85), "SOME ROOMS ARE LIT.", "FIND THE CAMP. FIND THE CREW.", color=(255, 214, 140))
    img.save(path)


def lore(path):
    """Thumbnail 6: lore. Notes on a dark wall, half scanned out of it, with a tape and a
    redaction: enough to make you wonder who wrote them."""
    size = (1920, 1080)
    base = Image.new("RGB", size, (2, 3, 5))
    rng = np.random.default_rng(6)
    items = []
    beam = (1010, 520, 640)
    # A faint scatter of wall dots, brighter near the beam.
    for _ in range(9000):
        x, y = rng.uniform(0, 1920), rng.uniform(0, 1080)
        d = np.hypot(x - beam[0], y - beam[1]) / 900.0
        if rng.uniform() < np.clip(1.0 - d, 0.02, 1.0) * 0.7:
            items.append((x, y, rng.uniform(0.9, 1.6), tuple(int(v * np.clip(1.1 - d, 0.1, 1)) for v in (120, 130, 150))))
    lit = (beam[0], beam[1], 980)
    notes = [
        ("SURVEY BULLETIN", (260, 230), 40, (226, 232, 245)),
        ("LEVEL 2: THE WARDS", (260, 300), 64, (226, 232, 245)),
        ("DO NOT ANSWER VOICES.", (260, 392), 52, (255, 214, 110)),
        ("SURVEY: 3% MAPPED.", (720, 620), 58, (226, 232, 245)),
        ("EXIT: NOT FOUND.", (720, 696), 58, (255, 110, 110)),
        ("THE BOTTOM IS THE LAMP.", (1130, 270), 42, (226, 232, 245)),
        ("WADE. DO NOT LINGER.", (1130, 344), 42, (150, 190, 255)),
    ]
    for index, (text, xy, size_px, color) in enumerate(notes):
        items += text_dots(text, xy, size_px, max(size_px // 8, 4), lit=lit, color=color, seed=20 + index)
    # A redaction bar over a line, the way a surveyor blacks out a name.
    items += text_dots("UNIT 0041", (260, 490), 44, 6, lit=lit, color=(200, 206, 220), seed=40)
    for gx in range(0, 230, 7):
        for gy in range(0, 34, 7):
            items.append((560 + gx, 492 + gy, 2.3, (210, 216, 228)))
    img = glow_compose(base, soft_dot_layer(size, items))
    # A tape marker: REC dot and a play triangle.
    draw = ImageDraw.Draw(img)
    draw.ellipse((130, 118, 156, 144), fill=(255, 60, 60))
    plain_text(img, "TAPE 03", (176, 131), 30, (230, 150, 150), anchor="lm", bold=True, spacing=4)
    img = vignette(img, 0.85)
    img = dot_text(img, "THE DARK HAS A STORY", (960, 790), 96, pitch=7, anchor="ma")
    plain_text(img, "FIND THE SURVEYORS. FIND THE TAPES. FIND THE WAY OUT.", (960, 960), 30, (200, 206, 220), anchor="ma", bold=True, spacing=4)
    img.save(path)


# The scanner skins in src/shared/data/Skins.luau on claude/skins-monetization (PR #15): a plain
# Classic, four earned by playtime (minutes in the dark), three bought with Robux. Colours are
# each skin's dot colour. Keep in step with that file. The earned skins are drawn muted on
# purpose (quiet, a little greyed) so the premium ones, drawn vivid with a halo, stand out.
LOOKS_EARNED = [
    ("CLASSIC", (196, 200, 210), "DEFAULT"),
    ("TUNGSTEN", (214, 196, 160), "15 MIN"),
    ("GLACIER", (150, 214, 196), "45 MIN"),
    ("ORCHID", (196, 176, 208), "90 MIN"),
    ("BLUEPRINT", (92, 140, 245), "180 MIN"),
]
LOOKS_ROBUX = [
    ("ROSE QUARTZ", (255, 80, 170)),
    ("AURORA", (40, 225, 255)),
    ("NIGHTBLOOM", (105, 70, 255)),
]


def muted(color, amount=0.55, dim=0.62):
    """Pulls a colour towards grey and darkens it: the standard looks stay quiet."""
    grey = sum(color) / 3.0
    return tuple(int((grey + (c - grey) * amount) * dim) for c in color)


def vivid(color, boost=1.35):
    """Pushes a colour away from grey to full strength: the premium looks pop."""
    grey = sum(color) / 3.0
    return tuple(int(np.clip(grey + (c - grey) * boost, 0, 255)) for c in color)


def burst_items(cx, cy, color, rng, radius=118, sparkle=0):
    """A scan burst: rings of dots with a bright core, in a dot colour. `sparkle` adds a
    scatter of large bright dots and an outer halo ring for premium looks."""
    items = []
    for ring, r in enumerate(np.linspace(radius * 0.18, radius, 7)):
        n = int(14 + ring * 11 * radius / 118)
        for k in range(n):
            ang = (k / n) * 2 * np.pi + rng.uniform(-0.03, 0.03)
            fade = 1.0 - ring / 9.0
            items.append((cx + np.cos(ang) * r, cy + np.sin(ang) * r, max(2.4 - ring * 0.12, 1.2), tuple(c * fade for c in color)))
    items.append((cx, cy, 5, color))
    if sparkle:
        for k in range(70):
            ang = rng.uniform(0, 2 * np.pi)
            r = radius * rng.uniform(1.05, 1.5)
            items.append((cx + np.cos(ang) * r, cy + np.sin(ang) * r, rng.uniform(1.6, 3.4), color))
        for k in range(130):
            ang = (k / 130) * 2 * np.pi
            items.append((cx + np.cos(ang) * radius * 1.22, cy + np.sin(ang) * radius * 1.22, 2.2, color))
    return items


def looks(path):
    """Thumbnail 7: make the dark yours. Scanner skins earned by playing, and a few to buy.
    Looks only, never power."""
    size = (1920, 1080)
    base = Image.new("RGB", size, (2, 3, 5))
    rng = np.random.default_rng(9)
    items = []
    row1_y, row2_y = 415, 850
    xs1 = [260 + i * 350 for i in range(5)]
    xs2 = [610 + i * 350 for i in range(3)]
    # a progress line through the earned row, with a bright head at the last unlock
    for x in np.arange(xs1[0], xs1[-1], 9):
        items.append((x, row1_y + 128, 1.6, (70, 78, 96)))
    for (name, color, tag), x in zip(LOOKS_EARNED, xs1):
        quiet = color
        items += burst_items(x, row1_y, quiet, rng, 92)
        if name == "BLUEPRINT":
            # in game only the dots and the gold gun are different; keep the extras small:
            # a faint dashed ring and a gold dot at the centre for the gun
            for k in range(0, 72, 2):
                a = k / 72 * 2 * np.pi
                items.append((x + np.cos(a) * 108, row1_y + np.sin(a) * 108, 1.8, tuple(int(c * 0.7) for c in color)))
            items.append((x, row1_y, 6.5, (205, 165, 70)))
        items.append((x, row1_y + 128, 6, quiet))
    premium = []
    for (name, color), x in zip(LOOKS_ROBUX, xs2):
        premium += burst_items(x, row2_y, color, rng, 92, sparkle=1)
    # standard looks glow softly; premium looks get a stronger glow of their own
    img = glow_compose(base, soft_dot_layer(size, items), 0.55)
    img = glow_compose(img, soft_dot_layer(size, premium), 1.9)
    plain_text(img, "EARNED BY PLAYING", (960, row1_y - 125), 24, (150, 160, 178), anchor="ma", bold=True, spacing=5)
    plain_text(img, "PREMIUM", (960, row2_y - 172), 24, (255, 214, 110), anchor="ma", bold=True, spacing=5)
    for (name, color, tag), x in zip(LOOKS_EARNED, xs1):
        plain_text(img, name, (x, row1_y + 158), 26, color, anchor="ma", bold=True, spacing=4)
        plain_text(img, tag, (x, row1_y + 196), 20, (150, 160, 178) if tag != "DEFAULT" else (96, 240, 140), anchor="ma", bold=True, spacing=3)
    for (name, color), x in zip(LOOKS_ROBUX, xs2):
        plain_text(img, name, (x, row2_y + 148), 30, tuple(int(c + (255 - c) * 0.3) for c in color), anchor="ma", bold=True, spacing=4)
    img = vignette(img, 0.8)
    img = dot_text(img, "MAKE THE DARK YOURS", (960, 60), 110, pitch=8, anchor="ma")
    plain_text(img, "NEW DOT COLOURS AND SCANNER LOOKS. LOOKS ONLY, NEVER POWER.", (960, 215), 30, (200, 206, 220), anchor="ma", bold=True, spacing=4)
    img.save(path)


# ---- icons ----------------------------------------------------------------------------


def icon_corridor(path, side):
    """Icon A: a white dotted corridor with something tall and red looming in it."""
    boxes = corridor_scene(red_at=(1.0, -26), exit_door=False)
    img = fp(
        (side, side), boxes, seed=5, count=900_000 if side >= 1024 else 600_000,
        eye=(0.0, 5.6, 3.0), target=(0.0, 5.0, -60.0), fov=68, first_person=(46, 46),
        first_person_cone=(0.0, 0.0, 18.0), lines=(-34, -20, -8, 8, 20, 34), dot=side / 640.0 * 1.2,
        line_level=0.55,
    )
    img = tint_edges(vignette(img, 0.9), (255, 30, 30), 0.3, 0.6)
    img.save(path)


def icon_radar(path, side):
    """Icon B: a radar-style scan burst, a bright sweep wedge, one red blip and one green."""
    size = (side, side)
    rng = np.random.default_rng(3)
    c = side / 2
    items = []
    k = side / 1024.0
    for ring, r in enumerate(np.linspace(70, 470, 11) * k):
        n = int(26 + ring * 20)
        for j in range(n):
            ang = (j / n) * 2 * np.pi + rng.uniform(-0.02, 0.02)
            # the sweep wedge points up and to the right; rings are brightest there
            diff = abs((ang - (-np.pi / 3) + np.pi) % (2 * np.pi) - np.pi)
            level = 0.22 + 0.78 * np.clip(1 - diff / 1.0, 0, 1)
            fade = (1.0 - ring / 14.0) * level
            items.append((c + np.cos(ang) * r, c + np.sin(ang) * r, (4.2 - ring * 0.2) * k * 1.5, tuple(v * fade for v in (226, 232, 245))))
    # wedge edge line
    for t in np.linspace(40, 480, 90) * k:
        ang = -np.pi / 3
        items.append((c + np.cos(ang) * t, c + np.sin(ang) * t, 4 * k, (226, 232, 245)))
    # blips
    for _ in range(90):
        items.append((c + 190 * k + rng.normal(0, 14 * k), c - 250 * k + rng.normal(0, 22 * k), 5 * k, (255, 84, 84)))
    for _ in range(40):
        items.append((c - 220 * k + rng.normal(0, 10 * k), c + 160 * k + rng.normal(0, 10 * k), 4.5 * k, (96, 240, 140)))
    items.append((c, c, 11 * k, (226, 232, 245)))
    img = glow_compose(Image.new("RGB", size, (2, 3, 5)), soft_dot_layer(size, items))
    img = vignette(img, 0.8)
    img.save(path)


def icon_letter(path, side):
    """Icon C: a big dot-matrix L, the last dot of its foot glowing red."""
    size = (side, side)
    k = side / 1024.0
    pitch = 100 * k
    cols = np.arange(5)
    items = []
    cells = [(0, r) for r in range(7)] + [(c, 6) for c in range(1, 5)]
    ox, oy = (side - 5 * pitch) / 2 + pitch / 2, (side - 7 * pitch) / 2 + pitch / 2
    for cx, cy in cells:
        x, y = ox + cx * pitch, oy + cy * pitch
        red = (cx, cy) == (4, 6)
        color = (255, 70, 70) if red else (226, 232, 245)
        items.append((x, y, pitch * 0.4, color))
    # faint ghost grid so it reads as a dot display
    for gx in range(5):
        for gy in range(7):
            if (gx, gy) not in cells:
                items.append((ox + gx * pitch, oy + gy * pitch, pitch * 0.09, (60, 66, 80)))
    img = glow_compose(Image.new("RGB", size, (2, 3, 5)), soft_dot_layer(size, items))
    img.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    def icons():
        for side in (512, 1024):
            icon_corridor(os.path.join(OUT, f"icon-a-corridor-{side}.png"), side)
            icon_radar(os.path.join(OUT, f"icon-b-radar-{side}.png"), side)
            icon_letter(os.path.join(OUT, f"icon-c-letter-{side}.png"), side)
            # the icon in use is option B (Vasco's pick, 2026-10-31)
            shutil.copyfile(os.path.join(OUT, f"icon-b-radar-{side}.png"), os.path.join(OUT, f"icon-{side}.png"))

    jobs = {
        "icon": icons,
        "hero": lambda: hero(os.path.join(OUT, "thumbnail-1-hero.png")),
        "scan": lambda: scan_view(os.path.join(OUT, "thumbnail-2-scan.png")),
        "aura": lambda: aura(os.path.join(OUT, "thumbnail-3-aura.png")),
        "together": lambda: together(os.path.join(OUT, "thumbnail-4-together.png")),
        "camp": lambda: camp(os.path.join(OUT, "thumbnail-5-camp.png")),
        "lore": lambda: lore(os.path.join(OUT, "thumbnail-6-lore.png")),
        "looks": lambda: looks(os.path.join(OUT, "thumbnail-7-looks.png")),
    }
    which = sys.argv[1:] or list(jobs)
    for name in which:
        print("rendering", name, flush=True)
        jobs[name]()


if __name__ == "__main__":
    main()
