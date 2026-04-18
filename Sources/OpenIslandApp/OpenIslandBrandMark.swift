import SwiftUI

struct OpenIslandBrandMark: View {
    enum Style {
        case duotone
        case template
    }

    let size: CGFloat
    var tint: Color = .mint
    var isAnimating: Bool = false
    var style: Style = .duotone

    private static let scoutPattern = [
        "..B..B..",
        "..BBBB..",
        ".BHHHHB.",
        "BBHEHEBB",
        ".BHHHHB.",
        "..BBBB..",
        ".B....B.",
        "........",
    ]

    private static let pixels: [(x: Int, y: Int, role: Character)] = scoutPattern.enumerated().flatMap { rowIndex, row in
        row.enumerated().compactMap { columnIndex, character in
            character == "." ? nil : (columnIndex, rowIndex, character)
        }
    }

    var body: some View {
        if isAnimating {
            TimelineView(.animation(minimumInterval: 0.033)) { context in
                markContent(brightness: pulseBrightness(at: context.date))
                    .scaleEffect(pulseScale(at: context.date))
                    .shadow(
                        color: tint.opacity(glowOpacity(at: context.date)),
                        radius: pulseGlowRadius(at: context.date),
                        x: 0,
                        y: 0
                    )
            }
        } else {
            markContent(brightness: 1.0)
        }
    }

    private func markContent(brightness: Double) -> some View {
        GeometryReader { proxy in
            let cell = min(proxy.size.width / 8, proxy.size.height / 8)
            let markWidth = cell * 8
            let markHeight = cell * 8
            let originX = (proxy.size.width - markWidth) / 2
            let originY = (proxy.size.height - markHeight) / 2

            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.pixels.enumerated()), id: \.offset) { _, pixel in
                    Rectangle()
                        .fill(fillColor(for: pixel.role, brightness: brightness))
                        .frame(width: cell, height: cell)
                        .offset(
                            x: originX + CGFloat(pixel.x) * cell,
                            y: originY + CGFloat(pixel.y) * cell
                        )
                }
            }
        }
        .frame(width: size, height: size)
        .drawingGroup(opaque: false, colorMode: .extendedLinear)
    }

    /// Pulse cycle: 1.5 seconds. Wave goes 0→1→0→-1→0.
    private func pulsePhase(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return sin(t * Double.pi * 4 / 3)
    }

    private func pulseBrightness(at date: Date) -> Double {
        let wave = pulsePhase(at: date)
        return 0.45 + (wave + 1) / 2 * 0.75
    }

    private func pulseScale(at date: Date) -> CGFloat {
        let wave = pulsePhase(at: date)
        return CGFloat(0.82 + (wave + 1) / 2 * 0.18)
    }

    private func glowOpacity(at date: Date) -> Double {
        let wave = pulsePhase(at: date)
        return (wave + 1) / 2 * 0.55
    }

    private func pulseGlowRadius(at date: Date) -> CGFloat {
        let wave = pulsePhase(at: date)
        return CGFloat(2 + (wave + 1) / 2 * 5)
    }

    private func fillColor(for role: Character, brightness: Double) -> Color {
        switch style {
        case .duotone:
            switch role {
            case "B":
                return tint.opacity(min(1.0, 0.86 * brightness))
            case "H":
                return tint.opacity(min(0.92, 0.64 * brightness))
            case "E":
                return Color.black.opacity(0.72)
            default:
                return .clear
            }
        case .template:
            return Color.primary.opacity(role == "E" ? 0.9 : 1.0)
        }
    }
}
