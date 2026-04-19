import Foundation

public enum HermesHookEventName: String, Codable, Sendable {
    case sessionStart = "session_start"
    case preToolCall = "pre_tool_call"
    case postToolCall = "post_tool_call"
    case sessionEnd = "session_end"
}

public struct HermesHookPayload: Equatable, Codable, Sendable {
    public var hookEventName: HermesHookEventName
    public var sessionID: String
    public var cwd: String
    public var pid: Int?
    public var model: String?
    public var platform: String?
    public var toolName: String?
    public var toolArgs: CodexHookJSONValue?
    public var toolCallID: String?
    public var taskID: String?
    public var completed: Bool?
    public var interrupted: Bool?
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var terminalTitle: String?

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case pid
        case model
        case platform
        case toolName = "tool_name"
        case toolArgs = "tool_args"
        case toolCallID = "tool_call_id"
        case taskID = "task_id"
        case completed
        case interrupted
        case terminalApp = "terminal_app"
        case terminalSessionID = "terminal_session_id"
        case terminalTTY = "terminal_tty"
        case terminalTitle = "terminal_title"
    }

    public init(
        hookEventName: HermesHookEventName,
        sessionID: String,
        cwd: String,
        pid: Int? = nil,
        model: String? = nil,
        platform: String? = nil,
        toolName: String? = nil,
        toolArgs: CodexHookJSONValue? = nil,
        toolCallID: String? = nil,
        taskID: String? = nil,
        completed: Bool? = nil,
        interrupted: Bool? = nil,
        terminalApp: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        terminalTitle: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionID = sessionID
        self.cwd = cwd
        self.pid = pid
        self.model = model
        self.platform = platform
        self.toolName = toolName
        self.toolArgs = toolArgs
        self.toolCallID = toolCallID
        self.taskID = taskID
        self.completed = completed
        self.interrupted = interrupted
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.terminalTitle = terminalTitle
    }
}

public struct HermesSessionMetadata: Equatable, Codable, Sendable {
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var currentTool: String?
    public var currentToolInputPreview: String?
    public var model: String?
    public var cwd: String?

    public init(
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        currentTool: String? = nil,
        currentToolInputPreview: String? = nil,
        model: String? = nil,
        cwd: String? = nil
    ) {
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.currentTool = currentTool
        self.currentToolInputPreview = currentToolInputPreview
        self.model = model
        self.cwd = cwd
    }

    public var isEmpty: Bool {
        initialUserPrompt == nil
            && lastUserPrompt == nil
            && lastAssistantMessage == nil
            && currentTool == nil
            && currentToolInputPreview == nil
            && model == nil
            && cwd == nil
    }
}

public extension HermesHookPayload {
    var workspaceName: String {
        WorkspaceNameResolver.workspaceName(for: cwd)
    }

    var sessionTitle: String {
        "Hermes · \(workspaceName)"
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: terminalApp ?? "Terminal",
            workspaceName: workspaceName,
            paneTitle: terminalTitle ?? "Hermes \(sessionID.prefix(8))",
            workingDirectory: cwd,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY
        )
    }

    var defaultHermesMetadata: HermesSessionMetadata {
        HermesSessionMetadata(
            currentTool: toolName,
            currentToolInputPreview: toolArgsPreview,
            model: model,
            cwd: cwd
        )
    }

    var implicitSummary: String {
        switch hookEventName {
        case .sessionStart:
            return "Started Hermes session in \(workspaceName)."
        case .preToolCall:
            return "Hermes is preparing \(toolName ?? "a tool") in \(workspaceName)."
        case .postToolCall:
            return "Hermes finished \(toolName ?? "a tool") in \(workspaceName)."
        case .sessionEnd:
            if interrupted == true {
                return "Hermes session interrupted in \(workspaceName)."
            }
            return "Hermes session ended in \(workspaceName)."
        }
    }

    var toolArgsPreview: String? {
        guard let toolArgs else {
            return nil
        }

        return clipped(renderToolArgs(toolArgs), limit: 160)
    }

    func withRuntimeContext(environment: [String: String]) -> HermesHookPayload {
        var payload = self

        if payload.terminalApp == nil {
            payload.terminalApp = Self.inferTerminalApp(from: environment)
        }

        if payload.terminalTTY == nil {
            payload.terminalTTY = Self.currentTTY()
        }

        if payload.terminalSessionID == nil {
            if let sessionID = environment["ITERM_SESSION_ID"] {
                payload.terminalSessionID = sessionID
            } else if let sessionID = environment["TERM_SESSION_ID"] {
                payload.terminalSessionID = sessionID
            }
        }

        return payload
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

    private func renderToolArgs(_ value: CodexHookJSONValue) -> String {
        switch value {
        case let .string(text):
            return text
        case let .number(number):
            return String(number)
        case let .boolean(flag):
            return flag ? "true" : "false"
        case .null:
            return "null"
        case let .array(items):
            let rendered = items.map(renderToolArgs(_:)).joined(separator: ", ")
            return "[\(rendered)]"
        case let .object(object):
            let rendered = object
                .keys
                .sorted()
                .map { key in
                    let value = object[key].map(renderToolArgs(_:)) ?? "null"
                    return "\(key)=\(value)"
                }
                .joined(separator: " ")
            return rendered
        }
    }

    private static func inferTerminalApp(from environment: [String: String]) -> String? {
        if environment["ITERM_SESSION_ID"] != nil || environment["LC_TERMINAL"] == "iTerm2" {
            return "iTerm"
        }

        if environment["CMUX_WORKSPACE_ID"] != nil || environment["CMUX_SOCKET_PATH"] != nil {
            return "cmux"
        }

        if environment["ZELLIJ"] != nil {
            return "Zellij"
        }

        if environment["GHOSTTY_RESOURCES_DIR"] != nil {
            return "Ghostty"
        }

        if environment["WARP_IS_LOCAL_SHELL_SESSION"] != nil {
            return "Warp"
        }

        let termProgram = environment["TERM_PROGRAM"]?.lowercased()
        switch termProgram {
        case .some("apple_terminal"):
            return "Terminal"
        case .some("iterm.app"), .some("iterm2"):
            return "iTerm"
        case let value? where value.contains("ghostty"):
            return "Ghostty"
        case let value? where value.contains("warp"):
            return "Warp"
        case let value? where value.contains("wezterm"):
            return "WezTerm"
        case .some("kaku"):
            return "Kaku"
        case .some("vscode"):
            return "VS Code"
        case .some("vscode-insiders"):
            return "VS Code Insiders"
        case .some("windsurf"):
            return "Windsurf"
        case .some("trae"):
            return "Trae"
        default:
            break
        }

        return nil
    }

    private static func currentTTY() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tty")
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty,
              let output = String(data: data, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty,
              !output.contains("not a tty") else {
            return nil
        }

        return output
    }
}
