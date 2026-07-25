import SwiftUI
import OpenIslandCore

/// Per-cell state for the closed-island agents grid. Drives tile rendering:
/// running = full color, idle = dim, waiting = opacity pulse.
enum AgentGridCellState: Equatable {
    case running
    case idle
    case waiting
}

/// One cell in the closed-island agents grid. `.session` carries the agent
/// tool's brand color and its current state. `.overflow` is a single trailing
/// cell shown when there are more sessions than the grid can display.
enum AgentGridCell: Equatable {
    case session(color: Color, state: AgentGridCellState)
    case overflow(Int)
}

/// Concrete payload for the closed island's right slot. The `AppModel`
/// computes one of these from live session state — the first three cases are
/// derived from what the agents are actually doing and outrank the user's
/// `islandRightSlot` preference, the last two *are* that preference
/// (`IslandRightSlotResolver` owns the ladder). The view side is agnostic to
/// which rule produced it.
enum IslandRightSlotContent: Equatable {
    case count(Int)              // "×N" badge
    case agents([AgentGridCell]) // balanced grid, one tile per session

    /// AB-322: how many sessions are blocked on the user, and on what.
    /// `count` is sessions, never queued requests.
    case attentionCount(count: Int, kind: IslandAttentionKind)

    /// AB-322: the spotlight session's todo progress (`⏲ 2/5`) and subagent
    /// fan-out. `subagents` is 0 when the session isn't fanning out.
    case taskCounter(completed: Int, total: Int, subagents: Int)

    /// AB-322: the worst rate-limit window once it turns critical
    /// (`IslandRightSlotResolver.usageAlertThreshold`). `percent` is already
    /// rounded for display.
    case usage(percent: Int, windowLabel: String, providerTitle: String)
}

extension IslandRightSlotContent {
    /// The number a themed "×N" count badge shows for this content.
    ///
    /// AB-322 adds three content kinds but only their *selection*; the themed
    /// visuals (attention pill, `⏲ 2/5` chip, usage dial/tape) land with each
    /// theme's own ticket. Until then every theme degrades the new kinds to the
    /// count badge it already draws, and this is the value it renders — never a
    /// blank slot. `nil` for `.agents`, which has its own grid rendering.
    var fallbackBadgeCount: Int? {
        switch self {
        case .count(let n):
            return n
        case .agents:
            return nil
        case .attentionCount(let count, _):
            return count
        case .taskCounter(_, let total, let subagents):
            // The todo list is the headline; a pure fan-out falls back to the
            // number of subagents so the badge is never a bare "×0".
            return total > 0 ? total : subagents
        case .usage(let percent, _, _):
            return percent
        }
    }

    /// VoiceOver text for the degraded count-badge rendering. Each kind says
    /// what it actually is — a stack of unexplained numbers would be worse than
    /// the shipped "N sessions".
    func fallbackBadgeAccessibilityLabel(_ lang: LanguageManager) -> String {
        switch self {
        case .count(let n):
            return lang.t("a11y.agentsGrid.countBadge", n)
        case .agents(let cells):
            return V6RightSlotView.agentsGridAccessibilitySummary(for: cells, lang: lang)
        case .attentionCount(let count, let kind):
            switch kind {
            case .permission: return lang.t("a11y.rightSlot.attention.permission", count)
            case .question:   return lang.t("a11y.rightSlot.attention.question", count)
            }
        case .taskCounter(let completed, let total, let subagents):
            if total > 0 {
                return lang.t("a11y.rightSlot.tasks", completed, total)
            }
            return lang.t("a11y.rightSlot.subagents", subagents)
        case .usage(let percent, let windowLabel, let providerTitle):
            return lang.t("a11y.rightSlot.usage", providerTitle, windowLabel, percent)
        }
    }
}

// MARK: - Right-slot renderers

struct V6RightSlotView: View {
    let content: IslandRightSlotContent
    var lang: LanguageManager = .shared
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch content {
        case .count, .attentionCount, .taskCounter, .usage:
            // AB-322: the three new kinds degrade to Classic's count badge until
            // their themed renderings land. Listed explicitly — no `default:` —
            // so a future case fails the build here instead of silently
            // rendering as a number.
            countBadge
        case .agents(let cells):
            AgentsGridBody(cells: cells)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.agentsGridAccessibilitySummary(for: cells, lang: lang))
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

    /// AB-244: the closed-island agents grid packs each session into a tiny
    /// colored square with no text of its own — individually exposing each
    /// tile would be a wall of unlabeled shapes to VoiceOver. Collapsed into
    /// one aggregate label ("2 running, 1 waiting for input") instead, the
    /// same "grouped summary" shape used for session rows.
    static func agentsGridAccessibilitySummary(for cells: [AgentGridCell], lang: LanguageManager) -> String {
        var running = 0
        var waiting = 0
        var idle = 0
        var overflow = 0
        for cell in cells {
            switch cell {
            case .session(_, .running): running += 1
            case .session(_, .waiting): waiting += 1
            case .session(_, .idle): idle += 1
            case .overflow(let n): overflow += n
            }
        }

        var parts: [String] = []
        if running > 0 { parts.append(lang.t("a11y.agentsGrid.running", running)) }
        if waiting > 0 { parts.append(lang.t("a11y.agentsGrid.waiting", waiting)) }
        if idle > 0 { parts.append(lang.t("a11y.agentsGrid.idle", idle)) }
        if overflow > 0 { parts.append(lang.t("a11y.agentsGrid.more", overflow)) }
        return parts.joined(separator: ", ")
    }

    /// Intrinsic width used by the fluid-layout math. Values are slightly
    /// padded beyond the raw text measurement so the pill always reserves
    /// enough room for the `.fixedSize()` content to render on one line,
    /// without HStack compression forcing a wrap.
    static func intrinsicWidth(of content: IslandRightSlotContent) -> CGFloat {
        switch content {
        case .count, .attentionCount, .taskCounter, .usage:
            // All four render as the "×N" badge today, so they share its width
            // math — the pill reserves room for the number it will actually draw.
            return countBadgeWidth(content.fallbackBadgeCount ?? 0)
        case .agents(let cells):
            let n = cells.count
            guard n > 0 else { return 0 }
            let rows = balancedRows(n)
            let maxRow = rows.max() ?? 0
            let geom = cellGeometry(rowCount: rows.count)
            return CGFloat(maxRow) * geom.cell + CGFloat(max(0, maxRow - 1)) * geom.gap
        }
    }

    /// Width of the "×N" badge for an N-digit number.
    static func countBadgeWidth(_ n: Int) -> CGFloat {
        let digits = Double(max(1, String(n).count))
        // "×" + digits at 11pt mono ≈ 7.2pt/char.
        return CGFloat(14.4 + max(0.0, digits - 1.0) * 7.2)
    }

    // MARK: Balanced layout algorithm
    //
    // For each n from 1 to 9, we hand-tune the per-row cell counts so the
    // matrix reads as a deliberate shape instead of a wrap-at-4-columns grid.
    // For n >= 10 the AppModel caps the list at 7 sessions + 1 overflow cell,
    // which lays out as [4,4] — so balancedRows(8) is what actually renders
    // for all high-count cases in production.
    static func balancedRows(_ n: Int) -> [Int] {
        switch n {
        case ..<1: return []
        case 1: return [1]
        case 2: return [2]
        case 3: return [3]
        case 4: return [2, 2]
        case 5: return [3, 2]
        case 6: return [3, 3]
        case 7: return [4, 3]
        case 8: return [4, 4]
        case 9: return [3, 3, 3]
        default: return [4, 4]
        }
    }

    /// Cell size shrinks when the matrix has 3 rows so total height still
    /// fits inside the pill's internal vertical budget (~20pt).
    static func cellGeometry(rowCount: Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat) {
        if rowCount >= 3 { return (cell: 6, gap: 1.5, radius: 1.0) }
        return (cell: 8, gap: 2, radius: 1.5)
    }

    static func splitIntoRows(_ cells: [AgentGridCell], rowSizes: [Int]) -> [[AgentGridCell]] {
        var out: [[AgentGridCell]] = []
        var idx = 0
        for size in rowSizes {
            let end = min(idx + size, cells.count)
            out.append(Array(cells[idx..<end]))
            idx = end
            if idx >= cells.count { break }
        }
        return out
    }
}

// MARK: - Agents grid body

/// V1a Dense Grid renderer. 2D matrix of 8×8 rounded squares (6×6 when 3 rows),
/// each row horizontally centered around the widest row. Running = full color,
/// idle = 22% alpha, waiting = opacity 0.35 ↔ 1 breathing pulse.
private struct AgentsGridBody: View {
    let cells: [AgentGridCell]

    /// AB-299: the matrix shape comes from the active theme's grid strategy.
    /// Classic delegates straight back to the `V6RightSlotView` statics (which
    /// stay the single implementation the width math and `AgentsGridLayoutTests`
    /// share), so its layout is unchanged.
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
                        AgentsGridTileView(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

private struct AgentsGridTileView: View {
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
                    .fill(color.opacity(0.22))
                    .frame(width: size, height: size)
            case .waiting:
                AgentsGridWaitingTile(color: color, size: size, radius: radius)
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

private struct AgentsGridWaitingTile: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// AB-244: fixed opacity used in place of the 0.35↔1.0 breathing pulse
    /// when Reduce Motion is on — roughly the pulse's midpoint, so a
    /// waiting tile still reads as visually distinct from a fully dim idle
    /// tile (0.22) or a fully solid running one (1.0), just without motion.
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

// MARK: - Center label renderer

struct V6CenterLabelView: View {
    let text: String
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tokens.colors.paper)
    }

    static func intrinsicWidth(of text: String) -> CGFloat {
        CGFloat(Double(text.count) * 7.3 + 10)
    }
}

// MARK: - Notch-lane label renderer (AB-241)

/// Beside-the-cutout activity text for notched Macs. Unlike
/// `V6CenterLabelView` (external displays, where the whole pill grows to
/// fit the text), this lane has a hard width cap — long text truncates
/// gracefully instead of pushing the pill past the safe zone beside the
/// physical notch.
struct V6NotchLaneLabelView: View {
    let text: String
    let maxWidth: CGFloat
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        ViewThatFits(in: .horizontal) {
            label
                .fixedSize(horizontal: true, vertical: false)
            label
                .frame(width: maxWidth, alignment: .leading)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(tokens.colors.paper)
    }

    static func intrinsicWidth(of text: String, cappedAt maxWidth: CGFloat) -> CGFloat {
        min(maxWidth, CGFloat(Double(text.count) * 6.6 + 4))
    }
}

// MARK: - Closed-pill layouts

/// The canonical v6 closed-island pill rendered inside a fixed-height frame.
/// Pure view — takes all parameters explicitly so it can be reused for the
/// live settings preview and the real island.
struct V6ClosedPill: View {
    var mode: UnifiedBars.Mode
    var label: String?          // external: centered; macbook: notch-adjacent lane (AB-241)
    var rightSlot: IslandRightSlotContent?
    var layout: V6ClosedLayout
    var height: CGFloat = 32

    /// MacBook mode only — width of the physical notch cutout to wrap.
    var physicalNotchWidth: CGFloat = 0

    /// External mode only — minimum pill width (locked). Defaults to the
    /// width that fits just the glyph.
    var minWidth: CGFloat = 70

    /// AB-243: when the notch morph owns the glyph (rendered externally, as
    /// its own overlay, so it can travel into the opened header instead of
    /// fading in place), the pill renders a transparent placeholder in the
    /// glyph's slot instead — otherwise the real glyph would be drawn twice
    /// (once here, fading with the rest of this content; once traveling to
    /// its opened position), reading as a duplicate-image glitch mid-morph.
    /// Defaults to `true` so every other caller (the settings-tab live
    /// preview, the Reduce Motion crossfade) keeps rendering its own glyph
    /// unchanged.
    var showsGlyph: Bool = true

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch layout {
        case .external: externalBody
        case .macbook:  macbookBody
        }
    }

    // Horizontal edge padding is identical left/right — canonical v6 pill
    // has r = h/2 semicircular bottoms, so edge inset = r keeps content
    // clear of the curve.
    private var pad: CGFloat { height / 2 }

    private static let glyphSize: CGFloat = 24

    // Minimum breathing room between the center label (or glyph, when no
    // label) and the right-slot content so they never touch at small widths.
    private static let innerGap: CGFloat = 6

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

    // MARK: External (fluid)

    /// Intrinsic pill width for the external/top-bar layout — shared with
    /// `IslandPanelView`'s notch-morph container (AB-243) so the closed-state
    /// target frame it animates from/to always matches this view's own
    /// layout exactly, without duplicating the math in two places.
    static func externalOuterWidth(
        label: String?,
        rightSlot: IslandRightSlotContent?,
        minWidth: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        let pad = height / 2
        let labelW = label.map { V6CenterLabelView.intrinsicWidth(of: $0) } ?? 0
        let rightW = rightSlot.map { V6RightSlotView.intrinsicWidth(of: $0) } ?? 0

        let labelBlock = (label == nil ? 0 : 6 + labelW)
        let rightBlock = (rightSlot == nil ? 0 : innerGap + rightW)
        let intrinsic = pad * 2 + glyphSize + labelBlock + rightBlock
        return max(minWidth, intrinsic)
    }

    private var externalBody: some View {
        let width = Self.externalOuterWidth(
            label: label,
            rightSlot: rightSlot,
            minWidth: minWidth,
            height: height
        )

        return ZStack {
            V6ClosedPillShape()
                .fill(tokens.colors.surfaceInk)

            HStack(spacing: 0) {
                glyphOrPlaceholder

                if let label {
                    V6CenterLabelView(text: label)
                        .padding(.leading, 6)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: Self.innerGap)

                if let rightSlot {
                    V6RightSlotView(content: rightSlot)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, pad)
        }
        .frame(width: width, height: height)
        .animation(
            .timingCurve(0.4, 0, 0.2, 1, duration: 0.45),
            value: AnyHashable([
                AnyHashable(label ?? ""),
                AnyHashable(rightSlot.map(RightSlotKey.init) ?? .none),
                AnyHashable(mode),
            ])
        )
    }

    // MARK: MacBook (outer width locked, notch-lane label opt-in — AB-241)

    /// Per-side reserve around the physical notch when no label lane is
    /// shown — the original v6 spec constant. Leaving the lane off (the
    /// default) must reproduce today's pill dimensions exactly.
    private static let macbookBaseHalfReserve: CGFloat = 44
    private static let notchLaneLabelGap: CGFloat = 6
    private static let notchLaneLabelTrailingMargin: CGFloat = 4
    /// Hard cap on the notch-lane label's width — keeps the pill's growth
    /// bounded so a very long activity string truncates (ViewThatFits)
    /// instead of pushing the pill arbitrarily wide.
    static let notchLaneLabelMaxWidth: CGFloat = 84

    /// Intrinsic outer pill width for the MacBook layout — shared with
    /// `IslandPanelView`'s notch-morph container (AB-243); see
    /// `externalOuterWidth` doc above.
    static func macbookOuterWidth(
        label: String?,
        physicalNotchWidth: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        let pad = height / 2
        let labelWidth = label.map {
            V6NotchLaneLabelView.intrinsicWidth(of: $0, cappedAt: notchLaneLabelMaxWidth)
        }

        // Left wing must fit: leading pad + glyph + (gap + label, if any) +
        // a small safety margin before the physical notch. Growing this
        // symmetrically on both sides (rather than just the left) keeps the
        // notch gap centered in the pill — the pill is one continuous shape
        // (see `V6ClosedPillShape` doc), so an asymmetric reserve would slide
        // the true physical cutout out from under where we think it is.
        let leftContentWidth = pad + glyphSize + notchLaneLabelTrailingMargin
            + (labelWidth.map { notchLaneLabelGap + $0 } ?? 0)
        let halfReserve = max(macbookBaseHalfReserve, leftContentWidth)
        return halfReserve + physicalNotchWidth + halfReserve
    }

    private var macbookBody: some View {
        let outer = Self.macbookOuterWidth(
            label: label,
            physicalNotchWidth: physicalNotchWidth,
            height: height
        )

        return ZStack {
            V6ClosedPillShape()
                .fill(tokens.colors.surfaceInk)

            HStack(spacing: 0) {
                glyphOrPlaceholder

                if let label {
                    V6NotchLaneLabelView(text: label, maxWidth: Self.notchLaneLabelMaxWidth)
                        .padding(.leading, Self.notchLaneLabelGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: 0)

                if let rightSlot {
                    V6RightSlotView(content: rightSlot)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, pad)
        }
        .frame(width: outer, height: height)
        .animation(
            .timingCurve(0.4, 0, 0.2, 1, duration: 0.45),
            value: AnyHashable([
                AnyHashable(label ?? ""),
                AnyHashable(rightSlot.map(RightSlotKey.init) ?? .none),
                AnyHashable(mode),
            ])
        )
    }
}

enum V6ClosedLayout: Equatable {
    case external
    case macbook
}

/// Identity of the right slot for the pill's layout animation — the *shape* of
/// the content, not its rendering. Two payloads that hash equal must never
/// require a re-layout.
private enum RightSlotKey: Hashable {
    case count(Int)
    case agents(Int)
    case attention(Int, IslandAttentionKind)
    case tasks(Int, Int, Int)
    case usage(Int, String, String)

    init(_ content: IslandRightSlotContent) {
        switch content {
        case .count(let n):    self = .count(n)
        case .agents(let cs):  self = .agents(cs.count)
        case .attentionCount(let count, let kind):
            self = .attention(count, kind)
        case .taskCounter(let completed, let total, let subagents):
            self = .tasks(completed, total, subagents)
        case .usage(let percent, let window, let provider):
            self = .usage(percent, window, provider)
        }
    }
}

// MARK: - Settings-tab live preview

/// Fixed-width pill that mimics the real island inside the settings-tab
/// preview stage. Parameters match what the tab exposes.
struct IslandPreviewPill: View {
    let mode: UnifiedBars.Mode
    let label: String?
    let rightSlot: IslandRightSlotContent?
    let layout: V6ClosedLayout
    let physicalNotchWidth: CGFloat
    let now: Date

    var body: some View {
        V6ClosedPill(
            mode: mode,
            label: label,
            rightSlot: rightSlot,
            layout: layout,
            physicalNotchWidth: physicalNotchWidth
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
