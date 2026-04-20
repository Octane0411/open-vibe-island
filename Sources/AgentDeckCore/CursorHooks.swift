import Foundation

public enum CursorHookEventName: String, Codable, Sendable {
    case beforeSubmitPrompt
    case beforeShellExecution
    case beforeMCPExecution
    case beforeReadFile
    case afterFileEdit
    case stop
}

public struct CursorFileEdit: Equatable, Codable, Sendable {
    public var oldString: String
    public var newString: String

    public init(oldString: String, newString: String) {
        self.oldString = oldString
        self.newString = newString
    }

    private enum CodingKeys: String, CodingKey {
        case oldString = "old_string"
        case newString = "new_string"
    }
}

public struct CursorAttachment: Equatable, Codable, Sendable {
    public var type: String?
    public var filePath: String?

    public init(type: String? = nil, filePath: String? = nil) {
        self.type = type
        self.filePath = filePath
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case filePath = "file_path"
    }
}

public struct CursorHookPayload: Equatable, Codable, Sendable {
    public var hookEventName: CursorHookEventName
    public var conversationId: String
    public var generationId: String
    public var workspaceRoots: [String]

    // Event-specific (all optional)
    public var prompt: String?
    public var command: String?
    public var cwd: String?
    public var server: String?
    public var toolName: String?
    public var toolInput: String?
    public var filePath: String?
    public var edits: [CursorFileEdit]?
    public var content: String?
    public var status: String?
    public var attachments: [CursorAttachment]?

    // Cursor-specific metadata
    public var model: String?
    public var cursorVersion: String?
    public var transcriptPath: String?
    public var sandbox: Bool?

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case conversationId = "conversation_id"
        case generationId = "generation_id"
        case workspaceRoots = "workspace_roots"
        case prompt
        case command
        case cwd
        case server
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case filePath = "file_path"
        case edits
        case content
        case status
        case attachments
        case model
        case cursorVersion = "cursor_version"
        case transcriptPath = "transcript_path"
        case sandbox
    }

    public init(
        hookEventName: CursorHookEventName,
        conversationId: String,
        generationId: String,
        workspaceRoots: [String],
        prompt: String? = nil,
        command: String? = nil,
        cwd: String? = nil,
        server: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil,
        filePath: String? = nil,
        edits: [CursorFileEdit]? = nil,
        content: String? = nil,
        status: String? = nil,
        attachments: [CursorAttachment]? = nil,
        model: String? = nil,
        cursorVersion: String? = nil,
        transcriptPath: String? = nil,
        sandbox: Bool? = nil
    ) {
        self.hookEventName = hookEventName
        self.conversationId = conversationId
        self.generationId = generationId
        self.workspaceRoots = workspaceRoots
        self.prompt = prompt
        self.command = command
        self.cwd = cwd
        self.server = server
        self.toolName = toolName
        self.toolInput = toolInput
        self.filePath = filePath
        self.edits = edits
        self.content = content
        self.status = status
        self.attachments = attachments
        self.model = model
        self.cursorVersion = cursorVersion
        self.transcriptPath = transcriptPath
        self.sandbox = sandbox
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hookEventName = try container.decode(CursorHookEventName.self, forKey: .hookEventName)
        self.conversationId = try container.decode(String.self, forKey: .conversationId)
        self.generationId = try container.decode(String.self, forKey: .generationId)
        self.workspaceRoots = (try? container.decodeIfPresent([String].self, forKey: .workspaceRoots)) ?? []
        self.prompt = try? container.decodeIfPresent(String.self, forKey: .prompt)
        self.command = try? container.decodeIfPresent(String.self, forKey: .command)
        self.cwd = try? container.decodeIfPresent(String.self, forKey: .cwd)
        self.server = try? container.decodeIfPresent(String.self, forKey: .server)
        self.toolName = try? container.decodeIfPresent(String.self, forKey: .toolName)
        self.toolInput = try? container.decodeIfPresent(String.self, forKey: .toolInput)
        self.filePath = try? container.decodeIfPresent(String.self, forKey: .filePath)
        self.edits = try? container.decodeIfPresent([CursorFileEdit].self, forKey: .edits)
        self.content = try? container.decodeIfPresent(String.self, forKey: .content)
        self.status = try? container.decodeIfPresent(String.self, forKey: .status)
        self.attachments = try? container.decodeIfPresent([CursorAttachment].self, forKey: .attachments)
        self.model = try? container.decodeIfPresent(String.self, forKey: .model)
        self.cursorVersion = try? container.decodeIfPresent(String.self, forKey: .cursorVersion)
        self.transcriptPath = try? container.decodeIfPresent(String.self, forKey: .transcriptPath)
        self.sandbox = try? container.decodeIfPresent(Bool.self, forKey: .sandbox)
    }
}

public enum CursorPermission: String, Codable, Sendable {
    case allow
    case deny
    case ask
}

public struct CursorHookDirective: Equatable, Codable, Sendable {
    public var `continue`: Bool
    public var permission: CursorPermission
    public var userMessage: String?
    public var agentMessage: String?

    public init(
        `continue`: Bool = true,
        permission: CursorPermission,
        userMessage: String? = nil,
        agentMessage: String? = nil
    ) {
        self.`continue` = `continue`
        self.permission = permission
        self.userMessage = userMessage
        self.agentMessage = agentMessage
    }
}

public struct CursorSessionMetadata: Equatable, Codable, Sendable {
    public var conversationId: String?
    public var generationId: String?
    public var workspaceRoots: [String]?
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var currentTool: String?
    public var currentToolInputPreview: String?
    public var currentCommandPreview: String?
    public var model: String?
    public var transcriptPath: String?

    public init(
        conversationId: String? = nil,
        generationId: String? = nil,
        workspaceRoots: [String]? = nil,
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        currentTool: String? = nil,
        currentToolInputPreview: String? = nil,
        currentCommandPreview: String? = nil,
        model: String? = nil,
        transcriptPath: String? = nil
    ) {
        self.conversationId = conversationId
        self.generationId = generationId
        self.workspaceRoots = workspaceRoots
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.currentTool = currentTool
        self.currentToolInputPreview = currentToolInputPreview
        self.currentCommandPreview = currentCommandPreview
        self.model = model
        self.transcriptPath = transcriptPath
    }

    public var isEmpty: Bool {
        conversationId == nil
            && generationId == nil
            && workspaceRoots == nil
            && initialUserPrompt == nil
            && lastUserPrompt == nil
            && lastAssistantMessage == nil
            && currentTool == nil
            && currentToolInputPreview == nil
            && currentCommandPreview == nil
            && model == nil
            && transcriptPath == nil
    }
}

// MARK: - Payload Convenience Extensions

public extension CursorHookPayload {
    var primaryWorkspaceRoot: String {
        workspaceRoots.first ?? cwd ?? "Unknown"
    }

    var workspaceName: String {
        WorkspaceNameResolver.workspaceName(for: primaryWorkspaceRoot)
    }

    var sessionTitle: String {
        "Cursor \u{00B7} \(workspaceName)"
    }

    var sessionID: String {
        conversationId
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: "Cursor",
            workspaceName: workspaceName,
            paneTitle: "Cursor \(conversationId.prefix(8))",
            workingDirectory: primaryWorkspaceRoot
        )
    }

    var defaultCursorMetadata: CursorSessionMetadata {
        CursorSessionMetadata(
            conversationId: conversationId,
            generationId: generationId,
            workspaceRoots: workspaceRoots,
            initialUserPrompt: promptPreview,
            lastUserPrompt: promptPreview,
            currentTool: toolName,
            currentToolInputPreview: toolInputPreview,
            currentCommandPreview: commandPreview,
            model: model,
            transcriptPath: transcriptPath
        )
    }

    var implicitStartSummary: String {
        switch hookEventName {
        case .beforeSubmitPrompt:
            return "Cursor received a new prompt in \(workspaceName)."
        case .beforeShellExecution:
            return "Cursor is preparing a shell command in \(workspaceName)."
        case .beforeMCPExecution:
            return "Cursor is calling \(toolName ?? "an MCP tool") in \(workspaceName)."
        case .beforeReadFile:
            return "Cursor is reading \(filePath ?? "a file") in \(workspaceName)."
        case .afterFileEdit:
            return "Cursor edited \(filePath ?? "a file") in \(workspaceName)."
        case .stop:
            return "Cursor completed a turn in \(workspaceName)."
        }
    }

    var promptPreview: String? {
        clipped(prompt)
    }

    var toolInputPreview: String? {
        clipped(toolInput)
    }

    var commandPreview: String? {
        clipped(command)
    }

    var isBlockingHook: Bool {
        hookEventName == .beforeShellExecution || hookEventName == .beforeMCPExecution
    }

    var permissionRequestTitle: String {
        switch hookEventName {
        case .beforeShellExecution:
            return "Allow shell command"
        case .beforeMCPExecution:
            let name = toolName ?? server ?? "MCP tool"
            return "Allow \(name)"
        default:
            return "Allow Cursor action"
        }
    }

    var permissionRequestSummary: String {
        switch hookEventName {
        case .beforeShellExecution:
            return command ?? "Cursor wants to run a shell command."
        case .beforeMCPExecution:
            let name = toolName ?? "an MCP tool"
            let serverLabel = server.map { " via \($0)" } ?? ""
            return "Cursor wants to call \(name)\(serverLabel)."
        default:
            return "Cursor needs permission to continue."
        }
    }

    var permissionAffectedPath: String {
        cwd ?? primaryWorkspaceRoot
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
        return "\(collapsed[..<endIndex])\u{2026}"
    }
}
