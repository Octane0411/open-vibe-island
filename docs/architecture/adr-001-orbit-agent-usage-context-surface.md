# ADR-001: Make agent attention primary and usage/context evidence secondary

**Status:** Accepted
**Date:** 2026-07-26
**Deciders:** Austin Wise and Orbit maintainers

## Context

Orbit already owns one native macOS notch panel, agent/session discovery, approval and question flows, terminal jump-back, usage snapshots for Claude and Codex, immutable bounded receipts, and a metadata-only context budget model. The next product stage combines four reference roles:

- Open Island GPLv3 is the implementation base.
- Vibe Island is an observable behavior and polish reference only.
- CodexBar is a usage-visibility capability reference.
- Headroom and headroom-desktop are context-efficiency capability references subject to their licenses.

A notch has little space. Giving equal weight to sessions, quotas, savings, setup notices, and controls would turn it into a dashboard and obscure the urgent question: **what needs the user's attention now?**

## Decision

Orbit will use an **active-agent-first hierarchy**.

1. The compact pill shows the highest-priority agent state and task first.
2. Usage pressure and context savings appear as quiet secondary indicators only when trustworthy.
3. The expanded surface shows one primary session at a time, followed by provider usage and context evidence.
4. Attention arbitration is deterministic:
   `approval/question > error > active work > unread completion > idle`.
5. Every observed value carries a truth state: `live`, `inferred`, `stale`, or `unavailable`.
6. Context savings report estimated retained and omitted tokens, the source event, and confidence. Dollar savings appear only when authoritative token counts and versioned provider pricing are both available.
7. Raw prompts, transcripts, commands, file contents, credentials, tokens, private endpoints, and provider secrets never enter receipts, screenshots, or usage/context projections.
8. If a provider or context source is unavailable, agent execution continues unchanged and Orbit displays an honest degraded state.
9. Orbit owns the unified approval inbox, provider-neutral presentation, user decision capture, delivery status, and immutable audit receipt. The originating adapter and agent retain enforcement authority.
10. Allow-once is the default positive action. Broader scopes appear only when the originating provider explicitly supports them. Timeout, stale correlation, cancellation, disconnect, or delivery failure never becomes allow.
11. T3 Code is an optional adapter investigation only until a public documented interface and compatible license are verified; Orbit cannot depend on it.

## Options considered

### A. Active-agent-first surface — selected

**Pros**
- Answers the user's immediate question within two seconds.
- Fits the notch's constrained geometry.
- Reuses existing session and approval architecture.
- Keeps usage and savings useful without becoming a dashboard.

**Cons**
- Detailed usage requires expansion.
- Requires deterministic arbitration across agents.

### B. Usage-first meter

**Pros**
- Strong quota awareness.
- Familiar to users of menu-bar usage tools.

**Cons**
- Hides urgent approvals and failures.
- Provider coverage is uneven.
- Encourages false precision.

### C. Multi-agent dashboard

**Pros**
- Maximum observability.
- Easy side-by-side comparison.

**Cons**
- Poor fit for notch geometry.
- High cognitive load and idle cost.
- Duplicates terminals and provider dashboards.

## Consequences

### Easier

- Users can identify the active agent, task, and required action quickly.
- Accessibility has one predictable reading and focus order.
- Provider gaps can be represented honestly.
- Context-efficiency claims remain auditable.

### Harder

- Orbit needs a normalization layer for heterogeneous usage sources.
- Attention arbitration and stale-state handling require focused tests.
- The expanded layout must reveal detail progressively.

## Boundaries

- Orbit does not become a router, shell, agent loop, provider credential manager, billing system, or hook-policy owner.
- Orbit does not become a hidden provider-independent enforcement authority; it brokers decisions back to the source adapter and records acknowledgement.
- This decision does not add slash commands, skill/plugin/tool discovery, or M4/M1 infrastructure.
- Vibe Island branding, assets, binaries, source, and undocumented internals are excluded.

## Verification

- Unit tests for arbitration, truth state, usage normalization, and context evidence.
- Runtime captures for idle, running, approval, question, completion, error, stale usage, and unavailable usage.
- Keyboard and VoiceOver audit.
- Reduce Motion and Reduce Transparency captures.
- Secret-value scan of fixtures, receipts, logs, and screenshots.

## Supersedes

The product direction in `docs/exec-plans/active/2026-07-26-orbit-agent-command-surface-goal.md` is superseded. Its history is retained, but it is not an active implementation contract.
