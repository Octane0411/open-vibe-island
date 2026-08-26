import Foundation

/// The assembled Codex ingestion layer: sources in, `AgentEvent`s out.
///
/// This is the seam the rest of the app talks to. It owns the four source
/// adapters, the facet store, and the projector, and it is the only Codex type
/// callers outside this layer need to hold.
///
/// It is deliberately introduced alongside the existing implementation rather
/// than replacing it. `mode` selects which path actually drives the UI, with
/// `.shadow` running both and reporting where they disagree — so the rewrite
/// can be validated against real sessions before anything user-visible depends
/// on it.
public final class CodexIngestionPipeline: @unchecked Sendable {
    /// How the pipeline participates while the rewrite is being validated.
    public enum Mode: String, Sendable {
        /// Legacy path drives the UI; this pipeline runs alongside and only
        /// records divergence.
        case shadow
        /// This pipeline drives the UI.
        case live
        /// Disabled entirely.
        case off
    }

    public let diagnostics: CodexDiagnostics
    public let store: CodexFacetStore
    public let projector: CodexSessionProjector
    public let hooks: CodexHookSource
    public let appServer: CodexAppServerSource
    public let rollout: CodexRolloutSource

    private let lock = NSLock()
    private var mode: Mode
    private var divergences: [String] = []

    public init(mode: Mode = .shadow) {
        let diagnostics = CodexDiagnostics()
        let store = CodexFacetStore(diagnostics: diagnostics)
        self.diagnostics = diagnostics
        self.store = store
        self.projector = CodexSessionProjector(store: store, diagnostics: diagnostics)
        self.hooks = CodexHookSource()
        self.appServer = CodexAppServerSource()
        self.rollout = CodexRolloutSource(diagnostics: diagnostics)
        self.mode = mode
    }

    public var currentMode: Mode {
        lock.lock()
        defer { lock.unlock() }
        return mode
    }

    public func setMode(_ newMode: Mode) {
        lock.lock()
        mode = newMode
        lock.unlock()
    }

    /// Whether the caller should apply what `ingest` returns.
    ///
    /// `ingest` always returns the events this pipeline *would* emit — that is
    /// what makes a shadow run comparable. The caller applies them only when
    /// this is the path driving the UI; otherwise it applies the legacy
    /// events and hands both lists to `recordDivergence`.
    public var drivesUI: Bool {
        currentMode == .live
    }

    /// Compare legacy and candidate cold-start results at the session level.
    ///
    /// Cold start builds sessions directly rather than emitting events, so
    /// the event-level comparison does not apply. What matters there is which
    /// sessions each path would show — spawned threads leaking in was the
    /// headline defect.
    public func recordColdStartComparison(legacySessionIDs: Set<String>) {
        let visible = Set(store.allSessions().filter(\.isUserVisible).map(\.sessionKey))
        let withheld = store.allSessions().filter { !$0.isUserVisible }.count
        guard legacySessionIDs != visible else { return }
        let onlyLegacy = legacySessionIDs.subtracting(visible).count
        let onlyCandidate = visible.subtracting(legacySessionIDs).count
        lock.lock()
        if divergences.count < 500 {
            divergences.append(
                "cold-start: legacy \(legacySessionIDs.count) sessions, candidate \(visible.count) visible "
                + "(\(withheld) withheld as spawned); only-legacy \(onlyLegacy), only-candidate \(onlyCandidate)"
            )
        }
        lock.unlock()
    }

    // MARK: - Ingestion

    public func ingest(hook payload: CodexHookPayload, at timestamp: Date = .now) -> [AgentEvent] {
        guard currentMode != .off else { return [] }
        // A hook delivery proves a live source exists, so cold-start replay is
        // over and provisional values become replaceable.
        store.enterLiveMode()
        return projector.project(hooks.observe(payload, at: timestamp))
    }

    public func ingest(
        appServer notification: CodexAppServerNotification,
        at timestamp: Date = .now
    ) -> [AgentEvent] {
        guard currentMode != .off else { return [] }
        store.enterLiveMode()
        guard let observation = appServer.observe(notification, at: timestamp) else {
            return []
        }
        return projector.project(observation)
    }

    public func ingest(loadedThread thread: CodexThread, at timestamp: Date = .now) -> [AgentEvent] {
        guard currentMode != .off else { return [] }
        store.enterLiveMode()
        return projector.project(appServer.observeLoadedThread(thread, at: timestamp))
    }

    /// Fold a transcript during cold start. Returns no events for transcripts
    /// belonging to threads Codex spawned for itself.
    public func ingest(rolloutFile url: URL, at timestamp: Date = .now) -> [AgentEvent] {
        guard currentMode != .off else { return [] }
        let reading = rollout.read(fileAt: url, at: timestamp)
        guard let observation = reading.observation, !reading.isSubagent else { return [] }
        return projector.project(observation)
    }

    // MARK: - Shadow comparison

    /// Compare what the legacy path produced against what this pipeline would
    /// have produced, and record any disagreement.
    ///
    /// Only the fields a user can actually perceive are compared — event kind,
    /// session, and phase. Timestamps and summary wording differ harmlessly
    /// between the two implementations and would drown the signal.
    public func recordDivergence(legacy: [AgentEvent], candidate: [AgentEvent]) {
        let legacyKeys = Set(legacy.map(Self.comparisonKey))
        let candidateKeys = Set(candidate.map(Self.comparisonKey))
        guard legacyKeys != candidateKeys else { return }

        let missing = legacyKeys.subtracting(candidateKeys).sorted()
        let extra = candidateKeys.subtracting(legacyKeys).sorted()
        var line = ""
        if !missing.isEmpty { line += "missing: \(missing.joined(separator: ", ")) " }
        if !extra.isEmpty { line += "extra: \(extra.joined(separator: ", "))" }

        lock.lock()
        // Bounded so a systematic mismatch cannot grow without limit.
        if divergences.count < 500 {
            divergences.append(line.trimmingCharacters(in: .whitespaces))
        }
        lock.unlock()
    }

    public func divergenceReport() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return divergences
    }

    public func resetDivergences() {
        lock.lock()
        divergences.removeAll()
        lock.unlock()
    }

    static func comparisonKey(_ event: AgentEvent) -> String {
        switch event {
        case let .sessionStarted(payload):
            "started:\(payload.sessionID):\(payload.initialPhase.rawValue)"
        case let .activityUpdated(payload):
            "activity:\(payload.sessionID):\(payload.phase.rawValue)"
        case let .permissionRequested(payload):
            "permission:\(payload.sessionID)"
        case let .questionAsked(payload):
            "question:\(payload.sessionID)"
        case let .sessionCompleted(payload):
            "completed:\(payload.sessionID)"
        case let .jumpTargetUpdated(payload):
            "jump:\(payload.sessionID):\(payload.jumpTarget.terminalApp)"
        case let .sessionMetadataUpdated(payload):
            "metadata:\(payload.sessionID)"
        case let .actionableStateResolved(payload):
            "resolved:\(payload.sessionID)"
        case let .claudeSessionMetadataUpdated(payload):
            "claude:\(payload.sessionID)"
        case let .geminiSessionMetadataUpdated(payload):
            "gemini:\(payload.sessionID)"
        case let .openCodeSessionMetadataUpdated(payload):
            "opencode:\(payload.sessionID)"
        case let .cursorSessionMetadataUpdated(payload):
            "cursor:\(payload.sessionID)"
        }
    }
}
