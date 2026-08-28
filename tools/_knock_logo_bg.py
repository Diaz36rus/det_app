# -*- coding: utf-8 -*-
"""Make near-white PNG backgrounds transparent so logos work on dark UI."""
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    import subprocess
    import sys

    subprocess.check_call([sys.executable, "-m", "pip", "install", "pillow", "-q"])
    from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "assets" / "brands"


def knock_white(im: Image.Image, threshold: int = 245) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            # near-white / light gray plate
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
            # also kill very light near-white with slight tint
            elif min(r, g, b) >= threshold - 15 and (r + g + b) >= threshold * 3 - 20:
                px[x, y] = (r, g, b, 0)
    return im


def main() -> None:
    n = 0
    for p in sorted(ROOT.glob("*.png")):
        im = Image.open(p)
        out = knock_white(im)
        # trim transparent margins a bit
        bbox = out.getbbox()
        if bbox:
            out = out.crop(bbox)
        out.save(p, optimize=True)
        n += 1
        print("processed", p.name, out.size)
    print("done", n)


if __name__ == "__main__":
    main()
