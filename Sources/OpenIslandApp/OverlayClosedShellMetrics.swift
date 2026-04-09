import CoreGraphics

struct OverlayClosedShellMetrics: Equatable {
    enum LayoutFamily: Equatable {
        case notch
        case floatingPill
    }

    let mode: OverlayPlacementMode
    let closedHeight: CGFloat
    let openedHeaderHeight: CGFloat
    let iconSize: CGFloat
    let horizontalPadding: CGFloat
    let badgeSpacing: CGFloat
    let attentionIndicatorSize: CGFloat

    var isFloatingPill: Bool {
        mode == .topBar
    }

    var layoutFamily: LayoutFamily {
        isFloatingPill ? .floatingPill : .notch
    }

    static func openedHeaderAllowance(forClosedHeight closedHeight: CGFloat) -> CGFloat {
        max(closedHeight, 30)
    }

    static func forMode(
        _ mode: OverlayPlacementMode,
        closedHeight: CGFloat
    ) -> OverlayClosedShellMetrics {
        switch mode {
        case .notch:
            return OverlayClosedShellMetrics(
                mode: .notch,
                closedHeight: closedHeight,
                openedHeaderHeight: openedHeaderAllowance(forClosedHeight: closedHeight),
                iconSize: 14,
                horizontalPadding: 0,
                badgeSpacing: 4,
                attentionIndicatorSize: 14
            )
        case .topBar:
            return OverlayClosedShellMetrics(
                mode: .topBar,
                closedHeight: closedHeight,
                openedHeaderHeight: openedHeaderAllowance(forClosedHeight: closedHeight),
                iconSize: 12,
                horizontalPadding: 8,
                badgeSpacing: 4,
                attentionIndicatorSize: 10
            )
        }
    }
}
