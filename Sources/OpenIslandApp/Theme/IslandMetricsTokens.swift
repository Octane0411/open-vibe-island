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

/// Applies an `IslandShadowToken` only when the theme declares one, leaving the
/// render tree of themes that don't completely untouched.
struct OptionalShadow: ViewModifier {
    var token: IslandShadowToken?

    func body(content: Content) -> some View {
        if let token {
            content.shadow(color: token.resolvedColor, radius: token.radius, y: token.yOffset)
        } else {
            content
        }
    }
}

/// Geometry half of the island theme token layer.
///
/// Values were lifted verbatim from `NotchShape`'s opened-state radii,
/// `IslandChromeMetrics`' shadow insets and hover scale, and the opened
/// surface's shadow in `IslandPanelView` — the last of which now exists only
/// here (AB-295). AB-320 routed the remaining `IslandChromeMetrics` call sites
/// (content padding, hover scale) through these tokens too, so this struct is
/// now the sole definition of the overlay's chrome geometry; the legacy enum
/// survives only as the Classic drift pin. `IslandChromeLayout` turns these
/// values into the actual window / content / hit-test rects.
struct IslandMetricsTokens: Equatable, Sendable {
    /// Concave top-corner radius of the opened island shape.
    var openedTopRadius: CGFloat

    /// Rounded bottom-corner radius of the opened island shape.
    var openedBottomRadius: CGFloat

    /// Drop shadow cast by the opened island surface.
    var surfaceShadow: IslandShadowToken

    /// Optional drop shadow cast by the *closed* pill surface — the seam a
    /// theme uses to declare a closed-state glow (AB-320).
    ///
    /// `nil` — the default, and the value every shipped theme uses — means the
    /// closed pill casts nothing at all, which is exactly what the morph used
    /// to hard-code. Opting in also requires the window to have room for the
    /// glow: size `closedShadowHorizontalInset` / `closedShadowBottomInset` to
    /// contain it, since `IslandChromeLayout.reservedInsets(for:)` grows the
    /// overlay window from those tokens.
    var closedSurfaceShadow: IslandShadowToken? = nil

    /// Horizontal padding the opened shadow needs inside the overlay window
    /// so it is not clipped.
    var openedShadowHorizontalInset: CGFloat

    /// Bottom padding the opened shadow needs inside the overlay window.
    var openedShadowBottomInset: CGFloat

    /// Horizontal padding reserved for the closed pill's shadow. Since AB-320
    /// this is live: `IslandChromeLayout.reservedInsets(for:)` takes the max of
    /// it and `openedShadowHorizontalInset`, so a theme whose closed glow is
    /// louder than its opened shadow grows the overlay window rather than
    /// getting clipped by it.
    var closedShadowHorizontalInset: CGFloat

    /// Bottom padding reserved for the closed pill's shadow. Same max-with-
    /// opened treatment as `closedShadowHorizontalInset`.
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

extension IslandMetricsTokens {
    /// `closedSurfaceShadow`, or an inert shadow when the theme declares none.
    ///
    /// The fallback deliberately keeps `surfaceShadow`'s base colour and only
    /// zeroes opacity/radius/offset, so the open↔closed morph interpolates
    /// between two shadows of the same hue instead of snapping through a colour
    /// change. With the default `nil` this reproduces the previously hard-coded
    /// "closed casts nothing" behaviour exactly.
    var resolvedClosedSurfaceShadow: IslandShadowToken {
        closedSurfaceShadow ?? IslandShadowToken(
            color: surfaceShadow.color,
            opacity: 0,
            radius: 0,
            yOffset: 0
        )
    }
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

// MARK: - Annual

extension IslandMetricsTokens {
    /// Annual's chrome: a quiet editorial surface. The opened radii are modest —
    /// softer than Flight Deck's cut chamfer, tighter than Poured's glass curve —
    /// so the panel reads as a calmly rounded card rather than either a razor
    /// bezel or a molten slab, while `filletRadius` stays `0` (the plain concave
    /// top corner, the Classic path) so the surface still merges cleanly from the
    /// physical notch and morphs from the closed pill in both display profiles.
    /// The drop shadow is soft but restrained — the page sits on the desktop, it
    /// does not float. The shadow insets match Classic's, which already contain
    /// the blur, so `OverlayPanelController`'s window sizing never clips the chrome.
    static let annual = IslandMetricsTokens(
        openedTopRadius: 12,
        openedBottomRadius: 12,
        surfaceShadow: IslandShadowToken(
            color: .black,
            opacity: 0.32,
            radius: 20,
            yOffset: 10
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
