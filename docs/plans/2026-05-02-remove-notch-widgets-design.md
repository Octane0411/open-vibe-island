# Remove Notch Widgets — Design

**Status:** approved
**Date:** 2026-05-02
**Branch:** `feat/upstream-cleanup` (off `feat/notch-personalization`)

## Goal

Remove the Notch widgets slot system (closed-notch L2/R1/R2 + center external slot, expanded L2/R1/R2) from the codebase ahead of upstreaming the rest of `feat/notch-personalization` to `Octane0411/open-vibe-island`. The feature does not work well — every slot defaults to None for users who try it, and the abstraction adds complexity without earning its keep.

## Approach

**(b) — one new removal commit on top of the branch.** Cleaner alternatives (revert, interactive rebase) conflict with pets work that piggy-backs on slot infrastructure. A single forward commit lets the PR diff still show "everything except Notch widgets" while keeping local history intact and low-risk to apply.

## What gets deleted

### Files (full delete)
- `Sources/OpenIslandCore/NotchWidget.swift` — `NotchWidgetKind` enum + `NotchWidgetConfig` struct + Codable
- `Sources/OpenIslandApp/Views/NotchWidgets/NotchSlotHost.swift` — slot dispatch view
- `Sources/OpenIslandApp/Views/NotchWidgets/AgentToolIconWidget.swift`
- `Sources/OpenIslandApp/Views/NotchWidgets/DollarSpentWidget.swift`
- `Sources/OpenIslandApp/Views/NotchWidgets/ProjectChipWidget.swift`
- `Tests/OpenIslandCoreTests/NotchWidgetTests.swift`
- `docs/plans/2026-04-30-notch-personalization-design.md`
- `docs/plans/2026-04-30-notch-personalization.md`

### Files (move + keep)
- `Sources/OpenIslandApp/Views/NotchWidgets/AnimatedCompanionPet.swift` → `Sources/OpenIslandApp/Views/Companion/AnimatedCompanionPet.swift`
- `Sources/OpenIslandApp/Views/NotchWidgets/CompanionStateOverlay.swift` → `Sources/OpenIslandApp/Views/Companion/CompanionStateOverlay.swift`

After the move, remove the now-empty `NotchWidgets/` directory.

### Files (modify)
- `Sources/OpenIslandApp/AppModel.swift`
  - Remove `notchWidgetConfig` stored property + `didSet` persistence
  - Remove `notchWidgetConfigDefaultsKey` constant
  - Remove the load-from-UserDefaults block in init
  - Simplify `updateCodeburnPolling()` — drop the slot-based gates; keep only the `headerNeedsCodeburn` path
- `Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift`
  - Remove the `Section(lang.t("settings.notchWidgets.title"))` block (closed + expanded pickers, divider, hints) — ~62 lines
  - Remove the `slotBinding(_:)` helper
  - Remove the `localizedKindName(_:)` helper
- `Sources/OpenIslandApp/Views/IslandPanelView.swift`
  - Remove all 11 `NotchSlotHost(…)` call sites (closed L2/center/R1/R2 and expanded L2/R1/R2 across the notch-aware and flat header branches)
  - Restore `ClosedCountBadge` directly in the closed-notch right HStack (where R1 currently lives), keeping the `matchedGeometryEffect("right-indicator")` anchor
  - Drop the `centerSlotExternal != .none` gate around `CentralActivityLabel.isVisible`; the label is always visible on external displays again
  - Drop the dynamic frame-width adjustments tied to slot presence (`+ (closedLeft2 != .none ? 30 : 0)`, `+ (closedRight2 != .none ? 34 : 0)`)
- `Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings` — remove 15 `settings.notchWidgets.*` keys
- `Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings` — remove 15 `settings.notchWidgets.*` keys

## What stays (the contract)

These features remain functional and shipped on the branch:
- **Pets** (`AnimatedCompanionPet`, `PetSpriteData`, `PixelPetSprite`, `CompanionPet`) — overlaid directly on the `IslandPixelGlyph` custom-avatar branch (already wired this way; nothing to change in the call site)
- **CompanionStateOverlay** — overlaid directly on the same icon, used when no pet is selected
- **Ambient theme** (`AmbientThemeOverlay`)
- **Celebrations** (`CelebrationParticles`)
- **Project colors** (`ProjectColorRegistry`) and the Project colors settings section
- **Codeburn `$ today`** in the expanded header (`DollarTodayPill` — gated by `headerNeedsCodeburn`, independent of slots)
- **Per-row `ContextLeftBadge`** in expanded sessions
- **Token bar 1M-context auto-detect**
- **cmux tab-switching** (`CMUX_SURFACE_ID` capture, surface.focus jump)
- **Auto-detect open cmux tabs**

## Risks and mitigations

- **Codeburn polling regression** — the slot-based gating in `updateCodeburnPolling()` could mask whether `headerNeedsCodeburn` alone is sufficient. Mitigation: confirm at runtime that `$ today` still updates in the expanded header after removal.
- **Closed-notch right-indicator visual diff** — restoring `ClosedCountBadge` as a direct child instead of a `NotchSlotHost(.sessionCount)` should be visually identical, but the `matchedGeometryEffect("right-indicator")` anchor needs to land on the same view that previously held it. Mitigation: keep the modifier on the count badge.
- **Persisted UserDefaults remnants** — old users will have `notch.widgetConfig` JSON in defaults. Harmless (just unused bytes). Not worth a migration.
- **Localization compile** — `lang.t("settings.notchWidgets.*")` calls all live in the deleted Section, so removing the keys is safe. Verify by grep.

## Verification

- `swift build` clean
- `swift test` — current count drops by 4 tests (NotchWidgetTests has 4 `@Test` cases). All others stay green.
- Launch dev app via `zsh scripts/launch-dev-app.sh --skip-setup`:
  - Closed notch: agent icon + (companion overlay or pet) + count badge on the right. No extra slots.
  - Expanded notch: usage summary on the left, `DollarTodayPill` + buttons on the right. No extra slots between.
  - Settings → Appearance: pet picker, ambient toggle, celebrations toggle, project colors disclosure all present. **No "Notch widgets" section.**
  - Trigger a Claude Code session: pet animates, ambient gradient applies, celebration confetti fires on completion. `$ today` updates in expanded header.

## PR strategy

Single PR to `Octane0411/open-vibe-island:main` from `h4ckm1n-dev/open-vibe-island:feat/upstream-cleanup`. PR body groups the changes into logical bundles (bug fixes, personalization, infra) so the maintainer can ask for splits if they prefer. Include the bilingual changelog format from `.github/RELEASE_TEMPLATE.md` since the project requires it for releases.

## Out of scope

- Pet sourcing for the 5 additional pets (dog/ducky/dragon/plant/slime).
- Roadmap document for vibe-island feature parity.
- Refactoring the `Companion/` directory contents beyond moving the two view files.
