# Releasing

How to cut a new GitHub release for Open Island.

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
   OPEN_ISLAND_VERSION=<version> zsh scripts/package-app.sh
   ```
   This produces `output/package/Open Island.dmg` and `output/package/Open Island.zip`.
3. **Create the release**:
   ```bash
   gh release create v<version> \
     "output/package/Open Island.dmg#Open.Island.dmg" \
     "output/package/Open Island.zip#Open.Island.zip" \
     --target main \
     --title "Open Island v<version> — <Title>" \
     --notes-file release-notes.md
   ```
4. **Verify**: open the release page and confirm assets are downloadable.

## Release Notes Format

All release notes **must be bilingual** (English + Simplified Chinese). Use the following template:

```markdown
## Open Island v<version> — <Title>

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

1. Download **Open Island.dmg**, open it, and drag **Open Island** to **Applications**.
   下载 **Open Island.dmg**，打开后将 **Open Island** 拖入 **Applications**。

2. Since this is an unsigned app, macOS will show **"Open Island is damaged"** when you try to open it. Run this command in Terminal to fix it:
   由于应用未签名，macOS 会提示**「"Open Island"已损坏」**。请在终端中执行以下命令：

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Open Island.app"
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
| `Open Island.dmg` | Styled disk image with drag-to-Applications |
| `Open Island.zip` | Plain zip for automation / CI downloads |

## Signing (future)

When `OPEN_ISLAND_SIGN_IDENTITY` is set, `package-app.sh` handles codesign + notarization automatically. At that point:

1. Remove the "Installation Section" Gatekeeper instructions from future release notes.
2. Add `--verify` step to the checklist.

See [packaging.md](packaging.md) for signing details.
