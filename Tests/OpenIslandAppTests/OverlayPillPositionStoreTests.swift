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

    @Test
    func clampCollapsesNaNAnchorToVisibleFrameCenter() {
        let visible = NSRect(x: 0, y: 24, width: 1728, height: 1056)
        let clamped = OverlayPillPositionStore.clamp(
            NSPoint(x: CGFloat.nan, y: CGFloat.nan),
            within: visible,
            closedWidth: 72
        )

        #expect(clamped.x == visible.midX)
        #expect(clamped.y == visible.maxY)
    }

    @Test
    func clampCollapsesInfinityAnchorToVisibleFrameCenter() {
        let visible = NSRect(x: 0, y: 24, width: 1728, height: 1056)
        let clamped = OverlayPillPositionStore.clamp(
            NSPoint(x: CGFloat.infinity, y: -CGFloat.infinity),
            within: visible,
            closedWidth: 72
        )

        #expect(clamped.x == visible.midX)
        #expect(clamped.y == visible.maxY)
    }

    @Test
    func clampClipsRightEdgeOverflow() {
        let visible = NSRect(x: 0, y: 24, width: 1728, height: 1056)
        let clamped = OverlayPillPositionStore.clamp(
            NSPoint(x: 5_000, y: 500),
            within: visible,
            closedWidth: 72
        )

        #expect(clamped.x == visible.maxX - 36)
    }

    @Test
    func clampEnforcesTopYFloorAboveScreenBottom() {
        let visible = NSRect(x: 0, y: 24, width: 1728, height: 1056)
        let clamped = OverlayPillPositionStore.clamp(
            NSPoint(x: 900, y: -500),
            within: visible,
            closedWidth: 72
        )

        #expect(clamped.y == visible.minY + 40)
    }

    @Test
    func clampEnforcesTopYCeilingAtMenuBar() {
        let visible = NSRect(x: 0, y: 24, width: 1728, height: 1056)
        let clamped = OverlayPillPositionStore.clamp(
            NSPoint(x: 900, y: 100_000),
            within: visible,
            closedWidth: 72
        )

        #expect(clamped.y == visible.maxY)
    }
}
