# Session Lifecycle Policy

Open Island models session visibility and liveness with an explicit
`SessionLifecyclePolicy` plus explicit runtime evidence, instead of
reconstructing behavior from incidental booleans at restore time.

## Policies

- `processDriven`
  - Visibility follows policy-aware runtime presence.
  - Used for synthetic or process-only sessions.
- `hookDrivenWithProcessFallback`
  - Hooks remain the primary lifecycle signal.
  - Process/app evidence is still used as a bounded fallback when end hooks are
    missing or the bridge was unavailable.
- `appDriven`
  - Visibility follows desktop-app presence rather than CLI subprocess matching.
  - Currently used for `Codex.app` sessions.

## Restore Invariants

- Persistence must round-trip:
  - `lifecyclePolicy`
  - `isRemote`
  - `isSessionEnded`
- Ephemeral runtime evidence is not persisted.
- Restored sessions must not silently downgrade from hook/app-driven semantics
  to process-driven semantics just because they came from disk.
- Stale restored hook-driven sessions stay hidden until fresh liveness evidence
  arrives, so cold-start recovery does not surface old sessions prematurely.

## Evidence Model

- The reducer stores lifecycle policy and lifecycle state on the session.
- Runtime evidence is modeled separately from lifecycle policy:
  - runtime observation from `ps`/`lsof` or desktop-app presence
  - event presence from bridge events or live rollout appends
- Hook-managed sessions end only after two consecutive reconciliation polls
  without either runtime evidence or event presence.
- Bridge and rollout ingress add evidence to `livenessObservation`; the reducer
  interprets that evidence according to `lifecyclePolicy`.
- Core reducers and app logic should use policy-aware helpers such as
  `hasPresenceEvidence` and `presenceMissCount`.

## Match Strength

Process/app evidence is not treated as a single boolean. Matches carry an
explicit strength so the reducer can distinguish identity quality:

- `desktopApp`
- `sessionID`
- `transcriptPath`
- `terminalTTYAndWorkingDirectory`
- `workingDirectory`
- `terminalTTY`
- `toolFamily`

This keeps "session exists" and "how confidently we matched it" separate, which
lets the process monitor stay heuristic while the reducer stays deterministic.

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
