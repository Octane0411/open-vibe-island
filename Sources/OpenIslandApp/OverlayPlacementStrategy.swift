import AppKit

/// Geometry-only placement math for the overlay panel. Each case describes
/// how the closed anchor and panel frame relate to the target screen, so
/// callers can compute positions without touching AppKit mutable state.
///
/// - `.notch`: anchor sits at the top center of the full screen frame (on
///   top of the menu bar), and the panel hangs down from there. Used on
///   Macs with a physical notch, or when the user forces island mode.
/// - `.topBar`: anchor is a user-draggable point on the visible frame's
///   top edge minus a fixed gap; the panel is horizontally clamped inside
///   the visible frame so it never slides off-screen.
///
/// The strategy is a pure value type — it owns no state and has no side
/// effects. `OverlayPanelController` drives all window mutations.
enum OverlayPlacementStrategy: Equatable {
    case notch
    case topBar

    /// Vertical offset between the menu bar bottom and the top-bar pill's
    /// top edge, used when no user-dragged anchor has been persisted yet.
    private static let topBarMenuBarGap: CGFloat = 18

    init(mode: OverlayPlacementMode) {
        switch mode {
        case .notch:
            self = .notch
        case .topBar:
            self = .topBar
        }
    }

    /// Resolves the anchor point `(centerX, topY)` in Cocoa screen coords.
    /// For notch placement the anchor is fixed at the screen center on the
    /// menu bar; for top-bar placement the stored per-display drag anchor
    /// wins if present, otherwise the default sits just below the menu
    /// bar.
    func resolvedAnchor(
        screenFrame: NSRect,
        screenVisibleFrame: NSRect,
        storedTopBarAnchor: NSPoint?
    ) -> NSPoint {
        switch self {
        case .notch:
            return NSPoint(x: screenFrame.midX, y: screenFrame.maxY)
        case .topBar:
            return storedTopBarAnchor
                ?? NSPoint(x: screenFrame.midX, y: screenVisibleFrame.maxY - Self.topBarMenuBarGap)
        }
    }

    /// Builds the panel frame from the resolved anchor and a panel size.
    /// Notch placement lets the panel extend above the visible frame (into
    /// the menu bar) by design; top-bar placement clamps the frame to the
    /// visible frame so the pill never clips past the screen edges.
    func frame(
        anchor: NSPoint,
        size: NSSize,
        screenVisibleFrame: NSRect
    ) -> NSRect {
        switch self {
        case .notch:
            return NSRect(
                x: anchor.x - size.width / 2,
                y: anchor.y - size.height,
                width: size.width,
                height: size.height
            )
        case .topBar:
            var minX = anchor.x - size.width / 2
            var minY = anchor.y - size.height

            if minX + size.width > screenVisibleFrame.maxX {
                minX = screenVisibleFrame.maxX - size.width
            }
            if minX < screenVisibleFrame.minX {
                minX = screenVisibleFrame.minX
            }
            if minY < screenVisibleFrame.minY {
                minY = screenVisibleFrame.minY
            }

            return NSRect(x: minX, y: minY, width: size.width, height: size.height)
        }
    }

    /// Rect used for pointer hit-testing the closed shell (click-through
    /// region). It intentionally mirrors `frame(anchor:size:...)` at the
    /// closed size, independent of any opened-state allowance, so hover
    /// and click detection stay aligned with the visible surface.
    func closedHitRect(
        anchor: NSPoint,
        closedWidth: CGFloat,
        closedHeight: CGFloat
    ) -> NSRect {
        NSRect(
            x: anchor.x - closedWidth / 2,
            y: anchor.y - closedHeight,
            width: closedWidth,
            height: closedHeight
        )
    }

    /// Translation offset applied to the closing animation surface so the
    /// opened panel collapses onto the correct closed position. Notch
    /// placement returns `.zero` because the closed anchor is already
    /// colocated with the opened anchor; top-bar placement has to compute
    /// a delta because the opened panel is wider and centered, while the
    /// closed pill rides on the stored drag anchor plus shadow insets.
    func closeTransitionSurfaceOffset(
        currentPanelFrame: NSRect,
        targetClosedPanelFrame: NSRect,
        closedSurfaceSize: NSSize,
        targetClosedShadowInsets: (horizontal: CGFloat, bottom: CGFloat)
    ) -> CGSize {
        switch self {
        case .notch:
            return .zero
        case .topBar:
            let defaultX = (currentPanelFrame.width - closedSurfaceSize.width) / 2
            let defaultY = currentPanelFrame.height - closedSurfaceSize.height
            let targetX = (targetClosedPanelFrame.minX + targetClosedShadowInsets.horizontal) - currentPanelFrame.minX
            let targetY = (targetClosedPanelFrame.minY + targetClosedShadowInsets.bottom) - currentPanelFrame.minY

            return CGSize(
                width: targetX - defaultX,
                height: targetY - defaultY
            )
        }
    }
}
