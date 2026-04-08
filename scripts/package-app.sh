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
dmg_bg_script="$repo_root/scripts/generate_dmg_background.py"
entitlements_path="$repo_root/config/packaging/OpenIslandApp.entitlements"

cd "$repo_root"

arch_flags=()
if [[ "${OPEN_ISLAND_UNIVERSAL:-false}" == "true" ]]; then
    arch_flags=(--arch arm64 --arch x86_64)
fi

swift build -c release "${arch_flags[@]}" --product OpenIslandApp
swift build -c release "${arch_flags[@]}" --product OpenIslandHooks
swift build -c release "${arch_flags[@]}" --product OpenIslandSetup

build_bin_dir="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"
app_binary="$build_bin_dir/OpenIslandApp"
hooks_binary="$build_bin_dir/OpenIslandHooks"
setup_binary="$build_bin_dir/OpenIslandSetup"
brand_icon="$repo_root/Assets/Brand/OpenIsland.icns"

python3 "$brand_script"
python3 "$dmg_bg_script"

rm -rf "$bundle_dir" "$zip_path" "$dmg_path"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Helpers" "$bundle_dir/Contents/Resources" "$bundle_dir/Contents/Frameworks"

cp "$app_binary" "$bundle_dir/Contents/MacOS/OpenIslandApp"
cp "$hooks_binary" "$bundle_dir/Contents/Helpers/OpenIslandHooks"
cp "$setup_binary" "$bundle_dir/Contents/Helpers/OpenIslandSetup"
cp "$brand_icon" "$bundle_dir/Contents/Resources/OpenIsland.icns"

# Copy Sparkle.framework for auto-update support.
sparkle_framework="$repo_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$sparkle_framework" ]]; then
    cp -R "$sparkle_framework" "$bundle_dir/Contents/Frameworks/"
else
    echo "WARNING: Sparkle.framework not found at $sparkle_framework — run 'swift package resolve' first." >&2
fi

# Copy SPM resource bundle into Contents/Resources/ so the .app root stays
# clean for code signing (no unsealed contents). Our custom
# resource_bundle_accessor.swift searches Bundle.main.resourceURL first.
spm_resource_bundle="$build_bin_dir/OpenIsland_OpenIslandApp.bundle"
if [[ -d "$spm_resource_bundle" ]]; then
    cp -R "$spm_resource_bundle" "$bundle_dir/Contents/Resources/"
else
    echo "WARNING: SPM resource bundle not found at $spm_resource_bundle — app may crash on launch." >&2
fi

chmod +x \
    "$bundle_dir/Contents/MacOS/OpenIslandApp" \
    "$bundle_dir/Contents/Helpers/OpenIslandHooks" \
    "$bundle_dir/Contents/Helpers/OpenIslandSetup"

# Add rpath so the binary can find Sparkle.framework in Contents/Frameworks/.
install_name_tool -add_rpath @loader_path/../Frameworks "$bundle_dir/Contents/MacOS/OpenIslandApp" 2>/dev/null || true

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
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/Octane0411/open-vibe-island/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>${OPEN_ISLAND_EDDSA_PUBLIC_KEY:-3IF8txq9RRNanzE2FNhyGRcwhslTucCcJHpTkpxcgBQ=}</string>
</dict>
</plist>
EOF

plutil -lint "$bundle_dir/Contents/Info.plist" >/dev/null

# --- Verify bundle structure matches what the app expects at runtime ---
verify_errors=0
for required in \
    "Contents/MacOS/OpenIslandApp" \
    "Contents/Helpers/OpenIslandHooks" \
    "Contents/Helpers/OpenIslandSetup" \
    "Contents/Resources/OpenIsland.icns" \
    "Contents/Resources/OpenIsland_OpenIslandApp.bundle" \
; do
    if [[ ! -e "$bundle_dir/$required" ]]; then
        echo "ERROR: missing required file: $required" >&2
        verify_errors=$((verify_errors + 1))
    fi
done

if [[ $verify_errors -gt 0 ]]; then
    echo "Bundle verification failed with $verify_errors error(s)." >&2
    exit 1
fi
echo "Bundle structure verified."

# --- Smoke-test the app outside the repo to catch Bundle.module fallback hacks ---
# SPM's generated resource accessor has a hardcoded fallback to the local .build/
# directory. Running from /tmp ensures the app works without that crutch.
smoke_dir="$(mktemp -d)/smoke-test"
mkdir -p "$smoke_dir"
cp -R "$bundle_dir" "$smoke_dir/"
smoke_app="$smoke_dir/$(basename "$bundle_dir")"
smoke_binary="$smoke_app/Contents/MacOS/OpenIslandApp"
if [[ -x "$smoke_binary" ]]; then
    # Launch and give it a few seconds — if it crashes, the pid disappears.
    "$smoke_binary" &
    smoke_pid=$!
    sleep 3
    if kill -0 "$smoke_pid" 2>/dev/null; then
        kill "$smoke_pid" 2>/dev/null || true
        wait "$smoke_pid" 2>/dev/null || true
        echo "Smoke test passed — app launched successfully outside repo."
    else
        wait "$smoke_pid" 2>/dev/null || true
        echo "ERROR: app crashed when launched outside the repo directory." >&2
        echo "       This likely means Bundle.module cannot find its resource bundle." >&2
        rm -rf "$(dirname "$smoke_dir")"
        exit 1
    fi
    rm -rf "$(dirname "$smoke_dir")"
else
    echo "WARNING: smoke test skipped — binary not found at $smoke_binary" >&2
fi

sparkle_fw="$bundle_dir/Contents/Frameworks/Sparkle.framework"

if [[ -n "$signing_identity" ]]; then
    # Sign nested code objects inside-out: Sparkle internals → helpers → app.

    if [[ -d "$sparkle_fw" ]]; then
        for xpc in "$sparkle_fw"/Versions/B/XPCServices/*.xpc; do
            [[ -d "$xpc" ]] && codesign --force --options runtime --timestamp --sign "$signing_identity" "$xpc"
        done
        [[ -f "$sparkle_fw/Versions/B/Autoupdate" ]] && \
            codesign --force --options runtime --timestamp --sign "$signing_identity" "$sparkle_fw/Versions/B/Autoupdate"
        [[ -d "$sparkle_fw/Versions/B/Updater.app" ]] && \
            codesign --force --options runtime --timestamp --sign "$signing_identity" "$sparkle_fw/Versions/B/Updater.app"
        codesign --force --options runtime --timestamp --sign "$signing_identity" "$sparkle_fw"
    fi

    codesign --force --options runtime --timestamp --sign "$signing_identity" \
        "$bundle_dir/Contents/Helpers/OpenIslandHooks"
    codesign --force --options runtime --timestamp --sign "$signing_identity" \
        "$bundle_dir/Contents/Helpers/OpenIslandSetup"

    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "$entitlements_path" \
        --sign "$signing_identity" \
        "$bundle_dir"

    codesign --verify --deep --strict --verbose=2 "$bundle_dir"
else
    # Ad-hoc sign so macOS accepts the embedded Sparkle.framework.
    if [[ -d "$sparkle_fw" ]]; then
        for xpc in "$sparkle_fw"/Versions/B/XPCServices/*.xpc; do
            [[ -d "$xpc" ]] && codesign --force --sign - "$xpc" 2>/dev/null || true
        done
        codesign --force --sign - "$sparkle_fw" 2>/dev/null || true
    fi
    codesign --force --sign - "$bundle_dir/Contents/Helpers/OpenIslandHooks" 2>/dev/null || true
    codesign --force --sign - "$bundle_dir/Contents/Helpers/OpenIslandSetup" 2>/dev/null || true
    codesign --force --sign - "$bundle_dir" 2>/dev/null || true
fi

ditto -c -k --keepParent "$bundle_dir" "$zip_path"

# --- Notarize app bundle (before DMG so the stapled bundle goes into the DMG) ---
if [[ -n "$signing_identity" && -n "$notary_profile" ]]; then
    xcrun notarytool submit "$zip_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple -v "$bundle_dir"
    rm -f "$zip_path"
    ditto -c -k --keepParent "$bundle_dir" "$zip_path"
fi

# --- Styled DMG creation ---
dmg_bg="$repo_root/Assets/Brand/dmg-background@2x.png"

create-dmg \
    --volname "$app_name" \
    --background "$dmg_bg" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 96 \
    --text-size 13 \
    --icon "$app_name.app" 180 210 \
    --hide-extension "$app_name.app" \
    --app-drop-link 480 210 \
    --no-internet-enable \
    "$dmg_path" \
    "$bundle_dir"

# Sign the DMG itself (required before notarization)
if [[ -n "$signing_identity" ]]; then
    codesign \
        --force \
        --sign "$signing_identity" \
        --timestamp \
        "$dmg_path"
fi

# Notarize and staple the DMG
if [[ -n "$signing_identity" && -n "$notary_profile" ]]; then
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
