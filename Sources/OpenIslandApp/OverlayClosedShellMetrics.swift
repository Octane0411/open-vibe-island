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

    func closedSurfaceWidth(
        baseClosedWidth: CGFloat,
        liveCount: Int,
        hasAttention: Bool,
        isPopping: Bool
    ) -> CGFloat {
        let popWidth: CGFloat = isPopping ? 18 : 0

        guard liveCount > 0 else {
            return baseClosedWidth + popWidth
        }

        let badgeWidth = Self.closedBadgeWidth(forLiveCount: liveCount)

        switch layoutFamily {
        case .floatingPill:
            let attentionWidth = hasAttention ? badgeSpacing + attentionIndicatorSize : 0
            let contentWidth = (horizontalPadding * 2)
                + iconSize
                + badgeSpacing
                + badgeWidth
                + attentionWidth
            return max(baseClosedWidth, contentWidth) + popWidth
        case .notch:
            let sideWidth = max(0, closedHeight - 12) + 10
            let leftWidth = sideWidth + 8 + (hasAttention ? 18 : 0)
            let rightWidth = max(sideWidth, badgeWidth)
            let expansionWidth = leftWidth + rightWidth + 16 + (hasAttention ? 6 : 0)
            return baseClosedWidth + expansionWidth + popWidth
        }
    }

    static func openedHeaderAllowance(forClosedHeight closedHeight: CGFloat) -> CGFloat {
        max(closedHeight, 30)
    }

    private static func closedBadgeWidth(forLiveCount liveCount: Int) -> CGFloat {
        let digits = max(1, "\(liveCount)".count)
        return CGFloat(26 + max(0, digits - 1) * 8)
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
