import Foundation

/// Normalized lifecycle event emitted by the bundled `open-island-dsh`
/// cordis plugin. The plugin maps DSH cordis events (`session/created`,
/// `session/disposed`, `agent/status`, `tools/pre-execute`, `agent/error`)
/// onto these four values before forwarding them over the bridge socket.
public enum DshHookEventName: String, Codable, Sendable {
    case sessionStart
    case sessionEnd
    case activity
    case turnCompleted
}

/// Fire-and-forget payload for the DeepSeek Harness plugin bridge.
/// Mirrors the Pi extension shape: the plugin connects to the bridge socket
/// directly, so no hook CLI is involved and no directive is ever returned.
public struct DshHookPayload: Equatable, Codable, Sendable {
    public var hookEventName: DshHookEventName
    public var sessionID: String
    public var cwd: String
    public var profile: String?
    public var summary: String?
    public var toolName: String?
    public var toolInputPreview: String?
    public var lastAssistantMessage: String?
    public var terminalApp: String?
    public var terminalTTY: String?

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case profile
        case summary
        case toolName = "tool_name"
        case toolInputPreview = "tool_input_preview"
        case lastAssistantMessage = "last_assistant_message"
        case terminalApp = "terminal_app"
        case terminalTTY = "terminal_tty"
    }

    public init(
        hookEventName: DshHookEventName,
        sessionID: String,
        cwd: String,
        profile: String? = nil,
        summary: String? = nil,
        toolName: String? = nil,
        toolInputPreview: String? = nil,
        lastAssistantMessage: String? = nil,
        terminalApp: String? = nil,
        terminalTTY: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionID = sessionID
        self.cwd = cwd
        self.profile = profile
        self.summary = summary
        self.toolName = toolName
        self.toolInputPreview = toolInputPreview
        self.lastAssistantMessage = lastAssistantMessage
        self.terminalApp = terminalApp
        self.terminalTTY = terminalTTY
    }
}

public extension DshHookPayload {
    var workspaceName: String {
        WorkspaceNameResolver.workspaceName(for: cwd)
    }

    var sessionTitle: String {
        "DeepSeek Harness · \(workspaceName)"
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: terminalApp ?? "DeepSeek Harness",
            workspaceName: workspaceName,
            paneTitle: profile.map { "dsh \($0)" } ?? "dsh",
            workingDirectory: cwd,
            terminalTTY: terminalTTY
        )
    }

    /// Summary used for activity updates when the plugin did not pre-render one.
    var activitySummary: String {
        let base = toolName.map { "Running \($0)" } ?? "Working"
        return toolInputPreview.map { "\(base): \($0)" } ?? base
    }

    /// Summary for completion cards: prefers the last assistant message,
    /// then any plugin-provided summary, then a generic fallback.
    var completionSummary: String {
        clipped(lastAssistantMessage) ?? clipped(summary) ?? "DeepSeek Harness completed the turn."
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
