from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.config import settings
from app.db import get_db
from app.deps import get_current_user, require_platform_admin
from app.models import Company, User, BugReport
from app.security import decode_token
from jwt import InvalidTokenError

router = APIRouter(prefix="/bugs", tags=["bugs"])


class BugReportCreate(BaseModel):
    place: str = Field(default="", max_length=300)
    situation: str = Field(default="", max_length=500)
    details: str = Field(min_length=1, max_length=50000)
    app_version: str = Field(default="", max_length=40)
    app_build: int = Field(default=0, ge=0)
    platform: str = Field(default="", max_length=40)
    client_local_id: int | None = None


class BugReportPatch(BaseModel):
    status: str | None = Field(default=None, pattern="^(open|fixed)$")
    fix_note: str | None = Field(default=None, max_length=5000)


class BugReportOut(BaseModel):
    id: int
    place: str
    situation: str
    details: str
    status: str
    fix_note: str
    app_version: str
    app_build: int
    platform: str
    user_id: int | None
    user_email: str
    user_name: str
    company_id: int | None
    company_name: str
    company_slug: str
    client_local_id: int | None
    created_at: datetime
    updated_at: datetime | None = None

    model_config = {"from_attributes": True}


def _optional_user(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> User | None:
    """Сессия если есть; иначе аноним (репорт всё равно принимаем)."""
    if not authorization or not authorization.lower().startswith("bearer "):
        return None
    token = authorization.split(" ", 1)[1].strip()
    if not token:
        return None
    try:
        payload = decode_token(token)
        if payload.get("type") != "access":
            return None
        user_id = int(payload["sub"])
    except (InvalidTokenError, KeyError, ValueError):
        return None
    return db.scalar(
        select(User)
        .where(User.id == user_id, User.is_active.is_(True))
        .options(selectinload(User.company))
    )


def _require_list_access(
    user: User | None = Depends(_optional_user),
    x_release_token: str | None = Header(default=None, alias="X-Release-Token"),
) -> bool:
    if user is not None and user.is_platform_admin:
        return True
    expected = (settings.release_upload_token or "").strip()
    if expected and x_release_token and x_release_token.strip() == expected:
        return True
    raise HTTPException(status_code=403, detail="Нужен platform admin или X-Release-Token")


@router.post("", response_model=BugReportOut)
@router.post("/", response_model=BugReportOut)
def create_bug(
    body: BugReportCreate,
    db: Session = Depends(get_db),
    user: User | None = Depends(_optional_user),
):
    details = (body.details or "").strip()
    if not details:
        raise HTTPException(status_code=400, detail="Опишите ошибку")

    company: Company | None = None
    if user is not None:
        company = getattr(user, "company", None)

    row = BugReport(
        place=(body.place or "").strip()[:300] or "Без места",
        situation=(body.situation or "").strip()[:500],
        details=details[:50000],
        status="open",
        fix_note="",
        app_version=(body.app_version or "").strip()[:40],
        app_build=int(body.app_build or 0),
        platform=(body.platform or "").strip()[:40],
        user_id=user.id if user else None,
        user_email=(user.email if user else "") or "",
        user_name=(user.full_name if user else "") or "",
        company_id=user.company_id if user else None,
        company_name=(company.name if company else "") or "",
        company_slug=(company.slug if company else "") or "",
        client_local_id=body.client_local_id,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.get("", response_model=list[BugReportOut])
@router.get("/", response_model=list[BugReportOut])
def list_bugs(
    _: bool = Depends(_require_list_access),
    db: Session = Depends(get_db),
    status: str | None = Query(default=None, pattern="^(open|fixed)$"),
    limit: int = Query(default=100, ge=1, le=500),
):
    q = select(BugReport).order_by(BugReport.id.desc()).limit(limit)
    if status:
        q = q.where(BugReport.status == status)
    return list(db.scalars(q).all())


@router.get("/mine", response_model=list[BugReportOut])
def list_my_bugs(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    limit: int = Query(default=50, ge=1, le=200),
):
    q = (
        select(BugReport)
        .where(BugReport.user_id == user.id)
        .order_by(BugReport.id.desc())
        .limit(limit)
    )
    return list(db.scalars(q).all())


@router.patch("/{bug_id}", response_model=BugReportOut)
def patch_bug(
    bug_id: int,
    body: BugReportPatch,
    _: User = Depends(require_platform_admin),
    db: Session = Depends(get_db),
):
    row = db.get(BugReport, bug_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Репорт не найден")
    if body.status is not None:
        row.status = body.status
    if body.fix_note is not None:
        row.fix_note = body.fix_note.strip()
    db.commit()
    db.refresh(row)
    return row
