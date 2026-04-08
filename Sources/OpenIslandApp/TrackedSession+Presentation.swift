import Foundation
import OpenIslandCore

// MARK: - TrackedSession Presentation Extension

extension TrackedSession {
    private static let collapsedDetailAgeThreshold: TimeInterval = 20 * 60
    private static let islandActivityThreshold: TimeInterval = 20 * 60

    // MARK: Core activity date

    var islandActivityDate: Date {
        lastActivityAt
    }

    // MARK: Jump target

    /// Synthesises a JumpTarget from the terminal attachment info and working directory.
    var jumpTarget: JumpTarget? {
        guard let terminal else {
            return nil
        }

        let workspaceName: String
        if let dir = workingDirectory {
            let lastComponent = (dir as NSString).lastPathComponent
            workspaceName = lastComponent.isEmpty ? dir : lastComponent
        } else {
            workspaceName = displayName
        }

        return JumpTarget(
            terminalApp: terminal.app,
            workspaceName: workspaceName,
            paneTitle: workspaceName,
            workingDirectory: workingDirectory,
            terminalSessionID: terminal.terminalSessionID,
            terminalTTY: terminal.tty
        )
    }

    // MARK: Current tool / last assistant message

    var currentToolName: String? {
        metadata.currentTool
    }

    var lastAssistantMessageText: String? {
        metadata.lastAssistantMessage
    }

    // MARK: Prompt text helpers

    var initialPromptText: String? {
        let prompt = metadata.initialPrompt?.trimmedForSurface
        guard let prompt, !prompt.isEmpty else { return nil }
        return prompt
    }

    var latestPromptText: String? {
        let prompt = metadata.lastPrompt?.trimmedForSurface
        guard let prompt, !prompt.isEmpty else { return nil }
        return prompt
    }

    // MARK: Spotlight primary / secondary

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

        if let currentTool = currentToolName?.trimmedForSurface,
           !currentTool.isEmpty {
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

    // MARK: Spotlight workspace / headline

    var spotlightWorkspaceName: String {
        if let workspaceName = jumpTarget?.workspaceName.trimmedForSurface,
           !workspaceName.isEmpty {
            return workspaceName
        }

        let trimmedTitle = displayName.trimmedForSurface
        let pieces = trimmedTitle.split(separator: "·", maxSplits: 1).map {
            String($0).trimmedForSurface
        }
        if pieces.count == 2, !pieces[1].isEmpty {
            return pieces[1]
        }

        return trimmedTitle
    }

    var spotlightWorktreeBranch: String? {
        metadata.worktreeBranch
    }

    var spotlightHeadlineText: String {
        var headline = spotlightWorkspaceName

        if let branch = spotlightWorktreeBranch {
            headline += " (\(branch))"
        }

        if let title = customTitle?.trimmedForSurface, !title.isEmpty {
            return "\(headline) - \(title)"
        }

        return headline
    }

    var spotlightHeadlinePromptText: String? {
        initialPromptText ?? latestPromptText
    }

    // MARK: Spotlight prompt lines

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

    var notificationHeaderPromptLineText: String? {
        guard phase != .completed else {
            return nil
        }

        return spotlightPromptLineText
    }

    // MARK: Spotlight activity line / running activity

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
            return spotlightPromptLineText == nil ? "Running" : "Input"
        case .waitingForApproval:
            return permissionRequest?.summary.trimmedForSurface ?? "Approval needed"
        case .waitingForAnswer:
            return questionPrompt?.title.trimmedForSurface ?? "Answer needed"
        case .completed:
            if let assistantMessage = lastAssistantMessageText?.trimmedForSurface,
               !assistantMessage.isEmpty {
                return assistantMessage
            }

            return jumpTarget != nil ? "Ready" : "Completed"
        }
    }

    private var spotlightRunningActivityText: String? {
        guard let currentTool = currentToolName?.trimmedForSurface,
              !currentTool.isEmpty else {
            return nil
        }

        let label = currentToolDisplayName(for: currentTool)
        guard let preview = metadata.currentToolInputPreview?.trimmedForSurface,
              !preview.isEmpty else {
            return label
        }

        return "\(label) \(preview)"
    }

    private func currentToolDisplayName(for toolName: String) -> String {
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
        default:
            return toolName
        }
    }

    // MARK: Spotlight activity tone

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

    // MARK: Spotlight detail lines visibility

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

    // MARK: Spotlight badges

    var spotlightAgeBadge: String {
        spotlightAgeBadge(at: .now)
    }

    func spotlightAgeBadge(at referenceDate: Date) -> String {
        let age = max(0, Int(referenceDate.timeIntervalSince(lastActivityAt)))

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

    var spotlightToolBadge: String {
        tool.displayName
    }

    var spotlightTerminalBadge: String? {
        terminal?.app
    }

    /// Short model identifier for display (e.g. "claude-opus-4-5" → "opus-4-5").
    /// Returns nil if no model is set.
    var spotlightModelBadge: String? {
        guard let model = metadata.model, !model.isEmpty else { return nil }
        // Strip common "claude-" prefix for brevity.
        if model.hasPrefix("claude-") {
            return String(model.dropFirst("claude-".count))
        }
        return model
    }

    /// Warning badge when the session runs with elevated permissions.
    /// Returns nil for normal/default permission modes.
    var spotlightPermissionModeBadge: String? {
        guard let mode = metadata.permissionMode else { return nil }
        switch mode {
        case .bypassPermissions, .dontAsk:
            return "Auto-approve"
        case .acceptEdits:
            return "Accept edits"
        case .plan:
            return "Plan mode"
        case .default:
            return nil
        }
    }

    var spotlightTrackingLabel: String? {
        guard let path = transcriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    // MARK: Spotlight status / current tool labels

    var spotlightCurrentToolLabel: String? {
        guard let currentTool = currentToolName?.trimmedForSurface,
              !currentTool.isEmpty else {
            return nil
        }

        return currentTool
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

    // MARK: Subagent labels

    var spotlightSubagentLabel: String? {
        guard !metadata.activeSubagents.isEmpty else {
            return nil
        }
        return "Subagents (\(metadata.activeSubagents.count))"
    }

    // MARK: Island presence

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
}

// MARK: - String helpers

private extension String {
    var trimmedForSurface: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
