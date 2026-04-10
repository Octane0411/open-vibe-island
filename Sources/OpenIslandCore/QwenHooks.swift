import Foundation

public struct QwenHookPayload: Equatable, Codable, Sendable {
    public var cwd: String
    public var hookEventName: String
    public var sessionID: String
    public var transcriptPath: String?
    public var agentID: String?
    public var agentType: String?
    public var model: String?
    public var toolName: String?
    public var prompt: String?
    public var message: String?
    public var title: String?
    public var lastAssistantMessage: String?
    public var error: String?
    public var isInterrupt: Bool?
    public var remote: Bool?

    public var terminalApp: String?
    public var workspaceName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
    public var terminalTitle: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?

    private enum CodingKeys: String, CodingKey {
        case cwd
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case agentID = "agent_id"
        case agentType = "agent_type"
        case model
        case toolName = "tool_name"
        case prompt
        case message
        case title
        case lastAssistantMessage = "last_assistant_message"
        case error
        case isInterrupt = "is_interrupt"
        case remote
    }

    public init(
        cwd: String,
        hookEventName: String,
        sessionID: String,
        transcriptPath: String? = nil,
        agentID: String? = nil,
        agentType: String? = nil,
        model: String? = nil,
        toolName: String? = nil,
        prompt: String? = nil,
        message: String? = nil,
        title: String? = nil,
        lastAssistantMessage: String? = nil,
        error: String? = nil,
        isInterrupt: Bool? = nil,
        remote: Bool? = nil,
        terminalApp: String? = nil,
        terminalTitle: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil
    ) {
        self.cwd = cwd
        self.hookEventName = hookEventName
        self.sessionID = sessionID
        self.transcriptPath = transcriptPath
        self.agentID = agentID
        self.agentType = agentType
        self.model = model
        self.toolName = toolName
        self.prompt = prompt
        self.message = message
        self.title = title
        self.lastAssistantMessage = lastAssistantMessage
        self.error = error
        self.isInterrupt = isInterrupt
        self.remote = remote
        self.terminalApp = terminalApp
        self.terminalTitle = terminalTitle
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
    }

    public var sessionTitle: String {
        title ?? URL(fileURLWithPath: cwd).lastPathComponent
    }

    public var implicitStartSummary: String {
        "Started Qwen in \(URL(fileURLWithPath: cwd).lastPathComponent)."
    }

    public var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: terminalApp ?? "Unknown",
            workspaceName: workspaceName,
            paneTitle: terminalTitle ?? "Qwen \(sessionID.prefix(8))",
            workingDirectory: cwd,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY
        )
    }

    public var promptPreview: String? {
        clipped(prompt)
    }

    public var assistantMessagePreview: String? {
        clipped(lastAssistantMessage)
    }

    private func clipped(_ string: String?) -> String? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(200))
    }
}
