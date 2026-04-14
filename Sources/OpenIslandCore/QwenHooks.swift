import Foundation

public enum QwenHookDirective: Equatable, Codable, Sendable {
    case allow
    case deny(reason: String?)
    case answer(text: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case reason
        case text
    }

    private enum DirectiveType: String, Codable {
        case allow
        case deny
        case answer
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DirectiveType.self, forKey: .type)

        switch type {
        case .allow:
            self = .allow
        case .deny:
            self = .deny(reason: try container.decodeIfPresent(String.self, forKey: .reason))
        case .answer:
            self = .answer(text: try container.decode(String.self, forKey: .text))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .allow:
            try container.encode(DirectiveType.allow, forKey: .type)
        case let .deny(reason):
            try container.encode(DirectiveType.deny, forKey: .type)
            try container.encodeIfPresent(reason, forKey: .reason)
        case let .answer(text):
            try container.encode(DirectiveType.answer, forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

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
    public var toolInputPreview: String?
    public var toolInput: ClaudeHookJSONValue?
    public var permissionTitle: String?
    public var permissionDescription: String?
    public var questionText: String?

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
        case toolInputPreview = "tool_input_preview"
        case toolInput = "tool_input"
        case permissionTitle = "permission_title"
        case permissionDescription = "permission_description"
        case questionText = "question_text"
        case terminalApp = "terminal_app"
        case terminalTitle = "terminal_title"
        case terminalSessionID = "terminal_session_id"
        case terminalTTY = "terminal_tty"
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
        toolInputPreview: String? = nil,
        toolInput: ClaudeHookJSONValue? = nil,
        permissionTitle: String? = nil,
        permissionDescription: String? = nil,
        questionText: String? = nil,
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
        self.toolInputPreview = toolInputPreview
        self.toolInput = toolInput
        self.permissionTitle = permissionTitle
        self.permissionDescription = permissionDescription
        self.questionText = questionText
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

    public var normalizedHookEventName: String {
        hookEventName
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
    }

    public var isInteractiveHookEvent: Bool {
        switch normalizedHookEventName {
        case "permissionrequest", "questionasked":
            true
        default:
            false
        }
    }

    public var effectiveToolInputPreview: String? {
        if let preview = clipped(toolInputPreview) {
            return preview
        }

        if let object = parsedToolInputObject {
            let keyPriority = ["command", "file_path", "path", "pattern", "query", "prompt", "description", "url"]
            for key in keyPriority {
                if let value = object[key]?.stringValue, !value.isEmpty {
                    return clipped(value)
                }
            }
        }

        return clipped(stringValue(for: toolInput))
    }

    private var parsedToolInputObject: [String: ClaudeHookJSONValue]? {
        guard let toolInput else { return nil }
        
        // If it's already parsed as a JSON object, use it directly
        if case let .object(object) = toolInput {
            return object
        }
        
        // Qwen CLI might pass the entire JSON blob inside a single string.
        // Let's try to decode the string itself.
        if case let .string(jsonString) = toolInput,
           let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ClaudeHookJSONValue.self, from: data),
           case let .object(object) = decoded {
            return object
        }
        
        return nil
    }

    public var permissionRequestTitle: String {
        permissionTitle
            ?? toolName.map { "Allow \($0)" }
            ?? "Allow Qwen tool"
    }

    public var permissionRequestSummary: String {
        if let permissionDescription = clipped(permissionDescription) {
            return permissionDescription
        }

        if let questionText = clipped(questionText) {
            return questionText
        }

        if let toolName {
            return "Qwen wants to run \(toolName)."
        }

        return "Qwen needs permission to continue."
    }

    public var permissionAffectedPath: String {
        if let explicitPath = extractedPathValue, !explicitPath.isEmpty {
            return explicitPath
        }

        if let preview = effectiveToolInputPreview, !preview.isEmpty {
            return preview
        }

        return cwd
    }

    public var questionPrompt: QuestionPrompt? {
        if let prompt = askUserQuestionPrompt {
            return prompt
        }

        guard let title = clipped(questionText) else {
            return nil
        }

        return QuestionPrompt(title: title, options: [])
    }

    private var askUserQuestionPrompt: QuestionPrompt? {
        guard toolName == "AskUserQuestion",
              let root = parsedToolInputObject else {
            return nil
        }

        let questions = parsedQuestionItems(from: root)
        if !questions.isEmpty {
            let title: String
            if questions.count == 1, let firstQuestion = clipped(questions.first?.question) {
                title = firstQuestion
            } else {
                title = "Qwen has \(questions.count) questions for you."
            }

            return QuestionPrompt(title: title, questions: questions)
        }

        let fallbackTitle = clipped(
            root["question"]?.stringValue
                ?? root["prompt"]?.stringValue
                ?? questionText
        )

        let options = parsedQuestionOptions(from: root["options"])
        guard let fallbackTitle else {
            return nil
        }

        return QuestionPrompt(
            title: fallbackTitle,
            options: options.map(\.label)
        )
    }

    private func clipped(_ string: String?) -> String? {
        guard let string else { return nil }
        let collapsed = string
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return nil }

        guard collapsed.count > 200 else {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 199)
        return "\(collapsed[..<endIndex])…"
    }

    private var extractedPathValue: String? {
        guard let root = parsedToolInputObject else {
            return nil
        }

        let candidateKeys = [
            "file_path",
            "path",
            "notebook_path",
            "target_file",
            "working_directory",
        ]

        for key in candidateKeys {
            if let value = root[key]?.stringValue, !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private func parsedQuestionItems(from root: [String: ClaudeHookJSONValue]) -> [QuestionPromptItem] {
        guard case let .array(rawQuestions)? = root["questions"] else {
            return []
        }

        return rawQuestions.compactMap { rawQuestion in
            guard case let .object(questionObject) = rawQuestion else {
                return nil
            }

            let questionText = clipped(
                questionObject["question"]?.stringValue
                    ?? questionObject["prompt"]?.stringValue
            )
            let options = parsedQuestionOptions(from: questionObject["options"])

            guard let questionText, !options.isEmpty else {
                return nil
            }

            let header = clipped(questionObject["header"]?.stringValue) ?? "Question"
            return QuestionPromptItem(
                question: questionText,
                header: header,
                options: options,
                multiSelect: questionObject["multiSelect"]?.boolValue ?? false
            )
        }
    }

    private func parsedQuestionOptions(from rawValue: ClaudeHookJSONValue?) -> [QuestionOption] {
        guard case let .array(rawOptions)? = rawValue else {
            return []
        }

        return rawOptions.compactMap { rawOption in
            switch rawOption {
            case let .string(label):
                guard let label = clipped(label) else {
                    return nil
                }
                return QuestionOption(label: label)
            case let .object(optionObject):
                guard let label = clipped(optionObject["label"]?.stringValue) else {
                    return nil
                }

                let description = clipped(optionObject["description"]?.stringValue) ?? ""
                return QuestionOption(label: label, description: description)
            default:
                return nil
            }
        }
    }

    private func stringValue(for value: ClaudeHookJSONValue?) -> String? {
        guard let value else {
            return nil
        }

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
            return "[\(items.compactMap { stringValue(for: $0) }.joined(separator: ", "))]"
        case let .object(object):
            let rendered = object
                .keys
                .sorted()
                .map { key in
                    let value = stringValue(for: object[key]) ?? "null"
                    return "\(key): \(value)"
                }
                .joined(separator: ", ")
            return "{\(rendered)}"
        }
    }

    public func withRuntimeContext(environment: [String: String]) -> QwenHookPayload {
        withRuntimeContext(
            environment: environment,
            currentTTYProvider: { currentTTY() },
            terminalLocatorProvider: { terminalLocator(for: $0) }
        )
    }

    public func withRuntimeContext(
        environment: [String: String],
        currentTTYProvider: () -> String?,
        terminalLocatorProvider: (String) -> (sessionID: String?, tty: String?, title: String?)
    ) -> QwenHookPayload {
        var payload = self

        if payload.terminalApp == nil {
            payload.terminalApp = inferTerminalApp(from: environment)
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
            useLocator = false
        } else if let terminalApp = payload.terminalApp, isGhosttyTerminalApp(terminalApp) {
            if payload.hookEventName == "SessionStart" || payload.hookEventName == "UserPromptSubmit" {
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
        if environment["ITERM_SESSION_ID"] != nil || environment["LC_TERMINAL"] == "iTerm2" {
            return "iTerm"
        }

        if environment["CMUX_WORKSPACE_ID"] != nil || environment["CMUX_SOCKET_PATH"] != nil {
            return "cmux"
        }

        // Zellij runs inside another terminal; detect it before the parent
        // terminal so we can capture pane context for jump-back.
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
                sessionID: values.indices.contains(0) ? values[0] : nil,
                tty: values.indices.contains(1) ? values[1] : nil,
                title: values.indices.contains(2) ? values[2] : nil
            )
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
            return (
                sessionID: values.indices.contains(0) ? values[0] : nil,
                tty: nil,
                title: values.indices.contains(2) ? values[2] : nil
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
                tty: values.indices.contains(0) ? values[0] : nil,
                title: values.indices.contains(1) ? values[1] : nil
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
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty else { return nil }

            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

}

public enum QwenHookOutputEncoder {
    public static func standardOutput(for response: BridgeResponse) throws -> Data? {
        guard case let .qwenHookDirective(directive) = response else {
            return nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let payload: Data
        switch directive {
        case .allow:
            payload = try encoder.encode(QwenHookDirective.allow)
        case let .deny(reason):
            payload = try encoder.encode(QwenHookDirective.deny(reason: reason))
        case let .answer(text):
            payload = try encoder.encode(QwenHookDirective.answer(text: text))
        }

        var line = payload
        line.append(UInt8(ascii: "\n"))
        return line
    }
}

private extension ClaudeHookJSONValue {
    var stringValue: String? {
        if case let .string(value) = self {
            value
        } else {
            nil
        }
    }

    var boolValue: Bool? {
        if case let .boolean(value) = self {
            value
        } else {
            nil
        }
    }
}
