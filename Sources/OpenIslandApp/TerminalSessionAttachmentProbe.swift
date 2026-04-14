import AppKit
import Foundation
import OpenIslandCore

struct TerminalSessionAttachmentProbe {
    struct SessionResolution {
        var attachmentState: SessionAttachmentState
        var correctedJumpTarget: JumpTarget?
    }

    struct ResolutionReport {
        var resolutions: [String: SessionResolution]
        var isAuthoritative: Bool
    }

    typealias ActiveProcessSnapshot = ActiveAgentProcessDiscovery.ProcessSnapshot

    struct GhosttyTerminalSnapshot: Sendable {
        var sessionID: String
        var workingDirectory: String
        var title: String
    }

    struct TerminalTabSnapshot: Sendable {
        var tty: String
        var customTitle: String
    }

    struct ITermSessionSnapshot: Sendable {
        var sessionID: String
        var tty: String
        var title: String
    }

    enum SnapshotAvailability<Snapshot: Sendable>: Sendable {
        case unavailable(appIsRunning: Bool)
        case available([Snapshot], appIsRunning: Bool)

        var appIsRunning: Bool {
            switch self {
            case let .unavailable(appIsRunning):
                appIsRunning
            case let .available(_, appIsRunning):
                appIsRunning
            }
        }

        var hasExplicitSnapshotData: Bool {
            if case .available = self {
                return true
            }

            return false
        }

        var snapshots: [Snapshot]? {
            if case let .available(snapshots, _) = self {
                return snapshots
            }

            return nil
        }

        var isAuthoritative: Bool {
            if case .available = self {
                return true
            }

            return false
        }
    }

    private static let liveGraceWindow: TimeInterval = 120
    private static let staleGraceWindow: TimeInterval = 15 * 60
    private static let inactiveClaudeMatchWindow: TimeInterval = 120
    private static let appleScriptTimeout: TimeInterval = 1.0
    private static let fieldSeparator = "\u{1f}"
    private static let recordSeparator = "\u{1e}"

    func attachmentStates(
        for sessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot] = [],
        now: Date = .now
    ) -> [String: SessionAttachmentState] {
        sessionResolutionReport(
            for: sessions,
            ghosttyAvailability: ghosttySnapshotAvailability(),
            terminalAvailability: terminalSnapshotAvailability(),
            itermAvailability: itermSnapshotAvailability(),
            activeProcesses: activeProcesses,
            now: now
        ).resolutions.mapValues(\.attachmentState)
    }

    func sessionResolutions(
        for sessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot] = [],
        allowRecentAttachmentGrace: Bool = true,
        now: Date = .now
    ) -> [String: SessionResolution] {
        sessionResolutionReport(
            for: sessions,
            ghosttyAvailability: ghosttySnapshotAvailability(),
            terminalAvailability: terminalSnapshotAvailability(),
            itermAvailability: itermSnapshotAvailability(),
            activeProcesses: activeProcesses,
            allowRecentAttachmentGrace: allowRecentAttachmentGrace,
            now: now
        ).resolutions
    }

    func sessionResolutionReport(
        for sessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot] = [],
        allowRecentAttachmentGrace: Bool = true,
        now: Date = .now
    ) -> ResolutionReport {
        sessionResolutionReport(
            for: sessions,
            ghosttyAvailability: ghosttySnapshotAvailability(),
            terminalAvailability: terminalSnapshotAvailability(),
            itermAvailability: itermSnapshotAvailability(),
            activeProcesses: activeProcesses,
            allowRecentAttachmentGrace: allowRecentAttachmentGrace,
            now: now
        )
    }

    func sessionResolutionReport(
        for sessions: [AgentSession],
        ghosttyAvailability: SnapshotAvailability<GhosttyTerminalSnapshot>,
        terminalAvailability: SnapshotAvailability<TerminalTabSnapshot>,
        itermAvailability: SnapshotAvailability<ITermSessionSnapshot> = .available([], appIsRunning: false),
        activeProcesses: [ActiveProcessSnapshot] = [],
        allowRecentAttachmentGrace: Bool = true,
        now: Date = .now
    ) -> ResolutionReport {
        guard !sessions.isEmpty else {
            return ResolutionReport(
                resolutions: [:],
                isAuthoritative: ghosttyAvailability.isAuthoritative
                    && terminalAvailability.isAuthoritative
                    && itermAvailability.isAuthoritative
            )
        }

        let ghosttySessions = sessions.filter { normalizedTerminalName(for: $0.jumpTarget?.terminalApp) == "ghostty" }
        let terminalSessions = sessions.filter { normalizedTerminalName(for: $0.jumpTarget?.terminalApp) == "terminal" }
        let itermSessions = sessions.filter { normalizedTerminalName(for: $0.jumpTarget?.terminalApp) == "iterm" }
        let ambiguousSessions = sessions.filter { session in
            guard let terminalName = normalizedTerminalName(for: session.jumpTarget?.terminalApp) else {
                return true
            }

            return terminalName != "ghostty" && terminalName != "terminal"
                && terminalName != "iterm"
                && terminalName != "kaku" && terminalName != "wezterm"
        }
        let activeProcessesBySessionID = activeProcessesBySessionID(
            for: sessions,
            activeProcesses: activeProcesses
        )
        let activeSessionIDs = Set(activeProcessesBySessionID.keys)
        let attachedGhosttySessions = attachedGhosttySessions(
            for: ghosttySessions + ambiguousSessions,
            availability: ghosttyAvailability,
            activeSessionIDs: activeSessionIDs,
            activeProcessesBySessionID: activeProcessesBySessionID,
            now: now
        )
        let attachedTerminalSessions = attachedTerminalSessions(
            for: terminalSessions + ambiguousSessions,
            availability: terminalAvailability
        )
        let attachedITermSessions = attachedITermSessions(
            for: itermSessions + ambiguousSessions,
            availability: itermAvailability
        )

        var resolutions: [String: SessionResolution] = [:]

        for session in sessions {
            if ghosttySessions.contains(where: { $0.id == session.id })
                || attachedGhosttySessions[session.id] != nil {
                let matchedSnapshot = attachedGhosttySessions[session.id]
                resolutions[session.id] = SessionResolution(
                    attachmentState: resolveAttachmentState(
                        for: session,
                        isMatched: matchedSnapshot != nil,
                        isActiveProcess: activeProcessesBySessionID[session.id] != nil,
                        availability: ghosttyAvailability,
                        allowRecentAttachmentGrace: allowRecentAttachmentGrace,
                        now: now
                    ),
                    correctedJumpTarget: matchedSnapshot.flatMap { correctedGhosttyJumpTarget(for: session, snapshot: $0) }
                )
                continue
            }

            if itermSessions.contains(where: { $0.id == session.id })
                || attachedITermSessions[session.id] != nil {
                let matchedSnapshot = attachedITermSessions[session.id]
                resolutions[session.id] = SessionResolution(
                    attachmentState: resolveAttachmentState(
                        for: session,
                        isMatched: matchedSnapshot != nil,
                        isActiveProcess: activeProcessesBySessionID[session.id] != nil,
                        availability: itermAvailability,
                        allowRecentAttachmentGrace: allowRecentAttachmentGrace,
                        now: now
                    ),
                    correctedJumpTarget: matchedSnapshot.flatMap { correctedITermJumpTarget(for: session, snapshot: $0) }
                )
                continue
            }

            if terminalSessions.contains(where: { $0.id == session.id })
                || attachedTerminalSessions[session.id] != nil {
                let matchedSnapshot = attachedTerminalSessions[session.id]
                resolutions[session.id] = SessionResolution(
                    attachmentState: resolveAttachmentState(
                        for: session,
                        isMatched: matchedSnapshot != nil,
                        isActiveProcess: activeProcessesBySessionID[session.id] != nil,
                        availability: terminalAvailability,
                        allowRecentAttachmentGrace: allowRecentAttachmentGrace,
                        now: now
                    ),
                    correctedJumpTarget: matchedSnapshot.flatMap { correctedTerminalJumpTarget(for: session, snapshot: $0) }
                )
                continue
            }

            // For sessions from unsupported terminals, keep them
            // attached if they have an active process OR were recently active
            // via hooks (origin == .live and updated recently).
            // However, skip the recent-hook grace when the session's working
            // directory is contested: either another session at the same CWD
            // already owns a process, or an unassigned process shares the CWD
            // (ambiguous match).
            let isActiveProcess = activeProcessesBySessionID[session.id] != nil
            let cwdContested: Bool = {
                guard !isActiveProcess,
                      let cwd = normalizedPathForMatching(session.jumpTarget?.workingDirectory) else {
                    return false
                }
                let peerOwnsProcess = activeProcessesBySessionID.contains { entry in
                    entry.key != session.id
                        && normalizedPathForMatching(
                            sessions.first(where: { $0.id == entry.key })?.jumpTarget?.workingDirectory
                        ) == cwd
                }
                if peerOwnsProcess { return true }
                let unassignedProcessSharesCWD = activeProcesses.contains { process in
                    (process.tool == .claudeCode || process.tool == .qwenCode)
                        && !activeSessionIDs.contains(where: {
                            activeProcessesBySessionID[$0]?.terminalTTY == process.terminalTTY
                                && activeProcessesBySessionID[$0]?.workingDirectory == process.workingDirectory
                        })
                        && normalizedPathForMatching(process.workingDirectory) == cwd
                }
                return unassignedProcessSharesCWD
            }()
            let isRecentHookSession = !cwdContested
                && session.origin == .live
                && now.timeIntervalSince(session.updatedAt) < Self.staleGraceWindow
            resolutions[session.id] = SessionResolution(
                attachmentState: (isActiveProcess || isRecentHookSession)
                    ? .attached
                    : fallbackAttachmentState(
                        for: session,
                        appIsRunning: nil,
                        allowRecentAttachmentGrace: allowRecentAttachmentGrace,
                        now: now
                    ),
                correctedJumpTarget: nil
            )
        }

        // When a new session starts on the same TTY as an old session (e.g.
        // user closed Claude and reopened in the same terminal tab), both may
        // resolve as attached — the new one via process match, the old one via
        // grace period.  Keep only the most recently updated session per TTY.
        deduplicateAttachedSessionsByTTY(sessions: sessions, resolutions: &resolutions)

        return ResolutionReport(
            resolutions: resolutions,
            isAuthoritative: ghosttyAvailability.isAuthoritative
                && terminalAvailability.isAuthoritative
                && itermAvailability.isAuthoritative
        )
    }

    private func deduplicateAttachedSessionsByTTY(
        sessions: [AgentSession],
        resolutions: inout [String: SessionResolution]
    ) {
        var ttyOwners: [String: (sessionID: String, updatedAt: Date)] = [:]

        for session in sessions {
            guard let tty = normalizedTTYForMatching(session.jumpTarget?.terminalTTY),
                  resolutions[session.id]?.attachmentState == .attached else {
                continue
            }

            if let existing = ttyOwners[tty] {
                if session.updatedAt > existing.updatedAt {
                    resolutions[existing.sessionID]?.attachmentState = .stale
                    ttyOwners[tty] = (sessionID: session.id, updatedAt: session.updatedAt)
                } else {
                    resolutions[session.id]?.attachmentState = .stale
                }
            } else {
                ttyOwners[tty] = (sessionID: session.id, updatedAt: session.updatedAt)
            }
        }
    }

    func sessionResolutions(
        for sessions: [AgentSession],
        ghosttyAvailability: SnapshotAvailability<GhosttyTerminalSnapshot>,
        terminalAvailability: SnapshotAvailability<TerminalTabSnapshot>,
        itermAvailability: SnapshotAvailability<ITermSessionSnapshot> = .available([], appIsRunning: false),
        activeProcesses: [ActiveProcessSnapshot] = [],
        allowRecentAttachmentGrace: Bool = true,
        now: Date = .now
    ) -> [String: SessionResolution] {
        sessionResolutionReport(
            for: sessions,
            ghosttyAvailability: ghosttyAvailability,
            terminalAvailability: terminalAvailability,
            itermAvailability: itermAvailability,
            activeProcesses: activeProcesses,
            allowRecentAttachmentGrace: allowRecentAttachmentGrace,
            now: now
        ).resolutions
    }

    func attachmentStates(
        for sessions: [AgentSession],
        ghosttyAvailability: SnapshotAvailability<GhosttyTerminalSnapshot>,
        terminalAvailability: SnapshotAvailability<TerminalTabSnapshot>,
        itermAvailability: SnapshotAvailability<ITermSessionSnapshot> = .available([], appIsRunning: false),
        activeProcesses: [ActiveProcessSnapshot] = [],
        allowRecentAttachmentGrace: Bool = true,
        now: Date = .now
    ) -> [String: SessionAttachmentState] {
        sessionResolutionReport(
            for: sessions,
            ghosttyAvailability: ghosttyAvailability,
            terminalAvailability: terminalAvailability,
            itermAvailability: itermAvailability,
            activeProcesses: activeProcesses,
            allowRecentAttachmentGrace: allowRecentAttachmentGrace,
            now: now
        ).resolutions.mapValues(\.attachmentState)
    }

    private func resolveAttachmentState<Snapshot>(
        for session: AgentSession,
        isMatched: Bool,
        isActiveProcess: Bool,
        availability: SnapshotAvailability<Snapshot>,
        allowRecentAttachmentGrace: Bool,
        now: Date
    ) -> SessionAttachmentState {
        if isMatched {
            return .attached
        }

        if isActiveProcess {
            return .attached
        }

        return fallbackAttachmentState(
            for: session,
            appIsRunning: availability.appIsRunning,
            allowRecentAttachmentGrace: allowRecentAttachmentGrace && !availability.hasExplicitSnapshotData,
            now: now
        )
    }

    private func attachedGhosttySessions(
        for sessions: [AgentSession],
        availability: SnapshotAvailability<GhosttyTerminalSnapshot>,
        activeSessionIDs: Set<String>,
        activeProcessesBySessionID: [String: ActiveProcessSnapshot],
        now: Date
    ) -> [String: GhosttyTerminalSnapshot] {
        guard let snapshots = availability.snapshots else {
            return [:]
        }

        var assignments: [String: GhosttyTerminalSnapshot] = [:]
        var claimedSessionIDs: Set<String> = []
        var claimedSnapshotIDs: Set<String> = []

        for snapshot in snapshots where !claimedSnapshotIDs.contains(snapshot.sessionID) {
            let matches = sessions.filter { session in
                guard !claimedSessionIDs.contains(session.id) else {
                    return false
                }

                return snapshotTitleMentionsSessionID(snapshot, session: session)
            }

            guard let preferred = preferredSession(from: matches, activeSessionIDs: activeSessionIDs) else {
                continue
            }

            assignments[preferred.id] = snapshot
            claimedSessionIDs.insert(preferred.id)
            claimedSnapshotIDs.insert(snapshot.sessionID)
        }

        for snapshot in snapshots where !claimedSnapshotIDs.contains(snapshot.sessionID) {
            let matches = sessions.filter { session in
                exactGhosttySnapshotMatches(
                    snapshot,
                    session: session,
                    activeSessionIDs: activeSessionIDs,
                    now: now
                ) && activeSessionIDs.contains(session.id)
            }

            guard let preferred = preferredSession(from: matches, activeSessionIDs: activeSessionIDs) else {
                continue
            }

            assignments[preferred.id] = snapshot
            claimedSessionIDs.insert(preferred.id)
            claimedSnapshotIDs.insert(snapshot.sessionID)
        }

        for snapshot in snapshots where !claimedSnapshotIDs.contains(snapshot.sessionID) {
            let matches = sessions.filter { session in
                ghosttyFallbackCandidateMatches(
                    snapshot,
                    session: session,
                    claimedSessionIDs: claimedSessionIDs,
                    claimedSnapshotIDs: claimedSnapshotIDs,
                    activeSessionIDs: activeSessionIDs,
                    activeProcessesBySessionID: activeProcessesBySessionID,
                    requireActiveSession: true,
                    now: now
                )
            }

            guard let preferred = preferredSession(from: matches, activeSessionIDs: activeSessionIDs) else {
                continue
            }

            assignments[preferred.id] = snapshot
            claimedSessionIDs.insert(preferred.id)
            claimedSnapshotIDs.insert(snapshot.sessionID)
        }

        for snapshot in snapshots where !claimedSnapshotIDs.contains(snapshot.sessionID) {
            let matches = sessions.filter { session in
                !activeSessionIDs.contains(session.id)
                    && isRecentEnoughForInactiveMatch(session, now: now)
                    && exactGhosttySnapshotMatches(
                        snapshot,
                        session: session,
                        activeSessionIDs: activeSessionIDs,
                        now: now
                    )
            }

            guard let preferred = preferredSession(from: matches, activeSessionIDs: activeSessionIDs) else {
                continue
            }

            assignments[preferred.id] = snapshot
            claimedSessionIDs.insert(preferred.id)
            claimedSnapshotIDs.insert(snapshot.sessionID)
        }

        for snapshot in snapshots where !claimedSnapshotIDs.contains(snapshot.sessionID) {
            let matches = sessions.filter { session in
                isRecentEnoughForInactiveMatch(session, now: now)
                    && ghosttyFallbackCandidateMatches(
                        snapshot,
                        session: session,
                        claimedSessionIDs: claimedSessionIDs,
                        claimedSnapshotIDs: claimedSnapshotIDs,
                        activeSessionIDs: activeSessionIDs,
                        activeProcessesBySessionID: activeProcessesBySessionID,
                        requireActiveSession: false,
                        now: now
                    )
            }

            guard let preferred = preferredSession(from: matches, activeSessionIDs: activeSessionIDs) else {
                continue
            }

            assignments[preferred.id] = snapshot
            claimedSessionIDs.insert(preferred.id)
            claimedSnapshotIDs.insert(snapshot.sessionID)
        }

        return assignments
    }

    private func ghosttyFallbackCandidateMatches(
        _ snapshot: GhosttyTerminalSnapshot,
        session: AgentSession,
        claimedSessionIDs: Set<String>,
        claimedSnapshotIDs: Set<String>,
        activeSessionIDs: Set<String>,
        activeProcessesBySessionID: [String: ActiveProcessSnapshot],
        requireActiveSession: Bool,
        now: Date
    ) -> Bool {
        guard !claimedSessionIDs.contains(session.id) else {
            return false
        }

        let isActiveSession = activeSessionIDs.contains(session.id)
        if requireActiveSession && !isActiveSession {
            return false
        }

        guard snapshotLikelyHostsSession(
            snapshot,
            session: session,
            isActiveSession: isActiveSession,
            now: now
        ) else {
            return false
        }

        let jumpTarget = session.jumpTarget
        let activeProcess = activeProcessesBySessionID[session.id]

        let snapshotHint = hintedTool(for: snapshot.title)
        if let snapshotHint, session.tool != snapshotHint {
            return false
        }

        // When the snapshot title carries no tool hint (e.g. a plain shell
        // prompt like "~/project"), do not match it to agent sessions.  This
        // prevents Claude/Codex sessions from binding to an unrelated terminal
        // that just happens to share the same working directory.
        if snapshotHint == nil && (session.tool == .claudeCode || session.tool == .qwenCode || session.tool == .codex) {
            return false
        }

        if let jumpTarget {
            guard canFallbackFromRecordedGhosttySessionID(
                jumpTarget,
                allowRecordedSessionIDOverride: isActiveSession,
                claimedSnapshotIDs: claimedSnapshotIDs
            ) else {
                return false
            }
        }

        let candidateWorkingDirectory = normalizedPathForMatching(jumpTarget?.workingDirectory)
            ?? normalizedPathForMatching(activeProcess?.workingDirectory)
        if candidateWorkingDirectory == normalizedPathForMatching(snapshot.workingDirectory) {
            return true
        }

        return sessionWorkspaceNameCandidates(for: session).contains(snapshotWorkspaceName(for: snapshot))
    }

    private func exactGhosttySnapshotMatches(
        _ snapshot: GhosttyTerminalSnapshot,
        session: AgentSession,
        activeSessionIDs: Set<String>,
        now: Date
    ) -> Bool {
        guard nonEmptyValue(session.jumpTarget?.terminalSessionID) == snapshot.sessionID else {
            return false
        }

        return snapshotLikelyHostsSession(
            snapshot,
            session: session,
            isActiveSession: activeSessionIDs.contains(session.id),
            now: now
        )
    }

    private func snapshotLikelyHostsSession(
        _ snapshot: GhosttyTerminalSnapshot,
        session: AgentSession,
        isActiveSession: Bool,
        now: Date
    ) -> Bool {
        if let hintedTool = hintedTool(for: snapshot.title) {
            return hintedTool == session.tool
        }

        if isActiveSession {
            return true
        }

        return recentAttachmentGraceApplies(to: session, now: now)
    }

    private func canFallbackFromRecordedGhosttySessionID(
        _ jumpTarget: JumpTarget,
        allowRecordedSessionIDOverride: Bool,
        claimedSnapshotIDs: Set<String>
    ) -> Bool {
        if allowRecordedSessionIDOverride {
            return true
        }

        guard let recordedSessionID = nonEmptyValue(jumpTarget.terminalSessionID) else {
            return true
        }

        return claimedSnapshotIDs.contains(recordedSessionID)
    }

    private func sessionWorkspaceNameCandidates(for session: AgentSession) -> Set<String> {
        var candidates: Set<String> = []

        if let workspaceName = nonEmptyValue(session.jumpTarget?.workspaceName) {
            candidates.insert(workspaceName)
        }

        if let workingDirectory = nonEmptyValue(session.jumpTarget?.workingDirectory) {
            let derivedWorkspace = URL(fileURLWithPath: workingDirectory).lastPathComponent
            if !derivedWorkspace.isEmpty {
                candidates.insert(derivedWorkspace)
            }
        }

        let titlePieces = session.title
            .split(separator: "·", maxSplits: 1)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        if titlePieces.count == 2, !titlePieces[1].isEmpty {
            candidates.insert(titlePieces[1])
        }

        return candidates
    }

    private func snapshotWorkspaceName(for snapshot: GhosttyTerminalSnapshot) -> String {
        URL(fileURLWithPath: snapshot.workingDirectory).lastPathComponent
    }

    private func normalizedPathForMatching(_ value: String?) -> String? {
        guard let normalized = nonEmptyValue(value) else {
            return nil
        }

        return URL(fileURLWithPath: normalized).standardizedFileURL.path.lowercased()
    }

    private func normalizedTTYForMatching(_ value: String?) -> String? {
        guard let normalized = nonEmptyValue(value) else {
            return nil
        }

        if normalized.hasPrefix("/dev/") {
            return normalized
        }

        return "/dev/\(normalized)"
    }

    private func hintedTool(for title: String) -> AgentTool? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedTitle.contains("codex") {
            return .codex
        }

        if normalizedTitle.contains("claude") {
            return .claudeCode
        }

        if normalizedTitle.contains("qwen") {
            return .qwenCode
        }

        return nil
    }

    private func snapshotTitleMentionsSessionID(
        _ snapshot: GhosttyTerminalSnapshot,
        session: AgentSession
    ) -> Bool {
        let normalizedTitle = snapshot.title.lowercased()
        return sessionIDPrefixes(for: session).contains { normalizedTitle.contains($0) }
    }

    private func sessionIDPrefixes(for session: AgentSession) -> [String] {
        let normalizedID = session.id.lowercased()
        let prefixLengths = [normalizedID.count, 18, 13, 8]

        return prefixLengths.compactMap { length in
            guard length > 0, normalizedID.count >= length else {
                return nil
            }

            return String(normalizedID.prefix(length))
        }
    }

    private func attachedTerminalSessions(
        for sessions: [AgentSession],
        availability: SnapshotAvailability<TerminalTabSnapshot>
    ) -> [String: TerminalTabSnapshot] {
        guard let snapshots = availability.snapshots else {
            return [:]
        }

        return snapshots.reduce(into: [String: TerminalTabSnapshot]()) { partialResult, snapshot in
            guard let session = preferredSession(
                from: sessions.filter { terminalSnapshot(snapshot, matches: $0) }
            ) else {
                return
            }

            partialResult[session.id] = snapshot
        }
    }

    private func correctedGhosttyJumpTarget(
        for session: AgentSession,
        snapshot: GhosttyTerminalSnapshot
    ) -> JumpTarget? {
        let hadExistingJumpTarget = session.jumpTarget != nil
        var jumpTarget = session.jumpTarget ?? JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: URL(fileURLWithPath: snapshot.workingDirectory).lastPathComponent,
            paneTitle: snapshot.title,
            workingDirectory: snapshot.workingDirectory,
            terminalSessionID: snapshot.sessionID
        )

        // Zellij runs inside Ghostty but has its own jump-back mechanism
        // via pane IDs. Don't overwrite Zellij's terminal info with
        // Ghostty's session ID, as it would break Zellij pane targeting.
        if jumpTarget.terminalApp.lowercased() == "zellij" {
            return nil
        }

        var changed = !hadExistingJumpTarget

        if normalizedTerminalName(for: jumpTarget.terminalApp) != "ghostty" {
            jumpTarget.terminalApp = "Ghostty"
            changed = true
        }

        if nonEmptyValue(jumpTarget.terminalSessionID) != snapshot.sessionID {
            jumpTarget.terminalSessionID = snapshot.sessionID
            changed = true
        }

        if nonEmptyValue(jumpTarget.workingDirectory) != snapshot.workingDirectory {
            jumpTarget.workingDirectory = snapshot.workingDirectory
            changed = true
        }

        if let title = nonEmptyValue(snapshot.title), title != jumpTarget.paneTitle {
            jumpTarget.paneTitle = title
            changed = true
        }

        let workspaceName = URL(fileURLWithPath: snapshot.workingDirectory).lastPathComponent
        if !workspaceName.isEmpty, workspaceName != jumpTarget.workspaceName {
            jumpTarget.workspaceName = workspaceName
            changed = true
        }

        return changed ? jumpTarget : nil
    }

    private func correctedTerminalJumpTarget(
        for session: AgentSession,
        snapshot: TerminalTabSnapshot
    ) -> JumpTarget? {
        guard var jumpTarget = session.jumpTarget else {
            return nil
        }

        var changed = false

        if normalizedTerminalName(for: jumpTarget.terminalApp) != "terminal" {
            jumpTarget.terminalApp = "Terminal"
            changed = true
        }

        if nonEmptyValue(jumpTarget.terminalTTY) != snapshot.tty {
            jumpTarget.terminalTTY = snapshot.tty
            changed = true
        }

        if let title = nonEmptyValue(snapshot.customTitle),
           title != jumpTarget.paneTitle {
            jumpTarget.paneTitle = title
            changed = true
        }

        return changed ? jumpTarget : nil
    }

    // MARK: - iTerm attachment

    private func attachedITermSessions(
        for sessions: [AgentSession],
        availability: SnapshotAvailability<ITermSessionSnapshot>
    ) -> [String: ITermSessionSnapshot] {
        guard let snapshots = availability.snapshots else {
            return [:]
        }

        return snapshots.reduce(into: [String: ITermSessionSnapshot]()) { partialResult, snapshot in
            guard let session = preferredSession(
                from: sessions.filter { itermSnapshot(snapshot, matches: $0) }
            ) else {
                return
            }

            partialResult[session.id] = snapshot
        }
    }

    private func itermSnapshot(_ snapshot: ITermSessionSnapshot, matches session: AgentSession) -> Bool {
        guard let jumpTarget = session.jumpTarget else {
            return false
        }

        if let sessionID = nonEmptyValue(jumpTarget.terminalSessionID),
           snapshot.sessionID == sessionID {
            return true
        }

        if let tty = nonEmptyValue(jumpTarget.terminalTTY),
           snapshot.tty == tty {
            return true
        }

        guard let paneTitle = nonEmptyValue(jumpTarget.paneTitle) else {
            return false
        }

        return snapshot.title.contains(paneTitle)
    }

    private func correctedITermJumpTarget(
        for session: AgentSession,
        snapshot: ITermSessionSnapshot
    ) -> JumpTarget? {
        guard var jumpTarget = session.jumpTarget else {
            return nil
        }

        var changed = false

        if normalizedTerminalName(for: jumpTarget.terminalApp) != "iterm" {
            jumpTarget.terminalApp = "iTerm"
            changed = true
        }

        if nonEmptyValue(jumpTarget.terminalSessionID) != snapshot.sessionID {
            jumpTarget.terminalSessionID = snapshot.sessionID
            changed = true
        }

        if nonEmptyValue(jumpTarget.terminalTTY) != snapshot.tty {
            jumpTarget.terminalTTY = snapshot.tty
            changed = true
        }

        if let title = nonEmptyValue(snapshot.title),
           title != jumpTarget.paneTitle {
            jumpTarget.paneTitle = title
            changed = true
        }

        return changed ? jumpTarget : nil
    }

    private func ghosttySnapshot(_ snapshot: GhosttyTerminalSnapshot, matches session: AgentSession) -> Bool {
        guard let jumpTarget = session.jumpTarget else {
            return false
        }

        if let sessionID = nonEmptyValue(jumpTarget.terminalSessionID) {
            return snapshot.sessionID == sessionID
        }

        if let workingDirectory = nonEmptyValue(jumpTarget.workingDirectory) {
            return snapshot.workingDirectory == workingDirectory
        }

        guard let paneTitle = nonEmptyValue(jumpTarget.paneTitle) else {
            return false
        }

        return snapshot.title.contains(paneTitle)
    }

    private func terminalSnapshot(_ snapshot: TerminalTabSnapshot, matches session: AgentSession) -> Bool {
        guard let jumpTarget = session.jumpTarget else {
            return false
        }

        if let tty = nonEmptyValue(jumpTarget.terminalTTY) {
            return snapshot.tty == tty
        }

        guard let paneTitle = nonEmptyValue(jumpTarget.paneTitle) else {
            return false
        }

        return snapshot.customTitle.contains(paneTitle)
    }

    private func activeProcessesBySessionID(
        for sessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot]
    ) -> [String: ActiveProcessSnapshot] {
        var assignments: [String: ActiveProcessSnapshot] = [:]
        let activeCodexSessionIDs = Set(
            activeProcesses
                .filter { $0.tool == .codex }
                .compactMap(\.sessionID)
        )
        let activeClaudeProcesses = activeProcesses.filter { $0.tool == .claudeCode || $0.tool == .qwenCode }

        for session in sessions {
            if session.tool == .codex,
               activeCodexSessionIDs.contains(session.id),
               let matchedProcess = activeProcesses.first(where: { $0.tool == .codex && $0.sessionID == session.id }) {
                assignments[session.id] = matchedProcess
            }
        }

        var claimedClaudeSessionIDs = Set(assignments.keys)
        var claimedClaudeProcessIndexes: Set<Int> = []

        for (index, process) in activeClaudeProcesses.enumerated() {
            guard let processSessionID = nonEmptyValue(process.sessionID),
                  let matchedSession = sessions.first(where: {
                      $0.tool == .claudeCode
                          && !claimedClaudeSessionIDs.contains($0.id)
                          && $0.id == processSessionID
                  }) else {
                continue
            }

            assignments[matchedSession.id] = process
            claimedClaudeSessionIDs.insert(matchedSession.id)
            claimedClaudeProcessIndexes.insert(index)
        }

        for (index, process) in activeClaudeProcesses.enumerated() where !claimedClaudeProcessIndexes.contains(index) {
            guard let matchedSession = uniqueClaudeFallbackCandidate(
                for: process,
                sessions: sessions,
                claimedSessionIDs: claimedClaudeSessionIDs
            ) else {
                continue
            }

            assignments[matchedSession.id] = process
            claimedClaudeSessionIDs.insert(matchedSession.id)
            claimedClaudeProcessIndexes.insert(index)
        }

        return assignments
    }

    private func uniqueClaudeFallbackCandidate(
        for process: ActiveProcessSnapshot,
        sessions: [AgentSession],
        claimedSessionIDs: Set<String>
    ) -> AgentSession? {
        if let terminalTTY = normalizedTTYForMatching(process.terminalTTY),
           let workingDirectory = normalizedPathForMatching(process.workingDirectory) {
            let candidates = claudeCandidates(
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
            let candidates = claudeCandidates(
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
            let candidates = claudeCandidates(
                in: sessions,
                claimedSessionIDs: claimedSessionIDs,
                terminalTTY: nil,
                workingDirectory: workingDirectory
            )
            if candidates.count == 1 {
                return candidates[0]
            }
        }

        return nil
    }

    private func claudeCandidates(
        in sessions: [AgentSession],
        claimedSessionIDs: Set<String>,
        terminalTTY: String?,
        workingDirectory: String?
    ) -> [AgentSession] {
        sessions.filter { session in
            guard session.tool == .claudeCode || session.tool == .qwenCode,
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

    private func preferredSession(
        from sessions: [AgentSession],
        activeSessionIDs: Set<String> = []
    ) -> AgentSession? {
        sessions.sorted { lhs, rhs in
            let lhsIsActive = activeSessionIDs.contains(lhs.id)
            let rhsIsActive = activeSessionIDs.contains(rhs.id)
            if lhsIsActive != rhsIsActive {
                return lhsIsActive && !rhsIsActive
            }

            if phasePriority(lhs.phase) != phasePriority(rhs.phase) {
                return phasePriority(lhs.phase) > phasePriority(rhs.phase)
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }.first
    }

    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval:
            4
        case .waitingForAnswer:
            3
        case .running:
            2
        case .completed:
            1
        }
    }

    /// Claude Code sessions without an active process should only match
    /// Ghostty snapshots if they were updated very recently (within
    /// `inactiveClaudeMatchWindow`). This prevents old completed sessions
    /// from staying attached just because the terminal tab is still open.
    /// Non-Claude sessions (Codex) are always eligible.
    private func isRecentEnoughForInactiveMatch(_ session: AgentSession, now: Date) -> Bool {
        guard session.tool == .claudeCode || session.tool == .qwenCode else { return true }
        return now.timeIntervalSince(session.updatedAt) <= Self.inactiveClaudeMatchWindow
    }

    private func fallbackAttachmentState(
        for session: AgentSession,
        appIsRunning: Bool?,
        allowRecentAttachmentGrace: Bool,
        now: Date
    ) -> SessionAttachmentState {
        let age = now.timeIntervalSince(session.updatedAt)

        if allowRecentAttachmentGrace && recentAttachmentGraceApplies(to: session, now: now) {
            return .attached
        }

        if let appIsRunning, appIsRunning == false {
            return age <= Self.staleGraceWindow ? .stale : .detached
        }

        return age <= Self.staleGraceWindow ? .stale : .detached
    }

    private func recentAttachmentGraceApplies(
        to session: AgentSession,
        now: Date
    ) -> Bool {
        let age = now.timeIntervalSince(session.updatedAt)
        guard age <= Self.liveGraceWindow else {
            return false
        }

        guard session.attachmentState == .attached else {
            return false
        }

        return session.origin == .live
            || session.currentToolName?.isEmpty == false
    }

    func ghosttySnapshotAvailability() -> SnapshotAvailability<GhosttyTerminalSnapshot> {
        let appIsRunning = isRunning(bundleIdentifier: "com.mitchellh.ghostty")
        guard appIsRunning else {
            return .available([], appIsRunning: false)
        }

        do {
            return .available(try ghosttySnapshots(), appIsRunning: true)
        } catch {
            return .unavailable(appIsRunning: true)
        }
    }

    func terminalSnapshotAvailability() -> SnapshotAvailability<TerminalTabSnapshot> {
        let appIsRunning = isRunning(bundleIdentifier: "com.apple.Terminal")
        guard appIsRunning else {
            return .available([], appIsRunning: false)
        }

        do {
            return .available(try terminalSnapshots(), appIsRunning: true)
        } catch {
            return .unavailable(appIsRunning: true)
        }
    }

    func itermSnapshotAvailability() -> SnapshotAvailability<ITermSessionSnapshot> {
        let appIsRunning = isRunning(bundleIdentifier: "com.googlecode.iterm2")
        guard appIsRunning else {
            return .available([], appIsRunning: false)
        }

        do {
            return .available(try itermSnapshots(), appIsRunning: true)
        } catch {
            return .unavailable(appIsRunning: true)
        }
    }

    private func nonEmptyValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func ghosttySnapshots() throws -> [GhosttyTerminalSnapshot] {
        let script = """
        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        tell application "Ghostty"
            if not (it is running) then return ""
            set outputLines to {}
            repeat with aTerminal in terminals
                set terminalID to ""
                set terminalDirectory to ""
                set terminalTitle to ""
                try
                    set terminalID to (id of aTerminal as text)
                end try
                try
                    set terminalDirectory to (working directory of aTerminal as text)
                end try
                try
                    set terminalTitle to (name of aTerminal as text)
                end try
                set end of outputLines to terminalID & fieldSeparator & terminalDirectory & fieldSeparator & terminalTitle
            end repeat
            set AppleScript's text item delimiters to recordSeparator
            set joinedOutput to outputLines as string
            set AppleScript's text item delimiters to ""
            return joinedOutput
        end tell
        """

        let output = try runAppleScript(script)
        return output
            .split(separator: Character(Self.recordSeparator), omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap { line in
                let values = line.components(separatedBy: Self.fieldSeparator)
                guard values.count == 3 else {
                    return nil
                }

                return GhosttyTerminalSnapshot(
                    sessionID: values[0],
                    workingDirectory: values[1],
                    title: values[2]
                )
            }
    }

    private func terminalSnapshots() throws -> [TerminalTabSnapshot] {
        let script = """
        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        tell application "Terminal"
            if not (it is running) then return ""
            set outputLines to {}
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    set tabTTY to ""
                    set tabTitle to ""
                    try
                        set tabTTY to (tty of aTab as text)
                    end try
                    try
                        set tabTitle to (custom title of aTab as text)
                    end try
                    set end of outputLines to tabTTY & fieldSeparator & tabTitle
                end repeat
            end repeat
            set AppleScript's text item delimiters to recordSeparator
            set joinedOutput to outputLines as string
            set AppleScript's text item delimiters to ""
            return joinedOutput
        end tell
        """

        let output = try runAppleScript(script)
        return output
            .split(separator: Character(Self.recordSeparator), omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap { line in
                let values = line.components(separatedBy: Self.fieldSeparator)
                guard values.count == 2 else {
                    return nil
                }

                return TerminalTabSnapshot(
                    tty: values[0],
                    customTitle: values[1]
                )
            }
    }

    private func itermSnapshots() throws -> [ITermSessionSnapshot] {
        let script = """
        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        tell application "iTerm"
            if not (it is running) then return ""
            set outputLines to {}
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        set sessionID to ""
                        set sessionTTY to ""
                        set sessionTitle to ""
                        try
                            set sessionID to (id of aSession as text)
                        end try
                        try
                            set sessionTTY to (tty of aSession as text)
                        end try
                        try
                            set sessionTitle to (name of aSession as text)
                        end try
                        set end of outputLines to sessionID & fieldSeparator & sessionTTY & fieldSeparator & sessionTitle
                    end repeat
                end repeat
            end repeat
            set AppleScript's text item delimiters to recordSeparator
            set joinedOutput to outputLines as string
            set AppleScript's text item delimiters to ""
            return joinedOutput
        end tell
        """

        let output = try runAppleScript(script)
        return output
            .split(separator: Character(Self.recordSeparator), omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap { line in
                let values = line.components(separatedBy: Self.fieldSeparator)
                guard values.count == 3 else {
                    return nil
                }

                return ITermSessionSnapshot(
                    sessionID: values[0],
                    tty: values[1],
                    title: values[2]
                )
            }
    }

    private func normalizedTerminalName(for value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isRunning(bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }

    private func runAppleScript(_ script: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        let completionGroup = DispatchGroup()
        completionGroup.enter()
        task.terminationHandler = { _ in
            completionGroup.leave()
        }

        try task.run()
        let waitResult = completionGroup.wait(timeout: .now() + Self.appleScriptTimeout)
        if waitResult == .timedOut {
            task.terminate()
            _ = completionGroup.wait(timeout: .now() + 0.2)
            throw NSError(domain: "TerminalSessionAttachmentProbe", code: 408, userInfo: [
                NSLocalizedDescriptionKey: "AppleScript probe timed out.",
            ])
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard task.terminationStatus == 0 else {
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(domain: "TerminalSessionAttachmentProbe", code: Int(task.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: stderr.isEmpty ? "AppleScript probe failed." : stderr,
            ])
        }

        return output
    }
}
