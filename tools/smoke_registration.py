# -*- coding: utf-8 -*-
"""Smoke: регистрация студии / филиала / сотрудников / pending assign.

Usage (PowerShell):
  $env:PLATFORM_ADMIN_EMAIL="igorkarikh36@gmail.com"
  $env:PLATFORM_ADMIN_PASSWORD="…"
  python tools/smoke_registration.py

Пишет отчёт в tools/_smoke_shots/registration_smoke.json
Не трогает чужие боевые аккаунты — только smoke+…@det-app.test
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE = os.environ.get("DET_API_BASE", "http://api.det-app.ru").rstrip("/")
OWNER_EMAIL = os.environ.get("PLATFORM_ADMIN_EMAIL", "igorkarikh36@gmail.com")
OWNER_PASS = os.environ.get("PLATFORM_ADMIN_PASSWORD", "")
STAMP = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
# Не .test — email-validator режет reserved TLD.
MAIL_DOMAIN = os.environ.get("SMOKE_MAIL_DOMAIN", "smoke.det-app.ru")
OUT = Path(__file__).resolve().parents[1] / "tools" / "_smoke_shots" / "registration_smoke.json"


class Fail(Exception):
    pass


def req(method: str, path: str, *, token: str | None = None, body: dict | None = None, expect: int = 200):
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    r = urllib.request.Request(f"{BASE}{path}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=25) as resp:
            raw = resp.read()
            code = resp.status
            payload = json.loads(raw.decode("utf-8")) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            payload = json.loads(raw.decode("utf-8")) if raw else {"detail": str(e)}
        except Exception:
            payload = {"detail": raw.decode("utf-8", errors="replace")}
        code = e.code
    if code != expect and not (expect == 200 and code in (200, 201)):
        raise Fail(f"{method} {path} -> HTTP {code}: {payload}")
    return code, payload


def login(ident: str, password: str) -> str:
    _, tok = req("POST", "/auth/login", body={"login": ident, "password": password})
    access = (tok or {}).get("access_token")
    if not access:
        raise Fail(f"login {ident}: no access_token")
    return access


def main() -> int:
    if not OWNER_PASS:
        print("Set PLATFORM_ADMIN_PASSWORD", file=sys.stderr)
        return 2

    report: dict = {
        "started_at": datetime.now(timezone.utc).isoformat(),
        "base": BASE,
        "stamp": STAMP,
        "steps": [],
        "ok": False,
    }

    def step(name: str, fn):
        t0 = time.time()
        try:
            detail = fn()
            report["steps"].append(
                {"name": name, "ok": True, "ms": int((time.time() - t0) * 1000), "detail": detail}
            )
            print(f"OK  {name}: {detail}")
            return detail
        except Exception as e:
            report["steps"].append(
                {"name": name, "ok": False, "ms": int((time.time() - t0) * 1000), "error": str(e)}
            )
            print(f"FAIL {name}: {e}", file=sys.stderr)
            raise

    try:
        platform_tok = step(
            "platform_login",
            lambda: {"token_len": len(login(OWNER_EMAIL, OWNER_PASS))},
        )
        # re-login to get token in outer scope
        platform_tok = login(OWNER_EMAIL, OWNER_PASS)

        me = step("platform_me", lambda: req("GET", "/auth/me", token=platform_tok)[1])
        if not me.get("is_platform_admin"):
            raise Fail("user is not platform admin")

        slug = f"smoke-{STAMP}"
        studio_owner_email = f"smoke+owner-{STAMP}@{MAIL_DOMAIN}"
        studio_owner_pass = f"SmokeOwn{STAMP[-6:]}!"
        company_body = {
            "name": f"Smoke Studio {STAMP}",
            "slug": slug,
            "branch_name": "Основной филиал",
            "owner_email": studio_owner_email,
            "owner_password": studio_owner_pass,
            "owner_full_name": f"Smoke Owner {STAMP}",
            "owner_phone": f"900{STAMP[-7:]}",
        }

        created = step(
            "create_studio_with_owner",
            lambda: req("POST", "/platform/companies", token=platform_tok, body=company_body)[1],
        )
        company_id = created["company"]["id"]
        branch_id = created["branch"]["id"]
        if not created.get("owner_user_id"):
            raise Fail("owner_user_id missing")

        companies = step(
            "list_companies",
            lambda: req("GET", "/platform/companies", token=platform_tok)[1],
        )
        if not any(c.get("id") == company_id for c in companies):
            raise Fail("new company not in list")

        branch2 = step(
            "add_second_branch",
            lambda: req(
                "POST",
                f"/platform/companies/{company_id}/branches",
                token=platform_tok,
                body={"name": f"Филиал 2 {STAMP}"},
            )[1],
        )

        branches = step(
            "list_company_branches",
            lambda: req("GET", f"/platform/companies/{company_id}/branches", token=platform_tok)[1],
        )
        if len(branches) < 2:
            raise Fail(f"expected >=2 branches, got {len(branches)}")

        studio_tok = login(studio_owner_email, studio_owner_pass)
        step("studio_owner_login", lambda: {"email": studio_owner_email})

        studio_me = step("studio_owner_me", lambda: req("GET", "/auth/me", token=studio_tok)[1])
        if studio_me.get("company_id") != company_id:
            raise Fail("studio owner company_id mismatch")
        if "Владелец" not in (studio_me.get("roles") or []):
            raise Fail(f"expected role Владелец, got {studio_me.get('roles')}")

        admin_email = f"smoke+admin-{STAMP}@{MAIL_DOMAIN}"
        admin_pass = f"SmokeAdm{STAMP[-6:]}!"
        admin = step(
            "create_admin",
            lambda: req(
                "POST",
                "/company/users",
                token=studio_tok,
                body={
                    "email": admin_email,
                    "password": admin_pass,
                    "full_name": f"Smoke Admin {STAMP}",
                    "phone": f"901{STAMP[-7:]}",
                    "role_names": ["Администратор"],
                    "branch_ids": [branch_id],
                    "workshops": [],
                    "link_master": False,
                },
            )[1],
        )
        if admin.get("pending_assignment"):
            raise Fail("admin should not be pending")

        mgr_email = f"smoke+mgr-{STAMP}@{MAIL_DOMAIN}"
        mgr_pass = f"SmokeMgr{STAMP[-6:]}!"
        step(
            "create_manager",
            lambda: req(
                "POST",
                "/company/users",
                token=studio_tok,
                body={
                    "email": mgr_email,
                    "password": mgr_pass,
                    "full_name": f"Smoke Manager {STAMP}",
                    "role_names": ["Управляющий"],
                    "branch_ids": [branch2["id"]],
                    "workshops": [],
                },
            )[1],
        )

        master_email = f"smoke+master-{STAMP}@{MAIL_DOMAIN}"
        master_pass = f"SmokeMst{STAMP[-6:]}!"
        master = step(
            "create_master",
            lambda: req(
                "POST",
                "/company/users",
                token=studio_tok,
                body={
                    "email": master_email,
                    "password": master_pass,
                    "full_name": f"Smoke Master {STAMP}",
                    "role_names": ["Мастер"],
                    "branch_ids": [branch_id],
                    "workshops": ["Мойка", "Полировка"],
                    "link_master": True,
                },
            )[1],
        )
        if not master.get("master_id"):
            raise Fail("master_id not linked")

        step(
            "studio_create_branch",
            lambda: req(
                "POST",
                "/company/branches",
                token=studio_tok,
                body={"name": f"Филиал студии {STAMP}"},
            )[1],
        )

        pending_email = f"smoke+pending-{STAMP}@{MAIL_DOMAIN}"
        pending_pass = f"SmokePen{STAMP[-6:]}!"
        step(
            "request_access",
            lambda: req(
                "POST",
                "/auth/request-access",
                body={
                    "email": pending_email,
                    "password": pending_pass,
                    "full_name": f"Smoke Pending {STAMP}",
                    "phone": f"902{STAMP[-7:]}",
                    "company_slug": slug,
                },
            )[1],
        )

        pending_list = step(
            "list_pending",
            lambda: req("GET", "/company/users?pending=true", token=studio_tok)[1],
        )
        pending_user = next((u for u in pending_list if u.get("email") == pending_email), None)
        if pending_user is None:
            raise Fail("pending user not found in list")

        assigned = step(
            "assign_pending",
            lambda: req(
                "PATCH",
                f"/company/users/{pending_user['id']}/assign",
                token=studio_tok,
                body={
                    "role_names": ["Мастер"],
                    "branch_ids": [branch_id],
                    "workshops": ["Химчистка"],
                    "link_master": True,
                },
            )[1],
        )
        if assigned.get("pending_assignment"):
            raise Fail("still pending after assign")

        # logins
        for label, email, pw, expect_role in [
            ("login_admin", admin_email, admin_pass, "Администратор"),
            ("login_manager", mgr_email, mgr_pass, "Управляющий"),
            ("login_master", master_email, master_pass, "Мастер"),
            ("login_assigned", pending_email, pending_pass, "Мастер"),
        ]:

            def _check(email=email, pw=pw, expect_role=expect_role):
                tok = login(email, pw)
                info = req("GET", "/auth/me", token=tok)[1]
                roles = info.get("roles") or []
                if expect_role not in roles:
                    raise Fail(f"expected {expect_role}, got {roles}")
                return {"email": email, "roles": roles, "company_id": info.get("company_id")}

            step(label, _check)

        # duplicate email should fail
        def dup():
            code, payload = req(
                "POST",
                "/company/users",
                token=studio_tok,
                body={
                    "email": admin_email,
                    "password": "Another1!",
                    "full_name": "Dup",
                    "role_names": ["Мастер"],
                    "branch_ids": [branch_id],
                },
                expect=400,
            )
            return {"http": code, "detail": payload}

        step("reject_duplicate_email", dup)

        report["ok"] = True
        report["artifacts"] = {
            "company_id": company_id,
            "slug": slug,
            "studio_owner_email": studio_owner_email,
            "admin_email": admin_email,
            "manager_email": mgr_email,
            "master_email": master_email,
            "pending_then_assigned_email": pending_email,
            "passwords_hint": f"SmokeXxx{STAMP[-6:]}!  (Own/Adm/Mgr/Mst/Pen)",
            "note": "Учётки @smoke.det-app.ru — только для тестов, можно чистить позже.",
        }
    except Exception:
        report["ok"] = False
    finally:
        report["finished_at"] = datetime.now(timezone.utc).isoformat()
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\nReport: {OUT}")
        print("PASS" if report["ok"] else "FAIL")

    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
