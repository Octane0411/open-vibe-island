# Remove Notch Widgets — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Strip the Notch widgets slot system from the codebase so the rest of `feat/notch-personalization` can be upstreamed cleanly. Keep pets, ambient theme, celebrations, project colors, codeburn `$ today`, and all bug fixes.

**Architecture:** A single forward removal commit on top of `feat/notch-personalization`. Delete the slot abstraction; restore the closed-notch count badge as a direct child; rely on `headerNeedsCodeburn` to drive codeburn polling. Move the two pet/companion overlay views out of `NotchWidgets/` since the dir name no longer makes sense.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, SPM.

---

### Task 1: Delete Core widget model + tests

**Files:**
- Delete: `Sources/OpenIslandCore/NotchWidget.swift`
- Delete: `Tests/OpenIslandCoreTests/NotchWidgetTests.swift`

**Step 1: Remove the files**

```bash
git rm Sources/OpenIslandCore/NotchWidget.swift Tests/OpenIslandCoreTests/NotchWidgetTests.swift
```

**Step 2: Verify nothing in Core still references the types**

Run: `grep -rn "NotchWidgetKind\|NotchWidgetConfig" Sources/OpenIslandCore/ Tests/OpenIslandCoreTests/`
Expected: no output.

---

### Task 2: Delete widget views

**Files:**
- Delete: `Sources/OpenIslandApp/Views/NotchWidgets/NotchSlotHost.swift`
- Delete: `Sources/OpenIslandApp/Views/NotchWidgets/AgentToolIconWidget.swift`
- Delete: `Sources/OpenIslandApp/Views/NotchWidgets/DollarSpentWidget.swift`
- Delete: `Sources/OpenIslandApp/Views/NotchWidgets/ProjectChipWidget.swift`

**Step 1: Remove the files**

```bash
git rm Sources/OpenIslandApp/Views/NotchWidgets/NotchSlotHost.swift \
       Sources/OpenIslandApp/Views/NotchWidgets/AgentToolIconWidget.swift \
       Sources/OpenIslandApp/Views/NotchWidgets/DollarSpentWidget.swift \
       Sources/OpenIslandApp/Views/NotchWidgets/ProjectChipWidget.swift
```

---

### Task 3: Move pets/companion overlay out of NotchWidgets directory

**Files:**
- Move: `Sources/OpenIslandApp/Views/NotchWidgets/AnimatedCompanionPet.swift` → `Sources/OpenIslandApp/Views/Companion/AnimatedCompanionPet.swift`
- Move: `Sources/OpenIslandApp/Views/NotchWidgets/CompanionStateOverlay.swift` → `Sources/OpenIslandApp/Views/Companion/CompanionStateOverlay.swift`

**Step 1: Move files preserving git history**

```bash
mkdir -p Sources/OpenIslandApp/Views/Companion
git mv Sources/OpenIslandApp/Views/NotchWidgets/AnimatedCompanionPet.swift Sources/OpenIslandApp/Views/Companion/AnimatedCompanionPet.swift
git mv Sources/OpenIslandApp/Views/NotchWidgets/CompanionStateOverlay.swift Sources/OpenIslandApp/Views/Companion/CompanionStateOverlay.swift
rmdir Sources/OpenIslandApp/Views/NotchWidgets
```

**Step 2: Update header path comments inside the moved files**

In each moved file, change the leading `// Sources/OpenIslandApp/Views/NotchWidgets/...` comment to the new `Companion/` path.

---

### Task 4: Strip slot wiring from `IslandPanelView.swift`

**Files:**
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift`

**Step 1:** Closed notch — left side (around line 458-475)

Remove the `if model.notchWidgetConfig.closedLeft2 != .none { NotchSlotHost(...) }` block entirely. Drop the `+ (model.notchWidgetConfig.closedLeft2 != .none ? 30 : 0)` term from the `.frame(width:)` calculation.

**Step 2:** Closed notch — center (around line 482-510)

Remove the `centerSlotExternal` reference inside `CentralActivityLabel(isVisible: …)` so the label is `isExternalDisplayPlacement && hasClosedPresence`. Remove the entire `if isExternalDisplayPlacement && hasClosedPresence && model.notchWidgetConfig.centerSlotExternal != .none { NotchSlotHost(...) }` block.

**Step 3:** Closed notch — right side (around line 513-547)

Remove the R2 `if` block. Replace the R1 `NotchSlotHost(kind: model.notchWidgetConfig.closedRight1, ...)` with a direct `ClosedCountBadge(liveCount: model.liveSessionCount, tint: .white.opacity(0.85))` keeping the `.matchedGeometryEffect(id: "right-indicator", in: notchNamespace, isSource: true)` and `.frame(width: slotWidth)` modifiers. Drop the `+ (model.notchWidgetConfig.closedRight2 != .none ? 34 : 0)` from the outer frame.

**Step 4:** Expanded notch — notch-aware split-lane branch (around line 565-616)

Remove all three slot blocks (`expandedLeft2`, `expandedRight1`, `expandedRight2`).

**Step 5:** Expanded notch — flat header branch (around line 626-668)

Remove all three slot blocks (`expandedLeft2`, `expandedRight1`, `expandedRight2`).

**Step 6:** Verify no NotchSlotHost references remain

Run: `grep -n "NotchSlotHost\|notchWidgetConfig" Sources/OpenIslandApp/Views/IslandPanelView.swift`
Expected: no output.

---

### Task 5: Strip widget state from `AppModel.swift`

**Files:**
- Modify: `Sources/OpenIslandApp/AppModel.swift`

**Step 1:** Remove `private static let notchWidgetConfigDefaultsKey = "notch.widgetConfig"`.

**Step 2:** Remove the `var notchWidgetConfig: NotchWidgetConfig = .default { didSet { … } }` property and its `didSet` body that calls `updateCodeburnPolling()`.

**Step 3:** Simplify `updateCodeburnPolling()` to:

```swift
private func updateCodeburnPolling() {
    if headerNeedsCodeburn {
        if codeburnClient == nil {
            codeburnClient = CodeburnClient(runner: ProcessCodeburnRunner())
        }
        startCodeburnTimerIfNeeded()
    } else {
        codeburnTimerTask?.cancel()
        codeburnTimerTask = nil
    }
}
```

**Step 4:** Remove the load-from-UserDefaults block:

```swift
if let data = UserDefaults.standard.data(forKey: Self.notchWidgetConfigDefaultsKey),
   let decoded = try? JSONDecoder().decode(NotchWidgetConfig.self, from: data) {
    notchWidgetConfig = decoded
}
```

**Step 5:** Verify no slot references remain in the file

Run: `grep -n "notchWidgetConfig\|NotchWidgetConfig\|NotchWidgetKind" Sources/OpenIslandApp/AppModel.swift`
Expected: no output.

---

### Task 6: Strip widget pickers from `AppearanceSettingsPane.swift`

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift`

**Step 1:** Delete the entire `Section(lang.t("settings.notchWidgets.title")) { … }` block (closed pickers, divider, expanded pickers — roughly lines 92-154).

**Step 2:** Delete the `slotBinding(_:)` private helper (around line 480).

**Step 3:** Delete the `localizedKindName(_:)` private helper (around line 492).

**Step 4:** Verify no references remain

Run: `grep -n "NotchWidget\|notchWidgetConfig\|slotBinding\|localizedKindName\|settings.notchWidgets" Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift`
Expected: no output.

---

### Task 7: Drop notchWidgets localization keys

**Files:**
- Modify: `Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings`

**Step 1:** Remove every line matching `^"settings\.notchWidgets\.` from both files. There should be 15 keys per locale.

**Step 2:** Verify both files are clean

Run: `grep -n "notchWidgets" Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings`
Expected: no output.

---

### Task 8: Delete obsolete plan documents

**Files:**
- Delete: `docs/plans/2026-04-30-notch-personalization-design.md`
- Delete: `docs/plans/2026-04-30-notch-personalization.md`

**Step 1:** Remove both files

```bash
git rm docs/plans/2026-04-30-notch-personalization-design.md docs/plans/2026-04-30-notch-personalization.md
```

---

### Task 9: Build + test

**Step 1:** Run `swift build`
Expected: `Build complete!` with no errors.

**Step 2:** Run `swift test 2>&1 | tail -10`
Expected: all tests pass. Count drops by 4 from `NotchWidgetTests`.

**Step 3:** If anything fails, fix forward — do NOT add slot code back.

---

### Task 10: Commit

**Step 1:** Stage everything

```bash
git add -A
```

**Step 2:** Verify the diff scope

```bash
git diff --cached --stat
```

**Step 3:** Commit

```bash
git commit -m "$(cat <<'EOF'
refactor(app): remove Notch widgets slot system

Strip the closed-notch L2/R1/R2 + center external slot + expanded
L2/R1/R2 widget slot system. The feature was added in c416e3c and a
few follow-ups but didn't pull its weight: slots default to None and
the abstraction made the closed/expanded layout harder to reason
about. Delete the model, slot host, individual widget views, settings
pickers, persistence, localization keys, and tests.

Pets, companion state overlay, ambient theme, celebrations, project
colors, codeburn $ today (driven by headerNeedsCodeburn), and the
per-row context bar are unchanged. The closed-notch count badge is
restored as a direct child of the right HStack with the right-indicator
matchedGeometryEffect anchor.

Move AnimatedCompanionPet and CompanionStateOverlay out of
Views/NotchWidgets/ into Views/Companion/ since the dir name no longer
fits.
EOF
)"
```

---

### Task 11: Manual verification (dev app)

**Step 1:** Refresh and launch the dev bundle

```bash
zsh scripts/launch-dev-app.sh --skip-setup
```

**Step 2:** Confirm in the running app:

- Closed notch shows: avatar + (pet OR companion overlay) on the left, count badge on the right. No extra slots.
- Expanded notch shows: usage summary on the left, `$ today` pill + control buttons on the right. No extra slots between them.
- Settings → Appearance: pet picker, ambient toggle, celebrations toggle, project colors disclosure are all present. **"Notch widgets" section is gone.**
- Trigger a Claude Code session: pet animates, ambient gradient applies, celebration confetti fires on completion, `$ today` updates.

**Step 3:** If anything regresses, fix forward in a follow-up commit on this branch.

---

### Task 12: Push + open upstream PR

**Step 1:** Push the branch to the user's fork

```bash
git push -u origin feat/upstream-cleanup
```

**Step 2:** Open the PR

```bash
gh pr create \
  --repo Octane0411/open-vibe-island \
  --base main \
  --head h4ckm1n-dev:feat/upstream-cleanup \
  --title "feat: companion pets, ambient theme, celebrations, codeburn `$` today + multiple bug fixes" \
  --body "$(cat docs/plans/2026-05-02-pr-body.md)"
```

(Author the PR body file `docs/plans/2026-05-02-pr-body.md` first; it should group changes into bundles — bug fixes, personalization features, infra — with the bilingual EN/中文 changelog the upstream release process expects.)

**Step 3:** Capture and report the PR URL.
