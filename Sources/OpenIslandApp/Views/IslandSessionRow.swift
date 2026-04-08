import MarkdownUI
import OpenIslandCore
import SwiftUI

// MARK: - Session row (opened state)

struct IslandSessionRow: View {
    let session: TrackedSession
    let referenceDate: Date
    var isActionable: Bool = false
    var useDrawingGroup: Bool = true
    var isInteractive: Bool = true
    var showDebugIDs: Bool = false
    var lang: LanguageManager = .shared
    var onApprove: ((ClaudePermissionMode?) -> Void)?
    var onAnswer: ((QuestionPromptResponse) -> Void)?
    let onJump: () -> Void

    @State private var isHighlighted = false
    @State private var isManuallyExpanded = false

    var body: some View {
        rowBody(referenceDate: referenceDate)
    }

    private func rowBody(referenceDate: Date) -> some View {
        let rawPresence = session.islandPresence(at: referenceDate)
        let presence = (rawPresence == .inactive && isManuallyExpanded) ? .active : rawPresence
        let showsExpandedContent = presence != .inactive
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                brandMark(for: presence)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(session.spotlightHeadlineText)
                            .font(.system(size: isActionable ? 15 : 14, weight: .semibold))
                            .foregroundStyle(headlineColor(for: presence))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            compactBadge(session.tool.displayName, presence: presence, variant: .tool)
                            if session.isRemote {
                                compactBadge("SSH", presence: presence, icon: "network")
                            }
                            if let terminalBadge = session.spotlightTerminalBadge {
                                compactBadge(terminalBadge, presence: presence)
                            }
                            compactBadge(session.spotlightAgeBadge, presence: presence)
                        }
                    }

                    if showsExpandedContent || isActionable,
                       let promptLine = session.spotlightPromptLineText ?? expandedPromptLineText {
                        Text(promptLine)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    if showsExpandedContent || isActionable,
                       let activityLine = session.spotlightActivityLineText ?? expandedActivityLineText {
                        Text(activityLine)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(activityColor(for: presence).opacity(0.94))
                            .lineLimit(1)
                    }

                    // Debug: session ID + terminal ID
                    if showDebugIDs {
                        debugIDLine
                    }

                    if showsExpandedContent,
                       !session.metadata.activeSubagents.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 9, weight: .medium))
                                Text(lang.t("subagents.title", session.metadata.activeSubagents.count))
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(.cyan.opacity(0.8))

                            ForEach(session.metadata.activeSubagents, id: \.agentID) { sub in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(sub.summary != nil
                                            ? Color(red: 0.29, green: 0.86, blue: 0.46)
                                            : Color(red: 0.34, green: 0.61, blue: 0.99))
                                        .frame(width: 6, height: 6)
                                    Text(sub.agentType ?? sub.agentID)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                    if let desc = sub.taskDescription {
                                        Text("(\(desc))")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if sub.summary != nil {
                                        Text(lang.t("subagents.completed"))
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.4))
                                    } else if let started = sub.startedAt {
                                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                            Text(subagentElapsed(since: started, at: timeline.date))
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.4))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if showsExpandedContent,
                       !session.metadata.activeTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(taskSummary(session.metadata.activeTasks))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                            ForEach(session.metadata.activeTasks) { task in
                                HStack(spacing: 5) {
                                    taskStatusIcon(task.status)
                                    Text(task.title)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(task.status == .completed
                                            ? .white.opacity(0.4)
                                            : .white.opacity(0.7))
                                        .strikethrough(task.status == .completed)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, isActionable ? 16 : 16)
            .padding(.vertical, isActionable ? 14 : 14)

            if isActionable {
                actionableBody
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: isActionable ? 24 : 22, style: .continuous)
                .fill(isHighlighted ? Color.white.opacity(isActionable ? 0.06 : 0.05) : Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isActionable ? 24 : 22, style: .continuous)
                .strokeBorder(actionableBorderColor)
        )
        .shadow(color: isHighlighted ? .black.opacity(0.24) : .clear, radius: 8, y: 6)
        .overlay(
            Group {
                if !isActionable {
                    Rectangle()
                        .fill(Color.white.opacity(isHighlighted ? 0 : 0.02))
                        .frame(height: 1)
                }
            },
            alignment: .bottom
        )
        .modifier(ConditionalDrawingGroup(enabled: useDrawingGroup && !isActionable))
        .contentShape(RoundedRectangle(cornerRadius: isActionable ? 24 : 22, style: .continuous))
        .onTapGesture(perform: handlePrimaryTap)
        .onHover { hovering in
            guard isInteractive else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                isHighlighted = hovering
            }
        }
        .onChange(of: isInteractive) { _, interactive in
            if !interactive {
                isManuallyExpanded = false
                isHighlighted = false
            }
        }
    }

    private var debugIDLine: some View {
        let sid = String(session.id.prefix(8))
        let tid = String((session.terminal?.terminalSessionID ?? "none").prefix(8))
        let label = "sid: " + sid + "  tid: " + tid
        return Text(label)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.3))
            .lineLimit(1)
            .textSelection(.enabled)
    }

    private var actionableBorderColor: Color {
        if isActionable {
            return actionableStatusTint.opacity(isHighlighted ? 0.45 : 0.28)
        }
        return isHighlighted ? .white.opacity(0.24) : .white.opacity(0.04)
    }

    private var actionableStatusTint: Color {
        switch session.phase {
        case .waitingForApproval:
            .orange
        case .waitingForAnswer:
            .yellow
        case .running:
            Color(red: 0.34, green: 0.61, blue: 0.99)
        case .completed:
            Color(red: 0.29, green: 0.86, blue: 0.46)
        }
    }

    @ViewBuilder
    private var actionableBody: some View {
        switch session.phase {
        case .waitingForApproval:
            approvalActionBody
        case .waitingForAnswer:
            questionActionBody
        case .completed:
            completionActionBody
        case .running:
            EmptyView()
        }
    }

    // MARK: - Approval action area

    private var approvalActionBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
                Text(commandLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(commandPreviewText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let path = session.permissionRequest?.affectedPath.trimmedForNotificationCard,
                   !path.isEmpty {
                    Text(path)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.08, blue: 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.orange.opacity(0.18))
            )

            HStack(spacing: 8) {
                Button(lang.t("approval.manual")) { onApprove?(.default) }
                    .buttonStyle(IslandWideButtonStyle(kind: .secondary))
                Button(lang.t("approval.autoAcceptEdits")) { onApprove?(.acceptEdits) }
                    .buttonStyle(IslandWideButtonStyle(kind: .warning))
                Button(lang.t("approval.autoBypassPermissions")) { onApprove?(.bypassPermissions) }
                    .buttonStyle(IslandWideButtonStyle(kind: .danger))
            }
        }
    }

    // MARK: - Question action area

    private var questionActionBody: some View {
        StructuredQuestionPromptView(
            prompt: session.questionPrompt,
            lang: lang,
            onAnswer: { onAnswer?($0) }
        )
    }

    // MARK: - Completion action area

    private var completionActionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(completionPromptLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(lang.t("completion.done"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.29, green: 0.86, blue: 0.46).opacity(0.96))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(height: 1)

            AutoHeightScrollView(maxHeight: 260) {
                Markdown(completionMessageText)
                    .markdownTheme(.completionCard)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    // MARK: - Actionable helpers

    private var completionPromptLabel: String {
        if let prompt = session.latestPromptText?.trimmedForNotificationCard, !prompt.isEmpty {
            return "You: \(prompt)"
        }
        return "You:"
    }

    private var completionMessageText: String {
        if let text = session.lastAssistantMessageText?.trimmedForNotificationCard, !text.isEmpty {
            return text
        }
        return session.summary
    }

    private var commandLabel: String {
        switch session.currentToolName {
        case "exec_command", "Bash": return "Bash"
        case "AskUserQuestion": return "Question"
        case "ExitPlanMode": return "Plan"
        case "apply_patch": return "Patch"
        case "write_stdin": return "Input"
        case let value?: return value.capitalized
        case nil: return "Command"
        }
    }

    private var commandPreviewText: String {
        let preview = session.metadata.currentToolInputPreview?.trimmedForNotificationCard
        if let preview, !preview.isEmpty {
            return "$ \(preview)"
        }
        return session.permissionRequest?.summary.trimmedForNotificationCard ?? session.summary.trimmedForNotificationCard
    }

    private var allowTitle: String {
        let title = session.permissionRequest?.primaryActionTitle.trimmedForNotificationCard
        if title == nil || title == "Allow" {
            return "Allow Once"
        }
        return title ?? "Allow Once"
    }

    private var denyTitle: String {
        session.permissionRequest?.secondaryActionTitle.trimmedForNotificationCard ?? "Deny"
    }

    private func subagentElapsed(since start: Date, at now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(start))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes)m \(secs)s"
    }

    private func taskSummary(_ tasks: [ClaudeTaskInfo]) -> String {
        let done = tasks.filter { $0.status == .completed }.count
        let prog = tasks.filter { $0.status == .inProgress }.count
        let pend = tasks.filter { $0.status == .pending }.count
        return lang.t("tasks.summary", done, prog, pend)
    }

    @ViewBuilder
    private func taskStatusIcon(_ status: ClaudeTaskInfo.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
        case .inProgress:
            Circle()
                .fill(Color(red: 0.34, green: 0.61, blue: 0.99))
                .frame(width: 6, height: 6)
        case .pending:
            Circle()
                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                .frame(width: 6, height: 6)
        }
    }

    private func brandMark(for presence: IslandSessionPresence) -> some View {
        OpenIslandBrandMark(
            size: 22,
            tint: statusTint(for: presence),
            animation: rowAnimation(for: presence)
        )
        .padding(.top, 2)
    }

    private func rowAnimation(for presence: IslandSessionPresence) -> ScoutAnimation {
        if session.phase.requiresAttention {
            return .permissionAlert
        }
        if presence == .running {
            return .active
        }
        return .idle
    }

    /// Prompt line for manually expanded inactive rows (bypasses time-based filter).
    private var expandedPromptLineText: String? {
        guard isManuallyExpanded, let prompt = session.spotlightPromptText else { return nil }
        return "You: \(prompt)"
    }

    /// Activity line for manually expanded inactive rows (bypasses time-based filter).
    private var expandedActivityLineText: String? {
        guard isManuallyExpanded else { return nil }
        let trimmed = session.lastAssistantMessageText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let assistantMessage = trimmed, !assistantMessage.isEmpty {
            return assistantMessage
        }
        return session.jumpTarget != nil ? "Ready" : "Completed"
    }

    private func handlePrimaryTap() {
        let rawPresence = session.islandPresence(at: referenceDate)
        print("[IslandSessionRow] tap — presence=\(rawPresence) expanded=\(isManuallyExpanded) session=\(session.id.prefix(8))")
        if rawPresence == .inactive && !isManuallyExpanded {
            withAnimation(.easeInOut(duration: 0.2)) {
                isManuallyExpanded = true
            }
        } else {
            print("[IslandSessionRow] calling onJump")
            onJump()
        }
    }

    private enum BadgeVariant {
        case standard
        case tool
    }

    private func compactBadge(
        _ title: String,
        presence: IslandSessionPresence,
        icon: String? = nil,
        variant: BadgeVariant = .standard
    ) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 7.5, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(variant == .tool ? toolBadgeColor(title) : badgeTextColor(for: presence))
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(Color(red: 0.14, green: 0.14, blue: 0.15), in: Capsule())
    }

    private func toolBadgeColor(_ tool: String) -> Color {
        switch tool.lowercased() {
        case "claude":
            return Color(red: 0.89, green: 0.55, blue: 0.42) // coral
        case "codex":
            return Color(red: 0.42, green: 0.78, blue: 0.55) // green
        default:
            return .white.opacity(0.56)
        }
    }

    @ViewBuilder
    private func rowActionButtons(presence: IslandSessionPresence) -> some View {
        let tint = badgeTextColor(for: presence)

        Button {
            onJump()
        } label: {
            HStack(spacing: 2) {
                if let shortcut = jumpShortcutLabel {
                    Text(shortcut)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background(Color(red: 0.14, green: 0.14, blue: 0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var jumpShortcutLabel: String? {
        guard let terminal = session.spotlightTerminalBadge else { return nil }
        switch terminal.lowercased() {
        case "ghostty": return "^G"
        case "iterm", "iterm2": return "^I"
        case "terminal": return "^T"
        case "warp": return "^W"
        case "wezterm": return "^Z"
        default: return nil
        }
    }

    private func headlineColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? .white.opacity(0.78) : .white
    }

    private func badgeTextColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? .white.opacity(0.42) : .white.opacity(0.56)
    }

    private func statusTint(for presence: IslandSessionPresence) -> Color {
        if session.phase == .waitingForApproval {
            return .orange.opacity(0.94)
        }

        if session.phase == .waitingForAnswer {
            return .yellow.opacity(0.96)
        }

        switch presence {
        case .running:
            return Color(red: 0.34, green: 0.61, blue: 0.99)
        case .active:
            return Color(red: 0.29, green: 0.86, blue: 0.46)
        case .inactive:
            return .white.opacity(0.38)
        }
    }

    private func activityColor(for presence: IslandSessionPresence) -> Color {
        switch session.spotlightActivityTone {
        case .attention:
            .orange.opacity(0.94)
        case .live:
            statusTint(for: presence)
        case .idle:
            .white.opacity(0.46)
        case .ready:
            presence == .inactive ? .white.opacity(0.46) : statusTint(for: presence)
        }
    }
}

// MARK: - Structured question prompt

struct StructuredQuestionPromptView: View {
    let prompt: QuestionPrompt?
    var lang: LanguageManager = .shared
    let onAnswer: (QuestionPromptResponse) -> Void

    @State private var selections: [String: Set<String>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsPromptTitle {
                Text(promptTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.yellow.opacity(0.96))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if structuredQuestions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(prompt?.options.prefix(3) ?? [], id: \.self) { option in
                        Button(option) {
                            onAnswer(QuestionPromptResponse(answer: option))
                        }
                        .buttonStyle(IslandWideButtonStyle(kind: .secondary))
                    }
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(structuredQuestions, id: \.question) { question in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(question.header)
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))

                                Text(question.question)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 8) {
                                    ForEach(question.options.prefix(4), id: \.label) { option in
                                        Button(option.label) {
                                            toggle(option: option.label, for: question)
                                        }
                                        .buttonStyle(
                                            IslandWideButtonStyle(
                                                kind: selectedLabels(for: question).contains(option.label) ? .primary : .secondary
                                            )
                                        )
                                    }
                                }
                            }
                        }

                        Button(lang.t("question.submit")) {
                            onAnswer(QuestionPromptResponse(answers: answerMap))
                        }
                        .buttonStyle(IslandWideButtonStyle(kind: .primary))
                        .disabled(!hasCompleteSelection)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.06))
        )
    }

    private var structuredQuestions: [QuestionPromptItem] {
        prompt?.questions ?? []
    }

    private var promptTitle: String {
        prompt?.title.trimmedForNotificationCard ?? lang.t("question.answerNeeded")
    }

    private var showsPromptTitle: Bool {
        guard !promptTitle.isEmpty else {
            return false
        }

        guard structuredQuestions.count == 1,
              let questionTitle = structuredQuestions.first?.question.trimmedForNotificationCard else {
            return true
        }

        return questionTitle.caseInsensitiveCompare(promptTitle) != .orderedSame
    }

    private var answerMap: [String: String] {
        Dictionary(uniqueKeysWithValues: structuredQuestions.compactMap { question in
            let selected = selectedLabels(for: question)
            guard !selected.isEmpty else {
                return nil
            }

            return (question.question, selected.sorted().joined(separator: ", "))
        })
    }

    private var hasCompleteSelection: Bool {
        structuredQuestions.allSatisfy { !selectedLabels(for: $0).isEmpty }
    }

    private func selectedLabels(for question: QuestionPromptItem) -> Set<String> {
        selections[question.question] ?? []
    }

    private func toggle(option: String, for question: QuestionPromptItem) {
        var selected = selections[question.question] ?? []

        if question.multiSelect {
            if selected.contains(option) {
                selected.remove(option)
            } else {
                selected.insert(option)
            }
        } else {
            if selected.contains(option) {
                selected.removeAll()
            } else {
                selected = [option]
            }
        }

        selections[question.question] = selected
    }
}

// MARK: - String helper

extension String {
    var trimmedForNotificationCard: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
