import Foundation
import OpenIslandCore
import Testing
@testable import OpenIslandApp

@MainActor
struct CodexDesktopSessionHygieneTests {
    @Test
    func appServerOnlySurfacesActiveNonEphemeralThreads() {
        #expect(CodexAppServerCoordinator.shouldSurface(status: .active, ephemeral: false))
        #expect(!CodexAppServerCoordinator.shouldSurface(status: .idle, ephemeral: false))
        #expect(!CodexAppServerCoordinator.shouldSurface(status: .systemError, ephemeral: false))
        #expect(!CodexAppServerCoordinator.shouldSurface(status: .active, ephemeral: true))
    }

    @Test
    func rolloutFallbackOnlyRediscoversFreshRunningSessions() {
        let now = Date(timeIntervalSince1970: 40_000)
        let freshRunning = record(phase: .running, updatedAt: now.addingTimeInterval(-30))
        let staleRunning = record(
            sessionID: "stale-running",
            phase: .running,
            updatedAt: now.addingTimeInterval(-300)
        )
        let freshCompleted = record(
            sessionID: "fresh-completed",
            phase: .completed,
            updatedAt: now.addingTimeInterval(-10)
        )

        #expect(SessionDiscoveryCoordinator.shouldRediscoverCodexAppRecord(freshRunning, now: now))
        #expect(!SessionDiscoveryCoordinator.shouldRediscoverCodexAppRecord(staleRunning, now: now))
        #expect(!SessionDiscoveryCoordinator.shouldRediscoverCodexAppRecord(freshCompleted, now: now))
    }

    @Test
    func completedDesktopThreadIsNotVisibleWhenHostAppIsRunning() {
        let startedAt = Date(timeIntervalSince1970: 50_000)
        var state = SessionState()
        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "desktop-thread",
                    title: "Desktop thread",
                    tool: .codex,
                    origin: .live,
                    summary: "Working",
                    timestamp: startedAt,
                    jumpTarget: JumpTarget(
                        terminalApp: "Codex.app",
                        workspaceName: "open-island",
                        paneTitle: "Desktop thread",
                        codexThreadID: "desktop-thread"
                    )
                )
            )
        )

        #expect(state.session(id: "desktop-thread")?.isVisibleInIsland == true)

        state.apply(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "desktop-thread",
                    summary: "Idle.",
                    phase: .completed,
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )
        state.markProcessLiveness(
            aliveSessionIDs: ["desktop-thread"],
            isCodexAppRunning: true
        )

        #expect(state.session(id: "desktop-thread")?.isProcessAlive == true)
        #expect(state.session(id: "desktop-thread")?.isVisibleInIsland == false)
        #expect(state.liveSessionCount == 0)
    }

    @Test
    func attentionThreadDisappearsWhenDesktopHostStops() {
        var session = AgentSession(
            id: "desktop-approval",
            title: "Desktop approval",
            tool: .codex,
            phase: .waitingForApproval,
            summary: "Waiting for approval",
            updatedAt: Date(timeIntervalSince1970: 60_000),
            permissionRequest: PermissionRequest(
                title: "Run command",
                summary: "Waiting for approval",
                affectedPath: "/tmp/worktree"
            )
        )
        session.isCodexAppSession = true
        session.isProcessAlive = true
        var state = SessionState(sessions: [session])

        #expect(state.liveAttentionCount == 1)

        state.markProcessLiveness(aliveSessionIDs: [], isCodexAppRunning: false)

        #expect(state.session(id: "desktop-approval")?.isProcessAlive == false)
        #expect(state.session(id: "desktop-approval")?.isVisibleInIsland == false)
        #expect(state.liveAttentionCount == 0)
    }

    private func record(
        sessionID: String = "fresh-running",
        phase: SessionPhase,
        updatedAt: Date
    ) -> CodexTrackedSessionRecord {
        CodexTrackedSessionRecord(
            sessionID: sessionID,
            title: sessionID,
            summary: "Summary",
            phase: phase,
            updatedAt: updatedAt
        )
    }
}
