"""Создание лида студии + вебхук lead.created."""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.models import CrmStudioLead
from app.webhooks import fire_webhooks


def create_studio_lead(
    db: Session,
    *,
    company_id: int,
    name: str = "",
    phone: str = "",
    car_label: str = "",
    lead_source: str = "",
    note: str = "",
    status: str = "new",
    order_id: int | None = None,
) -> CrmStudioLead:
    row = CrmStudioLead(
        company_id=company_id,
        name=(name or "").strip()[:200],
        phone=(phone or "").strip()[:32],
        car_label=(car_label or "").strip()[:200],
        lead_source=(lead_source or "").strip()[:80],
        note=(note or "").strip()[:4000],
        status=(status or "new").strip() or "new",
        order_id=order_id,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    fire_webhooks(
        db,
        company_id,
        "lead.created",
        {
            "id": row.id,
            "name": row.name,
            "phone": row.phone,
            "car_label": row.car_label,
            "lead_source": row.lead_source,
            "note": row.note,
            "status": row.status,
        },
    )
    return row
