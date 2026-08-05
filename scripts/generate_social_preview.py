#!/usr/bin/env python3
"""Generate the GitHub social preview from checked-in brand assets."""

from pathlib import Path
from typing import Optional, Tuple

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = ROOT / "docs/images/social-preview-background.png"
SCREENSHOT = ROOT / "docs/images/screenshot-overview.png"
APP_ICON = ROOT / "Assets/Brand/app-icon-v6.png"
OUTPUT = ROOT / "docs/images/social-preview.png"

CANVAS_SIZE = (1280, 640)
FONT_REGULAR = "/System/Library/Fonts/SFNS.ttf"
FONT_HELVETICA = "/System/Library/Fonts/HelveticaNeue.ttc"
FONT_MONO = "/System/Library/Fonts/SFNSMono.ttf"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    if bold:
        return ImageFont.truetype(FONT_HELVETICA, size=size, index=1)
    return ImageFont.truetype(FONT_REGULAR, size=size)


def mono_font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_MONO, size=size)


def cover(image: Image.Image, size: Tuple[int, int]) -> Image.Image:
    scale = max(size[0] / image.width, size[1] / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))


def rounded_image(image: Image.Image, size: Tuple[int, int], radius: int) -> Image.Image:
    fitted = cover(image.convert("RGB"), size).convert("RGBA")
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    fitted.putalpha(mask)
    return fitted


def add_left_readability_gradient(image: Image.Image) -> None:
    overlay = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    pixels = overlay.load()
    for x in range(820):
        alpha = round(220 * max(0.0, 1.0 - x / 820) ** 1.35)
        for y in range(CANVAS_SIZE[1]):
            pixels[x, y] = (7, 7, 9, alpha)
    image.alpha_composite(overlay)


def pill(draw: ImageDraw.ImageDraw, x: int, y: int, label: str, dot: Optional[str] = None) -> int:
    label_font = mono_font(15)
    text_box = draw.textbbox((0, 0), label, font=label_font)
    text_width = text_box[2] - text_box[0]
    left_padding = 36 if dot else 18
    width = left_padding + text_width + 18
    draw.rounded_rectangle(
        (x, y, x + width, y + 34),
        radius=17,
        fill=(20, 20, 23, 218),
        outline=(241, 234, 217, 42),
        width=1,
    )
    if dot:
        draw.ellipse((x + 16, y + 13, x + 24, y + 21), fill=dot)
    draw.text((x + left_padding, y + 8), label, font=label_font, fill=(241, 234, 217, 214))
    return width


def main() -> None:
    background = cover(Image.open(BACKGROUND).convert("RGB"), CANVAS_SIZE).convert("RGBA")
    add_left_readability_gradient(background)

    draw = ImageDraw.Draw(background)

    icon = rounded_image(Image.open(APP_ICON), (58, 58), radius=14)
    background.alpha_composite(icon, (70, 54))
    draw.text((148, 60), "Open Island", font=font(31, bold=True), fill="#F7F3EA")
    draw.text((150, 96), "AGENTS IN YOUR MENU BAR", font=mono_font(13), fill=(241, 234, 217, 145))

    draw.text((70, 174), "All your coding agents.", font=font(54, bold=True), fill="#FFFFFF")
    draw.text((70, 236), "One island.", font=font(62, bold=True), fill="#F1EAD9")
    draw.ellipse((393, 266, 407, 280), fill="#68D983")

    draw.text(
        (74, 326),
        "Monitor sessions. Approve actions. Jump back instantly.",
        font=font(21),
        fill=(255, 255, 255, 172),
    )

    x = 72
    x += pill(draw, x, 386, "OPEN SOURCE", "#68D983") + 10
    x += pill(draw, x, 386, "NATIVE macOS") + 10
    pill(draw, x, 386, "LOCAL FIRST")

    draw.text(
        (74, 561),
        "github.com/Octane0411/open-vibe-island",
        font=mono_font(17),
        fill=(241, 234, 217, 168),
    )

    screenshot_size = (430, 223)
    screenshot_position = (805, 382)
    shadow = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (
            screenshot_position[0] - 8,
            screenshot_position[1] - 8,
            screenshot_position[0] + screenshot_size[0] + 8,
            screenshot_position[1] + screenshot_size[1] + 8,
        ),
        radius=28,
        fill=(0, 0, 0, 190),
    )
    background.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))

    screenshot = rounded_image(Image.open(SCREENSHOT), screenshot_size, radius=20)
    border = Image.new("RGBA", (screenshot_size[0] + 4, screenshot_size[1] + 4), (0, 0, 0, 0))
    border_draw = ImageDraw.Draw(border)
    border_draw.rounded_rectangle(
        (0, 0, border.width - 1, border.height - 1),
        radius=22,
        fill=(0, 0, 0, 0),
        outline=(241, 234, 217, 110),
        width=2,
    )
    background.alpha_composite(screenshot, screenshot_position)
    background.alpha_composite(border, (screenshot_position[0] - 2, screenshot_position[1] - 2))

    output = background.convert("RGB")
    output.save(OUTPUT, "PNG", optimize=True)
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
