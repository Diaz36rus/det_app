# -*- coding: utf-8 -*-
"""RuStore release: draft + AAB + listing + moderation.

Usage:
  python tools/publish_rustore.py --dry-run
  python tools/publish_rustore.py --status
  python tools/publish_rustore.py --watch
  python tools/publish_rustore.py --aab path/to/app-release.aab
  python tools/publish_rustore.py --aab ... --resume
  python tools/publish_rustore.py --aab ... --fresh
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
LISTING_PATH = TOOLS / "rustore_listing.json"
STATE_PATH = TOOLS / "rustore_state.json"
KEY_PATH = TOOLS / "rustore_key.json"
PERM_LOCK = TOOLS / "android_permissions.lock"
SCREENS_DIR = TOOLS / "rustore_screens"
PUBSPEC = ROOT / "pubspec.yaml"
PATCH_NOTES = ROOT / "lib" / "patch_notes.dart"
MANIFEST = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
KEY_PROPS = ROOT / "android" / "key.properties"
DEFAULT_AAB = ROOT / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"

API = "https://public-api.rustore.ru"
PACKAGE_FALLBACK = "ru.detapp.app"

MODERATION_STATUSES = {
    "TAKEN_FOR_MODERATION",
    "MODERATION",
    "AUTO_CHECK",
}
TERMINAL_OK = {"ACTIVE", "PARTIAL_ACTIVE", "READY_FOR_PUBLICATION"}
TERMINAL_FAIL = {
    "REJECTED_BY_MODERATOR",
    "REJECTED_BY_SECURITY",
    "AUTO_CHECK_FAILED",
}
INTERMEDIATE = MODERATION_STATUSES | {"DRAFT"}

SHORT_MAX = 80
FULL_MAX = 4000
WHATS_NEW_MAX = 5000
MODER_MAX = 180
SHOT_MAX_BYTES = 5 * 1024 * 1024
ICON_MAX_BYTES = 3 * 1024 * 1024
MAIN_CATEGORIES = {
    "business",
    "state",
    "foodAndDrink",
    "health",
    "books",
    "news",
    "lifestyle",
    "education",
    "social",
    "adsAndServices",
    "pets",
    "purchases",
    "tools",
    "travelling",
    "entertainment",
    "parenting",
    "sport",
    "gambling",
    "transport",
    "finance",
}


class Fail(SystemExit):
    def __init__(self, msg: str):
        super().__init__(f"ERROR: {msg}")


def _out(msg: str) -> None:
    print(msg, flush=True)


def _png_size(path: Path) -> tuple[int, int] | None:
    try:
        data = path.read_bytes()[:24]
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        w = int.from_bytes(data[16:20], "big")
        h = int.from_bytes(data[20:24], "big")
        return w, h
    except Exception:
        return None


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise Fail(f"нет файла {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_pubspec() -> tuple[str, int]:
    text = PUBSPEC.read_text(encoding="utf-8")
    m = re.search(r"^version:\s*([0-9.]+)\+(\d+)\s*$", text, re.M)
    if not m:
        raise Fail("pubspec.yaml: не разобрал version: x.y.z+build")
    return m.group(1), int(m.group(2))


def parse_patch_notes() -> list[tuple[int, str, list[str]]]:
    text = PATCH_NOTES.read_text(encoding="utf-8")
    out: list[tuple[int, str, list[str]]] = []
    for m in re.finditer(
        r"PatchRelease\(\s*build:\s*(\d+),\s*version:\s*'([^']+)',\s*items:\s*\[(.*?)\]",
        text,
        re.S,
    ):
        items = [s.replace(r"\'", "'") for s in re.findall(r"'((?:\\'|[^'])*)'", m.group(3))]
        out.append((int(m.group(1)), m.group(2), items))
    if not out:
        raise Fail("lib/patch_notes.dart: не нашёл PatchRelease")
    return out


def collect_whats_new(last_store_build: int, current: int) -> str:
    notes = parse_patch_notes()
    by_build = {b: items for b, _v, items in notes}
    if current not in by_build:
        raise Fail(f"в patch_notes.dart нет записи для build {current}")
    start = last_store_build if last_store_build > 0 else current - 1
    picked: list[str] = []
    for b, _v, items in sorted(notes, key=lambda x: x[0]):
        if start < b <= current:
            picked.extend(items)
    if not picked:
        picked = by_build[current]
    text = "\n".join(f"• {i}" for i in picked)
    if len(text) > WHATS_NEW_MAX:
        text = text[: WHATS_NEW_MAX - 1] + "…"
    return text


def manifest_permissions() -> list[str]:
    text = MANIFEST.read_text(encoding="utf-8")
    perms: set[str] = set()
    for m in re.finditer(r"<uses-permission\b([^>]*)/?>", text):
        block = m.group(1)
        if 'tools:node="remove"' in block:
            continue
        name = re.search(r'android:name="([^"]+)"', block)
        if name:
            perms.add(name.group(1))
    return sorted(perms)


def load_perm_lock() -> list[str]:
    if not PERM_LOCK.exists():
        raise Fail(f"нет {PERM_LOCK}")
    return sorted(
        line.strip()
        for line in PERM_LOCK.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    )


def keystore_ok() -> tuple[bool, str]:
    if not KEY_PROPS.exists():
        return False, f"нет {KEY_PROPS} — release подпишется debug-ключом"
    props: dict[str, str] = {}
    for line in KEY_PROPS.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            props[k.strip()] = v.strip()
    store = props.get("storeFile", "")
    if not store:
        return False, "key.properties без storeFile"
    candidates = [
        ROOT / "android" / store,
        ROOT / "android" / "app" / store,
        Path(store),
    ]
    for p in candidates:
        if p.is_file():
            return True, str(p)
    return False, f"keystore не найден: {store}"


def load_key() -> dict[str, str]:
    data: dict[str, str] = {}
    if KEY_PATH.exists():
        raw = load_json(KEY_PATH)
        data = {str(k): str(v) if v is not None else "" for k, v in raw.items()}
    data["key_id"] = os.environ.get("RUSTORE_KEY_ID", data.get("key_id", "")).strip()
    data["private_key"] = os.environ.get(
        "RUSTORE_PRIVATE_KEY", data.get("private_key", "")
    ).strip()
    data["telegram_bot_token"] = os.environ.get(
        "TELEGRAM_BOT_TOKEN", data.get("telegram_bot_token", "")
    ).strip()
    data["telegram_chat_id"] = os.environ.get(
        "TELEGRAM_CHAT_ID", data.get("telegram_chat_id", "")
    ).strip()
    return data


def sign_auth(key_id: str, private_key_b64: str) -> dict[str, str]:
    ts = datetime.now().astimezone().isoformat(timespec="milliseconds")
    message = (key_id + ts).encode("utf-8")
    raw = private_key_b64.strip()
    if "BEGIN" in raw:
        pem = raw.encode("ascii")
        der = None
    else:
        pem = (
            b"-----BEGIN PRIVATE KEY-----\n"
            + raw.encode("ascii")
            + b"\n-----END PRIVATE KEY-----\n"
        )
        try:
            der = base64.b64decode(raw)
        except Exception:
            der = None
    sig = _rsa_sha512_sign(message, pem, der)
    return {"keyId": key_id, "timestamp": ts, "signature": sig}


def _rsa_sha512_sign(message: bytes, pem: bytes, der: bytes | None) -> str:
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding

        key = serialization.load_pem_private_key(pem, password=None)
        signed = key.sign(message, padding.PKCS1v15(), hashes.SHA512())
        return base64.b64encode(signed).decode("ascii")
    except ImportError:
        pass
    except Exception as e:
        _out(f"cryptography sign failed: {e}")
    try:
        from Crypto.Hash import SHA512
        from Crypto.PublicKey import RSA
        from Crypto.Signature import pkcs1_15

        key = RSA.import_key(pem if der is None else der)
        signed = pkcs1_15.new(key).sign(SHA512.new(message))
        return base64.b64encode(signed).decode("ascii")
    except ImportError:
        pass
    except Exception as e:
        _out(f"pycryptodome sign failed: {e}")
    return _openssl_sign(message, pem)


def _openssl_sign(message: bytes, pem: bytes) -> str:
    import subprocess
    import tempfile

    openssl = _which("openssl")
    if not openssl:
        raise Fail(
            "нет cryptography / pycryptodome / openssl — "
            "pip install cryptography"
        )
    with tempfile.TemporaryDirectory() as tmp:
        key_path = Path(tmp) / "key.pem"
        msg_path = Path(tmp) / "msg.bin"
        sig_path = Path(tmp) / "sig.bin"
        key_path.write_bytes(pem)
        msg_path.write_bytes(message)
        r = subprocess.run(
            [openssl, "dgst", "-sha512", "-sign", str(key_path), "-out", str(sig_path), str(msg_path)],
            capture_output=True,
        )
        if r.returncode != 0:
            raise Fail(f"openssl sign: {r.stderr.decode('utf-8', 'replace')}")
        return base64.b64encode(sig_path.read_bytes()).decode("ascii")


def _which(name: str) -> str | None:
    from shutil import which

    return which(name)


class RuStore:
    def __init__(self, key_id: str, private_key: str):
        self.key_id = key_id
        self.private_key = private_key
        self._pkg = PACKAGE_FALLBACK
        self._jwe: str | None = None
        self._jwe_until = 0.0

    def token(self) -> str:
        if self._jwe and time.time() < self._jwe_until:
            return self._jwe
        body = sign_auth(self.key_id, self.private_key)
        data = self._request("POST", "/public/auth/", body, auth=False, timeout=30)
        jwe = (data.get("body") or {}).get("jwe")
        ttl = int((data.get("body") or {}).get("ttl") or 900)
        if not jwe:
            raise Fail(f"auth без jwe: {data}")
        self._jwe = jwe
        self._jwe_until = time.time() + max(60, ttl - 60)
        return jwe

    def _request(
        self,
        method: str,
        path: str,
        body: Any | None = None,
        *,
        auth: bool = True,
        timeout: int = 60,
        files: dict[str, Path] | None = None,
        query: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        url = API + path
        if query:
            url += "?" + urlencode(query, doseq=True)
        headers: dict[str, str] = {}
        data: bytes | None = None
        if files:
            data, ctype = _multipart({}, files)
            headers["Content-Type"] = ctype
        elif body is not None:
            data = json.dumps(body, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if auth:
            headers["Public-Token"] = self.token()
        req = Request(url, data=data, headers=headers, method=method)
        try:
            with urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
        except HTTPError as e:
            err = e.read().decode("utf-8", "replace")
            if e.code == 401 and auth:
                self._jwe = None
                headers["Public-Token"] = self.token()
                req = Request(url, data=data, headers=headers, method=method)
                try:
                    with urlopen(req, timeout=timeout) as resp:
                        raw = resp.read()
                except HTTPError as e2:
                    raise Fail(f"HTTP {e2.code} {path}: {e2.read().decode('utf-8', 'replace')}") from e2
            else:
                raise Fail(f"HTTP {e.code} {path}: {err}") from e
        except URLError as e:
            raise Fail(f"сеть {path}: {e}") from e
        if not raw:
            return {}
        try:
            parsed = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            raise Fail(f"не JSON от {path}: {raw[:200]!r}")
        code = parsed.get("code")
        if code and str(code).upper() not in ("OK", "SUCCESS"):
            raise Fail(f"{path}: {code} {parsed.get('message')}")
        return parsed

    def versions(self, statuses: str | None = None, size: int = 50) -> list[dict[str, Any]]:
        q: dict[str, Any] = {"page": 0, "size": size, "filterTestingType": "ALL"}
        if statuses:
            q["versionStatuses"] = statuses
        data = self._request("GET", f"/public/v1/application/{self.pkg}/version", query=q)
        body = data.get("body") or {}
        return list(body.get("content") or [])

    def create_draft(self, payload: dict[str, Any]) -> int:
        data = self._request(
            "POST",
            f"/public/v1/application/{self.pkg}/version",
            payload,
            timeout=60,
        )
        body = data.get("body")
        if isinstance(body, int):
            return body
        if isinstance(body, dict) and body.get("versionId"):
            return int(body["versionId"])
        raise Fail(f"create draft: нет versionId в {data}")

    def delete_draft(self, version_id: int) -> None:
        self._request(
            "DELETE",
            f"/public/v1/application/{self.pkg}/version/{version_id}",
        )

    def upload_aab(self, version_id: int, aab: Path) -> None:
        self._request(
            "POST",
            f"/public/v1/application/{self.pkg}/version/{version_id}/aab",
            files={"file": aab},
            timeout=600,
        )

    def upload_icon(self, version_id: int, icon: Path) -> None:
        self._request(
            "POST",
            f"/public/v1/application/{self.pkg}/version/{version_id}/image/icon",
            files={"file": icon},
            timeout=120,
        )

    def list_screenshots(self, version_id: int) -> list[dict[str, Any]]:
        data = self._request(
            "GET",
            f"/public/v2/application/{self.pkg}/version/{version_id}/image/screenshot",
            query={"size": 20, "page": 0},
        )
        body = data.get("body") or {}
        return list(body.get("content") or [])

    def upload_screenshot(self, version_id: int, ordinal: int, path: Path) -> None:
        self._request(
            "POST",
            f"/public/v2/application/{self.pkg}/version/{version_id}"
            f"/image/screenshot/PORTRAIT/{ordinal}/SCREENSHOT",
            files={"file": path},
            timeout=120,
        )

    def commit(self, version_id: int, priority: int) -> None:
        self._request(
            "POST",
            f"/public/v1/application/{self.pkg}/version/{version_id}/commit",
            query={"priorityUpdate": max(0, min(5, priority))},
        )

    @property
    def pkg(self) -> str:
        return self._pkg

    @pkg.setter
    def pkg(self, value: str) -> None:
        self._pkg = value


def _multipart(fields: dict[str, str], files: dict[str, Path]) -> tuple[bytes, str]:
    boundary = "----DetAppRuStore" + uuid.uuid4().hex
    chunks: list[bytes] = []
    for name, value in fields.items():
        chunks.append(f"--{boundary}\r\n".encode())
        chunks.append(
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        )
        chunks.append(value.encode("utf-8"))
        chunks.append(b"\r\n")
    for name, path in files.items():
        filename = path.name
        ext = path.suffix.lower()
        mime = {
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".aab": "application/octet-stream",
        }.get(ext, "application/octet-stream")
        chunks.append(f"--{boundary}\r\n".encode())
        chunks.append(
            f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'.encode()
        )
        chunks.append(f"Content-Type: {mime}\r\n\r\n".encode())
        chunks.append(path.read_bytes())
        chunks.append(b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def notify_telegram(key: dict[str, str], text: str) -> None:
    token = key.get("telegram_bot_token") or ""
    chat = key.get("telegram_chat_id") or ""
    if not token or not chat:
        _out("telegram: пропуск (нет telegram_bot_token / telegram_chat_id)")
        return
    payload = json.dumps(
        {"chat_id": chat, "text": text, "disable_web_page_preview": True},
        ensure_ascii=False,
    ).encode("utf-8")
    req = Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(req, timeout=20) as resp:
            raw = json.loads(resp.read().decode("utf-8"))
        if not raw.get("ok"):
            _out(f"telegram: {raw}")
        else:
            _out("telegram: ok")
    except Exception as e:
        _out(f"telegram: {e}")


def draft_payload(listing: dict[str, Any], whats_new: str, publish_type: str) -> dict[str, Any]:
    contacts = listing.get("developer_contacts") or {}
    payload: dict[str, Any] = {
        "appName": listing["app_name"],
        "appType": listing.get("app_type") or "MAIN",
        "categories": listing.get("categories") or ["tools"],
        "ageLegal": listing.get("age_legal") or "0+",
        "shortDescription": listing["short_description"],
        "fullDescription": listing["full_description"],
        "whatsNew": whats_new,
        "publishType": publish_type,
    }
    moder = (listing.get("moder_info") or "").strip()
    if moder:
        payload["moderInfo"] = moder
    if contacts:
        payload["developerContacts"] = contacts
    return payload


def local_preflight(
    listing: dict[str, Any],
    version: str,
    build: int,
    last_store: int,
    aab: Path | None,
    require_aab: bool,
) -> str:
    errors: list[str] = []
    short = listing["short_description"]
    full = listing["full_description"]
    moder = listing.get("moder_info") or ""
    if len(short) > SHORT_MAX:
        errors.append(f"short_description {len(short)} > {SHORT_MAX}")
    if len(full) > FULL_MAX:
        errors.append(f"full_description {len(full)} > {FULL_MAX}")
    if len(moder) > MODER_MAX:
        errors.append(f"moder_info {len(moder)} > {MODER_MAX}")
    cats = listing.get("categories") or []
    if not cats or len(cats) > 2:
        errors.append("categories: нужно 1–2 категории")
    for c in cats:
        if c not in MAIN_CATEGORIES:
            errors.append(f"неизвестная категория {c!r}")
    try:
        whats = collect_whats_new(last_store, build)
    except Fail as e:
        errors.append(str(e))
        whats = ""
    if whats and len(whats) > WHATS_NEW_MAX:
        errors.append(f"whatsNew {len(whats)} > {WHATS_NEW_MAX}")

    have, ks_msg = keystore_ok()
    if not have:
        errors.append(ks_msg)

    locked = load_perm_lock()
    current = manifest_permissions()
    extra = [p for p in current if p not in locked]
    missing = [p for p in locked if p not in current]
    if extra:
        errors.append(
            "новые permissions (API RuStore потребует декларацию в консоли): "
            + ", ".join(extra)
        )
    if missing:
        errors.append("permissions пропали из манифеста: " + ", ".join(missing))
    man_text = MANIFEST.read_text(encoding="utf-8")
    if "REQUEST_INSTALL_PACKAGES" in man_text and 'tools:node="remove"' not in man_text:
        errors.append("REQUEST_INSTALL_PACKAGES снова в манифесте")

    icon = SCREENS_DIR / listing.get("icon", "app_icon_512.png")
    if not icon.is_file():
        errors.append(f"нет иконки {icon}")
    elif icon.stat().st_size > ICON_MAX_BYTES:
        errors.append(f"иконка > 3 МБ: {icon}")
    else:
        wh = _png_size(icon)
        if wh and wh != (512, 512):
            errors.append(f"иконка {wh[0]}×{wh[1]}, нужно 512×512")
    shots = listing.get("screenshots") or []
    if len(shots) < 2:
        errors.append("нужно минимум 2 скриншота")
    for name in shots:
        p = SCREENS_DIR / name
        if not p.is_file():
            errors.append(f"нет скрина {p}")
            continue
        if p.stat().st_size > SHOT_MAX_BYTES:
            errors.append(f"скрин > 5 МБ: {p}")
        if p.suffix.lower() not in (".png", ".jpg", ".jpeg"):
            errors.append(f"скрин не png/jpg: {p}")

    if require_aab:
        if aab is None or not aab.is_file():
            errors.append(f"нет AAB: {aab}")
        elif aab.stat().st_size < 100_000:
            errors.append(f"AAB слишком маленький: {aab}")

    if errors:
        raise Fail("префлайт:\n  - " + "\n  - ".join(errors))
    return whats


def print_card(listing: dict[str, Any], version: str, build: int, whats: str) -> None:
    _out("=== карточка RuStore ===")
    _out(f"package:     {listing.get('package_name', PACKAGE_FALLBACK)}")
    _out(f"version:     {version}+{build}")
    _out(f"name:        {listing['app_name']}")
    _out(f"categories:  {listing.get('categories')}")
    _out(f"age:         {listing.get('age_legal')}")
    _out(f"short ({len(listing['short_description'])}): {listing['short_description']}")
    _out(f"full ({len(listing['full_description'])} chars)")
    _out(f"moder ({len(listing.get('moder_info') or '')}): {listing.get('moder_info')}")
    _out("whatsNew:")
    _out(whats)
    _out(f"icon:        {listing.get('icon')}")
    _out("screens:     " + ", ".join(listing.get("screenshots") or []))


def pick_latest(versions: list[dict[str, Any]], statuses: set[str]) -> dict[str, Any] | None:
    hits = [v for v in versions if v.get("versionStatus") in statuses]
    if not hits:
        return None
    return max(hits, key=lambda v: int(v.get("versionCode") or 0))


def cmd_status(api: RuStore, key: dict[str, str], notify: bool) -> int:
    vers = api.versions()
    if not vers:
        _out("версий нет")
        return 0
    for v in vers:
        _out(
            f"{v.get('versionStatus'):<24} "
            f"code={v.get('versionCode')} name={v.get('versionName')} "
            f"id={v.get('versionId')}"
        )
    if notify:
        top = vers[0]
        notify_telegram(
            key,
            f"RuStore {api.pkg}: {top.get('versionStatus')} "
            f"{top.get('versionName')}+{top.get('versionCode')}",
        )
    return 0


def cmd_watch(api: RuStore, key: dict[str, str], version_id: int | None, interval: int) -> int:
    last = ""
    _out(f"watch каждые {interval}с, Ctrl+C чтобы выйти")
    while True:
        vers = api.versions()
        target = None
        if version_id:
            target = next((v for v in vers if int(v.get("versionId") or 0) == version_id), None)
        if target is None:
            target = pick_latest(vers, MODERATION_STATUSES | TERMINAL_OK | TERMINAL_FAIL | {"DRAFT"})
        if target is None:
            _out("нет версий")
            return 1
        status = str(target.get("versionStatus") or "")
        line = (
            f"{status}  {target.get('versionName')}+{target.get('versionCode')}  "
            f"id={target.get('versionId')}"
        )
        if status != last:
            _out(line)
            if status in TERMINAL_OK or status in TERMINAL_FAIL:
                notify_telegram(
                    key,
                    f"RuStore {target.get('versionName')}+{target.get('versionCode')}: {status}",
                )
                return 0 if status in TERMINAL_OK else 2
            last = status
        time.sleep(interval)


def cmd_ship(args: argparse.Namespace) -> int:
    listing = load_json(LISTING_PATH)
    state = load_json(STATE_PATH) if STATE_PATH.exists() else {"last_store_build": 0, "pending": None}
    version, build = parse_pubspec()
    last_store = int(state.get("last_store_build") or 0)
    package = listing.get("package_name") or PACKAGE_FALLBACK
    aab = Path(args.aab) if args.aab else DEFAULT_AAB
    key = load_key()

    watch_only = args.watch and not args.resume and not args.fresh and not args.aab
    if args.status or watch_only:
        if not key.get("key_id") or not key.get("private_key"):
            raise Fail(
                "нет ключа API. Скопируйте tools/rustore_key.example.json → "
                "tools/rustore_key.json"
            )
        api = RuStore(key["key_id"], key["private_key"])
        api.pkg = package
        if args.status:
            return cmd_status(api, key, notify=False)
        pending = state.get("pending") or {}
        vid = args.version_id or pending.get("version_id")
        return cmd_watch(api, key, int(vid) if vid else None, args.interval)

    require_aab = not args.dry_run
    whats = local_preflight(listing, version, build, last_store, aab, require_aab)
    print_card(listing, version, build, whats)
    _out(f"last_store_build: {last_store}")
    have_ks, ks_msg = keystore_ok()
    _out(f"keystore: {ks_msg}" if have_ks else f"keystore FAIL: {ks_msg}")

    if args.dry_run:
        if key.get("key_id") and key.get("private_key"):
            try:
                api = RuStore(key["key_id"], key["private_key"])
                api.pkg = package
                vers = api.versions()
                active = pick_latest(vers, {"ACTIVE", "PARTIAL_ACTIVE"})
                draft = pick_latest(vers, {"DRAFT"})
                moder = pick_latest(vers, MODERATION_STATUSES)
                if active:
                    _out(
                        f"active: {active.get('versionName')}+{active.get('versionCode')} "
                        f"id={active.get('versionId')}"
                    )
                    if int(active.get("versionCode") or 0) >= build:
                        _out(
                            f"WARN: store versionCode {active.get('versionCode')} >= {build} — "
                            "бампните pubspec перед реальной отправкой"
                        )
                if draft:
                    _out(f"draft: id={draft.get('versionId')} code={draft.get('versionCode')}")
                if moder:
                    _out(
                        f"на модерации: {moder.get('versionStatus')} "
                        f"id={moder.get('versionId')}"
                    )
            except Fail as e:
                _out(f"remote dry-run: {e}")
        else:
            _out("remote: пропуск (скопируйте tools/rustore_key.example.json → rustore_key.json)")
        _out("dry-run ok, в магазин ничего не ушло")
        return 0

    if not key.get("key_id") or not key.get("private_key"):
        raise Fail(
            "нет ключа API. Скопируйте tools/rustore_key.example.json → "
            "tools/rustore_key.json и заполните key_id / private_key"
        )

    api = RuStore(key["key_id"], key["private_key"])
    api.pkg = package

    vers = api.versions()
    active = pick_latest(vers, {"ACTIVE", "PARTIAL_ACTIVE"})
    draft = pick_latest(vers, {"DRAFT"})
    moder = pick_latest(vers, MODERATION_STATUSES)
    if moder and not args.resume:
        raise Fail(
            f"предыдущая версия ещё на модерации: {moder.get('versionStatus')} "
            f"id={moder.get('versionId')} code={moder.get('versionCode')}. "
            "Дождитесь результата или tools\\ship_store.ps1 -Status"
        )
    if active:
        active_code = int(active.get("versionCode") or 0)
        _out(f"active versionCode={active_code}")
        if active_code >= build:
            raise Fail(
                f"versionCode {build} не выше активного {active_code}. "
                "Бампните version в pubspec.yaml"
            )

    pending = state.get("pending") if isinstance(state.get("pending"), dict) else None
    version_id: int | None = None
    done: list[str] = []

    if args.fresh and draft:
        _out(f"удаляю черновик {draft.get('versionId')}")
        api.delete_draft(int(draft["versionId"]))
        draft = None
        pending = None
    elif args.resume:
        if pending and pending.get("version_id"):
            version_id = int(pending["version_id"])
            done = list(pending.get("done") or [])
            _out(f"resume version_id={version_id} done={done}")
        elif draft:
            version_id = int(draft["versionId"])
            _out(f"resume существующего черновика {version_id}")
        else:
            raise Fail("нечего продолжать: нет pending и нет DRAFT")
    elif draft:
        raise Fail(
            f"уже есть черновик id={draft.get('versionId')}. "
            "Запустите с -Resume или -Fresh"
        )

    publish_type = "MANUAL" if args.manual else "INSTANTLY"
    payload = draft_payload(listing, whats, publish_type)

    if version_id is None:
        _out("создаю черновик…")
        version_id = api.create_draft(payload)
        done = ["draft"]
        _out(f"draft versionId={version_id}")
        _save_pending(state, version_id, build, version, done, whats)
    elif "draft" not in done:
        done.append("draft")
        _save_pending(state, version_id, build, version, done, whats)

    if "aab" not in done:
        _out(f"загружаю AAB {aab} ({aab.stat().st_size // 1024} KB)…")
        api.upload_aab(version_id, aab)
        done.append("aab")
        _save_pending(state, version_id, build, version, done, whats)
        _out("AAB ok")

    icon = SCREENS_DIR / listing.get("icon", "app_icon_512.png")
    if "icon" not in done:
        _out(f"иконка {icon.name}…")
        api.upload_icon(version_id, icon)
        done.append("icon")
        _save_pending(state, version_id, build, version, done, whats)

    if "screenshots" not in done:
        existing = {int(s.get("ordinal") or -1) for s in api.list_screenshots(version_id)}
        shots = listing.get("screenshots") or []
        for i, name in enumerate(shots):
            if i in existing:
                _out(f"скрин {i} уже есть, пропускаю")
                continue
            path = SCREENS_DIR / name
            _out(f"скрин {i}: {name}")
            api.upload_screenshot(version_id, i, path)
        done.append("screenshots")
        _save_pending(state, version_id, build, version, done, whats)

    if "commit" not in done:
        _out("отправляю на модерацию…")
        api.commit(version_id, args.priority)
        done.append("commit")
        state["last_store_build"] = build
        state["pending"] = None
        save_json(STATE_PATH, state)
        _out(f"на модерации: {version}+{build} id={version_id} publishType={publish_type}")
        notify_telegram(
            key,
            f"RuStore: {version}+{build} отправлен на модерацию "
            f"(id={version_id}, {publish_type})",
        )

    if args.watch:
        return cmd_watch(api, key, version_id, args.interval)
    return 0


def _save_pending(
    state: dict[str, Any],
    version_id: int,
    build: int,
    version: str,
    done: list[str],
    whats: str,
) -> None:
    state["pending"] = {
        "version_id": version_id,
        "build": build,
        "version": version,
        "done": done,
        "whats_new": whats,
    }
    save_json(STATE_PATH, state)


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    p = argparse.ArgumentParser(description="RuStore publish")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--status", action="store_true")
    p.add_argument("--watch", action="store_true")
    p.add_argument("--resume", action="store_true")
    p.add_argument("--fresh", action="store_true")
    p.add_argument("--manual", action="store_true", help="publishType=MANUAL")
    p.add_argument("--priority", type=int, default=0)
    p.add_argument("--aab", default="")
    p.add_argument("--version-id", type=int, default=0)
    p.add_argument("--interval", type=int, default=90)
    args = p.parse_args()
    try:
        return cmd_ship(args)
    except Fail as e:
        _out(str(e))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
