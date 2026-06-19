# Hide Fullscreen Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a default-off setting that lets users hide Open Island in fullscreen application Spaces.

**Architecture:** `AppModel` owns and persists the new Boolean preference. `SettingsView` exposes it in General > Behavior. `OverlayUICoordinator` forwards preference changes to `OverlayPanelController`, which centralizes `NSWindow.CollectionBehavior` construction and omits `.canJoinAllSpaces` plus `.fullScreenAuxiliary` when the option is enabled.

**Tech Stack:** Swift 6.2 package, SwiftUI, AppKit `NSPanel`, Swift Testing.

---

## Files

- Modify: `Sources/OpenIslandApp/AppModel.swift`
- Modify: `Sources/OpenIslandApp/OverlayUICoordinator.swift`
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift`
- Modify: `Sources/OpenIslandApp/Views/SettingsView.swift`
- Modify: `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift`
- Modify: `Tests/OpenIslandAppTests/AppModelSessionListTests.swift`

## Verification Constraint

This machine currently has Command Line Tools selected at `/Library/Developer/CommandLineTools` and no full Xcode app under `/Applications`. Baseline `swift test` fails before running tests with `no such module 'Testing'`. Run the listed test commands anyway to preserve the red/green workflow as far as the environment allows, and use `swift build` for production compile verification.

### Task 1: Panel Collection Behavior

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift`
- Test: `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift`

- [ ] **Step 1: Write failing tests for collection behavior**

Add these tests near the existing activation tests in `OverlayPanelControllerTests`:

```swift
    @Test
    func collectionBehaviorIncludesFullscreenAuxiliaryByDefault() {
        let behavior = OverlayPanelController.collectionBehavior(hideFullscreen: false)

        #expect(behavior.contains(.fullScreenAuxiliary))
        #expect(behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.ignoresCycle))
        #expect(behavior.contains(.stationary))
    }

    @Test
    func collectionBehaviorExcludesFullscreenAuxiliaryWhenFullscreenHidingIsEnabled() {
        let behavior = OverlayPanelController.collectionBehavior(hideFullscreen: true)

        #expect(!behavior.contains(.fullScreenAuxiliary))
        #expect(!behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.ignoresCycle))
        #expect(behavior.contains(.stationary))
    }
```

- [ ] **Step 2: Run targeted test to verify it fails**

Run:

```bash
swift test --filter OverlayPanelControllerTests.collectionBehaviorIncludesFullscreenAuxiliaryByDefault
```

Expected in a fully configured Xcode environment: failure because `OverlayPanelController.collectionBehavior(hideFullscreen:)` does not exist yet.

Expected on this machine until Xcode is installed or selected: test build stops earlier with `no such module 'Testing'`.

- [ ] **Step 3: Implement collection behavior helper and application**

In `OverlayPanelController`, add a stored preference:

```swift
    private var hideFullscreen = false
```

Add this helper near `shouldActivatePanel`:

```swift
    nonisolated static func collectionBehavior(hideFullscreen: Bool) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.ignoresCycle, .stationary]
        if hideFullscreen {
            return behavior
        }

        behavior.insert(.canJoinAllSpaces)
        behavior.insert(.fullScreenAuxiliary)
        return behavior
    }
```

Add this method near `setInteractive`:

```swift
    func setHideFullscreen(_ hideFullscreen: Bool) {
        guard self.hideFullscreen != hideFullscreen else {
            return
        }

        self.hideFullscreen = hideFullscreen
        panel?.collectionBehavior = Self.collectionBehavior(hideFullscreen: hideFullscreen)
    }
```

Replace the current `panel.collectionBehavior = [...]` assignment in `makePanel(model:)` with:

```swift
        panel.collectionBehavior = Self.collectionBehavior(hideFullscreen: hideFullscreen)
```

- [ ] **Step 4: Run targeted test again**

Run:

```bash
swift test --filter OverlayPanelControllerTests.collectionBehavior
```

Expected in a fully configured Xcode environment: the two collection behavior tests pass.

Expected on this machine until Xcode is installed or selected: test build stops earlier with `no such module 'Testing'`.

- [ ] **Step 5: Commit panel behavior slice**

Run:

```bash
git add Sources/OpenIslandApp/OverlayPanelController.swift Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift
git commit -m "feat: configure fullscreen overlay behavior"
```

### Task 2: Persisted Setting And Settings UI

**Files:**
- Modify: `Sources/OpenIslandApp/AppModel.swift`
- Modify: `Sources/OpenIslandApp/OverlayUICoordinator.swift`
- Modify: `Sources/OpenIslandApp/Views/SettingsView.swift`
- Modify: `Tests/OpenIslandAppTests/AppModelSessionListTests.swift`

- [ ] **Step 1: Write failing AppModel default test**

In `AppModelSessionListTests.init()`, add this key to the cleanup array:

```swift
            "app.hideFullscreen",
```

Add this test near the top of `AppModelSessionListTests`:

```swift
    @Test
    func hideFullscreenDefaultsToFalse() {
        UserDefaults.standard.removeObject(forKey: "app.hideFullscreen")

        let model = AppModel()

        #expect(model.hideFullscreen == false)
    }
```

- [ ] **Step 2: Run targeted test to verify it fails**

Run:

```bash
swift test --filter AppModelSessionListTests.hideFullscreenDefaultsToFalse
```

Expected in a fully configured Xcode environment: failure because `AppModel.hideFullscreen` does not exist yet.

Expected on this machine until Xcode is installed or selected: test build stops earlier with `no such module 'Testing'`.

- [ ] **Step 3: Add persisted AppModel setting**

In `AppModel`, add this defaults key near the other app defaults keys:

```swift
    private static let hideFullscreenDefaultsKey = "app.hideFullscreen"
```

Add this property near `suppressFrontmostNotifications`:

```swift
    var hideFullscreen: Bool = false {
        didSet {
            guard hasFinishedInit, hideFullscreen != oldValue else { return }
            UserDefaults.standard.set(hideFullscreen, forKey: Self.hideFullscreenDefaultsKey)
            overlay.setHideFullscreen(hideFullscreen)
        }
    }
```

Add this registered default in `init`:

```swift
            Self.hideFullscreenDefaultsKey: false,
```

Load the value in `init` after `suppressFrontmostNotifications`:

```swift
        hideFullscreen = UserDefaults.standard.bool(forKey: Self.hideFullscreenDefaultsKey)
```

After `overlay.appModel = self`, pass the initial value:

```swift
        overlay.setHideFullscreen(hideFullscreen)
```

- [ ] **Step 4: Forward the preference through OverlayUICoordinator**

In `OverlayUICoordinator`, add this method near `ensureOverlayPanel()`:

```swift
    func setHideFullscreen(_ hideFullscreen: Bool) {
        overlayPanelController.setHideFullscreen(hideFullscreen)
    }
```

- [ ] **Step 5: Add settings toggle**

In `GeneralSettingsPane`, add this Toggle in the Behavior section after `completionReplyEnabled` and before `suppressFrontmostNotifications`:

```swift
                Toggle(lang.t("settings.general.hideFullscreen"), isOn: Binding(
                    get: { model.hideFullscreen },
                    set: { model.hideFullscreen = $0 }
                ))
```

- [ ] **Step 6: Run build and targeted tests**

Run:

```bash
swift build
swift test --filter AppModelSessionListTests.hideFullscreenDefaultsToFalse
swift test --filter OverlayPanelControllerTests.collectionBehavior
```

Expected in a fully configured Xcode environment: build passes and targeted tests pass.

Expected on this machine until Xcode is installed or selected: `swift build` passes, while `swift test` stops earlier with `no such module 'Testing'`.

- [ ] **Step 7: Commit setting and UI slice**

Run:

```bash
git add Sources/OpenIslandApp/AppModel.swift Sources/OpenIslandApp/OverlayUICoordinator.swift Sources/OpenIslandApp/Views/SettingsView.swift Tests/OpenIslandAppTests/AppModelSessionListTests.swift
git commit -m "feat: add hide fullscreen setting"
```

### Task 3: Final Verification And Push

**Files:**
- No new files.

- [ ] **Step 1: Inspect final diff**

Run:

```bash
git status -sb
git diff --stat fork/feat/hide-fullscreen
```

Expected: clean status after commits, with code and test changes committed on `feat/hide-fullscreen`.

- [ ] **Step 2: Run available verification**

Run:

```bash
swift build
swift test
```

Expected on this machine until Xcode is installed or selected: `swift build` passes; `swift test` fails with `no such module 'Testing'`.

- [ ] **Step 3: Push feature branch to fork**

Run:

```bash
git push fork feat/hide-fullscreen
```

Expected: feature branch updates on `ForeverHYX/open-vibe-island`.
