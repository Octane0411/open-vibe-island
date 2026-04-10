import SwiftUI

enum IslandPixelShapeStyle: String, CaseIterable, Identifiable {
    case bars
    case steps
    case blocks

    var id: String { rawValue }

    fileprivate var chartFrames: [([Int], [Int])] {
        switch self {
        case .bars:
            [
                ([1, 3, 2, 1], [2, 3, 1]),
                ([2, 2, 3, 1], [1, 2, 3]),
                ([1, 2, 1, 3], [3, 1, 2]),
                ([3, 1, 2, 2], [2, 3, 1]),
            ]
        case .steps:
            [
                ([1, 2, 3, 4], [1, 2, 3]),
                ([2, 3, 4, 3], [2, 3, 2]),
                ([1, 2, 3, 4], [3, 2, 1]),
                ([2, 3, 2, 1], [2, 3, 4]),
            ]
        case .blocks:
            [
                ([2, 4, 4, 2], [2, 4, 2]),
                ([3, 4, 3, 2], [3, 4, 2]),
                ([2, 3, 4, 3], [2, 4, 3]),
                ([2, 4, 3, 2], [3, 4, 2]),
            ]
        }
    }
}

struct IslandPixelGlyph: View {
    var tint: Color
    var style: IslandPixelShapeStyle
    var isAnimating: Bool
    var width: CGFloat = 26
    var height: CGFloat = 14

    var body: some View {
        if style == .bars {
            TimelineView(.animation(minimumInterval: 0.18, paused: !isAnimating)) { context in
                let pulsePhase = frameIndex(for: context.date, frameCount: 2).isMultiple(of: 2)

                OpenIslandBrandMark(
                    size: min(width, height),
                    tint: tint,
                    isAnimating: pulsePhase,
                    style: .duotone
                )
                .frame(width: width, height: height)
            }
        } else {
            TimelineView(.animation(minimumInterval: 0.18, paused: !isAnimating)) { context in
                let frame = style.chartFrames[frameIndex(for: context.date, frameCount: style.chartFrames.count)]

                HStack(alignment: .bottom, spacing: 3) {
                    PixelColumnCluster(heights: frame.0, tint: tint)
                    PixelColumnCluster(heights: frame.1, tint: tint)
                }
                .frame(width: width, height: height, alignment: .bottomLeading)
            }
        }
    }

    private func frameIndex(for date: Date, frameCount: Int) -> Int {
        guard isAnimating else {
            return 0
        }

        let ticks = Int(date.timeIntervalSinceReferenceDate / 0.18)
        return ticks % max(frameCount, 1)
    }
}

private struct PixelColumnCluster: View {
    let heights: [Int]
    let tint: Color

    private let rows = 4
    private let pixelSize: CGFloat = 2.4
    private let pixelSpacing: CGFloat = 1.1

    var body: some View {
        HStack(alignment: .bottom, spacing: pixelSpacing) {
            ForEach(Array(heights.enumerated()), id: \.offset) { columnIndex, height in
                VStack(spacing: pixelSpacing) {
                    ForEach((0..<rows).reversed(), id: \.self) { row in
                        RoundedRectangle(cornerRadius: 0.4, style: .continuous)
                            .fill(pixelColor(row: row, height: height))
                            .frame(width: pixelSize, height: pixelSize)
                    }
                }
                .opacity(columnIndex == heights.count - 1 ? 0.86 : 1)
            }
        }
        .shadow(color: tint.opacity(0.55), radius: 2.2, x: 0, y: 0)
    }

    private func pixelColor(row: Int, height: Int) -> Color {
        guard row < height else {
            return .clear
        }

        let relativeLevel = Double(row + 1) / Double(max(height, 1))
        return tint.opacity(0.45 + (relativeLevel * 0.5))
    }
}
