import CoreGraphics

/// Shadow headroom reserved inside the overlay window, per axis.
///
/// The overlay window is deliberately larger than the surface it draws: the
/// extra ring of transparent pixels is where the surface's drop shadow (and,
/// for themes that opt into one, the closed pill's glow) lands. Nothing inside
/// that ring is interactive — `OverlayPanelController.contentRect(for:in:)`
/// deducts exactly these insets when answering hit tests.
struct IslandChromeInsets: Equatable, Sendable {
    /// Padding reserved on the leading *and* trailing edge (each side).
    var horizontal: CGFloat

    /// Padding reserved below the surface.
    var bottom: CGFloat

    static let zero = IslandChromeInsets(horizontal: 0, bottom: 0)
}

/// The single source of truth for overlay-window chrome geometry (AB-320).
///
/// Before this existed, `OverlayPanelController` sized the window from the live
/// theme's metric tokens while `IslandPanelView` padded its content with the
/// legacy `IslandChromeMetrics` statics. Any theme whose insets differed from
/// Classic's therefore rendered a surface that was wider than intended and
/// whose outer edge fell outside the controller's hit-test rect. Both sides now
/// route through these pure functions, so window size, content padding and hit
/// testing cannot drift apart.
///
/// Everything here is a pure function of the theme's `IslandMetricsTokens` plus
/// the screen/window width — no AppKit, no view state — precisely so it can be
/// exercised directly in tests.
enum IslandChromeLayout {
    /// Floor on the opened surface's content width. Matches the existing
    /// `max(360, …)` clamp in `OverlayPanelController.openedPanelWidth(for:)`:
    /// the window may spill past the screen before content is squeezed below
    /// this.
    static let minimumContentWidth: CGFloat = 360

    // MARK: - Reserved headroom

    /// Headroom a theme needs on each axis, taking the *worst case* of its
    /// opened and closed states.
    ///
    /// The overlay window is always kept at opened size (it never resizes
    /// between states), so a theme whose closed-pill glow is louder than its
    /// opened drop shadow — Halo, per `SPEC-halo` §1b — would otherwise have
    /// that glow clipped by the window edge. Taking the per-axis maximum grows
    /// the window instead. Every shipped theme declares closed insets smaller
    /// than its opened ones, so this is a no-op for all five of them.
    static func reservedInsets(for metrics: IslandMetricsTokens) -> IslandChromeInsets {
        IslandChromeInsets(
            horizontal: max(metrics.openedShadowHorizontalInset, metrics.closedShadowHorizontalInset),
            bottom: max(metrics.openedShadowBottomInset, metrics.closedShadowBottomInset)
        )
    }

    // MARK: - Window sizing

    /// Content width actually used, after reserving shadow headroom inside
    /// `availableWidth` (the screen's visible width).
    ///
    /// Reserving comes first so the *window* — not just the surface — fits on
    /// screen; the content only gives way once the reservation would push the
    /// window past the screen edge, and never below `minimumContentWidth`.
    static func contentWidth(
        preferred: CGFloat,
        metrics: IslandMetricsTokens,
        availableWidth: CGFloat
    ) -> CGFloat {
        let reserved = reservedInsets(for: metrics).horizontal
        let widest = max(minimumContentWidth, availableWidth - (reserved * 2))
        return max(minimumContentWidth, min(preferred, widest))
    }

    /// Full overlay-window size for a theme, given the content it has to hold.
    ///
    /// The width is clamped so the window never exceeds `availableWidth`;
    /// clamping eats into the reserved insets symmetrically (both sides
    /// equally) and only starts shrinking content once the insets are gone.
    static func windowSize(
        preferredContentWidth: CGFloat,
        contentHeight: CGFloat,
        metrics: IslandMetricsTokens,
        availableWidth: CGFloat
    ) -> CGSize {
        let content = contentWidth(
            preferred: preferredContentWidth,
            metrics: metrics,
            availableWidth: availableWidth
        )
        let reserved = reservedInsets(for: metrics)
        let horizontal = min(reserved.horizontal, max(0, (availableWidth - content) / 2))
        return CGSize(
            width: content + (horizontal * 2),
            height: max(0, contentHeight) + reserved.bottom
        )
    }

    // MARK: - Window → insets

    /// The insets actually in force inside a window of `windowWidth`.
    ///
    /// This is the exact inverse of `windowSize(…)`: feeding a window produced
    /// by that function back through here returns the insets it was built with,
    /// including the degenerate case where the screen was too narrow and the
    /// insets had to be trimmed. That round-trip is what lets
    /// `IslandPanelView` derive its padding from nothing but the geometry it is
    /// handed, while `OverlayPanelController` derives its hit-test rect from the
    /// window frame — with both landing on the same numbers.
    static func insets(forWindowWidth windowWidth: CGFloat, metrics: IslandMetricsTokens) -> IslandChromeInsets {
        let reserved = reservedInsets(for: metrics)
        return IslandChromeInsets(
            horizontal: min(reserved.horizontal, max(0, (windowWidth - minimumContentWidth) / 2)),
            bottom: reserved.bottom
        )
    }

    /// The interactive rect inside an overlay window: the window minus its
    /// shadow headroom. Callers pass either the panel's screen frame or the
    /// hosting view's bounds — only the size is consulted for the insets, so
    /// both coordinate spaces work.
    static func contentRect(in bounds: CGRect, metrics: IslandMetricsTokens) -> CGRect {
        let insets = insets(forWindowWidth: bounds.width, metrics: metrics)
        return CGRect(
            x: bounds.minX + insets.horizontal,
            y: bounds.minY + insets.bottom,
            width: max(0, bounds.width - (insets.horizontal * 2)),
            height: max(0, bounds.height - insets.bottom)
        )
    }

    /// The rect the island surface actually renders into, in the top-left-origin
    /// space SwiftUI lays out in (`IslandPanelView`'s `GeometryReader`).
    ///
    /// This is `contentRect(in:metrics:)`'s sibling: same rectangle, opposite
    /// vertical convention. The view sizes its surface from this while
    /// `OverlayPanelController` answers hit tests from `contentRect`, so the two
    /// are the same numbers by construction — `IslandChromeLayoutTests` pins the
    /// flip so a change to one without the other fails.
    static func surfaceRect(inWindowOfSize windowSize: CGSize, metrics: IslandMetricsTokens) -> CGRect {
        let insets = insets(forWindowWidth: windowSize.width, metrics: metrics)
        return CGRect(
            x: insets.horizontal,
            y: 0,
            width: max(0, windowSize.width - (insets.horizontal * 2)),
            height: max(0, windowSize.height - insets.bottom)
        )
    }

    // MARK: - Closed pill placement

    /// Where the closed pill's surface sits inside an overlay window that is
    /// held at opened size, in top-left-origin coordinates (the SwiftUI space
    /// `IslandPanelView` lays out in): horizontally centred, flush with the top
    /// of the content area.
    ///
    /// Exposed so the closed-state glow headroom can be asserted directly —
    /// see `closedSurfaceHeadroom(windowSize:closedSize:)`.
    static func closedSurfaceRect(inWindowOfSize windowSize: CGSize, closedSize: CGSize) -> CGRect {
        CGRect(
            x: (windowSize.width - closedSize.width) / 2,
            y: 0,
            width: closedSize.width,
            height: closedSize.height
        )
    }

    /// Free space between the closed pill and each window edge that a
    /// view-level `.shadow` can bleed into before the window clips it.
    ///
    /// `top` is reported for completeness but is structurally `0`: the overlay
    /// window's top edge is the physical screen top, so nothing can ever bleed
    /// above the pill. The closed glow is designed to spread sideways and down.
    static func closedSurfaceHeadroom(
        windowSize: CGSize,
        closedSize: CGSize
    ) -> (top: CGFloat, horizontal: CGFloat, bottom: CGFloat) {
        let rect = closedSurfaceRect(inWindowOfSize: windowSize, closedSize: closedSize)
        return (
            top: rect.minY,
            horizontal: max(0, rect.minX),
            bottom: max(0, windowSize.height - rect.maxY)
        )
    }
}
