import Foundation
import Testing
@testable import OpenIslandCore

struct DSHRootSessionTests {
    @Test
    func legacyRowsAreQuarantinedAndChildTombstonesNeverBecomeCompletions() async throws {
        let old = Date(timeIntervalSince1970: 1000)
        let restored = SessionState(sessions: ["root", "child"].map {
            AgentSession(id: $0, title: "DSH", tool: .dsh, origin: .live, phase: .running, summary: "Working", updatedAt: old)
        })
        #expect(restored.liveSessionCount == 0)
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        server.updateStateSnapshot(restored)
        try server.start()
        defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: socket)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        let timeout = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { observer.disconnect() }
        }
        defer { timeout.cancel() }
        try await observer.send(.processDSHHook(DSHHookPayload(hookEventName: .sessionEnd, sessionID: "child", cwd: "/tmp", isSubagent: true, parentSessionID: "root")))
        var iterator = stream.makeAsyncIterator()
        var state = restored
        var removed = false
        while let event = try await iterator.next() {
            state.apply(event)
            if case let .piSessionMetadataUpdated(payload) = event, payload.sessionID == "child" {
                removed = true
                break
            }
        }
        try #require(removed)
        #expect(state.session(id: "child") == nil)
        server.updateStateSnapshot(restored)
        // Stale root-looking replays and old unclassified hook producers must not
        // resurrect the child after its explicit exclusion.
        for name in [RuntimeHookEventName.sessionStart, .preToolUse, .postToolUse, .stop, .heartbeat] {
            try await observer.send(.processDSHHook(DSHHookPayload(hookEventName: name, sessionID: "child", cwd: "/tmp", toolName: "synthetic", isSubagent: false)))
        }
        try await observer.send(.processDSHHook(DSHHookPayload(hookEventName: .sessionStart, sessionID: "unknown", cwd: "/tmp", isSubagent: nil)))
        try await observer.send(.processDSHHook(DSHHookPayload(hookEventName: .heartbeat, sessionID: "root", cwd: "/tmp", isSubagent: false, parentSessionID: "fork-lineage")))
        try await observer.send(.processDSHHook(DSHHookPayload(hookEventName: .stop, sessionID: "root", cwd: "/tmp", isSubagent: false)))
        var completed = false
        while let event = try await iterator.next() {
            state.apply(event)
            switch event {
            case let .sessionStarted(payload): #expect(payload.sessionID != "child" && payload.sessionID != "unknown")
            case let .sessionCompleted(payload):
                #expect(payload.sessionID == "root")
                completed = payload.sessionID == "root"
            case .questionAsked, .permissionRequested: Issue.record("A child produced an actionable event")
            default: break
            }
            if completed { break }
        }
        try #require(completed)
        #expect(state.session(id: "child") == nil)
        #expect(state.session(id: "unknown") == nil)
        #expect(state.session(id: "root")?.piMetadata?.isSubagent == false)
        #expect(state.session(id: "root")?.piMetadata?.parentSessionID == "fork-lineage")
        #expect(state.session(id: "root")?.isVisibleInIsland == true)
        let childRecovery = SessionStarted(sessionID: "never-created-child", title: "DSH", tool: .dsh, summary: "Hidden", timestamp: .now, piMetadata: PiSessionMetadata(isSubagent: true))
        state.apply(.sessionHeartbeat(SessionHeartbeat(sessionID: childRecovery.sessionID, timestamp: .now, recoverySession: childRecovery)))
        #expect(state.session(id: childRecovery.sessionID) == nil)
    }
}
