# -*- coding: utf-8 -*-
"""Prefer color-accurate marks over Simple Icons mono for multi-color brands.

Simple Icons paints the whole glyph in one brand color (BMW becomes all-blue).
For brands with distinctive multi-color emblems we prefer:
  1) Wikimedia / real multi-fill SVG if present and not SI-mono
  2) else color PNG
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRANDS = ROOT / "assets" / "brands"
DART = ROOT / "lib" / "car_brands.dart"

# Slugs where mono SI looks wrong vs official multi-color mark.
COLOR_CRITICAL = {
    "bmw",
    "alfa",
    "alfa-romeo",
    "porsche",
    "ferrari",
    "lamborghini",
    "maserati",
    "mitsubishi",
    "subaru",
    "suzuki",
    "mini",
    "toyota",  # red emblem
    "honda",  # red H (classic)
    "acura",
    "infiniti",
    "lexus",  # often silver/graphite, SI OK-ish but PNG better
    "landrover",
    "land-rover",
    "jaguar",
    "bentley",
    "rollsroyce",
    "rolls-royce",
    "astonmartin",
    "aston-martin",
    "bugatti",
    "mclaren",
    "pagani",
    "koenigsegg",
    "lotus",
    "jeep",
    "dodge",
    "ram",
    "cadillac",
    "buick",
    "gmc",
    "chevrolet",
    "ford",  # blue oval is fine as mono, but PNG oval is better
    "hyundai",
    "kia",
    "genesis",
    # skoda: SI SVG (зелёная стрела) резче шумного 3D PNG
    "seat",
    "cupra",
    "opel",
    "peugeot",
    "renault",
    "citroen",
    "fiat",
    "abarth",
    "lancia",
    "dacia",
    "volvo",
    "saab",
    "smart",
    "tesla",
    "byd",
    "geely",
    "chery",
    "haval",
    "gwm",
    "great-wall",
    "tank",
    "exeed",
    "omoda",
    "jaecoo",
    "nio",
    "xpeng",
    "zeekr",
    "li",
    "li-auto",
}


def is_simple_icons_mono(svg: Path) -> bool:
    if not svg.exists() or svg.stat().st_size < 80:
        return False
    t = svg.read_text(encoding="utf-8", errors="ignore")
    if 'role="img"' not in t:
        return False
    fills = {x.upper() for x in re.findall(r'fill="#([0-9A-Fa-f]{3,8})"', t)}
    fills |= {x.upper() for x in re.findall(r"fill='#([0-9A-Fa-f]{3,8})'", t)}
    fills -= {"FFF", "FFFFFF", "000", "000000", "NONE"}
    # Simple Icons: single brand fill on the whole mark.
    return len(fills) <= 1


def png_ok(stem: str) -> Path | None:
    for name in (f"{stem}.png",):
        p = BRANDS / name
        if p.exists() and p.stat().st_size >= 2500:
            return p
    # hyphen variants
    for p in BRANDS.glob("*.png"):
        if p.stem.replace("-", "") == stem.replace("-", "") and p.stat().st_size >= 2500:
            return p
    return None


def main() -> None:
    text = DART.read_text(encoding="utf-8")
    m = re.search(
        r"static const Map<String, String> _assetFile = \{(?P<body>.*?)\n  \};",
        text,
        flags=re.S,
    )
    if not m:
        raise SystemExit("no _assetFile")
    entries = re.findall(r"'([^']+)':\s*'([^']+)'", m.group("body"))
    lines = []
    switched = []
    for slug, fname in entries:
        chosen = fname
        stem = Path(fname).stem
        critical = slug in COLOR_CRITICAL or stem in COLOR_CRITICAL
        svg = BRANDS / f"{stem}.svg"
        # also check slug.svg
        if not svg.exists():
            svg = BRANDS / f"{slug}.svg"

        if critical and fname.endswith(".svg") and is_simple_icons_mono(svg):
            png = png_ok(stem) or png_ok(slug)
            if png is not None:
                chosen = png.name
                switched.append(f"{slug}: {fname} -> {chosen}")
        lines.append(f"    '{slug}': '{chosen}',")

    new_body = "\n" + "\n".join(lines)
    DART.write_text(text[: m.start("body")] + new_body + text[m.end("body") :], encoding="utf-8")
    print(f"switched to color PNG: {len(switched)}")
    for s in switched:
        print(" ", s)


if __name__ == "__main__":
    main()
