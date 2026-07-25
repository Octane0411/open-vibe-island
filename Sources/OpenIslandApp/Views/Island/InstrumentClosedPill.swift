import SwiftUI
import OpenIslandCore

/// Instrument theme's closed-pill slot (AB-307).
///
/// The instrument look is a flat monospace readout, so the pill drops the glass
/// treatment entirely: a squared `surfaceInk` body outlined by a single hairline
/// rule, the idle mode glyph, mono labels, and the agents grid rendered as flat
/// *square status ticks* (sharp corners, no glow). Colour is spent only on
/// status — running ticks light full colour, idle ticks dim into the ground,
/// waiting ticks blink, and an overflow tick reads "+N".
///
/// Layout (glyph, centre label, notch-lane label, right slot) and the
/// fluid-width math are shared verbatim with `V6ClosedPill` — the same statics
/// `PouredClosedPill` reuses — so the pill's outer dimensions, and therefore the
/// closed↔opened morph frame in `IslandPanelView`, stay identical across themes.
/// Only the fill treatment and the tick styling differ. The centre / notch-lane
/// labels are already `.monospaced`, so reusing them keeps the widths pinned and
/// the "labels in mono" requirement met for free.
struct InstrumentClosedPill: View {
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

    var body: some View {
        switch layout {
        case .external: externalBody
        case .macbook:  macbookBody
        }
    }

    // MARK: Background

    /// Flat instrument body: a solid `surfaceInk` fill outlined by a single
    /// hairline rule at the theme's hairline opacity — the same hairline
    /// vocabulary the panel chrome uses, so the closed and opened states read as
    /// one instrument. No vibrancy, no specular; nothing to drop under Reduce
    /// Transparency because there is no transparency to reduce.
    private var instrumentBackground: some View {
        V6ClosedPillShape()
            .fill(tokens.colors.surfaceInk)
            .overlay(
                V6ClosedPillShape()
                    .stroke(
                        tokens.colors.paper.opacity(tokens.colors.hairlineOpacity),
                        lineWidth: 1
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
            InstrumentRightSlotView(content: rightSlot)
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
            instrumentBackground

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
            instrumentBackground

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
            AnyHashable(rightSlot.map(InstrumentRightSlotKey.init) ?? .none),
            AnyHashable(mode),
        ])
    }
}

private enum InstrumentRightSlotKey: Hashable {
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

/// Instrument's closed-island agents-grid geometry. It reuses Classic's balanced
/// matrix and cell/gap sizing verbatim — so the pill's outer width math is
/// unchanged and the morph frame stays identical — but squares the tick corners
/// (`radius = 0`) to match the instrument silhouette. Because the corner radius
/// deviates from Classic, this is the theme's own geometry strategy, pinned by
/// `InstrumentThemeTests` rather than Classic's `AgentsGridLayoutTests`.
enum InstrumentAgentsGrid {
    static func balancedRows(_ n: Int) -> [Int] {
        V6RightSlotView.balancedRows(n)
    }

    static func cellGeometry(rowCount: Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat) {
        let base = V6RightSlotView.cellGeometry(rowCount: rowCount)
        return (cell: base.cell, gap: base.gap, radius: 0)
    }
}

// MARK: - Right slot

/// Instrument's closed-pill right slot: the mono "×N" count badge, or the
/// square-tick agents grid. Mirrors `V6RightSlotView`'s API (and its
/// accessibility summary), differing only in the tick styling.
struct InstrumentRightSlotView: View {
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
            InstrumentAgentsGridBody(cells: cells)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(V6RightSlotView.agentsGridAccessibilitySummary(for: cells, lang: lang))
        }
    }

    private var countBadge: some View {
        Text("×\(content.fallbackBadgeCount ?? 0)")
            .font(InstrumentTypography.count)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tokens.colors.paper.opacity(0.72))
            .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
    }
}

/// Square-tick restyle of the closed-island agents grid. The matrix shape comes
/// from the active theme's grid strategy — Instrument's own, above — and each
/// tile renders as a flat square status tick.
private struct InstrumentAgentsGridBody: View {
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
                        InstrumentAgentsTickView(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

private struct InstrumentAgentsTickView: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch cell {
        case .session(let color, let state):
            switch state {
            case .running:
                // A working agent lights its tick full colour — flat, no glow.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
            case .idle:
                // Dimmed into the console ground.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color.opacity(0.24))
                    .frame(width: size, height: size)
            case .waiting:
                InstrumentWaitingTick(color: color, size: size, radius: radius)
            }
        case .overflow(let n):
            // The "+N" roll-up is a fitted micro-indicator sized to the tick, not
            // a readable typography role, so it is exempt from the ≥10pt floor
            // (the same exemption the aggregate accessibility summary relies on).
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tokens.colors.paper.opacity(0.16))
                Text("+\(n)")
                    .font(.system(size: max(5, size * 0.55), weight: .bold, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper)
            }
            .frame(width: size, height: size)
        }
    }
}

/// A waiting agent's tick: a flat square that blinks its opacity with motion
/// enabled, and holds a fixed mid-opacity under Reduce Motion so it still reads
/// as distinct from idle/running without animating.
private struct InstrumentWaitingTick: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    @State private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .opacity(reduceMotion ? 0.7 : (blink ? 1.0 : 0.3))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    blink = true
                }
            }
    }
}
