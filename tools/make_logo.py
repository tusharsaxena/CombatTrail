#!/usr/bin/env python3
"""tools/make_logo.py — draws the Combat Trail logo (layout-§4).

A dark square holding a gold trail: three icon tiles in a row that fade toward the left, the way the
lanes scroll a cast away from the "now" edge, and the "now" line at the right. Run from the repo root:

    python3 tools/make_logo.py

It writes the editable source media/logos/combattrail.logo.png (512x512, never shipped, .pkgmeta
ignores it) and the shipped media/logos/combattrail.logo.128.tga (128x128, uncompressed 32-bit,
bottom-left origin: the TOC IconTexture, the minimap button and the broker icon). Needs Pillow.
Deterministic: the same script draws the same bytes.
"""

import os
import struct

from PIL import Image, ImageDraw

SIZE = 512
BG = (16, 16, 22, 255)
EDGE = (60, 60, 70, 255)
GOLD = (255, 209, 0)
TILE_DARK = (34, 30, 18)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "media", "logos")


def lerp(a, b, t):
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def draw():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([8, 8, SIZE - 9, SIZE - 9], radius=72, fill=BG, outline=EDGE, width=6)

    # The trail: three tiles, newest at the right, each older one dimmer (blended toward the
    # background rather than made transparent, so the 128 px icon stays opaque).
    tile, gap, top = 112, 26, 200
    right = SIZE - 80
    strengths = (1.0, 0.55, 0.25)
    for i, strength in enumerate(strengths):
        x1 = right - i * (tile + gap)
        x0 = x1 - tile
        rim = lerp(BG[:3], GOLD, strength)
        fill = lerp(BG[:3], TILE_DARK, strength)
        d.rounded_rectangle([x0, top, x1, top + tile], radius=14, fill=fill + (255,), outline=rim + (255,),
                            width=10)
        # The icon's mark: a small diamond, the cast it stands for.
        cx, cy, r = (x0 + x1) // 2, top + tile // 2, 26
        d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=rim + (255,))

    # The "now" line at the right edge of the newest tile.
    nx = right + 22
    d.rectangle([nx, top - 34, nx + 8, top + tile + 34], fill=GOLD + (255,))
    # The GCD ticks under the trail.
    for i in range(3):
        tx = right - i * (tile + gap) - tile // 2
        d.rectangle([tx - 3, top + tile + 30, tx + 3, top + tile + 54], fill=lerp(BG[:3], GOLD, 0.45) + (255,))
    return img


def write_tga(img, path):
    """Uncompressed 32-bit BGRA, bottom-left origin, 8 alpha bits (descriptor 0x08)."""
    w, h = img.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    px = img.load()
    rows = []
    for y in range(h - 1, -1, -1):
        row = bytearray()
        for x in range(w):
            r, g, b, a = px[x, y]
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    with open(path, "wb") as fh:
        fh.write(header)
        fh.write(b"".join(rows))


def main():
    os.makedirs(OUT, exist_ok=True)
    big = draw()
    big.save(os.path.join(OUT, "combattrail.logo.png"), optimize=True)
    small = big.resize((128, 128), Image.LANCZOS)
    write_tga(small, os.path.join(OUT, "combattrail.logo.128.tga"))


if __name__ == "__main__":
    main()
