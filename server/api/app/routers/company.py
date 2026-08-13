from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db import get_db
from app.deps import get_current_user, require_permissions
from app.models import Branch, Permission, Role, User, UserBranch, UserRole
from app.schemas import (
    PermissionOut,
    RoleCreate,
    RoleOut,
    RoleUpdate,
    UserCreate,
    UserOut,
)
from app.security import hash_password
from app.seed import _set_role_permissions

router = APIRouter(prefix="/company", tags=["company"])


def _role_out(role: Role) -> RoleOut:
    return RoleOut(
        id=role.id,
        name=role.name,
        is_system=role.is_system,
        company_id=role.company_id,
        permission_codes=sorted(p.code for p in role.permissions),
    )


def _ensure_company_user(user: User) -> int:
    if user.is_platform_admin:
        raise HTTPException(
            status_code=400,
            detail="Platform admin работает через /platform. Для ролей компании войдите пользователем компании.",
        )
    if user.company_id is None:
        raise HTTPException(status_code=400, detail="Пользователь без компании")
    return user.company_id


@router.get("/permissions", response_model=list[PermissionOut])
def list_permissions(
    _: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return list(db.scalars(select(Permission).order_by(Permission.group_name, Permission.code)).all())


@router.get("/roles", response_model=list[RoleOut])
def list_roles(
    user: User = Depends(require_permissions("roles.manage")),
    db: Session = Depends(get_db),
):
    company_id = _ensure_company_user(user)
    roles = db.scalars(
        select(Role)
        .where(Role.company_id == company_id)
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
    company_id = _ensure_company_user(user)
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
    company_id = _ensure_company_user(user)
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
    company_id = _ensure_company_user(user)
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
    user: User = Depends(require_permissions("users.manage")),
    db: Session = Depends(get_db),
):
    company_id = _ensure_company_user(user)
    rows = db.scalars(
        select(User)
        .where(User.company_id == company_id)
        .options(
            selectinload(User.roles).selectinload(Role.permissions),
            selectinload(User.branches),
        )
        .order_by(User.id)
    ).all()
    out: list[UserOut] = []
    for u in rows:
        out.append(
            UserOut(
                id=u.id,
                email=u.email,
                full_name=u.full_name,
                is_active=u.is_active,
                is_platform_admin=u.is_platform_admin,
                company_id=u.company_id,
                roles=[r.name for r in u.roles],
                branch_ids=[b.id for b in u.branches],
                permissions=sorted({p.code for r in u.roles for p in r.permissions}),
            )
        )
    return out


@router.post("/users", response_model=UserOut)
def create_user(
    body: UserCreate,
    user: User = Depends(require_permissions("users.manage")),
    db: Session = Depends(get_db),
):
    company_id = _ensure_company_user(user)
    email = body.email.lower().strip()
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(status_code=400, detail="Email уже занят")

    new_user = User(
        email=email,
        password_hash=hash_password(body.password),
        full_name=body.full_name.strip(),
        company_id=company_id,
        is_active=True,
        is_platform_admin=False,
    )
    db.add(new_user)
    db.flush()

    if body.role_ids:
        roles = db.scalars(
            select(Role).where(Role.id.in_(body.role_ids), Role.company_id == company_id)
        ).all()
        for role in roles:
            db.add(UserRole(user_id=new_user.id, role_id=role.id))

    if body.branch_ids:
        branches = db.scalars(
            select(Branch).where(Branch.id.in_(body.branch_ids), Branch.company_id == company_id)
        ).all()
        for branch in branches:
            db.add(UserBranch(user_id=new_user.id, branch_id=branch.id))

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
    return UserOut(
        id=created.id,
        email=created.email,
        full_name=created.full_name,
        is_active=created.is_active,
        is_platform_admin=created.is_platform_admin,
        company_id=created.company_id,
        roles=[r.name for r in created.roles],
        branch_ids=[b.id for b in created.branches],
        permissions=sorted({p.code for r in created.roles for p in r.permissions}),
    )
