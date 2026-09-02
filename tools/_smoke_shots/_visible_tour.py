# -*- coding: utf-8 -*-
"""Visible slow GUI tour of Det App — mouse moves on screen so user can watch."""
import ctypes
import ctypes.wintypes as wt
import struct
import time
from pathlib import Path

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
kernel32 = ctypes.windll.kernel32

OUT = Path(__file__).resolve().parent / "visible_tour"
OUT.mkdir(exist_ok=True)

SW_MAXIMIZE = 3
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
KEYEVENTF_KEYUP = 0x0002
VK_CONTROL = 0x11
VK_ESCAPE = 0x1B
VK_RETURN = 0x0D
VK_V = 0x56
SRCCOPY = 0x00CC0020


class RECT(ctypes.Structure):
    _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                ("right", ctypes.c_long), ("bottom", ctypes.c_long)]


class POINT(ctypes.Structure):
    _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", ctypes.c_uint32), ("biWidth", ctypes.c_long),
        ("biHeight", ctypes.c_long), ("biPlanes", ctypes.c_uint16),
        ("biBitCount", ctypes.c_uint16), ("biCompression", ctypes.c_uint32),
        ("biSizeImage", ctypes.c_uint32), ("biXPelsPerMeter", ctypes.c_long),
        ("biYPelsPerMeter", ctypes.c_long), ("biClrUsed", ctypes.c_uint32),
        ("biClrImportant", ctypes.c_uint32),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", ctypes.c_uint32 * 3)]


def find_hwnd():
    found = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)
    def enum_proc(hwnd, _):
        if not user32.IsWindowVisible(hwnd):
            return True
        buf = ctypes.create_unicode_buffer(256)
        user32.GetWindowTextW(hwnd, buf, 256)
        if buf.value == "Det App":
            found.append(hwnd)
        return True

    user32.EnumWindows(enum_proc, 0)
    return found[0] if found else None


def bring_front(hwnd):
    user32.ShowWindow(hwnd, SW_MAXIMIZE)
    user32.SetForegroundWindow(hwnd)
    time.sleep(0.6)


def rect(hwnd):
    r = RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(r))
    return r


def shot(hwnd, name):
    r = rect(hwnd)
    w, h = r.right - r.left, r.bottom - r.top
    hdc = user32.GetDC(0)
    mdc = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(mdc, bmp)
    gdi32.BitBlt(mdc, 0, 0, w, h, hdc, r.left, r.top, SRCCOPY)
    bmi = BITMAPINFO()
    bmi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bmi.bmiHeader.biWidth = w
    bmi.bmiHeader.biHeight = h  # bottom-up for correct BMP
    bmi.bmiHeader.biPlanes = 1
    bmi.bmiHeader.biBitCount = 24
    row = ((w * 3 + 3) & ~3)
    buf = ctypes.create_string_buffer(row * h)
    gdi32.GetDIBits(mdc, bmp, 0, h, buf, ctypes.byref(bmi), 0)
    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mdc)
    user32.ReleaseDC(0, hdc)
    path = OUT / f"{name}.bmp"
    bf = struct.pack("<2sIHHI", b"BM", 14 + 40 + row * h, 0, 0, 14 + 40)
    bi = struct.pack("<IIIHHIIIIII", 40, w, h, 1, 24, 0, row * h, 0, 0, 0, 0)
    path.write_bytes(bf + bi + buf.raw)
    # also png via pillow if available
    try:
        from PIL import Image
        Image.open(path).save(path.with_suffix(".png"))
    except Exception:
        pass
    print(f"  shot -> {path.name}", flush=True)
    return path


def move_smooth(x, y, steps=32, pause=0.014):
    cur = POINT()
    user32.GetCursorPos(ctypes.byref(cur))
    for i in range(1, steps + 1):
        nx = int(cur.x + (x - cur.x) * i / steps)
        ny = int(cur.y + (y - cur.y) * i / steps)
        user32.SetCursorPos(nx, ny)
        time.sleep(pause)


def click_xy(x, y, hold=0.1):
    move_smooth(x, y)
    time.sleep(0.2)
    user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
    time.sleep(hold)
    user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
    time.sleep(0.45)


def key(vk, down=True):
    user32.keybd_event(vk, 0, 0 if down else KEYEVENTF_KEYUP, 0)


def press(vk):
    key(vk, True)
    time.sleep(0.05)
    key(vk, False)
    time.sleep(0.12)


def paste_text(text):
    """Set clipboard via PowerShell then Ctrl+V (more reliable than raw GMEM)."""
    import subprocess
    # Use clip.exe via powershell Set-Clipboard
    subprocess.run(
        ["powershell", "-NoProfile", "-Command", f"Set-Clipboard -Value {repr(text)}"],
        check=True,
        capture_output=True,
    )
    time.sleep(0.15)
    key(VK_CONTROL, True)
    press(VK_V)
    key(VK_CONTROL, False)
    time.sleep(0.25)


def announce(msg):
    print(f"\n>>> {msg}", flush=True)


def main():
    hwnd = find_hwnd()
    if not hwnd:
        raise SystemExit("Det App window not found")
    bring_front(hwnd)
    r = rect(hwnd)
    L, T = r.left, r.top
    W, H = r.right - r.left, r.bottom - r.top
    print(f"window {W}x{H} at ({L},{T})", flush=True)

    # Client-area origin (maximized has ~8px overscan)
    ox, oy = L + 8, T + 8

    def click(cx, cy):
        """Click client-relative pixels."""
        click_xy(ox + cx, oy + cy)

    # Calibrated on 2576x1416 sidebar_crop (00_flipV)
    # Menu item centers (client Y):
    MENU_X = 110
    MENU = {
        "board": 318,
        "new": 368,
        "cal": 415,
        "clients": 462,
        "cash": 512,
        "stats": 562,
        "staff": 610,
        "price": 658,
        "wh": 705,
    }

    stamp = int(time.time()) % 100000
    phone = f"903{stamp:07d}"
    name = f"VizTour {stamp}"
    car = "Kia Rio"
    plate = f"V{stamp % 1000:03d}77"

    announce("Esc dialogs")
    for _ in range(3):
        press(VK_ESCAPE)
        time.sleep(0.35)
    shot(hwnd, "00_start")
    time.sleep(1.0)

    announce("Board")
    click(MENU_X, MENU["board"])
    time.sleep(1.4)
    shot(hwnd, "01_board")
    time.sleep(0.8)

    announce("New order")
    click(MENU_X, MENU["new"])
    time.sleep(2.0)
    shot(hwnd, "02_new_order")
    time.sleep(1.0)

    # Form fields calibrated from 02_new_order.png
    announce(f"Phone {phone}")
    click(520, 160)
    time.sleep(0.3)
    key(VK_CONTROL, True)
    press(ord("A"))
    key(VK_CONTROL, False)
    paste_text(phone)
    time.sleep(0.8)

    announce(f"Name {name}")
    click(1000, 160)
    time.sleep(0.3)
    paste_text(name)
    time.sleep(0.8)

    announce(f"Car {car}")
    click(520, 250)
    time.sleep(0.3)
    paste_text(car)
    time.sleep(0.8)

    announce(f"Plate {plate}")
    click(1000, 250)
    time.sleep(0.3)
    paste_text(plate)
    time.sleep(0.8)
    shot(hwnd, "03_filled")
    time.sleep(1.0)

    announce("Category Moyka")
    click(480, 650)
    time.sleep(2.2)
    shot(hwnd, "04_moyka")
    time.sleep(0.8)

    announce("Pick first service in dialog")
    click(900, 520)
    time.sleep(0.9)
    click(1100, 780)
    time.sleep(0.7)
    press(VK_RETURN)
    time.sleep(1.2)
    shot(hwnd, "05_cart")
    time.sleep(1.0)

    announce("Create order")
    click(1280, 1365)
    time.sleep(2.5)
    shot(hwnd, "06_after_create")
    time.sleep(1.0)

    announce("Board + search")
    click(MENU_X, MENU["board"])
    time.sleep(1.6)
    click(700, 70)  # search top bar
    time.sleep(0.3)
    paste_text(str(stamp))
    time.sleep(0.3)
    press(VK_RETURN)
    time.sleep(1.5)
    shot(hwnd, "07_board_search")
    time.sleep(1.0)

    announce("Cash")
    click(MENU_X, MENU["cash"])
    time.sleep(1.8)
    shot(hwnd, "08_cash")
    time.sleep(1.0)

    announce("Stats")
    click(MENU_X, MENU["stats"])
    time.sleep(1.8)
    shot(hwnd, "09_stats")
    time.sleep(1.0)

    announce("Clients")
    click(MENU_X, MENU["clients"])
    time.sleep(1.8)
    shot(hwnd, "10_clients")
    time.sleep(0.8)

    announce("Back to board")
    click(MENU_X, MENU["board"])
    time.sleep(1.5)
    shot(hwnd, "11_done")

    announce("DONE — watch Det App window")
    (OUT / "result.txt").write_text(
        f"phone={phone}\nname={name}\ncar={car}\nplate={plate}\n",
        encoding="utf-8",
    )
    print(f"result: phone={phone} name={name} shots={OUT}", flush=True)


if __name__ == "__main__":
    main()
