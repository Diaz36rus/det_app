# -*- coding: utf-8 -*-
"""Capture Det App (by process) + prepare website screen assets."""
from __future__ import annotations

import ctypes
import ctypes.wintypes as wt
import time
from pathlib import Path

from PIL import Image, ImageEnhance, ImageGrab

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools" / "_website_shots"
WEB = ROOT / "server" / "website" / "assets"
RUSTORE = ROOT / "tools" / "rustore_screens"

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32
user32.SetProcessDPIAware()

EnumWindows = user32.EnumWindows
EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)
GetWindowTextLengthW = user32.GetWindowTextLengthW
GetWindowTextW = user32.GetWindowTextW
IsWindowVisible = user32.IsWindowVisible
GetWindowRect = user32.GetWindowRect
GetWindowThreadProcessId = user32.GetWindowThreadProcessId
IsIconic = user32.IsIconic
ShowWindow = user32.ShowWindow
SetForegroundWindow = user32.SetForegroundWindow
BringWindowToTop = user32.BringWindowToTop
SetCursorPos = user32.SetCursorPos
mouse_event = user32.mouse_event
keybd_event = user32.keybd_event
OpenProcess = kernel32.OpenProcess
QueryFullProcessImageNameW = kernel32.QueryFullProcessImageNameW
CloseHandle = kernel32.CloseHandle

PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
SW_RESTORE = 9
SW_MAXIMIZE = 3
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
VK_ESCAPE = 0x1B
PAD = 8

# Content Y from calibrate_sidebar.png @ 2560×1400 capture (after PAD crop).
# Recalibrate if sidebar layout changes.
MENU_Y = {
    "board": 300,
    "orders": 345,
    "clients": 391,
    "services": 450,
    "inventory": 500,
    "calendar": 535,
    "completed": 583,
    "cash": 660,
    "stats": 731,
}
CLICK_X_CONTENT = 140  # middle of 268px sidebar labels


def process_exe(pid: int) -> str:
    h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not h:
        return ""
    try:
        buf = ctypes.create_unicode_buffer(512)
        size = wt.DWORD(512)
        if QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size)):
            return buf.value
    finally:
        CloseHandle(h)
    return ""


def find_hwnd() -> int:
    found: list[int] = []

    def cb(hwnd, _):
        if not IsWindowVisible(hwnd):
            return True
        n = GetWindowTextLengthW(hwnd)
        if n <= 0:
            return True
        pid = wt.DWORD()
        GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        exe = process_exe(pid.value)
        if exe.lower().endswith("det_app.exe"):
            found.append(hwnd)
        return True

    EnumWindows(EnumWindowsProc(cb), 0)
    if not found:
        raise SystemExit("det_app.exe window not found")
    print("hwnd", hex(found[0]))
    return found[0]


def focus(hwnd: int) -> None:
    if IsIconic(hwnd):
        ShowWindow(hwnd, SW_RESTORE)
        time.sleep(0.35)
    ShowWindow(hwnd, SW_MAXIMIZE)
    BringWindowToTop(hwnd)
    SetForegroundWindow(hwnd)
    time.sleep(0.35)


def press_escape(times: int = 3) -> None:
    for _ in range(times):
        keybd_event(VK_ESCAPE, 0, 0, 0)
        keybd_event(VK_ESCAPE, 0, 2, 0)
        time.sleep(0.18)


def window_box(hwnd: int) -> tuple[int, int, int, int]:
    rect = wt.RECT()
    GetWindowRect(hwnd, ctypes.byref(rect))
    return (
        rect.left + PAD,
        rect.top + PAD,
        rect.right - PAD,
        rect.bottom - PAD,
    )


def capture(hwnd: int) -> Image.Image:
    focus(hwnd)
    box = window_box(hwnd)
    return ImageGrab.grab(bbox=box, all_screens=True).convert("RGB")


def click_menu(hwnd: int, key: str) -> None:
    focus(hwnd)
    press_escape(2)
    time.sleep(0.2)
    left, top, _, _ = window_box(hwnd)
    x = left + CLICK_X_CONTENT
    y = top + MENU_Y[key]
    SetCursorPos(x, y)
    time.sleep(0.08)
    mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
    mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
    time.sleep(1.15)
    # Calendar expands a flyout on first click — click again on label if needed
    if key == "calendar":
        SetCursorPos(x, y)
        time.sleep(0.05)
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
        time.sleep(1.0)
    press_escape(1)
    time.sleep(0.25)


def save_jpg(im: Image.Image, path: Path, max_w: int = 1600, quality: int = 88) -> None:
    if im.width > max_w:
        ratio = max_w / im.width
        im = im.resize((max_w, int(im.height * ratio)), Image.Resampling.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() == ".png":
        im.save(path, "PNG", optimize=True)
    else:
        im.save(path, "JPEG", quality=quality, optimize=True)
    print("wrote", path.name, im.size)


def from_rustore(name: str, dest: Path, max_w: int = 720) -> None:
    src = RUSTORE / name
    if not src.exists():
        print("skip", name)
        return
    save_jpg(Image.open(src).convert("RGB"), dest, max_w=max_w, quality=90)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    hwnd = find_hwnd()
    focus(hwnd)
    press_escape(4)
    time.sleep(0.3)

    shots: dict[str, Image.Image] = {}
    for key in ("board", "calendar", "cash", "clients", "stats", "orders"):
        click_menu(hwnd, key)
        shots[key] = capture(hwnd)
        save_jpg(shots[key], OUT / f"desktop_{key}.png", max_w=2200)

    # Website desktop
    save_jpg(shots["board"], WEB / "ui-board.jpg", max_w=1600)
    save_jpg(shots["board"], WEB / "screen-board.jpg", max_w=1400)
    save_jpg(shots["calendar"], WEB / "ui-calendar.jpg", max_w=1600)
    save_jpg(shots["cash"], WEB / "ui-cash.jpg", max_w=1600)
    save_jpg(shots["clients"], WEB / "screen-clients.jpg", max_w=1600)
    save_jpg(shots["stats"], WEB / "screen-stats.jpg", max_w=1600)
    save_jpg(shots["orders"], WEB / "screen-orders.jpg", max_w=1600)

    # Mobile RuStore pack (paired)
    from_rustore("01_board.png", WEB / "ui-phone.jpg", max_w=720)
    from_rustore("02_order.png", WEB / "ui-order.jpg", max_w=900)
    from_rustore("03_calendar.png", WEB / "ui-phone-calendar.jpg", max_w=720)
    from_rustore("04_cash.png", WEB / "ui-phone-cash.jpg", max_w=720)
    from_rustore("05_clients.png", WEB / "ui-phone-clients.jpg", max_w=720)
    from_rustore("06_inventory.png", WEB / "ui-phone-inventory.jpg", max_w=720)

    hero = ImageEnhance.Brightness(shots["board"]).enhance(0.66)
    hero = ImageEnhance.Color(hero).enhance(0.9)
    save_jpg(hero, WEB / "hero.jpg", max_w=1800, quality=85)

    click_menu(hwnd, "board")
    print("done")


if __name__ == "__main__":
    main()
