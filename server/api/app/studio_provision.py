"""Общая логика создания студии (platform + self-serve)."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Branch, Company, Role, User, UserBranch, UserRole
from app.permissions_catalog import COMPANY_ROLE_PRESETS
from app.phone_util import phone_digits10
from app.security import hash_password
from app.seed import _ensure_permissions, _set_role_permissions
from fastapi import HTTPException


def validate_slug(slug: str) -> str:
    s = slug.lower().strip()
    if not s.replace("-", "").replace("_", "").isalnum():
        raise HTTPException(status_code=400, detail="Slug: только латиница, цифры, - и _")
    return s


def provision_studio(
    db: Session,
    *,
    name: str,
    slug: str,
    branch_name: str,
    owner_email: str,
    owner_password: str,
    owner_full_name: str,
    owner_phone: str | None = None,
) -> tuple[Company, Branch, User]:
    slug = validate_slug(slug)
    if db.scalar(select(Company).where(Company.slug == slug)):
        raise HTTPException(status_code=400, detail="Такой slug уже есть")

    email = owner_email.lower().strip()
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(status_code=400, detail="Email уже занят")
    phone = phone_digits10(owner_phone) if owner_phone else None
    if phone and db.scalar(select(User).where(User.phone == phone)):
        raise HTTPException(status_code=400, detail="Телефон уже занят")

    company = Company(name=name.strip(), slug=slug, is_active=True)
    db.add(company)
    db.flush()
    branch = Branch(company_id=company.id, name=branch_name.strip(), is_active=True)
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

    owner = User(
        email=email,
        phone=phone,
        password_hash=hash_password(owner_password),
        full_name=owner_full_name.strip(),
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
    return company, branch, owner
