import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
@Suite(.serialized)
struct AppModelSessionListTests {
    init() {
        [
            "appearance.island.v8.stateIndicator",
            "appearance.island.v8.sessionGroup",
            "appearance.island.v8.sessionSort",
            "appearance.island.v8.sessionListLimitMode",
            "appearance.island.v8.sessionListFixedCount",
            "appearance.island.v8.sessionListActivityWindow",
            "appearance.island.v8.completedStaleThreshold",
            "appearance.island.v8.notch.rightSlot",
            "appearance.island.v8.notch.centerLabel",
            "appearance.island.v8.notch.stateIndicator",
            "appearance.island.v8.notch.sessionGroup",
            "appearance.island.v8.notch.sessionSort",
            "appearance.island.v8.notch.sessionListLimitMode",
            "appearance.island.v8.notch.sessionListFixedCount",
            "appearance.island.v8.notch.sessionListActivityWindow",
            "appearance.island.v8.notch.completedStaleThreshold",
            "appearance.island.v8.topBar.rightSlot",
            "appearance.island.v8.topBar.centerLabel",
            "appearance.island.v8.topBar.stateIndicator",
            "appearance.island.v8.topBar.sessionGroup",
            "appearance.island.v8.topBar.sessionSort",
            "appearance.island.v8.topBar.sessionListLimitMode",
            "appearance.island.v8.topBar.sessionListFixedCount",
            "appearance.island.v8.topBar.sessionListActivityWindow",
            "appearance.island.v8.topBar.completedStaleThreshold",
            "app.suppressFrontmostNotifications",
            "feature.completionReply.enabled",
            "overlay.sound.muted",
        ].forEach(UserDefaults.standard.removeObject(forKey:))
    }

    @Test
    func islandListSessionsOnlyIncludeLiveAttachedSessions() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        var liveSession = AgentSession(
            id: "live-session",
            title: "Claude · active",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "active",
                paneTitle: "claude ~/active",
                workingDirectory: "/tmp/active",
                terminalSessionID: "ghostty-1"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/live.jsonl",
                currentTool: "Task"
            )
        )
        liveSession.isProcessAlive = true

        model.state = SessionState(
            sessions: [
                liveSession,
                AgentSession(
                    id: "recent-session",
                    title: "Claude · recent",
                    tool: .claudeCode,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .completed,
                    summary: "Finished",
                    updatedAt: now.addingTimeInterval(-300),
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "recent",
                        paneTitle: "claude ~/recent",
                        workingDirectory: "/tmp/recent",
                        terminalSessionID: "ghostty-2"
                    ),
                    claudeMetadata: ClaudeSessionMetadata(
                        transcriptPath: "/tmp/recent.jsonl",
                        lastAssistantMessage: "Finished"
                    )
                ),
            ]
        )

        #expect(model.surfacedSessions.map(\.id) == ["live-session"])
        #expect(model.recentSessions.map(\.id) == ["recent-session"])
        #expect(model.islandListSessions.map(\.id) == ["live-session", "recent-session"])
    }

    @Test
    func dismissSessionArchivesCodexAppSessionFromIslandList() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        var session = codexAppSession(id: "codex-app-visible", updatedAt: now)
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])

        #expect(model.islandListSessions.map(\.id) == ["codex-app-visible"])

        model.dismissSession("codex-app-visible")

        #expect(model.islandListSessions.isEmpty)
    }

    @Test
    func activityEventRestoresArchivedCodexAppSession() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        var session = codexAppSession(id: "codex-app-visible", updatedAt: now)
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])

        model.dismissSession("codex-app-visible")
        model.applyTrackedEvent(
            .activityUpdated(SessionActivityUpdated(
                sessionID: "codex-app-visible",
                summary: "Bash swift test",
                phase: .running,
                timestamp: now.addingTimeInterval(10)
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        #expect(model.islandListSessions.map(\.id) == ["codex-app-visible"])
    }

    @Test
    func islandListDeduplicatesSessionsSharingTheSameLiveGhosttyTerminal() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        var runningLive = AgentSession(
            id: "running-live",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Current live turn",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-split-1"
            )
        )
        runningLive.isProcessAlive = true

        var oldTurnSameSplit = AgentSession(
            id: "old-turn-same-split",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Historical turn on the same split",
            updatedAt: now.addingTimeInterval(-90),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-split-1"
            )
        )
        oldTurnSameSplit.isProcessAlive = true

        var otherLive = AgentSession(
            id: "other-live",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Another live split",
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-split-2"
            )
        )
        otherLive.isProcessAlive = true

        model.state = SessionState(
            sessions: [runningLive, oldTurnSameSplit, otherLive]
        )

        #expect(model.surfacedSessions.map(\.id) == ["running-live", "other-live"])
        #expect(model.recentSessions.map(\.id).contains("old-turn-same-split"))
        #expect(model.liveSessionCount == 2)
        #expect(model.liveRunningCount == 1)
        #expect(model.liveAttentionCount == 0)
    }

    @Test
    func sessionBootstrapPlaceholderAppearsWhileStartupResolutionIsPending() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.isResolvingInitialLiveSessions = true
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "recovered-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .running,
                    summary: "Recovered from cache",
                    updatedAt: now
                ),
            ]
        )

        #expect(model.liveSessionCount == 0)
        #expect(model.shouldShowSessionBootstrapPlaceholder)
    }

    @Test
    func sessionBootstrapPlaceholderClearsOnceALiveSessionIsConfirmed() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.isResolvingInitialLiveSessions = true

        var liveSession = AgentSession(
            id: "live-session",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: now
        )
        liveSession.isProcessAlive = true

        model.state = SessionState(sessions: [liveSession])

        #expect(model.liveSessionCount == 1)
        #expect(!model.shouldShowSessionBootstrapPlaceholder)
    }

    @Test
    func freshCompletedSessionsSortAheadOfV8StaleCompletedSessions() {
        let now = Date()
        let model = AppModel()

        var staleCompleted = AgentSession(
            id: "stale-completed",
            title: "Codex · stale",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Finished earlier",
            updatedAt: now.addingTimeInterval(-301),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "stale",
                paneTitle: "codex ~/stale",
                workingDirectory: "/tmp/stale",
                terminalSessionID: "ghostty-stale"
            )
        )
        staleCompleted.isProcessAlive = true

        var freshCompleted = AgentSession(
            id: "fresh-completed",
            title: "Codex · fresh",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Finished just now",
            updatedAt: now.addingTimeInterval(-299),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "fresh",
                paneTitle: "codex ~/fresh",
                workingDirectory: "/tmp/fresh",
                terminalSessionID: "ghostty-fresh"
            )
        )
        freshCompleted.isProcessAlive = true

        model.state = SessionState(sessions: [staleCompleted, freshCompleted])

        #expect(model.islandListSessions.map(\.id) == ["fresh-completed", "stale-completed"])
    }

    @Test
    func defaultSessionListShowsActiveWithinOneHourAndFallsBackToThreeRecent() {
        let now = Date()
        let model = AppModel()

        let sessions = [
            makeVisibleSession(id: "recent-1", updatedAt: now.addingTimeInterval(-5 * 60)),
            makeVisibleSession(id: "recent-2", updatedAt: now.addingTimeInterval(-40 * 60)),
            makeVisibleSession(id: "old-1", updatedAt: now.addingTimeInterval(-2 * 60 * 60)),
            makeVisibleSession(id: "old-2", updatedAt: now.addingTimeInterval(-3 * 60 * 60)),
        ]

        model.state = SessionState(sessions: sessions)

        #expect(model.islandListSessions.map(\.id) == ["recent-1", "recent-2", "old-1"])
    }

    @Test
    func defaultSessionListFallsBackToOverflowWhenOnlyTwoSessionsAreSurfaced() {
        let now = Date()
        let model = AppModel()

        let surfacedSessions = [
            makeVisibleSession(id: "live-1", updatedAt: now.addingTimeInterval(-60)),
            makeVisibleSession(id: "live-2", updatedAt: now.addingTimeInterval(-120)),
        ]
        let overflowSession = listSession(
            id: "overflow-1",
            phase: .completed,
            updatedAt: now.addingTimeInterval(-2 * 60 * 60)
        )

        model.state = SessionState(sessions: surfacedSessions + [overflowSession])

        #expect(model.surfacedSessions.map(\.id) == ["live-1", "live-2"])
        #expect(model.islandListSessions.map(\.id) == ["live-1", "live-2", "overflow-1"])
    }

    @Test
    func activeWindowModeShowsAllSessionsWithinWindowWhenMoreThanThreeAreRecent() {
        let now = Date()
        let model = AppModel()

        let sessions = [
            makeVisibleSession(id: "recent-1", updatedAt: now.addingTimeInterval(-5 * 60)),
            makeVisibleSession(id: "recent-2", updatedAt: now.addingTimeInterval(-15 * 60)),
            makeVisibleSession(id: "recent-3", updatedAt: now.addingTimeInterval(-25 * 60)),
            makeVisibleSession(id: "recent-4", updatedAt: now.addingTimeInterval(-35 * 60)),
            makeVisibleSession(id: "old-1", updatedAt: now.addingTimeInterval(-2 * 60 * 60)),
        ]

        model.state = SessionState(sessions: sessions)

        #expect(model.islandListSessions.map(\.id) == ["recent-1", "recent-2", "recent-3", "recent-4"])
    }

    @Test
    func activeWindowModeUsesCustomMinuteWindow() {
        let now = Date()
        let model = AppModel()
        model.islandSessionListLimitMode = .activeWindow
        model.islandSessionListActivityWindowMinutes = 120

        let sessions = [
            makeVisibleSession(id: "recent-1", updatedAt: now.addingTimeInterval(-5 * 60)),
            makeVisibleSession(id: "recent-2", updatedAt: now.addingTimeInterval(-90 * 60)),
            makeVisibleSession(id: "old-1", updatedAt: now.addingTimeInterval(-3 * 60 * 60)),
            makeVisibleSession(id: "old-2", updatedAt: now.addingTimeInterval(-4 * 60 * 60)),
        ]

        model.state = SessionState(sessions: sessions)

        #expect(model.islandListSessions.map(\.id) == ["recent-1", "recent-2", "old-1"])
    }

    @Test
    func notchProfileFallsBackToTopBarCustomActivityWindowWhenUnset() {
        let defaults = UserDefaults.standard
        let notchKey = "appearance.island.v8.notch.sessionListActivityWindow"
        let topBarKey = "appearance.island.v8.topBar.sessionListActivityWindow"
        let settingsProfileKey = "appearance.island.v8.settingsProfile"
        let oldNotch = defaults.object(forKey: notchKey)
        let oldTopBar = defaults.object(forKey: topBarKey)
        let oldSettingsProfile = defaults.object(forKey: settingsProfileKey)
        defer {
            restoreDefault(oldNotch, forKey: notchKey)
            restoreDefault(oldTopBar, forKey: topBarKey)
            restoreDefault(oldSettingsProfile, forKey: settingsProfileKey)
        }

        defaults.removeObject(forKey: notchKey)
        defaults.set(120, forKey: topBarKey)
        defaults.set("topBar", forKey: settingsProfileKey)

        let now = Date()
        let model = AppModel()
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .notch)
        model.state = SessionState(sessions: [
            makeVisibleSession(id: "recent-1", updatedAt: now.addingTimeInterval(-5 * 60)),
            makeVisibleSession(id: "recent-2", updatedAt: now.addingTimeInterval(-90 * 60)),
            makeVisibleSession(id: "old-1", updatedAt: now.addingTimeInterval(-3 * 60 * 60)),
        ])

        #expect(model.islandSessionListActivityWindowMinutes == 120)
        #expect(model.islandListSessions.map(\.id) == ["recent-1", "recent-2", "old-1"])
    }

    @Test
    func runningSessionRowHeightEstimateIgnoresExplicitCollapse() {
        let now = Date(timeIntervalSince1970: 2_000)
        var session = listSession(id: "running-session", phase: .running, updatedAt: now)
        session.codexMetadata = CodexSessionMetadata(
            initialUserPrompt: "Make the island resize with collapsed rows",
            lastUserPrompt: "Make the island resize with collapsed rows",
            lastAssistantMessage: "Thinking",
            currentTool: "Bash",
            currentCommandPreview: "swift test --filter OverlayPanelControllerTests"
        )

        let expandedHeight = session.estimatedIslandRowHeight(at: now, detailOverride: nil)
        let collapsedHeight = session.estimatedIslandRowHeight(at: now, detailOverride: false)

        #expect(expandedHeight == collapsedHeight)
        #expect(expandedHeight >= 100)
    }

    @Test
    func inactiveSessionRowHeightEstimateRespectsExplicitExpansion() {
        let now = Date(timeIntervalSince1970: 2_000)
        var session = listSession(
            id: "completed-session",
            phase: .completed,
            updatedAt: now.addingTimeInterval(-4 * 60 * 60)
        )
        session.codexMetadata = CodexSessionMetadata(
            initialUserPrompt: "Inspect compact row expansion",
            lastUserPrompt: "Inspect compact row expansion",
            lastAssistantMessage: "Ready"
        )

        let compactHeight = session.estimatedIslandRowHeight(at: now, detailOverride: nil)
        let expandedHeight = session.estimatedIslandRowHeight(at: now, detailOverride: true)

        #expect(compactHeight == 42)
        #expect(expandedHeight > compactHeight)
    }

    @Test
    func changingSessionDetailOverrideInvalidatesMeasuredListHeight() {
        let model = AppModel()
        model.measuredSessionListContentHeight = 420

        model.setIslandSessionDetailOverride("session-1", false)

        #expect(model.measuredSessionListContentHeight == 0)
        #expect(model.islandSessionDetailOverride(for: "session-1") == false)
    }

    @Test
    func autoHeightSizingShrinksWhenEstimatedContentGetsSmaller() {
        #expect(AutoHeightScrollViewSizing.effectiveContentHeight(
            measured: 0,
            estimate: 320
        ) == 320)

        #expect(AutoHeightScrollViewSizing.effectiveContentHeight(
            measured: 260,
            estimate: 420
        ) == 260)

        #expect(!AutoHeightScrollViewSizing.isScrollable(contentHeight: 260, maxHeight: 420))
        #expect(AutoHeightScrollViewSizing.isScrollable(contentHeight: 421, maxHeight: 420))

        #expect(AutoHeightScrollViewSizing.contentHeightAfterEstimateChange(
            current: 476,
            estimate: 280
        ) == 280)

        #expect(AutoHeightScrollViewSizing.contentHeightAfterEstimateChange(
            current: 240,
            estimate: 320
        ) == 240)

        #expect(AutoHeightScrollViewSizing.contentHeightAfterEstimateChange(
            current: 240,
            estimate: 0
        ) == 240)
    }

    @Test
    func legacyActivityWindowRawValueMigratesToCustomMinutes() {
        UserDefaults.standard.set(
            "oneHour",
            forKey: "appearance.island.v8.topBar.sessionListActivityWindow"
        )

        let model = AppModel()
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

        #expect(model.islandSessionListActivityWindowMinutes == 60)
    }

    @Test
    func closedCountMatchesExpandedSessionListAfterActivityWindowLimit() {
        let now = Date()
        let model = AppModel()
        model.islandRightSlot = .count

        let recent = (1...6).map { index in
            makeVisibleSession(
                id: "recent-\(index)",
                updatedAt: now.addingTimeInterval(TimeInterval(-index * 60))
            )
        }
        let old = (1...14).map { index in
            makeVisibleSession(
                id: "old-\(index)",
                updatedAt: now.addingTimeInterval(TimeInterval(-(index + 1) * 60 * 60))
            )
        }

        model.state = SessionState(sessions: recent + old)

        #expect(model.surfacedSessions.count == 20)
        #expect(model.islandListSessions.count == 6)
        guard case let .count(count)? = model.islandClosedRightSlotContent() else {
            Issue.record("Expected count right-slot content")
            return
        }
        #expect(count == 6)
    }

    @Test
    func codexSubagentSessionsAreHiddenFromSessionList() {
        let now = Date()
        let model = AppModel()
        let userSession = makeVisibleSession(id: "user-session", updatedAt: now)
        var subagentSession = makeVisibleSession(id: "codex-subagent", updatedAt: now.addingTimeInterval(-30))
        subagentSession.codexMetadata = CodexSessionMetadata(
            transcriptPath: "/tmp/rollout-subagent.jsonl",
            isSubagentSession: true
        )

        model.state = SessionState(sessions: [userSession, subagentSession])

        #expect(model.surfacedSessions.map(\.id) == ["user-session"])
        #expect(model.islandListSessions.map(\.id) == ["user-session"])
    }

    @Test
    func fixedCountModeUsesConfiguredRowCount() {
        let now = Date()
        let model = AppModel()
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        model.updateAppearancePreferences(for: .topBar) {
            $0.sessionListLimitMode = .fixedCount
            $0.sessionListFixedCount = .five
        }

        let sessions = (1...6).map { index in
            makeVisibleSession(
                id: "session-\(index)",
                updatedAt: now.addingTimeInterval(TimeInterval(-index * 60))
            )
        }

        model.state = SessionState(sessions: sessions)
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

        #expect(model.islandListSessions.map(\.id) == ["session-1", "session-2", "session-3", "session-4", "session-5"])
    }

    @Test
    func islandSessionSectionsGroupStaleCompletedIntoIdle() {
        let now = Date()
        let model = AppModel()
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        model.islandSessionGroup = .state
        model.completedStaleThreshold = .fiveMinutes

        var approval = listSession(id: "approval", phase: .waitingForApproval, updatedAt: now)
        approval.permissionRequest = PermissionRequest(
            title: "Approve",
            summary: "Run tool",
            affectedPath: "/tmp"
        )

        var done = listSession(id: "done", phase: .completed, updatedAt: now.addingTimeInterval(-60))
        var stale = listSession(id: "stale", phase: .completed, updatedAt: now.addingTimeInterval(-360))
        approval.isProcessAlive = true
        done.isProcessAlive = true
        stale.isProcessAlive = true

        model.state = SessionState(sessions: [stale, done, approval])
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

        #expect(model.islandSessionSections.map(\.id) == ["state-approval", "state-done", "state-idle"])
        #expect(model.islandSessionSections.map(\.sessions.first?.id) == ["approval", "done", "stale"])
    }

    @Test
    func islandSessionSectionsKeepCompletedInDoneWhenStaleThresholdIsNever() {
        let now = Date()
        let model = AppModel()
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        model.updateAppearancePreferences(for: .topBar) {
            $0.sessionGroup = .state
            $0.completedStaleThreshold = .never
        }

        var oldDone = listSession(id: "old-done", phase: .completed, updatedAt: now.addingTimeInterval(-86_400))
        oldDone.isProcessAlive = true
        model.state = SessionState(sessions: [oldDone])
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

        #expect(model.islandSessionSections.map(\.id) == ["state-done"])
        #expect(model.islandSessionSections.first?.sessions.first?.id == "old-done")
    }

    @Test
    func islandSessionListCanSortByLastUpdate() {
        let now = Date()
        let model = AppModel()
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        model.islandSessionSort = .lastUpdate

        var olderRunning = listSession(id: "older-running", phase: .running, updatedAt: now.addingTimeInterval(-120))
        var newerCompleted = listSession(id: "newer-completed", phase: .completed, updatedAt: now.addingTimeInterval(-10))
        olderRunning.isProcessAlive = true
        newerCompleted.isProcessAlive = true

        model.state = SessionState(sessions: [olderRunning, newerCompleted])
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

        #expect(model.islandListSessions.map(\.id) == ["newer-completed", "older-running"])
    }

    @Test
    func islandAppearancePreferencesPersistPerDisplayProfile() {
        let model = AppModel()
        model.updateAppearancePreferences(for: .notch) {
            $0.usageDisplay = .hidden
            $0.sessionGroup = .state
            $0.sessionStateIndicator = .bar
            $0.sessionListActivityWindowMinutes = 120
            $0.completedStaleThreshold = .twoMinutes
        }
        model.updateAppearancePreferences(for: .topBar) {
            $0.usageDisplay = .compact
            $0.sessionGroup = .project
            $0.sessionStateIndicator = .tint
            $0.sessionListActivityWindowMinutes = 30
            $0.completedStaleThreshold = .never
        }

        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .notch)
        #expect(model.islandUsageDisplay == .hidden)
        #expect(model.islandSessionGroup == .state)
        #expect(model.islandSessionStateIndicator == .bar)
        #expect(model.islandSessionListActivityWindowMinutes == 120)
        #expect(model.completedStaleThreshold == .twoMinutes)

        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        #expect(model.islandUsageDisplay == .compact)
        #expect(model.islandSessionGroup == .project)
        #expect(model.islandSessionStateIndicator == .tint)
        #expect(model.islandSessionListActivityWindowMinutes == 30)
        #expect(model.completedStaleThreshold == .never)

        let reloaded = AppModel()
        reloaded.overlayPlacementDiagnostics = placementDiagnostics(mode: .notch)
        #expect(reloaded.islandUsageDisplay == .hidden)
        #expect(reloaded.islandSessionGroup == .state)
        #expect(reloaded.islandSessionStateIndicator == .bar)
        #expect(reloaded.islandSessionListActivityWindowMinutes == 120)
        reloaded.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        #expect(reloaded.islandUsageDisplay == .compact)
        #expect(reloaded.islandSessionGroup == .project)
        #expect(reloaded.islandSessionStateIndicator == .tint)
        #expect(reloaded.islandSessionListActivityWindowMinutes == 30)
        #expect(reloaded.completedStaleThreshold == .never)
    }

    @Test
    func jumpToSessionClosesOverlayBeforeTerminalJumpFinishes() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel { _ in
            Thread.sleep(forTimeInterval: 0.25)
            return "Focused the matching Ghostty terminal."
        }
        model.notchStatus = .opened
        model.notchOpenReason = .click
        model.islandSurface = .sessionList()

        let session = AgentSession(
            id: "live-session",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-1"
            )
        )

        model.jumpToSession(session)

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(model.islandSurface == .sessionList())

        let expected = "Focused the matching Ghostty terminal."
        for _ in 0..<20 {
            if model.lastActionMessage == expected { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(model.lastActionMessage == expected)
    }

    @Test
    func rolloutEventsDoNotPromoteRecoveredSessionsToAttachedDuringColdStart() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.isResolvingInitialLiveSessions = true
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "recovered-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .running,
                    summary: "Recovered from cache",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "recovered-session",
                    summary: "Reading recent rollout lines.",
                    phase: .running,
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .rollout
        )

        #expect(model.liveSessionCount == 0)
        #expect(model.state.session(id: "recovered-session")?.attachmentState == .stale)
        #expect(model.shouldShowSessionBootstrapPlaceholder)
    }

    @Test
    func bridgeEventsStillPromoteSessionsToAttached() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "live-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .running,
                    summary: "Recovered from cache",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "live-session",
                    summary: "Bridge says the agent is running.",
                    phase: .running,
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        #expect(model.liveSessionCount == 1)
        #expect(model.state.session(id: "live-session")?.attachmentState == .attached)
    }

    @Test
    func rolloutCompletionDoesNotPresentNotificationDuringColdStart() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.isResolvingInitialLiveSessions = true
        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "recovered-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .running,
                    summary: "Recovered from cache",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .sessionCompleted(
                SessionCompleted(
                    sessionID: "recovered-session",
                    summary: "Recovered rollout finished.",
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .rollout
        )

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(model.islandSurface == .sessionList())
    }

    @Test
    func bridgeNotificationIsSuppressedWhenSessionIsAlreadyFrontmost() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel(
            isNotificationSessionAlreadyFrontmost: { session in
                session.id == "frontmost-session"
            }
        )
        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "frontmost-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .attached,
                    phase: .running,
                    summary: "Already focused in the front terminal.",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .permissionRequested(
                PermissionRequested(
                    sessionID: "frontmost-session",
                    request: PermissionRequest(
                        title: "Edit",
                        summary: "main.swift",
                        affectedPath: "/tmp/main.swift"
                    ),
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        for _ in 0..<20 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(model.islandSurface == .sessionList())
    }

    @Test
    func bridgeNotificationStillPresentsWhenSessionIsNotFrontmost() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel(
            isNotificationSessionAlreadyFrontmost: { _ in false }
        )
        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "background-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .attached,
                    phase: .running,
                    summary: "Needs approval.",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .permissionRequested(
                PermissionRequested(
                    sessionID: "background-session",
                    request: PermissionRequest(
                        title: "Edit",
                        summary: "main.swift",
                        affectedPath: "/tmp/main.swift"
                    ),
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        for _ in 0..<20 {
            if model.notchStatus == .opened {
                break
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface == .sessionList(actionableSessionID: "background-session"))
    }

    @Test
    func hoverOpenedSessionListAutoCollapsesOnPointerExitAfterDelay() async throws {
        let model = AppModel()
        model.notchStatus = .opened
        model.notchOpenReason = .hover
        model.islandSurface = .sessionList()

        #expect(model.shouldAutoCollapseOnMouseLeave)

        model.handlePointerExitedIslandSurface()

        #expect(model.notchStatus == .opened)

        try await Task.sleep(for: .milliseconds(260))

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(model.islandSurface == .sessionList())
    }

    @Test
    func hoverOpenedSessionListCancelsDelayedCollapseWhenPointerReenters() async throws {
        let model = AppModel()
        model.notchStatus = .opened
        model.notchOpenReason = .hover
        model.islandSurface = .sessionList()

        model.handlePointerExitedIslandSurface()
        model.notePointerInsideIslandSurface()

        try await Task.sleep(for: .milliseconds(260))

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .hover)
    }

    @Test
    func closeTransitionSetsStateImmediatelyAndClearsPending() {
        let model = AppModel()
        model.notchStatus = .opened
        model.notchOpenReason = .hover
        model.islandSurface = .sessionList()

        model.notchClose()

        // State changes immediately; pending clears synchronously in tests
        // (no panel → fadeOutAndClose calls completion inline).
        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(!model.isOverlayCloseTransitionPending)
    }

    @Test
    func clickedSessionListDoesNotAutoCollapseOnPointerExit() {
        let model = AppModel()
        model.notchStatus = .opened
        model.notchOpenReason = .click
        model.islandSurface = .sessionList()

        #expect(!model.shouldAutoCollapseOnMouseLeave)

        model.notePointerInsideIslandSurface()
        model.handlePointerExitedIslandSurface()

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .click)
        #expect(model.islandSurface == .sessionList())
    }

    @Test
    func completionNotificationRequiresSurfaceEntryBeforePointerExitCollapse() {
        let model = AppModel()
        // Add a completed session so autoDismissesWhenPresentedAsNotification can check phase
        model.applyTrackedEvent(
            .sessionStarted(SessionStarted(
                sessionID: "session-1",
                title: "Test",
                tool: .codex,
                summary: "Done",
                timestamp: .now
            )),
            updateLastActionMessage: false
        )
        model.applyTrackedEvent(
            .sessionCompleted(SessionCompleted(
                sessionID: "session-1",
                summary: "Done",
                timestamp: .now
            )),
            updateLastActionMessage: false
        )
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = .sessionList(actionableSessionID: "session-1")

        #expect(model.shouldAutoCollapseOnMouseLeave)

        model.handlePointerExitedIslandSurface()

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)

        model.notePointerInsideIslandSurface()
        model.handlePointerExitedIslandSurface()

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
    }

    @Test
    func completionNotificationDefersTimedCollapseWhilePointerIsInside() {
        let model = AppModel()
        model.applyTrackedEvent(
            .sessionStarted(SessionStarted(
                sessionID: "session-1",
                title: "Test",
                tool: .codex,
                summary: "Done",
                timestamp: .now
            )),
            updateLastActionMessage: false
        )
        model.applyTrackedEvent(
            .sessionCompleted(SessionCompleted(
                sessionID: "session-1",
                summary: "Done",
                timestamp: .now
            )),
            updateLastActionMessage: false
        )
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = .sessionList(actionableSessionID: "session-1")

        #expect(model.shouldAutoCollapseOnMouseLeave)
        #expect(!model.shouldDeferTimedNotificationAutoCollapse)

        model.notePointerInsideIslandSurface()

        #expect(model.shouldDeferTimedNotificationAutoCollapse)

        model.handlePointerExitedIslandSurface()

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
    }

    @Test
    func completionNotificationHoverCancelsPendingTimedCollapse() {
        let model = AppModel()
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "session-1",
                    title: "Test",
                    tool: .codex,
                    attachmentState: .attached,
                    phase: .completed,
                    summary: "Done",
                    updatedAt: .now
                )
            ]
        )

        model.notchOpen(reason: .notification, surface: .sessionList(actionableSessionID: "session-1"))

        #expect(model.hasPendingNotificationAutoCollapse)

        model.notePointerInsideIslandSurface()

        #expect(!model.hasPendingNotificationAutoCollapse)
        #expect(model.shouldDeferTimedNotificationAutoCollapse)
        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)
    }

    @Test
    func mergeDiscoveredClaudeSessionsPreservesRegistryJumpTargetAndAddsTranscriptMetadata() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "claude-session",
                    title: "Claude · open-island",
                    tool: .claudeCode,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .completed,
                    summary: "Recovered from registry",
                    updatedAt: now.addingTimeInterval(-60),
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "open-island",
                        paneTitle: "claude ~/open-island",
                        workingDirectory: "/tmp/open-island",
                        terminalSessionID: "ghostty-claude",
                        terminalTTY: "/dev/ttys002"
                    )
                ),
            ]
        )

        let merged = model.discovery.mergeDiscoveredSessions([
            AgentSession(
                id: "claude-session",
                title: "Claude · open-island",
                tool: .claudeCode,
                origin: .live,
                attachmentState: .stale,
                phase: .running,
                summary: "Recovered from transcript",
                updatedAt: now,
                jumpTarget: JumpTarget(
                    terminalApp: "Unknown",
                    workspaceName: "open-island",
                    paneTitle: "Claude deadbeef",
                    workingDirectory: "/tmp/open-island"
                ),
                claudeMetadata: ClaudeSessionMetadata(
                    transcriptPath: "/tmp/claude.jsonl",
                    lastUserPrompt: "Check the Claude session registry.",
                    currentTool: "Task"
                )
            ),
        ])

        #expect(merged.count == 1)
        #expect(merged.first?.jumpTarget?.terminalApp == "Ghostty")
        #expect(merged.first?.jumpTarget?.terminalSessionID == "ghostty-claude")
        #expect(merged.first?.claudeMetadata?.transcriptPath == "/tmp/claude.jsonl")
        #expect(merged.first?.claudeMetadata?.lastUserPrompt == "Check the Claude session registry.")
        #expect(merged.first?.phase == .running)
    }

    @Test
    func mergeDiscoveredCodexAppSessionDoesNotReplaceAppServerTitleWithWorkspaceFallback() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "codex-thread",
                    title: "合并 hera-web 到 release",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .attached,
                    phase: .completed,
                    summary: "Turn completed.",
                    updatedAt: now.addingTimeInterval(-60),
                    jumpTarget: JumpTarget(
                        terminalApp: "Codex.app",
                        workspaceName: "hera",
                        paneTitle: "合并 hera-web 到 release",
                        workingDirectory: "/Users/lijie10/Desktop/code/hera",
                        codexThreadID: "codex-thread"
                    ),
                    codexMetadata: CodexSessionMetadata(
                        transcriptPath: "/tmp/codex.jsonl",
                        initialUserPrompt: "heraweb现在也需要merge到release分支"
                    )
                ),
            ]
        )

        let merged = model.discovery.mergeDiscoveredSessions([
            AgentSession(
                id: "codex-thread",
                title: "Codex · hera",
                tool: .codex,
                origin: .live,
                attachmentState: .stale,
                phase: .running,
                summary: "Thinking.",
                updatedAt: now,
                jumpTarget: JumpTarget(
                    terminalApp: "Codex.app",
                    workspaceName: "hera",
                    paneTitle: "Codex · hera",
                    workingDirectory: "/Users/lijie10/Desktop/code/hera",
                    codexThreadID: "codex-thread"
                ),
                codexMetadata: CodexSessionMetadata(
                    transcriptPath: "/tmp/codex.jsonl",
                    lastUserPrompt: "hera-chat的分支是heradesign"
                )
            ),
        ])

        #expect(merged.count == 1)
        #expect(merged.first?.title == "合并 hera-web 到 release")
        #expect(merged.first?.phase == .running)
        #expect(merged.first?.summary == "Thinking.")
        #expect(merged.first?.codexMetadata?.initialUserPrompt == "heraweb现在也需要merge到release分支")
        #expect(merged.first?.codexMetadata?.lastUserPrompt == "hera-chat的分支是heradesign")
    }

    @Test
    func codexAppRediscoveryRefreshesExistingRunningThread() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "codex-thread",
                    title: "web 模拟器画面",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .attached,
                    phase: .completed,
                    summary: "Thinking.",
                    updatedAt: now.addingTimeInterval(-120),
                    jumpTarget: JumpTarget(
                        terminalApp: "Codex.app",
                        workspaceName: "hera",
                        paneTitle: "web 模拟器画面",
                        workingDirectory: "/Users/lijie10/Desktop/code/hera",
                        codexThreadID: "codex-thread"
                    ),
                    codexMetadata: CodexSessionMetadata(
                        transcriptPath: "/tmp/codex.jsonl",
                        lastUserPrompt: "old prompt"
                    )
                ),
            ]
        )

        model.discovery.applyCodexAppRediscovery([
            CodexTrackedSessionRecord(
                sessionID: "codex-thread",
                title: "web 模拟器画面",
                origin: .live,
                attachmentState: .stale,
                summary: "Thinking.",
                phase: .running,
                updatedAt: now,
                jumpTarget: JumpTarget(
                    terminalApp: "Codex.app",
                    workspaceName: "hera",
                    paneTitle: "web 模拟器画面",
                    workingDirectory: "/Users/lijie10/Desktop/code/hera",
                    codexThreadID: "codex-thread"
                ),
                codexMetadata: CodexSessionMetadata(
                    transcriptPath: "/tmp/codex.jsonl",
                    lastUserPrompt: "new prompt"
                )
            ),
        ])

        let session = try #require(model.state.session(id: "codex-thread"))
        #expect(session.phase == .running)
        #expect(session.updatedAt == now)
        #expect(session.isProcessAlive)
        #expect(session.codexMetadata?.lastUserPrompt == "new prompt")
    }

    @Test
    func olderRunningCodexRolloutDoesNotPromoteCachedCompletedSession() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "codex-thread",
                    title: "web 模拟器画面",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .attached,
                    phase: .completed,
                    summary: "Thinking.",
                    updatedAt: now,
                    jumpTarget: JumpTarget(
                        terminalApp: "Codex.app",
                        workspaceName: "hera",
                        paneTitle: "web 模拟器画面",
                        workingDirectory: "/Users/lijie10/Desktop/code/hera",
                        codexThreadID: "codex-thread"
                    ),
                    codexMetadata: CodexSessionMetadata(transcriptPath: "/tmp/codex.jsonl")
                ),
            ]
        )

        var discovered = AgentSession(
            id: "codex-thread",
            title: "web 模拟器画面",
            tool: .codex,
            origin: .live,
            attachmentState: .stale,
            phase: .running,
            summary: "Thinking.",
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "hera",
                paneTitle: "web 模拟器画面",
                workingDirectory: "/Users/lijie10/Desktop/code/hera",
                codexThreadID: "codex-thread"
            ),
            codexMetadata: CodexSessionMetadata(transcriptPath: "/tmp/codex.jsonl")
        )
        discovered.isCodexAppSession = true
        discovered.isProcessAlive = true

        let merged = model.discovery.mergeDiscoveredSessions([discovered])
        let session = try #require(merged.first(where: { $0.id == "codex-thread" }))
        #expect(session.phase == .completed)
        #expect(session.summary == "Thinking.")
        #expect(session.isProcessAlive)
    }

    @Test
    func startupCodexRolloutDiscoveryMarksDiscoveredAppThreadsAlive() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        model.discovery.applyStartupDiscoveryPayload(
            SessionDiscoveryCoordinator.StartupDiscoveryPayload(
                codexRecords: [],
                codexRecordsNeedPrune: false,
                claudeRecords: [],
                claudeRecordsNeedPrune: false,
                openCodeRecords: [],
                openCodeRecordsNeedPrune: false,
                cursorRecords: [],
                cursorRecordsNeedPrune: false,
                discoveredCodexRecords: [
                    CodexTrackedSessionRecord(
                        sessionID: "codex-thread",
                        title: "web 模拟器画面",
                        origin: .live,
                        attachmentState: .stale,
                        summary: "Thinking.",
                        phase: .running,
                        updatedAt: now,
                        jumpTarget: JumpTarget(
                            terminalApp: "Codex.app",
                            workspaceName: "hera",
                            paneTitle: "web 模拟器画面",
                            workingDirectory: "/Users/lijie10/Desktop/code/hera",
                            codexThreadID: "codex-thread"
                        ),
                        codexMetadata: CodexSessionMetadata(transcriptPath: "/tmp/codex.jsonl")
                    ),
                ],
                discoveredClaudeSessions: [],
                hooksBinaryURL: nil
            )
        )

        let session = try #require(model.state.session(id: "codex-thread"))
        #expect(session.phase == .running)
        #expect(session.isProcessAlive)
        #expect(session.isCodexAppSession)
    }

    @Test
    func codexRediscoveryEnrichesWorkspaceFallbackWithAppServerTitle() {
        let records = [
            CodexTrackedSessionRecord(
                sessionID: "codex-thread",
                title: "Codex · hera",
                origin: .live,
                attachmentState: .stale,
                summary: "Thinking.",
                phase: .running,
                updatedAt: Date(timeIntervalSince1970: 2_000),
                jumpTarget: JumpTarget(
                    terminalApp: "Codex.app",
                    workspaceName: "hera",
                    paneTitle: "Codex · hera",
                    workingDirectory: "/Users/lijie10/Desktop/code/hera",
                    codexThreadID: "codex-thread"
                )
            ),
        ]

        let enriched = SessionDiscoveryCoordinator.enrichCodexRecords(
            records,
            titleBySessionID: ["codex-thread": "合并 hera-web 到 release"]
        )

        #expect(enriched.first?.title == "合并 hera-web 到 release")
        #expect(enriched.first?.jumpTarget?.paneTitle == "合并 hera-web 到 release")
    }

    @Test
    func mergedWithSyntheticClaudeSessionsAddsGhosttyClaudeProcessWhenNoTrackedSessionExists() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        let merged = model.monitoring.mergedWithSyntheticClaudeSessions(
            existingSessions: [],
            activeProcesses: [
                .init(
                    tool: .claudeCode,
                    sessionID: nil,
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys002",
                    terminalApp: "Ghostty"
                ),
            ],
            now: now
        )

        #expect(merged.count == 1)
        #expect(merged.first?.id.hasPrefix("claude-process:") == true)
        #expect(merged.first?.attachmentState == .attached)
        #expect(merged.first?.jumpTarget?.terminalApp == "Ghostty")
        #expect(merged.first?.jumpTarget?.terminalTTY == "/dev/ttys002")
    }

    @Test
    func sanitizeCrossToolGhosttyJumpTargetsClearsClaudeMisbinding() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        let misboundClaudeSession = AgentSession(
            id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
            title: "Claude · open-island",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-codex"
            )
        )

        let sanitized = model.monitoring.sanitizeCrossToolGhosttyJumpTargets(in: [misboundClaudeSession])

        #expect(sanitized.first?.jumpTarget?.terminalSessionID == nil)
        #expect(sanitized.first?.jumpTarget?.paneTitle == "Claude e45d5e87")
    }

    @Test
    func mergedWithSyntheticClaudeSessionsSkipsSyntheticWhenAttachedClaudeAlreadyRepresentsGroup() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        let existing = AgentSession(
            id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
            title: "Claude · open-island",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "open-island · hi · e45d5e87",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-claude"
            )
        )

        let merged = model.monitoring.mergedWithSyntheticClaudeSessions(
            existingSessions: [existing],
            activeProcesses: [
                .init(
                    tool: .claudeCode,
                    sessionID: nil,
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys002",
                    terminalApp: "Ghostty"
                ),
            ],
            now: now
        )

        #expect(merged.map(\.id) == [existing.id])
    }

    @Test
    func mergedWithSyntheticClaudeSessionsSkipsSyntheticWhenStaleClaudeSessionMatchesActiveProcess() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        let existing = AgentSession(
            id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
            title: "Claude · open-island-readme",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Recovered transcript",
            updatedAt: now.addingTimeInterval(-120),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island-readme",
                paneTitle: "Claude e45d5e87",
                workingDirectory: "/tmp/open-island-readme"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/claude-session.jsonl",
                lastUserPrompt: "整理 readme。"
            )
        )

        let merged = model.monitoring.mergedWithSyntheticClaudeSessions(
            existingSessions: [existing],
            activeProcesses: [
                .init(
                    tool: .claudeCode,
                    sessionID: existing.id,
                    workingDirectory: "/tmp/open-island-readme",
                    terminalTTY: "/dev/ttys008",
                    terminalApp: "Ghostty"
                ),
            ],
            now: now
        )

        #expect(merged.map(\.id) == [existing.id])
    }


    /// Regression test: `measuredNotificationContentHeight` MUST be cleared when the
    /// surface changes to a different session, to avoid sizing the new card with stale
    /// measurements from the previous one.
    @Test
    @MainActor
    func approvalCardMeasuredHeightClearedWhenSurfaceSessionChanges() {
        let model = AppModel()

        var sessionA = AgentSession(
            id: "approval-session-A",
            title: "Claude · proj-A",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve edit A",
            updatedAt: .now,
            permissionRequest: PermissionRequest(
                title: "Edit",
                summary: "file_a.swift",
                affectedPath: "/tmp/file_a.swift"
            )
        )
        sessionA.isProcessAlive = true

        var sessionB = AgentSession(
            id: "approval-session-B",
            title: "Claude · proj-B",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve edit B",
            updatedAt: .now,
            permissionRequest: PermissionRequest(
                title: "Edit",
                summary: "file_b.swift",
                affectedPath: "/tmp/file_b.swift"
            )
        )
        sessionB.isProcessAlive = true

        model.state = SessionState(sessions: [sessionA, sessionB])

        let surfaceA = IslandSurface.sessionList(actionableSessionID: "approval-session-A")
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = surfaceA
        model.measuredNotificationContentHeight = 320

        model.notchClose()

        let surfaceB = IslandSurface.sessionList(actionableSessionID: "approval-session-B")
        model.notchOpen(reason: .notification, surface: surfaceB)

        #expect(
            model.measuredNotificationContentHeight == 0,
            "Switching to a different session's card must clear the stale measurement from the previous session to prevent wrong initial panel sizing."
        )
    }

    @Test
    @MainActor
    func notificationMeasuredHeightClearedWhenSameSessionCardContentChanges() {
        let model = AppModel()
        model.isSoundMuted = true

        var session = AgentSession(
            id: "same-session",
            title: "Codex · proj",
            tool: .codex,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve edit",
            updatedAt: .now,
            permissionRequest: PermissionRequest(
                title: "Edit",
                summary: "A longer approval card",
                affectedPath: "/tmp/long-file-name.swift"
            )
        )
        session.isProcessAlive = true
        session.phase = .completed
        session.permissionRequest = nil
        session.summary = "Done"
        model.state = SessionState(sessions: [session])

        let surface = IslandSurface.sessionList(actionableSessionID: "same-session")
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = surface
        model.measuredNotificationContentHeight = 360

        model.overlay.presentNotificationSurface(surface)

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface == surface)
        #expect(model.activeIslandCardSession?.phase == .completed)
        #expect(
            model.measuredNotificationContentHeight == 0,
            "Replacing a notification with different content for the same session must discard the previous card's measured height."
        )
    }

    @Test
    @MainActor
    func hoveredNotificationCardIsNotReplacedByAnotherNotification() {
        let model = AppModel()
        model.isSoundMuted = true

        var currentSession = AgentSession(
            id: "current-session",
            title: "Claude · current",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve current edit",
            updatedAt: .now,
            permissionRequest: PermissionRequest(
                title: "Edit",
                summary: "current.swift",
                affectedPath: "/tmp/current.swift"
            )
        )
        currentSession.isProcessAlive = true

        var incomingSession = AgentSession(
            id: "other-session",
            title: "Codex · other",
            tool: .codex,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: .now
        )
        incomingSession.isProcessAlive = true

        let currentSurface = IslandSurface.sessionList(actionableSessionID: "current-session")
        model.state = SessionState(sessions: [currentSession, incomingSession])
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = currentSurface
        model.measuredNotificationContentHeight = 280

        model.notePointerInsideIslandSurface()

        model.applyTrackedEvent(
            .permissionRequested(PermissionRequested(
                sessionID: "other-session",
                request: PermissionRequest(
                    title: "Edit",
                    summary: "other.swift",
                    affectedPath: "/tmp/other.swift"
                ),
                timestamp: .now
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        #expect(model.state.session(id: "other-session")?.phase == .waitingForApproval)
        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface == currentSurface)
        #expect(model.activeIslandCardSession?.id == "current-session")
        #expect(model.measuredNotificationContentHeight == 280)
    }

    @Test
    @MainActor
    func legacyIncomingSwiftPermissionRequestIsIgnored() {
        let model = AppModel()
        var incomingSession = AgentSession(
            id: "incoming-session",
            title: "Codex · incoming",
            tool: .codex,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: .now
        )
        incomingSession.isProcessAlive = true
        model.state = SessionState(sessions: [incomingSession])

        model.applyTrackedEvent(
            .permissionRequested(PermissionRequested(
                sessionID: "incoming-session",
                request: PermissionRequest(
                    title: "Edit",
                    summary: "incoming.swift",
                    affectedPath: "/tmp/incoming.swift"
                ),
                timestamp: .now
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        #expect(model.state.session(id: "incoming-session")?.phase == .completed)
        #expect(model.state.session(id: "incoming-session")?.permissionRequest == nil)
        #expect(!model.islandListSessions.contains { $0.id == "incoming-session" })
    }

    @Test
    func recoveredSessionMatchesLiveGhosttyProcessByCWDWhenMultipleCandidatesExist() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        let recoveredSessions = [
            AgentSession(
                id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
                title: "Claude · open-island",
                tool: .claudeCode,
                origin: .live,
                attachmentState: .stale,
                phase: .completed,
                summary: "Recovered transcript",
                updatedAt: now.addingTimeInterval(-10_800),
                jumpTarget: JumpTarget(
                    terminalApp: "Unknown",
                    workspaceName: "open-island",
                    paneTitle: "Claude e45d5e87",
                    workingDirectory: "/tmp/open-island"
                )
            ),
            AgentSession(
                id: "c9a48d05-c1f9-4e39-ab66-19edef0c2bc9",
                title: "Claude · open-island",
                tool: .claudeCode,
                origin: .live,
                attachmentState: .stale,
                phase: .completed,
                summary: "Recovered transcript",
                updatedAt: now.addingTimeInterval(-64_800),
                jumpTarget: JumpTarget(
                    terminalApp: "Unknown",
                    workspaceName: "open-island",
                    paneTitle: "Claude c9a48d05",
                    workingDirectory: "/tmp/open-island"
                )
            ),
        ]
        let activeProcesses: [ActiveProcessSnapshot] = [
            .init(
                tool: .claudeCode,
                sessionID: nil,
                workingDirectory: "/tmp/open-island",
                terminalTTY: "/dev/ttys002",
                terminalApp: "Ghostty"
            ),
        ]

        let merged = model.monitoring.mergedWithSyntheticClaudeSessions(
            existingSessions: recoveredSessions,
            activeProcesses: activeProcesses,
            now: now
        )

        // With relaxed CWD matching, recovered session matches the process
        // so no synthetic session is created.
        #expect(merged.count == 2)
        #expect(merged.allSatisfy { !$0.id.hasPrefix("claude-process:") })

        let probe = TerminalSessionAttachmentProbe()
        let resolutions = probe.sessionResolutions(
            for: merged,
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: activeProcesses,
            now: now
        )

        model.state = SessionState(sessions: merged)
        _ = model.state.reconcileAttachmentStates(resolutions.mapValues(\.attachmentState))
        _ = model.state.reconcileJumpTargets(
            resolutions.reduce(into: [String: JumpTarget]()) { partialResult, entry in
                if let correctedJumpTarget = entry.value.correctedJumpTarget {
                    partialResult[entry.key] = correctedJumpTarget
                }
            }
        )

        let claudeSessions = model.state.sessions.filter { $0.tool == .claudeCode }
        #expect(claudeSessions.count == 2)
    }

    private func listSession(id: String, phase: SessionPhase, updatedAt: Date) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(id)",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: phase.displayName,
            updatedAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: id,
                paneTitle: "codex ~/\(id)",
                workingDirectory: "/tmp/\(id)",
                terminalSessionID: "ghostty-\(id)"
            )
        )
    }

    private func makeVisibleSession(id: String, updatedAt: Date) -> AgentSession {
        var session = listSession(id: id, phase: .running, updatedAt: updatedAt)
        session.isProcessAlive = true
        return session
    }

    private func codexAppSession(id: String, updatedAt: Date) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(id)",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "open-island",
                paneTitle: id,
                workingDirectory: "/tmp/open-island",
                codexThreadID: id
            )
        )
    }

    private func placementDiagnostics(mode: OverlayPlacementMode) -> OverlayPlacementDiagnostics {
        OverlayPlacementDiagnostics(
            targetScreenID: mode == .notch ? "display-notch" : "display-topbar",
            targetScreenName: mode == .notch ? "Built-in Display" : "External Display",
            selectionSummary: "test",
            mode: mode,
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(top: mode == .notch ? 37 : 0, left: 0, bottom: 0, right: 0),
            overlayFrame: NSRect(x: 400, y: 820, width: 700, height: 160)
        )
    }

    private func restoreDefault(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
