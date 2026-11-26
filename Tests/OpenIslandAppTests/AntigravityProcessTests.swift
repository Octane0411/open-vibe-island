import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

struct AntigravityProcessDiscoveryTests {
    @Test
    func discoverRecognizesStandaloneAndSymlinkedAntigravityEntries() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  101 200 ttys001 agy
                  102 201 ttys002 /Users/test/.antigravity/antigravity/bin/antigravity
                  200 900 ttys001 -/opt/homebrew/bin/fish
                  201 900 ttys002 -/opt/homebrew/bin/fish
                  103 202 ttys003 /Users/test/.local/bin/agy
                  202 900 ttys003 -/opt/homebrew/bin/fish
                  900 1 ?? /Applications/Ghostty.app/Contents/MacOS/ghostty
                """
            }

            guard executablePath == "/usr/sbin/lsof",
                  let pid = arguments.dropFirst(2).first else {
                return nil
            }

            switch pid {
            case "101", "102", "103":
                return """
                fcwd
                n/tmp/open-island
                """
            default:
                Issue.record("unexpected lsof lookup for pid \(pid)")
                return nil
            }
        }

        let snapshots = discovery.discover()

        #expect(snapshots.filter { $0.tool == .antigravity }.count == 3)
        #expect(snapshots.contains { snapshot in
            snapshot.tool == .antigravity
                && snapshot.workingDirectory == "/tmp/open-island"
                && snapshot.terminalTTY == "/dev/ttys001"
                && snapshot.terminalApp == "Ghostty"
        })
    }

    @Test
    func discoverIgnoresCommandsThatOnlyMentionAntigravityInArguments() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, _ in
            if executablePath == "/bin/ps" {
                return """
                  101 200 ttys001 vim notes-about-antigravity.md
                  102 201 ttys002 /usr/local/bin/agytool deploy
                  103 202 ttys003 grep agy log.txt
                  200 900 ttys001 -/opt/homebrew/bin/fish
                  201 900 ttys002 -/opt/homebrew/bin/fish
                  202 900 ttys003 -/opt/homebrew/bin/fish
                """
            }

            return nil
        }

        let snapshots = discovery.discover()

        #expect(snapshots.filter { $0.tool == .antigravity }.isEmpty)
    }
}

@MainActor
struct AntigravitySyntheticSessionTests {
    @Test
    func liveProcessBecomesSyntheticSession() {
        let coordinator = ProcessMonitoringCoordinator()
        let process = ActiveAgentProcessDiscovery.ProcessSnapshot(
            tool: .antigravity,
            sessionID: nil,
            workingDirectory: "/tmp/open-island",
            terminalTTY: "/dev/ttys001",
            terminalApp: "Ghostty"
        )

        let merged = coordinator.mergedWithSyntheticAntigravitySessions(
            existingSessions: [],
            activeProcesses: [process]
        )

        #expect(merged.count == 1)
        let session = merged[0]
        #expect(session.tool == .antigravity)
        #expect(session.id.hasPrefix("antigravity-process:"))
        #expect(session.title.hasPrefix("Antigravity · "))
        #expect(session.phase == .running)
        #expect(session.isProcessAlive)
        #expect(session.jumpTarget?.terminalTTY == "/dev/ttys001")
        #expect(session.jumpTarget?.workingDirectory == "/tmp/open-island")
    }

    @Test
    func noProcessLeavesExistingSessionsUnchanged() {
        let coordinator = ProcessMonitoringCoordinator()

        let merged = coordinator.mergedWithSyntheticAntigravitySessions(
            existingSessions: [],
            activeProcesses: []
        )

        #expect(merged.isEmpty)
    }

    @Test
    func sameProcessIsNotSynthesizedTwice() {
        let coordinator = ProcessMonitoringCoordinator()
        let process = ActiveAgentProcessDiscovery.ProcessSnapshot(
            tool: .antigravity,
            sessionID: nil,
            workingDirectory: "/tmp/open-island",
            terminalTTY: "/dev/ttys001",
            terminalApp: "Ghostty"
        )

        let firstMerge = coordinator.mergedWithSyntheticAntigravitySessions(
            existingSessions: [],
            activeProcesses: [process]
        )
        let secondMerge = coordinator.mergedWithSyntheticAntigravitySessions(
            existingSessions: firstMerge,
            activeProcesses: [process]
        )

        #expect(secondMerge.count == 1)
    }
}

@MainActor
struct AntigravityProcessLivenessTests {
    @Test
    func antigravityProcessKeepsSessionAlive() {
        let coordinator = ProcessMonitoringCoordinator()
        let session = AgentSession(
            id: "antigravity-process:ttys001|open-island|Ghostty",
            title: "Antigravity · open-island",
            tool: .antigravity,
            phase: .running,
            summary: "Working",
            updatedAt: .now
        )

        coordinator.stateAccessor = { SessionState(sessions: [session]) }

        let processes = [
            ActiveAgentProcessDiscovery.ProcessSnapshot(
                tool: .antigravity,
                sessionID: nil,
                workingDirectory: "/tmp/open-island",
                terminalTTY: "/dev/ttys001"
            ),
        ]

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: processes,
            isCodexAppRunning: false
        )
        #expect(alive.contains("antigravity-process:ttys001|open-island|Ghostty"))
    }

    @Test
    func noAntigravityProcessLeavesSessionOutOfAliveSet() {
        let coordinator = ProcessMonitoringCoordinator()
        let session = AgentSession(
            id: "antigravity-process:ttys001|open-island|Ghostty",
            title: "Antigravity · open-island",
            tool: .antigravity,
            phase: .running,
            summary: "Working",
            updatedAt: .now
        )

        coordinator.stateAccessor = { SessionState(sessions: [session]) }

        let alive = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: [],
            isCodexAppRunning: false
        )
        #expect(!alive.contains("antigravity-process:ttys001|open-island|Ghostty"))
    }
}
