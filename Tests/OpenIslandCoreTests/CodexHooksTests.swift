import Foundation
import Testing
@testable import OpenIslandCore

struct CodexHooksTests {
    @Test
    func codexPermissionRequestPayloadDecodesArbitraryToolInput() throws {
        let data = """
        {
          "cwd": "/tmp/worktree",
          "hook_event_name": "PermissionRequest",
          "model": "gpt-5-codex",
          "permission_mode": "default",
          "session_id": "codex-permission-1",
          "turn_id": "turn-1",
          "tool_name": "mcp__filesystem__write_file",
          "tool_input": {
            "path": "/tmp/worktree/Sources/App.swift",
            "reason": "write change"
          }
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(CodexHookPayload.self, from: data)

        #expect(payload.hookEventName.rawValue == "PermissionRequest")
        #expect(payload.toolName == "mcp__filesystem__write_file")
        #expect(payload.toolInput?.command == nil)
    }

    @Test
    func codexPermissionRequestUsesInteractiveBridgeTimeout() {
        let payload = CodexHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .permissionRequest,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "s1",
            transcriptPath: nil
        )

        #expect(payload.bridgeResponseTimeout == 86_400)
    }

    @Test
    func codexPermissionRequestOutputEncoderEmitsAllowDecision() throws {
        let maybeOutput = try CodexHookOutputEncoder.standardOutput(
            for: .codexHookDirective(.permissionRequest(.allow))
        )
        let output = try #require(maybeOutput)
        let object = try JSONSerialization.jsonObject(with: output) as? [String: Any]
        let hookSpecificOutput = object?["hookSpecificOutput"] as? [String: Any]
        let decision = hookSpecificOutput?["decision"] as? [String: Any]

        #expect(hookSpecificOutput?["hookEventName"] as? String == "PermissionRequest")
        #expect(decision?["behavior"] as? String == "allow")
    }

    @Test
    func codexPermissionRequestOutputEncoderEmitsDenyDecision() throws {
        let maybeOutput = try CodexHookOutputEncoder.standardOutput(
            for: .codexHookDirective(.permissionRequest(.deny(message: "Blocked")))
        )
        let output = try #require(maybeOutput)
        let object = try JSONSerialization.jsonObject(with: output) as? [String: Any]
        let hookSpecificOutput = object?["hookSpecificOutput"] as? [String: Any]
        let decision = hookSpecificOutput?["decision"] as? [String: Any]

        #expect(hookSpecificOutput?["hookEventName"] as? String == "PermissionRequest")
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] as? String == "Blocked")
    }

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

}
