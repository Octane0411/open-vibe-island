import AppKit
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

    /// AppKit template image for the menu-bar status item. SwiftUI's
    /// `MenuBarExtra` does not turn an arbitrary view into a real template
    /// image, which is why the live SwiftUI mark renders as an inverted
    /// black block when the menu bar item is highlighted (#428).
    static let menuBarTemplateImage: NSImage = makeMenuBarTemplateImage()

    static func makeMenuBarTemplateImage(pixelSize: CGFloat = 2, padding: CGFloat = 1) -> NSImage {
        let dimension = CGFloat(8) * pixelSize + padding * 2
        let size = NSSize(width: dimension, height: dimension)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            for pixel in pixels {
                let alpha: CGFloat = pixel.role == "E" ? 0.7 : 1.0
                ctx.setFillColor(NSColor.black.withAlphaComponent(alpha).cgColor)
                let rect = CGRect(
                    x: padding + CGFloat(pixel.x) * pixelSize,
                    y: padding + CGFloat(7 - pixel.y) * pixelSize,
                    width: pixelSize,
                    height: pixelSize
                )
                ctx.fill(rect)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
