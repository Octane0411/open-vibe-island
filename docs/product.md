# Product Scope

## Problem

Agent runtimes, local models, frontier models, terminals, and knowledge stores expose fragmented state and controls. Operators need one local-first control plane that can monitor and direct individual sessions today, then schedule, supervise, and explain multi-agent graphs without hiding execution behind provider-specific interfaces.

## Target User

- macOS developers using terminal-based coding agents daily
- Users running more than one agent or more than one terminal session
- Users orchestrating local and frontier models across research and engineering workflows
- Users maintaining a local knowledge base such as an Obsidian vault
- Users who care about low latency, native behavior, and open-source transparency

## Product Principles

- **Open source** — all code is public, all contributions are AI-produced
- **Local first** — no hosted control-plane dependency, no required account, no product analytics
- **Native macOS** — SwiftUI + AppKit, not a web wrapper
- **Capability first** — orchestration behavior is independent of project or provider names
- **Observable by design** — state transitions, tools, metrics, failures, retries, and handoffs are inspectable
- **One control plane** — native app, terminal, voice, and model clients share one state and command path
- **Knowledge under user control** — durable context and outputs remain in user-owned local storage
- **Fail open** — if the app or bridge is unavailable, agents keep running unchanged

## Supported Code Agents

| Agent | Status | Notes |
|---|---|---|
| **Claude Code** | Supported | Hook integration, JSONL session discovery, status line bridge, usage tracking |
| **Codex** | Supported | Full hook integration (SessionStart, UserPromptSubmit, Stop), usage tracking |
| **OpenCode** | Supported | JS plugin integration, permission/question flows, process detection |
| **Qoder** | Supported | Claude Code fork — same hook format, config at `~/.qoder/settings.json` |
| **Qwen Code** | Supported | Claude Code fork — same hook format, config at `~/.qwen/settings.json` |
| **Factory** | Supported | Claude Code fork — same hook format, config at `~/.factory/settings.json` |
| **CodeBuddy** | Supported | Claude Code fork — same hook format, config at `~/.codebuddy/settings.json` |
| **Gemini CLI** | Supported | Hook integration (`SessionStart`, `BeforeAgent`, `AfterAgent`, `SessionEnd`, `Notification`), session tracking, terminal jump metadata, completion-card compatibility handling |
| **Kimi CLI** | Supported | Hook integration via `~/.kimi/config.toml` `[[hooks]]` (Moonshot AI). Kimi's hook payload is byte-compatible with Claude Code, so runtime reuses the Claude decode path; a dedicated TOML installer preserves user-authored hooks |

## Supported Terminals

| Terminal | Status | Notes |
|---|---|---|
| **Terminal.app** | Full Support | Jump-back with TTY targeting |
| **Ghostty** | Full Support | Jump-back with ID matching |
| **cmux** | Full Support | Jump-back via Unix socket API |
| **Kaku** | Full Support | Jump-back via CLI pane targeting |
| **WezTerm** | Full Support | Jump-back via CLI pane targeting |
| **iTerm2** | Full Support | Jump-back with session ID / TTY matching |
| **tmux** (multiplexer) | Full Support | Jump-back with session/window/pane targeting |
| **Warp** | Planned | Fallback detection only |

## Features

- **Notch overlay** — sits in the notch area on notch Macs, falls back to a compact top-center bar on external displays or non-notch Macs
- **Settings** — hook install/uninstall, usage dashboard, General, Display, Sound, Shortcuts, Lab, About
- **Notification mode** — auto-height panel for permission requests and session events
- **Notification sounds** — configurable system sounds with mute toggle
- **i18n** — English and Simplified Chinese
- **Session discovery** — auto-discover from local transcripts, persist across launches
- **Process discovery** — match active agents via `ps`/`lsof`
- **Session observability** — normalized event timelines and aggregate activity metrics
- **Active-session hygiene** — live surfaces exclude idle, completed, ended, and stale desktop threads
- **DMG packaging** — signing, notarization, GitHub Actions release workflow
- **Auto-update** — Sparkle-based automatic updates with appcast

## Success Criteria

- Agent events appear in the overlay with low latency
- Live surfaces never show a session solely because its host application is running
- Operators can explain session state from its timeline and metrics
- Approval and answer actions round-trip back to the source process
- The app can restore focus to the owning terminal window reliably
- Idle resource usage remains low enough for all-day background use

## Future Directions

- Full AgentPeek-class inspection, interaction, usage, notification, widget, board, and operator surfaces
- Declarative graph orchestration with typed handoffs, scheduling, budgets, retries, and checkpoints
- Concurrent local Qwen execution with frontier-model routing and evaluation
- Evidence-preserving web research and compendium production
- Obsidian publishing, retrieval, provenance, and context compilation
- A unified terminal API for sessions, graphs, logs, metrics, approvals, artifacts, and memory

The active design and delivery sequence lives in
[the capability-first orchestration plan](./exec-plans/active/2026-07-19-capability-first-orchestration-control-plane.md).
