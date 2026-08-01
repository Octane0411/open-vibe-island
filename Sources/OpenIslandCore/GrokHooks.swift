import Foundation

/// Grok Build / Grok CLI hook event names.
///
/// Grok registers hooks with PascalCase names (`SessionStart`) but may emit
/// either PascalCase or snake_case values in the stdin envelope
/// (`session_start`). Decoding normalizes both forms.
public enum GrokHookEventName: String, Codable, Sendable, CaseIterable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case notification = "Notification"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
    case permissionDenied = "PermissionDenied"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let exact = GrokHookEventName(rawValue: raw) {
            self = exact
            return
        }

        let normalized = raw
            .replacingOccurrences(of: "_", with: "")
            .lowercased()

        switch normalized {
        case "sessionstart": self = .sessionStart
        case "sessionend": self = .sessionEnd
        case "userpromptsubmit": self = .userPromptSubmit
        case "pretooluse": self = .preToolUse
        case "posttooluse": self = .postToolUse
        case "posttoolusefailure": self = .postToolUseFailure
        case "stop": self = .stop
        case "stopfailure": self = .stopFailure
        case "notification": self = .notification
        case "subagentstart": self = .subagentStart
        case "subagentstop", "subagentend": self = .subagentStop
        case "precompact": self = .preCompact
        case "postcompact": self = .postCompact
        case "permissiondenied": self = .permissionDenied
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown Grok hook event name: \(raw)"
            )
        }
    }
}

public struct GrokHookPayload: Equatable, Codable, Sendable {
    public var cwd: String
    public var hookEventName: GrokHookEventName
    public var sessionID: String
    public var workspaceRoot: String?
    public var permissionMode: String?
    public var timestamp: String?
    public var toolName: String?
    public var toolInput: CodexHookJSONValue?
    public var toolUseID: String?
    public var toolResult: CodexHookJSONValue?
    public var prompt: String?
    public var lastAssistantMessage: String?
    public var stopHookActive: Bool?
    public var reason: String?
    public var source: String?
    public var message: String?
    public var notificationType: String?
    public var error: String?
    public var errorDetails: String?
    public var agentType: String?
    public var agentID: String?
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var terminalTitle: String?

    private enum CodingKeys: String, CodingKey {
        case cwd
        case hookEventName
        case sessionID = "sessionId"
        case workspaceRoot
        case permissionMode
        case timestamp
        case toolName
        case toolInput
        case toolUseID = "toolUseId"
        case toolResult
        case prompt
        case lastAssistantMessage
        case stopHookActive
        case reason
        case source
        case message
        case notificationType
        case error
        case errorDetails
        case agentType
        case agentID = "agentId"
        case terminalApp
        case terminalSessionID
        case terminalTTY
        case terminalTitle
    }

    public init(
        cwd: String,
        hookEventName: GrokHookEventName,
        sessionID: String,
        workspaceRoot: String? = nil,
        permissionMode: String? = nil,
        timestamp: String? = nil,
        toolName: String? = nil,
        toolInput: CodexHookJSONValue? = nil,
        toolUseID: String? = nil,
        toolResult: CodexHookJSONValue? = nil,
        prompt: String? = nil,
        lastAssistantMessage: String? = nil,
        stopHookActive: Bool? = nil,
        reason: String? = nil,
        source: String? = nil,
        message: String? = nil,
        notificationType: String? = nil,
        error: String? = nil,
        errorDetails: String? = nil,
        agentType: String? = nil,
        agentID: String? = nil,
        terminalApp: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        terminalTitle: String? = nil
    ) {
        self.cwd = cwd
        self.hookEventName = hookEventName
        self.sessionID = sessionID
        self.workspaceRoot = workspaceRoot
        self.permissionMode = permissionMode
        self.timestamp = timestamp
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolUseID = toolUseID
        self.toolResult = toolResult
        self.prompt = prompt
        self.lastAssistantMessage = lastAssistantMessage
        self.stopHookActive = stopHookActive
        self.reason = reason
        self.source = source
        self.message = message
        self.notificationType = notificationType
        self.error = error
        self.errorDetails = errorDetails
        self.agentType = agentType
        self.agentID = agentID
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.terminalTitle = terminalTitle
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName = try container.decode(GrokHookEventName.self, forKey: .hookEventName)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
            ?? container.decodeIfPresent(String.self, forKey: .workspaceRoot)
            ?? ""
        workspaceRoot = try container.decodeIfPresent(String.self, forKey: .workspaceRoot)
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolInput = try container.decodeIfPresent(CodexHookJSONValue.self, forKey: .toolInput)
        toolUseID = try container.decodeIfPresent(String.self, forKey: .toolUseID)
        toolResult = try container.decodeIfPresent(CodexHookJSONValue.self, forKey: .toolResult)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        lastAssistantMessage = try container.decodeIfPresent(String.self, forKey: .lastAssistantMessage)
        stopHookActive = try container.decodeIfPresent(Bool.self, forKey: .stopHookActive)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        notificationType = try container.decodeIfPresent(String.self, forKey: .notificationType)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        errorDetails = try container.decodeIfPresent(String.self, forKey: .errorDetails)
        agentType = try container.decodeIfPresent(String.self, forKey: .agentType)
        agentID = try container.decodeIfPresent(String.self, forKey: .agentID)
        terminalApp = try container.decodeIfPresent(String.self, forKey: .terminalApp)
        terminalSessionID = try container.decodeIfPresent(String.self, forKey: .terminalSessionID)
        terminalTTY = try container.decodeIfPresent(String.self, forKey: .terminalTTY)
        terminalTitle = try container.decodeIfPresent(String.self, forKey: .terminalTitle)
    }
}

public extension GrokHookPayload {
    var workspaceName: String {
        WorkspaceNameResolver.workspaceName(for: cwd.isEmpty ? (workspaceRoot ?? "") : cwd)
    }

    var sessionTitle: String {
        "Grok · \(workspaceName)"
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: terminalApp ?? "Terminal",
            workspaceName: workspaceName,
            paneTitle: terminalTitle ?? "Grok \(sessionID.prefix(8))",
            workingDirectory: cwd.isEmpty ? workspaceRoot : cwd,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY
        )
    }

    var implicitSummary: String {
        switch hookEventName {
        case .sessionStart:
            switch source?.lowercased() {
            case "resume":
                return "Resumed Grok session in \(workspaceName)."
            default:
                return "Started Grok session in \(workspaceName)."
            }
        case .sessionEnd:
            return reason.map { "Grok session ended: \($0)." }
                ?? "Grok session ended in \(workspaceName)."
        case .userPromptSubmit:
            return promptPreview.map { "Prompt: \($0)" }
                ?? "Grok received a new prompt in \(workspaceName)."
        case .preToolUse:
            return "Grok is preparing \(toolName ?? "a tool") in \(workspaceName)."
        case .postToolUse:
            return "Grok finished \(toolName ?? "a tool") in \(workspaceName)."
        case .postToolUseFailure:
            return error.map { "Grok tool failed: \($0)" }
                ?? "Grok hit a tool error in \(workspaceName)."
        case .stop:
            return lastAssistantMessagePreview
                ?? "Grok completed a turn in \(workspaceName)."
        case .stopFailure:
            return error.map { "Grok turn failed: \($0)" }
                ?? "Grok failed to finish a turn in \(workspaceName)."
        case .notification:
            return notificationSummary
        case .subagentStart:
            return agentType.map { "Started \($0) subagent." }
                ?? "Started Grok subagent in \(workspaceName)."
        case .subagentStop:
            return "Finished Grok subagent in \(workspaceName)."
        case .preCompact:
            return "Grok is compacting the conversation in \(workspaceName)."
        case .postCompact:
            return "Grok finished compacting the conversation in \(workspaceName)."
        case .permissionDenied:
            return "Grok permission was denied in \(workspaceName)."
        }
    }

    var promptPreview: String? {
        clipped(prompt)
    }

    var lastAssistantMessagePreview: String? {
        clipped(lastAssistantMessage)
    }

    var notificationSummary: String {
        clipped(message) ?? "Grok sent a notification."
    }

    var toolInputPreview: String? {
        if case let .object(obj) = toolInput {
            let keyPriority = ["command", "file_path", "target_file", "pattern", "query", "prompt", "description", "url"]
            for key in keyPriority {
                if case let .string(val)? = obj[key], !val.isEmpty {
                    return clipped(val)
                }
            }
        }
        return clipped(stringValue(for: toolInput))
    }

    /// True when this Stop is a genuine turn completion rather than the
    /// observe-only fire that Grok emits at session end.
    ///
    /// Decision (tested):
    /// - `reason == "end_turn"` → genuine turn completion.
    /// - `reason` present and not `"end_turn"` (e.g. `shutdown`, `channel_closed`)
    ///   → observe-only; do not emit sessionCompleted for the turn.
    /// - `reason` omitted → treat as genuine turn completion for older Grok
    ///   builds that do not populate the field (fail-open toward visibility).
    var isGenuineTurnStop: Bool {
        guard hookEventName == .stop else { return false }
        if let reason {
            return reason == "end_turn"
        }
        return true
    }

    func withRuntimeContext(environment: [String: String]) -> GrokHookPayload {
        withRuntimeContext(
            environment: environment,
            currentTTYProvider: { currentTTY() },
            terminalLocatorProvider: { terminalLocator(for: $0) }
        )
    }

    func withRuntimeContext(
        environment: [String: String],
        currentTTYProvider: () -> String?,
        terminalLocatorProvider: (String) -> (sessionID: String?, tty: String?, title: String?)
    ) -> GrokHookPayload {
        var payload = self

        if payload.cwd.isEmpty, let workspaceRoot = payload.workspaceRoot {
            payload.cwd = workspaceRoot
        }

        if payload.terminalApp == nil {
            payload.terminalApp = inferTerminalApp(from: environment)
        }

        if payload.terminalApp == "cmux", payload.terminalSessionID == nil {
            payload.terminalSessionID = environment["CMUX_SURFACE_ID"]
        }

        if payload.terminalApp?.lowercased() == "zellij", payload.terminalSessionID == nil {
            let paneID = environment["ZELLIJ_PANE_ID"] ?? ""
            let sessionName = environment["ZELLIJ_SESSION_NAME"] ?? ""
            if !paneID.isEmpty {
                payload.terminalSessionID = "\(paneID):\(sessionName)"
            }
        }

        if payload.terminalTTY == nil {
            payload.terminalTTY = currentTTYProvider()
        }

        let useLocator: Bool
        if isCmuxTerminalApp(payload.terminalApp) || isZellijTerminalApp(payload.terminalApp) {
            useLocator = false
        } else if let terminalApp = payload.terminalApp, isGhosttyTerminalApp(terminalApp) {
            switch payload.hookEventName {
            case .sessionStart, .userPromptSubmit, .notification:
                useLocator = true
            default:
                payload.terminalSessionID = nil
                payload.terminalTitle = nil
                useLocator = false
            }
        } else {
            useLocator = shouldUseFocusedTerminalLocator(for: payload.terminalApp ?? "")
        }

        if useLocator, let terminalApp = payload.terminalApp {
            let locator = terminalLocatorProvider(terminalApp)
            if payload.terminalSessionID == nil {
                payload.terminalSessionID = locator.sessionID
            }
            if payload.terminalTTY == nil {
                payload.terminalTTY = locator.tty
            }
            if payload.terminalTitle == nil {
                payload.terminalTitle = locator.title
            }
        }

        return payload
    }

    private static let noLocatorTerminalApps: Set<String> = [
        "cmux", "kaku", "wezterm", "zellij",
        "vs code", "vs code insiders", "cursor", "windsurf", "trae",
        "intellij idea", "webstorm", "pycharm", "goland", "clion",
        "rubymine", "phpstorm", "rider", "rustrover",
    ]

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

    private func stringValue(for value: CodexHookJSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case let .string(text): return text
        case let .number(number): return String(number)
        case let .boolean(flag): return flag ? "true" : "false"
        case .null: return "null"
        case let .array(items):
            return "[\(items.compactMap { stringValue(for: $0) }.joined(separator: ", "))]"
        case let .object(object):
            let rendered = object.keys.sorted().map { key in
                "\(key): \(stringValue(for: object[key]) ?? "null")"
            }.joined(separator: ", ")
            return "{\(rendered)}"
        }
    }

    private func shouldUseFocusedTerminalLocator(for terminalApp: String) -> Bool {
        let lower = terminalApp.lowercased()
        if lower.contains("ghostty") || lower.contains("jetbrains") {
            return false
        }
        return !Self.noLocatorTerminalApps.contains(lower)
    }

    private func isGhosttyTerminalApp(_ terminalApp: String?) -> Bool {
        terminalApp?.lowercased().contains("ghostty") == true
    }

    private func isCmuxTerminalApp(_ terminalApp: String?) -> Bool {
        terminalApp?.lowercased() == "cmux"
    }

    private func isZellijTerminalApp(_ terminalApp: String?) -> Bool {
        terminalApp?.lowercased() == "zellij"
    }

    private func inferTerminalApp(from environment: [String: String]) -> String? {
        if environment["CMUX_WORKSPACE_ID"] != nil || environment["CMUX_SOCKET_PATH"] != nil {
            return "cmux"
        }
        if environment["ZELLIJ"] != nil {
            return "Zellij"
        }

        if let termProgram = environment["TERM_PROGRAM"]?.lowercased(), !termProgram.isEmpty {
            switch termProgram {
            case "apple_terminal": return "Terminal"
            case "iterm.app", "iterm2": return "iTerm"
            case let value where value.contains("warp"): return "Warp"
            case let value where value.contains("ghostty"): return "Ghostty"
            case "kaku": return "Kaku"
            case "wezterm": return "WezTerm"
            case "vscode":
                if environment["CURSOR_TRACE_ID"] != nil { return "Cursor" }
                return "VS Code"
            case "vscode-insiders": return "VS Code Insiders"
            case "windsurf": return "Windsurf"
            case "trae": return "Trae"
            default: break
            }
        }

        if environment["ITERM_SESSION_ID"] != nil || environment["LC_TERMINAL"] == "iTerm2" {
            return "iTerm"
        }
        if environment["WARP_IS_LOCAL_SHELL_SESSION"] != nil {
            return "Warp"
        }
        if environment["GHOSTTY_RESOURCES_DIR"] != nil {
            return "Ghostty"
        }

        if let terminalEmulator = environment["TERMINAL_EMULATOR"]?.lowercased(),
           terminalEmulator.contains("jetbrains") {
            if let bundleID = environment["__CFBundleIdentifier"]?.lowercased() {
                if bundleID.contains("webstorm") { return "WebStorm" }
                if bundleID.contains("pycharm") { return "PyCharm" }
                if bundleID.contains("goland") { return "GoLand" }
                if bundleID.contains("clion") { return "CLion" }
                if bundleID.contains("rubymine") { return "RubyMine" }
                if bundleID.contains("phpstorm") { return "PhpStorm" }
                if bundleID.contains("rider") { return "Rider" }
                if bundleID.contains("rustrover") { return "RustRover" }
                if bundleID.contains("intellij") { return "IntelliJ IDEA" }
            }
            return "IntelliJ IDEA"
        }

        return nil
    }

    private func currentTTY() -> String? {
        if let tty = commandOutput(executablePath: "/usr/bin/tty", arguments: []),
           !tty.contains("not a tty") {
            return tty
        }
        return parentProcessTTY()
    }

    private func parentProcessTTY() -> String? {
        let ppid = getppid()
        guard let raw = commandOutput(executablePath: "/bin/ps", arguments: ["-p", "\(ppid)", "-o", "tty="]) else {
            return nil
        }

        let tty = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tty.isEmpty, tty != "??", tty != "-" else {
            return nil
        }

        return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    private func terminalLocator(for terminalApp: String) -> (sessionID: String?, tty: String?, title: String?) {
        let normalized = terminalApp.lowercased()

        if normalized.contains("iterm") {
            let values = osascriptValues(script: """
            tell application "iTerm"
                if not (it is running) then return ""
                tell current session of current window
                    return (id as text) & (ASCII character 31) & (tty as text) & (ASCII character 31) & (name as text)
                end tell
            end tell
            """)
            return (sessionID: values[safe: 0], tty: values[safe: 1], title: values[safe: 2])
        }

        if normalized == "cmux" {
            return (sessionID: nil, tty: nil, title: nil)
        }

        if normalized.contains("ghostty") {
            let values = osascriptValues(script: """
            tell application "Ghostty"
                if not (it is running) then return ""
                tell focused terminal of selected tab of front window
                    return (id as text) & (ASCII character 31) & (working directory as text) & (ASCII character 31) & (name as text)
                end tell
            end tell
            """)
            return (sessionID: values[safe: 0], tty: nil, title: values[safe: 2])
        }

        if normalized.contains("terminal") {
            let values = osascriptValues(script: """
            tell application "Terminal"
                if not (it is running) then return ""
                tell selected tab of front window
                    return (tty as text) & (ASCII character 31) & (custom title as text)
                end tell
            end tell
            """)
            return (sessionID: nil, tty: values[safe: 0], title: values[safe: 1])
        }

        return (nil, nil, nil)
    }

    private func osascriptValues(script: String) -> [String] {
        guard let raw = commandOutput(executablePath: "/usr/bin/osascript", arguments: ["-e", script]) else {
            return []
        }

        let separator = String(UnicodeScalar(31)!)
        return raw
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func commandOutput(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        return output
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
