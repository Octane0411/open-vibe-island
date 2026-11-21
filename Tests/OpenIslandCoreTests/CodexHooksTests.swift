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

    @Test
    func codexHookPayloadDecodesSubagentFields() throws {
        let data = """
        {
          "session_id": "parent-thread",
          "turn_id": "turn-1",
          "agent_id": "subagent-1",
          "agent_type": "default",
          "transcript_path": "/tmp/rollout-subagent-1.jsonl",
          "cwd": "/tmp/demo",
          "hook_event_name": "Stop",
          "model": "gpt-5-codex",
          "permission_mode": "default",
          "stop_hook_active": false,
          "last_assistant_message": "Done."
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(CodexHookPayload.self, from: data)

        #expect(payload.sessionID == "parent-thread")
        #expect(payload.agentID == "subagent-1")
        #expect(payload.agentType == "default")
    }

    @Test
    func codexHookPayloadWithoutAgentFieldsIsMainSession() throws {
        let data = """
        {
          "session_id": "thread-1",
          "turn_id": "turn-1",
          "transcript_path": "/tmp/rollout-thread-1.jsonl",
          "cwd": "/tmp/demo",
          "hook_event_name": "Stop",
          "model": "gpt-5-codex",
          "permission_mode": "default",
          "stop_hook_active": false,
          "last_assistant_message": "Done."
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(CodexHookPayload.self, from: data)

        #expect(payload.agentID == nil)
        #expect(payload.agentType == nil)
    }

    @Test
    func codexSubagentHooksAreSuppressed() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }

        let collector = CodexAgentEventCollector()
        let collectionTask = Task {
            do {
                for try await event in stream {
                    await collector.append(event)
                }
            } catch {}
        }
        defer { collectionTask.cancel() }

        try await observer.send(.registerClient(role: .observer))

        let sessionID = "codex-parent-thread"
        let subagentPayload = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .stop,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: sessionID,
            transcriptPath: "/tmp/codex-subagent.jsonl",
            lastAssistantMessage: "Subagent done.",
            agentID: "subagent-1",
            agentType: "default"
        )
        let response = try BridgeCommandClient(socketURL: socketURL).send(
            .processCodexHook(subagentPayload)
        )
        #expect(response == .acknowledged)

        // A marker event from the main session lets us wait until the bridge
        // has processed everything sent so far.
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processCodexHook(
                CodexHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .sessionStart,
                    model: "gpt-5-codex",
                    permissionMode: .default,
                    sessionID: "codex-marker-session",
                    transcriptPath: "/tmp/codex-marker.jsonl"
                )
            )
        )

        let deadline = Date().addingTimeInterval(5)
        var events: [AgentEvent] = []
        while Date() < deadline {
            events = await collector.events()
            if events.contains(where: { event in
                if case let .sessionStarted(payload) = event {
                    return payload.sessionID == "codex-marker-session"
                }
                return false
            }) {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(!events.isEmpty)
        #expect(!events.contains { event in
            switch event {
            case let .sessionStarted(payload):
                return payload.sessionID == sessionID
            case let .sessionCompleted(payload):
                return payload.sessionID == sessionID
            case let .activityUpdated(payload):
                return payload.sessionID == sessionID
            case let .permissionRequested(payload):
                return payload.sessionID == sessionID
            default:
                return false
            }
        })
    }

}

private actor CodexAgentEventCollector {
    private var storage: [AgentEvent] = []

    func append(_ event: AgentEvent) {
        storage.append(event)
    }

    func events() -> [AgentEvent] {
        storage
    }
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}
