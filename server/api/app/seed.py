from sqlalchemy import delete, select, text
from sqlalchemy.orm import Session

from app.config import settings
from app.db import engine
from app.models import (
    Branch,
    CashRegister,
    Company,
    CrmInventoryItem,
    CrmMaster,
    CrmService,
    Permission,
    Role,
    RolePermission,
    User,
    UserBranch,
    UserRole,
)
from app.permissions_catalog import COMPANY_ROLE_PRESETS, PERMISSIONS
from app.price_catalog import iter_price_catalog
from app.security import hash_password


def ensure_company_price_catalog(db: Session, company_id: int) -> dict[str, int]:
    """Upsert полного прайса: создаёт недостающие, обновляет category/price/workshop."""
    existing = {
        row.name: row
        for row in db.scalars(select(CrmService).where(CrmService.company_id == company_id)).all()
    }
    created = updated = 0
    for item in iter_price_catalog():
        row = existing.get(item["name"])
        if row is None:
            db.add(
                CrmService(
                    company_id=company_id,
                    name=item["name"],
                    category=item["category"],
                    price=item["price"],
                    workshop=item["workshop"],
                    is_active=True,
                )
            )
            created += 1
            continue
        changed = False
        if row.category != item["category"]:
            row.category = item["category"]
            changed = True
        if float(row.price or 0) != float(item["price"]):
            row.price = item["price"]
            changed = True
        if (row.workshop or "") != (item["workshop"] or ""):
            row.workshop = item["workshop"]
            changed = True
        if not row.is_active:
            row.is_active = True
            changed = True
        if changed:
            updated += 1
    return {"created": created, "updated": updated, "total": len(iter_price_catalog())}

_DEFAULT_CASH_REGISTERS = [
    ("Касса наличные", "Наличные", 0),
    ("Терминал", "Карта", 1),
    ("Перевод", "Перевод", 2),
    ("Счёт", "Счёт", 3),
]


def ensure_user_phone_column() -> None:
    """Добавляет users.phone на уже существующей БД (create_all новые колонки не добавляет)."""
    with engine.begin() as conn:
        conn.execute(
            text("ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20)")
        )
        conn.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS ix_users_phone_unique "
                "ON users (phone) WHERE phone IS NOT NULL"
            )
        )
        conn.execute(
            text("ALTER TABLE crm_orders ADD COLUMN IF NOT EXISTS start_time VARCHAR(32) DEFAULT ''")
        )
        conn.execute(
            text("ALTER TABLE crm_orders ADD COLUMN IF NOT EXISTS end_time VARCHAR(32) DEFAULT ''")
        )
        # Widen legacy 16-char columns so ISO datetime fits calendar slots.
        conn.execute(text("ALTER TABLE crm_orders ALTER COLUMN start_time TYPE VARCHAR(32)"))
        conn.execute(text("ALTER TABLE crm_orders ALTER COLUMN end_time TYPE VARCHAR(32)"))
        for col, typ in [
            ("end_date", "VARCHAR(32) DEFAULT ''"),
            ("client_notes", "TEXT DEFAULT ''"),
            ("client_visible_notes", "TEXT DEFAULT ''"),
            ("master_notes", "TEXT DEFAULT ''"),
            ("payment_method", "VARCHAR(40) DEFAULT 'Наличные'"),
            ("discount_percent", "DOUBLE PRECISION DEFAULT 0"),
            ("discount_fixed", "DOUBLE PRECISION DEFAULT 0"),
            ("promo_code", "VARCHAR(80) DEFAULT ''"),
            ("handover_ready", "BOOLEAN DEFAULT FALSE"),
            ("handover_works", "BOOLEAN DEFAULT FALSE"),
            ("handover_payment", "BOOLEAN DEFAULT FALSE"),
            ("handover_keys", "BOOLEAN DEFAULT FALSE"),
            ("handover_inspect", "BOOLEAN DEFAULT FALSE"),
            ("handover_notified", "BOOLEAN DEFAULT FALSE"),
            ("tech_wash_start", "VARCHAR(32) DEFAULT ''"),
            ("tech_wash_end", "VARCHAR(32) DEFAULT ''"),
            ("is_workshop_completed", "BOOLEAN DEFAULT FALSE"),
        ]:
            conn.execute(text(f"ALTER TABLE crm_orders ADD COLUMN IF NOT EXISTS {col} {typ}"))
        conn.execute(
            text(
                "ALTER TABLE crm_inventory_items "
                "ADD COLUMN IF NOT EXISTS meters_per_roll DOUBLE PRECISION DEFAULT 0"
            )
        )
        for col, typ in [
            ("comment", "TEXT DEFAULT ''"),
            ("master_ids", "VARCHAR(200) DEFAULT ''"),
            ("start_time", "VARCHAR(32) DEFAULT ''"),
            ("end_time", "VARCHAR(32) DEFAULT ''"),
            ("parent_id", "INTEGER"),
        ]:
            conn.execute(text(f"ALTER TABLE crm_order_items ADD COLUMN IF NOT EXISTS {col} {typ}"))
        for col, typ in [
            ("counterparty", "VARCHAR(200) DEFAULT ''"),
            ("master_id", "INTEGER"),
            ("inventory_id", "INTEGER"),
            ("inventory_qty", "DOUBLE PRECISION DEFAULT 0"),
            ("order_id", "INTEGER"),
            ("template_key", "VARCHAR(80) DEFAULT ''"),
        ]:
            conn.execute(text(f"ALTER TABLE cash_flows ADD COLUMN IF NOT EXISTS {col} {typ}"))


def _ensure_permissions(db: Session) -> dict[str, Permission]:
    by_code: dict[str, Permission] = {
        p.code: p for p in db.scalars(select(Permission)).all()
    }
    for code, title, group in PERMISSIONS:
        if code in by_code:
            continue
        row = Permission(code=code, title=title, group_name=group)
        db.add(row)
        by_code[code] = row
    db.flush()
    return by_code


def _set_role_permissions(
    db: Session,
    role: Role,
    codes: list[str],
    by_code: dict[str, Permission],
) -> None:
    db.execute(delete(RolePermission).where(RolePermission.role_id == role.id))
    for code in codes:
        perm = by_code.get(code)
        if perm is None:
            continue
        db.add(RolePermission(role_id=role.id, permission_id=perm.id))


def seed_database(db: Session) -> None:
    by_code = _ensure_permissions(db)

    admin = db.scalar(select(User).where(User.email == settings.platform_admin_email.lower()))
    if admin is None:
        admin = User(
            email=settings.platform_admin_email.lower().strip(),
            phone="9000000001",
            password_hash=hash_password(settings.platform_admin_password),
            full_name=settings.platform_admin_name,
            is_platform_admin=True,
            is_active=True,
        )
        db.add(admin)
    else:
        admin.is_platform_admin = True
        admin.is_active = True
        if not admin.phone:
            admin.phone = "9000000001"

    company = db.scalar(select(Company).where(Company.slug == "demo"))
    admin_role: Role | None = None
    main_branch: Branch | None = None
    if company is None:
        company = Company(name="Demo Detailing", slug="demo", is_active=True)
        db.add(company)
        db.flush()
        main_branch = Branch(company_id=company.id, name="Основной филиал", is_active=True)
        db.add(main_branch)
        db.flush()

        for role_name, codes in COMPANY_ROLE_PRESETS.items():
            role = Role(company_id=company.id, name=role_name, is_system=True)
            db.add(role)
            db.flush()
            _set_role_permissions(db, role, codes, by_code)
            if role_name == "Администратор компании":
                admin_role = role
    else:
        main_branch = db.scalar(
            select(Branch).where(Branch.company_id == company.id).order_by(Branch.id)
        )
        admin_role = db.scalar(
            select(Role).where(
                Role.company_id == company.id,
                Role.name == "Администратор компании",
            )
        )
        # Синхронизируем системные роли с актуальным каталогом (inventory и т.п.).
        for role_name, codes in COMPANY_ROLE_PRESETS.items():
            role = db.scalar(
                select(Role).where(Role.company_id == company.id, Role.name == role_name)
            )
            if role is None:
                role = Role(company_id=company.id, name=role_name, is_system=True)
                db.add(role)
                db.flush()
            _set_role_permissions(db, role, codes, by_code)
            if role_name == "Администратор компании":
                admin_role = role

    owner_email = "owner@demo.det-app.ru"
    owner = db.scalar(select(User).where(User.email == owner_email))
    if owner is None and company is not None:
        owner = User(
            email=owner_email,
            phone="9000000002",
            password_hash=hash_password(settings.platform_admin_password),
            full_name="Demo Owner",
            company_id=company.id,
            is_active=True,
            is_platform_admin=False,
        )
        db.add(owner)
        db.flush()
        if admin_role is not None:
            db.add(UserRole(user_id=owner.id, role_id=admin_role.id))
        if main_branch is not None:
            db.add(UserBranch(user_id=owner.id, branch_id=main_branch.id))
    elif owner is not None and not owner.phone:
        owner.phone = "9000000002"

    # Кассы компании (C2)
    if company is not None:
        existing = db.scalars(
            select(CashRegister).where(CashRegister.company_id == company.id).limit(1)
        ).first()
        if existing is None:
            for name, money_type, sort_order in _DEFAULT_CASH_REGISTERS:
                db.add(
                    CashRegister(
                        company_id=company.id,
                        name=name,
                        money_type=money_type,
                        is_active=True,
                        sort_order=sort_order,
                    )
                    )

    # C3 demo справочники
    if company is not None:
        if db.scalars(select(CrmMaster).where(CrmMaster.company_id == company.id).limit(1)).first() is None:
            db.add(CrmMaster(company_id=company.id, name="Иван Мастер", role="Универсал"))
            db.add(CrmMaster(company_id=company.id, name="Алексей", role="Полировка"))
        # Полный прайс (SERVICES_TREE + оклейка) — upsert, не только пустая база
        ensure_company_price_catalog(db, company.id)
        if (
            db.scalars(select(CrmInventoryItem).where(CrmInventoryItem.company_id == company.id).limit(1)).first()
            is None
        ):
            db.add(
                CrmInventoryItem(
                    company_id=company.id,
                    name="Плёнка демо",
                    quantity=0,
                    unit="м",
                    category="Плёнка оклейка",
                    min_qty=2,
                    meters_per_roll=15,
                )
            )

    db.commit()
