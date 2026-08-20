from fastapi import APIRouter, Depends, HTTPException, status
from jwt import InvalidTokenError
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db import get_db
from app.deps import get_current_user, user_permission_codes
from app.models import Branch, Company, Role, User, UserBranch
from app.permissions_catalog import PERMISSIONS
from app.phone_util import looks_like_email, phone_digits10
from app.schemas import (
    AccessRequest,
    LoginRequest,
    RefreshRequest,
    RegisterStudioRequest,
    StudioLookupOut,
    TokenResponse,
    UserOut,
)
from app.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)
from app.studio_provision import provision_studio

router = APIRouter(prefix="/auth", tags=["auth"])


def _user_out(user: User) -> UserOut:
    perms = sorted(user_permission_codes(user))
    if user.is_platform_admin:
        perms = sorted({code for code, _, _ in PERMISSIONS})
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
        workshops=[],
    )


def _find_user_by_login(db: Session, raw: str) -> User | None:
    ident = (raw or "").strip()
    if not ident:
        return None
    if looks_like_email(ident):
        return db.scalar(select(User).where(User.email == ident.lower()))
    phone = phone_digits10(ident)
    if phone:
        return db.scalar(select(User).where(User.phone == phone))
    # fallback: try as email anyway
    return db.scalar(select(User).where(User.email == ident.lower()))


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    raw = (body.login or (str(body.email) if body.email else "") or "").strip()
    if not raw:
        raise HTTPException(status_code=422, detail="Укажите email или телефон")
    user = _find_user_by_login(db, raw)
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Неверный логин или пароль")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Пользователь отключён")
    return TokenResponse(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
    )


@router.post("/refresh", response_model=TokenResponse)
def refresh(body: RefreshRequest, db: Session = Depends(get_db)):
    try:
        payload = decode_token(body.refresh_token)
        if payload.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="Неверный refresh-токен")
        user_id = int(payload["sub"])
    except (InvalidTokenError, KeyError, ValueError):
        raise HTTPException(status_code=401, detail="Refresh недействителен") from None

    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise HTTPException(status_code=401, detail="Пользователь не найден")
    return TokenResponse(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
    )


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return _user_out(user)


@router.get("/studio-lookup", response_model=StudioLookupOut)
def studio_lookup(slug: str, db: Session = Depends(get_db)):
    s = (slug or "").strip().lower()
    if len(s) < 2:
        raise HTTPException(status_code=422, detail="Укажите код студии")
    company = db.scalar(select(Company).where(Company.slug == s, Company.is_active.is_(True)))
    if company is None:
        raise HTTPException(status_code=404, detail="Студия не найдена")
    return StudioLookupOut(id=company.id, name=company.name, slug=company.slug, is_active=company.is_active)


@router.post("/register-studio", response_model=TokenResponse)
def register_studio(body: RegisterStudioRequest, db: Session = Depends(get_db)):
    """Клиент создаёт свою студию и сразу входит как её владелец."""
    _, _, owner = provision_studio(
        db,
        name=body.studio_name,
        slug=body.slug,
        branch_name=body.branch_name,
        owner_email=str(body.email),
        owner_password=body.password,
        owner_full_name=body.full_name,
        owner_phone=body.phone,
    )
    db.commit()
    return TokenResponse(
        access_token=create_access_token(owner.id),
        refresh_token=create_refresh_token(owner.id),
    )


@router.post("/request-access", response_model=TokenResponse)
def request_access(body: AccessRequest, db: Session = Depends(get_db)):
    """Сотрудник подключается к компании и ждёт назначения должности/цеха."""
    slug = (body.company_slug or "demo").strip().lower()
    company = db.scalar(select(Company).where(Company.slug == slug, Company.is_active.is_(True)))
    if company is None:
        raise HTTPException(status_code=404, detail="Компания не найдена")

    email = str(body.email).lower().strip()
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(status_code=400, detail="Email уже зарегистрирован")
    phone = phone_digits10(body.phone)
    if phone and db.scalar(select(User).where(User.phone == phone)):
        raise HTTPException(status_code=400, detail="Телефон уже зарегистрирован")

    user = User(
        email=email,
        phone=phone,
        password_hash=hash_password(body.password),
        full_name=body.full_name.strip(),
        company_id=company.id,
        is_active=True,
        is_platform_admin=False,
        pending_assignment=True,
    )
    db.add(user)
    db.flush()

    main = db.scalar(select(Branch).where(Branch.company_id == company.id).order_by(Branch.id))
    if main is not None:
        db.add(UserBranch(user_id=user.id, branch_id=main.id))

    db.commit()
    return TokenResponse(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
    )
