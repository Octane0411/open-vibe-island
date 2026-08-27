import Foundation

/// Turns arbitrated facets into the `AgentEvent` stream the rest of the app
/// consumes.
///
/// This is the only place Codex-specific knowledge is allowed to end. Once an
/// observation has passed through here it is an ordinary `AgentEvent`, and
/// `SessionState.apply` neither knows nor cares that Codex has four different
/// ways of describing the same session.
///
/// The projector holds no state of its own beyond what the store keeps: given
/// the same facets it always produces the same events, which is what makes the
/// ordering and authority invariants testable as properties rather than as a
/// handful of hand-written scenarios.
public final class CodexSessionProjector: @unchecked Sendable {
    private let store: CodexFacetStore
    private let diagnostics: CodexDiagnostics?
    private let lock = NSLock()
    /// Sessions for which `sessionStarted` has already been emitted.
    private var announced: Set<String> = []

    public init(store: CodexFacetStore, diagnostics: CodexDiagnostics? = nil) {
        self.store = store
        self.diagnostics = diagnostics
    }

    /// Ingest one observation and return the events it produces.
    public func project(_ observation: CodexObservation) -> [AgentEvent] {
        guard let sessionKey = resolveSessionKey(for: observation) else {
            return []
        }

        let change = store.apply(observation, sessionKey: sessionKey)
        guard change.didChange, let facets = store.session(for: sessionKey) else {
            return []
        }

        // Threads Codex spawned for itself never become user sessions. They are
        // still tracked, so a parent can count its running subagents, but they
        // produce no events of their own.
        guard facets.isUserVisible else {
            return []
        }

        var events: [AgentEvent] = []
        let timestamp = observation.observedAt

        let hasAnnounced = lock.withLock { announced.contains(sessionKey) }
        if !hasAnnounced {
            // A session is only announced once enough is known to render it —
            // otherwise the list would flash entries with no title or workspace.
            guard let started = makeSessionStarted(facets: facets, timestamp: timestamp) else {
                return []
            }
            lock.withLock { _ = announced.insert(sessionKey) }
            events.append(.sessionStarted(started))
            return events
        }

        if !change.accepted.isDisjoint(with: [.placement, .workspace, .surface]),
           let jumpTarget = makeJumpTarget(facets: facets) {
            events.append(.jumpTargetUpdated(JumpTargetUpdated(
                sessionID: sessionKey,
                jumpTarget: jumpTarget,
                timestamp: timestamp
            )))
        }

        if change.accepted.contains(.narrative), let metadata = makeMetadata(facets: facets) {
            events.append(.sessionMetadataUpdated(SessionMetadataUpdated(
                sessionID: sessionKey,
                codexMetadata: metadata,
                timestamp: timestamp
            )))
        }

        if change.accepted.contains(.actionable), let actionable = facets.actionable?.value {
            switch actionable {
            case let .permission(request):
                events.append(.permissionRequested(PermissionRequested(
                    sessionID: sessionKey,
                    request: request,
                    timestamp: timestamp
                )))
            case let .question(prompt):
                events.append(.questionAsked(QuestionAsked(
                    sessionID: sessionKey,
                    prompt: prompt,
                    timestamp: timestamp
                )))
            case .cleared:
                events.append(.actionableStateResolved(ActionableStateResolved(
                    sessionID: sessionKey,
                    summary: summaryText(facets: facets),
                    timestamp: timestamp
                )))
            }
        }

        // Liveness is checked before lifecycle: once a session has ended, its
        // phase no longer matters and emitting an activity update would revive
        // a row the user just watched disappear.
        if change.accepted.contains(.liveness), let liveness = facets.liveness?.value,
           case let .ended(reason) = liveness.state {
            events.append(.sessionCompleted(SessionCompleted(
                sessionID: sessionKey,
                summary: summaryText(facets: facets),
                timestamp: timestamp,
                isInterrupt: false,
                isSessionEnd: reason != .archived
            )))
            return events
        }

        if change.accepted.contains(.lifecycle), let lifecycle = facets.lifecycle?.value {
            if lifecycle.phase == .completed, lifecycle.announcesCompletion {
                // The agent finished answering: `sessionCompleted` with
                // `isSessionEnd` false. The distinction from an activity
                // update is not cosmetic — `IslandSurface` only pops the
                // island for `sessionCompleted` and `WatchNotificationRelay`
                // only pushes to the watch for it — which is exactly why a
                // merely-idle thread must not take this branch.
                events.append(.sessionCompleted(SessionCompleted(
                    sessionID: sessionKey,
                    summary: summaryText(facets: facets),
                    timestamp: timestamp,
                    isInterrupt: false,
                    isSessionEnd: false
                )))
            } else {
                events.append(.activityUpdated(SessionActivityUpdated(
                    sessionID: sessionKey,
                    summary: summaryText(facets: facets),
                    phase: lifecycle.phase,
                    timestamp: timestamp
                )))
            }
        }

        return events
    }

    /// Drop bookkeeping for a session, so a later observation with the same key
    /// is announced afresh.
    public func forget(sessionKey: String) {
        lock.withLock { _ = announced.remove(sessionKey) }
        store.removeSession(for: sessionKey)
    }

    public func hasAnnounced(sessionKey: String) -> Bool {
        lock.withLock { announced.contains(sessionKey) }
    }

    // MARK: - Identity

    private func resolveSessionKey(for observation: CodexObservation) -> String? {
        if let key = CodexIdentityResolver.sessionKey(for: observation.ref) {
            return key
        }
        return nil
    }

    // MARK: - Event construction

    private func makeSessionStarted(
        facets: CodexSessionFacets,
        timestamp: Date
    ) -> SessionStarted? {
        // Placement gives the workspace its name and the jump its target. Until
        // some source has supplied it there is nothing meaningful to show.
        guard let jumpTarget = makeJumpTarget(facets: facets) else {
            return nil
        }

        let narrative = facets.narrative?.value
        let title = narrative?.title
            ?? narrative?.initialUserPrompt.map(Self.condense)
            ?? jumpTarget.workspaceName

        return SessionStarted(
            sessionID: facets.sessionKey,
            title: title,
            tool: .codex,
            origin: .live,
            initialPhase: facets.lifecycle?.value.phase ?? .running,
            summary: summaryText(facets: facets),
            timestamp: timestamp,
            jumpTarget: jumpTarget,
            codexMetadata: makeMetadata(facets: facets),
            claudeMetadata: nil,
            geminiMetadata: nil,
            openCodeMetadata: nil,
            cursorMetadata: nil,
            isRemote: false
        )
    }

    private func makeJumpTarget(facets: CodexSessionFacets) -> JumpTarget? {
        let placement = facets.placement?.value

        // Terminal identity comes from a hook when one has fired. At cold
        // start none has, so it is derived from the surface instead:
        //
        // - a desktop thread has no terminal at all; the jump activates
        //   Codex.app and selects the thread by id
        // - anything else ran in *some* terminal we cannot yet name, so it
        //   takes the house "Unknown" sentinel and jumps by folder, the same
        //   convention transcript-restored Claude sessions use
        //
        // Guessing "Codex.app" for everything — as the previous implementation
        // did — is what mislabelled CLI sessions as desktop ones.
        let terminalApp: String
        if facets.isDesktopApp {
            terminalApp = "Codex.app"
        } else if let app = placement?.terminalApp, !app.isEmpty {
            terminalApp = app
        } else if facets.workspace != nil {
            terminalApp = "Unknown"
        } else {
            return nil
        }

        let cwd = facets.workspace?.value.workingDirectory
        let workspaceName = cwd.map { WorkspaceNameResolver.workspaceName(for: $0) } ?? terminalApp

        return JumpTarget(
            terminalApp: terminalApp,
            workspaceName: workspaceName,
            paneTitle: placement?.terminalTitle ?? workspaceName,
            workingDirectory: cwd,
            terminalSessionID: placement?.terminalSessionID,
            terminalTTY: placement?.terminalTTY,
            tmuxTarget: nil,
            tmuxSocketPath: nil,
            warpPaneUUID: placement?.warpPaneUUID,
            codexThreadID: facets.isDesktopApp ? facets.sessionKey : nil
        )
    }

    private func makeMetadata(facets: CodexSessionFacets) -> CodexSessionMetadata? {
        guard let narrative = facets.narrative?.value else { return nil }
        let metadata = CodexSessionMetadata(
            transcriptPath: narrative.transcriptPath,
            initialUserPrompt: narrative.initialUserPrompt,
            lastUserPrompt: narrative.lastUserPrompt,
            lastAssistantMessage: narrative.lastAssistantMessage,
            currentTool: narrative.currentTool,
            currentCommandPreview: narrative.currentCommandPreview,
            activeSubagentCount: narrative.activeSubagentCount
        )
        return metadata.isEmpty ? nil : metadata
    }

    private func summaryText(facets: CodexSessionFacets) -> String {
        let narrative = facets.narrative?.value
        if let preview = narrative?.currentCommandPreview, !preview.isEmpty {
            return Self.condense(preview)
        }
        if let tool = narrative?.currentTool, !tool.isEmpty {
            return tool
        }
        if let message = narrative?.lastAssistantMessage, !message.isEmpty {
            return Self.condense(message)
        }
        if let prompt = narrative?.lastUserPrompt, !prompt.isEmpty {
            return Self.condense(prompt)
        }
        return ""
    }

    /// Collapse a multi-line body to a single line short enough for a session row.
    static func condense(_ text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = flattened.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return collapsed.count > 120 ? String(collapsed.prefix(120)) + "…" : collapsed
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
