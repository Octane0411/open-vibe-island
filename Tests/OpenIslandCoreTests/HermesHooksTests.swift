import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

struct HermesHooksTests {
    @Test
    func hermesHookPayloadRoundTripsEachEventName() throws {
        let payloads: [HermesHookPayload] = [
            HermesHookPayload(
                hookEventName: .sessionStart,
                sessionID: "hermes-session-a",
                cwd: "/tmp/project",
                model: "claude-opus-4-7",
                platform: "cli"
            ),
            HermesHookPayload(
                hookEventName: .preToolCall,
                sessionID: "hermes-session-a",
                cwd: "/tmp/project",
                toolName: "read_file",
                toolArgs: .object([
                    "path": .string("/tmp/project/README.md"),
                    "limit": .number(200)
                ]),
                toolCallID: "call-1"
            ),
            HermesHookPayload(
                hookEventName: .postToolCall,
                sessionID: "hermes-session-a",
                cwd: "/tmp/project",
                toolName: "read_file",
                toolCallID: "call-1"
            ),
            HermesHookPayload(
                hookEventName: .sessionEnd,
                sessionID: "hermes-session-a",
                cwd: "/tmp/project",
                completed: true,
                interrupted: false
            ),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for payload in payloads {
            let data = try encoder.encode(payload)
            let decoded = try decoder.decode(HermesHookPayload.self, from: data)
            #expect(decoded == payload)
        }
    }

    @Test
    func hermesHookPayloadDecodesFromSnakeCaseJSON() throws {
        let json = """
        {
          "hook_event_name": "pre_tool_call",
          "session_id": "hermes-session-b",
          "cwd": "/Users/me/project",
          "pid": 4321,
          "platform": "cli",
          "tool_name": "run_shell",
          "tool_args": {"command": "ls -la"},
          "tool_call_id": "tc-7"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(HermesHookPayload.self, from: json)

        #expect(payload.hookEventName == .preToolCall)
        #expect(payload.sessionID == "hermes-session-b")
        #expect(payload.cwd == "/Users/me/project")
        #expect(payload.toolName == "run_shell")
        #expect(payload.toolCallID == "tc-7")
        #expect(payload.toolArgsPreview?.contains("command") == true)
    }

    @Test
    func defaultHermesMetadataCapturesToolState() {
        let payload = HermesHookPayload(
            hookEventName: .preToolCall,
            sessionID: "hermes-session-c",
            cwd: "/tmp/repo",
            model: "claude-opus-4-7",
            toolName: "run_shell",
            toolArgs: .object(["command": .string("npm install")])
        )

        let metadata = payload.defaultHermesMetadata
        #expect(metadata.currentTool == "run_shell")
        #expect(metadata.currentToolInputPreview?.contains("npm install") == true)
        #expect(metadata.model == "claude-opus-4-7")
        #expect(metadata.cwd == "/tmp/repo")
    }

    @Test
    func hermesSessionLifecycleProducesStartAndCompleteEvents() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let startPayload = HermesHookPayload(
            hookEventName: .sessionStart,
            sessionID: "hermes-session-lifecycle",
            cwd: "/tmp/project"
        )
        let endPayload = HermesHookPayload(
            hookEventName: .sessionEnd,
            sessionID: "hermes-session-lifecycle",
            cwd: "/tmp/project",
            completed: true
        )

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processHermesHook(startPayload))
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processHermesHook(endPayload))

        var iterator = stream.makeAsyncIterator()
        let startEvent = try await nextMatchingHermesEvent(from: &iterator, maxEvents: 8) { event in
            if case .sessionStarted = event { return true }
            return false
        }
        guard case let .sessionStarted(startedPayload) = startEvent else {
            Issue.record("Expected a Hermes sessionStarted event")
            return
        }
        #expect(startedPayload.sessionID == "hermes-session-lifecycle")
        #expect(startedPayload.tool == .hermes)
        #expect(startedPayload.initialPhase == .running)

        let completionEvent = try await nextMatchingHermesEvent(from: &iterator, maxEvents: 8) { event in
            if case .sessionCompleted = event { return true }
            return false
        }
        guard case let .sessionCompleted(completedPayload) = completionEvent else {
            Issue.record("Expected a Hermes sessionCompleted event")
            return
        }
        #expect(completedPayload.sessionID == "hermes-session-lifecycle")
        #expect(completedPayload.isSessionEnd == true)
    }

    @Test
    func hermesPreAndPostToolCallsUpdateMetadata() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let sessionID = "hermes-session-tool"
        let startPayload = HermesHookPayload(
            hookEventName: .sessionStart,
            sessionID: sessionID,
            cwd: "/tmp/project"
        )
        let prePayload = HermesHookPayload(
            hookEventName: .preToolCall,
            sessionID: sessionID,
            cwd: "/tmp/project",
            toolName: "run_shell",
            toolArgs: .object(["command": .string("ls -la")])
        )
        let postPayload = HermesHookPayload(
            hookEventName: .postToolCall,
            sessionID: sessionID,
            cwd: "/tmp/project",
            toolName: "run_shell"
        )

        let client = BridgeCommandClient(socketURL: socketURL)
        _ = try client.send(.processHermesHook(startPayload))
        _ = try client.send(.processHermesHook(prePayload))
        _ = try client.send(.processHermesHook(postPayload))

        var iterator = stream.makeAsyncIterator()

        let preMetadataEvent = try await nextMatchingHermesEvent(from: &iterator, maxEvents: 12) { event in
            if case let .hermesSessionMetadataUpdated(payload) = event,
               payload.hermesMetadata.currentTool == "run_shell" {
                return true
            }
            return false
        }
        guard case let .hermesSessionMetadataUpdated(preMetadata) = preMetadataEvent else {
            Issue.record("Expected a Hermes metadata update from pre_tool_call")
            return
        }
        #expect(preMetadata.hermesMetadata.currentToolInputPreview?.contains("ls -la") == true)

        let postMetadataEvent = try await nextMatchingHermesEvent(from: &iterator, maxEvents: 12) { event in
            if case let .hermesSessionMetadataUpdated(payload) = event,
               payload.hermesMetadata.currentTool == nil {
                return true
            }
            return false
        }
        guard case let .hermesSessionMetadataUpdated(postMetadata) = postMetadataEvent else {
            Issue.record("Expected a Hermes metadata update from post_tool_call")
            return
        }
        #expect(postMetadata.hermesMetadata.currentTool == nil)
        #expect(postMetadata.hermesMetadata.currentToolInputPreview == nil)
    }
}

private func nextMatchingHermesEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator,
    maxEvents: Int = 8,
    predicate: (AgentEvent) -> Bool
) async throws -> AgentEvent {
    for _ in 0..<maxEvents {
        guard let event = try await iterator.next() else {
            break
        }
        if predicate(event) {
            return event
        }
    }

    Issue.record("Expected matching event within \(maxEvents) events")
    throw CancellationError()
}
