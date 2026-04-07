import Foundation
import Observation
import OpenIslandCore

typealias ActiveProcessSnapshot = ActiveAgentProcessDiscovery.ProcessSnapshot

@MainActor
@Observable
final class ProcessMonitoringCoordinator {

    var isResolvingInitialLiveSessions = false

    @ObservationIgnored
    var syntheticClaudeSessionPrefix = ""

    @ObservationIgnored
    var stateAccessor: (() -> SessionState)?

    @ObservationIgnored
    var stateUpdater: ((SessionState) -> Void)?

    @ObservationIgnored
    var onSessionsReconciled: (() -> Void)?

    @ObservationIgnored
    var onPersistenceNeeded: (() -> Void)?

    @ObservationIgnored
    let activeAgentProcessDiscovery = ActiveAgentProcessDiscovery()

    @ObservationIgnored
    private let terminalSessionAttachmentProbe = TerminalSessionAttachmentProbe()

    @ObservationIgnored
    private let terminalJumpTargetResolver = TerminalJumpTargetResolver()

    @ObservationIgnored
    private var syntheticStartedAtCache: [String: Date] = [:]

    @ObservationIgnored
    private var sessionAttachmentMonitorTask: Task<Void, Never>?

    private var state: SessionState {
        get { stateAccessor?() ?? SessionState() }
        set { stateUpdater?(newValue) }
    }

    // MARK: - Monitoring lifecycle

    func startMonitoringIfNeeded() {
        guard sessionAttachmentMonitorTask == nil else {
            return
        }

        sessionAttachmentMonitorTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                let discovery = self.activeAgentProcessDiscovery
                let probe = self.terminalSessionAttachmentProbe
                let (snapshots, ghosttyAvail, terminalAvail) = await Task.detached(priority: .utility) {
                    let s = discovery.discover()
                    let g = probe.ghosttySnapshotAvailability()
                    let t = probe.terminalSnapshotAvailability()
                    return (s, g, t)
                }.value
                self.reconcileSessionAttachments(
                    activeProcesses: snapshots,
                    ghosttyAvailability: ghosttyAvail,
                    terminalAvailability: terminalAvail
                )
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Reconciliation

    func reconcileSessionAttachments(
        activeProcesses: [ActiveProcessSnapshot]? = nil,
        ghosttyAvailability: TerminalSessionAttachmentProbe.SnapshotAvailability<TerminalSessionAttachmentProbe.GhosttyTerminalSnapshot>? = nil,
        terminalAvailability: TerminalSessionAttachmentProbe.SnapshotAvailability<TerminalSessionAttachmentProbe.TerminalTabSnapshot>? = nil
    ) {
        let activeProcesses = activeProcesses ?? activeAgentProcessDiscovery.discover()
        let sanitizedSessions = sanitizeCrossToolGhosttyJumpTargets(in: state.sessions)
        let sanitizedSessionsChanged = sanitizedSessions != state.sessions
        if sanitizedSessionsChanged {
            var current = state
            current.mergeSessions(sanitizedSessions)
            state = current
        }

        let syntheticSessions = buildSyntheticClaudeSessions(
            existingSessions: state.sessions,
            activeProcesses: activeProcesses
        )
        let syntheticSessionsChanged = !syntheticSessions.isEmpty
        if syntheticSessionsChanged {
            var current = state
            current.mergeSessions(syntheticSessions)
            state = current
        }

        // Remove synthetic sessions whose process is no longer running.
        let activeSyntheticIDs = Set(syntheticSessions.map(\.id))
        pruneGoneSyntheticSessions(activeIDs: activeSyntheticIDs)

        adoptProcessTTYsForClaudeSessions(activeProcesses: activeProcesses)

        let sessions = state.sessions.filter(\.isTrackedLiveSession)
        guard !sessions.isEmpty else {
            isResolvingInitialLiveSessions = false
            return
        }

        let resolutionReport: TerminalSessionAttachmentProbe.ResolutionReport
        if let ghosttyAvailability, let terminalAvailability {
            resolutionReport = terminalSessionAttachmentProbe.sessionResolutionReport(
                for: sessions,
                ghosttyAvailability: ghosttyAvailability,
                terminalAvailability: terminalAvailability,
                activeProcesses: activeProcesses,
                allowRecentAttachmentGrace: !isResolvingInitialLiveSessions
            )
        } else {
            resolutionReport = terminalSessionAttachmentProbe.sessionResolutionReport(
                for: sessions,
                activeProcesses: activeProcesses,
                allowRecentAttachmentGrace: !isResolvingInitialLiveSessions
            )
        }
        let resolutions = resolutionReport.resolutions
        let attachmentUpdates = resolutions.mapValues { $0.attachmentState }
        let jumpTargetUpdates = resolutions.reduce(into: [String: JumpTarget]()) { partialResult, entry in
            if let correctedJumpTarget = entry.value.correctedJumpTarget {
                partialResult[entry.key] = correctedJumpTarget
            }
        }

        let attachmentsChanged = state.reconcileAttachmentStates(attachmentUpdates)
        let jumpTargetsChanged = state.reconcileJumpTargets(jumpTargetUpdates)

        // Phase 1: populate isProcessAlive in parallel with existing system.
        let aliveIDs = sessionIDsWithAliveProcesses(activeProcesses: activeProcesses)
        let livenessChanges = state.markProcessLiveness(aliveSessionIDs: aliveIDs)

        // Resolve jump targets via the new focused resolver.
        let resolverJumpTargets = terminalJumpTargetResolver.resolveJumpTargets(
            for: state.sessions.filter(\.isTrackedLiveSession),
            activeProcesses: activeProcesses
        )
        if !resolverJumpTargets.isEmpty {
            _ = state.reconcileJumpTargets(resolverJumpTargets)
        }

        // Phase 4: remove sessions that are no longer visible.
        let removedInvisible = state.removeInvisibleSessions()

        guard sanitizedSessionsChanged || syntheticSessionsChanged || attachmentsChanged || jumpTargetsChanged || removedInvisible else {
            if resolutionReport.isAuthoritative {
                isResolvingInitialLiveSessions = false
            }
            return
        }

        if resolutionReport.isAuthoritative {
            isResolvingInitialLiveSessions = false
        }
        onSessionsReconciled?()
        onPersistenceNeeded?()
    }

    // MARK: - Event helpers

    func markSessionAttached(for event: AgentEvent) {
        guard let sessionID = sessionID(for: event) else {
            return
        }

        _ = state.reconcileAttachmentStates([sessionID: .attached])
    }

    func markSessionProcessAlive(for event: AgentEvent) {
        guard let sessionID = sessionID(for: event) else {
            return
        }

        state.markSingleSessionAlive(sessionID: sessionID)
    }

    private func sessionID(for event: AgentEvent) -> String? {
        switch event {
        case let .sessionStarted(payload):
            payload.sessionID
        case let .activityUpdated(payload):
            payload.sessionID
        case let .permissionRequested(payload):
            payload.sessionID
        case let .questionAsked(payload):
            payload.sessionID
        case let .sessionCompleted(payload):
            payload.sessionID
        case let .jumpTargetUpdated(payload):
            payload.sessionID
        case let .sessionMetadataUpdated(payload):
            payload.sessionID
        case let .claudeSessionMetadataUpdated(payload):
            payload.sessionID
        case let .openCodeSessionMetadataUpdated(payload):
            payload.sessionID
        case let .actionableStateResolved(payload):
            payload.sessionID
        }
    }

    // MARK: - Process liveness

    func sessionIDsWithAliveProcesses(
        activeProcesses: [ActiveProcessSnapshot]
    ) -> Set<String> {
        var aliveIDs: Set<String> = []
        let sessions = state.sessions

        // Codex sessions: match by session ID directly.
        let codexProcessIDs = Set(
            activeProcesses
                .filter { $0.tool == .codex }
                .compactMap(\.sessionID)
        )
        for session in sessions where session.tool == .codex && !session.isDemoSession {
            if codexProcessIDs.contains(session.id) {
                aliveIDs.insert(session.id)
            }
        }

        // Claude sessions: reuse the multi-pass matching from representedClaudeProcessKeys.
        let claudeProcesses = activeProcesses.filter { $0.tool == .claudeCode }
        let trackedClaudeSessions = sessions.filter { $0.tool == .claudeCode && !isSyntheticClaudeSession($0) }
        var claimedSessionIDs: Set<String> = []

        // Pass 1: exact session ID match.
        for process in claudeProcesses {
            guard let processSessionID = process.sessionID,
                  let matched = trackedClaudeSessions.first(where: {
                      !claimedSessionIDs.contains($0.id) && $0.id == processSessionID
                  }) else { continue }
            aliveIDs.insert(matched.id)
            claimedSessionIDs.insert(matched.id)
        }

        // Pass 2: transcript path match.
        for process in claudeProcesses {
            guard let transcriptPath = process.transcriptPath,
                  let matched = trackedClaudeSessions.first(where: {
                      !claimedSessionIDs.contains($0.id)
                          && $0.claudeMetadata?.transcriptPath == transcriptPath
                  }) else { continue }
            aliveIDs.insert(matched.id)
            claimedSessionIDs.insert(matched.id)
        }

        // Pass 3: TTY + CWD fallback match.
        for process in claudeProcesses {
            guard let matched = uniqueTrackedClaudeSession(
                for: process,
                sessions: trackedClaudeSessions,
                claimedSessionIDs: claimedSessionIDs
            ) else { continue }
            aliveIDs.insert(matched.id)
            claimedSessionIDs.insert(matched.id)
        }

        // OpenCode sessions: the JS plugin runs inside the OpenCode process.
        // We can't match by session ID (plugin doesn't expose it to ps), so
        // keep all OpenCode sessions alive as long as any OpenCode process exists.
        let hasOpenCodeProcess = activeProcesses.contains { $0.tool == .openCode }
        if hasOpenCodeProcess {
            for session in sessions where session.tool == .openCode && !session.isDemoSession {
                aliveIDs.insert(session.id)
            }
        }

        // Synthetic sessions: always alive if the process exists.
        let syntheticSessions = sessions.filter { isSyntheticClaudeSession($0) }
        for session in syntheticSessions {
            aliveIDs.insert(session.id)
        }

        return aliveIDs
    }

    // MARK: - Synthetic Claude sessions

    func buildSyntheticClaudeSessions(
        existingSessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot],
        now: Date = .now
    ) -> [AgentSession] {
        let activeClaudeProcesses = activeProcesses.filter { $0.tool == .claudeCode }
        let trackedClaudeSessions = existingSessions.filter {
            $0.tool == .claudeCode && !isSyntheticClaudeSession($0)
        }

        let representedProcessKeys = representedClaudeProcessKeys(
            sessions: trackedClaudeSessions,
            activeProcesses: activeClaudeProcesses
        )

        return activeClaudeProcesses
            .filter { !representedProcessKeys.contains(processIdentityKey($0)) }
            .sorted { processIdentityKey($0) < processIdentityKey($1) }
            .map { syntheticClaudeSession(for: $0, now: now) }
    }

    private func syntheticClaudeSession(
        for process: ActiveProcessSnapshot,
        now: Date
    ) -> AgentSession {
        let workingDirectory = process.workingDirectory
        let workspaceName = workingDirectory.map { WorkspaceNameResolver.workspaceName(for: $0) } ?? "Workspace"
        let terminalApp = supportedTerminalApp(for: process.terminalApp) ?? "Unknown"
        let identity = processIdentityKey(process)
        let sessionID = "\(syntheticClaudeSessionPrefix)\(identity)"

        let transcriptPath = process.transcriptPath
            ?? Self.inferredTranscriptPath(sessionID: process.sessionID, workingDirectory: workingDirectory)

        let startedAt: Date = syntheticStartedAtCache[sessionID] ?? {
            let resolved = transcriptPath.flatMap {
                ClaudeTranscriptDiscovery.firstTimestamp(inTranscriptAt: $0)
            } ?? now
            syntheticStartedAtCache[sessionID] = resolved
            return resolved
        }()

        let customTitle = transcriptPath.flatMap {
            ClaudeTranscriptDiscovery.sessionTitle(inTranscriptAt: $0)
        }
        let metadata: ClaudeSessionMetadata? = (transcriptPath != nil || customTitle != nil)
            ? ClaudeSessionMetadata(transcriptPath: transcriptPath, customTitle: customTitle)
            : nil

        var session = AgentSession(
            id: sessionID,
            title: "Claude · \(workspaceName)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Claude session detected from \(terminalApp).",
            startedAt: startedAt,
            updatedAt: startedAt,
            jumpTarget: JumpTarget(
                terminalApp: terminalApp,
                workspaceName: workspaceName,
                paneTitle: "Claude \(workspaceName)",
                workingDirectory: workingDirectory,
                terminalTTY: process.terminalTTY
            ),
            claudeMetadata: metadata
        )
        session.isProcessAlive = true
        return session
    }

    func isSyntheticClaudeSession(_ session: AgentSession) -> Bool {
        session.tool == .claudeCode && session.id.hasPrefix(syntheticClaudeSessionPrefix)
    }

    /// Remove synthetic sessions whose process is no longer detected.
    private func pruneGoneSyntheticSessions(activeIDs: Set<String>) {
        let allSessions = state.sessions
        let goneSynthetics = allSessions.filter {
            isSyntheticClaudeSession($0) && !activeIDs.contains($0.id)
        }

        guard !goneSynthetics.isEmpty else { return }

        for session in goneSynthetics {
            syntheticStartedAtCache.removeValue(forKey: session.id)
        }

        let remaining = allSessions.filter { session in
            !goneSynthetics.contains(where: { $0.id == session.id })
        }
        state = SessionState(sessions: remaining)
    }

    /// Derives the transcript path from session ID and working directory
    /// since Claude Code doesn't keep the file open (lsof can't find it).
    private static func inferredTranscriptPath(sessionID: String?, workingDirectory: String?) -> String? {
        guard let sessionID, let cwd = workingDirectory else { return nil }
        let encodedCWD = cwd.replacingOccurrences(of: "/", with: "-")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.claude/projects/\(encodedCWD)/\(sessionID).jsonl"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    // MARK: - Process matching

    private func representedClaudeProcessKeys(
        sessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot]
    ) -> Set<String> {
        let trackedClaudeSessions = sessions.filter { session in
            session.tool == .claudeCode && !isSyntheticClaudeSession(session)
        }

        var representedProcessKeys: Set<String> = []
        var claimedSessionIDs: Set<String> = []

        for process in activeProcesses {
            guard let processSessionID = process.sessionID,
                  let matchedSession = trackedClaudeSessions.first(where: {
                      !claimedSessionIDs.contains($0.id) && $0.id == processSessionID
                  }) else {
                continue
            }

            representedProcessKeys.insert(processIdentityKey(process))
            claimedSessionIDs.insert(matchedSession.id)
        }

        for process in activeProcesses {
            let processKey = processIdentityKey(process)
            guard !representedProcessKeys.contains(processKey),
                  let transcriptPath = process.transcriptPath,
                  let matchedSession = trackedClaudeSessions.first(where: {
                      !claimedSessionIDs.contains($0.id)
                          && $0.claudeMetadata?.transcriptPath == transcriptPath
                  }) else {
                continue
            }

            representedProcessKeys.insert(processKey)
            claimedSessionIDs.insert(matchedSession.id)
        }

        for process in activeProcesses {
            let processKey = processIdentityKey(process)
            guard !representedProcessKeys.contains(processKey),
                  let matchedSession = uniqueTrackedClaudeSession(
                      for: process,
                      sessions: trackedClaudeSessions,
                      claimedSessionIDs: claimedSessionIDs
                  ) else {
                continue
            }

            representedProcessKeys.insert(processKey)
            claimedSessionIDs.insert(matchedSession.id)
        }

        return representedProcessKeys
    }

    private func uniqueTrackedClaudeSession(
        for process: ActiveProcessSnapshot,
        sessions: [AgentSession],
        claimedSessionIDs: Set<String>
    ) -> AgentSession? {
        if let terminalTTY = normalizedTTYForMatching(process.terminalTTY),
           let workingDirectory = normalizedPathForMatching(process.workingDirectory) {
            let candidates = claudeTrackedSessions(
                in: sessions,
                claimedSessionIDs: claimedSessionIDs,
                terminalTTY: terminalTTY,
                workingDirectory: workingDirectory
            )
            if candidates.count == 1 {
                return candidates[0]
            }
        }

        if let terminalTTY = normalizedTTYForMatching(process.terminalTTY) {
            let candidates = claudeTrackedSessions(
                in: sessions,
                claimedSessionIDs: claimedSessionIDs,
                terminalTTY: terminalTTY,
                workingDirectory: nil
            )
            if candidates.count == 1 {
                return candidates[0]
            }
        }

        if let workingDirectory = normalizedPathForMatching(process.workingDirectory) {
            let processTTY = normalizedTTYForMatching(process.terminalTTY)
            // When matching by cwd alone, skip sessions whose TTY is known but
            // differs from the process — they belong to a different terminal and
            // should not consume this process's slot.
            let candidates = claudeTrackedSessions(
                in: sessions,
                claimedSessionIDs: claimedSessionIDs,
                terminalTTY: nil,
                workingDirectory: workingDirectory
            ).filter { session in
                guard let sessionTTY = normalizedTTYForMatching(session.jumpTarget?.terminalTTY) else {
                    // Session has no TTY.  Transcript-discovered sessions (terminal
                    // "Unknown") should not match a process that DOES have a TTY —
                    // they belong to a different (likely dead) process and matching
                    // here would keep them alive incorrectly.  Sessions with a known
                    // terminal app (e.g. hook-connected but missing TTY) are OK.
                    if processTTY != nil,
                       supportedTerminalApp(for: session.jumpTarget?.terminalApp) == nil {
                        return false
                    }
                    return true
                }
                return processTTY == nil || sessionTTY == processTTY
            }
            if candidates.count == 1 {
                return candidates[0]
            }

            if candidates.count > 1 {
                return candidates.max(by: { $0.updatedAt < $1.updatedAt })
            }
        }

        return nil
    }

    private func claudeTrackedSessions(
        in sessions: [AgentSession],
        claimedSessionIDs: Set<String>,
        terminalTTY: String?,
        workingDirectory: String?
    ) -> [AgentSession] {
        sessions.filter { session in
            guard session.tool == .claudeCode,
                  !claimedSessionIDs.contains(session.id) else {
                return false
            }

            if let terminalTTY,
               normalizedTTYForMatching(session.jumpTarget?.terminalTTY) != terminalTTY {
                return false
            }

            if let workingDirectory,
               normalizedPathForMatching(session.jumpTarget?.workingDirectory) != workingDirectory {
                return false
            }

            return true
        }
    }

    /// When a Claude session was matched to a process by cwd but has a nil or
    /// mismatched TTY, adopt the process's TTY so that the subsequent terminal
    /// attachment resolution can find and promote the session.
    private func adoptProcessTTYsForClaudeSessions(activeProcesses: [ActiveProcessSnapshot]) {
        let claudeProcesses = activeProcesses.filter { $0.tool == .claudeCode }
        guard !claudeProcesses.isEmpty else { return }

        var sessions = state.sessions
        var changed = false

        for process in claudeProcesses {
            guard let processTTY = process.terminalTTY, !processTTY.isEmpty else { continue }
            let processCWD = normalizedPathForMatching(process.workingDirectory)

            for index in sessions.indices {
                let session = sessions[index]
                guard session.tool == .claudeCode,
                      !isSyntheticClaudeSession(session),
                      let jumpTarget = session.jumpTarget,
                      normalizedPathForMatching(jumpTarget.workingDirectory) == processCWD,
                      normalizedTTYForMatching(jumpTarget.terminalTTY) != normalizedTTYForMatching(processTTY) else {
                    continue
                }

                // Only adopt if no other session already owns this TTY.
                let ttyAlreadyClaimed = sessions.contains { other in
                    other.id != session.id
                        && other.tool == .claudeCode
                        && normalizedTTYForMatching(other.jumpTarget?.terminalTTY) == normalizedTTYForMatching(processTTY)
                }
                guard !ttyAlreadyClaimed else { continue }

                // Only adopt if no other process has the same cwd and already
                // matches this session's TTY (would mean a different process owns it).
                let sessionOwnedByOtherProcess = claudeProcesses.contains { other in
                    normalizedTTYForMatching(other.terminalTTY) == normalizedTTYForMatching(session.jumpTarget?.terminalTTY)
                        && normalizedPathForMatching(other.workingDirectory) == processCWD
                }
                guard !sessionOwnedByOtherProcess else { continue }

                sessions[index].jumpTarget?.terminalTTY = processTTY
                sessions[index].attachmentState = .attached
                sessions[index].updatedAt = .now
                changed = true
                break
            }
        }

        if changed {
            state = SessionState(sessions: sessions)
        }
    }

    // MARK: - Cross-tool sanitization

    func sanitizeCrossToolGhosttyJumpTargets(in sessions: [AgentSession]) -> [AgentSession] {
        sessions.map { session in
            guard var jumpTarget = session.jumpTarget,
                  supportedTerminalApp(for: jumpTarget.terminalApp) == "Ghostty",
                  let hintedTool = toolHint(forGhosttyPaneTitle: jumpTarget.paneTitle),
                  hintedTool != session.tool else {
                return session
            }

            jumpTarget.terminalSessionID = nil
            jumpTarget.paneTitle = sanitizedGhosttyPaneTitle(for: session)

            var sanitizedSession = session
            sanitizedSession.jumpTarget = jumpTarget
            return sanitizedSession
        }
    }

    // MARK: - Display helpers

    func liveAttachmentKey(for session: AgentSession) -> String? {
        guard let jumpTarget = session.jumpTarget else {
            return nil
        }

        let terminalApp = supportedTerminalApp(for: jumpTarget.terminalApp)
            ?? jumpTarget.terminalApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terminalApp.isEmpty else {
            return nil
        }

        if let terminalSessionID = jumpTarget.terminalSessionID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !terminalSessionID.isEmpty {
            return "\(terminalApp.lowercased()):session:\(terminalSessionID.lowercased())"
        }

        if let terminalTTY = normalizedTTYForMatching(jumpTarget.terminalTTY) {
            return "\(terminalApp.lowercased()):tty:\(terminalTTY.lowercased())"
        }

        let paneTitle = jumpTarget.paneTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let workingDirectory = normalizedPathForMatching(jumpTarget.workingDirectory),
           !paneTitle.isEmpty {
            return "\(terminalApp.lowercased()):cwd:\(workingDirectory):title:\(paneTitle)"
        }

        if let workingDirectory = normalizedPathForMatching(jumpTarget.workingDirectory) {
            return "\(terminalApp.lowercased()):cwd:\(workingDirectory)"
        }

        return nil
    }

    // MARK: - Utilities

    private func processIdentityKey(_ process: ActiveProcessSnapshot) -> String {
        [
            process.sessionID,
            normalizedTTYForMatching(process.terminalTTY),
            normalizedPathForMatching(process.workingDirectory),
            supportedTerminalApp(for: process.terminalApp),
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    private func syntheticClaudeGroupKey(for process: ActiveProcessSnapshot) -> String? {
        if let workingDirectory = normalizedPathForMatching(process.workingDirectory) {
            return "cwd:\(workingDirectory)"
        }

        if let terminalTTY = normalizedTTYForMatching(process.terminalTTY) {
            return "tty:\(terminalTTY)"
        }

        return nil
    }

    private func syntheticClaudeGroupKey(for session: AgentSession) -> String? {
        if let workingDirectory = normalizedPathForMatching(session.jumpTarget?.workingDirectory) {
            return "cwd:\(workingDirectory)"
        }

        if let terminalTTY = normalizedTTYForMatching(session.jumpTarget?.terminalTTY) {
            return "tty:\(terminalTTY)"
        }

        return nil
    }

    func normalizedPathForMatching(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: value).standardizedFileURL.path.lowercased()
    }

    func normalizedTTYForMatching(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value.hasPrefix("/dev/") ? value : "/dev/\(value)"
    }

    func supportedTerminalApp(for value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }

        switch normalized {
        case "ghostty":
            return "Ghostty"
        case "terminal", "apple_terminal":
            return "Terminal"
        case "cmux":
            return "cmux"
        case "warp":
            return "Warp"
        default:
            return nil
        }
    }

    private func toolHint(forGhosttyPaneTitle value: String) -> AgentTool? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("codex") {
            return .codex
        }

        if normalized.contains("claude") {
            return .claudeCode
        }

        return nil
    }

    private func sanitizedGhosttyPaneTitle(for session: AgentSession) -> String {
        switch session.tool {
        case .codex:
            return "Codex \(session.id.prefix(8))"
        case .claudeCode:
            return "Claude \(session.id.prefix(8))"
        case .geminiCLI:
            return "Gemini \(session.id.prefix(8))"
        case .openCode:
            return "OpenCode \(session.id.prefix(8))"
        }
    }
}
