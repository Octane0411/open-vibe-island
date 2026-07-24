import Foundation
import OpenIslandCore
import Testing
@testable import OpenIslandApp

@MainActor
struct ProcessMonitoringCoordinatorTests {
    @Test
    func staleCompletedCodexAppSessionRemainsAvailableForRolloutResumption() {
        let coordinator = ProcessMonitoringCoordinator()
        let sessionID = "resumable-codex-thread"
        var session = AgentSession(
            id: sessionID,
            title: "Resumable task",
            tool: .codex,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Previous turn completed.",
            updatedAt: Date().addingTimeInterval(-3_600),
            jumpTarget: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "project",
                paneTitle: "Resumable task",
                workingDirectory: "/tmp/project",
                codexThreadID: sessionID
            ),
            codexMetadata: CodexSessionMetadata(
                transcriptPath: "/tmp/resumable-codex-thread.jsonl"
            )
        )
        session.isCodexAppSession = true

        var state = SessionState(sessions: [session])
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }

        coordinator.reconcileSessionAttachments(
            activeProcesses: [],
            ghosttyAvailability: .available([], appIsRunning: false),
            terminalAvailability: .available([], appIsRunning: false),
            preResolvedJumpTargets: [:],
            observedCodexAppRunning: true
        )

        #expect(state.session(id: sessionID) != nil)
        #expect(state.session(id: sessionID)?.isProcessAlive == false)
    }
}
