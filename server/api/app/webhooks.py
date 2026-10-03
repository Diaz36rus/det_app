"""Best-effort исходящие вебхуки студии."""

from __future__ import annotations

import ipaddress
import json
import logging
import socket
from typing import Any
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import CrmWebhookEndpoint

logger = logging.getLogger(__name__)

WEBHOOK_TIMEOUT_SEC = 3


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: D401
        return None


_opener = build_opener(_NoRedirect)


def webhook_url_problem(url: str) -> str | None:
    """None — адрес допустим; иначе текст причины (только публичные http/https хосты)."""
    try:
        parts = urlsplit((url or "").strip())
    except ValueError:
        return "Некорректный URL"
    if parts.scheme not in ("http", "https"):
        return "Разрешены только http:// и https://"
    host = parts.hostname
    if not host:
        return "В URL нет хоста"
    if parts.username or parts.password:
        return "Логин/пароль в URL не поддерживаются"
    try:
        port = parts.port or (443 if parts.scheme == "https" else 80)
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except (socket.gaierror, ValueError, UnicodeError):
        return "Хост не найден"
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if not ip.is_global or ip.is_multicast:
            return "Адрес указывает во внутреннюю сеть"
    return None


def fire_webhooks(db: Session, company_id: int, event: str, payload: dict[str, Any]) -> None:
    """POST JSON на активные endpoint'ы; ошибки логируются, запрос не падает."""
    endpoints = db.scalars(
        select(CrmWebhookEndpoint).where(
            CrmWebhookEndpoint.company_id == company_id,
            CrmWebhookEndpoint.is_active.is_(True),
        )
    ).all()
    if not endpoints:
        return

    body = json.dumps({"event": event, "payload": payload}, ensure_ascii=False).encode("utf-8")
    for ep in endpoints:
        subscribed = {e.strip() for e in (ep.events or "").split(",") if e.strip()}
        if event not in subscribed:
            continue
        problem = webhook_url_problem(ep.url)
        if problem:
            logger.warning("webhook id=%s blocked: %s", ep.id, problem)
            continue
        headers = {
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "DetApp-Webhook/1.0",
        }
        if ep.secret:
            headers["X-Webhook-Secret"] = ep.secret
        try:
            req = Request(ep.url, data=body, headers=headers, method="POST")
            with _opener.open(req, timeout=WEBHOOK_TIMEOUT_SEC) as resp:
                resp.read(65536)
        except (URLError, OSError, TimeoutError, ValueError) as exc:
            logger.warning("webhook id=%s url=%s event=%s failed: %s", ep.id, ep.url, event, exc)
