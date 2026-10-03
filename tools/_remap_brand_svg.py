# -*- coding: utf-8 -*-
"""Remap car_brands.dart _assetFile to prefer SVG; fetch a few gap SVGs."""
from __future__ import annotations

import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRANDS = ROOT / "assets" / "brands"
DART = ROOT / "lib" / "car_brands.dart"
UA = "DetAppBrandRemap/1.0"


def download(url: str, dest: Path, min_size: int = 250) -> bool:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read()
        if len(data) < min_size:
            return False
        if b"<svg" not in data.lower()[:4000] and not data.startswith(b"\x89PNG"):
            return False
        dest.write_bytes(data)
        return True
    except Exception as e:
        print("fail", dest.name, e)
        return False


def fetch_gaps() -> None:
    # Wikimedia already fetched haval/lexus/mercedes; try avto-dev for CN gaps.
    url = "https://raw.githubusercontent.com/avto-dev/vehicle-logotypes/master/src/vehicle-logotypes.json"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = json.loads(r.read().decode("utf-8"))
    for key, stem in {
        "omoda": "omoda",
        "exeed": "exeed",
        "tank": "tank",
        "jaecoo": "jaecoo",
        "aito": "aito",
        "avatr": "avatr",
        "livan": "livan",
    }.items():
        item = data.get(key)
        if not item:
            print("avto miss", key)
            continue
        uri = (item.get("logotype") or {}).get("uri")
        if not uri:
            continue
        dest = BRANDS / f"{stem}.png"
        if download(uri, dest, min_size=400):
            print("avto png", stem, dest.stat().st_size)


def prefer_svg() -> None:
    text = DART.read_text(encoding="utf-8")
    m = re.search(
        r"static const Map<String, String> _assetFile = \{(?P<body>.*?)\n  \};",
        text,
        flags=re.S,
    )
    if not m:
        raise SystemExit("no _assetFile")
    entries = re.findall(r"'([^']+)':\s*'([^']+)'", m.group("body"))
    svg_stems = {p.stem for p in BRANDS.glob("*.svg") if p.stat().st_size >= 200}
    png_stems = {p.stem for p in BRANDS.glob("*.png")}
    svg_norm = {s.replace("-", ""): s for s in svg_stems}
    lines = []
    svg_n = png_n = 0
    for slug, fname in entries:
        stem = Path(fname).stem
        chosen = fname
        if stem in svg_stems:
            chosen = f"{stem}.svg"
        else:
            alt = svg_norm.get(stem.replace("-", "")) or svg_norm.get(slug.replace("-", ""))
            if alt:
                chosen = f"{alt}.svg"
        if chosen.endswith(".svg"):
            svg_n += 1
        else:
            if Path(chosen).stem not in png_stems:
                for p in png_stems:
                    if p.replace("-", "") in {stem.replace("-", ""), slug.replace("-", "")}:
                        chosen = f"{p}.png"
                        break
            png_n += 1
        lines.append(f"    '{slug}': '{chosen}',")
    new_body = "\n" + "\n".join(lines)
    DART.write_text(text[: m.start("body")] + new_body + text[m.end("body") :], encoding="utf-8")
    print(f"mapped svg={svg_n} png={png_n}")


def main() -> None:
    print("=== avto gap png refresh ===")
    fetch_gaps()
    print("=== prefer svg ===")
    prefer_svg()
    for n in ["bmw", "haval", "volkswagen", "omoda", "exeed", "tank", "lexus", "mercedes", "mazda"]:
        svg = BRANDS / f"{n}.svg"
        png = BRANDS / f"{n}.png"
        print(
            n,
            f"svg={svg.stat().st_size}" if svg.exists() else "svg=-",
            f"png={png.stat().st_size}" if png.exists() else "png=-",
        )


if __name__ == "__main__":
    main()
