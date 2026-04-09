import AppKit

enum OverlayPlacementStrategy: Equatable {
    case notch
    case topBar

    private static let topBarMenuBarGap: CGFloat = 18

    init(mode: OverlayPlacementMode) {
        switch mode {
        case .notch:
            self = .notch
        case .topBar:
            self = .topBar
        }
    }

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

    func frame(
        anchor: NSPoint,
        size: NSSize,
        screenFrame: NSRect,
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
}
