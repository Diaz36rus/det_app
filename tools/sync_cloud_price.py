# -*- coding: utf-8 -*-
"""Sync full price catalog to cloud company via CRM API (demo by default).

Usage:
  python tools/sync_cloud_price.py
"""
from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server" / "api"))

from app.price_catalog import iter_price_catalog  # noqa: E402

BASE = "http://api.det-app.ru"
LOGIN = "owner@demo.det-app.ru"
PASSWORD = "DetAppAdmin2026!"


def req(method: str, path: str, token: str | None = None, body: dict | None = None):
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    r = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            return None if (not raw or raw.strip() == "null") else json.loads(raw)
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"{method} {path} -> {e.code}: {err}") from e


def main() -> None:
    catalog = iter_price_catalog()
    login = req("POST", "/auth/login", body={"login": LOGIN, "password": PASSWORD})
    token = login["access_token"]
    existing = req("GET", "/crm/services", token=token) or []
    by_name = {s["name"]: s for s in existing}

    created = updated = skipped = 0
    for item in catalog:
        cur = by_name.get(item["name"])
        if cur is None:
            row = req(
                "POST",
                "/crm/services",
                token=token,
                body={
                    "name": item["name"],
                    "category": item["category"],
                    "price": item["price"],
                    "workshop": item["workshop"],
                },
            )
            by_name[item["name"]] = row
            created += 1
            continue
        need = (
            cur.get("category") != item["category"]
            or float(cur.get("price") or 0) != float(item["price"])
            or (cur.get("workshop") or "") != (item["workshop"] or "")
            or not cur.get("is_active", True)
        )
        if not need:
            skipped += 1
            continue
        req(
            "PATCH",
            f"/crm/services/{cur['id']}",
            token=token,
            body={
                "category": item["category"],
                "price": item["price"],
                "workshop": item["workshop"],
                "is_active": True,
            },
        )
        updated += 1

    obsolete = {
        "Krytex все остекление 1 кл.",
        "Krytex все остекление 2 кл.",
        "Krytex все остекление 3 кл.",
        "Krytex все остекление 4 кл.",
    }
    deactivated = 0
    for name in obsolete:
        cur = by_name.get(name)
        if cur is None or not cur.get("is_active", True):
            continue
        req("PATCH", f"/crm/services/{cur['id']}", token=token, body={"is_active": False})
        deactivated += 1

    final = req("GET", "/crm/services", token=token) or []
    cats: dict[str, int] = {}
    for s in final:
        if not s.get("is_active", True):
            continue
        c = s.get("category") or "?"
        cats[c] = cats.get(c, 0) + 1

    out = {
        "catalog": len(catalog),
        "created": created,
        "updated": updated,
        "unchanged": skipped,
        "deactivated_obsolete": deactivated,
        "cloud_active": sum(1 for s in final if s.get("is_active", True)),
        "by_category": cats,
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    Path(ROOT / "tools" / "_smoke_shots" / "price_sync_result.json").write_text(
        json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
