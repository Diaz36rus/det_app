from fastapi import APIRouter, Depends, HTTPException, status
from jwt import InvalidTokenError
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db import get_db
from app.deps import get_current_user, user_permission_codes
from app.models import Role, User
from app.permissions_catalog import PERMISSIONS
from app.phone_util import looks_like_email, phone_digits10
from app.schemas import LoginRequest, RefreshRequest, TokenResponse, UserOut
from app.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _user_out(user: User) -> UserOut:
    perms = sorted(user_permission_codes(user))
    if user.is_platform_admin:
        perms = sorted({code for code, _, _ in PERMISSIONS})
    return UserOut(
        id=user.id,
        email=user.email,
        phone=user.phone,
        full_name=user.full_name,
        is_active=user.is_active,
        is_platform_admin=user.is_platform_admin,
        company_id=user.company_id,
        roles=[r.name for r in user.roles],
        branch_ids=[b.id for b in user.branches],
        permissions=perms,
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
