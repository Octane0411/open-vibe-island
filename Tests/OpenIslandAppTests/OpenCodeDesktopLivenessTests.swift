import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct OpenCodeDesktopLivenessTests {
    @Test
    func runningDesktopAppKeepsActiveDesktopSessionAlive() {
        let coordinator = ProcessMonitoringCoordinator()
        coordinator.stateAccessor = {
            SessionState(sessions: [Self.session(phase: .running, updatedAt: .now)])
        }

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: [],
            isCodexAppRunning: false,
            isOpenCodeAppRunning: true
        )

        #expect(alive.contains("opencode-desktop"))
    }

    @Test
    func stoppedDesktopAppDoesNotKeepSessionAlive() {
        let coordinator = ProcessMonitoringCoordinator()
        coordinator.stateAccessor = {
            SessionState(sessions: [Self.session(phase: .running, updatedAt: .now)])
        }

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: [],
            isCodexAppRunning: false,
            isOpenCodeAppRunning: false
        )

        #expect(!alive.contains("opencode-desktop"))
    }

    @Test
    func staleCompletedDesktopSessionExpiresWhileAppRuns() {
        let coordinator = ProcessMonitoringCoordinator()
        coordinator.stateAccessor = {
            SessionState(sessions: [
                Self.session(phase: .completed, updatedAt: .now.addingTimeInterval(-601)),
            ])
        }

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: [],
            isCodexAppRunning: false,
            isOpenCodeAppRunning: true
        )

        #expect(!alive.contains("opencode-desktop"))
    }

    private static func session(phase: SessionPhase, updatedAt: Date) -> AgentSession {
        AgentSession(
            id: "opencode-desktop",
            title: "OpenCode Desktop",
            tool: .openCode,
            phase: phase,
            summary: "Testing",
            updatedAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: "OpenCode.app",
                workspaceName: "worktree",
                paneTitle: "OpenCode",
                workingDirectory: "/tmp/worktree"
            )
        )
    }
}
