from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from fastapi import APIRouter, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse

from app.config import settings

router = APIRouter(prefix="/updates", tags=["updates"])

_SAFE_NAME = re.compile(r"^[\w.\-+]+$")


def _releases_root() -> Path:
    root = Path(settings.releases_dir)
    root.mkdir(parents=True, exist_ok=True)
    (root / "packs").mkdir(parents=True, exist_ok=True)
    return root


def _public_base() -> str:
    return settings.public_base_url.rstrip("/")


def _require_token(token: str | None) -> None:
    expected = (settings.release_upload_token or "").strip()
    if not expected:
        raise HTTPException(status_code=503, detail="RELEASE_UPLOAD_TOKEN не задан на сервере")
    if not token or token.strip() != expected:
        raise HTTPException(status_code=401, detail="Неверный токен выгрузки")


@router.get("/latest.json")
def latest_manifest():
    path = _releases_root() / "latest.json"
    if not path.exists():
        raise HTTPException(status_code=404, detail="Релизов ещё нет. Загрузите первый билд.")
    data = json.loads(path.read_text(encoding="utf-8"))
    return JSONResponse(data)


@router.get("/packs/{filename}")
def download_pack(filename: str):
    if not _SAFE_NAME.match(filename) or ".." in filename:
        raise HTTPException(status_code=400, detail="Некорректное имя файла")
    path = _releases_root() / "packs" / filename
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Файл не найден")
    media = "application/vnd.android.package-archive" if filename.lower().endswith(".apk") else None
    if filename.lower().endswith(".zip"):
        media = "application/zip"
    return FileResponse(path, filename=filename, media_type=media)


@router.get("/android")
def latest_android_apk():
    """Постоянная ссылка/QR: всегда отдаёт актуальный APK из latest.json."""
    path = _releases_root() / "latest.json"
    if not path.exists():
        raise HTTPException(status_code=404, detail="Релизов ещё нет. Загрузите первый билд.")
    data = json.loads(path.read_text(encoding="utf-8"))
    android_url = (data.get("android_url") or "").strip()
    if not android_url:
        raise HTTPException(status_code=404, detail="APK ещё не загружен")
    name = Path(android_url).name
    local = _releases_root() / "packs" / name
    if local.is_file() and _SAFE_NAME.match(name):
        return FileResponse(
            local,
            filename=name,
            media_type="application/vnd.android.package-archive",
        )
    return RedirectResponse(android_url, status_code=302)


@router.post("/publish")
async def publish_release(
    x_release_token: str | None = Header(default=None, alias="X-Release-Token"),
    version: str = Form(...),
    build: int = Form(...),
    min_build: int = Form(1),
    notes: str = Form(""),
    db_version: int = Form(0),
    critical: bool = Form(False),
    windows_zip: UploadFile | None = File(default=None),
    android_apk: UploadFile | None = File(default=None),
    sha256: str = Form(""),
    size: int = Form(0),
    android_sha256: str = Form(""),
    android_size: int = Form(0),
):
    _require_token(x_release_token)
    if windows_zip is None and android_apk is None:
        raise HTTPException(status_code=400, detail="Нужен windows_zip и/или android_apk")

    notes_clean = (notes or "").strip()
    # Чинит типичный mojibake: UTF-8 «Сборка» прочитали как cp1251 → «РЎР±РѕСЂРєР°».
    if "РЎР±" in notes_clean or "РсР" in notes_clean:
        try:
            notes_clean = notes_clean.encode("cp1251").decode("utf-8")
        except Exception:
            pass

    root = _releases_root()
    packs = root / "packs"
    base = _public_base()
    manifest: dict = {
        "version": version.strip(),
        "build": int(build),
        "min_build": int(min_build),
        "notes": notes_clean,
        "db_version": int(db_version),
        "critical": bool(critical),
        "url": "",
        "sha256": "",
        "android_url": "",
        "android_sha256": "",
    }

    if windows_zip is not None:
        name = windows_zip.filename or f"DetApp-portable-{build}.zip"
        name = Path(name).name
        if not _SAFE_NAME.match(name):
            name = f"DetApp-portable-{build}.zip"
        dest = packs / name
        raw = await windows_zip.read()
        dest.write_bytes(raw)
        digest = sha256.strip().lower() or hashlib.sha256(raw).hexdigest()
        manifest["url"] = f"{base}/updates/packs/{name}"
        manifest["sha256"] = digest
        manifest["size"] = size if size > 0 else len(raw)

    if android_apk is not None:
        name = android_apk.filename or f"det_app-{build}.apk"
        name = Path(name).name
        if not _SAFE_NAME.match(name):
            name = f"det_app-{build}.apk"
        dest = packs / name
        raw = await android_apk.read()
        dest.write_bytes(raw)
        digest = android_sha256.strip().lower() or hashlib.sha256(raw).hexdigest()
        manifest["android_url"] = f"{base}/updates/packs/{name}"
        manifest["android_sha256"] = digest
        manifest["android_size"] = android_size if android_size > 0 else len(raw)

    # Сохраняем предыдущие URL, если грузили только одну платформу.
    prev_path = root / "latest.json"
    if prev_path.exists():
        try:
            prev = json.loads(prev_path.read_text(encoding="utf-8"))
            if not manifest["url"] and prev.get("url"):
                manifest["url"] = prev["url"]
                manifest["sha256"] = prev.get("sha256", "")
                if prev.get("size") is not None:
                    manifest["size"] = prev["size"]
            if not manifest["android_url"] and prev.get("android_url"):
                manifest["android_url"] = prev["android_url"]
                manifest["android_sha256"] = prev.get("android_sha256", "")
                if prev.get("android_size") is not None:
                    manifest["android_size"] = prev["android_size"]
        except Exception:
            pass

    (root / "latest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return {"ok": True, "manifest": manifest}
