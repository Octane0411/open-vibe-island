# Packaging

This repository can now produce a local macOS app bundle from the Swift package without requiring an Xcode project archive.

## Current Shape

- `zsh scripts/package-app.sh` builds `AgentDeckApp`, `AgentDeckHooks`, and `AgentDeckSetup` in release mode.
- The script creates `output/package/Agent Deck.app`.
- The bundle embeds helper binaries inside `Contents/Helpers/` so the app can still locate `AgentDeckHooks` after it leaves the repository checkout.
- The script also creates `output/package/Agent Deck.zip` for local sharing or later notarization.

## Unsigned First

If the machine does not yet have a `Developer ID Application` certificate, the script still works. It produces an unsigned `.app` bundle and `.zip` archive for local inspection.

Check whether signing identities are available with:

```bash
security find-identity -v -p codesigning
```

If that command reports `0 valid identities found`, packaging is limited to unsigned output until the certificate is created in the Apple Developer account and imported into the login keychain.

### "Agent Deck is damaged and can't be opened"

This Gatekeeper error appears when macOS quarantines an unsigned or un-notarized download. There are two workarounds:

**Option 1 — remove quarantine (internal/dev use only):**

```bash
xattr -dr com.apple.quarantine "/Applications/Agent Deck.app"
```

Or right-click the app → **Open** → click **Open** to bypass the block once.

**Option 2 — sign and notarize (required for external distribution):** follow the section below.

## Signing And Notarization

When a signing identity is available, pass it in with environment variables:

```bash
AGENT_DECK_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
zsh scripts/package-app.sh
```

The script signs the helper binaries and app bundle, then also signs the DMG itself (required for notarization). Entitlements are declared in `config/packaging/AgentDeckApp.entitlements`.

If a `notarytool` keychain profile is already stored, the same script notarizes and staples in the correct order (app bundle first so the stapled bundle is embedded in the DMG, then the DMG):

```bash
AGENT_DECK_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
AGENT_DECK_NOTARY_PROFILE="agent-deck-notary" \
zsh scripts/package-app.sh
```

That path expects `xcrun notarytool store-credentials` to have been run ahead of time.

## Optional Overrides

The script accepts these environment variables:

- `AGENT_DECK_APP_NAME`
- `AGENT_DECK_BUNDLE_ID`
- `AGENT_DECK_VERSION`
- `AGENT_DECK_BUILD_NUMBER`
- `AGENT_DECK_PACKAGE_ROOT`
- `AGENT_DECK_BUNDLE_DIR`
- `AGENT_DECK_ZIP_PATH`
- `AGENT_DECK_SIGN_IDENTITY`
- `AGENT_DECK_NOTARY_PROFILE`
