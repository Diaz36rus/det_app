# -*- coding: utf-8 -*-
"""Reseed 10 busy overlapping demo orders (20–29.08.2026).

Deletes previous seed orders (#92–101 if present) and recreates with
overlapping order windows and staggered per-work times.

Usage:
  python tools/seed_demo_orders.py
"""
from __future__ import annotations

import json
import urllib.error
import urllib.request

BASE = "http://api.det-app.ru"
LOGIN = "owner@demo.det-app.ru"
PASSWORD = "DetAppAdmin2026!"

# Previous seed ids (best-effort cleanup)
OLD_ORDER_IDS = list(range(92, 112))

PRICES = {
    "Экспресс-мойка": {1: 800, 2: 1000, 3: 1200, 4: 1400},
    "Мойка кузова": {1: 1400, 2: 1800, 3: 2200, 4: 2600},
    "Комплексная мойка": {1: 2500, 2: 3000, 3: 3500, 4: 4000},
    "Уборка багажника": {"fp": 200},
    "Уборка салона": {1: 1100, 2: 1200, 3: 1300, 4: 1400},
    "Химчистка салона": {1: 20000, 2: 23000, 3: 26000, 4: 29000},
    "Химчистка 1го сидения (Ткань)": {"fp": 2500},
    "Химчистка 1го сидения (Кожа)": {"fp": 2000},
    "Химчистка локально": {"fp": 1000},
    "Химчистка двигателя": {"fp": 6000},
    "Химчистка дисков": {"fp": 6000},
    "Детейлинг уборка салона": {"fp": 10000},
    "Восстановительная полировка": {1: 30000, 2: 35000, 3: 40000, 4: 45000},
    "Легкая полировка": {1: 10000, 2: 12000, 3: 14000, 4: 16000},
    "Керамика на кузов (1 слой)": {"fp": 10000},
    "Керамика на кузов (2 слоя)": {"fp": 15000},
    "Быстрая сухая керамика": {"fp": 5000},
    "Быстрая мокрая керамика": {"fp": 2000},
    "Силант на кузов": {"fp": 3000},
    "Krytex лобовое стекло": {"fp": 3500},
    "Krytex передняя полусфера": {"fp": 6000},
    "Krytex все остекление": {1: 8000, 2: 10000, 3: 12000, 4: 12000},
    "Тонировка · Заднее стекло": {"fp": 5500},
    "Тонировка · Лобовое стекло": {"fp": 4500},
    "Оклейка · Капот": {"fp": 8000},
    "Оклейка · Зеркала": {"fp": 3500},
}


def price_of(name: str, car_cls: int) -> float:
    row = PRICES[name]
    if "fp" in row:
        return float(row["fp"])
    return float(row[car_cls])


def workshop_of(name: str) -> str:
    n = name.lower()
    if "химчист" in n or "детейлинг уборка" in n:
        return "Химчистка"
    if any(x in n for x in ("полир", "керамик", "силант", "krytex", "антидожд")):
        return "Полировка"
    if "тонир" in n or "оклей" in n:
        return "Оклейка"
    if "уборка салона" in n:
        return "Интерьер"
    return "Мойка"


def req(method: str, path: str, token: str | None = None, body: dict | None = None):
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    r = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            return None if (not raw or raw.strip() == "null") else json.loads(raw)
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        if method == "DELETE" and e.code in (404, 400):
            return None
        raise SystemExit(f"{method} {path} -> {e.code}: {err}") from e


def iso(day: str, hour: int, minute: int = 0) -> str:
    return f"{day}T{hour:02d}:{minute:02d}:00"


# works: list of (name, start_h, start_m, end_h, end_m)
# order window = min start .. max end of works
# status = column for board (calendar uses work times)
ORDERS = [
    # --- 20.08 busy morning wash lane + хим + полир overlap ---
    {
        "client": ("Игорь Ковалёв", "9001112233"),
        "car": ("Toyota Camry", "А123ВС777", "1"),
        "day": "2026-08-20",
        "status": "Мойка",
        "works": [
            ("Комплексная мойка", 9, 0, 10, 30),
            ("Уборка багажника", 10, 0, 11, 0),
        ],
        "shop": None,
    },
    {
        "client": ("Дмитрий Орлов", "9003334455"),
        "car": ("Volkswagen Polo", "К789ОР136", "1"),
        "day": "2026-08-20",
        "status": "Мойка",
        "works": [
            ("Экспресс-мойка", 9, 45, 10, 45),
            ("Уборка салона", 10, 30, 12, 0),
        ],
        "shop": None,
    },
    {
        "client": ("Анна Смирнова", "9002223344"),
        "car": ("BMW X5", "Е456КХ777", "3"),
        "day": "2026-08-20",
        "status": "Химчистка",
        "works": [
            ("Комплексная мойка", 9, 30, 11, 0),
            ("Химчистка салона", 10, 30, 17, 0),
            ("Химчистка дисков", 14, 0, 16, 30),
        ],
        "shop": "Обратить внимание на бежевый потолок",
    },
    {
        "client": ("Елена Васильева", "9004445566"),
        "car": ("Mercedes-Benz E-Class", "М012ТУ777", "2"),
        "day": "2026-08-20",
        "status": "Полировка",
        "works": [
            ("Легкая полировка", 11, 0, 15, 30),
            ("Силант на кузов", 15, 0, 16, 30),
            ("Krytex лобовое стекло", 16, 0, 17, 30),
        ],
        "shop": "Без абразива на капоте",
    },
    # --- 21.08 оклейка + керамика + большая полировка ---
    {
        "client": ("Сергей Николаев", "9005556677"),
        "car": ("Kia Sportage", "Р451КТ777", "2"),
        "day": "2026-08-21",
        "status": "Оклейка",
        "works": [
            ("Комплексная мойка", 10, 0, 11, 30),
            ("Тонировка · Заднее стекло", 11, 0, 15, 0),
        ],
        "shop": "не повредить обогрев",
    },
    {
        "client": ("Мария Кузнецова", "9006667788"),
        "car": ("Hyundai Solaris", "О234РС777", "1"),
        "day": "2026-08-21",
        "status": "Принят в работу",
        "works": [
            ("Мойка кузова", 11, 30, 13, 0),
            ("Быстрая мокрая керамика", 12, 30, 14, 0),
        ],
        "shop": None,
    },
    {
        "client": ("Алексей Морозов", "9007778899"),
        "car": ("Audi Q7", "Т567УВ777", "4"),
        "day": "2026-08-21",
        "status": "Полировка",
        "works": [
            ("Восстановительная полировка", 9, 0, 17, 0),
            ("Керамика на кузов (1 слой)", 16, 0, 18, 30),
        ],
        "shop": "Сложные царапины на заднем крыле",
    },
    # --- 22.08 оклейка + предзапись пересекаются ---
    {
        "client": ("Павел Лебедев", "9009990011"),
        "car": ("Lexus RX", "В345ДЕ777", "3"),
        "day": "2026-08-22",
        "status": "Оклейка",
        "works": [
            ("Комплексная мойка", 9, 0, 10, 30),
            ("Оклейка · Капот", 10, 0, 14, 0),
            ("Оклейка · Зеркала", 13, 0, 15, 30),
        ],
        "shop": "Плёнка только матовая",
    },
    {
        "client": ("Ольга Соколова", "9008889900"),
        "car": ("Kia Rio", "У890ХЦ136", "1"),
        "day": "2026-08-22",
        "status": "Предварительная запись",
        "works": [
            ("Комплексная мойка", 10, 0, 11, 30),
            ("Krytex передняя полусфера", 11, 0, 13, 0),
        ],
        "shop": None,
    },
    {
        "client": ("Наталья Федорова", "9011112233"),
        "car": ("Skoda Octavia", "С678ФХ777", "2"),
        "day": "2026-08-22",
        "status": "Предварительная запись",
        "works": [
            ("Экспресс-мойка", 11, 0, 12, 0),
            ("Уборка салона", 11, 30, 13, 30),
            ("Химчистка 1го сидения (Ткань)", 12, 30, 14, 30),
        ],
        "shop": "Детское кресло не снимать",
    },
]


def find_or_create_client(token: str, name: str, phone: str) -> int:
    clients = req("GET", "/crm/clients", token=token) or []
    digits = "".join(ch for ch in phone if ch.isdigit())[-10:]
    for c in clients:
        p = "".join(ch for ch in (c.get("phone") or "") if ch.isdigit())[-10:]
        if p == digits:
            return int(c["id"])
    row = req("POST", "/crm/clients", token=token, body={"name": name, "phone": phone, "is_vip": False})
    return int(row["id"])


def plate_key(p: str) -> str:
    table = str.maketrans("АВЕКМНОРСТУХ", "ABEKMHOPCTYX")
    return (p or "").upper().replace(" ", "").translate(table)


def find_or_create_car(
    token: str, client_id: int, make: str, plate: str, category: str
) -> tuple[int, int]:
    """Returns (car_id, client_id). Reuses global plate match and its owner."""
    cars = req("GET", "/crm/cars", token=token) or []
    key = plate_key(plate)
    if key:
        for c in cars:
            if plate_key(c.get("plate") or "") == key:
                return int(c["id"]), int(c["client_id"])
    row = req(
        "POST",
        "/crm/cars",
        token=token,
        body={
            "client_id": client_id,
            "make_model": make,
            "plate": plate,
            "vin": "",
            "category": category,
        },
    )
    return int(row["id"]), client_id


def pick_admin_id(token: str) -> int | None:
    masters = req("GET", "/crm/masters", token=token) or []
    for m in masters:
        if "Администратор" in (m.get("role") or "") and m.get("is_active", True):
            return int(m["id"])
    return None


# Роли → цеха (зеркало Flutter WORKSHOP_ROLES)
WORKSHOP_ROLE_MAP = {
    "Мойка": {"Мойка", "Универсал"},
    "Химчистка": {"Химчистка", "Кузовные работы", "Универсал"},
    "Полировка": {"Полировка", "Кузовные работы", "Универсал"},
    "Оклейка": {"Оклейка", "Кузовные работы", "Универсал"},
    "Интерьер": {"Интерьер", "Тюнинг/Интерьер", "Универсал"},
    "Оборудование": {"Оборудование", "Кузовные работы", "Универсал"},
}


def _split_roles(role: str | None) -> list[str]:
    if not role:
        return []
    return [p.strip() for p in role.split(",") if p.strip()]


def workshop_master_ids(token: str) -> dict[str, list[int]]:
    masters = req("GET", "/crm/masters", token=token) or []
    by_ws: dict[str, list[int]] = {k: [] for k in WORKSHOP_ROLE_MAP}
    for m in masters:
        if not m.get("is_active", True):
            continue
        mid = int(m["id"])
        roles = _split_roles(m.get("role"))
        for ws, allowed in WORKSHOP_ROLE_MAP.items():
            if any(r == ws or r in allowed for r in roles):
                by_ws[ws].append(mid)
    return by_ws


SEED_PHONES = {
    "9001112233",
    "9002223344",
    "9003334455",
    "9004445566",
    "9005556677",
    "9006667788",
    "9007778899",
    "9008889900",
    "9009990011",
    "9011112233",
}


def cleanup_old(token: str) -> int:
    deleted = 0
    orders = req("GET", "/crm/orders", token=token) or []
    seed_tails = {p[-10:] for p in SEED_PHONES}

    for o in orders:
        oid = int(o["id"])
        client = o.get("client") or {}
        phone = "".join(ch for ch in (client.get("phone") or "") if ch.isdigit())[-10:]
        due = (o.get("due_date") or "")[:10]
        if phone in seed_tails and due.startswith("2026-08-"):
            req("DELETE", f"/crm/orders/{oid}", token=token)
            deleted += 1
            continue
        if oid in OLD_ORDER_IDS and due.startswith("2026-08-"):
            req("DELETE", f"/crm/orders/{oid}", token=token)
            deleted += 1
    return deleted


def main() -> None:
    login = req("POST", "/auth/login", body={"login": LOGIN, "password": PASSWORD})
    token = login["access_token"]
    deleted = cleanup_old(token)
    print(f"deleted old demo orders: {deleted}")

    admin_id = pick_admin_id(token)
    ws_masters = workshop_master_ids(token)
    created = []
    warned_ws: set[str] = set()

    for spec in ORDERS:
        cname, phone = spec["client"]
        make, plate, cat = spec["car"]
        car_cls = int(cat)
        day = spec["day"]
        works = spec["works"]

        starts = [(h, m) for _, h, m, _, _ in works]
        ends = [(h, m) for _, _, _, h, m in works]
        sh, sm = min(starts)
        eh, em = max(ends)

        client_id = find_or_create_client(token, cname, phone)
        car_id, client_id = find_or_create_car(token, client_id, make, plate, cat)

        items = []
        for wname, whs, wms, whe, wme in works:
            ws = workshop_of(wname)
            mids = ws_masters.get(ws) or []
            if not mids:
                warned_ws.add(ws)
            mid_str = ",".join(str(x) for x in mids[:1]) if mids else ""
            items.append(
                {
                    "name": wname,
                    "price": price_of(wname, car_cls),
                    "workshop": ws,
                    "start_time": iso(day, whs, wms),
                    "end_time": iso(day, whe, wme),
                    "master_ids": mid_str,
                }
            )

        body = {
            "client_id": client_id,
            "car_id": car_id,
            "status": spec["status"],
            "notes": ", ".join(w[0] for w in works),
            "due_date": day,
            "start_time": iso(day, sh, sm),
            "end_time": iso(day, eh, em),
            "end_date": day,
            # Админ на заказе — ок; на работы цеха админа не ставим.
            "master_ids": [admin_id] if admin_id else [],
            "receptionist_id": admin_id,
            "items": items,
        }
        order = req("POST", "/crm/orders", token=token, body=body)
        oid = int(order["id"])

        order = req("GET", f"/crm/orders/{oid}", token=token)
        by_name = {w[0]: w for w in works}
        for it in order.get("items") or []:
            iid = it.get("id")
            spec_w = by_name.get(it.get("name") or "")
            if not iid or not spec_w:
                continue
            _, whs, wms, whe, wme = spec_w
            ws = it.get("workshop") or workshop_of(it.get("name") or "")
            mids = ws_masters.get(ws) or []
            mid_str = ",".join(str(x) for x in mids[:1]) if mids else ""
            req(
                "PATCH",
                f"/crm/orders/{oid}/items/{iid}",
                token=token,
                body={
                    "start_time": iso(day, whs, wms),
                    "end_time": iso(day, whe, wme),
                    "workshop": ws,
                    "master_ids": mid_str,
                },
            )

        shop = spec.get("shop")
        if shop:
            target_ws = "Мойка"
            for w in works:
                ws = workshop_of(w[0])
                if ws != "Мойка":
                    target_ws = ws
                    break
            req(
                "POST",
                f"/crm/orders/{oid}/events",
                token=token,
                body={"event_text": f"Для цеха «{target_ws}»: {shop} · {works[-1][0]}"},
            )

        created.append(
            {
                "id": oid,
                "day": day,
                "status": spec["status"],
                "client": cname,
                "window": f"{sh:02d}:{sm:02d}-{eh:02d}:{em:02d}",
                "works": [f"{n} {hs:02d}:{ms:02d}-{he:02d}:{me:02d}" for n, hs, ms, he, me in works],
            }
        )
        print(f"OK #{oid} {day} {spec['status']}: {cname} {sh:02d}:{sm:02d}-{eh:02d}:{em:02d}")

    if warned_ws:
        print(
            "WARN: нет мастера на цеха (работы без назначения): "
            + ", ".join(sorted(warned_ws))
        )
    print(json.dumps({"created": len(created), "orders": created, "missing_workshops": sorted(warned_ws)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
