import SwiftUI

enum OrbitSurfaceStyle {
    static let defaultStarfieldEnabled = false
}

enum OrbitStarDensity: String, CaseIterable, Identifiable {
    case sparse
    case balanced
    case vivid

    var id: String { rawValue }
    var starCount: Int {
        switch self {
        case .sparse: 18
        case .balanced: 34
        case .vivid: 54
        }
    }
    var titleKey: String { "settings.appearance.starfield.\(rawValue)" }
}

struct OrbitSurfaceBackdrop: View {
    let density: OrbitStarDensity
    var showStars = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.037, blue: 0.045),
                    Color(red: 0.075, green: 0.080, blue: 0.092),
                    V6Palette.ink
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(0.055), .clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 260
            )
            if showStars {
                OrbitStarfield(count: density.starCount)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct OrbitStarfield: View {
    let count: Int

    var body: some View {
        Canvas { context, size in
            for index in 0..<count {
                let seed = Double(index + 1)
                let x = abs(sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
                let y = abs(sin(seed * 78.233) * 19341.127).truncatingRemainder(dividingBy: 1)
                let radius = 0.45 + (seed.truncatingRemainder(dividingBy: 3) * 0.18)
                let rect = CGRect(
                    x: x * size.width,
                    y: y * size.height,
                    width: radius * 2,
                    height: radius * 2
                )
                let opacity = 0.18 + (seed.truncatingRemainder(dividingBy: 5) * 0.055)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
            }
        }
    }
}
