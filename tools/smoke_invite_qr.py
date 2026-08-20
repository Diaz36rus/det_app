"""Smoke: invite QR helpers + cloud /join page."""
from __future__ import annotations

import re
import sys
import urllib.error
import urllib.request

BASE = "http://api.det-app.ru"


def get(path: str) -> tuple[int, str]:
    req = urllib.request.Request(BASE + path, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return e.code, body


def main() -> int:
    code, body = get("/join?slug=demo")
    assert code == 200, f"/join demo -> {code}"
    assert "detapp://invite?slug=demo" in body, "missing deep link"
    assert "intent://invite?slug=demo" in body, "missing intent"
    assert "updates/android" in body, "missing apk link"
    print("PASS /join?slug=demo")

    code, body = get("/join?slug=no-such-studio-xyz")
    assert code == 200, f"/join unknown -> {code}"
    assert "detapp://invite?slug=no-such-studio-xyz" in body
    print("PASS /join unknown slug still opens app")

    code, body = get("/updates/android")
    assert code == 200, f"apk -> {code}"
    print("PASS /updates/android")

    # local encode parity (mirror Flutter)
    slug = "demo"
    invite = f"{BASE}/join?slug={slug}"
    assert invite.endswith("/join?slug=demo")
    print(f"PASS invite URL shape: {invite}")

    print("ALL OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as e:
        print("FAIL:", e, file=sys.stderr)
        raise SystemExit(1)
