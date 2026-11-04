import Foundation
import Testing
@testable import OpenIslandCore

struct CodexLiveSessionPolicyTests {
    private func thread(status: String = "active", source: Any = "cli", updatedAt: Int = 1, ephemeral: Bool = false, flags: [String] = []) throws -> CodexThread {
        let object: [String: Any] = [
            "id": "real-thread", "cwd": "/tmp/project", "preview": "User task",
            "modelProvider": "openai", "createdAt": 1, "updatedAt": updatedAt,
            "ephemeral": ephemeral, "source": source,
            "status": ["type": status, "activeFlags": flags],
        ]
        return try JSONDecoder().decode(CodexThread.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test
    func admitsActiveRootsAndRecentCompletionsOnly() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(CodexLiveSessionPolicy.shouldShow(try thread(), now: now))
        #expect(CodexLiveSessionPolicy.shouldShow(try thread(status: "idle", updatedAt: 9_900), now: now))
        #expect(!CodexLiveSessionPolicy.shouldShow(try thread(status: "idle"), now: now))
        #expect(!CodexLiveSessionPolicy.shouldShow(try thread(status: "notLoaded", updatedAt: 9_999), now: now))
        #expect(!CodexLiveSessionPolicy.shouldShow(try thread(ephemeral: true), now: now))
    }

    @Test
    func structuredSubagentSourceDoesNotBreakThreadDecodingOrLeakBackgroundRows() throws {
        let child = try thread(source: ["subAgent": ["thread_spawn": ["parent_thread_id": "root"]]])
        #expect(child.source == .subagent)
        #expect(!CodexLiveSessionPolicy.shouldShow(child))
    }

    @Test
    func longRunningLegacyThreadKeepsItsRealCompletionWindow() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let finished = try thread(status: "idle")
        #expect(CodexLiveSessionPolicy.shouldShow(finished, now: now, lastActiveAt: now.addingTimeInterval(-10)))
        #expect(!CodexLiveSessionPolicy.shouldShow(finished, now: now, lastActiveAt: now.addingTimeInterval(-301)))
    }

    @Test
    func mapsActualApprovalAndInputFlags() throws {
        #expect(CodexLiveSessionPolicy.phase(for: try thread().status) == .running)
        #expect(CodexLiveSessionPolicy.phase(for: try thread(flags: ["waitingOnApproval"]).status) == .waitingForApproval)
        #expect(CodexLiveSessionPolicy.phase(for: try thread(flags: ["waitingOnUserInput"]).status) == .waitingForAnswer)
        #expect(CodexLiveSessionPolicy.phase(for: try thread(status: "idle").status) == .completed)
        #expect(CodexLiveSessionPolicy.phase(for: try thread(status: "systemError").status) == .completed)
    }

    @Test
    func indexedActivityRefreshPreservesRuntimeStatusAndCompletionRecency() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let finished = try thread(status: "idle").updatingActivityTimestamp(9_999)
        #expect(CodexLiveSessionPolicy.shouldShow(finished, now: now))
        let waiting = try thread(flags: ["waitingOnApproval"]).updatingActivityTimestamp(9_999)
        #expect(CodexLiveSessionPolicy.phase(for: waiting.status) == .waitingForApproval)
        #expect(waiting.updatingActivityTimestamp(1).updatedAt == 9_999)
    }
}
