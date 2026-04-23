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

    public var presentationComparableState: Self {
        SessionState(sessions: sessions.map { $0.normalizedForPresentationComparison() })
    }

    public var persistenceComparableState: Self {
        SessionState(sessions: sessions.map { $0.normalizedForPersistenceComparison() })
    }

    public func session(id: String?) -> AgentSession? {
        guard let id else {
            return nil
        }

        return sessionsByID[id]
    }

    public mutating func apply(
        _ event: AgentEvent,
        ingress: TrackedEventIngress = .bridge
    ) {
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
            session.lifecyclePolicy = AgentSession.inferredLifecyclePolicy(
                tool: payload.tool,
                origin: payload.origin,
                jumpTarget: payload.jumpTarget
            )
            // Codex.app sessions use app-level liveness (NSRunningApplication)
            // rather than CLI subprocess polling. Their app-driven lifecycle
            // is derived from jumpTarget.terminalApp via the shared helper.
            Self.refreshCodexAppClassification(for: &session)
            session.isSessionEnded = false
            if session.lifecyclePolicy == .appDriven {
                session.livenessObservation.seedRuntimePresence(.desktopApp)
            } else if session.lifecyclePolicy == .processDriven {
                session.livenessObservation.seedRuntimePresence(.toolFamily)
            }
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

        if let sessionID = event.sessionID {
            if ingress.isBridge {
                _ = reconcileAttachmentStates([sessionID: .attached])
            }
            if let source = ingress.eventPresenceSource {
                observeEventPresence(sessionID: sessionID, source: source)
            }
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

    /// Upgrade lifecycle policy if the session's current jumpTarget
    /// identifies it as a Codex.app session. Never downgrades — once a
    /// session is classified as app-driven, it stays classified even if a
    /// later resolver pass replaces the jumpTarget with a generic one.
    /// This handles the case where the first hook fires before terminalApp
    /// is known and a later `jumpTargetUpdated` fills it in.
    static func refreshCodexAppClassification(for session: inout AgentSession) {
        if session.jumpTarget?.terminalApp == "Codex.app" {
            session.lifecyclePolicy = .appDriven
            session.livenessObservation.seedRuntimePresence(.desktopApp)
        }
    }

    public mutating func observeEventPresence(
        sessionID: String,
        source: SessionEventPresenceSource
    ) {
        guard var session = sessionsByID[sessionID] else {
            return
        }

        guard session.lifecyclePolicy == .hookDrivenWithProcessFallback else {
            return
        }

        session.livenessObservation.recordEventPresence(source)
        upsert(session)
    }

    /// Update runtime liveness for all tracked sessions from explicit
    /// runtime evidence rather than ad hoc process booleans.
    @discardableResult
    public mutating func reconcileRuntimePresence(
        evidenceBySessionID: [String: SessionRuntimeMatchStrength]
    ) -> Set<String> {
        var changed: Set<String> = []

        for (id, var session) in sessionsByID {
            // Remote sessions have no local process — keep them alive as long
            // as the bridge is delivering hook events.
            if session.isRemote {
                continue
            }

            let hadPresenceEvidence = session.hasPresenceEvidence
            let wasVisible = session.isVisibleInIsland
            let wasEnded = session.isSessionEnded

            session.livenessObservation.advanceRuntimeObservation(match: evidenceBySessionID[id])

            // Hook-managed sessions primarily rely on hook lifecycle signals
            // (SessionStart / SessionEnd).  However, if the bridge becomes
            // unavailable the SessionEnd hook can never arrive, leaving the
            // session permanently stuck as visible.  As a fallback, we also
            // check runtime evidence: when the session receives neither event
            // nor runtime presence for two consecutive polls we mark it ended.
            // This keeps the rule deterministic regardless of ingress.
            //
            // App-driven sessions use the same reducer, but their runtime
            // evidence normally arrives via `.desktopApp` instead of CLI
            // subprocess matching.
            if session.lifecyclePolicy == .hookDrivenWithProcessFallback
                && !session.isSessionEnded
                && !session.hasFallbackPresence {
                session.isSessionEnded = true
                session.phase = .completed
            }

            if session.hasPresenceEvidence != hadPresenceEvidence
                || session.isVisibleInIsland != wasVisible
                || session.isSessionEnded != wasEnded {
                changed.insert(id)
            }

            upsert(session)
        }

        return changed
    }

    /// Remove sessions that are no longer visible in the island.
    /// Returns `true` if any sessions were removed.
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
