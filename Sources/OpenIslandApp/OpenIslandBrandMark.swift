import SwiftUI
import AppKit

struct OpenIslandBrandMark: View {
    enum Style {
        case duotone
        case template
    }

    let size: CGFloat
    var tint: Color = .mint
    var isAnimating: Bool = false
    var style: Style = .duotone
    var customAvatarImage: NSImage? = nil

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

    var body: some View {
        if style == .duotone, let customAvatarImage {
            Image(nsImage: customAvatarImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            spriteBody(pattern: Self.scoutPattern)
                .frame(width: size, height: size)
        }
    }

    private func spriteBody(pattern: [String]) -> some View {
        GeometryReader { proxy in
            let gridSize = CGFloat(pattern.count)
            let cell = floor(min(proxy.size.width / gridSize, proxy.size.height / gridSize))
            let markWidth = cell * gridSize
            let markHeight = cell * gridSize
            let originX = (proxy.size.width - markWidth) / 2
            let originY = (proxy.size.height - markHeight) / 2
            let pixels = Self.pixels(for: pattern)

            ZStack(alignment: .topLeading) {
                ForEach(Array(pixels.enumerated()), id: \.offset) { _, pixel in
                    Rectangle()
                        .fill(fillColor(for: pixel.role))
                        .frame(width: cell, height: cell)
                        .offset(
                            x: originX + CGFloat(pixel.x) * cell,
                            y: originY + CGFloat(pixel.y) * cell
                        )
                }
            }
        }
    }

    private static func pixels(for pattern: [String]) -> [(x: Int, y: Int, role: Character)] {
        pattern.enumerated().flatMap { rowIndex, row in
            row.enumerated().compactMap { columnIndex, character in
                character == "." ? nil : (columnIndex, rowIndex, character)
            }
        }
    }

    private func fillColor(for role: Character) -> Color {
        switch style {
        case .duotone:
            switch role {
            case "B":
                return tint.opacity(isAnimating ? 1.0 : 0.86)
            case "H":
                return tint.opacity(isAnimating ? 0.84 : 0.64)
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
