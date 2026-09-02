# -*- coding: utf-8 -*-
"""Showcase seed for «Детейлинг Ателье» — 3 days, screenshot-ready.

Days: 30.08 (2–3 выдано) · 31.08 (живая доска) · 01.09 (предзаписи).
Masters on order header = цех, not admin. Cash today has payments + expenses.

  PYTHONPATH=/app python /tmp/seed_studio_busy.py
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import select

from app.db import SessionLocal
from app.models import (
    Branch,
    CashFlow,
    CashPayment,
    CashShift,
    CashShiftBalance,
    Company,
    CrmCar,
    CrmClient,
    CrmMaster,
    CrmOrder,
    CrmOrderEvent,
    CrmOrderItem,
    CrmOrderMaster,
    User,
)
from app.routers.cash import ensure_registers

COMPANY_SLUG = "deteyling-atele"
OWNER_EMAIL = "igorkarikh6@gmail.com"
MSK = timezone(timedelta(hours=3))

PRICES = {
    "Экспресс-мойка": {1: 800, 2: 1000, 3: 1200, 4: 1400},
    "Мойка кузова": {1: 1400, 2: 1800, 3: 2200, 4: 2600},
    "Комплексная мойка": {1: 2500, 2: 3000, 3: 3500, 4: 4000},
    "Уборка багажника": {"fp": 200},
    "Уборка салона": {1: 1100, 2: 1200, 3: 1300, 4: 1400},
    "Химчистка салона": {1: 20000, 2: 23000, 3: 26000, 4: 29000},
    "Химчистка 1го сидения (Ткань)": {"fp": 2500},
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
    "Тонировка · Заднее стекло": {"fp": 5500},
    "Тонировка · Лобовое стекло": {"fp": 4500},
    "Оклейка · Капот": {"fp": 8000},
    "Оклейка · Зеркала": {"fp": 3500},
}

MASTERS = [
    ("Евгения Цурикова", "Администратор"),
    ("Сергей Мойкин", "Мойка"),
    ("Павел Раков", "Мойка"),
    ("Анна Химцова", "Химчистка"),
    ("Дмитрий Полиров", "Полировка"),
    ("Илья Плёнкин", "Оклейка"),
    ("Максим Универсал", "Универсал"),
    ("Наталья Салон", "Интерьер"),
]

SEED_PHONE_PREFIXES = ("900", "901", "902", "903", "904")

# day, status, client, phone, car, plate, cls, works, shop,
# pay_method|None, partial_pay|(method, amount)|None, header_ws|None
ORDERS = [
    # --- вчера: ровно 3 выдано (касса/история), оплаты сегодня утром тоже ок —
    # оплаты ставим в день выдачи; плюс дублируем часть приходов «сегодня» через partial на живых
    ("2026-08-30", "Выдан", "Игорь Ковалёв", "9001112233", "Toyota Camry", "A123BC777", 1,
     [("Комплексная мойка", 10, 0, 11, 30), ("Уборка салона", 11, 0, 12, 30)], None,
     "Наличные", None, "Мойка"),
    ("2026-08-30", "Выдан", "Анна Смирнова", "9002223344", "BMW X5", "E456KX777", 3,
     [("Химчистка салона", 9, 30, 16, 30), ("Химчистка дисков", 14, 0, 16, 0)], "бежевый потолок",
     "Карта", None, "Химчистка"),
    ("2026-08-30", "Выдан", "Алексей Морозов", "9007778899", "Audi Q7", "T567YB777", 4,
     [("Легкая полировка", 9, 0, 14, 0), ("Керамика на кузов (1 слой)", 13, 30, 16, 0)], None,
     "Перевод", None, "Полировка"),

    # --- сегодня: живая доска, все колонки ---
    ("2026-08-31", "Мойка", "Виктор Григорьев", "9032223344", "Chery Arrizo 8", "M678TY777", 2,
     [("Комплексная мойка", 9, 0, 10, 30), ("Уборка багажника", 10, 0, 10, 45)], "пятно на коврике",
     None, ("Наличные", 2000), "Мойка"),
    ("2026-08-31", "Мойка", "Дарья Климова", "9023334455", "Mazda 3", "H445KM777", 1,
     [("Экспресс-мойка", 10, 15, 11, 0), ("Быстрая мокрая керамика", 11, 0, 12, 15)], None,
     None, None, "Мойка"),
    ("2026-08-31", "Химчистка", "Марина Демидова", "9033334455", "Exeed TXL", "E789KX777", 3,
     [("Мойка кузова", 9, 30, 11, 0), ("Химчистка салона", 10, 30, 17, 0)], "к 17:00",
     None, ("Карта", 10000), "Химчистка"),
    ("2026-08-31", "Полировка", "Андрей Котов", "9034445566", "Lexus NX", "B890KE777", 3,
     [("Легкая полировка", 10, 0, 15, 0), ("Силант на кузов", 14, 30, 16, 0)], None,
     None, None, "Полировка"),
    ("2026-08-31", "Полировка", "Никита Орлов", "9024445566", "Volkswagen Tiguan", "P512KT777", 2,
     [("Восстановительная полировка", 9, 0, 17, 0)], "сложное крыло",
     None, ("Перевод", 15000), "Полировка"),
    ("2026-08-31", "Оклейка", "Павел Лебедев", "9009990011", "Lexus RX", "B345KE777", 3,
     [("Комплексная мойка", 9, 0, 10, 20), ("Оклейка · Капот", 10, 0, 14, 0), ("Оклейка · Зеркала", 13, 30, 15, 0)],
     "матовая", None, None, "Оклейка"),
    ("2026-08-31", "Оклейка", "Сергей Николаев", "9005556677", "Kia Sportage", "P451KT777", 2,
     [("Тонировка · Заднее стекло", 11, 0, 15, 0)], "не трогать обогрев",
     None, ("Карта", 3000), "Оклейка"),
    ("2026-08-31", "Интерьер", "Наталья Федорова", "9011112233", "Skoda Octavia", "C678XH777", 2,
     [("Уборка салона", 12, 0, 14, 0), ("Химчистка 1го сидения (Ткань)", 13, 30, 15, 30)],
     "детское кресло", None, None, "Интерьер"),
    ("2026-08-31", "Принят в работу", "София Мартынова", "9035556677", "Omoda C5", "O901PC777", 1,
     [("Экспресс-мойка", 14, 0, 15, 0), ("Krytex лобовое стекло", 15, 0, 16, 30)], None,
     None, ("Наличные", 1500), "Мойка"),
    ("2026-08-31", "Принят в работу", "Артём Зайцев", "9014445566", "Haval Jolion", "K234OP777", 1,
     [("Мойка кузова", 15, 30, 17, 0), ("Быстрая сухая керамика", 16, 30, 18, 0)], None,
     None, None, "Мойка"),

    # --- завтра: немного предзаписей (не забивать колонку) ---
    ("2026-09-01", "Предварительная запись", "Кирилл Носов", "9036667788", "Tank 300", "T345YB777", 4,
     [("Восстановительная полировка", 9, 0, 17, 0), ("Керамика на кузов (2 слоя)", 16, 0, 19, 0)],
     "без капота", None, None, "Полировка"),
    ("2026-09-01", "Предварительная запись", "Полина Жукова", "9037778899", "Geely Coolray", "M456TY777", 1,
     [("Комплексная мойка", 11, 0, 12, 30), ("Тонировка · Заднее стекло", 12, 0, 16, 0)], None,
     None, None, "Оклейка"),
    ("2026-09-01", "Предварительная запись", "Инна Фомина", "9039990011", "BMW X3", "E678KX777", 3,
     [("Химчистка салона", 10, 0, 16, 30)], None, None, None, "Химчистка"),
]

# Today cash extras (beyond order payments)
TODAY_FLOWS = [
    ("Приход", 5000, "Прочее", "Наличные", "Внесение размена / подкрепление"),
    ("Расход", 3200, "Химия", "Наличные", "Докупка расходников"),
    ("Расход", 900, "Прочее", "Наличные", "Кофе/вода"),
    ("Расход", 4500, "Химия", "Карта", "Паста/салфетки"),
    ("Расход", 8000, "Зарплата", "Наличные", "Аванс мойщикам"),
]

WORKSHOP_ROLE_MAP = {
    "Мойка": {"Мойка", "Универсал"},
    "Химчистка": {"Химчистка", "Кузовные работы", "Универсал"},
    "Полировка": {"Полировка", "Кузовные работы", "Универсал"},
    "Оклейка": {"Оклейка", "Кузовные работы", "Универсал"},
    "Интерьер": {"Интерьер", "Тюнинг/Интерьер", "Универсал"},
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
    if any(x in n for x in ("полир", "керамик", "силант", "krytex")):
        return "Полировка"
    if "тонир" in n or "оклей" in n:
        return "Оклейка"
    if "уборка салона" in n:
        return "Интерьер"
    return "Мойка"


def iso(day: str, hour: int, minute: int = 0) -> str:
    return f"{day}T{hour:02d}:{minute:02d}:00"


def at(day: str, hour: int, minute: int = 0) -> datetime:
    y, m, d = (int(x) for x in day.split("-"))
    return datetime(y, m, d, hour, minute, tzinfo=MSK)


def phone10(p: str) -> str:
    return "".join(ch for ch in p if ch.isdigit())[-10:]


def plate_key(p: str) -> str:
    table = str.maketrans("АВЕКМНОРСТУХавекмнорстух", "ABEKMHOPCTYXABEKMHOPCTYX")
    return (p or "").upper().replace(" ", "").translate(table)


def is_seed_phone(phone: str) -> bool:
    d = phone10(phone)
    return len(d) == 10 and d.startswith(SEED_PHONE_PREFIXES)


def main() -> None:
    db = SessionLocal()
    company = db.scalar(select(Company).where(Company.slug == COMPANY_SLUG))
    if company is None:
        raise SystemExit(f"company {COMPANY_SLUG} missing")
    cid = company.id
    owner = db.scalar(select(User).where(User.email == OWNER_EMAIL))
    owner_id = owner.id if owner else None
    branch = db.scalar(
        select(Branch).where(Branch.company_id == cid, Branch.is_active.is_(True)).order_by(Branch.id)
    )
    if branch is None:
        raise SystemExit("no branch")
    bid = branch.id
    print(f"company #{cid} {company.name} branch #{bid}")

    existing = {
        m.name: m
        for m in db.scalars(select(CrmMaster).where(CrmMaster.company_id == cid)).all()
    }
    for name, role in MASTERS:
        if name in existing:
            existing[name].role = role
            existing[name].is_active = True
        else:
            m = CrmMaster(company_id=cid, name=name, role=role, is_active=True)
            db.add(m)
            existing[name] = m
    db.flush()
    masters = list(
        db.scalars(select(CrmMaster).where(CrmMaster.company_id == cid, CrmMaster.is_active.is_(True))).all()
    )
    by_ws: dict[str, list[int]] = {k: [] for k in WORKSHOP_ROLE_MAP}
    admin_id = None
    for m in masters:
        roles = [p.strip() for p in (m.role or "").split(",") if p.strip()]
        if any("Администратор" in r for r in roles) and admin_id is None:
            admin_id = m.id
        for ws, allowed in WORKSHOP_ROLE_MAP.items():
            if any(r == ws or r in allowed for r in roles):
                by_ws[ws].append(m.id)
    print(f"masters={len(masters)} admin={admin_id} ws={ {k: len(v) for k, v in by_ws.items()} }")

    # wipe cash
    for p in db.scalars(select(CashPayment).where(CashPayment.company_id == cid)).all():
        db.delete(p)
    for f in db.scalars(select(CashFlow).where(CashFlow.company_id == cid)).all():
        db.delete(f)
    for s in db.scalars(select(CashShift).where(CashShift.company_id == cid)).all():
        db.delete(s)
    db.flush()

    clients = list(db.scalars(select(CrmClient).where(CrmClient.company_id == cid)).all())
    seed_cids = {c.id for c in clients if is_seed_phone(c.phone)}
    deleted = 0
    for o in db.scalars(select(CrmOrder).where(CrmOrder.company_id == cid)).all():
        if o.client_id in seed_cids:
            db.delete(o)
            deleted += 1
    db.commit()
    print(f"deleted seed orders={deleted}")

    regs = ensure_registers(db, cid)
    reg_by_method = {r.money_type: r for r in regs if r.is_active}
    cash_reg = reg_by_method.get("Наличные") or regs[0]

    # shifts: yesterday closed, today open (healthy opening)
    shift_y = CashShift(
        company_id=cid,
        branch_id=bid,
        status="closed",
        note="сид · 30.08",
        opened_by_user_id=owner_id,
        opened_at=at("2026-08-30", 8, 45),
        closed_at=at("2026-08-30", 19, 20),
    )
    db.add(shift_y)
    db.flush()
    for r in regs:
        if not r.is_active:
            continue
        opening = 25000.0 if r.id == cash_reg.id else 0.0
        db.add(
            CashShiftBalance(
                shift_id=shift_y.id,
                register_id=r.id,
                opening=opening,
                expected=opening,
                fact=opening,
                difference=0.0,
            )
        )

    shift_t = CashShift(
        company_id=cid,
        branch_id=bid,
        status="open",
        note="сид · сегодня",
        opened_by_user_id=owner_id,
        opened_at=at("2026-08-31", 8, 40),
    )
    db.add(shift_t)
    db.flush()
    for r in regs:
        if not r.is_active:
            continue
        # живой размен + терминал/перевод с переносом
        if r.money_type == "Наличные":
            opening = 42000.0
        elif r.money_type == "Карта":
            opening = 0.0
        else:
            opening = 0.0
        db.add(CashShiftBalance(shift_id=shift_t.id, register_id=r.id, opening=opening))

    shifts = {"2026-08-30": shift_y, "2026-08-31": shift_t}
    db.flush()

    # Also book yesterday payments into TODAY journal so «Сегодня» живая:
    # issued yesterday → payment created_at today morning (клиент доплатил / провели утром)
    # Actually better: keep payment on yesterday for week, AND add today's payments from partials + re-post
    # User looks at Сегодня — need payments with created_at = today.

    created = []
    pay_slot = 9  # hour for today's payment stamps
    pay_min = 10

    for day, status, cname, phone, make, plate, car_cls, works, shop, pay_method, partial, header_ws in ORDERS:
        starts = [(h, m) for _, h, m, _, _ in works]
        ends = [(h, m) for _, _, _, h, m in works]
        sh, sm = min(starts)
        eh, em = max(ends)

        digits = phone10(phone)
        client = next(
            (
                c
                for c in db.scalars(select(CrmClient).where(CrmClient.company_id == cid)).all()
                if phone10(c.phone) == digits
            ),
            None,
        )
        if client is None:
            client = CrmClient(company_id=cid, name=cname, phone=phone, is_vip=False)
            db.add(client)
            db.flush()

        key = plate_key(plate)
        car = None
        for c in db.scalars(select(CrmCar).where(CrmCar.company_id == cid)).all():
            if plate_key(c.plate) == key:
                car = c
                client = db.get(CrmClient, c.client_id) or client
                break
        if car is None:
            car = CrmCar(
                company_id=cid,
                client_id=client.id,
                make_model=make,
                plate=plate_key(plate),
                vin="",
                category=str(car_cls),
            )
            db.add(car)
            db.flush()

        items: list[CrmOrderItem] = []
        total = 0.0
        for wname, whs, wms, whe, wme in works:
            ws = workshop_of(wname)
            mids = by_ws.get(ws) or []
            mid_str = ",".join(str(x) for x in mids[:1]) if mids else ""
            price = price_of(wname, car_cls)
            total += price
            items.append(
                CrmOrderItem(
                    name=wname,
                    price=price,
                    workshop=ws,
                    start_time=iso(day, whs, wms),
                    end_time=iso(day, whe, wme),
                    master_ids=mid_str,
                    is_done=status == "Выдан",
                )
            )

        paid = 0.0
        if pay_method:
            paid = float(total)
        elif partial:
            paid = float(partial[1])

        order = CrmOrder(
            company_id=cid,
            branch_id=bid,
            client_id=client.id,
            car_id=car.id,
            status=status,
            notes=", ".join(w[0] for w in works),
            due_date=day,
            start_time=iso(day, sh, sm),
            end_time=iso(day, eh, em),
            end_date=day,
            price=total,
            paid_amount=paid,
            payment_method=(pay_method or (partial[0] if partial else "Наличные")),
            receptionist_id=admin_id,
            items=items,
            created_at=at(day, sh, sm),
            updated_at=at(day, eh, em),
        )
        db.add(order)
        db.flush()

        # header masters: только цех (карточка берёт первого) — админ в receptionist
        header_ids: list[int] = []
        ws_key = header_ws or workshop_of(works[0][0])
        for mid in by_ws.get(ws_key) or []:
            header_ids.append(mid)
            break
        for mid in header_ids:
            db.add(CrmOrderMaster(order_id=order.id, master_id=mid))

        if shop:
            db.add(
                CrmOrderEvent(
                    company_id=cid,
                    order_id=order.id,
                    event_text=f"Для цеха «{ws_key}»: {shop}",
                    created_at=at(day, sh, max(sm, 5)),
                )
            )

        # Full payment for issued — stamp TODAY so касса «Сегодня» живая
        if pay_method:
            reg = reg_by_method.get(pay_method) or cash_reg
            # split: half yesterday close, half today morning — actually all today for screenshot
            db.add(
                CashPayment(
                    company_id=cid,
                    branch_id=bid,
                    shift_id=shift_t.id,
                    register_id=reg.id,
                    crm_order_id=order.id,
                    amount=paid,
                    method=pay_method,
                    created_at=at("2026-08-31", pay_slot, pay_min),
                    created_by_user_id=owner_id,
                )
            )
            pay_min += 7
            if pay_min >= 60:
                pay_slot += 1
                pay_min = 5

        if partial:
            method, amount = partial
            reg = reg_by_method.get(method) or cash_reg
            db.add(
                CashPayment(
                    company_id=cid,
                    branch_id=bid,
                    shift_id=shift_t.id,
                    register_id=reg.id,
                    crm_order_id=order.id,
                    amount=float(amount),
                    method=method,
                    created_at=at("2026-08-31", pay_slot, pay_min),
                    created_by_user_id=owner_id,
                )
            )
            pay_min += 5
            if pay_min >= 60:
                pay_slot += 1
                pay_min = 5

        created.append(order)

    minute = 40
    for typ, amount, category, method, desc in TODAY_FLOWS:
        reg = reg_by_method.get(method) or cash_reg
        db.add(
            CashFlow(
                company_id=cid,
                branch_id=bid,
                shift_id=shift_t.id,
                register_id=reg.id,
                type=typ,
                amount=float(amount),
                category=category,
                method=method,
                description=desc,
                note="сид",
                created_at=at("2026-08-31", 11 if typ == "Приход" else 15, minute % 60),
                created_by_user_id=owner_id,
            )
        )
        minute += 4

    # refresh open-shift expected from opening + today's delta (UI uses expected)
    db.flush()
    pays = list(
        db.scalars(
            select(CashPayment).where(
                CashPayment.shift_id == shift_t.id, CashPayment.is_voided.is_(False)
            )
        ).all()
    )
    flows = list(db.scalars(select(CashFlow).where(CashFlow.shift_id == shift_t.id)).all())
    delta: dict[int, float] = {}
    for p in pays:
        delta[p.register_id] = delta.get(p.register_id, 0.0) + float(p.amount)
    for f in flows:
        sign = 1.0 if f.type == "Приход" else -1.0
        delta[f.register_id] = delta.get(f.register_id, 0.0) + sign * float(f.amount)
    for bal in db.scalars(select(CashShiftBalance).where(CashShiftBalance.shift_id == shift_t.id)).all():
        bal.expected = float(bal.opening or 0) + delta.get(bal.register_id, 0.0)

    # yesterday closed balances after its own ops (none besides opening — payments moved to today)
    for bal in db.scalars(select(CashShiftBalance).where(CashShiftBalance.shift_id == shift_y.id)).all():
        bal.expected = float(bal.opening or 0)
        bal.fact = bal.expected
        bal.difference = 0.0

    db.commit()
    live = sum(1 for o in created if o.status != "Выдан")
    issued = sum(1 for o in created if o.status == "Выдан")
    print(f"orders={len(created)} issued={issued} live={live} today_payments={len(pays)} today_flows={len(flows)}")
    print("OK")


if __name__ == "__main__":
    main()
