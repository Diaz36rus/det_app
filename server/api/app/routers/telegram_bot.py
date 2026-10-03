"""Telegram webhook + CRM notify endpoints для клиентов."""

from __future__ import annotations

import hmac
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.deps import require_permissions
from app.models import Company, CrmClient, CrmOrder, User
from app.telegram_notify import (
    NOTIFY_KIND_TITLES,
    bind_url,
    bot_configured,
    bot_username,
    cascade_send,
    parse_bind_payload,
    send_telegram_message,
    sms_configured,
)

router = APIRouter(tags=["telegram"])


def _client_out_extra(row: CrmClient) -> dict:
    chat = (getattr(row, "telegram_chat_id", None) or "").strip()
    return {
        "id": row.id,
        "company_id": row.company_id,
        "name": row.name,
        "phone": row.phone or "",
        "is_vip": bool(row.is_vip),
        "telegram_linked": bool(chat),
        "telegram_chat_id": chat if chat else "",
    }


def _company_id(user: User) -> int:
    if user.company_id is None:
        raise HTTPException(status_code=400, detail="Нет компании")
    return int(user.company_id)


class NotifyClientIn(BaseModel):
    kind: str = Field(default="custom", max_length=40)
    text: str = Field(default="", max_length=4000)


class NotifyClientOut(BaseModel):
    ok: bool
    channel: str
    detail: str = ""
    bind_url: str | None = None
    text: str = ""
    telegram_linked: bool = False
    bot_ready: bool = False
    sms_ready: bool = False


def _build_order_text(order: CrmOrder, client: CrmClient, kind: str, custom: str = "") -> str:
    if (custom or "").strip():
        return custom.strip()
    who = (client.name or "").strip() or "Клиент"
    oid = int(order.id)
    debt = max(0.0, float(order.price or 0) - float(order.paid_amount or 0))
    when = " ".join(
        x for x in [(order.due_date or "").strip(), (getattr(order, "start_time", None) or "").strip()] if x
    )
    kind = (kind or "custom").strip().lower()
    if kind == "tomorrow":
        lines = [
            f"Здравствуйте, {who}!",
            f"Напоминаем: завтра визит в студию (заказ #{oid}).",
        ]
        if when:
            lines.append(f"Время: {when}")
        lines.append("До встречи!")
        return "\n".join(lines)
    if kind == "ready":
        lines = [
            f"Здравствуйте, {who}!",
            "Ваш автомобиль готов к выдаче.",
            f"Заказ #{oid}",
        ]
        if debt > 0.01:
            lines.append(f"К оплате: {debt:.0f} ₽")
        lines.append("Ждём вас в студии!")
        return "\n".join(lines)
    if kind == "debt":
        lines = [
            f"Здравствуйте, {who}!",
            f"Напоминаем о задолженности по заказу #{oid}",
            f"Сумма: {debt:.0f} ₽",
            "Ждём вас в студии.",
        ]
        return "\n".join(lines)
    # booking / default
    lines = [
        f"Здравствуйте, {who}!",
        f"Вы записаны в студию. Заказ #{oid}",
    ]
    if when:
        lines.append(f"Когда: {when}")
    lines.append("Ждём вас!")
    return "\n".join(lines)


@router.get("/crm/notify/status")
def notify_platform_status(user: User = Depends(require_permissions("orders.read"))):
    return {
        "bot_ready": bot_configured() and bool(bot_username()),
        "bot_username": bot_username(),
        "sms_ready": sms_configured(),
        "cascade": ["telegram", "sms"],
    }


@router.get("/crm/clients/{client_id}/notify-channels")
def client_notify_channels(
    client_id: int,
    user: User = Depends(require_permissions("orders.read")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmClient).where(CrmClient.id == client_id, CrmClient.company_id == cid)
    )
    if row is None:
        raise HTTPException(404, "Клиент не найден")
    chat = (getattr(row, "telegram_chat_id", None) or "").strip()
    url = bind_url(cid, int(row.id)) if bot_configured() and bot_username() else None
    return {
        "client_id": row.id,
        "telegram_linked": bool(chat),
        "telegram_linked_at": getattr(row, "telegram_linked_at", None) or "",
        "bind_url": url,
        "bot_ready": bot_configured() and bool(bot_username()),
        "bot_username": bot_username(),
        "sms_ready": sms_configured(),
        "phone": row.phone or "",
    }


@router.post("/crm/clients/{client_id}/telegram-bind-link")
def client_telegram_bind_link(
    client_id: int,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    row = db.scalar(
        select(CrmClient).where(CrmClient.id == client_id, CrmClient.company_id == cid)
    )
    if row is None:
        raise HTTPException(404, "Клиент не найден")
    if not bot_configured() or not bot_username():
        raise HTTPException(503, "Telegram-бот не настроен на сервере")
    url = bind_url(cid, int(row.id))
    return {
        "bind_url": url,
        "bot_username": bot_username(),
        "telegram_linked": bool((getattr(row, "telegram_chat_id", None) or "").strip()),
        "instruction": "Отправьте ссылку клиенту. Он откроет бота и нажмёт Start — уведомления пойдут в Telegram.",
    }


@router.post("/crm/orders/{order_id}/notify-client", response_model=NotifyClientOut)
def notify_order_client(
    order_id: int,
    body: NotifyClientIn,
    user: User = Depends(require_permissions("orders.write")),
    db: Session = Depends(get_db),
):
    cid = _company_id(user)
    order = db.scalar(select(CrmOrder).where(CrmOrder.id == order_id, CrmOrder.company_id == cid))
    if order is None:
        raise HTTPException(404, "Заказ не найден")
    client = db.get(CrmClient, order.client_id)
    if client is None or int(client.company_id) != cid:
        raise HTTPException(404, "Клиент не найден")

    kind = (body.kind or "custom").strip().lower()
    if kind not in NOTIFY_KIND_TITLES:
        kind = "custom"
    text = _build_order_text(order, client, kind, body.text)
    chat = (getattr(client, "telegram_chat_id", None) or "").strip()
    url = bind_url(cid, int(client.id)) if bot_username() else None

    result = cascade_send(telegram_chat_id=chat or None, phone=client.phone, text=text)
    return NotifyClientOut(
        ok=bool(result.get("ok")),
        channel=str(result.get("channel") or "none"),
        detail=str(result.get("detail") or ""),
        bind_url=url,
        text=text,
        telegram_linked=bool(chat),
        bot_ready=bot_configured() and bool(bot_username()),
        sms_ready=sms_configured(),
    )


@router.post("/telegram/webhook")
async def telegram_webhook(request: Request, db: Session = Depends(get_db)):
    """Webhook от Telegram; при TELEGRAM_WEBHOOK_SECRET сверяем X-Telegram-Bot-Api-Secret-Token."""
    if not bot_configured():
        return {"ok": True, "skipped": "bot not configured"}
    expected = (settings.telegram_webhook_secret or "").strip()
    if expected:
        got = request.headers.get("X-Telegram-Bot-Api-Secret-Token") or ""
        if not hmac.compare_digest(got, expected):
            raise HTTPException(403, "Forbidden")
    elif settings.is_production:
        raise HTTPException(503, "TELEGRAM_WEBHOOK_SECRET не задан")
    try:
        update = await request.json()
    except Exception:
        raise HTTPException(400, "Invalid JSON") from None

    message = update.get("message") or update.get("edited_message") or {}
    chat = message.get("chat") or {}
    chat_id = chat.get("id")
    text = (message.get("text") or "").strip()
    if chat_id is None:
        return {"ok": True}

    if text.startswith("/start"):
        parts = text.split(maxsplit=1)
        payload = parts[1].strip() if len(parts) > 1 else ""
        parsed = parse_bind_payload(payload) if payload else None
        if parsed is None:
            send_telegram_message(
                chat_id,
                "Здравствуйте! Это бот уведомлений Det App.\n"
                "Откройте персональную ссылку из заказа студии и нажмите Start ещё раз.",
            )
            return {"ok": True}

        company_id, client_id = parsed
        client = db.scalar(
            select(CrmClient).where(
                CrmClient.id == client_id, CrmClient.company_id == company_id
            )
        )
        if client is None:
            send_telegram_message(chat_id, "Ссылка устарела или клиент не найден. Попросите студию прислать новую.")
            return {"ok": True}

        company = db.get(Company, company_id)
        studio = (company.name if company else "студия").strip() or "студия"
        client.telegram_chat_id = str(chat_id)
        client.telegram_linked_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        db.commit()
        send_telegram_message(
            chat_id,
            f"Готово! Уведомления от «{studio}» будут приходить сюда.\n"
            f"Клиент: {client.name}",
        )
        return {"ok": True, "linked": client_id}

    if text in ("/help", "помощь", "Помощь"):
        send_telegram_message(
            chat_id,
            "Бот присылает сервисные сообщения студии: запись, напоминание, готовность, долг.\n"
            "Отключить: удалите чат или /stop (сброс привязки).",
        )
        return {"ok": True}

    if text.startswith("/stop"):
        # сброс всех клиентов с этим chat_id в рамках… лучше только если один
        rows = list(
            db.scalars(
                select(CrmClient).where(CrmClient.telegram_chat_id == str(chat_id))
            ).all()
        )
        for row in rows:
            row.telegram_chat_id = ""
            row.telegram_linked_at = ""
        db.commit()
        send_telegram_message(chat_id, "Привязка снята. Чтобы снова получать уведомления — откройте ссылку из заказа.")
        return {"ok": True}

    send_telegram_message(
        chat_id,
        "Бот только для уведомлений студии. Вопросы — напрямую в студию по телефону.",
    )
    return {"ok": True}


@router.get("/telegram/setup-hint")
def telegram_setup_hint():
    """Публичная подсказка для админов сервера (без секретов)."""
    return {
        "bot_ready": bot_configured() and bool(bot_username()),
        "bot_username": bot_username() or None,
        "webhook_url": f"{settings.public_base_url.rstrip('/')}/telegram/webhook",
        "env": [
            "TELEGRAM_BOT_TOKEN",
            "TELEGRAM_BOT_USERNAME",
            "TELEGRAM_BIND_SECRET",
            "TELEGRAM_WEBHOOK_SECRET",
            "SMS_API_URL",
            "SMS_API_KEY",
        ],
    }
