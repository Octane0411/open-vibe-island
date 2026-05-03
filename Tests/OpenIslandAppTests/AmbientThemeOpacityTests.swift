import Foundation
import Testing
@testable import OpenIslandApp

@MainActor
struct AmbientThemeOpacityTests {
    @Test
    func opacityClampsToValidRange() {
        #expect(AmbientTheme.clampOpacity(0.30) == 0.20)
        #expect(AmbientTheme.clampOpacity(-0.10) == 0.05)
        #expect(AmbientTheme.clampOpacity(0.12) == 0.12)
    }

    @Test
    func effectiveOpacityIsZeroWhenDisabled() {
        #expect(AmbientTheme.effectiveOpacity(enabled: false, sliderValue: 0.20) == 0)
        #expect(AmbientTheme.effectiveOpacity(enabled: true, sliderValue: 0.20) == 0.20)
    }
}
