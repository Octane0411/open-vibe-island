import Foundation

public enum AgentTool: String, CaseIterable, Codable, Sendable {
    case claudeCode
    case codex
    case geminiCLI
    case openCode
    case qoder
    case qwenCode
    case factory
    case codebuddy
    case cursor

    public var displayName: String {
        switch self {
        case .claudeCode:
            "Claude Code"
        case .codex:
            "Codex"
        case .geminiCLI:
            "Gemini CLI"
        case .openCode:
            "OpenCode"
        case .qoder:
            "Qoder"
        case .qwenCode:
            "Qwen Code"
        case .factory:
            "Factory"
        case .codebuddy:
            "CodeBuddy"
        case .cursor:
            "Cursor"
        }
    }

    public var shortName: String {
        switch self {
        case .claudeCode:
            "CLAUDE"
        case .codex:
            "CODEX"
        case .geminiCLI:
            "GEMINI"
        case .openCode:
            "OPENCODE"
        case .qoder:
            "QODER"
        case .qwenCode:
            "QWEN"
        case .factory:
            "FACTORY"
        case .codebuddy:
            "CODEBUDDY"
        case .cursor:
            "CURSOR"
        }
    }

    public var isClaudeCodeFork: Bool {
        switch self {
        case .claudeCode, .qoder, .qwenCode, .factory, .codebuddy:
            true
        default:
            false
        }
    }
}

public enum SessionOrigin: String, Codable, Sendable {
    case live
    case demo
}

public enum SessionAttachmentState: String, Codable, Sendable {
    case attached
    case stale
    case detached

    public var isLive: Bool {
        self == .attached
    }
}

public enum SessionPhase: String, Codable, Sendable {
    case running
    case waitingForApproval
    case waitingForAnswer
    case completed

    public var displayName: String {
        switch self {
        case .running:
            "Running"
        case .waitingForApproval:
            "Needs approval"
        case .waitingForAnswer:
            "Needs answer"
        case .completed:
            "Completed"
        }
    }

    public var requiresAttention: Bool {
        switch self {
        case .waitingForApproval, .waitingForAnswer:
            true
        case .running, .completed:
            false
        }
    }
}

public struct JumpTarget: Equatable, Codable, Sendable {
    public var terminalApp: String
    public var workspaceName: String
    public var paneTitle: String
    public var workingDirectory: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var tmuxTarget: String?
    public var tmuxSocketPath: String?

    public init(
        terminalApp: String,
        workspaceName: String,
        paneTitle: String,
        workingDirectory: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        tmuxTarget: String? = nil,
        tmuxSocketPath: String? = nil
    ) {
        self.terminalApp = terminalApp
        self.workspaceName = workspaceName
        self.paneTitle = paneTitle
        self.workingDirectory = workingDirectory
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.tmuxTarget = tmuxTarget
        self.tmuxSocketPath = tmuxSocketPath
    }
}

public struct PermissionRequest: Equatable, Identifiable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var affectedPath: String
    public var primaryActionTitle: String
    public var secondaryActionTitle: String
    public var toolName: String?
    public var toolUseID: String?
    public var suggestedUpdates: [ClaudePermissionUpdate]

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        affectedPath: String,
        primaryActionTitle: String = "Allow",
        secondaryActionTitle: String = "Deny",
        toolName: String? = nil,
        toolUseID: String? = nil,
        suggestedUpdates: [ClaudePermissionUpdate] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.affectedPath = affectedPath
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.suggestedUpdates = suggestedUpdates
    }
}

public struct QuestionOption: Equatable, Codable, Sendable {
    public var label: String
    public var description: String

    public init(label: String, description: String = "") {
        self.label = label
        self.description = description
    }
}

public struct QuestionPromptItem: Equatable, Codable, Sendable {
    public var question: String
    public var header: String
    public var options: [QuestionOption]
    public var multiSelect: Bool

    public init(
        question: String,
        header: String,
        options: [QuestionOption],
        multiSelect: Bool = false
    ) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }
}

public struct QuestionPrompt: Equatable, Identifiable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var options: [String]
    public var questions: [QuestionPromptItem]

    public init(
        id: UUID = UUID(),
        title: String,
        options: [String],
        questions: [QuestionPromptItem] = []
    ) {
        self.id = id
        self.title = title
        self.options = options
        self.questions = questions
    }

    public init(
        id: UUID = UUID(),
        title: String,
        questions: [QuestionPromptItem]
    ) {
        self.id = id
        self.title = title
        self.questions = questions
        self.options = questions.first?.options.map(\.label) ?? []
    }
}

public struct QuestionAnswerAnnotation: Equatable, Codable, Sendable {
    public var preview: String?
    public var notes: String?

    public init(preview: String? = nil, notes: String? = nil) {
        self.preview = preview
        self.notes = notes
    }
}

public struct QuestionPromptResponse: Equatable, Codable, Sendable {
    public var rawAnswer: String?
    public var answers: [String: String]
    public var annotations: [String: QuestionAnswerAnnotation]

    public init(
        rawAnswer: String? = nil,
        answers: [String: String] = [:],
        annotations: [String: QuestionAnswerAnnotation] = [:]
    ) {
        self.rawAnswer = rawAnswer
        self.answers = answers
        self.annotations = annotations
    }

    public init(answer: String) {
        self.init(rawAnswer: answer)
    }

    public var displaySummary: String {
        if let rawAnswer, !rawAnswer.isEmpty {
            return rawAnswer
        }

        let renderedAnswers = answers
            .keys
            .sorted()
            .compactMap { key -> String? in
                guard let value = answers[key], !value.isEmpty else {
                    return nil
                }

                return "\(key): \(value)"
            }

        return renderedAnswers.joined(separator: " · ")
    }
}

/// User-facing approval action shown in the island notification card.
public enum ApprovalAction: Sendable {
    case deny
    case allowOnce
    case allowWithUpdates([ClaudePermissionUpdate])
}

public enum PermissionResolution: Equatable, Codable, Sendable {
    case allowOnce(updatedInput: ClaudeHookJSONValue? = nil, updatedPermissions: [ClaudePermissionUpdate] = [])
    case deny(message: String? = nil, interrupt: Bool = false)

    public var isApproved: Bool {
        switch self {
        case .allowOnce:
            true
        case .deny:
            false
        }
    }
}

public struct AgentSession: Equatable, Identifiable, Codable, Sendable {
    public var id: String
    public var title: String
    public var tool: AgentTool
    public var origin: SessionOrigin?
    public var attachmentState: SessionAttachmentState
    public var phase: SessionPhase
    public var summary: String
    public var updatedAt: Date
    public var permissionRequest: PermissionRequest?
    public var questionPrompt: QuestionPrompt?
    public var jumpTarget: JumpTarget?
    public var codexMetadata: CodexSessionMetadata?
    public var claudeMetadata: ClaudeSessionMetadata?
    public var openCodeMetadata: OpenCodeSessionMetadata?
    public var cursorMetadata: CursorSessionMetadata?

    /// Whether this session originates from a remote (SSH) connection.
    public var isRemote: Bool = false

    /// Whether this session's lifecycle is driven by hook events rather than
    /// process polling. When `true`, visibility is determined by hook signals
    /// (`SessionStart` / `SessionEnd`) instead of `ps`/`lsof` process discovery.
    public var isHookManaged: Bool = false

    /// Whether the agent session has ended (received `SessionEnd` hook).
    /// Only meaningful for hook-managed sessions.
    public var isSessionEnded: Bool = false

    /// Whether the agent process is currently alive according to process discovery.
    /// Used for non-hook-managed sessions (e.g. Codex, synthetic Claude sessions).
    public var isProcessAlive: Bool = false

    /// Number of consecutive reconciliation polls where the process was not found.
    /// Reset to 0 when the process is found. When >= 2 (~6 seconds), the session
    /// is considered gone. This prevents flicker from momentary `ps` gaps.
    public var processNotSeenCount: Int = 0

    public init(
        id: String,
        title: String,
        tool: AgentTool,
        origin: SessionOrigin? = nil,
        attachmentState: SessionAttachmentState = .stale,
        phase: SessionPhase,
        summary: String,
        updatedAt: Date,
        permissionRequest: PermissionRequest? = nil,
        questionPrompt: QuestionPrompt? = nil,
        jumpTarget: JumpTarget? = nil,
        codexMetadata: CodexSessionMetadata? = nil,
        claudeMetadata: ClaudeSessionMetadata? = nil,
        openCodeMetadata: OpenCodeSessionMetadata? = nil,
        cursorMetadata: CursorSessionMetadata? = nil
    ) {
        self.id = id
        self.title = title
        self.tool = tool
        self.origin = origin
        self.attachmentState = attachmentState
        self.phase = phase
        self.summary = summary
        self.updatedAt = updatedAt
        self.permissionRequest = permissionRequest
        self.questionPrompt = questionPrompt
        self.jumpTarget = jumpTarget
        self.codexMetadata = codexMetadata
        self.claudeMetadata = claudeMetadata
        self.openCodeMetadata = openCodeMetadata
        self.cursorMetadata = cursorMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case tool
        case origin
        case attachmentState
        case phase
        case summary
        case updatedAt
        case permissionRequest
        case questionPrompt
        case jumpTarget
        case codexMetadata
        case claudeMetadata
        case openCodeMetadata
        case cursorMetadata
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        tool = try container.decode(AgentTool.self, forKey: .tool)
        origin = try container.decodeIfPresent(SessionOrigin.self, forKey: .origin)
        attachmentState = try container.decodeIfPresent(SessionAttachmentState.self, forKey: .attachmentState) ?? .stale
        phase = try container.decode(SessionPhase.self, forKey: .phase)
        summary = try container.decode(String.self, forKey: .summary)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        permissionRequest = try container.decodeIfPresent(PermissionRequest.self, forKey: .permissionRequest)
        questionPrompt = try container.decodeIfPresent(QuestionPrompt.self, forKey: .questionPrompt)
        jumpTarget = try container.decodeIfPresent(JumpTarget.self, forKey: .jumpTarget)
        codexMetadata = try container.decodeIfPresent(CodexSessionMetadata.self, forKey: .codexMetadata)
        claudeMetadata = try container.decodeIfPresent(ClaudeSessionMetadata.self, forKey: .claudeMetadata)
        openCodeMetadata = try container.decodeIfPresent(OpenCodeSessionMetadata.self, forKey: .openCodeMetadata)
        cursorMetadata = try container.decodeIfPresent(CursorSessionMetadata.self, forKey: .cursorMetadata)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(tool, forKey: .tool)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encode(attachmentState, forKey: .attachmentState)
        try container.encode(phase, forKey: .phase)
        try container.encode(summary, forKey: .summary)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(permissionRequest, forKey: .permissionRequest)
        try container.encodeIfPresent(questionPrompt, forKey: .questionPrompt)
        try container.encodeIfPresent(jumpTarget, forKey: .jumpTarget)
        try container.encodeIfPresent(codexMetadata, forKey: .codexMetadata)
        try container.encodeIfPresent(claudeMetadata, forKey: .claudeMetadata)
        try container.encodeIfPresent(openCodeMetadata, forKey: .openCodeMetadata)
        try container.encodeIfPresent(cursorMetadata, forKey: .cursorMetadata)
    }
}

public extension AgentSession {
    var isDemoSession: Bool {
        origin == .demo
    }

    var isTrackedLiveSession: Bool {
        !isDemoSession && (tool == .codex || tool == .claudeCode || tool == .openCode || tool == .qoder || tool == .qwenCode || tool == .factory || tool == .codebuddy || tool == .cursor)
    }

    var isTrackedLiveCodexSession: Bool {
        tool == .codex && !isDemoSession
    }

    var isAttachedToTerminal: Bool {
        attachmentState.isLive
    }

    /// Visibility rule for the island UI.
    /// Hook-managed sessions (Claude Code via hooks) rely on hook lifecycle
    /// signals; non-hook sessions use process polling.
    var isVisibleInIsland: Bool {
        if isDemoSession { return true }
        if phase.requiresAttention { return true }
        if isHookManaged { return !isSessionEnded }
        if isProcessAlive { return true }
        return false
    }

    var currentToolName: String? {
        codexMetadata?.currentTool ?? claudeMetadata?.currentTool ?? openCodeMetadata?.currentTool ?? cursorMetadata?.currentTool
    }

    var lastAssistantMessageText: String? {
        codexMetadata?.lastAssistantMessage ?? claudeMetadata?.lastAssistantMessage ?? openCodeMetadata?.lastAssistantMessage ?? cursorMetadata?.lastAssistantMessage
    }

    var trackingTranscriptPath: String? {
        codexMetadata?.transcriptPath ?? claudeMetadata?.transcriptPath
    }

    var latestUserPromptText: String? {
        codexMetadata?.lastUserPrompt ?? claudeMetadata?.lastUserPrompt ?? openCodeMetadata?.lastUserPrompt ?? cursorMetadata?.lastUserPrompt
    }

    var initialUserPromptText: String? {
        codexMetadata?.initialUserPrompt ?? claudeMetadata?.initialUserPrompt ?? openCodeMetadata?.initialUserPrompt ?? cursorMetadata?.initialUserPrompt
    }

    var currentCommandPreviewText: String? {
        codexMetadata?.currentCommandPreview ?? claudeMetadata?.currentToolInputPreview ?? openCodeMetadata?.currentToolInputPreview ?? cursorMetadata?.currentToolInputPreview
    }
}
