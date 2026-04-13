import AppKit
import Testing
@testable import OpenIslandApp

struct OverlayPanelControllerTests {
    @Test
    func closedSurfaceRectCentersOnNotch() {
        let notchRect = NSRect(x: 200, y: 900, width: 200, height: 38)
        let closedWidth: CGFloat = 320

        let rect = OverlayPanelController.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )

        // Centered on notch midX (300), width 320
        #expect(rect.minX == 140)
        #expect(rect.minY == 900)
        #expect(rect.width == 320)
        #expect(rect.height == 38)
    }

    @Test
    func closedSurfaceRectHitTestingBoundary() {
        let notchRect = NSRect(x: 400, y: 1_000, width: 200, height: 38)
        let closedWidth: CGFloat = 420

        let rect = OverlayPanelController.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )

        #expect(rect.contains(NSPoint(x: rect.minX + 2, y: rect.midY)))
        #expect(rect.contains(NSPoint(x: rect.maxX - 2, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.minX - 1, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.maxX + 1, y: rect.midY)))
    }

    @Test
    func hiddenIdleEdgeClosedWidthStaysAtNotchWidth() {
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            notchHeight: 38,
            liveSessionCount: 3,
            hasAttention: true,
            notchStatus: .closed,
            showsIdleEdgeWhenCollapsed: true
        )

        #expect(width == 224)
    }

    @Test
    func regularClosedWidthStillIncludesSessionIndicators() {
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            notchHeight: 38,
            liveSessionCount: 3,
            hasAttention: true,
            notchStatus: .closed,
            showsIdleEdgeWhenCollapsed: false
        )

        // 344 + 18 (attention balance on right side keeps center rect aligned with physical notch)
        #expect(width == 362)
    }

    @Test
    func hiddenIdleEdgeHoverRectAnchorsToTopOfClosedArea() {
        let notchRect = NSRect(x: 400, y: 1_000, width: 224, height: 38)

        let rect = OverlayPanelController.hiddenIdleEdgeHoverRect(
            notchRect: notchRect,
            closedWidth: 224,
            hoverHitHeight: 8
        )

        #expect(rect.minX == 400)
        #expect(rect.maxY == notchRect.maxY)
        #expect(rect.height == 8)
    }

    @Test
    func clickOpensActivateThePanel() {
        #expect(OverlayPanelController.shouldActivatePanel(for: .click))
    }

    @Test
    func passiveOpensDoNotActivateThePanel() {
        #expect(!OverlayPanelController.shouldActivatePanel(for: .hover))
        #expect(!OverlayPanelController.shouldActivatePanel(for: .notification))
        #expect(!OverlayPanelController.shouldActivatePanel(for: .boot))
        #expect(!OverlayPanelController.shouldActivatePanel(for: nil))
    }

    // MARK: - islandClosedHeight

    @Test
    func islandClosedHeightClampsToNotchHeightWhenSmallerThanMenuBar() {
        // Simulates MacBook Air M2: physical notch ≈ 34 pt, menu bar reserved ≈ 37 pt.
        // Must return 34 (the smaller value) so the island sits flush with the notch.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 34, topStatusBarHeight: 37)
        #expect(height == 34)
    }

    @Test
    func islandClosedHeightUsesNotchHeightEvenWhenMenuBarIsShorter() {
        // When menu bar reserved < notch (e.g. auto-hide menu bar), the island must
        // still match the physical notch height to avoid a visible gap.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 37, topStatusBarHeight: 34)
        #expect(height == 37)
    }

    @Test
    func islandClosedHeightFallsBackToMenuBarHeightOnNonNotchScreen() {
        // Non-notch screen: safeAreaInsets.top == 0, fall back to topStatusBarHeight.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 0, topStatusBarHeight: 24)
        #expect(height == 24)
    }
}
