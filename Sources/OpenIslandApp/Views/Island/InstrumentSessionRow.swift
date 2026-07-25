import AppKit
import SwiftUI
import OpenIslandCore

/// Instrument's session row (AB-309 · instrument 3/4).
///
/// The tabular-grid re-skin of `IslandSessionRow` for the **non-actionable**
/// states — running, done, idle/stale — across the `.list` and `.notification`
/// presentations. Every row is typeset on one exact column grid (state /
/// workspace / agent tick / model / host / age) like a table set by a
/// typographer: the trailing model, host and age cells hold fixed lanes so they
/// land on the same x across every visible row, states are told apart by row
/// rhythm (1-line done, 2-line running/idle) rather than by decoration, the
/// agent is a 3px agent-colour tick beside a mono label, and there is not a
/// single filled pill anywhere — hierarchy is carried by mono type, dim greys
/// and load-bearing hairline rules.
///
/// **Actionable rows still route to Classic (this is a thin seam).** A
/// permission request, a question, or the single completion card is drawn by
/// `IslandSessionRow` until instrument 4/4 (AB-310) restyles those interiors;
/// because that row reads `\.islandTokens`, it already renders in the
/// near-mono instrument palette in the meantime. The behaviours that are
/// contract-level — the jump tap, the ⌘/1–9 keyboard wiring, and the grouped
/// VoiceOver summary — are preserved verbatim from Classic so the two rows stay
/// interchangeable inside one list.
struct InstrumentSessionRow: View {
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
    /// Shared 15fps clock for the running blink (AB-228). Passed through to the
    /// leaf tick view; rows that don't animate never touch it.
    var pulseClock: PulseClock?

    var body: some View {
        if isActionable {
            // Thin seam (AB-309): approval / question / completion interiors are
            // Classic's until AB-310 restyles them — Classic's row already
            // renders in the instrument palette via `\.islandTokens`.
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
            InstrumentRowContent(
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

// MARK: - Pure, testable row logic

/// The fixed trailing lanes for the instrument tabular grid. Every registered
/// column holds a constant width so the model, host and age cells land on the
/// same x across every visible row — the "exact vertical registers" the design
/// language is built on (AB-309 AC #1). Literal points, deliberately not
/// type-scaled, for the same reason `IslandSessionRowMetrics` isn't.
enum InstrumentSessionRowGrid {
    static let columnGap: CGFloat = 10
    static let agentTickWidth: CGFloat = 3
    static let agentColumnWidth: CGFloat = 46
    static let modelColumnWidth: CGFloat = 74
    static let hostColumnWidth: CGFloat = 30
    static let ageColumnWidth: CGFloat = IslandSessionRowMetrics.ageColumnWidth

    /// The trailing cells that must line up vertically across rows.
    static var registeredColumnWidths: [CGFloat] {
        [agentColumnWidth, modelColumnWidth, hostColumnWidth, ageColumnWidth]
    }
}

/// Pure formatting / mapping helpers, split out so the display rules the AC
/// pins (row rhythm, the "Unknown" guard, the interrupted/failed glyph, the
/// motion-gated blink, the ≥10pt floor) are unit-testable without rendering a
/// SwiftUI view.
enum InstrumentSessionRowFormat {
    /// Row rhythm (AC #3): `done` (a fresh completed row) is a single line;
    /// `running` and `idle` carry a second activity/prompt sub-line.
    static func showsSubLine(isRunning: Bool, isIdle: Bool) -> Bool {
        isRunning || isIdle
    }

    /// Never surface a bare "Unknown" workspace (AC #2 / AB-282…286): when the
    /// resolved workspace is the "Unknown" sentinel, substitute the agent's
    /// display name inside the headline instead.
    static func displayHeadline(headline: String, workspace: String, fallback: String) -> String {
        guard workspace == JumpTarget.unknownTerminalApp else { return headline }
        let replaced = headline.replacingOccurrences(of: workspace, with: fallback)
        return replaced.isEmpty ? fallback : replaced
    }

    /// The running tick's blink (AC #4): a crisp two-step mechanical blink off
    /// the shared clock's phase, pinned fully lit (static) under Reduce Motion.
    static func blinkOpacity(phase: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        return phase > 0.5 ? 1 : 0.45
    }

    /// The status glyph (AC #4): a quiet check for a clean finish, and distinct
    /// stop / cross glyphs so interrupted and failed completions never read the
    /// same as a success.
    static func statusGlyphName(phase: SessionPhase, outcome: SessionOutcome) -> String {
        switch phase {
        case .waitingForApproval:
            return "exclamationmark.triangle.fill"
        case .waitingForAnswer:
            return "questionmark.circle.fill"
        case .running:
            return "square.dashed"
        case .completed:
            switch outcome {
            case .success: return "checkmark"
            case .interrupted: return "stop.fill"
            case .failed: return "xmark"
            }
        }
    }

    /// Every readable point size the instrument row draws, for the ≥10pt-floor
    /// assertion (AC #7). The scaled reading roles sit above 10; the fixed
    /// tabular columns sit at exactly the 10.5 mono lane.
    static let readableTextSizes: [CGFloat] = [13.2, 11, 10.5]
}

// MARK: - Row content

/// The flat tabular body for every non-actionable instrument row.
private struct InstrumentRowContent: View {
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

    @State private var expandedOverride: Bool?

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    /// AB-309: the same one-reference type ramp Classic uses — every scaled
    /// reading size is expressed relative to this so the whole row scales
    /// together off one measurement (AC #7). The fixed tabular columns are
    /// deliberately left unscaled (see `IslandSessionRowMetrics`).
    @ScaledMetric(relativeTo: .body) private var typeScaleReference: CGFloat = 13

    private var typeScale: CGFloat { typeScaleReference / 13 }

    private func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * typeScale, weight: weight, design: .monospaced)
    }

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
        // Instrument's rhythm (AC #3) reads presence directly rather than
        // Classic's expand-driven promotion: a fresh completed row is `done`
        // (1 line), everything inactive is `idle` (2 lines, dimmed).
        let presence: IslandSessionPresence = isStaleCompleted ? .inactive : rawPresence
        let isRunning = presence == .running
        let isIdle = presence == .inactive
        let showsSubLine = InstrumentSessionRowFormat.showsSubLine(isRunning: isRunning, isIdle: isIdle)
        let isExpanded = (expandedOverride ?? false) && isInteractive

        return VStack(alignment: .leading, spacing: 0) {
            rowSummary(
                presence: presence,
                showsSubLine: showsSubLine,
                isExpanded: isExpanded,
                referenceDate: referenceDate
            )

            if isExpanded {
                expandedDetails(presence: presence)
            }
        }
        .background(rowFillColor(for: presence))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            if showsLeadingStatusBar {
                // Squared, not filleted — the instrument idiom.
                Rectangle()
                    .fill(statusTint(for: presence))
                    .frame(width: 3)
                    .padding(.vertical, showsSubLine ? 10 : 8)
                    .padding(.leading, 14)
            }
        }
        // Idle / stale rows recede — dimmed, matching Classic's threshold.
        .opacity(isIdle ? 0.7 : 1)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.12), value: isHighlighted)
        .animation(.easeInOut(duration: 0.16), value: session.phase)
        .animation(.easeInOut(duration: 0.16), value: session.outcome)
        .animation(.easeInOut(duration: 0.16), value: presence)
        .onTapGesture(perform: handlePrimaryTap)
        .onChange(of: isInteractive) { _, interactive in
            if !interactive { expandedOverride = nil }
        }
    }

    // MARK: - Summary (the tabular grid line)

    private func rowSummary(
        presence: IslandSessionPresence,
        showsSubLine: Bool,
        isExpanded: Bool,
        referenceDate: Date
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if showsLeadingStatusIndicator {
                statusIndicator(for: presence)
                    .frame(width: 18, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayHeadline)
                    .font(scaledFont(13.2, weight: .semibold))
                    .foregroundStyle(titleColor(for: presence))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Full name one hover away — the column truncates, the
                    // tooltip does not (AC #2).
                    .help(session.spotlightWorkspaceName)

                if showsSubLine, let subLine = summarySubLineText(presence: presence) {
                    Text(subLine)
                        .font(scaledFont(11, weight: .medium))
                        .foregroundStyle(subLineColor(for: presence))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 10)

            trailingGrid(presence: presence, isExpanded: isExpanded, referenceDate: referenceDate)
        }
        .padding(.leading, rowLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.top, 11)
        .padding(.bottom, showsSubLine ? 8 : 11)
        // AB-309: the one grouped VoiceOver summary, identical wording to Classic
        // and the other themes so rows read the same however they're skinned.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityRowSummaryText(referenceDate: referenceDate))
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        .accessibilityAction {
            guard isInteractive else { return }
            actions.jump()
        }
        .accessibilityAction(named: Text(lang.t(isExpanded ? "a11y.session.collapseDetail" : "a11y.session.expandDetail"))) {
            toggleExpanded(currentlyOpen: isExpanded)
        }
        .modifier(InstrumentOptionalNamedAccessibilityAction(
            name: actions.dismiss != nil ? lang.t("a11y.session.dismiss") : nil,
            action: { actions.dismiss?() }
        ))
    }

    /// The fixed-lane trailing block: agent tick, model, host and age each hold
    /// a constant width, and the chevron + dismiss lanes are always reserved
    /// (empty when absent), so the whole cluster is a constant width and the
    /// registered columns land on the same x across every row (AC #1).
    private func trailingGrid(
        presence: IslandSessionPresence,
        isExpanded: Bool,
        referenceDate: Date
    ) -> some View {
        HStack(spacing: InstrumentSessionRowGrid.columnGap) {
            agentCell(presence: presence)
                .frame(width: InstrumentSessionRowGrid.agentColumnWidth, alignment: .leading)

            columnText(session.displayModelName, presence: presence)
                .frame(width: InstrumentSessionRowGrid.modelColumnWidth, alignment: .leading)

            columnText(session.isRemote ? "SSH" : nil, presence: presence)
                .frame(width: InstrumentSessionRowGrid.hostColumnWidth, alignment: .leading)

            Text(ageBadgeText(at: referenceDate))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(columnColor(for: presence))
                .frame(width: InstrumentSessionRowGrid.ageColumnWidth, alignment: .trailing)

            detailToggleButton(isOpen: isExpanded)

            // Reserve the dismiss lane always, so the age column doesn't shift
            // between dismissible and non-dismissible rows.
            if let dismiss = actions.dismiss {
                DismissButton(action: dismiss, lang: lang)
            } else {
                Color.clear.frame(
                    width: IslandSessionRowMetrics.dismissColumnWidth,
                    height: IslandSessionRowMetrics.trailingControlHeight
                )
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The agent column: a 3px agent-colour tick beside a lowercase mono label —
    /// the tick carries the agent's brand colour without a filled pill (AC #1).
    private func agentCell(presence: IslandSessionPresence) -> some View {
        let tint = Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper
        return HStack(spacing: 5) {
            Rectangle()
                .fill(tint.opacity(presence == .inactive ? 0.55 : 1))
                .frame(width: InstrumentSessionRowGrid.agentTickWidth, height: 11)
                .accessibilityHidden(true)
            Text(agentBadgeTitle)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(columnColor(for: presence))
                .lineLimit(1)
        }
    }

    /// A registered trailing cell. An em-dash placeholder holds the lane when a
    /// value is absent so the columns keep their vertical register — and never
    /// prints "Unknown" (AC #2).
    private func columnText(_ value: String?, presence: IslandSessionPresence) -> some View {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValue = !(trimmed?.isEmpty ?? true)
        return Text(hasValue ? trimmed! : "—")
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(hasValue ? columnColor(for: presence) : placeholderColor)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: - Expanded details (chevron open)

    @ViewBuilder
    private func expandedDetails(presence: IslandSessionPresence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let prompt = expandedPromptLineText {
                Text(prompt)
                    .font(scaledFont(11, weight: .medium))
                    .foregroundStyle(subLineColor(for: presence))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let activity = expandedActivityLineText {
                Text(activity)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Rectangle().fill(tokens.colors.paper.opacity(0.04))
                    )
                    .overlay(
                        Rectangle().strokeBorder(tokens.colors.paper.opacity(0.06))
                    )
            }

            HStack(spacing: 12) {
                if let transcriptPath = session.trackingTranscriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !transcriptPath.isEmpty {
                    TranscriptAffordance(
                        path: transcriptPath,
                        workspace: session.spotlightWorkspaceName,
                        lang: lang
                    )
                }

                Spacer(minLength: 0)

                if isInteractive {
                    instrumentJumpButton
                }
            }
        }
        .padding(.leading, detailLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.bottom, 12)
    }

    /// The Jump affordance in the instrument idiom: an uppercase mono label in a
    /// squared hairline frame with no fill (AC #3).
    private var instrumentJumpButton: some View {
        Button {
            actions.jump()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9.5, weight: .semibold))
                    .accessibilityHidden(true)
                Text(InstrumentText.caps(lang.t("island.instrument.row.jump"), lang: lang))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(InstrumentText.tracking(0.8, lang: lang))
            }
            .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.72)))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .overlay(
                Rectangle().strokeBorder(tokens.colors.paper.opacity(0.16), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t("island.instrument.row.jump"))
    }

    // MARK: - Status indicator (all four preferences)

    @ViewBuilder
    private func statusIndicator(for presence: IslandSessionPresence) -> some View {
        let tint = statusTint(for: presence)
        switch stateIndicator {
        case .animatedDot:
            animatedIndicator(tint: tint, presence: presence)
        case .bar:
            Rectangle()
                .fill(tint)
                .frame(width: 4, height: 26)
                .padding(.top, 2)
        case .glyph:
            Image(systemName: InstrumentSessionRowFormat.statusGlyphName(phase: session.phase, outcome: session.outcome))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 20)
                .padding(.top, 1)
        case .tint:
            Rectangle()
                .fill(tint.opacity(presence == .inactive ? 0.55 : 0.95))
                .frame(width: 7, height: 7)
                .padding(.top, 6)
        }
    }

    /// The default indicator carries the instrument language most directly: a
    /// running row blinks a green square (static under Reduce Motion), a clean
    /// finish settles to a quiet check, an interrupted/failed row shows its
    /// distinct amber/red glyph, and an idle row is a dim static square.
    @ViewBuilder
    private func animatedIndicator(tint: Color, presence: IslandSessionPresence) -> some View {
        if session.phase == .completed, session.outcome != .success {
            Image(systemName: InstrumentSessionRowFormat.statusGlyphName(phase: session.phase, outcome: session.outcome))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 24, alignment: .top)
                .padding(.top, 3)
        } else if session.phase == .completed, session.outcome == .success, presence != .inactive {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 24, alignment: .top)
                .padding(.top, 3)
        } else if let pulseClock, stateIndicator.pulses(presence: presence, isActionable: false) {
            InstrumentPulsingStatusTick(pulseClock: pulseClock, tint: tint)
                .frame(width: 9, height: 24, alignment: .top)
        } else {
            instrumentStatusSquare(tint: tint, presence: presence, opacity: 1)
                .frame(width: 9, height: 24, alignment: .top)
        }
    }

    // MARK: - Trailing chevron

    private func detailToggleButton(isOpen: Bool) -> some View {
        Button {
            toggleExpanded(currentlyOpen: isOpen)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tokens.colors.paper.opacity(isOpen || isHighlighted ? 0.7 : 0.42))
                .frame(
                    width: IslandSessionRowMetrics.detailToggleColumnWidth,
                    height: IslandSessionRowMetrics.trailingControlHeight
                )
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t(isOpen ? "a11y.session.collapseDetail" : "a11y.session.expandDetail"))
    }

    private func toggleExpanded(currentlyOpen: Bool) {
        guard isInteractive else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            expandedOverride = !currentlyOpen
        }
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
            return lang.t("a11y.phase.running")
        case .waitingForApproval:
            return lang.t("a11y.phase.waitingForApproval")
        case .waitingForAnswer:
            return lang.t("a11y.phase.waitingForAnswer")
        case .completed:
            switch session.outcome {
            case .success: return lang.t("a11y.phase.completed")
            case .interrupted: return lang.t("a11y.phase.interrupted")
            case .failed: return lang.t("a11y.phase.failed")
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

    private var displayHeadline: String {
        InstrumentSessionRowFormat.displayHeadline(
            headline: session.spotlightHeadlineText,
            workspace: session.spotlightWorkspaceName,
            fallback: session.tool.displayName
        )
    }

    private func summarySubLineText(presence: IslandSessionPresence) -> String? {
        if presence == .running {
            return runningLineText
        }
        // Idle: the last prompt, else the trailing activity.
        return session.spotlightPromptLineText
            ?? forcedPromptLineText
            ?? session.spotlightActivityLineText
    }

    private var runningLineText: String? {
        if let preview = session.currentCommandPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return "$ \(preview)"
        }
        if let activity = session.spotlightActivityLineText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !activity.isEmpty {
            return activity
        }
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private var forcedPromptLineText: String? {
        guard let prompt = session.spotlightPromptText else { return nil }
        return "You: \(prompt)"
    }

    private var expandedPromptLineText: String? {
        session.spotlightPromptLineText ?? forcedPromptLineText
    }

    private var expandedActivityLineText: String? {
        if session.phase == .running, let running = runningLineText {
            return running
        }
        let trimmed = session.lastAssistantMessageText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let assistantMessage = trimmed, !assistantMessage.isEmpty {
            return assistantMessage
        }
        return session.spotlightActivityLineText
    }

    private var agentBadgeTitle: String {
        switch session.tool {
        case .claudeCode: return "claude"
        case .geminiCLI: return "gemini"
        case .qwenCode: return "qwen"
        case .kimiCLI: return "kimi"
        default: return session.tool.shortName.lowercased()
        }
    }

    private func ageBadgeText(at referenceDate: Date) -> String {
        if session.phase == .running {
            return session.elapsedRunningLabel(at: referenceDate)
        }
        return session.spotlightAgeBadge
    }

    private func contrastText(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: increasesContrast)
    }

    private func statusTint(for presence: IslandSessionPresence) -> Color {
        tokens.colors.statusTint(for: session.phase, presence: presence, outcome: session.outcome)
    }

    private func titleColor(for presence: IslandSessionPresence) -> Color {
        if stateIndicator == .tint, presence != .inactive {
            return statusTint(for: presence)
        }
        return presence == .inactive
            ? tokens.colors.paper.opacity(0.78)
            : tokens.colors.paper
    }

    private func subLineColor(for presence: IslandSessionPresence) -> Color {
        tokens.colors.paper.opacity(contrastText(
            presence == .inactive ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity
        ))
    }

    private func columnColor(for presence: IslandSessionPresence) -> Color {
        tokens.colors.paper.opacity(contrastText(
            presence == .inactive ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity
        ))
    }

    private var placeholderColor: Color {
        tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity) * 0.5)
    }

    private func rowFillColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return .clear
        }
        let base = isHighlighted ? tokens.colors.paper.opacity(0.05) : Color.clear
        guard stateIndicator == .tint else { return base }

        let tintOpacity: Double
        if isHighlighted {
            tintOpacity = 0.14
        } else {
            tintOpacity = presence == .inactive ? 0.03 : 0.07
        }
        return statusTint(for: presence).opacity(tintOpacity)
    }

    // MARK: - Layout insets

    private var showsLeadingStatusIndicator: Bool {
        presentation == .list && stateIndicator != .tint && stateIndicator != .bar
    }

    private var showsLeadingStatusBar: Bool {
        presentation == .list && stateIndicator == .bar
    }

    private var rowLeadingInset: CGFloat {
        if presentation == .notification { return sideInset }
        return stateIndicator == .bar ? max(28, sideInset) : sideInset
    }

    private var detailLeadingInset: CGFloat {
        if presentation == .notification { return sideInset }
        switch stateIndicator {
        case .bar:
            return max(28, sideInset)
        case .tint:
            return sideInset
        case .animatedDot, .glyph:
            return sideInset + 28
        }
    }
}

// MARK: - Instrument status tick

/// A flat squared status tick — the instrument idiom's answer to Classic's
/// round dot. `opacity` lets a running tick blink.
private func instrumentStatusSquare(tint: Color, presence: IslandSessionPresence, opacity: Double) -> some View {
    Rectangle()
        .fill(tint.opacity((presence == .inactive ? 0.55 : 1) * opacity))
        .frame(width: 8, height: 8)
        .padding(.top, 6)
}

/// The running tick, isolated in its own `View` so Observation's per-view
/// tracking invalidates only this square at 15fps (AB-228), and so Reduce
/// Motion never even acquires the shared clock — it renders the steady square
/// instead (AB-244). The blink is a crisp two-step (mechanical), not a breathe.
private struct InstrumentPulsingStatusTick: View {
    let pulseClock: PulseClock
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            instrumentStatusSquare(tint: tint, presence: .running, opacity: 1)
        } else {
            instrumentStatusSquare(
                tint: tint,
                presence: .running,
                opacity: InstrumentSessionRowFormat.blinkOpacity(phase: pulseClock.phase, reduceMotion: false)
            )
            .onAppear { pulseClock.acquire() }
            .onDisappear { pulseClock.release() }
        }
    }
}

/// Attaches a named VoiceOver action only when `name` is non-nil — the row's
/// "Dismiss" rotor action, present only for dismissible rows. A local copy of
/// the same modifier Classic's row uses.
private struct InstrumentOptionalNamedAccessibilityAction: ViewModifier {
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
