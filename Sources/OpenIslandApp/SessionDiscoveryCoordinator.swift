import Foundation
import Observation
import OpenIslandCore

@MainActor
@Observable
final class SessionDiscoveryCoordinator {

    /// Raw I/O results collected off the main thread during startup.
    struct StartupDiscoveryPayload: Sendable {
        var codexRecords: [CodexTrackedSessionRecord]
        var codexRecordsNeedPrune: Bool
        var claudeRecords: [ClaudeTrackedSessionRecord]
        var claudeRecordsNeedPrune: Bool
        var cursorRecords: [CursorTrackedSessionRecord]
        var cursorRecordsNeedPrune: Bool
        var discoveredCodexRecords: [CodexTrackedSessionRecord]
        var discoveredClaudeSessions: [AgentSession]
        var hooksBinaryURL: URL?
    }

    @ObservationIgnored
    var syntheticClaudeSessionPrefix = ""

    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    @ObservationIgnored
    var stateAccessor: (() -> SessionState)?

    @ObservationIgnored
    var stateUpdater: ((SessionState) -> Void)?

    @ObservationIgnored
    var onStateChanged: (() -> Void)?

    @ObservationIgnored
    private let codexSessionStore = CodexSessionStore()

    @ObservationIgnored
    private let claudeSessionRegistry = ClaudeSessionRegistry()

    @ObservationIgnored
    private let cursorSessionRegistry = CursorSessionRegistry()

    @ObservationIgnored
    let codexRolloutWatcher = CodexRolloutWatcher()

    @ObservationIgnored
    private let codexRolloutDiscovery = CodexRolloutDiscovery()

    @ObservationIgnored
    private let claudeTranscriptDiscovery = ClaudeTranscriptDiscovery()

    @ObservationIgnored
    private var codexSessionPersistenceTask: Task<Void, Never>?

    @ObservationIgnored
    private var claudeSessionPersistenceTask: Task<Void, Never>?

    @ObservationIgnored
    private var cursorSessionPersistenceTask: Task<Void, Never>?

    private var state: SessionState {
        get { stateAccessor?() ?? SessionState() }
        set {
            stateUpdater?(newValue)
            onStateChanged?()
        }
    }

    // MARK: - Startup discovery

    /// Performs all startup file I/O off the main thread and returns the raw results.
    nonisolated func loadStartupDiscoveryPayload() -> StartupDiscoveryPayload {
        let cutoff = Date.now.addingTimeInterval(-86_400)

        let allCodex = (try? codexSessionStore.load()) ?? []
        let codexRecords = allCodex.filter { $0.updatedAt >= cutoff && $0.shouldRestoreToLiveState }

        let allClaude = (try? claudeSessionRegistry.load()) ?? []
        let claudeRecords = allClaude.filter { $0.updatedAt >= cutoff && $0.shouldRestoreToLiveState }

        let allCursor = (try? cursorSessionRegistry.load()) ?? []
        let cursorRecords = allCursor.filter { $0.updatedAt >= cutoff && $0.shouldRestoreToLiveState }

        let discoveredCodex = codexRolloutDiscovery.discoverRecentSessions()
        let discoveredClaude = claudeTranscriptDiscovery.discoverRecentSessions()

        return StartupDiscoveryPayload(
            codexRecords: codexRecords,
            codexRecordsNeedPrune: codexRecords != allCodex,
            claudeRecords: claudeRecords,
            claudeRecordsNeedPrune: claudeRecords != allClaude,
            cursorRecords: cursorRecords,
            cursorRecordsNeedPrune: cursorRecords != allCursor,
            discoveredCodexRecords: discoveredCodex,
            discoveredClaudeSessions: discoveredClaude,
            hooksBinaryURL: HooksBinaryLocator.locate(
                executableDirectory: Bundle.main.executableURL?.deletingLastPathComponent()
            )
        )
    }

    /// Applies startup discovery results on the main thread after background I/O completes.
    /// Returns the hooksBinaryURL found during startup.
    func applyStartupDiscoveryPayload(_ payload: StartupDiscoveryPayload) {
        // Prune stale records if needed.
        if payload.codexRecordsNeedPrune {
            try? codexSessionStore.save(payload.codexRecords)
        }
        if payload.claudeRecordsNeedPrune {
            try? claudeSessionRegistry.save(payload.claudeRecords)
        }
        if payload.cursorRecordsNeedPrune {
            try? cursorSessionRegistry.save(payload.cursorRecords)
        }

        // Restore persisted Codex sessions.
        if !payload.codexRecords.isEmpty {
            state = SessionState(sessions: payload.codexRecords.map(\.restorableSession))
            onStatusMessage?("Restored \(payload.codexRecords.count) recent Codex session(s) from local cache.")
        }

        // Restore persisted Claude sessions.
        if !payload.claudeRecords.isEmpty {
            let restoredSessions = payload.claudeRecords.map(\.restorableSession)
            state = SessionState(sessions: mergeDiscoveredSessions(restoredSessions))
            onStatusMessage?("Restored \(payload.claudeRecords.count) recent Claude session(s) from local registry.")
        }

        // Restore persisted Cursor sessions.
        if !payload.cursorRecords.isEmpty {
            let restoredSessions = payload.cursorRecords.map(\.restorableSession)
            state = SessionState(sessions: mergeDiscoveredSessions(restoredSessions))
            onStatusMessage?("Restored \(payload.cursorRecords.count) recent Cursor session(s) from local registry.")
        }

        // Merge discovered Codex sessions.
        if !payload.discoveredCodexRecords.isEmpty {
            let mergedSessions = mergeDiscoveredSessions(payload.discoveredCodexRecords.map(\.session))
            state = SessionState(sessions: mergedSessions)
            scheduleCodexSessionPersistence()
            onStatusMessage?("Discovered \(payload.discoveredCodexRecords.count) recent Codex session(s) from local rollouts.")
        }

        // Merge discovered Claude sessions.
        if !payload.discoveredClaudeSessions.isEmpty {
            let mergedSessions = mergeDiscoveredSessions(payload.discoveredClaudeSessions)
            state = SessionState(sessions: mergedSessions)
            scheduleClaudeSessionPersistence()
            onStatusMessage?("Discovered \(payload.discoveredClaudeSessions.count) recent Claude session(s) from local transcripts.")
        }

        // Sync rollout tracking with current sessions.
        refreshCodexRolloutTracking()
    }

    // MARK: - Merge & discovery

    func mergeDiscoveredSessions(_ discoveredSessions: [AgentSession]) -> [AgentSession] {
        var mergedByID = Dictionary(uniqueKeysWithValues: state.sessions.map { ($0.id, $0) })

        for discovered in discoveredSessions {
            if let existing = mergedByID[discovered.id] {
                mergedByID[discovered.id] = merge(discovered: discovered, into: existing)
            } else if let existingID = existingSessionID(matchingTranscriptOf: discovered, in: mergedByID) {
                mergedByID[existingID] = merge(discovered: discovered, into: mergedByID[existingID]!)
            } else {
                mergedByID[discovered.id] = discovered
            }
        }

        return Array(mergedByID.values)
    }

    private func existingSessionID(
        matchingTranscriptOf discovered: AgentSession,
        in sessions: [String: AgentSession]
    ) -> String? {
        guard let discoveredPath = discovered.claudeMetadata?.transcriptPath,
              !discoveredPath.isEmpty else {
            return nil
        }

        return sessions.first(where: {
            $0.value.claudeMetadata?.transcriptPath == discoveredPath
        })?.key
    }

    private func merge(discovered: AgentSession, into existing: AgentSession) -> AgentSession {
        var merged = existing
        let discoveredIsNewer = discovered.updatedAt >= existing.updatedAt

        if discoveredIsNewer {
            merged.title = discovered.title
            merged.phase = discovered.phase
            merged.summary = discovered.summary
            merged.updatedAt = discovered.updatedAt
            merged.permissionRequest = discovered.permissionRequest
            merged.questionPrompt = discovered.questionPrompt
        }

        merged.origin = existing.origin ?? discovered.origin
        merged.attachmentState = mergeAttachmentState(existing.attachmentState, discovered.attachmentState)
        merged.jumpTarget = existing.jumpTarget ?? discovered.jumpTarget
        merged.codexMetadata = mergeCodexMetadata(existing.codexMetadata, discovered.codexMetadata)
        merged.claudeMetadata = mergeClaudeMetadata(existing.claudeMetadata, discovered.claudeMetadata)
        merged.cursorMetadata = mergeCursorMetadata(existing.cursorMetadata, discovered.cursorMetadata)

        return merged
    }

    private func mergeCursorMetadata(
        _ existing: CursorSessionMetadata?,
        _ discovered: CursorSessionMetadata?
    ) -> CursorSessionMetadata? {
        guard let existing else {
            return discovered?.isEmpty == true ? nil : discovered
        }

        guard let discovered else {
            return existing.isEmpty ? nil : existing
        }

        let merged = CursorSessionMetadata(
            conversationId: discovered.conversationId ?? existing.conversationId,
            generationId: discovered.generationId ?? existing.generationId,
            workspaceRoots: discovered.workspaceRoots ?? existing.workspaceRoots,
            initialUserPrompt: existing.initialUserPrompt ?? discovered.initialUserPrompt ?? discovered.lastUserPrompt,
            lastUserPrompt: discovered.lastUserPrompt ?? existing.lastUserPrompt,
            lastAssistantMessage: discovered.lastAssistantMessage ?? existing.lastAssistantMessage,
            currentTool: discovered.currentTool ?? existing.currentTool,
            currentToolInputPreview: discovered.currentToolInputPreview ?? existing.currentToolInputPreview,
            currentCommandPreview: discovered.currentCommandPreview ?? existing.currentCommandPreview,
            model: discovered.model ?? existing.model,
            transcriptPath: discovered.transcriptPath ?? existing.transcriptPath
        )
        return merged.isEmpty ? nil : merged
    }

    private func mergeAttachmentState(
        _ existing: SessionAttachmentState,
        _ discovered: SessionAttachmentState
    ) -> SessionAttachmentState {
        switch (existing, discovered) {
        case (.attached, _), (_, .attached):
            .attached
        case (.stale, _), (_, .stale):
            .stale
        case (.detached, .detached):
            .detached
        }
    }

    private func mergeCodexMetadata(
        _ existing: CodexSessionMetadata?,
        _ discovered: CodexSessionMetadata?
    ) -> CodexSessionMetadata? {
        guard let existing else {
            return discovered?.isEmpty == true ? nil : discovered
        }

        guard let discovered else {
            return existing.isEmpty ? nil : existing
        }

        let merged = CodexSessionMetadata(
            transcriptPath: discovered.transcriptPath ?? existing.transcriptPath,
            initialUserPrompt: existing.initialUserPrompt ?? discovered.initialUserPrompt ?? discovered.lastUserPrompt,
            lastUserPrompt: discovered.lastUserPrompt ?? existing.lastUserPrompt,
            lastAssistantMessage: discovered.lastAssistantMessage ?? existing.lastAssistantMessage,
            currentTool: discovered.currentTool ?? existing.currentTool,
            currentCommandPreview: discovered.currentCommandPreview ?? existing.currentCommandPreview
        )
        return merged.isEmpty ? nil : merged
    }

    private func mergeClaudeMetadata(
        _ existing: ClaudeSessionMetadata?,
        _ discovered: ClaudeSessionMetadata?
    ) -> ClaudeSessionMetadata? {
        guard let existing else {
            return discovered?.isEmpty == true ? nil : discovered
        }

        guard let discovered else {
            return existing.isEmpty ? nil : existing
        }

        let merged = ClaudeSessionMetadata(
            transcriptPath: discovered.transcriptPath ?? existing.transcriptPath,
            initialUserPrompt: existing.initialUserPrompt ?? discovered.initialUserPrompt ?? discovered.lastUserPrompt,
            lastUserPrompt: discovered.lastUserPrompt ?? existing.lastUserPrompt,
            lastAssistantMessage: discovered.lastAssistantMessage ?? existing.lastAssistantMessage,
            currentTool: discovered.currentTool ?? existing.currentTool,
            currentToolInputPreview: discovered.currentToolInputPreview ?? existing.currentToolInputPreview,
            model: discovered.model ?? existing.model,
            startupSource: discovered.startupSource ?? existing.startupSource,
            permissionMode: discovered.permissionMode ?? existing.permissionMode,
            agentID: discovered.agentID ?? existing.agentID,
            agentType: discovered.agentType ?? existing.agentType,
            worktreeBranch: discovered.worktreeBranch ?? existing.worktreeBranch,
            activeSubagents: existing.activeSubagents.isEmpty ? discovered.activeSubagents : existing.activeSubagents
        )
        return merged.isEmpty ? nil : merged
    }

    // MARK: - Rollout tracking

    func refreshCodexRolloutTracking() {
        let targets = state.sessions.compactMap { session -> CodexRolloutWatchTarget? in
            guard session.tool == .codex,
                  let transcriptPath = session.codexMetadata?.transcriptPath,
                  !transcriptPath.isEmpty else {
                return nil
            }

            return CodexRolloutWatchTarget(
                sessionID: session.id,
                transcriptPath: transcriptPath
            )
        }

        codexRolloutWatcher.sync(targets: targets)
    }

    // MARK: - Persistence scheduling

    func scheduleCodexSessionPersistence() {
        codexSessionPersistenceTask?.cancel()

        let records = state.sessions
            .filter { $0.isTrackedLiveCodexSession && $0.updatedAt >= Date.now.addingTimeInterval(-86_400) }
            .map(CodexTrackedSessionRecord.init(session:))
        let store = codexSessionStore

        codexSessionPersistenceTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(250))
            try? store.save(records)
        }
    }

    func scheduleClaudeSessionPersistence() {
        claudeSessionPersistenceTask?.cancel()

        let prefix = syntheticClaudeSessionPrefix
        let records = state.sessions
            .filter {
                ($0.tool == .claudeCode || $0.tool == .qwenCode)
                    && $0.isTrackedLiveSession
                    && (prefix.isEmpty || !$0.id.hasPrefix(prefix))
                    && $0.updatedAt >= Date.now.addingTimeInterval(-86_400)
                    && ($0.jumpTarget != nil || $0.claudeMetadata?.transcriptPath != nil)
            }
            .map(ClaudeTrackedSessionRecord.init(session:))
        let registry = claudeSessionRegistry

        claudeSessionPersistenceTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(250))
            try? registry.save(records)
        }
    }

    func scheduleCursorSessionPersistence() {
        cursorSessionPersistenceTask?.cancel()

        let records = state.sessions
            .filter {
                $0.tool == .cursor
                    && $0.isTrackedLiveSession
                    && $0.updatedAt >= Date.now.addingTimeInterval(-86_400)
                    && ($0.jumpTarget != nil || $0.cursorMetadata?.conversationId != nil)
            }
            .map(CursorTrackedSessionRecord.init(session:))
        let registry = cursorSessionRegistry

        cursorSessionPersistenceTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(250))
            try? registry.save(records)
        }
    }
}
