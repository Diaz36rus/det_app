"""Telegram-бот + SMS-каскад для уведомлений клиентам (РФ)."""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import urllib.error
import urllib.request
from typing import Any

from app.config import settings

logger = logging.getLogger(__name__)

TELEGRAM_API = "https://api.telegram.org"


def bot_configured() -> bool:
    return bool((settings.telegram_bot_token or "").strip())


def bot_username() -> str:
    return (settings.telegram_bot_username or "").strip().lstrip("@")


def _bind_secret() -> str:
    return (settings.telegram_bind_secret or settings.jwt_secret or "detapp-tg").strip()


def make_bind_payload(company_id: int, client_id: int) -> str:
    """Короткий токен для t.me/Bot?start=… (лимит start ≈ 64 символа)."""
    raw = f"{int(company_id)}:{int(client_id)}"
    sig = hmac.new(_bind_secret().encode(), raw.encode(), hashlib.sha256).hexdigest()[:10]
    return f"c{int(company_id)}u{int(client_id)}s{sig}"


def parse_bind_payload(payload: str) -> tuple[int, int] | None:
    p = (payload or "").strip()
    if p.startswith("bind_"):
        p = p[5:]
    # c12u34sabcdef0123
    if not p.startswith("c") or "u" not in p or "s" not in p:
        return None
    try:
        left, _sig = p.rsplit("s", 1)
        company_s, client_s = left[1:].split("u", 1)
        company_id = int(company_s)
        client_id = int(client_s)
    except (ValueError, IndexError):
        return None
    expect = make_bind_payload(company_id, client_id)
    if not hmac.compare_digest(expect, p):
        return None
    return company_id, client_id


def bind_url(company_id: int, client_id: int) -> str | None:
    user = bot_username()
    if not user:
        return None
    token = make_bind_payload(company_id, client_id)
    return f"https://t.me/{user}?start={token}"


def _tg_api(method: str, body: dict[str, Any]) -> dict[str, Any] | None:
    token = (settings.telegram_bot_token or "").strip()
    if not token:
        return None
    url = f"{TELEGRAM_API}/bot{token}/{method}"
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else None
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, ValueError, OSError) as exc:
        logger.warning("telegram %s failed: %s", method, exc)
        return None


def send_telegram_message(chat_id: str | int, text: str) -> bool:
    if not chat_id or not (text or "").strip():
        return False
    result = _tg_api(
        "sendMessage",
        {
            "chat_id": int(chat_id) if str(chat_id).isdigit() else chat_id,
            "text": text.strip()[:4000],
            "disable_web_page_preview": True,
        },
    )
    return bool(result and result.get("ok"))


def sms_configured() -> bool:
    return bool((settings.sms_api_url or "").strip())


def send_sms(phone: str, text: str) -> bool:
    """Best-effort SMS через внешний HTTP-провайдер."""
    url = (settings.sms_api_url or "").strip()
    if not url:
        return False
    digits = "".join(ch for ch in (phone or "") if ch.isdigit())
    if len(digits) < 10:
        return False
    if len(digits) == 11 and digits.startswith("8"):
        digits = "7" + digits[1:]
    if len(digits) == 10:
        digits = "7" + digits
    payload = {"phone": digits, "text": (text or "").strip()[:700]}
    headers = {"Content-Type": "application/json; charset=utf-8"}
    key = (settings.sms_api_key or "").strip()
    if key:
        headers["Authorization"] = f"Bearer {key}"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            resp.read()
            return 200 <= int(resp.status) < 300
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, OSError) as exc:
        logger.warning("sms send failed: %s", exc)
        return False


def cascade_send(
    *,
    telegram_chat_id: str | None,
    phone: str | None,
    text: str,
) -> dict[str, Any]:
    """
    Каскад: Telegram → SMS → fail.
    Возвращает {ok, channel, detail}.
    """
    text = (text or "").strip()
    if not text:
        return {"ok": False, "channel": "none", "detail": "Пустой текст"}

    chat = (telegram_chat_id or "").strip()
    if chat and bot_configured():
        if send_telegram_message(chat, text):
            return {"ok": True, "channel": "telegram", "detail": "Отправлено в Telegram"}
        # не валимся сразу — пробуем SMS

    if sms_configured() and send_sms(phone or "", text):
        return {"ok": True, "channel": "sms", "detail": "Отправлено SMS (Telegram недоступен)"}

    if not chat:
        return {
            "ok": False,
            "channel": "none",
            "detail": "Клиент не привязал Telegram",
        }
    if not bot_configured():
        return {"ok": False, "channel": "none", "detail": "Telegram-бот не настроен на сервере"}
    return {"ok": False, "channel": "none", "detail": "Не удалось доставить сообщение"}


NOTIFY_KIND_TITLES = {
    "booking": "Подтверждение записи",
    "tomorrow": "Напоминание на завтра",
    "ready": "Автомобиль готов",
    "debt": "Напоминание об оплате",
    "custom": "Сообщение",
}
