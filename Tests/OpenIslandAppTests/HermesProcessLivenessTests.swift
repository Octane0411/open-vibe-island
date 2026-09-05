import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct HermesProcessLivenessTests {
    @Test
    func anyHermesProcessKeepsNonEndedSessionsAlive() {
        let coordinator = ProcessMonitoringCoordinator()
        var session = AgentSession(
            id: "hermes-session-1",
            title: "Hermes · work",
            tool: .hermes,
            phase: .running,
            summary: "Working",
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "iTerm2",
                workspaceName: "work",
                paneTitle: "hermes",
                workingDirectory: "/tmp/work",
                terminalTTY: "/dev/ttys099"
            )
        )
        session.isHookManaged = true
        session.isSessionEnded = false

        coordinator.stateAccessor = { SessionState(sessions: [session]) }

        let processes = [
            ActiveAgentProcessDiscovery.ProcessSnapshot(
                tool: .hermes,
                sessionID: nil,
                workingDirectory: "/tmp/work",
                terminalTTY: "/dev/ttys001"
            ),
        ]

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: processes,
            isCodexAppRunning: false
        )
        #expect(alive.contains("hermes-session-1"))
    }

    @Test
    func endedHermesSessionIsNotKeptAliveByProcessPresence() {
        let coordinator = ProcessMonitoringCoordinator()
        var session = AgentSession(
            id: "hermes-session-ended",
            title: "Hermes · work",
            tool: .hermes,
            phase: .completed,
            summary: "Done",
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "iTerm2",
                workspaceName: "work",
                paneTitle: "hermes",
                workingDirectory: "/tmp/work",
                terminalTTY: "/dev/ttys042"
            )
        )
        session.isHookManaged = true
        session.isSessionEnded = true

        coordinator.stateAccessor = { SessionState(sessions: [session]) }

        let processes = [
            ActiveAgentProcessDiscovery.ProcessSnapshot(
                tool: .hermes,
                sessionID: nil,
                workingDirectory: "/tmp/work",
                terminalTTY: "/dev/ttys042"
            ),
        ]

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: processes,
            isCodexAppRunning: false
        )
        #expect(!alive.contains("hermes-session-ended"))
    }

    @Test
    func noHermesProcessLeavesSessionOutOfAliveSet() {
        let coordinator = ProcessMonitoringCoordinator()
        var session = AgentSession(
            id: "hermes-session-orphan",
            title: "Hermes · work",
            tool: .hermes,
            phase: .running,
            summary: "Working",
            updatedAt: .now
        )
        session.isHookManaged = true

        coordinator.stateAccessor = { SessionState(sessions: [session]) }

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: [],
            isCodexAppRunning: false
        )
        #expect(!alive.contains("hermes-session-orphan"))
    }
}
