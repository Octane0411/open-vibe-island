import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
@Suite(.serialized)
struct NotificationPreferencesTests {
    @Test
    func disablingCompletionRevealKeepsRealCompletionInTheList() {
        let keys = ["app.autoExpandOnCompletion", "app.suppressFrontmostNotifications"]
        let old = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, old) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let model = AppModel()
        model.autoExpandOnCompletion = false
        model.suppressFrontmostNotifications = false
        model.state = SessionState(sessions: [AgentSession(
            id: "root", title: "Codex", tool: .codex, origin: .live,
            attachmentState: .attached, phase: .running, summary: "Working", updatedAt: .now
        )])
        model.applyTrackedEvent(.sessionCompleted(SessionCompleted(
            sessionID: "root", summary: "Finished the task", timestamp: .now
        )))
        #expect(model.state.session(id: "root")?.phase == .completed)
        #expect(model.notchStatus == .closed)
        #expect(model.islandListSessions.map(\.id) == ["root"])
    }

    @Test
    func childCompletionDoesNotStealFocusOrChangeParentPhase() {
        let model = AppModel()
        model.state = SessionState(sessions: [
            AgentSession(id: "root", title: "Root", tool: .codex, phase: .running, summary: "Working", updatedAt: .now),
            AgentSession(id: "child", title: "Child", tool: .codex, phase: .running, summary: "Working", updatedAt: .now,
                         codexMetadata: CodexSessionMetadata(parentThreadID: "root")),
        ])
        model.applyTrackedEvent(.sessionCompleted(SessionCompleted(sessionID: "child", summary: "Done", timestamp: .now)))
        #expect(model.state.session(id: "root")?.phase == .running)
        #expect(model.notchStatus == .closed)
        #expect(!model.islandListSessions.contains { $0.id == "child" })
    }
}
