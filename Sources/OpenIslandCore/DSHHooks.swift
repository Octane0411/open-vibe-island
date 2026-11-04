import Foundation

public struct DSHInteractionResult: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case plan, question }
    public enum Outcome: String, Codable, Sendable { case approved, declined, answered, cancelled, failed }
    public var kind: Kind
    public var outcome: Outcome
    public var callID: String?

    enum CodingKeys: String, CodingKey {
        case kind, outcome
        case callID = "call_id"
    }

    public init(kind: Kind, outcome: Outcome, callID: String? = nil) {
        self.kind = kind
        self.outcome = outcome
        self.callID = callID
    }
}

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
    public var webOrigin: String?
    public var webFocusSocket: String?
    public var interaction: DSHInteraction?
    public var turnID: Int?
    public var turnOutcome: String?
    public var interactionResult: DSHInteractionResult?
    public var isSubagent: Bool?
    public var parentSessionID: String?

    public var defaultJumpTarget: JumpTarget {
        let webTarget: DSHWebJumpTarget?
        if let webOrigin, let webFocusSocket {
            webTarget = DSHWebJumpTarget(sessionID: sessionID, origin: webOrigin, focusSocketPath: webFocusSocket)
        } else {
            webTarget = nil
        }
        return JumpTarget(
            terminalApp: "DSH Web",
            workspaceName: workspaceName,
            paneTitle: "DSH \(sessionID.prefix(8))",
            workingDirectory: cwd,
            dshWeb: webTarget
        )
    }

    public var postToolUseSummary: String? {
        guard let result = interactionResult else { return nil }
        switch (result.kind, result.outcome) {
        case (.plan, .approved): return "DSH plan approved."
        case (.plan, .declined): return "DSH plan needs more work."
        case (_, .answered): return "DSH question answered."
        case (_, .cancelled): return "DSH interaction cancelled."
        case (_, .failed): return "DSH interaction failed."
        default: return "DSH interaction resolved."
        }
    }

    public var completionSummary: String? {
        switch turnOutcome {
        case "error", "failed": return "DSH turn failed."
        case "aborted", "interrupted": return "DSH turn interrupted."
        case "blocked": return "DSH turn stopped because it was blocked."
        case "max-tokens": return "DSH turn reached its token limit."
        case "forked": return "DSH turn ended after forking."
        case "completed", nil: return postToolUseSummary ?? assistantMessagePreview
        default: return "DSH turn ended."
        }
    }

    public var isInterrupt: Bool? {
        ["aborted", "interrupted"].contains(turnOutcome ?? "") ? true : nil
    }

    public var defaultPiMetadata: PiSessionMetadata {
        let fullMessage = lastAssistantMessage.flatMap { value -> String? in
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return String(decoding: value.utf8.prefix(16 * 1024), as: UTF8.self)
        }
        return PiSessionMetadata(
            initialUserPrompt: promptPreview, lastUserPrompt: promptPreview,
            lastAssistantMessage: fullMessage ?? (hookEventName == .stop ? completionSummary : nil),
            currentTool: toolName, currentToolInputPreview: toolInputPreview,
            model: model, transcriptPath: transcriptPath,
            isSubagent: isSubagent, parentSessionID: parentSessionID
        )
    }

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
        case webOrigin = "web_origin"
        case webFocusSocket = "web_focus_socket"
        case interaction
        case turnID = "turn_id"
        case turnOutcome = "turn_outcome"
        case interactionResult = "interaction_result"
        case isSubagent = "is_subagent"
        case parentSessionID = "parent_session_id"
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
        terminalTitle: String? = nil,
        webOrigin: String? = nil,
        webFocusSocket: String? = nil,
        interaction: DSHInteraction? = nil,
        turnID: Int? = nil,
        turnOutcome: String? = nil,
        interactionResult: DSHInteractionResult? = nil,
        isSubagent: Bool? = false,
        parentSessionID: String? = nil
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
        self.webOrigin = webOrigin
        self.webFocusSocket = webFocusSocket
        self.interaction = interaction
        self.turnID = turnID
        self.turnOutcome = turnOutcome
        self.interactionResult = interactionResult
        self.isSubagent = isSubagent
        self.parentSessionID = parentSessionID
    }
}
