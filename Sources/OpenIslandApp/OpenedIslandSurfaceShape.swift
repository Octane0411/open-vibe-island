import SwiftUI

struct OpenedIslandSurfaceShape: Shape {
    enum TopProfile: Equatable {
        case notch
        case topBar
    }

    var topProfile: TopProfile
    var topCornerRadius: CGFloat = NotchShape.openedTopRadius
    var bottomCornerRadius: CGFloat = NotchShape.openedBottomRadius
    /// Mirror vertically for an island pinned to the bottom screen edge: the
    /// square "notch" profile then faces the bottom and the rounded corners
    /// face up into the screen.
    var flipped: Bool = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let path: Path
        switch topProfile {
        case .notch:
            path = NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .path(in: rect)
        case .topBar:
            path = V6ClosedPillShape(cornerRadius: bottomCornerRadius)
                .path(in: rect)
        }
        return flipped ? path.verticallyMirrored(in: rect) : path
    }
}
