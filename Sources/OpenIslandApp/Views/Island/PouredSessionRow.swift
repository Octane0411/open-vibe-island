import AppKit
import SwiftUI
@preconcurrency import MarkdownUI
import OpenIslandCore

/// Poured Island's session row (AB-302 · AB-303).
///
/// The glass re-skin of `IslandSessionRow` for **every** row state — collapsed,
/// running, done, idle/stale (AB-302) and the actionable approval / question /
/// completion interiors (AB-303) — across the `.list` and `.notification`
/// presentations. Status is expressed as luminous glow rather than a chip: a
/// running row carries a breathing green dot (static under Reduce Motion), a
/// done row settles to a quiet check, and an idle row recedes into the
/// material; hover lifts the row with a lighter glass tint in `.list` only.
///
/// **Actionable rows are now fully Poured (AB-303).** A permission request
/// radiates a pulsing warm-amber glow above the glass — the loudest surface in
/// the panel — with a filled Allow and a quiet Deny; the question and completion
/// bodies reuse the shared, token-driven `StructuredQuestionPromptView` /
/// completion card, which already read cleanly on the frosted surface. The
/// behaviours that are contract-level — approve / answer / reply callbacks, the
/// ⌘Y / ⌘⇧Y / ⌘N keyboard wiring (driven globally from `OverlayPanelController`),
/// the 1–9 / Enter question shortcuts, and the grouped VoiceOver summary — are
/// preserved verbatim; only the surfaces change.
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
    /// Lets the visible question card register its option-selection state with
    /// `OverlayPanelController`'s keyboard shortcut handler (AB-227).
    var keyboardCoordinator: OverlayUICoordinator?
    /// Shared 15fps clock for the breathing status dot (AB-228) and the amber
    /// approval glow (AB-303). Passed through to the leaf views that animate;
    /// rows that don't animate never touch it.
    var pulseClock: PulseClock?

    var body: some View {
        PouredRowContent(
            session: session,
            stateIndicator: stateIndicator,
            completedStaleThreshold: completedStaleThreshold,
            isActionable: isActionable,
            isInteractive: isInteractive,
            isHighlighted: isHighlighted,
            presentation: presentation,
            sideInset: sideInset,
            lang: lang,
            actions: actions,
            keyboardCoordinator: keyboardCoordinator,
            pulseClock: pulseClock
        )
    }
}

/// The glass body for every Poured row. Renders the shared summary / auxiliary
/// chrome (verbatim from Classic so the two rows stay interchangeable inside one
/// list) plus, for actionable rows, the Poured approval / question / completion
/// interiors.
private struct PouredRowContent: View {
    let session: AgentSession
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let isActionable: Bool
    let isInteractive: Bool
    let isHighlighted: Bool
    let presentation: IslandSessionRowPresentation
    let sideInset: CGFloat
    let lang: LanguageManager
    let actions: RowActions
    let keyboardCoordinator: OverlayUICoordinator?
    let pulseClock: PulseClock?

    @State private var detailOverride: Bool?
    @State private var replyText: String = ""

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
        let defaultShowsDetail = !isStaleCompleted && (rawPresence != .inactive || isActionable)
        let showsDetail = detailOverride ?? defaultShowsDetail
        let presence: IslandSessionPresence = isStaleCompleted
            ? .inactive
            : ((showsDetail && rawPresence == .inactive) ? .active : rawPresence)

        return VStack(alignment: .leading, spacing: 0) {
            rowSummary(presence: presence, showsDetail: showsDetail, referenceDate: referenceDate)

            if showsDetail {
                rowAuxiliaryDetails(presence: presence)

                if shouldShowEmbeddedDetailBody {
                    embeddedDetailBody
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

    // MARK: - Embedded detail body (running preview / actionable interiors)

    /// Mirrors Classic's gate: attention phases always earn the body, a
    /// completed row only when it's the actionable card with something to show,
    /// and a running row only when it has a command/activity preview.
    private var shouldShowEmbeddedDetailBody: Bool {
        if session.phase.requiresAttention {
            return true
        }
        if session.phase == .completed {
            return isActionable && completionHasExpandedBody
        }
        return session.phase == .running && runningDetailText != nil
    }

    @ViewBuilder
    private var embeddedDetailBody: some View {
        switch session.phase {
        case .waitingForApproval:
            PouredApprovalCard(session: session, lang: lang, actions: actions, pulseClock: pulseClock)
        case .waitingForAnswer:
            questionActionBody
        case .completed:
            completionActionBody
        case .running:
            if let runningDetailText {
                runningDetailBody(runningDetailText)
            }
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

    // MARK: - Question action area

    /// The structured question card is fully token-driven and already reads on
    /// glass, so Poured reuses it verbatim — that keeps the 1–9 / Enter keyboard
    /// wiring, multi-select toggles, freeform + quick-reply fields and submit
    /// behaviour identical to Classic (AB-303).
    private var questionActionBody: some View {
        StructuredQuestionPromptView(
            prompt: session.questionPrompt,
            lang: lang,
            keyboardCoordinator: keyboardCoordinator,
            onAnswer: { actions.answer?($0) }
        )
    }

    // MARK: - Completion action area

    /// The completion card, restyled for glass: the markdown body resolves its
    /// text / link / code colours from `.completionCard(tokens.colors)` (already
    /// token-driven, so links and code read on the frosted surface), scrolls
    /// within the same 160pt cap, and the reply input / send stay wired to
    /// `actions.reply` exactly as Classic.
    private var completionActionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !completionMessageText.trimmedForRow.isEmpty {
                if session.outcome != .success {
                    completionOutcomeBanner
                }

                AutoHeightScrollView(maxHeight: 160) {
                    Markdown(completionMessageText)
                        .markdownTheme(.completionCard(tokens.colors))
                        .markdownImageProvider(.noNetwork)
                        .markdownInlineImageProvider(.noNetwork)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
            } else {
                completionEmptyState
            }

            if actions.reply != nil {
                Rectangle()
                    .fill(.white.opacity(0.05))
                    .frame(height: 1)

                completionReplyInput
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.09))
        )
    }

    private var completionHasExpandedBody: Bool {
        // A non-success outcome always earns the expanded card — even with no
        // message body — so an interrupted/failed completion isn't silently
        // indistinguishable from a plain "Completed" row.
        session.outcome != .success
            || !completionMessageText.trimmedForRow.isEmpty
            || actions.reply != nil
    }

    private var completionDoneOpacity: Double {
        presentation == .notification ? 0.82 : 0.96
    }

    private var completionOutcomeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: completionOutcomeGlyphName)
                .font(.system(size: 10.5, weight: .bold))
                .accessibilityHidden(true)
            Text(completionOutcomeLabel)
                .font(.system(size: 11, weight: .bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(completionOutcomeTint.opacity(completionDoneOpacity))
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    /// Only ever rendered from `completionOutcomeBanner`, which is gated on
    /// `session.outcome != .success` — "stop" is just the glyph for the
    /// remaining `.interrupted` case.
    private var completionOutcomeGlyphName: String {
        session.outcome == .failed ? "xmark.circle.fill" : "stop.circle.fill"
    }

    private var completionOutcomeTint: Color {
        tokens.colors.statusTint(for: .completed, outcome: session.outcome)
    }

    private var completionOutcomeLabel: String {
        switch session.outcome {
        case .success:
            lang.t("completion.done")
        case .interrupted:
            lang.t("completion.interrupted")
        case .failed:
            lang.t("completion.failed")
        }
    }

    private var completionEmptyState: some View {
        HStack {
            Text(completionOutcomeLabel)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(completionOutcomeTint.opacity(completionDoneOpacity))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var completionReplyInput: some View {
        HStack(spacing: 8) {
            ReplyTextField(
                placeholder: lang.t("completion.replyPlaceholder", session.completionReplyRecipientName),
                text: $replyText,
                onSubmit: { submitReply() }
            )
            .frame(height: 32)

            Button {
                submitReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel(lang.t("a11y.completion.sendReply"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submitReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyText = ""
        actions.reply?(text)
    }

    private var completionMessageText: String {
        if let text = session.completionAssistantMessageText?.trimmedForRow, !text.isEmpty {
            return text
        }
        let summary = session.summary.trimmedForRow
        return summary == SessionPhase.completed.displayName ? "" : summary
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
                .frame(width: 4, height: isActionable ? 34 : 28)
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
    /// a running (or actionable-waiting) row breathes a glowing dot, a
    /// done-success row settles to a quiet check, and an idle row recedes to a
    /// dim, glow-less dot.
    @ViewBuilder
    private func animatedIndicator(tint: Color, presence: IslandSessionPresence) -> some View {
        if session.phase == .completed, session.outcome == .success, presence != .inactive {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.4), radius: 3)
                .frame(width: 14, height: 24, alignment: .top)
                .padding(.top, 3)
        } else if let pulseClock, stateIndicator.pulses(presence: presence, isActionable: isActionable) {
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

        let base = isHighlighted ? Color.white.opacity(isActionable ? 0.07 : 0.06) : Color.clear
        guard stateIndicator == .tint else { return base }

        let tintOpacity: Double
        if isHighlighted {
            tintOpacity = isActionable ? 0.15 : 0.13
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

// MARK: - Poured approval hero card

/// The permission request rendered as Poured Island's hero: an amber-glow card
/// that radiates a pulsing warm glow above everything else on the glass (static
/// under Reduce Motion), a command preview in a mono block, an affected-path
/// line, an optional `PermissionDiffPreview`, and a prominent filled Allow next
/// to a quiet Deny — or the always-allow options / Codex terminal CTA.
///
/// Isolated in its own `View` so the amber glow's 15fps pulse (read off the
/// shared `PulseClock` via `PouredAmberGlow`) invalidates only the glow, and so
/// the approve / deny callbacks stay exactly the ones ⌘Y / ⌘⇧Y / ⌘N fire
/// against from `OverlayPanelController`.
private struct PouredApprovalCard: View {
    let session: AgentSession
    let lang: LanguageManager
    let actions: RowActions
    let pulseClock: PulseClock?

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    /// The hero glow is warm amber (`statusWarning`) so the permission card
    /// reads as the loudest, warmest surface next to the cool running/done/idle
    /// rows.
    private var amber: Color { tokens.colors.statusWarning }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.t("approval.toolPermissionRequested"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.9)))

            VStack(alignment: .leading, spacing: 8) {
                Text(commandPreviewText)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.82)))
                    .fixedSize(horizontal: false, vertical: true)

                if let path = affectedPath {
                    Text(path)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.5)))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            // AB-235: only for Edit/Write requests whose `tool_input` carried
            // enough to compute a diff; the shared renderer's token-driven +/−
            // colours already read on glass, within its 500-line / 180pt caps.
            if let diffResult = permissionDiffResult {
                PermissionDiffPreview(result: diffResult, lang: lang)
            }

            if session.permissionRequest?.requiresTerminalApproval == true {
                terminalApprovalCTA
            } else {
                HStack(spacing: 8) {
                    Button(session.permissionRequest?.secondaryActionTitle ?? lang.t("approval.deny")) { actions.approve?(.deny) }
                        .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true))
                        .accessibilityLabel(session.permissionRequest?.secondaryActionTitle ?? lang.t("a11y.approval.deny"))
                    Button(session.permissionRequest?.primaryActionTitle ?? lang.t("approval.allowOnce")) { actions.approve?(.allowOnce) }
                        .buttonStyle(IslandActionButtonStyle(kind: .warning, expands: true))
                        .accessibilityLabel(session.permissionRequest?.primaryActionTitle ?? lang.t("a11y.approval.allowOnce"))
                }

                alwaysAllowOptions
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(amber.opacity(reduceTransparency ? 0.75 : 0.5), lineWidth: 1)
        )
        .modifier(PouredAmberGlow(tint: amber, pulseClock: pulseClock))
        // The buttons carry their own labels/actions; group the surrounding
        // copy so VoiceOver reads the card, then reaches Allow / Deny.
        .accessibilityElement(children: .contain)
    }

    /// A warm amber wash over the frosted slab. Under Reduce Transparency the
    /// wash sits on an opaque ink base so the card never relies on the glass
    /// showing through to stay legible (AB-303).
    @ViewBuilder
    private var cardFill: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(tokens.colors.surfaceInk)
                shape.fill(amber.opacity(0.22))
            } else {
                shape.fill(amber.opacity(0.1))
            }
        }
    }

    /// AB-235: scoped always-allow options (one button per suggested update) or
    /// the generic session-scoped "Always allow <tool>" fallback. Choosing one
    /// fires `RowActions.approve(.allowWithUpdates(...))` with exactly that
    /// update — the same call ⌘⇧Y drives.
    @ViewBuilder
    private var alwaysAllowOptions: some View {
        if let updates = session.permissionRequest?.suggestedUpdates, !updates.isEmpty {
            VStack(spacing: 6) {
                ForEach(Array(updates.enumerated()), id: \.offset) { _, update in
                    Button(update.displayLabel) {
                        actions.approve?(.allowWithUpdates([update]))
                    }
                    .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true))
                }
            }
        } else if let toolName = session.permissionRequest?.toolName {
            Button(lang.t("approval.alwaysAllow", toolName)) {
                let rule = ClaudePermissionRuleValue(toolName: toolName)
                let update = ClaudePermissionUpdate.addRules(
                    destination: .session,
                    rules: [rule],
                    behavior: .allow
                )
                actions.approve?(.allowWithUpdates([update]))
            }
            .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true))
        }
    }

    /// AB-235: shown instead of Deny/Allow when `requiresTerminalApproval` is
    /// set — the decision can't be round-tripped through the bridge, so the CTA
    /// jumps to wherever the request lives (terminal pane or `codex://` URL).
    private var terminalApprovalCTA: some View {
        Button {
            actions.jump()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(lang.t("approval.respondInTerminal"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true))
    }

    private var affectedPath: String? {
        guard let path = session.permissionRequest?.affectedPath.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return path
    }

    private var commandPreviewText: String {
        let preview = session.currentCommandPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preview, !preview.isEmpty {
            return "$ \(preview)"
        }
        return (session.permissionRequest?.summary ?? session.summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Computes the diff lazily from the request's captured old/new text
    /// (AB-235). `nil` when there's nothing to diff or old/new are identical.
    private var permissionDiffResult: PermissionDiffResult? {
        guard let source = session.permissionRequest?.fileDiffSource else {
            return nil
        }
        let result = PermissionDiff.compute(oldText: source.oldText, newText: source.newText)
        return result.isEmpty ? nil : result
    }

    private func contrastText(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: increasesContrast)
    }
}

/// Wraps the approval card in Poured's pulsing amber glow. Isolated as a
/// modifier so the 15fps `PulseClock` read invalidates only the glow (not the
/// buttons inside), and so Reduce Motion — or a missing clock — renders a
/// static-but-still-loud glow rather than a breathing one (AB-303).
private struct PouredAmberGlow: ViewModifier {
    let tint: Color
    let pulseClock: PulseClock?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { !reduceMotion && pulseClock != nil }

    private var pulse: Double {
        animates ? (pulseClock?.phase ?? 0) : 0
    }

    func body(content: Content) -> some View {
        content
            .shadow(color: tint.opacity(0.34 + pulse * 0.26), radius: 10 + pulse * 8)
            .shadow(color: tint.opacity(0.18 + pulse * 0.16), radius: 20 + pulse * 10)
            .onAppear { if animates { pulseClock?.acquire() } }
            .onDisappear { if animates { pulseClock?.release() } }
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
