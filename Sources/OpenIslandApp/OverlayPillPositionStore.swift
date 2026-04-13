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
///
/// ## Persistence schema
///
/// Each anchor is persisted as a 2-element `[Double]` array under the key
/// `overlay.pill.position.<screenID>`, where `<screenID>` is an
/// `OverlayScreenIdentity` string (typically `display-<CGDisplayID>`).
///
/// `load(for:on:closedWidth:store:)` rejects arrays that are the wrong
/// length or that contain `NaN` / `±Infinity`, returning `nil` so the
/// caller falls back to the default centered placement. `save` similarly
/// refuses to persist non-finite input — a poisoned value on disk can
/// otherwise propagate across launches and silently break pill placement
/// on one display.
enum OverlayPillPositionStore {
    private static let keyPrefix = "overlay.pill.position."

    /// Loads the persisted anchor for `screenID` and clamps it into the
    /// screen's visible frame. Returns `nil` if nothing is stored, if the
    /// stored value has the wrong shape, or if it contains non-finite
    /// coordinates (`NaN` / `±Infinity`) — in all cases the caller should
    /// fall back to the default centered placement.
    static func load(
        for screenID: String,
        on screen: NSScreen,
        closedWidth: CGFloat,
        store: UserDefaults = .standard
    ) -> NSPoint? {
        let key = keyPrefix + screenID
        guard let array = store.array(forKey: key) as? [Double],
              array.count == 2 else {
            return nil
        }
        let x = array[0]
        let y = array[1]
        guard x.isFinite, y.isFinite else {
            // Purge the poisoned entry so the next save starts from a
            // clean slate.
            store.removeObject(forKey: key)
            return nil
        }
        return clamp(NSPoint(x: x, y: y), on: screen, closedWidth: closedWidth)
    }

    /// Persists the given anchor after clamping it to the screen's visible
    /// frame. Non-finite inputs are dropped with no side effect so that a
    /// transient bad value (e.g. from a drag gesture midway through a
    /// display disconnect) never corrupts the on-disk state.
    static func save(
        _ anchor: NSPoint,
        for screenID: String,
        on screen: NSScreen,
        closedWidth: CGFloat,
        store: UserDefaults = .standard
    ) {
        guard anchor.x.isFinite, anchor.y.isFinite else { return }
        let clamped = clamp(anchor, on: screen, closedWidth: closedWidth)
        let key = keyPrefix + screenID
        store.set([Double(clamped.x), Double(clamped.y)], forKey: key)
    }

    /// Removes the persisted anchor for `screenID`. Intended for rollback
    /// and test tear-down; not called from the production code path.
    static func remove(
        for screenID: String,
        store: UserDefaults = .standard
    ) {
        store.removeObject(forKey: keyPrefix + screenID)
    }

    /// Clamps a `(centerX, topY)` anchor so the closed pill stays fully within
    /// the screen's visible frame (menu-bar excluded).
    static func clamp(_ anchor: NSPoint, on screen: NSScreen, closedWidth: CGFloat) -> NSPoint {
        clamp(anchor, within: screen.visibleFrame, closedWidth: closedWidth)
    }

    static func clamp(
        _ anchor: NSPoint,
        within visible: NSRect,
        closedWidth: CGFloat
    ) -> NSPoint {
        // Defensive: non-finite input produces non-finite output in naive
        // `min`/`max`, so collapse to the visible-frame center.
        guard anchor.x.isFinite, anchor.y.isFinite else {
            return NSPoint(x: visible.midX, y: visible.maxY)
        }

        let halfWidth = max(0, closedWidth / 2)
        let clampedX: CGFloat
        if visible.width <= closedWidth {
            clampedX = visible.midX
        } else {
            let minCenterX = visible.minX + halfWidth
            let maxCenterX = visible.maxX - halfWidth
            clampedX = min(max(anchor.x, minCenterX), maxCenterX)
        }

        // `topY` = top edge of panel in Cocoa coordinates. Must sit just under
        // the menu bar (`visible.maxY`) and above the bottom of the screen.
        let maxTopY = visible.maxY
        let minTopY = visible.minY + 40
        let clampedY = min(max(anchor.y, minTopY), maxTopY)

        return NSPoint(x: clampedX, y: clampedY)
    }
}
