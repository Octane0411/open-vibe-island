import Foundation
import OpenIslandCore
import Testing

struct PiHooksTests {
    @Test
    func piHookPayloadDecodesFromExtensionShape() throws {
        let json = #"""
        {
          "hook_event_name": "PreToolUse",
          "session_id": "pi-session-1",
          "cwd": "/tmp/worktree",
          "transcript_path": "/Users/me/.pi/agent/sessions/session.jsonl",
          "model": "anthropic/claude-sonnet-4-5",
          "tool_name": "bash",
          "tool_use_id": "tool-1",
          "tool_input": "{\"command\":\"swift test\"}",
          "terminal_app": "Ghostty",
          "terminal_tty": "/dev/ttys001"
        }
        """#.data(using: .utf8)!

        let payload = try JSONDecoder().decode(PiHookPayload.self, from: json)

        #expect(payload.hookEventName == .preToolUse)
        #expect(payload.sessionID == "pi-session-1")
        #expect(payload.sessionTitle == "Pi · worktree")
        #expect(payload.toolActivitySummary.contains("Running bash"))
        #expect(payload.defaultJumpTarget.terminalApp == "Ghostty")
    }

    @Test
    func piPreToolUseWaitsForApprovalAndReturnsDenyDirective() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let payload = PiHookPayload(
            hookEventName: .preToolUse,
            sessionID: "pi-approval-1",
            cwd: "/tmp/worktree",
            toolName: "bash",
            toolInput: "{\"command\":\"rm -rf build\"}",
            toolUseID: "tool-1"
        )

        async let responseTask = sendPiOnGCDThread(.processPiHook(payload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let startedEvent = try await nextPiEvent(from: &iterator)
        let permissionEvent = try await nextPiEvent(from: &iterator)

        #expect(startedEvent.isPiSessionStarted)
        #expect(permissionEvent.piPermissionRequest?.request.toolName == "bash")
        #expect(permissionEvent.piPermissionRequest?.request.summary.contains("rm -rf build") == true)

        try await observer.send(
            .resolvePermission(
                sessionID: "pi-approval-1",
                resolution: .deny(message: "Use the project cleanup script instead.")
            )
        )

        let completedEvent = try await nextPiEvent(from: &iterator)
        let response = try await responseTask

        #expect(completedEvent.piCompletion?.summary == "Use the project cleanup script instead.")
        #expect(response == .piHookDirective(.deny(reason: "Use the project cleanup script instead.")))
    }
}

private enum PiHookTestError: Error {
    case streamEnded
}

private func nextPiEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
) async throws -> AgentEvent {
    guard let event = try await iterator.next() else {
        throw PiHookTestError.streamEnded
    }

    return event
}

private extension AgentEvent {
    var isPiSessionStarted: Bool {
        if case let .sessionStarted(payload) = self {
            payload.tool == .pi
        } else {
            false
        }
    }

    var piPermissionRequest: PermissionRequested? {
        if case let .permissionRequested(payload) = self {
            payload
        } else {
            nil
        }
    }

    var piCompletion: SessionCompleted? {
        if case let .sessionCompleted(payload) = self {
            payload
        } else {
            nil
        }
    }
}

private func sendPiOnGCDThread(
    _ command: BridgeCommand,
    socketURL: URL
) async throws -> BridgeResponse? {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            do {
                let response = try BridgeCommandClient(socketURL: socketURL).send(command)
                continuation.resume(returning: response)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
