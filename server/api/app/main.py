from contextlib import asynccontextmanager
from html import escape
from urllib.parse import quote

from fastapi import FastAPI, Query
from fastapi.responses import HTMLResponse
from sqlalchemy import select

from app.db import Base, SessionLocal, engine
from app.models import Company
from app.routers import auth, bugs, cash, company, crm, crm_extra, platform, updates
from app.seed import ensure_user_phone_column, seed_database


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    ensure_user_phone_column()
    db = SessionLocal()
    try:
        seed_database(db)
    finally:
        db.close()
    yield


app = FastAPI(title="Det App API", version="0.16.17", lifespan=lifespan)
app.include_router(auth.router)
app.include_router(platform.router)
app.include_router(company.router)
app.include_router(crm.router)
app.include_router(crm_extra.router)
app.include_router(cash.router)
app.include_router(updates.router)
app.include_router(bugs.router)


@app.get("/health")
def health():
    return {"ok": True, "service": "det-app-api", "version": "0.16.17"}


@app.get("/")
def root():
    return {
        "name": "Det App API",
        "docs": "/docs",
        "health": "/health",
        "auth": "/auth/login",
        "crm": "/crm/orders",
        "cash": "/cash/shifts/current",
        "updates": "/updates/latest.json",
        "bugs": "/bugs",
        "join": "/join?slug=код-студии",
        "version": "0.16.17",
    }


@app.get("/join", response_class=HTMLResponse)
def cloud_join(slug: str = Query(default="", min_length=0)):
    """QR приглашения: камера открывает страницу → Det App с кодом студии."""
    s = (slug or "").strip().lower()
    studio_name = ""
    if len(s) >= 2:
        db = SessionLocal()
        try:
            row = db.scalar(select(Company).where(Company.slug == s, Company.is_active.is_(True)))
            if row is not None:
                studio_name = row.name
        finally:
            db.close()

    deep = f"detapp://invite?slug={quote(s)}" if s else "detapp://invite"
    intent = (
        f"intent://invite?slug={quote(s)}#Intent;scheme=detapp;"
        f"package=com.example.det_app;"
        f"S.browser_fallback_url={quote(f'http://api.det-app.ru/updates/android')};end"
    )
    title = escape(studio_name) if studio_name else "Det App"
    slug_safe = escape(s) if s else "—"
    hint = (
        f"Студия «{escape(studio_name)}» · код <b>{slug_safe}</b>"
        if studio_name
        else (f"Код студии: <b>{slug_safe}</b>" if s else "В ссылке нет кода студии")
    )
    html = f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>{title} — приглашение</title>
<style>
  body{{margin:0;font-family:system-ui,sans-serif;background:#0f1419;color:#f1f5f9;
       padding:28px 20px;text-align:center}}
  h1{{font-size:22px;margin:0 0 8px}}
  p{{color:#94a3b8;line-height:1.45;font-size:14px}}
  a.btn{{display:block;margin:14px 0;padding:16px;border-radius:12px;text-decoration:none;
        font-weight:700;color:#fff}}
  .primary{{background:#2563eb}}
  .ok{{background:#16a34a}}
  .muted{{background:#334155}}
  code{{display:block;margin-top:16px;padding:10px;background:#1e293b;border-radius:8px;
       font-size:12px;word-break:break-all;color:#e2e8f0}}
</style>
</head>
<body>
  <h1>Det App</h1>
  <p>{hint}</p>
  <p>Откройте приложение и отправьте заявку на доступ. Должность назначит администратор студии.</p>
  <a class="btn ok" href="{escape(intent)}">Открыть Det App</a>
  <a class="btn primary" href="{escape(deep)}">Открыть (запасная ссылка)</a>
  <a class="btn muted" href="http://api.det-app.ru/updates/android">Скачать APK</a>
  <p>Нет приложения? Сначала установите APK, затем нажмите «Открыть» снова.<br>
  Либо на экране входа: «Меня пригласили» → введите код <b>{slug_safe}</b>.</p>
  <code>{escape(deep)}</code>
  <script>
    setTimeout(function(){{ location.href = {intent!r}; }}, 250);
    setTimeout(function(){{ location.href = {deep!r}; }}, 800);
  </script>
</body>
</html>"""
    return HTMLResponse(html)
