import SwiftUI
import Combine

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

    @State private var breathePhase: Bool = false
    @State private var eyesVisible: Bool = true
    @State private var antennaOffset: CGFloat = 0
    @State private var legOffset: CGFloat = 0

    private static let blinkTimer = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()

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
                        .opacity(pixel.part == .eye && !eyesVisible ? 0 : 1)
                        .frame(width: cell, height: cell)
                        .offset(
                            x: originX + CGFloat(pixel.x) * cell + partOffsetX(pixel.part),
                            y: originY + CGFloat(pixel.y) * cell + partOffsetY(pixel.part)
                        )
                }
            }
        }
        .frame(width: size, height: size)
        .drawingGroup(opaque: false, colorMode: .extendedLinear)
        .opacity(style == .duotone ? (breathePhase ? 1.0 : 0.78) : 1.0)
        .animation(
            style == .duotone
                ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                : nil,
            value: breathePhase
        )
        .onAppear {
            if style == .duotone {
                breathePhase = true
            }
            updatePartAnimations(animation)
        }
        .onChange(of: animation) { _, newAnimation in
            updatePartAnimations(newAnimation)
        }
        .onReceive(Self.blinkTimer) { _ in
            guard style == .duotone else { return }
            eyesVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                eyesVisible = true
            }
        }
    }

    private func updatePartAnimations(_ anim: ScoutAnimation) {
        switch anim {
        case .active, .permissionAlert, .taskComplete:
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                antennaOffset = 1.5
            }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                legOffset = 1.5
            }
        case .idle:
            withAnimation(.easeInOut(duration: 0.3)) {
                antennaOffset = 0
                legOffset = 0
            }
        }
    }

    private func partOffsetY(_ part: PixelPart) -> CGFloat {
        switch part {
        case .antenna: return -antennaOffset
        default: return 0
        }
    }

    private func partOffsetX(_ part: PixelPart) -> CGFloat {
        switch part {
        case .leg: return legOffset
        default: return 0
        }
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
