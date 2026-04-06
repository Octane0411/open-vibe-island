#!/bin/zsh

set -euo pipefail

skip_setup=false
for arg in "$@"; do
  case "$arg" in
    --skip-setup) skip_setup=true ;;
  esac
done

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$repo_root/.build/arm64-apple-macosx/debug"
app_binary="$build_root/OpenIslandApp"
hooks_binary="$build_root/OpenIslandHooks"
setup_binary="$build_root/OpenIslandSetup"
brand_script="$repo_root/scripts/generate_brand_icons.py"
brand_icon="$repo_root/Assets/Brand/OpenIsland.icns"
bundle_dir="$HOME/Applications/Open Island Dev.app"
plist_path="$bundle_dir/Contents/Info.plist"
bundle_binary="$bundle_dir/Contents/MacOS/OpenIslandApp"

cd "$repo_root"

swift build -c debug --product OpenIslandApp
swift build -c debug --product OpenIslandHooks
swift build -c debug --product OpenIslandSetup

python3 "$brand_script"
if [ "$skip_setup" = false ]; then
  "$setup_binary" install --hooks-binary "$hooks_binary"
fi

mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Helpers" "$bundle_dir/Contents/Resources" "$bundle_dir/Contents/Frameworks"
cp "$app_binary" "$bundle_binary"
cp "$hooks_binary" "$bundle_dir/Contents/Helpers/OpenIslandHooks"
cp "$setup_binary" "$bundle_dir/Contents/Helpers/OpenIslandSetup"
cp "$brand_icon" "$bundle_dir/Contents/Resources/OpenIsland.icns"
chmod +x "$bundle_binary" "$bundle_dir/Contents/Helpers/OpenIslandHooks" "$bundle_dir/Contents/Helpers/OpenIslandSetup"

# Add rpath so the binary can find Sparkle.framework in Contents/Frameworks/.
install_name_tool -add_rpath @loader_path/../Frameworks "$bundle_binary" 2>/dev/null || true

# Copy SPM resource bundle to .app root — SPM's generated Bundle.module accessor
# searches Bundle.main.bundleURL (the .app root), NOT Contents/Resources/.
resource_bundle="$build_root/OpenIsland_OpenIslandApp.bundle"
if [ -d "$resource_bundle" ]; then
    rm -rf "$bundle_dir/OpenIsland_OpenIslandApp.bundle"
    cp -R "$resource_bundle" "$bundle_dir/"
fi

# Copy Sparkle.framework for auto-update support.
sparkle_framework="$repo_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$sparkle_framework" ]; then
    rm -rf "$bundle_dir/Contents/Frameworks/Sparkle.framework"
    cp -R "$sparkle_framework" "$bundle_dir/Contents/Frameworks/"
fi

cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>OpenIslandApp</string>
    <key>CFBundleIdentifier</key>
    <string>app.openisland.dev</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>OpenIsland</string>
    <key>CFBundleName</key>
    <string>Open Island Dev</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Open Island needs automation access to focus Terminal and iTerm sessions for jump-back.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/Octane0411/open-vibe-island/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>3IF8txq9RRNanzE2FNhyGRcwhslTucCcJHpTkpxcgBQ=</string>
</dict>
</plist>
EOF

# Dev builds on macOS 26+: the SPM resource bundle at the .app root
# causes "unsealed contents" codesign failure. Move it into
# Contents/Resources/ so signing succeeds. On the developer machine
# Bundle.module falls back to the hardcoded .build/ path, so
# localization still works. (Release builds use package-app.sh which
# has its own resource bundle handling.)
resource_bundle_name="OpenIsland_OpenIslandApp.bundle"
root_bundle="$bundle_dir/$resource_bundle_name"
resources_bundle="$bundle_dir/Contents/Resources/$resource_bundle_name"
if [ -d "$root_bundle" ] && [ ! -L "$root_bundle" ]; then
    rm -rf "$resources_bundle"
    mv "$root_bundle" "$resources_bundle"
fi
# Remove stale symlinks from previous runs.
[ -L "$root_bundle" ] && rm -f "$root_bundle"

codesign --force --deep --sign - "$bundle_dir" 2>/dev/null || true

pkill -f "$bundle_binary" >/dev/null 2>&1 || true
open -na "$bundle_dir"
