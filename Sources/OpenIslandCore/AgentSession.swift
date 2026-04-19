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
    case kimiCLI

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
        case .kimiCLI:
            "Kimi CLI"
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
        case .kimiCLI:
            "KIMI"
        }
    }

    public var isClaudeCodeFork: Bool {
        switch self {
        case .claudeCode, .qoder, .qwenCode, .factory, .codebuddy, .kimiCLI:
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

public enum SessionPhase: String, Codable, Sendable, CaseIterable {
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
    public var warpPaneUUID: String?
    /// Codex.app thread/conversation ID.  When set and `terminalApp` is
    /// `"Codex.app"`, the jump uses the `codex://threads/<id>` URL scheme
    /// to open the conversation directly rather than just activating the app.
    public var codexThreadID: String?

    public init(
        terminalApp: String,
        workspaceName: String,
        paneTitle: String,
        workingDirectory: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        tmuxTarget: String? = nil,
        tmuxSocketPath: String? = nil,
        warpPaneUUID: String? = nil,
        codexThreadID: String? = nil
    ) {
        self.terminalApp = terminalApp
        self.workspaceName = workspaceName
        self.paneTitle = paneTitle
        self.workingDirectory = workingDirectory
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.tmuxTarget = tmuxTarget
        self.tmuxSocketPath = tmuxSocketPath
        self.warpPaneUUID = warpPaneUUID
        self.codexThreadID = codexThreadID
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
    public var requiresTerminalApproval: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        affectedPath: String,
        primaryActionTitle: String = "Allow",
        secondaryActionTitle: String = "Deny",
        toolName: String? = nil,
        toolUseID: String? = nil,
        suggestedUpdates: [ClaudePermissionUpdate] = [],
        requiresTerminalApproval: Bool = false
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
        self.requiresTerminalApproval = requiresTerminalApproval
    }
}

/// A single selectable option within a structured question prompt.
public struct QuestionOption: Equatable, Identifiable, Codable, Sendable {
    public var id: UUID
    public var label: String
    public var description: String
    /// When true, the submitted answer is the user's typed text, not the label.
    public var allowsFreeform: Bool

    public init(
        id: UUID = UUID(),
        label: String,
        description: String = "",
        allowsFreeform: Bool = false
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.allowsFreeform = allowsFreeform
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
    public var geminiMetadata: GeminiSessionMetadata?
    public var openCodeMetadata: OpenCodeSessionMetadata?
    public var cursorMetadata: CursorSessionMetadata?

    /// Whether this session originates from a remote (SSH) connection.
    public var isRemote: Bool = false

    /// Whether this session's lifecycle is driven by hook events rather than
    /// process polling. When `true`, visibility is determined by hook signals
    /// (`SessionStart` / `SessionEnd`) instead of `ps`/`lsof` process discovery.
    public var isHookManaged: Bool = false

    /// Whether this Codex session originates from the Codex desktop app
    /// rather than the Codex CLI.  When `true`, liveness is determined by
    /// whether Codex.app is running (`NSRunningApplication`), not by
    /// matching individual CLI subprocess PIDs.
    public var isCodexAppSession: Bool = false

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
        geminiMetadata: GeminiSessionMetadata? = nil,
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
        self.geminiMetadata = geminiMetadata
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
        case geminiMetadata
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
        geminiMetadata = try container.decodeIfPresent(GeminiSessionMetadata.self, forKey: .geminiMetadata)
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
        try container.encodeIfPresent(geminiMetadata, forKey: .geminiMetadata)
        try container.encodeIfPresent(openCodeMetadata, forKey: .openCodeMetadata)
        try container.encodeIfPresent(cursorMetadata, forKey: .cursorMetadata)
    }
}

public extension AgentSession {
    var isDemoSession: Bool {
        origin == .demo
    }

    var isTrackedLiveSession: Bool {
        !isDemoSession && (tool == .codex || tool == .claudeCode || tool == .geminiCLI || tool == .openCode || tool == .qoder || tool == .qwenCode || tool == .factory || tool == .codebuddy || tool == .cursor || tool == .kimiCLI)
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
        // Codex.app sessions stay visible while the desktop app is running.
        // Checked before isHookManaged because a Codex.app session may also
        // be hook-managed (when both hook and rediscovery converge on it).
        if isCodexAppSession { return isProcessAlive }
        if isHookManaged { return !isSessionEnded }
        if isProcessAlive { return true }
        return false
    }

    var currentToolName: String? {
        codexMetadata?.currentTool ?? claudeMetadata?.currentTool ?? openCodeMetadata?.currentTool ?? cursorMetadata?.currentTool
    }

    var lastAssistantMessageText: String? {
        codexMetadata?.lastAssistantMessage ?? claudeMetadata?.lastAssistantMessage ?? geminiMetadata?.lastAssistantMessage ?? openCodeMetadata?.lastAssistantMessage ?? cursorMetadata?.lastAssistantMessage
    }

    var completionAssistantMessageText: String? {
        if let gemini = geminiMetadata {
            if let body = gemini.lastAssistantMessageBody?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !body.isEmpty {
                if let extractedBody = Self.extractGeminiCompletionBody(from: body) {
                    return extractedBody
                }
            }
            return gemini.lastAssistantMessage
        }
        return lastAssistantMessageText
    }

    var trackingTranscriptPath: String? {
        codexMetadata?.transcriptPath ?? claudeMetadata?.transcriptPath ?? geminiMetadata?.transcriptPath
    }

    var latestUserPromptText: String? {
        codexMetadata?.lastUserPrompt ?? claudeMetadata?.lastUserPrompt ?? geminiMetadata?.lastUserPrompt ?? openCodeMetadata?.lastUserPrompt ?? cursorMetadata?.lastUserPrompt
    }

    var initialUserPromptText: String? {
        codexMetadata?.initialUserPrompt ?? claudeMetadata?.initialUserPrompt ?? geminiMetadata?.initialUserPrompt ?? openCodeMetadata?.initialUserPrompt ?? cursorMetadata?.initialUserPrompt
    }

    var currentCommandPreviewText: String? {
        codexMetadata?.currentCommandPreview ?? claudeMetadata?.currentToolInputPreview ?? openCodeMetadata?.currentToolInputPreview ?? cursorMetadata?.currentToolInputPreview
    }
}

private extension AgentSession {
    static func extractGeminiCompletionBody(from body: String) -> String? {
        let normalizedBody = normalizeGeminiBlankLines(in: body)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n\n", options: .regularExpression)

        let segments = normalizedBody
            .components(separatedBy: "\n\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let lastSegment = segments.last else {
            return nil
        }

        // Gemini hook payloads sometimes append a duplicate copy of the final
        // answer, often with only whitespace differences. Deduplicate against a
        // whitespace-compacted view of the text, but preserve the original
        // formatting in the string we return to the UI.
        let deduplicatedSegment = removeRepeatedTrailingGeminiContent(from: lastSegment)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return deduplicatedSegment.isEmpty ? nil : deduplicatedSegment
    }

    static func normalizeGeminiBlankLines(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                line.trimmingCharacters(in: .whitespaces).isEmpty ? "" : line
            }
            .joined(separator: "\n")
    }

    static func removeRepeatedTrailingGeminiContent(from text: String) -> String {
        let compacted = compactedGeminiText(text)
        let minimumRepeatedTailLength = 30

        guard compacted.characters.count >= minimumRepeatedTailLength * 2 else {
            return text
        }

        let maximumTailLength = compacted.characters.count / 2
        guard maximumTailLength >= minimumRepeatedTailLength else {
            return text
        }

        guard let repeatedTailStart = longestRepeatedGeminiTailStart(
            in: compacted.characters,
            minimumLength: minimumRepeatedTailLength
        ) else {
            return text
        }

        let originalTailStart = compacted.originalIndices[repeatedTailStart]
        let adjustedTailStart = adjustedGeminiDuplicateBoundary(in: text, from: originalTailStart)
        return String(text[..<adjustedTailStart]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compactedGeminiText(_ text: String) -> (characters: [Character], originalIndices: [String.Index]) {
        var characters: [Character] = []
        var originalIndices: [String.Index] = []

        for index in text.indices {
            let character = text[index]
            if character.isWhitespace {
                continue
            }
            characters.append(character)
            originalIndices.append(index)
        }

        return (characters, originalIndices)
    }

    static func longestRepeatedGeminiTailStart(
        in characters: [Character],
        minimumLength: Int
    ) -> Int? {
        let count = characters.count
        guard count >= minimumLength * 2 else {
            return nil
        }

        for length in stride(from: count / 2, through: minimumLength, by: -1) {
            let tailStart = count - length
            let tail = Array(characters[tailStart...])

            if tailStart < length {
                continue
            }

            for candidateStart in 0...(tailStart - length) {
                let candidateEnd = candidateStart + length
                if Array(characters[candidateStart..<candidateEnd]) == tail {
                    return tailStart
                }
            }
        }

        return nil
    }

    static func adjustedGeminiDuplicateBoundary(in text: String, from index: String.Index) -> String.Index {
        var boundary = index

        while boundary > text.startIndex {
            let previous = text.index(before: boundary)
            if text[previous].isWhitespace {
                boundary = previous
                continue
            }
            break
        }

        var searchIndex = boundary
        while searchIndex > text.startIndex {
            let candidate = text.index(before: searchIndex)
            if text[candidate] != "\n" {
                searchIndex = candidate
                continue
            }

            var newlineCount = 1
            var probe = candidate
            while probe > text.startIndex {
                let previous = text.index(before: probe)
                if text[previous] == "\n" {
                    newlineCount += 1
                    probe = previous
                    continue
                }
                if text[previous].isWhitespace {
                    probe = previous
                    continue
                }
                break
            }

            if newlineCount >= 2 {
                let fragment = text[searchIndex..<index]
                let compactedFragmentCount = fragment.reduce(into: 0) { count, character in
                    if !character.isWhitespace {
                        count += 1
                    }
                }

                if compactedFragmentCount <= 12 {
                    return searchIndex
                }
                return boundary
            }

            searchIndex = candidate
        }

        return boundary
    }
}
