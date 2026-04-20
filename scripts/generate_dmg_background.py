#!/usr/bin/env python3
"""Generate the DMG installer background image for Agent Deck.

Produces a 660x400 (Retina: 1320x800) PNG with:
- Dark gradient background matching the app's brand palette
- "AGENT DECK" pixel-art-style title
- Dashed arrow with "drag to install" label between icon positions
- Subtle star-field decoration
"""

import hashlib
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

# --- Dimensions (Retina 2x) ---
W, H = 1320, 800  # DMG window will be 660x400 @2x

# --- Colors ---
BG_TOP = (20, 22, 28)
BG_BOTTOM = (8, 10, 14)
TEXT_COLOR = (200, 200, 195)
TEXT_DIM = (120, 120, 118)
ACCENT = (160, 160, 155)
STAR_COLOR = (255, 255, 255)
PANEL_FILL = (18, 22, 30, 168)
PANEL_STROKE = (118, 255, 208, 150)
PANEL_GLOW = (86, 255, 214, 42)

# Icon center positions (in @2x coords)
# DMG window 660pt -> icons at ~180pt and ~480pt from left
APP_ICON_CENTER = (360, 420)
APPS_ICON_CENTER = (960, 420)

ARROW_Y = 420
ARROW_LEFT = 480
ARROW_RIGHT = 830


def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def draw_gradient(draw, w, h, c1, c2):
    for y in range(h):
        color = lerp_color(c1, c2, y / h)
        draw.line([(0, y), (w, y)], fill=color)


def draw_stars(draw, w, h, count=80):
    rng = random.Random(42)
    for _ in range(count):
        x = rng.randint(0, w)
        y = rng.randint(0, h)
        opacity = rng.randint(30, 100)
        size = rng.choice([1, 1, 1, 2])
        color = (*STAR_COLOR, opacity)
        draw.rectangle([x, y, x + size, y + size], fill=color)


def draw_corner_brackets(draw, w, h):
    """Draw decorative corner brackets like Agent Deck."""
    length = 50
    thickness = 2
    margin = 60
    color = (*ACCENT, 60)

    corners = [
        (margin, margin, 1, 1),
        (w - margin, margin, -1, 1),
        (margin, h - margin, 1, -1),
        (w - margin, h - margin, -1, -1),
    ]
    for cx, cy, dx, dy in corners:
        x0, x1 = sorted([cx, cx + length * dx])
        y0, y1 = sorted([cy, cy + thickness * dy])
        draw.rectangle([x0, y0, x1, y1], fill=color)
        x0, x1 = sorted([cx, cx + thickness * dx])
        y0, y1 = sorted([cy, cy + length * dy])
        draw.rectangle([x0, y0, x1, y1], fill=color)


def draw_pixel_title(draw, text, center_x, top_y):
    """Draw title text using available system font."""
    size = 72
    font = None
    for name in [
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/SFMono-Bold.otf",
        "/System/Library/Fonts/Monaco.dfont",
    ]:
        if os.path.exists(name):
            try:
                font = ImageFont.truetype(name, size)
                break
            except Exception:
                continue
    if font is None:
        font = ImageFont.load_default()

    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    x = center_x - tw // 2
    draw.text((x, top_y), text, fill=TEXT_COLOR, font=font)


def load_font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/SFNSMono.ttf",
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/SFMono-Bold.otf" if bold else "/System/Library/Fonts/SFMono-Regular.otf",
        "/System/Library/Fonts/Monaco.dfont",
    ]
    for name in candidates:
        if name and os.path.exists(name):
            try:
                return ImageFont.truetype(name, size)
            except Exception:
                continue
    return ImageFont.load_default()


def draw_applications_target(draw, center):
    """Draw a visible target behind the Finder Applications symlink."""
    cx, cy = center
    box_w, box_h = 238, 190
    x0 = cx - box_w // 2
    y0 = cy - box_h // 2
    x1 = cx + box_w // 2
    y1 = cy + box_h // 2

    for radius, alpha in [(36, 26), (24, 38), (12, 52)]:
        draw.rounded_rectangle(
            [x0 - radius, y0 - radius, x1 + radius, y1 + radius],
            radius=36 + radius // 2,
            outline=(86, 255, 214, alpha),
            width=2,
        )

    draw.rounded_rectangle([x0, y0, x1, y1], radius=34, fill=PANEL_FILL, outline=PANEL_STROKE, width=3)
    draw.rounded_rectangle([x0 + 14, y0 + 14, x1 - 14, y1 - 14], radius=24, outline=(*TEXT_COLOR, 48), width=2)

    # Folder shape behind the real Finder drop-link icon. It remains visible
    # even when Finder draws its Applications alias on top of this area.
    folder_x0, folder_y0 = cx - 58, cy - 48
    folder_x1, folder_y1 = cx + 58, cy + 48
    tab = [(folder_x0 + 8, folder_y0 + 12), (folder_x0 + 48, folder_y0 + 12), (folder_x0 + 62, folder_y0 + 28), (folder_x1 - 8, folder_y0 + 28)]
    draw.polygon(tab, fill=(45, 55, 70, 230), outline=(*TEXT_COLOR, 110))
    draw.rounded_rectangle([folder_x0, folder_y0 + 24, folder_x1, folder_y1], radius=18, fill=(28, 35, 47, 238), outline=(*TEXT_COLOR, 135), width=2)

    app_font = load_font(64, bold=True)
    bbox = draw.textbbox((0, 0), "A", font=app_font)
    draw.text((cx - (bbox[2] - bbox[0]) // 2, cy - 28), "A", fill=(230, 255, 248, 238), font=app_font)

    title_font = load_font(22, bold=True)
    hint_font = load_font(18)
    title = "Applications"
    hint = "drop here"
    title_box = draw.textbbox((0, 0), title, font=title_font)
    hint_box = draw.textbbox((0, 0), hint, font=hint_font)
    draw.text((cx - (title_box[2] - title_box[0]) // 2, y1 + 22), title, fill=TEXT_COLOR, font=title_font)
    draw.text((cx - (hint_box[2] - hint_box[0]) // 2, y1 + 52), hint, fill=(118, 255, 208, 210), font=hint_font)


def draw_app_source_label(draw, center):
    cx, cy = center
    label_font = load_font(22, bold=True)
    hint_font = load_font(17)
    title = "Agent Deck"
    hint = "drag this app"
    title_box = draw.textbbox((0, 0), title, font=label_font)
    hint_box = draw.textbbox((0, 0), hint, font=hint_font)
    y = cy + 118
    draw.text((cx - (title_box[2] - title_box[0]) // 2, y), title, fill=TEXT_COLOR, font=label_font)
    draw.text((cx - (hint_box[2] - hint_box[0]) // 2, y + 30), hint, fill=TEXT_DIM, font=hint_font)


def draw_dashed_arrow(draw, y, x1, x2):
    """Draw a dashed arrow with 'drag to install' label."""
    dash_len = 20
    gap_len = 14
    thickness = 3
    color = (*TEXT_COLOR, 190)

    x = x1
    while x < x2 - 20:
        end = min(x + dash_len, x2 - 20)
        draw.rectangle([x, y - thickness // 2, end, y + thickness // 2], fill=color)
        x = end + gap_len

    # Arrowhead
    arrow_size = 14
    for i in range(arrow_size):
        draw.line(
            [(x2 - arrow_size + i, y - arrow_size + i),
             (x2 - arrow_size + i, y + arrow_size - i)],
            fill=color,
        )

    # Label
    label = "drag to install"
    label_size = 24
    font = None
    for name in [
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/Monaco.dfont",
    ]:
        if os.path.exists(name):
            try:
                font = ImageFont.truetype(name, label_size)
                break
            except Exception:
                continue
    if font is None:
        font = ImageFont.load_default()

    bbox = draw.textbbox((0, 0), label, font=font)
    lw = bbox[2] - bbox[0]
    lx = (x1 + x2) // 2 - lw // 2
    draw.text((lx, y + 20), label, fill=(210, 218, 214), font=font)


def draw_bottom_bar(draw, w, h):
    """Draw a subtle bottom status bar."""
    bar_h = 50
    bar_y = h - bar_h
    draw.rectangle([0, bar_y, w, h], fill=(15, 17, 22))
    draw.line([(0, bar_y), (w, bar_y)], fill=(*ACCENT, 40))

    tagline = "> local agent control    drag app to Applications"
    font = None
    for name in [
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/Monaco.dfont",
    ]:
        if os.path.exists(name):
            try:
                font = ImageFont.truetype(name, 22)
                break
            except Exception:
                continue
    if font is None:
        font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), tagline, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(((w - tw) // 2, bar_y + 14), tagline, fill=TEXT_DIM, font=font)


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    output_path = os.path.join(repo_root, "Assets", "Brand", "dmg-background.png")
    retina_path = os.path.join(repo_root, "Assets", "Brand", "dmg-background@2x.png")

    img = Image.new("RGBA", (W, H))
    draw = ImageDraw.Draw(img)

    draw_gradient(draw, W, H, BG_TOP, BG_BOTTOM)
    draw_stars(draw, W, H)
    draw_corner_brackets(draw, W, H)
    draw_pixel_title(draw, "AGENT DECK", W // 2, 60)
    draw_applications_target(draw, APPS_ICON_CENTER)
    draw_app_source_label(draw, APP_ICON_CENTER)
    draw_dashed_arrow(draw, ARROW_Y, ARROW_LEFT, ARROW_RIGHT)
    draw_bottom_bar(draw, W, H)

    img.save(retina_path, "PNG")

    # Also save a 1x version for non-retina
    img_1x = img.resize((W // 2, H // 2), Image.LANCZOS)
    img_1x.save(output_path, "PNG")

    print(f"DMG background: {output_path}")
    print(f"DMG background @2x: {retina_path}")


if __name__ == "__main__":
    main()
