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
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

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
    heading = options.pop("heading")
    eye = options.pop("eye")
    target = options.pop("target")
    return render(size, boxes, (0.0, -2.0), heading, eye, target, count=count, seed=seed, **options)


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
    boxes = corridor_scene(red_at=(3.4, -92), friends=[(-6.8, -45), (-6.8, -48.5)])
    img = vignette(fp((1920, 1080), boxes, seed=3), 0.8)
    img.save(path)


def scan_view(path):
    """Thumbnail 2: the sweep mid-pass, half the room drawn, half still black."""
    size = (1920, 1080)
    boxes, scanner = maze(LEVEL)
    img = render(
        size, boxes, scanner, heading=np.radians(8), eye=(100, 108, 142), target=(90, 0, 28),
        fov=54, count=1_400_000, rings=170, max_range=130, wedge=80, seed=4, dot=1.25,
    )
    img = vignette(img, 0.7)
    img = dot_text(img, "LIDAR", (110, 120), 200, pitch=11)
    plain_text(img, "YOU CAN ONLY SEE WHAT YOU SCAN", (118, 345), 34, (226, 232, 245), bold=True, spacing=3)
    legend(img, 118, 420, 26, [(WHITE, "TERRAIN"), (GREEN, "FRIEND"), (RED, "DANGER")])
    img.save(path)


def aura(path):
    """Thumbnail 3: the screen edge glowing red, a few red dots round a corner."""
    boxes = corridor_scene(red_at=(5.4, -36), exit_door=False, extras=[Box(2.5, 5.5, -33, 1.2, 11, 6)])
    img = fp((1920, 1080), boxes, seed=8, lines=(-30, -14, 2, 18, 34), first_person_cone=(10.0, -3.0, 26.0))
    img = tint_edges(vignette(img, 0.85), (255, 40, 40), 0.5, 0.5)
    img = caption(img, "SOMETHING IS NEAR.", "THE EDGES GO RED BEFORE YOU SEE IT", color=(255, 120, 120))
    img.save(path)


def together(path):
    """Thumbnail 4: friends' green dots in a flooded hall, water in blue."""
    boxes = corridor_scene(
        friends=[(-5.5, -26), (3.0, -38), (-1.5, -56)], exit_door=False
    )
    img = fp(
        (1920, 1080), boxes, seed=12, floor_tint=(0.2, 0.52, 1.0), lines=(-44, -30, -16, -4, 8, 20, 34),
        first_person_cone=(0.0, -4.0, 34.0), line_level=0.7,
    )
    img = vignette(img, 0.8)
    img = dot_text(img, "SCAN TOGETHER", (960, 70), 112, pitch=8, anchor="ma")
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


def reveal(path):
    """Thumbnail 6: a hidden object lights its surroundings once it has been scanned enough."""
    spot = (-3.0, 3.4, -34.0)
    boxes = corridor_scene(
        exit_door=False,
        extras=[
            Box(-3.0, 1.2, -34.0, 3.0, 2.4, 3.0),
            Box(-3.0, 3.1, -34.0, 1.4, 1.2, 1.4, "gold"),
            Box(-3.0, 3.9, -34.0, 0.5, 0.6, 0.5, "gold"),
        ],
    )
    img = fp(
        (1920, 1080), boxes, seed=16, lamps=[(spot, 17.0)], lines=(-20, -8, 4, 16),
        first_person_cone=(-6.0, -4.0, 18.0), line_level=0.4,
    )
    img = caption(vignette(img, 0.88), "SCAN IT UNTIL IT SPEAKS.", "HIDDEN OBJECTS WAKE THE ROOM AROUND THEM", color=(255, 214, 140))
    img.save(path)


def variety_panel(kind, seed):
    size = (384, 1080)
    half = 9
    t = 1.0
    boxes = [
        Box(-half - t / 2, 5.5, -60, t, 11, 120),
        Box(half + t / 2, 5.5, -60, t, 11, 120),
        Box(0, 11 + t / 2, -60, 2 * half + 2 * t, t, 120),
        Box(0, 5.5, -120.5, 2 * half, 11, t),
    ]
    rng = np.random.default_rng(seed)
    opts = dict(floor_tint=(0.82, 0.86, 0.95))
    if kind == "OFFICE":
        for i in range(6):
            z = -16 - i * 15
            boxes += [Box(-6, 2.5, z, 5, 5, 2.4), Box(6, 2.5, z - 7, 5, 5, 2.4), Box(0, 10, z, 18, 0.8, 0.8)]
    elif kind == "FLOODED WING":
        boxes.append(Box(0, 0.25, -60, 18, 0.5, 120))
        for i in range(5):
            boxes.append(Box(rng.choice([-6.5, 6.5]), 5.5, -18 - i * 20, 1.6, 11, 1.6))
        opts = dict(floor_tint=(0.2, 0.5, 1.0))
    elif kind == "WARD":
        for i in range(6):
            z = -14 - i * 16
            boxes += [Box(-7, 1.4, z, 3.6, 2.8, 7.2), Box(7, 1.4, z - 6, 3.6, 2.8, 7.2), Box(0, 8, z - 4, 0.3, 6, 0.3)]
    elif kind == "CAVE":
        for i in range(22):
            boxes.append(Box(rng.uniform(-7.5, 7.5), rng.uniform(0.5, 10), -rng.uniform(10, 110), rng.uniform(1.5, 4), rng.uniform(3, 9), rng.uniform(1.5, 4)))
        opts = dict(wall_tint=(0.82, 0.78, 0.7), floor_tint=(0.85, 0.8, 0.7))
    elif kind == "GARAGE":
        for i in range(7):
            z = -12 - i * 16
            boxes += [Box(-7.5, 5.5, z, 1.8, 11, 1.8), Box(7.5, 5.5, z, 1.8, 11, 1.8)]
            if i % 2 == 0:
                boxes.append(Box(-3.2, 1.3, z - 6, 3.4, 2.6, 7.5))
    return fp(
        size, boxes, seed, count=420_000, first_person=(20, 52), lines=(-12, -5, 2, 9, 16),
        first_person_cone=(0.0, -3.0, 26.0), fov=78, eye=(1.2, 6.0, 3.0), dot=0.9, **opts,
    )


def variety(path):
    """Thumbnail 7: one panel each of office, flooded wing, ward, cave and garage."""
    names = ["OFFICE", "FLOODED WING", "WARD", "CAVE", "GARAGE"]
    sheet = Image.new("RGB", (1920, 1080), (2, 3, 5))
    for index, name in enumerate(names):
        panel = vignette(variety_panel(name, 30 + index), 0.9)
        sheet.paste(panel, (index * 384, 0))
        plain_text(sheet, name, (index * 384 + 192, 1030), 28, (226, 232, 245), anchor="ma", bold=True, spacing=4)
    draw = ImageDraw.Draw(sheet)
    for index in range(1, 5):
        draw.line((index * 384, 40, index * 384, 1040), fill=(40, 46, 58), width=2)
    sheet.save(path)


def icon(path, side):
    """The icon: one corridor of white dots vanishing to a point, one small red cluster far
    down it. High contrast and one focal point so it survives at 150x150."""
    boxes = corridor_scene(red_at=(1.0, -104), exit_door=False)
    boxes += figure(-0.5, -108, 6.5, "red", 0.9)
    img = fp(
        (side, side), boxes, seed=5, count=800_000 if side >= 1024 else 500_000,
        eye=(0.0, 5.4, 2.0), target=(0.0, 5.0, -80.0), fov=70, first_person=(46, 46),
        first_person_cone=(0.0, 0.0, 18.0), lines=(-32, -18, -7, 7, 18, 32), dot=side / 640.0 * 1.15,
        line_level=0.5,
    )
    img = vignette(img, 0.9)
    img.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = {
        "icon": lambda: (icon(os.path.join(OUT, "icon-512.png"), 512), icon(os.path.join(OUT, "icon-1024.png"), 1024)),
        "hero": lambda: hero(os.path.join(OUT, "thumbnail-1-hero.png")),
        "scan": lambda: scan_view(os.path.join(OUT, "thumbnail-2-scan.png")),
        "aura": lambda: aura(os.path.join(OUT, "thumbnail-3-aura.png")),
        "together": lambda: together(os.path.join(OUT, "thumbnail-4-together.png")),
        "camp": lambda: camp(os.path.join(OUT, "thumbnail-5-camp.png")),
        "reveal": lambda: reveal(os.path.join(OUT, "thumbnail-6-reveal.png")),
        "variety": lambda: variety(os.path.join(OUT, "thumbnail-7-variety.png")),
    }
    which = sys.argv[1:] or list(jobs)
    for name in which:
        print("rendering", name, flush=True)
        jobs[name]()


if __name__ == "__main__":
    main()
