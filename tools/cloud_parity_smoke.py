# -*- coding: utf-8 -*-
"""Extended cloud smoke for API 0.16.2 gaps (deletes, payment patch, promo, roles, registers)."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = "http://api.det-app.ru"
LOGIN = "owner@demo.det-app.ru"
PASSWORD = "DetAppAdmin2026!"
OUT = Path(__file__).resolve().parent / "_smoke_shots" / "cloud_parity_smoke.json"


def req(method: str, path: str, token: str | None = None, body: dict | None = None, query: str = ""):
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    url = BASE + path + (("?" + query) if query else "")
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            if resp.status == 204 or not raw.strip():
                return {"_status": resp.status}
            return json.loads(raw)
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"FAIL {method} {path} -> {e.code}: {err}") from e


def main() -> None:
    stamp = int(time.time())
    log: dict = {"stamp": stamp, "steps": []}

    health = req("GET", "/health")
    assert health.get("version") == "0.16.2", health
    log["steps"].append({"health": health["version"]})

    token = req("POST", "/auth/login", body={"login": LOGIN, "password": PASSWORD})["access_token"]

    # --- services catalog present ---
    services = req("GET", "/crm/services", token=token) or []
    active = [s for s in services if s.get("is_active", True)]
    assert len(active) >= 80, f"services too few: {len(active)}"
    log["steps"].append({"services_active": len(active)})

    # --- client + car + order ---
    phone = f"905{stamp % 10000000:07d}"
    client = req(
        "POST",
        "/crm/clients",
        token=token,
        body={"name": f"ParitySmoke {stamp % 10000}", "phone": phone, "is_vip": False},
    )
    car = req(
        "POST",
        "/crm/cars",
        token=token,
        body={
            "client_id": client["id"],
            "make_model": "Smoke Car",
            "plate": f"S{stamp % 10000:04d}77",
            "vin": "",
            "category": "1",
        },
    )
    svc = next((s for s in active if s.get("name") == "Мойка кузова"), active[0])
    order = req(
        "POST",
        "/crm/orders",
        token=token,
        body={
            "client_id": client["id"],
            "car_id": car["id"],
            "status": "Принят в работу",
            "items": [
                {
                    "name": svc["name"],
                    "price": float(svc.get("price") or 1000),
                    "workshop": svc.get("workshop") or "Мойка",
                }
            ],
        },
    )
    order_id = order["id"]
    item_id = order["items"][0]["id"]
    log["steps"].append({"created_order": order_id, "client": client["id"]})

    # open shift if needed
    cur = req("GET", "/cash/shifts/current", token=token)
    if not cur or cur.get("status") != "open":
        cur = req("POST", "/cash/shifts/open", token=token, body={"openings": {}, "note": "parity"})
    log["steps"].append({"shift": cur["id"]})

    # payment create + patch
    pay = req(
        "POST",
        "/cash/payments",
        token=token,
        body={"order_id": order_id, "amount": 500, "method": "Наличные"},
    )
    pay2 = req(
        "PATCH",
        f"/cash/payments/{pay['id']}",
        token=token,
        body={"amount": 700, "method": "Наличные"},
    )
    assert float(pay2["amount"]) == 700, pay2
    refreshed = req("GET", f"/crm/orders/{order_id}", token=token)
    assert float(refreshed.get("paid_amount") or 0) == 700, refreshed
    log["steps"].append({"payment_patch": pay2["id"], "paid": refreshed["paid_amount"]})

    # defect + delete
    defect = req(
        "POST",
        f"/crm/orders/{order_id}/defects",
        token=token,
        body={"description": "scratch smoke", "workshop": "Мойка", "photo_b64": ""},
    )
    req("DELETE", f"/crm/defects/{defect['id']}", token=token)
    left = req("GET", f"/crm/orders/{order_id}/defects", token=token) or []
    assert all(d["id"] != defect["id"] for d in left)
    log["steps"].append({"defect_deleted": defect["id"]})

    # promocode upsert + get + delete
    code = f"P{stamp % 100000}"
    promo = req(
        "POST",
        "/crm/promocodes",
        token=token,
        body={"code": code, "discount_percent": 10, "discount_fixed": 0},
    )
    got = req("GET", f"/crm/promocodes/{code}", token=token)
    assert got["code"].upper() == code.upper()
    req("DELETE", f"/crm/promocodes/{promo['id']}", token=token)
    log["steps"].append({"promocode": code})

    # workshop role
    role_name = f"SmokeRole{stamp % 1000}"
    role = req("POST", "/crm/workshop-roles", token=token, body={"name": role_name})
    roles = req("GET", "/crm/workshop-roles", token=token) or []
    assert any(r["name"] == role_name for r in roles)
    req("DELETE", f"/crm/workshop-roles/{role['id']}", token=token)
    log["steps"].append({"workshop_role": role_name})

    # register create
    reg_name = f"SmokeReg {stamp % 1000}"
    try:
        reg = req(
            "POST",
            "/cash/registers",
            token=token,
            body={"name": reg_name, "money_type": "Наличные", "sort_order": 99},
        )
        req("PATCH", f"/cash/registers/{reg['id']}", token=token, body={"is_active": False})
        log["steps"].append({"register": reg["id"]})
    except SystemExit as e:
        # unique name collision — still ok if endpoint exists
        log["steps"].append({"register_error": str(e)})
        raise

    # delete order item then order then client
    req("DELETE", f"/crm/orders/{order_id}/items/{item_id}", token=token)
    req("DELETE", f"/crm/orders/{order_id}", token=token)
    req("DELETE", f"/crm/clients/{client['id']}", token=token)
    clients = req("GET", "/crm/clients", token=token) or []
    assert all(c["id"] != client["id"] for c in clients)
    log["steps"].append({"client_deleted": client["id"]})

    # clear-board soft (should be no-op or clear leftovers)
    cleared = req("POST", "/crm/orders/clear-board", token=token, body={})
    log["steps"].append({"clear_board": cleared})

    log["ok"] = True
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(log, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(log, ensure_ascii=False, indent=2))
    print("OK cloud parity smoke")


if __name__ == "__main__":
    main()
