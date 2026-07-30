import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct CodexSessionTitleSyncTests {
    @Test
    func runningLegacyCodexSessionRequiresOneProcessingDurationBackfill() {
        let metadataWithoutDuration = CodexSessionMetadata(
            transcriptPath: "/tmp/rollout.jsonl",
            currentTurnStartedAt: Date(timeIntervalSince1970: 1_000)
        )
        let legacyRecord = CodexTrackedSessionRecord(
            sessionID: "codex-thread-1",
            title: "Running task",
            summary: "Thinking.",
            phase: .running,
            updatedAt: Date(timeIntervalSince1970: 1_010),
            codexMetadata: metadataWithoutDuration
        )
        let backfilledRecord = CodexTrackedSessionRecord(
            sessionID: "codex-thread-1",
            title: "Running task",
            summary: "Thinking.",
            phase: .running,
            updatedAt: Date(timeIntervalSince1970: 1_010),
            codexMetadata: CodexSessionMetadata(
                transcriptPath: "/tmp/rollout.jsonl",
                processedDuration: 0,
                currentTurnStartedAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        #expect(SessionDiscoveryCoordinator.needsCodexProcessingDurationBackfill(legacyRecord))
        #expect(SessionDiscoveryCoordinator.needsCodexProcessingDurationBackfill(legacyRecord.session))
        #expect(!SessionDiscoveryCoordinator.needsCodexProcessingDurationBackfill(backfilledRecord))
        #expect(!SessionDiscoveryCoordinator.needsCodexProcessingDurationBackfill(backfilledRecord.session))
    }

    @MainActor
    @Test
    func maintenanceReplacesWorkspaceFallbackWithPersistedTaskTitle() {
        let now = Date(timeIntervalSince1970: 2_000)
        var session = AgentSession(
            id: "codex-thread-1",
            title: "Codex · git",
            tool: .codex,
            origin: .live,
            phase: .running,
            summary: "Working",
            updatedAt: now
        )
        session.isCodexAppSession = true
        var state = SessionState(sessions: [session])

        let coordinator = SessionDiscoveryCoordinator()
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }
        coordinator.onAgentEvent = { state.apply($0) }
        coordinator.persistedCodexThreadTitles = { threadIDs in
            threadIDs.contains("codex-thread-1")
                ? ["codex-thread-1": "查找 VibeIsland 项目"]
                : [:]
        }

        coordinator.refreshCodexThreadTitlesIfNeeded(now: now)

        #expect(state.session(id: "codex-thread-1")?.title == "查找 VibeIsland 项目")
    }

    @MainActor
    @Test
    func maintenanceDoesNotOverwriteAppServerTaskNameWithPromptShapedDatabaseTitle() {
        let now = Date(timeIntervalSince1970: 2_000)
        var session = AgentSession(
            id: "codex-thread-1",
            title: "调研AI智能小车方案",
            tool: .codex,
            origin: .live,
            phase: .running,
            summary: "Working",
            updatedAt: now
        )
        session.isCodexAppSession = true
        var state = SessionState(sessions: [session])

        let coordinator = SessionDiscoveryCoordinator()
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }
        coordinator.onAgentEvent = { state.apply($0) }
        coordinator.persistedCodexThreadTitles = { _ in
            ["codex-thread-1": "我现在想做一个东西，这个东西呢，就是……"]
        }

        coordinator.refreshCodexThreadTitlesIfNeeded(now: now)

        #expect(state.session(id: "codex-thread-1")?.title == "调研AI智能小车方案")
    }
}
