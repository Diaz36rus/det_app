# -*- coding: utf-8 -*-
"""Clear active cloud orders from the board (mark as Выдан). Works on current API."""
import json
import urllib.request

BASE = "http://api.det-app.ru"
LOGIN = "owner@demo.det-app.ru"
PASSWORD = "DetAppAdmin2026!"


def req(method, path, token=None, body=None):
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
    h = {"Content-Type": "application/json; charset=utf-8"}
    if token:
        h["Authorization"] = f"Bearer {token}"
    r = urllib.request.Request(BASE + path, data=data, headers=h, method=method)
    with urllib.request.urlopen(r, timeout=60) as resp:
        raw = resp.read().decode("utf-8")
        return None if (not raw or raw.strip() == "null") else json.loads(raw)


def main():
    token = req("POST", "/auth/login", body={"login": LOGIN, "password": PASSWORD})["access_token"]
    orders = req("GET", "/crm/orders", token=token) or []
    cleared = 0
    for o in orders:
        if o.get("status") == "Выдан":
            continue
        req("PATCH", f"/crm/orders/{o['id']}", token=token, body={"status": "Выдан"})
        cleared += 1
        print(f"cleared #{o['id']} {o.get('status')} -> Vydan", flush=True)
    left = [o for o in (req("GET", "/crm/orders", token=token) or []) if o.get("status") != "Выдан"]
    print(json.dumps({"cleared": cleared, "active_left": len(left)}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
