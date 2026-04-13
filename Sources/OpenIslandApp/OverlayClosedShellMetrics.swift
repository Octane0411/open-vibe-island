import CoreGraphics

/// Pure-value description of the closed pill/island shell at a given
/// placement mode.
///
/// Two concrete layout families are modeled:
///
/// - `.notch`: the traditional Dynamic-Island-style shell that expands
///   horizontally around the physical notch with left/right "lanes" for
///   the icon and live-session count badge.
/// - `.floatingPill`: a compact capsule used on external and non-notch
///   displays. Content is laid out in a single padded `HStack` with a
///   smaller icon and indicator footprint.
///
/// Metrics are derived from the closed height so that the same struct can
/// drive both AppKit panel sizing (`OverlayPanelController`) and SwiftUI
/// closed-shell views (`Views/OverlayClosedShells.swift`) without the two
/// sides drifting. All methods are pure and deterministic for unit
/// testing.
struct OverlayClosedShellMetrics: Equatable {
    /// Which visual family the closed shell belongs to. Callers branch on
    /// this rather than `mode` directly when they only care about
    /// notch-style lane layout vs. floating pill layout.
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

    /// Width of the closed shell's visible surface for the given live-session
    /// state. The returned value includes any popping animation growth and,
    /// for the notch family, the left/right lane expansion around the
    /// physical notch. `liveCount == 0` collapses to `baseClosedWidth`
    /// (plus popping width) because no badge needs to be rendered.
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

    /// Minimum vertical allowance for the opened-state header. Notch-style
    /// shells pass their physical closed height through, while pill-style
    /// shells need a 30pt floor so the header hit-area stays tappable even
    /// when the closed pill is shorter than 30pt.
    static func openedHeaderAllowance(forClosedHeight closedHeight: CGFloat) -> CGFloat {
        max(closedHeight, 30)
    }

    private static func closedBadgeWidth(forLiveCount liveCount: Int) -> CGFloat {
        let digits = max(1, "\(liveCount)".count)
        return CGFloat(26 + max(0, digits - 1) * 8)
    }

    /// Builds the concrete metrics for the given placement mode. Height is
    /// the only runtime input — everything else (icon size, padding,
    /// indicator size) is fixed per family to keep closed-shell layout
    /// deterministic and visually consistent.
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
