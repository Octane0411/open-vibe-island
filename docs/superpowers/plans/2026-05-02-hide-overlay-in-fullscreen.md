# Hide Overlay In Fullscreen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-hide the Open Island overlay (closed bar + opened panel) when a native fullscreen Space is active on the island's display, while still surfacing attention-required agent prompts. Toggleable in settings, default on.

**Architecture:** A new `FullscreenSpaceObserver` watches `NSWorkspace.activeSpaceDidChangeNotification` + `NSApplication.didChangeScreenParametersNotification` and uses `CGWindowListCopyWindowInfo` to compute the set of fullscreen displays. `AppModel` owns the policy decision (`shouldSuppressOverlayForFullscreen`) combining the user toggle, the fullscreen state of the island's screen, and whether any session needs attention. `OverlayPanelController` gets `forceHide`/`forceShowIfNeeded` that flip `NSPanel.orderOut`/`orderFrontRegardless` and stop/start mouse-event monitors.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Swift Testing (`Testing` module). macOS 14+.

**Spec:** `docs/superpowers/specs/2026-05-02-hide-overlay-in-fullscreen-design.md`

**Branch:** `feat/hide-overlay-in-fullscreen` (worktree at `.claude/worktrees/feat-hide-overlay-fullscreen/`).

---

## Task 1: Pure helper — `FullscreenSpaceObserver.screenIsCovered`

**Files:**
- Create: `Sources/OpenIslandApp/FullscreenSpaceObserver.swift`
- Test: `Tests/OpenIslandAppTests/FullscreenSpaceObserverTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/OpenIslandAppTests/FullscreenSpaceObserverTests.swift`:

```swift
import AppKit
import Testing
@testable import OpenIslandApp

struct FullscreenSpaceObserverTests {
    @Test
    func coverageReturnsTrueWhenBoundsEqualScreenFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        #expect(FullscreenSpaceObserver.screenIsCovered(byTopWindowBounds: frame, screenFrame: frame))
    }

    @Test
    func coverageReturnsFalseWhenBoundsLeaveMenuBar() {
        // Screen frame includes menu bar; window stops at the menu bar bottom.
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let bounds = CGRect(x: 0, y: 25, width: 1_440, height: 875)
        #expect(!FullscreenSpaceObserver.screenIsCovered(byTopWindowBounds: bounds, screenFrame: frame))
    }

    @Test
    func coverageReturnsFalseWhenBoundsAreSmaller() {
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(!FullscreenSpaceObserver.screenIsCovered(byTopWindowBounds: bounds, screenFrame: frame))
    }

    @Test
    func coverageReturnsFalseWhenBoundsExceedScreen() {
        // Defensive: a window that spans multiple screens should not be treated
        // as fullscreen on either of them.
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let bounds = CGRect(x: -100, y: 0, width: 3_000, height: 900)
        #expect(!FullscreenSpaceObserver.screenIsCovered(byTopWindowBounds: bounds, screenFrame: frame))
    }

    @Test
    func coverageAllowsOnePixelTolerance() {
        // CGWindowListCopyWindowInfo bounds are sometimes off by a sub-pixel
        // due to coordinate rounding; the helper must tolerate ±1pt.
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let bounds = CGRect(x: 0, y: 0, width: 1_439, height: 900)
        #expect(FullscreenSpaceObserver.screenIsCovered(byTopWindowBounds: bounds, screenFrame: frame))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FullscreenSpaceObserverTests`
Expected: FAIL — `FullscreenSpaceObserver` is not defined.

- [ ] **Step 3: Create file with minimal implementation**

Create `Sources/OpenIslandApp/FullscreenSpaceObserver.swift`:

```swift
import AppKit
import Foundation

@MainActor
final class FullscreenSpaceObserver {
    /// Pure helper: does the topmost layer-0 window bound completely cover
    /// the screen frame (i.e. extend across the menu-bar area too)?
    /// A ±1pt tolerance absorbs sub-pixel rounding in `CGWindowListCopyWindowInfo`.
    static func screenIsCovered(byTopWindowBounds bounds: CGRect, screenFrame: CGRect) -> Bool {
        let widthDelta = abs(bounds.width - screenFrame.width)
        let heightDelta = abs(bounds.height - screenFrame.height)
        let originXDelta = abs(bounds.minX - screenFrame.minX)
        let originYDelta = abs(bounds.minY - screenFrame.minY)
        return widthDelta <= 1
            && heightDelta <= 1
            && originXDelta <= 1
            && originYDelta <= 1
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FullscreenSpaceObserverTests`
Expected: PASS — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenIslandApp/FullscreenSpaceObserver.swift Tests/OpenIslandAppTests/FullscreenSpaceObserverTests.swift
git commit -m "feat(overlay): add FullscreenSpaceObserver coverage helper"
```

---

## Task 2: Pure helper — `AppModel.shouldSuppressOverlayForFullscreen`

**Files:**
- Modify: `Sources/OpenIslandApp/AppModel.swift` (add static helper near other class-level helpers, e.g. just below `static let defaultStatusColors`)
- Test: `Tests/OpenIslandAppTests/FullscreenOverlayPolicyTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/OpenIslandAppTests/FullscreenOverlayPolicyTests.swift`:

```swift
import Testing
@testable import OpenIslandApp

struct FullscreenOverlayPolicyTests {
    @Test
    func suppressOnlyWhenEnabledAndFullscreenAndNoAttention() {
        // (hideEnabled, isFullscreen, hasAttention) -> expectedSuppress
        let cases: [(Bool, Bool, Bool, Bool)] = [
            (false, false, false, false),
            (false, false, true,  false),
            (false, true,  false, false),
            (false, true,  true,  false),
            (true,  false, false, false),
            (true,  false, true,  false),
            (true,  true,  false, true),   // the only case that suppresses
            (true,  true,  true,  false),
        ]
        for (enabled, fs, attention, expected) in cases {
            let actual = AppModel.shouldSuppressOverlayForFullscreen(
                hideInFullscreenEnabled: enabled,
                isOverlayScreenFullscreen: fs,
                hasAttentionRequiredSession: attention
            )
            #expect(actual == expected, "enabled=\(enabled) fs=\(fs) attention=\(attention)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FullscreenOverlayPolicyTests`
Expected: FAIL — `shouldSuppressOverlayForFullscreen` is not defined.

- [ ] **Step 3: Add the static helper to `AppModel`**

In `Sources/OpenIslandApp/AppModel.swift`, find the `static let defaultStatusColors: [SessionPhase: String] = [...]` block (around line 30) and add directly after its closing `]`:

```swift
    /// Pure decision function exposed for unit tests.
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

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FullscreenOverlayPolicyTests`
Expected: PASS — all 8 truth-table rows pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenIslandApp/AppModel.swift Tests/OpenIslandAppTests/FullscreenOverlayPolicyTests.swift
git commit -m "feat(overlay): add fullscreen suppression policy helper"
```

---

## Task 3: Runtime — `FullscreenSpaceObserver` class

**Files:**
- Modify: `Sources/OpenIslandApp/FullscreenSpaceObserver.swift`

No new test — the class wraps `NSWorkspace` notifications and `CGWindowListCopyWindowInfo`, neither of which is meaningful to mock. Coverage is via Task 1's pure helper plus the manual smoke checklist.

- [ ] **Step 1: Add notification observers, scan logic, and onChange callback**

Replace the entire body of `Sources/OpenIslandApp/FullscreenSpaceObserver.swift` with:

```swift
import AppKit
import Foundation

@MainActor
final class FullscreenSpaceObserver {
    /// Called when the set of fullscreen displays changes. Set BEFORE `start()`.
    var onChange: ((Set<CGDirectDisplayID>) -> Void)?

    private var lastValue: Set<CGDirectDisplayID> = []
    private var workspaceObserver: NSObjectProtocol?
    private var screenParamsObserver: NSObjectProtocol?

    deinit {
        // Tokens are released; nothing to invalidate beyond the notification center entries.
        // Removal must happen on main; rely on `stop()` being called explicitly.
    }

    func start() {
        guard workspaceObserver == nil else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }

        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }

        // Initial sample so AppModel has a correct value before any space changes.
        recompute()
    }

    func stop() {
        if let token = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            workspaceObserver = nil
        }
        if let token = screenParamsObserver {
            NotificationCenter.default.removeObserver(token)
            screenParamsObserver = nil
        }
    }

    /// Forces a re-scan. Public so AppModel can trigger an evaluation right
    /// after the panel is created (initial state).
    func recompute() {
        let value = currentFullscreenDisplays()
        guard value != lastValue else { return }
        lastValue = value
        onChange?(value)
    }

    // MARK: - Scan

    private func currentFullscreenDisplays() -> Set<CGDirectDisplayID> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // Layer-0 windows are regular app windows. Higher layers are status
        // bar / dock / system overlays.
        let appWindows = raw.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }

        var result: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let displayID = Self.displayID(for: screen) else { continue }
            // CGWindowList bounds are in CG (top-left origin) coordinates.
            // NSScreen.frame is bottom-left; convert by flipping against the
            // primary screen height.
            let primary = NSScreen.screens.first
            let primaryHeight = primary?.frame.height ?? screen.frame.height
            let cgScreenFrame = CGRect(
                x: screen.frame.minX,
                y: primaryHeight - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            // Take the topmost (= first) layer-0 window whose bounds intersect
            // this screen's CG frame.
            let topWindow = appWindows.first { entry in
                guard let dict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                      let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else {
                    return false
                }
                return bounds.intersects(cgScreenFrame)
            }
            guard let dict = topWindow?[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else {
                continue
            }
            if Self.screenIsCovered(byTopWindowBounds: bounds, screenFrame: cgScreenFrame) {
                result.insert(displayID)
            }
        }
        return result
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    /// Pure helper: does the topmost layer-0 window bound completely cover
    /// the screen frame (i.e. extend across the menu-bar area too)?
    /// A ±1pt tolerance absorbs sub-pixel rounding in `CGWindowListCopyWindowInfo`.
    static func screenIsCovered(byTopWindowBounds bounds: CGRect, screenFrame: CGRect) -> Bool {
        let widthDelta = abs(bounds.width - screenFrame.width)
        let heightDelta = abs(bounds.height - screenFrame.height)
        let originXDelta = abs(bounds.minX - screenFrame.minX)
        let originYDelta = abs(bounds.minY - screenFrame.minY)
        return widthDelta <= 1
            && heightDelta <= 1
            && originXDelta <= 1
            && originYDelta <= 1
    }
}
```

- [ ] **Step 2: Re-run Task 1 tests to confirm helper still passes**

Run: `swift test --filter FullscreenSpaceObserverTests`
Expected: PASS — all 5 tests still pass.

- [ ] **Step 3: Build to confirm class compiles**

Run: `swift build`
Expected: success (no errors).

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenIslandApp/FullscreenSpaceObserver.swift
git commit -m "feat(overlay): scan fullscreen displays via CGWindowList"
```

---

## Task 4: `OverlayPanelController.forceHide` / `forceShowIfNeeded`

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift` — insert the two methods directly after the existing `setInteractive(_:)` (around line 97).

- [ ] **Step 1: Add the two methods**

In `Sources/OpenIslandApp/OverlayPanelController.swift`, find the `setInteractive(_:)` method (around line 86–97). Directly after its closing `}`, insert:

```swift
    /// Fully orders the panel out of the window list and stops mouse-event
    /// monitors. Used to make the overlay disappear from fullscreen Spaces
    /// (Mission Control, app fullscreen) when the user has opted in.
    func forceHide() {
        guard let panel else { return }
        panel.orderOut(nil)
        eventMonitors.stop()
    }

    /// Restores the panel after `forceHide()`. Re-positions it on the resolved
    /// target screen and re-arms the event monitors. No-op if the panel is
    /// already visible.
    func forceShowIfNeeded(model: AppModel, preferredScreenID: String?) {
        self.model = model
        guard let panel else { return }
        if !panel.isVisible {
            positionPanel(panel, preferredScreenID: preferredScreenID, animated: false)
            panel.orderFrontRegardless()
            panel.ignoresMouseEvents = true
            panel.acceptsMouseMovedEvents = false
        }
        startEventMonitoring()
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/OpenIslandApp/OverlayPanelController.swift
git commit -m "feat(overlay): add forceHide/forceShowIfNeeded controls"
```

---

## Task 5: Wire into `AppModel`

**Files:**
- Modify: `Sources/OpenIslandApp/AppModel.swift`

This task adds: defaults key, stored toggle, fullscreen state, derived `hasAttentionRequiredSession`, observer instance, init wiring, didSet hook, and post-mutation hook in `applyTrackedEvent`.

- [ ] **Step 1: Add the defaults key**

In `Sources/OpenIslandApp/AppModel.swift`, find the block of `private static let ...DefaultsKey` declarations (around line 18–28). Add after the existing `suppressFrontmostNotificationsDefaultsKey` line:

```swift
    private static let hideInFullscreenDefaultsKey = "app.hideInFullscreen"
```

- [ ] **Step 2: Add the stored toggle and fullscreen state**

In the same file, find the `var suppressFrontmostNotifications: Bool = true { ... }` block (around line 255–260). Directly after its closing `}`, insert:

```swift
    var hideInFullscreenEnabled: Bool = true {
        didSet {
            guard hasFinishedInit, hideInFullscreenEnabled != oldValue else { return }
            UserDefaults.standard.set(hideInFullscreenEnabled, forKey: Self.hideInFullscreenDefaultsKey)
            applyFullscreenVisibility()
        }
    }

    private(set) var isOverlayScreenFullscreen: Bool = false
```

- [ ] **Step 3: Add the observer instance and `hasAttentionRequiredSession`**

Still in `AppModel.swift`, find a suitable spot near the other coordinator properties (e.g. just below `let updateChecker = UpdateChecker()` around line 63). Add:

```swift
    private let fullscreenObserver = FullscreenSpaceObserver()

    var hasAttentionRequiredSession: Bool {
        surfacedSessions.contains { $0.phase.requiresAttention }
    }
```

- [ ] **Step 4: Register the default and read it during init**

In `AppModel.init`, find the `UserDefaults.standard.register(defaults: [...])` block (around line 492–497). Add the new key with default value `true`:

```swift
        UserDefaults.standard.register(defaults: [
            Self.showDockIconDefaultsKey: true,
            Self.hapticFeedbackEnabledDefaultsKey: false,
            Self.completionReplyEnabledDefaultsKey: false,
            Self.suppressFrontmostNotificationsDefaultsKey: true,
            Self.hideInFullscreenDefaultsKey: true,
        ])
```

Then, immediately after the existing `suppressFrontmostNotifications = UserDefaults.standard.bool(...)` line (around line 502), add:

```swift
        hideInFullscreenEnabled = UserDefaults.standard.bool(forKey: Self.hideInFullscreenDefaultsKey)
```

- [ ] **Step 5: Start the observer at the end of init**

Still in `AppModel.init`, find where `hasFinishedInit = true` is set (around line 609). Directly **before** that line, insert:

```swift
        fullscreenObserver.onChange = { [weak self] fullscreenDisplays in
            self?.handleFullscreenDisplaysChanged(fullscreenDisplays)
        }
        fullscreenObserver.start()
```

- [ ] **Step 6: Add the handler and visibility application methods**

Find a location in `AppModel` near other overlay-related forwarders (e.g. just before `func notchOpen(...)` forwarder around line 912, or grouped with the other internal helpers — anywhere is fine as long as it compiles). Add:

```swift
    private func handleFullscreenDisplaysChanged(_ fullscreenDisplays: Set<CGDirectDisplayID>) {
        let resolvedScreen = OverlayDisplayResolver.resolveTargetScreen(
            preferredScreenID: overlay.preferredOverlayScreenIDForExternalUse
        )
        let islandDisplayID = resolvedScreen.flatMap { FullscreenSpaceObserver.displayID(for: $0) }
        let newValue = islandDisplayID.map { fullscreenDisplays.contains($0) } ?? false
        guard newValue != isOverlayScreenFullscreen else { return }
        isOverlayScreenFullscreen = newValue
        applyFullscreenVisibility()
    }

    func applyFullscreenVisibility() {
        let suppress = Self.shouldSuppressOverlayForFullscreen(
            hideInFullscreenEnabled: hideInFullscreenEnabled,
            isOverlayScreenFullscreen: isOverlayScreenFullscreen,
            hasAttentionRequiredSession: hasAttentionRequiredSession
        )
        if suppress {
            overlay.overlayPanelController.forceHide()
        } else {
            overlay.overlayPanelController.forceShowIfNeeded(
                model: self,
                preferredScreenID: overlay.preferredOverlayScreenIDForExternalUse
            )
        }
    }
```

> **Note on `OverlayDisplayResolver.resolveTargetScreen` and `preferredOverlayScreenIDForExternalUse`**: these don't exist yet as public surfaces. Step 7 expands access. Step 8 calls the post-mutation hook.

- [ ] **Step 7: Expose the screen resolver and preferred screen ID**

`OverlayDisplayResolver.resolveTargetScreen` is currently used only inside `OverlayPanelController` via a private method. Add a public static helper. In `Sources/OpenIslandApp/OverlayDisplayConfiguration.swift`, find the `enum OverlayDisplayResolver` block and add (matching existing helper style):

```swift
    /// Public façade for the same screen-resolution logic
    /// `OverlayPanelController` uses internally. Returns the screen the
    /// island will be placed on, or nil if no screens are connected.
    static func resolveTargetScreen(preferredScreenID: String?) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        if let preferredScreenID,
           let screen = screens.first(where: { screenID(for: $0) == preferredScreenID }) {
            return screen
        }
        if let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }
        return NSScreen.main ?? screens[0]
    }
```

In `Sources/OpenIslandApp/OverlayUICoordinator.swift`, find the `private var preferredOverlayScreenID: String?` property (around line 76). Directly after that block add:

```swift
    /// Public read-only mirror of `preferredOverlayScreenID` so `AppModel`
    /// can pass it through to the panel controller without taking a
    /// dependency on `OverlayUICoordinator` internals.
    var preferredOverlayScreenIDForExternalUse: String? { preferredOverlayScreenID }
```

`overlay.overlayPanelController` referenced in Step 6 must also be reachable from `AppModel`. In `OverlayUICoordinator.swift`, find the `private let overlayPanelController = OverlayPanelController()` declaration (search the file). If it is `private`, change to:

```swift
    let overlayPanelController = OverlayPanelController()
```

- [ ] **Step 8: Hook into `applyTrackedEvent`**

In `AppModel.swift`, find `func applyTrackedEvent(...)` (around line 1180). Locate the line `refreshOverlayPlacementIfVisible()` (around line 1213). Directly **after** that line, insert:

```swift
        applyFullscreenVisibility()
```

(This catches phase transitions that flip `hasAttentionRequiredSession`. The call is cheap and idempotent.)

- [ ] **Step 9: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 10: Run all tests**

Run: `swift test`
Expected: all existing tests pass plus the two new test files.

- [ ] **Step 11: Commit**

```bash
git add Sources/OpenIslandApp/AppModel.swift Sources/OpenIslandApp/OverlayDisplayConfiguration.swift Sources/OpenIslandApp/OverlayUICoordinator.swift
git commit -m "feat(overlay): wire fullscreen suppression into AppModel"
```

---

## Task 6: Settings toggle

**Files:**
- Modify: `Sources/OpenIslandApp/Views/SettingsView.swift`

- [ ] **Step 1: Add the toggle to the General → Behavior section**

Find `Section(lang.t("settings.general.behavior")) { ... }` in `GeneralSettingsPane` (around line 207). Directly **after** the `Toggle(lang.t("settings.general.autoCollapse"), isOn: .constant(true))` line, insert:

```swift
                Toggle(lang.t("settings.general.hideFullscreen"), isOn: Binding(
                    get: { model.hideInFullscreenEnabled },
                    set: { model.hideInFullscreenEnabled = $0 }
                ))
```

(Localization keys for `settings.general.hideFullscreen` already exist in en/zh-Hans/zh-Hant — no string changes needed.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/OpenIslandApp/Views/SettingsView.swift
git commit -m "feat(settings): add hide-in-fullscreen toggle"
```

---

## Task 7: Smoke verification & PR

- [ ] **Step 1: Refresh the dev signing & dev bundle, then launch**

Run:

```bash
zsh scripts/launch-dev-app.sh
```

Expected: `~/Applications/Open Island Dev.app` launches with the rebuilt binary; menu-bar icon appears.

- [ ] **Step 2: Run through the manual checklist**

Walk through the 10-step manual checklist from the spec (`docs/superpowers/specs/2026-05-02-hide-overlay-in-fullscreen-design.md` → "Manual verification"). For each step, note whether it passes. The critical ones:

1. Toggle visible in Settings → General → Behavior, default ON.
2. Safari → Enter Full Screen on the island's screen → island disappears.
3. Exit fullscreen → island reappears.
4. While fullscreen, run a Claude Code action that triggers PreToolUse (e.g. `Bash(rm test.txt)` against an unapproved path) → notification card pops; Allow/Deny works; after response, island re-hides.
5. While fullscreen, let an agent finish a task (`completed`) → no notification appears; on exiting fullscreen, completion is reflected in island state.
6. Toggle OFF → repeat #2: island stays visible during fullscreen.
7. External display fullscreen, island on built-in → island visible.
8. Built-in fullscreen, island on built-in, external untouched → island hidden, no errors elsewhere.
9. Hot-plug external display while fullscreen → no crash.
10. Mission Control invocation → no overlay flicker.

- [ ] **Step 3: Push branch and open PR**

Run:

```bash
git push -u origin feat/hide-overlay-in-fullscreen
```

Then create the PR with `gh pr create` targeting `main`. Title: `feat: hide island in fullscreen with toggle`. Body must include:
- Summary (3 bullets)
- Test plan (paste the 10-step manual checklist with checkboxes)
- Reference to the spec and plan files

- [ ] **Step 4: Exit the worktree**

After the PR is open, hand control back to the user; do NOT auto-merge. Use `ExitWorktree` action `keep` so the branch and worktree remain available for follow-up review fixes.

---

## Self-Review Notes (kept inline)

Spec coverage: every numbered decision (1–4) and every architecture item (`FullscreenSpaceObserver`, `forceHide`, `applyFullscreenVisibility`, settings toggle, `hasAttentionRequiredSession`) maps to a task above. Manual checklist items 1–10 map 1:1 to Task 7 Step 2.

Type / signature consistency:
- `FullscreenSpaceObserver.screenIsCovered(byTopWindowBounds:screenFrame:)` — defined Task 1, re-used Task 3.
- `FullscreenSpaceObserver.displayID(for:)` — defined Task 3, called Task 5.
- `AppModel.shouldSuppressOverlayForFullscreen(hideInFullscreenEnabled:isOverlayScreenFullscreen:hasAttentionRequiredSession:)` — defined Task 2, called Task 5.
- `OverlayPanelController.forceHide()` / `forceShowIfNeeded(model:preferredScreenID:)` — defined Task 4, called Task 5.
- `OverlayDisplayResolver.resolveTargetScreen(preferredScreenID:)` — defined Task 5 Step 7, called Task 5 Step 6.
- `OverlayUICoordinator.preferredOverlayScreenIDForExternalUse` and `overlayPanelController` access — exposed Task 5 Step 7.
