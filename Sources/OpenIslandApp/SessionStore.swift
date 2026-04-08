import Foundation
import OpenIslandCore

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

/// Single owner of all TrackedSession state for the app UI layer.
@MainActor @Observable
final class SessionStore {

    // MARK: State

    /// Direct access to the sessions dictionary. Use `applyHookEvent` for authoritative updates.
    var sessions: [String: TrackedSession] = [:]

    // MARK: Queries

    func session(id: String?) -> TrackedSession? {
        guard let id else { return nil }
        return sessions[id]
    }

    /// All sessions that are visible right now, sorted by phase priority then activity then name.
    var visibleSessions: [TrackedSession] {
        visibleSessions(at: .now)
    }

    /// All sessions visible at the given reference date, sorted consistently.
    func visibleSessions(at referenceDate: Date) -> [TrackedSession] {
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
    var actionableSession: TrackedSession? {
        visibleSessions.first { $0.phase.requiresAttention }
    }

    // MARK: Hook events (authoritative)

    /// Apply an AgentEvent from the bridge hook. This is the authoritative path;
    /// it creates sessions if necessary (except for sessionCompleted).
    func applyHookEvent(_ event: AgentEvent) {
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
            s.terminal = TerminalInfo(
                app: jt.terminalApp,
                tty: jt.terminalTTY,
                terminalSessionID: jt.terminalSessionID
            )
            s.workingDirectory = jt.workingDirectory ?? s.workingDirectory
            s.lastActivityAt = payload.timestamp
            sessions[payload.sessionID] = s

        case let .sessionMetadataUpdated(payload):
            guard var s = sessions[payload.sessionID] else { return }
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

    func restoreFromTranscripts(_ transcripts: [DiscoveredTranscript]) {
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

    // MARK: User actions

    func resolvePermission(sessionID: String, resolution: PermissionResolution) {
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

    func answerQuestion(sessionID: String, answer: String) {
        guard var s = sessions[sessionID] else { return }
        s.questionPrompt = nil
        s.phase = .running
        s.summary = answer.isEmpty ? "Answered the question." : "Answered: \(answer)"
        s.lastActivityAt = Date.now
        sessions[sessionID] = s
    }

    // MARK: Claude session file discovery (~/.claude/sessions/)

    /// Discover active Claude Code sessions from ~/.claude/sessions/*.json.
    /// Each file contains: pid, sessionId, cwd, startedAt, name.
    /// PID is checked against `ps` to determine liveness.
    func discoverClaudeSessions() {
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
                existing.processState = .alive
                existing.processConfirmedByDiscovery = true
                if let name, !name.isEmpty {
                    existing.customTitle = name
                }
                existing.workingDirectory = existing.workingDirectory ?? cwd
                if existing.terminal == nil {
                    existing.terminal = terminal
                }
                sessions[sessionID] = existing
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
        for (id, session) in sessions {
            if session.tool == .claudeCode
                && !activeSessionIDs.contains(id)
                && !session.phase.requiresAttention {
                sessions.removeValue(forKey: id)
            }
        }
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
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
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
    func reconcileProcesses(
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

    func pruneInvisibleSessions(at referenceDate: Date = .now) {
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

    /// Convert `ClaudeSessionMetadata` → `SessionMetadata`.
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
            activeSubagents: cm.activeSubagents,
            activeTasks: cm.activeTasks
        )
    }
}
