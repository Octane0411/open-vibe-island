import SwiftUI

/// A drop shadow expressed as data rather than a pre-applied modifier, so a
/// theme can declare one and any view can apply it.
struct IslandShadowToken: Equatable, Sendable {
    /// Base shadow colour, before `opacity` is applied.
    var color: Color

    /// Opacity applied to `color`.
    var opacity: Double

    /// Blur radius passed to `View.shadow(color:radius:x:y:)`.
    var radius: CGFloat

    /// Vertical offset passed to `View.shadow(color:radius:x:y:)`.
    var yOffset: CGFloat

    /// `color` with `opacity` folded in — the value handed to `.shadow(...)`.
    var resolvedColor: Color {
        color.opacity(opacity)
    }
}

/// Geometry half of the island theme token layer.
///
/// Values were lifted verbatim from `NotchShape`'s opened-state radii,
/// `IslandChromeMetrics`' shadow insets and hover scale, and the opened
/// surface's shadow in `IslandPanelView` — the last of which now exists only
/// here (AB-295). The shadow insets and hover scale still have un-migrated
/// `IslandChromeMetrics` call sites; later tickets route the rest.
struct IslandMetricsTokens: Equatable, Sendable {
    /// Concave top-corner radius of the opened island shape.
    var openedTopRadius: CGFloat

    /// Rounded bottom-corner radius of the opened island shape.
    var openedBottomRadius: CGFloat

    /// Drop shadow cast by the opened island surface.
    var surfaceShadow: IslandShadowToken

    /// Horizontal padding the opened shadow needs inside the overlay window
    /// so it is not clipped.
    var openedShadowHorizontalInset: CGFloat

    /// Bottom padding the opened shadow needs inside the overlay window.
    var openedShadowBottomInset: CGFloat

    /// Horizontal padding reserved for the closed pill's shadow.
    var closedShadowHorizontalInset: CGFloat

    /// Bottom padding reserved for the closed pill's shadow.
    var closedShadowBottomInset: CGFloat

    /// Scale applied to the closed pill while the pointer hovers it.
    var closedHoverScale: CGFloat

    /// Concave fillet radius at the notch junction of the opened (`.notch`)
    /// profile — the "poured" curve that merges the black stem into the panel
    /// body. `0` reproduces the plain concave top corner Classic ships; a
    /// positive value deepens and softens the transition. Ignored by the
    /// top-bar profile, which has no physical notch to merge with.
    var filletRadius: CGFloat
}

// MARK: - Classic

extension IslandMetricsTokens {
    /// Today's shipping geometry, expressed as literals so the token layer is
    /// self-contained once the legacy constants are retired.
    static let classic = IslandMetricsTokens(
        openedTopRadius: 22,
        openedBottomRadius: 22,
        surfaceShadow: IslandShadowToken(
            color: .black,
            opacity: 0.36,
            radius: 22,
            yOffset: 12
        ),
        openedShadowHorizontalInset: 18,
        openedShadowBottomInset: 22,
        closedShadowHorizontalInset: 12,
        closedShadowBottomInset: 14,
        closedHoverScale: 1.028,
        filletRadius: 0
    )
}

// MARK: - Flight Deck

extension IslandMetricsTokens {
    /// Flight Deck's chrome: a tightly-cut annunciator panel. The opened radii
    /// are small (a hair tighter than Instrument's 8pt) so the corners read as
    /// *chamfered* — a cut instrument bezel rather than a soft "poured" curve —
    /// while `filletRadius` stays `0`, the plain concave top corner, so the panel
    /// still merges cleanly from the physical notch and morphs from the closed
    /// pill in both display profiles. The drop shadow is crisp and shallow: an
    /// avionics panel is seated in the airframe, it does not float. The shadow
    /// insets match Classic's, which already contain the tighter blur, so
    /// `OverlayPanelController`'s window sizing never clips the chrome.
    static let flightDeck = IslandMetricsTokens(
        openedTopRadius: 6,
        openedBottomRadius: 6,
        surfaceShadow: IslandShadowToken(
            color: .black,
            opacity: 0.42,
            radius: 14,
            yOffset: 7
        ),
        openedShadowHorizontalInset: 18,
        openedShadowBottomInset: 22,
        closedShadowHorizontalInset: 12,
        closedShadowBottomInset: 14,
        closedHoverScale: 1.028,
        filletRadius: 0
    )
}

// MARK: - Poured Island

extension IslandMetricsTokens {
    /// Poured Island's chrome: slightly larger opened radii, a concave notch
    /// fillet, and a deeper/softer drop shadow. The shadow insets grow to
    /// match so the larger blur is never clipped inside the overlay window —
    /// these flow into `OverlayPanelController`'s panel sizing.
    static let poured = IslandMetricsTokens(
        openedTopRadius: 26,
        openedBottomRadius: 26,
        surfaceShadow: IslandShadowToken(
            color: .black,
            opacity: 0.5,
            radius: 34,
            yOffset: 18
        ),
        openedShadowHorizontalInset: 28,
        openedShadowBottomInset: 34,
        closedShadowHorizontalInset: 16,
        closedShadowBottomInset: 18,
        closedHoverScale: 1.03,
        filletRadius: 12
    )
}

// MARK: - Instrument

extension IslandMetricsTokens {
    /// Instrument's chrome: a squared-off panel (small opened radii instead of
    /// Classic's soft 22pt) that still merges cleanly from the notch via the
    /// plain concave top corner — `filletRadius` stays `0`, the Classic path, so
    /// there is no "poured" fillet. The drop shadow is crisp and restrained
    /// rather than the deep soft bloom Poured casts: a flat instrument sits on
    /// the wallpaper, it does not float above it. The shadow insets match
    /// Classic's, which already comfortably contain the tighter blur, so panel
    /// sizing in `OverlayPanelController` never clips the chrome.
    static let instrument = IslandMetricsTokens(
        openedTopRadius: 8,
        openedBottomRadius: 8,
        surfaceShadow: IslandShadowToken(
            color: .black,
            opacity: 0.4,
            radius: 16,
            yOffset: 8
        ),
        openedShadowHorizontalInset: 18,
        openedShadowBottomInset: 22,
        closedShadowHorizontalInset: 12,
        closedShadowBottomInset: 14,
        closedHoverScale: 1.028,
        filletRadius: 0
    )
}
