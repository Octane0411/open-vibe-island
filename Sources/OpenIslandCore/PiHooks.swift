import Foundation

public enum PiHookEventName: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case agentStart = "AgentStart"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case stop = "Stop"
}

public struct PiHookPayload: Equatable, Codable, Sendable {
    public var hookEventName: PiHookEventName
    public var sessionID: String
    public var cwd: String
    public var transcriptPath: String?
    public var model: String?
    public var prompt: String?
    public var lastAssistantMessage: String?
    public var toolName: String?
    public var toolInput: String?
    public var toolUseID: String?
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var terminalTitle: String?

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case transcriptPath = "transcript_path"
        case model
        case prompt
        case lastAssistantMessage = "last_assistant_message"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseID = "tool_use_id"
        case terminalApp = "terminal_app"
        case terminalSessionID = "terminal_session_id"
        case terminalTTY = "terminal_tty"
        case terminalTitle = "terminal_title"
    }

    public init(
        hookEventName: PiHookEventName,
        sessionID: String,
        cwd: String,
        transcriptPath: String? = nil,
        model: String? = nil,
        prompt: String? = nil,
        lastAssistantMessage: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil,
        toolUseID: String? = nil,
        terminalApp: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        terminalTitle: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionID = sessionID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.prompt = prompt
        self.lastAssistantMessage = lastAssistantMessage
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolUseID = toolUseID
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.terminalTitle = terminalTitle
    }
}

public enum PiHookDirective: Equatable, Codable, Sendable {
    case allow
    case deny(reason: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case reason
    }

    private enum DirectiveType: String, Codable {
        case allow
        case deny
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DirectiveType.self, forKey: .type)

        switch type {
        case .allow:
            self = .allow
        case .deny:
            self = .deny(reason: try container.decodeIfPresent(String.self, forKey: .reason))
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
        }
    }
}

public extension PiHookPayload {
    var workspaceName: String {
        WorkspaceNameResolver.workspaceName(for: cwd)
    }

    var sessionTitle: String {
        "Pi · \(workspaceName)"
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: terminalApp ?? "Terminal",
            workspaceName: workspaceName,
            paneTitle: terminalTitle ?? "Pi \(sessionID.prefix(8))",
            workingDirectory: cwd,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY
        )
    }

    var implicitStartSummary: String {
        "Started Pi session in \(workspaceName)."
    }

    var promptPreview: String? {
        clipped(prompt)
    }

    var assistantMessagePreview: String? {
        clipped(lastAssistantMessage)
    }

    var toolInputPreview: String? {
        clipped(toolInput, limit: 160)
    }

    var toolActivitySummary: String {
        let base = toolName.map { "Running \($0)" } ?? "Running Pi tool"
        return toolInputPreview.map { "\(base): \($0)" } ?? base
    }

    private func clipped(_ value: String?, limit: Int = 240) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.count <= limit {
            return trimmed
        }

        return "\(trimmed.prefix(limit))…"
    }
}
