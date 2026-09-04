import SwiftUI
import Testing
@testable import OpenIslandApp

struct OpenedIslandSurfaceShapeTests {
    @Test
    func bothCornerRadiiParticipateInTheMorphAnimation() {
        var shape = OpenedIslandSurfaceShape(
            topProfile: .notch,
            topCornerRadius: 0,
            bottomCornerRadius: 16
        )

        shape.animatableData = AnimatablePair(22, 22)

        #expect(shape.topCornerRadius == 22)
        #expect(shape.bottomCornerRadius == 22)
    }
}
