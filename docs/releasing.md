# Releasing

How to cut a new GitHub release for Agent Deck.

## Versioning

Follow [Semantic Versioning](https://semver.org/):

- **Patch** (0.1.x): bug fixes, doc updates, small improvements
- **Minor** (0.x.0): new features, non-breaking changes
- **Major** (x.0.0): breaking changes

## Checklist

1. **Confirm target**: ensure all intended changes are merged to `main`.
2. **Build & package**:
   ```bash
   git checkout main && git pull
   AGENT_DECK_VERSION=<version> \
   AGENT_DECK_EDDSA_PUBLIC_KEY="<your-public-key>" \
   zsh scripts/package-app.sh
   ```
   This produces `output/package/Agent Deck.dmg` and `output/package/Agent Deck.zip`.
3. **Sign the update zip with EdDSA** (for Sparkle auto-update):
   ```bash
   .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/bin/sign_update \
     "output/package/Agent Deck.zip"
   ```
   Copy the `sparkle:edSignature` and `length` values for the appcast entry.
4. **Update `appcast.xml`** in the repo root — add a new `<item>` entry with the version, download URL, EdDSA signature, and length. See the "Sparkle Appcast" section below.
5. **Commit and push** the updated `appcast.xml` to `main`.
6. **Create the release**:
   ```bash
   gh release create v<version> \
     "output/package/Agent Deck.dmg#Open.Island.dmg" \
     "output/package/Agent Deck.zip#Open.Island.zip" \
     --target main \
     --title "Agent Deck v<version> — <Title>" \
     --notes-file release-notes.md
   ```
7. **Verify**: open the release page and confirm assets are downloadable.

## Release Notes Format

All release notes **must be bilingual** (English + Simplified Chinese). Use the following template:

```markdown
## Agent Deck v<version> — <Title>

### Changes since v<prev> | 自 v<prev> 以来的变更

- <emoji> **Category**: English description (#PR)
  中文描述 (#PR)

---

## Installation | 安装说明

<< See "Installation Section" below >>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### Change categories

| Emoji | Category | When to use |
|-------|----------|-------------|
| ✨ | Feature | New user-facing functionality |
| 🐛 | Fix | Bug fix |
| 📸/📋 | Docs | Documentation changes |
| ♻️ | Refactor | Code restructuring |
| 🏗️ | Infra | Build, CI, packaging changes |

## Installation Section

**Include in every release** until code signing is in place. Remove once we ship a signed & notarized build.

```markdown
## Installation | 安装说明

1. Download **Agent Deck.dmg**, open it, and drag **Agent Deck** to **Applications**.
   下载 **Agent Deck.dmg**，打开后将 **Agent Deck** 拖入 **Applications**。

2. Since this is an unsigned app, macOS will show **"Agent Deck is damaged"** when you try to open it. Run this command in Terminal to fix it:
   由于应用未签名，macOS 会提示**「"Agent Deck"已损坏」**。请在终端中执行以下命令：

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Agent Deck.app"
   ```

3. Requirements: **macOS 14+**, **Apple Silicon** (M1/M2/M3/M4/M5).
   系统要求：**macOS 14+**，**Apple Silicon**（M1/M2/M3/M4/M5）。

> ⚠️ **Note**: This is an unsigned early-access build. Code signing and notarization will be added once our Apple Developer account is approved.
> **注意**：这是未签名的早期测试版。代码签名和 Apple 公证将在 Developer 账号审核通过后添加。
```

## Assets

Every release ships two artifacts:

| File | Purpose |
|------|---------|
| `Agent Deck.dmg` | Styled disk image with drag-to-Applications |
| `Agent Deck.zip` | Plain zip for automation / CI downloads |

## Sparkle Appcast

The file `appcast.xml` in the repo root is the Sparkle update feed. It is served via GitHub raw content at:

```
https://raw.githubusercontent.com/Octane0411/agent-deck/main/appcast.xml
```

Each release needs a new `<item>` entry. Template:

```xml
<item>
    <title>Version X.Y.Z</title>
    <sparkle:version>BUILD_NUMBER</sparkle:version>
    <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <pubDate>Thu, 06 Apr 2026 00:00:00 +0000</pubDate>
    <enclosure
        url="https://github.com/Octane0411/agent-deck/releases/download/vX.Y.Z/Open.Island.zip"
        type="application/octet-stream"
        sparkle:edSignature="PASTE_SIGNATURE_HERE"
        length="PASTE_LENGTH_HERE"
    />
</item>
```

### EdDSA Key Setup (one-time)

Generate a key pair with Sparkle's tool:

```bash
.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/bin/generate_keys
```

This stores the private key in your macOS Keychain and prints the public key. Save the public key — it goes into `AGENT_DECK_EDDSA_PUBLIC_KEY` env var during packaging and into `SUPublicEDKey` in Info.plist.

## Signing (future)

When `AGENT_DECK_SIGN_IDENTITY` is set, `package-app.sh` handles codesign + notarization automatically. At that point:

1. Remove the "Installation Section" Gatekeeper instructions from future release notes.
2. Add `--verify` step to the checklist.

See [packaging.md](packaging.md) for signing details.
