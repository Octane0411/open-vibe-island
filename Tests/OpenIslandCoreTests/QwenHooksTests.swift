import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

struct QwenHooksTests {
    @Test
    func qwenPayloadDecodesJSONObjectToolInputAndExtractsCommandPreview() throws {
        let data = Data(
            """
            {
              "cwd": "/tmp/worktree",
              "hook_event_name": "pre_tool_use",
              "session_id": "qwen-session-1",
              "tool_name": "Bash",
              "tool_input": {
                "command": "grep -i default_api:question README.md"
              }
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(QwenHookPayload.self, from: data)

        #expect(payload.toolInput == .object(["command": .string("grep -i default_api:question README.md")]))
        #expect(payload.effectiveToolInputPreview == "grep -i default_api:question README.md")
    }

    @Test
    func qwenPreToolUseUsesExtractedCommandPreviewInActivitySummary() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let payload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "pre_tool_use",
            sessionID: "qwen-tool-preview",
            toolName: "Bash",
            toolInput: .object(["command": .string("grep -i default_api:question README.md")])
        )

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processQwenHook(payload))

        var iterator = stream.makeAsyncIterator()
        let activityEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .activityUpdated = event {
                return true
            }
            return false
        }

        if case let .activityUpdated(update) = activityEvent {
            #expect(update.summary == "Running Bash: grep -i default_api:question README.md")
        } else {
            Issue.record("Expected a Qwen activity update event")
        }
    }

    @Test
    func qwenAskUserQuestionExtractsStructuredPromptFromToolInput() throws {
        let payload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "permission_request",
            sessionID: "qwen-ask-user-question",
            toolName: "AskUserQuestion",
            toolInput: .string(
                """
                {
                  "questions": [
                    {
                      "question": "Choose environment",
                      "header": "Env",
                      "options": [
                        { "label": "Production", "description": "Use production" },
                        { "label": "Staging", "description": "Use staging" }
                      ]
                    }
                  ]
                }
                """
            )
        )

        let prompt = try #require(payload.questionPrompt)
        #expect(prompt.title == "Choose environment")
        #expect(prompt.questions.count == 1)
        #expect(prompt.questions.first?.header == "Env")
        #expect(prompt.questions.first?.options.map(\.label) == ["Production", "Staging"])
        #expect(prompt.options == ["Production", "Staging"])
    }

    @Test
    func qwenPermissionRequestReturnsAllowDirectiveAfterApproval() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let payload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "permission_request",
            sessionID: "qwen-permission-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("ls -la")]),
            permissionTitle: "Allow Bash",
            permissionDescription: "Qwen needs approval to continue."
        )

        async let responseTask = sendOnGCDThread(.processQwenHook(payload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let permissionEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .permissionRequested = event {
                return true
            }
            return false
        }

        if case let .permissionRequested(requested) = permissionEvent {
            #expect(requested.request.title == "Allow Bash")
            #expect(requested.request.affectedPath == "ls -la")
            #expect(requested.request.toolName == "Bash")
        } else {
            Issue.record("Expected a Qwen permission request event")
        }

        try await observer.send(.resolvePermission(sessionID: "qwen-permission-1", resolution: .allowOnce()))

        let response = try await responseTask
        #expect(response == .qwenHookDirective(.allow))
    }

    @Test
    func qwenPermissionRequestForAskUserQuestionEmitsQuestionEvent() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let payload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "permission_request",
            sessionID: "qwen-question-via-permission",
            toolName: "AskUserQuestion",
            toolInput: .object([
                "questions": .array([
                    .object([
                        "question": .string("Which environment?"),
                        "header": .string("Env"),
                        "options": .array([
                            option(label: "Production", description: "Use production"),
                            option(label: "Staging", description: "Use staging"),
                        ]),
                    ]),
                ]),
            ])
        )

        async let responseTask = sendOnGCDThread(.processQwenHook(payload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let questionEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .questionAsked = event {
                return true
            }
            return false
        }

        if case let .questionAsked(question) = questionEvent {
            #expect(question.prompt.title == "Which environment?")
            #expect(question.prompt.options == ["Production", "Staging"])
            #expect(question.prompt.questions.first?.header == "Env")
        } else {
            Issue.record("Expected AskUserQuestion to emit a Qwen question event")
        }

        try await observer.send(
            .answerQuestion(
                sessionID: "qwen-question-via-permission",
                response: QuestionPromptResponse(answer: "Staging")
            )
        )

        let response = try await responseTask
        #expect(response == .qwenHookDirective(.answer(text: "Staging")))
    }

    @Test
    func qwenNotificationDoesNotResolvePendingPermission() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let permissionPayload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "permission_request",
            sessionID: "qwen-pending-notification",
            toolName: "WriteFile",
            toolInput: .object(["file_path": .string("/tmp/worktree/file.txt")]),
            permissionDescription: "Qwen wants to write a file."
        )

        async let responseTask = sendOnGCDThread(.processQwenHook(permissionPayload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        _ = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .permissionRequested = event {
                return true
            }
            return false
        }

        let notificationPayload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "notification",
            sessionID: "qwen-pending-notification",
            message: "Still waiting for user confirmation."
        )
        let notificationResponse = try BridgeCommandClient(socketURL: socketURL).send(.processQwenHook(notificationPayload))
        #expect(notificationResponse == .acknowledged)

        try await observer.send(
            .resolvePermission(
                sessionID: "qwen-pending-notification",
                resolution: .allowOnce()
            )
        )

        let response = try await responseTask
        #expect(response == .qwenHookDirective(.allow))
    }

    @Test
    func qwenStopDoesNotResolvePendingPermission() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let permissionPayload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "permission_request",
            sessionID: "qwen-pending-stop",
            toolName: "WriteFile",
            toolInput: .object(["file_path": .string("/tmp/worktree/file.txt")]),
            permissionDescription: "Qwen wants to write a file."
        )

        async let responseTask = sendOnGCDThread(.processQwenHook(permissionPayload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        _ = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .permissionRequested = event {
                return true
            }
            return false
        }

        let stopPayload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "stop",
            sessionID: "qwen-pending-stop",
            lastAssistantMessage: "Should not mark completed while approval is pending."
        )
        let stopResponse = try BridgeCommandClient(socketURL: socketURL).send(.processQwenHook(stopPayload))
        #expect(stopResponse == .acknowledged)

        try await observer.send(
            .resolvePermission(
                sessionID: "qwen-pending-stop",
                resolution: .allowOnce()
            )
        )

        let response = try await responseTask
        #expect(response == .qwenHookDirective(.allow))
    }

    @Test
    func qwenQuestionAskedReturnsAnswerDirectiveAfterResponse() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let payload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "question_asked",
            sessionID: "qwen-question-1",
            questionText: "Which environment?"
        )

        async let responseTask = sendOnGCDThread(.processQwenHook(payload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let questionEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .questionAsked = event {
                return true
            }
            return false
        }

        if case let .questionAsked(question) = questionEvent {
            #expect(question.prompt.title == "Which environment?")
        } else {
            Issue.record("Expected a Qwen question event")
        }

        try await observer.send(
            .answerQuestion(
                sessionID: "qwen-question-1",
                response: QuestionPromptResponse(answer: "Production")
            )
        )

        let response = try await responseTask
        #expect(response == .qwenHookDirective(.answer(text: "Production")))
    }

    @Test
    func qwenHookOutputEncoderEncodesAnswerDirective() throws {
        let output = try QwenHookOutputEncoder.standardOutput(
            for: .qwenHookDirective(.answer(text: "Production"))
        )

        let payload = try #require(output)
        let object = try jsonObject(from: payload)

        #expect(object["type"] as? String == "answer")
        #expect(object["text"] as? String == "Production")
    }
}

private enum QwenHooksTestError: Error {
    case streamEnded
    case noMatchingEvent
}

private func nextEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
) async throws -> AgentEvent {
    guard let event = try await iterator.next() else {
        throw QwenHooksTestError.streamEnded
    }

    return event
}

private func nextMatchingEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator,
    maxEvents: Int,
    predicate: (AgentEvent) -> Bool
) async throws -> AgentEvent {
    for _ in 0..<maxEvents {
        let event = try await nextEvent(from: &iterator)
        if predicate(event) {
            return event
        }
    }

    throw QwenHooksTestError.noMatchingEvent
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
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

private func option(label: String, description: String) -> ClaudeHookJSONValue {
    .object([
        "label": .string(label),
        "description": .string(description),
    ])
}
