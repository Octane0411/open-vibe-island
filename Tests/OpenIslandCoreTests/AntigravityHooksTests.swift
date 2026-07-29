import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

struct AntigravityHooksTests {
    @Test
    func antigravityHookPayloadDecodesNotification() throws {
        let json = """
        {
          "cwd": "/tmp/worktree",
          "hook_event_name": "Notification",
          "session_id": "antigravity-session-1",
          "message": "Antigravity CLI requires permission to continue.",
          "notification_type": "ToolPermission",
          "details": {
            "tool_name": "run_shell_command",
            "file_path": "/tmp/worktree/package.json"
          }
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(AntigravityHookPayload.self, from: json)

        #expect(payload.hookEventName == .notification)
        #expect(payload.notificationSummary == "Antigravity CLI requires permission to continue.")
        #expect(payload.renderedDetails == "{file_path: /tmp/worktree/package.json, tool_name: run_shell_command}")
    }

    @Test
    func antigravityHookInstallerInstallsIntoEmptySettingsFile() throws {
        let mutation = try AntigravityHookInstaller.installSettingsJSON(
            existingData: nil,
            hookCommand: "/usr/local/bin/OpenIslandHooks --source antigravity"
        )

        #expect(mutation.changed)
        #expect(mutation.managedHooksPresent)

        let data = try #require(mutation.contents)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = object["hooks"] as! [String: Any]

        #expect(hooks.keys.contains("SessionStart"))
        #expect(hooks.keys.contains("SessionEnd"))
        #expect(hooks.keys.contains("BeforeAgent"))
        #expect(hooks.keys.contains("AfterAgent"))
        #expect(hooks.keys.contains("Notification"))
    }

    @Test
    func antigravityNotificationBecomesActivityUpdate() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }

        let hookClient = BridgeCommandClient(socketURL: socketURL)
        let payload = AntigravityHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .notification,
            sessionID: "antigravity-session-1",
            message: "Antigravity CLI completed step."
        )

        let response = try hookClient.send(.processAntigravityHook(payload))
        #expect(response == .acknowledged)

        let receivedEvent = try await withTimeout(seconds: 2.0) {
            for await event in stream {
                if case let .activityUpdated(activity) = event, activity.sessionID == "antigravity-session-1" {
                    return event
                }
            }
            return nil
        }

        guard case let .activityUpdated(activity)? = receivedEvent else {
            Issue.record("Expected activityUpdated for antigravity notification")
            return
        }

        #expect(activity.summary == "Antigravity CLI completed step.")
    }
}

private func withTimeout<T: Sendable>(seconds: Double, body: @escaping @Sendable () async throws -> T) async throws -> T? {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask {
            try await body()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }

        let result = try await group.next()
        group.cancelAll()
        return result ?? nil
    }
}
