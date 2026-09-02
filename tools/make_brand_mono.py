# -*- coding: utf-8 -*-
"""Convert brand PNG logos → mono silhouettes (black + alpha), same geometry.

Does NOT redraw logos. Output: assets/brands_mono/<same name>.png
Safe to delete the folder and re-run.

Usage:
  python tools/make_brand_mono.py
  python tools/make_brand_mono.py --preview   # also write tools/_brand_mono_preview.png
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "brands"
DST = ROOT / "assets" / "brands_mono"
PREVIEW = ROOT / "tools" / "_brand_mono_preview.png"

# Brands from the current board + a few common — shown on contact sheet
PREVIEW_SLUGS = [
    "bmw",
    "geely",
    "tank",
    "haval",
    "omoda",
    "mazda",
    "chery",
    "exeed",
    "volkswagen",
    "lexus",
    "kia",
    "skoda",
    "toyota",
    "audi",
    "mercedes",
    "hongqi",
    "changan",
    "zeekr",
]


def knock_background(im: Image.Image, white_thr: int = 236) -> Image.Image:
    """Make near-white / near-gray page background transparent."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            mx, mn = max(r, g, b), min(r, g, b)
            # near-white
            if r >= white_thr and g >= white_thr and b >= white_thr:
                px[x, y] = (0, 0, 0, 0)
                continue
            # light gray / desaturated paper
            if mn >= white_thr - 28 and (mx - mn) <= 18 and (r + g + b) >= (white_thr - 20) * 3:
                px[x, y] = (0, 0, 0, 0)
    return im


def to_mono_mask(im: Image.Image) -> Image.Image:
    """Keep shape; ink → black with alpha from darkness/saturation/original alpha."""
    im = knock_background(im)
    # Slight blur on alpha helps thin chrome lines survive thresholding
    r, g, b, a = im.split()
    a_soft = a.filter(ImageFilter.MaxFilter(3))
    im = Image.merge("RGBA", (r, g, b, a_soft))

    px = im.load()
    w, h = im.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    opx = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 12:
                continue
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            sat = max(r, g, b) - min(r, g, b)
            # Logo ink: dark OR chromatic (red Haval, blue BMW, etc.)
            ink = max(255.0 - lum, sat * 1.15)
            # Soften very light leftover pixels
            if ink < 28 and a < 80:
                continue
            strength = max(ink, a * 0.85)
            na = int(max(0, min(255, strength * (a / 255.0) * 1.15)))
            if na < 18:
                continue
            opx[x, y] = (0, 0, 0, na)
    return out


def trim_and_pad(im: Image.Image, max_side: int = 384, pad_frac: float = 0.06) -> Image.Image:
    bbox = im.getbbox()
    if not bbox:
        return im
    im = im.crop(bbox)
    pad = max(2, int(max(im.size) * pad_frac))
    canvas = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    canvas.paste(im, (pad, pad), im)
    mw = max(canvas.size)
    if mw > max_side:
        ratio = max_side / mw
        canvas = canvas.resize(
            (max(1, int(canvas.width * ratio)), max(1, int(canvas.height * ratio))),
            Image.Resampling.LANCZOS,
        )
    return canvas


def convert_one(src: Path, dst: Path) -> bool:
    try:
        im = Image.open(src)
        mono = to_mono_mask(im)
        if mono.getbbox() is None:
            print("empty", src.name)
            return False
        mono = trim_and_pad(mono)
        dst.parent.mkdir(parents=True, exist_ok=True)
        mono.save(dst, optimize=True)
        return True
    except Exception as e:
        print("fail", src.name, e)
        return False


def write_preview(slugs: list[str]) -> None:
    cell = 120
    cols = 6
    rows = math.ceil(len(slugs) / cols)
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (22, 24, 30, 255))
    draw = ImageDraw.Draw(sheet)
    for i, slug in enumerate(slugs):
        # prefer mono; fall back to color for missing
        mono = DST / f"{slug}.png"
        color = SRC / f"{slug}.png"
        path = mono if mono.exists() else color
        x = (i % cols) * cell
        y = (i // cols) * cell
        draw.rounded_rectangle(
            (x + 6, y + 6, x + cell - 6, y + cell - 22),
            radius=10,
            fill=(14, 16, 22, 255),
            outline=(55, 58, 70, 255),
        )
        draw.text((x + 10, y + cell - 18), slug[:14], fill=(180, 185, 200, 255))
        if not path.exists():
            continue
        im = Image.open(path).convert("RGBA")
        # tint white for preview (simulate ColorFilter srcIn)
        px = im.load()
        for yy in range(im.height):
            for xx in range(im.width):
                r, g, b, a = px[xx, yy]
                if a:
                    px[xx, yy] = (236, 238, 244, a)
        im.thumbnail((cell - 28, cell - 40), Image.Resampling.LANCZOS)
        px0 = x + (cell - im.width) // 2
        py0 = y + 10 + (cell - 36 - im.height) // 2
        sheet.paste(im, (px0, py0), im)
    sheet.convert("RGB").save(PREVIEW, quality=92)
    print("preview", PREVIEW)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--only", nargs="*", help="Only these stems (without .png)")
    args = ap.parse_args()

    DST.mkdir(parents=True, exist_ok=True)
    files = sorted(SRC.glob("*.png"))
    if args.only:
        want = {s.lower().removesuffix(".png") for s in args.only}
        files = [f for f in files if f.stem.lower() in want]

    ok = 0
    for src in files:
        dst = DST / src.name
        if convert_one(src, dst):
            ok += 1
    print(f"converted {ok}/{len(files)} -> {DST}")

    if args.preview:
        # ensure preview slugs converted even if --only
        for s in PREVIEW_SLUGS:
            src = SRC / f"{s}.png"
            if src.exists():
                convert_one(src, DST / f"{s}.png")
        write_preview(PREVIEW_SLUGS)


if __name__ == "__main__":
    main()
