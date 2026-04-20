# Claude Lifecycle: Replace ps/lsof Polling with Kernel PID Exit Monitoring

**Status:** Active. Task steps use `- [ ]` checkboxes — update them in place as work lands.

**Goal:** Stop using `ps`/`lsof` polling as an authoritative signal for hook-managed Claude Code session liveness. Replace it with `DispatchSource.makeProcessSource(eventMask: .exit)` anchored to the Claude CLI PID that each hook brings in. Hook events + kernel exit notifications become the only source of truth for live-session lifecycle. Process polling is retained **only** for cold-start discovery of orphan Claude processes that have no hook history.

**Tech Stack:** Swift 6.2, AppKit, Foundation (`Process`, `DispatchSource`, Unix sockets), Observation framework.

**Context / why this is needed:**

The current architecture fails in a very concrete way users have hit in production (see PR #375 for the symptom): when `lsof` transiently returns late or with partial output, `ActiveAgentProcessDiscovery.claudeSnapshot` produces snapshots missing `sessionID` and `transcriptPath`. `ProcessMonitoringCoordinator.reconcileSessionAttachments`'s three-pass matching can't pin those processes to their tracked hook-managed sessions (Pass 3's uniqueness check also gives up when multiple Claude sessions share a workspace). The downstream effects cascade:

1. `sessionIDsWithAliveProcesses` omits real sessions.
2. `SessionState.markProcessLiveness` ticks `processNotSeenCount` and after 2 polls (4 seconds) flips hook-managed sessions to `isSessionEnded = true`. `removeInvisibleSessions` then evicts them.
3. `mergedWithSyntheticClaudeSessions` spawns one synthetic row per unrepresented process, each with `updatedAt = .now`; every subsequent tick refreshes `updatedAt` to now again — hence the "<1m" phantom rows users reported.

The architectural root cause is **double source of truth**: hook events are the authoritative lifecycle signal (they come from Claude itself), but `ps`/`lsof`-driven `markProcessLiveness` is allowed to override them. A less reliable signal is permitted to kill entries that the more reliable signal still considers live.

Prior-art note: other macOS implementations in this space draw the same line — sessions with an active kernel-level PID monitor trust only explicit Stop/SessionEnd hooks or kernel exit events, never time- or poll-based inference; sessions without a PID (hook-only) fall back to looser time thresholds. We are adopting the same discipline.

---

## Target Architecture

```
┌──────────────────────┐    stdin    ┌────────────────────┐  envelope  ┌──────────────────┐
│ Claude CLI (long-    ├────────────►│ OpenIslandHooks    ├───────────►│ BridgeServer     │
│ running process PID) │             │ (short-lived CLI)  │            │                  │
└──────────▲───────────┘             │ reads getppid()    │            │  on sessionStart │
           │                         │ → payload.agentPID │            │  → PIDMonitor    │
           │                         └────────────────────┘            │    .track(pid)   │
           │                                                           │                  │
           │  kernel DispatchSource.makeProcessSource(.exit, pid)      │                  │
           └───────────────────────────────────────────────────────────┤ on .exit         │
                                                                       │  → 5s grace      │
                                                                       │  → dismissSession│
                                                                       └──────────────────┘
```

**Invariants after this refactor:**

- **Live hook-managed Claude session** = `isHookManaged == true` AND `ClaudePIDMonitor` holds a live monitor for its PID, OR the session has never had a PID (legacy hooks / remote SSH). No `ps`/`lsof` polling for these.
- **`SessionState.markProcessLiveness` no longer flips `isSessionEnded = true` for hook-managed Claude sessions.** The reducer path for `isSessionEnded` is either (a) explicit `SessionEnd` hook event, (b) `ClaudePIDMonitor` reports exit + 5s grace elapsed without re-attachment, or (c) cold-start discovery sweep during app launch determines the PID is gone and hook history is stale (> 24h).
- **Synthetic Claude sessions only exist for cold-start discovery** (orphan process seen at launch that never emits a hook). They never overwrite hook-managed sessions, and their `updatedAt` is frozen at first-discovery time — not refreshed on each poll.
- **`ps`/`lsof` is used exclusively for**: (i) cold-start orphan discovery, (ii) workspace/jumpTarget enrichment (terminal app, TTY, tmux), (iii) OpenCode/Cursor/Kimi/Gemini whose hooks don't carry a stable PID path yet. It does **not** decide Claude liveness.

---

## Scope & Non-Goals

**In scope (this plan):**
- Claude Code hook sessions and every Claude-format hook variant that already shares `ClaudeHookPayload` (qoder, qwen, factory, droid, codebuddy, kimi — they all go through the same wire format).
- Removal of the `processNotSeenCount` eviction path for hook-managed Claude sessions.
- Synthetic Claude session isolation (frozen `updatedAt`, creation gated by absence of hook history for the workspace).

**Out of scope (separate future work):**
- Codex session lifecycle (the rollout watcher + Codex.app liveness already works differently; touching it here enlarges blast radius).
- OpenCode, Cursor, Gemini — they don't currently hit this bug and their hook payloads don't carry a PID path; migrating them is a follow-up.
- Reverting PR #375's CWD fallback in `ProcessMonitoringCoordinator`. **PR #375 will be closed without merging** in favour of this refactor, because the fallback is no longer needed once polling no longer evicts sessions.

**Backwards compat stance:**
- Old `OpenIslandHooks` binaries (installed by previous app versions, not re-installed) will continue to send payloads without `agentPID`. The bridge must handle missing `agentPID` gracefully: fall back to hook-only liveness (no PID monitor, session stays alive until explicit `SessionEnd` hook or 30-minute absence timeout). No forced re-install; users get improved behaviour automatically when hooks are refreshed (or the app proactively reinstalls on version bump — existing flow).

---

## Concrete Touch Points

| File | Change |
| --- | --- |
| `Sources/OpenIslandCore/ClaudeHooks.swift` | Add `agentPID: Int32?` to `ClaudeHookPayload` + CodingKey. Populate in `withRuntimeContext` via `getppid()`. |
| `Sources/OpenIslandHooks/OpenIslandHooksCLI.swift` | No code change required — already calls `withRuntimeContext`. Verify path. |
| `Sources/OpenIslandCore/ClaudePIDMonitor.swift` | **New file.** Wraps `DispatchSource.makeProcessSource(eventMask: .exit)`. Owns a `[sessionID: MonitorRecord]` dictionary. Public API: `track(sessionID:pid:onExit:)`, `untrack(sessionID:)`, `isTracking(sessionID:)`, `isAlive(sessionID:)` (via `kill(pid, 0)` sanity check). |
| `Sources/OpenIslandCore/BridgeServer.swift` | In `handleClaudeHook` for `.sessionStart` / `.userPromptSubmit` / `.preToolUse`, if `payload.agentPID` is non-nil and no monitor yet for that sessionID, call `claudePIDMonitor.track(sessionID:pid:onExit:)`. On `.sessionEnd` (explicit), `untrack`. The `onExit` callback posts a new `AgentEvent.claudeProcessExited(sessionID:)` to the reducer after a 5s grace period unless re-attached. |
| `Sources/OpenIslandCore/AgentEvent.swift` | Add `.claudeProcessExited(ClaudeProcessExited)` case with sessionID + timestamp. |
| `Sources/OpenIslandCore/SessionState.swift` | Add reducer branch for `.claudeProcessExited`: set `isSessionEnded = true`, `phase = .completed`. In `markProcessLiveness`, **remove** the `processNotSeenCount >= 2 → isSessionEnded` path for `session.isHookManaged && session.tool == .claudeCode`. Leave it for other hook-managed tools (OpenCode, Cursor, etc.) until they're migrated. |
| `Sources/OpenIslandApp/ProcessMonitoringCoordinator.swift` | Drop the synthetic-session creation for workspaces that have any tracked hook-managed Claude session (regardless of matching success). Freeze synthetic `updatedAt` at first-discovery time (store in a `[identityKey: Date]` first-seen map). Remove PR #375's CWD fallback in `representedClaudeProcessKeys` / `sessionIDsWithAliveProcesses` once the hook-managed eviction path is gone — it becomes redundant. |
| `Sources/OpenIslandApp/AppModel.swift` | Wire `claudePIDMonitor` ownership; hand it to `BridgeServer` at init. On cold-start discovery apply, for each restored session that has a recorded PID in metadata, attempt to rehydrate the monitor (and if `kill(pid, 0)` fails, mark session as ended immediately — the process died while the app was off). |
| `Sources/OpenIslandCore/ClaudeSessionRegistry.swift` / `ClaudeTrackedSessionRecord` | Persist `agentPID: Int32?` alongside transcriptPath so we can rehydrate the PID monitor on startup. |
| `Tests/OpenIslandCoreTests/ClaudePIDMonitorTests.swift` | **New.** Unit-test track/untrack, exit callback, grace period, kill(0) sanity check. Use dummy `sleep` subprocesses to get deterministic PIDs. |
| `Tests/OpenIslandCoreTests/BridgeServerTests.swift` | Add: sessionStart with agentPID registers a monitor; explicit sessionEnd unregisters; simulated process exit triggers `.claudeProcessExited` after grace. |
| `Tests/OpenIslandAppTests/AppModelSessionListTests.swift` | Add: hook-managed Claude session whose process is clearly "not seen by ps" (empty `activeProcesses`) stays alive — no eviction. Remove / rewrite the PR #375 regression tests that assumed `ps`-based aliveness was the driver. |

---

### Task 1: Add `agentPID` to `ClaudeHookPayload`

**Files:**
- Modify: `Sources/OpenIslandCore/ClaudeHooks.swift`

- [ ] **Step 1: Add the property, CodingKey, and init parameter**

  - Declare `public var agentPID: Int32?` alongside the existing runtime-context fields (`terminalApp`, `terminalSessionID`, etc.).
  - Add `case agentPID = "agent_pid"` to `CodingKeys`.
  - Extend the main `init(...)` to accept `agentPID: Int32? = nil`.
  - **Why `Int32`:** macOS `pid_t` is `Int32`. Using `Int32` avoids platform-size surprises when serialized.

- [ ] **Step 2: Populate in `withRuntimeContext`**

  - In the existing `func withRuntimeContext(environment:)` path, after the Warp pane resolution block, add:
    ```swift
    if payload.agentPID == nil {
        payload.agentPID = getppid()
    }
    ```
  - `getppid()` from Darwin returns the parent PID of the current process (`OpenIslandHooks` binary), which is the Claude CLI that spawned the hook. This is the PID we want to monitor.
  - **Do NOT** populate from environment — stdin-invoked hooks don't reliably inherit any PID-identifying env var, and CLAUDE_* envs aren't stable contract.

- [ ] **Step 3: Unit tests**

  - In `Tests/OpenIslandCoreTests/ClaudeHookPayloadTests.swift` (or nearest existing sibling): verify round-trip codec with `agent_pid: 12345`, verify absence is tolerated, verify `withRuntimeContext` populates a positive value when called from the test process.

- [ ] **Step 4: Verify**

  - [ ] `swift build` succeeds.
  - [ ] New codec tests pass.
  - [ ] Existing Claude hook tests still pass.

---

### Task 2: Create `ClaudePIDMonitor`

**Files:**
- Create: `Sources/OpenIslandCore/ClaudePIDMonitor.swift`
- Create: `Tests/OpenIslandCoreTests/ClaudePIDMonitorTests.swift`

- [ ] **Step 1: Implement the monitor**

  Minimal public surface:

  ```swift
  public final class ClaudePIDMonitor: @unchecked Sendable {
      public struct ExitEvent: Sendable {
          public let sessionID: String
          public let pid: Int32
          public let exitedAt: Date
      }

      public init(gracePeriod: TimeInterval = 5.0, queue: DispatchQueue = .global(qos: .utility))

      /// Begins watching `pid`. If already tracking `sessionID` with a different
      /// PID, the previous monitor is cancelled and replaced. If the PID is
      /// already dead at track time, `onExit` fires synchronously on `queue`.
      public func track(sessionID: String, pid: Int32, onExit: @escaping (ExitEvent) -> Void)

      /// Stops watching and cancels any pending grace timer.
      public func untrack(sessionID: String)

      /// Returns true while a monitor is registered.
      public func isTracking(sessionID: String) -> Bool

      /// Returns true if the last-known PID for this session passes `kill(pid, 0)`.
      public func isAlive(sessionID: String) -> Bool
  }
  ```

  Internals:

  - `DispatchSource.makeProcessSource(identifier: pid_t(pid), eventMask: .exit, queue: queue)` per tracked PID.
  - On exit event: start a `DispatchWorkItem` on `queue` with `gracePeriod` delay. If `untrack` is called before it fires (new monitor re-attached during grace), the pending work item is cancelled. If it fires, invoke `onExit`.
  - **Why the 5s grace:** covers `claude --resume`-style restarts and agent self-update flows where the old PID exits but a new PID is about to register for the same sessionID. Without grace, we'd briefly flip the session to ended and then re-create it, which churns the UI.
  - Internal state (`[sessionID: MonitorRecord]`) synchronized on a dedicated serial queue to keep `track`/`untrack`/exit-callback races deterministic.

- [ ] **Step 2: Unit tests**

  - Track a short-lived `/bin/sleep 0.2` subprocess; assert `onExit` fires within `0.2 + gracePeriod + slack` seconds with correct `sessionID`.
  - Track a long-lived `/bin/sleep 10` subprocess; assert `isAlive` is true. Call `untrack`; assert no callback fires even after we kill the process externally.
  - Track, then within the grace window call `track` again with a new PID for the same sessionID; assert exit callback never fires for the first PID.
  - Track a PID that's already dead (spawn then wait); assert `onExit` fires exactly once on the monitor's queue.
  - Test with `gracePeriod: 0` for determinism in CI.

- [ ] **Step 3: Verify**

  - [ ] `swift test --filter ClaudePIDMonitorTests` all green.
  - [ ] No leaked `DispatchSource`s (instruments check or ref-count assertion in teardown).

---

### Task 3: Add `claudeProcessExited` event to `AgentEvent`

**Files:**
- Modify: `Sources/OpenIslandCore/AgentEvent.swift`
- Modify: `Sources/OpenIslandCore/SessionState.swift`

- [ ] **Step 1: Event case**

  Add to `AgentEvent`:

  ```swift
  case claudeProcessExited(ClaudeProcessExited)

  public struct ClaudeProcessExited: Equatable, Codable, Sendable {
      public let sessionID: String
      public let pid: Int32
      public let timestamp: Date
  }
  ```

  Wire format: serialize as a new envelope type `claude_process_exited`. **Not** emitted by hooks — only by the in-app `ClaudePIDMonitor` via `BridgeServer.emit`.

- [ ] **Step 2: Reducer branch**

  In `SessionState.apply(_:)`:

  ```swift
  case let .claudeProcessExited(payload):
      guard var session = sessionsByID[payload.sessionID] else { return }
      // If hook explicitly ended this session already, don't re-process.
      guard !session.isSessionEnded else { return }
      session.isSessionEnded = true
      session.phase = .completed
      session.updatedAt = payload.timestamp
      session.isProcessAlive = false
      upsert(session)
  ```

  Update the exhaustive-switch sites that reference `AgentEvent` cases (there are several `switch event { ... }` blocks in `AppModel.swift`, `BridgeServer.swift`, and `ProcessMonitoringCoordinator.swift`'s `sessionID(for:)`). Add the new case everywhere.

- [ ] **Step 3: Remove ps-based eviction for hook-managed Claude sessions**

  In `SessionState.markProcessLiveness`, locate the hook-managed branch:

  ```swift
  if session.isHookManaged {
      if session.isSessionEnded { continue }
      ...
      if aliveSessionIDs.contains(id) {
          session.processNotSeenCount = 0
      } else {
          session.processNotSeenCount += 1
          if session.processNotSeenCount >= 2 {
              session.isSessionEnded = true
              session.phase = .completed
              changed.insert(id)
          }
      }
      upsert(session)
      continue
  }
  ```

  Change to: for `session.tool == .claudeCode`, never mutate `processNotSeenCount`, never set `isSessionEnded` based on `aliveSessionIDs`. Still reset `processNotSeenCount = 0` when `aliveSessionIDs.contains(id)` (cheap, defensive). Leave the branch intact for `.openCode`, `.cursor`, `.kimiCLI`, `.qoder` etc. — their migrations come later.

  Add a `SessionState` unit test: hook-managed Claude session + `markProcessLiveness(aliveSessionIDs: [])` called 10 times → session remains non-ended.

- [ ] **Step 4: Verify**

  - [ ] `swift build` succeeds (all exhaustive switches updated).
  - [ ] New reducer test + updated `markProcessLiveness` test pass.

---

### Task 4: Bridge integration — track / untrack / emit

**Files:**
- Modify: `Sources/OpenIslandCore/BridgeServer.swift`
- Modify: `Tests/OpenIslandCoreTests/BridgeServerTests.swift` (or create if absent)

- [ ] **Step 1: Own the monitor**

  Add a private `let claudePIDMonitor: ClaudePIDMonitor` to `BridgeServer`. Accept it through `init` with a default `ClaudePIDMonitor()` so tests can inject mocks. Pass an `onExit` closure that, in turn, calls `self.handleClaudeProcessExit(sessionID: pid:)` serialized on the bridge's internal queue.

- [ ] **Step 2: Track on hook events that prove liveness**

  In `handleClaudeHook`, after the subagent filter and before the event emit, add:

  ```swift
  if let pid = payload.agentPID,
     pid > 0,
     payload.agentID == nil,              // parent session only
     payload.hookEventName != .sessionEnd // handled below
  {
      claudePIDMonitor.track(sessionID: payload.sessionID, pid: pid) { [weak self] exit in
          self?.handleClaudeProcessExit(sessionID: exit.sessionID, pid: exit.pid, at: exit.exitedAt)
      }
  }
  ```

  Rationale: any hook event from the parent session with a valid PID re-confirms liveness and lets us re-bind if a previous monitor was lost. `track` is idempotent for the same PID.

- [ ] **Step 3: Untrack on explicit `.sessionEnd`**

  In the `.sessionEnd` branch, immediately after emitting `.sessionCompleted(isSessionEnd: true)`, call `claudePIDMonitor.untrack(sessionID: payload.sessionID)`. The explicit hook is authoritative; the monitor's grace period would add useless latency.

- [ ] **Step 4: `handleClaudeProcessExit`**

  ```swift
  private func handleClaudeProcessExit(sessionID: String, pid: Int32, at exitTime: Date) {
      // If a later hook re-attached a different PID (resume flow), ignore.
      if let current = claudePIDMonitor.currentPID(for: sessionID), current != pid {
          return
      }
      claudePIDMonitor.untrack(sessionID: sessionID)
      emit(.claudeProcessExited(.init(sessionID: sessionID, pid: pid, timestamp: exitTime)))
  }
  ```

  (Requires a `currentPID(for:)` accessor on `ClaudePIDMonitor`.)

- [ ] **Step 5: Tests**

  - sessionStart with `agentPID = <running pid>` → `isTracking(sessionID)` becomes true.
  - sessionEnd → `isTracking(sessionID)` becomes false.
  - Simulated process exit → after grace, `.claudeProcessExited` is visible in the bridge's local state; reducer flips session to `.completed / isSessionEnded`.
  - sessionStart with `agentPID = nil` (legacy hook) → no monitor registered; no crash; existing hook flow unaffected.

- [ ] **Step 6: Verify**

  - [ ] `swift test --filter BridgeServerTests` all green.

---

### Task 5: Persist PID for cross-launch rehydration

**Files:**
- Modify: `Sources/OpenIslandCore/ClaudeSessionRegistry.swift` (and the record type)
- Modify: `Sources/OpenIslandApp/AppModel.swift` / `SessionDiscoveryCoordinator.swift`

- [ ] **Step 1: Record field**

  Add `public var agentPID: Int32?` to `ClaudeTrackedSessionRecord`. Codec via `Codable` default. Old records without the field decode to `nil` — don't break the JSON schema.

- [ ] **Step 2: Populate on persist**

  Wherever `ClaudeTrackedSessionRecord(session:)` is constructed (see `SessionDiscoveryCoordinator.scheduleClaudeSessionPersistence`), pull the agentPID from the session's `claudeMetadata` (Task 6 will add a stash there) or from the bridge's `claudePIDMonitor.currentPID(for:)`.

- [ ] **Step 3: Rehydrate on startup**

  In `applyStartupDiscoveryPayload`, for each restored Claude session:

  - If the record has `agentPID`, call `kill(pid, 0)`:
    - Success → re-track via `BridgeServer.claudePIDMonitor.track`.
    - Failure (`errno == ESRCH`) → emit `.claudeProcessExited` immediately; the process died while the app was off, the session is stale.
  - If the record has no `agentPID` (legacy), do nothing special — the session stays in its restored `.completed` phase and will age out normally.

- [ ] **Step 4: Tests**

  - Record codec round-trip with and without `agentPID`.
  - Startup rehydration: a record whose PID is dead → session becomes `isSessionEnded` synchronously.

- [ ] **Step 5: Verify**

  - [ ] `swift test --filter ClaudeSessionRegistryTests` + startup tests green.

---

### Task 6: Stash agentPID on the session itself

**Files:**
- Modify: `Sources/OpenIslandCore/AgentSession.swift` (or `ClaudeSessionMetadata`)

- [ ] **Step 1: Where to put it**

  Prefer `ClaudeSessionMetadata.agentPID: Int32?` rather than a top-level `AgentSession` field — keeps the core model tool-agnostic. Update `ClaudeSessionMetadata.isEmpty` to not treat a solitary `agentPID` as "empty" (we'd lose it on merge otherwise — see `SessionDiscoveryCoordinator.mergeClaudeMetadata`).

- [ ] **Step 2: Write-through on hook events**

  In `BridgeServer.handleClaudeHook`, when we have `payload.agentPID`, emit an additional `.claudeSessionMetadataUpdated` piggybacking the PID alongside existing fields, OR simpler: stash it in the `sessionStarted` event payload's initial `claudeMetadata`. Pick whichever keeps diffs small — the former is safer because multiple hook paths need to populate it.

- [ ] **Step 3: Tests**

  - `SessionState.apply(.sessionStarted)` with `claudeMetadata.agentPID = 1234` produces a session whose metadata carries the PID.
  - Merge test: a later `.claudeSessionMetadataUpdated` event without PID doesn't blow away an earlier PID (merge preserves).

---

### Task 7: Synthetic Claude session isolation

**Files:**
- Modify: `Sources/OpenIslandApp/ProcessMonitoringCoordinator.swift`

- [ ] **Step 1: Freeze synthetic `updatedAt`**

  Introduce `private var syntheticClaudeFirstSeen: [String: Date] = [:]` on the coordinator, keyed by `processIdentityKey`. In `syntheticClaudeSession(for:now:)`, look up first-seen; if absent, record `now`; use the stored value as `updatedAt`. Evict entries whose identity key no longer appears in active processes (keeps the map bounded).

  **Why:** stops the "<1m" refresh phantom. A synthetic that's been around for 20 minutes should read "20m".

- [ ] **Step 2: Don't synthesize in workspaces with hook history**

  `mergedWithSyntheticClaudeSessions` currently filters `baseSessions = existingSessions.filter { !isSyntheticClaudeSession($0) }` and unconditionally produces synthetics for unmatched processes. Add a gate:

  ```swift
  let workspacesWithHookHistory: Set<String> = Set(
      baseSessions
          .filter { $0.tool == .claudeCode && $0.isHookManaged }
          .compactMap { normalizedPathForMatching($0.jumpTarget?.workingDirectory) }
  )
  ```

  In the synthetic-building loop, skip any process whose normalized CWD is in `workspacesWithHookHistory`. The real hook-managed session for that workspace is authoritative, even if we can't pin this specific process to it.

- [ ] **Step 3: Remove PR #375's CWD fallback from `representedClaudeProcessKeys` and `sessionIDsWithAliveProcesses`**

  Once Task 3 removes the `ps`-based eviction path for hook-managed Claude sessions, the workspace fallback from PR #375 becomes dead weight. Delete those two Pass-4 blocks.

- [ ] **Step 4: Tests**

  - Synthetic session created at t0, reconciled at t0+5s: `updatedAt == t0` (frozen).
  - Hook-managed session exists for workspace `/tmp/proj`; a Claude process with identical CWD and no hook match appears — `mergedWithSyntheticClaudeSessions` produces **no synthetic** (it's the same logical session, just temporarily unmatched).
  - Orphan Claude process in workspace `/tmp/other` with no hook session anywhere — synthetic **is** created (cold-start discovery still works).
  - Remove / rewrite the PR #375 regression tests (they asserted the now-removed fallback).

---

### Task 8: Integration test — simulate the original bug

**Files:**
- Create: `Tests/OpenIslandAppTests/ClaudeSessionLifecycleIntegrationTests.swift`

- [ ] **Step 1: End-to-end regression**

  1. Boot `AppModel` with test-injectable `ActiveAgentProcessDiscovery` and `ClaudePIDMonitor`.
  2. Simulate 4 Claude hook `sessionStart` events, each with `agentPID` pointing to real `/bin/sleep 30` subprocesses in the same fake CWD.
  3. Simulate 4 `userPromptSubmit` hooks with realistic `initialUserPrompt` text.
  4. Have the injected `ActiveAgentProcessDiscovery` return `[]` for 10 reconcile cycles (simulate total lsof failure).
  5. Assert: all 4 sessions remain alive and their metadata is intact. `spotlightHeadlineText` still shows `"workspace · <prompt>"`, not bare `workspace`. `spotlightAgeBadge` doesn't regress to `"<1m"`.
  6. Kill one of the `sleep` subprocesses externally. Wait `5s + slack`. Assert: that specific session flips to `isSessionEnded`, others remain alive.

- [ ] **Step 2: Verify**

  - [ ] `swift test --filter ClaudeSessionLifecycleIntegrationTests` green on CI.

---

### Task 9: Manual verification in dev app

- [ ] **Step 1: Refresh hooks**

  - `zsh scripts/setup-dev-signing.sh` (one-time, if not done).
  - `zsh scripts/launch-dev-app.sh`.
  - Open Settings → reinstall Claude hooks so the new `OpenIslandHooks` binary is in place.

- [ ] **Step 2: Reproduce original scenario**

  - Open 3+ Ghostty tabs, each `cd` into the same repo, start `claude` in each.
  - Induce load that would previously trigger the collapse: run a `find / -name ...` in another terminal to contend I/O, or `stress-ng --io 4 --timeout 60s` if installed.
  - Keep sessions active for 10 minutes with intermittent prompts.
  - Assert: no row ever collapses to bare workspace name + "<1m"; task metadata remains; age badges read the true age.

- [ ] **Step 3: Kill-path check**

  - In one tab, `kill -9` the claude process. Within ~5s, that specific session on the island should flip to Completed. Others stay untouched.

- [ ] **Step 4: Resume path check**

  - In a tab where you killed Claude, immediately run `claude --resume <prior-session-id>`. The old session should re-activate (new PID adopted, same sessionID) — no duplicate row should appear.

---

### Task 10: Close PR #375 and cut the new PR

- [ ] **Step 1: Close #375 with a comment**

  Explain that the fallback patch is superseded by this refactor and paste a link to the new PR.

- [ ] **Step 2: Open new PR from this branch**

  - Target: `main`.
  - Title: `refactor(claude): replace ps/lsof liveness polling with kernel PID exit monitoring`.
  - Body: link to this plan document, summarize the architectural shift, include the integration-test evidence.

---

## Testing Strategy

| Layer | Tool | What it covers |
| --- | --- | --- |
| Unit — codec | `ClaudeHookPayloadTests` | `agentPID` round-trips; legacy payloads decode. |
| Unit — monitor | `ClaudePIDMonitorTests` | track/untrack, grace, already-dead PID, PID reuse during grace. |
| Unit — reducer | `SessionStateTests` | `.claudeProcessExited` flips the session; `markProcessLiveness` does NOT touch hook-managed Claude sessions. |
| Unit — bridge | `BridgeServerTests` | sessionStart→track, sessionEnd→untrack, kernel exit→event emission, legacy-no-PID path. |
| Unit — persistence | `ClaudeSessionRegistryTests` | record round-trip with PID, rehydration on dead PID. |
| Unit — app | updated `AppModelSessionListTests` | synthetic `updatedAt` frozen; no synthetic in hook-history workspaces. |
| Integration | `ClaudeSessionLifecycleIntegrationTests` | 4-session collapse scenario reproduced and **not** reproducible on the new code. |
| Manual | dev-app smoke | realistic multi-terminal session for ≥10 minutes; kill and resume paths. |

---

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Legacy `OpenIslandHooks` binary without `agentPID` leaves sessions without monitors → they never get a clean end. | Medium for users who don't re-install. | Fall back to hook-only liveness (no ps polling). Add a 30-minute "no activity" safety timeout for hook-managed Claude sessions as a last-resort zombie cleaner (much looser than current 4s). Nudge reinstallation via existing health-check UI. |
| `DispatchSource` process source missing an exit event (macOS has known sporadic misses). | Low but non-zero. | Periodic (60s) self-check: for each tracked sessionID, `kill(pid, 0)`; if `ESRCH`, synthesize the exit manually. |
| `getppid()` returning non-Claude PID — e.g., `claude` was invoked via `npm exec` or a wrapper shell. | Medium. | `withRuntimeContext` walks parents briefly (up to 4 levels) looking for an executable whose name matches Claude CLI patterns (`/\bclaude$/`, `/.local/bin/claude$/`). If found, use that PID; otherwise fall back to `getppid()`. Add a test for `npm exec claude` wrapping. |
| Test flakiness due to timing-sensitive grace period. | Medium. | `ClaudePIDMonitor(gracePeriod: 0)` in unit tests; only integration test uses non-zero grace and widens tolerance. |
| Session ID collision across restarts (user runs `claude --resume same-id` in a different terminal). | Low. | `track` replaces the previous monitor for the same sessionID (explicit contract). Test covers this path. |
| Removing `processNotSeenCount` path for Claude leaves OpenCode/Cursor etc. with divergent behaviour. | Inherent — this is only Claude's migration. | Scope doc (above) is explicit; follow-up plan covers other tools. |

---

## Phases & Rollout

| Phase | Tasks | Gating |
| --- | --- | --- |
| 1. Foundation | 1, 2, 3 | All unit tests green. |
| 2. Integration | 4, 5, 6 | Bridge + persistence tests green. |
| 3. UI isolation | 7 | Synthetic tests green. |
| 4. Verification | 8, 9 | Integration test + manual smoke clean. |
| 5. Release | 10 | PR open, reviewed, merged. |

Phases 1-4 can all land in one PR (this is a coherent refactor) unless review asks to split. Phase 5 is PR lifecycle bookkeeping.

---

## Success Criteria

- `ActiveAgentProcessDiscovery` returning `[]` for an arbitrary number of reconcile cycles does **not** evict hook-managed Claude sessions.
- `kill -9 <claude-pid>` flips the specific session to Completed within `grace_period + 1s`.
- Synthetic rows (when present at all) show a true age, not "<1m".
- Integration test `ClaudeSessionLifecycleIntegrationTests` passes on CI.
- Manual 10-minute multi-session smoke on the dev app shows no collapse.
- No regression in OpenCode / Cursor / Gemini session handling (their code paths are unchanged).
