# Car brand marks

Real logos for `CarBrandMark` in the detailing CRM.

## Sources

1. **[Simple Icons](https://simpleicons.org/)** — sharp mono SVG (preferred when available)
2. **[Wikimedia Commons](https://commons.wikimedia.org/)** — official SVGs for RU/CN gaps (Haval, Chery, …)
3. **[car-logos-dataset](https://github.com/filippofilip95/car-logos-dataset)** — color PNGs fallback
4. **[avto-dev/vehicle-logotypes](https://github.com/avto-dev/vehicle-logotypes)** — RU/CN PNG gaps (Tank, Omoda, Exeed, …)

White / near-black plates on PNGs are knocked to transparent (`tools/_upgrade_brand_quality.py`, edge flood-fill for dark plates).

## Mapping

`lib/car_brands.dart` — aliases (latin + cyrillic) → `assets/brands/{file}`.
Prefer **SVG** when present and color-accurate; for multi-color emblems (BMW, Ferrari, …)
Simple Icons mono is skipped in favor of color PNG (`tools/_prefer_color_brands.py`).

## Refresh

```powershell
python tools\_upgrade_brand_quality.py
python tools\_fix_brand_pngs.py   # if any PNG got damaged
python tools\_remap_brand_svg.py   # remap _assetFile → prefer SVG
```

Do **not** invent monogram logos — only real marks from the packs above.
