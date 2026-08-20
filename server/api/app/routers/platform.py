from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_platform_admin
from app.models import Branch, Company, Role, User, UserBranch, UserRole
from app.permissions_catalog import COMPANY_ROLE_PRESETS
from app.phone_util import phone_digits10
from app.schemas import BranchCreate, BranchOut, CompanyCreate, CompanyCreatedOut, CompanyOut
from app.security import hash_password
from app.seed import _ensure_permissions, _set_role_permissions

router = APIRouter(prefix="/platform", tags=["platform"])


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
    slug = body.slug.lower().strip()
    if not slug.replace("-", "").replace("_", "").isalnum():
        raise HTTPException(status_code=400, detail="Slug: только латиница, цифры, - и _")
    if db.scalar(select(Company).where(Company.slug == slug)):
        raise HTTPException(status_code=400, detail="Такой slug уже есть")

    company = Company(name=body.name.strip(), slug=slug, is_active=True)
    db.add(company)
    db.flush()
    branch = Branch(company_id=company.id, name=body.branch_name.strip(), is_active=True)
    db.add(branch)
    db.flush()

    by_code = _ensure_permissions(db)
    owner_role: Role | None = None
    for role_name, codes in COMPANY_ROLE_PRESETS.items():
        role = Role(company_id=company.id, name=role_name, is_system=True)
        db.add(role)
        db.flush()
        _set_role_permissions(db, role, codes, by_code)
        if role_name == "Владелец":
            owner_role = role

    owner_user_id: int | None = None
    owner_email: str | None = None
    if body.owner_email and body.owner_password:
        email = str(body.owner_email).lower().strip()
        if db.scalar(select(User).where(User.email == email)):
            raise HTTPException(status_code=400, detail="Email владельца уже занят")
        phone = phone_digits10(body.owner_phone)
        if phone and db.scalar(select(User).where(User.phone == phone)):
            raise HTTPException(status_code=400, detail="Телефон владельца уже занят")
        name = (body.owner_full_name or body.name).strip()
        owner = User(
            email=email,
            phone=phone,
            password_hash=hash_password(body.owner_password),
            full_name=name,
            company_id=company.id,
            is_active=True,
            is_platform_admin=False,
            pending_assignment=False,
        )
        db.add(owner)
        db.flush()
        if owner_role is not None:
            db.add(UserRole(user_id=owner.id, role_id=owner_role.id))
        db.add(UserBranch(user_id=owner.id, branch_id=branch.id))
        owner_user_id = owner.id
        owner_email = email

    db.commit()
    db.refresh(company)
    db.refresh(branch)
    return CompanyCreatedOut(
        company=CompanyOut.model_validate(company),
        branch=BranchOut.model_validate(branch),
        owner_user_id=owner_user_id,
        owner_email=owner_email,
    )


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
