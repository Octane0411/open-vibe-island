import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

/// Regression coverage for core session lifecycle and visibility behavior.
struct SessionStateTests {
    /// Completed Codex CLI sessions outside Codex.app should age out even while Codex.app is running.
    @Test
    func completedCodexCLISessionEndsEvenWhenCodexAppIsRunning() {
        let startedAt = Date(timeIntervalSince1970: 7_000)
        var state = SessionState()

        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "codex-vscode-review",
                    title: "Codex · jobfeed",
                    tool: .codex,
                    origin: .live,
                    summary: "Reviewing code",
                    timestamp: startedAt,
                    jumpTarget: JumpTarget(
                        terminalApp: "VS Code",
                        workspaceName: "jobfeed",
                        paneTitle: "Codex 019e9716",
                        workingDirectory: "/Users/example/jobfeed"
                    )
                )
            )
        )
        state.apply(
            .sessionCompleted(
                SessionCompleted(
                    sessionID: "codex-vscode-review",
                    summary: "no issues found",
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )

        _ = state.markProcessLiveness(aliveSessionIDs: [], isCodexAppRunning: true)
        _ = state.markProcessLiveness(aliveSessionIDs: [], isCodexAppRunning: true)

        #expect(state.session(id: "codex-vscode-review")?.isSessionEnded == true)
        #expect(state.liveSessionCount == 0)
    }

    /// Verifies permission and question events update an already-tracked session.
    @Test
    func appliesPermissionAndQuestionEventsToExistingSessions() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var state = SessionState()

        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "session-1",
                    title: "Fix auth bug",
                    tool: .codex,
                    summary: "Booting up",
                    timestamp: startedAt
                )
            )
        )

        state.apply(
            .permissionRequested(
                PermissionRequested(
                    sessionID: "session-1",
                    request: PermissionRequest(
                        title: "Edit file",
                        summary: "Wants to edit middleware",
                        affectedPath: "src/auth/middleware.ts"
                    ),
                    timestamp: startedAt.addingTimeInterval(5)
                )
            )
        )

        #expect(state.attentionCount == 1)
        #expect(state.activeActionableSession?.phase == .waitingForApproval)
        #expect(state.activeActionableSession?.permissionRequest?.affectedPath == "src/auth/middleware.ts")

        state.apply(
            .questionAsked(
                QuestionAsked(
                    sessionID: "session-1",
                    prompt: QuestionPrompt(
                        title: "Which environment?",
                        options: ["Production", "Staging"]
                    ),
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )

        #expect(state.activeActionableSession?.phase == .waitingForAnswer)
        #expect(state.activeActionableSession?.questionPrompt?.options == ["Production", "Staging"])
        #expect(state.activeActionableSession?.permissionRequest == nil)
    }

    /// Contract that the Claude Desktop fix (#510) relies on: a hook-managed
    /// Claude session stays visible for as long as its ID is reported in
    /// `aliveSessionIDs`, and is only evicted after two consecutive polls
    /// where it is absent. ProcessMonitoringCoordinator keeps Claude Desktop
    /// session IDs in that set while Claude.app is running (the desktop
    /// subprocess is TTY-less and invisible to ps/lsof discovery), so they no
    /// longer vanish ~6s after appearing.
    @Test
    func hookManagedClaudeSessionLivenessFollowsReportedAliveSet() {
        var session = AgentSession(
            id: "desktop-1",
            title: "Claude · demo",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        session.isHookManaged = true
        session.isProcessAlive = true
        var state = SessionState(sessions: [session])

        // Reported alive (Claude.app running): stays visible across polls.
        state.markProcessLiveness(aliveSessionIDs: ["desktop-1"])
        state.markProcessLiveness(aliveSessionIDs: ["desktop-1"])
        #expect(state.session(id: "desktop-1")?.isSessionEnded == false)
        #expect(state.session(id: "desktop-1")?.isVisibleInIsland == true)

        // First miss (e.g. Claude.app just quit): debounced, not yet evicted.
        state.markProcessLiveness(aliveSessionIDs: [])
        #expect(state.session(id: "desktop-1")?.isSessionEnded == false)
        #expect(state.session(id: "desktop-1")?.isVisibleInIsland == true)

        // Second consecutive miss: session ends and leaves the island.
        state.markProcessLiveness(aliveSessionIDs: [])
        #expect(state.session(id: "desktop-1")?.isSessionEnded == true)
        #expect(state.session(id: "desktop-1")?.isVisibleInIsland == false)
    }

    @Test
    func resolvesUserActionsAndKeepsSessionsSortedByRecency() {
        let startedAt = Date(timeIntervalSince1970: 2_000)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "older",
                    title: "Older session",
                    tool: .claudeCode,
                    phase: .running,
                    summary: "Working",
                    updatedAt: startedAt
                ),
                AgentSession(
                    id: "newer",
                    title: "Newer session",
                    tool: .codex,
                    phase: .waitingForApproval,
                    summary: "Needs approval",
                    updatedAt: startedAt.addingTimeInterval(5),
                    permissionRequest: PermissionRequest(
                        title: "Edit users.ts",
                        summary: "Needs access",
                        affectedPath: "src/routes/users.ts"
                    )
                ),
            ]
        )

        state.resolvePermission(
            sessionID: "newer",
            resolution: .allowOnce(),
            at: startedAt.addingTimeInterval(20)
        )

        #expect(state.sessions.first?.id == "newer")
        #expect(state.sessions.first?.phase == .running)
        #expect(state.sessions.first?.permissionRequest == nil)

        state.answerQuestion(
            sessionID: "older",
            response: QuestionPromptResponse(answer: "Production"),
            at: startedAt.addingTimeInterval(25)
        )

        #expect(state.sessions.first?.id == "older")
        #expect(state.sessions.first?.summary == "Answered: Production")
    }

    @Test
    func keepsQuestionStateWhileIncidentalRunningUpdatesArrive() {
        let startedAt = Date(timeIntervalSince1970: 2_500)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "claude-question",
                    title: "Claude · repo",
                    tool: .claudeCode,
                    attachmentState: .attached,
                    phase: .waitingForAnswer,
                    summary: "Which environment?",
                    updatedAt: startedAt,
                    questionPrompt: QuestionPrompt(
                        title: "Which environment?",
                        questions: [
                            QuestionPromptItem(
                                question: "Which environment?",
                                header: "Env",
                                options: [
                                    QuestionOption(label: "Production"),
                                    QuestionOption(label: "Staging"),
                                ]
                            )
                        ]
                    )
                )
            ]
        )

        state.apply(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "claude-question",
                    summary: "Claude is still waiting for your answer.",
                    phase: .running,
                    timestamp: startedAt.addingTimeInterval(5)
                )
            )
        )

        #expect(state.session(id: "claude-question")?.phase == .waitingForAnswer)
        #expect(state.session(id: "claude-question")?.summary == "Which environment?")
        #expect(state.session(id: "claude-question")?.questionPrompt?.title == "Which environment?")
    }

    @Test
    func actionableStateResolvedClearsWaitingForApproval() {
        let startedAt = Date(timeIntervalSince1970: 5_000)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "claude-approval",
                    title: "Claude · repo",
                    tool: .claudeCode,
                    attachmentState: .attached,
                    phase: .waitingForApproval,
                    summary: "Wants to edit file",
                    updatedAt: startedAt,
                    permissionRequest: PermissionRequest(
                        title: "Edit file",
                        summary: "Wants to edit file",
                        affectedPath: "src/main.ts"
                    )
                )
            ]
        )

        state.apply(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: "claude-approval",
                    summary: "Approval was handled outside Open Island.",
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )

        #expect(state.session(id: "claude-approval")?.phase == .running)
        #expect(state.session(id: "claude-approval")?.permissionRequest == nil)
        #expect(state.session(id: "claude-approval")?.summary == "Approval was handled outside Open Island.")
    }

    @Test
    func actionableStateResolvedClearsWaitingForAnswer() {
        let startedAt = Date(timeIntervalSince1970: 5_500)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "claude-question",
                    title: "Claude · repo",
                    tool: .claudeCode,
                    attachmentState: .attached,
                    phase: .waitingForAnswer,
                    summary: "Which environment?",
                    updatedAt: startedAt,
                    questionPrompt: QuestionPrompt(
                        title: "Which environment?",
                        options: ["Production", "Staging"]
                    )
                )
            ]
        )

        state.apply(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: "claude-question",
                    summary: "Approval was handled outside Open Island.",
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )

        #expect(state.session(id: "claude-question")?.phase == .running)
        #expect(state.session(id: "claude-question")?.questionPrompt == nil)
    }

    @Test
    func actionableStateResolvedIsNoOpWhenAlreadyRunning() {
        let startedAt = Date(timeIntervalSince1970: 6_000)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "claude-running",
                    title: "Claude · repo",
                    tool: .claudeCode,
                    phase: .running,
                    summary: "Working on it",
                    updatedAt: startedAt
                )
            ]
        )

        state.apply(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: "claude-running",
                    summary: "Should not change anything.",
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )

        #expect(state.session(id: "claude-running")?.phase == .running)
        #expect(state.session(id: "claude-running")?.summary == "Working on it")
    }

    @Test
    func preservesLiveSessionOriginFromStartEvent() {
        var state = SessionState()

        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "live-session-1",
                    title: "Live session",
                    tool: .codex,
                    origin: .live,
                    summary: "Live data",
                    timestamp: .now
                )
            )
        )

        #expect(state.session(id: "live-session-1")?.origin == .live)
        #expect(state.session(id: "live-session-1")?.isDemoSession == false)
        #expect(state.session(id: "live-session-1")?.attachmentState == .attached)
    }

    @Test
    func reconcileAttachmentStatesUpdatesExistingSessionsOnly() {
        let startedAt = Date(timeIntervalSince1970: 4_000)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "attached-session",
                    title: "Attached session",
                    tool: .codex,
                    attachmentState: .stale,
                    phase: .completed,
                    summary: "Turn completed",
                    updatedAt: startedAt
                ),
                AgentSession(
                    id: "untouched-session",
                    title: "Untouched session",
                    tool: .codex,
                    attachmentState: .attached,
                    phase: .running,
                    summary: "Still running",
                    updatedAt: startedAt.addingTimeInterval(5)
                ),
            ]
        )

        let changed = state.reconcileAttachmentStates([
            "attached-session": .attached,
            "missing-session": .detached,
        ])

        #expect(changed)
        #expect(state.session(id: "attached-session")?.attachmentState == .attached)
        #expect(state.session(id: "attached-session")?.summary == "Turn completed")
        #expect(state.session(id: "untouched-session")?.attachmentState == .attached)
    }

    @Test
    func liveCountsOnlyIncludeVisibleSessions() {
        var liveRunning = AgentSession(
            id: "live-running",
            title: "Live running",
            tool: .codex,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: .now
        )
        liveRunning.isProcessAlive = true

        var liveAttention = AgentSession(
            id: "live-attention",
            title: "Live attention",
            tool: .codex,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Needs approval",
            updatedAt: .now
        )
        liveAttention.isProcessAlive = true

        let state = SessionState(
            sessions: [
                liveRunning,
                liveAttention,
                AgentSession(
                    id: "detached-running",
                    title: "Detached running",
                    tool: .codex,
                    attachmentState: .detached,
                    phase: .running,
                    summary: "Old run",
                    updatedAt: .now
                ),
            ]
        )

        #expect(state.liveSessionCount == 2)
        #expect(state.liveRunningCount == 1)
        #expect(state.liveAttentionCount == 1)
        #expect(state.runningCount == 2)
    }

    @Test
    func bridgeEnvelopeRoundTripsThroughLineCodec() throws {
        let envelope = BridgeEnvelope.event(
            .permissionRequested(
                PermissionRequested(
                    sessionID: "session-42",
                    request: PermissionRequest(
                        title: "Edit middleware",
                        summary: "Needs to edit auth middleware.",
                        affectedPath: "src/auth/middleware.ts"
                    ),
                    timestamp: Date(timeIntervalSince1970: 3_000)
                )
            )
        )

        var buffer = try BridgeCodec.encodeLine(envelope)
        let decoded = try BridgeCodec.decodeLines(from: &buffer)

        #expect(decoded == [envelope])
        #expect(buffer.isEmpty)
    }

    @Test
    func bridgeQuestionCommandEmitsQuestionEventForExistingSession() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let startPayload = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "codex-session-question",
            transcriptPath: nil
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(startPayload))

        let prompt = QuestionPrompt(
            title: "Which environment?",
            options: ["Production", "Staging", "Local"]
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .requestQuestion(sessionID: "codex-session-question", prompt: prompt)
        )

        var iterator = stream.makeAsyncIterator()
        let startedEvent = try await nextEvent(from: &iterator)
        let questionEvent = try await nextEvent(from: &iterator)

        #expect(startedEvent.isSessionStarted)
        #expect(questionEvent.questionPrompt?.title == "Which environment?")
        #expect(questionEvent.questionPrompt?.options == ["Production", "Staging", "Local"])
    }

    @Test
    func codexSubagentHooksPreserveParentLifecycle() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-codex-hook-subagent-\(UUID().uuidString)", isDirectory: true)
        let parentRolloutURL = fixtureRoot.appendingPathComponent("parent.jsonl")
        let childRolloutURL = fixtureRoot.appendingPathComponent("child.jsonl")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try """
        {"type":"session_meta","payload":{"id":"parent-thread","cwd":"/tmp/worktree","thread_source":"user","source":"vscode"}}
        """.write(to: parentRolloutURL, atomically: true, encoding: .utf8)
        try """
        {"type":"session_meta","payload":{"id":"child-thread","session_id":"parent-thread","parent_thread_id":"parent-thread","thread_source":"subagent","cwd":"/tmp/worktree","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent-thread","depth":1}}}}}
        """.write(to: childRolloutURL, atomically: true, encoding: .utf8)

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let parentStart = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "parent-thread",
            terminalApp: "Codex.app",
            transcriptPath: parentRolloutURL.path
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(parentStart))

        var iterator = stream.makeAsyncIterator()
        let parentStartedEvent = try await nextEvent(from: &iterator)
        guard case let .sessionStarted(parentStarted) = parentStartedEvent else {
            Issue.record("Expected parent SessionStart")
            return
        }
        #expect(parentStarted.codexMetadata?.transcriptPath == parentRolloutURL.path)

        let childStart = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "parent-thread",
            terminalApp: "Codex.app",
            transcriptPath: childRolloutURL.path
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(childStart))

        let childStartedEvent = try await nextEvent(from: &iterator)
        guard case let .activityUpdated(childActivity) = childStartedEvent else {
            Issue.record("Expected subagent SessionStart to keep the parent running")
            return
        }
        #expect(childActivity.sessionID == "parent-thread")
        #expect(childActivity.phase == .running)

        let childStop = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .stop,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "parent-thread",
            terminalApp: "Codex.app",
            transcriptPath: childRolloutURL.path,
            lastAssistantMessage: "Child finished."
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(childStop))

        let parentPrompt = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .userPromptSubmit,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "parent-thread",
            terminalApp: "Codex.app",
            transcriptPath: parentRolloutURL.path,
            prompt: "Continue the parent turn."
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(parentPrompt))

        let parentMetadataEvent = try await nextEvent(from: &iterator)
        #expect(parentMetadataEvent.trackedMetadataUpdate?.codexMetadata.transcriptPath == parentRolloutURL.path)
        let parentActivityEvent = try await nextEvent(from: &iterator)
        #expect(parentActivityEvent.activityUpdate?.phase == .running)

        let parentStop = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .stop,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "parent-thread",
            terminalApp: "Codex.app",
            transcriptPath: parentRolloutURL.path,
            lastAssistantMessage: "Parent finished."
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(parentStop))

        let finalMetadataEvent = try await nextEvent(from: &iterator)
        #expect(finalMetadataEvent.trackedMetadataUpdate?.codexMetadata.transcriptPath == parentRolloutURL.path)
        let completedEvent = try await nextEvent(from: &iterator)
        #expect(completedEvent.sessionCompleted?.summary == "Parent finished.")
    }

    @Test
    func codexSubagentPermissionDenialKeepsParentRunning() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-codex-hook-subagent-permission-\(UUID().uuidString)", isDirectory: true)
        let parentRolloutURL = fixtureRoot.appendingPathComponent("parent.jsonl")
        let childRolloutURL = fixtureRoot.appendingPathComponent("child.jsonl")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try """
        {"type":"session_meta","payload":{"id":"parent-thread","cwd":"/tmp/worktree","thread_source":"user","source":"vscode"}}
        """.write(to: parentRolloutURL, atomically: true, encoding: .utf8)
        try """
        {"type":"session_meta","payload":{"id":"child-thread","session_id":"parent-thread","parent_thread_id":"parent-thread","thread_source":"subagent","cwd":"/tmp/worktree","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent-thread","depth":1}}}}}
        """.write(to: childRolloutURL, atomically: true, encoding: .utf8)

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let parentStart = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "parent-thread",
            terminalApp: "Codex.app",
            transcriptPath: parentRolloutURL.path
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(parentStart))

        var iterator = stream.makeAsyncIterator()
        _ = try await nextEvent(from: &iterator)

        let childPermission = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .permissionRequest,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "parent-thread",
            terminalApp: "Codex.app",
            transcriptPath: childRolloutURL.path,
            toolName: "apply_patch",
            toolUseID: "child-tool-1",
            toolInput: CodexHookToolInput(description: "Edit a child-owned file")
        )
        async let childResponse = sendOnGCDThread(.processCodexHook(childPermission), socketURL: socketURL)

        let firstChildEvent = try await nextEvent(from: &iterator)
        let permissionEvent: AgentEvent
        if firstChildEvent.isPermissionRequested {
            permissionEvent = firstChildEvent
        } else {
            permissionEvent = try await nextEvent(from: &iterator)
        }
        #expect(firstChildEvent.isPermissionRequested)
        #expect(permissionEvent.isPermissionRequested)

        try await observer.send(
            .resolvePermission(
                sessionID: "parent-thread",
                resolution: .deny(message: "Skip this child edit.")
            )
        )

        let resolutionEvent = try await nextEvent(from: &iterator)
        #expect(resolutionEvent.activityUpdate?.phase == .running)
        #expect(resolutionEvent.activityUpdate?.summary == "Skip this child edit.")
        #expect(
            try await childResponse
                == .codexHookDirective(.permissionRequest(.deny(message: "Skip this child edit.")))
        )
    }

    @Test
    func openCodeQuestionAskedCarriesStructuredOptionsUntilAnswered() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let payload = OpenCodeHookPayload(
            hookEventName: .questionAsked,
            sessionID: "opencode-question-1",
            cwd: "/tmp/worktree",
            questionID: "question-1",
            questionText: "Which notification treatment should this session use?",
            questions: [
                OpenCodeQuestionPayload(
                    question: "Which notification treatment should this session use?",
                    header: "Notification",
                    options: [
                        OpenCodeQuestionOptionPayload(
                            label: "Inline choices",
                            description: "Answer directly in the island"
                        ),
                        OpenCodeQuestionOptionPayload(
                            label: "Jump back",
                            description: "Return to the terminal first"
                        ),
                    ]
                ),
            ]
        )

        async let responseTask = sendOnGCDThread(.processOpenCodeHook(payload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let startedEvent = try await nextEvent(from: &iterator)
        let questionEvent = try await nextEvent(from: &iterator)

        #expect(startedEvent.isSessionStarted)
        #expect(questionEvent.questionPrompt?.questions.first?.question == "Which notification treatment should this session use?")
        #expect(questionEvent.questionPrompt?.questions.first?.options.map(\.label) == ["Inline choices", "Jump back"])
        #expect(questionEvent.questionPrompt?.questions.first?.options.first?.description == "Answer directly in the island")

        try await observer.send(
            .answerQuestion(
                sessionID: "opencode-question-1",
                response: QuestionPromptResponse(answer: "Inline choices")
            )
        )

        let activityEvent = try await nextEvent(from: &iterator)
        let response = try await responseTask

        #expect(activityEvent.activityUpdate?.summary == "Answered: Inline choices")
        #expect(response == .openCodeHookDirective(.answer(text: "Inline choices")))
    }

    @Test
    func codexPreToolUseWaitsForApprovalAndReturnsDenyDirective() async throws {
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
            sessionID: "codex-session-1",
            transcriptPath: nil,
            turnID: "turn-1",
            toolName: "Bash",
            toolUseID: "tool-use-1",
            toolInput: CodexHookToolInput(command: "rm -rf build")
        )

        async let responseTask = sendOnGCDThread(.processCodexHook(payload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let startedEvent = try await nextEvent(from: &iterator)
        let permissionEvent = try await nextEvent(from: &iterator)

        #expect(startedEvent.isSessionStarted)
        #expect(permissionEvent.isPermissionRequested)

        try await observer.send(
            .resolvePermission(
                sessionID: "codex-session-1",
                resolution: .deny(message: "Use the project cleanup script instead.")
            )
        )

        let response = try await responseTask
        #expect(response == .codexHookDirective(.deny(reason: "Use the project cleanup script instead.")))
    }

    @Test
    func codexPermissionRequestReturnsAllowDirectiveAfterApproval() async throws {
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
            hookEventName: .permissionRequest,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "codex-permission-allow",
            transcriptPath: nil,
            turnID: "turn-1",
            toolName: "apply_patch",
            toolUseID: "tool-use-1",
            toolInput: CodexHookToolInput(description: "Apply a focused patch to Sources/App.swift")
        )

        async let responseTask = sendOnGCDThread(.processCodexHook(payload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let startedEvent = try await nextEvent(from: &iterator)
        let permissionEvent = try await nextEvent(from: &iterator)

        #expect(startedEvent.isSessionStarted)
        guard case let .permissionRequested(permission) = permissionEvent else {
            Issue.record("Expected Codex permission request")
            return
        }
        #expect(permission.request.title == "Apply code patch")
        #expect(permission.request.summary == "Apply a focused patch to Sources/App.swift")
        #expect(permission.request.toolName == "apply_patch")
        #expect(permission.request.toolUseID == "tool-use-1")

        try await observer.send(.resolvePermission(sessionID: "codex-permission-allow", resolution: .allowOnce()))

        let activityEvent = try await nextEvent(from: &iterator)
        let response = try await responseTask

        #expect(activityEvent.activityUpdate?.summary == "Permission approved. Codex continued the tool.")
        #expect(response == .codexHookDirective(.permissionRequest(.allow)))
    }

    @Test
    func codexPermissionRequestReturnsDenyDirectiveAfterRejection() async throws {
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
            hookEventName: .permissionRequest,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "codex-permission-deny",
            transcriptPath: nil,
            turnID: "turn-1",
            toolName: "Bash",
            toolUseID: "tool-use-2",
            toolInput: CodexHookToolInput(
                command: "rm -rf build",
                description: "Run a cleanup command"
            )
        )

        async let responseTask = sendOnGCDThread(.processCodexHook(payload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        _ = try await nextEvent(from: &iterator)
        let permissionEvent = try await nextEvent(from: &iterator)

        guard case let .permissionRequested(permission) = permissionEvent else {
            Issue.record("Expected Codex permission request")
            return
        }
        #expect(permission.request.title == "Run Bash command")
        #expect(permission.request.summary == "Run a cleanup command")
        #expect(permission.request.affectedPath == "rm -rf build")

        try await observer.send(
            .resolvePermission(
                sessionID: "codex-permission-deny",
                resolution: .deny(message: "Use the project cleanup script instead.")
            )
        )

        let completedEvent = try await nextEvent(from: &iterator)
        let response = try await responseTask

        guard case let .sessionCompleted(completed) = completedEvent else {
            Issue.record("Expected Codex completion after denial")
            return
        }
        #expect(completed.summary == "Use the project cleanup script instead.")
        #expect(
            response == .codexHookDirective(
                .permissionRequest(.deny(message: "Use the project cleanup script instead."))
            )
        )
    }

    @Test
    func codexPreToolUseStillRequiresResolutionWhenHookArrivesInDontAskMode() async throws {
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
            permissionMode: .dontAsk,
            sessionID: "codex-session-no-ask",
            terminalApp: "Ghostty",
            terminalSessionID: "ghostty-session-1",
            transcriptPath: nil,
            turnID: "turn-1",
            toolName: "Bash",
            toolUseID: "tool-use-1",
            toolInput: CodexHookToolInput(command: "ls")
        )

        async let responseTask = sendOnGCDThread(.processCodexHook(payload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let startedEvent = try await nextEvent(from: &iterator)
        let permissionEvent = try await nextEvent(from: &iterator)

        #expect(startedEvent.isSessionStarted)
        #expect(permissionEvent.isPermissionRequested)

        try await observer.send(.resolvePermission(sessionID: "codex-session-no-ask", resolution: .allowOnce()))

        let activityEvent = try await nextEvent(from: &iterator)
        let response = try await responseTask

        #expect(activityEvent.activityUpdate?.summary == "Permission approved. Codex continued the command.")
        #expect(response == .acknowledged)
    }

    @Test
    func codexHookUpdatesJumpTargetWhenLaterHooksLearnMoreAboutTheTerminal() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let startedPayload = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "codex-session-jump",
            terminalApp: "Terminal",
            transcriptPath: nil
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(startedPayload))

        let updatedPayload = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .userPromptSubmit,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "codex-session-jump",
            terminalApp: "Ghostty",
            terminalSessionID: "ghostty-terminal-42",
            terminalTitle: "codex ~/tmp/worktree",
            transcriptPath: nil,
            prompt: "inspect the auth flow"
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(updatedPayload))

        var iterator = stream.makeAsyncIterator()
        let startedEvent = try await nextEvent(from: &iterator)
        let jumpTargetEvent = try await nextEvent(from: &iterator)
        let metadataEvent = try await nextEvent(from: &iterator)
        let activityEvent = try await nextEvent(from: &iterator)

        #expect(startedEvent.isSessionStarted)
        #expect(jumpTargetEvent.jumpTargetUpdate?.jumpTarget.terminalApp == "Ghostty")
        #expect(jumpTargetEvent.jumpTargetUpdate?.jumpTarget.terminalSessionID == "ghostty-terminal-42")
        #expect(metadataEvent.trackedMetadataUpdate?.codexMetadata.lastUserPrompt == "inspect the auth flow")
        #expect(activityEvent.activityUpdate?.summary == "Prompt: inspect the auth flow")
    }

    @Test
    func cursorHookPreservesToolMetadataAcrossNonStopEvents() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCursorHook(CursorHookPayload(
            hookEventName: .beforeReadFile,
            conversationId: "cursor-preserve-metadata",
            generationId: "gen-read-1",
            workspaceRoots: ["/tmp/cursor-preserve-metadata"],
            toolName: "ReadFile",
            toolInput: "{\"path\":\"README.md\"}",
            filePath: "/tmp/cursor-preserve-metadata/README.md",
            model: "gpt-5-codex",
            transcriptPath: "/tmp/cursor-preserve-metadata/transcript.jsonl"
        )))

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCursorHook(CursorHookPayload(
            hookEventName: .beforeSubmitPrompt,
            conversationId: "cursor-preserve-metadata",
            generationId: "gen-prompt-2",
            workspaceRoots: ["/tmp/cursor-preserve-metadata"],
            prompt: "Please continue with test coverage."
        )))

        var iterator = stream.makeAsyncIterator()
        let e1 = try await nextEvent(from: &iterator)
        let e2 = try await nextEvent(from: &iterator)
        let e3 = try await nextEvent(from: &iterator)
        let e4 = try await nextEvent(from: &iterator)

        #expect(e1.isSessionStarted)
        #expect(e2.activityUpdate != nil)
        let metadata = e3.cursorMetadataUpdate
        #expect(metadata?.cursorMetadata.initialUserPrompt == "Please continue with test coverage.")
        #expect(metadata?.cursorMetadata.currentTool == "ReadFile")
        #expect(metadata?.cursorMetadata.model == "gpt-5-codex")
        #expect(metadata?.cursorMetadata.transcriptPath == "/tmp/cursor-preserve-metadata/transcript.jsonl")
        #expect(e4.activityUpdate != nil)
    }

    @Test
    func cursorStopClearsCurrentToolMetadata() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCursorHook(CursorHookPayload(
            hookEventName: .beforeSubmitPrompt,
            conversationId: "cursor-stop-clear",
            generationId: "gen-shell-1",
            workspaceRoots: ["/tmp/cursor-stop-clear"],
            prompt: "Run lint and summarize warnings.",
            command: "swift test",
            toolName: "Bash",
            toolInput: "swift test",
            model: "gpt-5-codex",
            transcriptPath: "/tmp/cursor-stop-clear/transcript.jsonl"
        )))

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCursorHook(CursorHookPayload(
            hookEventName: .stop,
            conversationId: "cursor-stop-clear",
            generationId: "gen-stop-2",
            workspaceRoots: ["/tmp/cursor-stop-clear"],
            status: "completed"
        )))

        var iterator = stream.makeAsyncIterator()
        let e1 = try await nextEvent(from: &iterator)
        let e2 = try await nextEvent(from: &iterator)
        let e3 = try await nextEvent(from: &iterator)
        let e4 = try await nextEvent(from: &iterator)

        #expect(e1.isSessionStarted)
        #expect(e2.activityUpdate != nil)
        let metadata = e3.cursorMetadataUpdate
        #expect(metadata?.cursorMetadata.currentTool == nil)
        #expect(metadata?.cursorMetadata.currentToolInputPreview == nil)
        #expect(metadata?.cursorMetadata.currentCommandPreview == nil)
        #expect(metadata?.cursorMetadata.lastUserPrompt == "Run lint and summarize warnings.")
        #expect(metadata?.cursorMetadata.model == "gpt-5-codex")
        #expect(e4.sessionCompleted?.sessionID == "cursor-stop-clear")
        #expect(e4.sessionCompleted?.summary == "Cursor completed the turn.")
    }

    @Test
    func codexHookInstallerMergesManagedGroupsWithoutDroppingUnrelatedHooks() throws {
        let existing = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/usr/bin/true",
                    "statusMessage": "Other hook"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)

        let mutation = try CodexHookInstaller.installHooksJSON(
            existingData: existing,
            hookCommand: "'/tmp/OpenIslandHooks'"
        )

        #expect(mutation.changed)
        let root = try jsonObject(from: mutation.contents)
        let hooks = root["hooks"] as? [String: Any]
        let stopGroups = hooks?["Stop"] as? [[String: Any]]
        let stopCommands = stopGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String } ?? []
        let managedStopHook = stopGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .first(where: { $0["command"] as? String == "'/tmp/OpenIslandHooks'" })

        #expect(stopCommands.contains("/usr/bin/true"))
        #expect(stopCommands.contains("'/tmp/OpenIslandHooks'"))
        #expect(managedStopHook?["statusMessage"] == nil)

        let sessionStartGroups = hooks?["SessionStart"] as? [[String: Any]]
        let permissionGroups = hooks?["PermissionRequest"] as? [[String: Any]]
        let managedPermissionHook = permissionGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .first(where: { $0["command"] as? String == "'/tmp/OpenIslandHooks'" })
        #expect(sessionStartGroups?.contains(where: { $0["matcher"] as? String == "startup|resume" }) == true)
        #expect(managedPermissionHook?["timeout"] as? Int == CodexHookInstaller.managedInteractiveTimeout)
        #expect(hooks?["PreToolUse"] == nil)
        #expect(hooks?["PostToolUse"] == nil)
    }

    @Test
    func codexHookInstallerInstallReplacesLegacyOpenIslandCommands() throws {
        let existing = """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/Users/test/.open-island/bin/open-island-bridge' --source codex"
                  },
                  {
                    "type": "command",
                    "command": "/usr/bin/printf"
                  }
                ]
              }
            ],
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/Users/test/.open-island/bin/open-island-bridge' --source codex"
                  },
                  {
                    "type": "command",
                    "command": "'/tmp/old-debug/OpenIslandHooks'"
                  },
                  {
                    "type": "command",
                    "command": "/usr/bin/true"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)

        let mutation = try CodexHookInstaller.installHooksJSON(
            existingData: existing,
            hookCommand: "'/tmp/new-release/OpenIslandHooks'"
        )

        #expect(mutation.changed)

        let root = try jsonObject(from: mutation.contents)
        let hooks = root["hooks"] as? [String: Any]
        let preToolGroups = hooks?["PreToolUse"] as? [[String: Any]]
        let preToolCommands = preToolGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String } ?? []
        let stopGroups = hooks?["Stop"] as? [[String: Any]]
        let stopCommands = stopGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String } ?? []
        let permissionGroups = hooks?["PermissionRequest"] as? [[String: Any]]
        let permissionCommands = permissionGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String } ?? []

        #expect(preToolCommands == ["/usr/bin/printf"])
        #expect(permissionCommands == ["'/tmp/new-release/OpenIslandHooks'"])
        #expect(hooks?["PostToolUse"] == nil)
        #expect(stopCommands.contains("/usr/bin/true"))
        #expect(stopCommands.contains("'/tmp/new-release/OpenIslandHooks'"))
        #expect(!stopCommands.contains("'/Users/test/.open-island/bin/open-island-bridge' --source codex"))
        #expect(!stopCommands.contains("'/tmp/old-debug/OpenIslandHooks'"))
    }

    @Test
    func codexHookInstallerUninstallRemovesOnlyManagedHooks() throws {
        let existing = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/tmp/OpenIslandHooks'",
                    "statusMessage": "Managed by Open Island"
                  },
                  {
                    "type": "command",
                    "command": "/usr/bin/true",
                    "statusMessage": "Other hook"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)

        let mutation = try CodexHookInstaller.uninstallHooksJSON(
            existingData: existing,
            managedCommand: "'/tmp/OpenIslandHooks'"
        )

        #expect(mutation.changed)
        #expect(mutation.hasRemainingHooks)

        let root = try jsonObject(from: mutation.contents)
        let hooks = root["hooks"] as? [String: Any]
        let stopGroups = hooks?["Stop"] as? [[String: Any]]
        let stopCommands = stopGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String } ?? []

        #expect(stopCommands == ["/usr/bin/true"])
    }

    @Test
    func codexHookInstallerEnablesAndRemovesFeatureFlag() {
        let initialConfig = """
        personality = "pragmatic"

        [projects."/tmp"]
        trust_level = "trusted"
        """

        let enabled = CodexHookInstaller.enableCodexHooksFeature(in: initialConfig)
        #expect(enabled.changed)
        #expect(enabled.featureEnabledByInstaller)
        #expect(enabled.contents.contains("[features]"))
        #expect(enabled.contents.contains("hooks = true"))
        #expect(!enabled.contents.contains("codex_hooks = true"))

        let removed = CodexHookInstaller.disableCodexHooksFeatureIfManaged(in: enabled.contents)
        #expect(removed.changed)
        #expect(!removed.contents.contains("hooks = true"))
    }

    @Test
    func codexHookInstallerMigratesLegacyFeatureFlag() {
        let legacyConfig = """
        [features]
        codex_hooks = true
        """

        let enabled = CodexHookInstaller.enableCodexHooksFeature(in: legacyConfig)
        #expect(enabled.changed)
        #expect(!enabled.featureEnabledByInstaller)
        #expect(enabled.contents.contains("hooks = true"))
        #expect(!enabled.contents.contains("codex_hooks = true"))
    }

    @Test
    func codexHookInstallerCanUseLegacyFeatureFlagForOlderCodex() {
        let initialConfig = """
        model = "gpt-5-codex"
        """

        let enabled = CodexHookInstaller.enableCodexHooksFeature(in: initialConfig, preferredKey: .legacy)
        #expect(enabled.changed)
        #expect(enabled.featureEnabledByInstaller)
        #expect(enabled.contents.contains("[features]"))
        let enabledLines = enabled.contents.components(separatedBy: "\n")
        #expect(enabledLines.contains("codex_hooks = true"))
        #expect(!enabledLines.contains("hooks = true"))
    }

    @Test
    func codexHookInstallerRemovesLegacyFlagWhenCurrentFlagExists() {
        let mixedConfig = """
        [features]
        hooks = true
        codex_hooks = true
        """

        let enabled = CodexHookInstaller.enableCodexHooksFeature(in: mixedConfig)
        #expect(enabled.changed)
        #expect(!enabled.featureEnabledByInstaller)
        #expect(enabled.contents.contains("hooks = true"))
        #expect(!enabled.contents.contains("codex_hooks = true"))
    }

    @Test
    func codexHookInstallerRecognizesCurrentAndLegacyFeatureFlags() {
        #expect(CodexHookInstaller.isCodexHooksFeatureEnabled(in: """
        [features]
        hooks = true
        """))

        #expect(CodexHookInstaller.isCodexHooksFeatureEnabled(in: """
        [features]
        hooks=true # enabled by user
        """))

        #expect(CodexHookInstaller.isCodexHooksFeatureEnabled(in: """
        [features]
        codex_hooks = true
        """))

        #expect(CodexHookInstaller.isCodexHooksFeatureEnabled(in: """
        [features]
        codex_hooks=true # legacy enabled by user
        """))

        #expect(!CodexHookInstaller.isCodexHooksFeatureEnabled(in: """
        [features]
        hooks=false # disabled by user
        """))
    }

    /// Verifies Codex hook feature detection across current, legacy, and invalid CLI output.
    @Test
    func codexHookInstallerDetectsPreferredFeatureFlagFromCodexOutput() {
        let currentFeatures = """
        plugin_hooks  under development  false
        hooks         stable             true
        """
        let legacyFeatures = """
        codex_hooks   stable             true
        shell_tool    stable             true
        """

        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromFeatureList: currentFeatures) == .current)
        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromFeatureList: legacyFeatures) == .legacy)
        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromVersionOutput: "codex-cli 0.130.0") == .current)
        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromVersionOutput: "codex-cli 0.129.0") == .legacy)
        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromFeatureList: "shell_tool stable true") == nil)
        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromVersionOutput: "not a version") == nil)
    }

    @Test
    func codexHookPayloadInfersTerminalAppFromRuntimeEnvironment() throws {
        let payload = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "session-1",
            terminalSessionID: "ghostty-frontmost",
            terminalTitle: "codex ~/tmp/other-worktree",
            transcriptPath: nil
        )

        let inferredITerm = payload.withRuntimeContext(environment: [
            "TERM_PROGRAM": "iTerm.app",
            "ITERM_SESSION_ID": "w0t0p0",
        ])
        #expect(inferredITerm.terminalApp == "iTerm")

        let inferredGhostty = payload.withRuntimeContext(environment: [
            "TERM_PROGRAM": "ghostty",
        ])
        #expect(inferredGhostty.terminalApp == "Ghostty")
        #expect(inferredGhostty.defaultJumpTarget.workingDirectory == "/tmp/worktree")
    }

    @Test
    func codexGhosttyLocatorUsedForSessionStartAndPromptButNotToolUse() {
        let locator: (String) -> (sessionID: String?, tty: String?, title: String?) = { _ in
            (sessionID: "ghostty-frontmost", tty: nil, title: "codex ~/tmp/worktree")
        }
        let env = ["TERM_PROGRAM": "ghostty"]
        let ttyProvider: () -> String? = { "/dev/ttys022" }

        let atStart = CodexHookPayload(
            cwd: "/tmp/worktree", hookEventName: .sessionStart,
            model: "gpt-5-codex", permissionMode: .default, sessionID: "s1", transcriptPath: nil
        ).withRuntimeContext(environment: env, currentTTYProvider: ttyProvider, terminalLocatorProvider: locator)

        #expect(atStart.terminalSessionID == "ghostty-frontmost")
        #expect(atStart.terminalTitle == "codex ~/tmp/worktree")

        let atPrompt = CodexHookPayload(
            cwd: "/tmp/worktree", hookEventName: .userPromptSubmit,
            model: "gpt-5-codex", permissionMode: .default, sessionID: "s1", transcriptPath: nil
        ).withRuntimeContext(environment: env, currentTTYProvider: ttyProvider, terminalLocatorProvider: locator)

        #expect(atPrompt.terminalSessionID == "ghostty-frontmost")
        #expect(atPrompt.terminalTitle == "codex ~/tmp/worktree")

        let atTool = CodexHookPayload(
            cwd: "/tmp/worktree", hookEventName: .preToolUse,
            model: "gpt-5-codex", permissionMode: .default, sessionID: "s1", transcriptPath: nil
        ).withRuntimeContext(
            environment: env, currentTTYProvider: ttyProvider,
            terminalLocatorProvider: { _ in (sessionID: "ghostty-wrong", tty: nil, title: "wrong") }
        )

        #expect(atTool.terminalSessionID == nil)
        #expect(atTool.terminalTitle == nil)
    }

    @Test
    func codexHookPayloadCarriesSessionLocatorIntoJumpTarget() {
        let payload = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "session-1",
            terminalApp: "iTerm",
            terminalSessionID: "A6C5F356-DEED-40F7-A787-AB9DADF27AD6",
            terminalTTY: "/dev/ttys022",
            terminalTitle: "codex ~/P/open-island",
            transcriptPath: nil
        )

        let jumpTarget = payload.defaultJumpTarget
        #expect(jumpTarget.terminalApp == "iTerm")
        #expect(jumpTarget.terminalSessionID == "A6C5F356-DEED-40F7-A787-AB9DADF27AD6")
        #expect(jumpTarget.terminalTTY == "/dev/ttys022")
        #expect(jumpTarget.paneTitle == "codex ~/P/open-island")
    }

    @Test
    func codexHookInstallationManagerRoundTripsInstallAndUninstall() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-tests-\(UUID().uuidString)", isDirectory: true)
        let codexDirectory = rootURL.appendingPathComponent(".codex", isDirectory: true)
        let managedHooksBinaryURL = rootURL
            .appendingPathComponent("managed", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")
        let manager = CodexHookInstallationManager(
            codexDirectory: codexDirectory,
            managedHooksBinaryURL: managedHooksBinaryURL
        )
        let hooksBinaryURL = rootURL
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("VibeIslandHooks")

        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: hooksBinaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("codex-hook".utf8).write(to: hooksBinaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hooksBinaryURL.path)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let installed = try manager.install(hooksBinaryURL: hooksBinaryURL)
        #expect(installed.featureFlagEnabled)
        #expect(installed.managedHooksPresent)
        #expect(installed.hooksBinaryURL?.path == managedHooksBinaryURL.standardizedFileURL.path)
        #expect(installed.manifest?.hookCommand == CodexHookInstaller.hookCommand(for: managedHooksBinaryURL.path))
        #expect(FileManager.default.isExecutableFile(atPath: managedHooksBinaryURL.path))
        #expect(try Data(contentsOf: managedHooksBinaryURL) == Data("codex-hook".utf8))
        let hooksData = try Data(contentsOf: installed.hooksURL)
        let installedHooks = try jsonObject(from: hooksData)
        let installedStopGroups = (installedHooks["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        let installedManagedHook = installedStopGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .first(where: { $0["command"] as? String == CodexHookInstaller.hookCommand(for: managedHooksBinaryURL.path) })
        #expect(installedManagedHook?["statusMessage"] == nil)

        try FileManager.default.removeItem(at: hooksBinaryURL)

        let reloaded = try manager.status()
        #expect(reloaded.managedHooksPresent)
        #expect(reloaded.featureFlagEnabled)
        #expect(reloaded.hooksBinaryURL?.path == managedHooksBinaryURL.standardizedFileURL.path)

        let uninstalled = try manager.uninstall()
        #expect(!uninstalled.managedHooksPresent)
        #expect(!FileManager.default.fileExists(atPath: uninstalled.manifestURL.path))
    }

    @Test
    func jumpTargetRoundTripsWarpPaneUUIDThroughCodable() throws {
        let target = JumpTarget(
            terminalApp: "Warp",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            warpPaneUUID: "D1A5DF3027E44FC080FE2656FAF2BA2E"
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(JumpTarget.self, from: data)
        #expect(decoded.warpPaneUUID == "D1A5DF3027E44FC080FE2656FAF2BA2E")

        // And: legacy JSON without the field decodes to nil
        let legacyJSON = """
        {"terminalApp":"Warp","workspaceName":"demo","paneTitle":"Claude demo","workingDirectory":"/tmp/demo"}
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(JumpTarget.self, from: legacyJSON)
        #expect(legacy.warpPaneUUID == nil)
    }

    @Test
    func firstSeenAtIsWrittenOnceAndPreservedAcrossSubsequentEvents() {
        let t0 = Date(timeIntervalSince1970: 10_000)
        var state = SessionState()
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "s-1",
            title: "First boot",
            tool: .claudeCode,
            summary: "Starting",
            timestamp: t0
        )))

        #expect(state.session(id: "s-1")?.firstSeenAt == t0)

        // A repeated sessionStarted (e.g. hook reconnect) must preserve the
        // original firstSeenAt even though the payload timestamp is later.
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "s-1",
            title: "Re-attached",
            tool: .claudeCode,
            summary: "Reattached",
            timestamp: t0.addingTimeInterval(120)
        )))
        #expect(state.session(id: "s-1")?.firstSeenAt == t0)
        #expect(state.session(id: "s-1")?.updatedAt == t0.addingTimeInterval(120))

        // Activity updates leave firstSeenAt untouched.
        state.apply(.activityUpdated(SessionActivityUpdated(
            sessionID: "s-1",
            summary: "Working",
            phase: .running,
            timestamp: t0.addingTimeInterval(240)
        )))
        #expect(state.session(id: "s-1")?.firstSeenAt == t0)
    }

    @Test
    func firstSeenAtPersistsThroughRegistryRoundTrip() throws {
        let t0 = Date(timeIntervalSince1970: 20_000)
        let session = AgentSession(
            id: "claude-1",
            title: "Repo",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            updatedAt: t0.addingTimeInterval(60),
            firstSeenAt: t0
        )
        let record = ClaudeTrackedSessionRecord(session: session)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeTrackedSessionRecord.self, from: data)

        #expect(decoded.firstSeenAt == t0)
        #expect(decoded.session.firstSeenAt == t0)

        // Legacy records without firstSeenAt decode cleanly and fall back to
        // updatedAt on the restored AgentSession.
        let legacyJSON = """
        {
          "attachmentState": "stale",
          "phase": "running",
          "sessionID": "claude-legacy",
          "summary": "Legacy",
          "title": "Legacy",
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let legacy = try decoder.decode(ClaudeTrackedSessionRecord.self, from: legacyJSON)
        #expect(legacy.firstSeenAt == nil)
        let legacyUpdated = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")
        #expect(legacy.session.firstSeenAt == legacyUpdated)
    }
}

private enum SessionStateTestError: Error {
    case streamEnded
}

private func nextEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
) async throws -> AgentEvent {
    guard let event = try await iterator.next() else {
        throw SessionStateTestError.streamEnded
    }

    return event
}

private extension AgentEvent {
    var isSessionStarted: Bool {
        if case .sessionStarted = self {
            true
        } else {
            false
        }
    }

    var isPermissionRequested: Bool {
        if case .permissionRequested = self {
            true
        } else {
            false
        }
    }

    var questionPrompt: QuestionPrompt? {
        if case let .questionAsked(payload) = self {
            payload.prompt
        } else {
            nil
        }
    }

    var activityUpdate: SessionActivityUpdated? {
        if case let .activityUpdated(payload) = self {
            payload
        } else {
            nil
        }
    }

    var jumpTargetUpdate: JumpTargetUpdated? {
        if case let .jumpTargetUpdated(payload) = self {
            payload
        } else {
            nil
        }
    }

    var trackedMetadataUpdate: SessionMetadataUpdated? {
        if case let .sessionMetadataUpdated(payload) = self {
            payload
        } else {
            nil
        }
    }

    var cursorMetadataUpdate: CursorSessionMetadataUpdated? {
        if case let .cursorSessionMetadataUpdated(payload) = self {
            payload
        } else {
            nil
        }
    }

    var sessionCompleted: SessionCompleted? {
        if case let .sessionCompleted(payload) = self {
            payload
        } else {
            nil
        }
    }
}

private func jsonObject(from data: Data?) throws -> [String: Any] {
    guard let data else {
        return [:]
    }

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
