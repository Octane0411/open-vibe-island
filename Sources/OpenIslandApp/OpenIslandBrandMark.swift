import SwiftUI

enum ScoutAnimation: Equatable {
    case idle
    case active
    case permissionAlert
    case taskComplete
}

struct OpenIslandBrandMark: View {
    enum Style {
        case duotone
        case template
    }

    enum PixelPart {
        case antenna
        case head
        case eye
        case body
        case leg
    }

    let size: CGFloat
    var tint: Color = .mint
    var animation: ScoutAnimation = .idle
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

    private static let pixels: [(x: Int, y: Int, role: Character, part: PixelPart)] = scoutPattern.enumerated().flatMap { rowIndex, row in
        row.enumerated().compactMap { columnIndex, character in
            guard character != "." else { return nil }
            let part: PixelPart = switch rowIndex {
            case 0: .antenna
            case 1, 2: .head
            case 3: character == "E" ? .eye : .body
            case 4, 5: .body
            case 6: .leg
            default: .body
            }
            return (columnIndex, rowIndex, character, part)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let cell = min(proxy.size.width / 8, proxy.size.height / 8)
            let markWidth = cell * 8
            let markHeight = cell * 8
            let originX = (proxy.size.width - markWidth) / 2
            let originY = (proxy.size.height - markHeight) / 2

            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.pixels.enumerated()), id: \.offset) { _, pixel in
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
        .frame(width: size, height: size)
        .drawingGroup(opaque: false, colorMode: .extendedLinear)
    }

    private func fillColor(for role: Character) -> Color {
        switch style {
        case .duotone:
            switch role {
            case "B":
                return tint.opacity(animation != .idle ? 1.0 : 0.86)
            case "H":
                return tint.opacity(animation != .idle ? 0.84 : 0.64)
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
