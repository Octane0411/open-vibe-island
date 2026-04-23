# Session State Management Refactoring Plan

> Historical design note. This plan predates the current
> `SessionLifecyclePolicy` + `SessionLivenessObservation` model and is kept as
> background context, not as the source of truth for current behavior. See
> [docs/session-lifecycle-policy.md](./session-lifecycle-policy.md) for the
> current lifecycle model.

## 1. Problem Statement

The current session state management is overly complex: a 3-state attachment model (`attached`/`stale`/`detached`) with 6+ reconciliation passes, AppleScript snapshots driving visibility, multi-pass matching, 15-minute grace windows, synthetic session creation, and CWD-based fallback matching. Every new terminal (e.g., cmux) requires patches across multiple code paths.

The reference product achieves the same UX with a much simpler model: sessions map 1:1 to terminal processes. Process running → session visible. Process gone → session gone.

**Core principle: a session IS a running agent process in a terminal. Nothing more.**

## 2. Signal Sources and Their Reliability

### Claude Code Hooks

Claude Code fires hooks at various lifecycle points. However, **`SessionEnd` is NOT a reliable exit signal**:

| Exit method | SessionEnd fires? |
|---|---|
| Ctrl+D | ✅ Yes |
| `/exit` command | ❌ No (confirmed bug, GitHub #17885) |
| Ctrl+C | Uncertain |
| Process crash/kill | No |

Therefore: hooks are reliable for **creation and updates**, but NOT for **removal**.

Available hook events we use:
- `SessionStart` — session begins (reliable for creation)
- `UserPromptSubmit` — user sends a message
- `PreToolUse` / `PostToolUse` — tool execution
- `PermissionRequest` — needs user approval
- `Notification` — agent wants to notify
- `SubagentStart` / `SubagentStop` — subagent lifecycle
- `Stop` — agent finished a turn (fires every turn, NOT session end)
- `SessionEnd` — fires sometimes on exit (unreliable, use as optimization only)

### Codex Hooks

Codex has its own hook system via `hooks.json` with similar lifecycle events. The same reliability concerns apply — process discovery is the only reliable exit detection for Codex as well.

### Process Discovery (`ps` / `lsof`)

Polls every 3 seconds. Detects ALL running agent processes regardless of hook configuration. This is the **only 100% reliable signal for both session existence and session exit**.

Returns per process: tool type, session ID (from open JSONL files), working directory, terminal TTY, terminal app (from process tree).

### Transcript Discovery (`~/.claude/projects/`)

Scans JSONL transcript files on disk. Used for initial session recovery on app launch. Provides historical session data but cannot determine if a process is currently running.

## 3. The New Model

### Source of Truth: Process Discovery

**Process discovery is the authoritative source for session visibility.** Period.

- Process found → session visible
- Process not found → session not visible

Hooks enrich sessions with metadata (prompts, tool status, permissions, etc.) but never determine visibility.

### Session Lifecycle

```
CREATION:
  Hook SessionStart fires     → create session with rich metadata
  OR process discovered       → create session with basic metadata (tool, CWD, TTY)
  (whichever comes first)

UPDATES:
  Hook events                 → update metadata (prompts, tools, permissions, subagents)
  Process discovery           → confirm alive, update TTY if changed

VISIBILITY:
  Process alive               → visible
  OR phase.requiresAttention  → visible (waiting for approval/answer)
  OR isDemoSession            → visible
  Otherwise                   → not visible

REMOVAL:
  Process not found for 2+ consecutive polls (~6 seconds)  → remove from state
  SessionEnd hook             → immediately mark completed (optimization, not required)
```

The "2 consecutive polls" requirement prevents flicker from momentary `ps` gaps.

### State Model Changes

**Remove:**
- `SessionAttachmentState` enum (attached/stale/detached)
- `SessionOrigin` enum (live/demo → replace with `isDemoSession` computed property)
- All grace window constants (120s, 15min, 120s)
- `isAttachedToTerminal` computed property

**Add to `AgentSession`:**
```swift
var isProcessAlive: Bool = false
var processNotSeenCount: Int = 0    // incremented each poll when process not found, reset to 0 when found
```

**New visibility rule (replaces `isAttachedToTerminal`):**
```swift
var isVisibleInIsland: Bool {
    if isDemoSession { return true }
    if phase.requiresAttention { return true }
    if isProcessAlive { return true }
    return false
}
```

## 4. Scope: Both Claude Code and Codex

This refactoring applies to BOTH agent types:

| Aspect | Claude Code | Codex |
|---|---|---|
| Hook creation | `SessionStart` via Claude hooks | Session events via Codex hooks |
| Process detection | `ps` finds `claude` processes | `ps` finds `codex` processes |
| Session ID source | JSONL transcript path or hook payload | JSONL transcript path or hook payload |
| Terminal detection | `CMUX_*` env vars, process tree, hook payload | Same mechanism |
| Transcript discovery | `~/.claude/projects/` JSONL files | `~/.codex/sessions/` JSONL files |

The new model treats both identically: process alive = visible, process gone = gone.

## 5. AppleScript Snapshots: Jump Precision Only

The current system uses Ghostty and Terminal.app AppleScript queries for TWO purposes:
1. **Visibility** — determining if a session is "attached" to a terminal tab
2. **Jump precision** — knowing which exact tab/pane to focus when user clicks "jump"

After refactoring, AppleScript is used ONLY for jump precision (#2). This is extracted into a new `TerminalJumpTargetResolver` that periodically updates jump targets but never affects visibility.

## 6. File Changes

### Delete entirely
- `Sources/OpenIslandApp/TerminalSessionAttachmentProbe.swift` (1170 lines)

### New file
- `Sources/OpenIslandApp/TerminalJumpTargetResolver.swift` (~250 lines) — AppleScript snapshot matching for jump target precision only

### Simplify or delete
- `Sources/OpenIslandCore/ClaudeSessionRegistry.swift` (159 lines) — delete or gut to ~30 lines for pending-interaction-only persistence

### Modify: `Sources/OpenIslandCore/AgentSession.swift`
- Remove: `SessionAttachmentState`, `SessionOrigin`, `attachmentState`, `origin`, `isAttachedToTerminal`
- Add: `isProcessAlive`, `processNotSeenCount`, `isVisibleInIsland`

### Modify: `Sources/OpenIslandCore/SessionState.swift`
- Remove: `reconcileAttachmentStates()`, `reconcileJumpTargets()`, attachment-based counts
- Add: `markProcessAlive()`, `removeSession()`, `removeInvisibleSessions()`

### Modify: `Sources/OpenIslandApp/AppModel.swift` (~450 lines removed)
- Remove: synthetic session infrastructure, `adoptProcessTTYsForClaudeSessions`, `sanitizeCrossToolGhosttyJumpTargets`, `mergeAttachmentState`, `liveAttachmentKey`, complex `displayPriority`
- Rewrite `reconcileSessionAttachments()` (~70 lines → ~30 lines):
  1. Run process discovery
  2. For each session: if process found → `isProcessAlive=true, processNotSeenCount=0`; else → `processNotSeenCount += 1`
  3. `isProcessAlive = processNotSeenCount < 2`
  4. Remove sessions where `!isVisibleInIsland`
  5. Run jump target resolver for Ghostty/Terminal precision
- Rewrite `computeSessionBuckets()` (~35 lines → ~10 lines): filter by `isVisibleInIsland`, sort by attention > running > updatedAt

### Modify: `Sources/OpenIslandCore/BridgeServer.swift`
- Minimal changes. SessionEnd handler can set `phase = .completed` as before. Hooks continue to create and update sessions as they do now.

## 7. Migration Phases

### Phase 1: Add `isProcessAlive` in parallel (LOW RISK, no behavior change)
- Add new fields to `AgentSession`
- Populate from process discovery in `reconcileSessionAttachments()`
- Log: compare old `isAttachedToTerminal` vs new `isProcessAlive` each cycle
- Write `SessionLivenessTests.swift`

### Phase 2: Extract `TerminalJumpTargetResolver` (LOW RISK, no behavior change)
- Move AppleScript snapshot + jump target matching to new focused type
- Old probe stays intact — new type runs in parallel
- Verify jump targets match

### Phase 3: Switch visibility to process liveness (MEDIUM RISK, behavior change)
- `computeSessionBuckets` uses `isVisibleInIsland` instead of `isAttachedToTerminal`
- Stop calling old attachment probe for visibility
- Keep `TerminalJumpTargetResolver` for jump precision
- **Behavior change: sessions disappear within ~6 seconds of process exit**

### Phase 4: Session removal + cleanup (MEDIUM RISK)
- Remove invisible sessions from state entirely
- Remove synthetic session creation — process discovery creates sessions directly
- Remove `adoptProcessTTYsForClaudeSessions`

### Phase 5: Delete dead code (LOW RISK)
- Delete `TerminalSessionAttachmentProbe.swift` (1170 lines)
- Delete or gut `ClaudeSessionRegistry.swift`
- Remove `SessionAttachmentState`, `SessionOrigin` enums
- Clean up tests
- **Net: ~1000 lines removed**

## 8. Verification Plan

### Key Scenarios (both Claude Code AND Codex)
1. Start agent → session appears within 3s
2. Exit agent (Ctrl+D) → session disappears within 6s
3. Exit agent (`/exit`) → session disappears within 6s (process discovery catches it even though SessionEnd doesn't fire)
4. Kill agent (Ctrl+C / kill -9) → session disappears within 6s
5. Jump to Ghostty/Terminal.app/cmux works
6. Permission approval works end-to-end
7. Question answering works
8. Notification fires on completion
9. Subagent shows as parent metadata, not separate session
10. Multiple terminals simultaneously — each has its own session
11. App restart → sessions reappear within 3s via process discovery
12. Demo mode unaffected

### Before/After Comparison (Phase 1-2)
Log old `isAttachedToTerminal` vs new `isProcessAlive` per reconciliation cycle. All discrepancies must be explained.

### Risk Mitigation
- Phase 1-2 are purely additive — zero behavior change, easy rollback
- Phase 3 is the key switch — can revert to Phase 2 if issues found
- Phase 4-5 are cleanup — each independently revertible

## 9. Impact Summary

| Metric | Before | After |
|---|---|---|
| TerminalSessionAttachmentProbe | 1170 lines | 0 (deleted) |
| TerminalJumpTargetResolver (new) | 0 | ~250 lines |
| AppModel session management | ~750 lines | ~300 lines |
| Attachment state values | 3 | 0 (deleted) |
| Grace windows | 3 (120s, 15min, 120s) | 0 |
| Reconciliation passes per cycle | 6+ | 2 |
| Persisted sessions | All (~29) | Only pending-interaction |
| Agents covered | Claude only in some paths | Claude + Codex uniformly |
| **Net lines removed** | | **~1000** |
