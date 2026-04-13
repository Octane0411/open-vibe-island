import CoreGraphics
import AppKit
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
    func topBarClosedSurfaceWidthFitsSingleSessionContent() {
        let metrics = OverlayClosedShellMetrics.forMode(
            .topBar,
            closedHeight: 22
        )

        let width = metrics.closedSurfaceWidth(
            baseClosedWidth: 56,
            liveCount: 1,
            hasAttention: false,
            isPopping: false
        )

        #expect(width == 58)
    }

    @Test
    func topBarClosedSurfaceWidthAddsOnlyNeededAttentionSpace() {
        let metrics = OverlayClosedShellMetrics.forMode(
            .topBar,
            closedHeight: 22
        )

        let width = metrics.closedSurfaceWidth(
            baseClosedWidth: 56,
            liveCount: 1,
            hasAttention: true,
            isPopping: false
        )

        #expect(width == 72)
    }

    @Test
    func notchClosedSurfaceWidthKeepsLaneExpansionModel() {
        let metrics = OverlayClosedShellMetrics.forMode(
            .notch,
            closedHeight: 34
        )

        let width = metrics.closedSurfaceWidth(
            baseClosedWidth: 200,
            liveCount: 1,
            hasAttention: false,
            isPopping: false
        )

        #expect(width == 288)
    }

    @Test
    func openedHeaderAllowanceIsAtLeastThirtyOnTopBar() {
        let metrics = OverlayClosedShellMetrics.forMode(
            .topBar,
            closedHeight: 22
        )

        #expect(metrics.openedHeaderHeight == 30)
    }

    @Test
    func pillPresentationUsesCompactBaseSizeEvenOnNotchedScreen() {
        let size = OverlayPresentationMode.pill.closedBaseSize(
            physicalIslandBaseSize: NSSize(width: 210, height: 34)
        )

        #expect(size == NSSize(width: 56, height: 22))
    }

    @Test
    func closedSurfaceWidthWithZeroLiveCountReturnsBaseWidth() {
        // Covers the `liveCount > 0` guard — with no live sessions there is
        // no badge to render, so the surface width must equal the base pill
        // width. This branch is otherwise exercised only at runtime when the
        // last session ends.
        let metrics = OverlayClosedShellMetrics.forMode(
            .topBar,
            closedHeight: 22
        )

        let width = metrics.closedSurfaceWidth(
            baseClosedWidth: 56,
            liveCount: 0,
            hasAttention: false,
            isPopping: false
        )

        #expect(width == 56)
    }

    @Test
    func closedSurfaceWidthWithZeroLiveCountStillAddsPoppingWidth() {
        // The `isPopping` contribution must still be applied when there are
        // no live sessions — otherwise the pop animation clips.
        let metrics = OverlayClosedShellMetrics.forMode(
            .topBar,
            closedHeight: 22
        )

        let width = metrics.closedSurfaceWidth(
            baseClosedWidth: 56,
            liveCount: 0,
            hasAttention: false,
            isPopping: true
        )

        #expect(width == 74) // 56 + 18 pop width
    }

    @Test
    func notchClosedSurfaceWidthAddsPoppingWidth() {
        let metrics = OverlayClosedShellMetrics.forMode(
            .notch,
            closedHeight: 34
        )

        let widthStatic = metrics.closedSurfaceWidth(
            baseClosedWidth: 200,
            liveCount: 1,
            hasAttention: false,
            isPopping: false
        )
        let widthPopping = metrics.closedSurfaceWidth(
            baseClosedWidth: 200,
            liveCount: 1,
            hasAttention: false,
            isPopping: true
        )

        #expect(widthPopping == widthStatic + 18)
    }

    @Test
    func notchClosedSurfaceWidthIncludesAttentionIndicatorWidth() {
        let metrics = OverlayClosedShellMetrics.forMode(
            .notch,
            closedHeight: 34
        )

        let widthNoAttention = metrics.closedSurfaceWidth(
            baseClosedWidth: 200,
            liveCount: 1,
            hasAttention: false,
            isPopping: false
        )
        let widthAttention = metrics.closedSurfaceWidth(
            baseClosedWidth: 200,
            liveCount: 1,
            hasAttention: true,
            isPopping: false
        )

        // Attention adds 18 to leftWidth, 18 to rightWidth (notch-centering
        // balance restored from main #300), and 6 to expansionWidth.
        #expect(widthAttention == widthNoAttention + 42)
    }

    @Test
    func topBarClosedSurfaceWidthGrowsForMultiDigitLiveCount() {
        // The badge widens by 8 per extra digit — guards against the
        // `digits - 1` arithmetic regressing for two-digit counts.
        let metrics = OverlayClosedShellMetrics.forMode(
            .topBar,
            closedHeight: 22
        )

        let singleDigit = metrics.closedSurfaceWidth(
            baseClosedWidth: 56,
            liveCount: 9,
            hasAttention: false,
            isPopping: false
        )
        let twoDigits = metrics.closedSurfaceWidth(
            baseClosedWidth: 56,
            liveCount: 10,
            hasAttention: false,
            isPopping: false
        )

        #expect(twoDigits == singleDigit + 8)
    }
}
