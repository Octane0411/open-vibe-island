# Brand Assets

This directory contains the current `Scout` mascot icon assets for macOS app packaging and internal product surfaces.

Structure:

- `Source/` keeps raw brand source assets that should not be treated as generated runtime output.
- `AppIcon.appiconset/`, `OpenIsland.iconset/`, and `OpenIsland.icns` are generated packaging assets.
- `Internal/` contains small derived assets for in-app surfaces.

Generation workflow:

- the generated assets are committed; `scripts/launch-dev-app.sh` and `scripts/package-app.sh` package the committed `OpenIsland.icns` (and `dmg-background.png`) as-is and do not re-render anything
- regenerate everything with `python3 scripts/generate_brand_icons.py` (or `zsh scripts/launch-dev-app.sh --regenerate-icons`, or `OPEN_ISLAND_REGENERATE_BRAND_ASSETS=true zsh scripts/package-app.sh`, which also re-renders `dmg-background.png`) only when you deliberately change the brand source, then commit the result
- PNG bytes differ between Pillow versions even when every pixel is identical, so regenerating on another machine produces a 14-file diff; do not commit that unless the artwork itself changed
- the script outputs:
  - `AppIcon.appiconset/` for future asset-catalog use
  - `OpenIsland.iconset/` and `OpenIsland.icns` for manual macOS bundle packaging
  - `Internal/color/` for in-app colored usage
  - `Internal/template/` for monochrome template-style usage
  - `Internal/badge/` for small boxed icon treatments

Current raw source assets:

- `Source/logo.png`: original 1280x1280 logo source image

macOS app icon sizes included:

- `16x16`
- `16x16@2x`
- `32x32`
- `32x32@2x`
- `128x128`
- `128x128@2x`
- `256x256`
- `256x256@2x`
- `512x512`
- `512x512@2x`

Why both formats exist:

- Apple’s asset-catalog workflow for macOS expects explicit icon sizes for the platform.
- Our current dev app bundle is assembled manually by `scripts/launch-dev-app.sh`, so it also needs a bundled `.icns` referenced by `CFBundleIconFile`.

Current design direction:

- shell: black glass face with a cool metallic rim
- mark: white `Scout` mascot with the three-square punctuation column from the chosen icon reference
- internal surfaces: simplified mascot-only versions without punctuation when space is tight
