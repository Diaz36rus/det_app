from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_platform_admin
from app.models import Branch, Company, Role, User
from app.permissions_catalog import COMPANY_ROLE_PRESETS
from app.schemas import BranchCreate, BranchOut, CompanyCreate, CompanyCreatedOut, CompanyOut
from app.seed import _ensure_permissions, _set_role_permissions
from app.studio_provision import provision_studio, validate_slug

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
