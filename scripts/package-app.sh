#!/bin/zsh

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Open Island packaging runs only on macOS." >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="${OPEN_ISLAND_APP_NAME:-Open Island}"
bundle_identifier="${OPEN_ISLAND_BUNDLE_ID:-io.github.robinedquist.openisland.dev}"
version="${OPEN_ISLAND_VERSION:-0.1.0}"
build_number="${OPEN_ISLAND_BUILD_NUMBER:-$(git -C "$repo_root" rev-list --count HEAD 2>/dev/null || echo 1)}"
package_root="${OPEN_ISLAND_PACKAGE_ROOT:-$repo_root/output/package}"
bundle_dir="${OPEN_ISLAND_BUNDLE_DIR:-$package_root/$app_name.app}"
zip_path="${OPEN_ISLAND_ZIP_PATH:-$package_root/$app_name.zip}"
dmg_path="${OPEN_ISLAND_DMG_PATH:-$package_root/$app_name.dmg}"
signing_identity="${OPEN_ISLAND_SIGN_IDENTITY:-}"
notary_profile="${OPEN_ISLAND_NOTARY_PROFILE:-}"
build_root="${OPEN_ISLAND_BUILD_ROOT:-$repo_root/.build}"
create_dmg_tool="${OPEN_ISLAND_CREATE_DMG_TOOL:-create-dmg}"
create_dmg="${OPEN_ISLAND_CREATE_DMG:-true}"
if [[ "$create_dmg" != "true" && "$create_dmg" != "false" ]]; then
    echo "OPEN_ISLAND_CREATE_DMG must be true or false." >&2
    exit 1
fi

# Updates remain unavailable until the fork release gate is reviewed and completed.
if [[ "${OPEN_ISLAND_ENABLE_UPDATES:-false}" != "false" || -n "${OPEN_ISLAND_UPDATE_FEED_URL:-}" || -n "${OPEN_ISLAND_EDDSA_PUBLIC_KEY:-}" ]]; then
    echo "Fork updates are disabled. Complete docs/release-signing.md before enabling a channel." >&2
    exit 1
fi
if [[ "${1:-}" == "--verify-configuration" ]]; then
    echo "Development bundle: $bundle_identifier; automatic updates: disabled"
    exit 0
fi
if (( $# > 0 )); then
    echo "Usage: scripts/package-app.sh [--verify-configuration]" >&2
    exit 64
fi

brand_script="$repo_root/scripts/generate_brand_icons.py"
dmg_bg_script="$repo_root/scripts/generate_dmg_background.py"
entitlements_path="$repo_root/config/packaging/OpenIslandApp.entitlements"

cd "$repo_root"

swift_build_flags=(--force-resolved-versions --scratch-path "$build_root")
if [[ -n "${OPEN_ISLAND_SWIFT_CACHE:-}" ]]; then
    swift_build_flags+=(--cache-path "$OPEN_ISLAND_SWIFT_CACHE")
fi
if [[ -n "${OPEN_ISLAND_SWIFT_CONFIG:-}" ]]; then
    swift_build_flags+=(--config-path "$OPEN_ISLAND_SWIFT_CONFIG")
fi
if [[ -n "${OPEN_ISLAND_SWIFT_SECURITY:-}" ]]; then
    swift_build_flags+=(--security-path "$OPEN_ISLAND_SWIFT_SECURITY")
fi
if [[ "$create_dmg" == "true" ]]; then
    tool_version="$("$create_dmg_tool" --version)"
    if [[ "$tool_version" != "create-dmg 1.2.3" ]]; then
        echo "Packaging requires pinned create-dmg 1.2.3 (see CI for its exact revision)." >&2
        exit 1
    fi
fi

arch_flags=()
if [[ "${OPEN_ISLAND_UNIVERSAL:-false}" == "true" ]]; then
    arch_flags=(--arch arm64 --arch x86_64)
fi

swift build "${swift_build_flags[@]}" -c release "${arch_flags[@]}" --product OpenIslandApp
swift build "${swift_build_flags[@]}" -c release "${arch_flags[@]}" --product OpenIslandHooks
swift build "${swift_build_flags[@]}" -c release "${arch_flags[@]}" --product OpenIslandSetup

build_bin_dir="$(swift build "${swift_build_flags[@]}" -c release "${arch_flags[@]}" --show-bin-path)"
app_binary="$build_bin_dir/OpenIslandApp"
hooks_binary="$build_bin_dir/OpenIslandHooks"
setup_binary="$build_bin_dir/OpenIslandSetup"
brand_icon="$repo_root/Assets/Brand/OpenIsland.icns"

# Package the committed brand assets instead of re-rendering them: the icon
# generator rewrites tracked PNGs whenever the local Pillow encodes them
# differently, and the DMG background depends on whichever fonts the machine
# has (see scripts/launch-dev-app.sh). Opt in when the brand source changed.
dmg_background="$repo_root/Assets/Brand/dmg-background.png"
if [[ "${OPEN_ISLAND_REGENERATE_BRAND_ASSETS:-false}" == "true" ]]; then
    python3 -c 'import PIL; assert PIL.__version__ == "11.3.0", "Brand regeneration requires Pillow 11.3.0"'
    python3 "$brand_script"
    python3 "$dmg_bg_script"
else
    for asset in "$brand_icon" "$dmg_background"; do
        if [[ ! -f "$asset" ]]; then
            echo "Missing $asset — run scripts/generate_brand_icons.py and scripts/generate_dmg_background.py, or set OPEN_ISLAND_REGENERATE_BRAND_ASSETS=true" >&2
            exit 1
        fi
    done
fi

# Refuse dangerous destinations before removing previous packaging outputs.
if [[ "$bundle_dir" != *.app || "$zip_path" != *.zip || "$dmg_path" != *.dmg ]]; then
    echo "Bundle/archive destinations must end in .app, .zip, and .dmg." >&2
    exit 1
fi
rm -rf "$bundle_dir" "$zip_path" "$dmg_path"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Helpers" "$bundle_dir/Contents/Resources" "$bundle_dir/Contents/Frameworks"

cp "$app_binary" "$bundle_dir/Contents/MacOS/OpenIslandApp"
cp "$hooks_binary" "$bundle_dir/Contents/Helpers/OpenIslandHooks"
cp "$setup_binary" "$bundle_dir/Contents/Helpers/OpenIslandSetup"
cp "$brand_icon" "$bundle_dir/Contents/Resources/OpenIsland.icns"
cp -R "$repo_root/ThirdPartyLicenses" "$bundle_dir/Contents/Resources/"
{
    git rev-parse HEAD
    if [[ -n "$(git status --porcelain)" ]]; then echo "working-tree: dirty"; else echo "working-tree: clean"; fi
    shasum -a 256 Package.resolved
    xcodebuild -version
    swift --version
    echo "create-dmg: ${tool_version:-not used}; regenerated assets: ${OPEN_ISLAND_REGENERATE_BRAND_ASSETS:-false}"
} > "$bundle_dir/Contents/Resources/build-info.txt"

# Copy Sparkle.framework for auto-update support.
sparkle_framework="$build_root/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
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
    <key>OpenIslandUpdatesEnabled</key>
    <false/>
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
if [[ "${OPEN_ISLAND_PACKAGE_SMOKE:-false}" == "true" ]]; then
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

else
    echo "Desktop smoke test requires OPEN_ISLAND_PACKAGE_SMOKE=true in an isolated test account."
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
# Local ad-hoc packages must also fail verification rather than hiding signing errors.
codesign --verify --deep --strict --verbose=2 "$bundle_dir"

ditto -c -k --keepParent "$bundle_dir" "$zip_path"

# --- Notarize app bundle (before DMG so the stapled bundle goes into the DMG) ---
if [[ -n "$signing_identity" && -n "$notary_profile" ]]; then
    xcrun notarytool submit "$zip_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple -v "$bundle_dir"
    rm -f "$zip_path"
    ditto -c -k --keepParent "$bundle_dir" "$zip_path"
fi

if [[ "$create_dmg" == "true" ]]; then
# --- Styled DMG creation ---
dmg_bg="$repo_root/Assets/Brand/dmg-background@2x.png"

"$create_dmg_tool" \
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

fi

echo "Bundle: $bundle_dir"
echo "Archive: $zip_path"
if [[ "$create_dmg" == "true" ]]; then echo "DMG: $dmg_path"; fi
if [[ -n "$signing_identity" ]]; then
    echo "Signed with identity: $signing_identity"
else
    echo "No Developer ID identity configured; produced an ad-hoc development bundle."
fi

if [[ -n "$notary_profile" ]]; then
    echo "Notary profile: $notary_profile"
fi
