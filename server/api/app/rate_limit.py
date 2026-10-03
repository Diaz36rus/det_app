"""In-memory sliding-window лимиты для публичных и auth-эндпоинтов (один процесс uvicorn)."""

from __future__ import annotations

import threading
import time
from collections import deque

from fastapi import HTTPException, Request

_lock = threading.Lock()
_hits: dict[str, deque[float]] = {}
_last_sweep = 0.0


def client_ip(request: Request) -> str:
    # uvicorn --proxy-headers подставляет реальный IP из X-Forwarded-For (Caddy).
    return request.client.host if request.client else "unknown"


def _sweep(now: float, horizon: float) -> None:
    global _last_sweep
    if now - _last_sweep < 60:
        return
    _last_sweep = now
    for key in [k for k, q in _hits.items() if not q or now - q[-1] > horizon]:
        _hits.pop(key, None)


def hit(key: str, limit: int, window_sec: float) -> None:
    """Регистрирует попытку; 429 при превышении `limit` за `window_sec`."""
    now = time.monotonic()
    with _lock:
        _sweep(now, 3600)
        q = _hits.setdefault(key, deque())
        while q and now - q[0] > window_sec:
            q.popleft()
        if len(q) >= limit:
            retry = max(1, int(window_sec - (now - q[0])) + 1)
            raise HTTPException(
                status_code=429,
                detail="Слишком много попыток. Повторите позже.",
                headers={"Retry-After": str(retry)},
            )
        q.append(now)


def reset(key: str) -> None:
    with _lock:
        _hits.pop(key, None)


def limit_by_ip(scope: str, limit: int, window_sec: float):
    """Dependency: лимит запросов с одного IP на `scope`."""

    def _dep(request: Request) -> None:
        hit(f"{scope}:{client_ip(request)}", limit, window_sec)

    return _dep
