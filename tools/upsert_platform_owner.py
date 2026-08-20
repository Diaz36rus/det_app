# -*- coding: utf-8 -*-
"""Upsert владельца платформы (is_platform_admin) из env — пароль не хранить в git.

Usage (PowerShell):
  $env:PLATFORM_ADMIN_EMAIL="igorkarikh36@gmail.com"
  $env:PLATFORM_ADMIN_PHONE="79803447473"
  $env:PLATFORM_ADMIN_NAME="Игорь Карих"
  $env:PLATFORM_ADMIN_PASSWORD="…"
  python tools/upsert_platform_owner.py

Или против уже запущенного API через SQL на сервере — этот скрипт бьёт в БД
по DATABASE_URL / локальному import seed path.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server" / "api"))

from app.config import settings  # noqa: E402
from app.db import SessionLocal  # noqa: E402
from app.models import User  # noqa: E402
from app.phone_util import phone_digits10
from app.security import hash_password
from sqlalchemy import select  # noqa: E402


def main() -> None:
    email = (os.environ.get("PLATFORM_ADMIN_EMAIL") or settings.platform_admin_email).lower().strip()
    password = os.environ.get("PLATFORM_ADMIN_PASSWORD") or settings.platform_admin_password
    name = os.environ.get("PLATFORM_ADMIN_NAME") or settings.platform_admin_name
    phone_raw = os.environ.get("PLATFORM_ADMIN_PHONE") or settings.platform_admin_phone or ""
    phone = phone_digits10(phone_raw) if phone_raw else None

    if not email or not password:
        raise SystemExit("Need PLATFORM_ADMIN_EMAIL and PLATFORM_ADMIN_PASSWORD")

    db = SessionLocal()
    try:
        user = db.scalar(select(User).where(User.email == email))
        if user is None and phone:
            user = db.scalar(select(User).where(User.phone == phone))
        if user is None:
            user = User(
                email=email,
                phone=phone,
                password_hash=hash_password(password),
                full_name=name,
                is_platform_admin=True,
                is_active=True,
                company_id=None,
            )
            db.add(user)
            action = "created"
        else:
            user.email = email
            user.full_name = name
            user.is_platform_admin = True
            user.is_active = True
            user.company_id = None  # владелец приложения, не студии
            user.password_hash = hash_password(password)
            if phone:
                user.phone = phone
            action = "updated"
        db.commit()
        print(f"OK {action} platform owner id={user.id} email={user.email} phone={user.phone}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
