import AppKit
import Testing
@testable import OpenIslandApp

struct OverlayPanelControllerTests {
    @Test
    func closedSurfaceRectRemovesPanelShadowInsets() {
        let panelFrame = NSRect(x: 100, y: 900, width: 320, height: 38)

        let rect = OverlayPanelController.closedSurfaceRect(
            for: panelFrame,
            shadowInsets: (horizontal: 12, bottom: 14)
        )

        #expect(rect.minX == 112)
        #expect(rect.minY == 914)
        #expect(rect.width == 296)
        #expect(rect.height == 24)
    }

    @Test
    func closedSurfaceRectKeepsFullVisibleWidthInteractive() {
        let panelFrame = NSRect(x: 500, y: 1_000, width: 420, height: 38)

        let rect = OverlayPanelController.closedSurfaceRect(
            for: panelFrame,
            shadowInsets: (horizontal: 12, bottom: 14)
        )

        #expect(rect.contains(NSPoint(x: rect.minX + 2, y: rect.midY)))
        #expect(rect.contains(NSPoint(x: rect.maxX - 2, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.minX - 1, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.maxX + 1, y: rect.midY)))
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
    func islandClosedHeightClampsToMenuBarHeightWhenSmallerThanNotch() {
        // Defensive: if menu bar reserved < notch for some future model, don't exceed it.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 37, topStatusBarHeight: 34)
        #expect(height == 34)
    }

    @Test
    func islandClosedHeightFallsBackToMenuBarHeightOnNonNotchScreen() {
        // Non-notch screen: safeAreaInsets.top == 0, fall back to topStatusBarHeight.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 0, topStatusBarHeight: 24)
        #expect(height == 24)
    }
}
