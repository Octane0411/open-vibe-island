import Foundation
import Testing
@testable import OpenIslandCore

/// Live regression: a resolved Claude session title must survive the hook
/// traffic of a running session. Claude metadata updates replace the whole
/// struct and several bridge emitters (metadata sync against a stale bridge
/// snapshot, subagent/task bookkeeping, `SessionStart` re-emits) build it
/// without the title, which used to wipe the headline back to
/// "workspace · prompt" while the session kept working.
struct ClaudeSessionTitlePersistenceTests {
    /// Mirrors AppModel: applies every bridge event to its own state and
    /// pushes the result back as the bridge snapshot (AppModel's `didSet`).
    private actor AppStateMirror {
        var state: SessionState
        var eventCount = 0
        var pushesSnapshots = false
        var titleHistory: [String?] = []

        init(state: SessionState) {
            self.state = state
        }

        func apply(_ event: AgentEvent, sessionID: String, server: BridgeServer) {
            state.apply(event)
            eventCount += 1
            titleHistory.append(state.session(id: sessionID)?.claudeMetadata?.sessionTitle)
            if pushesSnapshots {
                server.updateStateSnapshot(state)
            }
        }

        func setPushesSnapshots(_ value: Bool) {
            pushesSnapshots = value
        }
    }

    private func makeTempDirectory(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-title-persist-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeDesktopSession(base: URL, cliSessionID: String, title: String) throws {
        let dir = base
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{"sessionId":"local_\#(UUID().uuidString)","cliSessionId":"\#(cliSessionID)","title":"\#(title)"}"#
        try json.write(to: dir.appendingPathComponent("local_x.json"), atomically: true, encoding: .utf8)
    }

    /// Waits until the mirror has seen no new event for `quietPeriod`.
    private func waitForQuiet(_ mirror: AppStateMirror, quietPeriod: Duration = .milliseconds(150)) async {
        var last = await mirror.eventCount
        for _ in 0..<40 {
            try? await Task.sleep(for: quietPeriod)
            let current = await mirror.eventCount
            if current == last { return }
            last = current
        }
    }

    @Test
    func resolvedTitleSurvivesLiveHookTrafficFromClaudeDesktopSession() async throws {
        let sessionID = "0f1e2d3c-4b5a-4697-8a8b-9c0d1e2f3a4b"
        let cwd = "/tmp/scratch-demo"
        let desktopBase = try makeTempDirectory("desktop")
        defer { try? FileManager.default.removeItem(at: desktopBase) }

        // The bridge's title service has nothing for this session yet: the
        // title came from transcript discovery / the restored registry on
        // the app side, exactly like right after launch.
        let index = ClaudeDesktopSessionTitleIndex(baseURL: desktopBase, minimumRescanInterval: 0)
        let titleService = ClaudeSessionTitleService(desktopIndex: index)

        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, claudeTitleService: titleService)
        try server.start()
        defer { server.stop() }

        let jumpTarget = JumpTarget(
            terminalApp: "Claude.app",
            workspaceName: "scratch-demo",
            paneTitle: "Claude Code 0f1e2d3c",
            workingDirectory: cwd
        )
        var discovered = AgentSession(
            id: sessionID,
            title: "Claude Code · scratch-demo",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Idle",
            updatedAt: .now,
            jumpTarget: jumpTarget,
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/\(sessionID).jsonl",
                initialUserPrompt: "Come funziona?",
                sessionTitle: "How the notch island works"
            )
        )
        discovered.isHookManaged = true

        // The bridge holds a snapshot that predates the discovery merge
        // (AppModel pushes snapshots asynchronously), so its copy has no title.
        var stale = discovered
        stale.claudeMetadata?.sessionTitle = nil
        server.updateStateSnapshot(SessionState(sessions: [stale]))

        let mirror = AppStateMirror(state: SessionState(sessions: [discovered]))
        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        let consumer = Task {
            for try await event in stream {
                await mirror.apply(event, sessionID: sessionID, server: server)
            }
        }
        defer { consumer.cancel() }

        func hook(
            _ name: ClaudeHookEventName,
            agentID: String? = nil,
            agentType: String? = nil,
            source: ClaudeSessionStartSource? = nil,
            toolName: String? = nil,
            toolInput: ClaudeHookJSONValue? = nil,
            toolUseID: String? = nil,
            toolResponse: ClaudeHookJSONValue? = nil,
            prompt: String? = nil
        ) throws {
            // Shape of the payload Claude Desktop's embedded Claude Code sends.
            let payload = ClaudeHookPayload(
                cwd: cwd,
                hookEventName: name,
                sessionID: sessionID,
                transcriptPath: "/tmp/\(sessionID).jsonl",
                permissionMode: .default,
                agentID: agentID,
                agentType: agentType,
                source: source,
                toolName: toolName,
                toolInput: toolInput,
                toolUseID: toolUseID,
                toolResponse: toolResponse,
                prompt: prompt,
                terminalApp: "Claude.app"
            )
            _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(payload))
        }

        try hook(.userPromptSubmit, prompt: "Fai il fix")
        try hook(.preToolUse, toolName: "Bash", toolInput: .object(["command": .string("ls")]), toolUseID: "t1")
        try hook(.postToolUse, toolName: "Bash", toolInput: .object(["command": .string("ls")]), toolUseID: "t1")
        try hook(
            .preToolUse,
            toolName: "Agent",
            toolInput: .object(["description": .string("Explore the bridge"), "prompt": .string("...")]),
            toolUseID: "t2"
        )
        try hook(.subagentStart, agentID: "agent-1", agentType: "Explore")
        try hook(
            .preToolUse,
            toolName: "TaskCreate",
            toolInput: .object(["subject": .string("Write the regression test")]),
            toolUseID: "t3"
        )
        try hook(
            .postToolUse,
            toolName: "TaskCreate",
            toolInput: .object(["subject": .string("Write the regression test")]),
            toolUseID: "t3",
            toolResponse: .object(["task": .object(["id": .string("7")])])
        )
        try hook(.subagentStop, agentID: "agent-1", agentType: "Explore")
        try hook(.stop)
        // Compaction re-fires SessionStart for the same session.
        try hook(.sessionStart, source: .compact)
        await waitForQuiet(mirror)

        // From here on the app pushes a snapshot after every event (AppModel's
        // didSet), as in the live app.
        await mirror.setPushesSnapshots(true)
        for index in 0..<5 {
            try hook(.userPromptSubmit, prompt: "Prompt \(index)")
            try hook(.preToolUse, toolName: "Read", toolInput: .object(["file_path": .string("/tmp/a")]), toolUseID: "r\(index)")
            try hook(.postToolUse, toolName: "Read", toolInput: .object(["file_path": .string("/tmp/a")]), toolUseID: "r\(index)")
            try hook(.stop)
        }
        await waitForQuiet(mirror)

        let history = await mirror.titleHistory
        #expect(!history.isEmpty)
        #expect(history.allSatisfy { $0 == "How the notch island works" }, "title history: \(history)")
        let finalState = await mirror.state
        #expect(finalState.session(id: sessionID)?.claudeMetadata?.sessionTitle == "How the notch island works")
        #expect(server.sessionStateSnapshotForTests().session(id: sessionID)?.claudeMetadata?.sessionTitle == "How the notch island works")

        // A newer title (Desktop rename) still replaces the known one.
        try writeDesktopSession(base: desktopBase, cliSessionID: sessionID, title: "Titoli persistenti")
        try hook(.userPromptSubmit, prompt: "Dopo il rename")
        await waitForQuiet(mirror, quietPeriod: .milliseconds(300))
        let renamed = await mirror.state
        #expect(renamed.session(id: sessionID)?.claudeMetadata?.sessionTitle == "Titoli persistenti")
    }

    @Test
    func metadataUpdateWithoutTitleKeepsKnownTitleButNewTitleWins() {
        let sessionID = "claude-title-merge"
        var state = SessionState(sessions: [
            AgentSession(
                id: sessionID,
                title: "Claude Code · repo",
                tool: .claudeCode,
                phase: .running,
                summary: "Working",
                updatedAt: .now,
                claudeMetadata: ClaudeSessionMetadata(lastUserPrompt: "hi", sessionTitle: "Known title")
            ),
        ])

        state.apply(.claudeSessionMetadataUpdated(ClaudeSessionMetadataUpdated(
            sessionID: sessionID,
            claudeMetadata: ClaudeSessionMetadata(currentTool: "Bash"),
            timestamp: .now
        )))
        #expect(state.session(id: sessionID)?.claudeMetadata?.sessionTitle == "Known title")
        #expect(state.session(id: sessionID)?.claudeMetadata?.currentTool == "Bash")

        state.apply(.sessionStarted(SessionStarted(
            sessionID: sessionID,
            title: "Claude Code · repo",
            tool: .claudeCode,
            summary: "Restarted",
            timestamp: .now
        )))
        #expect(state.session(id: sessionID)?.claudeMetadata?.sessionTitle == "Known title")

        state.apply(.claudeSessionMetadataUpdated(ClaudeSessionMetadataUpdated(
            sessionID: sessionID,
            claudeMetadata: ClaudeSessionMetadata(sessionTitle: "Renamed"),
            timestamp: .now
        )))
        #expect(state.session(id: sessionID)?.claudeMetadata?.sessionTitle == "Renamed")
    }
}
