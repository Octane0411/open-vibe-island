import Dispatch
import Foundation
import Testing
@testable import AgentDeckCore

struct GeminiHooksTests {
    @Test
    func geminiHookPayloadDecodesNotification() throws {
        let json = """
        {
          "cwd": "/tmp/worktree",
          "hook_event_name": "Notification",
          "session_id": "gemini-session-1",
          "message": "Gemini CLI requires permission to continue.",
          "notification_type": "ToolPermission",
          "details": {
            "tool_name": "run_shell_command",
            "file_path": "/tmp/worktree/package.json"
          }
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(GeminiHookPayload.self, from: json)

        #expect(payload.hookEventName == .notification)
        #expect(payload.notificationSummary == "Gemini CLI requires permission to continue.")
        #expect(payload.renderedDetails == "{file_path: /tmp/worktree/package.json, tool_name: run_shell_command}")
    }

    @Test
    func geminiHookInstallerInstallsIntoEmptySettingsFile() throws {
        let mutation = try GeminiHookInstaller.installSettingsJSON(
            existingData: nil,
            hookCommand: "/usr/local/bin/AgentDeckHooks --source gemini"
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
    func geminiNotificationBecomesActivityUpdate() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let startPayload = GeminiHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            sessionID: "gemini-session-1"
        )
        let notificationPayload = GeminiHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .notification,
            sessionID: "gemini-session-1",
            notificationType: "ToolPermission",
            message: "Gemini CLI requires permission to run a tool.",
            details: .object([
                "tool_name": .string("run_shell_command"),
                "file_path": .string("/tmp/worktree/package.json"),
            ])
        )

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processGeminiHook(startPayload))
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processGeminiHook(notificationPayload))

        var iterator = stream.makeAsyncIterator()
        let activityEvent = try await nextMatchingGeminiEvent(from: &iterator, maxEvents: 8) { event in
            if case .activityUpdated = event {
                return true
            }
            return false
        }

        guard case let .activityUpdated(payload) = activityEvent else {
            Issue.record("Expected a Gemini notification activity update")
            return
        }

        #expect(payload.sessionID == "gemini-session-1")
        #expect(payload.phase == .completed)
        #expect(payload.summary == "Gemini CLI requires permission to run a tool.")
    }

    @Test
    func geminiAfterAgentEmitsSessionCompletedWithoutEndingSession() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let startPayload = GeminiHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            sessionID: "gemini-session-2"
        )
        let afterPayload = GeminiHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .afterAgent,
            sessionID: "gemini-session-2",
            promptResponse: "Done."
        )

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processGeminiHook(startPayload))
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processGeminiHook(afterPayload))

        var iterator = stream.makeAsyncIterator()
        let event = try await nextMatchingGeminiEvent(from: &iterator, maxEvents: 8) { event in
            if case .sessionCompleted = event {
                return true
            }
            return false
        }

        guard case let .sessionCompleted(payload) = event else {
            Issue.record("Expected Gemini after-agent session completion")
            return
        }

        #expect(payload.sessionID == "gemini-session-2")
        #expect(payload.summary == "Done.")
        #expect(payload.isInterrupt != true)
        #expect(payload.isSessionEnd != true)
    }

    @Test
    func geminiMetadataTracksPromptAndResponse() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let startPayload = GeminiHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            sessionID: "gemini-session-3"
        )
        let beforePayload = GeminiHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .beforeAgent,
            sessionID: "gemini-session-3",
            prompt: "Explain the current repository status."
        )
        let afterPayload = GeminiHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .afterAgent,
            sessionID: "gemini-session-3",
            promptResponse: "The repository has local Gemini integration changes."
        )

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processGeminiHook(startPayload))
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processGeminiHook(beforePayload))
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processGeminiHook(afterPayload))

        var iterator = stream.makeAsyncIterator()
        let metadataEvent = try await nextMatchingGeminiEvent(from: &iterator, maxEvents: 12) { event in
            if case .geminiSessionMetadataUpdated = event {
                return true
            }
            return false
        }

        guard case let .geminiSessionMetadataUpdated(payload) = metadataEvent else {
            Issue.record("Expected Gemini metadata update")
            return
        }

        #expect(payload.sessionID == "gemini-session-3")
        #expect(payload.geminiMetadata.lastUserPrompt == "Explain the current repository status.")
        #expect(payload.geminiMetadata.initialUserPrompt == "Explain the current repository status.")
    }

    @Test
    func geminiMetadataStoresAssistantPreviewInsteadOfFullMultilineResponse() {
        let response = """
        Here is the first paragraph of the answer.

        Here is the second paragraph with process details that should not be shown in full.

        Final summary line.
        """
        let payload = GeminiHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .afterAgent,
            sessionID: "gemini-session-4",
            promptResponse: response
        )

        let preview = payload.defaultGeminiMetadata.lastAssistantMessage
        #expect(preview == payload.promptResponsePreview)
        #expect(preview != response)
        #expect(preview?.contains("\n") == false)
        #expect(payload.defaultGeminiMetadata.lastAssistantMessageBody == response)
    }

    @Test
    func geminiGhosttyLocatorScriptSeparatesIDWorkingDirectoryAndTitle() {
        let script = GeminiHookPayload.terminalLocatorAppleScript(for: "Ghostty")

        #expect(script.contains("(id as text) & (ASCII character 31) & (working directory as text)"))
        #expect(script.contains("(working directory as text) & (ASCII character 31) & (name as text)"))
    }

    @Test
    func geminiCompletionMessageUsesLastBodySegmentAndDropsRepeatedTail() {
        let response = """
        I'll review the integration guide and summarize the migration plan.

         

         
        The migration plan has three concrete steps:

        1. Update the request validation layer.
        2. Migrate the endpoint signatures to the new types.
        3. Regenerate the API examples for the docs.

        This keeps the rollout incremental and reduces migration risk for the API team.

        In short, the migration should stay incremental so each stage is easy to verify.

        he migration plan has three concrete steps:

        1. Update the request validation layer.
        2. Migrate the endpoint signatures to the new types.
        3. Regenerate the API examples for the docs.

        This keeps the rollout incremental and reduces migration risk for the API team.

        In short, the migration should stay incremental so each stage is easy to verify.
        """

        let session = AgentSession(
            id: "gemini-session-deduped",
            title: "Gemini CLI · repo",
            tool: .geminiCLI,
            phase: .completed,
            summary: "summary",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            geminiMetadata: GeminiSessionMetadata(
                lastAssistantMessage: "preview",
                lastAssistantMessageBody: response
            )
        )

        let completion = session.completionAssistantMessageText

        #expect(completion?.hasPrefix("The migration plan has three concrete steps:") == true)
        #expect(completion?.contains("I'll review the integration guide") == false)
        #expect(completion?.contains("\n\nhe migration plan has three concrete steps:") == false)
        #expect(completion?.components(separatedBy: "In short, the migration should stay incremental so each stage is easy to verify.").count == 2)
    }

    @Test
    func geminiCompletionMessageDropsRepeatedTailAfterWhitespaceNormalization() {
        let response = """
        Updated the API query parameter guide with typed examples:
        - Added the recommended annotated syntax.
        - Added support for repeated query values.
        - Added advanced metadata examples.
        - Updated the snippets for Python 3.10+.

        Updated the API query parameter guide with typed examples:
        - Added the recommended annotated syntax .
        - Added support for repeated query values.
        - Added advanced metadata examples.
        - Updated the snippets for Python 3.10+.
        """

        let session = AgentSession(
            id: "gemini-session-whitespace-deduped",
            title: "Gemini CLI · repo",
            tool: .geminiCLI,
            phase: .completed,
            summary: "summary",
            updatedAt: Date(timeIntervalSince1970: 1_001),
            geminiMetadata: GeminiSessionMetadata(
                lastAssistantMessage: "preview",
                lastAssistantMessageBody: response
            )
        )

        let completion = session.completionAssistantMessageText

        #expect(completion?.hasPrefix("Updated the API query parameter guide with typed examples:") == true)
        #expect(completion?.contains("Updated the API query parameter guide with typed examples:\n- Added the recommended annotated syntax .") == false)
        #expect(completion?.components(separatedBy: "- Updated the snippets for Python 3.10+.").count == 2)
    }
}

private func nextMatchingGeminiEvent(
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
