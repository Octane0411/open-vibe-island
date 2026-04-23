import Foundation

public enum AgentTool: String, CaseIterable, Codable, Sendable {
    case claudeCode
    case codex
    case geminiCLI
    case openCode
    case qoder
    case qwenCode
    case factory
    case codebuddy
    case cursor
    case kimiCLI

    public var displayName: String {
        switch self {
        case .claudeCode:
            "Claude Code"
        case .codex:
            "Codex"
        case .geminiCLI:
            "Gemini CLI"
        case .openCode:
            "OpenCode"
        case .qoder:
            "Qoder"
        case .qwenCode:
            "Qwen Code"
        case .factory:
            "Factory"
        case .codebuddy:
            "CodeBuddy"
        case .cursor:
            "Cursor"
        case .kimiCLI:
            "Kimi CLI"
        }
    }

    public var shortName: String {
        switch self {
        case .claudeCode:
            "CLAUDE"
        case .codex:
            "CODEX"
        case .geminiCLI:
            "GEMINI"
        case .openCode:
            "OPENCODE"
        case .qoder:
            "QODER"
        case .qwenCode:
            "QWEN"
        case .factory:
            "FACTORY"
        case .codebuddy:
            "CODEBUDDY"
        case .cursor:
            "CURSOR"
        case .kimiCLI:
            "KIMI"
        }
    }

    public var isClaudeCodeFork: Bool {
        switch self {
        case .claudeCode, .qoder, .qwenCode, .factory, .codebuddy, .kimiCLI:
            true
        default:
            false
        }
    }
}

public enum SessionOrigin: String, Codable, Sendable {
    case live
    case demo
}

public enum SessionAttachmentState: String, Codable, Sendable {
    case attached
    case stale
    case detached

    public var isLive: Bool {
        self == .attached
    }
}

public enum SessionPhase: String, Codable, Sendable, CaseIterable {
    case running
    case waitingForApproval
    case waitingForAnswer
    case completed

    public var displayName: String {
        switch self {
        case .running:
            "Running"
        case .waitingForApproval:
            "Needs approval"
        case .waitingForAnswer:
            "Needs answer"
        case .completed:
            "Completed"
        }
    }

    public var requiresAttention: Bool {
        switch self {
        case .waitingForApproval, .waitingForAnswer:
            true
        case .running, .completed:
            false
        }
    }
}

public enum SessionLifecyclePolicy: String, Codable, Sendable {
    case processDriven
    case hookDrivenWithProcessFallback
    case appDriven
}

public enum SessionRuntimeMatchStrength: Int, Codable, Comparable, Sendable {
    case toolFamily
    case terminalTTY
    case workingDirectory
    case terminalTTYAndWorkingDirectory
    case transcriptPath
    case sessionID
    case desktopApp

    public static func < (lhs: SessionRuntimeMatchStrength, rhs: SessionRuntimeMatchStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum SessionEventPresenceSource: String, Codable, Sendable {
    case bridge
    case rolloutBootstrap
    case rolloutLive
}

public struct SessionLivenessObservation: Equatable, Sendable {
    public var observationCycle: Int
    public var lastRuntimePositiveCycle: Int?
    public var strongestRuntimeMatch: SessionRuntimeMatchStrength?
    public var lastEventPositiveCycle: Int?
    public var lastEventSource: SessionEventPresenceSource?

    public init(
        observationCycle: Int = 0,
        lastRuntimePositiveCycle: Int? = nil,
        strongestRuntimeMatch: SessionRuntimeMatchStrength? = nil,
        lastEventPositiveCycle: Int? = nil,
        lastEventSource: SessionEventPresenceSource? = nil
    ) {
        self.observationCycle = observationCycle
        self.lastRuntimePositiveCycle = lastRuntimePositiveCycle
        self.strongestRuntimeMatch = strongestRuntimeMatch
        self.lastEventPositiveCycle = lastEventPositiveCycle
        self.lastEventSource = lastEventSource
    }

    public var runtimeMissCount: Int {
        missCount(since: lastRuntimePositiveCycle)
    }

    public var eventMissCount: Int {
        missCount(since: lastEventPositiveCycle)
    }

    public var fallbackMissCount: Int {
        [lastRuntimePositiveCycle.map { _ in runtimeMissCount }, lastEventPositiveCycle.map { _ in eventMissCount }]
            .compactMap { $0 }
            .min()
            ?? observationCycle
    }

    public var hasRuntimePresence: Bool {
        guard lastRuntimePositiveCycle != nil else {
            return false
        }
        return runtimeMissCount < 2
    }

    public var hasEventPresence: Bool {
        guard lastEventPositiveCycle != nil else {
            return false
        }
        return eventMissCount < 2
    }

    public mutating func advanceRuntimeObservation(match: SessionRuntimeMatchStrength?) {
        observationCycle += 1
        guard let match else {
            return
        }

        lastRuntimePositiveCycle = observationCycle
        strongestRuntimeMatch = match
    }

    public mutating func recordEventPresence(_ source: SessionEventPresenceSource) {
        lastEventPositiveCycle = observationCycle
        lastEventSource = source
    }

    public mutating func seedRuntimePresence(_ match: SessionRuntimeMatchStrength) {
        lastRuntimePositiveCycle = observationCycle
        strongestRuntimeMatch = match
    }

    public mutating func clearRuntimePresence() {
        lastRuntimePositiveCycle = nil
        strongestRuntimeMatch = nil
    }

    private func missCount(since positiveCycle: Int?) -> Int {
        guard let positiveCycle else {
            return observationCycle
        }

        return max(0, observationCycle - positiveCycle)
    }
}

public struct SessionTrackingIdentity: Equatable, Codable, Sendable {
    public var sessionID: String
    public var transcriptPath: String?
    public var workingDirectory: String?
    public var terminalTTY: String?
    public var terminalSessionID: String?

    public init(
        sessionID: String,
        transcriptPath: String? = nil,
        workingDirectory: String? = nil,
        terminalTTY: String? = nil,
        terminalSessionID: String? = nil
    ) {
        self.sessionID = sessionID
        self.transcriptPath = transcriptPath
        self.workingDirectory = workingDirectory
        self.terminalTTY = terminalTTY
        self.terminalSessionID = terminalSessionID
    }
}

public struct JumpTarget: Equatable, Codable, Sendable {
    public var terminalApp: String
    public var workspaceName: String
    public var paneTitle: String
    public var workingDirectory: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var tmuxTarget: String?
    public var tmuxSocketPath: String?
    public var warpPaneUUID: String?
    /// Codex.app thread/conversation ID.  When set and `terminalApp` is
    /// `"Codex.app"`, the jump uses the `codex://threads/<id>` URL scheme
    /// to open the conversation directly rather than just activating the app.
    public var codexThreadID: String?

    public init(
        terminalApp: String,
        workspaceName: String,
        paneTitle: String,
        workingDirectory: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        tmuxTarget: String? = nil,
        tmuxSocketPath: String? = nil,
        warpPaneUUID: String? = nil,
        codexThreadID: String? = nil
    ) {
        self.terminalApp = terminalApp
        self.workspaceName = workspaceName
        self.paneTitle = paneTitle
        self.workingDirectory = workingDirectory
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.tmuxTarget = tmuxTarget
        self.tmuxSocketPath = tmuxSocketPath
        self.warpPaneUUID = warpPaneUUID
        self.codexThreadID = codexThreadID
    }
}

public struct PermissionRequest: Equatable, Identifiable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var affectedPath: String
    public var primaryActionTitle: String
    public var secondaryActionTitle: String
    public var toolName: String?
    public var toolUseID: String?
    public var suggestedUpdates: [ClaudePermissionUpdate]
    public var requiresTerminalApproval: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        affectedPath: String,
        primaryActionTitle: String = "Allow",
        secondaryActionTitle: String = "Deny",
        toolName: String? = nil,
        toolUseID: String? = nil,
        suggestedUpdates: [ClaudePermissionUpdate] = [],
        requiresTerminalApproval: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.affectedPath = affectedPath
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.suggestedUpdates = suggestedUpdates
        self.requiresTerminalApproval = requiresTerminalApproval
    }
}

/// A single selectable option within a structured question prompt.
public struct QuestionOption: Equatable, Identifiable, Codable, Sendable {
    public var id: UUID
    public var label: String
    public var description: String
    /// When true, the submitted answer is the user's typed text, not the label.
    public var allowsFreeform: Bool

    public init(
        id: UUID = UUID(),
        label: String,
        description: String = "",
        allowsFreeform: Bool = false
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.allowsFreeform = allowsFreeform
    }
}

public struct QuestionPromptItem: Equatable, Codable, Sendable {
    public var question: String
    public var header: String
    public var options: [QuestionOption]
    public var multiSelect: Bool

    public init(
        question: String,
        header: String,
        options: [QuestionOption],
        multiSelect: Bool = false
    ) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }
}

public struct QuestionPrompt: Equatable, Identifiable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var options: [String]
    public var questions: [QuestionPromptItem]

    public init(
        id: UUID = UUID(),
        title: String,
        options: [String],
        questions: [QuestionPromptItem] = []
    ) {
        self.id = id
        self.title = title
        self.options = options
        self.questions = questions
    }

    public init(
        id: UUID = UUID(),
        title: String,
        questions: [QuestionPromptItem]
    ) {
        self.id = id
        self.title = title
        self.questions = questions
        self.options = questions.first?.options.map(\.label) ?? []
    }
}

public struct QuestionAnswerAnnotation: Equatable, Codable, Sendable {
    public var preview: String?
    public var notes: String?

    public init(preview: String? = nil, notes: String? = nil) {
        self.preview = preview
        self.notes = notes
    }
}

public struct QuestionPromptResponse: Equatable, Codable, Sendable {
    public var rawAnswer: String?
    public var answers: [String: String]
    public var annotations: [String: QuestionAnswerAnnotation]

    public init(
        rawAnswer: String? = nil,
        answers: [String: String] = [:],
        annotations: [String: QuestionAnswerAnnotation] = [:]
    ) {
        self.rawAnswer = rawAnswer
        self.answers = answers
        self.annotations = annotations
    }

    public init(answer: String) {
        self.init(rawAnswer: answer)
    }

    public var displaySummary: String {
        if let rawAnswer, !rawAnswer.isEmpty {
            return rawAnswer
        }

        let renderedAnswers = answers
            .keys
            .sorted()
            .compactMap { key -> String? in
                guard let value = answers[key], !value.isEmpty else {
                    return nil
                }

                return "\(key): \(value)"
            }

        return renderedAnswers.joined(separator: " · ")
    }
}

/// User-facing approval action shown in the island notification card.
public enum ApprovalAction: Sendable {
    case deny
    case allowOnce
    case allowWithUpdates([ClaudePermissionUpdate])
}

public enum PermissionResolution: Equatable, Codable, Sendable {
    case allowOnce(updatedInput: ClaudeHookJSONValue? = nil, updatedPermissions: [ClaudePermissionUpdate] = [])
    case deny(message: String? = nil, interrupt: Bool = false)

    public var isApproved: Bool {
        switch self {
        case .allowOnce:
            true
        case .deny:
            false
        }
    }
}

public struct AgentSession: Equatable, Identifiable, Codable, Sendable {
    public var id: String
    public var title: String
    public var tool: AgentTool
    public var origin: SessionOrigin?
    public var attachmentState: SessionAttachmentState
    public var phase: SessionPhase
    public var summary: String
    public var updatedAt: Date
    public var permissionRequest: PermissionRequest?
    public var questionPrompt: QuestionPrompt?
    public var jumpTarget: JumpTarget?
    public var codexMetadata: CodexSessionMetadata?
    public var claudeMetadata: ClaudeSessionMetadata?
    public var geminiMetadata: GeminiSessionMetadata?
    public var openCodeMetadata: OpenCodeSessionMetadata?
    public var cursorMetadata: CursorSessionMetadata?

    /// Whether this session originates from a remote (SSH) connection.
    public var isRemote: Bool = false

    /// The authoritative lifecycle law for this session. Persisted so restored
    /// sessions retain the same liveness semantics as live ones.
    public var lifecyclePolicy: SessionLifecyclePolicy = .processDriven

    /// Whether the agent session has ended (received `SessionEnd` hook).
    /// Only meaningful for hook-managed sessions.
    public var isSessionEnded: Bool = false

    /// Runtime and ingress evidence is ephemeral. It is intentionally not
    /// persisted; restored sessions must earn freshness again via new evidence.
    public var livenessObservation = SessionLivenessObservation()

    public init(
        id: String,
        title: String,
        tool: AgentTool,
        origin: SessionOrigin? = nil,
        attachmentState: SessionAttachmentState = .stale,
        phase: SessionPhase,
        summary: String,
        updatedAt: Date,
        permissionRequest: PermissionRequest? = nil,
        questionPrompt: QuestionPrompt? = nil,
        jumpTarget: JumpTarget? = nil,
        codexMetadata: CodexSessionMetadata? = nil,
        claudeMetadata: ClaudeSessionMetadata? = nil,
        geminiMetadata: GeminiSessionMetadata? = nil,
        openCodeMetadata: OpenCodeSessionMetadata? = nil,
        cursorMetadata: CursorSessionMetadata? = nil,
        isRemote: Bool = false,
        lifecyclePolicy: SessionLifecyclePolicy = .processDriven,
        isSessionEnded: Bool = false
    ) {
        self.id = id
        self.title = title
        self.tool = tool
        self.origin = origin
        self.attachmentState = attachmentState
        self.phase = phase
        self.summary = summary
        self.updatedAt = updatedAt
        self.permissionRequest = permissionRequest
        self.questionPrompt = questionPrompt
        self.jumpTarget = jumpTarget
        self.codexMetadata = codexMetadata
        self.claudeMetadata = claudeMetadata
        self.geminiMetadata = geminiMetadata
        self.openCodeMetadata = openCodeMetadata
        self.cursorMetadata = cursorMetadata
        self.isRemote = isRemote
        self.lifecyclePolicy = lifecyclePolicy
        self.isSessionEnded = isSessionEnded
        self.livenessObservation = SessionLivenessObservation()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case tool
        case origin
        case attachmentState
        case phase
        case summary
        case updatedAt
        case permissionRequest
        case questionPrompt
        case jumpTarget
        case codexMetadata
        case claudeMetadata
        case geminiMetadata
        case openCodeMetadata
        case cursorMetadata
        case isRemote
        case lifecyclePolicy
        case isSessionEnded
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        tool = try container.decode(AgentTool.self, forKey: .tool)
        origin = try container.decodeIfPresent(SessionOrigin.self, forKey: .origin)
        attachmentState = try container.decodeIfPresent(SessionAttachmentState.self, forKey: .attachmentState) ?? .stale
        phase = try container.decode(SessionPhase.self, forKey: .phase)
        summary = try container.decode(String.self, forKey: .summary)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        permissionRequest = try container.decodeIfPresent(PermissionRequest.self, forKey: .permissionRequest)
        questionPrompt = try container.decodeIfPresent(QuestionPrompt.self, forKey: .questionPrompt)
        jumpTarget = try container.decodeIfPresent(JumpTarget.self, forKey: .jumpTarget)
        codexMetadata = try container.decodeIfPresent(CodexSessionMetadata.self, forKey: .codexMetadata)
        claudeMetadata = try container.decodeIfPresent(ClaudeSessionMetadata.self, forKey: .claudeMetadata)
        geminiMetadata = try container.decodeIfPresent(GeminiSessionMetadata.self, forKey: .geminiMetadata)
        openCodeMetadata = try container.decodeIfPresent(OpenCodeSessionMetadata.self, forKey: .openCodeMetadata)
        cursorMetadata = try container.decodeIfPresent(CursorSessionMetadata.self, forKey: .cursorMetadata)
        isRemote = try container.decodeIfPresent(Bool.self, forKey: .isRemote) ?? false
        lifecyclePolicy = try container.decodeIfPresent(SessionLifecyclePolicy.self, forKey: .lifecyclePolicy)
            ?? Self.inferredLifecyclePolicy(
                tool: tool,
                origin: origin,
                jumpTarget: jumpTarget
            )
        isSessionEnded = try container.decodeIfPresent(Bool.self, forKey: .isSessionEnded) ?? false
        livenessObservation = SessionLivenessObservation()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(tool, forKey: .tool)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encode(attachmentState, forKey: .attachmentState)
        try container.encode(phase, forKey: .phase)
        try container.encode(summary, forKey: .summary)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(permissionRequest, forKey: .permissionRequest)
        try container.encodeIfPresent(questionPrompt, forKey: .questionPrompt)
        try container.encodeIfPresent(jumpTarget, forKey: .jumpTarget)
        try container.encodeIfPresent(codexMetadata, forKey: .codexMetadata)
        try container.encodeIfPresent(claudeMetadata, forKey: .claudeMetadata)
        try container.encodeIfPresent(geminiMetadata, forKey: .geminiMetadata)
        try container.encodeIfPresent(openCodeMetadata, forKey: .openCodeMetadata)
        try container.encodeIfPresent(cursorMetadata, forKey: .cursorMetadata)
        try container.encode(isRemote, forKey: .isRemote)
        try container.encode(lifecyclePolicy, forKey: .lifecyclePolicy)
        try container.encode(isSessionEnded, forKey: .isSessionEnded)
    }
}

public extension AgentSession {
    static func inferredLifecyclePolicy(
        tool: AgentTool,
        origin: SessionOrigin?,
        jumpTarget: JumpTarget?
    ) -> SessionLifecyclePolicy {
        if tool == .codex && jumpTarget?.terminalApp == "Codex.app" {
            return .appDriven
        }

        if origin == .live && tool.supportsHookLifecycleSignals {
            return .hookDrivenWithProcessFallback
        }

        return .processDriven
    }

    var isDemoSession: Bool {
        origin == .demo
    }

    var isTrackedLiveSession: Bool {
        !isDemoSession && (tool == .codex || tool == .claudeCode || tool == .geminiCLI || tool == .openCode || tool == .qoder || tool == .qwenCode || tool == .factory || tool == .codebuddy || tool == .cursor || tool == .kimiCLI)
    }

    var isTrackedLiveCodexSession: Bool {
        tool == .codex && !isDemoSession
    }

    var isAttachedToTerminal: Bool {
        attachmentState.isLive
    }

    var hasEventPresence: Bool {
        livenessObservation.hasEventPresence
    }

    var hasRuntimePresence: Bool {
        livenessObservation.hasRuntimePresence
    }

    var hasFallbackPresence: Bool {
        hasRuntimePresence || hasEventPresence
    }

    /// Policy-aware presence used by the core reducer and UI.
    var hasPresenceEvidence: Bool {
        switch lifecyclePolicy {
        case .appDriven, .processDriven:
            return hasRuntimePresence
        case .hookDrivenWithProcessFallback:
            return hasFallbackPresence
        }
    }

    /// Policy-aware miss count. Process-driven sessions expire on runtime
    /// misses; hook-managed sessions expire on the first missing source among
    /// runtime or events.
    var presenceMissCount: Int {
        switch lifecyclePolicy {
        case .appDriven, .processDriven:
            return livenessObservation.runtimeMissCount
        case .hookDrivenWithProcessFallback:
            return livenessObservation.fallbackMissCount
        }
    }

    func normalizedForPresentationComparison() -> Self {
        var normalized = self
        normalized.livenessObservation = SessionLivenessObservation(
            observationCycle: 0,
            lastRuntimePositiveCycle: hasRuntimePresence ? 0 : nil,
            strongestRuntimeMatch: hasRuntimePresence ? livenessObservation.strongestRuntimeMatch : nil,
            lastEventPositiveCycle: hasEventPresence ? 0 : nil,
            lastEventSource: hasEventPresence ? livenessObservation.lastEventSource : nil
        )
        return normalized
    }

    func normalizedForPersistenceComparison() -> Self {
        var normalized = self
        normalized.livenessObservation = SessionLivenessObservation()
        return normalized
    }

    var trackingIdentity: SessionTrackingIdentity {
        SessionTrackingIdentity(
            sessionID: id,
            transcriptPath: trackingTranscriptPath,
            workingDirectory: jumpTarget?.workingDirectory,
            terminalTTY: jumpTarget?.terminalTTY,
            terminalSessionID: jumpTarget?.terminalSessionID
        )
    }

    /// Visibility rule for the island UI.
    /// Hook-managed sessions (Claude Code via hooks) rely on hook lifecycle
    /// signals; non-hook sessions use process polling.
    var isVisibleInIsland: Bool {
        if isDemoSession { return true }
        if phase.requiresAttention { return true }
        switch lifecyclePolicy {
        case .appDriven:
            return hasRuntimePresence
        case .hookDrivenWithProcessFallback:
            if attachmentState.isLive {
                return !isSessionEnded
            }
            return hasFallbackPresence
        case .processDriven:
            return hasRuntimePresence
        }
    }

    var currentToolName: String? {
        codexMetadata?.currentTool ?? claudeMetadata?.currentTool ?? openCodeMetadata?.currentTool ?? cursorMetadata?.currentTool
    }

    var lastAssistantMessageText: String? {
        codexMetadata?.lastAssistantMessage ?? claudeMetadata?.lastAssistantMessage ?? geminiMetadata?.lastAssistantMessage ?? openCodeMetadata?.lastAssistantMessage ?? cursorMetadata?.lastAssistantMessage
    }

    var completionAssistantMessageText: String? {
        if let gemini = geminiMetadata {
            if let body = gemini.lastAssistantMessageBody?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !body.isEmpty {
                if let extractedBody = Self.extractGeminiCompletionBody(from: body) {
                    return extractedBody
                }
            }
            return gemini.lastAssistantMessage
        }
        return lastAssistantMessageText
    }

    var trackingTranscriptPath: String? {
        codexMetadata?.transcriptPath ?? claudeMetadata?.transcriptPath ?? geminiMetadata?.transcriptPath
    }

    var latestUserPromptText: String? {
        codexMetadata?.lastUserPrompt ?? claudeMetadata?.lastUserPrompt ?? geminiMetadata?.lastUserPrompt ?? openCodeMetadata?.lastUserPrompt ?? cursorMetadata?.lastUserPrompt
    }

    var initialUserPromptText: String? {
        codexMetadata?.initialUserPrompt ?? claudeMetadata?.initialUserPrompt ?? geminiMetadata?.initialUserPrompt ?? openCodeMetadata?.initialUserPrompt ?? cursorMetadata?.initialUserPrompt
    }

    var currentCommandPreviewText: String? {
        codexMetadata?.currentCommandPreview ?? claudeMetadata?.currentToolInputPreview ?? openCodeMetadata?.currentToolInputPreview ?? cursorMetadata?.currentToolInputPreview
    }
}

private extension AgentSession {
    static func extractGeminiCompletionBody(from body: String) -> String? {
        let normalizedBody = normalizeGeminiBlankLines(in: body)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n\n", options: .regularExpression)

        let segments = normalizedBody
            .components(separatedBy: "\n\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let lastSegment = segments.last else {
            return nil
        }

        // Gemini hook payloads sometimes append a duplicate copy of the final
        // answer, often with only whitespace differences. Deduplicate against a
        // whitespace-compacted view of the text, but preserve the original
        // formatting in the string we return to the UI.
        let deduplicatedSegment = removeRepeatedTrailingGeminiContent(from: lastSegment)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return deduplicatedSegment.isEmpty ? nil : deduplicatedSegment
    }

    static func normalizeGeminiBlankLines(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                line.trimmingCharacters(in: .whitespaces).isEmpty ? "" : line
            }
            .joined(separator: "\n")
    }

    static func removeRepeatedTrailingGeminiContent(from text: String) -> String {
        let compacted = compactedGeminiText(text)
        let minimumRepeatedTailLength = 30

        guard compacted.characters.count >= minimumRepeatedTailLength * 2 else {
            return text
        }

        let maximumTailLength = compacted.characters.count / 2
        guard maximumTailLength >= minimumRepeatedTailLength else {
            return text
        }

        guard let repeatedTailStart = longestRepeatedGeminiTailStart(
            in: compacted.characters,
            minimumLength: minimumRepeatedTailLength
        ) else {
            return text
        }

        let originalTailStart = compacted.originalIndices[repeatedTailStart]
        let adjustedTailStart = adjustedGeminiDuplicateBoundary(in: text, from: originalTailStart)
        return String(text[..<adjustedTailStart]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compactedGeminiText(_ text: String) -> (characters: [Character], originalIndices: [String.Index]) {
        var characters: [Character] = []
        var originalIndices: [String.Index] = []

        for index in text.indices {
            let character = text[index]
            if character.isWhitespace {
                continue
            }
            characters.append(character)
            originalIndices.append(index)
        }

        return (characters, originalIndices)
    }

    static func longestRepeatedGeminiTailStart(
        in characters: [Character],
        minimumLength: Int
    ) -> Int? {
        let count = characters.count
        guard count >= minimumLength * 2 else {
            return nil
        }

        for length in stride(from: count / 2, through: minimumLength, by: -1) {
            let tailStart = count - length
            let tail = Array(characters[tailStart...])

            if tailStart < length {
                continue
            }

            for candidateStart in 0...(tailStart - length) {
                let candidateEnd = candidateStart + length
                if Array(characters[candidateStart..<candidateEnd]) == tail {
                    return tailStart
                }
            }
        }

        return nil
    }

    static func adjustedGeminiDuplicateBoundary(in text: String, from index: String.Index) -> String.Index {
        var boundary = index

        while boundary > text.startIndex {
            let previous = text.index(before: boundary)
            if text[previous].isWhitespace {
                boundary = previous
                continue
            }
            break
        }

        var searchIndex = boundary
        while searchIndex > text.startIndex {
            let candidate = text.index(before: searchIndex)
            if text[candidate] != "\n" {
                searchIndex = candidate
                continue
            }

            var newlineCount = 1
            var probe = candidate
            while probe > text.startIndex {
                let previous = text.index(before: probe)
                if text[previous] == "\n" {
                    newlineCount += 1
                    probe = previous
                    continue
                }
                if text[previous].isWhitespace {
                    probe = previous
                    continue
                }
                break
            }

            if newlineCount >= 2 {
                let fragment = text[searchIndex..<index]
                let compactedFragmentCount = fragment.reduce(into: 0) { count, character in
                    if !character.isWhitespace {
                        count += 1
                    }
                }

                if compactedFragmentCount <= 12 {
                    return searchIndex
                }
                return boundary
            }

            searchIndex = candidate
        }

        return boundary
    }
}

public extension AgentTool {
    var supportsHookLifecycleSignals: Bool {
        switch self {
        case .codex, .claudeCode, .geminiCLI, .openCode, .qoder, .qwenCode, .factory, .codebuddy, .cursor, .kimiCLI:
            true
        }
    }
}
