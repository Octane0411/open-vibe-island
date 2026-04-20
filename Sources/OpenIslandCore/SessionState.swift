import Foundation

public struct SessionState: Equatable, Sendable {
    public private(set) var sessionsByID: [String: AgentSession]

    public init(sessions: [AgentSession] = []) {
        self.sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    public var sessions: [AgentSession] {
        sessionsByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public var activeActionableSession: AgentSession? {
        sessions.first(where: { $0.phase.requiresAttention })
    }

    public var runningCount: Int {
        sessionsByID.values.filter { $0.phase == .running }.count
    }

    public var attentionCount: Int {
        sessionsByID.values.filter { $0.phase.requiresAttention }.count
    }

    public var liveSessionCount: Int {
        sessionsByID.values.filter(\.isVisibleInIsland).count
    }

    public var liveAttentionCount: Int {
        sessionsByID.values.filter { $0.isVisibleInIsland && $0.phase.requiresAttention }.count
    }

    public var liveRunningCount: Int {
        sessionsByID.values.filter { $0.isVisibleInIsland && $0.phase == .running }.count
    }

    public var completedCount: Int {
        sessionsByID.values.filter { $0.phase == .completed }.count
    }

    public func session(id: String?) -> AgentSession? {
        guard let id else {
            return nil
        }

        return sessionsByID[id]
    }

    public mutating func apply(_ event: AgentEvent) {
        switch event {
        case let .sessionStarted(payload):
            var session = AgentSession(
                id: payload.sessionID,
                title: payload.title,
                tool: payload.tool,
                origin: payload.origin,
                attachmentState: .attached,
                phase: payload.initialPhase,
                summary: payload.summary,
                updatedAt: payload.timestamp,
                jumpTarget: payload.jumpTarget,
                codexMetadata: payload.codexMetadata?.isEmpty == true ? nil : payload.codexMetadata,
                claudeMetadata: payload.claudeMetadata?.isEmpty == true ? nil : payload.claudeMetadata,
                geminiMetadata: payload.geminiMetadata?.isEmpty == true ? nil : payload.geminiMetadata,
                openCodeMetadata: payload.openCodeMetadata?.isEmpty == true ? nil : payload.openCodeMetadata,
                cursorMetadata: payload.cursorMetadata?.isEmpty == true ? nil : payload.cursorMetadata
            )
            session.isRemote = payload.isRemote
            session.isHookManaged = payload.origin == .live
            // Codex.app sessions use app-level liveness (NSRunningApplication)
            // rather than hook-managed processNotSeenCount polling — flag is
            // derived from jumpTarget.terminalApp via the shared helper.
            Self.refreshCodexAppClassification(for: &session)
            session.isSessionEnded = false
            session.isProcessAlive = true
            session.processNotSeenCount = 0
            upsert(session)

        case let .activityUpdated(payload):
            guard var session = sessionsByID[payload.sessionID] else {
                return
            }

            let keepsPendingApproval = payload.phase == .running
                && session.phase == .waitingForApproval
                && session.permissionRequest != nil
            let keepsPendingQuestion = payload.phase == .running
                && session.phase == .waitingForAnswer
                && session.questionPrompt != nil
            let preservesActionableState = keepsPendingApproval || keepsPendingQuestion

            if !preservesActionableState {
                session.phase = payload.phase
                session.summary = payload.summary
                if payload.phase != .waitingForApproval {
                    session.permissionRequest = nil
                }
                if payload.phase != .waitingForAnswer {
                    session.questionPrompt = nil
                }
            }

            session.updatedAt = payload.timestamp
            upsert(session)

        case let .permissionRequested(payload):
            guard var session = sessionsByID[payload.sessionID] else {
                return
            }

            session.phase = .waitingForApproval
            session.summary = payload.request.summary
            session.permissionRequest = payload.request
            session.questionPrompt = nil
            session.updatedAt = payload.timestamp
            upsert(session)

        case let .questionAsked(payload):
            guard var session = sessionsByID[payload.sessionID] else {
                return
            }

            session.phase = .waitingForAnswer
            session.summary = payload.prompt.title
            session.questionPrompt = payload.prompt
            session.permissionRequest = nil
            session.updatedAt = payload.timestamp
            upsert(session)

        case let .sessionCompleted(payload):
            guard var session = sessionsByID[payload.sessionID] else {
                return
            }

            session.phase = .completed
            session.summary = payload.summary
            session.permissionRequest = nil
            session.questionPrompt = nil
            session.updatedAt = payload.timestamp
            if payload.isSessionEnd == true {
                session.isSessionEnded = true
            }
            upsert(session)

        case let .jumpTargetUpdated(payload):
            guard var session = sessionsByID[payload.sessionID] else {
                return
            }

            session.jumpTarget = payload.jumpTarget
            session.updatedAt = payload.timestamp
            Self.refreshCodexAppClassification(for: &session)
            upsert(session)

        case let .sessionMetadataUpdated(payload):
            guard var session = sessionsByID[payload.sessionID] else {
                return
            }

            session.codexMetadata = payload.codexMetadata.isEmpty ? nil : payload.codexMetadata
            session.updatedAt = payload.timestamp
            upsert(session)

        case let .claudeSessionMetadataUpdated(payload):
            guard var session = sessionsByID[payload.sessionID] else {
                return
            }

            session.claudeMetadata = payload.claudeMetadata.isEmpty ? nil : payload.claudeMetadata
            session.updatedAt = payload.timestamp
            upsert(session)

        case let .claudeProcessExited(payload):
            guard var session = sessionsByID[payload.sessionID] else { return }
            guard !session.isSessionEnded else { return }
            session.isSessionEnded = true
            session.phase = .completed
            session.isProcessAlive = false
            session.updatedAt = payload.timestamp
            session.processNotSeenCount = 0
            upsert(session)

        case let .geminiSessionMetadataUpdated(payload):
            guard var session = sessionsByID[payload.sessionID] else {
                return
            }

            session.geminiMetadata = payload.geminiMetadata.isEmpty ? nil : payload.geminiMetadata
            session.updatedAt = payload.timestamp
            upsert(session)

        case let .openCodeSessionMetadataUpdated(payload):
            guard var session = sessionsByID[payload.sessionID] else {
                return
            }

            session.openCodeMetadata = payload.openCodeMetadata.isEmpty ? nil : payload.openCodeMetadata
            session.updatedAt = payload.timestamp
            upsert(session)

        case let .cursorSessionMetadataUpdated(payload):
            guard var session = sessionsByID[payload.sessionID] else {
                return
            }

            session.cursorMetadata = payload.cursorMetadata.isEmpty ? nil : payload.cursorMetadata
            session.updatedAt = payload.timestamp
            upsert(session)

        case let .actionableStateResolved(payload):
            guard var session = sessionsByID[payload.sessionID] else {
                return
            }

            guard session.phase == .waitingForApproval || session.phase == .waitingForAnswer else {
                return
            }

            session.phase = .running
            session.summary = payload.summary
            session.permissionRequest = nil
            session.questionPrompt = nil
            session.updatedAt = payload.timestamp
            upsert(session)
        }
    }

    public mutating func resolvePermission(
        sessionID: String,
        resolution: PermissionResolution,
        at timestamp: Date = .now
    ) {
        guard var session = sessionsByID[sessionID] else {
            return
        }

        session.permissionRequest = nil
        session.updatedAt = timestamp

        if resolution.isApproved {
            session.phase = .running
            switch session.tool {
            case .claudeCode, .geminiCLI, .qoder, .qwenCode, .factory, .codebuddy, .kimiCLI:
                session.summary = "Permission approved. \(session.tool.displayName) continued the tool."
            case .openCode:
                session.summary = "Permission approved. OpenCode continued the tool."
            default:
                session.summary = "Permission approved. Agent resumed work."
            }
        } else {
            session.phase = .completed
            switch session.tool {
            case .claudeCode, .geminiCLI, .qoder, .qwenCode, .factory, .codebuddy, .kimiCLI:
                session.summary = "Permission denied in Open Island."
            case .openCode:
                session.summary = "Permission denied in Open Island."
            default:
                session.summary = "Permission denied. Review the session in the terminal."
            }
        }

        upsert(session)
    }

    public mutating func answerQuestion(
        sessionID: String,
        response: QuestionPromptResponse,
        at timestamp: Date = .now
    ) {
        guard var session = sessionsByID[sessionID] else {
            return
        }

        session.questionPrompt = nil
        session.phase = .running
        let summary = response.displaySummary
        session.summary = summary.isEmpty ? "Answered the question." : "Answered: \(summary)"
        session.updatedAt = timestamp
        upsert(session)
    }

    @discardableResult
    public mutating func reconcileAttachmentStates(_ updates: [String: SessionAttachmentState]) -> Bool {
        var changed = false

        for (sessionID, attachmentState) in updates {
            guard var session = sessionsByID[sessionID],
                  session.attachmentState != attachmentState else {
                continue
            }

            session.attachmentState = attachmentState
            upsert(session)
            changed = true
        }

        return changed
    }

    @discardableResult
    public mutating func reconcileJumpTargets(_ updates: [String: JumpTarget]) -> Bool {
        var changed = false

        for (sessionID, jumpTarget) in updates {
            guard var session = sessionsByID[sessionID],
                  session.jumpTarget != jumpTarget else {
                continue
            }

            session.jumpTarget = jumpTarget
            Self.refreshCodexAppClassification(for: &session)
            upsert(session)
            changed = true
        }

        return changed
    }

    /// Upgrade `isCodexAppSession` if the session's current jumpTarget
    /// identifies it as a Codex.app session.  Never downgrades — once a
    /// session is classified as Codex.app, it stays classified even if a
    /// later resolver pass replaces the jumpTarget with a generic one.
    /// This handles the case where the first hook fires before terminalApp
    /// is known and a later `jumpTargetUpdated` fills it in.
    static func refreshCodexAppClassification(for session: inout AgentSession) {
        if session.jumpTarget?.terminalApp == "Codex.app" {
            session.isCodexAppSession = true
            // Codex.app sessions use app-level liveness, not hook-managed polling.
            session.isHookManaged = false
        }
    }

    /// Mark a single session as alive (e.g. when a hook event is received).
    /// Does not affect other sessions' processNotSeenCount.
    public mutating func markSingleSessionAlive(sessionID: String) {
        guard var session = sessionsByID[sessionID] else { return }
        guard !session.isProcessAlive || session.processNotSeenCount != 0 else { return }
        session.isProcessAlive = true
        session.processNotSeenCount = 0
        upsert(session)
    }

    /// Update process liveness for all tracked sessions based on process discovery.
    /// Returns the set of session IDs whose `isProcessAlive` changed.
    @discardableResult
    public mutating func markProcessLiveness(
        aliveSessionIDs: Set<String>,
        isCodexAppRunning: Bool = false
    ) -> Set<String> {
        var changed: Set<String> = []

        for (id, var session) in sessionsByID {
            // Remote sessions have no local process — keep them alive as long
            // as the bridge is delivering hook events.
            if session.isRemote {
                continue
            }

            // Codex.app sessions use app-level liveness (NSRunningApplication)
            // rather than subprocess matching.  Phase is driven by hooks or
            // the rollout watcher / app-server notifications.
            if session.isCodexAppSession {
                let wasAlive = session.isProcessAlive
                session.isProcessAlive = aliveSessionIDs.contains(id)
                if session.isProcessAlive != wasAlive {
                    changed.insert(id)
                }
                upsert(session)
                continue
            }

            // Hook-managed sessions primarily rely on hook lifecycle signals
            // (SessionStart / SessionEnd).  However, if the bridge becomes
            // unavailable the SessionEnd hook can never arrive, leaving the
            // session permanently stuck as visible.  As a fallback, we also
            // check process liveness: when the agent process is confirmed dead
            // by two consecutive polls we mark the session ended so it can be
            // cleaned up.
            if session.isHookManaged {
                if session.isSessionEnded {
                    continue
                }

                if session.tool == .claudeCode {
                    // Lifecycle is driven by hook events + ClaudePIDMonitor exit signals.
                    // ps/lsof is unreliable under load and must not evict healthy sessions.
                    if aliveSessionIDs.contains(id) {
                        session.processNotSeenCount = 0
                        upsert(session)
                    }
                    continue
                }

                // When a Codex session reached .completed via hooks (.stop)
                // and Codex.app is still running, don't kill it through
                // process polling — the CLI subprocess exits after each turn
                // but the desktop app session is still valid.  The session
                // stays visible as "Completed" and fades via island presence.
                if session.tool == .codex && session.phase == .completed && isCodexAppRunning {
                    upsert(session)
                    continue
                }

                if aliveSessionIDs.contains(id) {
                    session.processNotSeenCount = 0
                } else {
                    session.processNotSeenCount += 1
                    if session.processNotSeenCount >= 2 {
                        session.isSessionEnded = true
                        session.phase = .completed
                        changed.insert(id)
                    }
                }

                upsert(session)
                continue
            }

            let wasAlive = session.isProcessAlive

            if aliveSessionIDs.contains(id) {
                session.isProcessAlive = true
                session.processNotSeenCount = 0
            } else {
                session.processNotSeenCount += 1
                session.isProcessAlive = session.processNotSeenCount < 2
            }

            if session.isProcessAlive != wasAlive {
                changed.insert(id)
                upsert(session)
            } else if !aliveSessionIDs.contains(id), session.processNotSeenCount >= 1 {
                upsert(session)
            }
        }

        return changed
    }

    /// Remove sessions that are no longer visible in the island.
    /// Returns `true` if any sessions were removed.
    @discardableResult
    /// Manually mark a session as completed and ended.
    /// Intended for remote sessions whose SSH tunnel dropped without a
    /// SessionEnd hook.
    public mutating func dismissSession(id: String) {
        guard var session = sessionsByID[id] else { return }
        session.isSessionEnded = true
        session.phase = .completed
        session.updatedAt = .now
        upsert(session)
    }

    public mutating func removeInvisibleSessions() -> Bool {
        let before = sessionsByID.count
        sessionsByID = sessionsByID.filter { _, session in
            session.isVisibleInIsland
        }
        return sessionsByID.count != before
    }

    private mutating func upsert(_ session: AgentSession) {
        sessionsByID[session.id] = session
    }
}
