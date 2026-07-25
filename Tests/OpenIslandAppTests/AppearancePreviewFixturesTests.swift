import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// AB-326 stage 1: conformance preview fixtures + debug scenarios.
struct AppearancePreviewFixturesTests {
    private static let now = Date(timeIntervalSince1970: 1_770_000_000)

    // MARK: - Determinism

    @Test
    func fixturesAreDeterministicForTheSameNow() {
        let lang = LanguageManager()

        #expect(AppearancePreviewFixtures.sessions(now: Self.now, lang: lang)
            == AppearancePreviewFixtures.sessions(now: Self.now, lang: lang))
        #expect(AppearancePreviewFixtures.completedInterrupted(now: Self.now)
            == AppearancePreviewFixtures.completedInterrupted(now: Self.now))
        #expect(AppearancePreviewFixtures.completedFailed(now: Self.now)
            == AppearancePreviewFixtures.completedFailed(now: Self.now))
        #expect(AppearancePreviewFixtures.duplicateWorkspaceTrio(now: Self.now)
            == AppearancePreviewFixtures.duplicateWorkspaceTrio(now: Self.now))
        #expect(AppearancePreviewFixtures.permissionCommand(now: Self.now)
            == AppearancePreviewFixtures.permissionCommand(now: Self.now))
        #expect(AppearancePreviewFixtures.permissionDiff(now: Self.now)
            == AppearancePreviewFixtures.permissionDiff(now: Self.now))
        #expect(AppearancePreviewFixtures.codexTerminalApproval(now: Self.now)
            == AppearancePreviewFixtures.codexTerminalApproval(now: Self.now))
        #expect(AppearancePreviewFixtures.questionMulti(now: Self.now)
            == AppearancePreviewFixtures.questionMulti(now: Self.now))
        #expect(AppearancePreviewFixtures.subagentsAndTasks(now: Self.now)
            == AppearancePreviewFixtures.subagentsAndTasks(now: Self.now))
    }

    @Test
    func stableIDIsSeedDeterministicAndDistinct() {
        #expect(AppearancePreviewFixtures.stableID("seed-a") == AppearancePreviewFixtures.stableID("seed-a"))
        #expect(AppearancePreviewFixtures.stableID("seed-a") != AppearancePreviewFixtures.stableID("seed-b"))
        // No wall-clock coupling: the derived id never lands on the all-zero UUID
        // for a non-empty seed.
        #expect(AppearancePreviewFixtures.stableID("seed-a") != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    // MARK: - Every fixture is a demo session

    @Test
    func everyFixtureIsADemoSession() {
        let lang = LanguageManager()
        var all: [AgentSession] = AppearancePreviewFixtures.sessions(now: Self.now, lang: lang)
        all += AppearancePreviewFixtures.duplicateWorkspaceTrio(now: Self.now)
        all += [
            AppearancePreviewFixtures.completedInterrupted(now: Self.now),
            AppearancePreviewFixtures.completedFailed(now: Self.now),
            AppearancePreviewFixtures.permissionCommand(now: Self.now),
            AppearancePreviewFixtures.permissionDiff(now: Self.now),
            AppearancePreviewFixtures.codexTerminalApproval(now: Self.now),
            AppearancePreviewFixtures.questionMulti(now: Self.now),
            AppearancePreviewFixtures.subagentsAndTasks(now: Self.now),
        ]

        #expect(all.allSatisfy { $0.origin == .demo })
        #expect(AppearancePreviewFixtures.empty.isEmpty)
    }

    // MARK: - Completion outcomes

    @Test
    func completionOutcomeFixturesCarryTheRightOutcome() {
        let interrupted = AppearancePreviewFixtures.completedInterrupted(now: Self.now)
        #expect(interrupted.phase == .completed)
        #expect(interrupted.outcome == .interrupted)
        #expect(interrupted.tool == .claudeCode)
        #expect(interrupted.jumpTarget?.workspaceName == "niche-radar")
        #expect(interrupted.updatedAt == Self.now.addingTimeInterval(-4 * 60))

        let failed = AppearancePreviewFixtures.completedFailed(now: Self.now)
        #expect(failed.phase == .completed)
        #expect(failed.outcome == .failed)
        #expect(failed.tool == .codex)
        #expect(failed.jumpTarget?.workspaceName == "open-vibe-island")
        #expect(failed.updatedAt == Self.now.addingTimeInterval(-9 * 60))
    }

    // MARK: - Duplicate-workspace trio

    @Test
    func trioCollidesOnWorkspaceAndDisambiguatesByBranchThenRecency() {
        let trio = AppearancePreviewFixtures.duplicateWorkspaceTrio(now: Self.now)
        #expect(trio.count == 3)

        // They all collide on the exact string a row headline leads with.
        #expect(Set(trio.map(\.spotlightDisplayName)) == ["the-automator"])

        let disambiguators = SessionDisambiguation.disambiguators(for: trio, now: Self.now)
        #expect(disambiguators.count == 3)
        #expect(disambiguators[trio[0].id] == "feat/bridge-auth")
        #expect(disambiguators[trio[1].id] == "main")
        // Codex carries no branch (branch is Claude-only ground truth) → recency.
        #expect(disambiguators[trio[2].id]?.contains("ago") == true)

        // The middle member fans out across three subagents.
        #expect(trio[1].claudeMetadata?.activeSubagents.count == 3)
    }

    // MARK: - Permission: shell command

    @Test
    func permissionCommandExposesCommandSummaryPathAndAllowRunLabels() throws {
        let session = AppearancePreviewFixtures.permissionCommand(now: Self.now)
        #expect(session.phase == .waitingForApproval)
        // The command preview drives the hero's `$ …` line via currentCommandPreviewText.
        #expect(session.currentCommandPreviewText == "swift build -c release --product OpenIslandHooks")

        let request = try #require(session.permissionRequest)
        #expect(!request.summary.isEmpty)
        #expect(!request.affectedPath.isEmpty)
        #expect(request.suggestedUpdates.count >= 2)

        // Real ClaudePermissionUpdate cases whose labels read like
        // "Yes, allow running swift build … from this project".
        let projectLabel = request.suggestedUpdates[0].displayLabel
        #expect(projectLabel.contains("allow running"))
        #expect(projectLabel.contains("swift build"))
        #expect(projectLabel.contains("from this project"))
    }

    // MARK: - Permission: inline diff

    @Test
    func permissionDiffProducesARealMultiLineDiff() throws {
        let session = AppearancePreviewFixtures.permissionDiff(now: Self.now)
        let request = try #require(session.permissionRequest)
        #expect(request.affectedPath == "AGENTS.md")

        let source = try #require(request.fileDiffSource)
        let result = PermissionDiff.compute(oldText: source.oldText, newText: source.newText)
        #expect(!result.isEmpty)
        // ≥3 changed lines: additions + removals combined.
        #expect(result.addedCount + result.removedCount >= 3)
    }

    // MARK: - Permission: terminal-only

    @Test
    func codexTerminalApprovalRequiresTerminalApproval() {
        let session = AppearancePreviewFixtures.codexTerminalApproval(now: Self.now)
        #expect(session.tool == .codex)
        #expect(session.phase == .waitingForApproval)
        #expect(session.permissionRequest?.requiresTerminalApproval == true)
    }

    // MARK: - Question: multi-question conformance set

    @Test
    func questionMultiMatchesTheSharedConformanceSet() throws {
        let session = AppearancePreviewFixtures.questionMulti(now: Self.now)
        let prompt = try #require(session.questionPrompt)
        #expect(prompt.questions.count == 2)

        let auth = prompt.questions[0]
        #expect(auth.header == "Auth")
        #expect(auth.question == "Which auth method should the bridge use?")
        #expect(auth.multiSelect == false)
        #expect(auth.options.count == 3)
        // Single-select options carry per-option descriptions.
        #expect(auth.options.allSatisfy { !$0.description.isEmpty })

        let scope = prompt.questions[1]
        #expect(scope.header == "Scope")
        #expect(scope.multiSelect == true)
        #expect(scope.options.count == 4)
        #expect(scope.options.filter(\.allowsFreeform).map(\.label) == ["Other"])
    }

    // MARK: - Subagents + tasks

    @Test
    func subagentsAndTasksFixtureFansOutAsSpecified() throws {
        let session = AppearancePreviewFixtures.subagentsAndTasks(now: Self.now)
        #expect(session.phase == .running)

        let metadata = try #require(session.claudeMetadata)
        #expect(metadata.activeSubagents.map(\.agentType) == ["Explore", "general-purpose", "Plan"])
        #expect(metadata.activeSubagents.map(\.startedAt) == [
            Self.now.addingTimeInterval(-42),
            Self.now.addingTimeInterval(-75),
            Self.now.addingTimeInterval(-8),
        ])

        #expect(metadata.activeTasks.count == 5)
        let byStatus = Dictionary(grouping: metadata.activeTasks, by: \.status)
        #expect(byStatus[.completed]?.count == 2)
        #expect(byStatus[.inProgress]?.count == 1)
        #expect(byStatus[.pending]?.count == 2)
    }

    // MARK: - Running row narration (AB-321 wiring)

    @Test
    func baselineRunningRowNarratesEditingAppModel() throws {
        let lang = LanguageManager()
        let sessions = AppearancePreviewFixtures.sessions(now: Self.now, lang: lang)
        let running = try #require(sessions.first { $0.id == "preview-running" })
        #expect(running.phase == .running)
        #expect(running.narratedActivity?.text == "Editing AppModel.swift")
    }

    // MARK: - Usage fixtures

    @Test
    func usageProvidersMatchTheSpecifiedWindows() {
        let providers = AppearancePreviewFixtures.usageProviders(now: Self.now)
        #expect(providers.map(\.id) == ["claude", "codex"])

        let claude = providers[0]
        #expect(claude.windows.map(\.label) == ["5h", "7d"])
        #expect(claude.peakUsagePercentage == 78)
        #expect(claude.peakWindowLabel == "7d")
        #expect(claude.windows[0].roundedUsedPercentage == 34)
        #expect(claude.windows[0].resetsAt == Self.now.addingTimeInterval(2 * 3_600 + 10 * 60))
        #expect(claude.windows[1].resetsAt == Self.now.addingTimeInterval(3 * 86_400 + 4 * 3_600))

        let codex = providers[1]
        #expect(codex.windows.map(\.label) == ["7d"])
        #expect(codex.peakUsagePercentage == 92)
        #expect(codex.windows[0].resetsAt == Self.now.addingTimeInterval(19 * 3_600))
    }

    // MARK: - Preview scenario mapping (stage 2)

    @Test
    func scenarioContentMapsEachScenarioToItsFixtureSet() {
        let now = Self.now
        let lang = LanguageManager()

        func content(_ scenario: AppearancePreviewScenario) -> AppearancePreviewScenarioContent {
            AppearancePreviewFixtures.scenarioContent(scenario, now: now, lang: lang)
        }

        // list: the baseline five, no hero, no meters.
        let list = content(.list)
        #expect(list.sessions == AppearancePreviewFixtures.sessions(now: now, lang: lang))
        #expect(list.actionableSessionID == nil)
        #expect(list.usageProviders == nil)

        // Each single-card scenario surfaces its fixture as the actionable hero.
        let cardCases: [(AppearancePreviewScenario, AgentSession)] = [
            (.permissionCommand, AppearancePreviewFixtures.permissionCommand(now: now)),
            (.permissionDiff, AppearancePreviewFixtures.permissionDiff(now: now)),
            (.codexApproval, AppearancePreviewFixtures.codexTerminalApproval(now: now)),
            (.questionMulti, AppearancePreviewFixtures.questionMulti(now: now)),
            (.subagents, AppearancePreviewFixtures.subagentsAndTasks(now: now)),
        ]
        for (scenario, fixture) in cardCases {
            let resolved = content(scenario)
            #expect(resolved.sessions == [fixture], "\(scenario.rawValue) fixture mismatch")
            #expect(resolved.actionableSessionID == fixture.id, "\(scenario.rawValue) missing hero id")
            #expect(resolved.usageProviders == nil)
        }

        // completed variants: both outcomes, interrupted is the expanded hero.
        let completed = content(.completedVariants)
        #expect(completed.sessions.map(\.id) == [
            AppearancePreviewFixtures.completedInterrupted(now: now).id,
            AppearancePreviewFixtures.completedFailed(now: now).id,
        ])
        #expect(completed.actionableSessionID == AppearancePreviewFixtures.completedInterrupted(now: now).id)
        #expect(completed.usageProviders == nil)

        // duplicates: the whole trio, no single hero.
        let duplicates = content(.duplicates)
        #expect(duplicates.sessions == AppearancePreviewFixtures.duplicateWorkspaceTrio(now: now))
        #expect(duplicates.actionableSessionID == nil)
        #expect(duplicates.usageProviders == nil)

        // meters: baseline sessions + the fixture usage providers (34/78/92).
        let meters = content(.meters)
        #expect(meters.sessions == AppearancePreviewFixtures.sessions(now: now, lang: lang))
        #expect(meters.actionableSessionID == nil)
        #expect(meters.usageProviders?.map(\.id) == ["claude", "codex"])
        #expect(meters.usageProviders?[0].peakUsagePercentage == 78)
        #expect(meters.usageProviders?[1].peakUsagePercentage == 92)

        // empty: no sessions, no hero, no meters.
        let empty = content(.empty)
        #expect(empty.sessions.isEmpty)
        #expect(empty.actionableSessionID == nil)
        #expect(empty.usageProviders == nil)
    }

    @Test
    func onlyMetersScenarioCarriesUsageProviders() {
        let lang = LanguageManager()
        for scenario in AppearancePreviewScenario.allCases {
            let content = AppearancePreviewFixtures.scenarioContent(scenario, now: Self.now, lang: lang)
            if scenario == .meters {
                #expect(content.usageProviders?.isEmpty == false)
            } else {
                #expect(content.usageProviders == nil, "\(scenario.rawValue) leaked usage providers")
            }
        }
    }

    @Test
    func everyScenarioLabelKeyResolvesInEnglish() {
        let lang = LanguageManager()
        for scenario in AppearancePreviewScenario.allCases {
            let label = lang.t(scenario.labelKey)
            // A missing key falls through to the raw key string; a resolved key
            // never equals its own dotted key.
            #expect(label != scenario.labelKey, "missing localization for \(scenario.labelKey)")
            #expect(!label.isEmpty)
        }
    }
}

/// AB-326: the new debug scenarios must stay demo-only and self-consistent
/// while leaving the pre-existing scenarios untouched.
struct IslandDebugScenarioConformanceTests {
    @Test
    func newScenariosExist() {
        let ids = Set(IslandDebugScenario.allCases.map(\.rawValue))
        for expected in [
            "diffApprovalCard", "codexApprovalCard", "multiQuestionCard", "subagentsCard",
            "completedInterrupted", "completedFailed", "usageMeters", "emptyState",
        ] {
            #expect(ids.contains(expected), "missing scenario \(expected)")
        }
    }

    @Test
    func everyScenarioSnapshotIsDemoOnly() {
        for scenario in IslandDebugScenario.allCases {
            let snapshot = scenario.snapshot()
            #expect(snapshot.sessions.allSatisfy { $0.origin == .demo }, "\(scenario.rawValue) leaked a non-demo session")
        }
    }

    @Test
    func onlyUsageMetersScenarioCarriesUsageProviders() {
        for scenario in IslandDebugScenario.allCases {
            let snapshot = scenario.snapshot()
            if scenario == .usageMeters {
                #expect(snapshot.usageProviders?.isEmpty == false)
            } else {
                #expect(snapshot.usageProviders == nil, "\(scenario.rawValue) unexpectedly set usage providers")
            }
        }
    }

    @Test
    func emptyStateScenarioHasNoSessions() {
        let snapshot = IslandDebugScenario.emptyState.snapshot()
        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.selectedSessionID == nil)
    }
}
