# Open Island

Native macOS companion for AI coding agents — lives in the notch / top bar, tracks your local agent sessions, and jumps you back to the right terminal or IDE. Open-source, local-first, no server.

## Requirements

- macOS 14+
- Swift 6.2 (Xcode)

## Build & run

Canonical dev runtime — build and launch the app straight from the package:

```bash
swift build                    # compile all targets
swift test                     # run the test suite
swift run OpenIslandApp        # build + launch the app
```

Or open it in Xcode and hit **Run**:

```bash
open Package.swift
```

Run the full local check suite — lint, docs, tests, and build:

```bash
zsh scripts/harness.sh ci
```

## Install to /Applications

Package a standalone `Open Island.app` and move it into `/Applications`:

```bash
zsh scripts/package-app.sh                          # builds output/package/Open Island.app
mv "output/package/Open Island.app" /Applications/  # remove the old copy first when reinstalling
```

Then launch it from Spotlight or the Applications folder — or drag `output/package/Open Island.app` onto **Applications** in Finder.

`package-app.sh` builds `OpenIslandApp`, `OpenIslandHooks`, and `OpenIslandSetup` in release mode, embeds the helper binaries in the bundle, and also writes `output/package/Open Island.zip`.

### "Open Island is damaged and can't be opened"

Gatekeeper shows this for an unsigned local build. Clear the quarantine flag (dev use only):

```bash
xattr -dr com.apple.quarantine "/Applications/Open Island.app"
```

Or right-click the app → **Open** → **Open** to bypass it once. For signing and notarization, see [docs/packaging.md](docs/packaging.md).

## On first launch

Open Island auto-discovers your active agent sessions and starts the live bridge. Install the per-agent hooks from the in-app **Settings** window.

## More

Repository map, architecture, and deeper docs: [docs/index.md](docs/index.md).
