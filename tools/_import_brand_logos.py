# -*- coding: utf-8 -*-
"""Import real car logos into assets/brands and regenerate car_brands.dart.

Sources:
  - filippofilip95/car-logos-dataset (already downloaded as *.png)
  - avto-dev/vehicle-logotypes (RU/CN gaps)
  - Simple Icons SVGs kept when no PNG (mono, good on dark UI)
"""
from __future__ import annotations

import json
import re
import urllib.request
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    import subprocess
    import sys

    subprocess.check_call([sys.executable, "-m", "pip", "install", "pillow", "-q"])
    from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRANDS = ROOT / "assets" / "brands"
DART = ROOT / "lib" / "car_brands.dart"
UA = "DetAppBrandImport/1.0"

# Our app slug → list of human aliases (latin + cyrillic). File may be slug.png or mapped.
ALIASES: dict[str, list[str]] = {
    "toyota": ["toyota", "тойота"],
    "bmw": ["bmw", "бмв"],
    "mercedes": ["mercedes", "mercedes-benz", "mercedesbenz", "мерседес", "benz"],
    "audi": ["audi", "ауди"],
    "volkswagen": ["volkswagen", "vw", "фольксваген", "фолькс", "фольц"],
    "hyundai": ["hyundai", "хендай", "хёндай", "хюндай", "хундай"],
    "kia": ["kia", "киа"],
    "skoda": ["skoda", "škoda", "шкода"],
    "porsche": ["porsche", "порше"],
    "landrover": [
        "land rover",
        "landrover",
        "range rover",
        "rangerover",
        "ленд ровер",
        "лендровер",
        "рендж ровер",
        "рейндж ровер",
    ],
    "mini": ["mini", "мини"],
    "nissan": ["nissan", "ниссан"],
    "mazda": ["mazda", "мазда"],
    "honda": ["honda", "хонда"],
    "mitsubishi": ["mitsubishi", "митсубиси", "мицубиси", "мицубиши"],
    "subaru": ["subaru", "субару"],
    "volvo": ["volvo", "вольво"],
    "tesla": ["tesla", "тесла"],
    "ford": ["ford", "форд"],
    "chevrolet": ["chevrolet", "chevy", "шевроле"],
    "renault": ["renault", "рено"],
    "peugeot": ["peugeot", "пежо"],
    "bentley": ["bentley", "бентли"],
    "jaguar": ["jaguar", "ягуар"],
    "infiniti": ["infiniti", "инфинити"],
    "cadillac": ["cadillac", "кадиллак", "кадилак"],
    "jeep": ["jeep", "джип"],
    "suzuki": ["suzuki", "сузуки"],
    "opel": ["opel", "опель"],
    "citroen": ["citroen", "citroën", "ситроен"],
    "fiat": ["fiat", "фиат"],
    "alfa": ["alfa", "alfa romeo", "alfaromeo", "альфа", "альфа ромео"],
    "rollsroyce": ["rolls-royce", "rolls royce", "rollsroyce", "роллс", "роллс-ройс"],
    "bugatti": ["bugatti", "бугатти", "бугатии"],
    "lada": ["lada", "ваз", "лада"],
    "seat": ["seat", "сеат"],
    "smart": ["smart", "смарт"],
    "acura": ["acura", "акура"],
    "chrysler": ["chrysler", "крайслер"],
    "ram": ["ram", "рам"],
    "ferrari": ["ferrari", "феррари"],
    "lamborghini": ["lamborghini", "ламборгини", "ламборджини"],
    "maserati": ["maserati", "мазерати", "масерати"],
    "dacia": ["dacia", "дачия"],
    "ds": ["ds", "ds automobiles", "дс"],
    "vauxhall": ["vauxhall", "воксолл"],
    "tata": ["tata", "тата"],
    "gm": ["gm", "general motors", "generalmotors", "джиэм"],
    "astonmartin": ["aston martin", "astonmartin", "астон мартин", "астон"],
    "mclaren": ["mclaren", "mc laren", "макларен"],
    "polestar": ["polestar", "полестар"],
    "lucid": ["lucid", "lucid motors", "люсид"],
    "mg": ["mg", "morris garages", "мж", "мг"],
    "koenigsegg": ["koenigsegg", "кёнигсегг", "кенигсегг"],
    "scania": ["scania", "скания"],
    "iveco": ["iveco", "ивеко"],
    "man": ["man", "ман"],
    "daf": ["daf", "даф"],
    "saturn": ["saturn", "сатурн"],
    "xiaomi": ["xiaomi", "сяоми"],
    "mahindra": ["mahindra", "махиндра"],
    "proton": ["proton", "протон"],
    "lexus": ["lexus", "лексус"],
    "genesis": ["genesis", "генезис", "дженезис"],
    "byd": ["byd", "бйд", "бид"],
    "geely": ["geely", "джили", "геели"],
    "chery": ["chery", "чери"],
    "haval": ["haval", "хавал", "хавейл"],
    "gwm": ["gwm", "great wall", "greatwall", "грейт вол"],
    "zeekr": ["zeekr", "зикр", "зеекр"],
    "li": ["li auto", "lixiang", "li xiang", "ликсианг", "ли авто", "лисян", "лисян"],
    "changan": ["changan", "чанган", "чангаан"],
    "exeed": ["exeed", "ексид", "эксид"],
    "omoda": ["omoda", "омода"],
    "jaecoo": ["jaecoo", "джаку", "джеку", "jaeco"],
    "hongqi": ["hongqi", "хунци", "хонци"],
    "uaz": ["uaz", "уаз"],
    "gaz": ["gaz", "газ", "gazelle", "газель", "sobol", "соболь"],
    "tank": ["tank", "танк"],
    "dodge": ["dodge", "додж"],
    "lotus": ["lotus", "лотос"],
    "buick": ["buick", "бьюик", "буик"],
    "gmc": ["gmc", "джиэмси"],
    "lincoln": ["lincoln", "линкольн"],
    "cupra": ["cupra", "купра"],
    "isuzu": ["isuzu", "исузу"],
    "ssangyong": ["ssangyong", "ssang yong", "кгм", "kgm", "ссангйонг", "ссанъйонг"],
    "nio": ["nio", "нио"],
    "xpeng": ["xpeng", "xiaopeng", "кспенг", "сяопенг"],
    "vinfast": ["vinfast", "винфаст"],
    "rivian": ["rivian", "ривиан"],
    "hummer": ["hummer", "хаммер"],
    "evolute": ["evolute", "эволют", "еволют"],
    "moskvich": ["moskvich", "москвич", "moskvitch"],
    "jetour": ["jetour", "джетур"],
    "dongfeng": ["dongfeng", "донгфенг", "дунфэн"],
    "faw": ["faw", "фав"],
    "aito": ["aito", "айто"],
    "voyah": ["voyah", "воя", "воях"],
    "leapmotor": ["leapmotor", "leap motor", "липмотор"],
    "skywell": ["skywell", "скайвелл"],
    "jac": ["jac", "джак"],
    "lancia": ["lancia", "ланча"],
    "abarth": ["abarth", "абарт"],
    "alpine": ["alpine", "альпин"],
    "saab": ["saab", "сааб"],
    "daihatsu": ["daihatsu", "дайхатсу", "дайхацу"],
    "aurus": ["aurus", "аурус"],
    "belgee": ["belgee", "белджи", "белжи"],
    "kaiyi": ["kaiyi", "кайи", "каийи"],
    "livan": ["livan", "ливан"],
    "swm": ["swm", "свм"],
    "avatr": ["avatr", "аватр"],
    "hiphi": ["hiphi", "хипхи"],
    "jetta": ["jetta", "джетта"],
    "oshan": ["oshan", "ошан"],
    "lynkco": ["lynk", "lynk & co", "lynk and co", "линк", "линк ко"],
    "lifan": ["lifan", "лифан"],
    "baic": ["baic", "baic motor", "баик", "баик мотор"],
    "gac": ["gac", "gac group", "гак"],
    "saic": ["saic", "saic motor", "саик"],
    "arcfox": ["arcfox", "аркфокс"],
    "baojun": ["baojun", "баоджун", "баоцзюнь"],
    "brabus": ["brabus", "брабус"],
    "alpina": ["alpina", "альпина"],
    "pagani": ["pagani", "пагани"],
    "maybach": ["maybach", "майбах"],
    "pontiac": ["pontiac", "понтиак"],
    "plymouth": ["plymouth", "плимут"],
    "oldsmobile": ["oldsmobile", "олдсмобиль"],
}

# App slug → preferred asset file stem (without extension)
FILE_MAP: dict[str, str] = {
    "mercedes": "mercedes-benz",
    "landrover": "land-rover",
    "alfa": "alfa-romeo",
    "rollsroyce": "rolls-royce",
    "astonmartin": "aston-martin",
    "gwm": "great-wall",
    "li": "li-auto",
    "gm": "general-motors",
    "moskvich": "moskvitch",
    "lynkco": "lynk-and-co",
    "baic": "baic-motor",
    "gac": "gac-group",
    "saic": "saic-motor",
    "jac": "jac",
}

# avto-dev keys → our slug (download if missing)
AVTO_GAPS: dict[str, str] = {
    "tank": "tank",
    "jaecoo": "jaecoo",
    "aito": "aito",
    "voyah": "voyah",
    "moskvitch": "moskvitch",
    "lixiang": "lixiang",
    "aurus": "aurus",
    "belgee": "belgee",
    "kaiyi": "kaiyi",
    "livan": "livan",
    "swm": "swm",
    "avatr": "avatr",
    "hiphi": "hiphi",
    "jetta": "jetta",
    "oshan": "oshan",
    "lynk-and-co": "lynk-and-co",
    "jac-motors": "jac-motors",
}


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
            elif min(r, g, b) >= threshold - 18 and (r + g + b) >= threshold * 3 - 30:
                px[x, y] = (r, g, b, 0)
    return im


def process_png(path: Path) -> None:
    im = Image.open(path)
    out = knock_white(im)
    bbox = out.getbbox()
    if bbox:
        out = out.crop(bbox)
    # keep reasonable size
    mw = max(out.size)
    if mw > 512:
        ratio = 512 / mw
        out = out.resize((int(out.width * ratio), int(out.height * ratio)), Image.Resampling.LANCZOS)
    out.save(path, optimize=True)


def download(url: str, dest: Path) -> bool:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=45) as r:
            data = r.read()
        if len(data) < 200:
            return False
        dest.write_bytes(data)
        return True
    except Exception as e:
        print("fail", url, e)
        return False


def fetch_avto() -> None:
    url = "https://raw.githubusercontent.com/avto-dev/vehicle-logotypes/master/src/vehicle-logotypes.json"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = json.loads(r.read().decode("utf-8"))
    for key, stem in AVTO_GAPS.items():
        item = data.get(key)
        if not item:
            print("avto missing key", key)
            continue
        uri = (item.get("logotype") or {}).get("uri")
        if not uri:
            continue
        dest = BRANDS / f"{stem}.png"
        # always refresh gap brands from avto (better for RU/CN)
        if download(uri, dest):
            print("avto", stem)
            try:
                process_png(dest)
            except Exception as e:
                print("process fail", stem, e)


def sync_canonical_copies() -> None:
    """Ensure our slug.png exists when dataset used hyphenated names."""
    copies = {
        "li.png": "li-auto.png",
        "landrover.png": "land-rover.png",
        "alfa.png": "alfa-romeo.png",
        "rollsroyce.png": "rolls-royce.png",
        "astonmartin.png": "aston-martin.png",
        "gwm.png": "great-wall.png",
        "gm.png": "general-motors.png",
        "mercedes.png": "mercedes-benz.png",
        "moskvich.png": "moskvitch.png",
        "lynkco.png": "lynk-and-co.png",
        "baic.png": "baic-motor.png",
        "gac.png": "gac-group.png",
        "saic.png": "saic-motor.png",
        "jac.png": "jac-motors.png",  # prefer avto if present
        "lixiang.png": "li-auto.png",
    }
    for dst_name, src_name in copies.items():
        src = BRANDS / src_name
        dst = BRANDS / dst_name
        if src.exists() and (not dst.exists() or dst.stat().st_size < 200):
            dst.write_bytes(src.read_bytes())
            print("copy", src_name, "->", dst_name)
        # if jac.png exists from dataset and jac-motors from avto, prefer larger
        if dst_name == "jac.png":
            alt = BRANDS / "jac-motors.png"
            if alt.exists() and (not dst.exists() or alt.stat().st_size > dst.stat().st_size):
                dst.write_bytes(alt.read_bytes())
                print("prefer jac-motors -> jac.png")


def remove_fake_svgs() -> None:
    # tiny monograms / wordmarks that conflict with real PNG
    for p in BRANDS.glob("*.svg"):
        if p.stat().st_size < 900:
            print("rm tiny svg", p.name)
            p.unlink()
    # also remove svg when we have good png for same stem
    for png in BRANDS.glob("*.png"):
        svg = png.with_suffix(".svg")
        if svg.exists() and svg.stat().st_size < 5000:
            # keep Simple Icons-sized real SVGs only if no png preferred —
            # we prefer PNG for color logos; drop svg sibling to avoid wrong path
            pass


def knock_all() -> None:
    n = 0
    for p in sorted(BRANDS.glob("*.png")):
        try:
            process_png(p)
            n += 1
            if n % 50 == 0:
                print("knocked", n)
        except Exception as e:
            print("knock fail", p.name, e)
    print("knocked total", n)


def auto_aliases_from_files() -> dict[str, list[str]]:
    """Add every png/svg stem as its own alias if not already covered."""
    out = {k: list(v) for k, v in ALIASES.items()}
    known_files = set()
    for p in BRANDS.glob("*.png"):
        known_files.add(p.stem)
    for p in BRANDS.glob("*.svg"):
        known_files.add(p.stem)

    # map file stem → canonical slug
    file_to_slug: dict[str, str] = {}
    for slug, file_stem in FILE_MAP.items():
        file_to_slug[file_stem] = slug
        file_to_slug[slug] = slug
    for slug in out:
        file_to_slug[slug] = slug

    for stem in sorted(known_files):
        # skip variant logos
        if stem in {
            "audi-sport",
            "bmw-m",
            "chevrolet-corvette",
            "dodge-viper",
            "ford-mustang",
            "mercedes-amg",
            "nissan-gt-r",
            "nissan-nismo",
            "toyota-alphard",
            "toyota-century",
            "toyota-crown",
            "faw-jiefang",
        }:
            continue
        slug = file_to_slug.get(stem)
        if slug is None:
            # create slug without hyphens for multi-word
            slug = stem.replace("-", "")
            if slug not in out:
                pretty = stem.replace("-", " ")
                out[slug] = [pretty, stem, slug]
            file_to_slug[stem] = slug
        else:
            # ensure stem aliases point to existing slug
            aliases = out.setdefault(slug, [slug])
            for a in (stem, stem.replace("-", " "), stem.replace("-", "")):
                if a not in aliases:
                    aliases.append(a)
    return out, file_to_slug, known_files


def dart_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


def write_dart(aliases: dict[str, list[str]], file_to_slug: dict[str, str], known_files: set[str]) -> None:
    # resolve asset path: prefer png for slug
    png_slugs: list[str] = []
    svg_only: list[str] = []
    asset_override: dict[str, str] = {}  # slug -> full relative path stem+ext without dir

    for slug in sorted(aliases.keys()):
        candidates = []
        if slug in FILE_MAP:
            candidates.append(FILE_MAP[slug])
        candidates.append(slug)
        # also hyphenated form
        if "-" not in slug and len(slug) > 4:
            # try common hyphen inserts from files
            pass
        # Prefer SVG when present (Simple Icons / cleaned mono — better on dark UI).
        # Fall back to color PNG from datasets.
        chosen = None
        for c in candidates:
            svg = BRANDS / f"{c}.svg"
            if svg.exists() and svg.stat().st_size >= 400:
                chosen = f"{c}.svg"
                break
        if not chosen:
            for c in candidates:
                if (BRANDS / f"{c}.png").exists():
                    chosen = f"{c}.png"
                    break
        if not chosen:
            for stem, s in file_to_slug.items():
                if s != slug:
                    continue
                svg = BRANDS / f"{stem}.svg"
                if svg.exists() and svg.stat().st_size >= 400:
                    chosen = f"{stem}.svg"
                    break
                if (BRANDS / f"{stem}.png").exists():
                    chosen = f"{stem}.png"
                    break
        if not chosen:
            continue
        asset_override[slug] = chosen
        if chosen.endswith(".png"):
            png_slugs.append(slug)
        else:
            svg_only.append(slug)

    lines: list[str] = []
    lines.append("/// Маппинг марки авто → лого в `assets/brands/`.")
    lines.append("/// Источники: car-logos-dataset + avto-dev/vehicle-logotypes + Simple Icons.")
    lines.append("/// Нет файла → инициалы в [CarBrandMark].")
    lines.append("class CarBrands {")
    lines.append("  CarBrands._();")
    lines.append("")
    lines.append("  static const assetDir = 'assets/brands';")
    lines.append("")
    lines.append("  /// slug файла → список алиасов (латиница + кириллица).")
    lines.append("  static const Map<String, List<String>> _aliases = {")
    for slug in sorted(aliases.keys()):
        if slug not in asset_override:
            continue
        vals = aliases[slug]
        # unique preserve order
        seen = set()
        uniq = []
        for v in vals:
            k = v.lower()
            if k in seen:
                continue
            seen.add(k)
            uniq.append(v)
        body = ", ".join(f"'{dart_escape(v)}'" for v in uniq)
        lines.append(f"    '{dart_escape(slug)}': [{body}],")
    lines.append("  };")
    lines.append("")
    lines.append("  /// slug → имя файла (png/svg) внутри assetDir.")
    lines.append("  static const Map<String, String> _assetFile = {")
    for slug, fname in sorted(asset_override.items()):
        lines.append(f"    '{dart_escape(slug)}': '{dart_escape(fname)}',")
    lines.append("  };")
    lines.append("")
    lines.append("  static final Map<String, String> _aliasToSlug = () {")
    lines.append("    final m = <String, String>{};")
    lines.append("    for (final e in _aliases.entries) {")
    lines.append("      for (final a in e.value) {")
    lines.append("        m[_norm(a)] = e.key;")
    lines.append("      }")
    lines.append("      m[_norm(e.key)] = e.key;")
    lines.append("    }")
    lines.append("    return m;")
    lines.append("  }();")
    lines.append("")
    lines.append("  static String _norm(String s) =>")
    lines.append(
        "      s.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'[^a-zа-я0-9]+'), '');"
    )
    lines.append("")
    lines.append("  /// Из «Toyota Camry» / «BMW X5» → slug `toyota` / `bmw`, иначе null.")
    lines.append("  static String? slugFor(String? makeModel) {")
    lines.append("    final raw = (makeModel ?? '').trim();")
    lines.append("    if (raw.isEmpty) return null;")
    lines.append("    final lower = raw.toLowerCase();")
    lines.append("    final compact = _norm(raw);")
    lines.append("")
    lines.append("    final multi = _aliasToSlug.keys.where((k) => k.length >= 6).toList()")
    lines.append("      ..sort((a, b) => b.length.compareTo(a.length));")
    lines.append("    for (final key in multi) {")
    lines.append("      if (compact.startsWith(key) || compact.contains(key)) {")
    lines.append("        return _aliasToSlug[key];")
    lines.append("      }")
    lines.append("    }")
    lines.append("")
    lines.append("    final first = lower.split(RegExp(r'[\\s/\\-]+')).firstWhere(")
    lines.append("          (e) => e.isNotEmpty,")
    lines.append("          orElse: () => '',")
    lines.append("        );")
    lines.append("    if (first.isEmpty) return null;")
    lines.append("    final n = _norm(first);")
    lines.append("    if (_aliasToSlug.containsKey(n)) return _aliasToSlug[n];")
    lines.append("")
    lines.append("    for (final e in _aliasToSlug.entries) {")
    lines.append("      if (e.key.length >= 3 && compact.startsWith(e.key)) return e.value;")
    lines.append("    }")
    lines.append("    return null;")
    lines.append("  }")
    lines.append("")
    lines.append("  static String? assetPathFor(String? makeModel) {")
    lines.append("    final slug = slugFor(makeModel);")
    lines.append("    if (slug == null) return null;")
    lines.append("    final file = _assetFile[slug];")
    lines.append("    if (file == null) return null;")
    lines.append("    return '$assetDir/$file';")
    lines.append("  }")
    lines.append("}")
    lines.append("")

    DART.write_text("\n".join(lines), encoding="utf-8")
    print(
        "wrote",
        DART.name,
        "slugs",
        len(asset_override),
        "png",
        len(png_slugs),
        "svg",
        len(svg_only),
    )


def main() -> None:
    BRANDS.mkdir(parents=True, exist_ok=True)
    print("=== avto gaps ===")
    fetch_avto()
    print("=== sync copies ===")
    sync_canonical_copies()
    print("=== remove tiny fake svgs ===")
    remove_fake_svgs()
    print("=== knock white bg ===")
    knock_all()
    print("=== write dart ===")
    aliases, file_to_slug, known = auto_aliases_from_files()
    write_dart(aliases, file_to_slug, known)
    print("png", len(list(BRANDS.glob('*.png'))), "svg", len(list(BRANDS.glob('*.svg'))))


if __name__ == "__main__":
    main()
