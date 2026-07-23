# Closed Agent Grid Sorting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five persisted ordering modes for the closed island's right-side agent grid, defaulting to status priority.

**Architecture:** Extend the existing per-display `IslandAppearancePreferences` value and `UserDefaults` path with one enum. Keep ordering in `AppModel.islandClosedRightSlotContent()`, where observation tickets already exist, and expose the five choices through the existing appearance option-card UI.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, macOS 14+

## Global Constraints

- The setting affects only the closed island's `.agents` right slot.
- Preserve agent brand colors and the existing waiting/running/idle cell presentation.
- Reuse `completedStaleThreshold`; do not add another timeout.
- Preserve the expanded session list's grouping and sorting behavior.
- Add no dependency, strategy object, factory, or unrelated refactor.
- Missing or invalid persisted values default to `statusPriority`.

---

## File map

- `Sources/OpenIslandApp/AppModelTypes.swift`: define the five-case preference type and store it in appearance preferences.
- `Sources/OpenIslandApp/AppModel.swift`: persist/load the preference and apply the selected ordering before overflow.
- `Tests/OpenIslandAppTests/AgentsGridRightSlotTests.swift`: cover all five orderings and keep stable-order tests explicit.
- `Tests/OpenIslandAppTests/AppModelSessionListTests.swift`: extend the existing per-display persistence test.
- `Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift`: show five option cards when the Agents right slot is selected.
- `Sources/OpenIslandApp/Resources/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings`: localize the settings copy.

### Task 1: Preference, persistence, and grid ordering

**Files:**
- Modify: `Sources/OpenIslandApp/AppModelTypes.swift:56-105`
- Modify: `Sources/OpenIslandApp/AppModel.swift:350-430, 550-585, 885-940`
- Test: `Tests/OpenIslandAppTests/AgentsGridRightSlotTests.swift`
- Test: `Tests/OpenIslandAppTests/AppModelSessionListTests.swift:7-28, 368-410`

**Interfaces:**
- Produces: `IslandAgentGridSort: String, CaseIterable, Identifiable, Sendable`
- Produces: `IslandAppearancePreferences.agentGridSort: IslandAgentGridSort`
- Produces: `AppModel.islandAgentGridSort: IslandAgentGridSort`
- Consumes: `AgentSession.phase`, `updatedAt`, `firstSeenAt`, `tool`, `isStaleCompletedForIsland(at:threshold:)`, and existing observation tickets.

- [ ] **Step 1: Write the failing five-mode ordering test**

Add a `tool` argument to the local session helper and pass it to `AgentSession`:

```swift
private func makeSession(
    id: String,
    tool: AgentTool = .claudeCode,
    firstSeenAt: Date,
    updatedAt: Date,
    phase: SessionPhase = .running,
    permissionRequest: PermissionRequest? = nil
) -> AgentSession {
    var session = AgentSession(
        id: id,
        title: "\(tool.displayName) · \(id)",
        tool: tool,
        origin: .live,
        attachmentState: .attached,
        phase: phase,
        summary: "",
        updatedAt: updatedAt,
        firstSeenAt: firstSeenAt,
        permissionRequest: permissionRequest,
        jumpTarget: JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: id,
            paneTitle: "agent ~/\(id)",
            workingDirectory: "/tmp/\(id)",
            terminalSessionID: "ghostty-\(id)"
        ),
        claudeMetadata: ClaudeSessionMetadata(
            transcriptPath: "/tmp/\(id).jsonl",
            currentTool: "Task"
        )
    )
    session.isProcessAlive = true
    session.isHookManaged = true
    return session
}
```

Add this table-driven test to `AgentsGridRightSlotTests`:

```swift
@Test
func gridSortModesProduceExpectedOrder() {
    let now = Date()
    let waiting = makeSession(
        id: "waiting", tool: .openCode,
        firstSeenAt: now.addingTimeInterval(-40),
        updatedAt: now.addingTimeInterval(-20),
        phase: .waitingForAnswer
    )
    let running = makeSession(
        id: "running", tool: .codex,
        firstSeenAt: now.addingTimeInterval(-10),
        updatedAt: now.addingTimeInterval(-30)
    )
    let recentDone = makeSession(
        id: "recent", tool: .geminiCLI,
        firstSeenAt: now.addingTimeInterval(-30),
        updatedAt: now.addingTimeInterval(-5),
        phase: .completed
    )
    let staleDone = makeSession(
        id: "stale", tool: .claudeCode,
        firstSeenAt: now.addingTimeInterval(-20),
        updatedAt: now.addingTimeInterval(-300),
        phase: .completed
    )
    let sessions = [running, staleDone, waiting, recentDone]
    let cases: [(IslandAgentGridSort, [AgentSession])] = [
        (.statusPriority, [waiting, running, recentDone, staleDone]),
        (.recentActivity, [recentDone, waiting, running, staleDone]),
        (.newestSession, [running, staleDone, recentDone, waiting]),
        (.agent, [staleDone, running, recentDone, waiting]),
        (.stable, [waiting, recentDone, staleDone, running]),
    ]

    for (sort, expected) in cases {
        let model = AppModel()
        model.islandRightSlot = .agents
        model.islandAgentGridSort = sort
        model.completedStaleThreshold = .twoMinutes
        model.state = SessionState(sessions: sessions)

        guard case let .agents(cells)? = model.islandClosedRightSlotContent() else {
            Issue.record("Expected agents for \(sort.rawValue)")
            continue
        }
        #expect(cells == expected.map(Self.cellFor), "Unexpected \(sort.rawValue) order")
    }
}
```

Set `model.islandAgentGridSort = .stable` in the existing tests whose purpose is stable observation order: `bulkFirstObservationOrdersByHistoricalFirstSeenAt`, `newlyObservedSessionAlwaysLandsAtTheEndRegardlessOfHistoricalTime`, `returningSessionKeepsItsOriginalSlot`, and `cellStateReflectsSessionPhase`.

- [ ] **Step 2: Extend the failing per-display persistence test**

Add `appearance.island.v8.notch.agentGridSort` and `appearance.island.v8.topBar.agentGridSort` to the defaults cleanup list in `AppModelSessionListTests.init()`.

Replace `islandAppearancePreferencesPersistPerDisplayProfile()` with:

```swift
@Test
func islandAppearancePreferencesPersistPerDisplayProfile() {
    let model = AppModel()
    model.updateAppearancePreferences(for: .notch) {
        $0.agentGridSort = .stable
        $0.usageDisplay = .hidden
        $0.sessionGroup = .state
        $0.sessionStateIndicator = .bar
        $0.completedStaleThreshold = .twoMinutes
    }
    model.updateAppearancePreferences(for: .topBar) {
        $0.agentGridSort = .agent
        $0.usageDisplay = .compact
        $0.sessionGroup = .project
        $0.sessionStateIndicator = .tint
        $0.completedStaleThreshold = .never
    }

    model.overlayPlacementDiagnostics = placementDiagnostics(mode: .notch)
    #expect(model.islandAgentGridSort == .stable)
    #expect(model.islandUsageDisplay == .hidden)
    #expect(model.islandSessionGroup == .state)
    #expect(model.islandSessionStateIndicator == .bar)
    #expect(model.completedStaleThreshold == .twoMinutes)

    model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
    #expect(model.islandAgentGridSort == .agent)
    #expect(model.islandUsageDisplay == .compact)
    #expect(model.islandSessionGroup == .project)
    #expect(model.islandSessionStateIndicator == .tint)
    #expect(model.completedStaleThreshold == .never)

    let reloaded = AppModel()
    reloaded.overlayPlacementDiagnostics = placementDiagnostics(mode: .notch)
    #expect(reloaded.islandAgentGridSort == .stable)
    #expect(reloaded.islandUsageDisplay == .hidden)
    #expect(reloaded.islandSessionGroup == .state)
    #expect(reloaded.islandSessionStateIndicator == .bar)
    #expect(reloaded.completedStaleThreshold == .twoMinutes)

    reloaded.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
    #expect(reloaded.islandAgentGridSort == .agent)
    #expect(reloaded.islandUsageDisplay == .compact)
    #expect(reloaded.islandSessionGroup == .project)
    #expect(reloaded.islandSessionStateIndicator == .tint)
    #expect(reloaded.completedStaleThreshold == .never)
}
```

- [ ] **Step 3: Run the focused tests and confirm they fail**

Run:

```bash
swift test --filter AgentsGridRightSlotTests
swift test --filter AppModelSessionListTests.islandAppearancePreferencesPersistPerDisplayProfile
```

Expected: compilation fails because `IslandAgentGridSort`, `agentGridSort`, and `islandAgentGridSort` do not exist yet.

- [ ] **Step 4: Add the preference type and default**

In `AppModelTypes.swift`, add the preference field beside `rightSlot`:

```swift
struct IslandAppearancePreferences: Equatable, Sendable {
    var rightSlot: IslandRightSlot = .count
    var agentGridSort: IslandAgentGridSort = .statusPriority
    var centerLabel: IslandCenterLabel = .agentAction
    var usageDisplay: IslandUsageDisplay = .compact
    var sessionStateIndicator: IslandSessionStateIndicator = .animatedDot
    var sessionGroup: IslandSessionGroup = .none
    var sessionSort: IslandSessionSort = .attention
    var completedStaleThreshold: IslandCompletedStaleThreshold = .fiveMinutes
}

enum IslandAgentGridSort: String, CaseIterable, Identifiable, Sendable {
    case statusPriority
    case recentActivity
    case newestSession
    case agent
    case stable

    var id: String { rawValue }
}
```

- [ ] **Step 5: Persist and load the preference**

In `AppModel.swift`, add the runtime accessor:

```swift
var islandAgentGridSort: IslandAgentGridSort {
    get { appearancePreferences(for: activeAppearanceProfile).agentGridSort }
    set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.agentGridSort = newValue } }
}
```

Add this line to `persistAppearancePreferences(_:for:)`:

```swift
defaults.set(preferences.agentGridSort.rawValue, forKey: Self.appearanceDefaultsKey(profile, "agentGridSort"))
```

Add this memberwise argument to `loadAppearancePreferences(for:)` immediately after `rightSlot`:

```swift
agentGridSort: IslandAgentGridSort(
    rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "agentGridSort")) ?? ""
) ?? .statusPriority,
```

Do not add a legacy key. This new preference has no old storage location.

- [ ] **Step 6: Replace the fixed grid order with the selected order**

Add this method next to `stampAgentsGridObservationTickets(for:)`:

```swift
private func orderedAgentsGridSessions(
    _ sessions: [AgentSession],
    now: Date = .now
) -> [AgentSession] {
    func statusRank(_ session: AgentSession) -> Int {
        if session.phase.requiresAttention { return 0 }
        if session.phase == .running { return 1 }
        if !session.isStaleCompletedForIsland(
            at: now,
            threshold: completedStaleThreshold.seconds
        ) { return 2 }
        return 3
    }

    func agentRank(_ session: AgentSession) -> Int {
        AgentTool.allCases.firstIndex { $0.rawValue == session.tool.rawValue } ?? .max
    }

    return sessions.sorted { a, b in
        switch islandAgentGridSort {
        case .statusPriority:
            if statusRank(a) != statusRank(b) { return statusRank(a) < statusRank(b) }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        case .recentActivity:
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        case .newestSession:
            if a.firstSeenAt != b.firstSeenAt { return a.firstSeenAt > b.firstSeenAt }
        case .agent:
            if agentRank(a) != agentRank(b) { return agentRank(a) < agentRank(b) }
            if statusRank(a) != statusRank(b) { return statusRank(a) < statusRank(b) }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        case .stable:
            break
        }

        let ta = _agentsGridObservedSequence[a.id] ?? .max
        let tb = _agentsGridObservedSequence[b.id] ?? .max
        if ta != tb { return ta < tb }
        return a.id < b.id
    }
}
```

In the `.agents` branch of `islandClosedRightSlotContent()`, retain the ticket-stamping call, replace the current fixed `ordered` closure with:

```swift
let ordered = orderedAgentsGridSessions(sessions)
```

Replace the current active-session overflow selection with the already ordered first seven:

```swift
if ordered.count <= 9 {
    cells = ordered.map(Self.agentsGridCell(for:))
} else {
    cells = ordered.prefix(7).map(Self.agentsGridCell(for:))
    cells.append(.overflow(ordered.count - cells.count))
}
```

- [ ] **Step 7: Run the focused tests**

Run:

```bash
swift test --filter AgentsGridRightSlotTests
swift test --filter AppModelSessionListTests.islandAppearancePreferencesPersistPerDisplayProfile
```

Expected: both commands exit 0; the grid suite covers five modes plus the existing overflow and phase checks.

- [ ] **Step 8: Commit the model slice**

```bash
git add Sources/OpenIslandApp/AppModelTypes.swift Sources/OpenIslandApp/AppModel.swift Tests/OpenIslandAppTests/AgentsGridRightSlotTests.swift Tests/OpenIslandAppTests/AppModelSessionListTests.swift
git commit -m "feat: add agent grid sort modes"
```

### Task 2: Appearance controls and localizations

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift:255-310, 590-625`
- Modify: `Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/OpenIslandApp/Resources/zh-Hant.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `IslandAgentGridSort.allCases`, `editingPreferences.agentGridSort`, and `model.updateAppearancePreferences(for:_:)` from Task 1.
- Produces: Five localized option cards visible only when `editingPreferences.rightSlot == .agents`.

- [ ] **Step 1: Add the five localized labels**

Add to `en.lproj/Localizable.strings`:

```text
"settings.appearance.agentGridSort.title" = "Agent grid order";
"settings.appearance.agentGridSort.note" = "Choose how sessions are placed in the closed island grid.";
"settings.appearance.agentGridSort.statusPriority" = "Status priority";
"settings.appearance.agentGridSort.recentActivity" = "Recent activity";
"settings.appearance.agentGridSort.newestSession" = "Newest session";
"settings.appearance.agentGridSort.agent" = "By agent";
"settings.appearance.agentGridSort.stable" = "Stable order";
```

Add to `zh-Hans.lproj/Localizable.strings`:

```text
"settings.appearance.agentGridSort.title" = "代理网格顺序";
"settings.appearance.agentGridSort.note" = "选择会话在收起状态网格中的排列方式。";
"settings.appearance.agentGridSort.statusPriority" = "状态优先";
"settings.appearance.agentGridSort.recentActivity" = "最近活动";
"settings.appearance.agentGridSort.newestSession" = "最新会话";
"settings.appearance.agentGridSort.agent" = "按代理";
"settings.appearance.agentGridSort.stable" = "固定顺序";
```

Add to `zh-Hant.lproj/Localizable.strings`:

```text
"settings.appearance.agentGridSort.title" = "代理網格順序";
"settings.appearance.agentGridSort.note" = "選擇工作階段在收合狀態網格中的排列方式。";
"settings.appearance.agentGridSort.statusPriority" = "狀態優先";
"settings.appearance.agentGridSort.recentActivity" = "最近活動";
"settings.appearance.agentGridSort.newestSession" = "最新工作階段";
"settings.appearance.agentGridSort.agent" = "依代理";
"settings.appearance.agentGridSort.stable" = "固定順序";
```

- [ ] **Step 2: Add the conditional option cards**

Append this block to `rightSlotSection`, after the existing three right-slot cards:

```swift
if editingPreferences.rightSlot == .agents {
    sectionHeader(
        title: lang.t("settings.appearance.agentGridSort.title"),
        note: lang.t("settings.appearance.agentGridSort.note")
    )

    LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 110), spacing: 12)],
        alignment: .leading,
        spacing: 12
    ) {
        ForEach(IslandAgentGridSort.allCases) { option in
            optionCard(
                selected: editingPreferences.agentGridSort == option,
                title: title(for: option)
            ) {
                model.updateAppearancePreferences(for: editingProfile) {
                    $0.agentGridSort = option
                }
            } icon: {
                Image(systemName: icon(for: option))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.82))
            }
        }
    }
}
```

Add these two helpers beside the existing appearance-option title helpers:

```swift
private func title(for option: IslandAgentGridSort) -> String {
    switch option {
    case .statusPriority: lang.t("settings.appearance.agentGridSort.statusPriority")
    case .recentActivity: lang.t("settings.appearance.agentGridSort.recentActivity")
    case .newestSession:  lang.t("settings.appearance.agentGridSort.newestSession")
    case .agent:          lang.t("settings.appearance.agentGridSort.agent")
    case .stable:         lang.t("settings.appearance.agentGridSort.stable")
    }
}

private func icon(for option: IslandAgentGridSort) -> String {
    switch option {
    case .statusPriority: "bolt.fill"
    case .recentActivity: "clock.arrow.circlepath"
    case .newestSession:  "sparkles"
    case .agent:          "square.grid.2x2"
    case .stable:         "pin.fill"
    }
}
```

- [ ] **Step 3: Build the app**

Run:

```bash
swift build --product OpenIslandApp
```

Expected: exit 0 with `Build complete!` and no missing localization or SwiftUI type errors.

- [ ] **Step 4: Refresh and manually verify the development app**

Run:

```bash
PATH="/opt/homebrew/bin:$PATH" zsh scripts/launch-dev-app.sh
```

Verify in `Open Island Dev.app`:

1. Appearance > Right slot > Agents reveals exactly five ordering cards.
2. Status priority is selected for a profile with no prior grid-sort value.
3. Changing the card reorders the closed right grid without changing cell colors.
4. Notch and external-display profiles retain independent selections.
5. More than nine sessions show seven ordered cells plus the overflow count.

- [ ] **Step 5: Commit the settings slice**

```bash
git add Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings Sources/OpenIslandApp/Resources/zh-Hant.lproj/Localizable.strings
git commit -m "feat: expose agent grid sort settings"
```

- [ ] **Step 6: Confirm the final branch state**

Run:

```bash
git status -sb
git log -5 --oneline
```

Expected: clean `codex-fix/codex-rollout-reopen` worktree with the design, model, and settings commits ahead of `origin/main`.
