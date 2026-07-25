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

    init(_ content: IslandRightSlotContent) {
        switch content {
        case .count(let n):   self = .count(n)
        case .agents(let cs): self = .agents(cs.count)
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
        case .count(let n):
            Text("×\(n)")
                .font(FlightDeckTypography.count)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(tokens.colors.paper.opacity(0.72))
                .accessibilityLabel(lang.t("a11y.agentsGrid.countBadge", n))
        case .agents(let cells):
            FlightDeckAgentsGridBody(cells: cells)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(V6RightSlotView.agentsGridAccessibilitySummary(for: cells, lang: lang))
        }
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
                tokens.colors.paper.opacity(tokens.colors.hairlineOpacity * 2),
                lineWidth: 1
            )
    }

    var body: some View {
        switch cell {
        case .session(_, let state):
            switch state {
            case .running:
                // A working agent lights its lamp full cyan-green nominal — flat,
                // no glow. Brand colour is intentionally dropped for the semantic
                // status colour.
                lamp(fill: tokens.colors.statusRunning)
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

/// A waiting agent's annunciator light: an amber lamp that flashes its opacity
/// with motion enabled, and holds a fixed mid-opacity under Reduce Motion so it
/// still reads as distinct from an idle (dark) or running (steady-lit) lamp
/// without animating.
private struct FlightDeckWaitingLight: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    let housing: AnyView
    @State private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(color)
                .opacity(reduceMotion ? 0.7 : (blink ? 1.0 : 0.3))
            housing
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                blink = true
            }
        }
    }
}
