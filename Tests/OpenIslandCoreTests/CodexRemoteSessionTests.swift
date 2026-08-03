import Foundation
import Testing
@testable import OpenIslandCore

/// Pins Codex SSH-remote support. The Python hook client
/// (`scripts/open-island-hooks.py`) marks every bridge payload with
/// `remote: true`; the Codex decode + bridge path must surface that as
/// `isRemote` on the session so the UI shows the SSH badge and
/// process-liveness checks skip sessions whose process lives on a
/// remote machine.
struct CodexRemoteSessionTests {
    @Test
    func codexSessionStartWithRemoteFlagCreatesRemoteSession() async throws {
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
            hookEventName: .sessionStart,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "codex-remote-1",
            transcriptPath: nil,
            remote: true
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(payload))

        var iterator = stream.makeAsyncIterator()
        let startedEvent = try await nextEvent(from: &iterator)

        #expect(startedEvent.sessionStarted?.isRemote == true)
    }

    @Test
    func codexSessionStartWithoutRemoteFlagCreatesLocalSession() async throws {
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
            hookEventName: .sessionStart,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "codex-local-1",
            transcriptPath: nil
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(payload))

        var iterator = stream.makeAsyncIterator()
        let startedEvent = try await nextEvent(from: &iterator)

        #expect(startedEvent.sessionStarted?.isRemote == false)
    }

    @Test
    func codexHookPayloadDecodesRemoteFlag() throws {
        let withRemote = """
        {
          "cwd": "/tmp/demo",
          "hook_event_name": "SessionStart",
          "model": "gpt-5-codex",
          "permission_mode": "default",
          "session_id": "s-remote",
          "transcript_path": null,
          "remote": true
        }
        """.data(using: .utf8)!

        let remotePayload = try JSONDecoder().decode(CodexHookPayload.self, from: withRemote)
        #expect(remotePayload.remote == true)

        let withoutRemote = """
        {
          "cwd": "/tmp/demo",
          "hook_event_name": "SessionStart",
          "model": "gpt-5-codex",
          "permission_mode": "default",
          "session_id": "s-local",
          "transcript_path": null
        }
        """.data(using: .utf8)!

        let localPayload = try JSONDecoder().decode(CodexHookPayload.self, from: withoutRemote)
        #expect(localPayload.remote == nil)
    }
}

private enum CodexRemoteSessionTestError: Error {
    case streamEnded
}

private func nextEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
) async throws -> AgentEvent {
    guard let event = try await iterator.next() else {
        throw CodexRemoteSessionTestError.streamEnded
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
}
