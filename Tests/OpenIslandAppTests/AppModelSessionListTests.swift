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
            "appearance.island.v8.completedStaleThreshold",
            "appearance.island.v8.notch.rightSlot",
            "appearance.island.v8.notch.centerLabel",
            "appearance.island.v8.notch.stateIndicator",
            "appearance.island.v8.notch.sessionGroup",
            "appearance.island.v8.notch.sessionSort",
            "appearance.island.v8.notch.completedStaleThreshold",
            "appearance.island.v8.topBar.rightSlot",
            "appearance.island.v8.topBar.centerLabel",
            "appearance.island.v8.topBar.stateIndicator",
            "appearance.island.v8.topBar.sessionGroup",
            "appearance.island.v8.topBar.sessionSort",
            "appearance.island.v8.topBar.completedStaleThreshold",
            "appearance.island.v8.notch.showIdleSessions",
            "appearance.island.v8.topBar.showIdleSessions",
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
        #expect(model.islandListSessions.map(\.id) == ["live-session"])
    }

    @Test
    func islandListDeduplicatesSessionsSharingTheSameLiveGhosttyTerminal() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.updateAppearancePreferences(for: .topBar) { $0.showIdleSessions = true }
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

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
    func islandListKeepsDistinctCodexAppThreadsInTheSameWorkspace() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.updateAppearancePreferences(for: .topBar) { $0.showIdleSessions = true }
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

        var firstThread = AgentSession(
            id: "codex-app-thread-1",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "First Codex.app thread",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "open-island",
                paneTitle: "Codex · open-island",
                workingDirectory: "/tmp/open-island",
                codexThreadID: "codex-app-thread-1"
            )
        )
        firstThread.isCodexAppSession = true
        firstThread.isProcessAlive = true

        var secondThread = AgentSession(
            id: "codex-app-thread-2",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Second Codex.app thread",
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "open-island",
                paneTitle: "Codex · open-island",
                workingDirectory: "/tmp/open-island",
                codexThreadID: "codex-app-thread-2"
            )
        )
        secondThread.isCodexAppSession = true
        secondThread.isProcessAlive = true

        model.state = SessionState(sessions: [firstThread, secondThread])

        #expect(model.surfacedSessions.map(\.id) == ["codex-app-thread-1", "codex-app-thread-2"])
        #expect(model.liveSessionCount == 2)
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
        model.updateAppearancePreferences(for: .topBar) { $0.showIdleSessions = true }
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

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
    func islandSessionSectionsGroupStaleCompletedIntoIdle() {
        let now = Date()
        let model = AppModel()
        model.updateAppearancePreferences(for: .topBar) {
            $0.sessionGroup = .state
            $0.completedStaleThreshold = .fiveMinutes
            $0.showIdleSessions = true
        }
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

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

        #expect(model.islandSessionSections.map(\.id) == ["state-approval", "state-done", "state-idle"])
        #expect(model.islandSessionSections.map(\.sessions.first?.id) == ["approval", "done", "stale"])
    }

    @Test
    func islandSessionSectionsKeepCompletedInDoneWhenStaleThresholdIsNever() {
        let now = Date()
        let model = AppModel()
        model.updateAppearancePreferences(for: .topBar) {
            $0.sessionGroup = .state
            $0.completedStaleThreshold = .never
            $0.showIdleSessions = true
        }
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

        var oldDone = listSession(id: "old-done", phase: .completed, updatedAt: now.addingTimeInterval(-86_400))
        oldDone.isProcessAlive = true
        model.state = SessionState(sessions: [oldDone])

        #expect(model.islandSessionSections.map(\.id) == ["state-done"])
        #expect(model.islandSessionSections.first?.sessions.first?.id == "old-done")
    }

    @Test
    func idleSessionsAreHiddenByDefaultAndCanBeEnabledPerDisplayProfile() {
        let now = Date()
        let model = AppModel()
        var running = listSession(id: "running", phase: .running, updatedAt: now)
        var idle = listSession(id: "idle", phase: .completed, updatedAt: now.addingTimeInterval(-360))
        running.isProcessAlive = true
        idle.isProcessAlive = true
        model.state = SessionState(sessions: [idle, running])
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        model.islandRightSlot = .count

        #expect(model.islandListSessions.map(\.id) == ["running"])
        #expect(model.islandClosedSpotlight?.id == "running")
        if case let .count(count)? = model.islandClosedRightSlotContent() {
            #expect(count == 1)
        } else {
            Issue.record("Expected a closed-island count with idle sessions filtered out")
        }

        model.updateAppearancePreferences(for: .topBar) { $0.showIdleSessions = true }
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        #expect(model.showIdleSessions)
        #expect(Set(model.surfacedSessions.map(\.id)) == Set(["running", "idle"]))
        #expect(Set(model.islandListSessions.map(\.id)) == Set(["running", "idle"]))
        if case let .count(count)? = model.islandClosedRightSlotContent() {
            #expect(count == 2)
        } else {
            Issue.record("Expected a closed-island count with idle sessions enabled")
        }

        let reloaded = AppModel()
        reloaded.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        #expect(reloaded.showIdleSessions)
    }

    @Test
    func islandSessionListCanSortByLastUpdate() {
        let now = Date()
        let model = AppModel()
        model.updateAppearancePreferences(for: .topBar) {
            $0.sessionSort = .lastUpdate
            $0.showIdleSessions = true
        }
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

        var olderRunning = listSession(id: "older-running", phase: .running, updatedAt: now.addingTimeInterval(-120))
        var newerCompleted = listSession(id: "newer-completed", phase: .completed, updatedAt: now.addingTimeInterval(-10))
        olderRunning.isProcessAlive = true
        newerCompleted.isProcessAlive = true

        model.state = SessionState(sessions: [olderRunning, newerCompleted])

        #expect(model.islandListSessions.map(\.id) == ["newer-completed", "older-running"])
    }

    @Test
    func islandAppearancePreferencesPersistPerDisplayProfile() {
        let model = AppModel()
        model.updateAppearancePreferences(for: .notch) {
            $0.usageDisplay = .hidden
            $0.sessionGroup = .state
            $0.sessionStateIndicator = .bar
            $0.completedStaleThreshold = .twoMinutes
            $0.showIdleSessions = false
        }
        model.updateAppearancePreferences(for: .topBar) {
            $0.usageDisplay = .compact
            $0.sessionGroup = .project
            $0.sessionStateIndicator = .tint
            $0.completedStaleThreshold = .never
            $0.showIdleSessions = true
        }

        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .notch)
        #expect(model.islandUsageDisplay == .hidden)
        #expect(model.islandSessionGroup == .state)
        #expect(model.islandSessionStateIndicator == .bar)
        #expect(model.completedStaleThreshold == .twoMinutes)
        #expect(!model.showIdleSessions)

        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        #expect(model.islandUsageDisplay == .compact)
        #expect(model.islandSessionGroup == .project)
        #expect(model.islandSessionStateIndicator == .tint)
        #expect(model.completedStaleThreshold == .never)
        #expect(model.showIdleSessions)

        let reloaded = AppModel()
        reloaded.overlayPlacementDiagnostics = placementDiagnostics(mode: .notch)
        #expect(reloaded.islandUsageDisplay == .hidden)
        #expect(reloaded.islandSessionGroup == .state)
        #expect(reloaded.islandSessionStateIndicator == .bar)
        reloaded.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        #expect(reloaded.islandUsageDisplay == .compact)
        #expect(reloaded.islandSessionGroup == .project)
        #expect(reloaded.islandSessionStateIndicator == .tint)
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
    func newerRolloutActivityRestartsACompletedCodexTurn() {
        let completedAt = Date(timeIntervalSince1970: 2_000)
        let resumedAt = completedAt.addingTimeInterval(1)
        let model = AppModel()
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)

        var session = AgentSession(
            id: "resumed-codex-thread",
            title: "Project task",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Previous turn completed.",
            updatedAt: completedAt,
            codexMetadata: CodexSessionMetadata(
                transcriptPath: "/tmp/resumed-rollout.jsonl",
                lastUserPrompt: "Previous prompt"
            )
        )
        session.isCodexAppSession = true
        session.isProcessAlive = false
        model.state = SessionState(sessions: [session])

        // The watcher emits metadata before activity for the same appended
        // rollout batch, so both events carry the same newest timestamp.
        model.applyTrackedEvent(
            .sessionMetadataUpdated(
                SessionMetadataUpdated(
                    sessionID: session.id,
                    codexMetadata: CodexSessionMetadata(
                        transcriptPath: "/tmp/resumed-rollout.jsonl",
                        lastUserPrompt: "Continue the project"
                    ),
                    timestamp: resumedAt
                )
            ),
            updateLastActionMessage: false,
            ingress: .rollout
        )
        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: session.id,
                    summary: "Thinking.",
                    phase: .running,
                    timestamp: resumedAt
                )
            ),
            updateLastActionMessage: false,
            ingress: .rollout
        )

        #expect(model.state.session(id: session.id)?.phase == .running)
        #expect(model.state.session(id: session.id)?.summary == "Thinking.")
        #expect(model.state.session(id: session.id)?.isProcessAlive == true)
        #expect(model.islandListSessions.map(\.id) == [session.id])
    }

    @Test
    func staleRolloutActivityDoesNotRestartACompletedCodexTurn() {
        let completedAt = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        var session = AgentSession(
            id: "completed-codex-thread",
            title: "Completed project task",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Turn completed.",
            updatedAt: completedAt
        )
        session.isCodexAppSession = true
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: session.id,
                    summary: "Stale rollout tail.",
                    phase: .running,
                    timestamp: completedAt.addingTimeInterval(-1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .rollout
        )

        #expect(model.state.session(id: session.id)?.phase == .completed)
        #expect(model.state.session(id: session.id)?.summary == "Turn completed.")
    }

    @Test
    func appServerMetadataSyncDoesNotMakeOldCompletedThreadsRecent() {
        let now = Date()
        let model = AppModel()
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        model.updateAppearancePreferences(for: .topBar) {
            $0.completedStaleThreshold = .fiveMinutes
            $0.showIdleSessions = false
        }

        var running = AgentSession(
            id: "running-thread",
            title: "Running task",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Thinking.",
            updatedAt: now
        )
        running.isCodexAppSession = true
        running.isProcessAlive = true

        var recentlyCompleted = AgentSession(
            id: "recent-thread",
            title: "Recently completed task",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Just finished.",
            updatedAt: now.addingTimeInterval(-60)
        )
        recentlyCompleted.isCodexAppSession = true
        recentlyCompleted.isProcessAlive = true

        let oldCompletionDate = now.addingTimeInterval(-3_600)
        var oldCompleted = AgentSession(
            id: "old-thread",
            title: "Old completed task",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Finished long ago.",
            updatedAt: oldCompletionDate,
            jumpTarget: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "old-project",
                paneTitle: "Old completed task",
                workingDirectory: "/tmp/old-project",
                codexThreadID: "old-thread"
            ),
            codexMetadata: CodexSessionMetadata(
                transcriptPath: "/tmp/old-thread.jsonl"
            )
        )
        oldCompleted.isCodexAppSession = true
        oldCompleted.isProcessAlive = true

        model.state = SessionState(
            sessions: [running, recentlyCompleted, oldCompleted]
        )
        #expect(Set(model.islandListSessions.map(\.id)) == ["running-thread", "recent-thread"])

        let syncDate = now.addingTimeInterval(1)
        model.applyTrackedEvent(
            .sessionTitleUpdated(
                SessionTitleUpdated(
                    sessionID: oldCompleted.id,
                    title: "Synced old task title",
                    timestamp: syncDate
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )
        model.applyTrackedEvent(
            .jumpTargetUpdated(
                JumpTargetUpdated(
                    sessionID: oldCompleted.id,
                    jumpTarget: oldCompleted.jumpTarget!,
                    timestamp: syncDate
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )
        model.applyTrackedEvent(
            .sessionMetadataUpdated(
                SessionMetadataUpdated(
                    sessionID: oldCompleted.id,
                    codexMetadata: CodexSessionMetadata(
                        transcriptPath: "/tmp/old-thread.jsonl",
                        model: "gpt-5.6-sol",
                        reasoningEffort: "xhigh",
                        serviceTier: "priority"
                    ),
                    timestamp: syncDate
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        #expect(model.state.session(id: oldCompleted.id)?.updatedAt == oldCompletionDate)
        #expect(Set(model.islandListSessions.map(\.id)) == ["running-thread", "recent-thread"])
    }

    @Test
    func rolloutMetadataRefreshPreservesKnownCodexConfiguration() {
        let now = Date()
        let model = AppModel()
        model.state = SessionState(sessions: [
            AgentSession(
                id: "codex-project-thread",
                title: "Project task",
                tool: .codex,
                origin: .live,
                attachmentState: .attached,
                phase: .running,
                summary: "Working",
                updatedAt: now,
                codexMetadata: CodexSessionMetadata(
                    transcriptPath: "/tmp/rollout.jsonl",
                    lastUserPrompt: "Original prompt",
                    model: "gpt-5.6-sol",
                    reasoningEffort: "xhigh",
                    serviceTier: "priority"
                )
            ),
        ])

        model.applyTrackedEvent(
            .sessionMetadataUpdated(
                SessionMetadataUpdated(
                    sessionID: "codex-project-thread",
                    codexMetadata: CodexSessionMetadata(
                        transcriptPath: "/tmp/rollout.jsonl",
                        lastUserPrompt: "Updated prompt"
                    ),
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .rollout
        )

        let metadata = model.state.session(id: "codex-project-thread")?.codexMetadata
        #expect(metadata?.lastUserPrompt == "Updated prompt")
        #expect(metadata?.model == "gpt-5.6-sol")
        #expect(metadata?.reasoningEffort == "xhigh")
        #expect(metadata?.serviceTier == "priority")
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
    func hoverOpenedSessionListAutoCollapsesOnPointerExit() {
        let model = AppModel()
        model.notchStatus = .opened
        model.notchOpenReason = .hover
        model.islandSurface = .sessionList()

        #expect(model.shouldAutoCollapseOnMouseLeave)

        model.handlePointerExitedIslandSurface()

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(model.islandSurface == .sessionList())
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
    func startupRestoreDropsCachedInternalCodexSubagents() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-cached-subagents-\(UUID().uuidString)", isDirectory: true)
        let parentURL = rootURL.appendingPathComponent("rollout-parent.jsonl")
        let childURL = rootURL.appendingPathComponent("rollout-child.jsonl")
        let parentID = "codex-parent-thread"
        let now = Date(timeIntervalSince1970: 1_774_536_000)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        {"timestamp":"2026-03-27T12:00:00.000Z","type":"session_meta","payload":{"id":"\(parentID)","timestamp":"2026-03-27T12:00:00.000Z","cwd":"/tmp/project","source":"vscode"}}
        """.appending("\n").write(to: parentURL, atomically: true, encoding: .utf8)
        try """
        {"timestamp":"2026-03-27T12:00:01.000Z","type":"session_meta","payload":{"id":"codex-child-thread","timestamp":"2026-03-27T12:00:01.000Z","cwd":"/tmp/project","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(parentID)","depth":1,"agent_path":"/root/audit"}}}}}
        """.appending("\n").write(to: childURL, atomically: true, encoding: .utf8)

        func record(id: String, transcriptPath: String) -> CodexTrackedSessionRecord {
            CodexTrackedSessionRecord(
                sessionID: id,
                title: "Task",
                origin: .live,
                attachmentState: .attached,
                summary: "Working",
                phase: .running,
                updatedAt: now,
                codexMetadata: CodexSessionMetadata(transcriptPath: transcriptPath)
            )
        }

        let records = SessionDiscoveryCoordinator.restorableCodexRecords(
            from: [
                record(id: parentID, transcriptPath: parentURL.path),
                record(id: "codex-child-thread", transcriptPath: childURL.path),
            ],
            cutoff: now.addingTimeInterval(-60)
        )

        #expect(records.map(\.sessionID) == [parentID])
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

    @Test
    func mergedWithSyntheticCursorSessionsAddsCursorAgentWhenNoTrackedSessionExists() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        let merged = model.monitoring.mergedWithSyntheticCursorSessions(
            existingSessions: [],
            activeProcesses: [
                .init(
                    tool: .cursor,
                    sessionID: "6f7b9f8a-2bd0-48b4-a497-9801dd191d03",
                    workingDirectory: "/tmp/simple-agent-lab",
                    terminalTTY: "/dev/ttys003",
                    terminalApp: "Ghostty"
                ),
            ],
            now: now
        )

        #expect(merged.count == 1)
        #expect(merged.first?.id == "6f7b9f8a-2bd0-48b4-a497-9801dd191d03")
        #expect(merged.first?.tool == .cursor)
        #expect(merged.first?.attachmentState == .attached)
        #expect(merged.first?.jumpTarget?.terminalApp == "Ghostty")
        #expect(merged.first?.jumpTarget?.terminalTTY == "/dev/ttys003")
        #expect(merged.first?.cursorMetadata?.conversationId == "6f7b9f8a-2bd0-48b4-a497-9801dd191d03")
    }

    @Test
    func mergedWithSyntheticCursorSessionsSkipsSyntheticWhenHookSessionMatchesConversation() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        let existing = AgentSession(
            id: "6f7b9f8a-2bd0-48b4-a497-9801dd191d03",
            title: "Cursor · simple-agent-lab",
            tool: .cursor,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Cursor",
                workspaceName: "simple-agent-lab",
                paneTitle: "Cursor 6f7b9f8a",
                workingDirectory: "/tmp/simple-agent-lab"
            ),
            cursorMetadata: CursorSessionMetadata(
                conversationId: "6f7b9f8a-2bd0-48b4-a497-9801dd191d03"
            )
        )

        let merged = model.monitoring.mergedWithSyntheticCursorSessions(
            existingSessions: [existing],
            activeProcesses: [
                .init(
                    tool: .cursor,
                    sessionID: "6f7b9f8a-2bd0-48b4-a497-9801dd191d03",
                    workingDirectory: "/tmp/simple-agent-lab",
                    terminalTTY: "/dev/ttys003",
                    terminalApp: "Ghostty"
                ),
            ],
            now: now
        )

        #expect(merged.map(\.id) == [existing.id])
    }

    @Test
    func mergedWithSyntheticCursorSessionsDeduplicatesRepeatedConversationProcesses() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        let merged = model.monitoring.mergedWithSyntheticCursorSessions(
            existingSessions: [],
            activeProcesses: [
                .init(
                    tool: .cursor,
                    sessionID: "6f7b9f8a-2bd0-48b4-a497-9801dd191d03",
                    workingDirectory: "/tmp/simple-agent-lab",
                    terminalTTY: "/dev/ttys003",
                    terminalApp: "Ghostty"
                ),
                .init(
                    tool: .cursor,
                    sessionID: "6f7b9f8a-2bd0-48b4-a497-9801dd191d03",
                    workingDirectory: "/tmp/simple-agent-lab",
                    terminalTTY: "/dev/ttys004",
                    terminalApp: "Ghostty"
                ),
            ],
            now: now
        )

        #expect(merged.map(\.id) == ["6f7b9f8a-2bd0-48b4-a497-9801dd191d03"])
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
            id: "incoming-session",
            title: "Codex · incoming",
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

        #expect(model.state.session(id: "incoming-session")?.phase == .waitingForApproval)
        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface == currentSurface)
        #expect(model.activeIslandCardSession?.id == "current-session")
        #expect(model.measuredNotificationContentHeight == 280)
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
}
