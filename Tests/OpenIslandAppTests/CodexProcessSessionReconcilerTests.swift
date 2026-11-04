import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct CodexProcessSessionReconcilerTests {
    private func process(_ pid: String, tty: String, sessionID: String? = nil) -> ActiveProcessSnapshot {
        .init(
            tool: .codex, sessionID: sessionID,
            workingDirectory: "/tmp/project", terminalTTY: tty,
            terminalApp: "Terminal", processID: pid
        )
    }

    private func session(_ id: String, tty: String?) -> AgentSession {
        AgentSession(
            id: id, title: "Codex", tool: .codex, origin: .live,
            phase: .running, summary: "Working", updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Terminal", workspaceName: "project", paneTitle: "Codex",
                workingDirectory: "/tmp/project", terminalTTY: tty
            )
        )
    }

    @Test
    func separateTerminalsInSameWorkspaceHaveSeparateIdleRows() {
        let result = CodexProcessSessionReconciler.reconcile(
            sessions: [],
            processes: [process("101", tty: "/dev/ttys001"), process("102", tty: "/dev/ttys002")]
        )
        #expect(result.sessions.map(\.id) == ["codex-process:101", "codex-process:102"])
        #expect(result.sessions.map { $0.jumpTarget?.terminalTTY } == ["/dev/ttys001", "/dev/ttys002"])
        #expect(result.sessions.allSatisfy { $0.isProcessAlive && $0.isVisibleInIsland })
        #expect(result.sessions.allSatisfy { $0.phase == .completed && !$0.isHookManaged })
    }

    @Test
    func hookSessionReplacesPlaceholderOnlyOnItsOwnTTY() {
        let processes = [process("101", tty: "/dev/ttys001"), process("102", tty: "/dev/ttys002")]
        let initial = CodexProcessSessionReconciler.reconcile(sessions: [], processes: processes)
        var hookSession = session("real-thread", tty: "ttys002")
        hookSession.phase = .waitingForApproval
        hookSession.permissionRequest = PermissionRequest(
            title: "Approve", summary: "Run command", affectedPath: "/tmp/project"
        )

        let result = CodexProcessSessionReconciler.reconcile(
            sessions: initial.sessions + [hookSession], processes: processes
        )
        #expect(Set(result.sessions.map(\.id)) == ["codex-process:101", "real-thread"])
        #expect(result.processes.map(\.sessionID) == ["codex-process:101", "real-thread"])
        #expect(result.sessions.first { $0.id == "real-thread" } == hookSession)
    }

    @Test
    func doesNotGuessConversationFromWorkspaceOrAmbiguousTTY() {
        let processes = [process("101", tty: "/dev/ttys001")]
        let candidates = [session("old-one", tty: nil), session("old-two", tty: nil)]
        let result = CodexProcessSessionReconciler.reconcile(sessions: candidates, processes: processes)
        #expect(result.processes.first?.sessionID == "codex-process:101")

        let ambiguous = CodexProcessSessionReconciler.reconcile(
            sessions: [session("one", tty: "ttys001"), session("two", tty: "ttys001")],
            processes: processes
        )
        #expect(ambiguous.processes.first?.sessionID == "codex-process:101")
    }

    @Test
    func explicitTranscriptIdentityWinsBeforeFallbackMatching() {
        let processes = [
            process("101", tty: "ttys001"),
            process("102", tty: "ttys002", sessionID: "real-thread"),
        ]
        let result = CodexProcessSessionReconciler.reconcile(
            sessions: [session("real-thread", tty: "ttys001")], processes: processes
        )
        #expect(result.processes.map(\.sessionID) == ["codex-process:101", "real-thread"])
    }

    @Test
    func rejectsConflictingWorkspaceAndDesktopSessions() {
        var conflicting = session("other-workspace", tty: "ttys001")
        conflicting.jumpTarget?.workingDirectory = "/tmp/different-project"
        var desktop = session("desktop", tty: "ttys001")
        desktop.isCodexAppSession = true
        var ended = session("ended", tty: "ttys001")
        ended.isSessionEnded = true
        let result = CodexProcessSessionReconciler.reconcile(
            sessions: [conflicting, desktop, ended], processes: [process("101", tty: "ttys001")]
        )
        #expect(result.processes.first?.sessionID == "codex-process:101")
    }

    @Test
    func exitedProcessesDisappearAndTTYReuseGetsNewIdentity() {
        let initial = CodexProcessSessionReconciler.reconcile(
            sessions: [], processes: [process("101", tty: "ttys001")]
        )
        let exited = CodexProcessSessionReconciler.reconcile(sessions: initial.sessions, processes: [])
        #expect(exited.sessions.isEmpty)
        let restarted = CodexProcessSessionReconciler.reconcile(
            sessions: initial.sessions, processes: [process("102", tty: "ttys001")]
        )
        #expect(restarted.sessions.map(\.id) == ["codex-process:102"])
    }
}

@MainActor
@Suite(.serialized)
struct CodexProcessMonitoringTests {
    @Test
    func delayedHistoryRestorePreservesAlreadyDiscoveredTerminal() {
        let model = AppModel()
        let process = ActiveProcessSnapshot(
            tool: .codex, sessionID: nil, workingDirectory: "/tmp/project",
            terminalTTY: "/dev/ttys001", terminalApp: "Terminal", processID: "101"
        )
        model.monitoring.reconcileSessionAttachments(
            activeProcesses: [process],
            ghosttyAvailability: .available([], appIsRunning: false),
            terminalAvailability: .available([], appIsRunning: false),
            preResolvedJumpTargets: [:], observedCodexAppRunning: false
        )
        let cached = CodexTrackedSessionRecord(
            sessionID: "cached-thread", title: "Codex", summary: "Earlier conversation",
            phase: .completed, updatedAt: .now
        )
        model.discovery.applyStartupDiscoveryPayload(.init(
            codexRecords: [cached], codexRecordsNeedPrune: false,
            claudeRecords: [], claudeRecordsNeedPrune: false,
            openCodeRecords: [], openCodeRecordsNeedPrune: false,
            cursorRecords: [], cursorRecordsNeedPrune: false,
            piRecords: [], piRecordsNeedPrune: false,
            discoveredCodexRecords: [], discoveredClaudeSessions: [], hooksBinaryURL: nil
        ))

        #expect(Set(model.state.sessions.map(\.id)) == ["codex-process:101", "cached-thread"])
        #expect(model.state.sessions.first { $0.id == "codex-process:101" }?.isProcessAlive == true)
        #expect(model.islandListSessions.map(\.id) == ["codex-process:101"])
    }

    @Test
    func firstMonitorPollSurfacesCodexAndExitRemovesIt() {
        let model = AppModel()
        let process = ActiveProcessSnapshot(
            tool: .codex, sessionID: nil, workingDirectory: "/tmp/project",
            terminalTTY: "/dev/ttys001", terminalApp: "Terminal", processID: "101"
        )
        model.monitoring.reconcileSessionAttachments(
            activeProcesses: [process],
            ghosttyAvailability: .available([], appIsRunning: false),
            terminalAvailability: .available([], appIsRunning: false),
            preResolvedJumpTargets: [:], observedCodexAppRunning: false
        )
        #expect(model.state.sessions.map(\.id) == ["codex-process:101"])
        #expect(model.islandListSessions.map(\.id) == ["codex-process:101"])
        #expect(model.state.sessions.first?.isProcessAlive == true)

        model.monitoring.reconcileSessionAttachments(
            activeProcesses: [],
            ghosttyAvailability: .available([], appIsRunning: false),
            terminalAvailability: .available([], appIsRunning: false),
            preResolvedJumpTargets: [:], observedCodexAppRunning: false
        )
        #expect(model.state.sessions.isEmpty)
        #expect(model.islandListSessions.isEmpty)
    }
}
