import Foundation
import OpenIslandCore

enum SpotlightActivityTone {
    case live
    case idle
    case ready
    case attention
}

enum IslandSessionPresence: Equatable {
    case running
    case active
    case inactive
}

extension AgentSession {
    private static let collapsedDetailAgeThreshold: TimeInterval = 20 * 60
    private static let islandActivityThreshold: TimeInterval = 20 * 60
    static let staleCompletedDisplayThreshold: TimeInterval = 5 * 60

    /// Whether this session represents a subagent (worktree agent) that should
    /// not appear as a separate entry in the session list.  The parent session
    /// already tracks subagents via `claudeMetadata.activeSubagents`.
    ///
    /// Note: `claudeMetadata.agentID` is NOT a reliable signal here because
    /// SubagentStart hooks set `agent_id` on the *parent* session's metadata.
    var isSubagentSession: Bool {
        if let path = claudeMetadata?.transcriptPath, path.contains("/subagents/") {
            return true
        }
        return false
    }

    var islandActivityDate: Date {
        updatedAt
    }

    var spotlightPrimaryText: String {
        if let request = permissionRequest {
            return request.summary
        }

        if let prompt = questionPrompt {
            return prompt.title
        }

        if let assistantMessage = lastAssistantMessageText?.trimmedForSurface,
           !assistantMessage.isEmpty {
            return assistantMessage
        }

        return summary
    }

    var spotlightSecondaryText: String? {
        if let request = permissionRequest {
            return request.affectedPath.isEmpty ? nil : request.affectedPath
        }

        if let currentTool = displayCurrentToolName {
            return phase == .completed
                ? summary
                : "Running \(currentTool)"
        }

        let normalizedPrimary = spotlightPrimaryText.trimmedForSurface
        let normalizedSummary = summary.trimmedForSurface
        guard normalizedSummary != normalizedPrimary else {
            return nil
        }

        return summary
    }

    var spotlightCurrentToolLabel: String? {
        displayCurrentToolName
    }

    var spotlightStatusLabel: String {
        switch phase {
        case .running:
            if let currentTool = spotlightCurrentToolLabel {
                return "Live · \(currentTool)"
            }
            return "Live"
        case .waitingForApproval:
            return "Approval"
        case .waitingForAnswer:
            return "Question"
        case .completed:
            return jumpTarget != nil ? "Idle" : "Completed"
        }
    }

    var spotlightTerminalLabel: String? {
        guard let jumpTarget else {
            return nil
        }

        return "\(jumpTarget.terminalApp) · \(jumpTarget.workspaceName)"
    }

    var spotlightTerminalBadge: String? {
        guard let terminalApp = jumpTarget?.terminalApp,
              terminalApp != JumpTarget.unknownTerminalApp else {
            return nil
        }

        return terminalApp
    }

    var spotlightWorkspaceName: String {
        if let workspaceName = jumpTarget?.workspaceName.trimmedForSurface,
           !workspaceName.isEmpty {
            return workspaceName
        }

        let trimmedTitle = title.trimmedForSurface
        let pieces = trimmedTitle.split(separator: "·", maxSplits: 1).map {
            String($0).trimmedForSurface
        }
        if pieces.count == 2, !pieces[1].isEmpty {
            return pieces[1]
        }

        return trimmedTitle
    }

    var spotlightWorktreeBranch: String? {
        // This is a SwiftUI computed property read on every layout
        // pass. It MUST stay free of filesystem IO. Calling
        // `WorkspaceNameResolver.gitBranch` here previously walked
        // parent directories every layout, which combined with
        // SwiftUI's measure/layout convergence cycle pinned the
        // process at 99 % CPU during session-list rendering even
        // with the resolver result cached.
        //
        // Read order: hook-supplied metadata wins (already resolved
        // by `BridgeServer` from the hook payload), then the pure
        // string-based worktree-path detector (no IO). Other
        // sessions surface the workspace name without a branch
        // suffix; for branch info on arbitrary `cwd` values to
        // come back, it has to be resolved when the session is
        // created or updated, not from the view body.
        if let branch = claudeMetadata?.worktreeBranch?.trimmedForSurface,
           !branch.isEmpty {
            return branch
        }

        guard let workingDirectory = jumpTarget?.workingDirectory?.trimmedForSurface,
              !workingDirectory.isEmpty else {
            return nil
        }

        return WorkspaceNameResolver.worktreeBranch(for: workingDirectory)
    }

    var spotlightSubagentLabel: String? {
        guard let subagents = claudeMetadata?.activeSubagents, !subagents.isEmpty else {
            return nil
        }
        return "Subagents (\(subagents.count))"
    }

    var spotlightHeadlineText: String {
        var headline = spotlightWorkspaceName

        if let branch = spotlightWorktreeBranch {
            headline += " (\(branch))"
        }

        guard let prompt = spotlightHeadlinePromptText else {
            return headline
        }

        return "\(headline) · \(prompt)"
    }

    var spotlightHeadlinePromptText: String? {
        // Headline shows the initial prompt (session topic), not the latest.
        // The latest prompt is shown separately in the "You:" line.
        initialPromptText ?? latestPromptText
    }

    var spotlightPromptText: String? {
        latestPromptText
    }

    var spotlightPromptLineText: String? {
        guard spotlightShowsDetailLines,
              let prompt = spotlightPromptText else {
            return nil
        }

        return "You: \(prompt)"
    }

    var completionReplyRecipientName: String {
        switch tool {
        case .claudeCode:
            return "Claude"
        case .codex:
            return "Codex"
        case .geminiCLI:
            return "Gemini"
        case .openCode:
            return "OpenCode"
        case .qoder:
            return "Qoder"
        case .qwenCode:
            return "Qwen Code"
        case .factory:
            return "Factory"
        case .codebuddy:
            return "CodeBuddy"
        case .cursor:
            return "Cursor"
        case .kimiCLI:
            return "Kimi"
        }
    }

    var notificationHeaderPromptLineText: String? {
        guard phase != .completed else {
            return nil
        }

        return spotlightPromptLineText
    }

    var spotlightActivityLineText: String? {
        guard spotlightShowsDetailLines else {
            return nil
        }

        if let request = permissionRequest?.summary.trimmedForSurface,
           !request.isEmpty {
            return request
        }

        if let prompt = questionPrompt?.title.trimmedForSurface,
           !prompt.isEmpty {
            return prompt
        }

        switch phase {
        case .running:
            if let activity = spotlightRunningActivityText {
                return activity
            }
            return spotlightPromptLineText == nil ? "Running" : "Thinking"
        case .waitingForApproval:
            return permissionRequest?.summary.trimmedForSurface ?? "Approval needed"
        case .waitingForAnswer:
            return questionPrompt?.title.trimmedForSurface ?? "Answer needed"
        case .completed:
            if let assistantMessage = lastAssistantMessageText?.trimmedForSurface,
               !assistantMessage.isEmpty {
                return assistantMessage
            }

            switch outcome {
            case .success:
                return jumpTarget != nil ? "Ready" : "Completed"
            case .interrupted:
                return "Interrupted"
            case .failed:
                return "Failed"
            }
        }
    }

    var spotlightActivityTone: SpotlightActivityTone {
        if phase.requiresAttention {
            return .attention
        }

        switch phase {
        case .running:
            return .live
        case .completed:
            if lastAssistantMessageText?.trimmedForSurface.isEmpty == false {
                return .idle
            }
            return .ready
        case .waitingForApproval, .waitingForAnswer:
            return .attention
        }
    }

    var spotlightShowsDetailLines: Bool {
        spotlightShowsDetailLines(at: .now)
    }

    func spotlightShowsDetailLines(at referenceDate: Date) -> Bool {
        if phase == .running || phase.requiresAttention {
            return true
        }

        if referenceDate.timeIntervalSince(islandActivityDate) >= Self.collapsedDetailAgeThreshold {
            return false
        }

        return spotlightPromptText != nil || lastAssistantMessageText?.trimmedForSurface.isEmpty == false
    }

    var spotlightAgeBadge: String {
        let age = max(0, Int(Date.now.timeIntervalSince(islandActivityDate)))

        if age < 60 {
            return "<1m"
        }

        if age < 3_600 {
            return "\(max(1, age / 60))m"
        }

        if age < 86_400 {
            return "\(max(1, age / 3_600))h"
        }

        return "\(max(1, age / 86_400))d"
    }

    /// How long the main session has actually been running, derived from
    /// `firstSeenAt` — distinct from `spotlightAgeBadge`, which measures time
    /// since the *last update* and reads as "<1m" for most running sessions.
    /// Minute granularity (AB-230); callers re-derive this from their own
    /// periodic tick rather than a dedicated high-frequency timer.
    func elapsedRunningLabel(at referenceDate: Date) -> String {
        let totalSeconds = max(0, Int(referenceDate.timeIntervalSince(firstSeenAt)))
        let totalMinutes = totalSeconds / 60

        if totalMinutes < 1 {
            return "<1m"
        }

        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours < 24 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours == 0 ? "\(days)d" : "\(days)d \(remainingHours)h"
    }

    /// Short display form of the session's model metadata, e.g.
    /// `"claude-sonnet-4-5"` → `"Sonnet 4.5"`, `"gpt-5-codex"` → `"GPT-5"`.
    /// `nil` when no model metadata is present (AB-230) — the model badge is
    /// hidden entirely in that case.
    var displayModelName: String? {
        let rawModel = claudeMetadata?.model ?? openCodeMetadata?.model ?? cursorMetadata?.model
        guard let trimmed = rawModel?.trimmedForSurface, !trimmed.isEmpty else {
            return nil
        }

        return Self.shortModelDisplayName(for: trimmed)
    }

    /// Family keywords recognized regardless of where they appear in the raw
    /// model string (e.g. both `"claude-opus-4-6"` and `"claude-4.6-opus"`).
    private static let modelFamilyDisplayNames: [String: String] = [
        "opus": "Opus",
        "sonnet": "Sonnet",
        "haiku": "Haiku",
        "fable": "Fable",
        "mythos": "Mythos",
        "gemini": "Gemini",
        "grok": "Grok",
        "llama": "Llama",
        "mistral": "Mistral",
        "qwen": "Qwen",
        "kimi": "Kimi",
        "deepseek": "DeepSeek",
        "glm": "GLM",
    ]

    static func shortModelDisplayName(for rawModel: String) -> String {
        var value = rawModel.trimmedForSurface
        guard !value.isEmpty else { return rawModel }

        // Drop a leading provider namespace, e.g. "anthropic/claude-opus-4-6".
        if let slashIndex = value.lastIndex(of: "/") {
            value = String(value[value.index(after: slashIndex)...])
        }

        let tokens = value
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !tokens.isEmpty else { return value }

        var family: String?
        var isGPTFamily = false

        for token in tokens {
            if let mapped = modelFamilyDisplayNames[token] {
                family = mapped
                break
            }
            if token == "gpt" {
                family = "GPT"
                isGPTFamily = true
                break
            }
            if token.count == 2, token.hasPrefix("o"), token.dropFirst().allSatisfy(\.isNumber) {
                family = token.uppercased()
                break
            }
        }

        guard let resolvedFamily = family else {
            return humanizedModelName(from: tokens)
        }

        // Version = the numeric tokens, in original order — but drop
        // date-like tokens (e.g. the "20260101" trailing a Claude model id).
        let version = tokens
            .filter { $0.allSatisfy(\.isNumber) && $0.count < 6 }
            .joined(separator: ".")

        if version.isEmpty {
            return resolvedFamily
        }

        return isGPTFamily ? "\(resolvedFamily)-\(version)" : "\(resolvedFamily) \(version)"
    }

    private static func humanizedModelName(from tokens: [String]) -> String {
        let filtered = tokens.filter { !($0.allSatisfy(\.isNumber) && $0.count >= 6) }
        let source = filtered.isEmpty ? tokens : filtered
        return source
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    func islandPresence(at referenceDate: Date) -> IslandSessionPresence {
        if phase == .running {
            return .running
        }

        if phase.requiresAttention {
            return .active
        }

        if referenceDate.timeIntervalSince(islandActivityDate) <= Self.islandActivityThreshold {
            return .active
        }

        return .inactive
    }

    /// v8 UI-only staleness: keep `SessionPhase.completed` unchanged, but
    /// visually fold older completed rows into the low-priority presentation.
    func isStaleCompletedForIsland(
        at referenceDate: Date,
        threshold: TimeInterval = Self.staleCompletedDisplayThreshold
    ) -> Bool {
        phase == .completed
            && referenceDate.timeIntervalSince(islandActivityDate) >= threshold
    }

    private var spotlightRunningActivityText: String? {
        guard let currentTool = currentToolName?.trimmedForSurface,
              !currentTool.isEmpty else {
            return nil
        }

        let label = Self.currentToolDisplayName(for: currentTool)
        guard let preview = currentCommandPreviewText?.trimmedForSurface,
              !preview.isEmpty else {
            return label
        }

        return "\(label) \(preview)"
    }

    var displayCurrentToolName: String? {
        guard let currentTool = currentToolName?.trimmedForSurface,
              !currentTool.isEmpty else {
            return nil
        }

        return Self.currentToolDisplayName(for: currentTool)
    }

    static func currentToolDisplayName(for toolName: String) -> String {
        switch toolName {
        case "exec_command":
            return "Bash"
        case "Bash":
            return "Bash"
        case "AskUserQuestion":
            return "Question"
        case "ExitPlanMode":
            return "Plan"
        case "apply_patch":
            return "Patch"
        case "write_stdin":
            return "Input"
        case "web_search", "tool_search":
            return "Search"
        case "image_generation", "view_image":
            return "Image"
        case "context_compaction":
            return "Compact"
        case "update_plan":
            return "Plan"
        case "request_user_input":
            return "Question"
        case "spawn_agent":
            return "Subagent"
        default:
            return humanizedToolName(toolName)
        }
    }

    private static func humanizedToolName(_ toolName: String) -> String {
        let trimmed = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrivatePrefix = String(trimmed.drop(while: { $0 == "_" }))
        let pieces = withoutPrivatePrefix
            .split(separator: "_", omittingEmptySubsequences: true)
            .map { piece -> String in
                let upper = piece.uppercased()
                if ["API", "CI", "ID", "PR", "URL"].contains(upper) {
                    return upper
                }
                return piece.prefix(1).uppercased() + piece.dropFirst().lowercased()
            }
        let label = pieces.joined(separator: " ")
        return label.isEmpty ? toolName : label
    }

    private var initialPromptText: String? {
        let prompt = initialUserPromptText?.trimmedForSurface
        guard let prompt, !prompt.isEmpty else {
            return nil
        }

        return prompt
    }

    private var latestPromptText: String? {
        let prompt = latestUserPromptText?.trimmedForSurface
        guard let prompt, !prompt.isEmpty else {
            return nil
        }

        return prompt
    }

    private var prefersLivePromptHeadline: Bool {
        isProcessAlive || phase == .running || phase.requiresAttention
    }
}

private extension String {
    var trimmedForSurface: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Narrated activity (AB-321)

/// The canonical, localizable verbs the narrated-activity layer speaks.
///
/// Every case's raw value is already the English gerund, so ``englishText`` is a
/// pure capitalization — no second table to keep in sync. Verbs localize
/// (`island.activity.verb.<case>` in all three `.strings` files); the *object*
/// half of a narration never does, because it is data (a file name, a shell
/// command, a host, a search pattern).
enum NarrationVerb: String, CaseIterable, Sendable {
    case editing
    case reading
    case running
    case searching
    case fetching
    case orchestrating
    case asking
    case planning
    case evaluating
    case navigating
    case clicking
    case typing
    case opening
    case closing
    case listing
    case creating
    case updating
    case deleting
    case sending
    case waiting
    case checking
    case capturing
    case uploading
    case downloading
    case generating
    case resolving
    case moving
    case copying
    case exporting
    case importing
    case selecting
    case scrolling
    case building
    case publishing
    case commenting
    case replying
    case working

    var localizationKey: String { "island.activity.verb.\(rawValue)" }

    /// English rendering — also the fallback when a bundle lookup misses.
    var englishText: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// A human sentence describing what an agent is doing right now, kept split
/// into the two parts themes style differently (verb dim, object bright).
///
/// This is the translation layer BRIEF §1.2 demands: the UI must narrate
/// ("Editing AppModel.swift") instead of echoing internal state
/// ("Mcp Playwright Browser Evaluate ×4").
struct NarratedActivity: Equatable, Sendable {
    /// Set when the verb came from the canonical localizable set. `nil` for
    /// verbs derived from an unknown identifier (those render in English).
    let verbToken: NarrationVerb?

    /// The verb, in English. Always non-empty.
    let verb: String

    /// The data half — never localized, `nil` when the verb says it all.
    let object: String?

    init(_ token: NarrationVerb, object: String? = nil) {
        self.verbToken = token
        self.verb = token.englishText
        self.object = Self.normalized(object)
    }

    init(rawVerb: String, object: String? = nil) {
        let trimmed = rawVerb.trimmedForSurface
        self.verbToken = trimmed.isEmpty ? NarrationVerb.working : nil
        self.verb = trimmed.isEmpty ? NarrationVerb.working.englishText : trimmed
        self.object = Self.normalized(object)
    }

    /// Joined plain string, e.g. `"Editing AppModel.swift"`.
    var text: String {
        guard let object else { return verb }
        return "\(verb) \(object)"
    }

    func localizedVerb(_ language: LanguageManager) -> String {
        guard let verbToken else { return verb }
        let resolved = language.t(verbToken.localizationKey).trimmedForSurface
        return (resolved.isEmpty || resolved == verbToken.localizationKey) ? verb : resolved
    }

    func localizedText(_ language: LanguageManager) -> String {
        let localizedVerb = localizedVerb(language)
        guard let object else { return localizedVerb }
        return "\(localizedVerb) \(object)"
    }

    private static func normalized(_ object: String?) -> String? {
        guard let trimmed = object?.trimmedForSurface, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Pure translation of `currentToolName` + `currentCommandPreviewText` into a
/// ``NarratedActivity``. Theme-agnostic and free of view code — themes opt in
/// by reading `AgentSession.narratedActivity`.
enum ActivityNarrator {
    /// Default budget for a narrated object, in characters.
    static let defaultObjectMaxLength = 40

    // MARK: Entry point

    static func narrate(
        toolName: String?,
        preview: String? = nil,
        activeSubagentCount: Int = 0,
        maxObjectLength: Int = defaultObjectMaxLength
    ) -> NarratedActivity? {
        guard let rawTool = toolName?.trimmedForSurface, !rawTool.isEmpty else {
            return nil
        }

        let preview = sanitizedPreview(preview)
        let budget = max(8, maxObjectLength)

        if let mcp = mcpComponents(of: rawTool) {
            return narrateMCP(server: mcp.server, actionTokens: mcp.actionTokens, maxObjectLength: budget)
        }

        switch rawTool.lowercased() {
        case "edit", "write", "multiedit", "apply_patch", "notebookedit", "notebook_edit",
             "edit_file", "write_file", "create_file", "str_replace_editor":
            return NarratedActivity(.editing, object: preview.map { filePathObject(from: $0, maxLength: budget) })

        case "read", "notebookread", "notebook_read", "read_file":
            return NarratedActivity(.reading, object: preview.map { filePathObject(from: $0, maxLength: budget) })

        case "bash", "exec_command", "shell", "run_command", "run_terminal_cmd":
            return NarratedActivity(.running, object: preview.map { commandObject(from: $0, maxLength: budget) })

        case "grep", "glob", "web_search", "tool_search", "search", "codebase_search":
            return NarratedActivity(.searching, object: preview.map { quotedPatternObject(from: $0, maxLength: budget) })

        case "webfetch", "web_fetch", "fetch":
            return NarratedActivity(.fetching, object: preview.map { hostObject(from: $0, maxLength: budget) })

        case "task", "spawn_agent":
            return NarratedActivity(
                .orchestrating,
                object: subagentObject(count: activeSubagentCount, preview: preview, maxLength: budget)
            )

        case "askuserquestion", "request_user_input":
            return NarratedActivity(.asking)

        case "exitplanmode", "update_plan":
            return NarratedActivity(.planning)

        default:
            break
        }

        // Unknown tool: keep today's humanized noun as the leading token and
        // hang the preview off it. Never empty, never a crash.
        let noun = AgentSession.currentToolDisplayName(for: rawTool)
        return NarratedActivity(rawVerb: noun, object: preview.map { truncatedTail($0, maxLength: budget) })
    }

    // MARK: MCP

    /// Splits `mcp__<server>__<action>` — or its title-cased echo
    /// (`"Mcp Playwright Browser Evaluate"`) — into server + action tokens.
    static func mcpComponents(of toolName: String) -> (server: String, actionTokens: [String])? {
        let parts: [String]
        if toolName.contains("__") {
            parts = toolName.components(separatedBy: "__").filter { !$0.isEmpty }
        } else {
            parts = toolName.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        }

        guard let first = parts.first, first.lowercased() == "mcp", parts.count >= 2 else {
            return nil
        }

        let actionTokens = parts
            .dropFirst(2)
            .flatMap { $0.split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init) }
            .flatMap(camelCaseTokens(in:))
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }

        return (parts[1], actionTokens)
    }

    private static func narrateMCP(
        server: String,
        actionTokens: [String],
        maxObjectLength: Int
    ) -> NarratedActivity {
        var verbToken: NarrationVerb?
        var derivedVerb: String?
        var contextTokens: [String] = []

        if let first = actionTokens.first, let mapped = mcpVerbLexicon[first] {
            verbToken = mapped
            contextTokens = Array(actionTokens.dropFirst())
        } else if let last = actionTokens.last, let mapped = mcpVerbLexicon[last] {
            verbToken = mapped
            contextTokens = Array(actionTokens.dropLast())
        } else if let last = actionTokens.last {
            // Unknown action word — the ticket's rule: gerund of the last segment.
            derivedVerb = capitalizedFirst(gerund(last))
            contextTokens = Array(actionTokens.dropLast())
        }

        let object = mcpObject(contextTokens: contextTokens, server: server, maxObjectLength: maxObjectLength)

        if let verbToken {
            return NarratedActivity(verbToken, object: object)
        }
        if let derivedVerb {
            return NarratedActivity(rawVerb: derivedVerb, object: object)
        }
        return NarratedActivity(.working, object: object)
    }

    private static func mcpObject(contextTokens: [String], server: String, maxObjectLength: Int) -> String? {
        guard !contextTokens.isEmpty else {
            return truncatedTail(serverLocationPhrase(for: server), maxLength: maxObjectLength)
        }

        let phrase = contextTokens.joined(separator: " ")
        if contextTokens.count == 1, locationNouns.contains(contextTokens[0]) {
            return truncatedTail("in the \(phrase)", maxLength: maxObjectLength)
        }
        return truncatedTail(phrase, maxLength: maxObjectLength)
    }

    /// Action words that map onto a canonical (and therefore localizable) verb.
    static let mcpVerbLexicon: [String: NarrationVerb] = [
        "get": .reading, "read": .reading, "describe": .reading,
        // NOTE: ambiguous nouns-that-are-also-verbs ("pull" in `pull_request`)
        // stay out of the lexicon so the trailing-verb rule can win.
        "fetch": .fetching, "download": .downloading,
        "list": .listing, "ls": .listing,
        "search": .searching, "find": .searching, "query": .searching, "grep": .searching,
        "create": .creating, "add": .creating, "new": .creating, "install": .creating,
        "update": .updating, "modify": .updating, "set": .updating, "resize": .updating, "sync": .updating,
        "edit": .editing, "write": .editing, "patch": .editing, "replace": .editing,
        "delete": .deleting, "remove": .deleting, "drop": .deleting,
        "run": .running, "exec": .running, "execute": .running, "invoke": .running, "call": .running,
        "evaluate": .evaluating, "eval": .evaluating,
        "navigate": .navigating, "goto": .navigating, "visit": .navigating,
        "open": .opening, "close": .closing,
        "click": .clicking, "press": .clicking, "tap": .clicking,
        "type": .typing, "fill": .typing, "input": .typing,
        "screenshot": .capturing, "capture": .capturing, "snapshot": .capturing,
        "upload": .uploading, "send": .sending, "post": .sending,
        "wait": .waiting, "check": .checking, "verify": .checking, "validate": .checking,
        "generate": .generating, "render": .generating,
        "resolve": .resolving, "parse": .resolving,
        "move": .moving, "drag": .moving, "copy": .copying, "duplicate": .copying,
        "export": .exporting, "import": .importing,
        "select": .selecting, "hover": .selecting, "scroll": .scrolling,
        "build": .building, "compile": .building,
        "publish": .publishing, "deploy": .publishing,
        "comment": .commenting, "reply": .replying,
    ]

    /// Context nouns that read as a *place* ("in the browser") rather than an
    /// object ("pull request").
    static let locationNouns: Set<String> = [
        "browser", "page", "tab", "window", "terminal", "shell", "editor",
        "canvas", "dashboard", "workspace", "document", "sheet", "board", "chat",
    ]

    private static let browserServers: Set<String> = [
        "playwright", "puppeteer", "chrome", "chromium", "browser", "browserbase", "selenium", "webkit",
    ]

    private static let serverDisplayNames: [String: String] = [
        "github": "GitHub", "gitlab": "GitLab", "openai": "OpenAI",
        "aws": "AWS", "gcp": "GCP", "npm": "npm", "postgres": "Postgres",
    ]

    static func serverLocationPhrase(for server: String) -> String {
        let normalized = server.lowercased()
        if browserServers.contains(normalized) {
            return "in the browser"
        }
        return "in \(humanizedServerName(server))"
    }

    private static func humanizedServerName(_ server: String) -> String {
        if let known = serverDisplayNames[server.lowercased()] {
            return known
        }
        let words = server
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { capitalizedFirst(String($0)) }
        let joined = words.joined(separator: " ")
        return joined.isEmpty ? server : joined
    }

    // MARK: Object builders

    /// Strips the shell-prompt affordance the views add (`"$ "`) and folds all
    /// whitespace runs — including newlines — into single spaces.
    static func sanitizedPreview(_ preview: String?) -> String? {
        guard var value = preview?.trimmedForSurface, !value.isEmpty else { return nil }

        while value.hasPrefix("$ ") || value.hasPrefix("$\t") {
            value = String(value.dropFirst(2)).trimmedForSurface
        }

        let collapsed = value
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    static func filePathObject(from preview: String, maxLength: Int) -> String {
        let tokens = preview.split(separator: " ").map(String.init)

        if tokens.count == 1 {
            return middleTruncated(lastPathComponent(of: tokens[0]), maxLength: maxLength)
        }

        if let pathToken = tokens.first(where: { $0.contains("/") || looksLikeFileName($0) }) {
            return middleTruncated(lastPathComponent(of: pathToken), maxLength: maxLength)
        }

        return truncatedTail(preview, maxLength: maxLength)
    }

    static func commandObject(from preview: String, maxLength: Int) -> String {
        truncatedTail(preview, maxLength: maxLength)
    }

    static func quotedPatternObject(from preview: String, maxLength: Int) -> String {
        let inner = truncatedTail(preview, maxLength: max(3, maxLength - 2))
        return "\"\(inner)\""
    }

    static func hostObject(from preview: String, maxLength: Int) -> String {
        if let url = URL(string: preview), let host = url.host, !host.isEmpty {
            return middleTruncated(host, maxLength: maxLength)
        }

        var value = preview
        if let schemeRange = value.range(of: "://") {
            value = String(value[schemeRange.upperBound...])
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        value = value.trimmedForSurface
        return middleTruncated(value.isEmpty ? preview : value, maxLength: maxLength)
    }

    static func subagentObject(count: Int, preview: String?, maxLength: Int) -> String? {
        if count > 0 {
            return count == 1 ? "1 subagent" : "\(count) subagents"
        }
        guard let preview else { return nil }
        return truncatedTail(preview, maxLength: maxLength)
    }

    // MARK: Truncation

    /// Trailing truncation on a word boundary — used for prose-ish objects
    /// (commands, task descriptions) where the head carries the meaning.
    static func truncatedTail(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength, maxLength > 1 else { return value }

        let words = value.split(separator: " ").map(String.init)
        var kept: [String] = []
        var used = 1 // the ellipsis

        for word in words {
            let cost = kept.isEmpty ? word.count : word.count + 1
            if used + cost > maxLength { break }
            used += cost
            kept.append(word)
        }

        guard !kept.isEmpty else {
            return middleTruncatedWord(words.first ?? value, maxLength: maxLength)
        }
        return kept.joined(separator: " ") + "…"
    }

    /// Middle truncation preserving the basename — used for paths and file
    /// names, where the tail carries the meaning.
    static func middleTruncated(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength, maxLength > 1 else { return value }

        if value.contains("/") {
            let components = value.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            if components.count > 2, let head = components.first {
                var tail: [String] = []
                var used = head.count + 2 + 1 // "head/" + "…/"
                for component in components.dropFirst().reversed() {
                    let cost = component.count + 1
                    if used + cost > maxLength, !tail.isEmpty { break }
                    tail.insert(component, at: 0)
                    used += cost
                }
                let candidate = ([head, "…"] + tail).joined(separator: "/")
                if candidate.count <= maxLength { return candidate }
            }
            let basename = components.last ?? value
            return basename.count <= maxLength ? basename : middleTruncatedWord(basename, maxLength: maxLength)
        }

        return middleTruncatedWord(value, maxLength: maxLength)
    }

    /// Middle-truncates a single token on word boundaries (camel humps, `-`,
    /// `_`, `.`) so the extension and the leading words both survive.
    static func middleTruncatedWord(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength, maxLength > 1 else { return value }

        let chunks = wordChunks(value)
        if chunks.count > 1 {
            var head: [String] = []
            var tail: [String] = []
            var used = 1 // the ellipsis
            var low = 0
            var high = chunks.count - 1
            var takeHead = true

            while low <= high {
                let index = takeHead ? low : high
                let cost = chunks[index].count
                if used + cost > maxLength { break }
                used += cost
                if takeHead {
                    head.append(chunks[index])
                    low += 1
                } else {
                    tail.insert(chunks[index], at: 0)
                    high -= 1
                }
                takeHead.toggle()
            }

            if !head.isEmpty || !tail.isEmpty {
                let candidate = head.joined() + "…" + tail.joined()
                if candidate.count <= maxLength { return candidate }
            }
        }

        // Single unbreakable token longer than the budget — nothing to break on.
        return String(value.prefix(max(1, maxLength - 1))) + "…"
    }

    /// Splits on camel humps while keeping `-`, `_`, `.`, `/` and spaces as
    /// their own chunks so a reassembled string stays faithful.
    static func wordChunks(_ value: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        var previous: Character?

        for character in value {
            if character == "_" || character == "-" || character == "." || character == " " || character == "/" {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                chunks.append(String(character))
                previous = character
                continue
            }

            if let previous, previous.isLowercase || previous.isNumber, character.isUppercase, !current.isEmpty {
                chunks.append(current)
                current = ""
            }

            current.append(character)
            previous = character
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    // MARK: Word helpers

    static func camelCaseTokens(in value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var previous: Character?

        for character in value {
            if let previous, previous.isLowercase || previous.isNumber, character.isUppercase, !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            current.append(character)
            previous = character
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// English gerund of an arbitrary lowercase word — only reached for MCP
    /// actions outside ``mcpVerbLexicon``.
    static func gerund(_ word: String) -> String {
        let value = word.lowercased()
        guard value.count > 2 else { return value + "ing" }

        if value.count > 4, value.hasSuffix("ing") { return value }
        if value.hasSuffix("ie") { return String(value.dropLast(2)) + "ying" }
        if value.hasSuffix("e"), !value.hasSuffix("ee"), !value.hasSuffix("oe"), !value.hasSuffix("ye") {
            return String(value.dropLast()) + "ing"
        }

        let characters = Array(value)
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        if characters.count <= 4, characters.count >= 3 {
            let last = characters[characters.count - 1]
            let middle = characters[characters.count - 2]
            let first = characters[characters.count - 3]
            if !vowels.contains(last), !"wxy".contains(last), vowels.contains(middle), !vowels.contains(first) {
                return value + String(last) + "ing"
            }
        }

        return value + "ing"
    }

    static func capitalizedFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }

    private static func lastPathComponent(of value: String) -> String {
        var trimmed = value
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        guard trimmed.contains("/") else { return trimmed }
        let component = trimmed.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init)
        return component ?? trimmed
    }

    private static func looksLikeFileName(_ token: String) -> Bool {
        guard let dot = token.lastIndex(of: "."), dot != token.startIndex else { return false }
        let ext = token[token.index(after: dot)...]
        return !ext.isEmpty && ext.count <= 5 && ext.allSatisfy(\.isLetter)
    }
}

extension AgentSession {
    /// The narrated form of what this session is doing right now — verb + object
    /// kept apart so themes can style them independently.
    ///
    /// Purely additive: `spotlightActivityLineText`, `spotlightSecondaryText`
    /// and `currentToolDisplayName` are untouched, so the shipped themes keep
    /// their existing rendering until they opt in.
    var narratedActivity: NarratedActivity? {
        ActivityNarrator.narrate(
            toolName: currentToolName,
            preview: currentCommandPreviewText,
            activeSubagentCount: claudeMetadata?.activeSubagents.count ?? 0
        )
    }

    /// Tuple form of ``narratedActivity`` for call sites that only need the two
    /// styleable parts.
    var narratedActivityLine: (verb: String, object: String?)? {
        guard let narratedActivity else { return nil }
        return (narratedActivity.verb, narratedActivity.object)
    }

    /// Joined plain string, e.g. `"Editing AppModel.swift"`.
    var narratedActivityLineText: String? {
        narratedActivity?.text
    }

    /// Joined string with the verb localized for `language`.
    func narratedActivityLineText(_ language: LanguageManager) -> String? {
        narratedActivity?.localizedText(language)
    }
}
