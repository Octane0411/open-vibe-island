import Foundation
import Testing
@testable import OpenIslandCore

struct CodexHooksTests {
    @Test
    func codexDefaultJumpTargetForwardsWarpPaneUUID() {
        var payload = CodexHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionStart,
            model: "gpt-4o",
            permissionMode: .default,
            sessionID: "s1",
            transcriptPath: nil
        )
        payload.terminalApp = "Warp"
        payload.warpPaneUUID = "D1A5DF3027E44FC080FE2656FAF2BA2E"
        #expect(payload.defaultJumpTarget.warpPaneUUID == "D1A5DF3027E44FC080FE2656FAF2BA2E")
    }

    @Test
    func codexWithRuntimeContextPopulatesWarpPaneUUIDFromResolver() {
        let payload = CodexHookPayload(
            cwd: "/Users/u/demo",
            hookEventName: .sessionStart,
            model: "gpt-4o",
            permissionMode: .default,
            sessionID: "s1",
            transcriptPath: nil
        ).withRuntimeContext(
            environment: ["WARP_IS_LOCAL_SHELL_SESSION": "1"],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) },
            warpPaneResolver: { cwd in
                cwd == "/Users/u/demo" ? "DEADBEEFDEADBEEFDEADBEEFDEADBEEF" : nil
            }
        )

        #expect(payload.terminalApp == "Warp")
        #expect(payload.warpPaneUUID == "DEADBEEFDEADBEEFDEADBEEFDEADBEEF")
        #expect(payload.defaultJumpTarget.warpPaneUUID == "DEADBEEFDEADBEEFDEADBEEFDEADBEEF")
    }

    @Test
    func codexWithRuntimeContextSkipsWarpResolverForNonWarpTerminal() {
        var resolverCalls = 0
        let payload = CodexHookPayload(
            cwd: "/Users/u/demo",
            hookEventName: .sessionStart,
            model: "gpt-4o",
            permissionMode: .default,
            sessionID: "s1",
            transcriptPath: nil
        ).withRuntimeContext(
            environment: ["TERM_PROGRAM": "ghostty"],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) },
            warpPaneResolver: { _ in
                resolverCalls += 1
                return "SHOULD-NOT-BE-USED"
            }
        )

        #expect(payload.terminalApp == "Ghostty")
        #expect(payload.warpPaneUUID == nil)
        #expect(resolverCalls == 0)
    }

    @Test
    func codexWithRuntimeContextDetectsCodexDesktopApp() {
        let payload = CodexHookPayload(
            cwd: "/Users/u/project",
            hookEventName: .sessionStart,
            model: "gpt-4o",
            permissionMode: .default,
            sessionID: "s1",
            transcriptPath: nil
        ).withRuntimeContext(
            environment: ["__CFBundleIdentifier": "com.openai.codex"],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) },
            warpPaneResolver: { _ in nil }
        )

        #expect(payload.terminalApp == "Codex.app")
        #expect(payload.warpPaneUUID == nil)
    }

    @Test
    func codexPermissionRequestPayloadAcceptsDescriptionOnlyToolInput() throws {
        let data = """
        {
          "cwd": "/tmp/demo",
          "hook_event_name": "PermissionRequest",
          "model": "gpt-5-codex",
          "permission_mode": "default",
          "session_id": "s1",
          "tool_name": "apply_patch",
          "tool_input": {
            "description": "Apply a focused patch to Sources/App.swift",
            "path": "Sources/App.swift"
          },
          "transcript_path": null,
          "turn_id": "turn-1"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(CodexHookPayload.self, from: data)

        #expect(payload.hookEventName == .permissionRequest)
        #expect(payload.toolInput?.command == nil)
        #expect(payload.toolInput?.description == "Apply a focused patch to Sources/App.swift")
        #expect(payload.permissionRequestTitle == "Apply code patch")
        #expect(payload.permissionRequestSummary == "Apply a focused patch to Sources/App.swift")
    }

    @Test
    func codexHookOutputEncoderEncodesPermissionRequestAllowDecision() throws {
        let output = try CodexHookOutputEncoder.standardOutput(
            for: .codexHookDirective(.permissionRequest(.allow))
        )

        let payload = try #require(output)
        let object = try jsonObject(from: payload)
        let hookSpecificOutput = object["hookSpecificOutput"] as? [String: Any]
        let decision = hookSpecificOutput?["decision"] as? [String: Any]

        #expect(object["continue"] as? Bool == true)
        #expect(hookSpecificOutput?["hookEventName"] as? String == "PermissionRequest")
        #expect(decision?["behavior"] as? String == "allow")
    }

    @Test
    func codexHookOutputEncoderEncodesPermissionRequestDenyDecision() throws {
        let output = try CodexHookOutputEncoder.standardOutput(
            for: .codexHookDirective(.permissionRequest(.deny(message: "Use a narrower patch.")))
        )

        let payload = try #require(output)
        let object = try jsonObject(from: payload)
        let hookSpecificOutput = object["hookSpecificOutput"] as? [String: Any]
        let decision = hookSpecificOutput?["decision"] as? [String: Any]

        #expect(hookSpecificOutput?["hookEventName"] as? String == "PermissionRequest")
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] as? String == "Use a narrower patch.")
    }

}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}
