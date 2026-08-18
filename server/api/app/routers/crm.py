from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db import get_db
from app.deps import require_permissions
from app.models import (
    Branch,
    CrmCar,
    CrmClient,
    CrmOrder,
    CrmOrderItem,
    CrmOrderMaster,
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


def _recalc_order_price(order: CrmOrder) -> None:
    order.price = sum(float(it.price or 0) for it in (order.items or []))


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
        master_ids=master_ids,
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
    if body.status is not None:
        order.status = body.status.strip()
    if body.notes is not None:
        order.notes = body.notes
    if body.due_date is not None:
        order.due_date = body.due_date
    if body.start_time is not None:
        order.start_time = body.start_time
    if body.end_time is not None:
        order.end_time = body.end_time
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


@router.post("/orders/{order_id}/items", response_model=CrmOrderItemOut)
def create_order_item(
    order_id: int,
    body: CrmOrderItemIn,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    company_id = _company_id(user)
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
    order = _get_company_order(db, order_id, company_id)
    row = next((it for it in order.items if it.id == item_id), None)
    if row is None:
        raise HTTPException(status_code=404, detail="Позиция не найдена")
    db.delete(row)
    db.flush()
    db.refresh(order)
    _recalc_order_price(order)
    db.commit()
    return {"ok": True}
