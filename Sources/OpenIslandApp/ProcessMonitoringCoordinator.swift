import Foundation
import Observation
import OpenIslandCore

typealias ActiveProcessSnapshot = ActiveAgentProcessDiscovery.ProcessSnapshot

@MainActor
@Observable
final class ProcessMonitoringCoordinator {

    var isResolvingInitialLiveSessions = false

    @ObservationIgnored
    var sessionStore: SessionStore?

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
    private var sessionAttachmentMonitorTask: Task<Void, Never>?

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
        guard let sessionStore else { return }

        let activeProcesses = activeProcesses ?? activeAgentProcessDiscovery.discover()

        // Discover/update Claude sessions from ~/.claude/sessions/ files.
        sessionStore.discoverClaudeSessions()

        // Compute alive session IDs from process discovery matching.
        let aliveIDs = sessionIDsWithAliveProcesses(activeProcesses: activeProcesses)

        // Compute terminal updates from process TTY adoption.
        let terminalUpdates = terminalUpdatesFromProcesses(activeProcesses: activeProcesses)

        // Update process liveness and terminal info in the store.
        sessionStore.reconcileProcesses(
            aliveSessionIDs: aliveIDs,
            terminalUpdates: terminalUpdates
        )

        // Prune sessions that are no longer visible.
        sessionStore.pruneInvisibleSessions()

        isResolvingInitialLiveSessions = false
        onSessionsReconciled?()
        onPersistenceNeeded?()
    }

    // MARK: - Event helpers

    func markSessionAttached(for event: AgentEvent) {
        guard let sessionStore, let sessionID = sessionID(for: event) else {
            return
        }

        guard var session = sessionStore.sessions[sessionID] else { return }
        // Already attached — no-op.
        guard session.processState != .alive || session.terminal == nil else { return }
        session.processState = .alive
        sessionStore.sessions[sessionID] = session
    }

    func markSessionProcessAlive(for event: AgentEvent) {
        guard let sessionStore, let sessionID = sessionID(for: event) else {
            return
        }

        guard var session = sessionStore.sessions[sessionID] else { return }
        session.processState = .alive
        sessionStore.sessions[sessionID] = session
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
        guard let sessionStore else { return [] }

        var aliveIDs: Set<String> = []
        let sessions = Array(sessionStore.sessions.values)

        // Codex sessions: match by session ID directly.
        let codexProcessIDs = Set(
            activeProcesses
                .filter { $0.tool == .codex }
                .compactMap(\.sessionID)
        )
        for session in sessions where session.tool == .codex && session.origin != .demo {
            if codexProcessIDs.contains(session.id) {
                aliveIDs.insert(session.id)
            }
        }

        // Claude sessions: reuse the multi-pass matching.
        let claudeProcesses = activeProcesses.filter { $0.tool == .claudeCode }
        let trackedClaudeSessions = sessions.filter { $0.tool == .claudeCode }
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
                          && $0.transcriptPath == transcriptPath
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
        let hasOpenCodeProcess = activeProcesses.contains { $0.tool == .openCode }
        if hasOpenCodeProcess {
            for session in sessions where session.tool == .openCode && session.origin != .demo {
                aliveIDs.insert(session.id)
            }
        }

        return aliveIDs
    }

    // MARK: - Terminal updates from process TTY adoption

    /// Compute terminal info updates by matching processes to sessions that lack terminal info.
    private func terminalUpdatesFromProcesses(
        activeProcesses: [ActiveProcessSnapshot]
    ) -> [String: TerminalInfo] {
        guard let sessionStore else { return [:] }

        var updates: [String: TerminalInfo] = [:]
        let claudeProcesses = activeProcesses.filter { $0.tool == .claudeCode }
        guard !claudeProcesses.isEmpty else { return updates }

        let sessions = Array(sessionStore.sessions.values)

        for process in claudeProcesses {
            guard let processTTY = process.terminalTTY, !processTTY.isEmpty else { continue }
            let processCWD = normalizedPathForMatching(process.workingDirectory)

            for session in sessions {
                guard session.tool == .claudeCode,
                      session.terminal == nil,
                      normalizedPathForMatching(session.workingDirectory) == processCWD,
                      !updates.keys.contains(session.id) else {
                    continue
                }

                let terminalApp = supportedTerminalApp(for: process.terminalApp) ?? process.terminalApp ?? "Unknown"
                updates[session.id] = TerminalInfo(
                    app: terminalApp,
                    tty: processTTY
                )
                break
            }
        }

        return updates
    }

    // MARK: - Process matching (TrackedSession-based)

    private func uniqueTrackedClaudeSession(
        for process: ActiveProcessSnapshot,
        sessions: [TrackedSession],
        claimedSessionIDs: Set<String>
    ) -> TrackedSession? {
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
            let candidates = claudeTrackedSessions(
                in: sessions,
                claimedSessionIDs: claimedSessionIDs,
                terminalTTY: nil,
                workingDirectory: workingDirectory
            ).filter { session in
                guard let sessionTTY = normalizedTTYForMatching(session.terminal?.tty) else {
                    // Session has no TTY (e.g., transcript-discovered) — allow CWD-only match.
                    return true
                }
                return processTTY == nil || sessionTTY == processTTY
            }
            if candidates.count == 1 {
                return candidates[0]
            }

            if candidates.count > 1 {
                return candidates.max(by: { $0.lastActivityAt < $1.lastActivityAt })
            }
        }

        return nil
    }

    private func claudeTrackedSessions(
        in sessions: [TrackedSession],
        claimedSessionIDs: Set<String>,
        terminalTTY: String?,
        workingDirectory: String?
    ) -> [TrackedSession] {
        sessions.filter { session in
            guard session.tool == .claudeCode,
                  !claimedSessionIDs.contains(session.id) else {
                return false
            }

            if let terminalTTY,
               normalizedTTYForMatching(session.terminal?.tty) != terminalTTY {
                return false
            }

            if let workingDirectory,
               normalizedPathForMatching(session.workingDirectory) != workingDirectory {
                return false
            }

            return true
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
