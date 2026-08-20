from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete, select
from sqlalchemy.orm import Session, selectinload

from app.db import get_db
from app.deps import get_current_user, require_permissions, user_permission_codes
from app.models import Branch, Company, CrmMaster, Permission, Role, User, UserBranch, UserRole
from app.permissions_catalog import PERMISSIONS
from app.phone_util import phone_digits10
from app.schemas import (
    BranchCreate,
    BranchOut,
    PermissionOut,
    RoleCreate,
    RoleOut,
    RoleUpdate,
    UserAssign,
    UserCreate,
    UserOut,
)
from app.security import hash_password
from app.seed import _set_role_permissions

router = APIRouter(prefix="/company", tags=["company"])

KNOWN_WORKSHOPS = (
    "Мойка",
    "Химчистка",
    "Полировка",
    "Оклейка",
    "Интерьер",
    "Оборудование",
)


def _role_out(role: Role) -> RoleOut:
    return RoleOut(
        id=role.id,
        name=role.name,
        is_system=role.is_system,
        company_id=role.company_id,
        permission_codes=sorted(p.code for p in role.permissions),
    )


def _resolve_company_id(user: User, db: Session, company_id: int | None = None) -> int:
    """Компания текущего пользователя; platform admin может указать company_id или берёт demo."""
    if user.is_platform_admin:
        if company_id is not None:
            c = db.get(Company, company_id)
            if c is None:
                raise HTTPException(status_code=404, detail="Компания не найдена")
            return c.id
        demo = db.scalar(select(Company).where(Company.slug == "demo"))
        if demo is not None:
            return demo.id
        first = db.scalar(select(Company).order_by(Company.id).limit(1))
        if first is not None:
            return first.id
        raise HTTPException(status_code=400, detail="Нет компаний на платформе")
    if user.company_id is None:
        raise HTTPException(status_code=400, detail="Пользователь без компании")
    if company_id is not None and company_id != user.company_id:
        raise HTTPException(status_code=403, detail="Чужая компания")
    return user.company_id


def _user_out(user: User) -> UserOut:
    perms = sorted(user_permission_codes(user))
    if user.is_platform_admin:
        perms = sorted({code for code, _, _ in PERMISSIONS})
    workshops: list[str] = []
    # workshops из связанного CrmMaster.role (CSV)
    # подгружается отдельно при необходимости — см. list/assign
    company = getattr(user, "company", None)
    company_slug = company.slug if company is not None else None
    return UserOut(
        id=user.id,
        email=user.email,
        phone=user.phone,
        full_name=user.full_name,
        is_active=user.is_active,
        is_platform_admin=user.is_platform_admin,
        company_id=user.company_id,
        company_slug=company_slug,
        roles=[r.name for r in user.roles],
        branch_ids=[b.id for b in user.branches],
        permissions=perms,
        pending_assignment=bool(getattr(user, "pending_assignment", False)),
        master_id=getattr(user, "master_id", None),
        workshops=workshops,
    )


def _user_out_with_master(db: Session, user: User) -> UserOut:
    out = _user_out(user)
    mid = getattr(user, "master_id", None)
    if mid:
        m = db.get(CrmMaster, mid)
        if m and m.role:
            out.workshops = [p.strip() for p in m.role.split(",") if p.strip()]
    return out


def _ensure_company_user(user: User, db: Session, company_id: int | None = None) -> int:
    return _resolve_company_id(user, db, company_id)


@router.get("/permissions", response_model=list[PermissionOut])
def list_permissions(
    _: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return list(db.scalars(select(Permission).order_by(Permission.group_name, Permission.code)).all())


@router.get("/workshops")
def list_workshops(_: User = Depends(get_current_user)):
    return {"items": list(KNOWN_WORKSHOPS)}


@router.get("/branches", response_model=list[BranchOut])
def list_branches(
    company_id: int | None = Query(default=None),
    user: User = Depends(require_permissions("users.manage")),
    db: Session = Depends(get_db),
):
    cid = _resolve_company_id(user, db, company_id)
    rows = db.scalars(
        select(Branch).where(Branch.company_id == cid).order_by(Branch.id)
    ).all()
    return list(rows)


@router.post("/branches", response_model=BranchOut)
def create_branch(
    body: BranchCreate,
    company_id: int | None = Query(default=None),
    user: User = Depends(require_permissions("branches.manage")),
    db: Session = Depends(get_db),
):
    cid = _resolve_company_id(user, db, company_id)
    name = body.name.strip()
    if len(name) < 2:
        raise HTTPException(status_code=400, detail="Слишком короткое имя филиала")
    exists = db.scalar(select(Branch).where(Branch.company_id == cid, Branch.name == name))
    if exists:
        raise HTTPException(status_code=400, detail="Филиал с таким именем уже есть")
    branch = Branch(company_id=cid, name=name, is_active=True)
    db.add(branch)
    db.commit()
    db.refresh(branch)
    return branch


@router.get("/roles", response_model=list[RoleOut])
def list_roles(
    company_id: int | None = Query(default=None),
    user: User = Depends(require_permissions("roles.manage")),
    db: Session = Depends(get_db),
):
    cid = _resolve_company_id(user, db, company_id)
    roles = db.scalars(
        select(Role)
        .where(Role.company_id == cid)
        .options(selectinload(Role.permissions))
        .order_by(Role.id)
    ).all()
    return [_role_out(r) for r in roles]


@router.post("/roles", response_model=RoleOut)
def create_role(
    body: RoleCreate,
    user: User = Depends(require_permissions("roles.manage")),
    db: Session = Depends(get_db),
):
    company_id = _ensure_company_user(user, db)
    name = body.name.strip()
    exists = db.scalar(select(Role).where(Role.company_id == company_id, Role.name == name))
    if exists:
        raise HTTPException(status_code=400, detail="Роль с таким именем уже есть")
    role = Role(company_id=company_id, name=name, is_system=False)
    db.add(role)
    db.flush()
    by_code = {p.code: p for p in db.scalars(select(Permission)).all()}
    _set_role_permissions(db, role, body.permission_codes, by_code)
    db.commit()
    role = db.scalar(
        select(Role).where(Role.id == role.id).options(selectinload(Role.permissions))
    )
    return _role_out(role)  # type: ignore[arg-type]


@router.patch("/roles/{role_id}", response_model=RoleOut)
def update_role(
    role_id: int,
    body: RoleUpdate,
    user: User = Depends(require_permissions("roles.manage")),
    db: Session = Depends(get_db),
):
    company_id = _ensure_company_user(user, db)
    role = db.scalar(
        select(Role)
        .where(Role.id == role_id, Role.company_id == company_id)
        .options(selectinload(Role.permissions))
    )
    if role is None:
        raise HTTPException(status_code=404, detail="Роль не найдена")
    if body.name is not None:
        role.name = body.name.strip()
    if body.permission_codes is not None:
        by_code = {p.code: p for p in db.scalars(select(Permission)).all()}
        _set_role_permissions(db, role, body.permission_codes, by_code)
    db.commit()
    role = db.scalar(
        select(Role).where(Role.id == role_id).options(selectinload(Role.permissions))
    )
    return _role_out(role)  # type: ignore[arg-type]


@router.delete("/roles/{role_id}")
def delete_role(
    role_id: int,
    user: User = Depends(require_permissions("roles.manage")),
    db: Session = Depends(get_db),
):
    company_id = _ensure_company_user(user, db)
    role = db.scalar(select(Role).where(Role.id == role_id, Role.company_id == company_id))
    if role is None:
        raise HTTPException(status_code=404, detail="Роль не найдена")
    if role.is_system:
        raise HTTPException(status_code=400, detail="Системную роль удалять нельзя")
    db.delete(role)
    db.commit()
    return {"ok": True}


@router.get("/users", response_model=list[UserOut])
def list_users(
    pending: bool | None = Query(default=None),
    company_id: int | None = Query(default=None),
    user: User = Depends(require_permissions("users.manage")),
    db: Session = Depends(get_db),
):
    cid = _resolve_company_id(user, db, company_id)
    q = (
        select(User)
        .where(User.company_id == cid, User.is_platform_admin.is_(False))
        .options(
            selectinload(User.roles).selectinload(Role.permissions),
            selectinload(User.branches),
            selectinload(User.company),
        )
        .order_by(User.id)
    )
    if pending is True:
        q = q.where(User.pending_assignment.is_(True))
    elif pending is False:
        q = q.where(User.pending_assignment.is_(False))
    rows = db.scalars(q).all()
    return [_user_out_with_master(db, u) for u in rows]


@router.post("/users", response_model=UserOut)
def create_user(
    body: UserCreate,
    company_id: int | None = Query(default=None),
    user: User = Depends(require_permissions("users.manage")),
    db: Session = Depends(get_db),
):
    cid = _resolve_company_id(user, db, company_id)
    email = body.email.lower().strip()
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(status_code=400, detail="Email уже занят")
    phone = phone_digits10(body.phone)
    if phone and db.scalar(select(User).where(User.phone == phone)):
        raise HTTPException(status_code=400, detail="Телефон уже занят")

    role_names = [n.strip() for n in body.role_names if n and n.strip()]
    roles: list[Role] = []
    if body.role_ids:
        roles = list(
            db.scalars(
                select(Role).where(Role.id.in_(body.role_ids), Role.company_id == cid)
            ).all()
        )
    if role_names:
        by_name = list(
            db.scalars(select(Role).where(Role.company_id == cid, Role.name.in_(role_names))).all()
        )
        found = {r.name for r in by_name}
        missing = [n for n in role_names if n not in found]
        if missing:
            raise HTTPException(status_code=400, detail=f"Нет ролей: {', '.join(missing)}")
        # merge unique by id
        seen = {r.id for r in roles}
        for r in by_name:
            if r.id not in seen:
                roles.append(r)
                seen.add(r.id)

    if not roles:
        raise HTTPException(status_code=400, detail="Укажите хотя бы одну должность")

    workshops = [w.strip() for w in body.workshops if w and w.strip()]
    bad = [w for w in workshops if w not in KNOWN_WORKSHOPS]
    if bad:
        raise HTTPException(status_code=400, detail=f"Неизвестные цеха: {', '.join(bad)}")

    new_user = User(
        email=email,
        phone=phone,
        password_hash=hash_password(body.password),
        full_name=body.full_name.strip(),
        company_id=cid,
        is_active=True,
        is_platform_admin=False,
        pending_assignment=False,
    )
    db.add(new_user)
    db.flush()

    for role in roles:
        db.add(UserRole(user_id=new_user.id, role_id=role.id))

    branch_ids = list(body.branch_ids)
    if not branch_ids:
        main = db.scalar(select(Branch).where(Branch.company_id == cid).order_by(Branch.id))
        if main is not None:
            branch_ids = [main.id]
    if branch_ids:
        branches = db.scalars(
            select(Branch).where(Branch.id.in_(branch_ids), Branch.company_id == cid)
        ).all()
        for branch in branches:
            db.add(UserBranch(user_id=new_user.id, branch_id=branch.id))

    role_name_set = {r.name for r in roles}
    if body.link_master and (workshops or "Мастер" in role_name_set):
        role_csv = ", ".join(workshops) if workshops else "Универсал"
        master = CrmMaster(
            company_id=cid,
            name=new_user.full_name or new_user.email,
            role=role_csv,
            is_active=True,
        )
        db.add(master)
        db.flush()
        new_user.master_id = master.id
    elif workshops:
        role_csv = ", ".join(workshops)
        master = CrmMaster(
            company_id=cid,
            name=new_user.full_name or new_user.email,
            role=role_csv,
            is_active=True,
        )
        db.add(master)
        db.flush()
        new_user.master_id = master.id

    db.commit()
    created = db.scalar(
        select(User)
        .where(User.id == new_user.id)
        .options(
            selectinload(User.roles).selectinload(Role.permissions),
            selectinload(User.branches),
        )
    )
    assert created is not None
    return _user_out_with_master(db, created)


@router.patch("/users/{user_id}/assign", response_model=UserOut)
def assign_user(
    user_id: int,
    body: UserAssign,
    company_id: int | None = Query(default=None),
    user: User = Depends(require_permissions("users.manage")),
    db: Session = Depends(get_db),
):
    cid = _resolve_company_id(user, db, company_id)
    target = db.scalar(
        select(User)
        .where(User.id == user_id, User.company_id == cid)
        .options(
            selectinload(User.roles).selectinload(Role.permissions),
            selectinload(User.branches),
        )
    )
    if target is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    if target.is_platform_admin:
        raise HTTPException(status_code=400, detail="Нельзя назначать владельца платформы")

    role_names = [n.strip() for n in body.role_names if n and n.strip()]
    if not role_names:
        raise HTTPException(status_code=400, detail="Укажите хотя бы одну должность")

    roles = db.scalars(
        select(Role).where(Role.company_id == cid, Role.name.in_(role_names))
    ).all()
    found = {r.name for r in roles}
    missing = [n for n in role_names if n not in found]
    if missing:
        raise HTTPException(status_code=400, detail=f"Нет ролей: {', '.join(missing)}")

    # заменить должности
    db.execute(delete(UserRole).where(UserRole.user_id == target.id))
    for role in roles:
        db.add(UserRole(user_id=target.id, role_id=role.id))

    # филиалы
    if body.branch_ids is not None:
        db.execute(delete(UserBranch).where(UserBranch.user_id == target.id))
        if body.branch_ids:
            branches = db.scalars(
                select(Branch).where(Branch.id.in_(body.branch_ids), Branch.company_id == cid)
            ).all()
            for branch in branches:
                db.add(UserBranch(user_id=target.id, branch_id=branch.id))
        else:
            # если не указали — основной филиал компании
            main = db.scalar(select(Branch).where(Branch.company_id == cid).order_by(Branch.id))
            if main is not None:
                db.add(UserBranch(user_id=target.id, branch_id=main.id))

    workshops = [w.strip() for w in body.workshops if w and w.strip()]
    bad = [w for w in workshops if w not in KNOWN_WORKSHOPS]
    if bad:
        raise HTTPException(status_code=400, detail=f"Неизвестные цеха: {', '.join(bad)}")

    if body.link_master and (workshops or "Мастер" in role_names):
        role_csv = ", ".join(workshops) if workshops else "Универсал"
        master = db.get(CrmMaster, target.master_id) if target.master_id else None
        if master is None or master.company_id != cid:
            master = CrmMaster(
                company_id=cid,
                name=target.full_name or target.email,
                role=role_csv,
                is_active=True,
            )
            db.add(master)
            db.flush()
            target.master_id = master.id
        else:
            master.name = target.full_name or master.name
            master.role = role_csv
            master.is_active = True
    elif workshops:
        # должности без link_master, но цеха заданы — всё равно пишем в master
        role_csv = ", ".join(workshops)
        master = db.get(CrmMaster, target.master_id) if target.master_id else None
        if master is None:
            master = CrmMaster(
                company_id=cid,
                name=target.full_name or target.email,
                role=role_csv,
                is_active=True,
            )
            db.add(master)
            db.flush()
            target.master_id = master.id
        else:
            master.role = role_csv

    target.pending_assignment = False
    db.commit()

    refreshed = db.scalar(
        select(User)
        .where(User.id == target.id)
        .options(
            selectinload(User.roles).selectinload(Role.permissions),
            selectinload(User.branches),
        )
    )
    assert refreshed is not None
    return _user_out_with_master(db, refreshed)
