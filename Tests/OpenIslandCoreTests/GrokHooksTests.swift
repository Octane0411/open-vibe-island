import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

struct GrokHooksTests {
    private let openIslandCommand = "'/usr/local/bin/OpenIslandHooks' --source grok"
    private let vibeCommand = "'/Users/me/.vibe-island/bin/vibe-island-bridge' --source grok"

    // MARK: - Decode

    @Test
    func grokHookPayloadDecodesCamelCaseEnvelope() throws {
        let json = """
        {
          "hookEventName": "pre_tool_use",
          "sessionId": "grok-session-1",
          "cwd": "/tmp/worktree",
          "workspaceRoot": "/tmp/worktree",
          "permissionMode": "default",
          "toolName": "run_terminal_command",
          "toolInput": { "command": "npm test" },
          "toolUseId": "tool-1",
          "timestamp": "2026-08-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(GrokHookPayload.self, from: json)

        #expect(payload.hookEventName == .preToolUse)
        #expect(payload.sessionID == "grok-session-1")
        #expect(payload.toolName == "run_terminal_command")
        #expect(payload.toolUseID == "tool-1")
        #expect(payload.sessionTitle == "Grok · worktree")
        #expect(payload.implicitSummary.contains("run_terminal_command"))
    }

    @Test
    func workspaceRootFallbackWhenCwdMissing() throws {
        let json = """
        {
          "hookEventName": "SessionStart",
          "sessionId": "grok-cwd-fallback",
          "workspaceRoot": "/tmp/from-workspace-root"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(GrokHookPayload.self, from: json)
        #expect(payload.cwd == "/tmp/from-workspace-root")
        #expect(payload.workspaceName == "from-workspace-root")
    }

    @Test
    func grokHookEventNameAcceptsPascalCaseAndSnakeCase() throws {
        let cases: [(String, GrokHookEventName)] = [
            ("SessionStart", .sessionStart),
            ("session_start", .sessionStart),
            ("UserPromptSubmit", .userPromptSubmit),
            ("user_prompt_submit", .userPromptSubmit),
            ("PreToolUse", .preToolUse),
            ("pre_tool_use", .preToolUse),
            ("Stop", .stop),
            ("stop", .stop),
            ("PermissionDenied", .permissionDenied),
            ("permission_denied", .permissionDenied),
            ("PostCompact", .postCompact),
            ("post_compact", .postCompact),
            ("subagent_end", .subagentStop),
        ]

        for (raw, expected) in cases {
            let decoded = try JSONDecoder().decode(
                GrokHookEventName.self,
                from: Data("\"\(raw)\"".utf8)
            )
            #expect(decoded == expected, "raw \(raw)")
        }
    }

    @Test
    func genuineTurnStopFiltersSessionEndFire() {
        let turnEnd = GrokHookPayload(
            cwd: "/tmp",
            hookEventName: .stop,
            sessionID: "s1",
            reason: "end_turn"
        )
        let sessionEndFire = GrokHookPayload(
            cwd: "/tmp",
            hookEventName: .stop,
            sessionID: "s1",
            reason: "shutdown"
        )
        let missingReason = GrokHookPayload(
            cwd: "/tmp",
            hookEventName: .stop,
            sessionID: "s1"
        )

        #expect(turnEnd.isGenuineTurnStop)
        #expect(!sessionEndFire.isGenuineTurnStop)
        // Missing reason: treat as genuine turn completion (older Grok builds).
        #expect(missingReason.isGenuineTurnStop)
    }

    // MARK: - Installer

    @Test
    func managedInstallEmitsCompleteRequiredEventSet() throws {
        let mutation = try GrokHookInstaller.installHooksJSON(hookCommand: openIslandCommand)
        #expect(mutation.changed)
        #expect(mutation.managedHooksPresent)

        let data = try #require(mutation.contents)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = object["hooks"] as! [String: Any]
        let installedKeys = Set(hooks.keys)
        let expectedKeys = Set(GrokHookInstaller.requiredEventNames)

        #expect(installedKeys == expectedKeys)
        #expect(
            GrokHookInstaller.managedHooksPresent(in: data, managedCommand: openIslandCommand)
        )
    }

    @Test
    func installIsIdempotentWhenContentUnchanged() throws {
        let first = try GrokHookInstaller.installHooksJSON(hookCommand: openIslandCommand)
        let firstData = try #require(first.contents)
        #expect(first.changed)

        let second = try GrokHookInstaller.installHooksJSON(
            existingData: firstData,
            hookCommand: openIslandCommand
        )
        #expect(second.changed == false)
        #expect(second.contents == firstData)
    }

    @Test
    func completeManagedJSONReportsInstalled() throws {
        let data = try #require(
            try GrokHookInstaller.installHooksJSON(hookCommand: openIslandCommand).contents
        )
        #expect(GrokHookInstaller.managedHooksPresent(in: data, managedCommand: openIslandCommand))
        #expect(GrokHookInstaller.isOpenIslandOwnedManagedFile(data))
    }

    @Test
    func missingCriticalEventReportsNotInstalled() throws {
        var root: [String: Any] = ["hooks": [:]]
        var hooks: [String: Any] = [:]
        for name in GrokHookInstaller.requiredEventNames where name != "SessionEnd" {
            hooks[name] = [[
                "hooks": [[
                    "type": "command",
                    "command": openIslandCommand,
                ]],
            ]]
        }
        root["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: root)

        #expect(
            GrokHookInstaller.managedHooksPresent(in: data, managedCommand: openIslandCommand) == false
        )
    }

    @Test
    func unrelatedCommandReportsNotInstalled() throws {
        var hooks: [String: Any] = [:]
        for name in GrokHookInstaller.requiredEventNames {
            hooks[name] = [[
                "hooks": [[
                    "type": "command",
                    "command": "echo unrelated",
                ]],
            ]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["hooks": hooks])
        #expect(GrokHookInstaller.managedHooksPresent(in: data, managedCommand: openIslandCommand) == false)
        #expect(GrokHookInstaller.isOpenIslandOwnedManagedFile(data) == false)
    }

    @Test
    func vibeIslandOnlyCommandDoesNotCountAsOpenIslandInstalled() throws {
        var hooks: [String: Any] = [:]
        for name in GrokHookInstaller.requiredEventNames {
            hooks[name] = [[
                "hooks": [[
                    "type": "command",
                    "command": vibeCommand,
                ]],
            ]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["hooks": hooks])
        #expect(GrokHookInstaller.managedHooksPresent(in: data, managedCommand: openIslandCommand) == false)
        #expect(GrokHookInstaller.isOpenIslandOwnedManagedFile(data) == false)
    }

    @Test
    func installationManagerInstallUninstallAndRefusesForeignFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-grok-install-\(UUID().uuidString)", isDirectory: true)
        let binDir = tmp.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let fakeHooks = binDir.appendingPathComponent("OpenIslandHooks")
        try Data("#!/bin/sh\n".utf8).write(to: fakeHooks)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeHooks.path)

        let managedBinary = binDir.appendingPathComponent("managed-OpenIslandHooks")
        let grokDir = tmp.appendingPathComponent("grok", isDirectory: true)
        let manager = GrokHookInstallationManager(
            grokDirectory: grokDir,
            managedHooksBinaryURL: managedBinary
        )

        defer { try? FileManager.default.removeItem(at: tmp) }

        let installed = try manager.install(hooksBinaryURL: fakeHooks)
        #expect(installed.managedHooksPresent)
        #expect(FileManager.default.fileExists(atPath: installed.hooksURL.path))

        let again = try manager.install(hooksBinaryURL: fakeHooks)
        #expect(again.managedHooksPresent)

        let uninstalled = try manager.uninstall()
        #expect(uninstalled.managedHooksPresent == false)
        #expect(FileManager.default.fileExists(atPath: installed.hooksURL.path) == false)

        // User-replaced foreign content must not be deleted.
        try FileManager.default.createDirectory(at: manager.hooksDirectory, withIntermediateDirectories: true)
        try Data("{\"hooks\":{}}".utf8).write(to: manager.hooksURL)
        #expect(throws: GrokHookInstallerError.managedFileNotOwnedByOpenIsland) {
            try manager.uninstall()
        }
        #expect(FileManager.default.fileExists(atPath: manager.hooksURL.path))
    }

    // MARK: - Bridge lifecycle

    @Test
    func grokSessionStartAndStopFlowThroughBridge() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let startPayload = GrokHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            sessionID: "grok-session-bridge"
        )
        let stopPayload = GrokHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .stop,
            sessionID: "grok-session-bridge",
            lastAssistantMessage: "All done.",
            reason: "end_turn"
        )

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processGrokHook(startPayload))
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processGrokHook(stopPayload))

        var iterator = stream.makeAsyncIterator()
        let event = try await nextMatchingGrokEvent(from: &iterator, maxEvents: 8) { event in
            if case .sessionCompleted = event {
                return true
            }
            return false
        }

        guard case let .sessionCompleted(payload) = event else {
            Issue.record("Expected Grok stop session completion")
            return
        }

        #expect(payload.sessionID == "grok-session-bridge")
        #expect(payload.summary == "All done.")
        #expect(payload.isSessionEnd != true)
        #expect(server.sessionStateSnapshotForTests().session(id: "grok-session-bridge")?.isSessionEnded != true)
    }

    @Test
    func nonTurnStopDoesNotCompleteTurn() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .sessionStart,
                    sessionID: "grok-non-turn-stop"
                )
            )
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .userPromptSubmit,
                    sessionID: "grok-non-turn-stop",
                    prompt: "hi"
                )
            )
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .stop,
                    sessionID: "grok-non-turn-stop",
                    reason: "shutdown"
                )
            )
        )

        let session = try #require(server.sessionStateSnapshotForTests().session(id: "grok-non-turn-stop"))
        #expect(session.phase == .running)
        #expect(session.isSessionEnded == false)
    }

    @Test
    func postToolUseFailureDoesNotLeaveSessionRunning() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .sessionStart,
                    sessionID: "grok-tool-fail"
                )
            )
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .postToolUseFailure,
                    sessionID: "grok-tool-fail",
                    toolName: "run_terminal_command",
                    error: "exit 1"
                )
            )
        )

        let session = try #require(server.sessionStateSnapshotForTests().session(id: "grok-tool-fail"))
        #expect(session.phase == .completed)
        #expect(session.isSessionEnded == false)
    }

    @Test
    func stopFailureDoesNotLeaveSessionRunning() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .sessionStart,
                    sessionID: "grok-stop-fail"
                )
            )
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .stopFailure,
                    sessionID: "grok-stop-fail",
                    error: "rate_limit"
                )
            )
        )

        let session = try #require(server.sessionStateSnapshotForTests().session(id: "grok-stop-fail"))
        #expect(session.phase == .completed)
    }

    @Test
    func grokSessionEndMarksSessionEnded() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .sessionStart,
                    sessionID: "grok-session-end"
                )
            )
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .sessionEnd,
                    sessionID: "grok-session-end",
                    reason: "user_exit"
                )
            )
        )

        let session = try #require(server.sessionStateSnapshotForTests().session(id: "grok-session-end"))
        #expect(session.isSessionEnded == true)
        #expect(session.phase == .completed)
    }

    @Test
    func lateEventAfterSessionEndDoesNotResurrectSession() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let client = BridgeCommandClient(socketURL: socketURL)
        _ = try client.send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .sessionStart,
                    sessionID: "grok-ended"
                )
            )
        )
        _ = try client.send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .sessionEnd,
                    sessionID: "grok-ended"
                )
            )
        )
        _ = try client.send(
            .processGrokHook(
                GrokHookPayload(
                    cwd: "/tmp/worktree",
                    hookEventName: .userPromptSubmit,
                    sessionID: "grok-ended",
                    prompt: "late prompt"
                )
            )
        )

        let session = try #require(server.sessionStateSnapshotForTests().session(id: "grok-ended"))
        #expect(session.isSessionEnded == true)
        // Summary must not be rewritten by late UserPromptSubmit recreation.
        #expect(session.summary.contains("late prompt") == false)
    }

    // MARK: - Process liveness (SessionState contract)

    @Test
    func liveGrokProcessKeepsHookManagedSessionAcrossMissThreshold() {
        var session = AgentSession(
            id: "grok-live-1",
            title: "Grok · demo",
            tool: .grokBuild,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        session.isHookManaged = true
        session.isProcessAlive = true
        var state = SessionState(sessions: [session])

        // Process monitoring reports the session as alive (Grok process present).
        state.markProcessLiveness(aliveSessionIDs: ["grok-live-1"])
        state.markProcessLiveness(aliveSessionIDs: ["grok-live-1"])
        state.markProcessLiveness(aliveSessionIDs: ["grok-live-1"])
        #expect(state.session(id: "grok-live-1")?.isSessionEnded == false)
        #expect(state.session(id: "grok-live-1")?.isVisibleInIsland == true)
    }

    @Test
    func missingGrokProcessEventuallyEndsHookManagedSessionWithoutSessionEnd() {
        var session = AgentSession(
            id: "grok-orphan-1",
            title: "Grok · demo",
            tool: .grokBuild,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        session.isHookManaged = true
        session.isProcessAlive = true
        var state = SessionState(sessions: [session])

        state.markProcessLiveness(aliveSessionIDs: [])
        #expect(state.session(id: "grok-orphan-1")?.isSessionEnded == false)

        state.markProcessLiveness(aliveSessionIDs: [])
        #expect(state.session(id: "grok-orphan-1")?.isSessionEnded == true)
        #expect(state.session(id: "grok-orphan-1")?.isVisibleInIsland == false)
    }

    @Test
    func explicitlyEndedGrokSessionIsNotResurrectedByAliveProcessSet() {
        var session = AgentSession(
            id: "grok-ended-1",
            title: "Grok · demo",
            tool: .grokBuild,
            phase: .completed,
            summary: "Done",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        session.isHookManaged = true
        session.isSessionEnded = true
        var state = SessionState(sessions: [session])

        // Even if process discovery still reports the session id as "alive",
        // ended sessions must stay ended.
        state.markProcessLiveness(aliveSessionIDs: ["grok-ended-1"])
        state.markProcessLiveness(aliveSessionIDs: ["grok-ended-1"])
        #expect(state.session(id: "grok-ended-1")?.isSessionEnded == true)
        #expect(state.session(id: "grok-ended-1")?.isVisibleInIsland == false)
    }
}

// MARK: - Helpers

private func nextMatchingGrokEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator,
    maxEvents: Int,
    match: (AgentEvent) -> Bool
) async throws -> AgentEvent {
    for _ in 0..<maxEvents {
        guard let event = try await iterator.next() else {
            break
        }
        if match(event) {
            return event
        }
    }
    Issue.record("Timed out waiting for matching Grok bridge event")
    throw CancellationError()
}
