import SwiftUI
import OpenIslandCore

/// Annual theme's closed-pill slot (AB-315).
///
/// The Annual look is a quiet editorial page, so the pill drops every chip and
/// capsule: a solid `surfaceInk` body outlined by a single 1px hairline bezel
/// (the theme's structural device), the idle mode glyph, a **quiet lowercase**
/// mono label, and the agents grid rendered as **6px square brand marks** rather
/// than capsule tiles. The dot grammar is spent by *state*: a running mark is the
/// agent's full brand colour, an idle mark dims that same brand colour, and a
/// waiting mark drops the brand entirely for the theme's one orange-red accent,
/// pulsing — accent is reserved for attention, so a calm grid (only running /
/// idle marks) carries zero accent pixels apart from the brand squares
/// themselves. Overflow rolls up to a neutral "+N".
///
/// Layout (glyph, centre label, notch-lane label, right slot) and the fluid-width
/// math are shared verbatim with `V6ClosedPill` — the same statics
/// `FlightDeckClosedPill` / `InstrumentClosedPill` reuse — so the pill's outer
/// dimensions, and therefore the closed↔opened morph frame in `IslandPanelView`,
/// stay identical across themes. The label is pre-lowercased per-character (Latin
/// only; Han is uncased and passes through), which cannot change a monospaced
/// width, so the shared `V6CenterLabelView` / `V6NotchLaneLabelView` renderers —
/// already mono — are reused unchanged and the "quiet lowercase mono" requirement
/// is met without a bespoke label view or any width drift.
struct AnnualClosedPill: View {
    var mode: UnifiedBars.Mode
    var label: String?
    var rightSlot: IslandRightSlotContent?
    var layout: V6ClosedLayout
    var height: CGFloat = 32
    var physicalNotchWidth: CGFloat = 0
    var minWidth: CGFloat = 70
    var showsGlyph: Bool = true

    @Environment(\.islandTokens) private var tokens

    private static let glyphSize: CGFloat = 24
    private static let innerGap: CGFloat = 6
    private static let notchLaneLabelGap: CGFloat = 6

    private var pad: CGFloat { height / 2 }

    /// The label lowercased for the editorial treatment. `String.lowercased()`
    /// only maps cased characters, so Latin is quieted and CJK renders naturally;
    /// in a monospaced font the case change never alters the glyph advance, so the
    /// shared width math and the closed↔opened morph frame are unaffected.
    private var displayLabel: String? { label?.lowercased() }

    var body: some View {
        switch layout {
        case .external: externalBody
        case .macbook:  macbookBody
        }
    }

    // MARK: Background

    /// Flat editorial body: a solid `surfaceInk` fill outlined by a single 1px
    /// hairline bezel at the theme's hairline opacity — the same hairline
    /// vocabulary the panel chrome uses, so the closed and opened states read as
    /// one quiet page. No vibrancy, no specular; nothing to drop under Reduce
    /// Transparency because there is no transparency to reduce.
    private var annualBackground: some View {
        V6ClosedPillShape()
            .fill(tokens.colors.surfaceInk)
            .overlay(
                V6ClosedPillShape()
                    .stroke(
                        tokens.colors.paper.opacity(tokens.colors.hairlineOpacity),
                        lineWidth: AnnualHairline.hairline
                    )
                    .allowsHitTesting(false)
            )
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
            AnnualRightSlotView(content: rightSlot)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    // MARK: External (fluid)

    private var externalBody: some View {
        let width = V6ClosedPill.externalOuterWidth(
            label: displayLabel,
            rightSlot: rightSlot,
            minWidth: minWidth,
            height: height
        )

        return ZStack {
            annualBackground

            HStack(spacing: 0) {
                glyphOrPlaceholder

                if let displayLabel {
                    V6CenterLabelView(text: displayLabel)
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
            label: displayLabel,
            physicalNotchWidth: physicalNotchWidth,
            height: height
        )

        return ZStack {
            annualBackground

            HStack(spacing: 0) {
                glyphOrPlaceholder

                if let displayLabel {
                    V6NotchLaneLabelView(text: displayLabel, maxWidth: V6ClosedPill.notchLaneLabelMaxWidth)
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
            AnyHashable(displayLabel ?? ""),
            AnyHashable(rightSlot.map(AnnualRightSlotKey.init) ?? .none),
            AnyHashable(mode),
        ])
    }
}

private enum AnnualRightSlotKey: Hashable {
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

/// Annual's closed-island agents-grid geometry. It reuses Classic's balanced
/// matrix and cell/gap sizing verbatim — so the pill's outer width math is
/// unchanged and the morph frame stays identical — but squares the marks'
/// corners (`radius = 0`) so the cells read as the design's 6px brand squares
/// rather than rounded tiles or capsules. Because the corner radius deviates from
/// Classic, this is the theme's own geometry strategy, pinned by
/// `AnnualThemeTests` rather than Classic's `AgentsGridLayoutTests`.
enum AnnualAgentsGrid {
    static func balancedRows(_ n: Int) -> [Int] {
        V6RightSlotView.balancedRows(n)
    }

    static func cellGeometry(rowCount: Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat) {
        let base = V6RightSlotView.cellGeometry(rowCount: rowCount)
        return (cell: base.cell, gap: base.gap, radius: 0)
    }
}

// MARK: - Right slot

/// Annual's closed-pill right slot: the quiet lowercase-mono "×N" count badge, or
/// the square-brand-mark agents grid. Mirrors `V6RightSlotView`'s API (and its
/// accessibility summary), differing only in the mark styling and the calmer
/// count typography.
struct AnnualRightSlotView: View {
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
            AnnualAgentsGridBody(cells: cells)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(V6RightSlotView.agentsGridAccessibilitySummary(for: cells, lang: lang))
        }
    }

    private var countBadge: some View {
        Text("×\(content.fallbackBadgeCount ?? 0)")
            .font(AnnualTypography.count)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tokens.colors.paper.opacity(0.72))
            .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
    }
}

/// Square-brand-mark restyle of the closed-island agents grid. The matrix shape
/// comes from the active theme's grid strategy — Annual's own, above — and each
/// cell renders as a 6px brand square, never a capsule.
private struct AnnualAgentsGridBody: View {
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
                        AnnualAgentMark(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

/// One agent brand mark — a flat square, no housing, no capsule. The dot grammar
/// is spent by state, and the accent is disciplined to attention only:
///
/// * running → the agent's full brand colour, fully filled ("filled = running");
/// * idle → the same brand colour, dimmed ("dim = idle") — still a brand mark, so
///   it never spends the accent;
/// * waiting → the theme's one orange-red accent, pulsing ("pulsing accent =
///   attention"), static under Reduce Motion — the *only* mark that leaves the
///   brand palette, and only because it is an attention state;
/// * overflow → a neutral "+N" roll-up in dimmed ink, no accent.
private struct AnnualAgentMark: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch cell {
        case .session(let color, let state):
            switch state {
            case .running:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
            case .idle:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color.opacity(0.3))
                    .frame(width: size, height: size)
            case .waiting:
                // Attention: the one accent, never the brand colour. `annualAccent`
                // is exactly the value `statusWaitingAggregate` resolves to, kept
                // in one place so the accent-discipline pin has a single source.
                AnnualWaitingMark(
                    color: tokens.colors.statusWaitingAggregate,
                    size: size,
                    radius: radius
                )
            }
        case .overflow(let n):
            // The "+N" roll-up is a fitted micro-indicator sized to the mark, not
            // a readable typography role, so it is exempt from the type floor (the
            // same exemption the aggregate accessibility summary relies on).
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tokens.colors.paper.opacity(0.14))
                Text("+\(n)")
                    .font(.system(size: max(5, size * 0.55), weight: .bold, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper)
            }
            .frame(width: size, height: size)
        }
    }
}

/// A waiting agent's brand mark: the accent square pulsing its opacity with
/// motion enabled, holding a fixed mid-opacity under Reduce Motion so it still
/// reads as distinct from a dim idle mark or a solid running one without
/// animating.
private struct AnnualWaitingMark: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fixed opacity in place of the pulse under Reduce Motion — roughly its
    /// midpoint, so a waiting mark still reads as distinct from a dim idle (0.3)
    /// or a solid running (1.0) mark, just without motion.
    private static let reducedMotionOpacity: Double = 0.7

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .opacity(reduceMotion ? Self.reducedMotionOpacity : (pulse ? 1.0 : 0.35))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
