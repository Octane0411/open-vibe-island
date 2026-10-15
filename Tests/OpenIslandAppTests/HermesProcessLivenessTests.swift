import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct HermesProcessLivenessTests {
    @Test
    func anyHermesProcessKeepsNonEndedSessionsAlive() {
        let coordinator = ProcessMonitoringCoordinator()
        var state = SessionState()
        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "hermes-session-1",
                    title: "Hermes · work",
                    tool: .hermes,
                    origin: .live,
                    initialPhase: .running,
                    summary: "Working",
                    timestamp: .now,
                    jumpTarget: JumpTarget(
                        terminalApp: "iTerm2",
                        workspaceName: "work",
                        paneTitle: "hermes",
                        workingDirectory: "/tmp/work",
                        terminalTTY: "/dev/ttys099"
                    )
                )
            )
        )
        coordinator.stateAccessor = { state }

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
        var state = SessionState()
        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "hermes-session-ended",
                    title: "Hermes · work",
                    tool: .hermes,
                    origin: .live,
                    initialPhase: .running,
                    summary: "Working",
                    timestamp: .now,
                    jumpTarget: JumpTarget(
                        terminalApp: "iTerm2",
                        workspaceName: "work",
                        paneTitle: "hermes",
                        workingDirectory: "/tmp/work",
                        terminalTTY: "/dev/ttys042"
                    )
                )
            )
        )
        state.apply(
            .sessionCompleted(
                SessionCompleted(
                    sessionID: "hermes-session-ended",
                    summary: "Done",
                    timestamp: .now,
                    isSessionEnd: true
                )
            )
        )
        coordinator.stateAccessor = { state }

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
        var state = SessionState()
        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "hermes-session-orphan",
                    title: "Hermes · work",
                    tool: .hermes,
                    origin: .live,
                    initialPhase: .running,
                    summary: "Working",
                    timestamp: .now
                )
            )
        )
        coordinator.stateAccessor = { state }

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: [],
            isCodexAppRunning: false
        )
        #expect(!alive.contains("hermes-session-orphan"))
    }
}
