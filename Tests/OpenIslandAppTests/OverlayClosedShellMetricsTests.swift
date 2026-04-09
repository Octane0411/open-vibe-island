import CoreGraphics
import Testing
@testable import OpenIslandApp

struct OverlayClosedShellMetricsTests {
    @Test
    func notchModeReturnsNotchMetrics() {
        let metrics = OverlayClosedShellMetrics.forMode(
            .notch,
            closedHeight: 34
        )

        #expect(metrics.mode == .notch)
        #expect(!metrics.isFloatingPill)
        #expect(metrics.closedHeight == 34)
        #expect(metrics.openedHeaderHeight == 34)
        #expect(metrics.iconSize == 14)
        #expect(metrics.horizontalPadding == 0)
        #expect(metrics.badgeSpacing == 4)
        #expect(metrics.attentionIndicatorSize == 14)
    }

    @Test
    func topBarModeReturnsCompactPillMetrics() {
        let metrics = OverlayClosedShellMetrics.forMode(
            .topBar,
            closedHeight: 22
        )

        #expect(metrics.mode == .topBar)
        #expect(metrics.isFloatingPill)
        #expect(metrics.closedHeight == 22)
        #expect(metrics.iconSize == 12)
        #expect(metrics.horizontalPadding == 8)
        #expect(metrics.badgeSpacing == 4)
        #expect(metrics.attentionIndicatorSize == 10)
    }

    @Test
    func openedHeaderAllowanceIsAtLeastThirtyOnTopBar() {
        let metrics = OverlayClosedShellMetrics.forMode(
            .topBar,
            closedHeight: 22
        )

        #expect(metrics.openedHeaderHeight == 30)
    }
}
