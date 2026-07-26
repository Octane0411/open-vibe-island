import AppKit
import SwiftUI
@preconcurrency import MarkdownUI
import OpenIslandCore

/// Flight Deck's session row (AB-313 · flightdeck 3/4).
///
/// The annunciator re-skin of `IslandSessionRow` for the **non-actionable**
/// states — running, done (success / interrupted / failed), idle-stale, SSH and
/// demo — across the `.list` and `.notification` presentations. Every row
/// carries a colored **STATUS LANE** on its left edge like an EICAS warning
/// light (red alert / green run / blue done / gray idle); the live lane pulses
/// off the shared clock and holds steady under Reduce Motion. The body is
/// typeset on the STATUS / SESSION / MODEL / TIME column grid (AB-337 re-registers
/// it — a STATUS text-code column joins the leading edge and APP folds into an
/// SSH chip): the leading STATUS cell and trailing model / time cells hold fixed
/// lanes so they land on the same x under their captions across every visible
/// row, and the chevron and
/// dismiss controls sit in reserved lanes so the registers never shift. Agent
/// identity is a small neutral mono mark so the lane's state colour always wins.
///
/// **Actionable rows are now fully Flight Deck (AB-314).** A permission request
/// draws the **MASTER CAUTION** annunciator — a full-width chamfered alert block
/// with a pulsing status glow (static under Reduce Motion), a stenciled
/// `MASTER CAUTION` placard + `PERMISSION REQUIRED` kicker, the command in a
/// bordered mono box above the affected-path line and `PermissionDiffPreview`,
/// and chamfered ALLOW / DENY switches carrying the real ⌘Y / ⌘⇧Y / ⌘N key-hint
/// glyphs — via `FlightDeckApprovalCard`; the question reuses the shared,
/// token-driven `StructuredQuestionPromptView`, and the completion is a squared
/// mono card. The behaviours that are contract-level — the jump tap, the
/// ⌘Y / ⌘⇧Y / ⌘N approval wiring and the 1–9 / Enter question shortcuts (both
/// driven globally from `OverlayPanelController`), the reply callback, and the
/// grouped VoiceOver summary — are preserved verbatim so the two rows stay
/// interchangeable inside one list. Only the surfaces change.
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
    /// Shared 15fps clock for the actionable card's annunciator beacon / caution
    /// glow (AB-228). The non-actionable status lane no longer needs it — since
    /// AB-336 the lane breathes / settles off its own clock-free `@State` (the
    /// `FlightDeckRunningLight` pattern), so only the alarm interiors touch this.
    var pulseClock: PulseClock?

    var body: some View {
        if isActionable {
            // AB-314: the approval (MASTER CAUTION) / question / completion
            // interiors are now drawn in the Flight Deck idiom by
            // `FlightDeckActionableRowContent` (the old thin seam to Classic is
            // gone). The header keeps the mono tabular idiom so an actionable row
            // still reads as one of the annunciator grid.
            FlightDeckActionableRowContent(
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
            FlightDeckRowContent(
                session: session,
                stateIndicator: stateIndicator,
                completedStaleThreshold: completedStaleThreshold,
                isInteractive: isInteractive,
                isHighlighted: isHighlighted,
                presentation: presentation,
                sideInset: sideInset,
                lang: lang,
                actions: actions
            )
        }
    }
}

// MARK: - Pure, testable row logic

/// The fixed lanes for the Flight Deck column grid. Every registered column
/// holds a constant width so the STATUS, model and time cells land on the same x
/// under their `STATUS | SESSION | MODEL | TIME` captions across every visible
/// row — the "exact vertical registers" the design language is built on
/// (AB-337 · SPEC §3-Slot3 / §4). Literal points, deliberately not type-scaled,
/// for the same reason `IslandSessionRowMetrics` isn't. The `columnCaptionStrip`
/// in `FlightDeckSessionListScaffold` draws from these exact constants so the
/// captions and the cells share one geometry and can never drift.
///
/// AB-337 re-registers the grid: a **STATUS** text-code column joins the leading
/// edge, and the shipped **APP** column is gone — a remote session now reads via
/// an `SSH` chip on the session cell, and the terminal app name moves to the
/// expanded detail (§3-Slot3).
enum FlightDeckSessionRowGrid {
    /// The leading STATUS column: a status lamp + its text code (`RUN` / `WARN`
    /// / …). Fixed so the code register lines up down the list under the STATUS
    /// caption.
    static let statusColumnWidth: CGFloat = 58
    /// The gap between the leading STATUS cell and the flexing SESSION cell —
    /// shared by the row's summary HStack and the caption strip so the SESSION
    /// caption lands over the headline.
    static let leadingColumnGap: CGFloat = 10
    static let columnGap: CGFloat = 8
    static let modelColumnWidth: CGFloat = 66
    static let timeColumnWidth: CGFloat = 44

    /// Trailing controls, reserved as fixed lanes in both the row and the
    /// caption strip so the time register never shifts between rows that do and
    /// don't carry a dismiss control.
    static let detailToggleColumnWidth: CGFloat = IslandSessionRowMetrics.detailToggleColumnWidth
    static let dismissColumnWidth: CGFloat = IslandSessionRowMetrics.dismissColumnWidth

    /// The registered fixed-width cells that must line up vertically across rows
    /// — the leading STATUS lane and the trailing MODEL / TIME lanes. (SESSION
    /// flexes; the control lanes are reserved clear space.)
    static var registeredColumnWidths: [CGFloat] {
        [statusColumnWidth, modelColumnWidth, timeColumnWidth]
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

    /// The retimed 2.0 motion a status lane runs in (AB-336 · SPEC §1c / §4K).
    /// The shipped lane lit running *and* waiting identically off one two-step
    /// blink; the phosphor identity splits them: a running lane **breathes** (2.0s,
    /// halo `5 → 11pt`), an attention lane **pulses** on its EICAS cadence
    /// (warning red `1.0s` / caution amber `1.2s`, brighter than the calm breathe),
    /// a freshly-completed *success* lane plays the one-shot **settle** (nominal
    /// flash → advisory dot, A5), and every settled / idle lane holds **steady**.
    /// A non-success completion (interrupted / failed) rests steady in its loud
    /// alert colour — its glyph + width carry the state, not a pulse.
    enum LaneMotion: Equatable {
        case steady
        case breathe
        case attention(period: Double)
        case settle
    }

    static func laneMotion(
        phase: SessionPhase,
        presence: IslandSessionPresence,
        outcome: SessionOutcome
    ) -> LaneMotion {
        // A stale / inactive row recedes to a steady dim bar regardless of its
        // stored phase (mirrors `lanePriority`'s idle-wins rule).
        if presence == .inactive { return .steady }
        switch phase {
        case .waitingForApproval:
            return .attention(period: FlightDeckMotion.Attention.warningPeriod)
        case .waitingForAnswer:
            return .attention(period: FlightDeckMotion.Attention.cautionPeriod)
        case .running:
            return .breathe
        case .completed:
            return outcome == .success ? .settle : .steady
        }
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

    /// The alert-lane static glow intensity (AB-336): a loud steady lane (a failed
    /// / interrupted completion, resting opacity `1.0`) still reads as a self-lit
    /// phosphor lamp, so it carries a modest static halo; the recessed idle lane
    /// (resting opacity `0.4`) stays dark — an unlit lamp casts no light. Gated on
    /// resting opacity so the mapping stays a pure function of the lane's own
    /// brightness ramp.
    static func steadyLaneGlowIntensity(restingOpacity: Double) -> Double {
        restingOpacity > 0.5 ? 0.4 : 0
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

    /// The STATUS text-code that heads every non-actionable row (SPEC §3-Slot3 ·
    /// AB-337): a four-glyph EICAS code paired with the status lamp — `RUN`
    /// (nominal running) / `DONE` (advisory success) / `CAUT` (question, amber) /
    /// `WARN` (permission, red) / `INTR` (interrupted, amber) / `FAIL` (failed,
    /// red) / `IDLE` (dim). Inactive presence wins first, so a stale row reads
    /// `IDLE` regardless of its stored phase/outcome — the same idle-wins rule
    /// `lanePriority` follows, keeping the code, the lane and the lamp in lock-step.
    static func statusCode(
        phase: SessionPhase,
        presence: IslandSessionPresence,
        outcome: SessionOutcome
    ) -> String {
        if presence == .inactive { return "IDLE" }
        switch phase {
        case .running:
            return "RUN"
        case .waitingForApproval:
            return "WARN"
        case .waitingForAnswer:
            return "CAUT"
        case .completed:
            switch outcome {
            case .success: return "DONE"
            case .interrupted: return "INTR"
            case .failed: return "FAIL"
            }
        }
    }

    /// A tone run of the row's narrated activity line (AB-337 · T03 / AB-321 ·
    /// mockup `.narr2`). The **verb** is tinted nominal green (`#4AC99E`), the
    /// **object** (the file / thing the human scans for) reads bright, and a bare
    /// human-fallback line (no structured narration) reads dim. Pure and view-free
    /// so the tone split is unit-testable and the mockup's tinting can't silently
    /// regress into the shipped `$ <preview>` echo.
    struct NarrationSegment: Equatable {
        enum Role: Equatable {
            /// Tinted nominal green (`#4AC99E`) — the mockup `.narr2 .v` verb.
            case verb
            /// Bright paper — the mockup `.narr2 b` object.
            case object
            /// Dim — a human-fallback line with no structured verb/object.
            case plain
        }

        var text: String
        var role: Role
    }

    /// Tone-segments the narration line. A structured verb (with optional object)
    /// tints the verb green and the object bright; otherwise the human fallback
    /// renders as one dim run. Returns `[]` when there is nothing to narrate — the
    /// row then draws no sub-line rather than echoing a raw command preview.
    static func narrationSegments(verb: String?, object: String?, fallback: String?) -> [NarrationSegment] {
        if let verb = verb?.flightDeckTrimmed, !verb.isEmpty {
            var segments = [NarrationSegment(text: verb, role: .verb)]
            if let object = object?.flightDeckTrimmed, !object.isEmpty {
                segments.append(NarrationSegment(text: " " + object, role: .object))
            }
            return segments
        }
        if let fallback = fallback?.flightDeckTrimmed, !fallback.isEmpty {
            return [NarrationSegment(text: fallback, role: .plain)]
        }
        return []
    }

    /// The expanded-detail attachment badge (AC #4 · mockup §D `Terminal · badge`):
    /// an avionics placard code from `attachmentState`. Latin caps like the STATUS
    /// codes (never localized), paired with `isLive` so an attached pane reads in
    /// the nominal tint and a stale / detached one recedes.
    static func attachmentBadge(_ state: SessionAttachmentState) -> (code: String, isLive: Bool) {
        switch state {
        case .attached: return ("ATTACHED", true)
        case .stale:    return ("STALE", false)
        case .detached: return ("DETACHED", false)
        }
    }

    /// Every readable point size the Flight Deck row draws, for the ≥10pt-floor
    /// assertion (AC #6). The sans headline (13.5), sans narration (12) and sans
    /// assistant body (13) sit above the floor; the mono tabular columns sit at the
    /// 10.5 lane; the mono STATUS code and metacell key sit at the 10pt floor.
    static let readableTextSizes: [CGFloat] = [13.5, 13, 12, 10.5, 10]
}

// MARK: - Actionable surface logic (AB-314)

/// Pure display rules for the Flight Deck MASTER CAUTION / completion surfaces,
/// split out so the AC-bearing decisions (which key-hint glyph a switch carries,
/// which glyph a non-success completion shows, the pulsing caution-glow ramp, and
/// the ≥10pt floor on the alarm block) are unit-testable without rendering a
/// SwiftUI view.
enum FlightDeckApprovalFormat {
    /// The three approval decisions the MASTER CAUTION block exposes, each paired
    /// with the **real** registered `OverlayPanelController` shortcut it fires. The
    /// glyph strings the ALLOW / DENY / always-allow switches print must stay in
    /// lock-step with that handler (`⌘Y` / `⌘⇧Y` / `⌘N`), never the mockup's ⏎/⎋.
    enum Shortcut: CaseIterable {
        case allowOnce
        case alwaysAllow
        case deny

        /// The key-hint glyphs printed on the switch, in order.
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

    /// The completion outcome banner glyph (AC #4): a stop for an interrupted
    /// turn, a cross for a failure. Only ever shown for a non-success outcome.
    static func completionOutcomeGlyphName(outcome: SessionOutcome) -> String {
        outcome == .failed ? "xmark.square.fill" : "stop.fill"
    }

    /// The MASTER CAUTION block's caution-glow opacity (AC #1). A smooth triangle
    /// breathe off the shared clock's phase — the loud, slow throb of a warning
    /// annunciator, not the crisp two-step of the status lane — pinned to a steady
    /// mid-level under Reduce Motion so the glow reads without animating.
    static func glowOpacity(phase: Double, reduceMotion: Bool) -> Double {
        let restingLevel = 0.5
        guard !reduceMotion else { return restingLevel }
        let triangle = phase < 0.5 ? phase * 2 : (1 - phase) * 2  // 0 → 1 → 0
        return 0.3 + triangle * 0.35                              // 0.30 … 0.65
    }

    /// Every readable point size the alarm / completion surfaces draw, for the
    /// ≥10pt-floor assertion (AC #7).
    static let readableTextSizes: [CGFloat] = [13.2, 12.5, 11.5, 11, 10.5, 10]

    // MARK: - Annunciator beacon (AB-334 · retimed AB-336)

    /// Beacon-lamp pulse periods, seconds. EICAS retiming: the red **WARNING**
    /// lamp on a held permission throbs faster (a 1.0s alarm cadence) than the
    /// amber **CAUTION** lamp on a question (a calmer 1.2s), so the two
    /// annunciators are distinguishable by rhythm as well as colour. AB-336 folds
    /// these into `FlightDeckMotion.Attention` so the pill bloom, the beacons and
    /// the motion strip share one source of truth — these stay the beacon's
    /// public names but read straight off the motion enum.
    static let permissionBeaconPeriod: Double = FlightDeckMotion.Attention.warningPeriod
    static let questionBeaconPeriod: Double = FlightDeckMotion.Attention.cautionPeriod

    /// The annunciator beacon-lamp brightness. AB-336 routes it through the shared
    /// `FlightDeckMotion.attentionLevel` ramp (mockup `attn`: opacity `1.0 → 0.28`
    /// at the lamp's own `period`), a pure function of wall-clock time so the red
    /// (1.0s) and amber (1.2s) lamps retime independently — something the shared
    /// fixed-period `PulseClock` can't express. Reduce Motion pins it to the peak
    /// (`opacityMax`) — a lit lamp, never dark.
    static func beaconLevel(now: Date, period: Double, reduceMotion: Bool) -> Double {
        FlightDeckMotion.attentionLevel(now: now, period: period, reduceMotion: reduceMotion)
    }

    // MARK: - HELD count-up (AB-334)

    /// Longest elapsed span the `HELD` readout will show before it is treated as
    /// implausible and hidden (a stale `updatedAt` from a long-idle registry row).
    static let heldReadoutCeiling: TimeInterval = 24 * 60 * 60

    /// The `HELD` count-up shown on the permission annunciator (AB-334): how long
    /// the agent has been blocked, formatted `0m 08s`.
    ///
    /// Honesty note: there is no dedicated "request arrived at" field on the
    /// session, so this approximates the held time as `now − session.updatedAt` —
    /// `updatedAt` is stamped by the very hook event that raised the permission
    /// request, which is the best proxy available. Returns `nil` (readout hidden)
    /// when the approximation is negative (clock skew) or implausibly large
    /// (> `heldReadoutCeiling`, i.e. a stale row rather than a live hold).
    static func heldReadout(now: Date, since updatedAt: Date) -> String? {
        let elapsed = now.timeIntervalSince(updatedAt)
        guard elapsed >= 0, elapsed <= heldReadoutCeiling else { return nil }
        let total = Int(elapsed)
        return String(format: "%dm %02ds", total / 60, total % 60)
    }
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

    @State private var expandedOverride: Bool?

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    /// AB-337 · T05 (AB-323): list-level duplicate-workspace disambiguators. A
    /// Claude row disambiguates via its branch chip; the recency phrase this map
    /// carries is the fallback for a collided non-Claude / branchless row.
    @Environment(\.islandSessionDisambiguators) private var sessionDisambiguators

    /// AB-313: the same one-reference type ramp Classic uses — every scaled
    /// reading size is expressed relative to this so the whole row scales
    /// together off one measurement (AC #6). The fixed tabular columns are
    /// deliberately left unscaled (see `IslandSessionRowMetrics`).
    @ScaledMetric(relativeTo: .body) private var typeScaleReference: CGFloat = 13
    private var typeScale: CGFloat { typeScaleReference / 13 }

    private func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * typeScale, weight: weight, design: .monospaced)
    }

    /// The sans companion to `scaledFont` (AB-337 · SPEC §2): the narration
    /// typeface for prose the reader *reads* — the session / workspace name and
    /// the activity narration — scaled off the same one reference so it tracks
    /// Dynamic Type alongside the mono value columns. Every value (durations,
    /// ages, codes, placards) keeps `scaledFont`.
    private func sansScaled(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * typeScale, weight: weight, design: .default)
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
                expandedDetails(presence: presence, referenceDate: referenceDate)
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
                    flashTint: tokens.colors.statusRunning,
                    width: FlightDeckSessionRowFormat.laneWidth(priority),
                    restingOpacity: FlightDeckSessionRowFormat.laneOpacity(priority),
                    motion: FlightDeckSessionRowFormat.laneMotion(
                        phase: session.phase,
                        presence: presence,
                        outcome: session.outcome
                    )
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
        HStack(alignment: .top, spacing: FlightDeckSessionRowGrid.leadingColumnGap) {
            statusCell(for: presence)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayHeadline)
                        // AB-337 · SPEC §2: the session / workspace name is sans
                        // narration — the reader *reads* it — not the mono value
                        // columns beside it. 13.5pt, semibold, −0.01em.
                        .font(sansScaled(FlightDeckTypography.sessionNameSize, weight: .semibold))
                        .tracking(FlightDeckTypography.sessionNameTracking)
                        .foregroundStyle(titleColor(for: presence))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                        // Full name one hover away — the column truncates, the
                        // tooltip does not (AC #2).
                        .help(session.spotlightWorkspaceName)

                    // AB-337 · SPEC §3-Slot3 / §4C: the chip row beside the name —
                    // a remote session flags `SSH` (the folded APP column), a
                    // Claude worktree flags its branch (⑂), a Claude session in a
                    // non-default permission mode flags it, and active subagents
                    // roll up to `⚙ N SUB`. A collided non-Claude / branchless row
                    // instead carries a recency disambiguator (T05). Every chip is
                    // `flex:none` so the name — not the chips — absorbs truncation.
                    if session.isRemote {
                        FlightDeckRowChip(text: "SSH", lang: lang)
                    }
                    if let branch = branchChipText {
                        FlightDeckRowChip(text: branch, lang: lang, uppercases: false, leadingGlyph: "⑂")
                    } else if let recency = recencyDisambiguator {
                        FlightDeckRowChip(text: recency, lang: lang, uppercases: false)
                    }
                    if let mode = permissionModeChipText {
                        FlightDeckRowChip(text: mode, lang: lang, uppercases: false)
                    }
                    if let subagentCount = activeSubagentCount {
                        FlightDeckRowChip(text: "⚙ \(subagentCount) SUB", lang: lang, tint: tokens.colors.statusRunning)
                    }
                }

                if showsSubLine {
                    let segments = narrationSegments(presence: presence)
                    if !segments.isEmpty {
                        composedNarration(segments, presence: presence)
                            // Narration prose — sans, 12pt (SPEC §2). The verb is
                            // tinted nominal green; the object reads bright.
                            .font(sansScaled(FlightDeckTypography.narrationSize, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
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

            Text(ageBadgeText(at: referenceDate))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(columnColor(for: presence))
                .frame(width: FlightDeckSessionRowGrid.timeColumnWidth, alignment: .trailing)

            detailToggleButton(isOpen: isExpanded)

            // Reserve the dismiss lane always, so the time column doesn't shift
            // between dismissible and non-dismissible rows.
            if let dismiss = actions.dismiss {
                // AC #3: hover-reveal — hidden at rest, fades in on the row's
                // `isHighlighted` (mirroring Poured AB-332). The row's grouped
                // VoiceOver summary already exposes dismiss as a named rotor
                // action (`FlightDeckOptionalNamedAccessibilityAction`), so it
                // stays reachable while visually hidden.
                DismissButton(action: dismiss, lang: lang)
                    .opacity(isHighlighted ? 1 : 0)
                    .accessibilityHidden(true)
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

    // MARK: - STATUS column (lamp + text code)

    /// The leading STATUS column (AB-337 · SPEC §3-Slot3): the row's status
    /// **lamp** (the indicator-preference mark) paired with its **text code**
    /// (`RUN` / `DONE` / `CAUT` / `WARN` / `INTR` / `FAIL` / `IDLE`), mono 10pt /
    /// 700 / 0.08em. The lamp's *glow* is the always-present left-edge
    /// `FlightDeckStatusLane` (AB-336) — this column adds the code beside it and
    /// does not duplicate that self-lit lamp. Fixed to `statusColumnWidth` so the
    /// code register lines up down the list under the STATUS caption.
    private func statusCell(for presence: IslandSessionPresence) -> some View {
        HStack(spacing: 5) {
            if showsLeadingMark {
                leadingMark(for: presence)
            }
            Text(statusCodeText(for: presence))
                .font(scaledFont(FlightDeckTypography.statusCodeSize, weight: .bold))
                .tracking(FlightDeckTypography.statusCodeTracking)
                .foregroundStyle(statusCodeColor(for: presence))
                .lineLimit(1)
                .fixedSize()
                .padding(.top, 1)
                .accessibilityHidden(true)
        }
        .frame(width: FlightDeckSessionRowGrid.statusColumnWidth, alignment: .leading)
    }

    private func statusCodeText(for presence: IslandSessionPresence) -> String {
        FlightDeckSessionRowFormat.statusCode(
            phase: session.phase,
            presence: presence,
            outcome: session.outcome
        )
    }

    /// The code inherits the status hue so `WARN` reads red and `CAUT` amber even
    /// with the lamp glowing beside it; an idle row's code recedes to the dim
    /// idle grey. It never dips below the readable secondary-text ink.
    private func statusCodeColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive
            ? tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
            : statusTint(for: presence).opacity(increasesContrast ? 1 : 0.92)
    }

    // MARK: - Expanded details (chevron open)

    @ViewBuilder
    private func expandedDetails(presence: IslandSessionPresence, referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metagrid(referenceDate: referenceDate)

            if let message = lastAssistantMessageForDetail {
                assistantMessageCard(message)
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

    // MARK: - §4D metagrid (AC #4)

    /// The expanded-detail metadata grid (SPEC §4D · mockup `.metagrid`): a wrap
    /// of chamfered `.metacell` tiles, each a caps key (10pt, lifted to the FD
    /// floor) over a mono value. Absent fields render **nothing** — no `—` dashes
    /// (BRIEF §1.3): Model appears only with a resolved name; Mode / Branch only
    /// for Claude; Uptime only while running; Terminal only with a resolved app.
    private func metagrid(referenceDate: Date) -> some View {
        FlightDeckMetaFlow(spacing: 6) {
            metacell(key: lang.t("island.flightDeck.detail.agent")) {
                agentIdentityValue
            }

            if let model = session.displayModelName {
                metacellText(key: lang.t("island.flightDeck.detail.model"), value: model)
            }

            if let mode = permissionModeChipText {
                metacellText(key: lang.t("island.flightDeck.detail.mode"), value: mode)
            }

            if let branch = branchChipText {
                metacellText(key: lang.t("island.flightDeck.detail.branch"), value: branch)
            }

            if session.phase == .running {
                metacellText(
                    key: lang.t("island.flightDeck.detail.uptime"),
                    value: session.elapsedRunningLabel(at: referenceDate)
                )
            }

            if let terminal = FlightDeckSessionRowFormat.appColumnText(
                isRemote: session.isRemote,
                terminalBadge: session.spotlightTerminalBadge
            ) {
                metacell(key: lang.t("island.flightDeck.detail.terminal")) {
                    terminalValue(app: terminal)
                }
            }
        }
    }

    private func metacellText(key: String, value: String) -> some View {
        // Mono design already renders tabular figures, so timers / ages align.
        metacell(key: key) {
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.92)))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func metacell<Value: View>(key: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(FlightDeckText.caps(key, lang: lang))
                // Metacell key — 10pt caps (lifted from the mockup's 9px), on the
                // lifted metacell role (AC #4).
                .font(.system(size: FlightDeckTypography.microLabelSize, weight: .semibold, design: .default))
                .tracking(FlightDeckText.tracking(1.0, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
            value()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(minWidth: 74, alignment: .leading)
        .background(FlightDeckChamferedRectangle(chamfer: 3).fill(FlightDeckSurfaces.tile))
        .overlay(
            FlightDeckChamferedRectangle(chamfer: 3)
                .strokeBorder(FlightDeckSurfaces.hairline(tier: 1, increaseContrast: increasesContrast), lineWidth: 1)
        )
    }

    /// The Agent cell value — a brand dot + the agent's full display name, the
    /// identity the collapsed row keeps a whisper.
    private var agentIdentityValue: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper)
                .frame(width: 6, height: 6)
            Text(session.tool.displayName)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.92)))
                .lineLimit(1)
        }
    }

    /// The Terminal cell value — the terminal / IDE app name + an
    /// `ATTACHED` / `STALE` / `DETACHED` placard badge from `attachmentState`
    /// (AC #4). The badge reads nominal green when the pane is live and recedes to
    /// the dim ink otherwise.
    private func terminalValue(app: String) -> some View {
        let badge = FlightDeckSessionRowFormat.attachmentBadge(session.attachmentState)
        return HStack(spacing: 6) {
            Text(app)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.92)))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(badge.code)
                .font(.system(size: FlightDeckTypography.microLabelSize, weight: .semibold, design: .monospaced))
                .tracking(FlightDeckText.tracking(0.6, lang: lang))
                .foregroundStyle(
                    badge.isLive
                        ? tokens.colors.statusRunning
                        : tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
                )
                .lineLimit(1)
                .fixedSize()
        }
    }

    // MARK: - §4D last message (AC #5)

    /// The last assistant message as rich prose (Markdown), through the sans
    /// `assistant` role with inline `code` tinted `#4AC99E` (AC #5) — never the
    /// raw single-line dump the shipped detail echoed. Capped in an
    /// `AutoHeightScrollView` so a long message can't run the row off the panel.
    private func assistantMessageCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(FlightDeckText.caps(lang.t("island.flightDeck.detail.lastMessage"), lang: lang))
                .font(.system(size: FlightDeckTypography.microLabelSize, weight: .semibold, design: .default))
                .tracking(FlightDeckText.tracking(1.0, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))

            AutoHeightScrollView(maxHeight: 150) {
                Markdown(message)
                    .markdownTheme(.flightDeckAssistant(tokens.colors))
                    .markdownImageProvider(.noNetwork)
                    .markdownInlineImageProvider(.noNetwork)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlightDeckChamferedRectangle(chamfer: 4).fill(FlightDeckSurfaces.well))
        .overlay(
            FlightDeckChamferedRectangle(chamfer: 4)
                .strokeBorder(FlightDeckSurfaces.hairline(tier: 1, increaseContrast: increasesContrast), lineWidth: 1)
        )
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

    // MARK: - Chips (AC #1)

    /// The branch chip text (AC #1): the worktree branch, but **only** for a
    /// Claude session that carries one — `SessionDisambiguation.branch` is the
    /// honesty gate (Codex computes a branch and throws it away, so surfacing one
    /// on a Codex row would invent data). Middle-truncated so a long branch keeps
    /// its readable tail. For a Claude row this chip doubles as the T05
    /// duplicate-workspace disambiguator.
    private var branchChipText: String? {
        guard let branch = SessionDisambiguation.branch(for: session) else { return nil }
        return SessionDisambiguation.displayBranch(branch)
    }

    /// The recency disambiguator (AC #1): for a collided **non-Claude / branchless**
    /// row (which can't carry a branch chip), the list-level T05 disambiguator is a
    /// recency phrase (`12m ago`). Only rendered when a branch chip is absent, so
    /// the two disambiguators never double up.
    private var recencyDisambiguator: String? {
        guard branchChipText == nil else { return nil }
        return sessionDisambiguators[session.id]
    }

    /// The permission-mode chip (mockup §C · running row `acceptEdits`): Claude
    /// only, and only for a non-default mode (`.default` carries no information).
    private var permissionModeChipText: String? {
        guard session.tool == .claudeCode,
              let mode = session.claudeMetadata?.permissionMode,
              mode != .default else {
            return nil
        }
        return mode.rawValue
    }

    /// The `⚙ N SUB` subagent count (AC #1 · mockup §G′): the count of active
    /// subagents, or `nil` when there are none — the only detail the row invents
    /// is this real count.
    private var activeSubagentCount: Int? {
        guard let subagents = session.claudeMetadata?.activeSubagents, !subagents.isEmpty else {
            return nil
        }
        return subagents.count
    }

    // MARK: - Narration (T03 verb map · AC #2)

    /// The row's narrated activity, tone-split into `verb` (tinted `#4AC99E`) /
    /// `object` (bright) / `plain` (dim) runs (AB-337 · T03 / AB-321). A running
    /// row narrates its structured verb+object (`Editing AppModel.swift`); every
    /// other row falls back to its human activity / prompt line — never the raw
    /// `$ <preview>` echo the shipped row printed.
    private func narrationSegments(presence: IslandSessionPresence) -> [FlightDeckSessionRowFormat.NarrationSegment] {
        if presence == .running {
            if let narrated = session.narratedActivity {
                return FlightDeckSessionRowFormat.narrationSegments(
                    verb: narrated.localizedVerb(lang),
                    object: narrated.object,
                    fallback: nil
                )
            }
            return FlightDeckSessionRowFormat.narrationSegments(
                verb: nil, object: nil, fallback: runningFallbackText
            )
        }
        // Idle / done sub-line: the last prompt, else the trailing activity — as
        // one dim run, no verb tint (and no `$` echo).
        let fallback = session.spotlightPromptLineText
            ?? forcedPromptLineText
            ?? session.spotlightActivityLineText
        return FlightDeckSessionRowFormat.narrationSegments(verb: nil, object: nil, fallback: fallback)
    }

    /// The human fallback a running row narrates when there is no structured
    /// tool activity yet — its activity summary, never a command echo.
    private var runningFallbackText: String? {
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

    /// Composes the tone-split segments into one styled `Text`: the verb reads
    /// nominal green (`#4AC99E`), the object reads bright, and a plain fallback
    /// recedes to the sub-line ink.
    private func composedNarration(
        _ segments: [FlightDeckSessionRowFormat.NarrationSegment],
        presence: IslandSessionPresence
    ) -> Text {
        let verbColor = tokens.colors.statusRunning
        let objectColor = tokens.colors.paper.opacity(contrastText(
            presence == .inactive ? tokens.colors.tertiaryTextOpacity : 0.92
        ))
        let plainColor = subLineColor(for: presence)
        return segments.reduce(Text(verbatim: "")) { accumulated, segment in
            let color: Color
            switch segment.role {
            case .verb: color = verbColor
            case .object: color = objectColor
            case .plain: color = plainColor
            }
            return accumulated + Text(verbatim: segment.text).foregroundStyle(color)
        }
    }

    /// The last assistant message rendered in the §4D detail, trimmed; `nil` when
    /// there is nothing to show.
    private var lastAssistantMessageForDetail: String? {
        guard let text = session.lastAssistantMessageText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
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
        // AB-335: hover lifts the row onto the FD `hover` surface tone
        // (#161C22), replacing the shipped `paper.opacity(0.05)` wash.
        let base = isHighlighted ? FlightDeckSurfaces.hover : Color.clear
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
        // Indent the expanded detail under the SESSION cell — past the leading
        // STATUS column and its gap — so it aligns with the headline above it.
        return sideInset + FlightDeckSessionRowGrid.statusColumnWidth + FlightDeckSessionRowGrid.leadingColumnGap
    }
}

// MARK: - Flight Deck status lane

/// The colored EICAS warning-light lane on the row's left edge — now a self-lit
/// phosphor lamp (AB-336). A flat squared bar (no fillet, the Flight Deck idiom)
/// that fills the row's height and, per its `motion` mode, breathes (running),
/// pulses on its EICAS cadence (attention), plays the one-shot success settle, or
/// holds steady; every lit bar bleeds a phosphor halo outside its silhouette via
/// the shared `phosphorGlow` primitive.
///
/// All four modes live in this one leaf (rather than branching into per-mode
/// sub-views) so its `@State` keeps a **stable identity** across a phase change:
/// that lets the settle fire only on the *live* transition into completed-success
/// (via `onChange`), not when a list of already-done rows first appears — which
/// keeps the settled dot deterministic under the snapshot harness and stops the
/// panel re-flashing every done row on each open. Motion is driven by two
/// clock-free `@State` values (the `FlightDeckRunningLight` / `PouredPillGlow`
/// precedent): a peak/trough toggle animated `repeatForever` for the breathe /
/// attention ramps, and a one-shot `settleProgress`. Under Reduce Motion no
/// animation is started and no clock is acquired — the lamp holds its lit peak
/// (breathe / attention) or its settled dot (settle), never dark.
private struct FlightDeckStatusLane: View {
    /// The lamp's settled/resting tint (advisory blue for a done lane, the alert
    /// hue for a failed one, the dim idle grey when inactive).
    let color: Color
    /// The nominal-green tint the success settle flashes through before it crosses
    /// to `color` (`statusRunning`).
    let flashTint: Color
    let width: CGFloat
    let restingOpacity: Double
    let motion: FlightDeckSessionRowFormat.LaneMotion

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Peak/trough toggle for the breathe + attention ramps. `true` (peak) whenever
    /// Reduce Motion holds the lamp steady-lit, otherwise driven between trough and
    /// peak by the `repeatForever` animation.
    @State private var breathePhase = false
    /// The one-shot success settle `0 → 1`. Starts at `1` (settled) so a lane born
    /// completed rests as the calm advisory dot; a live transition into
    /// completed-success drives it `0 → 1` for the flash.
    @State private var settleProgress: Double = 1

    private var lit: Bool { reduceMotion || breathePhase }
    private var flashAmount: Double {
        FlightDeckMotion.settleFlashAmount(progress: settleProgress)
    }

    // Per-frame resolved values (functions of `motion` + the two `@State`s).

    private var barOpacity: Double {
        switch motion {
        case .breathe:
            return lit ? FlightDeckMotion.Breathe.opacityMax : FlightDeckMotion.Breathe.opacityMin
        case .attention:
            return lit ? FlightDeckMotion.Attention.opacityMax : FlightDeckMotion.Attention.opacityMin
        case .settle, .steady:
            return restingOpacity
        }
    }

    private var glowRadius: CGFloat {
        switch motion {
        case .breathe:
            return lit ? FlightDeckMotion.Breathe.glowRadiusMax : FlightDeckMotion.Breathe.glowRadiusMin
        case .attention:
            return FlightDeckMotion.Breathe.glowRadiusMin
        case .settle:
            let span = FlightDeckMotion.Settle.flashGlowRadius - FlightDeckMotion.Settle.settledGlowRadius
            return FlightDeckMotion.Settle.settledGlowRadius + span * CGFloat(flashAmount)
        case .steady:
            return FlightDeckMotion.Breathe.glowRadiusMin
        }
    }

    private var glowIntensity: Double {
        switch motion {
        case .breathe:
            return lit ? 0.8 : 0.55
        case .attention:
            return lit ? 0.6 : 0.3
        case .settle:
            return 0.55 + 0.35 * flashAmount
        case .steady:
            return FlightDeckSessionRowFormat.steadyLaneGlowIntensity(restingOpacity: restingOpacity)
        }
    }

    private var laneScale: CGFloat {
        guard case .settle = motion else { return 1 }
        return 1 + (FlightDeckMotion.Settle.flashScale - 1) * CGFloat(flashAmount)
    }

    var body: some View {
        Rectangle()
            .fill(color)
            .opacity(barOpacity)
            // The settle flashes the nominal green through the settled advisory bar
            // by crossfading a green overlay on top (SwiftUI can't blend two
            // `Color`s directly); `flashAmount` is `0` at rest so the bar reads pure
            // advisory once settled.
            .overlay {
                if case .settle = motion, flashAmount > 0 {
                    Rectangle().fill(flashTint).opacity(flashAmount)
                }
            }
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .scaleEffect(x: laneScale, y: 1, anchor: .center)
            // The phosphor halo bleeds outside the bar (BRIEF §7). During the
            // settle flash the halo is the nominal green; once settled it's the
            // advisory tint — a small steady dot.
            .phosphorGlow(
                shape: Rectangle(),
                tint: settleFlashing ? flashTint : color,
                radius: glowRadius,
                intensity: glowIntensity
            )
            .accessibilityHidden(true)
            .onAppear { syncMotion(initial: true) }
            .onChange(of: motion) { _, _ in syncMotion(initial: false) }
    }

    private var settleFlashing: Bool {
        if case .settle = motion { return flashAmount > 0 }
        return false
    }

    private func syncMotion(initial: Bool) {
        // Reduce Motion: hold the lit peak / settled dot, never animate, never
        // acquire a clock (AC #5, §K).
        guard !reduceMotion else {
            breathePhase = false // `lit` resolves to peak via `reduceMotion || …`
            settleProgress = 1
            return
        }
        switch motion {
        case .breathe:
            animateBreathe(period: FlightDeckMotion.Breathe.period)
        case .attention(let period):
            animateBreathe(period: period)
        case .settle:
            if initial {
                // Born completed — rest at the settled advisory dot, no flash.
                settleProgress = 1
            } else {
                // Live completion — play the one-shot nominal flash → advisory (A5).
                settleProgress = 0
                withAnimation(.easeOut(duration: FlightDeckMotion.Settle.duration)) {
                    settleProgress = 1
                }
            }
        case .steady:
            break
        }
    }

    /// Drives the peak/trough toggle on a `period`-second ease-in-out that
    /// autoreverses forever, so `barOpacity` / `glowRadius` bounce between their
    /// pinned trough and peak (the `FlightDeckRunningLight` pattern). Half the
    /// period per leg, so a full breathe/pulse cycle takes `period`.
    private func animateBreathe(period: Double) {
        breathePhase = false
        withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) {
            breathePhase = true
        }
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

// MARK: - Row entrance (relay-snap in)

/// AB-337 · §4K: the one-shot relay-snap a Flight Deck row plays when it is
/// **inserted** into an already-mounted list (`FlightDeckMotion.Entrance`,
/// mockup `enter`).
///
/// Mirrors Poured's `PouredRowEntrance`: expressed as a SwiftUI insertion
/// `.transition` (applied per row by `FlightDeckSessionListScaffold`, driven by
/// the scaffold's entrance animation keyed to the section's row-id set) rather
/// than an `onAppear` state machine. A container's **initial** appearance never
/// plays insertion transitions, so the whole list arrives at its settled frame
/// under the panel's own open morph (and the first-render snapshot pins that
/// settled frame); the scaffold gates the driving animation on Reduce Motion, so
/// a reduced-motion insert simply snaps in — no clock is ever touched.
enum FlightDeckRowEntrance {
    /// Horizontal slide + fade, from the mockup `enter` keyframe. Removal is a
    /// plain fade so a dismissed row doesn't lurch.
    static var transition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: FlightDeckMotion.Entrance.slideOffset)
                .combined(with: .opacity),
            removal: .opacity
        )
    }

    /// The relay-snap settle spring the scaffold drives the insertion with (nil
    /// under Reduce Motion → the insert snaps).
    static let animation: Animation = .spring(
        response: FlightDeckMotion.Entrance.springResponse,
        dampingFraction: FlightDeckMotion.Entrance.springDamping,
        blendDuration: 0
    )
}

// MARK: - Row chip

/// A small mono placard chip that rides beside the session name (AB-337). Part 1
/// uses it for the `SSH` remote flag folded out of the removed APP column; Part 2
/// adds the branch / permission-mode / `⚙ N SUB` chips through the same grammar.
/// A caps mono micro-label in a chamfered hairline frame — a value placard, so it
/// stays Latin + letterspaced on Latin and neutralizes for CJK via
/// `FlightDeckText`, and holds the 10pt floor.
private struct FlightDeckRowChip: View {
    let text: String
    let lang: LanguageManager
    /// Placards (`SSH`, `ACCEPTEDITS`) uppercase + letterspace; data chips (a
    /// branch name, a recency phrase) render verbatim so their case survives.
    var uppercases: Bool = true
    /// An optional leading glyph drawn faint before the text (the branch `⑂`).
    var leadingGlyph: String?
    /// An optional status tint — the `⚙ N SUB` chip reads nominal green with a
    /// green-tinted border; nil keeps the quiet dim ink + hairline frame.
    var tint: Color?

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var resolvedText: String {
        uppercases ? FlightDeckText.caps(text, lang: lang) : text
    }

    private var textColor: Color {
        if let tint { return tint }
        return tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast))
    }

    private var borderColor: Color {
        if let tint { return tint.opacity(0.4) }
        return FlightDeckSurfaces.hairline(tier: 2, increaseContrast: increasesContrast)
    }

    var body: some View {
        HStack(spacing: 0) {
            if let leadingGlyph {
                Text(leadingGlyph + " ")
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            }
            Text(resolvedText)
                .foregroundStyle(textColor)
        }
        .font(.system(size: FlightDeckTypography.microLabelSize, weight: .semibold, design: .monospaced))
        .tracking(uppercases ? FlightDeckText.tracking(0.6, lang: lang) : 0)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(FlightDeckChamferedRectangle(chamfer: 2.5).fill(FlightDeckSurfaces.tile))
        .overlay(
            FlightDeckChamferedRectangle(chamfer: 2.5)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Metagrid flow

/// A left-to-right wrapping flow for the §4D metacell tiles (mockup `.metagrid`,
/// a CSS `repeat(auto-fill)` grid). Each cell is placed at its intrinsic size and
/// wraps to the next row when the current one is full, so absent fields simply
/// don't take a slot — no reserved empty cells, no `—` dashes.
private struct FlightDeckMetaFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let addedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, addedWidth > maxWidth {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = addedWidth
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

// MARK: - Chamfer geometry

/// A rectangle with its four corners cut at 45° — the Flight Deck idiom's answer
/// to a rounded corner. A true bevel (not a fillet), so the panel reads as
/// milled hardware rather than poured glass; the `chamfer` size is clamped so it
/// can never exceed half the shorter edge. `InsettableShape` so it composes with
/// `strokeBorder` like `RoundedRectangle`.
struct FlightDeckChamferedRectangle: InsettableShape {
    var chamfer: CGFloat
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> FlightDeckChamferedRectangle {
        FlightDeckChamferedRectangle(chamfer: chamfer, inset: inset + amount)
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let c = min(chamfer, min(r.width, r.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.closeSubpath()
        return path
    }
}

// MARK: - Actionable row content (AB-314)

/// The Flight Deck body for an **actionable** row — a permission request
/// (MASTER CAUTION), a question, or the single completion card — across the
/// `.list` and `.notification` presentations. A mono tabular header (so an
/// actionable row still reads as one of the annunciator grid) sits above the
/// phase-specific interior: `FlightDeckApprovalCard` for approvals, the shared
/// `StructuredQuestionPromptView` for questions, and a squared mono completion
/// card for completions. The header carries the same grouped VoiceOver summary as
/// every other theme, and the tap-to-jump / dismiss behaviours are preserved
/// verbatim from Classic.
private struct FlightDeckActionableRowContent: View {
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

    private func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * typeScale, weight: weight, design: .monospaced)
    }

    /// The sans companion to `scaledFont` (AB-337 · SPEC §2): the narration
    /// typeface for prose the reader *reads* — the session / workspace name and
    /// the activity narration — scaled off the same one reference so it tracks
    /// Dynamic Type alongside the mono value columns. Every value (durations,
    /// ages, codes, placards) keeps `scaledFont`.
    private func sansScaled(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * typeScale, weight: weight, design: .default)
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
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.12), value: isHighlighted)
        .animation(.easeInOut(duration: 0.16), value: session.phase)
        .animation(.easeInOut(duration: 0.16), value: session.outcome)
        .onTapGesture(perform: handlePrimaryTap)
    }

    // MARK: - Header (mono tabular idiom)

    private func header(referenceDate: Date) -> some View {
        HStack(alignment: .top, spacing: FlightDeckSessionRowGrid.leadingColumnGap) {
            // Reserve the leading STATUS column so an actionable list row's
            // headline registers under the SESSION caption alongside the
            // non-actionable rows (AB-337). The annunciator header below carries
            // the WARN / CAUT status, so the column holds only the indicator
            // glyph, not a code. The notification card has no column grid, so it
            // reserves nothing.
            if presentation == .list {
                Group {
                    if showsLeadingStatusIndicator {
                        Image(systemName: FlightDeckSessionRowFormat.statusGlyphName(phase: session.phase, outcome: session.outcome))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(statusTint)
                            .padding(.top, 1)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: FlightDeckSessionRowGrid.statusColumnWidth, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayHeadline)
                    // AB-337 · SPEC §2: the session name is sans narration, matching
                    // the non-actionable row so an alarm still reads as one of the
                    // annunciator grid — 13.5pt semibold, −0.01em.
                    .font(sansScaled(FlightDeckTypography.sessionNameSize, weight: .semibold))
                    .tracking(FlightDeckTypography.sessionNameTracking)
                    .foregroundStyle(tokens.colors.paper)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(session.spotlightWorkspaceName)

                if let promptLine = headerPromptLineText {
                    Text(promptLine)
                        // Narration prose — sans, 12pt (SPEC §2).
                        .font(sansScaled(FlightDeckTypography.narrationSize, weight: .medium))
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: FlightDeckSessionRowGrid.columnGap) {
                agentCell
                Text(ageBadgeText(at: referenceDate))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
                    .frame(width: FlightDeckSessionRowGrid.timeColumnWidth, alignment: .trailing)
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
        .padding(.bottom, showsActionableBody ? 8 : 11)
        // The one grouped VoiceOver summary, identical wording to every theme.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityRowSummaryText(referenceDate: referenceDate))
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        .accessibilityAction {
            guard isInteractive else { return }
            actions.jump()
        }
        .modifier(FlightDeckOptionalNamedAccessibilityAction(
            name: actions.dismiss != nil ? lang.t("a11y.session.dismiss") : nil,
            action: { actions.dismiss?() }
        ))
    }

    /// Agent identity as a small **neutral** mono mark (a dim square + label) so
    /// the annunciator status colour — the row's real signal — always wins.
    private var agentCell: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                .frame(width: 3, height: 11)
                .accessibilityHidden(true)
            Text(agentBadgeTitle)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
                .lineLimit(1)
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
            FlightDeckApprovalCard(session: session, lang: lang, actions: actions, pulseClock: pulseClock)
        case .waitingForAnswer:
            // AB-334: the question is an amber MASTER CAUTION — the shared
            // `StructuredQuestionPromptView` interior is *wrapped* (an annunciator
            // header lit above it), never modified.
            VStack(alignment: .leading, spacing: 10) {
                FlightDeckQuestionAnnunciator(lang: lang, pulseClock: pulseClock)
                StructuredQuestionPromptView(
                    prompt: session.questionPrompt,
                    lang: lang,
                    keyboardCoordinator: keyboardCoordinator,
                    onAnswer: { actions.answer?($0) }
                )
            }
        case .completed:
            completionBody
        case .running:
            if let preview = runningDetailText {
                runningPreviewBox(preview)
            }
        }
    }

    private func runningPreviewBox(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.82)))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FlightDeckChamferedRectangle(chamfer: 6).fill(tokens.colors.paper.opacity(0.04)))
            .overlay(FlightDeckChamferedRectangle(chamfer: 6).strokeBorder(tokens.colors.paper.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Completion body (chamfered, mono-leaning)

    private var completionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !completionMessageText.isEmpty {
                if session.outcome != .success {
                    completionOutcomeBanner
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
                    .frame(height: 1)

                completionReplyInput
            }
        }
        // AB-335: the completion card seats on the FD `tile` sub-panel tone
        // (#101519), framed by a tier-2 bezel that brightens under Increase
        // Contrast, replacing the shipped `paper.opacity(0.04)` wash.
        .background(FlightDeckChamferedRectangle(chamfer: 6).fill(FlightDeckSurfaces.tile))
        .overlay(FlightDeckChamferedRectangle(chamfer: 6).strokeBorder(FlightDeckSurfaces.hairline(tier: 2, increaseContrast: increasesContrast), lineWidth: 1))
    }

    private var completionOutcomeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: FlightDeckApprovalFormat.completionOutcomeGlyphName(outcome: session.outcome))
                .font(.system(size: 10.5, weight: .bold))
                .accessibilityHidden(true)
            Text(FlightDeckText.caps(completionOutcomeLabel, lang: lang))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(FlightDeckText.tracking(0.8, lang: lang))
            Spacer(minLength: 0)
        }
        .foregroundStyle(statusTint.opacity(0.96))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var completionEmptyState: some View {
        HStack {
            Text(FlightDeckText.caps(completionOutcomeLabel, lang: lang))
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .tracking(FlightDeckText.tracking(0.8, lang: lang))
                .foregroundStyle(statusTint.opacity(0.96))
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

    private var completionOutcomeLabel: String {
        switch session.outcome {
        case .success: return lang.t("completion.done")
        case .interrupted: return lang.t("completion.interrupted")
        case .failed: return lang.t("completion.failed")
        }
    }

    private var completionMessageText: String {
        if let text = session.completionAssistantMessageText?.flightDeckTrimmed, !text.isEmpty {
            return text
        }
        let summary = session.summary.flightDeckTrimmed
        return summary == SessionPhase.completed.displayName ? "" : summary
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

    private var headerPromptLineText: String? {
        if presentation == .notification {
            return session.notificationHeaderPromptLineText
        }
        return session.spotlightPromptLineText
    }

    private var runningDetailText: String? {
        if let preview = session.currentCommandPreviewText?.flightDeckTrimmed, !preview.isEmpty {
            return "$ \(preview)"
        }
        if let activity = session.spotlightActivityLineText?.flightDeckTrimmed, !activity.isEmpty {
            return activity
        }
        let summary = session.summary.flightDeckTrimmed
        return summary.isEmpty ? nil : summary
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

    private var statusTint: Color {
        tokens.colors.statusTint(for: session.phase, outcome: session.outcome)
    }

    // MARK: - Layout insets

    private var showsLeadingStatusIndicator: Bool {
        presentation == .list && stateIndicator != .tint && stateIndicator != .bar
    }

    private var rowLeadingInset: CGFloat {
        if presentation == .notification { return sideInset }
        return sideInset
    }

    private var detailLeadingInset: CGFloat {
        if presentation == .notification { return sideInset }
        // Indent the alarm / completion interior under the SESSION cell — past the
        // reserved leading STATUS column and its gap — so it aligns with the
        // headline above it and with the non-actionable rows (AB-337).
        return sideInset + FlightDeckSessionRowGrid.statusColumnWidth + FlightDeckSessionRowGrid.leadingColumnGap
    }

    private var rowFillColor: Color {
        if presentation == .notification { return .clear }
        // AB-335: hover lifts onto the FD `hover` surface tone (#161C22).
        return isHighlighted ? FlightDeckSurfaces.hover : .clear
    }
}

// MARK: - Flight Deck annunciator header (AB-334)

/// The shared annunciator-header grammar both actionable alarms wear: a pulsing
/// beacon lamp, a filled placard chip, a kicker, and an optional right-aligned
/// slot (the permission card fills it with `HELD`; the question leaves it empty).
///
/// The permission card lights it **red** (`MASTER WARNING` · `PERMISSION
/// REQUIRED`, 1.0s beacon); the question lights it **amber** (`MASTER CAUTION` ·
/// `QUESTION`, 1.2s beacon). Splitting the grammar into one component keeps the
/// two annunciators identical in structure and lets the question wrap the shared
/// `StructuredQuestionPromptView` interior without touching it (AB-334).
private struct FlightDeckAnnunciatorHeader<Trailing: View>: View {
    let tint: Color
    let placard: String
    let kicker: String
    let beaconPeriod: Double
    let pulseClock: PulseClock?
    let lang: LanguageManager
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    var body: some View {
        HStack(spacing: 8) {
            FlightDeckAnnunciatorBeacon(color: tint, period: beaconPeriod, pulseClock: pulseClock)

            Text(FlightDeckText.caps(placard, lang: lang))
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .tracking(FlightDeckText.tracking(1.2, lang: lang))
                .foregroundStyle(tokens.colors.surfaceInk)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(FlightDeckChamferedRectangle(chamfer: 3).fill(tint))
                .accessibilityHidden(true)

            Text(FlightDeckText.caps(kicker, lang: lang))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(FlightDeckText.tracking(0.6, lang: lang))
                .foregroundStyle(tint.opacity(increasesContrast ? 1 : 0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            trailing()
        }
    }
}

/// A single annunciator beacon lamp: a small chamfered square in the alarm tint
/// that breathes at its own `period` (AB-334). It rides the shared 15fps
/// `PulseClock` for invalidation but derives its brightness from wall-clock time
/// at `period`, so the red (1.0s) and amber (1.2s) lamps can be retimed
/// independently — something the shared clock's single fixed period can't do.
/// Reduce Motion (or a missing clock) draws it steady-lit.
private struct FlightDeckAnnunciatorBeacon: View {
    let color: Color
    let period: Double
    let pulseClock: PulseClock?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let side: CGFloat = 11
    static let chamfer: CGFloat = 3

    var body: some View {
        if let pulseClock, !reduceMotion {
            FlightDeckPulsingBeacon(color: color, period: period, pulseClock: pulseClock)
        } else {
            lamp(opacity: FlightDeckApprovalFormat.beaconLevel(now: .now, period: period, reduceMotion: true))
        }
    }

    func lamp(opacity: Double) -> some View {
        FlightDeckChamferedRectangle(chamfer: Self.chamfer)
            .fill(color)
            .frame(width: Self.side, height: Self.side)
            .opacity(opacity)
            .accessibilityHidden(true)
    }
}

/// The animating beacon leaf. Isolated so Observation's per-view tracking
/// invalidates only the lamp on each 15fps tick (AB-228 pattern), and so Reduce
/// Motion never even acquires the clock — its steady sibling is drawn instead.
private struct FlightDeckPulsingBeacon: View {
    let color: Color
    let period: Double
    let pulseClock: PulseClock

    var body: some View {
        // Touch `phase` so Observation re-runs this leaf on every shared 15fps
        // tick; the actual brightness is a pure function of wall-clock time at this
        // lamp's own `period` (the shared clock's fixed period can't be retimed).
        _ = pulseClock.phase
        return FlightDeckChamferedRectangle(chamfer: FlightDeckAnnunciatorBeacon.chamfer)
            .fill(color)
            .frame(width: FlightDeckAnnunciatorBeacon.side, height: FlightDeckAnnunciatorBeacon.side)
            .opacity(FlightDeckApprovalFormat.beaconLevel(now: .now, period: period, reduceMotion: false))
            .onAppear { pulseClock.acquire() }
            .onDisappear { pulseClock.release() }
            .accessibilityHidden(true)
    }
}

/// The amber **MASTER CAUTION** annunciator that heads the question phase
/// (AB-334): it wraps — never modifies — the shared `StructuredQuestionPromptView`
/// interior. `MASTER CAUTION` placard + `QUESTION` kicker, tinted the caution
/// amber (`statusWaitingForAnswer`), 1.2s beacon.
private struct FlightDeckQuestionAnnunciator: View {
    let lang: LanguageManager
    let pulseClock: PulseClock?

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        FlightDeckAnnunciatorHeader(
            tint: tokens.colors.statusWaitingForAnswer,
            placard: lang.t("island.flightDeck.approval.masterCaution"),
            kicker: lang.t("island.flightDeck.question.kicker"),
            beaconPeriod: FlightDeckApprovalFormat.questionBeaconPeriod,
            pulseClock: pulseClock,
            lang: lang
        ) {
            EmptyView()
        }
    }
}

// MARK: - Flight Deck approval card (AB-314)

/// The permission request rendered as the Flight Deck **MASTER CAUTION** —
/// a full-width chamfered alert block that stays the loudest row on the panel.
/// A pulsing caution glow rides the block edge (a slow warning-annunciator throb
/// off the shared clock, held steady under Reduce Motion); a stenciled
/// `MASTER CAUTION` placard and `PERMISSION REQUIRED` kicker head it, the command
/// sits in a chamfered mono box above the affected-path line and the optional
/// `PermissionDiffPreview` (whose +/− already render in the phosphor green/red),
/// and the ALLOW (inverted) / DENY (outlined) chamfered switches each print the
/// **real** ⌘Y / ⌘N key-hint glyph the global keyboard handler fires; the
/// always-allow options carry ⌘⇧Y.
///
/// The alarm tint follows the semantic status token — warning **red** for a
/// blocked permission (`statusWaitingForApproval == statusFailed`) — so the block
/// matches the red status lane the row already draws in the list; the amber
/// caution light stays the question phase's signal. (Semantic state colours
/// always win.) Nothing but the glow animates, so Reduce Motion pins it steady.
private struct FlightDeckApprovalCard: View {
    let session: AgentSession
    let lang: LanguageManager
    let actions: RowActions
    let pulseClock: PulseClock?

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    private static let cardChamfer: CGFloat = 6

    /// The alarm tint — the same token approval / failure status resolves to.
    private var alarm: Color { tokens.colors.statusWaitingForApproval }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            annunciatorHeader

            // Command preview in a chamfered mono box + affected-path line.
            VStack(alignment: .leading, spacing: 6) {
                commandContent
                    .fixedSize(horizontal: false, vertical: true)

                if let path = affectedPath {
                    Text(path)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.5)))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            // AB-335: the command sits in a recessed FD `well` (#060708), darker
            // than the card around it, so it reads as sunk into the panel — not
            // the shipped light `paper` wash that read raised.
            .background(FlightDeckChamferedRectangle(chamfer: 5).fill(FlightDeckSurfaces.well))
            .overlay(FlightDeckChamferedRectangle(chamfer: 5).strokeBorder(FlightDeckSurfaces.hairline(tier: 2, increaseContrast: increasesContrast), lineWidth: 1))

            if let diffResult = permissionDiffResult {
                // AB-335: the diff reads recessed too — seated in the same FD
                // `well` tone as the command box, a matched pair of sunk panels.
                PermissionDiffPreview(result: diffResult, lang: lang)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FlightDeckChamferedRectangle(chamfer: 5).fill(FlightDeckSurfaces.well))
                    .overlay(FlightDeckChamferedRectangle(chamfer: 5).strokeBorder(FlightDeckSurfaces.hairline(tier: 2, increaseContrast: increasesContrast), lineWidth: 1))
            }

            if session.permissionRequest?.requiresTerminalApproval == true {
                terminalApprovalCTA
            } else {
                HStack(spacing: 8) {
                    FlightDeckApprovalButton(
                        title: denyTitle,
                        shortcut: .deny,
                        kind: .outlined,
                        lang: lang,
                        accessibilityLabel: session.permissionRequest?.secondaryActionTitle ?? lang.t("a11y.approval.deny"),
                        action: { actions.approve?(.deny) }
                    )
                    FlightDeckApprovalButton(
                        title: allowTitle,
                        shortcut: .allowOnce,
                        kind: .inverted,
                        lang: lang,
                        accessibilityLabel: session.permissionRequest?.primaryActionTitle ?? lang.t("a11y.approval.allowOnce"),
                        action: { actions.approve?(.allowOnce) }
                    )
                }

                alwaysAllowOptions
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlightDeckChamferedRectangle(chamfer: Self.cardChamfer).fill(cardFill))
        // The chamfered alarm frame — a hard bevel, no fillet.
        .overlay(
            FlightDeckChamferedRectangle(chamfer: Self.cardChamfer)
                .strokeBorder(alarm.opacity(increasesContrast ? 1 : 0.85), lineWidth: 1.5)
        )
        // The MASTER CAUTION glow behind the block — pulsing with motion, steady
        // under Reduce Motion (both handled by the leaf).
        .background(
            FlightDeckCautionGlow(color: alarm, chamfer: Self.cardChamfer, pulseClock: pulseClock)
        )
        .accessibilityElement(children: .contain)
    }

    /// The red **MASTER WARNING** annunciator (AB-334): the pulsing red beacon lamp
    /// (1.0s), a filled `MASTER WARNING` placard chip, the `PERMISSION REQUIRED`
    /// kicker, and a right-aligned `HELD` count-up. EICAS nomenclature — a blocked
    /// permission is a red *WARNING*, not the amber *CAUTION* the question phase
    /// carries. The placard/kicker neutralize (uncased, untracked) on CJK via
    /// `FlightDeckText`.
    private var annunciatorHeader: some View {
        FlightDeckAnnunciatorHeader(
            tint: alarm,
            placard: lang.t("island.flightDeck.approval.masterWarning"),
            kicker: lang.t("island.flightDeck.approval.permissionRequired"),
            beaconPeriod: FlightDeckApprovalFormat.permissionBeaconPeriod,
            pulseClock: pulseClock,
            lang: lang
        ) {
            heldReadout
        }
    }

    /// The `HELD 0m 08s` count-up: how long the agent has been blocked on this
    /// request. A dedicated ≤1s `TimelineView` ticks only this readout (not the
    /// whole card), the digits are tabular mono, and the block hides itself when
    /// the elapsed approximation is implausible (see `FlightDeckApprovalFormat`).
    @ViewBuilder
    private var heldReadout: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let elapsed = FlightDeckApprovalFormat.heldReadout(
                now: context.date,
                since: session.updatedAt
            ) {
                HStack(spacing: 5) {
                    Text(FlightDeckText.caps(lang.t("island.flightDeck.approval.held"), lang: lang))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(FlightDeckText.tracking(1.2, lang: lang))
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                    Text(elapsed)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced).monospacedDigit())
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.86)))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The command awaiting approval, syntax-highlighted through the shipped
    /// `ShellCommandTokenizer` (T10 / AB-328) via an FD-local kind→tone table:
    /// command = paper/600, subcommand + strings = nominal green, flags + paths =
    /// dim paper, everything else inherits the block ink. Falls back to a plain
    /// mono summary line when there is no command preview to tokenize.
    private var commandContent: some View {
        commandText
            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
    }

    private var commandText: Text {
        if let preview = session.currentCommandPreviewText?.flightDeckTrimmed, !preview.isEmpty {
            let highlighted = ShellCommandTokenizer.attributed(
                preview,
                palette: commandSyntaxPalette,
                weights: [.command: .semibold],
                baseFont: .system(size: 11.5, weight: .regular, design: .monospaced)
            )
            return Text("$ ")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundColor(tokens.colors.paper.opacity(contrastText(0.4)))
                + Text(highlighted)
        }
        let fallback = (session.permissionRequest?.summary ?? session.summary).flightDeckTrimmed
        return Text(fallback)
            .foregroundColor(tokens.colors.paper.opacity(contrastText(0.86)))
    }

    /// The FD-local kind→tone table (AC #6). No new hexes are invented — every tone
    /// is an existing Flight Deck token: paper for the command, the nominal green
    /// for subcommands + strings, dim paper for flags + paths.
    private var commandSyntaxPalette: [ShellCommandTokenizer.Kind: Color] {
        let paper = tokens.colors.paper
        let dim = paper.opacity(contrastText(0.5))
        return [
            .command: paper.opacity(contrastText(0.92)),
            .subcommand: tokens.colors.statusRunning,
            .string: tokens.colors.statusRunning,
            .flag: dim,
            .path: dim,
            .plain: paper.opacity(contrastText(0.86)),
        ]
    }

    /// Under Reduce Transparency (a no-op for this opaque theme, but guarded) and
    /// by default the card sits on the opaque ink ground with a faint alarm wash,
    /// so legibility never depends on anything showing through.
    private var cardFill: Color {
        reduceTransparency ? tokens.colors.surfaceInk : alarm.opacity(0.08)
    }

    /// AB-235: scoped always-allow options (one per suggested update) or the
    /// generic session-scoped fallback — the same calls ⌘⇧Y drives. The first
    /// option carries the ⌘⇧Y key-hint glyph the shortcut fires against.
    @ViewBuilder
    private var alwaysAllowOptions: some View {
        if let updates = session.permissionRequest?.suggestedUpdates, !updates.isEmpty {
            VStack(spacing: 6) {
                ForEach(Array(updates.enumerated()), id: \.offset) { index, update in
                    FlightDeckApprovalButton(
                        title: update.displayLabel,
                        shortcut: index == 0 ? .alwaysAllow : nil,
                        kind: .ghost,
                        lang: lang,
                        uppercases: false,
                        accessibilityLabel: update.displayLabel,
                        action: { actions.approve?(.allowWithUpdates([update])) }
                    )
                }
            }
        } else if let toolName = session.permissionRequest?.toolName {
            FlightDeckApprovalButton(
                title: lang.t("approval.alwaysAllow", toolName),
                shortcut: .alwaysAllow,
                kind: .ghost,
                lang: lang,
                uppercases: false,
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
        FlightDeckApprovalButton(
            title: lang.t("approval.respondInTerminal"),
            shortcut: nil,
            kind: .ghost,
            lang: lang,
            leadingGlyph: "arrow.up.forward.square",
            accessibilityLabel: lang.t("approval.respondInTerminal"),
            action: { actions.jump() }
        )
    }

    private var allowTitle: String {
        session.permissionRequest?.primaryActionTitle ?? lang.t("island.flightDeck.approval.allow")
    }

    private var denyTitle: String {
        session.permissionRequest?.secondaryActionTitle ?? lang.t("island.flightDeck.approval.deny")
    }

    private var affectedPath: String? {
        guard let path = session.permissionRequest?.affectedPath.flightDeckTrimmed, !path.isEmpty else {
            return nil
        }
        return path
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

/// The pulsing MASTER CAUTION glow behind the alarm block. A blurred chamfered
/// halo in the alarm tint whose opacity throbs off the shared 15fps clock;
/// isolated in its own `View` so Observation's per-view tracking invalidates only
/// the halo at 15fps (AB-228), and so Reduce Motion never even acquires the clock
/// — the steady halo is drawn instead (AB-244).
private struct FlightDeckCautionGlow: View {
    let color: Color
    let chamfer: CGFloat
    let pulseClock: PulseClock?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let pulseClock, !reduceMotion {
            FlightDeckPulsingGlow(color: color, chamfer: chamfer, pulseClock: pulseClock)
        } else {
            halo(opacity: FlightDeckApprovalFormat.glowOpacity(phase: 0, reduceMotion: true))
        }
    }

    /// The alarm halo is now the shared `FlightDeckPhosphorGlow` primitive
    /// (AB-336) at the caution block's radius (9) — the same blur/bleed the
    /// shipped inline halo drew, so the MASTER WARNING / CAUTION goldens are
    /// unchanged, but there is one glow technique across the theme now.
    static let haloRadius: CGFloat = 9

    func halo(opacity: Double) -> some View {
        FlightDeckPhosphorGlow(
            shape: FlightDeckChamferedRectangle(chamfer: chamfer),
            tint: color,
            radius: Self.haloRadius,
            intensity: opacity
        )
    }
}

private struct FlightDeckPulsingGlow: View {
    let color: Color
    let chamfer: CGFloat
    let pulseClock: PulseClock

    var body: some View {
        FlightDeckPhosphorGlow(
            shape: FlightDeckChamferedRectangle(chamfer: chamfer),
            tint: color,
            radius: FlightDeckCautionGlow.haloRadius,
            intensity: FlightDeckApprovalFormat.glowOpacity(phase: pulseClock.phase, reduceMotion: false)
        )
        .onAppear { pulseClock.acquire() }
        .onDisappear { pulseClock.release() }
    }
}

/// A chamfered Flight Deck approval switch. `inverted` fills with paper for the
/// loud affirmative (ALLOW), `outlined` is a paper hairline frame (DENY), and
/// `ghost` is a dim outline for the stacked always-allow / terminal options. The
/// trailing key-hint chip prints the real registered shortcut glyphs.
private struct FlightDeckApprovalButton: View {
    enum Kind { case inverted, outlined, ghost }

    let title: String
    let shortcut: FlightDeckApprovalFormat.Shortcut?
    let kind: Kind
    let lang: LanguageManager
    var uppercases: Bool = true
    var leadingGlyph: String?
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    private static let chamfer: CGFloat = 5

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let leadingGlyph {
                    Image(systemName: leadingGlyph)
                        .font(.system(size: 10.5, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(uppercases ? FlightDeckText.caps(title, lang: lang) : title)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .tracking(uppercases ? FlightDeckText.tracking(0.8, lang: lang) : 0)
                    .lineLimit(1)
                if let shortcut {
                    keyHint(shortcut)
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(FlightDeckChamferedRectangle(chamfer: Self.chamfer).fill(background))
            .overlay(FlightDeckChamferedRectangle(chamfer: Self.chamfer).strokeBorder(border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The key-hint chip — a chamfered mono glyph run (`⌘Y`) in the switch's own
    /// foreground, faintly boxed so it reads as a keycap without shouting.
    private func keyHint(_ shortcut: FlightDeckApprovalFormat.Shortcut) -> some View {
        Text(shortcut.glyphString)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(foreground.opacity(0.85))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(FlightDeckChamferedRectangle(chamfer: 2.5).strokeBorder(foreground.opacity(0.35), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var foreground: Color {
        switch kind {
        case .inverted:
            return tokens.colors.surfaceInk
        case .outlined:
            return tokens.colors.paper.opacity(tokens.colors.text(0.85, increaseContrast: increasesContrast))
        case .ghost:
            return tokens.colors.paper.opacity(tokens.colors.text(0.7, increaseContrast: increasesContrast))
        }
    }

    private var background: Color {
        switch kind {
        case .inverted:
            return tokens.colors.paper
        case .outlined, .ghost:
            return tokens.colors.paper.opacity(0.03)
        }
    }

    private var border: Color {
        switch kind {
        case .inverted:
            return tokens.colors.paper
        case .outlined:
            return tokens.colors.paper.opacity(increasesContrast ? 0.7 : 0.4)
        case .ghost:
            return tokens.colors.paper.opacity(increasesContrast ? 0.5 : 0.18)
        }
    }
}

private extension String {
    var flightDeckTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
