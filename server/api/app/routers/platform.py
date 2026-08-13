from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_platform_admin
from app.models import Branch, Company, Role, User
from app.permissions_catalog import COMPANY_ROLE_PRESETS
from app.schemas import BranchCreate, BranchOut, CompanyCreate, CompanyOut
from app.seed import _ensure_permissions, _set_role_permissions

router = APIRouter(prefix="/platform", tags=["platform"])


@router.get("/companies", response_model=list[CompanyOut])
def list_companies(
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    return list(db.scalars(select(Company).order_by(Company.id)).all())


@router.post("/companies", response_model=CompanyOut)
def create_company(
    body: CompanyCreate,
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    slug = body.slug.lower().strip()
    if db.scalar(select(Company).where(Company.slug == slug)):
        raise HTTPException(status_code=400, detail="Такой slug уже есть")
    company = Company(name=body.name.strip(), slug=slug, is_active=True)
    db.add(company)
    db.flush()
    db.add(Branch(company_id=company.id, name=body.branch_name.strip(), is_active=True))

    by_code = _ensure_permissions(db)
    for role_name, codes in COMPANY_ROLE_PRESETS.items():
        role = Role(company_id=company.id, name=role_name, is_system=True)
        db.add(role)
        db.flush()
        _set_role_permissions(db, role, codes, by_code)

    db.commit()
    db.refresh(company)
    return company


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
