# Architecture

## System Shape

The project is a single Swift package with four targets:

| Target | Role |
|---|---|
| **OpenIslandApp** | SwiftUI + AppKit shell — menu bar extra, overlay panel (notch/top-bar), control center, settings. Entry point: `OpenIslandApp.swift` with `AppModel` as the central `@Observable` state owner. |
| **OpenIslandCore** | Shared library — models (`AgentSession`, `AgentEvent`, `SessionState`), bridge transport (Unix socket IPC with JSON line protocol), hook models/installers, transcript discovery, session persistence/registry. |
| **OpenIslandHooks** | Lightweight CLI executable invoked by agent hooks. Reads hook payload from stdin, forwards to app bridge via Unix socket, writes blocking JSON to stdout only when island denies a `PreToolUse`. |
| **OpenIslandSetup** | Installer CLI for managing `~/.codex/config.toml` and `hooks.json`. |

### Overlay Composition

- Closed-state shell is split by placement mode (`notch` vs `topBar`) to keep mode-specific geometry and chrome isolated.
- Opened-state content remains a single shared rendering path across both modes. Session list, actionable cards, and opened header actions are not duplicated.
- Mode-specific differences in opened state should be limited to small layout tokens (for example header allowance / spacing), not separate content trees.
- Opened header allowance is computed from a single metrics helper (`OverlayClosedShellMetrics.openedHeaderAllowance`) and reused by both modes.

### Presentation Policy

The overlay shape (Dynamic-Island vs. floating pill) is decided by a two-layer model so user preference, physical display capability, and placement geometry each stay in their own pure helper:

| Type | Role |
|---|---|
| `OverlayScreenCapability` | Describes what the screen can host — `.notched` or `.plain`. Derived from `NSScreen.safeAreaInsets`. |
| `OverlayPresentationPolicy` | User-facing setting: `.automaticIslandWhenNotched` (default), `.alwaysIsland`, `.alwaysPill`. Persisted under `overlay.presentation.policy`. |
| `OverlayPresentationMode` | Resolved result: `.island` or `.pill`. Computed from policy + capability by `policy.resolvePresentationMode(screenCapability:)`. |
| `OverlayPlacementMode` | Geometry family: `.notch` or `.topBar`. Computed from policy + capability by `policy.resolvePlacementMode(screenCapability:)`, and drives which closed shell and `OverlayPlacementStrategy` case renders. |

`OverlayScreenSelectionResolver` picks *which* attached display to use from a preferred-screen ID plus the current `NSScreen` list. The resolver is pure and produces a tagged `selectionSummary` (`manual`, `manual missing, auto fallback`, `manual missing, main fallback`, `manual missing, first-display fallback`, `automatic`) used in logs and placement diagnostics so drops can be attributed. Per-display drag anchors for the top-bar pill are persisted by `OverlayPillPositionStore` using `OverlayScreenIdentity` as the key.

## Data Flow

### Hook-based agents (Codex, Claude Code, and forks)

```
Agent
  │  stdin: JSON payload
  ▼
OpenIslandHooks CLI  (--source codex | --source claude | ...)
  │  Unix socket
  ▼
BridgeServer → AppModel → UI
  │  BridgeResponse
  ▼
OpenIslandHooks CLI
  │  stdout: JSON directive (only when a response is needed)
  ▼
Agent
```

### Plugin-based agents (OpenCode)

```
OpenCode → JS plugin (~/.config/opencode/plugins/) → Unix socket → BridgeServer → AppModel → UI
```

### Session discovery (on launch)

1. Restore cached sessions from registry
2. Discover recent JSONL transcripts (`~/.claude/projects/`)
3. Reconcile with active terminal processes
4. Start live bridge

**Fail-open principle**: if the bridge is unavailable, the hook process exits silently without writing to stdout, so the agent continues running unaffected.

## Event Model

The shared `AgentEvent` enum drives all state transitions:

- Session started / updated / completed
- Permission requested
- Question asked
- Tool use (pre/post)
- Subagent lifecycle
- Jump target updated

Each event carries a stable session identifier, agent type, timestamps, and enough metadata to route approvals or focus changes.

## State Management

- `SessionState.apply(_:)` is the single source of truth for session mutations (pure reducer)
- `AppModel` owns all live state and bridge lifecycle
- All models are `Sendable` and `Codable`

## Transport

- Unix domain sockets for app ↔ hook communication
- Newline-delimited JSON envelopes (`BridgeCodec`)
- Bridge server lives inside the app process

## Terminal Jump-Back

Terminal focus restoration is implemented per-terminal:

| Terminal | Strategy |
|---|---|
| Terminal.app | TTY targeting via AppleScript |
| Ghostty | Window ID matching |
| cmux | Unix socket API |
| Kaku | CLI pane targeting |
| WezTerm | CLI pane targeting |
| iTerm2 | AppleScript session/TTY probe |
| tmux (multiplexer) | switch-client → select-window → select-pane |

The hook helper enriches payloads with terminal-local hints (terminal app, TTY, session ID, window title) from environment inspection at hook invocation time.

## Technologies

- SwiftUI for most UI composition
- AppKit for panel behavior, status item control, and activation policy edge cases
- Unix domain sockets for IPC
- JSON event envelopes for debugging and adapter simplicity
- Sparkle for auto-updates

## Engineering Rules

- Preserve clean separation between UI state and transport concerns
- Version the event schema so adapters can evolve safely
- Keep setup reversible when editing third-party tool config files
- Keep the runtime surface bound to real agent state rather than shipping UI-level demo toggles
