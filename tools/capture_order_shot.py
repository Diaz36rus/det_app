import re
import pathlib
import subprocess
import time
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SDK = r"D:\Android\Sdk"
ADB = fr"{SDK}\platform-tools\adb.exe"
DIR = pathlib.Path(r"D:\Projects\det_app\tools\rustore_screens")

# Fixed menu centers from a known-good dump (Pixel 7 1080x2400)
MENU = {
    "board": (420, 600),
    "orders": (420, 845),
    "clients": (420, 990),
    "services": (420, 1131),
    "inventory": (420, 1272),
    "calendar": (420, 1414),
    "done": (420, 1580),
    "cash": (420, 1981),
}


def adb(*args):
    return subprocess.run([ADB, *args], capture_output=True)


def tap(x, y, wait=0.9):
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(wait)


def back(wait=0.8):
    adb("shell", "input", "keyevent", "4")
    time.sleep(wait)


def pull_screen(name):
    remote = f"/sdcard/{name}"
    adb("shell", "screencap", "-p", remote)
    adb("pull", remote, str(DIR / name))
    size = (DIR / name).stat().st_size
    print(f"OK {name} ({size})")
    return size


def dump_ui():
    adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    adb("pull", "/sdcard/ui.xml", str(DIR / "ui.xml"))
    return (DIR / "ui.xml").read_text(encoding="utf-8", errors="replace")


def nodes(xml):
    out = []
    for m in re.finditer(r"<node\b[^>]*>", xml):
        tag = m.group(0)
        d = re.search(r'content-desc="([^"]*)"', tag)
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
        c = re.search(r'clickable="(true|false)"', tag)
        if not b:
            continue
        x1, y1, x2, y2 = map(int, b.groups())
        out.append(
            {
                "desc": d.group(1) if d else "",
                "clickable": (c.group(1) == "true") if c else False,
                "x": (x1 + x2) // 2,
                "y": (y1 + y2) // 2,
                "bounds": (x1, y1, x2, y2),
            }
        )
    return out


def open_menu_item(key):
    tap(74, 210, 0.8)
    x, y = MENU[key]
    tap(x, y, 1.5)


def main():
    adb("shell", "am", "start", "-n", "ru.detapp.app/.MainActivity")
    time.sleep(2)

    open_menu_item("board")
    xml = dump_ui()
    card = None
    brands = ("Camry", "Sportage", "Octavia", "BMW", "Toyota", "Mercedes", "Hyundai", "Kia", "X5")
    for n in nodes(xml):
        if not n["clickable"]:
            continue
        d = n["desc"]
        if not any(k in d for k in brands):
            continue
        x1, y1, x2, y2 = n["bounds"]
        if (x2 - x1) > 250 and (y2 - y1) > 250:
            card = n
            break

    if card:
        print("card bounds", card["bounds"], "keys", [k for k in brands if k in card["desc"]])
        tap(card["x"], card["y"], 4.0)
    else:
        print("no card found, fallback tap")
        for n in nodes(xml):
            if n["desc"] and n["clickable"]:
                print("node", n["bounds"], repr(n["desc"][:60]))
        tap(477, 1281, 4.0)

    size = pull_screen("02_order.png")
    if size < 80000:
        print("order shot too small, wait and retry")
        time.sleep(3)
        pull_screen("02_order.png")

    # scroll a bit on cash for showcase flows
    open_menu_item("cash")
    time.sleep(1)
    adb("shell", "input", "swipe", "540", "1800", "540", "900", "400")
    time.sleep(1)
    pull_screen("04_cash.png")

    print("done")


if __name__ == "__main__":
    main()
