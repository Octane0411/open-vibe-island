import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct ProcessMonitoringCoordinatorTests {
    @Test
    func codexLivenessMatchesTranscriptPathWhenProcessSessionIDIsUnavailable() {
        let coordinator = ProcessMonitoringCoordinator()
        var state = SessionState(
            sessions: [
                codexSession(
                    id: "tracked-codex",
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001",
                    transcriptPath: "/Users/test/.codex/sessions/2026/04/03/rollout-2026-04-03T11-42-31-019d516f-71ee-7e40-bcff-502fedac0928.jsonl"
                ),
            ]
        )
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }

        let aliveIDs = aliveSessionIDs(
            coordinator,
            activeProcesses: [
                .init(
                    tool: .codex,
                    sessionID: nil,
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001",
                    terminalApp: "WezTerm",
                    transcriptPath: "/Users/test/.codex/sessions/2026/04/03/rollout-2026-04-03T11-42-31-019d516f-71ee-7e40-bcff-502fedac0928.jsonl"
                ),
            ]
        )

        #expect(aliveIDs == Set(["tracked-codex"]))
    }

    @Test
    func codexRuntimeEvidenceCarriesMatchStrength() {
        let coordinator = ProcessMonitoringCoordinator()
        var state = SessionState(
            sessions: [
                codexSession(
                    id: "tracked-codex",
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001",
                    transcriptPath: "/Users/test/.codex/sessions/2026/04/03/rollout-2026-04-03T11-42-31-019d516f-71ee-7e40-bcff-502fedac0928.jsonl"
                ),
            ]
        )
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }

        let evidence = coordinator.runtimeEvidenceBySessionID(
            activeProcesses: [
                .init(
                    tool: .codex,
                    sessionID: nil,
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001",
                    terminalApp: "WezTerm",
                    transcriptPath: "/Users/test/.codex/sessions/2026/04/03/rollout-2026-04-03T11-42-31-019d516f-71ee-7e40-bcff-502fedac0928.jsonl"
                ),
            ]
        )

        #expect(evidence["tracked-codex"] == .transcriptPath)
    }

    @Test
    func codexLivenessFallsBackToUniqueTTYAndWorkingDirectory() {
        let coordinator = ProcessMonitoringCoordinator()
        var state = SessionState(
            sessions: [
                codexSession(
                    id: "tracked-codex",
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001"
                ),
            ]
        )
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }

        let aliveIDs = aliveSessionIDs(
            coordinator,
            activeProcesses: [
                .init(
                    tool: .codex,
                    sessionID: nil,
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001",
                    terminalApp: "WezTerm"
                ),
            ]
        )

        #expect(aliveIDs == Set(["tracked-codex"]))
    }

    @Test
    func codexLivenessFallsBackToUniqueTTYWhenProcessWorkingDirectoryIsUnavailable() {
        let coordinator = ProcessMonitoringCoordinator()
        var state = SessionState(
            sessions: [
                codexSession(
                    id: "tracked-codex",
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001"
                ),
            ]
        )
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }

        let aliveIDs = aliveSessionIDs(
            coordinator,
            activeProcesses: [
                .init(
                    tool: .codex,
                    sessionID: nil,
                    workingDirectory: nil,
                    terminalTTY: "/dev/ttys001",
                    terminalApp: "WezTerm"
                ),
            ]
        )

        #expect(aliveIDs == Set(["tracked-codex"]))
    }

    @Test
    func codexLivenessDoesNotGuessAcrossAmbiguousTTYAndWorkingDirectoryMatches() {
        let coordinator = ProcessMonitoringCoordinator()
        var state = SessionState(
            sessions: [
                codexSession(
                    id: "tracked-codex-1",
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001"
                ),
                codexSession(
                    id: "tracked-codex-2",
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001"
                ),
            ]
        )
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }

        let aliveIDs = aliveSessionIDs(
            coordinator,
            activeProcesses: [
                .init(
                    tool: .codex,
                    sessionID: nil,
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001",
                    terminalApp: "WezTerm"
                ),
            ]
        )

        #expect(aliveIDs.isEmpty)
    }

    @Test
    func codexLivenessDoesNotGuessAcrossAmbiguousTTYOnlyMatches() {
        let coordinator = ProcessMonitoringCoordinator()
        var state = SessionState(
            sessions: [
                codexSession(
                    id: "tracked-codex-1",
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001"
                ),
                codexSession(
                    id: "tracked-codex-2",
                    workingDirectory: "/tmp/other",
                    terminalTTY: "/dev/ttys001"
                ),
            ]
        )
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }

        let aliveIDs = aliveSessionIDs(
            coordinator,
            activeProcesses: [
                .init(
                    tool: .codex,
                    sessionID: nil,
                    workingDirectory: nil,
                    terminalTTY: "/dev/ttys001",
                    terminalApp: "WezTerm"
                ),
            ]
        )

        #expect(aliveIDs.isEmpty)
    }

    @Test
    func reconcileSessionAttachmentsUsesLocallyUpdatedSessionSnapshotForRuntimeEvidence() {
        let coordinator = ProcessMonitoringCoordinator()
        let now = Date(timeIntervalSince1970: 2_000)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "tracked-claude",
                    title: "Claude · open-island",
                    tool: .claudeCode,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .running,
                    summary: "Working",
                    updatedAt: now,
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "open-island",
                        paneTitle: "claude ~/tmp/open-island",
                        workingDirectory: "/tmp/open-island",
                        terminalTTY: "/dev/ttys009"
                    ),
                    lifecyclePolicy: .hookDrivenWithProcessFallback
                ),
            ]
        )
        coordinator.stateAccessor = { state }
        coordinator.stateUpdater = { state = $0 }

        coordinator.reconcileSessionAttachments(
            activeProcesses: [
                .init(
                    tool: .claudeCode,
                    sessionID: nil,
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys001",
                    terminalApp: "Ghostty"
                ),
            ],
            ghosttyAvailability: .available([], appIsRunning: true),
            terminalAvailability: .available([], appIsRunning: false),
            preResolvedJumpTargets: [:]
        )

        #expect(state.sessions.map(\.id) == ["tracked-claude"])
        #expect(state.session(id: "tracked-claude")?.jumpTarget?.terminalTTY == "/dev/ttys001")
        #expect(state.session(id: "tracked-claude")?.hasRuntimePresence == true)
        #expect(state.session(id: "tracked-claude")?.isVisibleInIsland == true)
    }
}

@MainActor
private func aliveSessionIDs(
    _ coordinator: ProcessMonitoringCoordinator,
    activeProcesses: [ActiveProcessSnapshot]
) -> Set<String> {
    Set(coordinator.runtimeEvidenceBySessionID(activeProcesses: activeProcesses).keys)
}

private func codexSession(
    id: String,
    workingDirectory: String,
    terminalTTY: String,
    transcriptPath: String? = nil
) -> AgentSession {
    AgentSession(
        id: id,
        title: "Codex · open-island",
        tool: .codex,
        origin: .live,
        attachmentState: .attached,
        phase: .running,
        summary: "Working",
        updatedAt: Date(timeIntervalSince1970: 2_000),
        jumpTarget: JumpTarget(
            terminalApp: "WezTerm",
            workspaceName: "open-island",
            paneTitle: "codex ~/tmp/open-island",
            workingDirectory: workingDirectory,
            terminalTTY: terminalTTY
        ),
        codexMetadata: transcriptPath.map { CodexSessionMetadata(transcriptPath: $0) }
    )
}
