import CoreGraphics
import Testing
@testable import OpenIslandApp

struct IslandChromeMetricsTests {
    @Test
    func openedVisualStateUsesOpenedShadowInsets() {
        let insets = IslandChromeMetrics.panelShadowInsets(
            usesOpenedVisualState: true
        )

        #expect(insets.horizontal == IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(insets.bottom == IslandChromeMetrics.openedShadowBottomInset)
    }

    @Test
    func closedVisualStateUsesClosedShadowInsets() {
        let insets = IslandChromeMetrics.panelShadowInsets(
            usesOpenedVisualState: false
        )

        #expect(insets.horizontal == IslandChromeMetrics.closedShadowHorizontalInset)
        #expect(insets.bottom == IslandChromeMetrics.closedShadowBottomInset)
    }
}
