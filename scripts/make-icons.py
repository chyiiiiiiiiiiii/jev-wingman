#!/usr/bin/env python3
"""Build the app icon and the menu bar glyph from one artwork: a coloured stroke on white.

    scripts/make-icons.py artwork.png

Writes Resources/AppIcon.icns (macOS squircle body per Apple's 1024 template, stroke
multiplied onto it so the white artwork background disappears) and Resources/MenuBarIcon*.png
(a black template image whose alpha is the stroke).
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
CANVAS, BODY, RADIUS = 1024, 824, 185     # Apple's macOS icon template
MARK_BOX = (0.66, 0.60)                    # widest and tallest the mark may be, as parts of the body


def stroke_mask(art: Image.Image) -> Image.Image:
    """Alpha of the stroke: how far each pixel is from white."""
    r, g, b = art.convert("RGB").split()
    darkest = ImageChops.darker(ImageChops.darker(r, g), b)
    return darkest.point(lambda v: 0 if v > 245 else min(255, int((255 - v) * 1.25)))


def app_icon(art: Image.Image, mark: tuple[int, int, int, int]) -> Image.Image:
    crop = art.convert("RGB").crop(mark)
    scale = min(BODY * MARK_BOX[0] / crop.width, BODY * MARK_BOX[1] / crop.height)
    crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.LANCZOS)

    body = Image.new("RGB", (BODY, BODY))
    top, bottom = (255, 255, 255), (240, 242, 247)
    for y in range(BODY):
        t = y / (BODY - 1)
        ImageDraw.Draw(body).line([(0, y), (BODY, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    field = Image.new("RGB", (BODY, BODY), (255, 255, 255))
    field.paste(crop, ((BODY - crop.width) // 2, (BODY - crop.height) // 2))
    body = ImageChops.multiply(body, field)          # white artwork background vanishes

    shape = Image.new("L", (BODY, BODY), 0)
    ImageDraw.Draw(shape).rounded_rectangle([0, 0, BODY - 1, BODY - 1], RADIUS, fill=255)
    origin = (CANVAS - BODY) // 2
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 70), (origin, origin + 12), shape)
    icon = Image.alpha_composite(icon, shadow.filter(ImageFilter.GaussianBlur(18)))
    icon.paste(body, (origin, origin), shape)
    return icon


def menu_bar_glyph(art: Image.Image, mark: tuple[int, int, int, int], height: int) -> Image.Image:
    alpha = stroke_mask(art).crop(mark)
    width = round(alpha.width * height / alpha.height)
    glyph = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    glyph.putalpha(alpha.resize((width, height), Image.LANCZOS))
    return glyph


def main(artwork: str) -> None:
    art = Image.open(artwork)
    mark = stroke_mask(art).getbbox()
    resources = ROOT / "Resources"

    icon = app_icon(art, mark)
    icon.save(resources / "AppIcon-1024.png")
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
                icon.resize((points * scale,) * 2, Image.LANCZOS).save(iconset / name)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(resources / "AppIcon.icns")], check=True)

    menu_bar_glyph(art, mark, 14).save(resources / "MenuBarIcon.png")
    menu_bar_glyph(art, mark, 28).save(resources / "MenuBarIcon@2x.png")
    print("wrote AppIcon.icns, AppIcon-1024.png, MenuBarIcon.png, MenuBarIcon@2x.png")


if __name__ == "__main__":
    main(sys.argv[1])
