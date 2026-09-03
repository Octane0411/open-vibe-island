import Foundation

public enum PiAgentVariant: String, Codable, Sendable, CaseIterable {
    case pi
    case ohMyPi = "oh-my-pi"

    public var tool: AgentTool {
        switch self {
        case .pi: .pi
        case .ohMyPi: .ohMyPi
        }
    }
}

public enum PiHookEventName: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case stop = "Stop"
    case heartbeat = "Heartbeat"
}

public struct PiHookPayload: Equatable, Codable, Sendable {
    public var hookEventName: PiHookEventName
    public var agent: PiAgentVariant
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
        case agent
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
        hookEventName: PiHookEventName,
        agent: PiAgentVariant,
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
        self.agent = agent
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

public struct PiSessionMetadata: Equatable, Codable, Sendable {
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var currentTool: String?
    public var currentToolInputPreview: String?
    public var model: String?
    public var transcriptPath: String?

    public init(
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        currentTool: String? = nil,
        currentToolInputPreview: String? = nil,
        model: String? = nil,
        transcriptPath: String? = nil
    ) {
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.currentTool = currentTool
        self.currentToolInputPreview = currentToolInputPreview
        self.model = model
        self.transcriptPath = transcriptPath
    }

    public var isEmpty: Bool {
        initialUserPrompt == nil
            && lastUserPrompt == nil
            && lastAssistantMessage == nil
            && currentTool == nil
            && currentToolInputPreview == nil
            && model == nil
            && transcriptPath == nil
    }

    /// Field-level merge shared by the live bridge path and registry restore.
    ///
    /// `initialUserPrompt` is anchored on first sight and never overwritten;
    /// every other field prefers the incoming value and falls back to what
    /// was already known. `clearsCurrentTool` drops the active tool and its
    /// input preview instead of carrying them forward (PostToolUse / Stop /
    /// SessionEnd).
    public static func merged(
        existing: PiSessionMetadata?,
        update: PiSessionMetadata,
        clearsCurrentTool: Bool = false
    ) -> PiSessionMetadata {
        PiSessionMetadata(
            initialUserPrompt: existing?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existing?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing?.lastAssistantMessage,
            currentTool: clearsCurrentTool ? nil : (update.currentTool ?? existing?.currentTool),
            currentToolInputPreview: clearsCurrentTool
                ? nil
                : (update.currentToolInputPreview ?? existing?.currentToolInputPreview),
            model: update.model ?? existing?.model,
            transcriptPath: update.transcriptPath ?? existing?.transcriptPath
        )
    }
}

public extension PiHookPayload {
    var workspaceName: String {
        WorkspaceNameResolver.workspaceName(for: cwd)
    }

    var sessionTitle: String {
        "\(agent.tool.displayName) · \(workspaceName)"
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: terminalApp ?? "Unknown",
            workspaceName: workspaceName,
            paneTitle: terminalTitle ?? "\(agent.tool.displayName) \(sessionID.prefix(8))",
            workingDirectory: cwd,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY
        )
    }

    var defaultPiMetadata: PiSessionMetadata {
        PiSessionMetadata(
            initialUserPrompt: promptPreview,
            lastUserPrompt: promptPreview,
            lastAssistantMessage: assistantMessagePreview,
            currentTool: toolName,
            currentToolInputPreview: toolInputPreview,
            model: model,
            transcriptPath: transcriptPath
        )
    }

    var implicitStartSummary: String {
        let name = agent.tool.displayName
        return switch hookEventName {
        case .sessionStart: "Started \(name) session in \(workspaceName)."
        case .sessionEnd: "\(name) session ended in \(workspaceName)."
        case .userPromptSubmit: "\(name) received a new prompt in \(workspaceName)."
        case .preToolUse: "\(name) is preparing \(toolName ?? "a tool") in \(workspaceName)."
        case .postToolUse: "\(name) finished \(toolName ?? "a tool") in \(workspaceName)."
        case .stop: "\(name) completed a turn in \(workspaceName)."
        case .heartbeat: "\(name) session is ready in \(workspaceName)."
        }
    }

    var promptPreview: String? { clipped(prompt) }
    var assistantMessagePreview: String? { clipped(lastAssistantMessage) }
    var toolInputPreview: String? { clipped(toolInput) }

    private func clipped(_ value: String?, limit: Int = 110) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > limit else { return collapsed }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
        return "\(collapsed[..<endIndex])…"
    }
}
