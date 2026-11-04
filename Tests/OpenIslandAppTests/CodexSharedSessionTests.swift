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
}
