import Foundation

// MARK: - SessionPhase sort priority

extension SessionPhase {
    /// Higher value = shown first in session list.
    var sortPriority: Int {
        switch self {
        case .waitingForApproval: return 4
        case .waitingForAnswer:   return 3
        case .running:            return 2
        case .completed:          return 1
        }
    }
}

// MARK: - SessionStore

/// Single owner of all `TrackedSession` state for the app UI layer.
///
/// Two data paths feed into the store:
///   1. **Hook events** (`applyHookEvent`) — real-time updates from the bridge as Claude Code
///      runs tools, asks questions, requests permission, etc. This is the authoritative path
///      for session phase, summary, metadata, and actionable state.
///   2. **Session file discovery** (`discoverClaudeSessions`) — periodic poll of
///      `~/.claude/sessions/*.json` that creates sessions for newly-appeared files and
///      removes sessions whose PID is no longer alive. This is the source of truth for
///      process liveness and session existence.
///
/// The store also supports `reconcileProcesses` for non-Claude agents (Codex) that rely
/// on process discovery via `ps`/`lsof` rather than session files.
@MainActor @Observable
public final class SessionStore {

    public init() {}

    // MARK: State

    /// Direct access to the sessions dictionary. Use `applyHookEvent` for authoritative updates.
    public var sessions: [String: TrackedSession] = [:]

    // MARK: Queries

    public func session(id: String?) -> TrackedSession? {
        guard let id else { return nil }
        return sessions[id]
    }

    /// All sessions that are visible right now, sorted by phase priority then activity then name.
    public var visibleSessions: [TrackedSession] {
        visibleSessions(at: .now)
    }

    /// All sessions visible at the given reference date, sorted consistently.
    public func visibleSessions(at referenceDate: Date) -> [TrackedSession] {
        sessions.values
            .filter { !$0.isSubagentSession && $0.isVisible(at: referenceDate) }
            .sorted { lhs, rhs in
                let lp = lhs.phase.sortPriority
                let rp = rhs.phase.sortPriority
                if lp != rp { return lp > rp }
                if lhs.lastActivityAt != rhs.lastActivityAt {
                    return lhs.lastActivityAt > rhs.lastActivityAt
                }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    /// The first session requiring user attention (permission or question), if any.
    public var actionableSession: TrackedSession? {
        visibleSessions.first { $0.phase.requiresAttention }
    }

    // MARK: Hook events (authoritative)

    /// Apply an AgentEvent from the bridge hook. This is the authoritative path;
    /// it creates sessions if necessary (except for sessionCompleted).
    public func applyHookEvent(_ event: AgentEvent) {
        switch event {

        case let .sessionStarted(payload):
            let existingStartedAt = sessions[payload.sessionID]?.startedAt
            let terminal = payload.jumpTarget.map { jt in
                TerminalInfo(
                    app: jt.terminalApp,
                    tty: jt.terminalTTY,
                    terminalSessionID: jt.terminalSessionID
                )
            }
            let meta = sessionMetadata(from: payload.claudeMetadata)
            let customTitle = payload.claudeMetadata?.customTitle
            let transcriptPath = payload.claudeMetadata?.transcriptPath

            let s = TrackedSession(
                id: payload.sessionID,
                tool: payload.tool,
                phase: payload.initialPhase,
                summary: payload.summary,
                startedAt: existingStartedAt ?? payload.timestamp,
                lastActivityAt: payload.timestamp,
                terminal: terminal,
                workingDirectory: payload.jumpTarget?.workingDirectory,
                permissionRequest: nil,
                questionPrompt: nil,
                processState: .alive,
                customTitle: customTitle,
                transcriptPath: transcriptPath,
                metadata: meta,
                isRemote: payload.isRemote,
                origin: payload.origin
            )
            sessions[payload.sessionID] = s

        case let .activityUpdated(payload):
            ensureSession(id: payload.sessionID, timestamp: payload.timestamp)
            guard var s = sessions[payload.sessionID] else { return }

            // Preserve actionable state if we're getting a spurious running update
            // while waiting for approval/answer and the pending item is still present.
            let keepsPendingApproval = payload.phase == .running
                && s.phase == .waitingForApproval
                && s.permissionRequest != nil
            let keepsPendingQuestion = payload.phase == .running
                && s.phase == .waitingForAnswer
                && s.questionPrompt != nil
            let preservesActionableState = keepsPendingApproval || keepsPendingQuestion

            if !preservesActionableState {
                s.phase = payload.phase
                s.summary = payload.summary
                if payload.phase != .waitingForApproval {
                    s.permissionRequest = nil
                }
                if payload.phase != .waitingForAnswer {
                    s.questionPrompt = nil
                }
            }
            s.lastActivityAt = payload.timestamp
            sessions[payload.sessionID] = s

        case let .permissionRequested(payload):
            ensureSession(id: payload.sessionID, timestamp: payload.timestamp)
            guard var s = sessions[payload.sessionID] else { return }
            s.phase = .waitingForApproval
            s.summary = payload.request.summary
            s.permissionRequest = payload.request
            s.questionPrompt = nil
            s.lastActivityAt = payload.timestamp
            sessions[payload.sessionID] = s

        case let .questionAsked(payload):
            ensureSession(id: payload.sessionID, timestamp: payload.timestamp)
            guard var s = sessions[payload.sessionID] else { return }
            s.phase = .waitingForAnswer
            s.summary = payload.prompt.title
            s.questionPrompt = payload.prompt
            s.permissionRequest = nil
            s.lastActivityAt = payload.timestamp
            sessions[payload.sessionID] = s

        case let .sessionCompleted(payload):
            // Only update existing sessions — don't create for completion events.
            guard var s = sessions[payload.sessionID] else { return }
            s.phase = .completed
            s.summary = payload.summary
            s.permissionRequest = nil
            s.questionPrompt = nil
            s.lastActivityAt = payload.timestamp
            sessions[payload.sessionID] = s

        case let .jumpTargetUpdated(payload):
            guard var s = sessions[payload.sessionID] else { return }
            let jt = payload.jumpTarget
            // Keep the existing terminalSessionID if the update doesn't provide one.
            // Ghostty's surface UUID is resolved once at session start and should
            // not be wiped by later hooks that lack this info.
            let existingSessionID = s.terminal?.terminalSessionID
            s.terminal = TerminalInfo(
                app: jt.terminalApp,
                tty: jt.terminalTTY,
                terminalSessionID: jt.terminalSessionID ?? existingSessionID
            )
            s.workingDirectory = jt.workingDirectory ?? s.workingDirectory
            s.lastActivityAt = payload.timestamp
            sessions[payload.sessionID] = s

        case let .sessionMetadataUpdated(payload):
            guard var s = sessions[payload.sessionID] else { return }
            let cm = payload.codexMetadata
            s.metadata.initialPrompt = s.metadata.initialPrompt ?? cm.initialUserPrompt
            s.metadata.lastPrompt = cm.lastUserPrompt ?? s.metadata.lastPrompt
            s.metadata.lastAssistantMessage = cm.lastAssistantMessage ?? s.metadata.lastAssistantMessage
            s.metadata.currentTool = cm.currentTool
            s.metadata.currentToolInputPreview = cm.currentCommandPreview
            if let path = cm.transcriptPath {
                s.transcriptPath = path
            }
            s.lastActivityAt = payload.timestamp
            sessions[payload.sessionID] = s

        case let .claudeSessionMetadataUpdated(payload):
            guard var s = sessions[payload.sessionID] else { return }
            let cm = payload.claudeMetadata
            s.metadata = sessionMetadata(from: cm)
            if let title = cm.customTitle, !title.isEmpty {
                s.customTitle = title
            }
            if let path = cm.transcriptPath {
                s.transcriptPath = path
            }
            s.lastActivityAt = payload.timestamp
            sessions[payload.sessionID] = s

        case let .openCodeSessionMetadataUpdated(payload):
            guard var s = sessions[payload.sessionID] else { return }
            s.lastActivityAt = payload.timestamp
            sessions[payload.sessionID] = s

        case let .actionableStateResolved(payload):
            guard var s = sessions[payload.sessionID],
                  s.phase == .waitingForApproval || s.phase == .waitingForAnswer else { return }
            s.phase = .running
            s.summary = payload.summary
            s.permissionRequest = nil
            s.questionPrompt = nil
            s.lastActivityAt = payload.timestamp
            sessions[payload.sessionID] = s
        }
    }

    // MARK: Transcript restore (startup only — never overwrites existing)

    public func restoreFromTranscripts(_ transcripts: [DiscoveredTranscript]) {
        for t in transcripts {
            // Skip if hook has already established a session for this ID.
            guard sessions[t.sessionID] == nil else { continue }

            let meta = SessionMetadata(
                initialPrompt: t.initialPrompt,
                lastPrompt: t.lastPrompt,
                lastAssistantMessage: t.lastAssistantMessage,
                model: t.model
            )
            let s = TrackedSession(
                id: t.sessionID,
                tool: .claudeCode,
                phase: .completed,
                summary: t.lastAssistantMessage ?? t.lastPrompt ?? "",
                startedAt: t.startedAt,
                lastActivityAt: t.lastActivityAt,
                terminal: nil,
                workingDirectory: t.workingDirectory,
                permissionRequest: nil,
                questionPrompt: nil,
                processState: .unknown,
                customTitle: t.customTitle,
                transcriptPath: t.transcriptPath,
                metadata: meta
            )
            sessions[t.sessionID] = s
        }
    }

    // MARK: Restore persisted terminal info

    /// Apply persisted terminal info from disk. For sessions that have no
    /// terminalSessionID (e.g. restored from transcripts or discovered by PID),
    /// fill it in from the persisted file written by the hook binary.
    public func restorePersistedTerminalInfo() {
        let entries = TerminalInfoStore.loadAll()
        guard !entries.isEmpty else { return }

        for (sessionID, entry) in entries {
            guard var s = sessions[sessionID] else { continue }
            // Don't overwrite if we already have a terminalSessionID.
            guard s.terminal?.terminalSessionID == nil else { continue }

            if s.terminal != nil {
                s.terminal?.terminalSessionID = entry.terminalSessionID
            } else {
                s.terminal = TerminalInfo(
                    app: entry.terminalApp,
                    tty: entry.tty,
                    terminalSessionID: entry.terminalSessionID
                )
            }
            sessions[sessionID] = s
        }
    }

    // MARK: User actions

    public func resolvePermission(sessionID: String, resolution: PermissionResolution) {
        guard var s = sessions[sessionID] else { return }
        s.permissionRequest = nil
        let now = Date.now
        if resolution.isApproved {
            s.phase = .running
            s.summary = "Permission approved."
        } else {
            s.phase = .completed
            s.summary = "Permission denied."
        }
        s.lastActivityAt = now
        sessions[sessionID] = s
    }

    public func answerQuestion(sessionID: String, answer: String) {
        guard var s = sessions[sessionID] else { return }
        s.questionPrompt = nil
        s.phase = .running
        s.summary = answer.isEmpty ? "Answered the question." : "Answered: \(answer)"
        s.lastActivityAt = Date.now
        sessions[sessionID] = s
    }

    // MARK: Claude session file discovery (~/.claude/sessions/)

    /// Discover active Claude Code sessions from `~/.claude/sessions/*.json`.
    ///
    /// This is the **source of truth** for Claude Code session liveness. Each JSON file
    /// contains `pid`, `sessionId`, `cwd`, `startedAt`, and `name`. The PID is checked
    /// with `kill(pid, 0)` to determine liveness — if the process is gone, the session
    /// is skipped.
    ///
    /// For sessions already known from hook events, this updates `processState` and
    /// fills in terminal/title info. For unknown sessions (e.g. started before the app
    /// launched), it creates new TrackedSessions.
    ///
    /// Sessions whose files disappear (or whose PID dies) are removed — unless they
    /// have pending permission/question state that the user hasn't responded to yet.
    public func discoverClaudeSessions() {
        let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions", isDirectory: true)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: nil
        ) else { return }

        let jsonFiles = files.filter { $0.pathExtension == "json" }

        // Track which session IDs are in the session files.
        var activeSessionIDs: Set<String> = []

        for file in jsonFiles {
            guard let data = try? Data(contentsOf: file),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = obj["pid"] as? Int,
                  let sessionID = obj["sessionId"] as? String,
                  let cwd = obj["cwd"] as? String else { continue }

            let isAlive = ProcessInfo.processInfo.processIdentifier != Int32(pid)
                && kill(Int32(pid), 0) == 0

            guard isAlive else { continue }

            activeSessionIDs.insert(sessionID)

            let startedAtMs = obj["startedAt"] as? Double ?? 0
            let startedAt = Date(timeIntervalSince1970: startedAtMs / 1000)
            let name = obj["name"] as? String

            // Look up terminal info from process tree if we don't have it yet.
            let existingTerminal = sessions[sessionID]?.terminal
            let terminal = existingTerminal ?? Self.terminalInfo(forPID: Int32(pid))

            // Use transcript file mod time as last activity (more accurate than startedAt).
            let transcriptPath = Self.transcriptPath(sessionID: sessionID)
            let lastActivityAt: Date = {
                guard let path = transcriptPath,
                      let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let modDate = attrs[.modificationDate] as? Date else {
                    return startedAt
                }
                return modDate
            }()

            if var existing = sessions[sessionID] {
                var changed = false
                if existing.processState != .alive {
                    existing.processState = .alive
                    changed = true
                }
                if !existing.processConfirmedByDiscovery {
                    existing.processConfirmedByDiscovery = true
                    changed = true
                }
                if let name, !name.isEmpty, existing.customTitle != name {
                    existing.customTitle = name
                    changed = true
                }
                if existing.workingDirectory == nil {
                    existing.workingDirectory = cwd
                    changed = true
                }
                if existing.terminal == nil, let terminal {
                    existing.terminal = terminal
                    changed = true
                }
                // Keep lastActivityAt fresh from transcript mod time so sessions
                // don't go grey while the agent is still actively running.
                if lastActivityAt > existing.lastActivityAt {
                    existing.lastActivityAt = lastActivityAt
                    changed = true
                }
                if changed {
                    sessions[sessionID] = existing
                }
            } else {
                sessions[sessionID] = TrackedSession(
                    id: sessionID,
                    tool: .claudeCode,
                    phase: .running,
                    summary: name ?? "Claude session",
                    startedAt: startedAt,
                    lastActivityAt: lastActivityAt,
                    terminal: terminal,
                    workingDirectory: cwd,
                    processState: .alive,
                    processConfirmedByDiscovery: true,
                    customTitle: name,
                    transcriptPath: transcriptPath
                )
            }
        }

        // Remove Claude sessions not in session files — but keep sessions
        // that require attention (permission/question) to avoid dropping
        // actionable state before the user can respond.
        // Hook-created sessions get a grace period (2 consecutive misses)
        // to avoid a race where the hook fires before Claude Code writes
        // the session file to ~/.claude/sessions/.
        for (id, var session) in sessions {
            guard session.tool == .claudeCode else { continue }
            if activeSessionIDs.contains(id) {
                session.discoveryMissCount = 0
                sessions[id] = session
            } else if !session.phase.requiresAttention {
                session.discoveryMissCount += 1
                if session.discoveryMissCount >= 2 {
                    sessions.removeValue(forKey: id)
                } else {
                    sessions[id] = session
                }
            }
        }

        // Apply persisted terminal info (surface UUIDs) saved by the hook binary.
        // This restores jump-to-terminal capability after app restart.
        restorePersistedTerminalInfo()
    }

    /// Resolve terminal app by walking the process parent chain.
    private static func terminalInfo(forPID pid: Int32) -> TerminalInfo? {
        // Get TTY
        let ttyOutput = shellOutput("/bin/ps", ["-p", "\(pid)", "-o", "tty="])
        let tty = ttyOutput?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Walk parent chain to find terminal app
        var current = pid
        for _ in 0..<15 {
            guard let ppidStr = shellOutput("/bin/ps", ["-p", "\(current)", "-o", "ppid="]),
                  let ppid = Int32(ppidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ppid > 1 else { break }
            current = ppid

            guard let comm = shellOutput("/bin/ps", ["-p", "\(current)", "-o", "comm="])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !comm.isEmpty else { break }

            // Use full path for matching — some terminals have generic binary names
            // (e.g., Warp's binary is "stable", not "warp")
            guard let fullPath = shellOutput("/bin/ps", ["-p", "\(current)", "-o", "command="])?
                .trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            let lowered = fullPath.lowercased()
            let appName: String? =
                lowered.contains("ghostty") ? "Ghostty" :
                lowered.contains("warp.app") ? "Warp" :
                lowered.contains("iterm") ? "iTerm" :
                lowered.contains("terminal.app") ? "Terminal" :
                lowered.contains("wezterm") ? "WezTerm" :
                lowered.contains("kaku") ? "Kaku" :
                nil

            if let appName {
                return TerminalInfo(
                    app: appName,
                    tty: tty?.isEmpty == false ? tty : nil
                )
            }
        }

        return tty?.isEmpty == false
            ? TerminalInfo(app: "Unknown", tty: tty)
            : nil
    }

    private static func shellOutput(_ path: String, _ arguments: [String]) -> String? {
        ShellProcess.output(executablePath: path, arguments: arguments)
    }

    /// Find transcript by globbing for the session UUID across all project directories.
    /// This avoids CWD encoding bugs (dots, underscores, spaces in paths).
    private static func transcriptPath(sessionID: String) -> String? {
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return nil }

        for dir in dirs {
            let candidate = dir.appendingPathComponent("\(sessionID).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }

    // MARK: Process reconciliation

    /// Update process liveness and terminal info from process discovery.
    /// Never creates sessions — only updates existing ones.
    public func reconcileProcesses(
        aliveSessionIDs: Set<String>,
        terminalUpdates: [String: TerminalInfo]
    ) {
        for (id, var session) in sessions {
            if session.isRemote { continue }
            // Claude sessions are handled by discoverClaudeSessions() — skip here.
            if session.tool == .claudeCode { continue }

            if aliveSessionIDs.contains(id) {
                session.processState = .alive
                session.processConfirmedByDiscovery = true
            } else if session.processState == .alive && session.processConfirmedByDiscovery {
                session.processState = .gone(since: .now)
            }

            if session.terminal == nil, let terminal = terminalUpdates[id] {
                session.terminal = terminal
            }

            sessions[id] = session
        }
    }

    // MARK: Pruning

    public func pruneInvisibleSessions(at referenceDate: Date = .now) {
        sessions = sessions.filter { _, s in s.isVisible(at: referenceDate) }
    }

    // MARK: Private helpers

    /// Ensures a minimal session exists for `id`. Used when hook events arrive
    /// for a session that was not yet started via `.sessionStarted`.
    private func ensureSession(id: String, timestamp: Date) {
        guard sessions[id] == nil else { return }
        let s = TrackedSession(
            id: id,
            tool: .claudeCode,
            phase: .running,
            summary: "",
            startedAt: timestamp,
            lastActivityAt: timestamp,
            processState: .alive
        )
        sessions[id] = s
    }

    /// Convert agent-specific `ClaudeSessionMetadata` into the shared `SessionMetadata`
    /// used by the UI layer. Fields that only exist in the Claude model but are useful
    /// for display (permissionMode, startupSource) are propagated here.
    private func sessionMetadata(from cm: ClaudeSessionMetadata?) -> SessionMetadata {
        guard let cm else { return SessionMetadata() }
        return SessionMetadata(
            initialPrompt: cm.initialUserPrompt,
            lastPrompt: cm.lastUserPrompt,
            lastAssistantMessage: cm.lastAssistantMessage,
            model: cm.model,
            currentTool: cm.currentTool,
            currentToolInputPreview: cm.currentToolInputPreview,
            worktreeBranch: cm.worktreeBranch,
            permissionMode: cm.permissionMode,
            startupSource: cm.startupSource,
            activeSubagents: cm.activeSubagents,
            activeTasks: cm.activeTasks
        )
    }
}
