# NotchTune
<img width="1024" height="1024" alt="app-icon-v6" src="https://github.com/user-attachments/assets/593c9462-70fb-44d1-9967-e8ad9aeef3b1" />

Monitor your agents and music all in one place.

**NotchTune** is a native macOS companion that turns your Mac's notch, or a compact top bar on external displays, into a live control surface for music and terminal-native AI agents. It combines playback controls, agent monitoring, approvals, questions, and session jump-back in one lightweight local app.

## Highlights

- **Dynamic notch switching**: NotchTune moves between Music and Agents automatically, so the island can show the thing that matters now: current playback, active agent work, permission prompts, questions, or recently completed sessions.
- **Music controls**: Control Spotify or Apple Music from the notch, including playback, track details, artwork, progress, shuffle, repeat, love, volume, and quick open actions.
- **Agent monitoring**: Track local coding-agent sessions from the menu bar or notch, including running state, waiting approvals, questions, completions, subagents, and usage summaries.
- **Character personalization**: Choose the island character that fits your setup, including dino, cat, and dog appearances.
- **Notch-aware layouts**: Runs as a real notch surface on MacBook displays and falls back to a clean top-center bar on external or non-notch screens.
- **Local and native**: Built with SwiftUI and AppKit. No Electron shell, no telemetry, and no remote server dependency.

## Supported Integrations

NotchTune currently supports Spotify and Apple Music for playback.

For coding agents, it supports Claude Code, Codex, OpenCode, Gemini CLI, Kimi CLI, Qoder, Qwen Code, Factory, and CodeBuddy through local hooks, transcript discovery, and process matching where available.

Supported terminal jump-back includes Terminal.app, Ghostty, cmux, Kaku, WezTerm, iTerm2, and tmux. Warp support is planned.

## Quick Start

### Install The App

Download the latest `NotchTune.dmg` from [Releases](https://github.com/dw2lam/NotchTune/releases), open it, and drag `NotchTune.app` into Applications.

This release is currently unsigned. If macOS blocks the first launch, right-click `NotchTune.app`, choose **Open**, then confirm the Gatekeeper prompt.

Open NotchTune, go to **Settings → Setup**, and install hooks for the coding agents you use. Grant Accessibility permission if macOS asks; NotchTune uses it to detect terminal windows and jump back to active sessions.

### Run From Source

Clone the repo and run the app locally:

```bash
git clone https://github.com/dw2lam/NotchTune.git
cd NotchTune
zsh scripts/launch-dev-app.sh
```

To build the hook helper used by agent integrations:

```bash
swift build -c release
```

Or open the package in Xcode:

```bash
open Package.swift
```

## Development

This repository is a Swift package with native app, core bridge, hook helper, and setup targets.

The helper scripts are the recommended way to exercise app-bundle behavior locally because they refresh the generated assets, helper binaries, and local dev bundle.

Useful commands:

```bash
swift build
swift test
zsh scripts/launch-dev-app.sh
zsh scripts/package-app.sh
```

## Credits

NotchTune builds on work from:

- [Tuneful](https://github.com/martinfekete10/Tuneful), originally developed by [Martin Fekete](https://github.com/martinfekete10), for native macOS playback controls and interface ideas.
- [Octane0411](https://github.com/Octane0411), for the dynamic notch integration and terminal-native AI tracking foundations that helped shape NotchTune.

## What's Next

More connectors, personalization options, and deeper agent workflows are planned as NotchTune continues to grow into a local-first control surface for music and coding agents.
