import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct CodexAppServerCoordinatorTests {
    @Test
    func syncListMergesLoadedAndRecentThreadsWithLoadedFirst() {
        let loaded = [
            makeThread(id: "live-1", updatedAt: 1_780_000_000_000),
            makeThread(id: "live-2", updatedAt: 1_780_000_001_000),
        ]
        let recent = [
            makeThread(id: "live-2", updatedAt: 1_780_000_001_000),
            makeThread(id: "recent-1", updatedAt: 1_779_999_000_000),
            makeThread(id: "recent-2", updatedAt: 1_779_998_000_000),
        ]

        let merged = CodexAppServerCoordinator.mergedThreadSyncList(
            loadedThreads: loaded,
            recentThreads: recent
        )

        #expect(merged.map(\.id) == ["live-1", "live-2", "recent-1", "recent-2"])
    }

    @Test
    func threadUpdatedAtDateDecodesMillisecondsWithoutUsingNow() throws {
        let date = try #require(CodexAppServerCoordinator.threadUpdatedAtDate(from: 1_780_000_000_000))

        #expect(date == Date(timeIntervalSince1970: 1_780_000_000))
    }

    @Test
    func threadUpdatedAtDateDecodesSeconds() throws {
        let date = try #require(CodexAppServerCoordinator.threadUpdatedAtDate(from: 1_780_000_000))

        #expect(date == Date(timeIntervalSince1970: 1_780_000_000))
    }

    @Test
    func itemActivityMetadataPreservesExistingThreadContext() {
        let existing = CodexSessionMetadata(
            transcriptPath: "/tmp/rollout.jsonl",
            initialUserPrompt: "检查状态展示",
            lastUserPrompt: "继续",
            lastAssistantMessage: "正在处理",
            currentTool: nil,
            currentCommandPreview: nil,
            isSubagentSession: false
        )
        let activity = CodexAppServerItemActivity(
            threadID: "thread-1",
            toolName: "exec_command",
            preview: "swift test --filter CodexAppServerCoordinatorTests"
        )

        let metadata = CodexAppServerCoordinator.codexMetadata(existing: existing, activity: activity)

        #expect(metadata.transcriptPath == "/tmp/rollout.jsonl")
        #expect(metadata.initialUserPrompt == "检查状态展示")
        #expect(metadata.lastUserPrompt == "继续")
        #expect(metadata.lastAssistantMessage == "正在处理")
        #expect(metadata.currentTool == "exec_command")
        #expect(metadata.currentCommandPreview == "swift test --filter CodexAppServerCoordinatorTests")
    }

    @Test
    func clearingItemActivityMetadataPreservesExistingThreadContext() {
        let existing = CodexSessionMetadata(
            transcriptPath: "/tmp/rollout.jsonl",
            initialUserPrompt: "检查状态展示",
            lastUserPrompt: "继续",
            lastAssistantMessage: "完成",
            currentTool: "exec_command",
            currentCommandPreview: "swift test",
            isSubagentSession: true
        )

        let metadata = CodexAppServerCoordinator.codexMetadataClearingTool(existing: existing)

        #expect(metadata.transcriptPath == "/tmp/rollout.jsonl")
        #expect(metadata.initialUserPrompt == "检查状态展示")
        #expect(metadata.lastUserPrompt == "继续")
        #expect(metadata.lastAssistantMessage == "完成")
        #expect(metadata.currentTool == nil)
        #expect(metadata.currentCommandPreview == nil)
        #expect(metadata.isSubagentSession)
    }

    @Test
    func outputDeltaMetadataKeepsExistingCommandPreview() {
        let existing = CodexSessionMetadata(
            transcriptPath: "/tmp/rollout.jsonl",
            initialUserPrompt: "运行测试",
            lastUserPrompt: "继续",
            lastAssistantMessage: "正在处理",
            currentTool: "exec_command",
            currentCommandPreview: "swift test --filter AppModelSessionListTests"
        )
        let activity = CodexAppServerItemActivity(
            threadID: "thread-1",
            toolName: "exec_command",
            preview: "Building for debugging..."
        )

        let metadata = CodexAppServerCoordinator.codexMetadataForOutputDelta(
            existing: existing,
            activity: activity
        )

        #expect(metadata.transcriptPath == "/tmp/rollout.jsonl")
        #expect(metadata.initialUserPrompt == "运行测试")
        #expect(metadata.currentTool == "exec_command")
        #expect(metadata.currentCommandPreview == "swift test --filter AppModelSessionListTests")
    }

    @Test
    func outputDeltaMetadataUsesOutputAsPreviewWhenCommandIsMissing() {
        let existing = CodexSessionMetadata(
            transcriptPath: "/tmp/rollout.jsonl",
            initialUserPrompt: "运行测试"
        )
        let activity = CodexAppServerItemActivity(
            threadID: "thread-1",
            toolName: "exec_command",
            preview: "Building for debugging..."
        )

        let metadata = CodexAppServerCoordinator.codexMetadataForOutputDelta(
            existing: existing,
            activity: activity
        )

        #expect(metadata.transcriptPath == "/tmp/rollout.jsonl")
        #expect(metadata.currentTool == "exec_command")
        #expect(metadata.currentCommandPreview == "Building for debugging...")
    }

    @Test
    func patchUpdatedMetadataDisplaysEditingTarget() {
        let existing = CodexSessionMetadata(
            transcriptPath: "/tmp/rollout.jsonl",
            initialUserPrompt: "优化动画",
            lastUserPrompt: "继续",
            lastAssistantMessage: "正在处理"
        )
        let activity = CodexAppServerItemActivity(
            threadID: "thread-1",
            toolName: "apply_patch",
            preview: "IslandPanelView.swift"
        )

        let metadata = CodexAppServerCoordinator.codexMetadata(
            existing: existing,
            activity: activity
        )

        #expect(metadata.transcriptPath == "/tmp/rollout.jsonl")
        #expect(metadata.initialUserPrompt == "优化动画")
        #expect(metadata.lastUserPrompt == "继续")
        #expect(metadata.currentTool == "apply_patch")
        #expect(metadata.currentCommandPreview == "IslandPanelView.swift")
    }

    @Test
    func assistantDeltaMetadataPreservesRunningToolContext() {
        let existing = CodexSessionMetadata(
            transcriptPath: "/tmp/rollout.jsonl",
            initialUserPrompt: "对齐 Vibe Island",
            lastUserPrompt: "继续",
            lastAssistantMessage: "我先检查",
            currentTool: "exec_command",
            currentCommandPreview: "swift test --filter CodexSessionTrackingTests"
        )
        let delta = CodexAppServerAgentMessageDelta(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-3",
            text: "我先检查 reducer。"
        )

        let metadata = CodexAppServerCoordinator.codexMetadataForAgentMessageDelta(
            existing: existing,
            delta: delta
        )

        #expect(metadata.transcriptPath == "/tmp/rollout.jsonl")
        #expect(metadata.initialUserPrompt == "对齐 Vibe Island")
        #expect(metadata.lastUserPrompt == "继续")
        #expect(metadata.lastAssistantMessage == "我先检查 reducer。")
        #expect(metadata.currentTool == "exec_command")
        #expect(metadata.currentCommandPreview == "swift test --filter CodexSessionTrackingTests")
    }

    @Test
    func rawResponseItemFunctionCallMetadataDisplaysToolTarget() {
        let existing = CodexSessionMetadata(
            transcriptPath: "/tmp/rollout.jsonl",
            initialUserPrompt: "继续对齐事件"
        )
        let item = CodexAppServerRawResponseItem(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "call-1",
            toolName: "exec_command",
            preview: "swift test --filter CodexAppServerDecodingTests"
        )

        let metadata = CodexAppServerCoordinator.codexMetadataForRawResponseItem(
            existing: existing,
            item: item
        )

        #expect(metadata.transcriptPath == "/tmp/rollout.jsonl")
        #expect(metadata.initialUserPrompt == "继续对齐事件")
        #expect(metadata.currentTool == "exec_command")
        #expect(metadata.currentCommandPreview == "swift test --filter CodexAppServerDecodingTests")
    }

    @Test
    func rawResponseItemAssistantMessageUpdatesAssistantTextWithoutClearingContext() {
        let existing = CodexSessionMetadata(
            transcriptPath: "/tmp/rollout.jsonl",
            initialUserPrompt: "继续对齐事件",
            lastUserPrompt: "继续",
            currentTool: "exec_command",
            currentCommandPreview: "swift test"
        )
        let item = CodexAppServerRawResponseItem(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "msg-1",
            assistantText: "已经完成事件对齐。"
        )

        let metadata = CodexAppServerCoordinator.codexMetadataForRawResponseItem(
            existing: existing,
            item: item
        )

        #expect(metadata.transcriptPath == "/tmp/rollout.jsonl")
        #expect(metadata.lastUserPrompt == "继续")
        #expect(metadata.lastAssistantMessage == "已经完成事件对齐。")
        #expect(metadata.currentTool == "exec_command")
        #expect(metadata.currentCommandPreview == "swift test")
    }

    @Test
    func rolloutActivityDateUsesLatestJSONLTimestamp() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-codex-app-server-\(UUID().uuidString)", isDirectory: true)
        let rolloutURL = rootURL.appendingPathComponent("rollout.jsonl")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        {"timestamp":"2026-06-04T06:00:00.000Z","type":"session_meta","payload":{"id":"thread-1"}}
        {"timestamp":"2026-06-04T06:42:30Z","type":"event_msg","payload":{"type":"agent_message","message":"Done."}}

        """.write(to: rolloutURL, atomically: true, encoding: .utf8)

        let date = try #require(CodexAppServerCoordinator.rolloutActivityDate(atPath: rolloutURL.path))

        #expect(date == ISO8601DateFormatter().date(from: "2026-06-04T06:42:30Z"))
    }

    @Test
    func rolloutSnapshotUsesPromptForWorkspaceFallbackTitle() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-codex-app-server-\(UUID().uuidString)", isDirectory: true)
        let rolloutURL = rootURL.appendingPathComponent("rollout.jsonl")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        {"timestamp":"2026-06-04T06:00:00.000Z","type":"session_meta","payload":{"id":"thread-1"}}
        {"timestamp":"2026-06-04T06:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"web 模拟器画面现在还是截图预览"}]}}
        {"timestamp":"2026-06-04T06:00:02.000Z","type":"response_item","payload":{"type":"reasoning"}}

        """.write(to: rolloutURL, atomically: true, encoding: .utf8)

        let payload = CodexAppServerCoordinator.threadPayload(
            from: makeThread(
                id: "thread-1",
                cwd: "/Users/lijie10/Desktop/code/hera",
                name: "Codex · hera",
                path: rolloutURL.path,
                status: CodexThreadStatus(type: .idle, activeFlags: nil)
            )
        )

        #expect(payload.title == "web 模拟器画面现在还是截图预览")
        #expect(payload.jumpTarget.workspaceName == "hera")
        #expect(payload.jumpTarget.paneTitle == "web 模拟器画面现在还是截图预览")
        #expect(payload.codexMetadata.initialUserPrompt == "web 模拟器画面现在还是截图预览")
    }

    @Test
    func threadPayloadMarksSubagentSessionFromRolloutSessionMeta() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-codex-app-server-subagent-\(UUID().uuidString)", isDirectory: true)
        let rolloutURL = rootURL.appendingPathComponent("rollout-subagent.jsonl")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        {"timestamp":"2026-06-04T08:39:14.100Z","type":"session_meta","payload":{"id":"019e91c9-5f68-7310-ad42-4c460c4516cd","cwd":"/Users/lijie10/Desktop/code/hera","originator":"Codex Desktop","source":"vscode","thread_source":"subagent"}}
        {"timestamp":"2026-06-04T08:39:20.875Z","type":"event_msg","payload":{"type":"user_message","message":"排查 PreviewRuntime 权限门"}}

        """.write(to: rolloutURL, atomically: true, encoding: .utf8)

        let payload = CodexAppServerCoordinator.threadPayload(
            from: makeThread(
                id: "019e91c9-5f68-7310-ad42-4c460c4516cd",
                cwd: "/Users/lijie10/Desktop/code/hera",
                name: "排查 PreviewRuntime 权限门",
                path: rolloutURL.path,
                status: CodexThreadStatus(type: .active, activeFlags: nil)
            )
        )

        #expect(payload.codexMetadata.isSubagentSession)
    }

    @Test
    func recentRunningRolloutOverridesIdleAppServerStatus() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshot = CodexRolloutSnapshot(
            summary: "Thinking.",
            phase: .running,
            updatedAt: now.addingTimeInterval(-30),
            initialUserPrompt: "修复 bundle id 冲突",
            isCompleted: false
        )

        let phase = CodexAppServerCoordinator.threadPhase(
            from: CodexThreadStatus(type: .idle, activeFlags: nil),
            rolloutSnapshot: snapshot,
            now: now
        )

        #expect(phase == .running)
    }

    @Test
    func recentRunningRolloutOverridesNotLoadedAppServerStatus() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshot = CodexRolloutSnapshot(
            summary: "Thinking.",
            phase: .running,
            updatedAt: now.addingTimeInterval(-30),
            initialUserPrompt: "web 模拟器画面",
            isCompleted: false
        )

        let phase = CodexAppServerCoordinator.threadPhase(
            from: CodexThreadStatus(type: .notLoaded, activeFlags: nil),
            rolloutSnapshot: snapshot,
            now: now
        )

        #expect(phase == .running)
    }

    @Test
    func recentThreadUpdateKeepsNotLoadedDesktopThreadRunning() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let staleSnapshot = CodexRolloutSnapshot(
            summary: "Ready.",
            phase: .completed,
            updatedAt: now.addingTimeInterval(-24 * 60 * 60),
            initialUserPrompt: "web 模拟器画面",
            isCompleted: false
        )

        let phase = CodexAppServerCoordinator.threadPhase(
            from: CodexThreadStatus(type: .notLoaded, activeFlags: nil),
            rolloutSnapshot: staleSnapshot,
            threadUpdatedAt: now.addingTimeInterval(-20),
            now: now
        )

        #expect(phase == .running)
    }

    @Test
    func threadPayloadPrefersFreshThreadUpdateOverStaleRolloutTimestamp() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-thread-updated-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let rolloutURL = rootURL.appendingPathComponent("rollout.jsonl")
        try """
        {"timestamp":"2026-06-04T00:00:00Z","type":"event_msg","payload":{"type":"agent_message","message":"Ready."}}

        """.write(to: rolloutURL, atomically: true, encoding: .utf8)

        let threadUpdatedAt = 1_780_629_108
        let payload = CodexAppServerCoordinator.threadPayload(
            from: makeThread(
                id: "thread-1",
                name: "web 模拟器画面",
                updatedAt: threadUpdatedAt,
                path: rolloutURL.path,
                status: CodexThreadStatus(type: .notLoaded, activeFlags: nil)
            ),
            now: Date(timeIntervalSince1970: Double(threadUpdatedAt) + 20)
        )

        #expect(payload.phase == .running)
        #expect(payload.timestamp == Date(timeIntervalSince1970: Double(threadUpdatedAt)))
    }

    @Test
    func oldRunningRolloutDoesNotOverrideIdleAppServerStatus() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshot = CodexRolloutSnapshot(
            summary: "Thinking.",
            phase: .running,
            updatedAt: now.addingTimeInterval(-3_600),
            initialUserPrompt: "old prompt",
            isCompleted: false
        )

        let phase = CodexAppServerCoordinator.threadPhase(
            from: CodexThreadStatus(type: .idle, activeFlags: nil),
            rolloutSnapshot: snapshot,
            now: now
        )

        #expect(phase == .completed)
    }

    @Test
    func commandApprovalRequestUsesCommandAsPermissionSummary() {
        let request = CodexAppServerApprovalRequest(
            requestID: 51,
            kind: .commandExecution,
            threadID: "thread-1",
            reason: "Needs shell",
            command: ["git", "status"],
            cwd: "/tmp/project"
        )

        let permission = CodexAppServerCoordinator.permissionRequest(from: request)

        #expect(permission.title == "Command approval")
        #expect(permission.summary == "git status")
        #expect(permission.affectedPath == "/tmp/project")
        #expect(permission.toolName == "command")
    }

    @Test
    func waitingOnApprovalStatusDoesNotCreateFakePermissionCard() {
        let event = CodexAppServerCoordinator.eventForThreadStatusChanged(
            threadId: "thread-1",
            status: CodexThreadStatus(type: .active, activeFlags: ["waitingOnApproval"]),
            timestamp: Date(timeIntervalSince1970: 1_780_000_000)
        )

        guard case let .activityUpdated(update)? = event else {
            Issue.record("Expected a non-actionable activity update for waitingOnApproval status hints.")
            return
        }
        #expect(update.sessionID == "thread-1")
        #expect(update.phase == .running)
        #expect(update.summary == "Codex is waiting for approval.")
    }

    private func makeThread(
        id: String,
        cwd: String? = nil,
        name: String? = nil,
        updatedAt: Int = 1_780_000_000_000,
        path: String? = nil,
        status: CodexThreadStatus? = nil
    ) -> CodexThread {
        CodexThread(
            id: id,
            cwd: cwd ?? "/tmp/\(id)",
            name: name ?? id,
            preview: "preview \(id)",
            modelProvider: "openai",
            createdAt: updatedAt,
            updatedAt: updatedAt,
            ephemeral: false,
            path: path ?? "/tmp/\(id).jsonl",
            status: status ?? CodexThreadStatus(type: .idle, activeFlags: nil),
            source: .vscode,
            turns: nil
        )
    }
}
