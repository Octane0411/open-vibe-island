import AppKit
import Testing
@testable import OpenIslandApp

struct FullscreenSpaceObserverTests {
    @Test
    func coverageReturnsTrueWhenBoundsEqualScreenFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        #expect(FullscreenSpaceObserver.screenIsCovered(byTopWindowBounds: frame, screenFrame: frame))
    }

    @Test
    func coverageReturnsFalseWhenBoundsLeaveMenuBar() {
        // Screen frame includes menu bar; window stops at the menu bar bottom.
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let bounds = CGRect(x: 0, y: 25, width: 1_440, height: 875)
        #expect(!FullscreenSpaceObserver.screenIsCovered(byTopWindowBounds: bounds, screenFrame: frame))
    }

    @Test
    func coverageReturnsFalseWhenBoundsAreSmaller() {
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(!FullscreenSpaceObserver.screenIsCovered(byTopWindowBounds: bounds, screenFrame: frame))
    }

    @Test
    func coverageReturnsFalseWhenBoundsExceedScreen() {
        // Defensive: a window that spans multiple screens should not be treated
        // as fullscreen on either of them.
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let bounds = CGRect(x: -100, y: 0, width: 3_000, height: 900)
        #expect(!FullscreenSpaceObserver.screenIsCovered(byTopWindowBounds: bounds, screenFrame: frame))
    }

    @Test
    func coverageAllowsOnePixelTolerance() {
        // CGWindowListCopyWindowInfo bounds are sometimes off by a sub-pixel
        // due to coordinate rounding; the helper must tolerate ±1pt.
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let bounds = CGRect(x: 0, y: 0, width: 1_439, height: 900)
        #expect(FullscreenSpaceObserver.screenIsCovered(byTopWindowBounds: bounds, screenFrame: frame))
    }
}
