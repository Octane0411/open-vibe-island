import AppKit
import Foundation

/// Persists user-dragged pill anchor positions per external display.
///
/// Anchor format: `(centerX, topY)` in Cocoa screen coordinates, where
/// `centerX` is the horizontal center of the closed pill and `topY` is the
/// top edge of the panel (Cocoa `maxY`). Storing the center + top keeps the
/// anchor stable across closed/opened panel size changes, because the SwiftUI
/// content is horizontally centered inside the panel and the panel extends
/// downward when opened.
///
/// Only used for `.topBar` placement mode. Built-in notch screens ignore the
/// store entirely and keep the existing centered-on-notch behavior.
enum OverlayPillPositionStore {
    private static let keyPrefix = "overlay.pill.position."

    static func load(for screenID: String, on screen: NSScreen) -> NSPoint? {
        let key = keyPrefix + screenID
        guard let array = UserDefaults.standard.array(forKey: key) as? [Double],
              array.count == 2 else {
            return nil
        }
        return clamp(NSPoint(x: array[0], y: array[1]), on: screen)
    }

    static func save(_ anchor: NSPoint, for screenID: String, on screen: NSScreen) {
        let clamped = clamp(anchor, on: screen)
        let key = keyPrefix + screenID
        UserDefaults.standard.set([Double(clamped.x), Double(clamped.y)], forKey: key)
    }

    /// Clamps a `(centerX, topY)` anchor so the closed pill stays fully within
    /// the screen's visible frame (menu-bar excluded).
    static func clamp(_ anchor: NSPoint, on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let horizontalMargin: CGFloat = 24
        let minCenterX = visible.minX + horizontalMargin
        let maxCenterX = visible.maxX - horizontalMargin
        let clampedX = min(max(anchor.x, minCenterX), maxCenterX)

        // `topY` = top edge of panel in Cocoa coordinates. Must sit just under
        // the menu bar (`visible.maxY`) and above the bottom of the screen.
        let maxTopY = visible.maxY
        let minTopY = visible.minY + 40
        let clampedY = min(max(anchor.y, minTopY), maxTopY)

        return NSPoint(x: clampedX, y: clampedY)
    }
}
