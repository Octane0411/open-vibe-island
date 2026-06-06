import SwiftUI

// MARK: - Morphing expand/collapse shape (from Top Notch)
//
// Clip mask that interpolates from the compact pill (progress=0) to the
// fully expanded panel (progress=1). The frame is always the expanded size;
// at progress=0 only the compact-pill rect at the top-centre is visible.

struct GrowingNotchShape: Shape {
    var progress: CGFloat
    var compactW: CGFloat
    var compactH: CGFloat
    var expandedW: CGFloat
    var expandedH: CGFloat
    var compactR: CGFloat = 6
    var expandedR: CGFloat = 22
    /// When set with `compactNotchGapWidth`, anchors the compact clip so the
    /// notch gap lines up with the physical cutout instead of centering the
    /// whole pill (required for asymmetric wings).
    var compactLeftWingWidth: CGFloat = 0
    var compactNotchGapWidth: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, compactW) }
        set {
            progress = newValue.first
            compactW = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = compactW + (expandedW - compactW) * progress
        let h = compactH + (expandedH - compactH) * progress
        let r = compactR + (expandedR - compactR) * progress

        let compactX: CGFloat
        if compactNotchGapWidth > 0 {
            compactX = rect.midX - compactLeftWingWidth - compactNotchGapWidth / 2
        } else {
            compactX = (rect.width - compactW) / 2
        }
        let expandedX = (rect.width - expandedW) / 2
        // Closed: anchor the notch gap to the physical cutout. Open: center the panel.
        let x = compactX + (expandedX - compactX) * progress

        return Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x + w, y: 0))
            p.addLine(to: CGPoint(x: x + w, y: h - r))
            p.addArc(center: CGPoint(x: x + w - r, y: h - r),
                     radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: x + r, y: h))
            p.addArc(center: CGPoint(x: x + r, y: h - r),
                     radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
        }
    }
}

/// Dedicated compact clip for the music track notification. Sized from the
/// pill's live measurements so long titles can extend the left wing without
/// cropping album art. Only used while the notification is visible.
struct MusicNotificationClipShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var leftWingWidth: CGFloat
    var notchGapWidth: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, leftWingWidth) }
        set {
            width = newValue.first
            leftWingWidth = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard width > 0, height > 0 else { return Path() }

        let x: CGFloat
        if notchGapWidth > 0 {
            x = rect.midX - leftWingWidth - notchGapWidth / 2
        } else {
            x = (rect.width - width) / 2
        }

        let pillRect = CGRect(x: x, y: 0, width: width, height: height)
        return V6ClosedPillShape(topFilletRadius: 0).path(in: pillRect)
    }
}

struct NotchSurfaceClipModifier: ViewModifier {
    let usesMusicNotificationClip: Bool
    let musicClipMetrics: MusicNotificationClipMetrics
    let musicNotchGapWidth: CGFloat
    let morphProgress: CGFloat
    let compactW: CGFloat
    let compactH: CGFloat
    let expandedW: CGFloat
    let expandedH: CGFloat
    let compactR: CGFloat
    let compactLeftWingWidth: CGFloat
    let compactNotchGapWidth: CGFloat

    func body(content: Content) -> some View {
        if usesMusicNotificationClip {
            // Closed music surfaces (notification + compact) draw their own
            // V6ClosedPillShape. Parent GrowingNotchShape uses agent wing metrics
            // and misaligns them, which reads as extra side padding.
            content
        } else {
            content.clipShape(
                GrowingNotchShape(
                    progress: morphProgress,
                    compactW: compactW,
                    compactH: compactH,
                    expandedW: expandedW,
                    expandedH: expandedH,
                    compactR: compactR,
                    compactLeftWingWidth: compactLeftWingWidth,
                    compactNotchGapWidth: compactNotchGapWidth
                )
            )
        }
    }
}

// MARK: -

struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let f: CGFloat = 8 // top fillet radius
        let topR = min(topCornerRadius, (rect.width - 2 * f) / 4, rect.height / 4)
        let botR = min(bottomCornerRadius, (rect.width - 2 * f) / 4, rect.height / 2)

        var path = Path()

        // Start at top-left, at the very edge
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left outward concave curve
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + f, y: rect.minY + f),
            control: CGPoint(x: rect.minX + f, y: rect.minY)
        )

        // Top-left inward curve (concave, mimics notch edge)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + f + topR, y: rect.minY + f + topR),
            control: CGPoint(x: rect.minX + f + topR, y: rect.minY + f)
        )

        // Left edge down to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + f + topR, y: rect.maxY - botR))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + f + topR + botR, y: rect.maxY),
            control: CGPoint(x: rect.minX + f + topR, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - f - topR - botR, y: rect.maxY))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - f - topR, y: rect.maxY - botR),
            control: CGPoint(x: rect.maxX - f - topR, y: rect.maxY)
        )

        // Right edge up to top-right inward curve
        path.addLine(to: CGPoint(x: rect.maxX - f - topR, y: rect.minY + f + topR))

        // Top-right inward curve (concave)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - f, y: rect.minY + f),
            control: CGPoint(x: rect.maxX - f - topR, y: rect.minY + f)
        )

        // Top-right outward concave curve
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - f, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}

extension NotchShape {
    /// The opened island uses a concave-top-corner notch shape so it blends
    /// with the physical MacBook notch on built-in displays. The closed
    /// state no longer uses this shape — it renders via `V6ClosedPillShape`
    /// instead.
    static let openedTopRadius: CGFloat = 22
    static let openedBottomRadius: CGFloat = 22

    static var opened: NotchShape {
        NotchShape(topCornerRadius: openedTopRadius, bottomCornerRadius: openedBottomRadius)
    }
}
