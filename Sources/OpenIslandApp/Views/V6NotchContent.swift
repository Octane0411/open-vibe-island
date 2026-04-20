import SwiftUI
import OpenIslandCore

/// Concrete payload for the closed island's right slot. The `AppModel`
/// computes one of these from live session state according to the user's
/// `islandRightSlot` preference; the view side is agnostic to which
/// setting produced it.
enum IslandRightSlotContent: Equatable {
    case count(Int)          // "×N" badge
    case agents([Color])     // one dot per active agent (ordered)
    case time(String)        // mono time-left string
}

// MARK: - Right-slot renderers

struct V6RightSlotView: View {
    let content: IslandRightSlotContent

    var body: some View {
        switch content {
        case .count(let n):
            Text("×\(n)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(V6Palette.paper)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(V6Palette.paper.opacity(0.14))
                )
                .overlay(
                    Capsule().stroke(V6Palette.paper.opacity(0.32), lineWidth: 1)
                )
        case .agents(let colors):
            HStack(spacing: 4) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                }
            }
        case .time(let text):
            Text(text)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(0.75))
        }
    }

    /// Intrinsic width used by the fluid-layout math. Matches the padding
    /// budget inside each variant above.
    static func intrinsicWidth(of content: IslandRightSlotContent) -> CGFloat {
        switch content {
        case .count(let n):
            let digits = max(1, String(n).count)
            return CGFloat(22 + (digits - 1) * 7) // "×" + digits padding
        case .agents(let colors):
            return CGFloat(colors.count * 7 + max(0, colors.count - 1) * 4)
        case .time(let s):
            return CGFloat(s.count) * 6.5 + 4
        }
    }
}

// MARK: - Center label renderer

struct V6CenterLabelView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(V6Palette.paper)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    static func intrinsicWidth(of text: String) -> CGFloat {
        CGFloat(text.count) * 6.8 + 10
    }
}

// MARK: - Closed-pill layouts

/// The canonical v6 closed-island pill rendered inside a fixed-height frame.
/// Pure view — takes all parameters explicitly so it can be reused for the
/// live settings preview and the real island.
struct V6ClosedPill: View {
    var mode: UnifiedBars.Mode
    var label: String?          // suppressed automatically in MacBook layout
    var rightSlot: IslandRightSlotContent?
    var layout: V6ClosedLayout
    var height: CGFloat = 32

    /// MacBook mode only — width of the physical notch cutout to wrap.
    var physicalNotchWidth: CGFloat = 0

    /// External mode only — minimum pill width (locked). Defaults to the
    /// width that fits just the glyph.
    var minWidth: CGFloat = 70

    var body: some View {
        switch layout {
        case .external: externalBody
        case .macbook:  macbookBody
        }
    }

    // MARK: External (fluid)

    private var externalBody: some View {
        let padL: CGFloat = height / 2
        let padR: CGFloat = height / 2
        let glyphW: CGFloat = 24
        let labelW = label.map { V6CenterLabelView.intrinsicWidth(of: $0) } ?? 0
        let rightW = rightSlot.map { V6RightSlotView.intrinsicWidth(of: $0) } ?? 0
        let rightFullW = rightSlot == nil ? 0 : rightW + 14

        let intrinsic = padL + glyphW + (label == nil ? 0 : labelW + 6) + rightFullW + padR
        let width = max(minWidth, intrinsic)

        return ZStack(alignment: .leading) {
            V6ClosedPillShape()
                .fill(V6Palette.ink)

            HStack(spacing: 0) {
                UnifiedBars(mode: mode, size: 24)
                    .frame(width: glyphW, height: 24)
                    .padding(.leading, padL)

                if let label {
                    V6CenterLabelView(text: label)
                        .padding(.leading, 6)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: 0)

                if let rightSlot {
                    V6RightSlotView(content: rightSlot)
                        .padding(.trailing, padR)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(width: width, height: height)
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

    // MARK: MacBook (outer width locked)

    private var macbookBody: some View {
        let padL: CGFloat = height / 2
        let padR: CGFloat = height / 2
        let halfReserve: CGFloat = 44
        let outer = halfReserve + physicalNotchWidth + halfReserve

        return ZStack(alignment: .leading) {
            V6ClosedPillShape()
                .fill(V6Palette.ink)
                .frame(width: outer, height: height)

            // Left half: glyph, pinned to pill's left edge.
            UnifiedBars(mode: mode, size: 24)
                .frame(width: 24, height: 24)
                .padding(.leading, padL)

            // Right half: right-slot, pinned to pill's right edge.
            if let rightSlot {
                HStack { Spacer(minLength: 0); V6RightSlotView(content: rightSlot) }
                    .frame(width: outer, alignment: .trailing)
                    .padding(.trailing, padR)
            }
        }
        .frame(width: outer, height: height)
    }
}

enum V6ClosedLayout: Equatable {
    case external
    case macbook
}

private enum RightSlotKey: Hashable {
    case count(Int)
    case agents(Int)
    case time(String)

    init(_ content: IslandRightSlotContent) {
        switch content {
        case .count(let n):    self = .count(n)
        case .agents(let cs):  self = .agents(cs.count)
        case .time(let t):     self = .time(t)
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
