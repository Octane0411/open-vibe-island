# Codex Subagent Parent Lifecycle Design

## Problem

Codex Desktop subagent rollouts use their own rollout `id`, but also carry the
parent thread as `session_id`. Hook payloads therefore arrive with the parent
session ID and the subagent transcript path. Open Island currently treats these
as normal parent hooks, so a subagent can replace the parent's transcript
metadata and its `Stop` hook can mark the parent completed while sibling
subagents are still running.

The rollout discovery layer already hides subagent rollouts as separate
sessions. The remaining bug is in the hook ingestion path.

## Desired Behavior

- Show one Codex session row for the parent thread.
- Keep that parent row running when a subagent reports active work.
- Never replace the parent's transcript path or prompt metadata with subagent
  transcript data.
- Never complete the parent because a subagent emitted `Stop`.
- Preserve permission requests from subagent tools on the parent row.
- Complete the parent only from parent lifecycle signals, including its own
  hook, rollout, or app-server status.

## Design

`BridgeServer` will classify a Codex hook as a subagent hook when its
`transcript_path` points to a rollout whose `session_meta` contains an explicit
subagent marker (`thread_source`, `parent_thread_id`, or `source.subagent`). It
will reuse the existing rollout classification helper so discovery and hook
ingestion agree on the definition.

For classified subagent hooks:

- `SessionStart`, `UserPromptSubmit`, and tool activity keep the parent session
  running without recreating it or synchronizing subagent transcript metadata.
- `PreToolUse` and `PermissionRequest` retain the existing approval flow, but
  do not replace the parent's transcript or jump target.
- `Stop` is acknowledged without emitting parent completion.
- If the parent has not yet been discovered, Open Island may create a minimal
  parent session using the parent ID and workspace context, but it must omit the
  child transcript metadata.

Normal parent and Codex CLI hooks keep their current behavior. If the transcript
cannot be read or does not contain an explicit subagent marker, Open Island
uses the normal hook path rather than guessing.

## Data Flow

1. `OpenIslandHooks` forwards the Codex hook payload unchanged.
2. `BridgeServer` inspects only the rollout `session_meta` identified by
   `transcript_path`.
3. A normal rollout follows the existing lifecycle path.
4. A subagent rollout updates parent activity or approval state, but cannot
   update parent transcript metadata or emit parent completion.
5. The parent rollout watcher and Codex app-server remain authoritative for
   final completion.

## Error And Race Handling

- Missing or malformed transcript metadata falls back to existing behavior.
- A subagent `Stop` never promotes or demotes parent state, avoiding races with
  sibling agents and parent completion.
- The change does not add polling or scan loops; classification reads the first
  rollout line only when a hook arrives.
- Persisted parent records that already point at subagent transcripts continue
  to be removed by the startup pruning added in the preceding fix.

## Verification

Add regression coverage proving that:

1. A subagent hook cannot replace the parent's transcript metadata.
2. A subagent `Stop` cannot complete the parent session.
3. A normal parent `Stop` still completes the parent.
4. Existing Codex rollout discovery, hook approval, and session-list tests stay
   green.

After automated verification, package and install the app for live testing and
update the existing PR #580 only. Do not create another PR.
