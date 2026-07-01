import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct ProcessMonitoringCoordinatorTests {
    @Test
    @MainActor
    func pollingIntervalTracksSessionUrgency() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(ProcessMonitoringCoordinator.pollingInterval(
            for: [],
            isResolvingInitialLiveSessions: true,
            now: now
        ) == 2)
        #expect(ProcessMonitoringCoordinator.pollingInterval(
            for: [],
            isResolvingInitialLiveSessions: false,
            now: now
        ) == 30)
        #expect(ProcessMonitoringCoordinator.pollingInterval(
            for: [session(phase: .running, updatedAt: now.addingTimeInterval(-600))],
            isResolvingInitialLiveSessions: false,
            now: now
        ) == 2)
        #expect(ProcessMonitoringCoordinator.pollingInterval(
            for: [session(phase: .completed, updatedAt: now.addingTimeInterval(-60))],
            isResolvingInitialLiveSessions: false,
            now: now
        ) == 8)
        #expect(ProcessMonitoringCoordinator.pollingInterval(
            for: [session(phase: .completed, updatedAt: now.addingTimeInterval(-600))],
            isResolvingInitialLiveSessions: false,
            now: now
        ) == 20)
    }

    @Test
    @MainActor
    func terminalSnapshotsAreGatedByTrackedSessionTargets() {
        let now = Date(timeIntervalSince1970: 1_000)

        let empty = ProcessMonitoringCoordinator.monitoringOptions(
            for: [],
            isResolvingInitialLiveSessions: false,
            now: now
        )
        #expect(empty.probeGhostty == false)
        #expect(empty.probeTerminal == false)
        #expect(empty.probeITerm == false)

        let ghostty = ProcessMonitoringCoordinator.monitoringOptions(
            for: [session(terminalApp: "Ghostty", updatedAt: now)],
            isResolvingInitialLiveSessions: false,
            now: now
        )
        #expect(ghostty.probeGhostty == true)
        #expect(ghostty.probeTerminal == false)
        #expect(ghostty.probeITerm == false)

        let terminal = ProcessMonitoringCoordinator.monitoringOptions(
            for: [session(terminalApp: "Terminal", updatedAt: now)],
            isResolvingInitialLiveSessions: false,
            now: now
        )
        #expect(terminal.probeGhostty == false)
        #expect(terminal.probeTerminal == true)
        #expect(terminal.probeITerm == false)

        let iterm = ProcessMonitoringCoordinator.monitoringOptions(
            for: [session(terminalApp: "iTerm", updatedAt: now)],
            isResolvingInitialLiveSessions: false,
            now: now
        )
        #expect(iterm.probeGhostty == false)
        #expect(iterm.probeTerminal == false)
        #expect(iterm.probeITerm == true)
    }

    private func session(
        phase: SessionPhase = .completed,
        terminalApp: String = "Ghostty",
        updatedAt: Date
    ) -> AgentSession {
        AgentSession(
            id: UUID().uuidString.lowercased(),
            title: "Codex",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "Summary",
            updatedAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: terminalApp,
                workspaceName: "open-island",
                paneTitle: "codex ~/open-island",
                workingDirectory: "/tmp/open-island"
            )
        )
    }
}
