# -*- coding: utf-8 -*-
"""Restore damaged brand PNGs + safer edge flood-fill for dark plates."""
from __future__ import annotations

import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    import subprocess

    subprocess.check_call([sys.executable, "-m", "pip", "install", "pillow", "-q"])
    from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRANDS = ROOT / "assets" / "brands"
UA = "DetAppBrandFix/1.0"
DATASET = "https://raw.githubusercontent.com/filippofilip95/car-logos-dataset/master/logos/optimized"


def log(msg: str) -> None:
    print(msg, flush=True)


def download(url: str, dest: Path, min_size: int = 500) -> bool:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read()
        if len(data) < min_size or data[:8] != b"\x89PNG\r\n\x1a\n":
            return False
        dest.write_bytes(data)
        return True
    except Exception:
        return False


def is_damaged(path: Path) -> bool:
    try:
        if path.stat().st_size < 1500:
            return True
        im = Image.open(path).convert("RGBA")
        w, h = im.size
        if w < 40 or h < 20:
            return True
        # mostly empty after bad knock
        alpha = im.getchannel("A")
        opaque = sum(1 for p in alpha.getdata() if p > 20)
        if opaque < max(80, (w * h) * 0.01):
            return True
        return False
    except Exception:
        return True


def knock_white(im: Image.Image, threshold: int = 242) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
    return im


def flood_knock_dark_edges(im: Image.Image, threshold: int = 36) -> Image.Image:
    """Remove near-black plate by flood-fill from image edges only (keeps dark glyphs)."""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()

    def dark(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        return a > 0 and r <= threshold and g <= threshold and b <= threshold

    # Only run if corners look like a dark plate.
    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    if sum(1 for c in corners if dark(*c)) < 2:
        return im

    stack = [c for c in corners if dark(*c)]
    # also seed along edges
    for x in range(0, w, max(1, w // 40)):
        if dark(x, 0):
            stack.append((x, 0))
        if dark(x, h - 1):
            stack.append((x, h - 1))
    for y in range(0, h, max(1, h // 40)):
        if dark(0, y):
            stack.append((0, y))
        if dark(w - 1, y):
            stack.append((w - 1, y))

    seen = set()
    while stack:
        x, y = stack.pop()
        if (x, y) in seen:
            continue
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        if not dark(x, y):
            continue
        seen.add((x, y))
        r, g, b, _ = px[x, y]
        px[x, y] = (r, g, b, 0)
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return im


def refine(path: Path) -> None:
    im = Image.open(path)
    out = knock_white(im)
    out = flood_knock_dark_edges(out)
    bbox = out.getbbox()
    if bbox:
        out = out.crop(bbox)
    mw = max(out.size) if out.size[0] and out.size[1] else 0
    if 0 < mw < 256:
        ratio = 384 / mw
        out = out.resize(
            (max(1, int(out.width * ratio)), max(1, int(out.height * ratio))),
            Image.Resampling.LANCZOS,
        )
    elif mw > 768:
        ratio = 768 / mw
        out = out.resize(
            (max(1, int(out.width * ratio)), max(1, int(out.height * ratio))),
            Image.Resampling.LANCZOS,
        )
    out.save(path, optimize=True)


def restore_one(stem: str) -> str | None:
    dest = BRANDS / f"{stem}.png"
    url = f"{DATASET}/{stem}.png"
    if download(url, dest):
        try:
            refine(dest)
        except Exception:
            pass
        return stem
    return None


def main() -> None:
    damaged = [p.stem for p in sorted(BRANDS.glob("*.png")) if is_damaged(p)]
    log(f"damaged pngs: {len(damaged)}")
    restored = []
    with ThreadPoolExecutor(max_workers=10) as pool:
        futs = {pool.submit(restore_one, s): s for s in damaged}
        for fut in as_completed(futs):
            got = fut.result()
            if got:
                restored.append(got)
                log(f"  restored {got}")
            else:
                log(f"  miss {futs[fut]}")
    log(f"restored {len(restored)}/{len(damaged)}")

    # Re-refine remaining wide/dark-plate logos carefully (edge flood only).
    popular = [
        "volkswagen",
        "haval",
        "exeed",
        "omoda",
        "tank",
        "lexus",
        "bmw",
        "audi",
        "mercedes",
        "mercedes-benz",
        "toyota",
        "kia",
        "skoda",
        "geely",
        "chery",
        "mazda",
        "honda",
        "hyundai",
        "nissan",
    ]
    for stem in popular:
        p = BRANDS / f"{stem}.png"
        if p.exists() and not is_damaged(p):
            try:
                refine(p)
            except Exception as e:
                log(f"refine fail {stem}: {e}")


if __name__ == "__main__":
    main()
