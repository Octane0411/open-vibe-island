import AppKit
import Testing
@testable import OpenIslandApp

struct OverlayPillPositionStoreTests {
    @Test
    func clampUsesActualClosedWidthNearLeftEdge() {
        let clamped = OverlayPillPositionStore.clamp(
            NSPoint(x: 10, y: 500),
            within: NSRect(x: 0, y: 24, width: 1728, height: 1056),
            closedWidth: 72
        )

        #expect(clamped.x == 36)
        #expect(clamped.y == 500)
    }

    @Test
    func clampCentersWhenClosedWidthExceedsVisibleFrame() {
        let visibleFrame = NSRect(x: 100, y: 24, width: 80, height: 1056)
        let clamped = OverlayPillPositionStore.clamp(
            NSPoint(x: 20, y: 500),
            within: visibleFrame,
            closedWidth: 120
        )

        #expect(clamped.x == visibleFrame.midX)
    }
}
