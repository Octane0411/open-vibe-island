import Foundation

public enum OpenCodeHookEventName: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case questionAsked = "QuestionAsked"
    case stop = "Stop"
}

public struct OpenCodeQuestionOption: Equatable, Codable, Sendable {
    public var label: String
    public var description: String

    public init(label: String, description: String = "") {
        self.label = label
        self.description = description
    }
}

public struct OpenCodeQuestion: Equatable, Codable, Sendable {
    public var question: String
    public var header: String
    public var options: [OpenCodeQuestionOption]
    public var multiple: Bool

    public init(
        question: String,
        header: String = "",
        options: [OpenCodeQuestionOption] = [],
        multiple: Bool = false
    ) {
        self.question = question
        self.header = header
        self.options = options
        self.multiple = multiple
    }
}

public struct OpenCodeHookPayload: Equatable, Codable, Sendable {
    public var hookEventName: OpenCodeHookEventName
    public var sessionID: String
    public var cwd: String
    public var toolName: String?
    public var toolInput: String?
    public var permissionID: String?
    public var permissionTitle: String?
    public var permissionDescription: String?
    public var questionID: String?
    public var questionText: String?
    public var questions: [OpenCodeQuestion]?
    public var messageContent: String?
    public var model: String?
    public var prompt: String?
    public var lastAssistantMessage: String?
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var terminalTitle: String?
    public var isSubagent: Bool?

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case permissionID = "permission_id"
        case permissionTitle = "permission_title"
        case permissionDescription = "permission_description"
        case questionID = "question_id"
        case questionText = "question_text"
        case questions
        case messageContent = "message_content"
        case model
        case prompt
        case lastAssistantMessage = "last_assistant_message"
        case terminalApp = "terminal_app"
        case terminalSessionID = "terminal_session_id"
        case terminalTTY = "terminal_tty"
        case terminalTitle = "terminal_title"
        case isSubagent = "is_subagent"
    }

    public init(
        hookEventName: OpenCodeHookEventName,
        sessionID: String,
        cwd: String,
        toolName: String? = nil,
        toolInput: String? = nil,
        permissionID: String? = nil,
        permissionTitle: String? = nil,
        permissionDescription: String? = nil,
        questionID: String? = nil,
        questionText: String? = nil,
        questions: [OpenCodeQuestion]? = nil,
        messageContent: String? = nil,
        model: String? = nil,
        prompt: String? = nil,
        lastAssistantMessage: String? = nil,
        terminalApp: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        terminalTitle: String? = nil,
        isSubagent: Bool? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionID = sessionID
        self.cwd = cwd
        self.toolName = toolName
        self.toolInput = toolInput
        self.permissionID = permissionID
        self.permissionTitle = permissionTitle
        self.permissionDescription = permissionDescription
        self.questionID = questionID
        self.questionText = questionText
        self.questions = questions
        self.messageContent = messageContent
        self.model = model
        self.prompt = prompt
        self.lastAssistantMessage = lastAssistantMessage
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.terminalTitle = terminalTitle
        self.isSubagent = isSubagent
    }
}

public enum OpenCodeHookDirective: Equatable, Codable, Sendable {
    case allow
    case deny(reason: String?)
    case answer(text: String)
    case structuredAnswer(answers: [[String]])

    private enum CodingKeys: String, CodingKey {
        case type
        case reason
        case text
        case answers
    }

    private enum DirectiveType: String, Codable {
        case allow
        case deny
        case answer
        case structuredAnswer
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DirectiveType.self, forKey: .type)

        switch type {
        case .allow:
            self = .allow
        case .deny:
            self = .deny(reason: try container.decodeIfPresent(String.self, forKey: .reason))
        case .answer:
            self = .answer(text: try container.decode(String.self, forKey: .text))
        case .structuredAnswer:
            self = .structuredAnswer(answers: try container.decode([[String]].self, forKey: .answers))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .allow:
            try container.encode(DirectiveType.allow, forKey: .type)
        case let .deny(reason):
            try container.encode(DirectiveType.deny, forKey: .type)
            try container.encodeIfPresent(reason, forKey: .reason)
        case let .answer(text):
            try container.encode(DirectiveType.answer, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .structuredAnswer(answers):
            try container.encode(DirectiveType.structuredAnswer, forKey: .type)
            try container.encode(answers, forKey: .answers)
        }
    }
}

public struct OpenCodeSessionMetadata: Equatable, Codable, Sendable {
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var currentTool: String?
    public var currentToolInputPreview: String?
    public var model: String?

    public init(
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        currentTool: String? = nil,
        currentToolInputPreview: String? = nil,
        model: String? = nil
    ) {
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.currentTool = currentTool
        self.currentToolInputPreview = currentToolInputPreview
        self.model = model
    }

    public var isEmpty: Bool {
        initialUserPrompt == nil
            && lastUserPrompt == nil
            && lastAssistantMessage == nil
            && currentTool == nil
            && currentToolInputPreview == nil
            && model == nil
    }
}

// MARK: - Payload Convenience Extensions

public extension OpenCodeHookPayload {
    var workspaceName: String {
        WorkspaceNameResolver.workspaceName(for: cwd)
    }

    var sessionTitle: String {
        "OpenCode · \(workspaceName)"
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: terminalApp ?? "Unknown",
            workspaceName: workspaceName,
            paneTitle: terminalTitle ?? "OpenCode \(sessionID.prefix(8))",
            workingDirectory: cwd,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY
        )
    }

    var defaultOpenCodeMetadata: OpenCodeSessionMetadata {
        OpenCodeSessionMetadata(
            initialUserPrompt: prompt ?? promptPreview,
            lastUserPrompt: prompt ?? promptPreview,
            lastAssistantMessage: lastAssistantMessage ?? assistantMessagePreview,
            currentTool: toolName,
            currentToolInputPreview: toolInputPreview,
            model: model
        )
    }

    var implicitStartSummary: String {
        switch hookEventName {
        case .sessionStart:
            return "Started OpenCode session in \(workspaceName)."
        case .sessionEnd:
            return "OpenCode session ended in \(workspaceName)."
        case .userPromptSubmit:
            return "OpenCode received a new prompt in \(workspaceName)."
        case .preToolUse:
            return "OpenCode is preparing \(toolName ?? "a tool") in \(workspaceName)."
        case .postToolUse:
            return "OpenCode finished \(toolName ?? "a tool") in \(workspaceName)."
        case .permissionRequest:
            return "OpenCode needs approval in \(workspaceName)."
        case .questionAsked:
            return "OpenCode has a question in \(workspaceName)."
        case .stop:
            return "OpenCode completed a turn in \(workspaceName)."
        }
    }

    var promptPreview: String? {
        clipped(prompt)
    }

    var assistantMessagePreview: String? {
        clipped(lastAssistantMessage)
    }

    var toolInputPreview: String? {
        clipped(toolInput)
    }

    private func clipped(_ value: String?, limit: Int = 110) -> String? {
        guard let value else {
            return nil
        }

        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        guard !collapsed.isEmpty else {
            return nil
        }

        guard collapsed.count > limit else {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
        return "\(collapsed[..<endIndex])…"
    }
}
