"""Полное удаление данных студии (platform admin). Порядок важен из‑за FK без CASCADE."""

from __future__ import annotations

from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from app.models import (
    Branch,
    CashFlow,
    CashPayment,
    CashRegister,
    CashShift,
    CashShiftBalance,
    Company,
    CrmCar,
    CrmClient,
    CrmDefect,
    CrmFilmRoll,
    CrmInventoryItem,
    CrmInventoryMove,
    CrmMaster,
    CrmOrder,
    CrmOrderEvent,
    CrmOrderItem,
    CrmOrderMaster,
    CrmOrderWorkshopPayroll,
    CrmOrderWrapFilm,
    CrmPromocode,
    CrmService,
    CrmServiceRecipe,
    CrmWorkshopRole,
    Role,
    RolePermission,
    User,
    UserBranch,
    UserRole,
)


def wipe_company_data(db: Session, company_id: int) -> dict[str, int]:
    """Удаляет CRM/кассу/роли/юзеров студии. Саму Company не трогает."""
    stats: dict[str, int] = {}

    order_ids = list(
        db.scalars(select(CrmOrder.id).where(CrmOrder.company_id == company_id)).all()
    )
    if order_ids:
        n = db.execute(
            delete(CashPayment).where(CashPayment.crm_order_id.in_(order_ids))
        ).rowcount
        stats["cash_payments"] = int(n or 0)
        db.execute(
            update(CashFlow).where(CashFlow.order_id.in_(order_ids)).values(order_id=None)
        )
        db.execute(
            update(CrmInventoryMove)
            .where(CrmInventoryMove.order_id.in_(order_ids))
            .values(order_id=None)
        )
        for model in (
            CrmOrderWrapFilm,
            CrmDefect,
            CrmOrderEvent,
            CrmOrderMaster,
            CrmOrderWorkshopPayroll,
            CrmOrderItem,
        ):
            n = db.execute(delete(model).where(model.order_id.in_(order_ids))).rowcount
            stats[model.__tablename__] = int(n or 0)
        n = db.execute(delete(CrmOrder).where(CrmOrder.company_id == company_id)).rowcount
        stats["orders"] = int(n or 0)
    else:
        stats["orders"] = 0

    # касса: сначала flows, потом балансы смен, смены, кассы
    n = db.execute(delete(CashFlow).where(CashFlow.company_id == company_id)).rowcount
    stats["cash_flows"] = int(n or 0)
    shift_ids = list(
        db.scalars(select(CashShift.id).where(CashShift.company_id == company_id)).all()
    )
    if shift_ids:
        db.execute(delete(CashShiftBalance).where(CashShiftBalance.shift_id.in_(shift_ids)))
    n = db.execute(delete(CashShift).where(CashShift.company_id == company_id)).rowcount
    stats["cash_shifts"] = int(n or 0)
    n = db.execute(delete(CashRegister).where(CashRegister.company_id == company_id)).rowcount
    stats["cash_registers"] = int(n or 0)

    n = db.execute(delete(CrmServiceRecipe).where(CrmServiceRecipe.company_id == company_id)).rowcount
    stats["recipes"] = int(n or 0)
    n = db.execute(delete(CrmInventoryMove).where(CrmInventoryMove.company_id == company_id)).rowcount
    stats["inv_moves"] = int(n or 0)
    n = db.execute(delete(CrmOrderWrapFilm).where(CrmOrderWrapFilm.company_id == company_id)).rowcount
    stats["wrap_films_left"] = int(n or 0)
    n = db.execute(delete(CrmFilmRoll).where(CrmFilmRoll.company_id == company_id)).rowcount
    stats["film_rolls"] = int(n or 0)
    n = db.execute(delete(CrmInventoryItem).where(CrmInventoryItem.company_id == company_id)).rowcount
    stats["inventory"] = int(n or 0)
    n = db.execute(delete(CrmService).where(CrmService.company_id == company_id)).rowcount
    stats["services"] = int(n or 0)
    n = db.execute(delete(CrmWorkshopRole).where(CrmWorkshopRole.company_id == company_id)).rowcount
    stats["workshop_roles"] = int(n or 0)
    n = db.execute(delete(CrmPromocode).where(CrmPromocode.company_id == company_id)).rowcount
    stats["promocodes"] = int(n or 0)
    n = db.execute(delete(CrmDefect).where(CrmDefect.company_id == company_id)).rowcount
    stats["defects"] = int(n or 0)

    n = db.execute(delete(CrmCar).where(CrmCar.company_id == company_id)).rowcount
    stats["cars"] = int(n or 0)
    n = db.execute(delete(CrmClient).where(CrmClient.company_id == company_id)).rowcount
    stats["clients"] = int(n or 0)

    users = list(db.scalars(select(User).where(User.company_id == company_id)).all())
    user_ids = [u.id for u in users]
    for u in users:
        u.master_id = None
    db.flush()
    n = db.execute(delete(CrmMaster).where(CrmMaster.company_id == company_id)).rowcount
    stats["masters"] = int(n or 0)

    if user_ids:
        db.execute(delete(UserRole).where(UserRole.user_id.in_(user_ids)))
        db.execute(delete(UserBranch).where(UserBranch.user_id.in_(user_ids)))
        n = db.execute(delete(User).where(User.id.in_(user_ids))).rowcount
        stats["users"] = int(n or 0)
    else:
        stats["users"] = 0

    role_ids = list(db.scalars(select(Role.id).where(Role.company_id == company_id)).all())
    if role_ids:
        db.execute(delete(RolePermission).where(RolePermission.role_id.in_(role_ids)))
        n = db.execute(delete(Role).where(Role.id.in_(role_ids))).rowcount
        stats["roles"] = int(n or 0)

    n = db.execute(delete(Branch).where(Branch.company_id == company_id)).rowcount
    stats["branches"] = int(n or 0)

    db.flush()
    return stats


def delete_company_hard(db: Session, company: Company) -> dict[str, int]:
    stats = wipe_company_data(db, company.id)
    db.delete(company)
    db.flush()
    stats["company"] = 1
    return stats
