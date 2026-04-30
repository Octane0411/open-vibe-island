# Expanded View — `$` Today + Context-Left — Design

**Status:** Approved · **Date:** 2026-04-30 · **Owner:** h4ckm1n-dev fork

## Summary

Two additions to the **opened** (expanded) island view that were out of scope for the closed-notch personalization work:

1. **`$` today pill** in the header, after the existing rate-limit summary. Reuses `CodeburnClient` (already wired by the closed-notch work). Hidden when codeburn isn't installed.
2. **Context-left badge** per session row — small bar + percentage text — for Claude sessions only. Computed by reading the session's transcript JSONL directly, no codeburn dependency.

## Goals

- Surface `$` cost without forcing users to flip closed-notch slots.
- Tell each Claude session "how much room you have left" at a glance.
- Reuse what already exists — no new dependencies.

## Non-goals

- Per-session `$` breakdown in row badges (deferred to Phase 2).
- Context-left for non-Claude agents (Codex/Cursor/Gemini transcript shapes not analyzed yet).
- Tooltip/hover details on either badge (Phase 2 ergonomics).

## Locked decisions

| Area | Decision |
|---|---|
| Scope | A (header `$`) + C (per-row context-left) — not per-session `$` |
| `$` placement | After rate-limit summary, divided by `\|` |
| Context badge style | Bar + tiny percent number, color-graded by `% left` |
| Data source | `CodeburnClient` for `$` · transcript JSONL for context |
| Refresh | 30s timer (existing) for `$` · FSEvents file watcher for transcripts |

## Architecture

**`$` today pill (header)**
- New `DollarTodayPill` view rendered after the rate-limit summary in `openedHeaderContent` (`IslandPanelView.swift:472`).
- Reads `model.codeburnClient?.state` directly. No new state.
- Hidden unless `state == .ok(snapshot)`.

**Context-left per session**
- New core types in `Sources/OpenIslandCore/ContextUsage.swift`:
  - `ContextUsage` — `{ used: Int, window: Int, percentLeft: Double }`.
  - `ContextWindowTable` — model name → window size lookup.
  - `ContextUsageReader.parse(transcriptData:)` — pure parser (testable from `Data`).
  - `ContextUsageReader.read(transcriptPath:)` — thin file wrapper.
- New service on `AppModel`: `ContextUsageRegistry` (`@Observable @MainActor`):
  - `[String: ContextUsage]` cache keyed by sessionID.
  - Lazy: parses on first `usage(for:)` call.
  - Watches transcript file via `DispatchSourceFileSystemObject`; on modification, evicts cache + re-parses.
  - Prunes on session removal.
- New view `ContextLeftBadge` rendered in the right-side `HStack` of `IslandSessionRow` (`IslandPanelView.swift:1182`), inserted before the age badge.
  - Returns empty view if `registry.usage(for:) == nil`.

**File layout**
- `Sources/OpenIslandCore/ContextUsage.swift` — types + parser + table.
- `Sources/OpenIslandApp/Views/ContextLeftBadge.swift`
- `Sources/OpenIslandApp/Views/DollarTodayPill.swift`
- `Sources/OpenIslandApp/AppModel.swift` — registry + headerNeedsCodeburn flag.
- `Sources/OpenIslandApp/Views/IslandPanelView.swift` — wire both views.

## Data flow

### `$` today pill

```
CodeburnClient.state ◄── 30s timer (lazily started)
   │
   └─► DollarTodayPill renders only when state == .ok(snap)
```

The timer was previously started only when a closed-notch slot bound to `.dollarSpentToday`. We extend the bookkeeping: the expanded view's header sets a new flag `headerNeedsCodeburn` on AppModel when mounted; `updateCodeburnPolling()` ORs that flag with the slot config. When all consumers go away, the timer stops.

### Context usage (per row)

```
IslandSessionRow.body
   │
   ├─► reads model.contextUsageRegistry.usage(for: session) → ContextUsage?
   │
ContextUsageRegistry
   │   private var cache: [String: ContextUsage]
   │   private var watchers: [String: DispatchSourceFileSystemObject]
   │
   ├─► First call for a session: dispatch read on background queue,
   │   install file-mod watcher, post result back via MainActor.run
   ├─► Cache hit: return cached
   └─► Watcher fires: 200ms debounce, then re-read
```

### Reader logic

1. Open transcript, seek to last 64KB (extend to 256KB if no `usage` found).
2. Scan lines backwards. Decode each as JSON. Find first match where `type == "assistant"` and `message.usage` exists.
3. Compute effective context size:
   ```
   used = (message.usage.input_tokens ?? 0)
        + (message.usage.cache_read_input_tokens ?? 0)
        + (message.usage.cache_creation_input_tokens ?? 0)
   ```
4. Look up `message.model` in `ContextWindowTable`. Detect `[1m]` suffix for the 1M variant.
5. Return `ContextUsage(used:, window:)`.

### Context window table (Phase 1)

```swift
"claude-opus-4-7"        : 200_000   // [1m] suffix → 1_000_000
"claude-opus-4-6"        : 200_000
"claude-sonnet-4-6"      : 200_000
"claude-sonnet-4"        : 200_000
"claude-haiku-4-5"       : 200_000
"claude-haiku-4-5-*"     : 200_000
"claude-3-5-sonnet-*"    : 200_000
"claude-3-opus-*"        : 200_000
default                  : 200_000
```

Bundled in source; refreshable via Application Support JSON in a future iteration.

## Visual treatment

### `$` today pill

```
Claude  5h 24% 2h 26m | 7d 15% 6d | $3.42
```

- Font: `.system(size: 12, weight: .medium)` (matches rate-limit text).
- Color: `.green` if `< $5`, `.yellow` if `< $20`, `.orange` if `≥ $20`.
- Format: `$X.XX` if `< 10`, else `$XX.X`.
- Hidden when `state != .ok`.

### Context-left badge

Inserted into the existing right-side badge `HStack` of `IslandSessionRow`, before the age badge. Order: agent → SSH → terminal → **context** → age → dismiss.

```
[████░░░░] 64%
```

- Bar: 18×4pt rounded rectangle. Background `Color.white.opacity(0.12)`. Fill = `(used/window) * 18pt`, clamped `max(2, …)`.
- Bar fill color thresholds (by `% left`):
  - `> 50` → `.green`
  - `> 20` → `.yellow`
  - `> 10` → `.orange`
  - `≤ 10` → `.red`
- Text: 8pt monospaced semibold, `.white.opacity(0.7)`, format `XX%` (percent **left**).
- Capsule background `Color.white.opacity(0.04)` (matches adjacent badges).
- Compact / inactive rows: badge not rendered.
- Below 1% left: bar swaps for a single red dot.

## Error handling & edge cases

**Header `$` pill**
- Codeburn not installed → pill hidden (no install hint here).
- Stale data (timer hasn't refreshed) → last-good shown unchanged.
- Parse error → pill hidden, log once.

**Context-left registry**
- File missing or unreadable → registry returns nil, badge hidden.
- No `usage` block in last 64KB → extend window to 256KB, then give up (return nil).
- Unknown model → fallback to 200_000 default. Don't fail.
- 1M variant detection via `[1m]` suffix.
- Older transcripts without cache fields → treat as 0.
- FSEvents fails to install → fall back to 5s mtime polling for that one session.
- Mutations across actors → reader posts back via `MainActor.run`.

**Lifecycle**
- Session removed → registry evicts cache + cancels watcher.
- App restart → registry reconstructed; no leak.
- Many sessions watched simultaneously → cheap (one kernel object per watcher).

**Layout**
- Long workspace name → existing `Spacer(minLength: 8)` handles it.
- 0% used → bar fills 2pt minimum sliver.
- Below 1% left → red dot variant.

**Performance**
- Watcher re-fire storm → 200ms debounce per file.
- Memory bounded — one `ContextUsage` per active session.

## Testing

### `Tests/OpenIslandCoreTests/`

- **`ContextWindowTableTests.swift`** — model lookup, `[1m]` suffix detection, unknown fallback.
- **`ContextUsageReaderTests.swift`** — fixture-driven (parses `Data`, no FS):
  - Last-assistant-turn extraction with full `usage` block.
  - Skips user/system/tool turns when scanning backwards.
  - Returns nil if no assistant turn with `usage`.
  - Handles missing cache fields.
  - Handles malformed lines (skip, no throw).
  - Computes percentages correctly for various inputs.
  - 1M variant: `model="claude-opus-4-7[1m]"` with 300k tokens → 30%/70%.
- **`ContextUsageRegistryTests.swift`** — in-memory cache contract only:
  - Cache hit avoids re-parse (mock reader, assert call count).
  - `prune(activeSessionIDs:)` evicts.
  - File-watcher behavior NOT unit-tested.

### `Tests/OpenIslandAppTests/`

- **`ContextLeftBadgeTests.swift`** — pure layout sanity:
  - Bar fill clamped between 2pt minimum and full width.
  - Color thresholds at 60/30/15/5% left.
  - Below-1%-left → red dot variant.

### Manual smoke (PR description)

- Fresh Claude session in cmux → row shows `[░░░░░░] 99%`.
- Drive to ~70% used → bar grows green.
- ~85% used (15% left) → yellow.
- ~90%+ → orange/red as thresholds hit.
- Codex session next to a Claude one → only Claude row has badge.
- `npm i -g codeburn`, wait 30s → header shows `$X.YZ`. Without it: header unchanged.
- Quit cmux session → registry evicts, no zombie watcher.

### Out of scope

- FSEvents integration tests (manual only).
- Per-session `$` in row (Phase 2).
- Codex/Cursor/Gemini context-left support.

## Phasing

**Phase 1 — this design**
1. `ContextWindowTable` + `ContextUsage` types + reader.
2. `ContextUsageRegistry` in-memory cache.
3. File watcher + lifecycle wiring.
4. `ContextLeftBadge` view + integration in `IslandSessionRow`.
5. `DollarTodayPill` view + header integration + `headerNeedsCodeburn` flag.
6. Tests above.

**Phase 2 — separate design**
- Per-session `$` row badge (parse JSONL with bundled pricing table).
- Codex/Cursor/Gemini transcript shape investigation → context-left for non-Claude agents.
- Tooltip / hover detail on both badges.
- Refreshable `ContextWindowTable` via Application Support JSON.

## Open / deferred

- Where `$` data lives in settings — should there be a "Hide $ pill in header" toggle? Phase 2 if asked.
- Currency formatting beyond USD (matches the closed-notch widget's known-bug list).
- A11y labels — both new views need `.accessibilityLabel(…)` derived from their values.
