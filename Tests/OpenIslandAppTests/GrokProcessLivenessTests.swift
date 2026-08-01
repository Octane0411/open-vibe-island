import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct GrokProcessLivenessTests {
    @Test
    func anyGrokProcessKeepsUnmatchedNonEndedSessionsAlive() {
        let coordinator = ProcessMonitoringCoordinator()
        var session = AgentSession(
            id: "grok-uuid-1",
            title: "Grok · work",
            tool: .grokBuild,
            phase: .running,
            summary: "Working",
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workspaceName: "work",
                paneTitle: "Grok",
                workingDirectory: "/tmp/work",
                terminalTTY: "/dev/ttys099"
            )
        )
        session.isHookManaged = true
        session.isSessionEnded = false

        coordinator.stateAccessor = { SessionState(sessions: [session]) }

        // Process has no sessionID and a different TTY → no unique match.
        let processes = [
            ActiveAgentProcessDiscovery.ProcessSnapshot(
                tool: .grokBuild,
                sessionID: nil,
                workingDirectory: "/tmp/other",
                terminalTTY: "/dev/ttys001"
            ),
        ]

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: processes,
            isCodexAppRunning: false
        )
        #expect(alive.contains("grok-uuid-1"))
    }

    @Test
    func uniqueTTYMatchClaimsSingleGrokSession() {
        let coordinator = ProcessMonitoringCoordinator()
        var session = AgentSession(
            id: "grok-uuid-tty",
            title: "Grok · work",
            tool: .grokBuild,
            phase: .running,
            summary: "Working",
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workspaceName: "work",
                paneTitle: "Grok",
                workingDirectory: "/tmp/work",
                terminalTTY: "/dev/ttys042"
            )
        )
        session.isHookManaged = true

        coordinator.stateAccessor = { SessionState(sessions: [session]) }

        let processes = [
            ActiveAgentProcessDiscovery.ProcessSnapshot(
                tool: .grokBuild,
                sessionID: nil,
                workingDirectory: "/tmp/work",
                terminalTTY: "/dev/ttys042"
            ),
        ]

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: processes,
            isCodexAppRunning: false
        )
        #expect(alive == ["grok-uuid-tty"])
    }

    @Test
    func endedGrokSessionIsNotKeptAliveByProcessPresence() {
        let coordinator = ProcessMonitoringCoordinator()
        var session = AgentSession(
            id: "grok-uuid-ended",
            title: "Grok · work",
            tool: .grokBuild,
            phase: .completed,
            summary: "Done",
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workspaceName: "work",
                paneTitle: "Grok",
                workingDirectory: "/tmp/work",
                terminalTTY: "/dev/ttys042"
            )
        )
        session.isHookManaged = true
        session.isSessionEnded = true

        coordinator.stateAccessor = { SessionState(sessions: [session]) }

        let processes = [
            ActiveAgentProcessDiscovery.ProcessSnapshot(
                tool: .grokBuild,
                sessionID: nil,
                workingDirectory: "/tmp/work",
                terminalTTY: "/dev/ttys042"
            ),
        ]

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: processes,
            isCodexAppRunning: false
        )
        #expect(!alive.contains("grok-uuid-ended"))
    }

    @Test
    func noGrokProcessLeavesSessionOutOfAliveSet() {
        let coordinator = ProcessMonitoringCoordinator()
        var session = AgentSession(
            id: "grok-uuid-orphan",
            title: "Grok · work",
            tool: .grokBuild,
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
        #expect(!alive.contains("grok-uuid-orphan"))
    }
}
