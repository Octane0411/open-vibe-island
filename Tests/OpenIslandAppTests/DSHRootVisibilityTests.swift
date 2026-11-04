import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct DSHRootVisibilityTests {
    @Test
    func cachedUnknownAndChildSessionsCannotBecomeRowsCardsOrSelection() async throws {
        let now = Date.now
        var root = AgentSession(id: "root", title: "DSH", tool: .dsh, origin: .live, attachmentState: .attached, phase: .running, summary: "Working", updatedAt: now, piMetadata: PiSessionMetadata(isSubagent: false, parentSessionID: "fork-parent"))
        root.isHookManaged = true
        root.isProcessAlive = true
        root.lastHeartbeatAt = now
        let child = AgentSession(id: "child", title: "DSH", tool: .dsh, origin: .live, phase: .waitingForAnswer, summary: "Hidden question", updatedAt: now, questionPrompt: QuestionPrompt(title: "Hidden", options: ["A"]), piMetadata: PiSessionMetadata(isSubagent: true, parentSessionID: "root"))
        let unknown = AgentSession(id: "old-unknown", title: "DSH", tool: .dsh, origin: .live, phase: .completed, summary: "Old registry entry", updatedAt: now)
        let model = AppModel()
        model.state = SessionState(sessions: [root, child, unknown])
        model.selectedSessionID = child.id
        model.islandSurface = .sessionList(actionableSessionID: child.id)
        #expect(model.allSessions.map(\.id) == [root.id])
        #expect(model.surfacedSessions.map(\.id) == [root.id])
        #expect(model.recentSessions.isEmpty)
        #expect(model.activeIslandCardSession == nil)
        #expect(model.focusedSession?.id == root.id)
        #expect(model.liveSessionCount == 1)
        #expect(model.liveAttentionCount == 0)
        #expect(model.state.liveAttentionCount == 0)
        let quiet = AppModel(isNotificationSessionAlreadyFrontmost: { _ in false })
        quiet.state = SessionState(sessions: [unknown])
        quiet.applyTrackedEvent(.questionAsked(QuestionAsked(sessionID: unknown.id, prompt: QuestionPrompt(title: "Unconfirmed", options: ["A"]), timestamp: now)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(quiet.notchStatus == .closed)
        #expect(quiet.activeIslandCardSession == nil)
        #expect(quiet.allSessions.isEmpty)
        model.applyTrackedEvent(.piSessionMetadataUpdated(PiSessionMetadataUpdated(sessionID: child.id, piMetadata: PiSessionMetadata(isSubagent: true), timestamp: now)))
        #expect(model.state.session(id: child.id) == nil)
        #expect(model.selectedSessionID == root.id)
        var staleRoot = child
        staleRoot.piMetadata = PiSessionMetadata(isSubagent: false)
        model.acceptCoordinatorState(SessionState(sessions: [root, staleRoot, unknown]))
        #expect(model.state.session(id: child.id) == nil)
        model.state.apply(.sessionStarted(SessionStarted(sessionID: child.id, title: "DSH", tool: .dsh, summary: "Stale", timestamp: now, piMetadata: PiSessionMetadata(isSubagent: false))))
        #expect(model.state.session(id: child.id) == nil)
        let recovered = SessionStarted(sessionID: unknown.id, title: "DSH", tool: .dsh, summary: "Recovered", timestamp: now, piMetadata: PiSessionMetadata(isSubagent: false, parentSessionID: root.id))
        model.state.apply(.sessionHeartbeat(SessionHeartbeat(sessionID: unknown.id, timestamp: now, recoverySession: recovered)))
        #expect(Set(model.allSessions.map(\.id)) == [root.id, unknown.id])
        #expect(model.state.session(id: unknown.id)?.piMetadata?.isSubagent == false)
    }
}
