"""Masters, services, defects, inventory, import — C3..C6."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.crm_extra_schemas import (
    CrmDefectCreate,
    CrmDefectOut,
    CrmImportClients,
    CrmInventoryCreate,
    CrmInventoryMoveCreate,
    CrmInventoryMoveOut,
    CrmInventoryOut,
    CrmMasterCreate,
    CrmMasterOut,
    CrmMasterUpdate,
    CrmServiceCreate,
    CrmServiceOut,
    CrmServiceUpdate,
)
from app.db import get_db
from app.deps import require_permissions
from app.models import (
    CrmCar,
    CrmClient,
    CrmDefect,
    CrmInventoryItem,
    CrmInventoryMove,
    CrmMaster,
    CrmOrder,
    CrmService,
    User,
)
from app.routers.crm import _company_id

router = APIRouter(prefix="/crm", tags=["crm-extra"])


# --- Masters ---


@router.get("/masters", response_model=list[CrmMasterOut])
def list_masters(
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    return list(
        db.scalars(select(CrmMaster).where(CrmMaster.company_id == cid).order_by(CrmMaster.id)).all()
    )


@router.post("/masters", response_model=CrmMasterOut)
def create_master(
    body: CrmMasterCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = CrmMaster(company_id=cid, name=body.name.strip(), role=body.role or "Универсал")
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.patch("/masters/{master_id}", response_model=CrmMasterOut)
def update_master(
    master_id: int,
    body: CrmMasterUpdate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(select(CrmMaster).where(CrmMaster.id == master_id, CrmMaster.company_id == cid))
    if row is None:
        raise HTTPException(404, "Мастер не найден")
    if body.name is not None:
        row.name = body.name.strip()
    if body.role is not None:
        row.role = body.role
    if body.is_active is not None:
        row.is_active = body.is_active
    db.commit()
    db.refresh(row)
    return row


# --- Services ---


@router.get("/services", response_model=list[CrmServiceOut])
def list_services(
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    return list(
        db.scalars(
            select(CrmService).where(CrmService.company_id == cid).order_by(CrmService.category, CrmService.name)
        ).all()
    )


@router.post("/services", response_model=CrmServiceOut)
def create_service(
    body: CrmServiceCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = CrmService(
        company_id=cid,
        name=body.name.strip(),
        category=body.category or "Прочее",
        price=float(body.price or 0),
        workshop=body.workshop or "",
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.patch("/services/{service_id}", response_model=CrmServiceOut)
def update_service(
    service_id: int,
    body: CrmServiceUpdate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(select(CrmService).where(CrmService.id == service_id, CrmService.company_id == cid))
    if row is None:
        raise HTTPException(404, "Услуга не найдена")
    if body.name is not None:
        row.name = body.name.strip()
    if body.category is not None:
        row.category = body.category
    if body.price is not None:
        row.price = float(body.price)
    if body.workshop is not None:
        row.workshop = body.workshop
    if body.is_active is not None:
        row.is_active = body.is_active
    db.commit()
    db.refresh(row)
    return row


# --- Defects ---


@router.get("/orders/{order_id}/defects", response_model=list[CrmDefectOut])
def list_defects(
    order_id: int,
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    order = db.scalar(select(CrmOrder).where(CrmOrder.id == order_id, CrmOrder.company_id == cid))
    if order is None:
        raise HTTPException(404, "Заказ не найден")
    rows = db.scalars(
        select(CrmDefect).where(CrmDefect.order_id == order_id).order_by(CrmDefect.id.desc())
    ).all()
    return [
        CrmDefectOut(
            id=r.id,
            order_id=r.order_id,
            workshop=r.workshop,
            description=r.description,
            photo_b64=r.photo_b64 or "",
            created_at=r.created_at.isoformat() if r.created_at else None,
        )
        for r in rows
    ]


@router.post("/orders/{order_id}/defects", response_model=CrmDefectOut)
def create_defect(
    order_id: int,
    body: CrmDefectCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    order = db.scalar(select(CrmOrder).where(CrmOrder.id == order_id, CrmOrder.company_id == cid))
    if order is None:
        raise HTTPException(404, "Заказ не найден")
    row = CrmDefect(
        company_id=cid,
        order_id=order.id,
        workshop=body.workshop or "",
        description=body.description or "",
        photo_b64=body.photo_b64 or "",
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return CrmDefectOut(
        id=row.id,
        order_id=row.order_id,
        workshop=row.workshop,
        description=row.description,
        photo_b64=row.photo_b64 or "",
        created_at=row.created_at.isoformat() if row.created_at else None,
    )


# --- Inventory ---


@router.get("/inventory", response_model=list[CrmInventoryOut])
def list_inventory(
    user: User = Depends(require_permissions("inventory.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    return list(
        db.scalars(
            select(CrmInventoryItem).where(CrmInventoryItem.company_id == cid).order_by(CrmInventoryItem.name)
        ).all()
    )


@router.post("/inventory", response_model=CrmInventoryOut)
def create_inventory(
    body: CrmInventoryCreate,
    user: User = Depends(require_permissions("inventory.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = CrmInventoryItem(
        company_id=cid,
        name=body.name.strip(),
        quantity=float(body.quantity or 0),
        unit=body.unit or "шт",
        category=body.category or "Прочее",
        min_qty=float(body.min_qty or 0),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.post("/inventory/moves", response_model=CrmInventoryMoveOut)
def create_inventory_move(
    body: CrmInventoryMoveCreate,
    user: User = Depends(require_permissions("inventory.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    item = db.scalar(
        select(CrmInventoryItem).where(
            CrmInventoryItem.id == body.item_id, CrmInventoryItem.company_id == cid
        )
    )
    if item is None:
        raise HTTPException(404, "Позиция не найдена")
    delta = float(body.delta)
    item.quantity = float(item.quantity or 0) + delta
    move = CrmInventoryMove(
        company_id=cid,
        item_id=item.id,
        delta=delta,
        balance_after=float(item.quantity),
        reason=body.reason or "adjust",
        order_id=body.order_id,
        note=body.note or "",
    )
    db.add(move)
    db.commit()
    db.refresh(move)
    return move


# --- Import ---


@router.post("/import/clients")
def import_clients(
    body: CrmImportClients,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    """Разовый импорт [{name, phone, cars:[{make_model, plate}]}]"""
    cid = _company_id(user)
    created = 0
    for raw in body.clients:
        name = str(raw.get("name") or "").strip()
        if not name:
            continue
        client = CrmClient(
            company_id=cid,
            name=name,
            phone=str(raw.get("phone") or "").strip(),
            is_vip=bool(raw.get("is_vip")),
        )
        db.add(client)
        db.flush()
        for car in raw.get("cars") or []:
            mm = str(car.get("make_model") or car.get("name") or "").strip()
            if not mm:
                continue
            db.add(
                CrmCar(
                    company_id=cid,
                    client_id=client.id,
                    make_model=mm,
                    plate=str(car.get("plate") or "").strip(),
                    vin=str(car.get("vin") or "").strip(),
                    category=str(car.get("category") or "1"),
                )
            )
        created += 1
    db.commit()
    return {"ok": True, "created": created}
