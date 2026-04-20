# Notchi Integration Notes

Reviewed on 2026-04-02.

## Why This Matters

[`notchi`](https://github.com/sk-ruban/notchi) is a strong adjacent reference for Agent Deck:

- it proves there is real interest in a native macOS notch companion for coding agents
- it already uses the same local-first shape we want: hooks, Unix socket transport, per-session state, native Swift UI
- it shows which parts users notice first: instant liveliness, low-friction setup, and clear session presence

Agent Deck should learn from that execution without collapsing into a Claude-specific mascot app.

## What Notchi Gets Right

Based on the public README, release notes, and current source tree:

- Hook installation is automatic and reversible.
- The app receives local events over a Unix socket.
- Session state is richer than single-event status because it also syncs transcript activity.
- Multiple concurrent sessions are visible at once.
- The compact notch view is ambient, while the expanded panel carries detail.

That is a useful product pattern for Agent Deck:

1. ambient awareness in the notch
2. actionable detail on expand
3. local transport and setup automation underneath

## Where Agent Deck Should Differ

Notchi is optimized for Claude Code presence and delight. Agent Deck should stay optimized for control.

Agent Deck should keep these distinctions:

- Tool-agnostic core event model instead of a Claude-only data model.
- Approval and question flows as first-class actions, not just passive observation.
- Jump-back to terminal/editor context as a core feature.
- Support for non-notch and external-display layouts.
- Avoid coupling the core product to provider-specific quota APIs, sentiment analysis, or sound-driven personality.

## Concrete Ways To Combine The Ideas

### 1. Borrow the Hook Installer Pattern

Notchi auto-writes hook configuration into the tool's settings and installs a bundled script.

Agent Deck already has the beginning of the Codex side:

- [Sources/AgentDeckCore/CodexHooks.swift](/Users/wangruobing/Personal/agent-deck/Sources/AgentDeckCore/CodexHooks.swift)
- [Sources/AgentDeckHooks/main.swift](/Users/wangruobing/Personal/agent-deck/Sources/AgentDeckHooks/main.swift)

The next step is to add a native installer that:

- detects Codex config presence
- installs the `AgentDeckHooks` executable or a thin wrapper script
- patches the relevant hook entries safely
- can report installed / missing / broken status in the app

This is the cleanest immediate overlap with Notchi.

### 2. Enrich Sessions Beyond Raw Hook Events

Notchi does not rely only on incoming hook payloads. It also watches transcript-derived activity to make sessions feel alive and current.

Agent Deck should do a control-oriented version of that:

- use `transcriptPath` from Codex hook payloads when available
- tail or parse recent transcript content after `userPromptSubmit` and `stop`
- extract better summaries for the island and the control panel
- retain the current shared event model instead of leaking transcript-specific details into the UI layer

This would make the current summaries in the bridge meaningfully better without changing the transport contract.

### 3. Add an Ambient "Island Presence" Layer

The best visual idea in Notchi is not the mascot itself. It is the fact that multiple active sessions are visible simultaneously in the collapsed or semi-collapsed state.

Agent Deck can adopt that idea in a more neutral form:

- one compact presence marker per active session
- phase-driven motion or icon treatment for running / waiting / blocked / completed
- keep the expanded view focused on approvals, questions, and jump targets

In other words: borrow the multi-session island metaphor, not the Claude pet identity.

### 4. Keep the Bridge Generic Enough for Future Adapters

Notchi demonstrates that a narrow first integration is enough to ship. Agent Deck should still keep its bridge generic so Claude Code or other agents can be added later as adapters.

The current shared model and bridge transport already point in the right direction:

- [Sources/AgentDeckCore/AgentEvent.swift](/Users/wangruobing/Personal/agent-deck/Sources/AgentDeckCore/AgentEvent.swift)
- [Sources/AgentDeckCore/BridgeTransport.swift](/Users/wangruobing/Personal/agent-deck/Sources/AgentDeckCore/BridgeTransport.swift)
- [Sources/AgentDeckCore/SessionState.swift](/Users/wangruobing/Personal/agent-deck/Sources/AgentDeckCore/SessionState.swift)

That should remain the center of gravity.

## Recommended Next Slice

The most defensible next implementation round is:

1. add a `CodexHookInstaller` that safely installs and verifies local Codex hooks
2. expose hook installation state in the app UI
3. add transcript-based summary enrichment using `transcriptPath`

That would capture the highest-leverage lessons from Notchi while staying aligned with Agent Deck's stated product direction.

## Things To Explicitly Not Copy Yet

- Anthropic usage quota integration
- sentiment or emotion analysis
- Sparkle auto-update work
- sound packs and mascot-specific art pipeline

Those features may help Notchi's product identity, but they are not on Agent Deck's current critical path.

## Source Links

- [`sk-ruban/notchi` repository](https://github.com/sk-ruban/notchi)
- [`notchi` README](https://github.com/sk-ruban/notchi/blob/main/README.md)
- [`notchi` 1.0.3 release notes](https://github.com/sk-ruban/notchi/blob/main/docs/release-notes/1.0.3.md)
