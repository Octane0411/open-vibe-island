import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeHooksTests {
    @Test
    func claudeHookOutputEncoderEncodesPermissionDecision() throws {
        let output = try ClaudeHookOutputEncoder.standardOutput(
            for: .claudeHookDirective(
                .permissionRequest(
                    .deny(message: "Permission denied in Open Island.", interrupt: true)
                )
            )
        )

        let payload = try #require(output)
        let object = try jsonObject(from: payload)
        let hookSpecificOutput = object["hookSpecificOutput"] as? [String: Any]
        let decision = hookSpecificOutput?["decision"] as? [String: Any]

        #expect(hookSpecificOutput?["hookEventName"] as? String == "PermissionRequest")
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] as? String == "Permission denied in Open Island.")
        #expect(decision?["interrupt"] as? Bool == true)
    }

    @Test
    func claudeHookInstallationManagerRoundTripsInstallAndUninstall() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-hooks-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let managedHooksBinaryURL = rootURL
            .appendingPathComponent("managed", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")
        let manager = ClaudeHookInstallationManager(
            claudeDirectory: claudeDirectory,
            managedHooksBinaryURL: managedHooksBinaryURL
        )
        let hooksBinaryURL = rootURL
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("VibeIslandHooks")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: hooksBinaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("claude-hook".utf8).write(to: hooksBinaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hooksBinaryURL.path)

        let installed = try manager.install(hooksBinaryURL: hooksBinaryURL)
        #expect(installed.managedHooksPresent)
        #expect(installed.hooksBinaryURL?.path == managedHooksBinaryURL.standardizedFileURL.path)
        #expect(installed.manifest?.hookCommand == ClaudeHookInstaller.hookCommand(for: managedHooksBinaryURL.path))
        #expect(!installed.hasClaudeIslandHooks)
        #expect(FileManager.default.isExecutableFile(atPath: managedHooksBinaryURL.path))
        #expect(try Data(contentsOf: managedHooksBinaryURL) == Data("claude-hook".utf8))

        let settingsObject = try jsonObject(from: Data(contentsOf: installed.settingsURL))
        let hooksObject = settingsObject["hooks"] as? [String: Any]
        #expect(hooksObject?["PermissionRequest"] != nil)
        #expect(hooksObject?["PreToolUse"] != nil)
        #expect(hooksObject?["UserPromptSubmit"] != nil)

        try FileManager.default.removeItem(at: hooksBinaryURL)

        let reloaded = try manager.status()
        #expect(reloaded.managedHooksPresent)
        #expect(reloaded.hooksBinaryURL?.path == managedHooksBinaryURL.standardizedFileURL.path)

        let uninstalled = try manager.uninstall()
        #expect(!uninstalled.managedHooksPresent)
        #expect(!FileManager.default.fileExists(atPath: uninstalled.manifestURL.path))
    }

    @Test
    func claudeTranscriptDiscoveryRecoversRecentSessions() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-discovery-\(UUID().uuidString)", isDirectory: true)
        let workspaceDirectory = rootURL
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-tmp-demo-repo", isDirectory: true)
        let transcriptURL = workspaceDirectory
            .appendingPathComponent("session-123.jsonl")
        let discovery = ClaudeTranscriptDiscovery(rootURL: rootURL.appendingPathComponent("projects", isDirectory: true))

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        let transcript = """
        {"cwd":"/tmp/demo-repo","sessionId":"session-123","type":"user","message":{"role":"user","content":"Fix the flaky auth tests."},"timestamp":"2026-04-03T03:20:00Z"}
        {"cwd":"/tmp/demo-repo","sessionId":"session-123","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"I’m checking the auth test setup now."},{"type":"tool_use","id":"toolu_1","name":"Glob","input":{"pattern":"**/*auth*.test.ts"}}]},"timestamp":"2026-04-03T03:20:02Z"}
        {"cwd":"/tmp/demo-repo","sessionId":"session-123","type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"auth.test.ts"}]},"timestamp":"2026-04-03T03:20:04Z"}
        {"cwd":"/tmp/demo-repo","sessionId":"session-123","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"Found the failing auth test file."}]},"timestamp":"2026-04-03T03:20:06Z"}
        """
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let sessions = discovery.discoverRecentSessions(
            now: ISO8601DateFormatter().date(from: "2026-04-03T03:20:10Z")!
        )

        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.id == "session-123")
        #expect(session.tool == .claudeCode)
        #expect(session.title == "Claude · demo-repo")
        #expect(session.summary == "Found the failing auth test file.")
        #expect(session.claudeMetadata?.initialUserPrompt == "Fix the flaky auth tests.")
        #expect(session.claudeMetadata?.lastAssistantMessage == "Found the failing auth test file.")
        #expect(session.claudeMetadata?.currentTool == nil)
        #expect(
            URL(fileURLWithPath: session.claudeMetadata?.transcriptPath ?? "").standardizedFileURL.path
                == transcriptURL.standardizedFileURL.path
        )
    }

    @Test
    func claudeTranscriptDiscoveryStreamsTranscriptsLargerThanReadChunk() throws {
        // Pins streaming behavior across read-chunk boundaries. The
        // pre-fix `parseSession` used `String(contentsOf:)` which on
        // heavy Claude users (multi-hundred-MB transcripts) produced
        // multi-GB startup peaks. The streamed reader must still
        // recover the same final state when meaningful events sit
        // beyond the first 64 KB chunk.
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-discovery-stream-\(UUID().uuidString)", isDirectory: true)
        let workspaceDirectory = rootURL
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-tmp-demo-repo", isDirectory: true)
        let transcriptURL = workspaceDirectory.appendingPathComponent("session-large.jsonl")

        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)

        let header = """
        {"cwd":"/tmp/demo-repo","sessionId":"session-large","type":"user","message":{"role":"user","content":"Initial prompt for the streamed transcript."},"timestamp":"2026-04-03T03:20:00Z"}
        """

        // Build a padded assistant message that, repeated many times,
        // overshoots the 64 KB chunk boundary. The final assistant
        // message must be recovered as the session summary.
        let padding = String(repeating: "x", count: 256)
        var lines: [String] = [header]
        for index in 0..<400 {
            lines.append("""
            {"cwd":"/tmp/demo-repo","sessionId":"session-large","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"padding \(index) \(padding)"}]},"timestamp":"2026-04-03T03:20:01Z"}
            """)
        }
        lines.append("""
        {"cwd":"/tmp/demo-repo","sessionId":"session-large","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"Streamed the large transcript end-to-end."}]},"timestamp":"2026-04-03T03:20:99Z"}
        """)

        let body = lines.joined(separator: "\n").appending("\n")
        try body.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let fileSize = (try FileManager.default.attributesOfItem(atPath: transcriptURL.path)[.size] as? Int) ?? 0
        #expect(fileSize > 64 * 1_024)

        let discovery = ClaudeTranscriptDiscovery(rootURL: rootURL.appendingPathComponent("projects", isDirectory: true))
        let sessions = discovery.discoverRecentSessions(
            now: ISO8601DateFormatter().date(from: "2026-04-03T03:21:00Z")!
        )

        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.id == "session-large")
        #expect(session.summary == "Streamed the large transcript end-to-end.")
        #expect(session.claudeMetadata?.initialUserPrompt == "Initial prompt for the streamed transcript.")
        #expect(session.claudeMetadata?.lastAssistantMessage == "Streamed the large transcript end-to-end.")
    }

    @Test
    func claudeTranscriptDiscoveryHandlesTrailingLineWithoutNewline() throws {
        // If Claude is killed mid-flush the final transcript line can
        // land on disk without a trailing newline. The streamed reader
        // must still surface it rather than dropping it like a naive
        // split would.
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-discovery-trailing-\(UUID().uuidString)", isDirectory: true)
        let workspaceDirectory = rootURL
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-tmp-demo-repo", isDirectory: true)
        let transcriptURL = workspaceDirectory.appendingPathComponent("session-trailing.jsonl")

        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)

        let lines = [
            """
            {"cwd":"/tmp/demo-repo","sessionId":"session-trailing","type":"user","message":{"role":"user","content":"Trailing line check."},"timestamp":"2026-04-03T03:20:00Z"}
            """,
            """
            {"cwd":"/tmp/demo-repo","sessionId":"session-trailing","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"Final line without newline."}]},"timestamp":"2026-04-03T03:20:02Z"}
            """,
        ]

        // Deliberately omit the trailing "\n".
        try lines.joined(separator: "\n").write(to: transcriptURL, atomically: true, encoding: .utf8)

        let discovery = ClaudeTranscriptDiscovery(rootURL: rootURL.appendingPathComponent("projects", isDirectory: true))
        let sessions = discovery.discoverRecentSessions(
            now: ISO8601DateFormatter().date(from: "2026-04-03T03:20:10Z")!
        )

        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.id == "session-trailing")
        #expect(session.claudeMetadata?.lastAssistantMessage == "Final line without newline.")
    }

    @Test
    func claudeGhosttyLocatorUsedForSessionStartAndPromptButNotToolUse() {
        let locator: (String) -> (sessionID: String?, tty: String?, title: String?) = { _ in
            (sessionID: "ghostty-frontmost", tty: nil, title: "claude ~/tmp/worktree")
        }
        let env = ["TERM_PROGRAM": "ghostty"]
        let ttyProvider: () -> String? = { "/dev/ttys031" }

        // SessionStart: locator IS used.
        let atStart = ClaudeHookPayload(
            cwd: "/tmp/worktree", hookEventName: .sessionStart, sessionID: "s1"
        ).withRuntimeContext(environment: env, currentTTYProvider: ttyProvider, terminalLocatorProvider: locator)

        #expect(atStart.terminalSessionID == "ghostty-frontmost")
        #expect(atStart.terminalTitle == "claude ~/tmp/worktree")

        // UserPromptSubmit: locator IS used (user just typed, terminal is focused).
        let atPrompt = ClaudeHookPayload(
            cwd: "/tmp/worktree", hookEventName: .userPromptSubmit, sessionID: "s1"
        ).withRuntimeContext(environment: env, currentTTYProvider: ttyProvider, terminalLocatorProvider: locator)

        #expect(atPrompt.terminalSessionID == "ghostty-frontmost")
        #expect(atPrompt.terminalTitle == "claude ~/tmp/worktree")

        // PreToolUse: locator NOT used, values cleared.
        let atTool = ClaudeHookPayload(
            cwd: "/tmp/worktree", hookEventName: .preToolUse, sessionID: "s1",
            terminalSessionID: "ghostty-frontmost", terminalTitle: "claude ~/tmp/worktree"
        ).withRuntimeContext(
            environment: env, currentTTYProvider: ttyProvider,
            terminalLocatorProvider: { _ in (sessionID: "ghostty-wrong", tty: nil, title: "wrong") }
        )

        #expect(atTool.terminalSessionID == nil)
        #expect(atTool.terminalTitle == nil)
    }

    @Test
    func claudeInferTerminalAppRecognizesWarpViaEnvVar() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        ).withRuntimeContext(
            environment: ["WARP_IS_LOCAL_SHELL_SESSION": "1"],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) }
        )

        #expect(payload.terminalApp == "Warp")
    }

    @Test
    func claudeInferTerminalAppRecognizesWarpViaTermProgram() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        ).withRuntimeContext(
            environment: ["TERM_PROGRAM": "WarpTerminal"],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) }
        )

        #expect(payload.terminalApp == "Warp")
    }

    @Test
    func claudeInferTerminalAppPrefersWarpOverLeakedGhosttyEnvVars() {
        // Regression: launching Warp from a Ghostty tab leaks
        // GHOSTTY_RESOURCES_DIR (and friends) into every Warp shell via
        // macOS GUI app environment inheritance. The previous env-var-first
        // ordering tagged those Warp shells as Ghostty, causing
        // terminalLocator to query Ghostty's focused tab and stamp a
        // foreign Ghostty pane onto the Warp session's jumpTarget.
        // TERM_PROGRAM is the only signal that doesn't leak this way and
        // must dominate per-app env vars.
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        ).withRuntimeContext(
            environment: [
                "TERM_PROGRAM": "WarpTerminal",
                "WARP_IS_LOCAL_SHELL_SESSION": "1",
                "GHOSTTY_RESOURCES_DIR": "/Applications/Ghostty.app/Contents/Resources/ghostty",
                "GHOSTTY_BIN_DIR": "/Applications/Ghostty.app/Contents/MacOS",
            ],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) }
        )

        #expect(payload.terminalApp == "Warp")
    }

    @Test
    func claudeDefaultJumpTargetUsesUnknownSentinelForUnrecognizedTerminal() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        ).withRuntimeContext(
            environment: ["TERM_PROGRAM": "rio"],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) }
        )

        #expect(payload.terminalApp == nil)
        #expect(payload.defaultJumpTarget.terminalApp == "Unknown")
    }

    /// Verifies a Claude Desktop session is tagged `Claude.app` via the
    /// authoritative `CLAUDE_CODE_ENTRYPOINT=claude-desktop` signal. The
    /// desktop subprocess is TTY-less and invisible to process discovery, so
    /// this tag is what lets liveness follow the desktop app instead of a
    /// non-existent terminal process.
    @Test
    func claudeInferTerminalAppRecognizesClaudeDesktopViaEntrypoint() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        ).withRuntimeContext(
            environment: ["CLAUDE_CODE_ENTRYPOINT": "claude-desktop"],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) }
        )

        #expect(payload.terminalApp == "Claude.app")
        #expect(payload.defaultJumpTarget.terminalApp == "Claude.app")
    }

    /// Verifies the `__CFBundleIdentifier=com.anthropic.claudefordesktop`
    /// fallback also tags the session `Claude.app` — the hook binary inherits
    /// that bundle id when launched as a subprocess of Claude.app.
    @Test
    func claudeInferTerminalAppRecognizesClaudeDesktopViaBundleIdentifier() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        ).withRuntimeContext(
            environment: ["__CFBundleIdentifier": "com.anthropic.claudefordesktop"],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) }
        )

        #expect(payload.terminalApp == "Claude.app")
    }

    /// Verifies the desktop entrypoint signal wins over a leaked
    /// `TERM_PROGRAM`. Launching Claude.app from a terminal (e.g.
    /// `open -a Claude` from Ghostty) leaks the parent shell's `TERM_PROGRAM`
    /// into the subprocess env; the session must still classify as
    /// `Claude.app`, not the launching terminal.
    @Test
    func claudeInferTerminalAppPrefersClaudeDesktopOverLeakedTermProgram() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        ).withRuntimeContext(
            environment: [
                "CLAUDE_CODE_ENTRYPOINT": "claude-desktop",
                "TERM_PROGRAM": "ghostty",
            ],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) }
        )

        #expect(payload.terminalApp == "Claude.app")
    }

    @Test
    func claudePermissionRequestReturnsAllowDirectiveAfterApproval() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let toolInput: ClaudeHookJSONValue = .object(["command": .string("ls -la")])
        let preToolPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .preToolUse,
            sessionID: "claude-session-1",
            toolName: "Bash",
            toolInput: toolInput,
            toolUseID: "tool-use-1"
        )
        let permissionPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .permissionRequest,
            sessionID: "claude-session-1",
            toolName: "Bash",
            toolInput: toolInput
        )

        let preToolResponse = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(preToolPayload))
        #expect(preToolResponse == .acknowledged)

        async let responseTask = sendOnGCDThread(.processClaudeHook(permissionPayload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let permissionEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .permissionRequested = event {
                return true
            }
            return false
        }

        if case let .permissionRequested(payload) = permissionEvent {
            #expect(payload.request.toolName == "Bash")
            #expect(payload.request.toolUseID == "tool-use-1")
            #expect(payload.request.primaryActionTitle == "Allow Once")
        } else {
            Issue.record("Expected a Claude permission request event")
        }

        try await observer.send(.resolvePermission(sessionID: "claude-session-1", resolution: .allowOnce()))

        let response = try await responseTask
        guard case let .some(.claudeHookDirective(.permissionRequest(.allow(updatedInput, updatedPermissions)))) = response else {
            Issue.record("Expected an allow directive for Claude permission request")
            return
        }

        #expect(updatedPermissions.isEmpty)
        #expect(updatedInput == toolInput)
    }

    @Test
    func claudeAskUserQuestionReturnsUpdatedAnswers() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let questionToolInput: ClaudeHookJSONValue = .object([
            "questions": .array([
                .object([
                    "question": .string("Which environment?"),
                    "header": .string("Env"),
                    "options": .array([
                        option(label: "Production", description: "Use production"),
                        option(label: "Staging", description: "Use staging"),
                    ]),
                    "multiSelect": .boolean(false),
                ]),
                .object([
                    "question": .string("Which checks?"),
                    "header": .string("Checks"),
                    "options": .array([
                        option(label: "Unit tests", description: "Run unit tests"),
                        option(label: "Lint", description: "Run linter"),
                    ]),
                    "multiSelect": .boolean(true),
                ]),
            ]),
        ])

        let preToolPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .preToolUse,
            sessionID: "claude-session-question",
            toolName: "AskUserQuestion",
            toolInput: questionToolInput,
            toolUseID: "tool-use-question"
        )
        let permissionPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .permissionRequest,
            sessionID: "claude-session-question",
            toolName: "AskUserQuestion",
            toolInput: questionToolInput
        )

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(preToolPayload))

        async let responseTask = sendOnGCDThread(.processClaudeHook(permissionPayload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let questionEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .questionAsked = event {
                return true
            }
            return false
        }

        if case let .questionAsked(payload) = questionEvent {
            #expect(payload.prompt.questions.count == 2)
            #expect(payload.prompt.questions.first?.header == "Env")
        } else {
            Issue.record("Expected a Claude AskUserQuestion event")
        }

        try await observer.send(
            .answerQuestion(
                sessionID: "claude-session-question",
                response: QuestionPromptResponse(
                    answers: [
                        "Which environment?": "Staging",
                        "Which checks?": "Lint, Unit tests",
                    ]
                )
            )
        )

        let response = try await responseTask
        guard case let .some(.claudeHookDirective(.permissionRequest(.allow(updatedInput, _)))) = response,
              case let .object(root)? = updatedInput,
              case let .object(answers)? = root["answers"] else {
            Issue.record("Expected AskUserQuestion answers to round-trip through updatedInput")
            return
        }

        #expect(answers["Which environment?"] == .string("Staging"))
        #expect(answers["Which checks?"] == .string("Lint, Unit tests"))
    }

    @Test
    func claudeSubagentPermissionRequestSurfacesOnParentSession() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let parentSessionID = "claude-subagent-permission-parent"
        let subagentID = "subagent-alpha"
        let subagentType = "general-purpose"

        // Register the subagent on the parent so the card can label it.
        let subagentStartPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .subagentStart,
            sessionID: parentSessionID,
            agentID: subagentID,
            agentType: subagentType
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(subagentStartPayload))

        let toolInput: ClaudeHookJSONValue = .object(["command": .string("rm -rf /tmp/scratch")])
        let permissionPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .permissionRequest,
            sessionID: parentSessionID,
            agentID: subagentID,
            agentType: subagentType,
            toolName: "Bash",
            toolInput: toolInput,
            toolUseID: "subagent-tool-use-1"
        )

        async let responseTask = sendOnGCDThread(.processClaudeHook(permissionPayload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let permissionEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .permissionRequested = event {
                return true
            }
            return false
        }

        if case let .permissionRequested(payload) = permissionEvent {
            #expect(payload.sessionID == parentSessionID)
            #expect(payload.request.originatingAgentID == subagentID)
            #expect(payload.request.originatingAgentType == subagentType)
            #expect(payload.request.toolName == "Bash")
            #expect(payload.request.toolUseID == "subagent-tool-use-1")
        } else {
            Issue.record("Expected a subagent permission request event on the parent session")
        }

        let pendingSnapshot = server.pendingClaudeInteractionSnapshotForTests()
        #expect(pendingSnapshot.activeCount == 1)
        #expect(pendingSnapshot.queuedCount == 0)

        try await observer.send(.resolvePermission(sessionID: parentSessionID, resolution: .allowOnce()))

        let response = try await responseTask
        guard case let .some(.claudeHookDirective(.permissionRequest(.allow(updatedInput, updatedPermissions)))) = response else {
            Issue.record("Expected an allow directive routed to the subagent's hook connection")
            return
        }
        #expect(updatedPermissions.isEmpty)
        #expect(updatedInput == toolInput)

        let drainedSnapshot = server.pendingClaudeInteractionSnapshotForTests()
        #expect(drainedSnapshot.activeCount == 0)
        #expect(drainedSnapshot.queuedCount == 0)
    }

    @Test
    func claudeConcurrentSubagentPermissionRequestsAreQueuedInArrivalOrder() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let collector = AgentEventCollector()
        let collectionTask = Task {
            do { for try await event in stream { await collector.append(event) } } catch {}
        }
        defer { collectionTask.cancel() }

        let parentSessionID = "claude-subagent-queue-parent"
        let alphaToolInput: ClaudeHookJSONValue = .object(["command": .string("alpha-cmd")])
        let betaToolInput: ClaudeHookJSONValue = .object(["command": .string("beta-cmd")])

        func subagentPermissionPayload(agentID: String, toolInput: ClaudeHookJSONValue) -> ClaudeHookPayload {
            ClaudeHookPayload(
                cwd: "/tmp/worktree",
                hookEventName: .permissionRequest,
                sessionID: parentSessionID,
                agentID: agentID,
                agentType: "general-purpose",
                toolName: "Bash",
                toolInput: toolInput,
                toolUseID: "tool-use-\(agentID)"
            )
        }

        // A arrives first and becomes active; B arrives while A is active.
        async let responseTaskA = sendOnGCDThread(
            .processClaudeHook(subagentPermissionPayload(agentID: "subagent-alpha", toolInput: alphaToolInput)),
            socketURL: socketURL
        )
        let alphaEvent = try await waitForPermissionRequestedEvent(
            originatingAgentID: "subagent-alpha",
            collector: collector
        )
        #expect(alphaEvent != nil)

        async let responseTaskB = sendOnGCDThread(
            .processClaudeHook(subagentPermissionPayload(agentID: "subagent-beta", toolInput: betaToolInput)),
            socketURL: socketURL
        )

        // B must be queued, not emitted: exactly one permission request so far.
        try await Task.sleep(for: .milliseconds(60))
        let preResolveCount = await collector.snapshot().filter {
            if case .permissionRequested = $0 { return true }
            return false
        }.count
        #expect(preResolveCount == 1)

        let queuedSnapshot = server.pendingClaudeInteractionSnapshotForTests()
        #expect(queuedSnapshot.activeCount == 1)
        #expect(queuedSnapshot.queuedCount == 1)

        // Resolving A routes the directive to A's connection AND promotes B.
        try await observer.send(.resolvePermission(sessionID: parentSessionID, resolution: .allowOnce()))

        let responseA = try await responseTaskA
        guard case let .some(.claudeHookDirective(.permissionRequest(.allow(inputA, _)))) = responseA,
              inputA == alphaToolInput else {
            Issue.record("Expected A's allow directive routed to A's hook connection")
            return
        }

        let betaEvent = try await waitForPermissionRequestedEvent(
            originatingAgentID: "subagent-beta",
            collector: collector
        )
        #expect(betaEvent != nil)
        let promotedSnapshot = server.pendingClaudeInteractionSnapshotForTests()
        #expect(promotedSnapshot.activeCount == 1)
        #expect(promotedSnapshot.queuedCount == 0)

        // Resolving B routes to B's connection; the slot clears.
        try await observer.send(.resolvePermission(sessionID: parentSessionID, resolution: .deny(message: nil, interrupt: false)))

        let responseB = try await responseTaskB
        guard case .some(.claudeHookDirective(.permissionRequest(.deny))) = responseB else {
            Issue.record("Expected B's deny directive routed to B's hook connection")
            return
        }

        let drainedSnapshot = server.pendingClaudeInteractionSnapshotForTests()
        #expect(drainedSnapshot.activeCount == 0)
        #expect(drainedSnapshot.queuedCount == 0)
    }

    @Test
    func claudeSubagentAskUserQuestionIsQueuedBehindPermission() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let collector = AgentEventCollector()
        let collectionTask = Task {
            do { for try await event in stream { await collector.append(event) } } catch {}
        }
        defer { collectionTask.cancel() }

        let parentSessionID = "claude-subagent-question-parent"
        let alphaToolInput: ClaudeHookJSONValue = .object(["command": .string("alpha-cmd")])
        let questionToolInput: ClaudeHookJSONValue = .object([
            "questions": .array([
                .object([
                    "question": .string("Which environment?"),
                    "header": .string("Env"),
                    "options": .array([
                        option(label: "Production", description: "Use production"),
                        option(label: "Staging", description: "Use staging"),
                    ]),
                    "multiSelect": .boolean(false),
                ]),
            ]),
        ])

        // A: a subagent permission request (active).
        async let responseTaskA = sendOnGCDThread(
            .processClaudeHook(ClaudeHookPayload(
                cwd: "/tmp/worktree",
                hookEventName: .permissionRequest,
                sessionID: parentSessionID,
                agentID: "subagent-alpha",
                agentType: "general-purpose",
                toolName: "Bash",
                toolInput: alphaToolInput,
                toolUseID: "tool-use-alpha"
            )),
            socketURL: socketURL
        )
        let alphaEvent = try await waitForPermissionRequestedEvent(
            originatingAgentID: "subagent-alpha",
            collector: collector
        )
        #expect(alphaEvent != nil)

        // B: a subagent AskUserQuestion (queued behind A; no event yet).
        async let responseTaskB = sendOnGCDThread(
            .processClaudeHook(ClaudeHookPayload(
                cwd: "/tmp/worktree",
                hookEventName: .permissionRequest,
                sessionID: parentSessionID,
                agentID: "subagent-beta",
                agentType: "general-purpose",
                toolName: "AskUserQuestion",
                toolInput: questionToolInput,
                toolUseID: "tool-use-beta"
            )),
            socketURL: socketURL
        )

        try await Task.sleep(for: .milliseconds(60))
        let preResolveQuestionCount = await collector.snapshot().filter {
            if case .questionAsked = $0 { return true }
            return false
        }.count
        #expect(preResolveQuestionCount == 0)

        let queuedSnapshot = server.pendingClaudeInteractionSnapshotForTests()
        #expect(queuedSnapshot.activeCount == 1)
        #expect(queuedSnapshot.queuedCount == 1)

        // Resolving A promotes B: B's AskUserQuestion is now surfaced.
        try await observer.send(.resolvePermission(sessionID: parentSessionID, resolution: .allowOnce()))

        let responseA = try await responseTaskA
        guard case .some(.claudeHookDirective(.permissionRequest(.allow))) = responseA else {
            Issue.record("Expected A's allow directive routed to A's hook connection")
            return
        }

        let questionEvent = try await waitForQuestionAskedEvent(collector: collector)
        #expect(questionEvent != nil)
        #expect(questionEvent?.sessionID == parentSessionID)
        let promotedSnapshot = server.pendingClaudeInteractionSnapshotForTests()
        #expect(promotedSnapshot.activeCount == 1)
        #expect(promotedSnapshot.queuedCount == 0)

        // Answering B routes the directive to B's connection; the slot clears.
        try await observer.send(
            .answerQuestion(
                sessionID: parentSessionID,
                response: QuestionPromptResponse(answers: ["Which environment?": "Staging"])
            )
        )

        let responseB = try await responseTaskB
        guard case let .some(.claudeHookDirective(.permissionRequest(.allow(updatedInput, _)))) = responseB,
              case let .object(root)? = updatedInput,
              case let .object(answers)? = root["answers"] else {
            Issue.record("Expected B's AskUserQuestion answers to round-trip through updatedInput")
            return
        }
        #expect(answers["Which environment?"] == .string("Staging"))

        let drainedSnapshot = server.pendingClaudeInteractionSnapshotForTests()
        #expect(drainedSnapshot.activeCount == 0)
        #expect(drainedSnapshot.queuedCount == 0)
    }

    @Test
    func claudeSubagentQueuedRequestPurgedOnHookDisconnect() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let collector = AgentEventCollector()
        let collectionTask = Task {
            do { for try await event in stream { await collector.append(event) } } catch {}
        }
        defer { collectionTask.cancel() }

        let parentSessionID = "claude-subagent-disconnect-parent"

        func subagentPermissionPayload(agentID: String) -> ClaudeHookPayload {
            ClaudeHookPayload(
                cwd: "/tmp/worktree",
                hookEventName: .permissionRequest,
                sessionID: parentSessionID,
                agentID: agentID,
                agentType: "general-purpose",
                toolName: "Bash",
                toolInput: .object(["command": .string("\(agentID)-cmd")]),
                toolUseID: "tool-use-\(agentID)"
            )
        }

        // Retain the hook clients' event streams for the lifetime of the test
        // so their connections are not torn down by AsyncThrowingStream
        // deallocation before we explicitly disconnect them.
        var retainedHookStreams: [AsyncThrowingStream<AgentEvent, Error>] = []

        // A is active (kept open via a persistent client; no blocking send).
        let aClient = LocalBridgeClient(socketURL: socketURL)
        retainedHookStreams.append(try aClient.connect())
        defer { aClient.disconnect() }
        try await aClient.send(.processClaudeHook(subagentPermissionPayload(agentID: "subagent-alpha")))

        let alphaEvent = try await waitForPermissionRequestedEvent(
            originatingAgentID: "subagent-alpha",
            collector: collector
        )
        #expect(alphaEvent != nil)

        // B arrives while A is active and is queued.
        let bClient = LocalBridgeClient(socketURL: socketURL)
        retainedHookStreams.append(try bClient.connect())
        try await bClient.send(.processClaudeHook(subagentPermissionPayload(agentID: "subagent-beta")))

        try await waitForQueuedClaudeInteractionCount(1, server: server)
        #expect(server.pendingClaudeInteractionSnapshotForTests().activeCount == 1)

        // B's hook process dies (socket closes without resolving). The queued
        // interaction must be purged so it can never become active later.
        bClient.disconnect()

        try await waitForQueuedClaudeInteractionCount(0, server: server)
        let afterDisconnect = server.pendingClaudeInteractionSnapshotForTests()
        #expect(afterDisconnect.activeCount == 1)
        #expect(afterDisconnect.queuedCount == 0)

        // Resolving A must NOT promote B (it was purged): no beta event appears.
        try await observer.send(.resolvePermission(sessionID: parentSessionID, resolution: .allowOnce()))

        let betaEvent = try await waitForPermissionRequestedEvent(
            originatingAgentID: "subagent-beta",
            collector: collector
        )
        #expect(betaEvent == nil)

        let drainedSnapshot = server.pendingClaudeInteractionSnapshotForTests()
        #expect(drainedSnapshot.activeCount == 0)
        #expect(drainedSnapshot.queuedCount == 0)
    }

    @Test
    func claudeSubagentQueuedRequestClearedOnSessionEnd() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let collector = AgentEventCollector()
        let collectionTask = Task {
            do { for try await event in stream { await collector.append(event) } } catch {}
        }
        defer { collectionTask.cancel() }

        let parentSessionID = "claude-subagent-sessionend-parent"

        func subagentPermissionPayload(agentID: String) -> ClaudeHookPayload {
            ClaudeHookPayload(
                cwd: "/tmp/worktree",
                hookEventName: .permissionRequest,
                sessionID: parentSessionID,
                agentID: agentID,
                agentType: "general-purpose",
                toolName: "Bash",
                toolInput: .object(["command": .string("\(agentID)-cmd")]),
                toolUseID: "tool-use-\(agentID)"
            )
        }

        var retainedHookStreams: [AsyncThrowingStream<AgentEvent, Error>] = []

        let aClient = LocalBridgeClient(socketURL: socketURL)
        retainedHookStreams.append(try aClient.connect())
        defer { aClient.disconnect() }
        try await aClient.send(.processClaudeHook(subagentPermissionPayload(agentID: "subagent-alpha")))

        _ = try await waitForPermissionRequestedEvent(
            originatingAgentID: "subagent-alpha",
            collector: collector
        )

        let bClient = LocalBridgeClient(socketURL: socketURL)
        retainedHookStreams.append(try bClient.connect())
        defer { bClient.disconnect() }
        try await bClient.send(.processClaudeHook(subagentPermissionPayload(agentID: "subagent-beta")))

        try await waitForQueuedClaudeInteractionCount(1, server: server)

        // The parent session ends: both the active slot and the queue must clear.
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processClaudeHook(ClaudeHookPayload(
                cwd: "/tmp/worktree",
                hookEventName: .sessionEnd,
                sessionID: parentSessionID
            ))
        )

        let drainedSnapshot = server.pendingClaudeInteractionSnapshotForTests()
        #expect(drainedSnapshot.activeCount == 0)
        #expect(drainedSnapshot.queuedCount == 0)
    }

    @Test
    func claudeAwaySummaryNotificationCompletesRunningSessionWhenStopWasMissed() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let promptPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .userPromptSubmit,
            sessionID: "claude-away-summary",
            transcriptPath: "/tmp/claude-away-summary.jsonl",
            prompt: "Run the completion probe."
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(promptPayload))

        var iterator = stream.makeAsyncIterator()
        let runningEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 6) { event in
            if case let .activityUpdated(payload) = event {
                return payload.sessionID == "claude-away-summary" && payload.phase == .running
            }
            return false
        }
        if case let .activityUpdated(payload) = runningEvent {
            #expect(payload.summary == "Prompt: Run the completion probe.")
        }

        let awaySummaryPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .notification,
            sessionID: "claude-away-summary",
            transcriptPath: "/tmp/claude-away-summary.jsonl",
            message: "Claude produced an away summary.",
            notificationType: "away_summary"
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(awaySummaryPayload))

        let completedEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 6) { event in
            if case let .activityUpdated(payload) = event {
                return payload.sessionID == "claude-away-summary" && payload.phase == .completed
            }
            return false
        }
        if case let .activityUpdated(payload) = completedEvent {
            #expect(payload.summary == "Claude produced an away summary.")
        }
    }

    @Test
    func claudeSubagentStopAfterStopDoesNotReopenCompletedSession() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }

        let collector = AgentEventCollector()
        let collectionTask = Task {
            do {
                for try await event in stream {
                    await collector.append(event)
                }
            } catch {}
        }
        defer { collectionTask.cancel() }

        try await observer.send(.registerClient(role: .observer))

        let sessionID = "claude-subagent-stop-after-stop"
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processClaudeHook(
                ClaudeHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .userPromptSubmit,
                    sessionID: sessionID,
                    transcriptPath: "/tmp/claude-subagent-stop-after-stop.jsonl",
                    prompt: "Reply with exactly OK."
                )
            )
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processClaudeHook(
                ClaudeHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .stop,
                    sessionID: sessionID,
                    transcriptPath: "/tmp/claude-subagent-stop-after-stop.jsonl",
                    lastAssistantMessage: "OK"
                )
            )
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processClaudeHook(
                ClaudeHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .subagentStop,
                    sessionID: sessionID,
                    transcriptPath: "/tmp/claude-subagent-stop-after-stop.jsonl",
                    agentID: "statusline-agent",
                    agentType: "",
                    lastAssistantMessage: "(silence)"
                )
            )
        )

        let events = await waitForCompletedSessionEvent(
            sessionID: sessionID,
            collector: collector
        )
        var state = SessionState()
        for event in events {
            state.apply(event)
        }

        let session = try #require(state.session(id: sessionID))
        #expect(session.phase == .completed)
        #expect(session.summary == "OK")
        #expect(session.claudeMetadata?.agentID == nil)
        #expect(!events.contains { event in
            if case let .activityUpdated(payload) = event {
                return payload.sessionID == sessionID
                    && payload.phase == .running
                    && payload.summary == "(silence)"
            }
            return false
        })
    }

    @Test
    func questionPromptAlwaysAppendsOtherFreeformOption() throws {
        let payload = ClaudeHookPayload(
            cwd: "/tmp",
            hookEventName: .preToolUse,
            sessionID: "s1",
            toolName: "AskUserQuestion",
            toolInput: .object([
                "questions": .array([
                    .object([
                        "question": .string("Pick one"),
                        "header": .string("Pick"),
                        "options": .array([
                            option(label: "Production", description: ""),
                            option(label: "Staging", description: ""),
                        ]),
                    ]),
                ]),
            ])
        )

        let prompt = try #require(payload.questionPrompt)
        let options = try #require(prompt.questions.first?.options)
        #expect(options.map(\.label) == ["Production", "Staging", "Other"])
        #expect(options.last?.allowsFreeform == true)
        #expect(options.dropLast().allSatisfy { !$0.allowsFreeform })
    }

    @Test
    func claudeNotificationSubtypeCanIdentifyAwaySummary() throws {
        let data = Data("""
        {
          "cwd": "/tmp/worktree",
          "hook_event_name": "Notification",
          "session_id": "claude-away-summary",
          "subtype": "away_summary",
          "message": "Claude produced an away summary."
        }
        """.utf8)

        let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: data)

        #expect(payload.subtype == "away_summary")
        #expect(payload.isIdleNotification)
    }

    @Test
    func claudeDefaultJumpTargetForwardsWarpPaneUUID() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionStart,
            sessionID: "s1",
            terminalApp: "Warp",
            warpPaneUUID: "D1A5DF3027E44FC080FE2656FAF2BA2E"
        )
        #expect(payload.defaultJumpTarget.warpPaneUUID == "D1A5DF3027E44FC080FE2656FAF2BA2E")
    }

    @Test
    func claudeWithRuntimeContextPopulatesWarpPaneUUIDFromResolver() {
        let payload = ClaudeHookPayload(
            cwd: "/Users/u/demo",
            hookEventName: .sessionStart,
            sessionID: "s1"
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
    func claudeWithRuntimeContextSkipsWarpResolverForNonWarpTerminal() {
        var resolverCalls = 0
        let payload = ClaudeHookPayload(
            cwd: "/Users/u/demo",
            hookEventName: .sessionStart,
            sessionID: "s1"
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

}

private enum ClaudeHooksTestError: Error {
    case streamEnded
    case noMatchingEvent
}

private actor AgentEventCollector {
    private var events: [AgentEvent] = []

    func append(_ event: AgentEvent) {
        events.append(event)
    }

    func snapshot() -> [AgentEvent] {
        events
    }
}

private func waitForCompletedSessionEvent(
    sessionID: String,
    collector: AgentEventCollector
) async -> [AgentEvent] {
    for _ in 0..<100 {
        let events = await collector.snapshot()
        if events.contains(where: { event in
            if case let .sessionCompleted(payload) = event {
                return payload.sessionID == sessionID && payload.summary == "OK"
            }
            return false
        }) {
            return events
        }

        try? await Task.sleep(for: .milliseconds(10))
    }

    return await collector.snapshot()
}

private func waitForPermissionRequestedEvent(
    originatingAgentID: String,
    collector: AgentEventCollector
) async throws -> PermissionRequested? {
    for _ in 0..<100 {
        let events = await collector.snapshot()
        if let match = events.last(where: { event in
            if case let .permissionRequested(payload) = event {
                return payload.request.originatingAgentID == originatingAgentID
            }
            return false
        }) {
            if case let .permissionRequested(payload) = match {
                return payload
            }
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
}

private func waitForQuestionAskedEvent(
    collector: AgentEventCollector
) async throws -> QuestionAsked? {
    for _ in 0..<100 {
        let events = await collector.snapshot()
        if let match = events.last(where: { event in
            if case .questionAsked = event { return true }
            return false
        }) {
            if case let .questionAsked(payload) = match {
                return payload
            }
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
}

private func waitForQueuedClaudeInteractionCount(
    _ expected: Int,
    server: BridgeServer
) async throws {
    for _ in 0..<100 {
        if server.pendingClaudeInteractionSnapshotForTests().queuedCount == expected {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    // One final read so a failing assertion reports the actual value.
    _ = server.pendingClaudeInteractionSnapshotForTests()
}

private func nextEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
) async throws -> AgentEvent {
    guard let event = try await iterator.next() else {
        throw ClaudeHooksTestError.streamEnded
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

    throw ClaudeHooksTestError.noMatchingEvent
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}

private func option(label: String, description: String) -> ClaudeHookJSONValue {
    .object([
        "label": .string(label),
        "description": .string(description),
    ])
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
