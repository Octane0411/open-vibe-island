# Open Island

Open-source, local-first macOS companion for AI coding agents.  
Shows session state in a notch-aligned overlay (or top bar fallback), handles approvals, and jump-back to terminal/IDE context.

## Quick Start

### Download
- Latest release: https://github.com/Octane0411/open-vibe-island/releases

### Build
```bash
git clone https://github.com/Octane0411/open-vibe-island.git
cd open-vibe-island
open Package.swift
```

Requirements: macOS 14+, Swift 6.2, Xcode.

## Supported (Core)

- Agents: Claude Code, Codex, Cursor, Gemini CLI, Kimi CLI, OpenCode, Qoder, Qwen Code, Factory, CodeBuddy.
- Terminals/IDEs: Terminal.app, Ghostty, iTerm2, WezTerm, Zellij, tmux, cmux, Kaku, VS Code family, JetBrains family.

## Notes About The Notch

- The physical MacBook notch is a hardware cutout (non-display area).
- Open Island does not render inside the notch.
- It renders a notch-aligned overlay around it to create the island effect.

## Fork Changes (This Branch)

### Added

- Labs controls for closed-notch quota display:
  - `Always show LLM quota in closed notch`
  - `Never hide closed-notch quota`
  - Window mode: `All` / `5-hour only` / `Weekly only` / `Closest to 0% used`
  - Value mode: `Used %` or `Remaining % (100→0)`
  - Placement mode: `Right badge` or `Left near glyph`
- Language options in Settings:
  - Added: French, Spanish, German, Italian
  - Added localization bundles: `fr`, `es`, `de`, `it`
- Z.ai GLM hook support:
  - New setup row: `Z.ai GLM`
  - Install/uninstall managed hooks via `~/.zai/settings.json`
  - Hook source mapping: `zai`/`z.ai`/`glm`
  - Session/liveness integration for `zai` process detection

### Modified

- Closed-notch quota feature remains isolated in Labs (default UX unchanged unless enabled).
- Closed-notch usage fallback still reverts to session count when no usage snapshot exists.
- README trimmed to remove non-essential marketing/community blocks.

## Repo Docs

- Architecture: `docs/architecture.md`
- Hooks: `docs/hooks.md`
- Quality: `docs/quality.md`
- Roadmap: `docs/roadmap.md`

## License

GPL v3 (`LICENSE`).
