import Foundation

// CatPaw uses the same hook format as Claude Code.
// All payload parsing is handled by ClaudeHookPayload with hookSource = "catpaw".

public struct CatPawSessionMetadata: Equatable, Codable, Sendable {
    public var transcriptPath: String?
    public var initialUserPrompt: String?
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    public var currentTool: String?
    public var currentToolInputPreview: String?
    public var model: String?

    public init(
        transcriptPath: String? = nil,
        initialUserPrompt: String? = nil,
        lastUserPrompt: String? = nil,
        lastAssistantMessage: String? = nil,
        currentTool: String? = nil,
        currentToolInputPreview: String? = nil,
        model: String? = nil
    ) {
        self.transcriptPath = transcriptPath
        self.initialUserPrompt = initialUserPrompt
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.currentTool = currentTool
        self.currentToolInputPreview = currentToolInputPreview
        self.model = model
    }

    public var isEmpty: Bool {
        transcriptPath == nil
            && initialUserPrompt == nil
            && lastUserPrompt == nil
            && lastAssistantMessage == nil
            && currentTool == nil
            && currentToolInputPreview == nil
            && model == nil
    }
}

public extension ClaudeHookPayload {
    /// Metadata extracted from a CatPaw hook payload.
    var defaultCatPawMetadata: CatPawSessionMetadata {
        CatPawSessionMetadata(
            transcriptPath: transcriptPath ?? agentTranscriptPath,
            initialUserPrompt: prompt ?? promptPreview,
            lastUserPrompt: prompt ?? promptPreview,
            lastAssistantMessage: lastAssistantMessage ?? assistantMessagePreview,
            currentTool: toolName,
            currentToolInputPreview: toolInputPreview,
            model: model
        )
    }

    var catPawSessionTitle: String {
        "CatPaw · \(workspaceName)"
    }
}

