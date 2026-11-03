import Foundation

public struct DSHHookPayload: Equatable, Codable, Sendable, RuntimeHookPayload {
    public var hookEventName: RuntimeHookEventName
    public var tool: AgentTool { .dsh }
    public var sessionID: String
    public var cwd: String
    public var toolName: String?
    public var toolInput: String?
    public var prompt: String?
    public var lastAssistantMessage: String?
    public var model: String?
    public var transcriptPath: String?
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var terminalTitle: String?

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case prompt
        case lastAssistantMessage = "last_assistant_message"
        case model
        case transcriptPath = "transcript_path"
        case terminalApp = "terminal_app"
        case terminalSessionID = "terminal_session_id"
        case terminalTTY = "terminal_tty"
        case terminalTitle = "terminal_title"
    }

    public init(
        hookEventName: RuntimeHookEventName,
        sessionID: String,
        cwd: String,
        toolName: String? = nil,
        toolInput: String? = nil,
        prompt: String? = nil,
        lastAssistantMessage: String? = nil,
        model: String? = nil,
        transcriptPath: String? = nil,
        terminalApp: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        terminalTitle: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionID = sessionID
        self.cwd = cwd
        self.toolName = toolName
        self.toolInput = toolInput
        self.prompt = prompt
        self.lastAssistantMessage = lastAssistantMessage
        self.model = model
        self.transcriptPath = transcriptPath
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.terminalTitle = terminalTitle
    }
}
