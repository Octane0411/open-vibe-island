#!/bin/zsh

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Open Island packaging runs only on macOS." >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="${OPEN_ISLAND_APP_NAME:-Open Island}"
bundle_identifier="${OPEN_ISLAND_BUNDLE_ID:-app.openisland.dev}"
version="${OPEN_ISLAND_VERSION:-0.1.0}"
build_number="${OPEN_ISLAND_BUILD_NUMBER:-$(git -C "$repo_root" rev-list --count HEAD 2>/dev/null || echo 1)}"
package_root="${OPEN_ISLAND_PACKAGE_ROOT:-$repo_root/output/package}"
bundle_dir="${OPEN_ISLAND_BUNDLE_DIR:-$package_root/$app_name.app}"
zip_path="${OPEN_ISLAND_ZIP_PATH:-$package_root/$app_name.zip}"
dmg_path="${OPEN_ISLAND_DMG_PATH:-$package_root/$app_name.dmg}"
signing_identity="${OPEN_ISLAND_SIGN_IDENTITY:-}"
notary_profile="${OPEN_ISLAND_NOTARY_PROFILE:-}"

brand_script="$repo_root/scripts/generate_brand_icons.py"
entitlements_path="$repo_root/config/packaging/OpenIslandApp.entitlements"

cd "$repo_root"

swift build -c release --product OpenIslandApp
swift build -c release --product OpenIslandHooks
swift build -c release --product OpenIslandSetup

build_bin_dir="$(swift build -c release --show-bin-path)"
app_binary="$build_bin_dir/OpenIslandApp"
hooks_binary="$build_bin_dir/OpenIslandHooks"
setup_binary="$build_bin_dir/OpenIslandSetup"
brand_icon="$repo_root/Assets/Brand/OpenIsland.icns"

python3 "$brand_script"

rm -rf "$bundle_dir" "$zip_path" "$dmg_path"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Helpers" "$bundle_dir/Contents/Resources"

cp "$app_binary" "$bundle_dir/Contents/MacOS/OpenIslandApp"
cp "$hooks_binary" "$bundle_dir/Contents/Helpers/OpenIslandHooks"
cp "$setup_binary" "$bundle_dir/Contents/Helpers/OpenIslandSetup"
cp "$brand_icon" "$bundle_dir/Contents/Resources/OpenIsland.icns"

chmod +x \
    "$bundle_dir/Contents/MacOS/OpenIslandApp" \
    "$bundle_dir/Contents/Helpers/OpenIslandHooks" \
    "$bundle_dir/Contents/Helpers/OpenIslandSetup"

cat > "$bundle_dir/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$app_name</string>
    <key>CFBundleExecutable</key>
    <string>OpenIslandApp</string>
    <key>CFBundleIconFile</key>
    <string>OpenIsland</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_identifier</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$app_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$build_number</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Open Island needs automation access to focus Terminal and iTerm sessions for jump-back.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

plutil -lint "$bundle_dir/Contents/Info.plist" >/dev/null

if [[ -n "$signing_identity" ]]; then
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$signing_identity" \
        "$bundle_dir/Contents/Helpers/OpenIslandHooks"

    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$signing_identity" \
        "$bundle_dir/Contents/Helpers/OpenIslandSetup"

    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "$entitlements_path" \
        --sign "$signing_identity" \
        "$bundle_dir"

    codesign --verify --deep --strict --verbose=2 "$bundle_dir"
fi

ditto -c -k --keepParent "$bundle_dir" "$zip_path"

# --- DMG creation ---
dmg_staging="$package_root/dmg-staging"
rm -rf "$dmg_staging"
mkdir -p "$dmg_staging"
cp -R "$bundle_dir" "$dmg_staging/"
ln -s /Applications "$dmg_staging/Applications"

hdiutil create \
    -volname "$app_name" \
    -srcfolder "$dmg_staging" \
    -ov \
    -format UDZO \
    "$dmg_path"

rm -rf "$dmg_staging"

if [[ -n "$signing_identity" && -n "$notary_profile" ]]; then
    xcrun notarytool submit "$zip_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple -v "$bundle_dir"
    rm -f "$zip_path"
    ditto -c -k --keepParent "$bundle_dir" "$zip_path"

    xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple -v "$dmg_path"
fi

echo "Bundle: $bundle_dir"
echo "Archive: $zip_path"
echo "DMG: $dmg_path"
if [[ -n "$signing_identity" ]]; then
    echo "Signed with identity: $signing_identity"
else
    echo "No signing identity configured; produced an unsigned local bundle."
fi

if [[ -n "$notary_profile" ]]; then
    echo "Notary profile: $notary_profile"
fi
