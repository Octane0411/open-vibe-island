import Foundation

public typealias ClaudeHookJSONValue = CodexHookJSONValue

public enum ClaudePermissionMode: String, Codable, Sendable {
    case `default`
    case acceptEdits
    case plan
    case dontAsk
    case bypassPermissions
}

public enum ClaudePermissionBehavior: String, Codable, Sendable {
    case allow
    case deny
    case ask
}

public enum ClaudePermissionUpdateDestination: String, Codable, Sendable {
    case userSettings
    case projectSettings
    case localSettings
    case session
    case cliArg
}

public struct ClaudePermissionRuleValue: Equatable, Codable, Sendable {
    public var toolName: String
    public var ruleContent: String?

    public init(toolName: String, ruleContent: String? = nil) {
        self.toolName = toolName
        self.ruleContent = ruleContent
    }
}

public enum ClaudePermissionUpdate: Equatable, Codable, Sendable {
    case addRules(destination: ClaudePermissionUpdateDestination, rules: [ClaudePermissionRuleValue], behavior: ClaudePermissionBehavior)
    case replaceRules(destination: ClaudePermissionUpdateDestination, rules: [ClaudePermissionRuleValue], behavior: ClaudePermissionBehavior)
    case removeRules(destination: ClaudePermissionUpdateDestination, rules: [ClaudePermissionRuleValue], behavior: ClaudePermissionBehavior)
    case setMode(destination: ClaudePermissionUpdateDestination, mode: ClaudePermissionMode)
    case addDirectories(destination: ClaudePermissionUpdateDestination, directories: [String])
    case removeDirectories(destination: ClaudePermissionUpdateDestination, directories: [String])

    private enum CodingKeys: String, CodingKey {
        case type
        case destination
        case rules
        case behavior
        case mode
        case directories
    }

    private enum UpdateType: String, Codable {
        case addRules
        case replaceRules
        case removeRules
        case setMode
        case addDirectories
        case removeDirectories
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(UpdateType.self, forKey: .type)
        let destination = try container.decode(ClaudePermissionUpdateDestination.self, forKey: .destination)

        switch type {
        case .addRules:
            self = .addRules(
                destination: destination,
                rules: try container.decode([ClaudePermissionRuleValue].self, forKey: .rules),
                behavior: try container.decode(ClaudePermissionBehavior.self, forKey: .behavior)
            )
        case .replaceRules:
            self = .replaceRules(
                destination: destination,
                rules: try container.decode([ClaudePermissionRuleValue].self, forKey: .rules),
                behavior: try container.decode(ClaudePermissionBehavior.self, forKey: .behavior)
            )
        case .removeRules:
            self = .removeRules(
                destination: destination,
                rules: try container.decode([ClaudePermissionRuleValue].self, forKey: .rules),
                behavior: try container.decode(ClaudePermissionBehavior.self, forKey: .behavior)
            )
        case .setMode:
            self = .setMode(
                destination: destination,
                mode: try container.decode(ClaudePermissionMode.self, forKey: .mode)
            )
        case .addDirectories:
            self = .addDirectories(
                destination: destination,
                directories: try container.decode([String].self, forKey: .directories)
            )
        case .removeDirectories:
            self = .removeDirectories(
                destination: destination,
                directories: try container.decode([String].self, forKey: .directories)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .addRules(destination, rules, behavior):
            try container.encode(UpdateType.addRules, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(rules, forKey: .rules)
            try container.encode(behavior, forKey: .behavior)
        case let .replaceRules(destination, rules, behavior):
            try container.encode(UpdateType.replaceRules, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(rules, forKey: .rules)
            try container.encode(behavior, forKey: .behavior)
        case let .removeRules(destination, rules, behavior):
            try container.encode(UpdateType.removeRules, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(rules, forKey: .rules)
            try container.encode(behavior, forKey: .behavior)
        case let .setMode(destination, mode):
            try container.encode(UpdateType.setMode, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(mode, forKey: .mode)
        case let .addDirectories(destination, directories):
            try container.encode(UpdateType.addDirectories, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(directories, forKey: .directories)
        case let .removeDirectories(destination, directories):
            try container.encode(UpdateType.removeDirectories, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(directories, forKey: .directories)
        }
    }

    /// Human-readable label for rendering as a button in the approval card.
    /// Matches Claude Code's actual option text as closely as possible.
    public var displayLabel: String {
        switch self {
        case let .addRules(destination, rules, _):
            guard let rule = rules.first else { return "Yes, always allow" }
            let action = Self.actionVerb(for: rule.toolName)
            let path = Self.shortenedPath(rule.ruleContent)
            let scope = Self.scopeLabel(for: destination)
            if let path {
                return scope.isEmpty
                    ? "Yes, allow \(action) \(path)"
                    : "Yes, allow \(action) \(path) \(scope)"
            }
            return scope.isEmpty
                ? "Yes, always allow \(rule.toolName)"
                : "Yes, always allow \(rule.toolName) \(scope)"
        case let .setMode(_, mode):
            switch mode {
            case .acceptEdits:
                return "Yes, manually approve edits"
            case .bypassPermissions, .dontAsk:
                return "Yes, and bypass permissions"
            case .plan:
                return "Plan Mode"
            case .default:
                return "Manual Mode"
            }
        case .replaceRules:
            return "Update Rules"
        case .removeRules:
            return "Remove Rules"
        case .addDirectories:
            return "Add Directories"
        case .removeDirectories:
            return "Remove Directories"
        }
    }

    private static func actionVerb(for toolName: String) -> String {
        switch toolName {
        case "Read": return "reading from"
        case "Write", "Edit": return "writing to"
        case "Bash": return "running"
        case "Glob", "Grep": return "searching"
        default: return toolName.lowercased()
        }
    }

    private static func shortenedPath(_ ruleContent: String?) -> String? {
        guard let content = ruleContent, !content.isEmpty else { return nil }
        // Strip leading slashes and glob suffixes for cleaner display
        var path = content
        while path.hasPrefix("/") { path = String(path.dropFirst()) }
        if path.hasSuffix("/**") { path = String(path.dropLast(3)) }
        return path.isEmpty ? nil : path + "/"
    }

    private static func scopeLabel(for destination: ClaudePermissionUpdateDestination) -> String {
        switch destination {
        case .projectSettings: return "from this project"
        case .userSettings: return "globally"
        case .localSettings: return ""
        case .session: return "for this session"
        case .cliArg: return ""
        }
    }
}

public struct ClaudeSubagentInfo: Equatable, Codable, Sendable {
    public var agentID: String
    public var agentType: String?
    public var summary: String?
    public var taskDescription: String?
    public var startedAt: Date?

    public init(
        agentID: String,
        agentType: String? = nil,
        summary: String? = nil,
        taskDescription: String? = nil,
        startedAt: Date? = nil
    ) {
        self.agentID = agentID
        self.agentType = agentType
        self.summary = summary
        self.taskDescription = taskDescription
        self.startedAt = startedAt
    }
}

public struct ClaudeTaskInfo: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var status: Status

    public enum Status: String, Codable, Sendable {
        case pending, inProgress = "in_progress", completed
    }

    public init(id: String, title: String, status: Status = .pending) {
        self.id = id
        self.title = title
        self.status = status
    }
}

public struct ClaudeSessionMetadata: Equatable, Codable, Sendable {
    public var transcriptPath: String?
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var currentTool: String?
    public var currentToolInputPreview: String?
    public var model: String?
    public var startupSource: ClaudeSessionStartSource?
    public var permissionMode: ClaudePermissionMode?
    public var agentID: String?
    public var agentType: String?
    public var worktreeBranch: String?
    public var activeSubagents: [ClaudeSubagentInfo]
    public var activeTasks: [ClaudeTaskInfo]

    public init(
        transcriptPath: String? = nil,
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        currentTool: String? = nil,
        currentToolInputPreview: String? = nil,
        model: String? = nil,
        startupSource: ClaudeSessionStartSource? = nil,
        permissionMode: ClaudePermissionMode? = nil,
        agentID: String? = nil,
        agentType: String? = nil,
        worktreeBranch: String? = nil,
        activeSubagents: [ClaudeSubagentInfo] = [],
        activeTasks: [ClaudeTaskInfo] = []
    ) {
        self.transcriptPath = transcriptPath
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.currentTool = currentTool
        self.currentToolInputPreview = currentToolInputPreview
        self.model = model
        self.startupSource = startupSource
        self.permissionMode = permissionMode
        self.agentID = agentID
        self.agentType = agentType
        self.worktreeBranch = worktreeBranch
        self.activeSubagents = activeSubagents
        self.activeTasks = activeTasks
    }

    public var isEmpty: Bool {
        transcriptPath == nil
            && initialUserPrompt == nil
            && lastUserPrompt == nil
            && lastAssistantMessage == nil
            && currentTool == nil
            && currentToolInputPreview == nil
            && model == nil
            && startupSource == nil
            && permissionMode == nil
            && agentID == nil
            && agentType == nil
            && worktreeBranch == nil
            && activeSubagents.isEmpty
            && activeTasks.isEmpty
    }
}

public enum ClaudeHookEventName: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case permissionRequest = "PermissionRequest"
    case permissionDenied = "PermissionDenied"
    case notification = "Notification"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
}

public enum ClaudeSessionStartSource: String, Codable, Sendable {
    case startup
    case resume
    case clear
    case compact
}

public struct ClaudeHookPayload: Equatable, Codable, Sendable {
    public var cwd: String
    public var hookEventName: ClaudeHookEventName
    public var sessionID: String
    public var transcriptPath: String?
    public var permissionMode: ClaudePermissionMode?
    public var agentID: String?
    public var agentType: String?
    public var model: String?
    public var source: ClaudeSessionStartSource?
    public var toolName: String?
    public var toolInput: ClaudeHookJSONValue?
    public var toolUseID: String?
    public var toolResponse: ClaudeHookJSONValue?
    public var permissionSuggestions: [ClaudePermissionUpdate]?
    public var prompt: String?
    public var message: String?
    public var title: String?
    public var notificationType: String?
    public var stopHookActive: Bool?
    public var lastAssistantMessage: String?
    public var error: String?
    public var errorDetails: String?
    public var isInterrupt: Bool?
    public var agentTranscriptPath: String?
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var terminalTitle: String?
    /// Warp-specific per-pane identifier discovered via Warp's SQLite state
    /// at hook runtime. Not sent over the wire by the hook script — populated
    /// in `withRuntimeContext` and serialized through the bridge.
    public var warpPaneUUID: String?
    /// Set to `true` by the Python hook client to indicate a remote (SSH) session.
    public var remote: Bool?

    /// The agent tool that produced this hook payload (e.g. "claude", "qoder", "factory", "codebuddy", "kimi").
    /// Set by the hooks CLI from the `--source` argument; absent from the JSON emitted by agents
    /// themselves but included on the Unix-socket wire so `BridgeServer.resolvedAgentTool` can
    /// dispatch to the correct `AgentTool`.
    public var hookSource: String?

    private enum CodingKeys: String, CodingKey {
        case cwd
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case hookSource = "hook_source"
        case permissionMode = "permission_mode"
        case agentID = "agent_id"
        case agentType = "agent_type"
        case model
        case source
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseID = "tool_use_id"
        case toolResponse = "tool_response"
        case permissionSuggestions = "permission_suggestions"
        case prompt
        case message
        case title
        case notificationType = "notification_type"
        case stopHookActive = "stop_hook_active"
        case lastAssistantMessage = "last_assistant_message"
        case error
        case errorDetails = "error_details"
        case isInterrupt = "is_interrupt"
        case agentTranscriptPath = "agent_transcript_path"
        case terminalApp = "terminal_app"
        case terminalSessionID = "terminal_session_id"
        case terminalTTY = "terminal_tty"
        case terminalTitle = "terminal_title"
        case warpPaneUUID = "warp_pane_uuid"
        case remote
    }

    public init(
        cwd: String,
        hookEventName: ClaudeHookEventName,
        sessionID: String,
        transcriptPath: String? = nil,
        permissionMode: ClaudePermissionMode? = nil,
        agentID: String? = nil,
        agentType: String? = nil,
        model: String? = nil,
        source: ClaudeSessionStartSource? = nil,
        toolName: String? = nil,
        toolInput: ClaudeHookJSONValue? = nil,
        toolUseID: String? = nil,
        toolResponse: ClaudeHookJSONValue? = nil,
        permissionSuggestions: [ClaudePermissionUpdate]? = nil,
        prompt: String? = nil,
        message: String? = nil,
        title: String? = nil,
        notificationType: String? = nil,
        stopHookActive: Bool? = nil,
        lastAssistantMessage: String? = nil,
        error: String? = nil,
        errorDetails: String? = nil,
        isInterrupt: Bool? = nil,
        agentTranscriptPath: String? = nil,
        terminalApp: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        terminalTitle: String? = nil,
        warpPaneUUID: String? = nil,
        remote: Bool? = nil
    ) {
        self.cwd = cwd
        self.hookEventName = hookEventName
        self.sessionID = sessionID
        self.transcriptPath = transcriptPath
        self.permissionMode = permissionMode
        self.agentID = agentID
        self.agentType = agentType
        self.model = model
        self.source = source
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolUseID = toolUseID
        self.toolResponse = toolResponse
        self.permissionSuggestions = permissionSuggestions
        self.prompt = prompt
        self.message = message
        self.title = title
        self.notificationType = notificationType
        self.stopHookActive = stopHookActive
        self.lastAssistantMessage = lastAssistantMessage
        self.error = error
        self.errorDetails = errorDetails
        self.isInterrupt = isInterrupt
        self.agentTranscriptPath = agentTranscriptPath
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.terminalTitle = terminalTitle
        self.warpPaneUUID = warpPaneUUID
        self.remote = remote
    }
}

public struct ClaudePreToolUseDirective: Equatable, Codable, Sendable {
    public var permissionDecision: ClaudePermissionBehavior?
    public var permissionDecisionReason: String?
    public var updatedInput: ClaudeHookJSONValue?
    public var additionalContext: String?

    public init(
        permissionDecision: ClaudePermissionBehavior? = nil,
        permissionDecisionReason: String? = nil,
        updatedInput: ClaudeHookJSONValue? = nil,
        additionalContext: String? = nil
    ) {
        self.permissionDecision = permissionDecision
        self.permissionDecisionReason = permissionDecisionReason
        self.updatedInput = updatedInput
        self.additionalContext = additionalContext
    }
}

public enum ClaudePermissionRequestDecision: Equatable, Codable, Sendable {
    case allow(updatedInput: ClaudeHookJSONValue? = nil, updatedPermissions: [ClaudePermissionUpdate] = [])
    case deny(message: String? = nil, interrupt: Bool = false)

    private enum CodingKeys: String, CodingKey {
        case behavior
        case updatedInput
        case updatedPermissions
        case message
        case interrupt
    }

    private enum Behavior: String, Codable {
        case allow
        case deny
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let behavior = try container.decode(Behavior.self, forKey: .behavior)

        switch behavior {
        case .allow:
            self = .allow(
                updatedInput: try container.decodeIfPresent(ClaudeHookJSONValue.self, forKey: .updatedInput),
                updatedPermissions: try container.decodeIfPresent([ClaudePermissionUpdate].self, forKey: .updatedPermissions) ?? []
            )
        case .deny:
            self = .deny(
                message: try container.decodeIfPresent(String.self, forKey: .message),
                interrupt: try container.decodeIfPresent(Bool.self, forKey: .interrupt) ?? false
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .allow(updatedInput, updatedPermissions):
            try container.encode(Behavior.allow, forKey: .behavior)
            try container.encodeIfPresent(updatedInput, forKey: .updatedInput)
            if !updatedPermissions.isEmpty {
                try container.encode(updatedPermissions, forKey: .updatedPermissions)
            }
        case let .deny(message, interrupt):
            try container.encode(Behavior.deny, forKey: .behavior)
            try container.encodeIfPresent(message, forKey: .message)
            if interrupt {
                try container.encode(true, forKey: .interrupt)
            }
        }
    }
}

public enum ClaudeHookDirective: Equatable, Codable, Sendable {
    case preToolUse(ClaudePreToolUseDirective)
    case permissionRequest(ClaudePermissionRequestDecision)

    private enum CodingKeys: String, CodingKey {
        case type
        case directive
    }

    private enum DirectiveType: String, Codable {
        case preToolUse
        case permissionRequest
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DirectiveType.self, forKey: .type)

        switch type {
        case .preToolUse:
            self = .preToolUse(try container.decode(ClaudePreToolUseDirective.self, forKey: .directive))
        case .permissionRequest:
            self = .permissionRequest(try container.decode(ClaudePermissionRequestDecision.self, forKey: .directive))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .preToolUse(directive):
            try container.encode(DirectiveType.preToolUse, forKey: .type)
            try container.encode(directive, forKey: .directive)
        case let .permissionRequest(directive):
            try container.encode(DirectiveType.permissionRequest, forKey: .type)
            try container.encode(directive, forKey: .directive)
        }
    }
}

public enum ClaudeHookOutputEncoder {
    private struct PreToolUseOutput: Encodable {
        struct HookSpecificOutput: Encodable {
            var hookEventName = ClaudeHookEventName.preToolUse.rawValue
            var permissionDecision: ClaudePermissionBehavior?
            var permissionDecisionReason: String?
            var updatedInput: ClaudeHookJSONValue?
            var additionalContext: String?
        }

        var continue_: Bool = true
        var suppressOutput: Bool = true
        var hookSpecificOutput: HookSpecificOutput

        private enum CodingKeys: String, CodingKey {
            case continue_ = "continue"
            case suppressOutput
            case hookSpecificOutput
        }
    }

    private struct PermissionRequestOutput: Encodable {
        struct HookSpecificOutput: Encodable {
            var hookEventName = ClaudeHookEventName.permissionRequest.rawValue
            var decision: ClaudePermissionRequestDecision
        }

        var continue_: Bool = true
        var suppressOutput: Bool = true
        var hookSpecificOutput: HookSpecificOutput

        private enum CodingKeys: String, CodingKey {
            case continue_ = "continue"
            case suppressOutput
            case hookSpecificOutput
        }
    }

    public static func standardOutput(for response: BridgeResponse) throws -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data: Data?
        switch response {
        case .acknowledged:
            data = nil
        case .codexHookDirective:
            data = nil
        case .openCodeHookDirective:
            data = nil
        case .cursorHookDirective:
            data = nil
        case let .claudeHookDirective(directive):
            switch directive {
            case let .preToolUse(payload):
                data = try encoder.encode(
                    PreToolUseOutput(
                        hookSpecificOutput: PreToolUseOutput.HookSpecificOutput(
                            permissionDecision: payload.permissionDecision,
                            permissionDecisionReason: payload.permissionDecisionReason,
                            updatedInput: payload.updatedInput,
                            additionalContext: payload.additionalContext
                        )
                    )
                )
            case let .permissionRequest(decision):
                data = try encoder.encode(
                    PermissionRequestOutput(
                        hookSpecificOutput: PermissionRequestOutput.HookSpecificOutput(decision: decision)
                    )
                )
            }
        }

        guard var line = data else {
            return nil
        }

        line.append(UInt8(ascii: "\n"))
        return line
    }
}

public extension ClaudeHookPayload {
    var workspaceName: String {
        WorkspaceNameResolver.workspaceName(for: cwd)
    }

    var worktreeBranch: String? {
        WorkspaceNameResolver.worktreeBranch(for: cwd)
    }

    var sessionTitle: String {
        "Claude · \(workspaceName)"
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: terminalApp ?? "Unknown",
            workspaceName: workspaceName,
            paneTitle: terminalTitle ?? "Claude \(sessionID.prefix(8))",
            workingDirectory: cwd,
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY,
            warpPaneUUID: warpPaneUUID
        )
    }

    var defaultClaudeMetadata: ClaudeSessionMetadata {
        ClaudeSessionMetadata(
            transcriptPath: transcriptPath ?? agentTranscriptPath,
            initialUserPrompt: prompt ?? promptPreview,
            lastUserPrompt: prompt ?? promptPreview,
            lastAssistantMessage: lastAssistantMessage ?? assistantMessagePreview,
            currentTool: toolName,
            currentToolInputPreview: toolInputPreview,
            model: model,
            startupSource: source,
            permissionMode: permissionMode,
            agentID: agentID,
            agentType: agentType,
            worktreeBranch: worktreeBranch
        )
    }

    var implicitStartSummary: String {
        let agent = resolvedAgentTool.displayName
        switch hookEventName {
        case .sessionStart:
            switch source {
            case .resume:
                return "Resumed \(agent) session in \(workspaceName)."
            case .clear:
                return "Cleared \(agent) context in \(workspaceName)."
            case .compact:
                return "Compacted \(agent) context in \(workspaceName)."
            case .startup, .none:
                return "Started \(agent) session in \(workspaceName)."
            }
        case .userPromptSubmit:
            return "\(agent) received a new prompt in \(workspaceName)."
        case .preToolUse:
            return "\(agent) is preparing \(toolName ?? "a tool") in \(workspaceName)."
        case .postToolUse:
            return "\(agent) finished \(toolName ?? "a tool") in \(workspaceName)."
        case .postToolUseFailure:
            return "\(agent) hit a tool error in \(workspaceName)."
        case .permissionRequest:
            return "\(agent) needs approval in \(workspaceName)."
        case .permissionDenied:
            return "\(agent) permission was denied in \(workspaceName)."
        case .notification:
            return "\(agent) sent a notification in \(workspaceName)."
        case .stop:
            return "\(agent) completed a turn in \(workspaceName)."
        case .stopFailure:
            return "\(agent) failed to finish a turn in \(workspaceName)."
        case .subagentStart:
            return "\(agent) started a subagent in \(workspaceName)."
        case .subagentStop:
            return "\(agent) finished a subagent in \(workspaceName)."
        case .preCompact:
            return "\(agent) is compacting the conversation in \(workspaceName)."
        case .sessionEnd:
            return "\(agent) session ended in \(workspaceName)."
        }
    }

    var promptPreview: String? {
        clipped(prompt)
    }

    var assistantMessagePreview: String? {
        clipped(lastAssistantMessage)
    }

    var toolInputPreview: String? {
        // For object-type tool inputs, extract the most relevant field
        // instead of serializing the entire JSON structure.
        if case let .object(obj) = toolInput {
            let keyPriority = ["command", "file_path", "pattern", "query", "prompt", "description", "skill", "url"]
            for key in keyPriority {
                if let val = obj[key]?.stringValue, !val.isEmpty {
                    return clipped(val)
                }
            }
        }
        return clipped(stringValue(for: toolInput))
    }

    var toolResponsePreview: String? {
        clipped(stringValue(for: toolResponse))
    }

    var notificationPreview: String? {
        let preview = [title, message]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return clipped(preview)
    }

    var permissionCorrelationKey: String {
        let input = serializedToolInput ?? "<none>"
        return "\(sessionID)|\(toolName ?? "<unknown>")|\(input)"
    }

    var serializedToolInput: String? {
        guard let toolInput else {
            return nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try? encoder.encode(toolInput)
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    var questionPrompt: QuestionPrompt? {
        guard toolName == "AskUserQuestion",
              case let .object(root) = toolInput,
              case let .array(rawQuestions) = root["questions"] else {
            return nil
        }

        let questions = rawQuestions.compactMap { rawQuestion -> QuestionPromptItem? in
            guard case let .object(questionObject) = rawQuestion,
                  let questionText = questionObject["question"]?.stringValue,
                  let header = questionObject["header"]?.stringValue,
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

            // CLIs add "Other" client-side and tell the model not to include one; mirror that here.
            var resolvedOptions = options
            resolvedOptions.append(
                QuestionOption(label: "Other", description: "", allowsFreeform: true)
            )

            return QuestionPromptItem(
                question: questionText,
                header: header,
                options: resolvedOptions,
                multiSelect: questionObject["multiSelect"]?.boolValue ?? false
            )
        }

        guard !questions.isEmpty else {
            return nil
        }

        let title: String
        if questions.count == 1, let firstQuestion = questions.first?.question {
            title = firstQuestion
        } else {
            title = "Claude has \(questions.count) questions for you."
        }

        return QuestionPrompt(title: title, questions: questions)
    }

    /// Resolves the `AgentTool` for this payload based on `hookSource`.
    /// Defaults to `.claudeCode` for unknown or nil sources.
    var resolvedAgentTool: AgentTool {
        switch hookSource {
        case "qoder":
            return .qoder
        case "qwen":
            return .qwenCode
        case "factory", "droid":
            return .factory
        case "codebuddy":
            return .codebuddy
        case "kimi":
            return .kimiCLI
        default:
            return .claudeCode
        }
    }

    var permissionRequestTitle: String {
        switch toolName {
        case "ExitPlanMode":
            return "Exit plan mode"
        case "AskUserQuestion":
            return "Answer Claude's questions"
        case let toolName?:
            return "Allow \(toolName)"
        case nil:
            return "Allow Claude tool"
        }
    }

    var permissionRequestSummary: String {
        if toolName == "ExitPlanMode" {
            return "Claude wants to exit plan mode and start implementation."
        }

        if let questionPrompt {
            return questionPrompt.title
        }

        if let notificationPreview {
            return notificationPreview
        }

        let agent = resolvedAgentTool.displayName

        if let toolName {
            return "\(agent) wants to run \(toolName)."
        }

        return "\(agent) needs permission to continue."
    }

    var permissionAffectedPath: String {
        if let explicitPath = extractedPathValue, !explicitPath.isEmpty {
            return explicitPath
        }

        if let preview = toolInputPreview, !preview.isEmpty {
            return preview
        }

        return cwd
    }

    func withRuntimeContext(environment: [String: String]) -> ClaudeHookPayload {
        withRuntimeContext(
            environment: environment,
            currentTTYProvider: { currentTTY() },
            terminalLocatorProvider: { terminalLocator(for: $0) },
            warpPaneResolver: Self.defaultWarpPaneResolver
        )
    }

    /// Default production resolver. Tries the PID-based lookup first
    /// (unambiguous even for sibling tabs sharing a cwd) and falls back
    /// to the cwd-based lookup when PID correlation is unavailable —
    /// either because the hook is running outside a Warp pane (e.g.
    /// invoked by tests) or because Warp's terminal-server child
    /// enumeration is in a transient state.
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
    ) -> ClaudeHookPayload {
        var payload = self

        if payload.terminalApp == nil {
            payload.terminalApp = inferTerminalApp(from: environment)
        }

        // Resolve Warp pane UUID from the live SQLite state.
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
            // Ghostty's AppleScript returns the *focused* terminal which is
            // only reliable when the user just interacted with the terminal.
            // SessionStart and UserPromptSubmit are safe because the user's
            // terminal is guaranteed to be focused at those moments.  Later
            // hooks (tool use, etc.) may fire after the user switched tabs,
            // so clear stale values and skip the locator.
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

    private var extractedPathValue: String? {
        guard case let .object(root) = toolInput else {
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
        // leak across apps via macOS GUI app environment inheritance.
        //
        // Concrete leak this guards against: launching Warp via
        // `open -a Warp` (or any other path) from a Ghostty tab causes
        // Warp's main process — and every shell Warp later spawns — to
        // inherit Ghostty's GHOSTTY_RESOURCES_DIR. The previous
        // env-var-first ordering then tagged those Warp shells as
        // Ghostty, which fed the wrong terminal app to terminalLocator,
        // which queried Ghostty's `focused terminal of selected tab of
        // front window` and stamped a foreign Ghostty pane's
        // sessionID/cwd/title onto the Warp session's jumpTarget. The
        // resulting liveAttachmentKey collided with the real Ghostty
        // owner and the Warp session was deduped out of the island list.
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
            case "kaku":
                return "Kaku"
            case "wezterm":
                return "WezTerm"
            case "vscode":
                // Cursor also sets TERM_PROGRAM=vscode; check its unique
                // env var first.
                if environment["CURSOR_TRACE_ID"] != nil {
                    return "Cursor"
                }
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

        // Fallback for terminals that don't set TERM_PROGRAM (older builds,
        // exotic launchers, etc.). These per-app env vars are vulnerable to
        // the GUI inheritance leak documented above; only consult them when
        // TERM_PROGRAM gave us nothing useful. Within this fallback, check
        // Warp before Ghostty so a leaked GHOSTTY_RESOURCES_DIR cannot win
        // over a real WARP_IS_LOCAL_SHELL_SESSION on the same shell.
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
            // Try to identify the specific IDE from __CFBundleIdentifier or IDEA_INITIAL_DIRECTORY.
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
            return "IntelliJ IDEA"  // Fallback for unknown JetBrains IDE
        }

        // Last resort: some launchers (notably certain managed Claude Code
        // setups) strip TERM_PROGRAM / GHOSTTY_RESOURCES_DIR / ITERM_*
        // before spawning the hook. Walk the process ancestry and match
        // the terminal by executable path. Unlike env vars, parent-chain
        // lookup can't be fooled by GUI inheritance because every pane has
        // its own real parent.
        return inferTerminalAppFromProcessAncestry()
    }

    private func inferTerminalAppFromProcessAncestry() -> String? {
        var pid = getppid()
        var hops = 0
        while pid > 1, hops < 12 {
            guard let command = commandOutput(
                executablePath: "/bin/ps",
                arguments: ["-p", "\(pid)", "-o", "command="]
            )?.lowercased() else {
                return nil
            }

            if let app = Self.terminalAppName(forProcessCommand: command) {
                return app
            }

            guard let ppidRaw = commandOutput(
                executablePath: "/bin/ps",
                arguments: ["-p", "\(pid)", "-o", "ppid="]
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let next = Int32(ppidRaw), next > 1, next != pid else {
                return nil
            }
            pid = next
            hops += 1
        }
        return nil
    }

    private static func terminalAppName(forProcessCommand command: String) -> String? {
        if command.contains("/ghostty.app/") || command.contains("ghostty-helper") { return "Ghostty" }
        if command.contains("/iterm.app/") || command.contains("/iterm2") { return "iTerm" }
        if command.contains("/warp.app/") || command.contains("/warp-stable") { return "Warp" }
        if command.contains("/wezterm.app/") || command.contains("wezterm-gui") { return "WezTerm" }
        if command.contains("/kaku.app/") { return "Kaku" }
        if command.contains("/cmux.app/") { return "cmux" }
        if command.contains("/terminal.app/") { return "Terminal" }
        if command.contains("/visual studio code.app/") || command.contains("/code helper") { return "VS Code" }
        if command.contains("/visual studio code - insiders.app/") { return "VS Code Insiders" }
        if command.contains("/cursor.app/") { return "Cursor" }
        if command.contains("/windsurf.app/") { return "Windsurf" }
        if command.contains("/trae.app/") { return "Trae" }
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
