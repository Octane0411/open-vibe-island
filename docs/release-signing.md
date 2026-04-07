# Release Signing & Notarization

Open Island releases are code-signed and notarized via GitHub Actions. This document explains how to set up the required secrets.

## Required GitHub Secrets

Go to **Settings → Secrets and variables → Actions** in the repository and add:

| Secret | Description |
|--------|-------------|
| `APPLE_CERTIFICATE_P12` | Base64-encoded Developer ID Application certificate (.p12) |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the .p12 file |
| `APPLE_SIGNING_IDENTITY` | Signing identity string, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_TEAM_ID` | 10-character Apple Developer Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for notarization (generate at appleid.apple.com) |

## How to export the certificate

1. Open **Keychain Access** → **My Certificates**
2. Find your **Developer ID Application** certificate
3. Right-click → **Export** → save as `.p12` with a password
4. Base64-encode it:
   ```bash
   base64 -i Certificates.p12 | pbcopy
   ```
5. Paste the result into the `APPLE_CERTIFICATE_P12` secret

## How to generate an app-specific password

1. Go to [appleid.apple.com](https://appleid.apple.com) → **Sign-In and Security** → **App-Specific Passwords**
2. Generate a new password, label it `open-island-notary`
3. Save it as the `APPLE_APP_SPECIFIC_PASSWORD` secret

## Local signed builds

You can also build signed locally:

```bash
export OPEN_ISLAND_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export OPEN_ISLAND_NOTARY_PROFILE="open-island-notary"
export OPEN_ISLAND_VERSION="0.2.0"

# First, store notarization credentials (one-time):
xcrun notarytool store-credentials "open-island-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "xxxx-xxxx-xxxx-xxxx"

# Then build:
zsh scripts/package-app.sh
```

## Release flow

1. Merge all PRs to `main`
2. Tag the release: `git tag v0.2.0 && git push origin v0.2.0`
3. The `Release` workflow runs automatically — builds, signs, notarizes, and creates a draft GitHub Release
4. Review the draft release and publish it
5. Update `appcast.xml` for Sparkle auto-update
