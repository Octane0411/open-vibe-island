import AppKit
import Testing
@testable import OpenIslandApp

struct OverlayPlacementStrategyTests {
    @Test
    func topBarDefaultAnchorUsesVisibleFrameTopMinusGap() {
        let anchor = OverlayPlacementStrategy.topBar.resolvedAnchor(
            screenFrame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
            screenVisibleFrame: NSRect(x: 0, y: 24, width: 1728, height: 1093),
            storedTopBarAnchor: nil
        )

        #expect(anchor.x == 864)
        #expect(anchor.y == 1099)
    }

    @Test
    func topBarUsesStoredAnchorWhenAvailable() {
        let stored = NSPoint(x: 1000, y: 1000)
        let anchor = OverlayPlacementStrategy.topBar.resolvedAnchor(
            screenFrame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
            screenVisibleFrame: NSRect(x: 0, y: 24, width: 1728, height: 1093),
            storedTopBarAnchor: stored
        )

        #expect(anchor == stored)
    }

    @Test
    func closedHitRectCentersAroundAnchorAndClosedWidth() {
        let rect = OverlayPlacementStrategy.topBar.closedHitRect(
            anchor: NSPoint(x: 500, y: 1000),
            closedWidth: 240,
            closedHeight: 22
        )

        #expect(rect.minX == 380)
        #expect(rect.maxX == 620)
        #expect(rect.minY == 978)
        #expect(rect.height == 22)
    }

    @Test
    func topBarFrameClampsToVisibleFrame() {
        let frame = OverlayPlacementStrategy.topBar.frame(
            anchor: NSPoint(x: 1900, y: 1060),
            size: NSSize(width: 740, height: 520),
            screenVisibleFrame: NSRect(x: 0, y: 0, width: 1728, height: 1117)
        )

        #expect(frame.maxX <= 1728)
        #expect(frame.minX >= 0)
        #expect(frame.minY >= 0)
    }
}
