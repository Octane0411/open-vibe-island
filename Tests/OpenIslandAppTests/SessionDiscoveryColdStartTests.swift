import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct SessionDiscoveryColdStartTests {
    @Test
    func restoresPersistedCodexSnapshotSynchronouslyBeforeAsyncDiscovery() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-cold-start-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let codexStore = CodexSessionStore(
            fileURL: rootURL.appendingPathComponent("session-terminals.json")
        )
        try codexStore.save([
            CodexTrackedSessionRecord(
                sessionID: "codex-thread",
                title: "查找开源实现",
                origin: .live,
                attachmentState: .stale,
                summary: "Thinking.",
                phase: .running,
                updatedAt: Date(),
                jumpTarget: JumpTarget(
                    terminalApp: "Codex.app",
                    workspaceName: "lijie10",
                    paneTitle: "查找开源实现",
                    workingDirectory: "/Users/lijie10",
                    codexThreadID: "codex-thread"
                ),
                codexMetadata: CodexSessionMetadata(
                    transcriptPath: "/tmp/rollout.jsonl",
                    lastUserPrompt: "冷启动 app"
                )
            ),
        ])

        var state = SessionState()
        let discovery = SessionDiscoveryCoordinator(
            codexSessionStore: codexStore,
            claudeSessionRegistry: ClaudeSessionRegistry(fileURL: rootURL.appendingPathComponent("claude.json")),
            openCodeSessionRegistry: OpenCodeSessionRegistry(fileURL: rootURL.appendingPathComponent("opencode.json")),
            cursorSessionRegistry: CursorSessionRegistry(fileURL: rootURL.appendingPathComponent("cursor.json"))
        )
        discovery.stateAccessor = { state }
        discovery.stateUpdater = { state = $0 }

        let restoredCount = discovery.restorePersistedSessionsImmediately()

        #expect(restoredCount == 1)
        let session = try #require(state.session(id: "codex-thread"))
        #expect(session.title == "查找开源实现")
        #expect(session.isCodexAppSession)
        #expect(session.isProcessAlive)
        #expect(session.codexMetadata?.lastUserPrompt == "冷启动 app")
    }
}
