import CoreGraphics

struct OverlayClosedShellMetrics: Equatable {
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

    static func forMode(
        _ mode: OverlayPlacementMode,
        closedHeight: CGFloat,
        liveCountDigits _: Int,
        showsAttention _: Bool
    ) -> OverlayClosedShellMetrics {
        switch mode {
        case .notch:
            return OverlayClosedShellMetrics(
                mode: .notch,
                closedHeight: closedHeight,
                openedHeaderHeight: max(closedHeight, 30),
                iconSize: 14,
                horizontalPadding: 0,
                badgeSpacing: 4,
                attentionIndicatorSize: 14
            )
        case .topBar:
            return OverlayClosedShellMetrics(
                mode: .topBar,
                closedHeight: closedHeight,
                openedHeaderHeight: max(closedHeight, 30),
                iconSize: 12,
                horizontalPadding: 8,
                badgeSpacing: 4,
                attentionIndicatorSize: 10
            )
        }
    }
}
