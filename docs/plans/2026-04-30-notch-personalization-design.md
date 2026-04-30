# Notch Personalization — Design

**Status:** Approved · **Date:** 2026-04-30 · **Owner:** h4ckm1n-dev fork

## Summary

Add a slot-based widget system to the closed (small-state) notch so users can choose what shows next to the existing island icon. Phase 1 ships an animated **companion** in the left slot (overlays on the existing avatar) and a configurable **right slot** (built-in display) plus an additional **center slot** (external displays). Available widgets: project chip (color dot + workspace name), agent-tool icon, and `$ spent today` (via the user's local `codeburn` install). Phase 2 ships a curated CC0 pixel-pet library that plugs into the same companion contract.

## Goals

- Give the closed notch real personality without sacrificing glanceability.
- Reuse existing data (sessions, phases, workspace metadata) — no new IPC, no new hooks.
- Make `$` cost visibility opt-in via an existing OSS tool (`codeburn`) rather than building a pricing pipeline in-house.
- Keep the upgrade invisible to users who don't open settings (defaults preserve today's look).

## Non-goals

- A native Swift port of `codeburn` (out of scope; α′ shells out to user's install).
- Stacked / rotating widgets in a single slot — single widget per slot only.
- Bundling Node or any JS runtime inside `OpenIsland.app`.
- Reworking the **opened** island surface — this design only touches the closed notch.

## Locked decisions

| Area | Decision |
|---|---|
| Approach | Slot-based widgets |
| Slot model | Single widget per slot. Companion fixed left. Right slot picker on built-in. Center + right picker on external. |
| Widget catalog (Phase 1) | Companion · Project chip · Agent-tool icon · `$` spent today · (legacy) Session count |
| Companion | Pet and mood are merged: animation states *are* the mood (idle / waiting / working / celebrating). |
| Companion fidelity | Phase 1 — overlays on existing avatar (Z-Z, dot, gear, sparkle). Phase 2 — curated CC0 pixel-pet library. |
| Cost tracking | α′ — shell out to user-installed `codeburn`, gracefully degrade if absent. No bundled Node. |
| Project color | Auto-hash from workspace path on first sight, with per-project override in settings. |

## Architecture

### New types in `OpenIslandCore`

```swift
public enum NotchSlot { case left, center, right }

public enum NotchWidgetKind: String, Codable, CaseIterable {
    case none
    case sessionCount       // current default — kept for back-compat
    case projectChip
    case agentToolIcon
    case dollarSpentToday
    case rateLimitGauge     // stretch — uses existing ClaudeUsage/CodexUsage
}

public struct NotchWidgetConfig: Codable, Equatable {
    public var rightSlot: NotchWidgetKind
    public var centerSlotExternal: NotchWidgetKind
}
```

The companion is **not** a `NotchWidgetKind` — it always occupies the left slot and is configured by existing appearance settings (avatar / pixel-shape) plus the new overlay state machine.

### New views (`Sources/OpenIslandApp/Views/NotchWidgets/`)

- `CompanionStateOverlay.swift` — Phase 1 overlay layer atop `IslandPixelGlyph` / `OpenIslandIcon`.
- `ProjectChipWidget.swift` — color dot + truncated workspace name; icon-only fallback at narrow widths.
- `AgentToolIconWidget.swift` — branded glyph for the spotlight session's `AgentTool`.
- `DollarSpentWidget.swift` — renders `$3.42`, faded `$—` (stale), or install hint when codeburn absent.
- `NotchSlotHost.swift` — dispatcher: `(NotchWidgetKind, available width) -> AnyView`.

The existing `headerRow` in `IslandPanelView.swift` is refactored to read `model.notchWidgetConfig` and dispatch through `NotchSlotHost` for the right slot (and center slot when `isExternalDisplayPlacement`).

### New core services

- `Sources/OpenIslandCore/CodeburnClient.swift` — `@Observable` client. Probes `codeburn --version` once, then runs `codeburn status --format json` on a 30s timer when at least one slot is bound to `.dollarSpentToday`. Single-flight, 5s subprocess timeout, sticky 60s backoff on failure. Subprocess invocation isolated behind a `CodeburnRunner` protocol so tests inject a fake.
- `Sources/OpenIslandCore/ProjectColorRegistry.swift` — workspace path → color map. FNV-1a hash → HSL hue (fixed S/L) for unset entries. Persisted at `~/Library/Application Support/OpenIsland/project-colors.json`. Exposes `color(for:)`, `setColor(_:for:)`, `resetAll()`, `pruneUnusedKeys(activePaths:)`.

## Data flow

```
AppModel (sessions, phase, config, isExternalDisplayPlacement)
   │
   ├─► CompanionStateOverlay  ◄── derived from model only
   ├─► ProjectChipWidget      ◄── + ProjectColorRegistry
   ├─► AgentToolIconWidget    ◄── derived from model only
   └─► DollarSpentWidget      ◄── + CodeburnClient (timer-driven)
```

### Companion state derivation

| Model state | Companion state | Overlay |
|---|---|---|
| No live sessions | `.idle` | "Z-Z" pixel glyph, dim tint |
| Spotlight phase = `running` | `.working` | small spinner / gear, scout tint |
| Spotlight phase = `waitingForApproval` / `waitingForAnswer` | `.waiting` | pulsing dot, attention tint |
| Spotlight phase transitioned to `completed` within 8s | `.celebrating` | sparkle, success tint |

After 8s of `.celebrating`, decays back to `.idle`. Debounced: two completions within 2s yield only one `celebrating` enter.

### Project chip

- Workspace key: `JumpTarget.workspaceName` (preferred) or last path component of `JumpTarget.workingDirectory`.
- Color resolution: `ProjectColorRegistry.color(for: key)` — first call hashes and stores; subsequent calls return stored value. Settings UI mutates the same registry.
- Compact fallback: drop the name, render the dot at slightly larger size when `availableWidth < threshold`.

### `$` spent today (codeburn)

1. `CodeburnClient` is created lazily when `dollarSpentToday` is selected for any slot.
2. Probe `codeburn --version`. Cache the result for the session.
3. If found: every 30s, run `codeburn status --format json`. Parse `{today: {cost: number, currency: string}}`. Publish `CodeburnSnapshot.ok(amount, currency)`.
4. If absent: publish `.notInstalled`. Widget renders an install hint (clickable → opens codeburn's GitHub install URL in default browser). **Never auto-install.**
5. Failure modes (timeout, non-zero exit, malformed JSON, unsupported version): publish `.unavailable` with reason; widget renders last-good faded value or `$—`. Backoff to 60s.

## Settings UX

New section in `AppearanceSettingsPane.swift`, below "Status colors":

### "Notch widgets"

```
Right slot       [ Session count        ▾ ]
                   None / Session count (default) / Project chip
                   / Agent-tool icon / $ spent today

Center slot      [ None                 ▾ ]
(external displays only — disabled if no external display connected)

┌─── live preview ───┐
│  🐱   Bash   ● 3  │
└────────────────────┘
```

- "$ spent today" shows ⓘ next to it when codeburn is missing — hover text "Requires `codeburn` — click to install" linking to GitHub.
- Center slot picker is grayed when no external non-notched display is connected.
- Live preview uses the same mock-driving harness `AppearanceSettingsPane` already has.

### "Project colors" (collapsible, defaults collapsed)

```
●  OpenIsland          ~/Documents/.../OpenIsland
●  Compta-Terra-Lao    ~/Documents/.../Compta...
●  btc-bot             ~/Documents/.../btc-bot

[ Reset all to auto ]   [ Remove unused ]
```

- Populated from `ProjectColorRegistry`.
- Click any swatch → 12 preset swatches + "Custom…" (`NSColorPanel`).
- "Reset all to auto" wipes the registry; everything re-hashes on next render.
- "Remove unused" prunes paths no longer referenced by any active session.

### Defaults

- `rightSlot = .sessionCount` (preserves today's behavior).
- `centerSlotExternal = .none` (opt-in).
- Companion overlays **on** in custom appearance mode, **off** in default mode (don't change look-and-feel without opt-in).

### Localization

- New keys under `settings.notchWidgets.*` and `settings.projectColors.*` added to `en.lproj`, `zh-Hans.lproj`, `zh-Hant.lproj`.

## Error handling & edge cases

**codeburn**
- Not installed → `.notInstalled`, never spawn. Inline install hint.
- Subprocess timeout (>5s) → cancel, mark stale, retry in 60s. Last-good value with faded tint.
- Non-zero exit / malformed JSON → log once at warn, treat as `.unavailable`, retry in 60s.
- Unsupported version → tooltip "codeburn ≥ X.Y required" instead of install link.
- Single-flight: skip a tick if previous run hasn't returned.

**Spotlight session absence**
- No live sessions: project chip / agent icon / `$` widget render dim/empty at full slot width — never collapse to zero (prevents notch shape twitch).
- Missing `JumpTarget`: project chip falls back to "—". Agent icon always available from `AgentTool`.
- Multiple live sessions: existing `closedSpotlightSession` picks one; widgets follow the spotlight (except session count which aggregates).

**Project color registry**
- Corruption: catch, log, start fresh, write empty registry. Auto-hash takes over.
- Path collision (two checkouts of same repo): treated as separate entries by full path.
- Renamed/moved paths: stay in registry until "Remove unused" is clicked.

**External display**
- Disconnected mid-session: closed notch falls back to built-in layout; center widget hides without animation jump. Existing `isExternalDisplayPlacement` already gates this.
- Notch lane too narrow: existing `notchLaneSafetyInset` gates layout. Widget intrinsic width > available lane → renders its `compactRepresentation` (e.g. project chip → just the dot).

**Companion overlay**
- Custom avatar with extreme aspect ratio: overlays anchor to avatar bounding box, not pixels.
- Strobe protection: `.celebrating` enters only if previous celebration ended >2s ago.

**Settings**
- Picking a widget before any data is observed: widget renders zero-state (e.g. `$0.00`), not empty.
- Missing localization: existing `LanguageManager` falls back to the key string.

## Testing

### `Tests/OpenIslandCoreTests/`

- **`ProjectColorRegistryTests.swift`** — stable hashing, override persistence, reset, corruption recovery, prune.
- **`CodeburnClientTests.swift`** — JSON parsing fixtures; state machine transitions (`notProbed → notInstalled`, `installed → ok → stale`); single-flight; backoff; subprocess injected via `CodeburnRunner` fake.
- **`CompanionStateMachineTests.swift`** — phase → companion-state mapping; 8s celebration window; 2s debounce.

### `Tests/OpenIslandAppTests/`

- **`NotchSlotConfigTests.swift`** — JSON round-trip; default values match migration story.
- **`NotchSlotHostTests.swift`** — `.none` returns empty-but-sized view; compact-representation fallback fires below width threshold.

### Manual smoke (documented in PR)

- Notched MacBook + external non-notched display side-by-side: center slot only on external; disappears on disconnect.
- codeburn install / uninstall: widget populates within 30s on install; install hint surfaces on uninstall without crash.
- Long project-name truncation at narrow widths (13" notched MBP).

### Out of scope for tests

- Real subprocess spawning (covered by manual smoke).
- Sprite-sheet playback (Phase 2 work).
- Localization-key completeness.

## Phasing

**Phase 1 — this design**
1. `NotchWidgetConfig`, `NotchSlotHost`, refactor of `headerRow`.
2. `ProjectColorRegistry` + project chip widget.
3. Agent-tool icon widget.
4. `CodeburnClient` + `$` spent widget (with `.notInstalled` graceful path).
5. `CompanionStateOverlay` Phase 1 (overlays on existing avatar).
6. Settings section + localization keys.
7. Tests above.

**Phase 2 — separate design / plan**
- Curated CC0 pixel-pet library (sourced via `pixel-art-sprite-sourcing` skill — Kenney.nl, OpenGameArt).
- Sprite-sheet animation pipeline.
- Pet picker in settings.
- Same companion-state contract; pets just replace the overlay layer with full sprite frames.

## Open / deferred

- Whether to surface `$` in the **opened** island as well — out of scope here, easy follow-up once `CodeburnClient` exists.
- Rate-limit gauge widget (`.rateLimitGauge`) — listed in the enum but Phase 1 implementation is a stretch; uses existing `ClaudeUsageWindow` / `CodexUsageWindow` data, no new subsystems.
- iCloud / cross-device sync of `ProjectColorRegistry` — not needed; local file is fine.
