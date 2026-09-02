import re
import pathlib
import subprocess
import time
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ADB = r"C:\Users\KDFX Modes\AppData\Local\Android\Sdk\platform-tools\adb.exe"
DIR = pathlib.Path(r"D:\Projects\det_app\tools\rustore_screens")


def adb(*args):
    return subprocess.run([ADB, *args], capture_output=True)


def tap(x, y, wait=0.9):
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(wait)


def swipe(x1, y1, x2, y2, ms=350, wait=0.6):
    adb("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(ms))
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
                "w": x2 - x1,
                "h": y2 - y1,
            }
        )
    return out


def open_menu():
    tap(74, 210, 0.7)


def tap_menu_label(label, max_swipes=4):
    """Find exact menu row by content-desc, swipe drawer if needed."""
    open_menu()
    for _ in range(max_swipes + 1):
        xml = dump_ui()
        # collapse workshops if expanded (Мойка under Цеха)
        workshops = [n for n in nodes(xml) if n["desc"] == "Цеха" and n["clickable"]]
        wash = [n for n in nodes(xml) if n["desc"] == "Мойка" and n["clickable"] and n["w"] > 400]
        if workshops and wash:
            print("collapse workshops")
            tap(workshops[0]["x"], workshops[0]["y"], 0.8)
            xml = dump_ui()

        hits = [n for n in nodes(xml) if n["desc"] == label and n["clickable"] and n["w"] > 400]
        if hits:
            # prefer lower-in-drawer main items (not tiny)
            hit = hits[0]
            print(f"tap menu {label} @ {hit['x']},{hit['y']}")
            tap(hit["x"], hit["y"], 1.6)
            return True

        # swipe drawer up to reveal lower items
        swipe(420, 1900, 420, 900, 400, 0.7)
    print(f"MISS menu {label}")
    return False


def tap_order_card():
    xml = dump_ui()
    brands = ("Camry", "Sportage", "Octavia", "BMW", "Toyota", "Mercedes", "Hyundai", "Kia", "X5")
    for n in nodes(xml):
        if not n["clickable"]:
            continue
        if not any(k in n["desc"] for k in brands):
            continue
        if n["w"] > 250 and n["h"] > 250:
            print("card", [k for k in brands if k in n["desc"]], n["bounds"])
            tap(n["x"], n["y"], 4.0)
            return True
    # maybe need horizontal swipe on board
    for _ in range(3):
        swipe(200, 1400, 900, 1400, 400, 0.5)
        xml = dump_ui()
        for n in nodes(xml):
            if not n["clickable"]:
                continue
            if not any(k in n["desc"] for k in brands):
                continue
            if n["w"] > 250 and n["h"] > 250:
                print("card after swipe", [k for k in brands if k in n["desc"]], n["bounds"])
                tap(n["x"], n["y"], 4.0)
                return True
    print("no card")
    return False


def main():
    adb("shell", "am", "start", "-n", "ru.detapp.app/.MainActivity")
    time.sleep(2)

    # 01 board (already good, refresh)
    tap_menu_label("Доска")
    time.sleep(0.5)
    pull_screen("01_board.png")

    # 02 order
    if tap_order_card():
        pull_screen("02_order.png")
        back()
    else:
        print("order failed")

    # 03 calendar
    tap_menu_label("Календарь")
    time.sleep(1)
    pull_screen("03_calendar.png")

    # 04 cash + scroll
    tap_menu_label("Касса")
    time.sleep(1)
    swipe(540, 1800, 540, 900, 400, 0.8)
    pull_screen("04_cash.png")

    # 05 clients
    tap_menu_label("Клиенты")
    time.sleep(1)
    pull_screen("05_clients.png")

    # 06 inventory
    tap_menu_label("Склад")
    time.sleep(1)
    pull_screen("06_inventory.png")

    for p in sorted(DIR.glob("0*.png")):
        print(p.name, p.stat().st_size)


if __name__ == "__main__":
    main()
