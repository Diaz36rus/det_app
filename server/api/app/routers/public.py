"""Публичная запись на сайте и API лидов для интеграторов."""

from __future__ import annotations

from html import escape

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.lead_util import create_studio_lead
from app.models import Company, CrmMaster, CrmOrder
from app.rate_limit import limit_by_ip

router = APIRouter(tags=["public"])

BOOKING_LEAD_SOURCE = "Сайт"
PUBLIC_BASE = "https://api.det-app.ru"
_DONE = "Выдан"


def _clip(value: object, limit: int) -> str:
    return str(value or "").strip()[:limit]


def _booking_url(slug: str) -> str:
    return f"{PUBLIC_BASE}/book/{slug}"


def _get_company_by_slug(db: Session, slug: str) -> Company:
    s = (slug or "").strip().lower()
    if len(s) < 2:
        raise HTTPException(status_code=404, detail="Студия не найдена")
    row = db.scalar(select(Company).where(Company.slug == s, Company.is_active.is_(True)))
    if row is None:
        raise HTTPException(status_code=404, detail="Студия не найдена")
    if not getattr(row, "booking_enabled", True):
        raise HTTPException(status_code=403, detail="Онлайн-запись отключена")
    return row


def _thank_you_html(company_name: str, slug: str) -> str:
    title = escape(company_name)
    slug_e = escape(slug)
    return f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Заявка принята — {title}</title>
<style>
  body{{margin:0;font-family:system-ui,sans-serif;background:#0f1419;color:#f1f5f9;padding:32px 20px}}
  .card{{max-width:480px;margin:0 auto;background:#1e293b;border-radius:16px;padding:28px 24px}}
  h1{{font-size:22px;margin:0 0 12px;color:#22c55e}}
  p{{color:#94a3b8;line-height:1.5;font-size:15px;margin:0 0 16px}}
  a{{color:#60a5fa;text-decoration:none}}
</style>
</head>
<body>
  <div class="card">
    <h1>Спасибо!</h1>
    <p>Ваша заявка принята. Студия «{title}» свяжется с вами для подтверждения записи.</p>
    <p><a href="/book/{slug_e}">← Назад</a></p>
  </div>
</body>
</html>"""


def _booking_form_html(company: Company) -> str:
    slug = escape(company.slug)
    name = escape(company.name)
    return f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Запись — {name}</title>
<style>
  body{{margin:0;font-family:system-ui,sans-serif;background:#0f1419;color:#f1f5f9;padding:24px 16px}}
  .card{{max-width:520px;margin:0 auto;background:#1e293b;border-radius:16px;padding:24px 20px}}
  h1{{font-size:22px;margin:0 0 4px}}
  .sub{{color:#94a3b8;font-size:14px;margin:0 0 20px}}
  label{{display:block;font-size:13px;color:#cbd5e1;margin:14px 0 6px}}
  input,textarea{{width:100%;box-sizing:border-box;padding:12px;border-radius:10px;border:1px solid #334155;
                  background:#0f172a;color:#f8fafc;font-size:15px}}
  textarea{{min-height:88px;resize:vertical}}
  .row{{display:flex;gap:12px}}
  .row > div{{flex:1}}
  button{{width:100%;margin-top:20px;padding:14px;border:none;border-radius:12px;background:#2563eb;
          color:#fff;font-size:16px;font-weight:700;cursor:pointer}}
  button:hover{{background:#1d4ed8}}
  .hint{{font-size:12px;color:#64748b;margin-top:16px;text-align:center}}
</style>
</head>
<body>
  <div class="card">
    <h1>{name}</h1>
    <p class="sub">Онлайн-запись · Det App</p>
    <form method="post" action="/book/{slug}">
      <input name="website" tabindex="-1" autocomplete="off" aria-hidden="true"
             style="position:absolute;left:-9999px;width:1px;height:1px;opacity:0"/>
      <label for="name">Ваше имя *</label>
      <input id="name" name="name" required maxlength="200" autocomplete="name"/>

      <label for="phone">Телефон *</label>
      <input id="phone" name="phone" type="tel" required maxlength="32" autocomplete="tel"/>

      <label for="car">Автомобиль</label>
      <input id="car" name="car" maxlength="200" placeholder="Марка, модель"/>

      <label for="note">Услуга / комментарий</label>
      <textarea id="note" name="note" maxlength="4000" placeholder="Что нужно сделать?"></textarea>

      <div class="row">
        <div>
          <label for="preferred_date">Желаемая дата</label>
          <input id="preferred_date" name="preferred_date" type="date"/>
        </div>
        <div>
          <label for="preferred_time">Время</label>
          <input id="preferred_time" name="preferred_time" type="time"/>
        </div>
      </div>

      <button type="submit">Отправить заявку</button>
    </form>
    <p class="hint">Отправляя форму, вы соглашаетесь на обработку контактных данных для связи.</p>
  </div>
</body>
</html>"""


class PublicLeadCreate(BaseModel):
    name: str = Field(default="", max_length=200)
    phone: str = Field(default="", max_length=32)
    car_label: str = Field(default="", max_length=200)
    note: str = Field(default="", max_length=4000)
    lead_source: str = Field(default="", max_length=80)


class PublicLeadOut(BaseModel):
    id: int
    company_id: int
    name: str
    phone: str
    car_label: str
    lead_source: str
    note: str
    status: str


def _company_by_api_key(db: Session, api_key: str | None) -> Company:
    key = (api_key or "").strip()
    if len(key) < 16:
        raise HTTPException(status_code=401, detail="Нужен X-Api-Key или query token")
    row = db.scalar(
        select(Company).where(Company.api_key == key, Company.is_active.is_(True))
    )
    if row is None:
        raise HTTPException(status_code=401, detail="Неверный API-ключ")
    return row


@router.get("/public/demo", dependencies=[Depends(limit_by_ip("public-demo", 60, 60))])
def public_demo_pulse(db: Session = Depends(get_db)):
    """Агрегаты только демо-студии — без имён, телефонов и номеров."""
    company = db.scalar(select(Company).where(Company.slug == "demo", Company.is_active.is_(True)))
    if company is None:
        raise HTTPException(status_code=404, detail="Демо недоступно")
    cid = company.id
    open_n = db.scalar(
        select(func.count()).select_from(CrmOrder).where(
            CrmOrder.company_id == cid, CrmOrder.status != _DONE
        )
    ) or 0
    done_n = db.scalar(
        select(func.count()).select_from(CrmOrder).where(
            CrmOrder.company_id == cid, CrmOrder.status == _DONE
        )
    ) or 0
    pipeline = db.scalar(
        select(func.coalesce(func.sum(CrmOrder.price), 0)).where(
            CrmOrder.company_id == cid, CrmOrder.status != _DONE
        )
    ) or 0
    on_shift = db.scalar(
        select(func.count()).select_from(CrmMaster).where(
            CrmMaster.company_id == cid,
            CrmMaster.is_active.is_(True),
            CrmMaster.on_shift.is_(True),
        )
    ) or 0
    masters_total = db.scalar(
        select(func.count()).select_from(CrmMaster).where(
            CrmMaster.company_id == cid, CrmMaster.is_active.is_(True)
        )
    ) or 0
    status_rows = db.execute(
        select(CrmOrder.status, func.count())
        .where(CrmOrder.company_id == cid)
        .group_by(CrmOrder.status)
    ).all()
    status_map = {str(name or "").strip() or "Без статуса": int(n) for name, n in status_rows}
    order = [
        "Предварительная запись",
        "Принят в работу",
        "Мойка",
        "Химчистка",
        "Полировка",
        "Кузовные работы",
        "Оклейка",
        "Интерьер",
        _DONE,
    ]
    columns = [{"name": name, "count": status_map.pop(name, 0)} for name in order]
    for name, n in sorted(status_map.items(), key=lambda x: (-x[1], x[0])):
        columns.append({"name": name, "count": n})
    return {
        "ok": True,
        "slug": company.slug,
        "name": company.name,
        "open_orders": int(open_n),
        "done_orders": int(done_n),
        "on_shift": int(on_shift),
        "masters_total": int(masters_total),
        "pipeline": float(pipeline),
        "columns": columns,
        "booking_enabled": bool(getattr(company, "booking_enabled", True)),
    }


@router.get("/book/{slug}", response_class=HTMLResponse)
def booking_page(slug: str, db: Session = Depends(get_db)):
    company = _get_company_by_slug(db, slug)
    return HTMLResponse(_booking_form_html(company))


@router.get("/book/{slug}/api")
def booking_info(slug: str, db: Session = Depends(get_db)):
    company = _get_company_by_slug(db, slug)
    return {
        "company_name": company.name,
        "slug": company.slug,
        "booking_enabled": bool(getattr(company, "booking_enabled", True)),
        "booking_url": _booking_url(company.slug),
        "open_hours": None,
    }


@router.post("/book/{slug}", dependencies=[Depends(limit_by_ip("book", 8, 600))])
async def booking_submit(slug: str, request: Request, db: Session = Depends(get_db)):
    company = _get_company_by_slug(db, slug)
    ctype = (request.headers.get("content-type") or "").lower()

    if "application/json" in ctype:
        try:
            data = await request.json()
        except ValueError:
            raise HTTPException(status_code=400, detail="Некорректный JSON") from None
        if not isinstance(data, dict):
            raise HTTPException(status_code=400, detail="Некорректный JSON")
    else:
        data = await request.form()

    if _clip(data.get("website"), 200):
        # Honeypot: скрытое поле заполняют только боты — отвечаем «ок», лид не пишем.
        if "application/json" in ctype:
            return JSONResponse({"ok": True, "message": "Заявка принята"})
        return HTMLResponse(_thank_you_html(company.name, company.slug))

    name = _clip(data.get("name"), 200)
    phone = _clip(data.get("phone"), 32)
    car = _clip(data.get("car") or data.get("car_label"), 200)
    note = _clip(data.get("note"), 4000)
    preferred_date = _clip(data.get("preferred_date"), 32)
    preferred_time = _clip(data.get("preferred_time"), 16)

    if sum(ch.isdigit() for ch in phone) < 5:
        raise HTTPException(status_code=422, detail="Укажите телефон")

    extra_parts: list[str] = []
    if preferred_date:
        extra_parts.append(f"Дата: {preferred_date}")
    if preferred_time:
        extra_parts.append(f"Время: {preferred_time}")
    full_note = note
    if extra_parts:
        suffix = " · ".join(extra_parts)
        full_note = f"{full_note}\n{suffix}".strip() if full_note else suffix

    create_studio_lead(
        db,
        company_id=company.id,
        name=name,
        phone=phone,
        car_label=car,
        lead_source=BOOKING_LEAD_SOURCE,
        note=full_note,
        status="new",
    )

    if "application/json" in ctype:
        return JSONResponse({"ok": True, "message": "Заявка принята"})
    return HTMLResponse(_thank_you_html(company.name, company.slug))


@router.post(
    "/public/v1/leads",
    response_model=PublicLeadOut,
    dependencies=[Depends(limit_by_ip("public-leads", 60, 60))],
)
def public_create_lead(
    body: PublicLeadCreate,
    db: Session = Depends(get_db),
    x_api_key: str | None = Header(default=None, alias="X-Api-Key"),
    token: str | None = Query(default=None),
):
    company = _company_by_api_key(db, x_api_key or token)
    phone = (body.phone or "").strip()
    if len(phone) < 5:
        raise HTTPException(status_code=422, detail="Укажите телефон")
    row = create_studio_lead(
        db,
        company_id=company.id,
        name=body.name,
        phone=phone,
        car_label=body.car_label,
        lead_source=(body.lead_source or "").strip() or "API",
        note=body.note,
        status="new",
    )
    return PublicLeadOut(
        id=row.id,
        company_id=row.company_id,
        name=row.name,
        phone=row.phone,
        car_label=row.car_label,
        lead_source=row.lead_source,
        note=row.note,
        status=row.status,
    )
