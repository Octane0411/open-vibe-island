import Foundation

public enum KiroHookEventName: String, Codable, Sendable {
    case agentSpawn
    case agentStop
    case userPromptSubmit
    case preToolUse
    case postToolUse
    case postToolUseFailure
    case stop
}

public struct KiroHookPayload: Equatable, Codable, Sendable {
    public var hookEventName: KiroHookEventName
    public var cwd: String?
    public var prompt: String?
    public var assistantResponse: String?
    public var toolName: String?
    public var toolInput: KiroHookJSONValue?

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case cwd
        case prompt
        case assistantResponse = "assistant_response"
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }

    public init(
        hookEventName: KiroHookEventName,
        cwd: String? = nil,
        prompt: String? = nil,
        assistantResponse: String? = nil,
        toolName: String? = nil,
        toolInput: KiroHookJSONValue? = nil
    ) {
        self.hookEventName = hookEventName
        self.cwd = cwd
        self.prompt = prompt
        self.assistantResponse = assistantResponse
        self.toolName = toolName
        self.toolInput = toolInput
    }
}

/// Minimal JSON value type for Kiro tool_input.
public enum KiroHookJSONValue: Equatable, Codable, Sendable {
    case string(String)
    case object([String: String])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
            return
        }
        if let obj = try? container.decode([String: String].self) {
            self = .object(obj)
            return
        }
        self = .string("")
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(s): try container.encode(s)
        case let .object(o): try container.encode(o)
        }
    }
}

public struct KiroSessionMetadata: Equatable, Codable, Sendable {
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var currentTool: String?
    public var currentToolInputPreview: String?

    public init(
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        currentTool: String? = nil,
        currentToolInputPreview: String? = nil
    ) {
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.currentTool = currentTool
        self.currentToolInputPreview = currentToolInputPreview
    }

    public var isEmpty: Bool {
        initialUserPrompt == nil
            && lastUserPrompt == nil
            && lastAssistantMessage == nil
            && currentTool == nil
            && currentToolInputPreview == nil
    }
}

// MARK: - Payload Convenience Extensions

public extension KiroHookPayload {
    var workspaceName: String {
        WorkspaceNameResolver.workspaceName(for: cwd ?? "")
    }

    var sessionTitle: String {
        "Kiro CLI · \(workspaceName)"
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: "Unknown",
            workspaceName: workspaceName,
            paneTitle: "Kiro CLI",
            workingDirectory: cwd ?? ""
        )
    }

    var defaultKiroMetadata: KiroSessionMetadata {
        KiroSessionMetadata(
            initialUserPrompt: promptPreview,
            lastUserPrompt: promptPreview,
            lastAssistantMessage: assistantResponsePreview,
            currentTool: toolName,
            currentToolInputPreview: toolInputPreview
        )
    }

    var implicitStartSummary: String {
        switch hookEventName {
        case .agentSpawn:
            "Started Kiro CLI session in \(workspaceName)."
        case .agentStop:
            "Kiro CLI session ended in \(workspaceName)."
        case .userPromptSubmit:
            "Kiro CLI received a new prompt in \(workspaceName)."
        case .preToolUse:
            "Kiro CLI is preparing \(toolName ?? "a tool") in \(workspaceName)."
        case .postToolUse:
            "Kiro CLI finished \(toolName ?? "a tool") in \(workspaceName)."
        case .postToolUseFailure:
            "Kiro CLI tool failed in \(workspaceName)."
        case .stop:
            "Kiro CLI completed a turn in \(workspaceName)."
        }
    }

    var promptPreview: String? {
        clipped(prompt)
    }

    var assistantResponsePreview: String? {
        clipped(assistantResponse)
    }

    var toolInputPreview: String? {
        switch toolInput {
        case let .string(s): return clipped(s)
        case let .object(o): return clipped(o["command"] ?? o.values.first)
        case nil: return nil
        }
    }

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
