import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct ClaudeBackgroundSessionDiscoveryTests {
    /// Process tree produced by `claude agents --cwd .` in an iTerm tab: the
    /// view starts the daemon, whose pty hosts run session engines and warm
    /// spares (a spare becomes the engine of the next dispatched session).
    private static let agentsViewProcessTree = """
      100 1 ?? /Applications/iTerm.app/Contents/MacOS/iTerm2
      110 100 ttys000 -zsh
      120 110 ttys000 claude agents --cwd . --dangerously-skip-permissions
      130 120 ?? /Users/test/.local/bin/claude daemon run --origin transient
      140 130 ?? /Users/test/.local/share/claude/ClaudeCode.app/Contents/MacOS/claude --bg-pty-host /tmp/cc-daemon-501/x/pty/72e15398.sock 207 58 -- /Users/test/.local/share/claude/versions/2.1.287
      150 140 ttys002 /Users/test/.local/share/claude/versions/2.1.287 --session-id 72e15398-ff3d-4a74-9d70-2424686dccdc --agent claude --permission-mode bypassPermissions
      160 130 ?? claude bg-pty-host --bg-pty-host /tmp/cc-daemon-501/x/spare/a.pty.sock 200 50 -- /Users/test/.local/share/claude/versions/2.1.287 --bg-spare /tmp/cc-daemon-501/x/spare/a.claim.sock
      170 160 ttys001 claude bg-spare --bg-spare /tmp/cc-daemon-501/x/spare/a.claim.sock
      180 110 ttys003 claude attach 72e15398
    """

    @Test
    func discoverReportsDaemonHostedProcessesAndSkipsControlProcesses() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return Self.agentsViewProcessTree
            }
            Issue.record("unexpected command \(executablePath) \(arguments)")
            return nil
        }

        let snapshots = discovery.discover()

        #expect(snapshots.count == 2)
        #expect(snapshots.contains(.init(
            tool: .claudeCode,
            sessionID: "72e15398-ff3d-4a74-9d70-2424686dccdc",
            workingDirectory: nil,
            terminalTTY: nil,
            processID: "150",
            isClaudeDaemonHosted: true
        )))
        #expect(snapshots.contains(.init(
            tool: .claudeCode,
            sessionID: nil,
            workingDirectory: nil,
            terminalTTY: nil,
            processID: "170",
            isClaudeDaemonHosted: true
        )))
    }

    @Test
    func interactiveClaudeInTerminalTabIsStillDiscovered() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  100 1 ?? /Applications/iTerm.app/Contents/MacOS/iTerm2
                  110 100 ttys000 -zsh
                  120 110 ttys000 claude --name feature-x
                """
            }

            guard executablePath == "/usr/sbin/lsof", arguments.dropFirst(2).first == "120" else {
                return nil
            }
            return """
            fcwd
            n/Users/test/dev/local
            """
        }

        let snapshots = discovery.discover()

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.workingDirectory == "/Users/test/dev/local")
        #expect(snapshots.first?.terminalTTY == "/dev/ttys000")
        #expect(snapshots.first?.isClaudeDaemonHosted == false)
    }

    @MainActor
    @Test
    func daemonHostedProcessesKeepOnlyTheirOwnSessionsAlive() {
        func session(_ id: String, pid: Int32?) -> AgentSession {
            AgentSession(
                id: id,
                title: "Claude · local",
                tool: .claudeCode,
                phase: .completed,
                summary: "Ready",
                updatedAt: .now,
                jumpTarget: JumpTarget(
                    terminalApp: "iTerm",
                    workspaceName: "local",
                    paneTitle: "Claude",
                    workingDirectory: "/Users/test/dev/local",
                    terminalSessionID: "BF4CAE15-CFAB-4204-85C2-048613CB13C3",
                    terminalTTY: "/dev/ttys000",
                    backgroundAgentPID: pid
                )
            )
        }

        var state = SessionState(sessions: [
            session("claimed-spare-session", pid: 170),
            session("72e15398-ff3d-4a74-9d70-2424686dccdc", pid: nil),
            session("engine-exited-session", pid: 999),
            session("same-cwd-without-pid", pid: nil),
        ])
        let coordinator = ProcessMonitoringCoordinator()
        coordinator.syntheticClaudeSessionPrefix = "claude-process:"
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }

        let aliveIDs = coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: [],
            isCodexAppRunning: false,
            daemonHostedClaudeProcesses: [
                .init(
                    tool: .claudeCode,
                    sessionID: "72e15398-ff3d-4a74-9d70-2424686dccdc",
                    workingDirectory: nil,
                    terminalTTY: nil,
                    processID: "150",
                    isClaudeDaemonHosted: true
                ),
                .init(
                    tool: .claudeCode,
                    sessionID: nil,
                    workingDirectory: nil,
                    terminalTTY: nil,
                    processID: "170",
                    isClaudeDaemonHosted: true
                ),
            ]
        )

        #expect(aliveIDs == ["claimed-spare-session", "72e15398-ff3d-4a74-9d70-2424686dccdc"])
    }

    @MainActor
    @Test
    func unclaimedDaemonSparesNeverStayAliveEvenWithLivePID() {
        var state = SessionState(sessions: [
            AgentSession(
                id: "4224385d-7e48-4983-a472-424799717f5b",
                title: "Claude · local",
                tool: .claudeCode,
                phase: .completed,
                summary: "Ready",
                updatedAt: .now,
                jumpTarget: JumpTarget(
                    terminalApp: "iTerm",
                    workspaceName: "local",
                    paneTitle: "Claude",
                    workingDirectory: "/Users/test/dev/local",
                    backgroundAgentPID: 21694
                )
            ),
        ])
        let coordinator = ProcessMonitoringCoordinator()
        coordinator.syntheticClaudeSessionPrefix = "claude-process:"
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }

        let spare = ActiveAgentProcessDiscovery.ProcessSnapshot(
            tool: .claudeCode,
            sessionID: nil,
            workingDirectory: nil,
            terminalTTY: nil,
            processID: "21694",
            isClaudeDaemonHosted: true
        )

        #expect(coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: [],
            isCodexAppRunning: false,
            daemonHostedClaudeProcesses: [spare]
        ) == ["4224385d-7e48-4983-a472-424799717f5b"])
        #expect(coordinator.sessionIDsWithAliveProcesses(
            activeProcesses: [],
            isCodexAppRunning: false,
            daemonHostedClaudeProcesses: [spare],
            unclaimedSpareSessionIDs: ["4224385d-7e48-4983-a472-424799717f5b"]
        ).isEmpty)
    }

    @MainActor
    @Test
    func daemonHostedProcessesNeverBecomeSyntheticSessions() {
        var state = SessionState(sessions: [])
        let coordinator = ProcessMonitoringCoordinator()
        coordinator.syntheticClaudeSessionPrefix = "claude-process:"
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }

        coordinator.reconcileSessionAttachments(activeProcesses: [
            .init(
                tool: .claudeCode,
                sessionID: nil,
                workingDirectory: nil,
                terminalTTY: nil,
                processID: "170",
                isClaudeDaemonHosted: true
            ),
        ])

        #expect(state.sessions.isEmpty)
    }
}
