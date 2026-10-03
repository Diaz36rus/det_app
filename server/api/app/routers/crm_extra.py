"""Masters, services, defects, inventory, import, stats — C3..C7."""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session, selectinload

from app.crm_extra_schemas import (
    CrmCarWarrantyCreate,
    CrmCarWarrantyOut,
    CrmCarWarrantyUpcomingOut,
    CrmCarWarrantyUpdate,
    CrmDefectCreate,
    CrmDefectOut,
    CrmFilmRollCreate,
    CrmFilmRollOut,
    CrmImportClients,
    CrmInventoryCreate,
    CrmInventoryMoveCreate,
    CrmInventoryMoveOut,
    CrmInventoryOut,
    CrmInventoryUpdate,
    CrmMasterCreate,
    CrmMasterOnShiftIn,
    CrmMasterOut,
    CrmMasterUpdate,
    CrmOrderWrapFilmOut,
    CrmOrderWrapFilmsPut,
    CrmOrderWrapFilmsPutResult,
    CrmPayrollRuleCreate,
    CrmPayrollRuleOut,
    CrmPromocodeCreate,
    CrmPromocodeOut,
    CrmRecipeApply,
    CrmRecipeApplyResult,
    CrmRecipeOut,
    CrmRecipeUpsert,
    CrmServiceCreate,
    CrmServiceOut,
    CrmServiceUpdate,
    CrmStatsOut,
    CrmStudioLeadCreate,
    CrmStudioLeadOut,
    CrmStudioLeadUpdate,
    CrmWorkshopRoleCreate,
    CrmWorkshopRoleOut,
    CrmWrapFilmOut,
)
from app.db import get_db
from app.deps import require_permissions
from app.lead_util import create_studio_lead
from app.models import (
    Branch,
    CashFlow,
    CrmCar,
    CrmCarWarranty,
    CrmClient,
    CrmDefect,
    CrmFilmRoll,
    CrmInventoryItem,
    CrmInventoryMove,
    CrmMaster,
    CrmOrder,
    CrmOrderWorkshopPayroll,
    CrmOrderWrapFilm,
    CrmPayrollRule,
    CrmPromocode,
    CrmService,
    CrmServiceRecipe,
    CrmStudioLead,
    CrmWorkshopRole,
    User,
)
from app.routers.crm import _company_id

router = APIRouter(prefix="/crm", tags=["crm-extra"])

_COMPLETED = "Выдан"
_MASTER_DAY_STATUSES = {
    "Мойка",
    "Химчистка",
    "Полировка",
    "Оклейка",
    "Интерьер",
    "Оборудование",
    "Кузовные работы",
    "Выдан",
}


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


@router.get("/masters/on-shift", response_model=list[CrmMasterOut])
def list_masters_on_shift(
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    return list(
        db.scalars(
            select(CrmMaster)
            .where(
                CrmMaster.company_id == cid,
                CrmMaster.is_active.is_(True),
                CrmMaster.on_shift.is_(True),
            )
            .order_by(CrmMaster.name)
        ).all()
    )


@router.put("/me/on-shift", response_model=CrmMasterOut)
def set_my_on_shift(
    body: CrmMasterOnShiftIn,
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    """Текущий пользователь (привязанный к мастеру) включает/выключает «На смене»."""
    cid = _company_id(user)
    mid = getattr(user, "master_id", None)
    if mid is None:
        raise HTTPException(
            400,
            "Аккаунт не привязан к мастеру — попросите админа связать профиль",
        )
    row = db.scalar(
        select(CrmMaster).where(
            CrmMaster.id == int(mid),
            CrmMaster.company_id == cid,
            CrmMaster.is_active.is_(True),
        )
    )
    if row is None:
        raise HTTPException(404, "Мастер не найден")
    row.on_shift = bool(body.on_shift)
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
    if body.on_shift is not None:
        row.on_shift = bool(body.on_shift)
    db.commit()
    db.refresh(row)
    return row


@router.delete("/masters/{master_id}")
def delete_master(
    master_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    """Soft-delete: is_active=False (заказы/смены могут ссылаться на мастера)."""
    cid = _company_id(user)
    row = db.scalar(select(CrmMaster).where(CrmMaster.id == master_id, CrmMaster.company_id == cid))
    if row is None:
        raise HTTPException(404, "Мастер не найден")
    row.is_active = False
    row.on_shift = False
    db.commit()
    db.refresh(row)
    return {"ok": True, "deleted": master_id, "is_active": False}


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
        price2=float(body.price2 or 0),
        price3=float(body.price3 or 0),
        price4=float(body.price4 or 0),
        fixed_price=float(body.fixed_price or 0),
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
    if body.price2 is not None:
        row.price2 = float(body.price2)
    if body.price3 is not None:
        row.price3 = float(body.price3)
    if body.price4 is not None:
        row.price4 = float(body.price4)
    if body.fixed_price is not None:
        row.fixed_price = float(body.fixed_price)
    if body.workshop is not None:
        row.workshop = body.workshop
    if body.is_active is not None:
        row.is_active = body.is_active
    db.commit()
    db.refresh(row)
    return row


@router.delete("/services/{service_id}")
def delete_service(
    service_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    """Soft-delete: is_active=False."""
    cid = _company_id(user)
    row = db.scalar(select(CrmService).where(CrmService.id == service_id, CrmService.company_id == cid))
    if row is None:
        raise HTTPException(404, "Услуга не найдена")
    row.is_active = False
    db.commit()
    db.refresh(row)
    return {"ok": True, "deleted": service_id, "is_active": False}


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


@router.delete("/defects/{defect_id}")
def delete_defect(
    defect_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmDefect).where(CrmDefect.id == defect_id, CrmDefect.company_id == cid)
    )
    if row is None:
        raise HTTPException(404, "Дефект не найден")
    db.delete(row)
    db.commit()
    return {"ok": True, "deleted": defect_id}


@router.delete("/orders/{order_id}/defects/{defect_id}")
def delete_order_defect(
    order_id: int,
    defect_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    order = db.scalar(select(CrmOrder).where(CrmOrder.id == order_id, CrmOrder.company_id == cid))
    if order is None:
        raise HTTPException(404, "Заказ не найден")
    row = db.scalar(
        select(CrmDefect).where(
            CrmDefect.id == defect_id,
            CrmDefect.order_id == order_id,
            CrmDefect.company_id == cid,
        )
    )
    if row is None:
        raise HTTPException(404, "Дефект не найден")
    db.delete(row)
    db.commit()
    return {"ok": True, "deleted": defect_id}


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
    name = body.name.strip()
    category = (body.category or "Прочее").strip() or "Прочее"
    # Идемпотентность: не плодим дубли по имени+категории (сид склада / повторные POST).
    existing = db.scalar(
        select(CrmInventoryItem).where(
            CrmInventoryItem.company_id == cid,
            CrmInventoryItem.category == category,
            CrmInventoryItem.name == name,
        )
    )
    if existing is not None:
        return existing
    row = CrmInventoryItem(
        company_id=cid,
        name=name,
        quantity=float(body.quantity or 0),
        unit=body.unit or "шт",
        category=category,
        min_qty=float(body.min_qty or 0),
        meters_per_roll=float(getattr(body, "meters_per_roll", 0) or 0),
        unit_cost=float(getattr(body, "unit_cost", 0) or 0),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.post("/inventory/dedupe")
def dedupe_inventory(
    user: User = Depends(require_permissions("inventory.write")),
    db: Session = Depends(get_db),
):
    """Схлопывает дубли склада: одна позиция на (category, lower(name))."""
    cid = _company_id(user)
    rows = list(
        db.scalars(select(CrmInventoryItem).where(CrmInventoryItem.company_id == cid)).all()
    )
    groups: dict[tuple[str, str], list[CrmInventoryItem]] = {}
    for row in rows:
        key = ((row.category or "").strip().lower(), (row.name or "").strip().lower())
        groups.setdefault(key, []).append(row)

    removed = 0
    for items in groups.values():
        if len(items) < 2:
            continue
        items.sort(key=lambda r: int(r.id))
        keep = items[0]
        keep.quantity = float(sum(float(i.quantity or 0) for i in items))
        keep.min_qty = max(float(i.min_qty or 0) for i in items)
        if not (keep.unit or "").strip():
            for i in items:
                if (i.unit or "").strip():
                    keep.unit = i.unit
                    break
        keep.meters_per_roll = max(float(i.meters_per_roll or 0) for i in items)

        for dup in items[1:]:
            dup_id = int(dup.id)
            keep_id = int(keep.id)
            # Рулоны: перенос или слияние метров при конфликте номера.
            keep_roll_nums = {
                (r.roll_number or "").strip().lower()
                for r in db.scalars(
                    select(CrmFilmRoll).where(
                        CrmFilmRoll.company_id == cid,
                        CrmFilmRoll.inventory_id == keep_id,
                    )
                ).all()
            }
            for roll in list(
                db.scalars(
                    select(CrmFilmRoll).where(
                        CrmFilmRoll.company_id == cid,
                        CrmFilmRoll.inventory_id == dup_id,
                    )
                ).all()
            ):
                rn = (roll.roll_number or "").strip().lower()
                if rn in keep_roll_nums:
                    # Сливаем остаток в любой рулон keep с тем же номером, дубль дропаем.
                    twin = db.scalar(
                        select(CrmFilmRoll).where(
                            CrmFilmRoll.company_id == cid,
                            CrmFilmRoll.inventory_id == keep_id,
                            CrmFilmRoll.roll_number == roll.roll_number,
                        )
                    )
                    if twin is not None:
                        twin.meters_left = float(twin.meters_left or 0) + float(roll.meters_left or 0)
                    db.delete(roll)
                else:
                    roll.inventory_id = keep_id
                    keep_roll_nums.add(rn)

            db.execute(
                update(CrmOrderWrapFilm)
                .where(CrmOrderWrapFilm.film_id == dup_id, CrmOrderWrapFilm.company_id == cid)
                .values(film_id=keep_id)
            )
            db.execute(
                update(CrmInventoryMove)
                .where(CrmInventoryMove.item_id == dup_id, CrmInventoryMove.company_id == cid)
                .values(item_id=keep_id)
            )
            db.execute(
                update(CashFlow)
                .where(CashFlow.inventory_id == dup_id, CashFlow.company_id == cid)
                .values(inventory_id=keep_id)
            )
            # Рецепты: если уже есть на keep — просто дропаем дубль (CASCADE).
            keep_recipe_keys = {
                (r.service_name or "").strip().lower()
                for r in db.scalars(
                    select(CrmServiceRecipe).where(
                        CrmServiceRecipe.company_id == cid,
                        CrmServiceRecipe.inventory_id == keep_id,
                    )
                ).all()
            }
            for recipe in list(
                db.scalars(
                    select(CrmServiceRecipe).where(
                        CrmServiceRecipe.company_id == cid,
                        CrmServiceRecipe.inventory_id == dup_id,
                    )
                ).all()
            ):
                sk = (recipe.service_name or "").strip().lower()
                if sk in keep_recipe_keys:
                    db.delete(recipe)
                else:
                    recipe.inventory_id = keep_id
                    keep_recipe_keys.add(sk)
            db.delete(dup)
            removed += 1

    db.commit()
    return {"ok": True, "removed": removed, "groups": len(groups)}


@router.patch("/inventory/{item_id}", response_model=CrmInventoryOut)
def update_inventory(
    item_id: int,
    body: CrmInventoryUpdate,
    user: User = Depends(require_permissions("inventory.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    item = db.scalar(
        select(CrmInventoryItem).where(
            CrmInventoryItem.id == item_id, CrmInventoryItem.company_id == cid
        )
    )
    if item is None:
        raise HTTPException(404, "Позиция не найдена")
    old_qty = float(item.quantity or 0)
    if body.name is not None:
        item.name = body.name.strip()
    if body.unit is not None:
        item.unit = body.unit
    if body.category is not None:
        item.category = body.category
    if body.min_qty is not None:
        item.min_qty = float(body.min_qty)
    if body.meters_per_roll is not None:
        item.meters_per_roll = float(body.meters_per_roll)
    if body.unit_cost is not None:
        item.unit_cost = float(body.unit_cost)
    if body.quantity is not None:
        item.quantity = float(body.quantity)
        delta = float(body.quantity) - old_qty
        if abs(delta) > 0.0001:
            db.add(
                CrmInventoryMove(
                    company_id=cid,
                    item_id=item.id,
                    delta=delta,
                    balance_after=float(item.quantity),
                    reason="inventory_count",
                    note="Инвентаризация / правка остатка",
                )
            )
    db.commit()
    db.refresh(item)
    return item


@router.delete("/inventory/{item_id}")
def delete_inventory(
    item_id: int,
    user: User = Depends(require_permissions("inventory.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    item = db.scalar(
        select(CrmInventoryItem).where(
            CrmInventoryItem.id == item_id, CrmInventoryItem.company_id == cid
        )
    )
    if item is None:
        raise HTTPException(404, "Позиция не найдена")
    db.execute(delete(CrmOrderWrapFilm).where(CrmOrderWrapFilm.film_id == item_id))
    db.execute(
        update(CashFlow).where(CashFlow.inventory_id == item_id).values(inventory_id=None)
    )
    # rolls / moves / recipes cascade via ondelete=CASCADE
    db.delete(item)
    db.commit()
    return {"ok": True, "deleted": item_id}


@router.get("/inventory/moves", response_model=list[CrmInventoryMoveOut])
def list_inventory_moves(
    item_id: int | None = None,
    limit: int = 100,
    user: User = Depends(require_permissions("inventory.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    q = select(CrmInventoryMove).where(CrmInventoryMove.company_id == cid)
    if item_id is not None:
        q = q.where(CrmInventoryMove.item_id == item_id)
    rows = db.scalars(q.order_by(CrmInventoryMove.id.desc()).limit(max(1, min(limit, 500)))).all()
    return list(rows)


def _own_order_id(db: Session, cid: int, order_id: int | None) -> int | None:
    """Ссылка на заказ только своей студии; иначе без привязки."""
    if not order_id:
        return None
    hit = db.scalar(select(CrmOrder.id).where(CrmOrder.id == order_id, CrmOrder.company_id == cid))
    return int(hit) if hit is not None else None


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
        order_id=_own_order_id(db, cid, body.order_id),
        note=body.note or "",
    )
    db.add(move)
    db.commit()
    db.refresh(move)
    return move


# --- Recipes ---


def _recipe_out(row: CrmServiceRecipe, inv: CrmInventoryItem | None) -> CrmRecipeOut:
    return CrmRecipeOut(
        id=row.id,
        service_name=row.service_name,
        inventory_id=row.inventory_id,
        qty=float(row.qty or 0),
        inventory_name=inv.name if inv else "",
        unit=(inv.unit if inv else "шт") or "шт",
        stock=float(inv.quantity) if inv else 0.0,
        unit_cost=float(getattr(inv, "unit_cost", 0) or 0) if inv else 0.0,
    )


@router.get("/recipes", response_model=list[CrmRecipeOut])
def list_recipes(
    service_name: str,
    user: User = Depends(require_permissions("inventory.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    name = (service_name or "").strip()
    rows = db.scalars(
        select(CrmServiceRecipe)
        .where(CrmServiceRecipe.company_id == cid, CrmServiceRecipe.service_name == name)
        .order_by(CrmServiceRecipe.id)
    ).all()
    return [_recipe_out(r, db.get(CrmInventoryItem, r.inventory_id)) for r in rows]


@router.put("/recipes")
def upsert_recipe(
    body: CrmRecipeUpsert,
    user: User = Depends(require_permissions("inventory.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    name = body.service_name.strip()
    inv = db.scalar(
        select(CrmInventoryItem).where(
            CrmInventoryItem.id == body.inventory_id, CrmInventoryItem.company_id == cid
        )
    )
    if inv is None:
        raise HTTPException(404, "Позиция не найдена")
    existing = db.scalar(
        select(CrmServiceRecipe).where(
            CrmServiceRecipe.company_id == cid,
            CrmServiceRecipe.service_name == name,
            CrmServiceRecipe.inventory_id == inv.id,
        )
    )
    qty = float(body.qty or 0)
    if qty <= 0:
        if existing is not None:
            db.delete(existing)
            db.commit()
        return {"ok": True, "deleted": True}
    if existing is None:
        existing = CrmServiceRecipe(
            company_id=cid,
            service_name=name,
            inventory_id=inv.id,
            qty=qty,
        )
        db.add(existing)
    else:
        existing.qty = qty
    db.commit()
    db.refresh(existing)
    return _recipe_out(existing, inv)


@router.delete("/recipes/{recipe_id}")
def delete_recipe(
    recipe_id: int,
    user: User = Depends(require_permissions("inventory.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmServiceRecipe).where(
            CrmServiceRecipe.id == recipe_id, CrmServiceRecipe.company_id == cid
        )
    )
    if row is None:
        raise HTTPException(404, "Рецепт не найден")
    db.delete(row)
    db.commit()
    return {"ok": True}


@router.post("/recipes/deduct", response_model=CrmRecipeApplyResult)
def deduct_recipe(
    body: CrmRecipeApply,
    user: User = Depends(require_permissions("inventory.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    name = body.service_name.strip()
    order_id = _own_order_id(db, cid, body.order_id)
    warnings: list[str] = []
    rows = db.scalars(
        select(CrmServiceRecipe).where(
            CrmServiceRecipe.company_id == cid, CrmServiceRecipe.service_name == name
        )
    ).all()
    for r in rows:
        qty = float(r.qty or 0)
        if qty <= 0:
            continue
        inv = db.get(CrmInventoryItem, r.inventory_id)
        if inv is None or inv.company_id != cid:
            continue
        stock = float(inv.quantity or 0)
        if stock + 0.001 < qty:
            warnings.append(f"{inv.name}: нужно {qty}, есть {stock}")
        inv.quantity = stock - qty
        db.add(
            CrmInventoryMove(
                company_id=cid,
                item_id=inv.id,
                delta=-qty,
                balance_after=float(inv.quantity),
                reason="recipe_deduct",
                order_id=order_id,
                note=f"Рецепт: {name}",
            )
        )
    db.commit()
    return CrmRecipeApplyResult(warnings=warnings)


@router.post("/recipes/restore", response_model=CrmRecipeApplyResult)
def restore_recipe(
    body: CrmRecipeApply,
    user: User = Depends(require_permissions("inventory.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    name = body.service_name.strip()
    order_id = _own_order_id(db, cid, body.order_id)
    rows = db.scalars(
        select(CrmServiceRecipe).where(
            CrmServiceRecipe.company_id == cid, CrmServiceRecipe.service_name == name
        )
    ).all()
    for r in rows:
        qty = float(r.qty or 0)
        if qty <= 0:
            continue
        inv = db.get(CrmInventoryItem, r.inventory_id)
        if inv is None or inv.company_id != cid:
            continue
        inv.quantity = float(inv.quantity or 0) + qty
        db.add(
            CrmInventoryMove(
                company_id=cid,
                item_id=inv.id,
                delta=qty,
                balance_after=float(inv.quantity),
                reason="recipe_restore",
                order_id=order_id,
                note=f"Возврат рецепта: {name}",
            )
        )
    db.commit()
    return CrmRecipeApplyResult(warnings=[])


# --- Film rolls / wrap films ---

_FILM_CATEGORIES = {"Плёнка оклейка", "Плёнка тонировка"}


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


def _order_wrap_out(
    row: CrmOrderWrapFilm,
    inv: CrmInventoryItem | None,
    roll: CrmFilmRoll | None,
) -> CrmOrderWrapFilmOut:
    return CrmOrderWrapFilmOut(
        id=row.id,
        order_id=row.order_id,
        film_id=row.film_id,
        roll_id=row.roll_id,
        meters=float(row.meters or 0),
        film_name=inv.name if inv else "",
        roll_number=roll.roll_number if roll else None,
        roll_meters_left=float(roll.meters_left) if roll else None,
        inventory_id=row.film_id,
    )


@router.get("/wrap-films", response_model=list[CrmWrapFilmOut])
def list_wrap_films(
    user: User = Depends(require_permissions("inventory.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    items = db.scalars(
        select(CrmInventoryItem)
        .where(CrmInventoryItem.company_id == cid, CrmInventoryItem.category.in_(_FILM_CATEGORIES))
        .order_by(CrmInventoryItem.category, CrmInventoryItem.name)
    ).all()
    out: list[CrmWrapFilmOut] = []
    for it in items:
        rolls = list(db.scalars(select(CrmFilmRoll).where(CrmFilmRoll.inventory_id == it.id)).all())
        stock = float(sum(float(r.meters_left or 0) for r in rolls))
        out.append(
            CrmWrapFilmOut(
                id=it.id,
                name=it.name,
                inventory_id=it.id,
                stock_meters=stock,
                meters_per_roll=float(getattr(it, "meters_per_roll", 0) or 0),
                inventory_category=it.category or "",
                unit=it.unit or "м",
            )
        )
    return out


@router.get("/film-rolls", response_model=list[CrmFilmRollOut])
def list_film_rolls(
    inventory_id: int,
    only_with_stock: bool = False,
    user: User = Depends(require_permissions("inventory.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    inv = db.scalar(
        select(CrmInventoryItem).where(
            CrmInventoryItem.id == inventory_id, CrmInventoryItem.company_id == cid
        )
    )
    if inv is None:
        raise HTTPException(404, "Позиция не найдена")
    q = select(CrmFilmRoll).where(
        CrmFilmRoll.company_id == cid, CrmFilmRoll.inventory_id == inventory_id
    )
    if only_with_stock:
        q = q.where(CrmFilmRoll.meters_left > 0.001)
    return list(db.scalars(q.order_by(CrmFilmRoll.roll_number)).all())


@router.post("/film-rolls", response_model=CrmFilmRollOut)
def create_film_roll(
    body: CrmFilmRollCreate,
    user: User = Depends(require_permissions("inventory.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    inv = db.scalar(
        select(CrmInventoryItem).where(
            CrmInventoryItem.id == body.inventory_id, CrmInventoryItem.company_id == cid
        )
    )
    if inv is None:
        raise HTTPException(404, "Позиция не найдена")
    roll_no = (body.roll_number or "").strip().upper()
    if not roll_no:
        raise HTTPException(400, "Номер рулона пуст")
    existing = db.scalar(
        select(CrmFilmRoll).where(
            CrmFilmRoll.inventory_id == inv.id, CrmFilmRoll.roll_number == roll_no
        )
    )
    if existing is not None:
        raise HTTPException(400, "Рулон с таким номером уже есть")
    per = float(getattr(inv, "meters_per_roll", 0) or 0)
    initial = float(body.meters_initial) if body.meters_initial is not None else (per if per > 0 else 0.0)
    row = CrmFilmRoll(
        company_id=cid,
        inventory_id=inv.id,
        roll_number=roll_no,
        meters_initial=initial,
        meters_left=initial,
    )
    db.add(row)
    db.flush()
    _sync_film_inventory_qty(db, inv)
    move_delta = 1.0 if _is_rolls_unit(inv.unit) else initial
    if move_delta:
        db.add(
            CrmInventoryMove(
                company_id=cid,
                item_id=inv.id,
                delta=move_delta,
                balance_after=float(inv.quantity or 0),
                reason="purchase",
                note=f"Рулон {roll_no}",
            )
        )
    db.commit()
    db.refresh(row)
    return row


@router.get("/orders/{order_id}/wrap-films", response_model=list[CrmOrderWrapFilmOut])
def get_order_wrap_films(
    order_id: int,
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    order = db.scalar(select(CrmOrder).where(CrmOrder.id == order_id, CrmOrder.company_id == cid))
    if order is None:
        raise HTTPException(404, "Заказ не найден")
    rows = db.scalars(
        select(CrmOrderWrapFilm)
        .where(CrmOrderWrapFilm.order_id == order_id, CrmOrderWrapFilm.company_id == cid)
        .order_by(CrmOrderWrapFilm.id)
    ).all()
    out: list[CrmOrderWrapFilmOut] = []
    for r in rows:
        inv = db.get(CrmInventoryItem, r.film_id)
        roll = db.get(CrmFilmRoll, r.roll_id) if r.roll_id else None
        out.append(_order_wrap_out(r, inv, roll))
    return out


@router.put("/orders/{order_id}/wrap-films", response_model=CrmOrderWrapFilmsPutResult)
def put_order_wrap_films(
    order_id: int,
    body: CrmOrderWrapFilmsPut,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    order = db.scalar(select(CrmOrder).where(CrmOrder.id == order_id, CrmOrder.company_id == cid))
    if order is None:
        raise HTTPException(404, "Заказ не найден")

    old_rows = list(
        db.scalars(
            select(CrmOrderWrapFilm).where(
                CrmOrderWrapFilm.order_id == order_id, CrmOrderWrapFilm.company_id == cid
            )
        ).all()
    )
    old_usage: dict[int, float] = {}
    for r in old_rows:
        if r.roll_id is None:
            continue
        old_usage[r.roll_id] = old_usage.get(r.roll_id, 0.0) + float(r.meters or 0)

    new_usage: dict[int, float] = {}
    for f in body.films:
        if f.roll_id is None or float(f.meters or 0) <= 0:
            continue
        new_usage[f.roll_id] = new_usage.get(f.roll_id, 0.0) + float(f.meters or 0)

    warnings: list[str] = []
    for roll_id in set(old_usage) | set(new_usage):
        before = old_usage.get(roll_id, 0.0)
        after = new_usage.get(roll_id, 0.0)
        stock_delta = before - after  # расход вырос → остаток падает
        if abs(stock_delta) < 0.0001:
            continue
        roll = db.scalar(
            select(CrmFilmRoll).where(CrmFilmRoll.id == roll_id, CrmFilmRoll.company_id == cid)
        )
        if roll is None:
            warnings.append(f"Рулон #{roll_id} не найден")
            continue
        left = float(roll.meters_left or 0)
        next_left = left + stock_delta
        if next_left < -0.001:
            warnings.append(
                f"Рулон {roll.roll_number}: остаток {left:.1f} м, "
                f"списание {(-stock_delta):.1f} м — уходит в минус"
            )
        roll.meters_left = next_left
        inv = db.get(CrmInventoryItem, roll.inventory_id)
        if inv is not None:
            _sync_film_inventory_qty(db, inv)

    for r in old_rows:
        db.delete(r)
    db.flush()

    for f in body.films:
        meters = float(f.meters or 0)
        if meters <= 0 and f.roll_id is None:
            continue
        inv = db.scalar(
            select(CrmInventoryItem).where(
                CrmInventoryItem.id == f.film_id, CrmInventoryItem.company_id == cid
            )
        )
        if inv is None:
            continue
        roll_id = f.roll_id
        if roll_id is not None:
            roll = db.scalar(
                select(CrmFilmRoll).where(
                    CrmFilmRoll.id == roll_id,
                    CrmFilmRoll.company_id == cid,
                    CrmFilmRoll.inventory_id == inv.id,
                )
            )
            if roll is None:
                # Не блокируем расход: сохраняем метры без привязки к рулону.
                warnings.append(
                    f"Рулон не подходит к плёнке {inv.name} — сохранено без рулона"
                )
                roll_id = None
        db.add(
            CrmOrderWrapFilm(
                company_id=cid,
                order_id=order_id,
                film_id=inv.id,
                roll_id=roll_id,
                meters=meters,
            )
        )
    db.commit()

    rows = db.scalars(
        select(CrmOrderWrapFilm)
        .where(CrmOrderWrapFilm.order_id == order_id, CrmOrderWrapFilm.company_id == cid)
        .order_by(CrmOrderWrapFilm.id)
    ).all()
    films_out = [
        _order_wrap_out(
            r,
            db.get(CrmInventoryItem, r.film_id),
            db.get(CrmFilmRoll, r.roll_id) if r.roll_id else None,
        )
        for r in rows
    ]
    return CrmOrderWrapFilmsPutResult(warnings=warnings, films=films_out)


# --- Import ---


def _norm_phone(raw: str) -> str:
    digits = "".join(ch for ch in (raw or "") if ch.isdigit())
    if len(digits) == 11 and digits[0] in ("7", "8"):
        return digits[-10:]
    if len(digits) == 10:
        return digits
    return digits


@router.post("/import/clients")
def import_clients(
    body: CrmImportClients,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    """Разовый импорт [{name, phone, is_vip, cars:[{make_model, plate, vin, category}]}]"""
    cid = _company_id(user)
    existing = list(db.scalars(select(CrmClient).where(CrmClient.company_id == cid)).all())
    by_phone = {_norm_phone(c.phone): c for c in existing if _norm_phone(c.phone)}
    created = 0
    skipped = 0
    cars_created = 0
    for raw in body.clients:
        name = str(raw.get("name") or "").strip()
        if not name:
            continue
        phone = str(raw.get("phone") or "").strip()
        phone_key = _norm_phone(phone)
        if phone_key and phone_key in by_phone:
            client = by_phone[phone_key]
            skipped += 1
        else:
            client = CrmClient(
                company_id=cid,
                name=name,
                phone=phone,
                is_vip=bool(raw.get("is_vip")),
            )
            db.add(client)
            db.flush()
            if phone_key:
                by_phone[phone_key] = client
            created += 1
        for car in raw.get("cars") or []:
            mm = str(car.get("make_model") or car.get("name") or "").strip()
            if not mm:
                continue
            plate = str(car.get("plate") or "").strip()
            dup = None
            if plate:
                dup = db.scalar(
                    select(CrmCar).where(
                        CrmCar.client_id == client.id,
                        CrmCar.plate == plate,
                    )
                )
            if dup is not None:
                continue
            db.add(
                CrmCar(
                    company_id=cid,
                    client_id=client.id,
                    make_model=mm,
                    plate=plate,
                    vin=str(car.get("vin") or "").strip(),
                    category=str(car.get("category") or "1"),
                )
            )
            cars_created += 1
    db.commit()
    return {
        "ok": True,
        "created": created,
        "skipped": skipped,
        "cars_created": cars_created,
    }


# --- Stats ---


def _day_key(dt: datetime | None) -> str:
    if dt is None:
        return ""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).date().isoformat()


def _order_activity_day(o: CrmOrder) -> str:
    """День активности заказа: end → start → created_at."""
    for raw in (o.end_time, o.start_time):
        stamp = (raw or "").replace("T", " ").strip()
        if len(stamp) >= 10:
            return stamp[:10]
    return _day_key(o.created_at)


def _order_margin_breakdown(
    order: CrmOrder,
    recipes_by_service: dict[str, list[tuple[float, float]]],
    inv_cost: dict[int, float],
    wrap_by_order: dict[int, list[tuple[float, int]]],
    payroll_by_order: dict[int, float],
) -> dict[str, float]:
    price = float(order.price or 0)
    materials = 0.0
    for it in order.items or []:
        if not it.is_done:
            continue
        name = (it.name or "").strip().lower()
        if not name:
            continue
        for qty, cost in recipes_by_service.get(name, []):
            materials += float(qty or 0) * float(cost or 0)
    for meters, film_id in wrap_by_order.get(int(order.id), []):
        cost = float(inv_cost.get(film_id, 0) or 0)
        materials += float(meters or 0) * cost
    payroll = float(payroll_by_order.get(int(order.id), 0) or 0)
    outsource = 0.0
    margin = price - materials - payroll - outsource
    return {
        "price": price,
        "materials": materials,
        "payroll": payroll,
        "outsource": outsource,
        "margin": margin,
    }


def _lead_out(row: CrmStudioLead) -> CrmStudioLeadOut:
    return CrmStudioLeadOut(
        id=row.id,
        company_id=row.company_id,
        name=row.name or "",
        phone=row.phone or "",
        car_label=row.car_label or "",
        lead_source=row.lead_source or "",
        note=row.note or "",
        status=row.status or "new",
        order_id=row.order_id,
        created_at=row.created_at.isoformat() if row.created_at else None,
        updated_at=row.updated_at.isoformat() if row.updated_at else None,
    )


def _warranty_out(row: CrmCarWarranty) -> CrmCarWarrantyOut:
    return CrmCarWarrantyOut(
        id=row.id,
        company_id=row.company_id,
        car_id=row.car_id,
        order_id=row.order_id,
        kind=row.kind or "",
        title=row.title or "",
        batch=row.batch or "",
        started_at=row.started_at or "",
        months=int(row.months or 0),
        ends_at=row.ends_at or "",
        note=row.note or "",
        reminder_sent=bool(row.reminder_sent),
        created_at=row.created_at.isoformat() if row.created_at else None,
    )


@router.get("/stats", response_model=CrmStatsOut)
def company_stats(
    master_day: str | None = Query(default=None, description="YYYY-MM-DD"),
    days: int = Query(default=30, ge=1, le=90),
    branch_id: int | None = Query(default=None),
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    now = datetime.now(timezone.utc)
    today = now.date().isoformat()
    month_prefix = now.strftime("%Y-%m")
    day = (master_day or today)[:10]
    since = (now.date() - timedelta(days=days - 1)).isoformat()

    q = select(CrmOrder).where(CrmOrder.company_id == cid)
    if branch_id is not None:
        br = db.scalar(
            select(Branch).where(Branch.id == branch_id, Branch.company_id == cid)
        )
        if br is None:
            raise HTTPException(404, "Филиал не найден")
        q = q.where(CrmOrder.branch_id == branch_id)
    orders = list(
        db.scalars(
            q.options(
                selectinload(CrmOrder.items),
                selectinload(CrmOrder.master_links),
            )
        ).all()
    )

    completed = [o for o in orders if o.status == _COMPLETED]
    open_orders = [o for o in orders if o.status != _COMPLETED]

    revenue_today = sum(
        float(o.paid_amount or 0) for o in completed if _day_key(o.created_at) == today
    )
    revenue_month = sum(
        float(o.paid_amount or 0)
        for o in completed
        if (_day_key(o.created_at) or "").startswith(month_prefix)
    )
    completed_period = [
        o for o in completed if (k := _day_key(o.created_at)) and k >= since
    ]
    revenue_period = sum(float(o.paid_amount or 0) for o in completed_period)
    orders_period = float(len(completed_period))
    revenue_all = sum(float(o.paid_amount or 0) for o in completed)
    orders_count = float(len(completed))
    avg_check = (revenue_period / orders_period) if orders_period else 0.0
    open_debt = sum(
        max(0.0, float(o.price or 0) - float(o.paid_amount or 0)) for o in open_orders
    )

    by_name_count: dict[str, int] = {}
    by_name_rev: dict[str, float] = {}
    top_src = completed_period if completed_period else completed
    for o in top_src:
        for it in o.items or []:
            name = (it.name or "").strip()
            if not name:
                continue
            by_name_count[name] = by_name_count.get(name, 0) + 1
            by_name_rev[name] = by_name_rev.get(name, 0.0) + float(it.price or 0)

    top_by_count = [
        {"name": k, "count": by_name_count[k]}
        for k in sorted(by_name_count, key=lambda n: by_name_count[n], reverse=True)[:8]
    ]
    top_by_revenue = [
        {
            "name": k,
            "count": by_name_count.get(k, 0),
            "revenue": by_name_rev[k],
        }
        for k in sorted(by_name_rev, key=lambda n: by_name_rev[n], reverse=True)[:8]
    ]

    day_totals: dict[str, float] = {}
    for o in completed:
        key = _day_key(o.created_at)
        if not key or key < since:
            continue
        day_totals[key] = day_totals.get(key, 0.0) + float(o.paid_amount or 0)
    revenue_by_day = [
        {"day": k, "total": day_totals[k]} for k in sorted(day_totals.keys())
    ]

    status_counts: dict[str, int] = {}
    for o in open_orders:
        st = (o.status or "—").strip() or "—"
        status_counts[st] = status_counts.get(st, 0) + 1
    by_status = [
        {"name": k, "count": status_counts[k]}
        for k in sorted(status_counts, key=lambda n: (-status_counts[n], n))
    ]

    def _master_ids_for_order(o: CrmOrder) -> set[int]:
        ids = {link.master_id for link in (o.master_links or [])}
        if not ids:
            for it in o.items or []:
                raw = (it.master_ids or "").replace(" ", "")
                for part in raw.split(","):
                    if part.isdigit():
                        ids.add(int(part))
        return ids

    def _master_ids_for_item(it) -> set[int]:
        ids: set[int] = set()
        raw = (it.master_ids or "").replace(" ", "")
        for part in raw.split(","):
            if part.isdigit():
                ids.add(int(part))
        return ids

    def _order_activity_day(o: CrmOrder) -> str:
        """День для блока «Мастера»: end → start → created_at (как у услуг по завершённым)."""
        for raw in (o.end_time, o.start_time):
            stamp = (raw or "").replace("T", " ").strip()
            if len(stamp) >= 10:
                return stamp[:10]
        return _day_key(o.created_at)

    payroll_by_order: dict[int, set[int]] = {}
    payroll_amount_by_order: dict[int, dict[int, float]] = {}
    for p in db.scalars(
        select(CrmOrderWorkshopPayroll).where(CrmOrderWorkshopPayroll.company_id == cid)
    ).all():
        if p.master_id is None:
            continue
        oid = int(p.order_id)
        mid = int(p.master_id)
        payroll_by_order.setdefault(oid, set()).add(mid)
        bucket = payroll_amount_by_order.setdefault(oid, {})
        bucket[mid] = float(bucket.get(mid, 0.0)) + float(p.amount or 0)

    masters = list(
        db.scalars(select(CrmMaster).where(CrmMaster.company_id == cid).order_by(CrmMaster.name)).all()
    )
    master_day_rows: list[dict] = []
    for m in masters:
        if not m.is_active:
            continue
        count = 0
        revenue = 0.0
        payroll = 0.0
        for o in orders:
            if o.status not in _MASTER_DAY_STATUSES:
                continue
            if _order_activity_day(o) != day:
                continue
            order_ids = _master_ids_for_order(o)
            payroll_ids = payroll_by_order.get(int(o.id), set())
            item_hit = False
            for it in o.items or []:
                mids = _master_ids_for_item(it)
                if m.id in mids or (not mids and (m.id in order_ids or m.id in payroll_ids)):
                    revenue += float(it.price or 0)
                    item_hit = True
            if m.id in order_ids or m.id in payroll_ids or item_hit:
                count += 1
                payroll += float(payroll_amount_by_order.get(int(o.id), {}).get(m.id, 0.0))
        master_day_rows.append(
            {
                "id": m.id,
                "name": m.name,
                "orders_count": count,
                "revenue": revenue,
                "payroll": payroll,
            }
        )
    master_day_rows.sort(
        key=lambda r: (-int(r["orders_count"]), -float(r["payroll"]), -float(r["revenue"]), str(r["name"]))
    )

    payroll_total_by_order: dict[int, float] = {}
    for p in db.scalars(
        select(CrmOrderWorkshopPayroll).where(CrmOrderWorkshopPayroll.company_id == cid)
    ).all():
        oid = int(p.order_id)
        payroll_total_by_order[oid] = payroll_total_by_order.get(oid, 0.0) + float(p.amount or 0)

    month_start = now.strftime("%Y-%m-01")
    month_end = today
    payroll_accrued = 0.0
    orders_by_id = {int(o.id): o for o in orders}
    for p in db.scalars(
        select(CrmOrderWorkshopPayroll).where(CrmOrderWorkshopPayroll.company_id == cid)
    ).all():
        o = orders_by_id.get(int(p.order_id))
        if o is None:
            continue
        act_day = _order_activity_day(o)
        if act_day and month_start <= act_day <= month_end:
            payroll_accrued += float(p.amount or 0)

    payroll_paid = 0.0
    for f in db.scalars(
        select(CashFlow).where(CashFlow.company_id == cid, CashFlow.type == "Расход")
    ).all():
        if (f.category or "") not in ("Зарплата", "Аванс"):
            continue
        fday = _day_key(f.created_at)
        if fday and month_start <= fday <= month_end:
            payroll_paid += float(f.amount or 0)

    if payroll_accrued > 0 or payroll_paid > 0:
        payroll_due = max(0.0, payroll_accrued - payroll_paid)
    else:
        payroll_due = sum(
            payroll_total_by_order.get(int(o.id), 0.0) for o in open_orders
        )

    by_lead_source_map: dict[str, dict] = {}
    for o in completed_period:
        src = (getattr(o, "lead_source", None) or "").strip() or "Не указан"
        bucket = by_lead_source_map.setdefault(
            src, {"name": src, "count": 0, "revenue": 0.0}
        )
        bucket["count"] += 1
        bucket["revenue"] += float(o.paid_amount or 0)
    by_lead_source = sorted(
        by_lead_source_map.values(),
        key=lambda r: (-float(r["revenue"]), -int(r["count"]), str(r["name"])),
    )

    inv_cost = {
        int(i.id): float(i.unit_cost or 0)
        for i in db.scalars(
            select(CrmInventoryItem).where(CrmInventoryItem.company_id == cid)
        ).all()
    }
    recipes_by_service: dict[str, list[tuple[float, float]]] = {}
    for r in db.scalars(
        select(CrmServiceRecipe).where(CrmServiceRecipe.company_id == cid)
    ).all():
        key = (r.service_name or "").strip().lower()
        if not key:
            continue
        cost = inv_cost.get(int(r.inventory_id), 0.0)
        recipes_by_service.setdefault(key, []).append((float(r.qty or 0), cost))

    wrap_by_order: dict[int, list[tuple[float, int]]] = {}
    for w in db.scalars(
        select(CrmOrderWrapFilm).where(CrmOrderWrapFilm.company_id == cid)
    ).all():
        wrap_by_order.setdefault(int(w.order_id), []).append(
            (float(w.meters or 0), int(w.film_id))
        )

    margin_period = materials_period = payroll_period = 0.0
    for o in completed_period:
        br = _order_margin_breakdown(
            o, recipes_by_service, inv_cost, wrap_by_order, payroll_total_by_order
        )
        margin_period += br["margin"]
        materials_period += br["materials"]
        payroll_period += br["payroll"]

    owner_pulse = {
        "revenue_today": revenue_today,
        "open_debt": open_debt,
        "open_orders": float(len(open_orders)),
        "payroll_due": payroll_due,
    }

    return CrmStatsOut(
        revenue_today=revenue_today,
        revenue_month=revenue_month,
        revenue_period=revenue_period,
        orders_count=orders_count,
        orders_period=orders_period,
        avg_check=avg_check,
        revenue_all=revenue_all,
        open_debt=open_debt,
        open_orders=float(len(open_orders)),
        days=days,
        top_by_count=top_by_count,
        top_by_revenue=top_by_revenue,
        revenue_by_day=revenue_by_day,
        by_status=by_status,
        master_day=master_day_rows,
        master_day_date=day,
        owner_pulse=owner_pulse,
        by_lead_source=by_lead_source,
        margin_period=margin_period,
        materials_period=materials_period,
        payroll_period=payroll_period,
    )


@router.get("/orders/{order_id}/margin")
def order_margin(
    order_id: int,
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    order = db.scalar(
        select(CrmOrder)
        .where(CrmOrder.id == order_id, CrmOrder.company_id == cid)
        .options(selectinload(CrmOrder.items))
    )
    if order is None:
        raise HTTPException(404, "Заказ не найден")

    inv_cost = {
        int(i.id): float(i.unit_cost or 0)
        for i in db.scalars(select(CrmInventoryItem).where(CrmInventoryItem.company_id == cid)).all()
    }
    recipes_by_service: dict[str, list[tuple[float, float]]] = {}
    for r in db.scalars(select(CrmServiceRecipe).where(CrmServiceRecipe.company_id == cid)).all():
        key = (r.service_name or "").strip().lower()
        if not key:
            continue
        recipes_by_service.setdefault(key, []).append(
            (float(r.qty or 0), float(inv_cost.get(int(r.inventory_id), 0)))
        )
    wrap_by_order: dict[int, list[tuple[float, int]]] = {int(order.id): []}
    for wf in db.scalars(
        select(CrmOrderWrapFilm).where(
            CrmOrderWrapFilm.company_id == cid, CrmOrderWrapFilm.order_id == order_id
        )
    ).all():
        wrap_by_order[int(order.id)].append((float(wf.meters or 0), int(wf.film_id)))
    payroll_sum = 0.0
    for p in db.scalars(
        select(CrmOrderWorkshopPayroll).where(
            CrmOrderWorkshopPayroll.company_id == cid,
            CrmOrderWorkshopPayroll.order_id == order_id,
        )
    ).all():
        payroll_sum += float(p.amount or 0)
    br = _order_margin_breakdown(
        order,
        recipes_by_service,
        inv_cost,
        wrap_by_order,
        {int(order.id): payroll_sum},
    )
    price = br["price"]
    margin = br["margin"]
    return {
        **br,
        "margin_pct": (margin / price * 100.0) if price > 0.01 else 0.0,
    }


# --- Studio leads ---


@router.get("/leads", response_model=list[CrmStudioLeadOut])
def list_studio_leads(
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    rows = list(
        db.scalars(
            select(CrmStudioLead)
            .where(CrmStudioLead.company_id == cid)
            .order_by(CrmStudioLead.id.desc())
        ).all()
    )
    return [_lead_out(r) for r in rows]


@router.post("/leads", response_model=CrmStudioLeadOut)
def create_studio_lead_endpoint(
    body: CrmStudioLeadCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    if body.order_id is not None:
        order = db.scalar(
            select(CrmOrder).where(CrmOrder.id == body.order_id, CrmOrder.company_id == cid)
        )
        if order is None:
            raise HTTPException(404, "Заказ не найден")
    row = create_studio_lead(
        db,
        company_id=cid,
        name=body.name,
        phone=body.phone,
        car_label=body.car_label,
        lead_source=body.lead_source,
        note=body.note,
        status=body.status or "new",
        order_id=body.order_id,
    )
    return _lead_out(row)


@router.patch("/leads/{lead_id}", response_model=CrmStudioLeadOut)
def update_studio_lead(
    lead_id: int,
    body: CrmStudioLeadUpdate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmStudioLead).where(CrmStudioLead.id == lead_id, CrmStudioLead.company_id == cid)
    )
    if row is None:
        raise HTTPException(404, "Лид не найден")
    if body.name is not None:
        row.name = body.name.strip()
    if body.phone is not None:
        row.phone = body.phone.strip()
    if body.car_label is not None:
        row.car_label = body.car_label.strip()
    if body.lead_source is not None:
        row.lead_source = body.lead_source.strip()
    if body.note is not None:
        row.note = body.note
    if body.status is not None:
        row.status = body.status.strip() or row.status
    if "order_id" in body.model_fields_set:
        if body.order_id is not None:
            order = db.scalar(
                select(CrmOrder).where(CrmOrder.id == body.order_id, CrmOrder.company_id == cid)
            )
            if order is None:
                raise HTTPException(404, "Заказ не найден")
        row.order_id = body.order_id
    db.commit()
    db.refresh(row)
    return _lead_out(row)


@router.delete("/leads/{lead_id}")
def delete_studio_lead(
    lead_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmStudioLead).where(CrmStudioLead.id == lead_id, CrmStudioLead.company_id == cid)
    )
    if row is None:
        raise HTTPException(404, "Лид не найден")
    db.delete(row)
    db.commit()
    return {"ok": True, "deleted": lead_id}


# --- Car warranties ---


@router.get("/warranties/upcoming", response_model=list[CrmCarWarrantyUpcomingOut])
def list_upcoming_warranties(
    within_days: int = Query(default=14, ge=1, le=365),
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    today = datetime.now(timezone.utc).date()
    until = today + timedelta(days=within_days)
    from_key = today.isoformat()
    until_key = until.isoformat()
    rows = db.execute(
        select(CrmCarWarranty, CrmCar, CrmClient)
        .join(CrmCar, CrmCar.id == CrmCarWarranty.car_id)
        .join(CrmClient, CrmClient.id == CrmCar.client_id)
        .where(
            CrmCarWarranty.company_id == cid,
            CrmCarWarranty.ends_at != "",
            CrmCarWarranty.ends_at >= from_key,
            CrmCarWarranty.ends_at <= until_key,
        )
        .order_by(CrmCarWarranty.ends_at)
    ).all()
    out: list[CrmCarWarrantyUpcomingOut] = []
    for w, car, client in rows:
        base = _warranty_out(w)
        out.append(
            CrmCarWarrantyUpcomingOut(
                **base.model_dump(),
                make_model=car.make_model or "",
                plate=car.plate or "",
                client_name=client.name or "",
                client_phone=client.phone or "",
            )
        )
    return out


@router.get("/warranties", response_model=list[CrmCarWarrantyOut])
def list_car_warranties(
    car_id: int | None = None,
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    q = select(CrmCarWarranty).where(CrmCarWarranty.company_id == cid)
    if car_id is not None:
        q = q.where(CrmCarWarranty.car_id == car_id)
    rows = list(db.scalars(q.order_by(CrmCarWarranty.id.desc())).all())
    return [_warranty_out(r) for r in rows]


@router.post("/warranties", response_model=CrmCarWarrantyOut)
def create_car_warranty(
    body: CrmCarWarrantyCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    car = db.scalar(
        select(CrmCar).where(CrmCar.id == body.car_id, CrmCar.company_id == cid)
    )
    if car is None:
        raise HTTPException(404, "Авто не найдено")
    if body.order_id is not None:
        order = db.scalar(
            select(CrmOrder).where(CrmOrder.id == body.order_id, CrmOrder.company_id == cid)
        )
        if order is None:
            raise HTTPException(404, "Заказ не найден")
    row = CrmCarWarranty(
        company_id=cid,
        car_id=body.car_id,
        order_id=body.order_id,
        kind=(body.kind or "").strip(),
        title=(body.title or "").strip(),
        batch=(body.batch or "").strip(),
        started_at=body.started_at or "",
        months=int(body.months or 0),
        ends_at=body.ends_at or "",
        note=body.note or "",
        reminder_sent=bool(body.reminder_sent),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _warranty_out(row)


@router.patch("/warranties/{warranty_id}", response_model=CrmCarWarrantyOut)
def update_car_warranty(
    warranty_id: int,
    body: CrmCarWarrantyUpdate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmCarWarranty).where(
            CrmCarWarranty.id == warranty_id, CrmCarWarranty.company_id == cid
        )
    )
    if row is None:
        raise HTTPException(404, "Гарантия не найдена")
    if body.car_id is not None:
        car = db.scalar(
            select(CrmCar).where(CrmCar.id == body.car_id, CrmCar.company_id == cid)
        )
        if car is None:
            raise HTTPException(404, "Авто не найдено")
        row.car_id = body.car_id
    if "order_id" in body.model_fields_set:
        if body.order_id is not None:
            order = db.scalar(
                select(CrmOrder).where(CrmOrder.id == body.order_id, CrmOrder.company_id == cid)
            )
            if order is None:
                raise HTTPException(404, "Заказ не найден")
        row.order_id = body.order_id
    if body.kind is not None:
        row.kind = body.kind.strip()
    if body.title is not None:
        row.title = body.title.strip()
    if body.batch is not None:
        row.batch = body.batch.strip()
    if body.started_at is not None:
        row.started_at = body.started_at
    if body.months is not None:
        row.months = int(body.months)
    if body.ends_at is not None:
        row.ends_at = body.ends_at
    if body.note is not None:
        row.note = body.note
    if body.reminder_sent is not None:
        row.reminder_sent = bool(body.reminder_sent)
    db.commit()
    db.refresh(row)
    return _warranty_out(row)


@router.delete("/warranties/{warranty_id}")
def delete_car_warranty(
    warranty_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmCarWarranty).where(
            CrmCarWarranty.id == warranty_id, CrmCarWarranty.company_id == cid
        )
    )
    if row is None:
        raise HTTPException(404, "Гарантия не найдена")
    db.delete(row)
    db.commit()
    return {"ok": True, "deleted": warranty_id}


# --- Payroll rules ---

_PAYROLL_MODES = frozenset({"percent", "fixed"})


@router.get("/payroll-rules", response_model=list[CrmPayrollRuleOut])
def list_payroll_rules(
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    return list(
        db.scalars(
            select(CrmPayrollRule)
            .where(CrmPayrollRule.company_id == cid, CrmPayrollRule.is_active.is_(True))
            .order_by(CrmPayrollRule.id)
        ).all()
    )


@router.post("/payroll-rules", response_model=CrmPayrollRuleOut)
def create_payroll_rule(
    body: CrmPayrollRuleCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    mode = (body.mode or "percent").strip().lower()
    if mode not in _PAYROLL_MODES:
        raise HTTPException(status_code=422, detail="mode: percent или fixed")
    row = CrmPayrollRule(
        company_id=cid,
        workshop=body.workshop.strip(),
        service_name=(body.service_name or "").strip(),
        mode=mode,
        value=float(body.value or 0),
        label=(body.label or "").strip(),
        is_active=bool(body.is_active),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.delete("/payroll-rules/{rule_id}")
def delete_payroll_rule(
    rule_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmPayrollRule).where(
            CrmPayrollRule.id == rule_id, CrmPayrollRule.company_id == cid
        )
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Правило не найдено")
    db.delete(row)
    db.commit()
    return {"ok": True, "deleted": rule_id}


# --- Workshop roles ---


@router.get("/workshop-roles", response_model=list[CrmWorkshopRoleOut])
def list_workshop_roles(
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    return list(
        db.scalars(
            select(CrmWorkshopRole)
            .where(CrmWorkshopRole.company_id == cid)
            .order_by(CrmWorkshopRole.name)
        ).all()
    )


@router.post("/workshop-roles", response_model=CrmWorkshopRoleOut)
def create_workshop_role(
    body: CrmWorkshopRoleCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Пустое имя роли")
    existing = db.scalar(
        select(CrmWorkshopRole).where(
            CrmWorkshopRole.company_id == cid, CrmWorkshopRole.name == name
        )
    )
    if existing is not None:
        return existing
    row = CrmWorkshopRole(company_id=cid, name=name)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.delete("/workshop-roles/{role_id}", status_code=204)
def delete_workshop_role_by_id(
    role_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmWorkshopRole).where(
            CrmWorkshopRole.id == role_id, CrmWorkshopRole.company_id == cid
        )
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Роль не найдена")
    db.delete(row)
    db.commit()
    return Response(status_code=204)


@router.delete("/workshop-roles", status_code=204)
def delete_workshop_role_by_name(
    name: str = Query(..., min_length=1),
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmWorkshopRole).where(
            CrmWorkshopRole.company_id == cid, CrmWorkshopRole.name == name.strip()
        )
    )
    if row is not None:
        db.delete(row)
        db.commit()
    return Response(status_code=204)


# --- Promocodes ---


@router.get("/promocodes", response_model=list[CrmPromocodeOut])
def list_promocodes(
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    return list(
        db.scalars(
            select(CrmPromocode).where(CrmPromocode.company_id == cid).order_by(CrmPromocode.code)
        ).all()
    )


@router.get("/promocodes/{code}", response_model=CrmPromocodeOut)
def get_promocode(
    code: str,
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmPromocode).where(
            CrmPromocode.company_id == cid,
            CrmPromocode.code == code.strip().upper(),
            CrmPromocode.is_active.is_(True),
        )
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Промокод не найден")
    return row


@router.post("/promocodes", response_model=CrmPromocodeOut)
def upsert_promocode(
    body: CrmPromocodeCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    code = body.code.strip().upper()
    if not code:
        raise HTTPException(status_code=400, detail="Пустой код")
    row = db.scalar(
        select(CrmPromocode).where(CrmPromocode.company_id == cid, CrmPromocode.code == code)
    )
    if row is None:
        row = CrmPromocode(
            company_id=cid,
            code=code,
            discount_percent=float(body.discount_percent or 0),
            discount_fixed=float(body.discount_fixed or 0),
            is_active=bool(body.is_active),
        )
        db.add(row)
    else:
        row.discount_percent = float(body.discount_percent or 0)
        row.discount_fixed = float(body.discount_fixed or 0)
        row.is_active = bool(body.is_active)
    db.commit()
    db.refresh(row)
    return row


@router.delete("/promocodes/{promo_id}", status_code=204)
def delete_promocode(
    promo_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmPromocode).where(CrmPromocode.id == promo_id, CrmPromocode.company_id == cid)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Промокод не найден")
    db.delete(row)
    db.commit()
    return Response(status_code=204)
