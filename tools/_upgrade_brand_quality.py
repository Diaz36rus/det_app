# -*- coding: utf-8 -*-
"""Upgrade car brand marks: crisp SVG where possible + cleaner PNGs.

Sources: Simple Icons CDN, Wikimedia Commons (curated), existing PNG cleanup.
Updates only `_assetFile` in lib/car_brands.dart.
"""
from __future__ import annotations

import re
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
DART = ROOT / "lib" / "car_brands.dart"
UA = "DetAppBrandUpgrade/1.2"

# stem → Simple Icons slug
SI_SLUG: dict[str, str] = {
    "abarth": "abarth",
    "acura": "acura",
    "alfa": "alfaromeo",
    "alfa-romeo": "alfaromeo",
    "alpine": "alpine",
    "astonmartin": "astonmartin",
    "aston-martin": "astonmartin",
    "audi": "audi",
    "bentley": "bentley",
    "bmw": "bmw",
    "bugatti": "bugatti",
    "buick": "buick",
    "byd": "byd",
    "cadillac": "cadillac",
    "chevrolet": "chevrolet",
    "chrysler": "chrysler",
    "citroen": "citroen",
    "cupra": "cupra",
    "dacia": "dacia",
    "daihatsu": "daihatsu",
    "dodge": "dodge",
    "ds": "dsautomobiles",
    "ferrari": "ferrari",
    "fiat": "fiat",
    "ford": "ford",
    "genesis": "genesis",
    "gm": "generalmotors",
    "general-motors": "generalmotors",
    "gmc": "gmc",
    "honda": "honda",
    "hummer": "hummer",
    "hyundai": "hyundai",
    "infiniti": "infiniti",
    "isuzu": "isuzu",
    "iveco": "iveco",
    "jaguar": "jaguar",
    "jeep": "jeep",
    "kia": "kia",
    "koenigsegg": "koenigsegg",
    "lada": "lada",
    "lamborghini": "lamborghini",
    "lancia": "lancia",
    "landrover": "landrover",
    "land-rover": "landrover",
    "lexus": "lexus",
    "lincoln": "lincoln",
    "lotus": "lotus",
    "lucid": "lucid",
    "mahindra": "mahindra",
    "maserati": "maserati",
    "mazda": "mazda",
    "mclaren": "mclaren",
    "mercedes": "mercedes",
    "mercedes-benz": "mercedes",
    "mg": "mg",
    "mini": "mini",
    "mitsubishi": "mitsubishi",
    "nissan": "nissan",
    "opel": "opel",
    "peugeot": "peugeot",
    "polestar": "polestar",
    "porsche": "porsche",
    "ram": "ram",
    "renault": "renault",
    "rivian": "rivian",
    "rollsroyce": "rollsroyce",
    "rolls-royce": "rollsroyce",
    "saab": "saab",
    "seat": "seat",
    "skoda": "skoda",
    "smart": "smart",
    "subaru": "subaru",
    "suzuki": "suzuki",
    "tata": "tata",
    "tesla": "tesla",
    "toyota": "toyota",
    "volkswagen": "volkswagen",
    "volvo": "volvo",
    "xiaomi": "xiaomi",
}

WIKI_SVG: dict[str, str] = {
    "haval": "Haval_2023_logo.svg",
    "geely": "Geely_logo.svg",
    "chery": "Chery_logo.svg",
    "tank": "Tank_(marque)_logo.svg",
    "exeed": "EXEED_logo.svg",
    "omoda": "Omoda_logo.svg",
    "jaecoo": "Jaecoo_logo.svg",
    "gwm": "Great_Wall_Motors_logo.svg",
    "great-wall": "Great_Wall_Motors_logo.svg",
    "changan": "Changan_Automobile_logo.svg",
    "hongqi": "Hongqi_logo.svg",
    "li": "Li_Auto_logo.svg",
    "li-auto": "Li_Auto_logo.svg",
    "nio": "NIO_logo.svg",
    "xpeng": "XPeng_logo.svg",
    "zeekr": "Zeekr_logo.svg",
    "voyah": "Voyah_logo.svg",
    "aito": "AITO_logo.svg",
    "avatr": "Avatr_logo.svg",
    "lynk-and-co": "Lynk_%26_Co_logo.svg",
    "lynkco": "Lynk_%26_Co_logo.svg",
    "uaz": "UAZ_logo.svg",
    "ssangyong": "SsangYong_Motor_logo.svg",
    "jetour": "Jetour_logo.svg",
    "baic": "BAIC_Motor_logo.svg",
    "baic-motor": "BAIC_Motor_logo.svg",
    "gac": "GAC_Group_logo.svg",
    "gac-group": "GAC_Group_logo.svg",
    "dongfeng": "Dongfeng_Motor_logo.svg",
    "faw": "FAW_Group_logo.svg",
    "bestune": "Bestune_logo.svg",
    "hiphi": "HiPhi_logo.svg",
    "leapmotor": "Leapmotor_logo.svg",
    "skywell": "Skywell_logo.svg",
    "evolute": "Evolute_logo.svg",
    "moskvich": "Moskvitch_logo.svg",
    "moskvitch": "Moskvitch_logo.svg",
    "belgee": "Belgee_logo.svg",
    "kaiyi": "Kaiyi_logo.svg",
    "aurus": "Aurus_logo.svg",
}


def log(msg: str) -> None:
    print(msg, flush=True)


def download(url: str, dest: Path, min_size: int = 250) -> bool:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=25) as r:
            data = r.read()
        if len(data) < min_size:
            return False
        head = data[:160].lstrip().lower()
        if head.startswith(b"<!doctype") or head.startswith(b"<html"):
            return False
        if b"<svg" not in data[:500].lower() and not url.lower().endswith(".png"):
            # SI CDN is svg without always starting with <svg in first bytes (BOM)
            if b"<svg" not in data.lower()[:2000]:
                return False
        dest.write_bytes(data)
        return True
    except Exception:
        return False


def fetch_si(stem: str) -> str | None:
    si = SI_SLUG.get(stem)
    if not si:
        return None
    dest = BRANDS / f"{stem}.svg"
    for url in (
        f"https://cdn.simpleicons.org/{si}",
        f"https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/{si}.svg",
    ):
        if download(url, dest):
            return f"SI {stem}"
    return None


def fetch_wiki(stem: str) -> str | None:
    name = WIKI_SVG.get(stem)
    if not name:
        return None
    dest = BRANDS / f"{stem}.svg"
    url = f"https://commons.wikimedia.org/wiki/Special:FilePath/{name}"
    if download(url, dest):
        return f"WIKI {stem}"
    return None


def knock_dark_bg(im: Image.Image, threshold: int = 36) -> Image.Image:
    """Edge flood-fill only — keeps near-black logo ink intact."""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()

    def dark(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        return a > 0 and r <= threshold and g <= threshold and b <= threshold

    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    if sum(1 for c in corners if dark(*c)) < 2:
        return im

    stack = [c for c in corners if dark(*c)]
    step_x = max(1, w // 40)
    step_y = max(1, h // 40)
    for x in range(0, w, step_x):
        if dark(x, 0):
            stack.append((x, 0))
        if dark(x, h - 1):
            stack.append((x, h - 1))
    for y in range(0, h, step_y):
        if dark(0, y):
            stack.append((0, y))
        if dark(w - 1, y):
            stack.append((w - 1, y))

    seen: set[tuple[int, int]] = set()
    while stack:
        x, y = stack.pop()
        if (x, y) in seen or x < 0 or y < 0 or x >= w or y >= h:
            continue
        if not dark(x, y):
            continue
        seen.add((x, y))
        r, g, b, _ = px[x, y]
        px[x, y] = (r, g, b, 0)
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return im


def knock_white_bg(im: Image.Image, threshold: int = 242) -> Image.Image:
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
            elif min(r, g, b) >= threshold - 18 and (r + g + b) >= threshold * 3 - 30:
                px[x, y] = (r, g, b, 0)
    return im


def refine_png(path: Path) -> None:
    im = Image.open(path)
    out = knock_white_bg(im)
    out = knock_dark_bg(out)
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
    tmp = path.with_suffix(".png.tmp")
    out.save(tmp, optimize=True)
    tmp.replace(path)


def prefer_svg_in_dart() -> None:
    text = DART.read_text(encoding="utf-8")
    m = re.search(
        r"static const Map<String, String> _assetFile = \{(?P<body>.*?)\n  \};",
        text,
        flags=re.S,
    )
    if not m:
        raise SystemExit("cannot find _assetFile in car_brands.dart")

    entries = re.findall(r"'([^']+)':\s*'([^']+)'", m.group("body"))
    svg_stems = {p.stem for p in BRANDS.glob("*.svg") if p.stat().st_size >= 200}
    png_stems = {p.stem for p in BRANDS.glob("*.png")}
    svg_norm = {s.replace("-", ""): s for s in svg_stems}

    new_lines: list[str] = []
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
            if stem not in png_stems:
                for p in png_stems:
                    if p.replace("-", "") in {stem.replace("-", ""), slug.replace("-", "")}:
                        chosen = f"{p}.png"
                        break
            png_n += 1
        new_lines.append(f"    '{slug}': '{chosen}',")

    new_body = "\n" + "\n".join(new_lines)
    DART.write_text(text[: m.start("body")] + new_body + text[m.end("body") :], encoding="utf-8")
    log(f"dart _assetFile: svg={svg_n} png={png_n}")


def main() -> None:
    BRANDS.mkdir(parents=True, exist_ok=True)
    targets = sorted(set(SI_SLUG) | set(WIKI_SVG))
    log(f"=== SVG fetch ({len(targets)} curated stems, parallel) ===")

    results: list[str] = []

    def one(stem: str) -> str | None:
        # Prefer Wikimedia official mark when curated; else Simple Icons.
        if stem in WIKI_SVG:
            got = fetch_wiki(stem)
            if got:
                return got
        return fetch_si(stem)

    with ThreadPoolExecutor(max_workers=12) as pool:
        futs = {pool.submit(one, s): s for s in targets}
        for fut in as_completed(futs):
            msg = fut.result()
            if msg:
                results.append(msg)
                log(f"  {msg}")

    log(f"svg downloaded/updated: {len(results)}")

    log("=== refine PNGs ===")
    n = 0
    for p in sorted(BRANDS.glob("*.png")):
        try:
            refine_png(p)
            n += 1
            if n % 80 == 0:
                log(f"  refined {n}")
        except Exception as e:
            log(f"  refine fail {p.name}: {e}")
    log(f"refined {n}")

    log("=== prefer SVG in car_brands.dart ===")
    prefer_svg_in_dart()
    log(f"png={len(list(BRANDS.glob('*.png')))} svg={len(list(BRANDS.glob('*.svg')))}")


if __name__ == "__main__":
    main()
