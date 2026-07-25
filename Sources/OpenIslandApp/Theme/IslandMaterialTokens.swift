import AppKit
import SwiftUI

/// A bright specular highlight painted along the top edge of a frosted
/// surface, expressed as data so a theme can declare one and the surface view
/// can apply it. `nil` on a theme means "no specular" — the flat, unlit look
/// Classic ships.
struct IslandSpecularEdge: Equatable, Sendable {
    /// Highlight colour, before `opacity` is applied.
    var color: Color

    /// Peak opacity of the highlight at the very top edge.
    var opacity: Double

    /// Height of the soft sheen that falls off below the crisp top line.
    var sheenHeight: CGFloat
}

/// Material half of the island theme token layer (AB-300).
///
/// The opened surface's vibrancy was hardcoded in `OpenedSurfaceMaterial.swift`
/// as `.hudWindow` / `.behindWindow` / `.vibrantDark` with a fixed `0.6` ink
/// tint and no specular edge. A liquid-glass theme needs its own material
/// family, a lighter tint so more of the blur reads through, and a specular
/// top edge — so those values move here, one axis per theme, exactly like the
/// colour / metric / motion axes.
///
/// The `NSVisualEffectView` enums are plain value types, so this struct stays
/// `Equatable` + `Sendable` like the rest of the token layer. The ink tint
/// itself is not stored here — it's derived from `IslandColorTokens.surfaceInk`
/// at the call site so the surface keeps one source of truth for its ink — only
/// the *opacity* of that tint lives here.
struct IslandMaterialTokens: Equatable, Sendable {
    /// `NSVisualEffectView.material` for the frosted base.
    var material: NSVisualEffectView.Material

    /// `NSVisualEffectView.blendingMode`.
    var blendingMode: NSVisualEffectView.BlendingMode

    /// Forced appearance for the effect view, or `nil` to inherit.
    var appearanceName: NSAppearance.Name?

    /// Opacity of the `surfaceInk` tint painted over the vibrancy to hold the
    /// surface's identity and text contrast against bright wallpapers.
    var tintOpacity: Double

    /// Specular top edge, or `nil` for a flat, unlit surface (Classic).
    var specularTopEdge: IslandSpecularEdge?
}

// MARK: - Classic

extension IslandMaterialTokens {
    /// Today's shipping vibrancy: the `.hudWindow` HUD family sampling what's
    /// behind the window, tinted `0.6` toward ink, with no specular edge.
    /// Lifted verbatim from `OpenedSurfaceMaterial.swift`.
    static let classic = IslandMaterialTokens(
        material: .hudWindow,
        blendingMode: .behindWindow,
        appearanceName: .vibrantDark,
        tintOpacity: 0.6,
        specularTopEdge: nil
    )
}

// MARK: - Poured Island

extension IslandMaterialTokens {
    /// Poured Island's frosted slab: the same always-dark HUD family, but a
    /// lighter ink tint so more of the heavy blur reads through as glass, plus
    /// a bright specular top edge so hierarchy is carried by light rather than
    /// by chrome.
    static let poured = IslandMaterialTokens(
        material: .hudWindow,
        blendingMode: .behindWindow,
        appearanceName: .vibrantDark,
        tintOpacity: 0.5,
        specularTopEdge: IslandSpecularEdge(
            color: .white,
            opacity: 0.5,
            sheenHeight: 26
        )
    )
}

// MARK: - Instrument

extension IslandMaterialTokens {
    /// Instrument is a flat panel, not glass: `InstrumentTheme.usesVibrancy` is
    /// `false`, so `OpenedSurfaceBackground` takes the opaque `surfaceInk` path
    /// and never instantiates a vibrancy view. These values are the fallback the
    /// surface would use if vibrancy were ever forced on — a fully opaque ink
    /// tint (`1.0`) and no specular edge, i.e. the same flat, unlit readout even
    /// then. Reduce Transparency is therefore a no-op for this theme: the surface
    /// is already flat.
    static let instrument = IslandMaterialTokens(
        material: .hudWindow,
        blendingMode: .behindWindow,
        appearanceName: .vibrantDark,
        tintOpacity: 1.0,
        specularTopEdge: nil
    )
}
