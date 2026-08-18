from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Response
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
    CrmOrder,
    User,
)
from app.cash_schemas import (
    CashFlowCreate,
    CashFlowOut,
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
        opening = float(body.openings.get(r.id, 0) or 0)
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

    # expected = opening + payments + income flows - expense flows per register
    flows = db.scalars(
        select(CashFlow).where(CashFlow.shift_id == shift.id)
    ).all()
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

    for bal in shift.balances:
        expected = float(bal.opening or 0) + delta.get(bal.register_id, 0.0)
        fact = float(body.facts.get(bal.register_id, expected))
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
    user: User = Depends(require_permissions("cash.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    branch_id = _default_branch_id(db, user, company_id)
    flows = db.scalars(
        select(CashFlow)
        .where(CashFlow.company_id == company_id, CashFlow.branch_id == branch_id)
        .order_by(CashFlow.id.desc())
        .limit(200)
    ).all()
    pays = db.scalars(
        select(CashPayment)
        .where(CashPayment.company_id == company_id, CashPayment.branch_id == branch_id)
        .order_by(CashPayment.id.desc())
        .limit(200)
    ).all()
    entries: list[CashJournalEntry] = []
    for f in flows:
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
            )
        )
    for p in pays:
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
        created_by_user_id=user.id,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


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
