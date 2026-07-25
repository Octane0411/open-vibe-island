import SwiftUI
import OpenIslandCore

/// Poured Island's closed-pill slot (AB-300).
///
/// The closed state is the "black stem" the panel pours out of, so the pill
/// keeps a dark `surfaceInk` body — hierarchy is carried by light, not chrome —
/// lit by a specular top edge for the glass hint. Layout (glyph, centre label,
/// notch-lane label, right slot) and the fluid-width math are shared verbatim
/// with `V6ClosedPill` so the pill's outer dimensions — and therefore the
/// closed↔opened morph frame in `IslandPanelView` — stay identical across
/// themes; only the fill treatment and the agents-grid tiles differ.
///
/// The agents grid restyles each tile for glass: running tiles glow at full
/// luminance, idle tiles dim into the surface, and waiting tiles breathe a soft
/// glow (static under Reduce Motion). The matrix geometry itself comes from the
/// active theme's `agentsGridGeometry`, which Poured shares with Classic, so no
/// new layout vectors are introduced.
struct PouredClosedPill: View {
    var mode: UnifiedBars.Mode
    var label: String?
    var rightSlot: IslandRightSlotContent?
    var layout: V6ClosedLayout
    var height: CGFloat = 32
    var physicalNotchWidth: CGFloat = 0
    var minWidth: CGFloat = 70
    var showsGlyph: Bool = true

    @Environment(\.islandTokens) private var tokens
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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

    /// Dark stem body plus the specular top edge — the "glass treatment" on a
    /// deliberately dark surface. Under Reduce Transparency the specular is
    /// dropped and only the flat ink remains, keeping every glyph/label legible.
    private var glassBackground: some View {
        ZStack {
            V6ClosedPillShape()
                .fill(tokens.colors.surfaceInk)

            if !reduceTransparency, let specular = tokens.material.specularTopEdge {
                LinearGradient(
                    stops: [
                        .init(color: specular.color.opacity(specular.opacity * 0.7), location: 0),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: min(specular.sheenHeight, height * 0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipShape(V6ClosedPillShape())
                .allowsHitTesting(false)
            }
        }
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
            PouredRightSlotView(content: rightSlot)
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
            glassBackground

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
            glassBackground

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
            AnyHashable(rightSlot.map(PouredRightSlotKey.init) ?? .none),
            AnyHashable(mode),
        ])
    }
}

private enum PouredRightSlotKey: Hashable {
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

// MARK: - Right slot

/// Poured Island's closed-pill right slot: the "×N" count badge, or the glass
/// agents grid. Mirrors `V6RightSlotView`'s API (and its accessibility
/// summary), differing only in the tile styling for the `.agents` case.
struct PouredRightSlotView: View {
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
            PouredAgentsGridBody(cells: cells)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(V6RightSlotView.agentsGridAccessibilitySummary(for: cells, lang: lang))
        }
    }

    private var countBadge: some View {
        Text("×\(content.fallbackBadgeCount ?? 0)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tokens.colors.paper.opacity(0.72))
            .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
    }
}

/// Glass restyle of the closed-island agents grid. The matrix shape (rows,
/// cell size, gap) comes from the active theme's grid strategy — Poured shares
/// Classic's, so the layout is pinned by the same `AgentsGridLayoutTests` — and
/// only the per-tile rendering changes for the frosted surface.
private struct PouredAgentsGridBody: View {
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
                        PouredAgentsTileView(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

private struct PouredAgentsTileView: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch cell {
        case .session(let color, let state):
            switch state {
            case .running:
                // Full luminance with a soft glow so a working agent reads as
                // lit glass rather than a flat chip.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
                    .shadow(color: color.opacity(0.65), radius: 2.5)
            case .idle:
                // Dimmed into the glass.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color.opacity(0.22))
                    .frame(width: size, height: size)
            case .waiting:
                PouredWaitingTile(color: color, size: size, radius: radius)
            }
        case .overflow(let n):
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

/// A waiting agent's tile: a breathing glow that pulses the halo radius and
/// opacity with motion enabled, and holds a fixed mid-glow under Reduce Motion
/// so the tile still reads as distinct from idle/running without animating.
private struct PouredWaitingTile: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let active = reduceMotion ? true : pulse
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(active ? 0.85 : 0.3), radius: active ? 4 : 1.5)
            .opacity(reduceMotion ? 0.85 : (pulse ? 1.0 : 0.55))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
