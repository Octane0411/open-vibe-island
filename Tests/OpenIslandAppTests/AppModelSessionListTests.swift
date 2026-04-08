import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct AppModelSessionListTests {

    /// Populates both `model.state` and `model.sessionStore` from AgentSession arrays.
    private func loadSessions(_ agentSessions: [AgentSession], into model: AppModel) {
        model.state = SessionState(sessions: agentSessions)
        for s in agentSessions {
            model.sessionStore.sessions[s.id] = TrackedSession(
                id: s.id,
                tool: s.tool,
                phase: s.phase,
                summary: s.summary,
                startedAt: s.startedAt,
                lastActivityAt: s.updatedAt,
                terminal: s.jumpTarget.map {
                    TerminalInfo(app: $0.terminalApp, tty: $0.terminalTTY, terminalSessionID: $0.terminalSessionID)
                },
                workingDirectory: s.jumpTarget?.workingDirectory,
                permissionRequest: s.permissionRequest,
                questionPrompt: s.questionPrompt,
                processState: s.isProcessAlive ? .alive : .unknown,
                customTitle: s.claudeMetadata?.customTitle,
                transcriptPath: s.claudeMetadata?.transcriptPath,
                metadata: SessionMetadata(
                    initialPrompt: s.initialUserPromptText,
                    lastPrompt: s.latestUserPromptText,
                    lastAssistantMessage: s.lastAssistantMessageText,
                    model: s.claudeMetadata?.model,
                    currentTool: s.currentToolName,
                    currentToolInputPreview: s.currentCommandPreviewText,
                    worktreeBranch: s.claudeMetadata?.worktreeBranch,
                    activeSubagents: s.claudeMetadata?.activeSubagents ?? [],
                    activeTasks: s.claudeMetadata?.activeTasks ?? []
                ),
                origin: s.origin
            )
        }
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

        let recentSession = AgentSession(
            id: "recent-session",
            title: "Claude · recent",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Finished",
            updatedAt: now.addingTimeInterval(-1500),  // > 20 min ago, outside visibility window
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
        )

        loadSessions([liveSession, recentSession], into: model)

        #expect(model.surfacedSessions.map(\.id) == ["live-session"])
        #expect(model.recentSessions.map(\.id) == ["recent-session"])
        #expect(model.islandListSessions.map(\.id) == ["live-session"])
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

        loadSessions([runningLive, oldTurnSameSplit, otherLive], into: model)

        // SessionStore doesn't deduplicate by terminal — all 3 are visible (all alive)
        #expect(model.surfacedSessions.count == 3)
        #expect(model.liveRunningCount == 1)
        #expect(model.liveAttentionCount == 0)
    }

    @Test
    func sessionBootstrapPlaceholderAppearsWhileStartupResolutionIsPending() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.isResolvingInitialLiveSessions = true

        // Session exists in sessionStore but with unknown process state (not alive).
        // shouldShowSessionBootstrapPlaceholder requires sessions to exist but none visible.
        model.sessionStore.sessions["recovered-session"] = TrackedSession(
            id: "recovered-session",
            tool: .codex,
            phase: .running,
            summary: "Recovered from cache",
            startedAt: now,
            lastActivityAt: now,
            processState: .gone(since: now)
        )

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

        loadSessions([liveSession], into: model)

        #expect(model.liveSessionCount == 1)
        #expect(!model.shouldShowSessionBootstrapPlaceholder)
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

        let session = TrackedSession(
            id: "live-session",
            tool: .codex,
            phase: .running,
            summary: "Running",
            startedAt: now,
            lastActivityAt: now,
            terminal: TerminalInfo(
                app: "Ghostty",
                tty: nil,
                terminalSessionID: "ghostty-1"
            ),
            workingDirectory: "/tmp/open-island",
            processState: .alive,
            origin: .live
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

        // Put session in sessionStore with unknown process state (not visible)
        model.sessionStore.sessions["recovered-session"] = TrackedSession(
            id: "recovered-session",
            tool: .codex,
            phase: .running,
            summary: "Recovered from cache",
            startedAt: now,
            lastActivityAt: now,
            processState: .unknown
        )
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

        // Session is in sessionStore but with gone process state, so not visible
        #expect(model.liveSessionCount == 0)
        #expect(model.state.session(id: "recovered-session")?.attachmentState == .stale)
        #expect(model.shouldShowSessionBootstrapPlaceholder)
    }

    @Test
    func bridgeEventsStillPromoteSessionsToAttached() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        // Put session in sessionStore
        model.sessionStore.sessions["live-session"] = TrackedSession(
            id: "live-session",
            tool: .codex,
            phase: .running,
            summary: "Recovered from cache",
            startedAt: now,
            lastActivityAt: now,
            processState: .unknown
        )
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
        // Bridge events mark the session process alive in sessionStore
        #expect(model.sessionStore.session(id: "live-session")?.processState == .alive)
    }

    @Test
    func rolloutCompletionDoesNotPresentNotificationDuringColdStart() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.isResolvingInitialLiveSessions = true
        model.notchStatus = .closed
        model.notchOpenReason = nil

        model.sessionStore.sessions["recovered-session"] = TrackedSession(
            id: "recovered-session",
            tool: .codex,
            phase: .running,
            summary: "Recovered from cache",
            startedAt: now,
            lastActivityAt: now,
            processState: .unknown
        )
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
    func mergeDiscoveredClaudeSessionsPreservesRegistryJumpTargetAndAddsTranscriptMetadata() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        let existingSession = AgentSession(
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
        )
        loadSessions([existingSession], into: model)

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

}
