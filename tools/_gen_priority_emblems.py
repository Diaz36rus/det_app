# -*- coding: utf-8 -*-
"""Clean mono emblems (24x24) for priority RU/CN brands — SI-style, colorFilter-safe."""
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "assets" / "brands"

# Accurate-enough brand emblems as single-color paths (not official trademark files).
EMBLEMS = {
    # Lexus — L in oval
    "lexus": (
        "M12 2.8c-5.8 0-10 2.9-10 9.2s4.2 9.2 10 9.2 10-2.9 10-9.2-4.2-9.2-10-9.2zm0 1.7c4.7 0 "
        "8.2 2.2 8.2 7.5S16.7 19.5 12 19.5 3.8 17.3 3.8 12 7.3 4.5 12 4.5zm-3.1 3.2h1.9v7.1h5.4v1.7H8.9V7.7z"
    ),
    # Genesis — twin wings
    "genesis": (
        "M12 4.2 3.2 8.1v1.8l7.6 3.3V20h2.4v-6.8l7.6-3.3V8.1L12 4.2zm0 2.3 5.5 2.4-5.5 2.4-5.5-2.4L12 6.5z"
        "M4.5 12.8l6.3 2.7V18H4.5v-5.2zm8.7 2.7 6.3-2.7V18h-6.3v-2.5z"
    ),
    # BYD — oval badge with bars (build-your-dreams era mark simplified)
    "byd": (
        "M12 3c-5.5 0-9.5 3.2-9.5 9s4 9 9.5 9 9.5-3.2 9.5-9-4-9-9.5-9zm0 1.8c4.3 0 7.6 2.4 7.6 7.2s-3.3 "
        "7.2-7.6 7.2S4.4 16.8 4.4 12 7.7 4.8 12 4.8zM7.2 8.2h9.6v1.7H7.2V8.2zm0 3h9.6v1.7H7.2V11.2zm0 "
        "3h9.6v1.7H7.2V14.2z"
    ),
    # Geely — shield / three peaks
    "geely": (
        "M12 2.5 3.5 6.8v10.4L12 21.5l8.5-4.3V6.8L12 2.5zm0 2.2 6.2 3.1v7.4L12 18.3l-6.2-3.1V7.8L12 4.7z"
        "M8 10.2h8v1.6H8v-1.6zm0 3h8v1.6H8V13.2z"
    ),
    # Chery — oval with inner chevron
    "chery": (
        "M12 3.2c-6.2 0-10.2 3.5-10.2 8.8S5.8 20.8 12 20.8s10.2-3.5 10.2-8.8S18.2 3.2 12 3.2zm0 1.7c5 "
        "0 8.4 2.6 8.4 7.1S17 19.1 12 19.1 3.6 16.5 3.6 12 7 4.9 12 4.9zm0 2.4L7.2 16.2h2.2L12 10.8l2.6 "
        "5.4h2.2L12 7.3z"
    ),
    # Haval — bold H in rounded square (emblem, not red wordmark)
    "haval": (
        "M4.2 3.5h15.6c.9 0 1.6.7 1.6 1.6v13.8c0 .9-.7 1.6-1.6 1.6H4.2c-.9 0-1.6-.7-1.6-1.6V5.1c0-.9.7-1.6 "
        "1.6-1.6zm3 3.2v10.6h2.4v-4.2h4.8v4.2h2.4V6.7h-2.4v4.1H9.6V6.7H7.2z"
    ),
    # Zeekr — Z in square (from Wikimedia emblem)
    "zeekr": (
        "M3.2 3.2h17.6v17.6H3.2V3.2zm2.4 2.4v4.9l4.4 4.4V5.6H5.6zm8.8 0v9.2H8.8l4.4-4.4v-4.8h1.2zm0 "
        "0H18.4v4.9l-4 4.3V5.6z"
    ),
    # Li Auto — Li wordmark badge
    "li": (
        "M4 4h7.2c3.6 0 6 2 6 5.4 0 2.2-1.1 3.9-3 4.7L20 20h-4.4l-5.6-5.6H8.2V20H4V4zm4.2 3.2v5h2.8c1.7 "
        "0 2.7-.9 2.7-2.4S12.7 7.2 11 7.2H8.2z"
    ),
    # Changan — V in circle (real emblem geometry)
    "changan": (
        "M12 2.2C6.6 2.2 2.2 6.6 2.2 12S6.6 21.8 12 21.8 21.8 17.4 21.8 12 17.4 2.2 12 2.2zm0 1.8a8 8 0 1 1 "
        "0 16 8 8 0 0 1 0-16zm-5.2 5.2 4.4 9.2h1.6l4.4-9.2h-2.1L12 14.6 8.9 9.2H6.8z"
    ),
    # Exeed — X diamond
    "exeed": (
        "M12 2.4 3.5 7v10L12 21.6 20.5 17V7L12 2.4zm0 2.4 6 3.1v6.2l-6 3.1-6-3.1V7.9l6-3.1zM9.1 9.2 12 "
        "12.1l2.9-2.9 1.3 1.3L13.3 13.4l2.9 2.9-1.3 1.3L12 14.7l-2.9 2.9-1.3-1.3 2.9-2.9-2.9-2.9 1.3-1.3z"
    ),
    # Omoda — angular O ring
    "omoda": (
        "M12 2.5c-5.3 0-9.5 4.2-9.5 9.5s4.2 9.5 9.5 9.5 9.5-4.2 9.5-9.5S17.3 2.5 12 2.5zm0 2.2a7.3 7.3 0 1 1 "
        "0 14.6 7.3 7.3 0 0 1 0-14.6zm0 2.4c2.7 0 4.9 2.2 4.9 4.9S14.7 17 12 17s-4.9-2.2-4.9-4.9S9.3 7.1 "
        "12 7.1zm0 2a2.9 2.9 0 1 0 0 5.8 2.9 2.9 0 0 0 0-5.8z"
    ),
    # Jaecoo — J in shield
    "jaecoo": (
        "M12 2.3 4 5.5v6.8c0 4.6 3.2 7.8 8 9.4 4.8-1.6 8-4.8 8-9.4V5.5L12 2.3zm0 2.3 5.5 2.1v5.6c0 3.2-2.1 "
        "5.5-5.5 6.7-3.4-1.2-5.5-3.5-5.5-6.7V6.7L12 4.6zm1.2 3.2v6.2c0 1.2-.5 1.9-1.6 1.9-.8 0-1.4-.3-1.8-.8l1.1-1.2c.2.2.4.4.7.4.3 0 .4-.2.4-.6V7.8h1.2z"
    ),
    # Hongqi — flag crest
    "hongqi": (
        "M7.2 3.2h2.2l.6 1.2L12 3.8l2 0.6.6-1.2h2.2v17.6H7.2V3.2zm2.2 3.5v11.9h5.2V6.7h-2l-1.4 2.8L9.8 6.7h-.4z"
        "M11.2 8.2l.8 1.6.8-1.6h1.4v8.8h-4.4V8.2h1.4z"
    ),
    # UAZ — bird in circle
    "uaz": (
        "M12 2.5C6.8 2.5 2.5 6.8 2.5 12S6.8 21.5 12 21.5 21.5 17.2 21.5 12 17.2 2.5 12 2.5zm0 1.8a7.7 7.7 0 "
        "1 1 0 15.4 7.7 7.7 0 0 1 0-15.4zM5.8 11.2c1.8-1.2 4.2-2.4 6.2-2.4s4.4 1.2 6.2 2.4c-1.5 1.8-3.6 "
        "3.4-6.2 3.4s-4.7-1.6-6.2-3.4zm6.2-3.8c.7 0 1.5.1 2.2.4L12 9.6l-2.2-1.8c.7-.3 1.5-.4 2.2-.4z"
    ),
    # GAZ — leaping deer (simplified silhouette)
    "gaz": (
        "M4.5 16.8c1.2-2.8 2.4-4.6 4.2-6.1.4-.3.7-1 .7-1.5V7.2c0-.8.4-1.4 1.1-1.7l1.4-.5.5-1.4c.3-.8 "
        "1.2-1.1 1.9-.7l1.2.7c.5.3.7.8.6 1.3l-.3 1.2 1.3.6c.7.3 1 1.1.7 1.8l-.8 1.6c1.4.9 2.5 2.2 3.4 "
        "3.8l1.1-.4 1.6 1.2-2.2 1.5c-.3 1.4-.9 2.6-1.8 3.5H8.2c-1.3-1-2.5-2.5-3.7-4.6zm5.2-7.8.3 "
        "1.8c1.1.2 2 .7 2.7 1.4l.9-1.1c-.9-1-2.1-1.6-3.9-2.1z"
    ),
    # Tank — bold TANK badge
    "tank": (
        "M3.2 5.5h17.6v2.6H3.2V5.5zm1.6 3.8h14.4v9.4c0 1.1-.9 2-2 2H6.8c-1.1 0-2-.9-2-2V9.3zm3.4 "
        "2.2v5.6h2.2v-2h3.2v2h2.2v-5.6h-2.2v2.1h-3.2v-2.1H8.2z"
    ),
    # Dodge — two racing stripes + crosshair-ish mark
    "dodge": (
        "M3 6.5h18v2.2L5.5 17.5H3V6.5zm3.2 0H21v2.2L8.7 17.5H6.2L14.5 8.7H6.2V6.5z"
        "M10.5 4.8h3v2.2h-3V4.8zm0 12.2h3v2.2h-3v-2.2zM4.8 10.5h2.2v3H4.8v-3zm12.2 0H19v3h-2v-3z"
    ),
    # Lotus — circle with triangle flower
    "lotus": (
        "M12 2.2C6.6 2.2 2.2 6.6 2.2 12S6.6 21.8 12 21.8 21.8 17.4 21.8 12 17.4 2.2 12 2.2zm0 1.8a8 8 0 "
        "1 1 0 16 8 8 0 0 1 0-16zm0 2.2 4.8 8.4H7.2L12 6.2zm0 3.2-2.2 3.8h4.4L12 9.4z"
    ),
}

TMPL = (
    '<svg role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    "<title>{title}</title><path fill=\"#000\" d=\"{d}\"/></svg>\n"
)

TITLES = {
    "lexus": "Lexus",
    "genesis": "Genesis",
    "byd": "BYD",
    "geely": "Geely",
    "chery": "Chery",
    "haval": "Haval",
    "zeekr": "Zeekr",
    "li": "Li Auto",
    "changan": "Changan",
    "exeed": "Exeed",
    "omoda": "Omoda",
    "jaecoo": "Jaecoo",
    "hongqi": "Hongqi",
    "uaz": "UAZ",
    "gaz": "GAZ",
    "tank": "Tank",
    "dodge": "Dodge",
    "lotus": "Lotus",
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for slug, path_d in EMBLEMS.items():
        (OUT / f"{slug}.svg").write_text(
            TMPL.format(title=TITLES.get(slug, slug.title()), d=path_d),
            encoding="utf-8",
        )
        png = OUT / f"{slug}.png"
        if png.exists():
            png.unlink()
            print("removed", png.name)
        print("wrote", slug)


if __name__ == "__main__":
    main()
