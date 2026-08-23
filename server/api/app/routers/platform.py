from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db import get_db
from app.deps import require_platform_admin
from app.models import Branch, Company, Role, User, UserBranch, UserRole
from app.permissions_catalog import COMPANY_ROLE_PRESETS
from app.schemas import (
    BranchCreate,
    BranchOut,
    CompanyCreate,
    CompanyCreatedOut,
    CompanyOut,
    CompanyPatch,
    PlatformUserOut,
    WipeResultOut,
)
from app.seed import _ensure_permissions, _set_role_permissions
from app.studio_provision import provision_studio, validate_slug
from app.studio_wipe import delete_company_hard, wipe_company_data

router = APIRouter(prefix="/platform", tags=["platform"])


def _user_brief(user: User) -> PlatformUserOut:
    return PlatformUserOut(
        id=user.id,
        email=user.email,
        phone=user.phone,
        full_name=user.full_name,
        is_active=user.is_active,
        roles=[r.name for r in (user.roles or [])],
        pending_assignment=bool(getattr(user, "pending_assignment", False)),
        company_id=user.company_id,
    )


@router.get("/companies", response_model=list[CompanyOut])
def list_companies(
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    return list(db.scalars(select(Company).order_by(Company.id)).all())


@router.post("/companies", response_model=CompanyCreatedOut)
def create_company(
    body: CompanyCreate,
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    if body.owner_email and body.owner_password:
        company, branch, owner = provision_studio(
            db,
            name=body.name,
            slug=body.slug,
            branch_name=body.branch_name,
            owner_email=str(body.owner_email),
            owner_password=body.owner_password,
            owner_full_name=(body.owner_full_name or body.name),
            owner_phone=body.owner_phone,
        )
        db.commit()
        db.refresh(company)
        db.refresh(branch)
        return CompanyCreatedOut(
            company=CompanyOut.model_validate(company),
            branch=BranchOut.model_validate(branch),
            owner_user_id=owner.id,
            owner_email=owner.email,
        )

    slug = validate_slug(body.slug)
    if db.scalar(select(Company).where(Company.slug == slug)):
        raise HTTPException(status_code=400, detail="Такой slug уже есть")
    company = Company(name=body.name.strip(), slug=slug, is_active=True)
    db.add(company)
    db.flush()
    branch = Branch(company_id=company.id, name=body.branch_name.strip(), is_active=True)
    db.add(branch)
    db.flush()
    by_code = _ensure_permissions(db)
    for role_name, codes in COMPANY_ROLE_PRESETS.items():
        role = Role(company_id=company.id, name=role_name, is_system=True)
        db.add(role)
        db.flush()
        _set_role_permissions(db, role, codes, by_code)
    db.commit()
    db.refresh(company)
    db.refresh(branch)
    return CompanyCreatedOut(
        company=CompanyOut.model_validate(company),
        branch=BranchOut.model_validate(branch),
        owner_user_id=None,
        owner_email=None,
    )


@router.patch("/companies/{company_id}", response_model=CompanyOut)
def patch_company(
    company_id: int,
    body: CompanyPatch,
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    company = db.get(Company, company_id)
    if company is None:
        raise HTTPException(status_code=404, detail="Компания не найдена")
    if body.is_active is not None:
        company.is_active = body.is_active
    db.commit()
    db.refresh(company)
    return company


@router.delete("/companies/{company_id}", response_model=WipeResultOut)
def delete_company(
    company_id: int,
    hard: bool = Query(default=False),
    wipe_data: bool = Query(default=False),
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    """hard=true — стереть данные и удалить компанию. wipe_data=true — только данные, компания остаётся выключенной."""
    company = db.get(Company, company_id)
    if company is None:
        raise HTTPException(status_code=404, detail="Компания не найдена")
    if company.slug == "demo" and hard:
        raise HTTPException(
            status_code=400,
            detail="Демо-студию нельзя удалить целиком. Выключите или очистите данные (wipe_data).",
        )
    if hard:
        stats = delete_company_hard(db, company)
        db.commit()
        return WipeResultOut(ok=True, company_id=company_id, deleted=True, stats=stats)
    if wipe_data:
        stats = wipe_company_data(db, company_id)
        company.is_active = False
        db.commit()
        return WipeResultOut(ok=True, company_id=company_id, deleted=False, stats=stats)
    raise HTTPException(status_code=400, detail="Укажите hard=true или wipe_data=true")


@router.get("/companies/{company_id}/users", response_model=list[PlatformUserOut])
def list_company_users(
    company_id: int,
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    if db.get(Company, company_id) is None:
        raise HTTPException(status_code=404, detail="Компания не найдена")
    rows = db.scalars(
        select(User)
        .where(User.company_id == company_id, User.is_platform_admin.is_(False))
        .options(selectinload(User.roles))
        .order_by(User.id)
    ).all()
    return [_user_brief(u) for u in rows]


@router.patch("/users/{user_id}", response_model=PlatformUserOut)
def patch_platform_user(
    user_id: int,
    is_active: bool = Query(...),
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    user = db.scalar(
        select(User).where(User.id == user_id).options(selectinload(User.roles))
    )
    if user is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    if user.is_platform_admin:
        raise HTTPException(status_code=400, detail="Нельзя менять владельца платформы")
    user.is_active = is_active
    db.commit()
    db.refresh(user)
    return _user_brief(user)


@router.delete("/users/{user_id}")
def delete_platform_user(
    user_id: int,
    actor: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    from sqlalchemy import delete as sa_delete, update as sa_update

    from app.models import CashShift

    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    if user.is_platform_admin or user.id == actor.id:
        raise HTTPException(status_code=400, detail="Нельзя удалить владельца платформы")
    db.execute(
        sa_update(CashShift)
        .where(CashShift.opened_by_user_id == user_id)
        .values(opened_by_user_id=None)
    )
    db.execute(sa_delete(UserRole).where(UserRole.user_id == user_id))
    db.execute(sa_delete(UserBranch).where(UserBranch.user_id == user_id))
    user.master_id = None
    db.flush()
    db.delete(user)
    db.commit()
    return {"ok": True, "user_id": user_id}


@router.patch("/branches/{branch_id}", response_model=BranchOut)
def patch_branch(
    branch_id: int,
    is_active: bool = Query(...),
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    branch = db.get(Branch, branch_id)
    if branch is None:
        raise HTTPException(status_code=404, detail="Филиал не найден")
    branch.is_active = is_active
    db.commit()
    db.refresh(branch)
    return branch


@router.post("/companies/{company_id}/branches", response_model=BranchOut)
def create_branch(
    company_id: int,
    body: BranchCreate,
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    company = db.get(Company, company_id)
    if company is None:
        raise HTTPException(status_code=404, detail="Компания не найдена")
    branch = Branch(company_id=company.id, name=body.name.strip(), is_active=True)
    db.add(branch)
    db.commit()
    db.refresh(branch)
    return branch


@router.get("/companies/{company_id}/branches", response_model=list[BranchOut])
def list_branches(
    company_id: int,
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    return list(
        db.scalars(
            select(Branch).where(Branch.company_id == company_id).order_by(Branch.id)
        ).all()
    )
