"""CRUD исходящих вебхуков студии."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_permissions
from app.models import CrmWebhookEndpoint, User
from app.routers.crm import _company_id
from app.webhooks import webhook_url_problem

router = APIRouter(prefix="/crm", tags=["webhooks"])

VALID_EVENTS = frozenset({"order.created", "order.status_changed", "lead.created"})


class WebhookCreate(BaseModel):
    url: str = Field(min_length=8, max_length=500)
    secret: str = Field(default="", max_length=128)
    is_active: bool = True
    events: str = Field(default="order.created,order.status_changed,lead.created", max_length=200)


class WebhookUpdate(BaseModel):
    url: str | None = Field(default=None, min_length=8, max_length=500)
    secret: str | None = Field(default=None, max_length=128)
    is_active: bool | None = None
    events: str | None = Field(default=None, max_length=200)


class WebhookOut(BaseModel):
    id: int
    company_id: int
    url: str
    secret: str
    is_active: bool
    events: str

    model_config = {"from_attributes": True}


def _checked_url(raw: str) -> str:
    url = (raw or "").strip()
    problem = webhook_url_problem(url)
    if problem:
        raise HTTPException(status_code=422, detail=f"URL вебхука: {problem}")
    return url


def _normalize_events(raw: str) -> str:
    parts = [p.strip() for p in (raw or "").split(",") if p.strip()]
    if not parts:
        raise HTTPException(status_code=422, detail="Укажите хотя бы одно событие")
    bad = [p for p in parts if p not in VALID_EVENTS]
    if bad:
        raise HTTPException(status_code=422, detail=f"Неизвестные события: {', '.join(bad)}")
    return ",".join(parts)


@router.get("/webhooks", response_model=list[WebhookOut])
def list_webhooks(
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    rows = db.scalars(
        select(CrmWebhookEndpoint)
        .where(CrmWebhookEndpoint.company_id == cid)
        .order_by(CrmWebhookEndpoint.id)
    ).all()
    return list(rows)


@router.post("/webhooks", response_model=WebhookOut)
def create_webhook(
    body: WebhookCreate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = CrmWebhookEndpoint(
        company_id=cid,
        url=_checked_url(body.url),
        secret=(body.secret or "").strip(),
        is_active=body.is_active,
        events=_normalize_events(body.events),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.patch("/webhooks/{webhook_id}", response_model=WebhookOut)
def update_webhook(
    webhook_id: int,
    body: WebhookUpdate,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmWebhookEndpoint).where(
            CrmWebhookEndpoint.id == webhook_id,
            CrmWebhookEndpoint.company_id == cid,
        )
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Вебхук не найден")
    if body.url is not None:
        row.url = _checked_url(body.url)
    if body.secret is not None:
        row.secret = body.secret.strip()
    if body.is_active is not None:
        row.is_active = body.is_active
    if body.events is not None:
        row.events = _normalize_events(body.events)
    db.commit()
    db.refresh(row)
    return row


@router.delete("/webhooks/{webhook_id}")
def delete_webhook(
    webhook_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmWebhookEndpoint).where(
            CrmWebhookEndpoint.id == webhook_id,
            CrmWebhookEndpoint.company_id == cid,
        )
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Вебхук не найден")
    db.delete(row)
    db.commit()
    return {"ok": True}
