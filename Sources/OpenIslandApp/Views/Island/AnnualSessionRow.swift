import AppKit
import SwiftUI
@preconcurrency import MarkdownUI
import OpenIslandCore

/// Annual's session row (AB-317 · annual 3/4, actionable surfaces AB-318 · annual 4/4).
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
/// **Actionable rows are now fully Annual (AB-318).** A permission request draws
/// the editorial **typographic alarm** — a 2px accent rule, a small-caps
/// `permission required` kicker, the command in a left-ruled mono quote above the
/// affected-path line and `PermissionDiffPreview`, and understated `allow` / `deny`
/// text buttons carrying the real ⌘Y / ⌘⇧Y / ⌘N key-hints with strong contrast on
/// `allow` — via `AnnualApprovalCard`; the question reuses the shared, token-driven
/// `StructuredQuestionPromptView`, and the completion is a quiet editorial markdown
/// card. There is not one pill, chip or capsule anywhere — hierarchy is purely
/// typographic, and the single accent appears **only** on the alarm and the pending
/// question, never on a completion or a calm surface. The behaviours that are
/// contract-level — the jump tap, the ⌘Y / ⌘⇧Y / ⌘N approval wiring and the 1–9 /
/// Enter question shortcuts (both driven globally from `OverlayPanelController`),
/// the reply callback, the dismiss action and the grouped VoiceOver summary — are
/// preserved verbatim so the two rows stay interchangeable inside one list. The
/// notification card reuses this seam automatically: `IslandNotificationCard` routes
/// its single row through `theme.sessionRow(isActionable: true)`, so the single
/// actionable session gets the same typographic alarm with no card-specific fork.
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
            // AB-318: the approval (typographic alarm) / question / completion
            // interiors are now drawn in the Annual editorial idiom by
            // `AnnualActionableRowContent` (the old thin seam to Classic is gone).
            // The header keeps the same editorial headline + meta idiom so an
            // actionable row still reads as one of the list.
            AnnualActionableRowContent(
                session: session,
                stateIndicator: stateIndicator,
                completedStaleThreshold: completedStaleThreshold,
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

// MARK: - Actionable surface logic (AB-318)

/// Pure display rules for the Annual typographic alarm / completion surfaces,
/// split out so the AC-bearing decisions (which key-hint glyph a button carries,
/// which glyph a non-success completion shows, and the ≥10pt floor on the alarm
/// block) are unit-testable without rendering a SwiftUI view.
enum AnnualApprovalFormat {
    /// The three approval decisions the typographic alarm exposes, each paired
    /// with the **real** registered `OverlayPanelController` shortcut it fires. The
    /// glyph strings the `allow` / `deny` / always-allow buttons print must stay in
    /// lock-step with that handler (`⌘Y` / `⌘⇧Y` / `⌘N`), never the mockup's ⏎/⎋.
    enum Shortcut: CaseIterable {
        case allowOnce
        case alwaysAllow
        case deny

        /// The key-hint glyphs printed on the button, in order.
        var glyphs: [String] {
            switch self {
            case .allowOnce: return ["⌘", "Y"]
            case .alwaysAllow: return ["⌘", "⇧", "Y"]
            case .deny: return ["⌘", "N"]
            }
        }

        /// The joined glyph string (e.g. `⌘⇧Y`) — the a11y / test-facing form.
        var glyphString: String { glyphs.joined() }
    }

    /// The completion outcome glyph (AC #4 / editorial): a stop for an interrupted
    /// turn, a cross for a failure. Only ever shown for a non-success outcome — and
    /// drawn in warm grey, never the accent, so a completed row never competes with
    /// the permission row for the panel's single accent (AC #6).
    static func completionOutcomeGlyphName(outcome: SessionOutcome) -> String {
        outcome == .failed ? "xmark" : "stop.fill"
    }

    /// Every readable point size the alarm / completion surfaces draw, for the
    /// ≥10pt-floor assertion — no sub-10pt micro-type anywhere on the alarm.
    static let readableTextSizes: [CGFloat] = [13.2, 12, 11.5, 11, 10.5, 10]
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

// MARK: - Actionable row content (AB-318)

/// The Annual body for an **actionable** row — a permission request (the
/// typographic alarm), a question, or the single completion card — across the
/// `.list` and `.notification` presentations. An editorial header (a leading
/// dot-grammar mark, the workspace headline over a prompt line, and the time in
/// its fixed lane) sits above the phase-specific interior: `AnnualApprovalCard`
/// for approvals, the shared, token-driven `StructuredQuestionPromptView` for
/// questions, and a quiet editorial markdown card for completions. The header
/// carries the same grouped VoiceOver summary as every other theme, and the
/// tap-to-jump / dismiss behaviours are preserved verbatim from Classic.
private struct AnnualActionableRowContent: View {
    let session: AgentSession
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let isInteractive: Bool
    let isHighlighted: Bool
    let presentation: IslandSessionRowPresentation
    let sideInset: CGFloat
    let lang: LanguageManager
    let actions: RowActions
    let keyboardCoordinator: OverlayUICoordinator?
    let pulseClock: PulseClock?

    @State private var replyText: String = ""

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

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
        VStack(alignment: .leading, spacing: 0) {
            header(referenceDate: referenceDate)

            if showsActionableBody {
                actionableBody
                    .padding(.leading, detailLeadingInset)
                    .padding(.trailing, sideInset)
                    .padding(.bottom, 13)
            }
        }
        .background(rowFillColor)
        // The 1px section hairline — the theme's structural divider, never a box.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: AnnualHairline.hairline)
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.12), value: isHighlighted)
        .animation(.easeInOut(duration: 0.16), value: session.phase)
        .animation(.easeInOut(duration: 0.16), value: session.outcome)
        .onTapGesture(perform: handlePrimaryTap)
    }

    // MARK: - Header (editorial headline + meta idiom)

    private func header(referenceDate: Date) -> some View {
        let mark = AnnualSessionRowFormat.statusMark(
            phase: session.phase,
            presence: .active,
            outcome: session.outcome
        )
        return HStack(alignment: .top, spacing: 10) {
            if showsLeadingStatusIndicator {
                leadingIndicator(mark: mark)
                    .frame(width: AnnualSessionRowGrid.indicatorLaneWidth, alignment: .top)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayHeadline)
                    .font(scaledMono(13.2, weight: .semibold))
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.95)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(session.spotlightWorkspaceName)

                if let promptLine = headerPromptLineText {
                    Text(promptLine)
                        .font(scaledMono(11, weight: .regular))
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 4) {
                Text(ageBadgeText(at: referenceDate))
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
                    .lineLimit(1)
                    .frame(width: AnnualSessionRowGrid.timeColumnWidth, alignment: .trailing)

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
        .padding(.leading, rowLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.top, 12)
        .padding(.bottom, showsActionableBody ? 8 : 12)
        // The one grouped VoiceOver summary, identical wording to every theme so
        // rows read the same however they're skinned (AC #7).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityRowSummaryText(referenceDate: referenceDate))
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        .accessibilityAction {
            guard isInteractive else { return }
            actions.jump()
        }
        .modifier(AnnualOptionalNamedAccessibilityAction(
            name: actions.dismiss != nil ? lang.t("a11y.session.dismiss") : nil,
            action: { actions.dismiss?() }
        ))
    }

    /// The leading dot-grammar mark for the actionable header: a pulsing accent dot
    /// for an attention phase (the alarm's live signal, static under Reduce Motion),
    /// the settled ring for a clean finish, a distinct grey glyph for a non-success
    /// completion, and the filled paper dot for a running preview.
    @ViewBuilder
    private func leadingIndicator(mark: AnnualSessionRowFormat.StatusMark) -> some View {
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

    /// Only an attention mark spends the accent (AC #6) — every completion mark
    /// stays warm grey, so a completed / running actionable row never lights the
    /// panel's single accent.
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

    // MARK: - Actionable body

    /// Mirrors Classic's gate: attention phases always earn the body, a completed
    /// row only when it has something to show, a running row only with a preview —
    /// so a content-less completed-success row never draws an empty card, just its
    /// header.
    private var showsActionableBody: Bool {
        switch session.phase {
        case .waitingForApproval, .waitingForAnswer:
            return true
        case .completed:
            return completionHasExpandedBody
        case .running:
            return runningDetailText != nil
        }
    }

    private var completionHasExpandedBody: Bool {
        session.outcome != .success
            || !completionMessageText.isEmpty
            || actions.reply != nil
    }

    @ViewBuilder
    private var actionableBody: some View {
        switch session.phase {
        case .waitingForApproval:
            AnnualApprovalCard(session: session, lang: lang, actions: actions, pulseClock: pulseClock)
        case .waitingForAnswer:
            StructuredQuestionPromptView(
                prompt: session.questionPrompt,
                lang: lang,
                keyboardCoordinator: keyboardCoordinator,
                onAnswer: { actions.answer?($0) }
            )
        case .completed:
            completionBody
        case .running:
            if let preview = runningDetailText {
                runningPreviewQuote(preview)
            }
        }
    }

    /// A running preview set as a left-ruled mono quote — the editorial answer to a
    /// bordered box, no fill or fillet.
    private func runningPreviewQuote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast) * 2.2))
                .frame(width: AnnualHairline.hairline)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.82)))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Completion body (quiet editorial markdown card)

    /// The completion card in the editorial idiom: the markdown message inside its
    /// 160pt cap, an optional non-success outcome line (in warm grey — never the
    /// accent, so the accent stays reserved for the permission row), and the reply
    /// field when enabled. A single flat wash and a 1px hairline frame — no fillet,
    /// no pill.
    private var completionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !completionMessageText.isEmpty {
                if session.outcome != .success {
                    completionOutcomeLine
                }

                AutoHeightScrollView(maxHeight: 160) {
                    Markdown(completionMessageText)
                        .markdownTheme(.completionCard(tokens.colors))
                        .markdownImageProvider(.noNetwork)
                        .markdownInlineImageProvider(.noNetwork)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
            } else {
                completionEmptyState
            }

            if actions.reply != nil {
                Rectangle()
                    .fill(tokens.colors.paper.opacity(0.08))
                    .frame(height: AnnualHairline.hairline)

                completionReplyInput
            }
        }
        .background(Rectangle().fill(tokens.colors.paper.opacity(0.035)))
        .overlay(Rectangle().strokeBorder(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast) * 1.6), lineWidth: AnnualHairline.hairline))
    }

    private var completionOutcomeLine: some View {
        HStack(spacing: 6) {
            Image(systemName: AnnualApprovalFormat.completionOutcomeGlyphName(outcome: session.outcome))
                .font(.system(size: 10, weight: .bold))
                .accessibilityHidden(true)
            Text(AnnualText.lower(completionOutcomeLabel, lang: lang))
                .font(AnnualTypography.smallCapsLabel)
                .tracking(AnnualText.tracking(0.4, lang: lang))
            Spacer(minLength: 0)
        }
        .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.72)))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var completionEmptyState: some View {
        HStack {
            Text(AnnualText.lower(completionOutcomeLabel, lang: lang))
                .font(AnnualTypography.smallCapsLabel)
                .tracking(AnnualText.tracking(0.4, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.82)))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
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
                Image(systemName: "arrow.up.square.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? tokens.colors.paper.opacity(0.2) : tokens.colors.paper.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel(lang.t("a11y.completion.sendReply"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func submitReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyText = ""
        actions.reply?(text)
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

    // MARK: - Text helpers

    private var displayHeadline: String {
        AnnualSessionRowFormat.displayHeadline(
            headline: session.spotlightHeadlineText,
            workspace: session.spotlightWorkspaceName,
            fallback: session.tool.displayName
        )
    }

    private var headerPromptLineText: String? {
        if presentation == .notification {
            return session.notificationHeaderPromptLineText
        }
        return session.spotlightPromptLineText
    }

    private var runningDetailText: String? {
        if let preview = session.currentCommandPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
            return "$ \(preview)"
        }
        if let activity = session.spotlightActivityLineText?.trimmingCharacters(in: .whitespacesAndNewlines), !activity.isEmpty {
            return activity
        }
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private func ageBadgeText(at referenceDate: Date) -> String {
        if session.phase == .running {
            return session.elapsedRunningLabel(at: referenceDate)
        }
        return session.spotlightAgeBadge
    }

    private var completionOutcomeLabel: String {
        switch session.outcome {
        case .success: return lang.t("completion.done")
        case .interrupted: return lang.t("completion.interrupted")
        case .failed: return lang.t("completion.failed")
        }
    }

    private var completionMessageText: String {
        if let text = session.completionAssistantMessageText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary == SessionPhase.completed.displayName ? "" : summary
    }

    private func contrastText(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: increasesContrast)
    }

    // MARK: - Layout insets

    private var showsLeadingStatusIndicator: Bool {
        presentation == .list && stateIndicator != .tint && stateIndicator != .bar
    }

    private var rowLeadingInset: CGFloat {
        sideInset
    }

    private var detailLeadingInset: CGFloat {
        if presentation == .notification { return sideInset }
        switch stateIndicator {
        case .bar, .tint:
            return sideInset
        case .animatedDot, .glyph:
            return sideInset + 28
        }
    }

    private var rowFillColor: Color {
        if presentation == .notification { return .clear }
        return isHighlighted ? tokens.colors.paper.opacity(0.03) : .clear
    }
}

// MARK: - Annual approval card (AB-318)

/// The permission request rendered as the Annual **typographic alarm** — a
/// box-free editorial block that stays the panel's unambiguous focal point through
/// type alone. A 2px accent rule and a small-caps `permission required` kicker head
/// it; the command sits in a left-ruled mono quote above the affected-path line and
/// the optional `PermissionDiffPreview` (whose +/− render legibly in the restrained
/// palette); and the `allow` (inverted, strong contrast) / `deny` (quiet) text
/// buttons each print the **real** ⌘Y / ⌘N key-hint the global keyboard handler
/// fires, with the always-allow options carrying ⌘⇧Y. The alarm tint is the single
/// `annualAccent` (approval / question / failure all resolve to it) — spent here
/// and only here among the panel's surfaces, so the accent discipline holds. There
/// is no pill, chip, capsule or fillet: hierarchy is the accent rule, the kicker and
/// the type weight.
private struct AnnualApprovalCard: View {
    let session: AgentSession
    let lang: LanguageManager
    let actions: RowActions
    let pulseClock: PulseClock?

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    /// The alarm tint — the theme's single accent, the same token approval / failure
    /// status resolves to.
    private var alarm: Color { tokens.colors.statusWaitingForApproval }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The load-bearing 2px accent rule — the alarm's top edge, the loudest
            // structural mark on the panel.
            Rectangle()
                .fill(alarm)
                .frame(height: AnnualHairline.rule)
                .accessibilityHidden(true)

            // The small-caps kicker, in the accent, fed lowercased so Latin renders
            // as true small capitals and CJK passes through untouched.
            Text(AnnualText.lower(lang.t("island.annual.approval.permissionRequired"), lang: lang))
                .font(AnnualTypography.smallCapsLabel)
                .tracking(AnnualText.tracking(1.0, lang: lang))
                .foregroundStyle(alarm.opacity(increasesContrast ? 1 : 0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            // The command in a left-ruled mono quote + the affected-path line.
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(alarm.opacity(increasesContrast ? 0.9 : 0.7))
                    .frame(width: AnnualHairline.rule)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(commandPreviewText)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.9)))
                        .fixedSize(horizontal: false, vertical: true)

                    if let path = affectedPath {
                        Text(path)
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.5)))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)

            if let diffResult = permissionDiffResult {
                PermissionDiffPreview(result: diffResult, lang: lang)
            }

            if session.permissionRequest?.requiresTerminalApproval == true {
                terminalApprovalCTA
            } else {
                HStack(spacing: 10) {
                    AnnualApprovalButton(
                        title: denyTitle,
                        shortcut: .deny,
                        kind: .quiet,
                        lang: lang,
                        accessibilityLabel: session.permissionRequest?.secondaryActionTitle ?? lang.t("a11y.approval.deny"),
                        action: { actions.approve?(.deny) }
                    )
                    AnnualApprovalButton(
                        title: allowTitle,
                        shortcut: .allowOnce,
                        kind: .strong,
                        lang: lang,
                        accessibilityLabel: session.permissionRequest?.primaryActionTitle ?? lang.t("a11y.approval.allowOnce"),
                        action: { actions.approve?(.allowOnce) }
                    )
                }

                alwaysAllowOptions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// AB-235: scoped always-allow options (one per suggested update) or the generic
    /// session-scoped fallback — the same calls ⌘⇧Y drives. The first option carries
    /// the ⌘⇧Y key-hint the shortcut fires against.
    @ViewBuilder
    private var alwaysAllowOptions: some View {
        if let updates = session.permissionRequest?.suggestedUpdates, !updates.isEmpty {
            VStack(spacing: 6) {
                ForEach(Array(updates.enumerated()), id: \.offset) { index, update in
                    AnnualApprovalButton(
                        title: update.displayLabel,
                        shortcut: index == 0 ? .alwaysAllow : nil,
                        kind: .ghost,
                        lang: lang,
                        lowercases: false,
                        accessibilityLabel: update.displayLabel,
                        action: { actions.approve?(.allowWithUpdates([update])) }
                    )
                }
            }
        } else if let toolName = session.permissionRequest?.toolName {
            AnnualApprovalButton(
                title: lang.t("approval.alwaysAllow", toolName),
                shortcut: .alwaysAllow,
                kind: .ghost,
                lang: lang,
                lowercases: false,
                accessibilityLabel: lang.t("approval.alwaysAllow", toolName),
                action: {
                    let rule = ClaudePermissionRuleValue(toolName: toolName)
                    let update = ClaudePermissionUpdate.addRules(
                        destination: .session,
                        rules: [rule],
                        behavior: .allow
                    )
                    actions.approve?(.allowWithUpdates([update]))
                }
            )
        }
    }

    private var terminalApprovalCTA: some View {
        AnnualApprovalButton(
            title: lang.t("approval.respondInTerminal"),
            shortcut: nil,
            kind: .ghost,
            lang: lang,
            lowercases: false,
            leadingGlyph: "arrow.up.forward",
            accessibilityLabel: lang.t("approval.respondInTerminal"),
            action: { actions.jump() }
        )
    }

    private var allowTitle: String {
        session.permissionRequest?.primaryActionTitle ?? lang.t("island.annual.approval.allow")
    }

    private var denyTitle: String {
        session.permissionRequest?.secondaryActionTitle ?? lang.t("island.annual.approval.deny")
    }

    private var affectedPath: String? {
        guard let path = session.permissionRequest?.affectedPath.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return path
    }

    private var commandPreviewText: String {
        if let preview = session.currentCommandPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
            return "$ \(preview)"
        }
        return (session.permissionRequest?.summary ?? session.summary).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var permissionDiffResult: PermissionDiffResult? {
        guard let source = session.permissionRequest?.fileDiffSource else { return nil }
        let result = PermissionDiff.compute(oldText: source.oldText, newText: source.newText)
        return result.isEmpty ? nil : result
    }

    private func contrastText(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: increasesContrast)
    }
}

/// An Annual approval button in the editorial idiom — a text button, never a pill.
/// `strong` is the high-contrast affirmative (`allow`): a squared knockout block,
/// off-white paper filled with ink text. `quiet` is the understated `deny`: a text
/// label under a hairline underline, no fill. `ghost` is a dim lowercase text button
/// for the stacked always-allow / terminal options. Every kind carries a ≥24pt-tall
/// hit target via padding + `contentShape`, and the trailing key-hint prints the
/// real registered shortcut glyphs.
private struct AnnualApprovalButton: View {
    enum Kind { case strong, quiet, ghost }

    let title: String
    let shortcut: AnnualApprovalFormat.Shortcut?
    let kind: Kind
    let lang: LanguageManager
    var lowercases: Bool = true
    var leadingGlyph: String?
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    /// The ≥24pt hit-target floor the AC pins, matched to the row's dismiss/jump
    /// controls.
    private static let minHitHeight: CGFloat = AnnualSessionRowGrid.minHitTarget

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let leadingGlyph {
                    Image(systemName: leadingGlyph)
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(displayTitle)
                    .font(.system(size: 11.5, weight: kind == .strong ? .semibold : .medium, design: .monospaced))
                    .tracking(lowercases ? AnnualText.tracking(0.4, lang: lang) : 0)
                    .lineLimit(1)
                if let shortcut {
                    keyHint(shortcut)
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: kind == .ghost ? .infinity : nil, alignment: kind == .ghost ? .leading : .center)
            .padding(.horizontal, kind == .strong ? 14 : 4)
            .padding(.vertical, 7)
            .frame(minHeight: Self.minHitHeight)
            .background(background)
            .overlay(alignment: .bottom) { underline }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var displayTitle: String {
        lowercases ? AnnualText.lower(title, lang: lang) : title
    }

    /// The key-hint — a quiet mono glyph run (`⌘Y`) in the button's own foreground.
    /// No keycap box (that would be a chip); the mono weight alone reads it as a
    /// shortcut.
    private func keyHint(_ shortcut: AnnualApprovalFormat.Shortcut) -> some View {
        Text(shortcut.glyphString)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(foreground.opacity(0.7))
            .accessibilityHidden(true)
    }

    private var foreground: Color {
        switch kind {
        case .strong:
            return tokens.colors.surfaceInk
        case .quiet:
            return tokens.colors.paper.opacity(tokens.colors.text(0.88, increaseContrast: increasesContrast))
        case .ghost:
            return tokens.colors.paper.opacity(tokens.colors.text(0.7, increaseContrast: increasesContrast))
        }
    }

    /// The knockout block behind `strong` only — a squared (radius 0) paper fill, an
    /// editorial solid button, not a pill. `quiet` and `ghost` carry no fill.
    @ViewBuilder
    private var background: some View {
        if kind == .strong {
            Rectangle().fill(tokens.colors.paper)
        } else {
            Color.clear
        }
    }

    /// The hairline underline under `quiet` / `ghost` — the editorial answer to a
    /// button border. `strong` needs none (its knockout block already reads).
    @ViewBuilder
    private var underline: some View {
        if kind != .strong {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast) * (kind == .quiet ? 2.4 : 1.6)))
                .frame(height: AnnualHairline.hairline)
        }
    }
}
