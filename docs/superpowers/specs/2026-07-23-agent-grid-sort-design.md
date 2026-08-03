# Closed Agent Grid Sorting

## Goal

Let users choose how sessions are ordered in the closed island's right-side
agent grid. The setting affects only the `.agents` right-slot presentation;
the expanded session list keeps its existing grouping and sorting settings.

The default is **Status priority**, so sessions needing attention or currently
running remain visible when completed or idle history fills the grid.

## Non-goals

- Do not change per-agent brand colors or phase opacity/animation.
- Do not add a completed-state green color or glyph.
- Do not change the expanded session list.
- Do not add a strategy abstraction or new dependency.

## Preference and settings UI

Add a five-case `IslandAgentGridSort` value to
`IslandAppearancePreferences`, persisted with the existing per-display-profile
appearance keys. A missing or unknown stored value falls back to
`statusPriority`; no migration is needed.

When the right-slot choice is **Agents**, the appearance pane shows five
compact option cards using the existing option-card style:

1. **Status priority**
2. **Recent activity**
3. **Newest session**
4. **By agent**
5. **Stable order**

The labels are localized in the existing English, Simplified Chinese, and
Traditional Chinese string tables. Other right-slot choices do not use this
preference.

## Ordering semantics

`AppModel.islandClosedRightSlotContent()` stamps the existing observation
tickets, orders all surfaced sessions according to the selected mode, then
maps them to the existing `AgentGridCell` representation.

All modes use observation ticket and session ID as deterministic final
tie-breakers.

| Mode | Primary order |
| --- | --- |
| Status priority | attention, running, recent completed, remaining idle/stale; within a bucket, `updatedAt` descending |
| Recent activity | `updatedAt` descending |
| Newest session | `firstSeenAt` descending |
| By agent | `AgentTool.allCases` order; within a tool, status-priority order |
| Stable order | observation ticket ascending, preserving the current behavior |

"Recent completed" reuses `completedStaleThreshold` and
`isStaleCompletedForIsland`; it does not introduce another timeout.
Waiting-for-approval and waiting-for-answer share the same attention bucket.

After ordering, up to nine sessions are shown directly. With more than nine,
the first seven ordered sessions are shown followed by one overflow cell with
the remaining count. Non-default modes may place a running session beyond the
first seven by user choice; Status priority prevents that in the default mode.

## Data flow and failure handling

1. The user selects a grid sort card for the current display profile.
2. The existing appearance update path persists its raw value in
   `UserDefaults` and refreshes the preview/runtime model.
3. Closed-island rendering reads the preference and orders the current
   `surfacedSessions` before applying the existing overflow rule.
4. Invalid persisted raw values decode to `statusPriority`.

There is no external I/O or recoverable runtime failure beyond preference
decoding. The existing observation-ticket pruning remains unchanged.

## Verification

Add one table-driven test in `AgentsGridRightSlotTests` that exercises the
five modes with the same deliberately mixed sessions and verifies their cell
order. Keep focused checks for the default mode's active-session visibility
and the seven-plus-overflow boundary. Run the targeted app test suite and
refresh `Open Island Dev.app` for manual settings and closed-grid verification.
