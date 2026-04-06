import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

struct SessionStateTests {
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

        try await observer.send(.resolvePermission(sessionID: "codex-session-1", resolution: .deny()))

        let response = try await responseTask
        #expect(response == .codexHookDirective(.deny(reason: "Permission denied in Open Island.")))
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
        let preToolGroups = hooks?["PreToolUse"] as? [[String: Any]]
        let preToolCommands = preToolGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String } ?? []
        #expect(sessionStartGroups?.contains(where: { $0["matcher"] as? String == "startup|resume" }) == true)
        #expect(preToolCommands.contains("'/tmp/OpenIslandHooks'"))
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

        #expect(preToolCommands.contains("/usr/bin/printf"))
        #expect(preToolCommands.contains("'/tmp/new-release/OpenIslandHooks'"))
        #expect(hooks?["PostToolUse"] == nil)
        #expect(stopCommands.contains("/usr/bin/true"))
        #expect(stopCommands.contains("'/tmp/new-release/OpenIslandHooks'"))
        #expect(!stopCommands.contains("'/Users/test/.open-island/bin/open-island-bridge' --source codex"))
        #expect(!stopCommands.contains("'/tmp/old-debug/OpenIslandHooks'"))
    }

    @Test
    func codexHookInstallerRequiredHooksCheckFailsWithoutPreToolUse() throws {
        let missingPreToolUse = """
        {
          "hooks": {
            "SessionStart": [
              {
                "matcher": "startup|resume",
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/tmp/OpenIslandHooks'"
                  }
                ]
              }
            ],
            "UserPromptSubmit": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/tmp/OpenIslandHooks'"
                  }
                ]
              }
            ],
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/tmp/OpenIslandHooks'"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)

        let hasRequiredHooks = try CodexHookInstaller.hasRequiredManagedHooks(
            existingData: missingPreToolUse,
            managedCommand: "'/tmp/OpenIslandHooks'"
        )

        #expect(!hasRequiredHooks)
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
        #expect(enabled.contents.contains("codex_hooks = true"))

        let removed = CodexHookInstaller.disableCodexHooksFeatureIfManaged(in: enabled.contents)
        #expect(removed.changed)
        #expect(!removed.contents.contains("codex_hooks = true"))
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
