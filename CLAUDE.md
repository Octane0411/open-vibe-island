# CLAUDE.md

## Project

Open Island — native macOS companion for AI coding agents. Sits in the notch / top bar, monitors local sessions, surfaces permission and question events, and jumps back to the right terminal/IDE. Local-first, no server.

- **Target product** (closed-source baseline): https://vibeisland.app/
- **OSS reference** (design ideas only, not a spec): https://github.com/farouqaldori/claude-island

## Architecture

One Swift package (`OpenIsland`), four targets:

- **OpenIslandApp** — SwiftUI + AppKit shell. `AppModel` owns state.
- **OpenIslandCore** — Models, bridge transport (Unix socket, NDJSON), hook installers, session discovery & registry.
- **OpenIslandHooks** — CLI invoked by agent hooks. Forwards stdin payload → bridge.
- **OpenIslandSetup** — Installer CLI for agent config files.

Data flow: `agent hook → OpenIslandHooks (stdin) → Unix socket → BridgeServer → AppModel → UI`. On launch: registry restore → JSONL transcript discovery → reconcile with active processes → live bridge.

Requires macOS 14+, Swift 6.2.

## Build & run

```bash
swift build
swift test
swift run OpenIslandApp                            # canonical dev runtime
swift build -c release --product OpenIslandHooks
```

For Xcode: open `Package.swift`.

## Dev app (Open Island Dev.app)

`~/Applications/Open Island Dev.app` is a wrapper around the repo build, not a separate product.

- **Launch**: `zsh scripts/launch-dev-app.sh` — never just `open -na`, the bundle goes stale.
- **One-time signing**: `zsh scripts/setup-dev-signing.sh` — without this every rebuild changes cdhash and silently invalidates TCC grants (Accessibility, Automation). Required for any AX-touching feature (precision jump, keystroke/menu injection).
- `scripts/harness.sh smoke` / `scripts/smoke-dev-app.sh` are for deterministic harness runs only.

## Workflow

- **Never edit in the main worktree.** Use `EnterWorktree` (preferred) or `git worktree add`, branched off latest local `main`.
- Branch name matches topic: `feat/<topic>`, `fix/<topic>`. One coherent change per round.
- `main` is protected — direct push is rejected. All changes ship via PR **targeting `main`**. No chain PRs (A → B → main) — wait for the dependency to merge, then rebase.
- Conventional commit messages (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`). Never `--amend` unless asked.
- After changes: run the matching verification (`swift build` / `swift test` / manual). If no check exists, say so in the summary and still commit.
- Never `git reset --hard`, force-push, or overwrite user changes without explicit approval. If unexpected state appears, inspect — don't bulldoze.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues on this fork repo via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role triage vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Scope guardrails

Current support matrix (agents / terminals / IDEs) lives in `README.md` — that's the single source of truth, keep it accurate at release time.

The project is past MVP and welcomes new ideas and creative directions, but the following stay off-limits without an explicit ask:

- Analytics or telemetry SDKs (Mixpanel etc.)
- Window-manager dependencies (`yabai` etc.)
- Claude-only assumptions that weaken the multi-agent model
- Anything that breaks local-first (remote-server dependencies, cloud-only paths)

## Release

- Triggered by pushing a `v*` tag to `main`. CI builds, signs, notarizes, publishes the DMG. Don't create the GitHub release manually — edit the draft CI produces.
- Before tagging: `git fetch origin main` and review every merged PR since the last tag. Don't trust memory.
- Bilingual required (English + 简体中文). Template: `.github/RELEASE_TEMPLATE.md`. Entry format: `- **Category**: English (#PR)\n  中文 (#PR)`. External contributors get `— Thanks @user` on the English line.
- Title: `Open Island vX.Y.Z — Short English Title`. Installation section bilingual.

## Conventions

- `SessionState.apply(_:)` is the single source of truth for session mutations.
- Bridge protocol: newline-delimited JSON envelopes (`BridgeCodec`).
- All models `Sendable` + `Codable`.
- Hooks **fail open** — if app/bridge is down, the agent runs unchanged.
- Native macOS APIs over cross-platform abstractions. Small end-to-end slices over speculative scaffolding.

## Key files

- `Sources/OpenIslandApp/AppModel.swift` — central state, session management, bridge lifecycle
- `Sources/OpenIslandCore/SessionState.swift` — pure reducer
- `Sources/OpenIslandCore/AgentEvent.swift` — event enum driving all transitions
- `Sources/OpenIslandCore/BridgeTransport.swift` + `BridgeServer.swift` — socket protocol & dispatch
- `Sources/OpenIslandCore/{Claude,Codex,Gemini,Kimi,Cursor}Hooks.swift` etc. — per-agent hook payload models
- `Sources/OpenIslandHooks/main.swift` — hook CLI entry
- `docs/product.md`, `docs/architecture.md`, `AGENTS.md` — design / working-agreement docs
