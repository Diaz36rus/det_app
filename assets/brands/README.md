# Car brand marks

Real logos for `CarBrandMark` in the detailing CRM.

## Sources

1. **[car-logos-dataset](https://github.com/filippofilip95/car-logos-dataset)** — ~387 optimized PNGs (primary bulk set)
2. **[avto-dev/vehicle-logotypes](https://github.com/avto-dev/vehicle-logotypes)** — RU/CN gaps (Tank, Jaecoo, Aito, Voyah, Moskvich, Belgee, …)
3. **[Simple Icons](https://simpleicons.org/)** / **vehiclespecs** — mono SVG where available (preferred on dark UI)

White backgrounds on PNGs are knocked to transparent (`tools/_import_brand_logos.py`).

## Mapping

`lib/car_brands.dart` — aliases (latin + cyrillic) → `assets/brands/{file}`.
Prefer SVG when present; otherwise color PNG on a light plate in the UI.

## Refresh

```powershell
# After refreshing PNGs from the dataset:
python tools\_import_brand_logos.py
```

Do **not** invent monogram logos — only real marks from the packs above.
