from __future__ import annotations

import hmac
from datetime import datetime

from fastapi import APIRouter, Depends, Header, HTTPException
from jwt import InvalidTokenError
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.config import settings
from app.db import get_db
from app.models import SiteLead, User
from app.rate_limit import limit_by_ip
from app.security import decode_token

router = APIRouter(prefix="/site", tags=["site"])


class LeadCreate(BaseModel):
    name: str = Field(default="", max_length=200)
    studio: str = Field(default="", max_length=200)
    contact: str = Field(min_length=3, max_length=255)
    message: str = Field(default="", max_length=4000)


class LeadOut(BaseModel):
    id: int
    name: str
    studio: str
    contact: str
    message: str
    status: str
    created_at: datetime

    model_config = {"from_attributes": True}


def _optional_admin(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> User | None:
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


def _require_leads_access(
    user: User | None = Depends(_optional_admin),
    x_release_token: str | None = Header(default=None, alias="X-Release-Token"),
) -> bool:
    if user is not None and user.is_platform_admin:
        return True
    expected = (settings.release_upload_token or "").strip()
    if expected and x_release_token and hmac.compare_digest(x_release_token.strip(), expected):
        return True
    raise HTTPException(status_code=403, detail="Нужен platform admin или X-Release-Token")


@router.post("/leads", response_model=LeadOut, dependencies=[Depends(limit_by_ip("site-leads", 5, 600))])
def create_lead(body: LeadCreate, db: Session = Depends(get_db)):
    contact = body.contact.strip()
    if len(contact) < 3:
        raise HTTPException(status_code=422, detail="Укажите email или телефон")
    row = SiteLead(
        name=body.name.strip()[:200],
        studio=body.studio.strip()[:200],
        contact=contact[:255],
        message=body.message.strip()[:4000],
        status="new",
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.get("/leads", response_model=list[LeadOut])
def list_leads(
    _: bool = Depends(_require_leads_access),
    db: Session = Depends(get_db),
):
    return list(db.scalars(select(SiteLead).order_by(SiteLead.id.desc()).limit(200)).all())
