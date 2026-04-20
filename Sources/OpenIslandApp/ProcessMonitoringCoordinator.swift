import AppKit
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

    /// Fires when Codex.app is detected as running / no longer running.
    @ObservationIgnored
    var onCodexAppRunningChanged: ((_ isRunning: Bool) -> Void)?

    @ObservationIgnored
    let activeAgentProcessDiscovery = ActiveAgentProcessDiscovery()

    @ObservationIgnored
    private let terminalSessionAttachmentProbe = TerminalSessionAttachmentProbe()

    @ObservationIgnored
    private let terminalJumpTargetResolver = TerminalJumpTargetResolver()

    @ObservationIgnored
    private var sessionAttachmentMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var wasCodexAppRunning = false

    private static let cursorStalenessTimeout: TimeInterval = 600  // 10 minutes

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
                let resolver = self.terminalJumpTargetResolver
                let liveSessions = self.state.sessions.filter(\.isTrackedLiveSession)
                let (snapshots, ghosttyAvail, terminalAvail, jumpTargets) = await Task.detached(priority: .utility) {
                    let s = discovery.discover()
                    let g = probe.ghosttySnapshotAvailability()
                    let t = probe.terminalSnapshotAvailability()
                    let j = resolver.resolveJumpTargets(for: liveSessions, activeProcesses: s)
                    return (s, g, t, j)
                }.value
                self.reconcileSessionAttachments(
                    activeProcesses: snapshots,
                    ghosttyAvailability: ghosttyAvail,
                    terminalAvailability: terminalAvail,
                    preResolvedJumpTargets: jumpTargets
                )
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Reconciliation

    func reconcileSessionAttachments(
        activeProcesses: [ActiveProcessSnapshot]? = nil,
        ghosttyAvailability: TerminalSessionAttachmentProbe.SnapshotAvailability<TerminalSessionAttachmentProbe.GhosttyTerminalSnapshot>? = nil,
        terminalAvailability: TerminalSessionAttachmentProbe.SnapshotAvailability<TerminalSessionAttachmentProbe.TerminalTabSnapshot>? = nil,
        preResolvedJumpTargets: [String: JumpTarget]? = nil
    ) {
        let activeProcesses = activeProcesses ?? activeAgentProcessDiscovery.discover()

        // Work on a local copy to avoid triggering didSet (and its queue.sync +
        // view invalidation) on every intermediate mutation.
        let originalState = state
        var local = originalState

        let sanitizedSessions = sanitizeCrossToolGhosttyJumpTargets(in: local.sessions)
        if sanitizedSessions != local.sessions {
            local = SessionState(sessions: sanitizedSessions)
        }

        let mergedSessions = mergedWithSyntheticClaudeSessions(
            existingSessions: local.sessions,
            activeProcesses: activeProcesses
        )
        if mergedSessions != local.sessions {
            local = SessionState(sessions: mergedSessions)
        }

        // Adopt process TTYs inline on local copy.
        adoptProcessTTYsForClaudeSessions(activeProcesses: activeProcesses, sessions: &local)

        // Detect Codex.app running state BEFORE the empty-sessions early
        // return — we need to fire the callback on a brand-new Codex.app
        // launch even when no sessions exist yet, so the app-server
        // coordinator can connect and report threads.
        let isCodexAppRunning = Self.isCodexDesktopAppRunning()
        if isCodexAppRunning != wasCodexAppRunning {
            wasCodexAppRunning = isCodexAppRunning
            onCodexAppRunningChanged?(isCodexAppRunning)
        }

        let sessions = local.sessions.filter(\.isTrackedLiveSession)
        guard !sessions.isEmpty else {
            // Flush local changes only if something actually changed.
            if local != originalState {
                state = local
            }
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

        _ = local.reconcileAttachmentStates(attachmentUpdates)
        _ = local.reconcileJumpTargets(jumpTargetUpdates)

        // Phase 1: populate isProcessAlive in parallel with existing system.
        let aliveIDs = sessionIDsWithAliveProcesses(activeProcesses: activeProcesses)
        _ = local.markProcessLiveness(
            aliveSessionIDs: aliveIDs,
            isCodexAppRunning: isCodexAppRunning
        )

        // Resolve jump targets via the new focused resolver.
        // When pre-resolved targets are provided (computed off-main-actor),
        // use them directly to avoid blocking the main thread with AppleScript calls.
        let resolverJumpTargets = preResolvedJumpTargets
            ?? terminalJumpTargetResolver.resolveJumpTargets(
                for: local.sessions.filter(\.isTrackedLiveSession),
                activeProcesses: activeProcesses
            )
        if !resolverJumpTargets.isEmpty {
            _ = local.reconcileJumpTargets(resolverJumpTargets)
        }

        // Phase 4: remove sessions that are no longer visible.
        _ = local.removeInvisibleSessions()

        // Single state assignment — triggers didSet exactly once.
        // Compare against the original snapshot to catch all mutations
        // (including liveness and resolver jump targets) and skip the
        // write when nothing actually changed, avoiding unnecessary
        // SwiftUI view invalidation.
        let anyChange = local != originalState
        if anyChange {
            state = local
        }

        guard anyChange else {
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
        case let .geminiSessionMetadataUpdated(payload):
            payload.sessionID
        case let .openCodeSessionMetadataUpdated(payload):
            payload.sessionID
        case let .cursorSessionMetadataUpdated(payload):
            payload.sessionID
        case let .actionableStateResolved(payload):
            payload.sessionID
        case let .claudeProcessExited(payload):
            payload.sessionID
        }
    }

    // MARK: - Process liveness

    /// Returns the set of session IDs whose backing agent process is still
    /// alive, based on ``ActiveProcessSnapshot`` matching and per-tool
    /// heuristics (e.g. bundle-ID liveness for Cursor, PID matching for
    /// Codex/Claude/Gemini).
    func sessionIDsWithAliveProcesses(
        activeProcesses: [ActiveProcessSnapshot]
    ) -> Set<String> {
        var aliveIDs: Set<String> = []
        let sessions = state.sessions

        // Codex CLI sessions: match by session ID directly.
        let codexProcessIDs = Set(
            activeProcesses
                .filter { $0.tool == .codex }
                .compactMap(\.sessionID)
        )
        // Codex.app sessions: keep alive while the desktop app is running.
        let isCodexAppRunning = Self.isCodexDesktopAppRunning()
        for session in sessions where session.tool == .codex && !session.isDemoSession {
            if session.isCodexAppSession {
                if isCodexAppRunning { aliveIDs.insert(session.id) }
            } else if codexProcessIDs.contains(session.id) {
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

        // OpenCode sessions are hook-managed, but OpenCode does not expose a stable
        // session ID through process discovery. Match each active OpenCode process
        // to at most one tracked session.
        let openCodeProcesses = activeProcesses.filter { $0.tool == .openCode }
        // Do not filter by `isHookManaged` here because restored sessions drop that flag.
        let trackedOpenCodeSessions = sessions.filter { $0.tool == .openCode && !$0.isDemoSession }
        var claimedOpenCodeSessionIDs: Set<String> = []
        var hasUnmatchedOpenCodeProcess = false

        for process in openCodeProcesses {
            let matchResult = uniqueTrackedOpenCodeSession(
                for: process,
                sessions: trackedOpenCodeSessions,
                claimedSessionIDs: claimedOpenCodeSessionIDs
            )
            switch matchResult {
            case .matched(let matched):
                aliveIDs.insert(matched.id)
                claimedOpenCodeSessionIDs.insert(matched.id)
            case .ambiguous:
                hasUnmatchedOpenCodeProcess = true
            case .rejectedConflict:
                break
            }
        }

        // Fallback: If there are active OpenCode processes that we couldn't uniquely
        // match, keep all remaining unclaimed OpenCode sessions alive to prevent
        // incorrectly marking them as ended.
        if hasUnmatchedOpenCodeProcess {
            for session in trackedOpenCodeSessions where !claimedOpenCodeSessionIDs.contains(session.id) {
                aliveIDs.insert(session.id)
            }
        }

        // Gemini sessions are hook-managed, but Gemini does not expose a stable
        // session ID through process discovery. Match each active Gemini process
        // to at most one tracked session, preferring the freshest transcript in
        // the same workspace while still keeping idle transcripts alive as long
        // as the Gemini CLI process remains running.
        let geminiProcesses = activeProcesses.filter { $0.tool == .geminiCLI }
        let trackedGeminiSessions = sessions.filter { $0.tool == .geminiCLI && !$0.isDemoSession }
        var claimedGeminiSessionIDs: Set<String> = []
        for process in geminiProcesses {
            guard let matched = uniqueTrackedGeminiSession(
                for: process,
                sessions: trackedGeminiSessions,
                claimedSessionIDs: claimedGeminiSessionIDs
            ) else {
                continue
            }
            aliveIDs.insert(matched.id)
            claimedGeminiSessionIDs.insert(matched.id)
        }

        // Kimi sessions are hook-managed and use UUIDs that Open Island cannot
        // recover from ps/lsof. As long as any kimi process exists, keep every
        // tracked Kimi session alive so Stop/completed sessions don't get
        // evicted by the hook-managed liveness fallback in
        // SessionState.markProcessLiveness.
        let hasKimiProcess = activeProcesses.contains { $0.tool == .kimiCLI }
        if hasKimiProcess {
            for session in sessions where session.tool == .kimiCLI && !session.isDemoSession {
                aliveIDs.insert(session.id)
            }
        }

        // Cursor sessions: Cursor is an Electron IDE — we cannot match
        // individual session IDs from ps/lsof.  Keep Cursor sessions alive
        // while Cursor.app is running, but let completed sessions expire
        // after a staleness window so the notch clears when the user is
        // no longer interacting with the conversation.  Cursor has no
        // "tab closed" hook, so this timeout is the best available proxy.
        let isCursorRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.todesktop.230313mzl4w4u92"
        ).isEmpty
        if isCursorRunning {
            for session in sessions where session.tool == .cursor && !session.isDemoSession {
                if session.isSessionEnded { continue }
                let isStale = session.phase == .completed
                    && session.updatedAt.addingTimeInterval(Self.cursorStalenessTimeout) < Date.now
                if !isStale {
                    aliveIDs.insert(session.id)
                }
            }
        }

        // Synthetic sessions: always alive if the process exists.
        let syntheticSessions = sessions.filter { isSyntheticClaudeSession($0) }
        for session in syntheticSessions {
            aliveIDs.insert(session.id)
        }

        return aliveIDs
    }

    private enum OpenCodeMatchResult {
        case matched(AgentSession)
        case ambiguous
        case rejectedConflict
    }

    private func uniqueTrackedOpenCodeSession(
        for process: ActiveProcessSnapshot,
        sessions: [AgentSession],
        claimedSessionIDs: Set<String>
    ) -> OpenCodeMatchResult {
        let unclaimedSessions = sessions.filter { !claimedSessionIDs.contains($0.id) }
        guard !unclaimedSessions.isEmpty else {
            return .ambiguous
        }

        if let terminalTTY = normalizedTTYForMatching(process.terminalTTY) {
            let candidates = unclaimedSessions.filter {
                normalizedTTYForMatching($0.jumpTarget?.terminalTTY) == terminalTTY
            }
            if candidates.count == 1 {
                let candidate = candidates[0]
                if let processCWD = normalizedPathForMatching(process.workingDirectory),
                   let sessionCWD = normalizedPathForMatching(candidate.jumpTarget?.workingDirectory),
                   processCWD != sessionCWD {
                    // TTY matched, but CWD explicitly differs (e.g., terminal tab was reused in another directory).
                    return .rejectedConflict
                }
                return .matched(candidate)
            }
            if !candidates.isEmpty {
                if let processCWD = normalizedPathForMatching(process.workingDirectory) {
                    let cwdCandidates = candidates.filter {
                        normalizedPathForMatching($0.jumpTarget?.workingDirectory) == processCWD
                    }
                    if cwdCandidates.count == 1 {
                        return .matched(cwdCandidates[0])
                    }
                }
                return .ambiguous
            }
        }

        if let processCWD = normalizedPathForMatching(process.workingDirectory) {
            let workspaceMatches = unclaimedSessions.filter {
                normalizedPathForMatching($0.jumpTarget?.workingDirectory) == processCWD
            }
            if workspaceMatches.count == 1 {
                return .matched(workspaceMatches[0])
            }
        }

        // We require at least a positive match on TTY or CWD.
        // Do not blindly link the process just because only one session remains.
        return .ambiguous
    }

    private func uniqueTrackedGeminiSession(
        for process: ActiveProcessSnapshot,
        sessions: [AgentSession],
        claimedSessionIDs: Set<String>
    ) -> AgentSession? {
        let unclaimedSessions = sessions.filter { !claimedSessionIDs.contains($0.id) }
        guard !unclaimedSessions.isEmpty else {
            return nil
        }

        if let transcriptPath = process.transcriptPath,
           let transcriptMatched = unclaimedSessions.first(where: { $0.geminiMetadata?.transcriptPath == transcriptPath }) {
            return transcriptMatched
        }

        if let processWorkingDirectory = process.workingDirectory {
            let workspaceMatches = unclaimedSessions.filter {
                $0.jumpTarget?.workingDirectory == processWorkingDirectory
            }
            if !workspaceMatches.isEmpty {
                return preferredGeminiSession(from: workspaceMatches)
            }
            return nil
        }

        return unclaimedSessions.count == 1 ? unclaimedSessions[0] : nil
    }

    private func preferredGeminiSession(from sessions: [AgentSession]) -> AgentSession? {
        sessions.max { lhs, rhs in
            let lhsDate = modificationDate(atPath: lhs.geminiMetadata?.transcriptPath) ?? .distantPast
            let rhsDate = modificationDate(atPath: rhs.geminiMetadata?.transcriptPath) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhsDate < rhsDate
        }
    }

    private func modificationDate(atPath path: String?) -> Date? {
        guard let path, !path.isEmpty else {
            return nil
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date
    }

    // MARK: - Synthetic Claude sessions

    func mergedWithSyntheticClaudeSessions(
        existingSessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot],
        now: Date = .now
    ) -> [AgentSession] {
        let baseSessions = existingSessions.filter { !isSyntheticClaudeSession($0) }
        let syntheticSessions = syntheticClaudeSessions(
            existingSessions: baseSessions,
            activeProcesses: activeProcesses,
            now: now
        )

        return baseSessions + syntheticSessions
    }

    private func syntheticClaudeSessions(
        existingSessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot],
        now: Date
    ) -> [AgentSession] {
        let activeClaudeProcesses = activeProcesses.filter { process in
            process.tool == .claudeCode
        }
        let trackedClaudeSessions = existingSessions.filter { session in
            session.tool == .claudeCode && !isSyntheticClaudeSession(session)
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

        var session = AgentSession(
            id: "\(syntheticClaudeSessionPrefix)\(identity)",
            title: "Claude · \(workspaceName)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Claude session detected from \(terminalApp).",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: terminalApp,
                workspaceName: workspaceName,
                paneTitle: "Claude \(workspaceName)",
                workingDirectory: workingDirectory,
                terminalTTY: process.terminalTTY,
                tmuxTarget: process.tmuxTarget,
                tmuxSocketPath: process.tmuxSocketPath
            )
        )
        session.isProcessAlive = true
        return session
    }

    func isSyntheticClaudeSession(_ session: AgentSession) -> Bool {
        session.tool == .claudeCode && session.id.hasPrefix(syntheticClaudeSessionPrefix)
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
    @discardableResult
    private func adoptProcessTTYsForClaudeSessions(
        activeProcesses: [ActiveProcessSnapshot],
        sessions localState: inout SessionState
    ) -> Bool {
        let claudeProcesses = activeProcesses.filter { $0.tool == .claudeCode }
        guard !claudeProcesses.isEmpty else { return false }

        var sessions = localState.sessions
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
            localState = SessionState(sessions: sessions)
        }
        return changed
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

    /// Check whether Codex.app is currently running.  Uses
    /// `NSWorkspace.shared.runningApplications` directly because
    /// `NSRunningApplication.runningApplications(withBundleIdentifier:)`
    /// has been observed to intermittently return an empty array even
    /// when the app is running (likely a brief indexing window after
    /// app launch / conversation switch), which would cause Open Island
    /// to incorrectly kill visible Codex sessions.
    static func isCodexDesktopAppRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.openai.codex"
        }
    }

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
        // Standalone terminals
        case "ghostty":
            return "Ghostty"
        case "terminal", "apple_terminal":
            return "Terminal"
        case "iterm", "iterm2", "iterm.app":
            return "iTerm"
        case "cmux":
            return "cmux"
        case "warp", "warpterminal":
            return "Warp"
        case "kaku":
            return "Kaku"
        case "wezterm":
            return "WezTerm"
        case "zellij":
            return "Zellij"
        // VS Code family
        case "vscode", "code", "visual studio code":
            return "VS Code"
        case "vscode-insiders", "code-insiders":
            return "VS Code Insiders"
        case "cursor":
            return "Cursor"
        case "windsurf":
            return "Windsurf"
        case "trae":
            return "Trae"
        // JetBrains family
        case "intellij", "idea":
            return "IntelliJ IDEA"
        case "webstorm":
            return "WebStorm"
        case "pycharm":
            return "PyCharm"
        case "goland":
            return "GoLand"
        case "clion":
            return "CLion"
        case "rubymine":
            return "RubyMine"
        case "phpstorm":
            return "PhpStorm"
        case "rider":
            return "Rider"
        case "rustrover":
            return "RustRover"
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
        case .qoder:
            return "Qoder \(session.id.prefix(8))"
        case .qwenCode:
            return "Qwen Code \(session.id.prefix(8))"
        case .factory:
            return "Factory \(session.id.prefix(8))"
        case .codebuddy:
            return "CodeBuddy \(session.id.prefix(8))"
        case .cursor:
            return "Cursor \(session.id.prefix(8))"
        case .kimiCLI:
            return "Kimi \(session.id.prefix(8))"
        }
    }
}
