import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

/// DSH plugin bridge: payload decoding, derived summaries, and the
/// fire-and-forget `processDshHook` path on a real BridgeServer.
struct DshHookTests {
    @Test
    func payloadDecodesSnakeCaseWireFormat() throws {
        let json = """
        {"hook_event_name":"sessionStart","session_id":"abc-123","cwd":"/Users/x/proj",
         "profile":"desktop","summary":"started","terminal_app":"iTerm"}
        """
        let payload = try JSONDecoder().decode(DshHookPayload.self, from: Data(json.utf8))
        #expect(payload.hookEventName == .sessionStart)
        #expect(payload.sessionID == "abc-123")
        #expect(payload.cwd == "/Users/x/proj")
        #expect(payload.profile == "desktop")
        #expect(payload.terminalApp == "iTerm")
    }

    @Test
    func derivedSessionIdentityAndSummaries() {
        let payload = DshHookPayload(
            hookEventName: .turnCompleted,
            sessionID: "s1",
            cwd: "/Users/x/Work/openisland",
            profile: "desktop",
            lastAssistantMessage: "All tests pass."
        )
        #expect(payload.workspaceName == "openisland")
        #expect(payload.sessionTitle == "DeepSeek Harness · openisland")
        #expect(payload.completionSummary == "All tests pass.")
        #expect(payload.defaultJumpTarget.terminalApp == "DeepSeek Harness")
        #expect(payload.defaultJumpTarget.paneTitle == "dsh desktop")

        let fallback = DshHookPayload(
            hookEventName: .turnCompleted,
            sessionID: "s1",
            cwd: "/tmp"
        )
        #expect(fallback.completionSummary == "DeepSeek Harness completed the turn.")

        let activity = DshHookPayload(
            hookEventName: .activity,
            sessionID: "s1",
            cwd: "/tmp",
            toolName: "read_file",
            toolInputPreview: "/tmp/notes.md"
        )
        #expect(activity.activitySummary == "Running read_file: /tmp/notes.md")
    }

    @Test
    func longAssistantMessageIsClipped() {
        let long = String(repeating: "x", count: 200)
        let payload = DshHookPayload(
            hookEventName: .turnCompleted,
            sessionID: "s1",
            cwd: "/tmp",
            lastAssistantMessage: long
        )
        #expect(payload.completionSummary.count <= 111)
        #expect(payload.completionSummary.hasSuffix("…"))
    }

    @Test
    func bridgeServerAcknowledgesAndDrivesLifecycle() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        func send(_ payload: DshHookPayload) async throws -> BridgeResponse? {
            try await sendOnGCDThread(.processDshHook(payload), socketURL: socketURL)
        }

        let start = try await send(DshHookPayload(
            hookEventName: .sessionStart,
            sessionID: "dsh-e2e-1",
            cwd: "/tmp/dsh-proj",
            profile: "desktop"
        ))
        #expect(start == .acknowledged)

        let activity = try await send(DshHookPayload(
            hookEventName: .activity,
            sessionID: "dsh-e2e-1",
            cwd: "/tmp/dsh-proj",
            toolName: "shell",
            toolInputPreview: "swift test"
        ))
        #expect(activity == .acknowledged)

        let done = try await send(DshHookPayload(
            hookEventName: .turnCompleted,
            sessionID: "dsh-e2e-1",
            cwd: "/tmp/dsh-proj",
            lastAssistantMessage: "Task finished."
        ))
        #expect(done == .acknowledged)

        let end = try await send(DshHookPayload(
            hookEventName: .sessionEnd,
            sessionID: "dsh-e2e-1",
            cwd: "/tmp/dsh-proj"
        ))
        #expect(end == .acknowledged)

        let session = try #require(waitForSession("dsh-e2e-1", on: server))
        #expect(session.tool == .dsh)
        #expect(session.isSessionEnded)
    }

    // MARK: - Helpers (mirror ClaudeHooksTests helpers)

    private func waitForSession(_ sessionID: String, on server: BridgeServer, timeout: TimeInterval = 3) -> AgentSession? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let session = server.sessionStateSnapshotForTests().sessions.first(where: { $0.id == sessionID }) {
                return session
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return server.sessionStateSnapshotForTests().sessions.first { $0.id == sessionID }
    }
}

private func sendOnGCDThread(
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
