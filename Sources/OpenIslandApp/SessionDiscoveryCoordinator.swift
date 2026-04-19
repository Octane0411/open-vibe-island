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
        var openCodeRecords: [OpenCodeTrackedSessionRecord]
        var openCodeRecordsNeedPrune: Bool
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
    private let openCodeSessionRegistry = OpenCodeSessionRegistry()

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
    private var openCodeSessionPersistenceTask: Task<Void, Never>?

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

        let allOpenCode = (try? openCodeSessionRegistry.load()) ?? []
        let openCodeRecords = allOpenCode.filter { $0.updatedAt >= cutoff }

        let allCursor = (try? cursorSessionRegistry.load()) ?? []
        let cursorRecords = allCursor.filter { $0.updatedAt >= cutoff && $0.shouldRestoreToLiveState }

        let discoveredCodex = codexRolloutDiscovery.discoverRecentSessions()
        let discoveredClaude = claudeTranscriptDiscovery.discoverRecentSessions()

        return StartupDiscoveryPayload(
            codexRecords: codexRecords,
            codexRecordsNeedPrune: codexRecords != allCodex,
            claudeRecords: claudeRecords,
            claudeRecordsNeedPrune: claudeRecords != allClaude,
            openCodeRecords: openCodeRecords,
            openCodeRecordsNeedPrune: openCodeRecords != allOpenCode,
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
        if payload.openCodeRecordsNeedPrune {
            try? openCodeSessionRegistry.save(payload.openCodeRecords)
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

        // Restore persisted OpenCode sessions.
        if !payload.openCodeRecords.isEmpty {
            let restoredSessions = payload.openCodeRecords.map(\.restorableSession)
            state = SessionState(sessions: mergeDiscoveredSessions(restoredSessions))
            onStatusMessage?("Restored \(payload.openCodeRecords.count) recent OpenCode session(s) from local registry.")
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
        merged.openCodeMetadata = mergeOpenCodeMetadata(existing.openCodeMetadata, discovered.openCodeMetadata)
        merged.cursorMetadata = mergeCursorMetadata(existing.cursorMetadata, discovered.cursorMetadata)
        // Once a session is identified as a Codex.app session by any source
        // (hook or rediscovery), preserve that flag so liveness uses the
        // app-level check instead of subprocess polling.
        merged.isCodexAppSession = existing.isCodexAppSession || discovered.isCodexAppSession

        return merged
    }

    private func mergeOpenCodeMetadata(
        _ existing: OpenCodeSessionMetadata?,
        _ discovered: OpenCodeSessionMetadata?
    ) -> OpenCodeSessionMetadata? {
        guard let existing else {
            return discovered?.isEmpty == true ? nil : discovered
        }

        guard let discovered else {
            return existing.isEmpty ? nil : existing
        }

        let merged = OpenCodeSessionMetadata(
            initialUserPrompt: existing.initialUserPrompt ?? discovered.initialUserPrompt ?? discovered.lastUserPrompt,
            lastUserPrompt: discovered.lastUserPrompt ?? existing.lastUserPrompt,
            lastAssistantMessage: discovered.lastAssistantMessage ?? existing.lastAssistantMessage,
            currentTool: discovered.currentTool ?? existing.currentTool,
            currentToolInputPreview: discovered.currentToolInputPreview ?? existing.currentToolInputPreview,
            model: discovered.model ?? existing.model
        )
        return merged.isEmpty ? nil : merged
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
            // Codex.app sessions already get their lifecycle from hooks
            // (and eventually app-server). The rollout watcher would
            // duplicate completion notifications and is not needed.
            if session.isCodexAppSession {
                return nil
            }

            return CodexRolloutWatchTarget(
                sessionID: session.id,
                transcriptPath: transcriptPath
            )
        }

        codexRolloutWatcher.sync(targets: targets)
    }

    // MARK: - Codex.app periodic re-discovery

    @ObservationIgnored
    private var lastCodexAppRescanDate: Date = .distantPast

    /// Re-scan `~/.codex/sessions/` for rollout files not yet tracked.
    /// Called periodically when Codex.app is running as a fallback when
    /// the app-server connection is unavailable.  Throttled to at most
    /// once per 10 seconds.
    func rediscoverCodexAppSessionsIfNeeded() {
        let now = Date.now
        guard now.timeIntervalSince(lastCodexAppRescanDate) >= 10 else { return }
        lastCodexAppRescanDate = now

        let discovery = codexRolloutDiscovery
        Task.detached(priority: .utility) { [weak self] in
            let discovered = discovery.discoverRecentSessions()
            guard !discovered.isEmpty else { return }
            await MainActor.run { [weak self] in
                self?.applyCodexAppRediscovery(discovered)
            }
        }
    }

    private func applyCodexAppRediscovery(_ records: [CodexTrackedSessionRecord]) {
        let existingIDs = Set(state.sessions.filter { $0.tool == .codex }.map(\.id))
        let existingPaths = Set(state.sessions.compactMap(\.codexMetadata?.transcriptPath))

        let newRecords = records.filter { record in
            !existingIDs.contains(record.sessionID)
                && (record.codexMetadata?.transcriptPath).map { !existingPaths.contains($0) } ?? true
        }
        guard !newRecords.isEmpty else { return }

        let newSessions = newRecords.map { record -> AgentSession in
            var session = record.session
            session.isCodexAppSession = true
            session.isProcessAlive = true
            // Prefer the discovered record's cwd (sourced from the rollout
            // file's session_meta) over an empty fallback.
            let cwd = record.jumpTarget?.workingDirectory ?? ""
            if session.jumpTarget == nil {
                session.jumpTarget = JumpTarget(
                    terminalApp: "Codex.app",
                    workspaceName: URL(fileURLWithPath: cwd).lastPathComponent,
                    paneTitle: session.title,
                    workingDirectory: cwd.isEmpty ? nil : cwd,
                    codexThreadID: session.id
                )
            } else {
                session.jumpTarget?.terminalApp = "Codex.app"
                session.jumpTarget?.codexThreadID = session.id
            }
            return session
        }

        let merged = mergeDiscoveredSessions(newSessions)
        state = SessionState(sessions: merged)
        refreshCodexRolloutTracking()
        scheduleCodexSessionPersistence()
        onStatusMessage?("Discovered \(newRecords.count) new Codex.app session(s) via rollout re-scan.")
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
                $0.tool == .claudeCode
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

    func scheduleOpenCodeSessionPersistence() {
        openCodeSessionPersistenceTask?.cancel()

        let records = state.sessions
            .filter {
                $0.tool == .openCode
                    && $0.isTrackedLiveSession
                    && $0.updatedAt >= Date.now.addingTimeInterval(-86_400)
            }
            .map(OpenCodeTrackedSessionRecord.init(session:))
        let registry = openCodeSessionRegistry

        openCodeSessionPersistenceTask = Task.detached(priority: .utility) {
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
