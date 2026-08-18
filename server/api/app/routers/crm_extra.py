"""Masters, services, defects, inventory, import, stats — C3..C7."""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.crm_extra_schemas import (
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
    CrmMasterOut,
    CrmMasterUpdate,
    CrmOrderWrapFilmOut,
    CrmOrderWrapFilmsPut,
    CrmOrderWrapFilmsPutResult,
    CrmRecipeApply,
    CrmRecipeApplyResult,
    CrmRecipeOut,
    CrmRecipeUpsert,
    CrmServiceCreate,
    CrmServiceOut,
    CrmServiceUpdate,
    CrmStatsOut,
    CrmWrapFilmOut,
)
from app.db import get_db
from app.deps import require_permissions
from app.models import (
    CrmCar,
    CrmClient,
    CrmDefect,
    CrmFilmRoll,
    CrmInventoryItem,
    CrmInventoryMove,
    CrmMaster,
    CrmOrder,
    CrmOrderWrapFilm,
    CrmService,
    CrmServiceRecipe,
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
        meters_per_roll=float(getattr(body, "meters_per_roll", 0) or 0),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


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
                order_id=body.order_id,
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
                order_id=body.order_id,
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
        if f.roll_id is not None:
            roll = db.scalar(
                select(CrmFilmRoll).where(
                    CrmFilmRoll.id == f.roll_id,
                    CrmFilmRoll.company_id == cid,
                    CrmFilmRoll.inventory_id == inv.id,
                )
            )
            if roll is None:
                warnings.append(f"Рулон не подходит к плёнке {inv.name}")
                continue
        db.add(
            CrmOrderWrapFilm(
                company_id=cid,
                order_id=order_id,
                film_id=inv.id,
                roll_id=f.roll_id,
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


@router.get("/stats", response_model=CrmStatsOut)
def company_stats(
    master_day: str | None = Query(default=None, description="YYYY-MM-DD"),
    days: int = Query(default=30, ge=1, le=90),
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    now = datetime.now(timezone.utc)
    today = now.date().isoformat()
    month_prefix = now.strftime("%Y-%m")
    day = (master_day or today)[:10]

    orders = list(
        db.scalars(
            select(CrmOrder)
            .where(CrmOrder.company_id == cid)
            .options(
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
    revenue_all = sum(float(o.paid_amount or 0) for o in completed)
    orders_count = float(len(completed))
    avg_check = (revenue_all / orders_count) if orders_count else 0.0
    open_debt = sum(
        max(0.0, float(o.price or 0) - float(o.paid_amount or 0)) for o in open_orders
    )

    by_name_count: dict[str, int] = {}
    by_name_rev: dict[str, float] = {}
    for o in orders:
        for it in o.items or []:
            name = (it.name or "").strip()
            if not name:
                continue
            by_name_count[name] = by_name_count.get(name, 0) + 1
            by_name_rev[name] = by_name_rev.get(name, 0.0) + float(it.price or 0)

    top_by_count = [
        {"name": k, "count": by_name_count[k]}
        for k in sorted(by_name_count, key=lambda n: by_name_count[n], reverse=True)[:5]
    ]
    top_by_revenue = [
        {
            "name": k,
            "count": by_name_count.get(k, 0),
            "revenue": by_name_rev[k],
        }
        for k in sorted(by_name_rev, key=lambda n: by_name_rev[n], reverse=True)[:5]
    ]

    since = (now.date() - timedelta(days=days - 1)).isoformat()
    day_totals: dict[str, float] = {}
    for o in completed:
        key = _day_key(o.created_at)
        if not key or key < since:
            continue
        day_totals[key] = day_totals.get(key, 0.0) + float(o.paid_amount or 0)
    revenue_by_day = [
        {"day": k, "total": day_totals[k]} for k in sorted(day_totals.keys())
    ]

    masters = list(
        db.scalars(select(CrmMaster).where(CrmMaster.company_id == cid).order_by(CrmMaster.name)).all()
    )
    master_day_rows: list[dict] = []
    for m in masters:
        count = 0
        for o in orders:
            if o.status not in _MASTER_DAY_STATUSES:
                continue
            stamp = (o.end_time or o.start_time or "").replace("T", " ").strip()
            if len(stamp) < 10 or stamp[:10] != day:
                continue
            ids = {link.master_id for link in (o.master_links or [])}
            if not ids:
                for it in o.items or []:
                    raw = (it.master_ids or "").replace(" ", "")
                    for part in raw.split(","):
                        if part.isdigit():
                            ids.add(int(part))
            if m.id in ids:
                count += 1
        master_day_rows.append({"id": m.id, "name": m.name, "orders_count": count})
    master_day_rows.sort(key=lambda r: (-int(r["orders_count"]), str(r["name"])))

    return CrmStatsOut(
        revenue_today=revenue_today,
        revenue_month=revenue_month,
        orders_count=orders_count,
        avg_check=avg_check,
        revenue_all=revenue_all,
        open_debt=open_debt,
        top_by_count=top_by_count,
        top_by_revenue=top_by_revenue,
        revenue_by_day=revenue_by_day,
        master_day=master_day_rows,
        master_day_date=day,
    )
