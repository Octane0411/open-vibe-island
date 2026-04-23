# Session Lifecycle Policy

Open Island models session visibility and liveness with an explicit
`SessionLifecyclePolicy` instead of reconstructing behavior from incidental
booleans at restore time.

## Policies

- `processDriven`
  - Visibility follows `isProcessAlive`.
  - Used for synthetic or process-only sessions.
- `hookDrivenWithProcessFallback`
  - Hooks remain the primary lifecycle signal.
  - Process/app evidence is still used as a bounded fallback when end hooks are
    missing or the bridge was unavailable.
- `appDriven`
  - Visibility follows the desktop app's presence rather than CLI subprocess
    matching.
  - Currently used for `Codex.app` sessions.

## Restore Invariants

- Persistence must round-trip:
  - `lifecyclePolicy`
  - `isRemote`
  - `isSessionEnded`
- Restored sessions must not silently downgrade from hook/app-driven semantics
  to process-driven semantics just because they came from disk.
- Stale restored hook-driven sessions stay hidden until fresh liveness evidence
  arrives, so cold-start recovery does not surface old sessions prematurely.

## Rollout Freshness

Codex rollout watcher events are split into two classes:

- `bootstrap`
  - Produced from the initial snapshot/tail bootstrap.
  - May update metadata and phase, but must not refresh keepalive counters.
- `live`
  - Produced from newly appended rollout lines after bootstrap.
  - May refresh Codex keepalive state for already tracked hook-driven sessions.

This keeps startup replay informative without letting old rollout tails
resurrect dead sessions.
