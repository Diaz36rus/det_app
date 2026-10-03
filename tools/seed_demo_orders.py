# -*- coding: utf-8 -*-
"""Reseed ~15 busy overlapping demo orders with R1–R7 enrichment.

Deletes previous seed orders (by seed phones + ±21 day window around today)
and recreates with:
  lead_source, deposit, inventory/unit_cost, recipes, film rolls,
  wrap films, payroll, partial payments, warranties, studio leads.

Usage:
  python tools/seed_demo_orders.py
  SEED_API=https://api.det-app.ru SEED_LOGIN=... SEED_PASSWORD=... python tools/seed_demo_orders.py
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta, timezone

BASE = os.environ.get("SEED_API", "https://api.det-app.ru").rstrip("/")
LOGIN = os.environ.get("SEED_LOGIN", "owner@demo.det-app.ru")
PASSWORD = os.environ.get("SEED_PASSWORD", "DetAppAdmin2026!")

MSK = timezone(timedelta(hours=3))
TODAY = datetime.now(MSK).date()

# Previous seed ids (best-effort cleanup)
OLD_ORDER_IDS = list(range(92, 400))

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


def day_offset(n: int) -> str:
    return (TODAY + timedelta(days=n)).isoformat()


def req(
    method: str,
    path: str,
    token: str | None = None,
    body: dict | None = None,
    *,
    soft: bool = False,
):
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
        if soft:
            print(f"  soft-fail {method} {path} -> {e.code}: {err[:200]}")
            return None
        if method == "DELETE" and e.code in (404, 400):
            return None
        raise SystemExit(f"{method} {path} -> {e.code}: {err}") from e


def iso(day: str, hour: int, minute: int = 0) -> str:
    return f"{day}T{hour:02d}:{minute:02d}:00"


# Enrichment keys per order:
#   lead_source, deposit, pay ("full"|"partial"|None), method, pay_frac,
#   done_workshops (list|None → auto by status), wrap_meters, warranty
ORDERS = [
    # --- сегодня−3 ---
    {
        "client": ("Роман Алексеев", "9031012233"),
        "car": ("Toyota Camry", "A781BC777", "1"),
        "day": day_offset(-3),
        "status": "Мойка",
        "lead_source": "Сарафан",
        "deposit": 0,
        "pay": "partial",
        "pay_frac": 0.5,
        "method": "Наличные",
        "works": [
            ("Комплексная мойка", 9, 0, 10, 30),
            ("Уборка багажника", 10, 0, 11, 0),
        ],
        "shop": None,
    },
    {
        "client": ("Кирилл Воронов", "9031023344"),
        "car": ("Volkswagen Tiguan", "K512OP136", "2"),
        "day": day_offset(-3),
        "status": "Мойка",
        "lead_source": "Avito",
        "deposit": 0,
        "pay": None,
        "works": [
            ("Экспресс-мойка", 9, 45, 10, 45),
            ("Уборка салона", 10, 30, 12, 0),
        ],
        "shop": None,
    },
    {
        "client": ("Алина Петрова", "9031034455"),
        "car": ("BMW X3", "E678KX777", "3"),
        "day": day_offset(-3),
        "status": "Химчистка",
        "lead_source": "Telegram",
        "deposit": 5000,
        "pay": "partial",
        "pay_frac": 0.35,
        "method": "Карта",
        "works": [
            ("Комплексная мойка", 9, 30, 11, 0),
            ("Химчистка салона", 10, 30, 17, 0),
            ("Химчистка дисков", 14, 0, 16, 30),
        ],
        "shop": "Светлый салон — аккуратно с химией",
    },
    {
        "client": ("Денис Козлов", "9031045566"),
        "car": ("Mercedes-Benz GLC", "M340TY777", "2"),
        "day": day_offset(-3),
        "status": "Полировка",
        "lead_source": "Повтор",
        "deposit": 0,
        "pay": "partial",
        "pay_frac": 0.4,
        "method": "Перевод",
        "works": [
            ("Легкая полировка", 11, 0, 15, 30),
            ("Силант на кузов", 15, 0, 16, 30),
            ("Krytex лобовое стекло", 16, 0, 17, 30),
        ],
        "shop": "Без жёсткого абразива на капоте",
        "warranty": {"kind": "Керамика/силант", "title": "Силант + Krytex", "months": 6},
    },
    # --- сегодня−2 ---
    {
        "client": ("Никита Ершов", "9031056677"),
        "car": ("Kia Sportage", "P218KT777", "2"),
        "day": day_offset(-2),
        "status": "Оклейка",
        "lead_source": "Сайт",
        "deposit": 3000,
        "pay": "partial",
        "pay_frac": 0.5,
        "method": "Карта",
        "works": [
            ("Комплексная мойка", 10, 0, 11, 30),
            ("Тонировка · Заднее стекло", 11, 0, 15, 0),
        ],
        "shop": "Не повредить обогрев",
        "wrap_meters": 4.5,
    },
    {
        "client": ("Юлия Савельева", "9031067788"),
        "car": ("Hyundai Creta", "O903PC777", "1"),
        "day": day_offset(-2),
        "status": "Принят в работу",
        "lead_source": "Avito",
        "deposit": 1000,
        "pay": "partial",
        "pay_frac": 0.3,
        "method": "Наличные",
        "works": [
            ("Мойка кузова", 11, 30, 13, 0),
            ("Быстрая мокрая керамика", 12, 30, 14, 0),
        ],
        "shop": None,
    },
    {
        "client": ("Владислав Тихонов", "9031078899"),
        "car": ("Audi Q5", "T661YB777", "3"),
        "day": day_offset(-2),
        "status": "Полировка",
        "lead_source": "Сарафан",
        "deposit": 10000,
        "pay": "partial",
        "pay_frac": 0.45,
        "method": "Перевод",
        "works": [
            ("Восстановительная полировка", 9, 0, 17, 0),
            ("Керамика на кузов (1 слой)", 16, 0, 18, 30),
        ],
        "shop": "Царапины на заднем крыле",
        "warranty": {"kind": "Керамика", "title": "Керамика 1 слой", "months": 12},
    },
    # --- сегодня−1 ---
    {
        "client": ("Глеб Мартынов", "9031089900"),
        "car": ("Lexus NX", "B447KE777", "3"),
        "day": day_offset(-1),
        "status": "Оклейка",
        "lead_source": "Telegram",
        "deposit": 5000,
        "pay": "partial",
        "pay_frac": 0.4,
        "method": "Карта",
        "works": [
            ("Комплексная мойка", 9, 0, 10, 30),
            ("Оклейка · Капот", 10, 0, 14, 0),
            ("Оклейка · Зеркала", 13, 0, 15, 30),
        ],
        "shop": "Только матовая плёнка",
        "wrap_meters": 8.0,
        "warranty": {"kind": "PPF", "title": "Капот + зеркала PPF", "months": 24},
    },
    {
        "client": ("Полина Крылова", "9031090011"),
        "car": ("Skoda Octavia", "C678XH777", "2"),
        "day": day_offset(-1),
        "status": "Интерьер",
        "lead_source": "Avito",
        "deposit": 2000,
        "pay": None,
        "works": [
            ("Экспресс-мойка", 11, 0, 12, 0),
            ("Уборка салона", 11, 30, 13, 30),
            ("Химчистка 1го сидения (Ткань)", 12, 30, 14, 30),
        ],
        "shop": "Детское кресло не снимать",
    },
    # --- сегодня: живая доска ---
    {
        "client": ("Антон Гришин", "9031101122"),
        "car": ("Mazda CX-5", "H319KM777", "2"),
        "day": day_offset(0),
        "status": "Мойка",
        "lead_source": "Повтор",
        "deposit": 0,
        "pay": "partial",
        "pay_frac": 0.5,
        "method": "Наличные",
        "works": [
            ("Комплексная мойка", 9, 0, 10, 30),
            ("Уборка салона", 10, 0, 11, 30),
            ("Химчистка локально", 11, 0, 12, 0),
        ],
        "shop": "Пятно на заднем ряду",
    },
    {
        "client": ("Марина Белова", "9031112233"),
        "car": ("Chery Tiggo 7 Pro", "A920BE777", "2"),
        "day": day_offset(0),
        "status": "Химчистка",
        "lead_source": "Сарафан",
        "deposit": 4000,
        "pay": "partial",
        "pay_frac": 0.3,
        "method": "Карта",
        "works": [
            ("Мойка кузова", 9, 30, 11, 0),
            ("Детейлинг уборка салона", 10, 30, 16, 0),
            ("Химчистка двигателя", 14, 0, 16, 30),
        ],
        "shop": "Клиент ждёт к 17:00",
    },
    {
        "client": ("Егор Зайцев", "9031123344"),
        "car": ("Haval Jolion", "K155OP777", "1"),
        "day": day_offset(0),
        "status": "Принят в работу",
        "lead_source": "Telegram",
        "deposit": 2000,
        "pay": "partial",
        "pay_frac": 0.35,
        "method": "Перевод",
        "works": [
            ("Экспресс-мойка", 12, 0, 13, 0),
            ("Быстрая сухая керамика", 12, 45, 14, 15),
            ("Krytex лобовое стекло", 14, 0, 15, 0),
        ],
        "shop": None,
        "warranty": {"kind": "Керамика", "title": "Сухая керамика + Krytex", "months": 6},
    },
    {
        "client": ("София Миронова", "9031134455"),
        "car": ("Exeed TXL", "E404TX777", "3"),
        "day": day_offset(0),
        "status": "Предварительная запись",
        "lead_source": "Сайт",
        "deposit": 2500,
        "pay": "partial",
        "pay_frac": 0.2,
        "method": "Карта",
        "works": [
            ("Комплексная мойка", 15, 0, 16, 30),
            ("Уборка салона", 16, 0, 17, 30),
        ],
        "shop": "Приедет после 14:30",
    },
    # --- завтра / послезавтра ---
    {
        "client": ("Вера Романова", "9031145566"),
        "car": ("Geely Coolray", "M277TY777", "1"),
        "day": day_offset(1),
        "status": "Предварительная запись",
        "lead_source": "Сайт",
        "deposit": 3500,
        "pay": "partial",
        "pay_frac": 0.25,
        "method": "Карта",
        "works": [
            ("Комплексная мойка", 10, 0, 11, 30),
            ("Тонировка · Лобовое стекло", 11, 0, 14, 0),
            ("Тонировка · Заднее стекло", 13, 30, 16, 30),
        ],
        "shop": "Плёнка 50% сзади",
        "wrap_meters": 6.0,
    },
    {
        "client": ("Игорь Кузьмин", "9031156677"),
        "car": ("Toyota Land Cruiser Prado", "T088YB777", "4"),
        "day": day_offset(2),
        "status": "Предварительная запись",
        "lead_source": "Сарафан",
        "deposit": 15000,
        "pay": "partial",
        "pay_frac": 0.2,
        "method": "Перевод",
        "works": [
            ("Комплексная мойка", 9, 0, 11, 0),
            ("Восстановительная полировка", 10, 0, 17, 0),
            ("Керамика на кузов (2 слоя)", 16, 0, 19, 0),
        ],
        "shop": "Полный кузов, капот уже в керамике",
        "warranty": {"kind": "Керамика", "title": "Керамика 2 слоя", "months": 24},
    },
]


INVENTORY_SEED = [
    # name, category, qty, unit, min_qty, unit_cost, meters_per_roll
    ("Шампунь активная пена", "Мойка", 48, "л", 8, 180, 0),
    ("Очиститель дисков", "Мойка", 12, "л", 2, 420, 0),
    ("Пенный очиститель салона", "Химчистка", 20, "л", 4, 350, 0),
    ("Пятновыводитель ткань", "Химчистка", 8, "л", 2, 890, 0),
    ("Паста полировальная cut", "Полировка", 6, "шт", 2, 2200, 0),
    ("Паста полировальная finish", "Полировка", 8, "шт", 2, 1900, 0),
    ("Силант кузов", "Полировка", 10, "шт", 2, 1400, 0),
    ("Керамика Krytex body", "Полировка", 5, "шт", 1, 8500, 0),
    ("Krytex стекло", "Полировка", 7, "шт", 2, 3200, 0),
    ("Плёнка тонировка 50%", "Плёнка тонировка", 0, "рул", 1, 450, 15),
    ("Плёнка PPF матовая", "Плёнка оклейка", 0, "рул", 1, 980, 15),
    ("Микрофибра пачка", "Расходники", 40, "шт", 10, 45, 0),
]

RECIPES = [
    # service_name, inventory_name, qty
    ("Комплексная мойка", "Шампунь активная пена", 0.4),
    ("Комплексная мойка", "Микрофибра пачка", 1),
    ("Экспресс-мойка", "Шампунь активная пена", 0.2),
    ("Мойка кузова", "Шампунь активная пена", 0.3),
    ("Химчистка салона", "Пенный очиститель салона", 1.5),
    ("Химчистка салона", "Пятновыводитель ткань", 0.3),
    ("Химчистка локально", "Пятновыводитель ткань", 0.15),
    ("Химчистка 1го сидения (Ткань)", "Пенный очиститель салона", 0.4),
    ("Химчистка дисков", "Очиститель дисков", 0.5),
    ("Химчистка двигателя", "Пенный очиститель салона", 0.8),
    ("Детейлинг уборка салона", "Пенный очиститель салона", 1.0),
    ("Детейлинг уборка салона", "Микрофибра пачка", 2),
    ("Легкая полировка", "Паста полировальная finish", 1),
    ("Восстановительная полировка", "Паста полировальная cut", 1),
    ("Восстановительная полировка", "Паста полировальная finish", 1),
    ("Силант на кузов", "Силант кузов", 1),
    ("Керамика на кузов (1 слой)", "Керамика Krytex body", 1),
    ("Керамика на кузов (2 слоя)", "Керамика Krytex body", 2),
    ("Быстрая сухая керамика", "Керамика Krytex body", 0.3),
    ("Быстрая мокрая керамика", "Силант кузов", 0.5),
    ("Krytex лобовое стекло", "Krytex стекло", 0.5),
    ("Krytex передняя полусфера", "Krytex стекло", 0.8),
]

PAYROLL_RULES = [
    ("Мойка", "", "percent", 25, "Мойка 25%"),
    ("Химчистка", "", "percent", 30, "Хим 30%"),
    ("Полировка", "", "percent", 35, "Полировка 35%"),
    ("Оклейка", "", "percent", 40, "Оклейка 40%"),
    ("Интерьер", "", "percent", 28, "Интерьер 28%"),
]

FILM_ROLLS = [
    ("Плёнка тонировка 50%", "TINT-A1", 15),
    ("Плёнка тонировка 50%", "TINT-A2", 12),
    ("Плёнка PPF матовая", "PPF-M1", 15),
    ("Плёнка PPF матовая", "PPF-M2", 10),
]

LEADS = [
    ("Кирилл Новиков", "9021112233", "Volvo XC60", "Сайт", "Хочет керамику на кузов, перезвонить вечером"),
    ("Дарья Орлова", "9022223344", "Renault Arkana", "Avito", "Тонировка + мойка на выходных"),
    ("Илья Семёнов", "9023334455", "Skoda Rapid", "Telegram", "Интересует оклейка капота PPF"),
    ("Екатерина Плотникова", "9024445566", "BMW 3", "Сарафан", "Химчистка салона, есть ребёнок"),
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
    table = str.maketrans("АВЕКМНОРСТУХавекмнорстух", "ABEKMHOPCTYXABEKMHOPCTYX")
    return (p or "").upper().replace(" ", "").translate(table)


def plate_latin(p: str) -> str:
    return plate_key(p)


def find_or_create_car(
    token: str, client_id: int, make: str, plate: str, category: str
) -> tuple[int, int]:
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
            "plate": plate_latin(plate),
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


WORKSHOP_ROLE_MAP = {
    "Мойка": {"Мойка", "Универсал"},
    "Химчистка": {"Химчистка", "Кузовные работы", "Универсал"},
    "Полировка": {"Полировка", "Кузовные работы", "Универсал"},
    "Кузовные работы": {"Кузовные работы", "Универсал"},
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
    "9012223344",
    "9013334455",
    "9014445566",
    "9015556677",
    "9016667788",
}


def cleanup_old(token: str) -> int:
    deleted = 0
    orders = req("GET", "/crm/orders", token=token) or []
    seed_tails = {p[-10:] for p in SEED_PHONES}
    lo = (TODAY - timedelta(days=30)).isoformat()
    hi = (TODAY + timedelta(days=21)).isoformat()
    # Also wipe legacy Aug–Sep 2026 demo window
    legacy_lo, legacy_hi = "2026-08-01", "2026-09-15"

    for o in orders:
        oid = int(o["id"])
        client = o.get("client") or {}
        phone = "".join(ch for ch in (client.get("phone") or "") if ch.isdigit())[-10:]
        due = (o.get("due_date") or "")[:10]
        in_window = (lo <= due <= hi) or (legacy_lo <= due <= legacy_hi)
        if phone in seed_tails and in_window:
            req("DELETE", f"/crm/orders/{oid}", token=token)
            deleted += 1
            continue
        if oid in OLD_ORDER_IDS and in_window:
            req("DELETE", f"/crm/orders/{oid}", token=token)
            deleted += 1
    return deleted


def ensure_inventory(token: str) -> dict[str, int]:
    """Create/top-up stock; return name → id."""
    existing = req("GET", "/crm/inventory", token=token) or []
    by_name = {(r.get("name") or "").strip(): r for r in existing}
    ids: dict[str, int] = {}

    for name, category, qty, unit, min_qty, unit_cost, mpr in INVENTORY_SEED:
        row = by_name.get(name)
        if row is None:
            row = req(
                "POST",
                "/crm/inventory",
                token=token,
                body={
                    "name": name,
                    "quantity": qty,
                    "unit": unit,
                    "category": category,
                    "min_qty": min_qty,
                    "meters_per_roll": mpr,
                    "unit_cost": unit_cost,
                },
            )
        else:
            patch: dict = {}
            if float(row.get("unit_cost") or 0) != float(unit_cost):
                patch["unit_cost"] = unit_cost
            if float(row.get("min_qty") or 0) != float(min_qty):
                patch["min_qty"] = min_qty
            if mpr and float(row.get("meters_per_roll") or 0) != float(mpr):
                patch["meters_per_roll"] = mpr
            if (row.get("unit") or "") != unit:
                patch["unit"] = unit
            if (row.get("category") or "") != category:
                patch["category"] = category
            if patch:
                row = req("PATCH", f"/crm/inventory/{row['id']}", token=token, body=patch) or row

        iid = int(row["id"])
        ids[name] = iid

        # Top up non-roll stock if low
        if unit not in {"рул", "рулон", "рулоны"}:
            cur = float(row.get("quantity") or 0)
            if cur < qty:
                req(
                    "POST",
                    "/crm/inventory/moves",
                    token=token,
                    body={
                        "item_id": iid,
                        "delta": qty - cur,
                        "reason": "purchase",
                        "note": "seed top-up",
                    },
                    soft=True,
                )
    return ids


def ensure_film_rolls(token: str, inv_ids: dict[str, int]) -> dict[str, list[dict]]:
    """Ensure demo rolls; return inventory_name → rolls list."""
    out: dict[str, list[dict]] = {}
    for inv_name, roll_no, meters in FILM_ROLLS:
        iid = inv_ids.get(inv_name)
        if not iid:
            continue
        rolls = req("GET", f"/crm/film-rolls?inventory_id={iid}", token=token) or []
        by_no = {(r.get("roll_number") or "").upper(): r for r in rolls}
        row = by_no.get(roll_no.upper())
        if row is None:
            row = req(
                "POST",
                "/crm/film-rolls",
                token=token,
                body={"inventory_id": iid, "roll_number": roll_no, "meters_initial": meters},
                soft=True,
            )
            if row is None:
                rolls = req("GET", f"/crm/film-rolls?inventory_id={iid}", token=token) or []
                by_no = {(r.get("roll_number") or "").upper(): r for r in rolls}
                row = by_no.get(roll_no.upper())
        if row:
            out.setdefault(inv_name, []).append(row)
    return out


def ensure_recipes(token: str, inv_ids: dict[str, int]) -> None:
    for service, inv_name, qty in RECIPES:
        iid = inv_ids.get(inv_name)
        if not iid:
            continue
        req(
            "PUT",
            "/crm/recipes",
            token=token,
            body={"service_name": service, "inventory_id": iid, "qty": qty},
            soft=True,
        )


def ensure_payroll_rules(token: str) -> None:
    existing = req("GET", "/crm/payroll-rules", token=token, soft=True) or []
    keys = {
        ((r.get("workshop") or "").strip(), (r.get("service_name") or "").strip())
        for r in existing
        if r.get("is_active", True)
    }
    for workshop, service, mode, value, label in PAYROLL_RULES:
        if (workshop, service) in keys:
            continue
        req(
            "POST",
            "/crm/payroll-rules",
            token=token,
            body={
                "workshop": workshop,
                "service_name": service,
                "mode": mode,
                "value": value,
                "label": label,
                "is_active": True,
            },
            soft=True,
        )


def ensure_cash_shift(token: str) -> bool:
    cur = req("GET", "/cash/shifts/current", token=token, soft=True)
    if cur and cur.get("id"):
        return True
    opened = req("POST", "/cash/shifts/open", token=token, body={"note": "seed demo"}, soft=True)
    return bool(opened and opened.get("id"))


def auto_done_workshops(status: str) -> set[str]:
    """Which workshops' items to mark done for a lively board."""
    s = (status or "").strip()
    if s == "Предварительная запись":
        return set()
    if s == "Мойка":
        return {"Мойка"}
    if s == "Химчистка":
        return {"Мойка", "Интерьер"}
    if s == "Полировка":
        return {"Мойка", "Полировка"}
    if s == "Оклейка":
        return {"Мойка", "Оклейка"}
    if s == "Принят в работу":
        return {"Мойка"}
    return {"Мойка"}


def order_total(items: list[dict]) -> float:
    return sum(float(it.get("price") or 0) for it in items)


def set_payroll_for_order(
    token: str, oid: int, items: list[dict], ws_masters: dict[str, list[int]]
) -> None:
    by_ws: dict[str, float] = {}
    for it in items:
        if not it.get("is_done"):
            continue
        ws = (it.get("workshop") or workshop_of(it.get("name") or "")).strip()
        by_ws[ws] = by_ws.get(ws, 0.0) + float(it.get("price") or 0)

    # Rough percent by workshop (mirrors seed rules)
    pct = {
        "Мойка": 0.25,
        "Химчистка": 0.30,
        "Полировка": 0.35,
        "Оклейка": 0.40,
        "Интерьер": 0.28,
    }
    for ws, revenue in by_ws.items():
        mids = ws_masters.get(ws) or []
        if not mids or revenue <= 0:
            continue
        amount = round(revenue * pct.get(ws, 0.3), 0)
        if amount <= 0:
            continue
        req(
            "PUT",
            f"/crm/orders/{oid}/payroll",
            token=token,
            body={"workshop": ws, "lines": [{"master_id": mids[0], "amount": amount}]},
            soft=True,
        )


def attach_wrap(
    token: str,
    oid: str | int,
    meters: float,
    film_rolls: dict[str, list[dict]],
    inv_ids: dict[str, int],
    prefer_ppf: bool,
) -> None:
    if meters <= 0:
        return
    inv_name = "Плёнка PPF матовая" if prefer_ppf else "Плёнка тонировка 50%"
    rolls = film_rolls.get(inv_name) or []
    film_id = inv_ids.get(inv_name)
    if not film_id or not rolls:
        # fallback
        for n, rs in film_rolls.items():
            if rs:
                inv_name, rolls = n, rs
                film_id = inv_ids.get(n)
                break
    if not film_id or not rolls:
        return
    roll = max(rolls, key=lambda r: float(r.get("meters_left") or 0))
    req(
        "PUT",
        f"/crm/orders/{oid}/wrap-films",
        token=token,
        body={
            "films": [
                {
                    "film_id": film_id,
                    "roll_id": int(roll["id"]),
                    "meters": float(meters),
                }
            ]
        },
        soft=True,
    )


def create_warranty(token: str, car_id: int, order_id: int, day: str, spec: dict) -> None:
    months = int(spec.get("months") or 12)
    start = day
    try:
        end = (date.fromisoformat(day) + timedelta(days=30 * months)).isoformat()
    except ValueError:
        end = day
    req(
        "POST",
        "/crm/warranties",
        token=token,
        body={
            "car_id": car_id,
            "order_id": order_id,
            "kind": spec.get("kind") or "Керамика",
            "title": spec.get("title") or "Гарантия",
            "batch": f"SEED-{order_id}",
            "started_at": start,
            "months": months,
            "ends_at": end,
            "note": "Демо-гарантия из seed",
            "reminder_sent": False,
        },
        soft=True,
    )


def seed_leads(token: str) -> int:
    existing = req("GET", "/crm/leads", token=token, soft=True)
    if existing is None:
        print("  skip leads: /crm/leads not on this API yet")
        return 0
    phones = {
        "".join(ch for ch in (l.get("phone") or "") if ch.isdigit())[-10:] for l in existing
    }
    n = 0
    for name, phone, car, source, note in LEADS:
        digits = "".join(ch for ch in phone if ch.isdigit())[-10:]
        if digits in phones:
            continue
        row = req(
            "POST",
            "/crm/leads",
            token=token,
            body={
                "name": name,
                "phone": phone,
                "car_label": car,
                "lead_source": source,
                "note": note,
                "status": "new",
            },
            soft=True,
        )
        if row:
            n += 1
    return n


def main() -> None:
    print(f"API={BASE} today={TODAY.isoformat()} orders={len(ORDERS)}")
    login = req("POST", "/auth/login", body={"login": LOGIN, "password": PASSWORD})
    token = login["access_token"]

    deleted = cleanup_old(token)
    print(f"deleted old demo orders: {deleted}")

    print("bootstrap: inventory / rolls / recipes / payroll / cash…")
    inv_ids = ensure_inventory(token)
    film_rolls = ensure_film_rolls(token, inv_ids)
    ensure_recipes(token, inv_ids)
    ensure_payroll_rules(token)
    cash_ok = ensure_cash_shift(token)
    print(f"  inventory={len(inv_ids)} film_sets={len(film_rolls)} cash_shift={cash_ok}")

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

        source = (spec.get("lead_source") or "").strip()
        deposit = float(spec.get("deposit") or 0)
        note_bits = [", ".join(w[0] for w in works)]
        if source:
            note_bits.append(f"Источник: {source}")
        if deposit > 0:
            note_bits.append(f"Депозит: {int(deposit)} ₽")
        body = {
            "client_id": client_id,
            "car_id": car_id,
            "status": spec["status"],
            "notes": " · ".join(note_bits),
            "due_date": day,
            "start_time": iso(day, sh, sm),
            "end_time": iso(day, eh, em),
            "end_date": day,
            "master_ids": [admin_id] if admin_id else [],
            "receptionist_id": admin_id,
            # Новые поля — на старом облаке игнорируются; после деплоя API подхватятся.
            "lead_source": source,
            "deposit_required": deposit,
            "items": items,
        }
        order = req("POST", "/crm/orders", token=token, body=body)
        oid = int(order["id"])

        # Ensure lead_source / deposit (когда API уже умеет)
        req(
            "PATCH",
            f"/crm/orders/{oid}",
            token=token,
            body={
                "lead_source": source,
                "deposit_required": deposit,
                "notes": " · ".join(note_bits),
            },
            soft=True,
        )

        order = req("GET", f"/crm/orders/{oid}", token=token)
        by_name = {w[0]: w for w in works}
        done_ws = set(spec.get("done_workshops") or auto_done_workshops(spec["status"]))

        for it in order.get("items") or []:
            iid = it.get("id")
            spec_w = by_name.get(it.get("name") or "")
            if not iid or not spec_w:
                continue
            _, whs, wms, whe, wme = spec_w
            ws = it.get("workshop") or workshop_of(it.get("name") or "")
            mids = ws_masters.get(ws) or []
            mid_str = ",".join(str(x) for x in mids[:1]) if mids else ""
            is_done = ws in done_ws
            req(
                "PATCH",
                f"/crm/orders/{oid}/items/{iid}",
                token=token,
                body={
                    "start_time": iso(day, whs, wms),
                    "end_time": iso(day, whe, wme),
                    "workshop": ws,
                    "master_ids": mid_str,
                    "is_done": is_done,
                },
            )
            if is_done:
                req(
                    "POST",
                    "/crm/recipes/deduct",
                    token=token,
                    body={
                        "service_name": it.get("name") or "",
                        "order_id": oid,
                        "order_item_id": iid,
                    },
                    soft=True,
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

        # Refresh items for payroll / total
        order = req("GET", f"/crm/orders/{oid}", token=token) or order
        items_out = order.get("items") or []
        set_payroll_for_order(token, oid, items_out, ws_masters)

        wrap_m = float(spec.get("wrap_meters") or 0)
        if wrap_m > 0:
            prefer_ppf = any("оклей" in w[0].lower() for w in works)
            attach_wrap(token, oid, wrap_m, film_rolls, inv_ids, prefer_ppf)

        if spec.get("warranty") and any(
            x in " ".join(w[0].lower() for w in works)
            for x in ("керамик", "krytex", "силант", "оклей")
        ):
            create_warranty(token, car_id, oid, day, spec["warranty"])

        pay = spec.get("pay")
        if cash_ok and pay:
            total = order_total(items_out)
            frac = float(spec.get("pay_frac") or (1.0 if pay == "full" else 0.4))
            amount = round(total * frac, 0)
            if amount > 0:
                req(
                    "POST",
                    "/cash/payments",
                    token=token,
                    body={
                        "order_id": oid,
                        "amount": amount,
                        "method": spec.get("method") or "Наличные",
                    },
                    soft=True,
                )

        created.append(
            {
                "id": oid,
                "day": day,
                "status": spec["status"],
                "source": spec.get("lead_source"),
                "deposit": spec.get("deposit") or 0,
                "client": cname,
                "window": f"{sh:02d}:{sm:02d}-{eh:02d}:{em:02d}",
                "works": [f"{n} {hs:02d}:{ms:02d}-{he:02d}:{me:02d}" for n, hs, ms, he, me in works],
            }
        )
        print(
            f"OK #{oid} {day} {spec['status']} [{spec.get('lead_source')}] "
            f"dep={spec.get('deposit') or 0}: {cname} {sh:02d}:{sm:02d}-{eh:02d}:{em:02d}"
        )

    leads_n = seed_leads(token)
    print(f"leads created/kept: +{leads_n}")

    if warned_ws:
        print(
            "WARN: нет мастера на цеха (работы без назначения): "
            + ", ".join(sorted(warned_ws))
        )
    print(
        json.dumps(
            {
                "created": len(created),
                "orders": created,
                "missing_workshops": sorted(warned_ws),
                "today": TODAY.isoformat(),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
