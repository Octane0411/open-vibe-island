# Hide Overlay In Fullscreen — Design

**Status:** Spec  
**Date:** 2026-05-02  
**Branch:** `feat/hide-overlay-in-fullscreen`

## Problem

Open Island's overlay panel uses `NSWindow.CollectionBehavior` `.fullScreenAuxiliary` and `.canJoinAllSpaces`, so the closed island bar (and any expanded panel) keeps drawing in the notch / top-bar area while the user is in a native macOS fullscreen Space (Safari video, IDE fullscreen, Keynote presentation, …). This breaks the immersive feel users expect from fullscreen.

The existing localization keys `settings.general.hideFullscreen` are present in en / zh-Hans / zh-Hant, and a UI toggle for this setting once existed but was removed in #103 because no implementation backed it. This spec re-introduces the toggle with a real implementation.

## Goals

- Hide the overlay (closed bar + opened panel) while the user is in a native fullscreen Space *on the same screen as the island*.
- Still surface attention-required events (`waitingForApproval`, `waitingForAnswer`) so agents do not get silently stuck.
- Add a single user-visible toggle in *General → Behavior*. Default **on**.
- No regressions in non-fullscreen, multi-display, or Mission Control transitions.

## Non-goals

- Hiding for non-native "covers the screen" cases (auto-hidden menu bar + maximized window). Out of scope (see "Scope of fullscreen detection" below).
- Hiding when fullscreen is on a screen *other than* the one the island is positioned on.
- Reworking the `IslandSurface` / notification card pipeline. We reuse the existing path.

## Decisions

| # | Question | Decision |
|---|---|---|
| 1 | What counts as "fullscreen"? | Native fullscreen Space only — detected via active-space change + a window covering the entire `NSScreen.frame` (incl. menu bar). |
| 2 | Behavior on attention-required events while in fullscreen? | Silent for non-urgent (e.g. `completed`); still surface `waitingForApproval` / `waitingForAnswer` as the existing notification card. |
| 3 | Default value of the toggle? | **On**. |
| 4 | Multi-display behavior? | Per-screen — only suppress if the *island's* screen is in fullscreen. |

## Architecture

### New: `Sources/OpenIslandApp/FullscreenSpaceObserver.swift`

```swift
@MainActor
final class FullscreenSpaceObserver {
    var onChange: ((Set<CGDirectDisplayID>) -> Void)?

    func start()
    func stop()

    // Pure helper, exported for unit tests.
    static func screenIsCovered(byTopWindowBounds bounds: CGRect, screenFrame: CGRect) -> Bool
}
```

- Subscribes to `NSWorkspace.shared.notificationCenter` `activeSpaceDidChangeNotification`, plus `NSApplication.didChangeScreenParametersNotification`.
- On any of those: calls `recompute()`:
  1. `CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)`.
  2. Filter to entries with `kCGWindowLayer == 0` (regular app windows).
  3. For each `NSScreen`, find the topmost layer-0 window whose bounds intersect the screen's frame (CG flipped coordinates).
  4. Use `screenIsCovered(byTopWindowBounds:screenFrame:)` to decide whether that window covers the *whole* screen including the menu bar area.
  5. Build `Set<CGDirectDisplayID>` of fullscreen screens.
- Emits `onChange` only when the set differs from the previous value.
- Throttling: triggered only by notifications, not polling. No timer.

### `AppModel`

New stored / derived state:

```swift
private static let hideInFullscreenDefaultsKey = "app.hideInFullscreen"

var hideInFullscreenEnabled: Bool = true {
    didSet {
        guard hasFinishedInit, hideInFullscreenEnabled != oldValue else { return }
        UserDefaults.standard.set(hideInFullscreenEnabled, forKey: Self.hideInFullscreenDefaultsKey)
        applyFullscreenVisibility()
    }
}

private(set) var isOverlayScreenFullscreen: Bool = false

var hasAttentionRequiredSession: Bool {
    surfacedSessions.contains { $0.phase.requiresAttention }
}

// Pure decision function — exposed for unit tests.
static func shouldSuppressOverlayForFullscreen(
    hideInFullscreenEnabled: Bool,
    isOverlayScreenFullscreen: Bool,
    hasAttentionRequiredSession: Bool
) -> Bool {
    hideInFullscreenEnabled
        && isOverlayScreenFullscreen
        && !hasAttentionRequiredSession
}
```

Wiring:
- Register default `true` for `hideInFullscreenDefaultsKey` alongside existing defaults.
- On init: instantiate `FullscreenSpaceObserver`, set `onChange` callback that maps `Set<CGDirectDisplayID>` → `isOverlayScreenFullscreen`. The island's `displayID` is read from the same `NSScreen` `OverlayPanelController.resolveTargetScreen(preferredScreenID:)` returns (i.e. the resolved overlay screen at the moment of evaluation), via its `deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]` (already used by the controller for screen IDs). Then call `applyFullscreenVisibility()`.
- After AgentEvent application that may flip `hasAttentionRequiredSession`: invoke `applyFullscreenVisibility()` from a single existing post-mutation hook in `AppModel` (e.g. the place that already triggers UI side-effects after `state.apply(_:)`). Cheap and idempotent.

### `OverlayPanelController`

Two new methods:

```swift
func forceHide() {
    guard let panel else { return }
    panel.orderOut(nil)
    eventMonitors.stop()
}

func forceShowIfNeeded(model: AppModel, preferredScreenID: String?) {
    guard let panel else { return }
    if !panel.isVisible {
        positionPanel(panel, preferredScreenID: preferredScreenID, animated: false)
        panel.orderFrontRegardless()
    }
    startEventMonitoring()
}
```

`forceHide` differs from existing `hide()`: existing `hide()` only flips `ignoresMouseEvents`. We need full `orderOut` so the panel does not participate in Mission Control / `.fullScreenAuxiliary` Space membership while suppressed.

### `AppModel.applyFullscreenVisibility()`

Lives on `AppModel` (single owner of `hideInFullscreenEnabled`, `isOverlayScreenFullscreen`, `surfacedSessions`). Forwards to `overlayPanelController` directly — no new responsibility added to `OverlayUICoordinator`.

```swift
func applyFullscreenVisibility() {
    let suppress = AppModel.shouldSuppressOverlayForFullscreen(
        hideInFullscreenEnabled: hideInFullscreenEnabled,
        isOverlayScreenFullscreen: isOverlayScreenFullscreen,
        hasAttentionRequiredSession: hasAttentionRequiredSession
    )

    if suppress {
        overlayPanelController.forceHide()
    } else {
        overlayPanelController.forceShowIfNeeded(
            model: self,
            preferredScreenID: preferredOverlayScreenID
        )
    }
}
```

Call sites:
- After observer fires (screen set changed, or island screen changed).
- `hideInFullscreenEnabled` `didSet`.
- After AgentEvent reducer mutations that may flip `hasAttentionRequiredSession` (centralized: invoke at the tail of the existing post-mutation hook).

### Settings UI

In `Sources/OpenIslandApp/Views/SettingsView.swift`, `GeneralSettingsPane > Section("settings.general.behavior")`, add **above** the existing `autoCollapse` row:

```swift
Toggle(lang.t("settings.general.hideFullscreen"), isOn: Binding(
    get: { model.hideInFullscreenEnabled },
    set: { model.hideInFullscreenEnabled = $0 }
))
```

No new localization strings required — `settings.general.hideFullscreen` already exists in `en`, `zh-Hans`, `zh-Hant`.

## Data flow

### Normal (non-attention) flow
1. User enters fullscreen → `activeSpaceDidChangeNotification` fires.
2. Observer recomputes screen set → `AppModel.isOverlayScreenFullscreen` flips `true`.
3. `applyFullscreenVisibility()` → `forceHide()` → panel `orderOut`, monitors stopped.
4. User exits fullscreen → reverse path → `forceShowIfNeeded()`.

### Attention-required override
1. Fullscreen active, panel suppressed.
2. Agent emits `PreToolUse` → reducer updates session phase to `.waitingForApproval` → `hasAttentionRequiredSession` becomes `true`.
3. `applyFullscreenVisibility()` re-evaluates → suppress = false → `forceShowIfNeeded()`.
4. Existing notification path runs (`coordinator.notchOpen(reason: .notification, ...)`), with sound/haptic per existing settings.
5. User responds → phase becomes `.running` or `.completed` → `hasAttentionRequiredSession` becomes `false`.
6. `applyFullscreenVisibility()` re-evaluates → if still fullscreen, `forceHide()` again.
7. Subsequent `.completed` notifications: stay silent (suppress = true).

### Edge cases handled
- **Island screen migration** (external display unplug, user moves overlay target): `didChangeScreenParameters` triggers recompute; observer pulls fresh `NSScreen.screens`; AppModel re-resolves overlay screen displayID.
- **Toggle flipped at runtime**: `didSet` calls `applyFullscreenVisibility()` immediately.
- **Pre-existing attention session when user enters fullscreen**: suppress = false → panel keeps showing; expected.
- **Panel not yet created**: `forceHide` and `forceShowIfNeeded` are guarded against `panel == nil`.

## Testing

### Unit tests

`OpenIslandAppTests/FullscreenSpaceObserverTests`:
- `screenIsCovered` returns `true` for bounds equal to screen frame.
- Returns `false` for bounds equal to `visibleFrame` (menu bar visible — not fullscreen).
- Returns `false` for bounds smaller than frame.
- Returns `false` for bounds larger than frame (multi-screen spanning, defensive).

`OpenIslandAppTests/FullscreenOverlayPolicyTests`:
- 8-row truth table over `(hideInFullscreenEnabled, isOverlayScreenFullscreen, hasAttentionRequiredSession)` against `shouldSuppressOverlayForFullscreen`. Only `(true, true, false)` returns `true`.

### Manual verification (PR test plan)
1. Default-on after upgrade: toggle visible in *General → Behavior*, checked by default.
2. Safari fullscreen on island's screen → overlay disappears (closed bar + any open panel).
3. Exit fullscreen → overlay reappears immediately.
4. In fullscreen, trigger Claude Code `PreToolUse` request → notification card pops; Allow / Deny works; after response, overlay re-hides.
5. In fullscreen, trigger a `completed` event → no notification; on exiting fullscreen, completion is reflected in island state.
6. Toggle off → overlay remains visible while in fullscreen (legacy behavior).
7. Multi-display: external display in fullscreen, island on built-in screen → overlay visible.
8. Multi-display: built-in screen (island) in fullscreen, external display unaffected → overlay hidden, no errors elsewhere.
9. Hot-plug external display while in fullscreen → no crash; state reconciles within ~1 frame.
10. Mission Control invocation does not cause overlay flicker.

End-to-end fullscreen automation is not pursued — Spaces transitions cannot be reliably driven from `swift test`.

## Out-of-scope / explicit non-changes
- The `panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]` flags stay as-is; suppression is dynamic via `orderOut`.
- No changes to notification sound, haptics, or auto-collapse timing.
- No new localization strings.
- No changes to closed-island idle-edge mode logic.

## Rollout
- Single feature branch → PR to `main`.
- Bilingual release-note entry under "Behavior":
  - **Behavior**: Hide the island automatically when an app is in fullscreen on the same display; urgent agent prompts still surface as notifications. Toggle in *General → Behavior*. Defaults to on.
  - 行为：当同屏应用进入全屏时自动隐藏灵动岛；agent 的紧急请求仍会以通知形式出现。可在 *常规 → 行为* 中关闭，默认开启。
