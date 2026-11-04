import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct DSHJumpCancellationTests {
    @Test
    func aNewerConversationClickCancelsTheDismissDelayedJump() async throws {
        let calls = JumpCallRecorder()
        let model = AppModel(terminalJumpAction: { target in
            calls.record(target.dshWeb?.sessionID ?? "missing")
            return target.dshWeb?.sessionID ?? "missing"
        })
        model.notchStatus = .opened
        model.notchOpenReason = .click
        model.islandSurface = .sessionList()
        let session = { (id: String) in
            AgentSession(id: id, title: "DSH", tool: .dsh, origin: .live, phase: .running, summary: "Working", updatedAt: .now,
                jumpTarget: JumpTarget(terminalApp: "DSH Web", workspaceName: "project", paneTitle: "DSH",
                    dshWeb: DSHWebJumpTarget(sessionID: id, origin: "http://127.0.0.1:3080/", focusSocketPath: "/tmp/oi-dsh-focus-test/focus.sock")))
        }
        model.jumpToSession(session("older"))
        model.jumpToSession(session("newer"))
        for _ in 0..<30 {
            if model.lastActionMessage == "newer" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.lastActionMessage == "newer")
        #expect(calls.snapshot() == ["newer"])
    }
}

private final class JumpCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func record(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
    }
    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
