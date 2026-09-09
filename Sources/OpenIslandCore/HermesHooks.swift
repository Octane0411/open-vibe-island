import Foundation

/// Event names emitted on the wire by Hermes Agent shell hooks.
public enum HermesHookEventName: String, Codable, Sendable {
    case onSessionStart = "on_session_start"
    case onSessionEnd = "on_session_end"
    case postLLMCall = "post_llm_call"
    case subagentStop = "subagent_stop"
    case preToolCall = "pre_tool_call"
    case preApprovalRequest = "pre_approval_request"
    case preAPIRequest = "pre_api_request"
}

/// Payload Hermes pipes to a shell hook's stdin.
///
/// Hermes canonical shape (hermes_agent website/docs/user-guide/features/hooks.md):
/// `hook_event_name`, `session_id`, `cwd`, `tool_name`, `tool_input`, and
/// `extra` (all other event kwargs, unserializable values stringified).
/// `tool_name`/`tool_input` are null for the lifecycle events Open Island
/// consumes. Terminal fields are absent on the wire; the OpenIslandHooks CLI
/// fills them via `withRuntimeContext` before forwarding.
public struct HermesHookPayload: Equatable, Codable, Sendable {
    public var hookEventName: HermesHookEventName
    public var sessionID: String
    public var cwd: String
    public var toolName: String?
    public var toolInput: CodexHookJSONValue?
    public var extra: CodexHookJSONValue?
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var terminalTitle: String?
    public var tmuxTarget: String?
    public var tmuxSocketPath: String?

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case extra
        case terminalApp = "terminal_app"
        case terminalSessionID = "terminal_session_id"
        case terminalTTY = "terminal_tty"
        case terminalTitle = "terminal_title"
        case tmuxTarget = "tmux_target"
        case tmuxSocketPath = "tmux_socket_path"
    }

    public init(
        hookEventName: HermesHookEventName,
        sessionID: String,
        cwd: String,
        toolName: String? = nil,
        toolInput: CodexHookJSONValue? = nil,
        extra: CodexHookJSONValue? = nil,
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
        self.extra = extra
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.terminalTitle = terminalTitle
        self.tmuxTarget = nil
        self.tmuxSocketPath = nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName = try container.decode(HermesHookEventName.self, forKey: .hookEventName)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? "unknown"
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolInput = try? container.decodeIfPresent(CodexHookJSONValue.self, forKey: .toolInput)
        extra = try? container.decodeIfPresent(CodexHookJSONValue.self, forKey: .extra)
        terminalApp = try container.decodeIfPresent(String.self, forKey: .terminalApp)
        terminalSessionID = try container.decodeIfPresent(String.self, forKey: .terminalSessionID)
        terminalTTY = try container.decodeIfPresent(String.self, forKey: .terminalTTY)
        terminalTitle = try container.decodeIfPresent(String.self, forKey: .terminalTitle)
        tmuxTarget = try container.decodeIfPresent(String.self, forKey: .tmuxTarget)
        tmuxSocketPath = try container.decodeIfPresent(String.self, forKey: .tmuxSocketPath)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hookEventName, forKey: .hookEventName)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(cwd, forKey: .cwd)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encodeIfPresent(toolInput, forKey: .toolInput)
        try container.encodeIfPresent(extra, forKey: .extra)
        try container.encodeIfPresent(terminalApp, forKey: .terminalApp)
        try container.encodeIfPresent(terminalSessionID, forKey: .terminalSessionID)
        try container.encodeIfPresent(terminalTTY, forKey: .terminalTTY)
        try container.encodeIfPresent(terminalTitle, forKey: .terminalTitle)
        try container.encodeIfPresent(tmuxTarget, forKey: .tmuxTarget)
        try container.encodeIfPresent(tmuxSocketPath, forKey: .tmuxSocketPath)
    }

    public static func decode(_ data: Data) throws -> HermesHookPayload {
        try JSONDecoder().decode(HermesHookPayload.self, from: data)
    }
}

/// Session metadata carried for Hermes sessions (mirrors GeminiSessionMetadata).
public struct HermesSessionMetadata: Equatable, Codable, Sendable {
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var lastAssistantMessageBody: String?
    public var platform: String?
    public var model: String?

    public init(
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        lastAssistantMessageBody: String? = nil,
        platform: String? = nil,
        model: String? = nil
    ) {
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.lastAssistantMessageBody = lastAssistantMessageBody
        self.platform = platform
        self.model = model
    }

    public var isEmpty: Bool {
        initialUserPrompt == nil
            && lastUserPrompt == nil
            && lastAssistantMessage == nil
            && lastAssistantMessageBody == nil
            && platform == nil
            && model == nil
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
            terminalTTY: terminalTTY,
            tmuxTarget: tmuxTarget,
            tmuxSocketPath: tmuxSocketPath
        )
    }

    var defaultHermesMetadata: HermesSessionMetadata {
        HermesSessionMetadata(
            initialUserPrompt: userMessage ?? userMessagePreview,
            lastUserPrompt: userMessage ?? userMessagePreview,
            lastAssistantMessage: preserveNewlinesFromStart(assistantResponse, limit: 20000) ?? assistantResponsePreview,
            lastAssistantMessageBody: preserveNewlinesFromStart(assistantResponse, limit: 20000),
            platform: extraValue(forKey: "platform"),
            model: extraValue(forKey: "model")
        )
    }

    var implicitSummary: String {
        switch hookEventName {
        case .onSessionStart:
            return "Started Hermes session in \(workspaceName)."
        case .onSessionEnd:
            return "Hermes session ended in \(workspaceName)."
        case .postLLMCall:
            return assistantResponsePreview ?? "Hermes completed a turn in \(workspaceName)."
        case .subagentStop:
            let role = extraValue(forKey: "child_role")
            return role.map { "Hermes subagent (\($0)) finished in \(workspaceName)." }
                ?? "Hermes subagent finished in \(workspaceName)."
        case .preToolCall:
            return hitlQuestionPrompt != nil
                ? "Hermes has a question for you in \(workspaceName)."
                : "Hermes is running \(toolName ?? "a tool") in \(workspaceName)."
        case .preApprovalRequest:
            return "Hermes is waiting for approval in \(workspaceName)."
        case .preAPIRequest:
            return userMessagePreview.map { "Hermes is working on: \($0)" }
                ?? "Hermes started a turn in \(workspaceName)."
        }
    }

    /// Human-in-the-loop prompt carried by a `pre_tool_call` firing of the
    /// `clarify` tool. Mirrors the Claude `AskUserQuestion` payload shape.
    var hitlQuestionPrompt: QuestionPrompt? {
        guard hookEventName == .preToolCall,
              toolName == "clarify",
              case let .object(root) = toolInput,
              case let .array(rawQuestions) = root["questions"] else {
            return nil
        }

        let questions = rawQuestions.compactMap { rawQuestion -> QuestionPromptItem? in
            guard case let .object(questionObject) = rawQuestion,
                  let questionText = questionObject["question"]?.stringValue,
                  case let .array(rawOptions) = questionObject["options"] else {
                return nil
            }

            let options = rawOptions.compactMap { rawOption -> QuestionOption? in
                guard case let .object(optionObject) = rawOption,
                      let label = optionObject["label"]?.stringValue else {
                    return nil
                }

                return QuestionOption(
                    label: label,
                    description: optionObject["description"]?.stringValue ?? ""
                )
            }

            guard !options.isEmpty else {
                return nil
            }

            var resolvedOptions = options
            resolvedOptions.append(
                QuestionOption(label: "Other", description: "", allowsFreeform: true)
            )

            return QuestionPromptItem(
                question: questionText,
                header: questionObject["header"]?.stringValue ?? "",
                options: resolvedOptions,
                multiSelect: {
                    if case let .boolean(value) = questionObject["multi_select"] {
                        return value
                    }
                    if case let .boolean(value) = questionObject["multiSelect"] {
                        return value
                    }
                    return false
                }()
            )
        }

        guard !questions.isEmpty else {
            return nil
        }

        let title: String
        if questions.count == 1, let firstQuestion = questions.first?.question {
            title = firstQuestion
        } else {
            title = "Hermes has \(questions.count) questions for you."
        }

        return QuestionPrompt(title: title, options: [], questions: questions)
    }

    /// Approval card carried by `pre_approval_request`.
    var hitlPermissionRequest: PermissionRequest? {
        guard hookEventName == .preApprovalRequest else {
            return nil
        }

        let command = extraValue(forKey: "command") ?? toolName
        let description = extraValue(forKey: "description")

        return PermissionRequest(
            title: description ?? "Hermes needs approval",
            summary: command.map { "Command: \($0)" } ?? "Hermes is asking for approval.",
            affectedPath: cwd,
            primaryActionTitle: "Approve",
            secondaryActionTitle: "Deny",
            toolName: toolName,
            toolUseID: extraValue(forKey: "tool_call_id")
        )
    }

    var userMessagePreview: String? {
        clipped(userMessage)
    }

    var assistantResponsePreview: String? {
        clipped(assistantResponse)
    }

    var userMessage: String? {
        extraValue(forKey: "user_message")
    }

    var assistantResponse: String? {
        extraValue(forKey: "assistant_response")
    }

    func extraValue(forKey key: String) -> String? {
        guard case let .object(object)? = extra else { return nil }
        return object[key]?.stringValue
    }

    // MARK: - Runtime context

    func withRuntimeContext(environment: [String: String]) -> HermesHookPayload {
        withRuntimeContext(
            environment: environment,
            currentTTYProvider: { currentTTY() },
            terminalLocatorProvider: { terminalLocator(for: $0) }
        )
    }

    func withRuntimeContext(
        environment: [String: String],
        currentTTYProvider: @escaping () -> String?,
        terminalLocatorProvider: @escaping (String) -> (sessionID: String?, tty: String?, title: String?)
    ) -> HermesHookPayload {
        withRuntimeContext(
            environment: environment,
            currentTTYProvider: currentTTYProvider,
            terminalLocatorProvider: terminalLocatorProvider,
            tmuxResolverProvider: { Self.tmuxResolver() }
        )
    }

    func withRuntimeContext(
        environment: [String: String],
        currentTTYProvider: @escaping () -> String?,
        terminalLocatorProvider: @escaping (String) -> (sessionID: String?, tty: String?, title: String?),
        tmuxResolverProvider: @escaping () -> (any TmuxPaneResolverProtocol)?,
        ancestorTTYProvider: @escaping ([Int]) -> [String] = { HermesHookPayload.ancestorTTYs(pids: $0) },
        parentPIDProvider: @escaping () -> [Int] = { HermesHookPayload.ancestorPIDs() }
    ) -> HermesHookPayload {
        var payload = self

        // $TMUX is set only inside a tmux pane. When present, tmux is
        // authoritative for the terminal identity and the env vars are leaked
        // host context.
        if environment["TMUX"] != nil,
           let tmux = tmuxResolverProvider() {
            // Inside tmux the inherited TERM_PROGRAM / ITERM_SESSION_ID point
            // at whatever launched the tmux client, not the host terminal this
            // session lives in. tmux is authoritative: resolve the pane and the
            // host terminal from the tmux client instead of the leaked env.
            // Hooks may run through pipelines whose direct TTY is a pipe-side
            // pty rather than the pane, so try ancestor TTYs too.
            if let pane = Self.resolvedTmuxPane(
                resolver: tmux,
                currentTTYProvider: currentTTYProvider,
                ancestorTTYProvider: ancestorTTYProvider,
                parentPIDProvider: parentPIDProvider
            ) {
                payload.tmuxTarget = pane.target
                payload.tmuxSocketPath = tmux.socketPath
                payload.terminalTTY = pane.tty
                if let hostApp = tmux.hostTerminalApp() {
                    payload.terminalApp = hostApp
                }
                payload.terminalSessionID = nil
                payload.terminalTitle = nil
                return payload
            }
        }

        if payload.terminalApp == nil {
            payload.terminalApp = inferTerminalApp(from: environment)
        }

        if payload.terminalTTY == nil {
            payload.terminalTTY = currentTTYProvider()
        }

        if let terminalApp = payload.terminalApp,
           shouldUseFocusedTerminalLocator(for: terminalApp) {
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

    static func tmuxResolver() -> (any TmuxPaneResolverProtocol)? {
        TmuxPaneResolver()
    }

    struct ResolvedPane: Equatable, Sendable {
        var target: String
        var tty: String
    }

    /// Resolve the tmux pane for this hook process: try the direct TTY first,
    /// then the TTYs of up to four ancestor processes, since hooks spawned
    /// through pipelines report the pipeline's pty instead of the pane's.
    static func resolvedTmuxPane(
        resolver: any TmuxPaneResolverProtocol,
        currentTTYProvider: () -> String?,
        ancestorTTYProvider: ([Int]) -> [String] = { HermesHookPayload.ancestorTTYs(pids: $0) },
        parentPIDProvider: () -> [Int] = { HermesHookPayload.ancestorPIDs() }
    ) -> ResolvedPane? {
        if let direct = currentTTYProvider(),
           let pane = resolver.pane(forTTY: direct) {
            return ResolvedPane(target: pane.target, tty: direct)
        }

        let ancestors = ancestorTTYProvider(parentPIDProvider())
        for tty in ancestors {
            if let pane = resolver.pane(forTTY: tty) {
                return ResolvedPane(target: pane.target, tty: tty)
            }
        }

        return nil
    }

    static func ancestorPIDs() -> [Int] {
        var pids: [Int] = []
        var pid = Int(getppid())
        var visited: Set<Int> = []
        while pid > 1, visited.insert(pid).inserted, pids.count < 4 {
            pids.append(pid)
            guard let parent = ProcessInfo.processInfo.parentPID(of: pid) else {
                break
            }
            pid = parent
        }
        return pids
    }

    static func ancestorTTYs(pids: [Int]) -> [String] {
        pids.compactMap { pid in
            guard let raw = HermesHookPayload.processOutput(
                executablePath: "/bin/ps",
                arguments: ["-p", "\(pid)", "-o", "tty="]
            ) else {
                return nil
            }
            let tty = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tty.isEmpty, tty != "??", tty != "-", tty != "?" else {
                return nil
            }
            return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        }
    }

    private static func processOutput(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
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

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
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

    // MARK: - Text shaping

    private func preserveNewlinesClipped(_ value: String?, limit: Int) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        if value.count <= limit {
            return value
        }

        // For transcripts, the newest content is at the end.
        return String(value.suffix(limit))
    }

    /// Keeps the beginning of a long string (up to `limit` chars), preserving
    /// newlines. Used for assistant responses shown in the completion card,
    /// where the summary/overview at the start matters most to the user.
    private func preserveNewlinesFromStart(_ value: String?, limit: Int) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        if value.count <= limit {
            return value
        }

        return String(value.prefix(limit)) + "…"
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

private extension CodexHookJSONValue {
    var stringValue: String? {
        if case let .string(value) = self {
            value
        } else {
            nil
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
