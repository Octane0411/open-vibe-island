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

public struct SessionMetadata: Equatable, Sendable {
    public var initialPrompt: String?
    public var lastPrompt: String?
    public var lastAssistantMessage: String?
    public var model: String?
    public var currentTool: String?
    public var currentToolInputPreview: String?
    public var worktreeBranch: String?
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

public struct TrackedSession: Identifiable, Equatable, Sendable {
    public let id: String
    public var tool: AgentTool
    public var phase: SessionPhase
    public var summary: String
    public var startedAt: Date
    public var lastActivityAt: Date
    public var terminal: TerminalInfo?
    public var workingDirectory: String?
    public var permissionRequest: PermissionRequest?
    public var questionPrompt: QuestionPrompt?
    public var processState: ProcessState
    /// Whether process discovery has ever confirmed this session's process.
    /// Only sessions confirmed by discovery can transition to `.gone` via discovery.
    public var processConfirmedByDiscovery: Bool
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
    /// Strictly synced with live Claude Code sessions — no grace period.
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
