import AppKit
import SwiftUI

/// Thin `NSVisualEffectView` wrapper providing a themed vibrancy base (AB-242,
/// AB-300). The material / blending / appearance are supplied by the active
/// theme's `IslandMaterialTokens` rather than hardcoded, so a liquid-glass
/// theme can pick its own family without every surface knowing about it.
///
/// Classic keeps the same `.hudWindow` / `.behindWindow` / `.vibrantDark`
/// configuration it always shipped — the HUD family is always dark and always
/// translucent regardless of system light/dark mode, matching this app's forced
/// `.dark` `preferredColorScheme`, and `.behindWindow` samples whatever sits
/// behind the panel so the overlay reads as a native blurred surface.
private struct VibrancyView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var appearanceName: NSAppearance.Name?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // Reapply so a live theme switch retargets the effect view.
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.appearance = appearanceName.map { NSAppearance(named: $0) } ?? nil
    }
}

/// The bright specular highlight painted along a frosted surface's top edge
/// (AB-300): a crisp near-opaque line at the very top fading into a soft sheen
/// below. Clipped by the caller to the surface shape, so it follows the
/// concave/filleted top rather than a plain rectangle.
struct OpenedSurfaceSpecularEdge: View {
    var edge: IslandSpecularEdge

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: edge.color.opacity(edge.opacity), location: 0),
                .init(color: edge.color.opacity(edge.opacity * 0.35), location: 0.14),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: edge.sheenHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

/// A crisp, near-solid hard specular line painted along the very top edge of a
/// frosted surface (AB-329) — the sharp light-catch that reads *in addition to*
/// the soft `OpenedSurfaceSpecularEdge` sheen. Reuses `IslandSpecularEdge`,
/// reading `sheenHeight` as the line's thickness (Poured: 1pt). Clipped by the
/// caller to the surface shape, exactly like the soft sheen.
struct OpenedSurfaceHardSpecularLine: View {
    var edge: IslandSpecularEdge

    var body: some View {
        Rectangle()
            .fill(edge.color.opacity(edge.opacity))
            .frame(height: edge.sheenHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }
}

/// A faint white inner inset stroke drawn just inside a frosted surface's edge
/// (AB-329). `Shape.strokeBorder` keeps the whole stroke *inside* the bounds, so
/// once the caller clips this to the surface shape it lands as a thin hairline
/// hugging the inner edge along the surface's straight runs (the concave notch
/// dip is trimmed by that same clip). White by design — it belongs to the same
/// specular light-catch family as the two edges above.
struct OpenedSurfaceInnerHairline: View {
    var hairline: IslandHairlineToken

    var body: some View {
        Rectangle()
            .strokeBorder(Color.white.opacity(hairline.opacity), lineWidth: hairline.width)
            .allowsHitTesting(false)
    }
}

/// Opened-surface fill (AB-242, AB-300): themed vibrancy tinted toward the
/// theme's `surfaceInk`, topped with the theme's specular edge, so the surface
/// reads as translucent native glass instead of a flat slab. Falls back to a
/// flat `surfaceInk` fill whenever `reduceTransparency` is set (or the theme
/// opts out of vibrancy) — pass in `@Environment(\.accessibilityReduceTransparency)`,
/// which SwiftUI keeps current as the user toggles System Settings →
/// Accessibility → Display → Reduce Transparency.
struct OpenedSurfaceBackground: View {
    var reduceTransparency: Bool

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        if reduceTransparency {
            // Flat, opaque, legible — no glass, no specular sheen.
            tokens.colors.surfaceInk
        } else {
            let material = tokens.material
            ZStack {
                VibrancyView(
                    material: material.material,
                    blendingMode: material.blendingMode,
                    appearanceName: material.appearanceName
                )

                // Fill over the vibrancy: a theme's multi-stop body gradient
                // (inner-luminance elevation, lighter top → darker bottom) when
                // it declares one, else the flat `surfaceInk` tint. Either way it
                // keeps the surface's ink identity and text contrast intact over
                // both bright and dark wallpapers — the blur alone would let a
                // light wallpaper wash the panel out. `nil` gradient ⇒ the flat
                // fill every other theme renders today, byte for byte.
                if let stops = material.bodyGradient {
                    LinearGradient(
                        stops: stops.map {
                            Gradient.Stop(color: $0.resolvedColor, location: $0.location)
                        },
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    tokens.colors.surfaceInk.opacity(material.tintOpacity)
                }

                // Light-carried edge layers, painted only on the glass path (this
                // whole branch is skipped under Reduce Transparency, so all three
                // skip with it — matching the soft sheen's existing gate exactly):
                // the soft sheen (unchanged), then the crisp hard top line on top
                // of it, then the faint inner hairline. Each is `nil` for every
                // theme but Poured, so those surfaces are untouched.
                if let specular = material.specularTopEdge {
                    OpenedSurfaceSpecularEdge(edge: specular)
                }

                if let hardEdge = material.specularHardEdge {
                    OpenedSurfaceHardSpecularLine(edge: hardEdge)
                }

                if let hairline = material.innerHairline {
                    OpenedSurfaceInnerHairline(hairline: hairline)
                }
            }
        }
    }
}
