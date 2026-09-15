import SwiftUI

struct OpenedIslandSurfaceShape: Shape {
    enum TopProfile: Equatable {
        case notch
        case topBar
    }

    var topProfile: TopProfile
    var topCornerRadius: CGFloat = NotchShape.openedTopRadius
    var bottomCornerRadius: CGFloat = NotchShape.openedBottomRadius

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        switch topProfile {
        case .notch:
            return NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .path(in: rect)
        case .topBar:
            return V6ClosedPillShape(cornerRadius: bottomCornerRadius)
                .path(in: rect)
        }
    }
}
