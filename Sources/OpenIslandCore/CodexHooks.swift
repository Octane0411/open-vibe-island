import Foundation

public enum CodexHookEventName: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case userPromptSubmit = "UserPromptSubmit"
    case stop = "Stop"
}

public enum CodexPermissionMode: String, Codable, Sendable {
    case `default`
    case acceptEdits
    case plan
    case dontAsk
    case bypassPermissions
}



public struct CodexHookToolInput: Equatable, Codable, Sendable {
    public var command: String

    public init(command: String) {
        self.command = command
    }
}

public enum CodexHookJSONValue: Equatable, Codable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: CodexHookJSONValue])
    case array([CodexHookJSONValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: CodexHookJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([CodexHookJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct CodexHookPayload: Equatable, Codable, Sendable {
    public var cwd: String
    public var hookEventName: CodexHookEventName
    public var model: String
    public var permissionMode: CodexPermissionMode
    public var sessionID: String
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var terminalTitle: String?
    /// Warp-specific per-pane identifier discovered via Warp's SQLite state
    /// at hook runtime. Not sent over the wire by the hook script — populated
    /// in `withRuntimeContext` and serialized through the bridge.
    public var warpPaneUUID: String?
    public var transcriptPath: String?
    public var source: String?
    public var turnID: String?
    public var toolName: String?
    public var toolUseID: String?
    public var toolInput: CodexHookToolInput?
    public var toolResponse: CodexHookJSONValue?
    public var prompt: String?
    public var stopHookActive: Bool?
    public var lastAssistantMessage: String?

    private enum CodingKeys: String, CodingKey {
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case permissionMode = "permission_mode"
        case sessionID = "session_id"
        case terminalApp = "terminal_app"
        case terminalSessionID = "terminal_session_id"
        case terminalTTY = "terminal_tty"
        case terminalTitle = "terminal_title"
        case warpPaneUUID = "warp_pane_uuid"
        case transcriptPath = "transcript_path"
        case source
        case turnID = "turn_id"
        case toolName = "tool_name"
        case toolUseID = "tool_use_id"
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
        case prompt
        case stopHookActive = "stop_hook_active"
        case lastAssistantMessage = "last_assistant_message"
    }

    public init(
        cwd: String,
        hookEventName: CodexHookEventName,
        model: String,
        permissionMode: CodexPermissionMode,
        sessionID: String,
        terminalApp: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        terminalTitle: String? = nil,
        warpPaneUUID: String? = nil,
        transcriptPath: String?,
        source: String? = nil,
        turnID: String? = nil,
        toolName: String? = nil,
        toolUseID: String? = nil,
        toolInput: CodexHookToolInput? = nil,
        toolResponse: CodexHookJSONValue? = nil,
        prompt: String? = nil,
        stopHookActive: Bool? = nil,
        lastAssistantMessage: String? = nil
    ) {
        self.cwd = cwd
        self.hookEventName = hookEventName
        self.model = model
        self.permissionMode = permissionMode
        self.sessionID = sessionID
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.terminalTitle = terminalTitle
        self.warpPaneUUID = warpPaneUUID
        self.transcriptPath = transcriptPath
        self.source = source
        self.turnID = turnID
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.toolInput = toolInput
        self.toolResponse = toolResponse
        self.prompt = prompt
        self.stopHookActive = stopHookActive
        self.lastAssistantMessage = lastAssistantMessage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cwd = try container.decode(String.self, forKey: .cwd)
        hookEventName = try container.decode(CodexHookEventName.self, forKey: .hookEventName)
        model = try container.decode(String.self, forKey: .model)
        permissionMode = try container.decodeIfPresent(CodexPermissionMode.self, forKey: .permissionMode) ?? .default
        sessionID = try container.decode(String.self, forKey: .sessionID)
        terminalApp = try container.decodeIfPresent(String.self, forKey: .terminalApp)
        terminalSessionID = try container.decodeIfPresent(String.self, forKey: .terminalSessionID)
        terminalTTY = try container.decodeIfPresent(String.self, forKey: .terminalTTY)
        terminalTitle = try container.decodeIfPresent(String.self, forKey: .terminalTitle)
        warpPaneUUID = try container.decodeIfPresent(String.self, forKey: .warpPaneUUID)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolUseID = try container.decodeIfPresent(String.self, forKey: .toolUseID)
        toolInput = try container.decodeIfPresent(CodexHookToolInput.self, forKey: .toolInput)
        toolResponse = try container.decodeIfPresent(CodexHookJSONValue.self, forKey: .toolResponse)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        stopHookActive = try container.decodeIfPresent(Bool.self, forKey: .stopHookActive)
        lastAssistantMessage = try container.decodeIfPresent(String.self, forKey: .lastAssistantMessage)
    }
}

public enum CodexHookDirective: Equatable, Codable, Sendable {
    case deny(reason: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case reason
    }

    private enum DirectiveType: String, Codable {
        case deny
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DirectiveType.self, forKey: .type)

        switch type {
        case .deny:
            self = .deny(reason: try container.decode(String.self, forKey: .reason))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .deny(reason):
            try container.encode(DirectiveType.deny, forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }
}

public enum CodexHookOutputEncoder {
    private struct LegacyBlockOutput: Codable {
        var decision = "block"
        var reason: String
    }

    public static func standardOutput(for response: BridgeResponse) throws -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        switch response {
        case .acknowledged:
            return nil
        case let .codexHookDirective(directive):
            let data: Data

            switch directive {
            case let .deny(reason):
                data = try encoder.encode(LegacyBlockOutput(reason: reason))
            }

            var line = data
            line.append(UInt8(ascii: "\n"))
            return line
        case .claudeHookDirective:
            return nil
        case .openCodeHookDirective:
            return nil
        case .cursorHookDirective:
            return nil
        case .submitPromptResult:
            return nil
        }
    }
}

public extension CodexHookPayload {
    var workspaceName: String {
        WorkspaceNameResolver.workspaceName(for: cwd)
    }

    var worktreeBranch: String? {
        WorkspaceNameResolver.worktreeBranch(for: cwd)
    }

    var sessionTitle: String {
        "Codex · \(workspaceName)"
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: terminalApp ?? "Unknown",
            workspaceName: workspaceName,
            paneTitle: terminalTitle ?? "Codex \(sessionID.prefix(8))",
            workingDirectory: cwd,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY,
            warpPaneUUID: warpPaneUUID
        )
    }

    var defaultCodexMetadata: CodexSessionMetadata {
        CodexSessionMetadata(
            transcriptPath: transcriptPath,
            initialUserPrompt: prompt ?? promptPreview,
            lastUserPrompt: prompt ?? promptPreview,
            lastAssistantMessage: lastAssistantMessage,
            currentTool: toolName,
            currentCommandPreview: commandPreview
        )
    }

    var implicitStartSummary: String {
        switch hookEventName {
        case .sessionStart:
            if source == "resume" {
                return "Resumed Codex session in \(workspaceName)."
            }

            return "Started Codex session in \(workspaceName)."
        case .preToolUse:
            return "Codex is preparing a Bash command in \(workspaceName)."
        case .postToolUse:
            return "Codex reported a Bash result in \(workspaceName)."
        case .userPromptSubmit:
            return "Codex received a new prompt in \(workspaceName)."
        case .stop:
            return "Codex completed a turn in \(workspaceName)."
        }
    }

    var commandText: String? {
        toolInput?.command
    }

    var commandPreview: String? {
        clipped(commandText)
    }

    var promptPreview: String? {
        clipped(prompt)
    }

    var assistantMessagePreview: String? {
        clipped(lastAssistantMessage)
    }

    var toolResponsePreview: String? {
        guard let toolResponse else {
            return nil
        }

        return clipped(stringValue(for: toolResponse))
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

        guard collapsed.count > limit else {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
        return "\(collapsed[..<endIndex])…"
    }

    private func stringValue(for value: CodexHookJSONValue) -> String {
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
            let rendered = items.map(stringValue(for:)).joined(separator: ", ")
            return "[\(rendered)]"
        case let .object(object):
            let rendered = object
                .keys
                .sorted()
                .map { key in
                    let value = object[key].map(stringValue(for:)) ?? "null"
                    return "\(key): \(value)"
                }
                .joined(separator: ", ")
            return "{\(rendered)}"
        }
    }
}

public extension CodexHookPayload {
    func withRuntimeContext(environment: [String: String]) -> CodexHookPayload {
        withRuntimeContext(
            environment: environment,
            currentTTYProvider: { currentTTY() },
            terminalLocatorProvider: { terminalLocator(for: $0) },
            warpPaneResolver: Self.defaultWarpPaneResolver
        )
    }

    /// Default production resolver — PID-based lookup first, cwd-based
    /// as the fallback. Mirrors ClaudeHookPayload.defaultWarpPaneResolver;
    /// see that file for the rationale.
    static let defaultWarpPaneResolver: @Sendable (String) -> String? = { cwd in
        let reader = WarpSQLiteReader()
        if let context = WarpProcessResolver.resolveCurrentPaneContext(),
           let uuid = reader.lookupPaneUUIDByShellPID(
               context.shellPID,
               terminalServerPID: context.terminalServerPID
           ) {
            return uuid
        }
        return reader.lookupPaneUUID(forCwd: cwd)
    }

    func withRuntimeContext(
        environment: [String: String],
        currentTTYProvider: () -> String?,
        terminalLocatorProvider: (String) -> (sessionID: String?, tty: String?, title: String?),
        warpPaneResolver: (String) -> String? = Self.defaultWarpPaneResolver
    ) -> CodexHookPayload {
        var payload = self

        if payload.terminalApp == nil {
            payload.terminalApp = inferTerminalApp(from: environment)
        }

        if payload.terminalApp == "Warp", payload.warpPaneUUID == nil {
            payload.warpPaneUUID = warpPaneResolver(payload.cwd)
        }

        // For cmux, use CMUX_SURFACE_ID as the terminal session identifier.
        if payload.terminalApp == "cmux" {
            if payload.terminalSessionID == nil {
                payload.terminalSessionID = environment["CMUX_SURFACE_ID"]
            }
        }

        // For Zellij, encode pane ID and session name so the jump service
        // can focus the correct pane via the Zellij CLI.
        if isZellijTerminalApp(payload.terminalApp) {
            if payload.terminalSessionID == nil {
                let paneID = environment["ZELLIJ_PANE_ID"] ?? ""
                let sessionName = environment["ZELLIJ_SESSION_NAME"] ?? ""
                if !paneID.isEmpty {
                    payload.terminalSessionID = "\(paneID):\(sessionName)"
                }
            }
        }

        if payload.terminalTTY == nil {
            payload.terminalTTY = currentTTYProvider()
        }

        let useLocator: Bool
        if isCmuxTerminalApp(payload.terminalApp) || isZellijTerminalApp(payload.terminalApp) {
            // cmux/Zellij session IDs come from environment variables;
            // no AppleScript locator is available, so skip entirely.
            useLocator = false
        } else if let terminalApp = payload.terminalApp, isGhosttyTerminalApp(terminalApp) {
            if payload.hookEventName == .sessionStart || payload.hookEventName == .userPromptSubmit {
                useLocator = true
            } else {
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

    private func shouldUseFocusedTerminalLocator(for terminalApp: String) -> Bool {
        let lower = terminalApp.lowercased()
        if lower.contains("ghostty") || lower.contains("jetbrains") {
            return false
        }
        return !Self.noLocatorTerminalApps.contains(lower)
    }

    private func isGhosttyTerminalApp(_ terminalApp: String?) -> Bool {
        guard let app = terminalApp?.lowercased() else { return false }
        return app.contains("ghostty")
    }

    private func isCmuxTerminalApp(_ terminalApp: String?) -> Bool {
        terminalApp?.lowercased() == "cmux"
    }

    private func isZellijTerminalApp(_ terminalApp: String?) -> Bool {
        terminalApp?.lowercased() == "zellij"
    }

    private func inferTerminalApp(from environment: [String: String]) -> String? {
        // Multiplexers run inside a host terminal but expose their own pane
        // context. Detect them first so the captured jumpTarget points at
        // the multiplexer pane instead of the outer terminal.
        if environment["CMUX_WORKSPACE_ID"] != nil || environment["CMUX_SOCKET_PATH"] != nil {
            return "cmux"
        }
        if environment["ZELLIJ"] != nil {
            return "Zellij"
        }

        // TERM_PROGRAM is the only authoritative terminal signal. Each
        // terminal sets it explicitly when it execs the user's shell, so
        // unlike per-app env vars (GHOSTTY_RESOURCES_DIR,
        // WARP_IS_LOCAL_SHELL_SESSION, ITERM_SESSION_ID, ...) it cannot
        // leak across apps via macOS GUI app environment inheritance. See
        // ClaudeHooks.swift:inferTerminalApp for the full leak rationale.
        if let termProgram = environment["TERM_PROGRAM"]?.lowercased(), !termProgram.isEmpty {
            switch termProgram {
            case "apple_terminal":
                return "Terminal"
            case "iterm.app", "iterm2":
                return "iTerm"
            case let value where value.contains("warp"):
                return "Warp"
            case let value where value.contains("ghostty"):
                return "Ghostty"
            case let value where value.contains("wezterm"):
                return "WezTerm"
            case "kaku":
                return "Kaku"
            case "vscode":
                return "VS Code"
            case "vscode-insiders":
                return "VS Code Insiders"
            case "windsurf":
                return "Windsurf"
            case "trae":
                return "Trae"
            default:
                break
            }
        }

        // Fallback for terminals that don't set TERM_PROGRAM. Vulnerable to
        // GUI inheritance leaks; only consulted when TERM_PROGRAM is empty.
        // Check Warp before Ghostty so a leaked GHOSTTY_RESOURCES_DIR cannot
        // win over a real WARP_IS_LOCAL_SHELL_SESSION on the same shell.
        if environment["ITERM_SESSION_ID"] != nil || environment["LC_TERMINAL"] == "iTerm2" {
            return "iTerm"
        }
        if environment["WARP_IS_LOCAL_SHELL_SESSION"] != nil {
            return "Warp"
        }
        if environment["GHOSTTY_RESOURCES_DIR"] != nil {
            return "Ghostty"
        }

        // JetBrains IDEs set TERMINAL_EMULATOR=JetBrains-JediTerm.
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
            return (
                sessionID: values[safe: 0],
                tty: values[safe: 1],
                title: values[safe: 2]
            )
        }

        if normalized == "cmux" {
            // cmux uses its own socket API; AppleScript locator is not available.
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
            return (
                sessionID: values[safe: 0],
                tty: nil,
                title: values[safe: 2]
            )
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
            return (
                sessionID: nil,
                tty: values[safe: 0],
                title: values[safe: 1]
            )
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
