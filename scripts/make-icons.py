#!/usr/bin/env python3
"""Build the app icon and the menu bar glyph from one artwork: a coloured stroke on white.

    scripts/make-icons.py artwork.png

The stroke's outline is filled solid, in the stroke's own indigo-to-cyan gradient: a solid shape is found
at a glance in a crowded menu bar or Dock, where a thin line is not. Writes Resources/AppIcon.icns (macOS
squircle body per Apple's 1024 template) and Resources/MenuBarIcon*.png (a black template image).
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
CANVAS, BODY, RADIUS = 1024, 824, 185     # Apple's macOS icon template
MARK_BOX = (0.66, 0.60)                    # widest and tallest the mark may be, as parts of the body
INDIGO, CYAN = (57, 48, 139), (38, 201, 206)   # the artwork stroke's two ends


def stroke_mask(art: Image.Image) -> Image.Image:
    """Alpha of the stroke: how far each pixel is from white."""
    r, g, b = art.convert("RGB").split()
    darkest = ImageChops.darker(ImageChops.darker(r, g), b)
    return darkest.point(lambda v: 0 if v > 245 else min(255, int((255 - v) * 1.25)))


def solid_mark(art: Image.Image) -> Image.Image:
    """The bubble as one filled shape: the stroke plus everything it encloses."""
    stroke = stroke_mask(art)
    line = stroke.point(lambda v: 255 if v > 90 else 0)
    inside = line.copy()
    box = stroke.getbbox()
    seed = ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2 - (box[3] - box[1]) // 8)   # above the tail
    ImageDraw.floodfill(inside, seed, 255)
    return ImageChops.lighter(inside, stroke)            # keep the stroke's soft outer edge


def gradient(size: tuple[int, int], start: tuple[int, int, int], end: tuple[int, int, int]) -> Image.Image:
    """Top-left to bottom-right, the direction the artwork's stroke shades."""
    ramp = Image.new("L", (256, 256))
    ramp.putdata([(x + y) // 2 for y in range(256) for x in range(256)])   # 0 top-left … 255 bottom-right
    return Image.composite(Image.new("RGB", size, end), Image.new("RGB", size, start), ramp.resize(size, Image.BILINEAR))


def app_icon(art: Image.Image, mark: tuple[int, int, int, int]) -> Image.Image:
    shape = solid_mark(art).crop(mark)
    scale = min(BODY * MARK_BOX[0] / shape.width, BODY * MARK_BOX[1] / shape.height)
    shape = shape.resize((round(shape.width * scale), round(shape.height * scale)), Image.LANCZOS)

    body = Image.new("RGB", (BODY, BODY))
    top, bottom = (255, 255, 255), (240, 242, 247)
    for y in range(BODY):
        t = y / (BODY - 1)
        ImageDraw.Draw(body).line([(0, y), (BODY, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    body.paste(gradient(shape.size, INDIGO, CYAN), ((BODY - shape.width) // 2, (BODY - shape.height) // 2), shape)

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
    alpha = solid_mark(art).crop(mark)
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

    menu_bar_glyph(art, mark, 16).save(resources / "MenuBarIcon.png")
    menu_bar_glyph(art, mark, 32).save(resources / "MenuBarIcon@2x.png")
    print("wrote AppIcon.icns, AppIcon-1024.png, MenuBarIcon.png, MenuBarIcon@2x.png")


if __name__ == "__main__":
    main(sys.argv[1])
