import AppKit
import Foundation

@MainActor
final class FullscreenSpaceObserver {
    /// Pure helper: does the topmost layer-0 window bound completely cover
    /// the screen frame (i.e. extend across the menu-bar area too)?
    /// A ±1pt tolerance absorbs sub-pixel rounding in `CGWindowListCopyWindowInfo`.
    static func screenIsCovered(byTopWindowBounds bounds: CGRect, screenFrame: CGRect) -> Bool {
        let widthDelta = abs(bounds.width - screenFrame.width)
        let heightDelta = abs(bounds.height - screenFrame.height)
        let originXDelta = abs(bounds.minX - screenFrame.minX)
        let originYDelta = abs(bounds.minY - screenFrame.minY)
        return widthDelta <= 1
            && heightDelta <= 1
            && originXDelta <= 1
            && originYDelta <= 1
    }
}
