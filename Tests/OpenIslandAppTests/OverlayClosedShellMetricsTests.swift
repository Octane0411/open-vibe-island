import CoreGraphics
import Testing
@testable import OpenIslandApp

struct OverlayClosedShellMetricsTests {
    @Test
    func openedHeaderAllowanceUsesSharedEntryForNotchAndTopBar() {
        let notchClosedHeight: CGFloat = 34
        let topBarClosedHeight: CGFloat = 22

        let notchAllowance = OverlayClosedShellMetrics.openedHeaderAllowance(
            forClosedHeight: notchClosedHeight
        )
        let topBarAllowance = OverlayClosedShellMetrics.openedHeaderAllowance(
            forClosedHeight: topBarClosedHeight
        )

        let notchMetrics = OverlayClosedShellMetrics.forMode(
            .notch,
            closedHeight: notchClosedHeight
        )
        let topBarMetrics = OverlayClosedShellMetrics.forMode(
            .topBar,
            closedHeight: topBarClosedHeight
        )

        #expect(
            notchMetrics.openedHeaderHeight == notchAllowance
        )
        #expect(
            topBarMetrics.openedHeaderHeight == topBarAllowance
        )
        #expect(topBarAllowance >= 30)
        #expect(notchAllowance == notchClosedHeight)
    }

    @Test
    func notchAndTopBarClosedShellsUseDifferentLayoutFamilies() {
        let notch = OverlayClosedShellMetrics.forMode(
            .notch,
            closedHeight: 34
        )
        let topBar = OverlayClosedShellMetrics.forMode(
            .topBar,
            closedHeight: 22
        )

        #expect(notch.layoutFamily == .notch)
        #expect(topBar.layoutFamily == .floatingPill)
    }

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
