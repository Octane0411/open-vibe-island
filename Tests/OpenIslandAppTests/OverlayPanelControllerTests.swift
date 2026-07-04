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
            closedWidth: closedWidth,
            closedHeight: 34
        )

        // Centered on notch midX (300), width 320
        #expect(rect.minX == 140)
        #expect(rect.minY == 904)
        #expect(rect.width == 320)
        #expect(rect.height == 34)
    }

    @Test
    func closedSurfaceRectHitTestingBoundary() {
        let notchRect = NSRect(x: 400, y: 1_000, width: 200, height: 38)
        let closedWidth: CGFloat = 420

        let rect = OverlayPanelController.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth,
            closedHeight: 30
        )

        #expect(rect.contains(NSPoint(x: rect.minX + 2, y: rect.midY)))
        #expect(rect.contains(NSPoint(x: rect.maxX - 2, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.minX - 1, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.maxX + 1, y: rect.midY)))
        #expect(rect.maxY == notchRect.maxY)
        #expect(!rect.contains(NSPoint(x: rect.midX, y: rect.minY - 1)))
    }

    @Test
    func closedSurfaceRectInPanelBoundsStaysTopAnchored() {
        let bounds = NSRect(x: 0, y: 0, width: 700, height: 160)

        let rect = OverlayPanelController.closedSurfaceRect(
            bounds: bounds,
            closedWidth: 320,
            closedHeight: 30
        )

        #expect(rect.minX == 190)
        #expect(rect.minY == 130)
        #expect(rect.width == 320)
        #expect(rect.height == 30)
        #expect(rect.maxY == bounds.maxY)
    }

    @Test
    func edgeInclusiveHitTestingTreatsMaxBoundaryAsInside() {
        let rect = NSRect(x: 100, y: 200, width: 224, height: 8)
        #expect(OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 150, y: 208)))
        #expect(OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 324, y: 205)))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 325, y: 205)))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 150, y: 209)))
    }

    @Test
    func notchedDisplayClosedWidthKeepsPhysicalCameraNotchCovered() {
        // Compact MacBook layout: keep the physical camera notch covered,
        // but use only 80% of the old 88pt side reserve.
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            isNotchedDisplay: true,
            notchStatus: .closed
        )
        #expect(width == CGFloat(224 + (88 * 0.8)))
    }

    @Test
    func externalDisplayClosedWidthUsesFixedHitArea() {
        // v6 external layout: fluid in SwiftUI, but the controller uses a
        // generous fixed hit-area so hover/click works without knowing the
        // live content width.
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 0,
            isNotchedDisplay: false,
            notchStatus: .closed
        )
        #expect(width == CGFloat(360))
    }

    @Test
    func poppingStatusAddsHoverBudget() {
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            isNotchedDisplay: true,
            notchStatus: .popping
        )
        #expect(width == CGFloat(224 + (88 * 0.8) + 18))
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
    func islandClosedHeightKeepsPhysicalNotchHeightWhenSmallerThanMenuBar() {
        // Simulates MacBook Air M2: physical notch ≈ 34 pt, menu bar reserved ≈ 37 pt.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 34, topStatusBarHeight: 37)
        #expect(height == 34)
    }

    @Test
    func islandClosedHeightKeepsPhysicalNotchHeightEvenWhenMenuBarIsShorter() {
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 37, topStatusBarHeight: 34)
        #expect(height == 37)
    }

    @Test
    func islandClosedHeightFallsBackToMenuBarHeightOnNonNotchScreen() {
        // Non-notch screen: safeAreaInsets.top == 0, fall back to topStatusBarHeight.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 0, topStatusBarHeight: 24)
        #expect(height == 24)
    }

    // MARK: - closedSurfaceHitHeight

    @Test
    func closedSurfaceHitHeightTrimsNotchScreenHitAreaOnly() {
        let height = NSScreen.computeClosedSurfaceHitHeight(safeAreaInsetsTop: 34, topStatusBarHeight: 37)
        #expect(height == 30)
    }

    @Test
    func closedSurfaceHitHeightKeepsExternalDisplayHitAreaUnchanged() {
        let height = NSScreen.computeClosedSurfaceHitHeight(safeAreaInsetsTop: 0, topStatusBarHeight: 24)
        #expect(height == 24)
    }
}
