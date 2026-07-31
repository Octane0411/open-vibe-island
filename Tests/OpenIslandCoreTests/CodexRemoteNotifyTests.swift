import Foundation
import Testing
@testable import OpenIslandCore

/// Pins the notify-only Codex hook path: when the remote Python hook client
/// runs with `OPEN_ISLAND_NOTIFY_ONLY=1`, PreToolUse events must post a
/// running-activity update instead of raising an approval request, so remote
/// agents are not blocked by a Mac-side approval round-trip.
struct CodexRemoteNotifyTests {
    @Test
    func notifyOnlyPreToolUsePostsActivityInsteadOfApproval() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let payload = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .preToolUse,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "codex-notify-1",
            transcriptPath: "/tmp/rollout.json",
            openIslandNotifyOnly: true
        )
        let response = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(payload))
        #expect(response == .acknowledged)

        var iterator = stream.makeAsyncIterator()
        let first = try await nextEvent(from: &iterator)
        // ensureSessionExists emits a sessionStarted event first.
        #expect(first.sessionStarted != nil)

        let second = try await nextEvent(from: &iterator)
        #expect(second.activityUpdated?.phase == .running)
        #expect(second.activityUpdated?.summary == "Running: Bash command")
    }

    @Test
    func codexHookPayloadDecodesNotifyOnlyFlag() throws {
        let json = """
        {
          "cwd": "/tmp/demo",
          "hook_event_name": "PreToolUse",
          "model": "gpt-5-codex",
          "permission_mode": "default",
          "session_id": "s-notify",
          "transcript_path": null,
          "open_island_notify_only": true
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(CodexHookPayload.self, from: json)
        #expect(payload.openIslandNotifyOnly == true)
    }
}

private enum CodexRemoteNotifyTestError: Error {
    case streamEnded
}

private func nextEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
) async throws -> AgentEvent {
    guard let event = try await iterator.next() else {
        throw CodexRemoteNotifyTestError.streamEnded
    }

    return event
}

private extension AgentEvent {
    var sessionStarted: SessionStarted? {
        if case let .sessionStarted(payload) = self {
            payload
        } else {
            nil
        }
    }

    var activityUpdated: SessionActivityUpdated? {
        if case let .activityUpdated(payload) = self {
            payload
        } else {
            nil
        }
    }

    var permissionRequested: PermissionRequested? {
        if case let .permissionRequested(payload) = self {
            payload
        } else {
            nil
        }
    }
}
