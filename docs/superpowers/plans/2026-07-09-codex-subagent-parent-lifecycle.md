# Codex Subagent Parent Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent Codex Desktop subagent hooks from replacing or completing their parent session while still surfacing subagent activity and approvals on the parent row.

**Architecture:** Classify hook payloads using the existing `CodexRolloutDiscovery.isSubagentRollout(atPath:)` helper. Route classified payloads through a narrow BridgeServer path that preserves parent identity and approvals but excludes child transcript metadata and child completion.

**Tech Stack:** Swift 6, Swift Testing, OpenIslandCore bridge and rollout tracking.

## Global Constraints

- Keep one visible Codex row per parent thread.
- Do not add polling, new dependencies, a new branch, or a new PR.
- Preserve normal Codex CLI and parent-thread hook behavior.
- Update existing PR #580 only after verification.

---

### Task 1: Reproduce The Hook Collision

**Files:**
- Modify: `Tests/OpenIslandCoreTests/SessionStateTests.swift`

**Interfaces:**
- Consumes: `BridgeServer`, `CodexHookPayload`, and a temporary rollout whose first line is `session_meta`.
- Produces: Regression tests for parent metadata preservation, child-stop suppression, and normal parent completion.

- [ ] **Step 1: Add a temporary rollout helper**

Create parent and child JSONL fixtures. The child fixture must include:

```json
{"type":"session_meta","payload":{"id":"child-thread","session_id":"parent-thread","parent_thread_id":"parent-thread","thread_source":"subagent","cwd":"/tmp/worktree","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent-thread","depth":1}}}}}
```

- [ ] **Step 2: Add the failing lifecycle test**

Start a parent with `parent.jsonl`, then send child `SessionStart` and `Stop` payloads using the parent session ID and `child.jsonl`. Assert that no child hook replaces the parent transcript and no child `Stop` emits `sessionCompleted`. Send a normal parent `Stop` and assert that it still emits completion.

- [ ] **Step 3: Run the focused test and verify RED**

Run:

```bash
swift test --filter codexSubagentHooksPreserveParentLifecycle
```

Expected: FAIL because the child `SessionStart` currently emits a replacement `sessionStarted` event or the child `Stop` emits parent completion.

### Task 2: Route Subagent Hooks Without Parent Completion

**Files:**
- Modify: `Sources/OpenIslandCore/BridgeServer.swift`
- Test: `Tests/OpenIslandCoreTests/SessionStateTests.swift`

**Interfaces:**
- Consumes: `CodexRolloutDiscovery.isSubagentRollout(atPath:)`.
- Produces: `handleCodexSubagentHook(_:from:)` and sanitized parent-session creation that never stores a child transcript path.

- [ ] **Step 1: Classify subagent payloads before the normal switch**

Use the explicit rollout metadata helper only when `transcriptPath` is non-empty. Do not infer from workspace or title.

- [ ] **Step 2: Implement minimal subagent behavior**

For `SessionStart`, `UserPromptSubmit`, and non-interactive tool events, ensure a minimal parent exists and emit parent `.running` activity. For `PreToolUse` and `PermissionRequest`, keep the current approval request and pending-approval response behavior without synchronizing transcript metadata or jump targets. For `Stop`, acknowledge only.

- [ ] **Step 3: Run the focused test and verify GREEN**

Run:

```bash
swift test --filter codexSubagentHooksPreserveParentLifecycle
```

Expected: PASS.

- [ ] **Step 4: Run related regression suites**

Run:

```bash
swift test --filter 'CodexSessionTrackingTests|SessionStateTests|AppModelSessionListTests'
```

Expected: all selected tests pass.

- [ ] **Step 5: Run the complete suite**

Run:

```bash
swift test
```

Expected: zero failures.

- [ ] **Step 6: Commit the implementation**

```bash
git add Sources/OpenIslandCore/BridgeServer.swift Tests/OpenIslandCoreTests/SessionStateTests.swift docs/superpowers/plans/2026-07-09-codex-subagent-parent-lifecycle.md
git commit -m "fix: preserve codex parent while subagents run"
```

### Task 3: Package And Update The Existing Review

**Files:**
- Generated local app bundle only; restore package-generated DMG background changes before committing or pushing.

**Interfaces:**
- Consumes: verified `OpenIslandApp` branch state.
- Produces: an installed local build and an updated existing PR #580.

- [ ] **Step 1: Package the verified branch**

Run `scripts/package-app.sh` with version `1.1.4` and a uniquely named temporary package root.

- [ ] **Step 2: Replace and launch the local application**

Install the generated `Open Island.app` at `/Applications/Open Island.app`, launch it, and verify bundle ID, version, build number, and running executable path.

- [ ] **Step 3: Clean generated package output**

Delete the temporary package directory and restore only package-generated DMG background images. Keep the active PR worktree and remove no source needed by PR #580.

- [ ] **Step 4: Push the existing branch**

Push `fix/reduce-closed-notch-height` to its current fork remote. Confirm PR #580 points at the new commit; do not create a PR.
