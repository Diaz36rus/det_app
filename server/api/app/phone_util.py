"""Нормализация телефона РФ → 10 цифр (без +7/8)."""
from __future__ import annotations

import re


def phone_digits10(raw: str | None) -> str | None:
    if not raw:
        return None
    digits = re.sub(r"\D+", "", raw.strip())
    if len(digits) == 11 and digits[0] in "78":
        digits = digits[1:]
    if len(digits) == 10 and digits.isdigit():
        return digits
    return None


def looks_like_email(raw: str) -> bool:
    s = raw.strip()
    return "@" in s and "." in s.split("@")[-1]
