from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session, selectinload

from app.db import get_db
from app.deps import require_permissions, user_permission_codes
from app.models import (
    Branch,
    CashFlow,
    CashPayment,
    CrmCar,
    CrmClient,
    CrmDefect,
    CrmInventoryMove,
    CrmMaster,
    CrmOrder,
    CrmOrderEvent,
    CrmOrderItem,
    CrmOrderMaster,
    CrmOrderWrapFilm,
    User,
)
from app.schemas import (
    CrmCarCreate,
    CrmCarOut,
    CrmCarUpdate,
    CrmClientCreate,
    CrmClientOut,
    CrmClientUpdate,
    CrmOrderCreate,
    CrmOrderEventCreate,
    CrmOrderEventOut,
    CrmOrderItemIn,
    CrmOrderItemOut,
    CrmOrderItemPatch,
    CrmOrderOut,
    CrmOrderUpdate,
)

router = APIRouter(prefix="/crm", tags=["crm"])


def _company_id(user: User) -> int:
    if user.is_platform_admin:
        raise HTTPException(
            status_code=400,
            detail="Войдите пользователем компании (например owner@demo.det-app.ru)",
        )
    if user.company_id is None:
        raise HTTPException(status_code=400, detail="Пользователь без компании")
    return user.company_id


def _is_studio_master(user: User) -> bool:
    if user.is_platform_admin:
        return False
    codes = user_permission_codes(user)
    # Полный доступ студии — не мастер.
    if "users.manage" in codes or "company.manage" in codes or "cash.write" in codes:
        return False
    role_names = {r.name for r in (user.roles or [])}
    if role_names & {"Владелец", "Управляющий", "Администратор", "Администратор компании"}:
        return False
    return "Мастер" in role_names or ("orders.write" in codes and "cash.read" not in codes)


def _user_workshops(db: Session, user: User) -> set[str]:
    mid = getattr(user, "master_id", None)
    if not mid:
        return set()
    m = db.get(CrmMaster, mid)
    if m is None or not m.role:
        return set()
    return {p.strip() for p in m.role.split(",") if p.strip()}


def _forbid_master_order_meta(user: User) -> None:
    if _is_studio_master(user):
        raise HTTPException(
            status_code=403,
            detail="Мастер не может менять даты, цены, выдачу и состав заказа",
        )


def _assert_master_item_workshop(db: Session, user: User, workshop: str | None) -> None:
    if not _is_studio_master(user):
        return
    allowed = _user_workshops(db, user)
    ws = (workshop or "").strip()
    if not allowed or ws not in allowed:
        raise HTTPException(
            status_code=403,
            detail="Мастер может менять только работы своего цеха",
        )


def _item_out(it: CrmOrderItem) -> CrmOrderItemOut:
    return CrmOrderItemOut(
        id=it.id,
        name=it.name,
        price=float(it.price or 0),
        workshop=it.workshop or "",
        is_done=bool(it.is_done),
        comment=getattr(it, "comment", None) or "",
        master_ids=getattr(it, "master_ids", None) or "",
        start_time=getattr(it, "start_time", None) or "",
        end_time=getattr(it, "end_time", None) or "",
        parent_id=getattr(it, "parent_id", None),
    )


def _fill_item_from_in(row: CrmOrderItem, body: CrmOrderItemIn) -> None:
    row.name = body.name.strip()
    row.price = float(body.price or 0)
    row.workshop = body.workshop or ""
    row.is_done = bool(body.is_done)
    row.comment = body.comment or ""
    row.master_ids = body.master_ids or ""
    row.start_time = body.start_time or ""
    row.end_time = body.end_time or ""
    row.parent_id = body.parent_id


def _purge_orders_by_ids(db: Session, ids: list[int]) -> int:
    """FK cleanup before deleting orders (same as delete_order / clear-board).

    Uses explicit SQL deletes (not ORM cascade) so child rows and orders are
    removed before cars/clients in the same transaction — ORM flush order
    otherwise can DELETE cars while crm_orders.car_id still references them.
    """
    if not ids:
        return 0
    uniq = list(dict.fromkeys(ids))
    db.execute(delete(CashPayment).where(CashPayment.crm_order_id.in_(uniq)))
    db.execute(update(CashFlow).where(CashFlow.order_id.in_(uniq)).values(order_id=None))
    db.execute(
        update(CrmInventoryMove).where(CrmInventoryMove.order_id.in_(uniq)).values(order_id=None)
    )
    db.execute(delete(CrmDefect).where(CrmDefect.order_id.in_(uniq)))
    db.execute(delete(CrmOrderWrapFilm).where(CrmOrderWrapFilm.order_id.in_(uniq)))
    db.execute(delete(CrmOrderEvent).where(CrmOrderEvent.order_id.in_(uniq)))
    db.execute(delete(CrmOrderMaster).where(CrmOrderMaster.order_id.in_(uniq)))
    # Self-FK parent_id: wipe children first, then remaining items.
    db.execute(
        delete(CrmOrderItem).where(
            CrmOrderItem.order_id.in_(uniq), CrmOrderItem.parent_id.is_not(None)
        )
    )
    db.execute(delete(CrmOrderItem).where(CrmOrderItem.order_id.in_(uniq)))
    result = db.execute(delete(CrmOrder).where(CrmOrder.id.in_(uniq)))
    db.flush()
    return int(result.rowcount or 0)


def _recalc_order_price(order: CrmOrder) -> None:
    works = sum(float(it.price or 0) for it in (order.items or []))
    pct = float(getattr(order, "discount_percent", 0) or 0)
    fixed = float(getattr(order, "discount_fixed", 0) or 0)
    if pct < 0:
        pct = 0
    if fixed < 0:
        fixed = 0
    disc = works * (pct / 100.0) + fixed
    if disc > works:
        disc = works
    order.price = works - disc


def _get_company_order(db: Session, order_id: int, company_id: int) -> CrmOrder:
    order = db.scalar(
        select(CrmOrder)
        .where(CrmOrder.id == order_id, CrmOrder.company_id == company_id)
        .options(selectinload(CrmOrder.items), selectinload(CrmOrder.master_links))
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Заказ не найден")
    return order


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


def _order_out(order: CrmOrder, client: CrmClient | None = None, car: CrmCar | None = None) -> CrmOrderOut:
    master_ids = [m.master_id for m in (getattr(order, "master_links", None) or [])]
    return CrmOrderOut(
        id=order.id,
        company_id=order.company_id,
        branch_id=order.branch_id,
        client_id=order.client_id,
        car_id=order.car_id,
        status=order.status,
        price=float(order.price or 0),
        paid_amount=float(order.paid_amount or 0),
        notes=order.notes or "",
        due_date=order.due_date or "",
        start_time=getattr(order, "start_time", None) or "",
        end_time=getattr(order, "end_time", None) or "",
        end_date=getattr(order, "end_date", None) or "",
        client_notes=getattr(order, "client_notes", None) or "",
        client_visible_notes=getattr(order, "client_visible_notes", None) or "",
        master_notes=getattr(order, "master_notes", None) or "",
        payment_method=getattr(order, "payment_method", None) or "Наличные",
        discount_percent=float(getattr(order, "discount_percent", 0) or 0),
        discount_fixed=float(getattr(order, "discount_fixed", 0) or 0),
        promo_code=getattr(order, "promo_code", None) or "",
        handover_ready=bool(getattr(order, "handover_ready", False)),
        handover_works=bool(getattr(order, "handover_works", False)),
        handover_payment=bool(getattr(order, "handover_payment", False)),
        handover_keys=bool(getattr(order, "handover_keys", False)),
        handover_inspect=bool(getattr(order, "handover_inspect", False)),
        handover_notified=bool(getattr(order, "handover_notified", False)),
        tech_wash_start=getattr(order, "tech_wash_start", None) or "",
        tech_wash_end=getattr(order, "tech_wash_end", None) or "",
        is_workshop_completed=bool(getattr(order, "is_workshop_completed", False)),
        master_ids=master_ids,
        receptionist_id=getattr(order, "receptionist_id", None),
        items=[_item_out(it) for it in (order.items or [])],
        client_name=client.name if client else None,
        car_label=(f"{car.make_model} {car.plate}".strip() if car else None),
    )


@router.get("/clients", response_model=list[CrmClientOut])
def list_clients(
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    rows = db.scalars(
        select(CrmClient).where(CrmClient.company_id == company_id).order_by(CrmClient.id.desc())
    ).all()
    return rows


@router.post("/clients", response_model=CrmClientOut)
def create_client(
    body: CrmClientCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    row = CrmClient(
        company_id=company_id,
        name=body.name.strip(),
        phone=(body.phone or "").strip(),
        is_vip=body.is_vip,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.patch("/clients/{client_id}", response_model=CrmClientOut)
def update_client(
    client_id: int,
    body: CrmClientUpdate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    row = db.scalar(
        select(CrmClient).where(CrmClient.id == client_id, CrmClient.company_id == company_id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Клиент не найден")
    if body.name is not None:
        row.name = body.name.strip()
    if body.phone is not None:
        row.phone = body.phone.strip()
    if body.is_vip is not None:
        row.is_vip = body.is_vip
    db.commit()
    db.refresh(row)
    return row


@router.delete("/clients/{client_id}")
def delete_client(
    client_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    row = db.scalar(
        select(CrmClient).where(CrmClient.id == client_id, CrmClient.company_id == company_id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Клиент не найден")
    cars = list(
        db.scalars(
            select(CrmCar).where(CrmCar.company_id == company_id, CrmCar.client_id == client_id)
        ).all()
    )
    car_ids = [c.id for c in cars]
    order_ids = list(
        db.scalars(
            select(CrmOrder.id).where(
                CrmOrder.company_id == company_id, CrmOrder.client_id == client_id
            )
        ).all()
    )
    if car_ids:
        order_ids.extend(
            db.scalars(
                select(CrmOrder.id).where(
                    CrmOrder.company_id == company_id, CrmOrder.car_id.in_(car_ids)
                )
            ).all()
        )
    deleted_orders = _purge_orders_by_ids(db, order_ids)
    for car in cars:
        db.delete(car)
    db.delete(row)
    db.commit()
    return {
        "ok": True,
        "deleted": client_id,
        "deleted_orders": deleted_orders,
        "deleted_cars": len(cars),
    }


@router.get("/cars", response_model=list[CrmCarOut])
def list_cars(
    client_id: int | None = None,
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    q = select(CrmCar).where(CrmCar.company_id == company_id)
    if client_id is not None:
        q = q.where(CrmCar.client_id == client_id)
    return list(db.scalars(q.order_by(CrmCar.id.desc())).all())


@router.post("/cars", response_model=CrmCarOut)
def create_car(
    body: CrmCarCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    client = db.scalar(
        select(CrmClient).where(CrmClient.id == body.client_id, CrmClient.company_id == company_id)
    )
    if client is None:
        raise HTTPException(status_code=404, detail="Клиент не найден")
    row = CrmCar(
        company_id=company_id,
        client_id=client.id,
        make_model=body.make_model.strip(),
        plate=(body.plate or "").strip(),
        vin=(body.vin or "").strip(),
        category=(body.category or "1").strip() or "1",
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.get("/orders", response_model=list[CrmOrderOut])
def list_orders(
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    orders = db.scalars(
        select(CrmOrder)
        .where(CrmOrder.company_id == company_id)
        .options(selectinload(CrmOrder.items), selectinload(CrmOrder.master_links))
        .order_by(CrmOrder.id.desc())
    ).all()
    client_ids = {o.client_id for o in orders}
    car_ids = {o.car_id for o in orders}
    clients = {
        c.id: c
        for c in db.scalars(select(CrmClient).where(CrmClient.id.in_(client_ids))).all()
    } if client_ids else {}
    cars = {
        c.id: c for c in db.scalars(select(CrmCar).where(CrmCar.id.in_(car_ids))).all()
    } if car_ids else {}
    return [_order_out(o, clients.get(o.client_id), cars.get(o.car_id)) for o in orders]


@router.post("/orders/clear-board")
def clear_board_orders(
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
    hard: bool = False,
    clients: bool = False,
):
    """Снять активные заказы с доски.

    По умолчанию: status → «Выдан» (прайс/клиенты не трогаем).
    hard=1: физически удалить все заказы компании (и оплаты по ним).
    clients=1: также удалить всех клиентов и авто (подразумевает hard).
    """
    company_id = _company_id(user)
    if clients:
        hard = True

    deleted_orders = 0
    deleted_clients = 0

    if hard:
        orders = list(
            db.scalars(select(CrmOrder).where(CrmOrder.company_id == company_id)).all()
        )
        ids = [o.id for o in orders]
        if ids:
            deleted_orders = _purge_orders_by_ids(db, ids)

        if clients:
            cl_rows = list(
                db.scalars(select(CrmClient).where(CrmClient.company_id == company_id)).all()
            )
            # авто: cascade delete-orphan с клиента; на всякий случай удалим явно
            db.execute(delete(CrmCar).where(CrmCar.company_id == company_id))
            for c in cl_rows:
                db.delete(c)
            deleted_clients = len(cl_rows)

        db.commit()
        return {
            "ok": True,
            "mode": "hard+clients" if clients else "hard",
            "deleted": deleted_orders,
            "deleted_clients": deleted_clients,
        }

    active = list(
        db.scalars(
            select(CrmOrder).where(
                CrmOrder.company_id == company_id,
                CrmOrder.status != "Выдан",
            )
        ).all()
    )
    for o in active:
        o.status = "Выдан"
    db.commit()
    return {"ok": True, "mode": "board", "cleared": len(active), "deleted_clients": 0}


@router.delete("/orders/{order_id}")
def delete_order(
    order_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    if _is_studio_master(user):
        raise HTTPException(status_code=403, detail="Мастер не может удалять заказы")
    company_id = _company_id(user)
    order = db.scalar(
        select(CrmOrder).where(CrmOrder.id == order_id, CrmOrder.company_id == company_id)
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Заказ не найден")
    _purge_orders_by_ids(db, [order_id])
    db.commit()
    return {"ok": True, "deleted": order_id}


@router.get("/orders/{order_id}", response_model=CrmOrderOut)
def get_order(
    order_id: int,
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    order = db.scalar(
        select(CrmOrder)
        .where(CrmOrder.id == order_id, CrmOrder.company_id == company_id)
        .options(selectinload(CrmOrder.items), selectinload(CrmOrder.master_links))
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Заказ не найден")
    client = db.get(CrmClient, order.client_id)
    car = db.get(CrmCar, order.car_id)
    return _order_out(order, client, car)


@router.post("/orders", response_model=CrmOrderOut)
def create_order(
    body: CrmOrderCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    if _is_studio_master(user):
        raise HTTPException(status_code=403, detail="Мастер не может создавать заказы")
    company_id = _company_id(user)
    client = db.scalar(
        select(CrmClient).where(CrmClient.id == body.client_id, CrmClient.company_id == company_id)
    )
    if client is None:
        raise HTTPException(status_code=404, detail="Клиент не найден")
    car = db.scalar(
        select(CrmCar).where(
            CrmCar.id == body.car_id,
            CrmCar.company_id == company_id,
            CrmCar.client_id == client.id,
        )
    )
    if car is None:
        raise HTTPException(status_code=404, detail="Авто не найдено")

    if body.branch_id is not None:
        branch = db.scalar(
            select(Branch).where(Branch.id == body.branch_id, Branch.company_id == company_id)
        )
        if branch is None:
            raise HTTPException(status_code=404, detail="Филиал не найден")
        branch_id = branch.id
    else:
        branch_id = _default_branch_id(db, user, company_id)

    total = sum(float(it.price or 0) for it in body.items)
    order = CrmOrder(
        company_id=company_id,
        branch_id=branch_id,
        client_id=client.id,
        car_id=car.id,
        status=body.status.strip() or "Принят в работу",
        notes=body.notes or "",
        due_date=body.due_date or "",
        start_time=getattr(body, "start_time", None) or "",
        end_time=getattr(body, "end_time", None) or "",
        end_date=getattr(body, "end_date", None) or "",
        client_notes=getattr(body, "client_notes", None) or "",
        client_visible_notes=getattr(body, "client_visible_notes", None) or "",
        master_notes=getattr(body, "master_notes", None) or "",
        payment_method=getattr(body, "payment_method", None) or "Наличные",
        discount_percent=float(getattr(body, "discount_percent", 0) or 0),
        discount_fixed=float(getattr(body, "discount_fixed", 0) or 0),
        promo_code=getattr(body, "promo_code", None) or "",
        price=total,
        paid_amount=0,
    )
    db.add(order)
    db.flush()
    for it in body.items:
        row = CrmOrderItem(order_id=order.id)
        _fill_item_from_in(row, it)
        db.add(row)
    for mid in getattr(body, "master_ids", None) or []:
        db.add(CrmOrderMaster(order_id=order.id, master_id=int(mid)))
    db.flush()
    db.refresh(order)
    _recalc_order_price(order)
    db.commit()
    order = db.scalar(
        select(CrmOrder)
        .where(CrmOrder.id == order.id)
        .options(selectinload(CrmOrder.items), selectinload(CrmOrder.master_links))
    )
    return _order_out(order, client, car)  # type: ignore[arg-type]


@router.patch("/orders/{order_id}", response_model=CrmOrderOut)
def update_order(
    order_id: int,
    body: CrmOrderUpdate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    order = db.scalar(
        select(CrmOrder)
        .where(CrmOrder.id == order_id, CrmOrder.company_id == company_id)
        .options(selectinload(CrmOrder.items), selectinload(CrmOrder.master_links))
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Заказ не найден")
    if _is_studio_master(user):
        # Мастер: только заметки мастера; даты/статус/скидки/выдача — нет.
        if (
            body.status is not None
            or body.due_date is not None
            or body.start_time is not None
            or body.end_time is not None
            or body.end_date is not None
            or body.discount_percent is not None
            or body.discount_fixed is not None
            or body.promo_code is not None
            or body.payment_method is not None
            or body.car_id is not None
            or any(
                getattr(body, k, None) is not None
                for k in (
                    "handover_ready",
                    "handover_works",
                    "handover_payment",
                    "handover_keys",
                    "handover_inspect",
                    "handover_notified",
                )
            )
        ):
            _forbid_master_order_meta(user)
    if body.status is not None:
        if body.status.strip() == "Выдан" and "orders.issue" not in user_permission_codes(user) and not user.is_platform_admin:
            raise HTTPException(status_code=403, detail="Нет права на выдачу заказа")
        order.status = body.status.strip()
    if body.notes is not None:
        order.notes = body.notes
    if body.due_date is not None:
        order.due_date = body.due_date
    if body.start_time is not None:
        order.start_time = body.start_time
    if body.end_time is not None:
        order.end_time = body.end_time
    if body.end_date is not None:
        order.end_date = body.end_date
    if body.client_notes is not None:
        order.client_notes = body.client_notes
    if body.client_visible_notes is not None:
        order.client_visible_notes = body.client_visible_notes
    if body.master_notes is not None:
        order.master_notes = body.master_notes
    if body.payment_method is not None:
        order.payment_method = body.payment_method
    discount_changed = False
    if body.discount_percent is not None:
        order.discount_percent = float(body.discount_percent)
        discount_changed = True
    if body.discount_fixed is not None:
        order.discount_fixed = float(body.discount_fixed)
        discount_changed = True
    if body.promo_code is not None:
        order.promo_code = body.promo_code
    for hand_key in (
        "handover_ready",
        "handover_works",
        "handover_payment",
        "handover_keys",
        "handover_inspect",
        "handover_notified",
    ):
        val = getattr(body, hand_key, None)
        if val is not None:
            setattr(order, hand_key, bool(val))
    if body.tech_wash_start is not None:
        order.tech_wash_start = body.tech_wash_start
    if body.tech_wash_end is not None:
        order.tech_wash_end = body.tech_wash_end
    if body.is_workshop_completed is not None:
        order.is_workshop_completed = bool(body.is_workshop_completed)
    if body.paid_amount is not None:
        order.paid_amount = float(body.paid_amount)
    if body.car_id is not None:
        car = db.scalar(
            select(CrmCar).where(
                CrmCar.id == body.car_id,
                CrmCar.company_id == company_id,
                CrmCar.client_id == order.client_id,
            )
        )
        if car is None:
            raise HTTPException(status_code=404, detail="Авто не найдено")
        order.car_id = car.id
    if body.master_ids is not None:
        for old in list(order.master_links):
            db.delete(old)
        db.flush()
        for mid in body.master_ids:
            db.add(CrmOrderMaster(order_id=order.id, master_id=int(mid)))
    if "receptionist_id" in body.model_fields_set:
        order.receptionist_id = body.receptionist_id
    if body.items is not None:
        existing = {it.id: it for it in list(order.items)}
        keep: set[int] = set()
        for it in body.items:
            if it.id is not None and it.id in existing:
                row = existing[it.id]
                _fill_item_from_in(row, it)
                keep.add(it.id)
            else:
                row = CrmOrderItem(order_id=order.id)
                _fill_item_from_in(row, it)
                db.add(row)
                db.flush()
                keep.add(row.id)
        for oid, old in existing.items():
            if oid not in keep:
                db.delete(old)
        db.flush()
        db.refresh(order)
        _recalc_order_price(order)
    elif discount_changed:
        _recalc_order_price(order)
    db.commit()
    order = db.scalar(
        select(CrmOrder)
        .where(CrmOrder.id == order_id)
        .options(selectinload(CrmOrder.items), selectinload(CrmOrder.master_links))
    )
    client = db.get(CrmClient, order.client_id)  # type: ignore[union-attr]
    car = db.get(CrmCar, order.car_id)  # type: ignore[union-attr]
    return _order_out(order, client, car)  # type: ignore[arg-type]


@router.patch("/cars/{car_id}", response_model=CrmCarOut)
def update_car(
    car_id: int,
    body: CrmCarUpdate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    row = db.scalar(select(CrmCar).where(CrmCar.id == car_id, CrmCar.company_id == company_id))
    if row is None:
        raise HTTPException(status_code=404, detail="Авто не найдено")
    if body.make_model is not None:
        row.make_model = body.make_model.strip()
    if body.plate is not None:
        row.plate = body.plate.strip()
    if body.vin is not None:
        row.vin = body.vin.strip()
    if body.category is not None:
        row.category = (body.category or "1").strip() or "1"
    db.commit()
    db.refresh(row)
    return row


@router.delete("/cars/{car_id}")
def delete_car(
    car_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    row = db.scalar(select(CrmCar).where(CrmCar.id == car_id, CrmCar.company_id == company_id))
    if row is None:
        raise HTTPException(status_code=404, detail="Авто не найдено")
    order_ids = list(
        db.scalars(
            select(CrmOrder.id).where(CrmOrder.company_id == company_id, CrmOrder.car_id == car_id)
        ).all()
    )
    deleted_orders = _purge_orders_by_ids(db, order_ids)
    db.delete(row)
    db.commit()
    return {"ok": True, "deleted": car_id, "deleted_orders": deleted_orders}


@router.post("/orders/{order_id}/items", response_model=CrmOrderItemOut)
def create_order_item(
    order_id: int,
    body: CrmOrderItemIn,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    if _is_studio_master(user):
        _forbid_master_order_meta(user)
    order = _get_company_order(db, order_id, company_id)
    row = CrmOrderItem(order_id=order.id)
    _fill_item_from_in(row, body)
    db.add(row)
    db.flush()
    db.refresh(order)
    _recalc_order_price(order)
    db.commit()
    db.refresh(row)
    return _item_out(row)


@router.patch("/orders/{order_id}/items/{item_id}", response_model=CrmOrderItemOut)
def patch_order_item(
    order_id: int,
    item_id: int,
    body: CrmOrderItemPatch,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    order = _get_company_order(db, order_id, company_id)
    row = next((it for it in order.items if it.id == item_id), None)
    if row is None:
        raise HTTPException(status_code=404, detail="Позиция не найдена")
    if _is_studio_master(user):
        if body.price is not None or body.name is not None or body.workshop is not None or body.parent_id is not None:
            _forbid_master_order_meta(user)
        _assert_master_item_workshop(db, user, row.workshop)
    if body.name is not None:
        row.name = body.name.strip()
    if body.price is not None:
        row.price = float(body.price)
    if body.workshop is not None:
        row.workshop = body.workshop
    if body.is_done is not None:
        row.is_done = bool(body.is_done)
    if body.comment is not None:
        row.comment = body.comment
    if body.master_ids is not None:
        row.master_ids = body.master_ids
    if body.start_time is not None:
        row.start_time = body.start_time
    if body.end_time is not None:
        row.end_time = body.end_time
    if body.parent_id is not None:
        row.parent_id = body.parent_id
    db.flush()
    _recalc_order_price(order)
    db.commit()
    db.refresh(row)
    return _item_out(row)


@router.delete("/orders/{order_id}/items/{item_id}")
def delete_order_item(
    order_id: int,
    item_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    if _is_studio_master(user):
        _forbid_master_order_meta(user)
    order = _get_company_order(db, order_id, company_id)
    row = next((it for it in order.items if it.id == item_id), None)
    if row is None:
        raise HTTPException(status_code=404, detail="Позиция не найдена")
    # Пакет оклейки/тонировки: шапка удаляет все зоны (FK CASCADE на старых БД может не быть).
    children = [it for it in list(order.items) if it.parent_id == item_id]
    for child in children:
        db.delete(child)
    db.delete(row)
    db.flush()
    db.refresh(order)
    _recalc_order_price(order)
    db.commit()
    return {"ok": True}


@router.get("/orders/{order_id}/events", response_model=list[CrmOrderEventOut])
def list_order_events(
    order_id: int,
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    _get_company_order(db, order_id, company_id)
    rows = db.scalars(
        select(CrmOrderEvent)
        .where(CrmOrderEvent.order_id == order_id, CrmOrderEvent.company_id == company_id)
        .order_by(CrmOrderEvent.id.desc())
    ).all()
    return [
        CrmOrderEventOut(
            id=r.id,
            order_id=r.order_id,
            event_text=r.event_text,
            created_at=r.created_at,
        )
        for r in rows
    ]


@router.post("/orders/{order_id}/events", response_model=CrmOrderEventOut)
def create_order_event(
    order_id: int,
    body: CrmOrderEventCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
    _get_company_order(db, order_id, company_id)
    text = (body.event_text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Пустое событие")
    row = CrmOrderEvent(company_id=company_id, order_id=order_id, event_text=text)
    db.add(row)
    db.commit()
    db.refresh(row)
    return CrmOrderEventOut(
        id=row.id,
        order_id=row.order_id,
        event_text=row.event_text,
        created_at=row.created_at,
    )
