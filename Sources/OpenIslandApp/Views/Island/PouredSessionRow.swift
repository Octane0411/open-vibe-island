import AppKit
import SwiftUI
import OpenIslandCore

/// Poured Island's session row (AB-302, poured 3/5).
///
/// The glass re-skin of `IslandSessionRow` for every *non-actionable* row
/// state — collapsed, running, done, idle/stale — across the `.list` and
/// `.notification` presentations. Status is expressed as luminous glow rather
/// than a chip: a running row carries a breathing green dot (static under
/// Reduce Motion), a done row settles to a quiet check, and an idle row
/// recedes into the material; hover lifts the row with a lighter glass tint in
/// `.list` only.
///
/// **Actionable bodies stay Classic this slice.** The approval / question /
/// completion interiors — and therefore the whole actionable row that wraps
/// them — route to `IslandSessionRow` until the poured 4/5 actionable surfaces
/// land (AB-303). `isActionable` is the seam: `true` (a permission/question
/// phase, the auto-expanded completion card, or the notification card, which
/// always passes `true`) delegates to Classic; `false` renders the glass row
/// below. The display rules (AB-282…286), grouped VoiceOver summary, type
/// scaling and Increase Contrast behaviour are reproduced verbatim from
/// Classic so the two rows stay interchangeable inside one list.
struct PouredSessionRow: View {
    let session: AgentSession
    var stateIndicator: IslandSessionStateIndicator = .animatedDot
    var completedStaleThreshold: TimeInterval = AgentSession.staleCompletedDisplayThreshold
    var isActionable: Bool = false
    var useDrawingGroup: Bool = true
    var isInteractive: Bool = true
    /// Hover highlight, owned by the enclosing `SessionRowContainer` (AB-297).
    let isHighlighted: Bool
    var presentation: IslandSessionRowPresentation = .list
    var sideInset: CGFloat = 16
    var lang: LanguageManager = .shared
    let actions: RowActions
    var keyboardCoordinator: OverlayUICoordinator?
    /// Shared 15fps clock for the breathing status dot (AB-228). Passed
    /// through to `PouredPulsingStatusDot`; rows that don't animate never
    /// touch it.
    var pulseClock: PulseClock?

    var body: some View {
        // Actionable rows keep Classic's `IslandSessionRow` — the approval /
        // question / completion interiors it draws are out of scope until
        // AB-303. `IslandSessionRow` reads the same environment tokens, so its
        // status tints already come from `.poured` while it renders.
        if isActionable {
            IslandSessionRow(
                session: session,
                stateIndicator: stateIndicator,
                completedStaleThreshold: completedStaleThreshold,
                isActionable: isActionable,
                useDrawingGroup: useDrawingGroup,
                isInteractive: isInteractive,
                isHighlighted: isHighlighted,
                presentation: presentation,
                sideInset: sideInset,
                lang: lang,
                actions: actions,
                keyboardCoordinator: keyboardCoordinator,
                pulseClock: pulseClock
            )
        } else {
            PouredNonActionableRow(
                session: session,
                stateIndicator: stateIndicator,
                completedStaleThreshold: completedStaleThreshold,
                isInteractive: isInteractive,
                isHighlighted: isHighlighted,
                presentation: presentation,
                sideInset: sideInset,
                lang: lang,
                actions: actions,
                pulseClock: pulseClock
            )
        }
    }
}

/// The glass body for every non-actionable Poured row. Split out so the
/// actionable delegation above stays a single decision and this view owns only
/// the states it actually renders.
private struct PouredNonActionableRow: View {
    let session: AgentSession
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let isInteractive: Bool
    let isHighlighted: Bool
    let presentation: IslandSessionRowPresentation
    let sideInset: CGFloat
    let lang: LanguageManager
    let actions: RowActions
    let pulseClock: PulseClock?

    @State private var detailOverride: Bool?

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    /// AB-302: type ramp for this row's core reading content, identical to
    /// Classic's — every literal point size is expressed relative to this one
    /// reference value so the whole row scales together off one measurement.
    @ScaledMetric(relativeTo: .body) private var typeScaleReference: CGFloat = 13

    private var typeScale: CGFloat {
        typeScaleReference / 13
    }

    private func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * typeScale, weight: weight, design: design)
    }

    /// Each row owns its own age refresh (AB-228) so a tick invalidates only
    /// this row, not its siblings or the list header.
    private static let ageRefreshInterval: TimeInterval = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.ageRefreshInterval)) { context in
            rowBody(referenceDate: context.date)
        }
    }

    private func rowBody(referenceDate: Date) -> some View {
        let rawPresence = session.islandPresence(at: referenceDate)
        let isStaleCompleted = session.isStaleCompletedForIsland(
            at: referenceDate,
            threshold: completedStaleThreshold
        )
        let defaultShowsDetail = !isStaleCompleted && rawPresence != .inactive
        let showsDetail = detailOverride ?? defaultShowsDetail
        let presence: IslandSessionPresence = isStaleCompleted
            ? .inactive
            : ((showsDetail && rawPresence == .inactive) ? .active : rawPresence)

        return VStack(alignment: .leading, spacing: 0) {
            rowSummary(presence: presence, showsDetail: showsDetail, referenceDate: referenceDate)

            if showsDetail {
                rowAuxiliaryDetails(presence: presence)

                if session.phase == .running, let runningDetailText {
                    runningDetailBody(runningDetailText)
                        .padding(.leading, detailLeadingInset)
                        .padding(.trailing, sideInset)
                        .padding(.bottom, 13)
                }
            }
        }
        .background(rowFillColor(for: presence))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            if showsLeadingStatusBar {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(statusTint(for: presence))
                    // Poured's leading bar reads as poured light: a soft glow
                    // bleeds off the bar into the glass rather than a hard chip.
                    .shadow(color: statusTint(for: presence).opacity(presence == .inactive ? 0 : 0.5), radius: 4)
                    .frame(width: 3)
                    .padding(.vertical, showsDetail ? 10 : 8)
                    .padding(.leading, 14)
            }
        }
        // Idle / stale rows recede into the material — the same threshold
        // behaviour as Classic, expressed a touch deeper to read as "sunk into
        // the glass".
        .opacity(isStaleCompleted ? 0.62 : 1)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        .animation(.easeInOut(duration: 0.2), value: session.outcome)
        .animation(.easeInOut(duration: 0.2), value: presence)
        .onTapGesture(perform: handlePrimaryTap)
        .onChange(of: isInteractive) { _, interactive in
            if !interactive {
                detailOverride = nil
            }
        }
    }

    // MARK: - Summary

    private func rowSummary(presence: IslandSessionPresence, showsDetail: Bool, referenceDate: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if showsLeadingStatusIndicator {
                statusIndicator(for: presence)
                    .frame(width: 20, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.spotlightHeadlineText)
                    .font(scaledFont(summaryTitleFontSize, weight: .semibold))
                    .foregroundStyle(titleColor(for: presence))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if showsDetail, let promptLine = summaryPromptLineText {
                    Text(promptLine)
                        .font(scaledFont(11.2, weight: .medium))
                        .foregroundStyle(summaryPromptColor(for: presence))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: IslandSessionRowMetrics.badgeSpacing) {
                agentBadge
                if let modelBadge = session.displayModelName {
                    sideBadge(modelBadge)
                }
                if let permissionChip = permissionModeBadgeKind {
                    permissionModeChip(permissionChip)
                }
                if session.isRemote {
                    sideBadge("SSH")
                }
                if let terminalBadge = session.spotlightTerminalBadge {
                    sideBadge(terminalBadge)
                }
                Text(ageBadgeText(at: referenceDate))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(summaryAgeColor(for: presence))
                    .frame(minWidth: IslandSessionRowMetrics.ageColumnWidth, alignment: .trailing)
                detailToggleButton(isOpen: showsDetail)
                if let dismiss = actions.dismiss {
                    DismissButton(action: dismiss, lang: lang)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, rowLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.top, 11)
        .padding(.bottom, showsDetail ? 8 : 11)
        // AB-302: identical grouped VoiceOver summary to Classic — one stop for
        // the whole row, with the toggle and dismiss recreated as named rotor
        // actions so both stay reachable without splitting the row.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityRowSummaryText(referenceDate: referenceDate))
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        .accessibilityAction {
            guard isInteractive else { return }
            actions.jump()
        }
        .accessibilityAction(named: Text(lang.t(showsDetail ? "a11y.session.collapseDetail" : "a11y.session.expandDetail"))) {
            toggleDetail(currentlyOpen: showsDetail)
        }
        .modifier(PouredOptionalNamedAccessibilityAction(name: actions.dismiss != nil ? lang.t("a11y.session.dismiss") : nil, action: { actions.dismiss?() }))
    }

    // MARK: - Auxiliary details

    @ViewBuilder
    private func rowAuxiliaryDetails(presence: IslandSessionPresence) -> some View {
        if session.phase != .running,
           let activityLine = session.spotlightActivityLineText ?? expandedActivityLineText {
            Text(activityLine)
                .font(scaledFont(11, weight: .medium))
                .foregroundStyle(activityColor(for: presence).opacity(0.94))
                .lineLimit(2)
                .padding(.leading, detailLeadingInset)
                .padding(.trailing, sideInset)
                .padding(.bottom, 10)
        }

        if let subagents = session.claudeMetadata?.activeSubagents, !subagents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .medium))
                        .accessibilityHidden(true)
                    Text(lang.t("subagents.title", subagents.count))
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(.cyan.opacity(0.8))

                ForEach(subagents, id: \.agentID) { sub in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(sub.summary != nil
                                ? tokens.colors.statusCompleted
                                : tokens.colors.statusRunning)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel(lang.t(sub.summary != nil ? "subagents.completed" : "a11y.subagent.running"))
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
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.leading, detailLeadingInset)
            .padding(.trailing, sideInset)
            .padding(.bottom, 10)
        }

        if let tasks = session.claudeMetadata?.activeTasks, !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(taskSummary(tasks))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                ForEach(tasks) { task in
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
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.leading, detailLeadingInset)
            .padding(.trailing, sideInset)
            .padding(.bottom, 10)
        }

        if let transcriptPath = session.trackingTranscriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !transcriptPath.isEmpty {
            TranscriptAffordance(
                path: transcriptPath,
                workspace: session.spotlightWorkspaceName,
                lang: lang
            )
            .padding(.leading, detailLeadingInset)
            .padding(.trailing, sideInset)
            .padding(.bottom, 10)
        }
    }

    private func runningDetailBody(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            )
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Status indicator (all four preferences)

    @ViewBuilder
    private func statusIndicator(for presence: IslandSessionPresence) -> some View {
        let tint = statusTint(for: presence)
        switch stateIndicator {
        case .animatedDot:
            animatedIndicator(tint: tint, presence: presence)
        case .bar:
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(tint)
                .frame(width: 4, height: 28)
                .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.5), radius: 4)
                .padding(.top, 2)
        case .glyph:
            Image(systemName: statusGlyphName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.45), radius: 4)
                .frame(width: 14, height: 20)
                .padding(.top, 1)
        case .tint:
            Circle()
                .fill(tint.opacity(presence == .inactive ? 0.54 : 0.92))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
        }
    }

    /// The default indicator carries Poured's design language most directly:
    /// a running row breathes a glowing dot, a done-success row settles to a
    /// quiet check, and an idle row recedes to a dim, glow-less dot.
    @ViewBuilder
    private func animatedIndicator(tint: Color, presence: IslandSessionPresence) -> some View {
        if session.phase == .completed, session.outcome == .success, presence != .inactive {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.4), radius: 3)
                .frame(width: 14, height: 24, alignment: .top)
                .padding(.top, 3)
        } else if let pulseClock, presence == .running {
            PouredPulsingStatusDot(pulseClock: pulseClock, tint: tint, presence: presence)
                .frame(width: 12, height: 24, alignment: .top)
        } else {
            pouredStatusDotView(tint: tint, presence: presence, pulse: 0)
                .frame(width: 12, height: 24, alignment: .top)
        }
    }

    // MARK: - Badges (display rules AB-282…286, verbatim from Classic)

    private var agentBadge: some View {
        let tint = Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper
        return Text(agentBadgeTitle)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint.opacity(notificationChromeOpacity))
            .frame(minWidth: IslandSessionRowMetrics.agentTitleWidth)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(notificationBadgeFillOpacity), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(notificationBadgeStrokeOpacity), lineWidth: 1))
    }

    private func sideBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(tokens.colors.paper.opacity(presentation == .notification ? 0.52 : 0.72))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(presentation == .notification ? 0.05 : 0.07), in: Capsule())
    }

    private enum PermissionModeBadgeKind {
        case plan
        case bypass
    }

    private var permissionModeBadgeKind: PermissionModeBadgeKind? {
        switch session.claudeMetadata?.permissionMode {
        case .plan:
            .plan
        case .bypassPermissions:
            .bypass
        default:
            nil
        }
    }

    @ViewBuilder
    private func permissionModeChip(_ kind: PermissionModeBadgeKind) -> some View {
        switch kind {
        case .plan:
            sideBadge(lang.t("badge.planMode"))
        case .bypass:
            Text(lang.t("badge.bypassPermissions"))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.colors.statusWarning.opacity(0.94))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tokens.colors.statusWarning.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(tokens.colors.statusWarning.opacity(0.4), lineWidth: 1))
        }
    }

    private func ageBadgeText(at referenceDate: Date) -> String {
        if session.phase == .running {
            return session.elapsedRunningLabel(at: referenceDate)
        }
        return session.spotlightAgeBadge
    }

    // MARK: - Trailing controls

    private func detailToggleButton(isOpen: Bool) -> some View {
        Button {
            toggleDetail(currentlyOpen: isOpen)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isOpen || isHighlighted ? .white.opacity(0.68) : .white.opacity(0.42))
                .frame(
                    width: IslandSessionRowMetrics.detailToggleColumnWidth,
                    height: IslandSessionRowMetrics.trailingControlHeight
                )
                .background(
                    Circle()
                        .fill(.white.opacity(detailToggleFillOpacity(isOpen: isOpen)))
                )
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t(isOpen ? "a11y.session.collapseDetail" : "a11y.session.expandDetail"))
    }

    private func toggleDetail(currentlyOpen: Bool) {
        guard isInteractive else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            detailOverride = !currentlyOpen
        }
    }

    private func detailToggleFillOpacity(isOpen: Bool) -> Double {
        if isHighlighted {
            return isOpen ? 0.09 : 0.07
        }
        return isOpen ? 0.055 : 0.025
    }

    private func handlePrimaryTap() {
        guard isInteractive else { return }
        actions.jump()
    }

    // MARK: - Accessibility (identical wording to Classic)

    private func accessibilityRowSummaryText(referenceDate: Date) -> String {
        lang.t(
            "a11y.session.summary",
            session.tool.displayName,
            session.spotlightWorkspaceName,
            accessibilityPhaseText,
            accessibilityElapsedText(at: referenceDate)
        )
    }

    private var accessibilityPhaseText: String {
        switch session.phase {
        case .running:
            lang.t("a11y.phase.running")
        case .waitingForApproval:
            lang.t("a11y.phase.waitingForApproval")
        case .waitingForAnswer:
            lang.t("a11y.phase.waitingForAnswer")
        case .completed:
            switch session.outcome {
            case .success: lang.t("a11y.phase.completed")
            case .interrupted: lang.t("a11y.phase.interrupted")
            case .failed: lang.t("a11y.phase.failed")
            }
        }
    }

    private func accessibilityElapsedText(at referenceDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: lang.language.resolvedCode)
        formatter.unitsStyle = .full
        let reference = session.phase == .running ? session.firstSeenAt : session.islandActivityDate
        return formatter.localizedString(for: reference, relativeTo: referenceDate)
    }

    // MARK: - Text / tint helpers

    private var summaryPromptLineText: String? {
        if presentation == .notification {
            return session.notificationHeaderPromptLineText
        }
        return session.spotlightPromptLineText ?? expandedPromptLineText
    }

    /// Prompt line for a manually expanded inactive row (bypasses the
    /// time-based filter), matching Classic.
    private var expandedPromptLineText: String? {
        guard detailOverride == true, let prompt = session.spotlightPromptText else { return nil }
        return "You: \(prompt)"
    }

    private var expandedActivityLineText: String? {
        guard detailOverride == true else { return nil }
        let trimmed = session.lastAssistantMessageText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let assistantMessage = trimmed, !assistantMessage.isEmpty {
            return assistantMessage
        }
        return session.jumpTarget != nil ? "Ready" : "Completed"
    }

    private var runningDetailText: String? {
        if let preview = session.currentCommandPreviewText?.trimmedForRow, !preview.isEmpty {
            return "$ \(preview)"
        }
        if let activity = session.spotlightActivityLineText?.trimmedForRow, !activity.isEmpty {
            return activity
        }
        let summary = session.summary.trimmedForRow
        return summary.isEmpty ? nil : summary
    }

    private var agentBadgeTitle: String {
        switch session.tool {
        case .claudeCode: "claude"
        case .geminiCLI: "gemini"
        case .qwenCode: "qwen"
        case .kimiCLI: "kimi"
        default: session.tool.shortName.lowercased()
        }
    }

    private var summaryTitleFontSize: CGFloat {
        presentation == .notification ? 13.2 : 13.2
    }

    private var notificationChromeOpacity: Double {
        presentation == .notification ? 0.82 : 1
    }

    private var notificationBadgeFillOpacity: Double {
        presentation == .notification ? 0.09 : 0.14
    }

    private var notificationBadgeStrokeOpacity: Double {
        presentation == .notification ? 0.24 : 0.35
    }

    private var showsLeadingStatusIndicator: Bool {
        presentation == .list && stateIndicator != .tint && stateIndicator != .bar
    }

    private var showsLeadingStatusBar: Bool {
        presentation == .list && stateIndicator == .bar
    }

    private var rowLeadingInset: CGFloat {
        if presentation == .notification {
            return sideInset
        }
        return stateIndicator == .bar ? max(28, sideInset) : sideInset
    }

    private var detailLeadingInset: CGFloat {
        if presentation == .notification {
            return sideInset
        }
        switch stateIndicator {
        case .bar:
            return max(28, sideInset)
        case .tint:
            return sideInset
        case .animatedDot, .glyph:
            return sideInset + 30
        }
    }

    private func titleColor(for presence: IslandSessionPresence) -> Color {
        if stateIndicator == .tint && presence != .inactive {
            return statusTint(for: presence)
        }
        return presence == .inactive
            ? tokens.colors.paper.opacity(0.78)
            : tokens.colors.paper
    }

    private func summaryPromptColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity))
        }
        return tokens.colors.paper.opacity(contrastText(presence == .inactive ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity))
    }

    private func summaryAgeColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
        }
        return tokens.colors.paper.opacity(contrastText(presence == .inactive ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity))
    }

    private func activityColor(for presence: IslandSessionPresence) -> Color {
        switch session.spotlightActivityTone {
        case .attention:
            return tokens.colors.statusTint(for: session.phase)
        case .live:
            return statusTint(for: presence)
        case .idle:
            return tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity))
        case .ready:
            return presence == .inactive
                ? tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity))
                : statusTint(for: presence)
        }
    }

    private func contrastText(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: increasesContrast)
    }

    private func statusTint(for presence: IslandSessionPresence) -> Color {
        tokens.colors.statusTint(for: session.phase, presence: presence, outcome: session.outcome)
    }

    private var statusGlyphName: String {
        switch session.phase {
        case .waitingForApproval:
            "exclamationmark.triangle.fill"
        case .waitingForAnswer:
            "questionmark.circle.fill"
        case .running:
            "circle.dashed"
        case .completed:
            switch session.outcome {
            case .success: "checkmark.circle.fill"
            case .interrupted: "stop.circle.fill"
            case .failed: "xmark.circle.fill"
            }
        }
    }

    /// Poured's hover is a lighter glass tint that lifts the row (list only).
    /// `.notification` never highlights (`SessionRowContainer` never sets it
    /// there, and this guards it a second time).
    private func rowFillColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return .clear
        }

        let base = isHighlighted ? Color.white.opacity(0.06) : Color.clear
        guard stateIndicator == .tint else { return base }

        let tintOpacity: Double
        if isHighlighted {
            tintOpacity = 0.13
        } else {
            tintOpacity = presence == .inactive ? 0.035 : 0.08
        }
        return statusTint(for: presence).opacity(tintOpacity)
    }

    // MARK: - Small formatters (verbatim from Classic)

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
                .accessibilityLabel(lang.t("a11y.task.completed"))
        case .inProgress:
            Circle()
                .fill(tokens.colors.statusRunning)
                .frame(width: 6, height: 6)
                .accessibilityLabel(lang.t("a11y.task.inProgress"))
        case .pending:
            Circle()
                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                .frame(width: 6, height: 6)
                .accessibilityLabel(lang.t("a11y.task.pending"))
        }
    }
}

// MARK: - Glow dot

/// Poured's status dot: a filled circle wrapped in a soft luminous glow so
/// status reads as light bleeding into the glass rather than a flat chip.
/// `pulse` (0…1, from the shared `PulseClock`) breathes both the scale and the
/// glow radius. A little softer/larger than Classic's dot to match the frosted
/// surface.
private func pouredStatusDotView(tint: Color, presence: IslandSessionPresence, pulse: Double) -> some View {
    Circle()
        .fill(tint)
        .frame(width: 9, height: 9)
        .scaleEffect(1 + (pulse * 0.2))
        .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.42 + (pulse * 0.3)), radius: 5 + (pulse * 4))
        .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.2 + (pulse * 0.16)), radius: 10 + (pulse * 5))
}

/// The breathing variant of `pouredStatusDotView`, isolated in its own `View`
/// so Observation's per-view tracking invalidates only this dot at 15fps
/// (AB-228), and so Reduce Motion never even acquires the shared clock — it
/// renders the settled (`pulse: 0`) dot instead (AB-244).
private struct PouredPulsingStatusDot: View {
    let pulseClock: PulseClock
    let tint: Color
    let presence: IslandSessionPresence

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            pouredStatusDotView(tint: tint, presence: presence, pulse: 0)
        } else {
            pouredStatusDotView(tint: tint, presence: presence, pulse: pulseClock.phase)
                .onAppear { pulseClock.acquire() }
                .onDisappear { pulseClock.release() }
        }
    }
}

/// AB-302: attaches a named VoiceOver action only when `name` is non-nil —
/// the row's "Dismiss" rotor action, present only for dismissible rows. A
/// local copy of the same modifier Classic's row uses (that one is file-private
/// to `IslandPanelView`).
private struct PouredOptionalNamedAccessibilityAction: ViewModifier {
    let name: String?
    let action: () -> Void

    func body(content: Content) -> some View {
        if let name {
            content.accessibilityAction(named: Text(name), action)
        } else {
            content
        }
    }
}

private extension String {
    var trimmedForRow: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
