from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db import get_db
from app.deps import require_permissions
from app.models import (
    Branch,
    CashFlow,
    CashPayment,
    CashRegister,
    CashShift,
    CashShiftBalance,
    CrmFilmRoll,
    CrmInventoryItem,
    CrmInventoryMove,
    CrmMaster,
    CrmOrder,
    CrmOrderWrapFilm,
    User,
)
from app.cash_schemas import (
    CashFlowCreate,
    CashFlowOut,
    CashFlowUpdate,
    CashJournalEntry,
    CashPaymentCreate,
    CashPaymentOut,
    CashRegisterOut,
    CashShiftClose,
    CashShiftOpen,
    CashShiftOut,
    CashShiftBalanceOut,
)

router = APIRouter(prefix="/cash", tags=["cash"])

DEFAULT_REGISTERS = [
    ("Касса наличные", "Наличные", 0),
    ("Терминал", "Карта", 1),
    ("Перевод", "Перевод", 2),
    ("Счёт", "Счёт", 3),
]

_FILM_CATEGORIES = {"Плёнка оклейка", "Плёнка тонировка"}


def _company_id(user: User) -> int:
    if user.is_platform_admin:
        raise HTTPException(
            status_code=400,
            detail="Войдите пользователем компании (например owner@demo.det-app.ru)",
        )
    if user.company_id is None:
        raise HTTPException(status_code=400, detail="Пользователь без компании")
    return user.company_id


def _default_branch_id(db: Session, user: User, company_id: int) -> int:
    if user.branches:
        for b in user.branches:
            if b.company_id == company_id and b.is_active:
                return b.id
    branch = db.scalar(
        select(Branch)
        .where(Branch.company_id == company_id, Branch.is_active.is_(True))
        .order_by(Branch.id)
    )
    if branch is None:
        raise HTTPException(status_code=400, detail="У компании нет филиала")
    return branch.id


def ensure_registers(db: Session, company_id: int) -> list[CashRegister]:
    rows = list(
        db.scalars(
            select(CashRegister)
            .where(CashRegister.company_id == company_id)
            .order_by(CashRegister.sort_order, CashRegister.id)
        ).all()
    )
    if rows:
        return rows
    for name, money_type, sort_order in DEFAULT_REGISTERS:
        db.add(
            CashRegister(
                company_id=company_id,
                name=name,
                money_type=money_type,
                is_active=True,
                sort_order=sort_order,
            )
        )
    db.flush()
    return list(
        db.scalars(
            select(CashRegister)
            .where(CashRegister.company_id == company_id)
            .order_by(CashRegister.sort_order, CashRegister.id)
        ).all()
    )


def _register_by_method(db: Session, company_id: int, method: str) -> CashRegister:
    regs = ensure_registers(db, company_id)
    for r in regs:
        if r.is_active and r.money_type == method:
            return r
    for r in regs:
        if r.is_active:
            return r
    raise HTTPException(status_code=400, detail="Нет касс компании")


def _is_rolls_unit(unit: str | None) -> bool:
    u = (unit or "").strip().lower().replace(" ", "")
    return u in {"рул", "рул.", "рулон", "рулоны", "roll", "rolls"}


def _sync_film_inventory_qty(db: Session, item: CrmInventoryItem) -> None:
    rolls = list(
        db.scalars(select(CrmFilmRoll).where(CrmFilmRoll.inventory_id == item.id)).all()
    )
    if _is_rolls_unit(item.unit):
        item.quantity = float(sum(1 for r in rolls if float(r.meters_left or 0) > 0.001))
    else:
        item.quantity = float(sum(float(r.meters_left or 0) for r in rolls))


def _shift_out(db: Session, shift: CashShift) -> CashShiftOut:
    regs = {
        r.id: r
        for r in db.scalars(
            select(CashRegister).where(CashRegister.company_id == shift.company_id)
        ).all()
    }
    balances = []
    for b in shift.balances or []:
        reg = regs.get(b.register_id)
        balances.append(
            CashShiftBalanceOut(
                register_id=b.register_id,
                register_name=reg.name if reg else None,
                money_type=reg.money_type if reg else None,
                opening=float(b.opening or 0),
                expected=float(b.expected) if b.expected is not None else None,
                fact=float(b.fact) if b.fact is not None else None,
                difference=float(b.difference) if b.difference is not None else None,
            )
        )
    return CashShiftOut(
        id=shift.id,
        company_id=shift.company_id,
        branch_id=shift.branch_id,
        status=shift.status,
        opened_at=shift.opened_at,
        closed_at=shift.closed_at,
        note=shift.note or "",
        balances=balances,
    )


def _current_open_shift(
    db: Session, company_id: int, branch_id: int
) -> CashShift | None:
    return db.scalar(
        select(CashShift)
        .where(
            CashShift.company_id == company_id,
            CashShift.branch_id == branch_id,
            CashShift.status == "open",
        )
        .options(selectinload(CashShift.balances))
        .order_by(CashShift.id.desc())
    )


def _require_open_shift(db: Session, company_id: int, branch_id: int) -> CashShift:
    shift = _current_open_shift(db, company_id, branch_id)
    if shift is None:
        raise HTTPException(status_code=400, detail="Нет открытой смены")
    return shift


def _opening_for(openings: dict, register_id: int) -> float:
    if register_id in openings:
        return float(openings.get(register_id) or 0)
    key = str(register_id)
    if key in openings:
        return float(openings.get(key) or 0)
    return 0.0


def _flow_out(db: Session, row: CashFlow) -> CashFlowOut:
    master_name = None
    inventory_name = None
    if row.master_id:
        m = db.get(CrmMaster, row.master_id)
        master_name = m.name if m else None
    if row.inventory_id:
        inv = db.get(CrmInventoryItem, row.inventory_id)
        inventory_name = inv.name if inv else None
    return CashFlowOut(
        id=row.id,
        type=row.type,
        amount=float(row.amount),
        category=row.category or "Прочее",
        method=row.method or "Наличные",
        register_id=row.register_id,
        shift_id=row.shift_id,
        description=row.description or "",
        note=row.note or "",
        counterparty=getattr(row, "counterparty", "") or "",
        master_id=row.master_id,
        inventory_id=row.inventory_id,
        inventory_qty=float(getattr(row, "inventory_qty", 0) or 0),
        order_id=row.order_id,
        template_key=getattr(row, "template_key", "") or "",
        created_at=row.created_at,
        master_name=master_name,
        inventory_name=inventory_name,
    )


def _stock_in_from_cash(
    db: Session,
    *,
    company_id: int,
    flow_id: int,
    inventory_id: int,
    qty: float,
) -> None:
    if qty <= 0:
        return
    inv = db.scalar(
        select(CrmInventoryItem).where(
            CrmInventoryItem.id == inventory_id, CrmInventoryItem.company_id == company_id
        )
    )
    if inv is None:
        raise HTTPException(status_code=404, detail="Складская позиция не найдена")
    cat = (inv.category or "").strip()
    if cat in _FILM_CATEGORIES:
        stamp = f"{flow_id}-{int(datetime.now(timezone.utc).timestamp() * 1_000_000)}"
        per = float(getattr(inv, "meters_per_roll", 0) or 0)
        if _is_rolls_unit(inv.unit):
            n = max(1, min(50, int(round(qty))))
            meters = per if per > 0 else 0.0
            for i in range(n):
                suffix = stamp if n == 1 else f"{stamp}-{i + 1}"
                roll_no = f"КАССА-{suffix}"
                db.add(
                    CrmFilmRoll(
                        company_id=company_id,
                        inventory_id=inv.id,
                        roll_number=roll_no,
                        meters_initial=meters,
                        meters_left=meters,
                    )
                )
            db.flush()
            _sync_film_inventory_qty(db, inv)
            db.add(
                CrmInventoryMove(
                    company_id=company_id,
                    item_id=inv.id,
                    delta=float(n),
                    balance_after=float(inv.quantity or 0),
                    reason="cash_purchase",
                    note=f"Закупка из кассы #{flow_id}",
                )
            )
        else:
            roll_no = f"КАССА-{stamp}"
            db.add(
                CrmFilmRoll(
                    company_id=company_id,
                    inventory_id=inv.id,
                    roll_number=roll_no,
                    meters_initial=float(qty),
                    meters_left=float(qty),
                )
            )
            db.flush()
            _sync_film_inventory_qty(db, inv)
            db.add(
                CrmInventoryMove(
                    company_id=company_id,
                    item_id=inv.id,
                    delta=float(qty),
                    balance_after=float(inv.quantity or 0),
                    reason="cash_purchase",
                    note=f"Закупка из кассы #{flow_id}",
                )
            )
        return

    inv.quantity = float(inv.quantity or 0) + float(qty)
    db.add(
        CrmInventoryMove(
            company_id=company_id,
            item_id=inv.id,
            delta=float(qty),
            balance_after=float(inv.quantity),
            reason="cash_purchase",
            note=f"Закупка из кассы #{flow_id}",
        )
    )


def _rollback_stock_in_from_cash(
    db: Session,
    *,
    company_id: int,
    flow_id: int,
    inventory_id: int,
    qty: float,
) -> None:
    if qty <= 0:
        return
    inv = db.scalar(
        select(CrmInventoryItem).where(
            CrmInventoryItem.id == inventory_id, CrmInventoryItem.company_id == company_id
        )
    )
    if inv is None:
        return
    cat = (inv.category or "").strip()
    if cat in _FILM_CATEGORIES:
        prefix = f"КАССА-{flow_id}-"
        rolls = list(
            db.scalars(
                select(CrmFilmRoll)
                .where(
                    CrmFilmRoll.inventory_id == inv.id,
                    CrmFilmRoll.company_id == company_id,
                    CrmFilmRoll.roll_number.like(f"{prefix}%"),
                )
                .order_by(CrmFilmRoll.id.desc())
            ).all()
        )
        if not rolls and _is_rolls_unit(inv.unit):
            n = max(1, min(50, int(round(qty))))
            rolls = list(
                db.scalars(
                    select(CrmFilmRoll)
                    .where(
                        CrmFilmRoll.inventory_id == inv.id,
                        CrmFilmRoll.roll_number.like("КАССА-%"),
                    )
                    .order_by(CrmFilmRoll.id.desc())
                    .limit(n)
                ).all()
            )
        for roll in rolls:
            for wf in db.scalars(
                select(CrmOrderWrapFilm).where(CrmOrderWrapFilm.roll_id == roll.id)
            ).all():
                wf.roll_id = None
            db.delete(roll)
        if rolls:
            db.flush()
            _sync_film_inventory_qty(db, inv)
            delta = (
                -float(len(rolls))
                if _is_rolls_unit(inv.unit)
                else -float(qty)
            )
            db.add(
                CrmInventoryMove(
                    company_id=company_id,
                    item_id=inv.id,
                    delta=delta,
                    balance_after=float(inv.quantity or 0),
                    reason="manual",
                    note=f"Откат закупки плёнки (касса #{flow_id})",
                )
            )
        return

    inv.quantity = max(0.0, float(inv.quantity or 0) - float(qty))
    db.add(
        CrmInventoryMove(
            company_id=company_id,
            item_id=inv.id,
            delta=-float(qty),
            balance_after=float(inv.quantity),
            reason="manual",
            note=f"Откат закупки (касса #{flow_id})",
        )
    )


def _validate_flow_links(
    db: Session,
    company_id: int,
    *,
    master_id: int | None,
    inventory_id: int | None,
    order_id: int | None,
) -> None:
    if master_id is not None:
        m = db.scalar(
            select(CrmMaster).where(CrmMaster.id == master_id, CrmMaster.company_id == company_id)
        )
        if m is None:
            raise HTTPException(status_code=404, detail="Мастер не найден")
    if inventory_id is not None:
        inv = db.scalar(
            select(CrmInventoryItem).where(
                CrmInventoryItem.id == inventory_id, CrmInventoryItem.company_id == company_id
            )
        )
        if inv is None:
            raise HTTPException(status_code=404, detail="Складская позиция не найдена")
    if order_id is not None:
        o = db.scalar(
            select(CrmOrder).where(CrmOrder.id == order_id, CrmOrder.company_id == company_id)
        )
        if o is None:
            raise HTTPException(status_code=404, detail="Заказ не найден")


@router.get("/registers", response_model=list[CashRegisterOut])
def list_registers(
    user: User = Depends(require_permissions("cash.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    return ensure_registers(db, company_id)


@router.get("/shifts/current", response_model=CashShiftOut | None)
def current_shift(
    user: User = Depends(require_permissions("cash.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    branch_id = _default_branch_id(db, user, company_id)
    ensure_registers(db, company_id)
    shift = _current_open_shift(db, company_id, branch_id)
    if shift is None:
        return None
    return _shift_out(db, shift)


@router.get("/shifts", response_model=list[CashShiftOut])
def list_shifts(
    limit: int = Query(default=20, ge=1, le=100),
    user: User = Depends(require_permissions("cash.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    branch_id = _default_branch_id(db, user, company_id)
    rows = db.scalars(
        select(CashShift)
        .where(CashShift.company_id == company_id, CashShift.branch_id == branch_id)
        .options(selectinload(CashShift.balances))
        .order_by(CashShift.id.desc())
        .limit(limit)
    ).all()
    return [_shift_out(db, s) for s in rows]


@router.get("/shifts/{shift_id}", response_model=CashShiftOut)
def get_shift(
    shift_id: int,
    user: User = Depends(require_permissions("cash.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    shift = db.scalar(
        select(CashShift)
        .where(CashShift.id == shift_id, CashShift.company_id == company_id)
        .options(selectinload(CashShift.balances))
    )
    if shift is None:
        raise HTTPException(status_code=404, detail="Смена не найдена")
    return _shift_out(db, shift)


@router.post("/shifts/open", response_model=CashShiftOut)
def open_shift(
    body: CashShiftOpen,
    user: User = Depends(require_permissions("cash.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    branch_id = body.branch_id or _default_branch_id(db, user, company_id)
    if body.branch_id is not None:
        br = db.scalar(
            select(Branch).where(Branch.id == body.branch_id, Branch.company_id == company_id)
        )
        if br is None:
            raise HTTPException(status_code=404, detail="Филиал не найден")
        branch_id = br.id
    if _current_open_shift(db, company_id, branch_id) is not None:
        raise HTTPException(status_code=400, detail="Смена уже открыта")
    regs = ensure_registers(db, company_id)
    shift = CashShift(
        company_id=company_id,
        branch_id=branch_id,
        status="open",
        note=body.note or "",
        opened_by_user_id=user.id,
    )
    db.add(shift)
    db.flush()
    for r in regs:
        if not r.is_active:
            continue
        opening = _opening_for(body.openings, r.id)
        db.add(
            CashShiftBalance(
                shift_id=shift.id,
                register_id=r.id,
                opening=opening,
            )
        )
    db.commit()
    shift = db.scalar(
        select(CashShift)
        .where(CashShift.id == shift.id)
        .options(selectinload(CashShift.balances))
    )
    return _shift_out(db, shift)  # type: ignore[arg-type]


@router.post("/shifts/{shift_id}/close", response_model=CashShiftOut)
def close_shift(
    shift_id: int,
    body: CashShiftClose,
    user: User = Depends(require_permissions("cash.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    shift = db.scalar(
        select(CashShift)
        .where(CashShift.id == shift_id, CashShift.company_id == company_id)
        .options(selectinload(CashShift.balances))
    )
    if shift is None:
        raise HTTPException(status_code=404, detail="Смена не найдена")
    if shift.status != "open":
        raise HTTPException(status_code=400, detail="Смена уже закрыта")

    flows = db.scalars(select(CashFlow).where(CashFlow.shift_id == shift.id)).all()
    pays = db.scalars(
        select(CashPayment).where(
            CashPayment.shift_id == shift.id, CashPayment.is_voided.is_(False)
        )
    ).all()
    delta: dict[int, float] = {}
    for f in flows:
        sign = 1.0 if f.type == "Приход" else -1.0
        delta[f.register_id] = delta.get(f.register_id, 0.0) + sign * float(f.amount)
    for p in pays:
        delta[p.register_id] = delta.get(p.register_id, 0.0) + float(p.amount)

    facts = body.facts or {}
    for bal in shift.balances:
        expected = float(bal.opening or 0) + delta.get(bal.register_id, 0.0)
        if bal.register_id in facts:
            fact = float(facts[bal.register_id])
        elif str(bal.register_id) in facts:
            fact = float(facts[str(bal.register_id)])  # type: ignore[index]
        else:
            fact = expected
        bal.expected = expected
        bal.fact = fact
        bal.difference = fact - expected
    shift.status = "closed"
    shift.closed_at = datetime.now(timezone.utc)
    if body.note:
        shift.note = (shift.note + "\n" + body.note).strip() if shift.note else body.note
    db.commit()
    shift = db.scalar(
        select(CashShift)
        .where(CashShift.id == shift_id)
        .options(selectinload(CashShift.balances))
    )
    return _shift_out(db, shift)  # type: ignore[arg-type]


@router.get("/journal", response_model=list[CashJournalEntry])
def journal(
    from_date: str | None = Query(default=None, alias="from"),
    to_date: str | None = Query(default=None, alias="to"),
    shift_id: int | None = None,
    user: User = Depends(require_permissions("cash.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    branch_id = _default_branch_id(db, user, company_id)
    regs = {r.id: r for r in ensure_registers(db, company_id)}

    fq = select(CashFlow).where(
        CashFlow.company_id == company_id, CashFlow.branch_id == branch_id
    )
    pq = select(CashPayment).where(
        CashPayment.company_id == company_id, CashPayment.branch_id == branch_id
    )
    if shift_id is not None:
        fq = fq.where(CashFlow.shift_id == shift_id)
        pq = pq.where(CashPayment.shift_id == shift_id)

    flows = db.scalars(fq.order_by(CashFlow.id.desc()).limit(500)).all()
    pays = db.scalars(pq.order_by(CashPayment.id.desc()).limit(500)).all()

    def _in_range(dt: datetime | None) -> bool:
        if dt is None:
            return True
        local = dt.astimezone(timezone.utc).date().isoformat() if dt.tzinfo else dt.date().isoformat()
        if from_date and local < from_date[:10]:
            return False
        if to_date and local > to_date[:10]:
            return False
        return True

    entries: list[CashJournalEntry] = []
    for f in flows:
        if not _in_range(f.created_at):
            continue
        reg = regs.get(f.register_id)
        entries.append(
            CashJournalEntry(
                kind="flow",
                id=f.id,
                created_at=f.created_at,
                amount=float(f.amount),
                method=f.method,
                title=f.description or f.category or f.type,
                shift_id=f.shift_id,
                register_id=f.register_id,
                flow_type=f.type,
                category=f.category or "Прочее",
                register_name=reg.name if reg else "",
            )
        )
    for p in pays:
        if not _in_range(p.created_at):
            continue
        reg = regs.get(p.register_id)
        entries.append(
            CashJournalEntry(
                kind="payment",
                id=p.id,
                created_at=p.created_at,
                amount=float(p.amount),
                method=p.method,
                title=f"Оплата заказа #{p.crm_order_id}",
                shift_id=p.shift_id,
                register_id=p.register_id,
                order_id=p.crm_order_id,
                is_voided=bool(p.is_voided),
                category="Оплата заказа",
                register_name=reg.name if reg else "",
            )
        )
    entries.sort(key=lambda e: e.created_at or datetime.min.replace(tzinfo=timezone.utc), reverse=True)
    return entries[:200]


@router.post("/flows", response_model=CashFlowOut)
def create_flow(
    body: CashFlowCreate,
    user: User = Depends(require_permissions("cash.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    branch_id = _default_branch_id(db, user, company_id)
    shift = _require_open_shift(db, company_id, branch_id)
    flow_type = body.type.strip()
    if flow_type not in ("Приход", "Расход"):
        raise HTTPException(status_code=400, detail="type: Приход или Расход")
    _validate_flow_links(
        db,
        company_id,
        master_id=body.master_id,
        inventory_id=body.inventory_id,
        order_id=body.order_id,
    )
    if body.register_id is not None:
        reg = db.scalar(
            select(CashRegister).where(
                CashRegister.id == body.register_id, CashRegister.company_id == company_id
            )
        )
        if reg is None:
            raise HTTPException(status_code=404, detail="Касса не найдена")
    else:
        reg = _register_by_method(db, company_id, body.method)
    row = CashFlow(
        company_id=company_id,
        branch_id=branch_id,
        shift_id=shift.id,
        register_id=reg.id,
        type=flow_type,
        amount=float(body.amount),
        category=body.category or "Прочее",
        method=body.method or reg.money_type,
        description=body.description or "",
        note=body.note or "",
        counterparty=body.counterparty or "",
        master_id=body.master_id,
        inventory_id=body.inventory_id,
        inventory_qty=float(body.inventory_qty or 0),
        order_id=body.order_id,
        template_key=body.template_key or "",
        created_by_user_id=user.id,
    )
    db.add(row)
    db.flush()
    if (
        row.inventory_id is not None
        and float(row.inventory_qty or 0) > 0
        and flow_type == "Расход"
    ):
        _stock_in_from_cash(
            db,
            company_id=company_id,
            flow_id=row.id,
            inventory_id=row.inventory_id,
            qty=float(row.inventory_qty),
        )
    db.commit()
    db.refresh(row)
    return _flow_out(db, row)


@router.get("/flows/{flow_id}", response_model=CashFlowOut)
def get_flow(
    flow_id: int,
    user: User = Depends(require_permissions("cash.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    row = db.scalar(
        select(CashFlow).where(CashFlow.id == flow_id, CashFlow.company_id == company_id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Операция не найдена")
    return _flow_out(db, row)


@router.patch("/flows/{flow_id}", response_model=CashFlowOut)
def update_flow(
    flow_id: int,
    body: CashFlowUpdate,
    user: User = Depends(require_permissions("cash.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    row = db.scalar(
        select(CashFlow).where(CashFlow.id == flow_id, CashFlow.company_id == company_id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Операция не найдена")
    shift = db.get(CashShift, row.shift_id)
    if shift is None or shift.status != "open":
        raise HTTPException(status_code=400, detail="Править можно только в открытой смене")

    old_type = row.type
    old_inv = row.inventory_id
    old_qty = float(row.inventory_qty or 0)
    if old_inv is not None and old_qty > 0 and old_type == "Расход":
        _rollback_stock_in_from_cash(
            db,
            company_id=company_id,
            flow_id=row.id,
            inventory_id=old_inv,
            qty=old_qty,
        )

    data = body.model_dump(exclude_unset=True)
    new_type = (data.get("type") or row.type).strip()
    if new_type not in ("Приход", "Расход"):
        raise HTTPException(status_code=400, detail="type: Приход или Расход")
    master_id = data["master_id"] if "master_id" in data else row.master_id
    inventory_id = data["inventory_id"] if "inventory_id" in data else row.inventory_id
    order_id = data["order_id"] if "order_id" in data else row.order_id
    _validate_flow_links(
        db,
        company_id,
        master_id=master_id,
        inventory_id=inventory_id,
        order_id=order_id,
    )

    if "register_id" in data and data["register_id"] is not None:
        reg = db.scalar(
            select(CashRegister).where(
                CashRegister.id == data["register_id"], CashRegister.company_id == company_id
            )
        )
        if reg is None:
            raise HTTPException(status_code=404, detail="Касса не найдена")
        row.register_id = reg.id
    elif "method" in data and data["method"]:
        reg = _register_by_method(db, company_id, data["method"])
        row.register_id = reg.id

    row.type = new_type
    if "amount" in data and data["amount"] is not None:
        row.amount = float(data["amount"])
    if "category" in data and data["category"] is not None:
        row.category = data["category"]
    if "method" in data and data["method"] is not None:
        row.method = data["method"]
    if "description" in data and data["description"] is not None:
        row.description = data["description"]
    if "note" in data and data["note"] is not None:
        row.note = data["note"]
    if "counterparty" in data and data["counterparty"] is not None:
        row.counterparty = data["counterparty"]
    if "master_id" in data:
        row.master_id = data["master_id"]
    if "inventory_id" in data:
        row.inventory_id = data["inventory_id"]
    if "inventory_qty" in data and data["inventory_qty"] is not None:
        row.inventory_qty = float(data["inventory_qty"])
    if "order_id" in data:
        row.order_id = data["order_id"]
    if "template_key" in data and data["template_key"] is not None:
        row.template_key = data["template_key"]

    if (
        row.inventory_id is not None
        and float(row.inventory_qty or 0) > 0
        and row.type == "Расход"
    ):
        _stock_in_from_cash(
            db,
            company_id=company_id,
            flow_id=row.id,
            inventory_id=row.inventory_id,
            qty=float(row.inventory_qty),
        )
    db.commit()
    db.refresh(row)
    return _flow_out(db, row)


@router.delete("/flows/{flow_id}", status_code=204)
def delete_flow(
    flow_id: int,
    user: User = Depends(require_permissions("cash.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    row = db.scalar(
        select(CashFlow).where(CashFlow.id == flow_id, CashFlow.company_id == company_id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Операция не найдена")
    shift = db.get(CashShift, row.shift_id)
    if shift is None or shift.status != "open":
        raise HTTPException(status_code=400, detail="Можно удалять только в открытой смене")
    if row.inventory_id is not None and float(row.inventory_qty or 0) > 0 and row.type == "Расход":
        _rollback_stock_in_from_cash(
            db,
            company_id=company_id,
            flow_id=row.id,
            inventory_id=row.inventory_id,
            qty=float(row.inventory_qty),
        )
    db.delete(row)
    db.commit()
    return Response(status_code=204)


@router.post("/payments", response_model=CashPaymentOut)
def create_payment(
    body: CashPaymentCreate,
    user: User = Depends(require_permissions("cash.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    branch_id = _default_branch_id(db, user, company_id)
    shift = _require_open_shift(db, company_id, branch_id)
    order = db.scalar(
        select(CrmOrder).where(CrmOrder.id == body.order_id, CrmOrder.company_id == company_id)
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Заказ не найден")
    if body.register_id is not None:
        reg = db.scalar(
            select(CashRegister).where(
                CashRegister.id == body.register_id, CashRegister.company_id == company_id
            )
        )
        if reg is None:
            raise HTTPException(status_code=404, detail="Касса не найдена")
    else:
        reg = _register_by_method(db, company_id, body.method)
    amount = float(body.amount)
    row = CashPayment(
        company_id=company_id,
        branch_id=branch_id,
        shift_id=shift.id,
        register_id=reg.id,
        crm_order_id=order.id,
        amount=amount,
        method=body.method or reg.money_type,
        created_by_user_id=user.id,
        is_voided=False,
    )
    order.paid_amount = float(order.paid_amount or 0) + amount
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.get("/payments", response_model=list[CashPaymentOut])
def list_payments(
    order_id: int | None = None,
    include_voided: bool = False,
    user: User = Depends(require_permissions("cash.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    q = select(CashPayment).where(CashPayment.company_id == company_id)
    if order_id is not None:
        q = q.where(CashPayment.crm_order_id == order_id)
    if not include_voided:
        q = q.where(CashPayment.is_voided.is_(False))
    rows = db.scalars(q.order_by(CashPayment.id.desc())).all()
    return list(rows)


@router.delete("/payments/{payment_id}", response_model=CashPaymentOut)
def void_payment(
    payment_id: int,
    user: User = Depends(require_permissions("cash.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    row = db.scalar(
        select(CashPayment).where(
            CashPayment.id == payment_id, CashPayment.company_id == company_id
        )
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Оплата не найдена")
    if row.is_voided:
        raise HTTPException(status_code=400, detail="Уже отменена")
    shift = db.get(CashShift, row.shift_id)
    if shift is None or shift.status != "open":
        raise HTTPException(status_code=400, detail="Отмена только в открытой смене")
    order = db.get(CrmOrder, row.crm_order_id)
    if order is not None:
        order.paid_amount = max(0.0, float(order.paid_amount or 0) - float(row.amount))
    row.is_voided = True
    db.commit()
    db.refresh(row)
    return row
