import SwiftUI
import OpenIslandCore

/// Flight Deck theme's closed-pill slot (AB-311).
///
/// The Flight Deck look is a flat avionics annunciator panel, so the pill drops
/// the glass treatment entirely: a solid `surfaceInk` body outlined by a single
/// hairline bezel rule, the idle mode glyph, mono labels, and the agents grid
/// rendered as **square annunciator lights** — each lamp seated in a hairline
/// housing. Colour is spent only on status *by state*, never on agent brand:
/// a running lamp lights cyan-green nominal, an idle lamp sits dark in its
/// housing, a waiting lamp flashes amber caution, and an overflow lamp reads
/// "+N". Keeping the lamps semantic (not brand-tinted) is how slice 1 manages the
/// ticket's known tension — the amber / green hierarchy always wins, and agent
/// identity stays the neutral square mark.
///
/// Layout (glyph, centre label, notch-lane label, right slot) and the
/// fluid-width math are shared verbatim with `V6ClosedPill` — the same statics
/// `PouredClosedPill` / `InstrumentClosedPill` reuse — so the pill's outer
/// dimensions, and therefore the closed↔opened morph frame in `IslandPanelView`,
/// stay identical across themes. Only the fill treatment and the lamp styling
/// differ. The centre / notch-lane labels are already `.monospaced`, so reusing
/// them keeps the widths pinned and the "mono labels" requirement met for free.
struct FlightDeckClosedPill: View {
    var mode: UnifiedBars.Mode
    var label: String?
    var rightSlot: IslandRightSlotContent?
    var layout: V6ClosedLayout
    var height: CGFloat = 32
    var physicalNotchWidth: CGFloat = 0
    var minWidth: CGFloat = 70
    var showsGlyph: Bool = true

    @Environment(\.islandTokens) private var tokens
    /// The spotlight's phase/outcome (AB-330 plumbing), folded into the pill's
    /// attention bloom so a held permission / open question tints the bezel and
    /// (via the seam layer) blooms a coloured glow — the pill's "one loud thing".
    @Environment(\.islandClosedPillActivity) private var activity

    private static let glyphSize: CGFloat = 24
    private static let innerGap: CGFloat = 6
    private static let notchLaneLabelGap: CGFloat = 6

    private var pad: CGFloat { height / 2 }

    var body: some View {
        switch layout {
        case .external: externalBody
        case .macbook:  macbookBody
        }
    }

    // MARK: Background

    /// Flat annunciator body: a solid `surfaceInk` fill outlined by a single
    /// hairline bezel rule at the theme's hairline opacity — the same hairline
    /// vocabulary the panel chrome uses, so the closed and opened states read as
    /// one instrument. No vibrancy, no specular; nothing to drop under Reduce
    /// Transparency because there is no transparency to reduce.
    private var flightDeckBackground: some View {
        V6ClosedPillShape()
            .fill(tokens.colors.surfaceInk)
            .overlay(
                V6ClosedPillShape()
                    .stroke(bezelColor, lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }

    /// The pill's bezel rule (AB-336): the neutral hairline normally, repointed to
    /// the attention tint (warning red / caution amber, at the mockup's border
    /// alpha) while the pill is the loud attention state — the border half of the
    /// bloom, whose colored-shadow half rides the `FlightDeckClosedGlow` seam.
    private var bezelColor: Color {
        if let bloom {
            return bloom.tint(tokens.colors).opacity(bloom.borderOpacity)
        }
        return tokens.colors.paper.opacity(tokens.colors.hairlineOpacity)
    }

    /// The resolved attention bloom, or `nil` for every non-attention state (the
    /// pill stays flat hardware).
    private var bloom: FlightDeckPillBloom? {
        FlightDeckPillBloom.resolve(activity: activity, mode: mode, rightSlot: rightSlot)
    }

    @ViewBuilder
    private var glyphOrPlaceholder: some View {
        if showsGlyph {
            UnifiedBars(mode: mode, size: Self.glyphSize)
                .frame(width: Self.glyphSize, height: Self.glyphSize)
        } else {
            Color.clear
                .frame(width: Self.glyphSize, height: Self.glyphSize)
        }
    }

    @ViewBuilder
    private var rightSlotView: some View {
        if let rightSlot {
            FlightDeckRightSlotView(content: rightSlot)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    // MARK: External (fluid)

    private var externalBody: some View {
        let width = V6ClosedPill.externalOuterWidth(
            label: label,
            rightSlot: rightSlot,
            minWidth: minWidth,
            height: height
        )

        return ZStack {
            flightDeckBackground

            HStack(spacing: 0) {
                glyphOrPlaceholder

                if let label {
                    V6CenterLabelView(text: label)
                        .padding(.leading, Self.innerGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: Self.innerGap)

                rightSlotView
            }
            .padding(.horizontal, pad)
        }
        .frame(width: width, height: height)
        .animation(pillLayoutAnimation, value: pillLayoutKey)
    }

    // MARK: MacBook (notch-lane label opt-in)

    private var macbookBody: some View {
        let outer = V6ClosedPill.macbookOuterWidth(
            label: label,
            physicalNotchWidth: physicalNotchWidth,
            height: height
        )

        return ZStack {
            flightDeckBackground

            HStack(spacing: 0) {
                glyphOrPlaceholder

                if let label {
                    V6NotchLaneLabelView(text: label, maxWidth: V6ClosedPill.notchLaneLabelMaxWidth)
                        .padding(.leading, Self.notchLaneLabelGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: 0)

                rightSlotView
            }
            .padding(.horizontal, pad)
        }
        .frame(width: outer, height: height)
        .animation(pillLayoutAnimation, value: pillLayoutKey)
    }

    // MARK: Layout transition

    private var pillLayoutAnimation: Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: 0.45)
    }

    private var pillLayoutKey: AnyHashable {
        AnyHashable([
            AnyHashable(label ?? ""),
            AnyHashable(rightSlot.map(FlightDeckRightSlotKey.init) ?? .none),
            AnyHashable(mode),
        ])
    }
}

private enum FlightDeckRightSlotKey: Hashable {
    case none
    case count(Int)
    case agents(Int)
    case attention(Int, IslandAttentionKind)
    case tasks(Int, Int, Int)
    case usage(Int, String, String)

    init(_ content: IslandRightSlotContent) {
        switch content {
        case .count(let n):   self = .count(n)
        case .agents(let cs): self = .agents(cs.count)
        case .attentionCount(let count, let kind):
            self = .attention(count, kind)
        case .taskCounter(let completed, let total, let subagents):
            self = .tasks(completed, total, subagents)
        case .usage(let percent, let window, let provider):
            self = .usage(percent, window, provider)
        }
    }
}

// MARK: - Grid geometry

/// Flight Deck's closed-island agents-grid geometry. It reuses Classic's
/// balanced matrix and cell/gap sizing verbatim — so the pill's outer width math
/// is unchanged and the morph frame stays identical — but squares the lamp
/// corners (`radius = 0`) so the cells read as annunciator lights. Because the
/// corner radius deviates from Classic, this is the theme's own geometry
/// strategy, pinned by `FlightDeckThemeTests` rather than Classic's
/// `AgentsGridLayoutTests`.
enum FlightDeckAgentsGrid {
    static func balancedRows(_ n: Int) -> [Int] {
        V6RightSlotView.balancedRows(n)
    }

    static func cellGeometry(rowCount: Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat) {
        let base = V6RightSlotView.cellGeometry(rowCount: rowCount)
        return (cell: base.cell, gap: base.gap, radius: 0)
    }
}

// MARK: - Right slot

/// Flight Deck's closed-pill right slot: the mono "×N" count badge, or the
/// square-annunciator-light agents grid. Mirrors `V6RightSlotView`'s API (and
/// its accessibility summary), differing only in the lamp styling.
struct FlightDeckRightSlotView: View {
    let content: IslandRightSlotContent
    var lang: LanguageManager = .shared
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch content {
        case .count, .attentionCount, .taskCounter, .usage:
            // AB-322: the attention / task-counter / usage kinds degrade to this
            // theme's existing count badge until its own redesign ticket gives
            // them a rendering. Spelled out rather than `default:` so a future
            // case breaks the build here instead of quietly becoming a number.
            countBadge
        case .agents(let cells):
            FlightDeckAgentsGridBody(cells: cells)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(V6RightSlotView.agentsGridAccessibilitySummary(for: cells, lang: lang))
        }
    }

    private var countBadge: some View {
        Text("×\(content.fallbackBadgeCount ?? 0)")
            .font(FlightDeckTypography.count)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tokens.colors.paper.opacity(0.72))
            .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
    }
}

/// Square-annunciator-light restyle of the closed-island agents grid. The matrix
/// shape comes from the active theme's grid strategy — Flight Deck's own, above
/// — and each tile renders as a lamp seated in a hairline housing.
private struct FlightDeckAgentsGridBody: View {
    let cells: [AgentGridCell]

    @Environment(\.islandTheme) private var theme

    var body: some View {
        let geometry = theme.agentsGridGeometry
        let rowSizes = geometry.balancedRows(cells.count)
        let geom = geometry.cellGeometry(rowSizes.count)
        let rows = V6RightSlotView.splitIntoRows(cells, rowSizes: rowSizes)

        VStack(spacing: geom.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: geom.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        FlightDeckAnnunciatorLight(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

/// One annunciator light. Every lamp is seated in a hairline bezel housing — the
/// grid-of-bezels is the panel's signature — and lit by a **semantic** status
/// colour keyed off the cell's state, never the agent's brand colour, so the
/// amber caution / nominal green hierarchy always wins and agent identity stays
/// the neutral square mark:
///
/// * running → cyan-green nominal, fully lit;
/// * idle → the lamp sits dark in its housing;
/// * waiting → amber caution, flashing (static-lit under Reduce Motion);
/// * overflow → a fitted "+N" roll-up.
private struct FlightDeckAnnunciatorLight: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat
    @Environment(\.islandTokens) private var tokens

    /// The hairline lamp housing drawn around (and beneath) every light, so the
    /// grid reads as bezelled hardware rather than loose ticks.
    private var housing: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                // AB-335: the lamp-housing bezel is the named FD hairline tier-2
                // (`#9AB0BC` @ 0.26), replacing the shipped inline
                // `hairlineOpacity * 2` paper wash.
                FlightDeckSurfaces.hairline2,
                lineWidth: 1
            )
    }

    var body: some View {
        switch cell {
        case .session(_, let state):
            switch state {
            case .running:
                // AB-336: a working agent's lamp is self-lit phosphor now — it
                // breathes at 2.0s and blooms a nominal-green halo outside its
                // silhouette (was a flat, glow-free fill). Brand colour is still
                // intentionally dropped for the semantic status colour.
                FlightDeckRunningLight(
                    color: tokens.colors.statusRunning,
                    size: size,
                    radius: radius,
                    housing: AnyView(housing)
                )
            case .idle:
                // The lamp is off: a dark core seated in its housing.
                lamp(fill: tokens.colors.statusIdle.opacity(0.5))
            case .waiting:
                FlightDeckWaitingLight(
                    color: tokens.colors.statusWaitingAggregate,
                    size: size,
                    radius: radius,
                    housing: AnyView(housing)
                )
            }
        case .overflow(let n):
            // The "+N" roll-up is a fitted micro-indicator sized to the lamp, not
            // a readable typography role, so it is exempt from the ≥10pt floor
            // (the same exemption the aggregate accessibility summary relies on).
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tokens.colors.paper.opacity(0.16))
                housing
                Text("+\(n)")
                    .font(.system(size: max(5, size * 0.55), weight: .bold, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper)
            }
            .frame(width: size, height: size)
        }
    }

    private func lamp(fill: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
            housing
        }
        .frame(width: size, height: size)
    }
}

/// A running agent's annunciator light (AB-336): a self-lit nominal-green lamp
/// that **breathes** — opacity `0.86 → 1.0` with a phosphor halo swelling
/// `5 → 11pt` outside its silhouette, once per `FlightDeckMotion.Breathe.period`
/// (2.0s), ease-in-out. Motion is a single `@State` toggle driven `repeatForever`
/// (the `FlightDeckWaitingLight` / `PouredPillGlow` precedent); under Reduce
/// Motion no animation is started and the lamp holds its **lit peak** (full
/// opacity + fully-bloomed halo) so it never even acquires a clock.
private struct FlightDeckRunningLight: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    let housing: AnyView

    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `true` (peak) whenever Reduce Motion holds the lamp steady-lit, otherwise
    /// the animated toggle drives it between trough and peak.
    private var lit: Bool { reduceMotion || breathing }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(color)
                .opacity(lit ? FlightDeckMotion.Breathe.opacityMax : FlightDeckMotion.Breathe.opacityMin)
                // The phosphor halo bleeds outside the lamp (BRIEF §7); the shape
                // matches the lamp fill so the light sits exactly under it.
                .phosphorGlow(
                    shape: RoundedRectangle(cornerRadius: radius, style: .continuous),
                    tint: color,
                    radius: lit ? FlightDeckMotion.Breathe.glowRadiusMax : FlightDeckMotion.Breathe.glowRadiusMin,
                    intensity: lit ? 0.7 : 0.5
                )
            housing
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: FlightDeckMotion.Breathe.period / 2).repeatForever(autoreverses: true)
            ) {
                breathing = true
            }
        }
    }
}

/// A waiting agent's annunciator light (AB-336): an amber caution lamp that now
/// carries a phosphor halo and pulses on the caution attention cadence
/// (`FlightDeckMotion.Attention.cautionPeriod`, 1.2s) so it reads as a lit
/// alarm, distinct from the running lamp's calmer breathe. Under Reduce Motion
/// it holds its lit peak (never dark), still distinct from an idle (dark) lamp.
private struct FlightDeckWaitingLight: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    let housing: AnyView
    @State private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lit: Bool { reduceMotion || blink }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(color)
                .opacity(lit ? FlightDeckMotion.Attention.opacityMax : FlightDeckMotion.Attention.opacityMin)
                .phosphorGlow(
                    shape: RoundedRectangle(cornerRadius: radius, style: .continuous),
                    tint: color,
                    radius: FlightDeckMotion.Breathe.glowRadiusMin,
                    intensity: lit ? 0.6 : 0.3
                )
            housing
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: FlightDeckMotion.Attention.cautionPeriod / 2).repeatForever(autoreverses: true)
            ) {
                blink = true
            }
        }
    }
}

// MARK: - Attention bloom

/// The closed pill's attention bloom (AB-336 · mockup `.attn-perm` / `.attn-caut`).
///
/// Only the two attention states bloom: a held permission (warning red) and an
/// open question (caution amber). Every other state resolves to `nil`, so the
/// pill stays flat hardware — the bloom is the pill's "exactly one loud thing".
/// The fold from the spotlight's phase/mode reuses the shared
/// `PouredPillAmbientState.resolve` (a theme-agnostic mapping despite its name)
/// so the pill picks the same frame Poured does; only the two attention frames
/// are surfaced here. The geometry constants live in `FlightDeckMotion.Bloom`.
enum FlightDeckPillBloom: Equatable {
    case permission
    case question

    static func resolve(
        activity: IslandClosedPillActivity?,
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?
    ) -> FlightDeckPillBloom? {
        switch PouredPillAmbientState.resolve(activity: activity, mode: mode, rightSlot: rightSlot) {
        case .permission: return .permission
        case .question:   return .question
        case .idle, .working, .completed: return nil
        }
    }

    /// The semantic status tint — warning red for a permission, caution amber for
    /// a question (the same tokens the row lanes and beacons resolve to).
    func tint(_ colors: IslandColorTokens) -> Color {
        switch self {
        case .permission: return colors.statusWaitingForApproval
        case .question:   return colors.statusWaitingForAnswer
        }
    }

    var borderOpacity: Double {
        self == .permission
            ? FlightDeckMotion.Bloom.permissionBorderOpacity
            : FlightDeckMotion.Bloom.questionBorderOpacity
    }

    var glowRadius: CGFloat {
        self == .permission
            ? FlightDeckMotion.Bloom.permissionRadius
            : FlightDeckMotion.Bloom.questionRadius
    }

    var glowOpacity: Double {
        self == .permission
            ? FlightDeckMotion.Bloom.permissionGlowOpacity
            : FlightDeckMotion.Bloom.questionGlowOpacity
    }

    /// The pulse cadence — the faster warning period for a permission, the calmer
    /// caution period for a question.
    var period: Double {
        self == .permission
            ? FlightDeckMotion.Attention.warningPeriod
            : FlightDeckMotion.Attention.cautionPeriod
    }
}

/// The closed-pill attention-bloom **seam** (AB-336, the AB-330 seam pattern).
///
/// `IslandPanelView` mounts this *behind* the closed surface and OUTSIDE the
/// notch morph's content clip, so its coloured `.shadow` bleeds past the pill
/// silhouette instead of being truncated at it. It draws the pill shape filled
/// with `surfaceInk` — occluded by the real pill drawn on top — so only the
/// bloom shows. The overlay window already reserves headroom via the theme's
/// closed-shadow insets / the larger opened reservation, which comfortably
/// contains this tight bloom (mockup effective radius ≤ 12pt).
struct FlightDeckClosedGlow: View {
    let bloom: FlightDeckPillBloom
    let width: CGFloat
    let height: CGFloat

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        V6ClosedPillShape()
            .fill(tokens.colors.surfaceInk)
            .frame(width: width, height: height)
            .modifier(FlightDeckPillBloomGlow(bloom: bloom))
            .allowsHitTesting(false)
    }
}

/// The bloom's colored drop-glow. SwiftUI `.shadow` has no spread, so the
/// mockup's negative-spread shadow is approximated as a tight radius
/// (`FlightDeckMotion.Bloom`) with the mockup's `6pt` down-offset. It pulses on
/// the `attn` cadence via a single `@State` toggle (`PouredPillGlow` precedent);
/// Reduce Motion never starts it and the glow holds its lit peak (§K).
private struct FlightDeckPillBloomGlow: ViewModifier {
    let bloom: FlightDeckPillBloom

    @Environment(\.islandTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    /// `true` at the pulse peak; held `true` (peak) under Reduce Motion.
    private var lit: Bool { reduceMotion || breathing }

    func body(content: Content) -> some View {
        let tint = bloom.tint(tokens.colors)
        let troughFactor = FlightDeckMotion.Attention.opacityMin / FlightDeckMotion.Attention.opacityMax
        let opacity = lit ? bloom.glowOpacity : bloom.glowOpacity * troughFactor
        return content
            .shadow(
                color: tint.opacity(opacity),
                radius: bloom.glowRadius,
                x: 0,
                y: FlightDeckMotion.Bloom.yOffset
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: bloom.period / 2).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}
