import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
@Suite(.serialized)
struct IslandKeyboardNavigationTests {
    @Test
    func navigationWrapsAcrossRootConversationsAndSkipsChildren() throws {
        let model = AppModel()
        model.state = SessionState(sessions: [
            AgentSession(id: "one", title: "One", tool: .codex, origin: .demo, phase: .running, summary: "Working", updatedAt: .now),
            AgentSession(id: "two", title: "Two", tool: .claudeCode, origin: .demo, phase: .running, summary: "Working", updatedAt: .now),
            AgentSession(id: "child", title: "Child", tool: .codex, origin: .demo, phase: .running, summary: "Working", updatedAt: .now,
                         codexMetadata: CodexSessionMetadata(parentThreadID: "one")),
        ])
        let ids = model.islandListSessions.map(\.id)
        #expect(ids.count == 2)
        model.selectedSessionID = try #require(ids.first)
        model.moveIslandSelection(by: -1)
        #expect(model.selectedSessionID == ids.last)
        model.moveIslandSelection(by: 1)
        #expect(model.selectedSessionID == ids.first)
        model.moveIslandSelection(by: 1)
        #expect(model.selectedSessionID == ids.last)
    }

    @Test
    func emptyListNavigationIsSafe() {
        let model = AppModel()
        model.moveIslandSelection(by: -1)
        #expect(model.selectedSessionID == nil)
    }
}
