import json
import os

p = os.path.join(os.environ["TEMP"], "det_bugs.json")
out = os.path.join(os.environ["TEMP"], "det_bugs_short.txt")
items = json.load(open(p, encoding="utf-8"))
if isinstance(items, dict):
    items = items.get("items") or []
items = sorted(items, key=lambda b: b.get("created_at") or "", reverse=True)
lines = [f"TOTAL {len(items)} newest={items[0].get('created_at') if items else None}", ""]
for b in items:
    sit = str(b.get("situation") or "")
    det = str(b.get("details") or "")
    place = str(b.get("place") or "")
    blob = (sit + " " + place + " " + det[:300]).lower()
    interesting = b.get("platform") == "windows" or any(
        w in blob for w in ("обнов", "update", "portable", "установ", "скач", "zip", "релиз")
    )
    if not interesting:
        continue
    lines.append("=" * 60)
    lines.append(f"id={b.get('id')}  {b.get('created_at')}  build={b.get('app_build')}  {b.get('platform')}")
    lines.append(f"user={b.get('user_name')}  company={b.get('company_name')}")
    lines.append(f"place={place}")
    lines.append(f"situation={sit}")
    # only first 400 chars of details, strip huge stacks somewhat
    short = det[:500].replace("\r", "")
    lines.append(f"details_head={short}")
    lines.append("")

# also list ALL situations for last 12
lines.append("# LAST 12 ALL PLATFORMS (situation only)")
for b in items[:12]:
    lines.append(
        f"- #{b.get('id')} {b.get('created_at')[:16]} b{b.get('app_build')} {b.get('platform')}: {b.get('situation')}"
    )

open(out, "w", encoding="utf-8").write("\n".join(lines))
print(out)
