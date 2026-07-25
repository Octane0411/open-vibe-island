import AppKit
import SwiftUI
import OpenIslandCore

/// Annual's session row (AB-317 · annual 3/4).
///
/// The editorial re-skin of `IslandSessionRow` for the **non-actionable** states —
/// running, done (success / interrupted / failed), idle-stale, SSH and demo —
/// across the `.list` and `.notification` presentations. There is not one pill,
/// chip or capsule anywhere: the row is a quiet typographic entry. A workspace
/// headline sits over a single **lowercase mono meta line** ("claude · fable 5 ·
/// ghostty") set behind a **6px brand square**; the time is right-aligned in one
/// fixed lane so every row's time lands on the same x. Status reads through the
/// theme's **dot grammar** — a filled dot for a running turn (a subtle pulse off
/// the shared clock, static under Reduce Motion), a hollow **ring** for a clean
/// finish, a **dim** dot for idle, and the one **accent** dot pulsing for an
/// attention row; interrupted / failed completions swap the dot for a distinct
/// glyph (plus wording), and — since a completed row does not require attention —
/// they stay warm grey, so a mixed list with no attention session carries zero
/// accent pixels. Expanding a row draws a **marginalia left hairline** rail
/// holding the prompt, the trailing activity, a Transcript affordance and the Jump
/// action.
///
/// **Actionable rows still route to Classic (the AB-318 seam).** A permission
/// request, a pending question and the completion card keep the shared
/// `IslandSessionRow` interior for this slice — it already reads the Annual tokens
/// from the environment, so it inherits the warm ground and calm palette — and
/// AB-318 (annual 4/4) replaces that seam with the editorial alarm, question and
/// notification card. The behaviours that are contract-level — the jump tap, the
/// dismiss action and the grouped VoiceOver summary — are preserved verbatim so
/// the two rows stay interchangeable inside one list.
struct AnnualSessionRow: View {
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
    /// Shared 15fps clock for the pulsing dot (AB-228). Passed through to the leaf
    /// dot view; rows that don't animate never touch it.
    var pulseClock: PulseClock?

    var body: some View {
        if isActionable {
            // AB-317 leaves the actionable interiors on the shared Classic row
            // (the seam AB-318 replaces with Annual's editorial alarm / question /
            // notification card). Classic reads the Annual tokens from the
            // environment, so a routed actionable row still sits on the warm
            // ground with the calm palette.
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
            AnnualRowContent(
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

// MARK: - Geometry

/// Annual's row geometry. The time lane is a single fixed width so every row's
/// time lands on the same x (AC #1), and the interactive controls carry hit
/// targets at or above the 24×24pt floor even where the visible glyph is small
/// (AC #5). Literal points, deliberately not type-scaled, matching
/// `IslandSessionRowMetrics`.
enum AnnualSessionRowGrid {
    /// The single right-aligned time column, shared with the classic age lane so
    /// the time register is a constant width across rows.
    static let timeColumnWidth: CGFloat = IslandSessionRowMetrics.ageColumnWidth

    /// The 6px agent brand square that heads the meta line.
    static let brandSquareSize: CGFloat = 6

    /// Leading lane the status dot / glyph sits in.
    static let indicatorLaneWidth: CGFloat = 18

    /// The `.bar` preference's marginalia rule width (the 2px emphasis weight).
    static let barRuleWidth: CGFloat = AnnualHairline.rule

    // Interactive control hit targets — all ≥ `minHitTarget` (AC #5).
    static let minHitTarget: CGFloat = 24
    static let controlHeight: CGFloat = 28
    static let chevronHitWidth: CGFloat = 28
    static let dismissHitWidth: CGFloat = 24
    static let jumpMinHeight: CGFloat = 24
    static let transcriptMinHeight: CGFloat = 24

    /// Every interactive control's effective hit target (the shorter dimension),
    /// for the ≥24pt assertion the AC-bearing hit-area test pins.
    static var controlHitTargets: [CGFloat] {
        [
            min(chevronHitWidth, controlHeight),
            min(dismissHitWidth, controlHeight),
            jumpMinHeight,
            transcriptMinHeight,
        ]
    }
}

// MARK: - Pure, testable row logic

/// Pure formatting / mapping helpers, split out so the display rules the AC pins
/// (the dot-grammar state mapping, the one-accent discipline, the meta line, the
/// "Unknown" guard, the SSH cell, the interrupted/failed glyph, the motion-gated
/// pulse, the ≥10pt floor) are unit-testable without rendering a SwiftUI view.
enum AnnualSessionRowFormat {
    /// The six status marks the dot grammar resolves to. `running` / `attention`
    /// are the live, pulsing marks; `done` is the settled ring; `idle` the dim
    /// dot; and `interrupted` / `failed` swap the dot for a distinct glyph so a
    /// non-success completion never reads the same as a clean finish.
    enum StatusMark: CaseIterable {
        case running
        case done
        case idle
        case attention
        case interrupted
        case failed
    }

    /// Maps a row's phase / presence / outcome onto its dot-grammar mark. `idle`
    /// (inactive presence) always wins so a stale completed row recedes to the dim
    /// dot regardless of its stored outcome.
    static func statusMark(
        phase: SessionPhase,
        presence: IslandSessionPresence,
        outcome: SessionOutcome
    ) -> StatusMark {
        if presence == .inactive { return .idle }
        switch phase {
        case .waitingForApproval, .waitingForAnswer:
            return .attention
        case .running:
            return .running
        case .completed:
            switch outcome {
            case .success: return .done
            case .interrupted: return .interrupted
            case .failed: return .failed
            }
        }
    }

    /// The one-accent discipline, pinned as pure logic: **only** a genuine
    /// attention mark spends the theme's single accent. Every calm mark — running,
    /// done, idle — and both non-success completions (interrupted / failed) stay
    /// warm grey, because a completed row does not require attention. This is the
    /// code-level guarantee behind "a mixed list with no attention session shows
    /// zero accent pixels" (AC #8); the pixel screenshot is flagged manual.
    static func spendsAccent(_ mark: StatusMark) -> Bool {
        mark == .attention
    }

    /// Whether the mark pulses (AC #2): the two live states — a running turn and
    /// an attention phase — breathe; every settled outcome holds steady. The view
    /// layer gates this on Reduce Motion so the pulse is static when motion is off.
    static func pulses(phase: SessionPhase, presence: IslandSessionPresence) -> Bool {
        presence == .running || phase.requiresAttention
    }

    /// The pulsing dot's opacity (AC #2): a subtle, slow breathe off the shared
    /// clock's phase — never a hard blink — pinned fully lit (static) under Reduce
    /// Motion. Stays a legible, in-range opacity throughout.
    static func pulseOpacity(phase: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        let triangle = phase < 0.5 ? phase * 2 : (1 - phase) * 2  // 0 → 1 → 0
        return 0.55 + triangle * 0.45                             // 0.55 … 1.0
    }

    /// Row rhythm: `done` (a fresh completed row) is a single line; `running` and
    /// `idle` carry a second activity/prompt sub-line under the meta line.
    static func showsSubLine(isRunning: Bool, isIdle: Bool) -> Bool {
        isRunning || isIdle
    }

    /// Never surface a bare "Unknown" workspace (AC #1 / AB-282…286): when the
    /// resolved workspace is the "Unknown" sentinel, substitute the agent's
    /// display name inside the headline instead.
    static func displayHeadline(headline: String, workspace: String, fallback: String) -> String {
        guard workspace == JumpTarget.unknownTerminalApp else { return headline }
        let replaced = headline.replacingOccurrences(of: workspace, with: fallback)
        return replaced.isEmpty ? fallback : replaced
    }

    /// The meta line's ordered pieces (AC #1): the lowercase agent name, the
    /// vendor-free model (dropped when absent), and the app — a remote session
    /// reads `ssh` so the SSH state renders within the line, a local session shows
    /// its terminal / IDE, and a session with neither drops the piece rather than
    /// printing a bare "Unknown". Every piece is lowercased for the editorial
    /// idiom (a no-op on CJK, which is uncased).
    static func metaPieces(
        agent: String,
        model: String?,
        isRemote: Bool,
        terminal: String?
    ) -> [String] {
        var pieces: [String] = [agent.lowercased()]
        if let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            pieces.append(model.lowercased())
        }
        if isRemote {
            pieces.append("ssh")
        } else if let terminal = terminal?.trimmingCharacters(in: .whitespacesAndNewlines), !terminal.isEmpty {
            pieces.append(terminal.lowercased())
        }
        return pieces
    }

    /// The joined meta line, e.g. `claude · fable 5 · ghostty`.
    static func metaLine(
        agent: String,
        model: String?,
        isRemote: Bool,
        terminal: String?
    ) -> String {
        metaPieces(agent: agent, model: model, isRemote: isRemote, terminal: terminal)
            .joined(separator: " · ")
    }

    /// The status glyph (AC #2): a quiet check for a clean finish, and distinct
    /// stop / cross glyphs so interrupted and failed completions never read the
    /// same as a success — the mark used by the `.glyph` indicator preference and
    /// the interrupted / failed swap under `.animatedDot`.
    static func statusGlyphName(phase: SessionPhase, outcome: SessionOutcome) -> String {
        switch phase {
        case .waitingForApproval:
            return "exclamationmark.triangle.fill"
        case .waitingForAnswer:
            return "questionmark.circle.fill"
        case .running:
            return "circle.fill"
        case .completed:
            switch outcome {
            case .success: return "checkmark"
            case .interrupted: return "stop.fill"
            case .failed: return "xmark"
            }
        }
    }

    /// Every readable point size the Annual row draws, for the ≥10pt-floor
    /// assertion (AC #7). No readable role dips below the theme's `floor`.
    static let readableTextSizes: [CGFloat] = [13.2, 11.5, 11, 10.5]
}

// MARK: - Row content

/// The editorial body for every non-actionable Annual row.
private struct AnnualRowContent: View {
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

    /// The same one-reference type ramp Classic uses — every scaled reading size
    /// is expressed relative to this so the whole row scales together off one
    /// measurement (AC #7). The fixed time lane is deliberately left unscaled (see
    /// `IslandSessionRowMetrics`).
    @ScaledMetric(relativeTo: .body) private var typeScaleReference: CGFloat = 13
    private var typeScale: CGFloat { typeScaleReference / 13 }

    private func scaledMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
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
        // Annual's rhythm reads presence directly: a fresh completed row is `done`
        // (1 line), everything inactive is `idle` (2 lines, receded).
        let presence: IslandSessionPresence = isStaleCompleted ? .inactive : rawPresence
        let isRunning = presence == .running
        let isIdle = presence == .inactive
        let showsSubLine = AnnualSessionRowFormat.showsSubLine(isRunning: isRunning, isIdle: isIdle)
        let isExpanded = (expandedOverride ?? false) && isInteractive
        let mark = AnnualSessionRowFormat.statusMark(
            phase: session.phase,
            presence: presence,
            outcome: session.outcome
        )

        return VStack(alignment: .leading, spacing: 0) {
            rowSummary(
                mark: mark,
                presence: presence,
                showsSubLine: showsSubLine,
                isExpanded: isExpanded,
                referenceDate: referenceDate
            )

            if isExpanded {
                expandedDetails(presence: presence)
            }
        }
        .background(rowFillColor(mark: mark, presence: presence))
        // The 1px section hairline — the theme's structural divider, never a box.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: AnnualHairline.hairline)
        }
        .overlay(alignment: .leading) {
            if showsLeadingStatusBar {
                // The `.bar` preference maps the dot grammar onto a marginalia
                // rule: the 2px emphasis weight in the mark's tint (accent only
                // for attention), the editorial answer to a status bar.
                Rectangle()
                    .fill(markTint(mark))
                    .frame(width: AnnualSessionRowGrid.barRuleWidth)
                    .padding(.vertical, showsSubLine ? 10 : 8)
                    .padding(.leading, 16)
                    .accessibilityHidden(true)
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

    // MARK: - Summary (headline + meta line + time)

    private func rowSummary(
        mark: AnnualSessionRowFormat.StatusMark,
        presence: IslandSessionPresence,
        showsSubLine: Bool,
        isExpanded: Bool,
        referenceDate: Date
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if showsLeadingStatusIndicator {
                statusIndicator(mark: mark)
                    .frame(width: AnnualSessionRowGrid.indicatorLaneWidth, alignment: .top)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayHeadline)
                    .font(scaledMono(13.2, weight: .semibold))
                    .foregroundStyle(titleColor(mark: mark, presence: presence))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Full name one hover away — the line truncates, the tooltip
                    // does not (AC #1: no wraps).
                    .help(session.spotlightWorkspaceName)

                metaLineView(presence: presence)

                if showsSubLine, let subLine = summarySubLineText(presence: presence) {
                    Text(subLine)
                        .font(scaledMono(11, weight: .regular))
                        .foregroundStyle(subLineColor(for: presence))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 10)

            trailingCluster(presence: presence, isExpanded: isExpanded, referenceDate: referenceDate)
        }
        .padding(.leading, rowLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.top, 12)
        .padding(.bottom, showsSubLine ? 10 : 12)
        // The one grouped VoiceOver summary, identical wording to Classic and the
        // other themes so rows read the same however they're skinned (AC #7).
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
        .modifier(AnnualOptionalNamedAccessibilityAction(
            name: actions.dismiss != nil ? lang.t("a11y.session.dismiss") : nil,
            action: { actions.dismiss?() }
        ))
    }

    /// The quiet lowercase mono meta line behind a 6px brand square (AC #1). No
    /// pill or capsule — the agent identity is only the flat colored square.
    private func metaLineView(presence: IslandSessionPresence) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(brandColor.opacity(presence == .inactive ? 0.5 : 1))
                .frame(width: AnnualSessionRowGrid.brandSquareSize, height: AnnualSessionRowGrid.brandSquareSize)
                .accessibilityHidden(true)

            Text(metaLineText)
                .font(scaledMono(10.5, weight: .regular))
                .tracking(AnnualText.tracking(0.2, lang: lang))
                .foregroundStyle(metaColor(for: presence))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// The trailing block: the time in its single fixed lane (so every row's time
    /// lands on the same x, AC #1), then the chevron and — always reserved — the
    /// dismiss lane, so the time register never shifts between dismissible and
    /// non-dismissible rows.
    private func trailingCluster(
        presence: IslandSessionPresence,
        isExpanded: Bool,
        referenceDate: Date
    ) -> some View {
        HStack(spacing: 4) {
            Text(ageBadgeText(at: referenceDate))
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(columnColor(for: presence))
                .lineLimit(1)
                .frame(width: AnnualSessionRowGrid.timeColumnWidth, alignment: .trailing)

            detailToggleButton(isOpen: isExpanded)

            if let dismiss = actions.dismiss {
                AnnualDismissButton(action: dismiss, lang: lang)
            } else {
                Color.clear.frame(
                    width: AnnualSessionRowGrid.dismissHitWidth,
                    height: AnnualSessionRowGrid.controlHeight
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Expanded details (marginalia rail)

    /// The expanded interior on a **marginalia left hairline** rail (AC #3): the
    /// prompt, the trailing activity, a Transcript affordance and the Jump action,
    /// all held to the right of a single 1px rule in the left margin — the
    /// editorial marginalia idiom, no box.
    @ViewBuilder
    private func expandedDetails(presence: IslandSessionPresence) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast) * 2.2))
                .frame(width: AnnualHairline.hairline)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                if let prompt = expandedPromptLineText {
                    Text(prompt)
                        .font(scaledMono(11, weight: .regular))
                        .foregroundStyle(subLineColor(for: presence))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let activity = expandedActivityLineText {
                    Text(activity)
                        .font(scaledMono(11.5, weight: .regular))
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 14) {
                    if let transcriptPath = session.trackingTranscriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !transcriptPath.isEmpty {
                        TranscriptAffordance(
                            path: transcriptPath,
                            workspace: session.spotlightWorkspaceName,
                            lang: lang
                        )
                        .frame(minHeight: AnnualSessionRowGrid.transcriptMinHeight)
                        .contentShape(Rectangle())
                    }

                    Spacer(minLength: 0)

                    if isInteractive {
                        AnnualJumpButton(lang: lang, tokens: tokens, increasesContrast: increasesContrast) {
                            actions.jump()
                        }
                    }
                }
            }
        }
        .padding(.leading, detailLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.bottom, 13)
    }

    // MARK: - Status indicator (all four preferences → dot grammar)

    /// Maps the user's `IslandSessionStateIndicator` preference onto the dot
    /// grammar (AC #4). `.animatedDot` is the signature — the filled / ring / dim /
    /// accent-pulse dots with the interrupted / failed glyph swap; `.glyph` prints
    /// the status glyph directly. `.bar` (a marginalia rule) and `.tint` (the
    /// state carried through the headline colour + a faint wash) draw no in-row
    /// dot and are handled by `showsLeadingStatusIndicator` returning false.
    @ViewBuilder
    private func statusIndicator(mark: AnnualSessionRowFormat.StatusMark) -> some View {
        switch stateIndicator {
        case .glyph:
            Image(systemName: AnnualSessionRowFormat.statusGlyphName(phase: session.phase, outcome: session.outcome))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(markTint(mark))
                .frame(width: 14, height: 18, alignment: .top)
        case .animatedDot:
            dotGrammarMark(mark)
        case .bar, .tint:
            EmptyView()
        }
    }

    /// The dot grammar under `.animatedDot`: a filled dot for a running turn and
    /// an accent dot for attention (both pulsing off the shared clock, static
    /// under Reduce Motion); a hollow ring for a clean finish; a dim dot for idle;
    /// and a distinct glyph for a non-success completion so interrupted / failed
    /// stay unmistakable at a glance.
    @ViewBuilder
    private func dotGrammarMark(_ mark: AnnualSessionRowFormat.StatusMark) -> some View {
        let tint = markTint(mark)
        switch mark {
        case .running, .attention:
            AnnualPulsingDot(tint: tint, pulseClock: pulseClock)
                .frame(width: 14, height: 18, alignment: .top)
                .padding(.top, 2)
        case .done:
            Circle()
                .strokeBorder(tint, lineWidth: 1.5)
                .frame(width: 9, height: 9)
                .frame(width: 14, height: 18, alignment: .top)
                .padding(.top, 2)
        case .idle:
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .frame(width: 14, height: 18, alignment: .top)
                .padding(.top, 2)
        case .interrupted, .failed:
            Image(systemName: AnnualSessionRowFormat.statusGlyphName(phase: session.phase, outcome: session.outcome))
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 18, alignment: .top)
                .padding(.top, 1)
        }
    }

    // MARK: - Trailing controls

    private func detailToggleButton(isOpen: Bool) -> some View {
        Button {
            toggleExpanded(currentlyOpen: isOpen)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tokens.colors.paper.opacity(isOpen || isHighlighted ? 0.7 : 0.4))
                .frame(
                    width: AnnualSessionRowGrid.chevronHitWidth,
                    height: AnnualSessionRowGrid.controlHeight
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
        AnnualSessionRowFormat.displayHeadline(
            headline: session.spotlightHeadlineText,
            workspace: session.spotlightWorkspaceName,
            fallback: session.tool.displayName
        )
    }

    private var brandColor: Color {
        Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper
    }

    private var metaLineText: String {
        AnnualSessionRowFormat.metaLine(
            agent: agentName,
            model: session.displayModelName,
            isRemote: session.isRemote,
            terminal: session.spotlightTerminalBadge
        )
    }

    private var agentName: String {
        switch session.tool {
        case .claudeCode: return "claude"
        case .geminiCLI: return "gemini"
        case .qwenCode: return "qwen"
        case .kimiCLI: return "kimi"
        default: return session.tool.shortName.lowercased()
        }
    }

    private func summarySubLineText(presence: IslandSessionPresence) -> String? {
        if presence == .running {
            return runningLineText
        }
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

    /// The one-accent discipline made concrete (AC #8): only an attention mark
    /// resolves to the accent; every calm mark and both non-success completions
    /// stay warm paper / grey, so a mixed list with no attention row is accent-free.
    private func markTint(_ mark: AnnualSessionRowFormat.StatusMark) -> Color {
        switch mark {
        case .attention:
            return tokens.colors.statusWaitingAggregate
        case .running:
            return tokens.colors.paper.opacity(contrastText(0.92))
        case .done:
            return tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity))
        case .interrupted, .failed:
            return tokens.colors.paper.opacity(contrastText(0.72))
        case .idle:
            return tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
        }
    }

    private func titleColor(mark: AnnualSessionRowFormat.StatusMark, presence: IslandSessionPresence) -> Color {
        // The `.tint` preference carries state in the headline: an attention row's
        // headline goes accent; every calm row stays warm paper (dimmed when idle).
        if stateIndicator == .tint, AnnualSessionRowFormat.spendsAccent(mark) {
            return tokens.colors.statusWaitingAggregate
        }
        if isHighlighted {
            return tokens.colors.paper
        }
        return presence == .inactive
            ? tokens.colors.paper.opacity(0.78)
            : tokens.colors.paper.opacity(contrastText(0.95))
    }

    private func subLineColor(for presence: IslandSessionPresence) -> Color {
        tokens.colors.paper.opacity(contrastText(
            presence == .inactive ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity
        ))
    }

    private func metaColor(for presence: IslandSessionPresence) -> Color {
        tokens.colors.paper.opacity(contrastText(
            presence == .inactive ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity
        ))
    }

    private func columnColor(for presence: IslandSessionPresence) -> Color {
        tokens.colors.paper.opacity(contrastText(
            presence == .inactive ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity
        ))
    }

    /// A typographic (not boxy) hover highlight (AC #3): a whisper-faint flat band
    /// — no fillet, no frame — that raises the hovered list row. The `.tint`
    /// preference layers its state wash on top: accent for an attention row, warm
    /// paper for a calm one, so accent discipline holds.
    private func rowFillColor(
        mark: AnnualSessionRowFormat.StatusMark,
        presence: IslandSessionPresence
    ) -> Color {
        if presentation == .notification { return .clear }
        let hoverBand = isHighlighted ? tokens.colors.paper.opacity(0.03) : Color.clear
        guard stateIndicator == .tint else { return hoverBand }

        if AnnualSessionRowFormat.spendsAccent(mark) {
            return tokens.colors.statusWaitingAggregate.opacity(isHighlighted ? 0.12 : 0.07)
        }
        let calm = presence == .inactive ? 0.02 : 0.05
        return tokens.colors.paper.opacity(isHighlighted ? 0.06 : calm)
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

// MARK: - Dot grammar leaves

/// A pulsing dot — the filled running / accent attention mark. Isolated in its
/// own `View` so Observation's per-view tracking invalidates only this dot at
/// 15fps (AB-228), and so Reduce Motion never even acquires the shared clock — a
/// steady dot is drawn instead (AB-244). The pulse is a subtle, slow breathe, not
/// a hard blink.
private struct AnnualPulsingDot: View {
    let tint: Color
    let pulseClock: PulseClock?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let pulseClock, !reduceMotion {
            AnnualClockedDot(tint: tint, pulseClock: pulseClock)
        } else {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
    }
}

private struct AnnualClockedDot: View {
    let tint: Color
    let pulseClock: PulseClock

    var body: some View {
        Circle()
            .fill(tint.opacity(AnnualSessionRowFormat.pulseOpacity(phase: pulseClock.phase, reduceMotion: false)))
            .frame(width: 8, height: 8)
            .onAppear { pulseClock.acquire() }
            .onDisappear { pulseClock.release() }
            .accessibilityHidden(true)
    }
}

// MARK: - Interactive affordances (≥24×24 hit targets)

/// The dismiss control in the editorial idiom — a quiet ✕ glyph carrying a
/// ≥24×24pt effective hit target via `contentShape`, even though the glyph is
/// small (AC #5). A local copy so Annual can widen the hit lane beyond the shared
/// 16pt `DismissButton`.
private struct AnnualDismissButton: View {
    let action: () -> Void
    var lang: LanguageManager = .shared
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovered ? 0.8 : 0.4))
                .frame(
                    width: AnnualSessionRowGrid.dismissHitWidth,
                    height: AnnualSessionRowGrid.controlHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(lang.t("a11y.session.dismiss"))
    }
}

/// The Jump affordance in the editorial idiom (AC #3): a quiet lowercase mono
/// label with a small arrow, underlined by a hairline rather than boxed in a pill,
/// carrying a ≥24pt-tall hit target via padding + `contentShape` (AC #5).
private struct AnnualJumpButton: View {
    let lang: LanguageManager
    let tokens: IslandThemeTokens
    let increasesContrast: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(AnnualText.lower(lang.t("island.annual.row.jump"), lang: lang))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(AnnualText.tracking(0.4, lang: lang))
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.82, increaseContrast: increasesContrast)))
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast) * 2.2))
                    .frame(height: AnnualHairline.hairline)
                    .padding(.horizontal, -1)
                    .offset(y: -3)
            }
            .frame(minHeight: AnnualSessionRowGrid.jumpMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t("island.annual.row.jump"))
    }
}

/// Attaches a named VoiceOver action only when `name` is non-nil — the row's
/// "Dismiss" rotor action, present only for dismissible rows. A local copy of the
/// same modifier Classic's row uses.
private struct AnnualOptionalNamedAccessibilityAction: ViewModifier {
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
