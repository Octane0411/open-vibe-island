# CLAUDE.md

## What is this project?

Open Island is a native macOS companion app for AI coding agents. It sits in the notch/top-bar area and monitors local agent sessions, surfaces permission requests, answers questions, and provides "jump back" to the correct terminal context. Local-first, no server dependency.

## References

- **Target product**: https://vibeisland.app/ — the commercial product we are building toward feature parity with
- **Reference OSS repo**: https://github.com/farouqaldori/claude-island — open-source implementation we can study for design patterns and ideas

## Architecture

Four targets in one Swift package (`OpenIsland`):

1. **OpenIslandApp** — SwiftUI + AppKit shell. Menu bar extra, overlay panel (notch/top-bar), and control center window. Entry point: `OpenIslandApp.swift` with `AppModel` as the central `@Observable` state owner.
2. **OpenIslandCore** — Shared library. Models (`TrackedSession`, `AgentSession`, `AgentEvent`), bridge transport (Unix socket IPC with JSON line protocol), hook models/installers for both Codex and Claude Code, transcript discovery.
3. **OpenIslandHooks** — Lightweight CLI executable invoked by agent hooks. Reads hook payload from stdin, forwards to app bridge via Unix socket, writes blocking JSON to stdout only when island denies a `PreToolUse`.
4. **OpenIslandSetup** — Installer CLI for managing `~/.codex/config.toml` and `hooks.json`.

## Key data flow

### Codex path
Codex → hooks.json → OpenIslandHooks (stdin/stdout) → Unix socket → BridgeServer → AppModel → UI

### Claude Code path
Claude Code → settings.json hooks → OpenIslandHooks (stdin/stdout) → Unix socket → BridgeServer.handleClaudeHook → AppModel → UI

### Session discovery
`~/.claude/sessions/*.json` is the source of truth for active Claude sessions. Each file contains `pid`, `sessionId`, `cwd`, `startedAt`, `name`. PID liveness checked with `kill(pid, 0)`. Terminal detected by walking PID parent process chain. Transcript JSONL files at `~/.claude/projects/*/‌<sessionId>.jsonl` provide last activity time and metadata. No registry — session files + transcripts are the only data sources.

## Supported scope (narrow by design)

- **Agents**: Codex (fully wired), Claude Code (hook-based integration)
- **Terminals**: Terminal.app, Ghostty, Warp, iTerm, WezTerm, Kaku
- Do NOT expand scope unless explicitly asked

## Build & test

```bash
swift build
swift test
swift run OpenIslandApp                            # run the app
swift build -c release --product OpenIslandHooks   # build hook binary
```

Open `Package.swift` in Xcode for the app target. Requires macOS 14+, Swift 6.2.

## Required Workflow

> **⚠️ NEVER edit files directly in the main worktree.** Use `EnterWorktree` or `git worktree` to work in an isolated copy.

1. Start each round by checking the current repository state with `git status -sb`.
2. **Enter a worktree** before making any edits — use `EnterWorktree` (preferred) or `git worktree add` to create an isolated working copy based on `main`.
3. Read the relevant files before editing. Do not guess repository structure or behavior.
4. Keep each round focused on a single coherent change.
5. After making changes, run the most relevant verification available for that round.
6. Summarize what changed, including any verification gaps.
7. Commit, push to remote, exit the worktree (`ExitWorktree`), and create a PR to merge into `main`.

## Commit Policy

- Every round that modifies files must end with a commit.
- Do not batch unrelated changes into one commit.
- Use conventional-style commit messages: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`.
- Do not amend existing commits unless explicitly requested.
- Create a feature branch (e.g. `fix/<topic>`, `feat/<topic>`) for every independent change. Do not commit directly to `main`.

## Safety Rules

- Never revert or overwrite user changes unless explicitly requested.
- If unexpected changes appear, inspect them and work around them when possible.
- If a conflict makes the task ambiguous or risky, stop and ask before proceeding.
- Never use destructive Git commands such as `git reset --hard` without explicit approval.

## Branching Rules

- `main` is a protected branch (GitHub branch protection enabled). **NEVER commit or push directly to `main`.**
- All changes MUST go through a Pull Request to merge into `main`. Direct pushes are rejected.
- All feature branches must be created from the latest local `main`.
- Each agent or workstream should work on its own branch, named to match the topic (e.g. `feat/<topic>`, `fix/<topic>`).
- Standard flow: **EnterWorktree → develop → commit → push → ExitWorktree → create PR → merge**.
- For parallel Agent sub-tasks, use `Agent(isolation: "worktree")` to give each agent its own isolated copy.
- **All PRs MUST target `main` as base branch.** Never target another feature branch. Chain PRs (A → B → main) are prohibited — they cause silent change loss when merge order is wrong. If work depends on an unmerged branch, wait for it to merge to main first, then rebase.

## App Targets And Naming

- `OpenIslandApp` (via `swift run OpenIslandApp` or the Xcode target) is the canonical development runtime.
- `~/Applications/Open Island Dev.app` is a local bundle wrapper around the repo-built binary, not a separate product.
- When launching `Open Island Dev.app`, refresh the bundle first with `zsh scripts/launch-dev-app.sh` instead of only `open -na` (avoids stale binaries).
- Use `scripts/harness.sh smoke` or `scripts/smoke-dev-app.sh` only for deterministic harness runs.
- `/Applications/Vibe Island.app` and `https://vibeisland.app/` are closed-source reference baselines only — behavior benchmarks, not the development runtime.

## Reference Baselines

- Official product reference: `https://vibeisland.app/`
- On Macs with a built-in notch, the island sits in the notch area; on external displays or non-notch Macs, it falls back to a compact top-center bar.
- Community reference: `https://github.com/farouqaldori/claude-island` — useful for design patterns, not a product spec.
- Do NOT import from `claude-island` unless explicitly asked: analytics (Mixpanel etc.), window-manager scope (`tmux`, `yabai`), Claude-only assumptions that weaken the shared agent model.

## Conventions

- Prefer small end-to-end slices over speculative scaffolding
- Native macOS APIs over cross-platform abstractions
- Hooks fail open — if app/bridge unavailable, agents keep running unchanged
- `SessionStore` is the single owner of all `TrackedSession` state — all mutations go through it
- `~/.claude/sessions/*.json` is the source of truth for active Claude sessions (no registry)
- Bridge protocol uses newline-delimited JSON envelopes (`BridgeCodec`)
- All models are `Sendable` and `Codable`

## Verification

- Run targeted checks that match the change (`swift build`, `swift test`, or manual verification).
- If no automated verification exists yet, state that explicitly in the summary and still commit.

## Important files

- `Sources/OpenIslandApp/AppModel.swift` — Central app state, session management, bridge lifecycle
- `Sources/OpenIslandApp/TerminalSessionAttachmentProbe.swift` — Ghostty/Terminal attachment matching
- `Sources/OpenIslandApp/ActiveAgentProcessDiscovery.swift` — Process discovery via ps/lsof
- `Sources/OpenIslandApp/SessionStore.swift` — Single owner of all TrackedSession state (discovery, hooks, process reconciliation)
- `Sources/OpenIslandCore/TrackedSession.swift` — Session model with ProcessState, TerminalInfo, SessionMetadata, visibility, display name
- `Sources/OpenIslandApp/TrackedSession+Presentation.swift` — UI computed properties for TrackedSession
- `Sources/OpenIslandCore/AgentSession.swift` — Legacy session model (used internally by BridgeServer)
- `Sources/OpenIslandCore/AgentEvent.swift` — Event enum driving hook event processing
- `Sources/OpenIslandCore/BridgeTransport.swift` — Unix socket protocol, codec, envelope types
- `Sources/OpenIslandCore/BridgeServer.swift` — Bridge server handling hook payloads
- `Sources/OpenIslandCore/ClaudeHooks.swift` — Claude Code hook payload model
- `Sources/OpenIslandCore/ClaudeTranscriptDiscovery.swift` — Discovers sessions from `~/.claude/projects/` JSONL files
- `Sources/OpenIslandCore/CodexHooks.swift` — Codex hook payload model
- `Sources/OpenIslandHooks/main.swift` — Hook CLI entry point
- `Sources/OpenIslandApp/OverlayPanelController.swift` — Notch/top-bar overlay window
- `docs/product.md` — Product scope and MVP boundary
- `docs/architecture.md` — System design and engineering decisions
- `AGENTS.md` — Working agreement for agent workflow
