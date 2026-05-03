import SwiftUI
import OpenIslandCore

enum AmbientTheme {
    static let minOpacity: Double = 0.05
    static let maxOpacity: Double = 0.20

    static func clampOpacity(_ value: Double) -> Double {
        max(minOpacity, min(maxOpacity, value))
    }

    static func effectiveOpacity(enabled: Bool, sliderValue: Double) -> Double {
        guard enabled else { return 0 }
        return clampOpacity(sliderValue)
    }
}

struct AmbientThemeOverlay: View {
    let tintColor: ProjectColor?
    let opacity: Double

    var body: some View {
        if let tint = tintColor, opacity > 0 {
            LinearGradient(
                colors: [
                    Color(red: tint.red, green: tint.green, blue: tint.blue).opacity(opacity),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.4), value: tint)
        } else {
            EmptyView()
        }
    }
}
