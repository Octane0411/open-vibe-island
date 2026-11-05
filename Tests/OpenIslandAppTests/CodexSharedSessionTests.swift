import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
@Suite(.serialized)
struct CodexSharedSessionTests {
    private func thread(_ id: String, status: String = "active", updatedAt: Int = 1, source: Any = "cli", flags: [String] = []) throws -> CodexThread {
        let object: [String: Any] = [
            "id": id, "cwd": "/tmp/project", "preview": "Actual user task",
            "modelProvider": "openai", "createdAt": 1, "updatedAt": updatedAt,
            "ephemeral": false, "source": source,
            "status": ["type": status, "activeFlags": flags],
        ]
        return try JSONDecoder().decode(CodexThread.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test
    func processPresenceAloneDoesNotInventConversationRows() {
        let model = AppModel()
        model.monitoring.reconcileSessionAttachments(
            activeProcesses: [.init(tool: .codex, sessionID: nil, workingDirectory: "/tmp/project", terminalTTY: "/dev/ttys001")],
            ghosttyAvailability: .available([], appIsRunning: false),
            terminalAvailability: .available([], appIsRunning: false),
            preResolvedJumpTargets: [:], observedCodexAppRunning: false
        )
        #expect(model.islandListSessions.isEmpty)
    }

    @Test
    func onlyRecentRootConversationsAreShownWithRealIdentities() throws {
        let model = AppModel()
        let now = Date(timeIntervalSince1970: 10_000)
        model.state = SessionState(sessions: [
            AgentSession(id: "child", title: "Old background row", tool: .codex,
                         phase: .waitingForAnswer, summary: "Waiting", updatedAt: now),
        ])
        model.applySharedCodexThreads([
            try thread("working"),
            try thread("finished", status: "idle", updatedAt: 9_900),
            try thread("old-idle", status: "idle"),
            try thread("child", source: ["subAgent": ["thread_spawn": ["parent_thread_id": "working"]]]),
        ], now: now)
        #expect(Set(model.state.sessions.map(\.id)) == ["working", "finished"])
        #expect(model.state.sessions.first { $0.id == "working" }?.phase == .running)
        #expect(model.state.sessions.first { $0.id == "finished" }?.phase == .completed)
        #expect(model.monitoring.sharedCodexSessionIDs == ["working", "finished"])
        #expect(model.state.sessions.allSatisfy { $0.jumpTarget == nil })
    }

    @Test
    func liveStateTransitionsAndCompletionExpiryDoNotFabricateApprovalControls() throws {
        let model = AppModel()
        let now = Date(timeIntervalSince1970: 10_000)
        model.applySharedCodexThreads([try thread("actual")], now: now)
        model.applySharedCodexThreads([try thread("actual", flags: ["waitingOnApproval"])], now: now)
        #expect(model.state.sessions.first?.phase == .waitingForApproval)
        #expect(model.state.sessions.first?.permissionRequest == nil)
        model.applySharedCodexThreads([try thread("actual", flags: ["waitingOnUserInput"])], now: now)
        #expect(model.state.sessions.first?.phase == .waitingForAnswer)
        model.applySharedCodexThreads([try thread("actual", status: "idle")], now: now.addingTimeInterval(1))
        #expect(model.state.sessions.first?.phase == .completed)
        model.applySharedCodexThreads([try thread("actual", status: "idle")], now: now.addingTimeInterval(301))
        #expect(model.state.sessions.isEmpty)
    }
    @Test
    func childrenKeepTheirOwnStatesAndNeverInflateRootCount() throws {
        let model = AppModel()
        let now = Date(timeIntervalSince1970: 10_000)
        func child(_ id: String, parent: String, status: String = "active", flags: [String] = []) throws -> CodexThread {
            try thread(id, status: status, updatedAt: 9_999, source: ["subAgent": ["thread_spawn": [
                "parent_thread_id": parent, "agent_nickname": id, "agent_role": "reviewer", "depth": 1,
            ]]], flags: flags)
        }
        model.applySharedCodexThreads([
            try thread("root", status: "idle", updatedAt: 9_999),
            try child("running", parent: "root"),
            try child("approval", parent: "running", flags: ["waitingOnApproval"]),
            try child("done", parent: "root", status: "idle"),
            try child("orphan", parent: "missing"),
            try child("cycleA", parent: "cycleB"), try child("cycleB", parent: "cycleA"),
        ], now: now)
        let root = try #require(model.state.sessions.first)
        #expect(model.state.sessions.count == 1)
        #expect(root.phase == .completed)
        #expect(root.islandSubagents.count == 3)
        #expect(root.islandSubagents.first { $0.id == "approval" }?.depth == 2)
        #expect(root.islandSubagents.first { $0.id == "approval" }?.phase == .waitingForApproval)
        #expect(root.islandSubagents.first { $0.id == "done" }?.phase == .completed)
        #expect(SessionSubagent.visible(root.islandSubagents, showDetails: false).map(\.id) == ["approval"])
        model.applySharedCodexThreads([try thread("root")], now: now)
        #expect(model.state.sessions.first?.islandSubagents.isEmpty == true)
    }

    @Test
    func runningChildKeepsCompletedParentVisibleWithoutReopeningIt() throws {
        let model = AppModel()
        let now = Date(timeIntervalSince1970: 10_000)
        model.applySharedCodexThreads([
            try thread("root", status: "idle"),
            try thread("child", source: ["subAgent": ["thread_spawn": ["parent_thread_id": "root"]]]),
        ], now: now)
        #expect(model.state.sessions.count == 1)
        let root = try #require(model.state.sessions.first)
        #expect(root.phase == .completed)
        #expect(!root.isStaleCompletedForIsland(at: now.addingTimeInterval(1_000)))
        #expect(model.islandClosedMode == .running)
        #expect(model.notchStatus == .closed)
    }

    @Test
    func jumpFallbackNeedsOneKnownHostAndNeverGuessesAPane() throws {
        let model = AppModel()
        model.applySharedCodexThreads([try thread("root")])
        let terminal = ActiveProcessSnapshot(tool: .codex, sessionID: nil, workingDirectory: "/tmp/project",
                                             terminalTTY: "/dev/ttys001", terminalApp: "Terminal")
        let fallback = model.monitoring.sharedCodexAppFallbacks(for: model.state.sessions, processes: [terminal])
        #expect(fallback["root"]?.terminalApp == "Terminal")
        #expect(fallback["root"]?.terminalTTY == nil)
        #expect(fallback["root"]?.workingDirectory == nil)
        var conflicting = terminal
        conflicting.terminalApp = "Ghostty"
        #expect(model.monitoring.sharedCodexAppFallbacks(for: model.state.sessions, processes: [terminal, conflicting]).isEmpty)
        conflicting.terminalApp = nil
        #expect(model.monitoring.sharedCodexAppFallbacks(for: model.state.sessions, processes: [terminal, conflicting]).isEmpty)
        model.state.reconcileJumpTargets(fallback)
        #expect(model.monitoring.sharedCodexAppFallbacks(for: model.state.sessions, processes: [terminal]).isEmpty)
        #expect(model.state.sessions.count == 1)
    }

}
