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
from app.security import hash_password

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
            text("ALTER TABLE crm_orders ADD COLUMN IF NOT EXISTS start_time VARCHAR(16) DEFAULT ''")
        )
        conn.execute(
            text("ALTER TABLE crm_orders ADD COLUMN IF NOT EXISTS end_time VARCHAR(16) DEFAULT ''")
        )
        for col, typ in [
            ("comment", "TEXT DEFAULT ''"),
            ("master_ids", "VARCHAR(200) DEFAULT ''"),
            ("start_time", "VARCHAR(32) DEFAULT ''"),
            ("end_time", "VARCHAR(32) DEFAULT ''"),
            ("parent_id", "INTEGER"),
        ]:
            conn.execute(text(f"ALTER TABLE crm_order_items ADD COLUMN IF NOT EXISTS {col} {typ}"))


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
        if db.scalars(select(CrmService).where(CrmService.company_id == company.id).limit(1)).first() is None:
            for name, cat, price, ws in [
                ("Мойка кузова", "Мойка", 3000, "Мойка"),
                ("Химчистка салона", "Химчистка", 12000, "Химчистка"),
                ("Полировка в 1 этап", "Полировка", 15000, "Полировка"),
            ]:
                db.add(
                    CrmService(
                        company_id=company.id,
                        name=name,
                        category=cat,
                        price=price,
                        workshop=ws,
                    )
                )
        if (
            db.scalars(select(CrmInventoryItem).where(CrmInventoryItem.company_id == company.id).limit(1)).first()
            is None
        ):
            db.add(
                CrmInventoryItem(
                    company_id=company.id,
                    name="Плёнка демо",
                    quantity=10,
                    unit="м",
                    category="Оклейка",
                    min_qty=2,
                )
            )

    db.commit()
