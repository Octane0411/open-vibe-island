#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE_BRAND_ROOT = REPO_ROOT / "Assets" / "Brand"

SCOUT_PATTERN = [
    "..B..B..",
    "..BBBB..",
    ".BHHHHB.",
    "BBHEHEBB",
    ".BHHHHB.",
    "..BBBB..",
    ".B....B.",
    "........",
]

APP_ICON_SPECS = [
    ("icon_16x16.png", "16x16", "1x", 16),
    ("icon_16x16@2x.png", "16x16", "2x", 32),
    ("icon_32x32.png", "32x32", "1x", 32),
    ("icon_32x32@2x.png", "32x32", "2x", 64),
    ("icon_128x128.png", "128x128", "1x", 128),
    ("icon_128x128@2x.png", "128x128", "2x", 256),
    ("icon_256x256.png", "256x256", "1x", 256),
    ("icon_256x256@2x.png", "256x256", "2x", 512),
    ("icon_512x512.png", "512x512", "1x", 512),
    ("icon_512x512@2x.png", "512x512", "2x", 1024),
]

# Apple's macOS icon grid (Big Sur+): the art occupies an 824×824 region
# centered in a 1024×1024 canvas, leaving a transparent safe zone so our
# squircle visually matches stock macOS icons in Finder/Launchpad/Dock.
MACOS_ICON_CONTENT_RATIO = 824 / 1024


@dataclass(frozen=True)
class OutputLayout:
    brand_root: Path
    iconset_dir: Path
    icns_path: Path
    app_iconset_dir: Path | None = None
    internal_color_dir: Path | None = None
    internal_template_dir: Path | None = None
    internal_badge_dir: Path | None = None
    svg_master_path: Path | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate Open Island brand icon assets.")
    parser.add_argument(
        "--output-root",
        type=Path,
        default=SOURCE_BRAND_ROOT,
        help="Directory that receives generated assets. Defaults to Assets/Brand in the repository.",
    )
    parser.add_argument(
        "--icns-only",
        action="store_true",
        help="Generate only the iconset and .icns bundle required for app packaging.",
    )
    return parser.parse_args()


def build_output_layout(output_root: Path, icns_only: bool) -> OutputLayout:
    if icns_only:
        return OutputLayout(
            brand_root=output_root,
            iconset_dir=output_root / "OpenIsland.iconset",
            icns_path=output_root / "OpenIsland.icns",
        )

    return OutputLayout(
        brand_root=output_root,
        app_iconset_dir=output_root / "AppIcon.appiconset",
        iconset_dir=output_root / "OpenIsland.iconset",
        internal_color_dir=output_root / "Internal" / "color",
        internal_template_dir=output_root / "Internal" / "template",
        internal_badge_dir=output_root / "Internal" / "badge",
        icns_path=output_root / "OpenIsland.icns",
        svg_master_path=output_root / "scout-app-icon-master.svg",
    )


def main() -> None:
    args = parse_args()
    layout = build_output_layout(args.output_root, args.icns_only)

    ensure_clean_dir(layout.iconset_dir)
    layout.brand_root.mkdir(parents=True, exist_ok=True)

    if layout.app_iconset_dir is not None:
        ensure_clean_dir(layout.app_iconset_dir)
    if layout.internal_color_dir is not None:
        ensure_clean_dir(layout.internal_color_dir)
    if layout.internal_template_dir is not None:
        ensure_clean_dir(layout.internal_template_dir)
    if layout.internal_badge_dir is not None:
        ensure_clean_dir(layout.internal_badge_dir)

    if layout.svg_master_path is not None:
        write_svg_master(layout.svg_master_path)
    write_app_icons(layout)
    if layout.app_iconset_dir is not None:
        write_internal_assets(layout)
        write_appiconset_contents_json(layout.app_iconset_dir / "Contents.json")
    build_icns(layout)


def ensure_clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def rgba(hex_color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[index : index + 2], 16) for index in range(0, 6, 2)) + (alpha,)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def solid_layer(size: tuple[int, int], color: tuple[int, int, int, int]) -> Image.Image:
    return Image.new("RGBA", size, color)


def vertical_gradient(size: tuple[int, int], top: str, bottom: str) -> Image.Image:
    top_rgba = rgba(top)
    bottom_rgba = rgba(bottom)
    image = Image.new("RGBA", size)
    pixels = image.load()
    height = max(size[1] - 1, 1)
    for y in range(size[1]):
        mix = y / height
        color = tuple(
            round(top_rgba[index] + (bottom_rgba[index] - top_rgba[index]) * mix)
            for index in range(4)
        )
        for x in range(size[0]):
            pixels[x, y] = color
    return image


def diagonal_gradient(size: tuple[int, int], top_left: str, mid: str, bottom_right: str) -> Image.Image:
    tl = rgba(top_left)
    m = rgba(mid)
    br = rgba(bottom_right)
    image = Image.new("RGBA", size)
    pixels = image.load()
    diag = max((size[0] + size[1]) - 2, 1)
    for y in range(size[1]):
        for x in range(size[0]):
            t = (x + y) / diag
            if t < 0.5:
                t2 = t * 2
                color = tuple(round(tl[i] + (m[i] - tl[i]) * t2) for i in range(4))
            else:
                t2 = (t - 0.5) * 2
                color = tuple(round(m[i] + (br[i] - m[i]) * t2) for i in range(4))
            pixels[x, y] = color
    return image


def draw_shadow(base: Image.Image, box: tuple[int, int, int, int], radius: int, color: str, blur: float) -> None:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(box, radius=radius, fill=rgba(color))
    shadow = layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(shadow)


def draw_glow_ellipse(base: Image.Image, box: tuple[int, int, int, int], color: str, blur: float) -> None:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.ellipse(box, fill=rgba(color))
    glow = layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(glow)


def paste_masked(base: Image.Image, overlay: Image.Image, xy: tuple[int, int], mask: Image.Image) -> None:
    base.paste(overlay, xy, mask)


def draw_app_shell(size: int) -> tuple[Image.Image, tuple[int, int, int, int]]:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    icon_size = int(size * 0.86)
    icon_x = (size - icon_size) // 2
    icon_y = (size - icon_size) // 2 - max(2, size // 64)
    outer_radius = max(12, int(icon_size * 0.24))

    face_x = icon_x
    face_y = icon_y
    face_size = icon_size
    face_radius = outer_radius

    face_gradient = diagonal_gradient((face_size, face_size), "#B8F0A8", "#88E0C0", "#78CCE8")
    face_mask = rounded_mask((face_size, face_size), face_radius)
    paste_masked(image, face_gradient, (face_x, face_y), face_mask)

    return image, (face_x, face_y, face_size, face_size)


def draw_mark_shadow(draw: ImageDraw.ImageDraw, origin: tuple[int, int], cell: int, pattern: list[str], alpha: int) -> None:
    ox, oy = origin
    offset = max(1, round(cell * 0.16))
    shadow_fill = rgba("#000000", alpha)
    for row_index, row in enumerate(pattern):
        for column_index, char in enumerate(row):
            if char == ".":
                continue
            x = ox + column_index * cell + offset
            y = oy + row_index * cell + offset
            draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=shadow_fill)


def draw_mark(
    draw: ImageDraw.ImageDraw,
    origin: tuple[int, int],
    cell: int,
    palette: dict[str, tuple[int, int, int, int]],
    include_punctuation: bool,
    silhouette_only: bool = False,
) -> None:
    ox, oy = origin

    for row_index, row in enumerate(SCOUT_PATTERN):
        for column_index, char in enumerate(row):
            if char == ".":
                continue

            fill = palette["B" if silhouette_only else char]
            x = ox + column_index * cell
            y = oy + row_index * cell
            draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=fill)

    if include_punctuation:
        x = ox + 11 * cell
        for row_index in (1, 3, 5):
            y = oy + row_index * cell
            draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=palette["P"])


def render_app_icon(size: int) -> Image.Image:
    image, face = draw_app_shell(size)
    draw = ImageDraw.Draw(image)

    face_x, face_y, face_size, face_height = face
    mark_width_units = 8
    mark_height_units = 8
    cell = max(1, min(face_size // (mark_width_units + 3), face_height // (mark_height_units + 3)))
    mark_width = mark_width_units * cell
    mark_height = mark_height_units * cell
    origin_x = face_x + (face_size - mark_width) // 2
    origin_y = face_y + (face_height - mark_height) // 2

    palette = {
        "B": rgba("#264653"),
        "H": rgba("#E9F5F2"),
        "E": rgba("#1A1C20"),
    }

    draw_mark_shadow(draw, (origin_x, origin_y), cell, SCOUT_PATTERN, 60)
    draw_mark(draw, (origin_x, origin_y), cell, palette, include_punctuation=False)
    return image


def render_color_mark(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    cell = size / 8
    palette = {
        "B": rgba("#6E9FFF"),
        "H": rgba("#96BCFF"),
        "E": rgba("#112548"),
        "P": rgba("#6E9FFF"),
    }
    origin = (0, 0)
    for row_index, row in enumerate(SCOUT_PATTERN):
        for column_index, char in enumerate(row):
            if char == ".":
                continue
            x = round(origin[0] + column_index * cell)
            y = round(origin[1] + row_index * cell)
            x2 = round(origin[0] + (column_index + 1) * cell)
            y2 = round(origin[1] + (row_index + 1) * cell)
            draw.rectangle((x, y, x2 - 1, y2 - 1), fill=palette[char])
    return image


def render_template_mark(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    cell = size / 8
    fill = rgba("#000000")
    for row_index, row in enumerate(SCOUT_PATTERN):
        for column_index, char in enumerate(row):
            if char == ".":
                continue
            x = round(column_index * cell)
            y = round(row_index * cell)
            x2 = round((column_index + 1) * cell)
            y2 = round((row_index + 1) * cell)
            draw.rectangle((x, y, x2 - 1, y2 - 1), fill=fill)
    return image


def render_badge(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bezel_size = size
    bezel_gradient = vertical_gradient((bezel_size, bezel_size), "#A7ADB4", "#575D65")
    bezel_mask = rounded_mask((bezel_size, bezel_size), max(6, int(size * 0.23)))
    paste_masked(image, bezel_gradient, (0, 0), bezel_mask)

    inset = max(2, int(size * 0.06))
    face_size = size - inset * 2
    face_gradient = vertical_gradient((face_size, face_size), "#2D3136", "#090A0D")
    face_mask = rounded_mask((face_size, face_size), max(5, int(size * 0.19)))
    paste_masked(image, face_gradient, (inset, inset), face_mask)

    mark = render_color_mark(int(face_size * 0.64)).resize((int(face_size * 0.64), int(face_size * 0.64)), Image.Resampling.NEAREST)
    mx = inset + (face_size - mark.width) // 2
    my = inset + (face_size - mark.height) // 2
    image.alpha_composite(mark, (mx, my))
    return image


def write_app_icons(layout: OutputLayout) -> None:
    cat_icon_path = SOURCE_BRAND_ROOT / "app-icon-cat.png"
    if cat_icon_path.exists():
        src = Image.open(cat_icon_path).convert("RGBA")
        for filename, _, _, pixel_size in APP_ICON_SPECS:
            canvas = Image.new("RGBA", (pixel_size, pixel_size), (0, 0, 0, 0))
            content_size = max(1, round(pixel_size * MACOS_ICON_CONTENT_RATIO))
            offset = (pixel_size - content_size) // 2
            resized = src.resize((content_size, content_size), Image.Resampling.LANCZOS)
            canvas.alpha_composite(resized, (offset, offset))
            if layout.app_iconset_dir is not None:
                canvas.save(layout.app_iconset_dir / filename)
            canvas.save(layout.iconset_dir / filename)
    else:
        for filename, _, _, pixel_size in APP_ICON_SPECS:
            icon = render_app_icon(pixel_size)
            if layout.app_iconset_dir is not None:
                icon.save(layout.app_iconset_dir / filename)
            icon.save(layout.iconset_dir / filename)


def write_internal_assets(layout: OutputLayout) -> None:
    assert layout.internal_color_dir is not None
    assert layout.internal_template_dir is not None
    assert layout.internal_badge_dir is not None

    for size in (14, 18, 32, 64):
        render_color_mark(size).save(layout.internal_color_dir / f"scout-mark-{size}.png")

    for size in (18, 36):
        render_template_mark(size).save(layout.internal_template_dir / f"scout-template-{size}.png")

    for size in (32, 64):
        render_badge(size).save(layout.internal_badge_dir / f"scout-badge-{size}.png")


def write_appiconset_contents_json(path: Path) -> None:
    images = [
        {
            "filename": filename,
            "idiom": "mac",
            "scale": scale,
            "size": size,
        }
        for filename, size, scale, _ in APP_ICON_SPECS
    ]
    contents = {
        "images": images,
        "info": {
            "author": "app.openisland.dev",
            "version": 1,
        },
    }
    path.write_text(json.dumps(contents, indent=2) + "\n")


def build_icns(layout: OutputLayout) -> None:
    if layout.icns_path.exists():
        layout.icns_path.unlink()

    subprocess.run(
        ["iconutil", "-c", "icns", str(layout.iconset_dir), "-o", str(layout.icns_path)],
        check=True,
    )


def write_svg_master(path: Path) -> None:
    pixel_rects = []
    palette = {
        "B": "#264653",
        "H": "#E9F5F2",
        "E": "#1A1C20",
    }

    cell = 58
    mark_width = 8 * cell
    mark_height = 8 * cell
    origin_x = (1024 - mark_width) // 2 - 24  # centered within face area
    origin_y = (1024 - mark_height) // 2 - 12
    for row_index, row in enumerate(SCOUT_PATTERN):
        for column_index, char in enumerate(row):
            if char == ".":
                continue
            pixel_rects.append(
                f'<rect x="{origin_x + column_index * cell}" y="{origin_y + row_index * cell}" width="{cell}" height="{cell}" fill="{palette[char]}"/>'
            )

    svg = f"""<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="face" x1="140" y1="128" x2="884" y2="872" gradientUnits="userSpaceOnUse">
      <stop stop-color="#B8F0A8"/>
      <stop offset="0.5" stop-color="#88E0C0"/>
      <stop offset="1" stop-color="#78CCE8"/>
    </linearGradient>
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
      <stop stop-color="white" stop-opacity="0.12"/>
      <stop offset="1" stop-color="white" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <g>
    <rect x="140" y="128" width="744" height="744" rx="178" fill="url(#face)"/>
    <rect x="140" y="128" width="744" height="348" rx="178" fill="url(#gloss)"/>
  </g>
  <g>
    {"".join(pixel_rects)}
  </g>
</svg>
"""
    path.write_text(svg)


if __name__ == "__main__":
    main()
