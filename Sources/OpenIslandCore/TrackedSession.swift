import Foundation

// MARK: - Supporting Types

public enum ProcessState: Equatable, Sendable {
    case alive
    case gone(since: Date)
    case unknown
}

public struct TerminalInfo: Equatable, Codable, Sendable {
    public var app: String
    public var tty: String?
    public var terminalSessionID: String?

    public init(
        app: String,
        tty: String? = nil,
        terminalSessionID: String? = nil
    ) {
        self.app = app
        self.tty = tty
        self.terminalSessionID = terminalSessionID
    }
}

/// Metadata about an agent session that flows from hooks through to the UI layer.
/// This is the shared representation — agent-specific metadata (e.g. `ClaudeSessionMetadata`)
/// is converted into this type by `SessionStore.sessionMetadata(from:)`.
public struct SessionMetadata: Equatable, Sendable {
    public var initialPrompt: String?
    public var lastPrompt: String?
    public var lastAssistantMessage: String?
    public var model: String?
    public var currentTool: String?
    public var currentToolInputPreview: String?
    public var worktreeBranch: String?
    /// The active permission mode for the session (e.g. default, acceptEdits, bypassPermissions).
    /// Useful for warning users when a session runs with elevated permissions.
    public var permissionMode: ClaudePermissionMode?
    /// How this session started — fresh startup, resumed, cleared context, or compacted.
    public var startupSource: ClaudeSessionStartSource?
    public var activeSubagents: [ClaudeSubagentInfo]
    public var activeTasks: [ClaudeTaskInfo]

    public init(
        initialPrompt: String? = nil,
        lastPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        model: String? = nil,
        currentTool: String? = nil,
        currentToolInputPreview: String? = nil,
        worktreeBranch: String? = nil,
        permissionMode: ClaudePermissionMode? = nil,
        startupSource: ClaudeSessionStartSource? = nil,
        activeSubagents: [ClaudeSubagentInfo] = [],
        activeTasks: [ClaudeTaskInfo] = []
    ) {
        self.initialPrompt = initialPrompt
        self.lastPrompt = lastPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.model = model
        self.currentTool = currentTool
        self.currentToolInputPreview = currentToolInputPreview
        self.worktreeBranch = worktreeBranch
        self.permissionMode = permissionMode
        self.startupSource = startupSource
        self.activeSubagents = activeSubagents
        self.activeTasks = activeTasks
    }
}

public struct DiscoveredTranscript: Equatable, Sendable {
    public var sessionID: String
    public var transcriptPath: String
    public var workingDirectory: String?
    public var startedAt: Date
    public var lastActivityAt: Date
    public var customTitle: String?
    public var initialPrompt: String?
    public var lastPrompt: String?
    public var lastAssistantMessage: String?
    public var model: String?

    public init(
        sessionID: String,
        transcriptPath: String,
        workingDirectory: String? = nil,
        startedAt: Date,
        lastActivityAt: Date,
        customTitle: String? = nil,
        initialPrompt: String? = nil,
        lastPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        model: String? = nil
    ) {
        self.sessionID = sessionID
        self.transcriptPath = transcriptPath
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.customTitle = customTitle
        self.initialPrompt = initialPrompt
        self.lastPrompt = lastPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.model = model
    }
}

// MARK: - TrackedSession

/// The primary session model used throughout the UI layer.
///
/// A TrackedSession represents one agent conversation (Claude Code, Codex, OpenCode).
/// Sessions are created by two paths:
///   1. **Hook events** — the authoritative path via `SessionStore.applyHookEvent(_:)`,
///      triggered by live hook payloads arriving through the bridge.
///   2. **Discovery** — `SessionStore.discoverClaudeSessions()` reads `~/.claude/sessions/*.json`
///      and creates/updates sessions based on PID liveness. This is the source of truth for
///      whether a Claude Code session is still alive.
///
/// Visibility is determined by `isVisible(at:)`: a session appears in the island if its
/// process is alive, it requires user attention, or it's a demo session.
public struct TrackedSession: Identifiable, Equatable, Sendable {
    public let id: String
    public var tool: AgentTool
    /// Current lifecycle phase — drives UI treatment (badge color, action buttons).
    public var phase: SessionPhase
    public var summary: String
    public var startedAt: Date
    /// Updated on every hook event and discovery poll. Used for age badges and sort order.
    public var lastActivityAt: Date
    public var terminal: TerminalInfo?
    public var workingDirectory: String?
    /// Non-nil when the session is waiting for the user to approve a tool use.
    public var permissionRequest: PermissionRequest?
    /// Non-nil when the session is waiting for the user to answer a question.
    public var questionPrompt: QuestionPrompt?
    /// Liveness state. For Claude Code sessions, this is driven by `~/.claude/sessions/` PID checks.
    public var processState: ProcessState
    /// Whether process discovery has ever confirmed this session's process.
    /// Only sessions confirmed by discovery can transition to `.gone` via discovery.
    public var processConfirmedByDiscovery: Bool
    /// Number of consecutive discovery polls where this session's file was missing.
    /// Hook-created sessions get a grace period (2 polls) before removal to avoid
    /// a race where the hook fires before Claude Code writes the session file.
    public var discoveryMissCount: Int
    public var customTitle: String?
    public var transcriptPath: String?
    public var metadata: SessionMetadata
    public var isRemote: Bool
    public var origin: SessionOrigin?

    public init(
        id: String,
        tool: AgentTool,
        phase: SessionPhase,
        summary: String,
        startedAt: Date,
        lastActivityAt: Date,
        terminal: TerminalInfo? = nil,
        workingDirectory: String? = nil,
        permissionRequest: PermissionRequest? = nil,
        questionPrompt: QuestionPrompt? = nil,
        processState: ProcessState = .unknown,
        processConfirmedByDiscovery: Bool = false,
        discoveryMissCount: Int = 0,
        customTitle: String? = nil,
        transcriptPath: String? = nil,
        metadata: SessionMetadata = SessionMetadata(),
        isRemote: Bool = false,
        origin: SessionOrigin? = nil
    ) {
        self.id = id
        self.tool = tool
        self.phase = phase
        self.summary = summary
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.terminal = terminal
        self.workingDirectory = workingDirectory
        self.permissionRequest = permissionRequest
        self.questionPrompt = questionPrompt
        self.processState = processState
        self.processConfirmedByDiscovery = processConfirmedByDiscovery
        self.discoveryMissCount = discoveryMissCount
        self.customTitle = customTitle
        self.transcriptPath = transcriptPath
        self.metadata = metadata
        self.isRemote = isRemote
        self.origin = origin
    }
}

// MARK: - Display

public extension TrackedSession {
    /// Returns a human-readable display name for the session.
    /// Priority: customTitle > last path component of workingDirectory > "Session <id prefix>"
    var displayName: String {
        if let title = customTitle, !title.isEmpty {
            return title
        }
        if let dir = workingDirectory {
            let lastComponent = (dir as NSString).lastPathComponent
            if !lastComponent.isEmpty {
                return lastComponent
            }
        }
        return "Session \(id.prefix(8))"
    }
}

// MARK: - Visibility

public extension TrackedSession {
    /// Returns whether this session should be shown in the island at the given reference date.
    ///
    /// Visibility rules (evaluated in order):
    ///   1. Demo sessions are always visible (for testing/preview).
    ///   2. Sessions needing user action (permission or question) stay visible regardless of process state.
    ///   3. Sessions with a live process (confirmed by `~/.claude/sessions/` PID check) are visible.
    ///   4. Everything else is hidden — no grace period. When the session file disappears
    ///      or the PID dies, the session drops from the island immediately.
    func isVisible(at referenceDate: Date) -> Bool {
        if origin == .demo { return true }
        if phase.requiresAttention { return true }
        if processState == .alive { return true }
        return false
    }

    /// Returns whether this session should be shown in the island right now.
    var isVisible: Bool {
        isVisible(at: .now)
    }
}

// MARK: - Age Badge

public extension TrackedSession {
    /// Returns a short human-readable string representing how long ago the session started.
    func ageBadge(at referenceDate: Date) -> String {
        let age = referenceDate.timeIntervalSince(startedAt)
        if age < 60 {
            return "<1m"
        } else if age < 3600 {
            return "\(Int(age / 60))m"
        } else if age < 86400 {
            return "\(Int(age / 3600))h"
        } else {
            return "\(Int(age / 86400))d"
        }
    }
}

// MARK: - Subagent Detection

public extension TrackedSession {
    /// Returns true if this session is a subagent session (path contains "/subagents/").
    var isSubagentSession: Bool {
        transcriptPath?.contains("/subagents/") == true
    }
}
