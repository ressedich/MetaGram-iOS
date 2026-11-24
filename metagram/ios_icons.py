#!/usr/bin/env python3
"""Replace the iOS app icons with the MetaGram default icon (metagram/icons.py, first entry).

Rewrites, at their current pixel sizes, every PNG of the app icon sets
(DefaultAppIcon.xcassets, AppIcons.xcassets, *.alticon, IconDefault-*.png), and the
Icon Composer bundle Telegram.icon used by iOS 26+ (glyph layer, background layer, colors).

Needs: pip install pillow resvg-py
Run from the repository root: python metagram/ios_icons.py
"""
import io
import pathlib
import re
import sys

import resvg_py
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from icons import ICONS, svg  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "Telegram/Telegram-iOS"
DEFAULT = ICONS[0]

# iOS masks app icons itself: the image must be a full square without transparency.
SQUARE_SVG = svg(DEFAULT, rounded=False)


def render(size):
    data = resvg_py.svg_to_bytes(svg_string=SQUARE_SVG, width=size, height=size)
    return Image.open(io.BytesIO(bytes(data))).convert("RGB")


def icon_pngs():
    for path in sorted(APP.rglob("*.png")):
        rel = path.relative_to(APP).as_posix()
        if (rel.startswith("DefaultAppIcon.xcassets/") or rel.startswith("AppIcons.xcassets/")
                or ".alticon/" in rel or path.name.startswith("IconDefault-")):
            yield path


def glyph_svg(size=1024):
    fg = DEFAULT.get("fg", "#FFFFFF")
    glyph = DEFAULT["glyph"].replace("FG", fg).replace("BG", DEFAULT["bg"])
    scale = size / 512
    return (f'<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<svg width="{size}px" height="{size}px" viewBox="0 0 {size} {size}" version="1.1" '
            f'xmlns="http://www.w3.org/2000/svg">\n'
            f'    <title>Plane</title>\n'
            f'    <g id="Plane" transform="scale({scale:g})">{glyph}</g>\n'
            f'</svg>\n')


def background_svg(size=1024):
    return (f'<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<svg width="{size}px" height="{size}px" viewBox="0 0 {size} {size}" version="1.1" '
            f'xmlns="http://www.w3.org/2000/svg">\n'
            f'    <title>Oval</title>\n'
            f'    <rect id="Oval" width="{size}" height="{size}" fill="#000000"/>\n'
            f'</svg>\n')


def srgb(hex_color):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def update_icon_composer():
    bundle = APP / "Telegram.icon"
    (bundle / "Assets/Plane.svg").write_text(glyph_svg(), encoding="utf-8", newline="\n")
    (bundle / "Assets/Oval.svg").write_text(background_svg(), encoding="utf-8", newline="\n")
    j = bundle / "icon.json"
    text = j.read_text(encoding="utf-8")
    color = srgb(DEFAULT["bg"])
    # background layer gradient (light) and its dark-appearance variant: one solid-looking color
    text = re.sub(r'("linear-gradient" : \[\s*)"[^"]+",(\s*)"[^"]+"',
                  lambda m: f'{m.group(1)}"{color}",{m.group(2)}"{color}"', text)
    text = re.sub(r'("automatic-gradient" : )"[^"]+"', lambda m: f'{m.group(1)}"{color}"', text)
    j.write_text(text, encoding="utf-8", newline="\n")


def main():
    count = 0
    for path in icon_pngs():
        with Image.open(path) as im:
            size = im.size
        if size[0] != size[1]:
            continue
        render(size[0]).save(path)
        count += 1
    update_icon_composer()
    print(f"{count} PNG icons replaced, Telegram.icon updated")


if __name__ == "__main__":
    main()
