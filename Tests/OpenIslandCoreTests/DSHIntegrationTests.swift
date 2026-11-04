import Foundation
import Testing
@testable import OpenIslandCore

struct DSHIntegrationTests {
    @Test
    func dshWireLifecycleAndLateEvents() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { observer.disconnect() }
        }
        defer { deadline.cancel() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()

        // Decode the actual dependency-free plugin envelope, without a Pi agent field.
        let wire = Data("""
        {"type":"command","command":{"type":"processDshHook","dshHook":{"hook_event_name":"SessionStart","session_id":"dsh-one","cwd":"/tmp/project","model":"deepseek"}}}
        """.utf8)
        let envelope = try JSONDecoder().decode(BridgeEnvelope.self, from: wire)
        guard case let .command(command) = envelope else { Issue.record("Expected command")
            return
        }
        #expect(try BridgeCommandClient(socketURL: socketURL).send(command) == .acknowledged)
        let start = try #require(try await iterator.next())
        guard case let .sessionStarted(payload) = start else { Issue.record("Expected session start")
            return
        }
        #expect(payload.tool == .dsh)
        #expect(payload.jumpTarget?.terminalApp == "DSH Web")
        #expect(payload.jumpTarget?.terminalTTY == nil)
        #expect(payload.jumpTarget?.workingDirectory == "/tmp/project")
        #expect(payload.piMetadata?.model == "deepseek")

        let stop = DSHHookPayload(hookEventName: .stop, sessionID: "dsh-one", cwd: "/tmp/project", lastAssistantMessage: "Implemented integration")
        #expect(try BridgeCommandClient(socketURL: socketURL).send(.processDSHHook(stop)) == .acknowledged)
        let metadata = try #require(try await iterator.next())
        guard case let .piSessionMetadataUpdated(update) = metadata else { Issue.record("Expected metadata")
            return
        }
        #expect(update.piMetadata.lastAssistantMessage == "Implemented integration")
        let completed = try #require(try await iterator.next())
        guard case .sessionCompleted = completed else { Issue.record("Expected completion")
            return
        }

        let end = DSHHookPayload(hookEventName: .sessionEnd, sessionID: "dsh-one", cwd: "/tmp/project")
        #expect(try BridgeCommandClient(socketURL: socketURL).send(.processDSHHook(end)) == .acknowledged)
        let ended = try #require(try await iterator.next())
        guard case let .sessionCompleted(ending) = ended else { Issue.record("Expected session end")
            return
        }
        #expect(ending.isSessionEnd == true)
        for name in [PiHookEventName.heartbeat, .preToolUse, .stop] {
            let late = DSHHookPayload(hookEventName: name, sessionID: "dsh-one", cwd: "/tmp/project", toolName: "bash")
            #expect(try BridgeCommandClient(socketURL: socketURL).send(.processDSHHook(late)) == .acknowledged)
        }
        let next = DSHHookPayload(hookEventName: .sessionStart, sessionID: "dsh-two", cwd: "/tmp/project")
        #expect(try BridgeCommandClient(socketURL: socketURL).send(.processDSHHook(next)) == .acknowledged)
        let nextEvent = try #require(try await iterator.next())
        guard case let .sessionStarted(second) = nextEvent else { Issue.record("Late event resurrected ended session")
            return
        }
        #expect(second.sessionID == "dsh-two")
    }

    @Test
    func heartbeatIsolationExpiryAndRegistryRestore() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        var state = SessionState()
        for id in ["one", "two"] {
            state.apply(.sessionStarted(SessionStarted(
                sessionID: id, title: "DSH", tool: .dsh, origin: .live,
                initialPhase: .running, summary: "Working", timestamp: now,
                piMetadata: PiSessionMetadata(lastUserPrompt: id, currentTool: "bash")
            )))
        }
        state.apply(.sessionHeartbeat(SessionHeartbeat(sessionID: "two", timestamp: now.addingTimeInterval(30))))
        _ = state.markProcessLiveness(aliveSessionIDs: [])
        _ = state.markProcessLiveness(aliveSessionIDs: [])
        #expect(state.session(id: "one")?.isSessionEnded == false)
        #expect(state.expireStalePiHeartbeats(before: now.addingTimeInterval(1)) == ["one"])
        #expect(state.session(id: "two")?.isSessionEnded == false)
        #expect(state.session(id: "two")?.phase == .running)
        #expect(state.session(id: "two")?.piMetadata?.currentTool == "bash")
        #expect(state.session(id: "two")?.updatedAt == now)
        state.apply(.sessionHeartbeat(SessionHeartbeat(sessionID: "one", timestamp: now.addingTimeInterval(40))))
        #expect(state.session(id: "one")?.isSessionEnded == true)

        let session = try #require(state.session(id: "two"))
        let record = try JSONDecoder().decode(PiTrackedSessionRecord.self, from: JSONEncoder().encode(PiTrackedSessionRecord(session: session)))
        let restored = record.restorableSession(at: now.addingTimeInterval(50))
        #expect(restored.tool == .dsh)
        #expect(restored.piMetadata == session.piMetadata)
        #expect(restored.isProcessAlive == false)
        #expect(restored.heartbeatReconnectStartedAt == now.addingTimeInterval(50))
    }
}
