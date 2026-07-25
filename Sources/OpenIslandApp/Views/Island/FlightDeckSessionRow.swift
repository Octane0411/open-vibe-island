import AppKit
import SwiftUI
import OpenIslandCore

/// Flight Deck's session row (AB-313 · flightdeck 3/4).
///
/// The annunciator re-skin of `IslandSessionRow` for the **non-actionable**
/// states — running, done (success / interrupted / failed), idle-stale, SSH and
/// demo — across the `.list` and `.notification` presentations. Every row
/// carries a colored **STATUS LANE** on its left edge like an EICAS warning
/// light (red alert / green run / blue done / gray idle); the live lane pulses
/// off the shared clock and holds steady under Reduce Motion. The body is
/// typeset on the SESSION / MODEL / APP / TIME column grid from flightdeck 2/4:
/// the trailing model, app and time cells hold fixed lanes so they land on the
/// same x under their captions across every visible row, and the chevron and
/// dismiss controls sit in reserved lanes so the registers never shift. Agent
/// identity is a small neutral mono mark so the lane's state colour always wins.
///
/// **Actionable rows still route to Classic (this is a thin seam).** A
/// permission request (MASTER CAUTION), a question, or the single completion
/// card is drawn by `IslandSessionRow` until flightdeck 4/4 (AB-314) restyles
/// those interiors; because that row reads `\.islandTokens`, it already renders
/// in the near-black phosphor palette in the meantime. The behaviours that are
/// contract-level — the jump tap, the ⌘/1–9 keyboard wiring, and the grouped
/// VoiceOver summary — are preserved verbatim from Classic so the two rows stay
/// interchangeable inside one list.
struct FlightDeckSessionRow: View {
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
    /// Shared 15fps clock for the pulsing lane (AB-228). Passed through to the
    /// leaf lane view; rows that don't animate never touch it.
    var pulseClock: PulseClock?

    var body: some View {
        if isActionable {
            // Thin seam (AB-313): approval / question / completion interiors are
            // Classic's until AB-314 restyles them — Classic's row already
            // renders in the Flight Deck palette via `\.islandTokens`.
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
            FlightDeckRowContent(
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

/// The fixed trailing lanes for the Flight Deck column grid. Every registered
/// column holds a constant width so the model, app and time cells land on the
/// same x under their SESSION / MODEL / APP / TIME captions across every visible
/// row — the "exact vertical registers" the design language is built on
/// (AB-313 AC #2). Literal points, deliberately not type-scaled, for the same
/// reason `IslandSessionRowMetrics` isn't. The `columnCaptionStrip` in
/// `FlightDeckSessionListScaffold` draws from these exact constants so the
/// captions and the cells share one geometry.
enum FlightDeckSessionRowGrid {
    static let columnGap: CGFloat = 8
    static let modelColumnWidth: CGFloat = 66
    static let appColumnWidth: CGFloat = 54
    static let timeColumnWidth: CGFloat = 44

    /// Trailing controls, reserved as fixed lanes in both the row and the
    /// caption strip so the time register never shifts between rows that do and
    /// don't carry a dismiss control.
    static let detailToggleColumnWidth: CGFloat = IslandSessionRowMetrics.detailToggleColumnWidth
    static let dismissColumnWidth: CGFloat = IslandSessionRowMetrics.dismissColumnWidth

    /// The registered cells that must line up vertically across rows.
    static var registeredColumnWidths: [CGFloat] {
        [modelColumnWidth, appColumnWidth, timeColumnWidth]
    }
}

/// Pure formatting / mapping helpers, split out so the display rules the AC
/// pins (the lane's state → colour / prominence / pulse mapping, the row rhythm,
/// the "Unknown" guard, the SSH / app cell, the interrupted/failed glyph, the
/// motion-gated pulse, the ≥10pt floor) are unit-testable without rendering a
/// SwiftUI view.
enum FlightDeckSessionRowFormat {
    /// The four EICAS lane states, in loudest-to-quietest order. `alert` folds in
    /// both the attention phases (the MASTER CAUTION the seam still routes to
    /// Classic in this slice) and the non-success completions (interrupted /
    /// failed) so a failed row reads as loud as an alarm — the grayscale
    /// redundancy (AC #7) rides on this ranking, not on hue.
    enum LanePriority: Int, CaseIterable {
        case alert = 0
        case running = 1
        case done = 2
        case idle = 3
    }

    /// Maps a row's phase / presence / outcome onto its lane state. `idle`
    /// (inactive presence) always wins so a stale completed row recedes to grey
    /// regardless of its stored outcome.
    static func lanePriority(
        phase: SessionPhase,
        presence: IslandSessionPresence,
        outcome: SessionOutcome
    ) -> LanePriority {
        if presence == .inactive { return .idle }
        switch phase {
        case .waitingForApproval, .waitingForAnswer:
            return .alert
        case .running:
            return .running
        case .completed:
            return outcome == .success ? .done : .alert
        }
    }

    /// The lane width, in points. The alert lane is physically the widest so it
    /// stays the loudest mark even in a grayscale screenshot where red carries no
    /// more luminance than green — brightness/area redundancy, not colour alone
    /// (AC #7).
    static func laneWidth(_ priority: LanePriority) -> CGFloat {
        switch priority {
        case .alert:   return 5
        case .running: return 4
        case .done:    return 3.5
        case .idle:    return 3
        }
    }

    /// The lane's resting opacity — the second half of the brightness ramp: the
    /// live lanes burn at full, the settled done lane a shade under, and the idle
    /// lane recedes.
    static func laneOpacity(_ priority: LanePriority) -> Double {
        switch priority {
        case .alert:   return 1.0
        case .running: return 1.0
        case .done:    return 0.85
        case .idle:    return 0.4
        }
    }

    /// Whether the lane pulses (AC #1): the live states — a running turn and an
    /// attention phase — blink like a warning light; every settled outcome holds
    /// steady. The view layer gates this on Reduce Motion so the pulse is static
    /// when motion is off.
    static func lanePulses(phase: SessionPhase, presence: IslandSessionPresence) -> Bool {
        presence == .running || phase.requiresAttention
    }

    /// Row rhythm (AC #4): `done` (a fresh completed row) is a single line;
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

    /// The APP cell (AC #2 / #4): a remote session reads `SSH` in the app lane so
    /// the SSH state renders distinctly; a local session shows its terminal / IDE
    /// app; and a session with neither yields `nil` so the cell draws its em-dash
    /// placeholder rather than a bare "Unknown".
    static func appColumnText(isRemote: Bool, terminalBadge: String?) -> String? {
        if isRemote { return "SSH" }
        let trimmed = terminalBadge?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The pulsing lane's blink (AC #1): a crisp two-step mechanical blink off the
    /// shared clock's phase, pinned fully lit (static) under Reduce Motion.
    static func pulseOpacity(phase: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        return phase > 0.5 ? 1 : 0.45
    }

    /// The status glyph (AC #4): a quiet check for a clean finish, and distinct
    /// stop / cross glyphs so interrupted and failed completions never read the
    /// same as a success — the mark used by the `.glyph` indicator preference.
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

    /// Every readable point size the Flight Deck row draws, for the ≥10pt-floor
    /// assertion (AC #6). The scaled reading roles sit above 10; the fixed
    /// tabular columns sit at exactly the 10.5 mono lane.
    static let readableTextSizes: [CGFloat] = [13.2, 11, 10.5]
}

// MARK: - Row content

/// The annunciator body for every non-actionable Flight Deck row.
private struct FlightDeckRowContent: View {
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

    /// AB-313: the same one-reference type ramp Classic uses — every scaled
    /// reading size is expressed relative to this so the whole row scales
    /// together off one measurement (AC #6). The fixed tabular columns are
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
        // Flight Deck's rhythm (AC #4) reads presence directly: a fresh completed
        // row is `done` (1 line), everything inactive is `idle` (2 lines, dimmed).
        let presence: IslandSessionPresence = isStaleCompleted ? .inactive : rawPresence
        let isRunning = presence == .running
        let isIdle = presence == .inactive
        let showsSubLine = FlightDeckSessionRowFormat.showsSubLine(isRunning: isRunning, isIdle: isIdle)
        let isExpanded = (expandedOverride ?? false) && isInteractive
        let priority = FlightDeckSessionRowFormat.lanePriority(
            phase: session.phase,
            presence: presence,
            outcome: session.outcome
        )

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
            if showsStatusLane {
                FlightDeckStatusLane(
                    color: statusTint(for: presence),
                    width: FlightDeckSessionRowFormat.laneWidth(priority),
                    restingOpacity: FlightDeckSessionRowFormat.laneOpacity(priority),
                    pulses: FlightDeckSessionRowFormat.lanePulses(phase: session.phase, presence: presence),
                    pulseClock: pulseClock
                )
                .padding(.vertical, 6)
                .padding(.leading, laneLeadingInset)
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
            if showsLeadingMark {
                leadingMark(for: presence)
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
        // AB-313: the one grouped VoiceOver summary, identical wording to Classic
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
        .modifier(FlightDeckOptionalNamedAccessibilityAction(
            name: actions.dismiss != nil ? lang.t("a11y.session.dismiss") : nil,
            action: { actions.dismiss?() }
        ))
    }

    /// The fixed-lane trailing block: model, app and time each hold a constant
    /// width under their captions, and the chevron + dismiss lanes are always
    /// reserved (empty when absent), so the whole cluster is a constant width and
    /// the registered columns land on the same x across every row (AC #2).
    private func trailingGrid(
        presence: IslandSessionPresence,
        isExpanded: Bool,
        referenceDate: Date
    ) -> some View {
        HStack(spacing: FlightDeckSessionRowGrid.columnGap) {
            columnText(session.displayModelName, presence: presence, alignment: .leading)
                .frame(width: FlightDeckSessionRowGrid.modelColumnWidth, alignment: .leading)

            columnText(appColumnText, presence: presence, alignment: .leading)
                .frame(width: FlightDeckSessionRowGrid.appColumnWidth, alignment: .leading)

            Text(ageBadgeText(at: referenceDate))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(columnColor(for: presence))
                .frame(width: FlightDeckSessionRowGrid.timeColumnWidth, alignment: .trailing)

            detailToggleButton(isOpen: isExpanded)

            // Reserve the dismiss lane always, so the time column doesn't shift
            // between dismissible and non-dismissible rows.
            if let dismiss = actions.dismiss {
                DismissButton(action: dismiss, lang: lang)
            } else {
                Color.clear.frame(
                    width: FlightDeckSessionRowGrid.dismissColumnWidth,
                    height: IslandSessionRowMetrics.trailingControlHeight
                )
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// A registered trailing cell. An em-dash placeholder holds the lane when a
    /// value is absent so the columns keep their vertical register — and never
    /// prints "Unknown" (AC #2).
    private func columnText(_ value: String?, presence: IslandSessionPresence, alignment: TextAlignment) -> some View {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValue = !(trimmed?.isEmpty ?? true)
        return Text(hasValue ? trimmed! : "—")
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(hasValue ? columnColor(for: presence) : placeholderColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(alignment)
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
                    flightDeckJumpButton
                }
            }
        }
        .padding(.leading, detailLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.bottom, 12)
    }

    /// The Jump affordance in the Flight Deck idiom: an uppercase mono label in a
    /// squared hairline frame with no fill (AC #4).
    private var flightDeckJumpButton: some View {
        Button {
            actions.jump()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9.5, weight: .semibold))
                    .accessibilityHidden(true)
                Text(FlightDeckText.caps(lang.t("island.flightDeck.row.jump"), lang: lang))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(FlightDeckText.tracking(0.8, lang: lang))
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
        .accessibilityLabel(lang.t("island.flightDeck.row.jump"))
    }

    // MARK: - Leading mark (the four indicator preferences)

    /// The in-row leading mark that layers **on top of** the always-present
    /// status lane, per the user's `IslandSessionStateIndicator` preference:
    /// `.animatedDot` seats a square annunciator lamp, `.glyph` a status glyph.
    /// `.bar` draws no in-row mark (the lane subsumes it) and `.tint` carries the
    /// state in the headline colour / row wash instead — both handled by
    /// `showsLeadingMark` returning false.
    @ViewBuilder
    private func leadingMark(for presence: IslandSessionPresence) -> some View {
        let tint = statusTint(for: presence)
        switch stateIndicator {
        case .glyph:
            Image(systemName: FlightDeckSessionRowFormat.statusGlyphName(phase: session.phase, outcome: session.outcome))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 20, alignment: .top)
                .padding(.top, 2)
        case .animatedDot:
            annunciatorLamp(tint: tint, presence: presence)
        case .bar, .tint:
            EmptyView()
        }
    }

    /// The `.animatedDot` mark in the Flight Deck idiom: a flat square lamp (never
    /// a round dot). It holds steady — the always-present lane is the row's
    /// animated element — so a non-success completion instead shows its distinct
    /// glyph here, keeping interrupted / failed unmistakable at a glance.
    @ViewBuilder
    private func annunciatorLamp(tint: Color, presence: IslandSessionPresence) -> some View {
        if session.phase == .completed, session.outcome != .success {
            Image(systemName: FlightDeckSessionRowFormat.statusGlyphName(phase: session.phase, outcome: session.outcome))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 20, alignment: .top)
                .padding(.top, 2)
        } else if session.phase == .completed, session.outcome == .success, presence != .inactive {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 20, alignment: .top)
                .padding(.top, 2)
        } else {
            Rectangle()
                .fill(tint.opacity(presence == .inactive ? 0.55 : 1))
                .frame(width: 8, height: 8)
                .frame(width: 14, height: 20, alignment: .top)
                .padding(.top, 5)
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
                    width: FlightDeckSessionRowGrid.detailToggleColumnWidth,
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
        FlightDeckSessionRowFormat.displayHeadline(
            headline: session.spotlightHeadlineText,
            workspace: session.spotlightWorkspaceName,
            fallback: session.tool.displayName
        )
    }

    private var appColumnText: String? {
        FlightDeckSessionRowFormat.appColumnText(
            isRemote: session.isRemote,
            terminalBadge: session.spotlightTerminalBadge
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

    /// The lane is the Flight Deck identity — it rides the left edge of every
    /// list row under every indicator preference (the `.bar` preference is
    /// subsumed by it). It is suppressed only in the notification presentation,
    /// where the single card carries no lane gutter.
    private var showsStatusLane: Bool {
        presentation == .list
    }

    /// The in-row leading mark (dot / glyph) is drawn for `.animatedDot` and
    /// `.glyph` only; `.bar` and `.tint` carry state through the lane / wash.
    private var showsLeadingMark: Bool {
        presentation == .list && (stateIndicator == .animatedDot || stateIndicator == .glyph)
    }

    private var laneLeadingInset: CGFloat { 5 }

    private var rowLeadingInset: CGFloat {
        if presentation == .notification { return sideInset }
        // The lane floats in the left gutter as a non-consuming overlay, so the
        // headline keeps the same leading as the SESSION caption above it.
        return sideInset
    }

    private var detailLeadingInset: CGFloat {
        if presentation == .notification { return sideInset }
        return showsLeadingMark ? sideInset + 28 : sideInset
    }
}

// MARK: - Flight Deck status lane

/// The colored EICAS warning-light lane on the row's left edge. A flat squared
/// bar (no fillet, the Flight Deck idiom) that fills the row's height. Live
/// lanes pulse off the shared 15fps clock; settled lanes — and any lane under
/// Reduce Motion — hold a steady bar at their resting opacity.
private struct FlightDeckStatusLane: View {
    let color: Color
    let width: CGFloat
    let restingOpacity: Double
    let pulses: Bool
    let pulseClock: PulseClock?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if pulses, !reduceMotion, let pulseClock {
            FlightDeckPulsingLane(color: color, width: width, pulseClock: pulseClock)
        } else {
            Rectangle()
                .fill(color.opacity(restingOpacity))
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
}

/// The pulsing lane, isolated in its own `View` so Observation's per-view
/// tracking invalidates only this bar at 15fps (AB-228), and so Reduce Motion
/// never even acquires the shared clock — the steady bar is drawn instead
/// (AB-244). The blink is a crisp two-step (mechanical), not a breathe.
private struct FlightDeckPulsingLane: View {
    let color: Color
    let width: CGFloat
    let pulseClock: PulseClock

    var body: some View {
        Rectangle()
            .fill(color.opacity(FlightDeckSessionRowFormat.pulseOpacity(phase: pulseClock.phase, reduceMotion: false)))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .onAppear { pulseClock.acquire() }
            .onDisappear { pulseClock.release() }
            .accessibilityHidden(true)
    }
}

/// Attaches a named VoiceOver action only when `name` is non-nil — the row's
/// "Dismiss" rotor action, present only for dismissible rows. A local copy of
/// the same modifier Classic's row uses.
private struct FlightDeckOptionalNamedAccessibilityAction: ViewModifier {
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
