import Foundation

// MARK: - Sources

/// The four channels through which Codex activity reaches Open Island.
///
/// These are not interchangeable. Each speaks a different protocol with a
/// different compatibility guarantee, and — critically — each is blind to parts
/// of the session state the others can see. `CodexAuthorityMatrix` encodes
/// which facets each source is allowed to write; this enum only names them.
public enum CodexSource: String, CaseIterable, Codable, Sendable, Comparable {
    /// Codex hook CLI invocations. A documented, config-driven contract, and
    /// the only source that knows which terminal the session runs in.
    case hook

    /// The `app-server` JSON-RPC channel exposed by Codex.app. Authoritative
    /// for thread lifecycle, and the only source that can observe a desktop
    /// thread closing.
    case appServer

    /// The rollout JSONL transcript. An internal Codex implementation detail
    /// with no compatibility contract — used for cold-start recovery and for
    /// classifying where a session came from, never for liveness or approvals.
    case rollout

    /// Process-table observation (pid liveness). A last-resort fallback.
    case process

    public var displayName: String {
        switch self {
        case .hook: "hook"
        case .appServer: "app-server"
        case .rollout: "rollout"
        case .process: "process"
        }
    }

    public static func < (lhs: CodexSource, rhs: CodexSource) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Identity

/// How a given source names a session.
///
/// Codex uses different identifiers depending on where you observe it from:
/// the app-server speaks thread IDs, hooks and `session_meta` speak session
/// IDs, and cold-start discovery starts with nothing but a file on disk.
/// `CodexIdentityResolver` collapses these into one session key.
public enum CodexIdentityRef: Hashable, Sendable {
    case threadID(String)
    case sessionID(String)
    case rolloutFile(URL)
    case processID(Int32)

    public var stringValue: String {
        switch self {
        case let .threadID(value): "thread:\(value)"
        case let .sessionID(value): "session:\(value)"
        case let .rolloutFile(url): "file:\(url.lastPathComponent)"
        case let .processID(pid): "pid:\(pid)"
        }
    }
}

// MARK: - Surface

/// Where a Codex session is running.
///
/// Derived from `session_meta.originator` and `session_meta.source`, which are
/// the only authoritative signals for this. The previous implementation
/// inferred it by string-matching `jumpTarget.terminalApp == "Codex.app"`,
/// which lags reality and silently breaks whenever Codex renames anything.
public enum CodexSurface: Equatable, Sendable {
    /// Codex.app, the desktop client.
    case desktopApp
    /// `codex` in a terminal (the TUI).
    case cli
    /// The Codex extension running inside VS Code.
    case vscode
    /// Non-interactive `codex exec`.
    case exec
    /// A thread Codex spawned for itself — a subagent, guardian, or other
    /// internal worker. Never surfaced as a user session.
    case subagent(parentThreadID: String?, kind: String?)
    /// A Codex-internal daemon that should not appear in the session list.
    case internalDaemon
    /// Recognized as Codex, but the originator is not in the allow-list. Shown
    /// as a plain session and reported through diagnostics.
    case unknown(originator: String?)

    /// Whether a session on this surface belongs in the user-visible list.
    public var isUserVisible: Bool {
        switch self {
        case .desktopApp, .cli, .vscode, .exec: true
        case .unknown: true
        case .subagent, .internalDaemon: false
        }
    }

    public var isDesktopApp: Bool {
        if case .desktopApp = self { return true }
        return false
    }

    public var isSubagent: Bool {
        if case .subagent = self { return true }
        return false
    }
}

// MARK: - Facets

/// Where the session's work lives on disk.
///
/// Kept separate from `CodexPlacement` because the two have different
/// witnesses: `session_meta.cwd` is written by Codex itself and is the
/// definitive record of the working directory, while only a hook can say which
/// terminal the session is attached to. Folding them together would force one
/// authority ranking onto two independently observable things — and would leave
/// Codex.app sessions, which have no terminal at all, with no workspace either.
public struct CodexWorkspace: Equatable, Sendable {
    public var workingDirectory: String

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }
}

/// Terminal identity — everything needed to return to the pane a session is
/// running in. Only hooks can observe this; the app-server and the rollout
/// transcript have no idea which terminal invoked Codex.
public struct CodexPlacement: Equatable, Sendable {
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var terminalTitle: String?
    public var warpPaneUUID: String?

    public init(
        terminalApp: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        terminalTitle: String? = nil,
        warpPaneUUID: String? = nil
    ) {
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.terminalTitle = terminalTitle
        self.warpPaneUUID = warpPaneUUID
    }

    public var isEmpty: Bool {
        terminalApp == nil && terminalSessionID == nil && terminalTTY == nil
            && terminalTitle == nil && warpPaneUUID == nil
    }
}

/// Run state within a turn. The app-server reports this directly; hooks imply
/// it from tool-use boundaries. The rollout transcript only ever reflects it
/// after the fact, which is why it may not write this facet.
public struct CodexLifecycle: Equatable, Sendable {
    public var phase: SessionPhase
    public var turnID: String?

    public init(phase: SessionPhase, turnID: String? = nil) {
        self.phase = phase
        self.turnID = turnID
    }
}

/// A pending approval or question. Hooks are the only source: Codex moved
/// approvals out of the rollout transcript into the hook system, and the
/// former rollout parsing path now matches nothing at all.
public enum CodexActionable: Equatable, Sendable {
    case permission(PermissionRequest)
    case question(QuestionPrompt)
    case cleared
}

/// Human-facing description of what the session is doing.
public struct CodexNarrative: Equatable, Sendable {
    public var title: String?
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var currentTool: String?
    public var currentCommandPreview: String?
    public var transcriptPath: String?
    /// Absolute count, not a delta — the source that observes subagent
    /// boundaries keeps the running total, so the store can merge it like any
    /// other narrative field.
    public var activeSubagentCount: Int?

    public init(
        title: String? = nil,
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        currentTool: String? = nil,
        currentCommandPreview: String? = nil,
        transcriptPath: String? = nil,
        activeSubagentCount: Int? = nil
    ) {
        self.title = title
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.currentTool = currentTool
        self.currentCommandPreview = currentCommandPreview
        self.transcriptPath = transcriptPath
        self.activeSubagentCount = activeSubagentCount
    }

    public var isEmpty: Bool {
        title == nil && initialUserPrompt == nil && lastUserPrompt == nil
            && lastAssistantMessage == nil && currentTool == nil
            && currentCommandPreview == nil && transcriptPath == nil
            && activeSubagentCount == nil
    }

    /// Merge another narrative over this one, keeping existing values where the
    /// incoming one has nothing to say. Narrative arrives in fragments from
    /// several sources, so a partial update must not erase what is already known.
    public func merging(_ other: CodexNarrative) -> CodexNarrative {
        CodexNarrative(
            title: other.title ?? title,
            initialUserPrompt: other.initialUserPrompt ?? initialUserPrompt,
            lastUserPrompt: other.lastUserPrompt ?? lastUserPrompt,
            lastAssistantMessage: other.lastAssistantMessage ?? lastAssistantMessage,
            currentTool: other.currentTool ?? currentTool,
            currentCommandPreview: other.currentCommandPreview ?? currentCommandPreview,
            transcriptPath: other.transcriptPath ?? transcriptPath,
            activeSubagentCount: other.activeSubagentCount ?? activeSubagentCount
        )
    }
}

/// Whether the session still exists.
public struct CodexLiveness: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case alive
        case ended(reason: EndReason)
    }

    public enum EndReason: String, Equatable, Sendable {
        /// `thread/closed` from the app-server — the strongest signal there is.
        case threadClosed
        /// The Codex process exited.
        case processExited
        /// A `Stop` hook fired and no further activity followed.
        case stopHook
        /// A `SessionEnd` hook fired — the strongest signal a terminal session
        /// can give, and the one that actually means "ended" rather than
        /// "finished a turn".
        case sessionEnd
        /// Codex.app moved the rollout into `archived_sessions/`.
        case archived
    }

    public var state: State
    public init(state: State) {
        self.state = state
    }

    public var isAlive: Bool { state == .alive }
}

/// A partial view of one session, carrying only the facets its source is able
/// to observe. Every field is optional: a source fills in what it knows and
/// leaves the rest alone.
public struct CodexFacetPatch: Equatable, Sendable {
    public var surface: CodexSurface?
    public var workspace: CodexWorkspace?
    public var placement: CodexPlacement?
    public var lifecycle: CodexLifecycle?
    public var actionable: CodexActionable?
    public var narrative: CodexNarrative?
    public var liveness: CodexLiveness?

    public init(
        surface: CodexSurface? = nil,
        workspace: CodexWorkspace? = nil,
        placement: CodexPlacement? = nil,
        lifecycle: CodexLifecycle? = nil,
        actionable: CodexActionable? = nil,
        narrative: CodexNarrative? = nil,
        liveness: CodexLiveness? = nil
    ) {
        self.surface = surface
        self.workspace = workspace
        self.placement = placement
        self.lifecycle = lifecycle
        self.actionable = actionable
        self.narrative = narrative
        self.liveness = liveness
    }

    public var isEmpty: Bool {
        surface == nil && workspace == nil && placement == nil && lifecycle == nil
            && actionable == nil && narrative == nil && liveness == nil
    }
}

// MARK: - Observation

/// One source's report about one session at one moment.
///
/// This is the only shape that crosses from the collection layer into
/// projection. Sources do not know about `AgentSession`, about `AgentEvent`, or
/// about each other — they translate their native protocol into observations
/// and stop there.
public struct CodexObservation: Equatable, Sendable {
    public let ref: CodexIdentityRef
    public let source: CodexSource
    /// Monotonic within a source. Used to order observations and to discard
    /// ones that arrive late, so out-of-order delivery cannot rewind state.
    public let seq: UInt64
    public let observedAt: Date
    public let patch: CodexFacetPatch
    /// Codex version that produced the observation, when known. Carried for
    /// diagnostics so drift can be attributed to a release.
    public let cliVersion: String?

    public init(
        ref: CodexIdentityRef,
        source: CodexSource,
        seq: UInt64,
        observedAt: Date,
        patch: CodexFacetPatch,
        cliVersion: String? = nil
    ) {
        self.ref = ref
        self.source = source
        self.seq = seq
        self.observedAt = observedAt
        self.patch = patch
        self.cliVersion = cliVersion
    }
}
