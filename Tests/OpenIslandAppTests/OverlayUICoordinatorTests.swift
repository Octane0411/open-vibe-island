import Testing
@testable import OpenIslandApp

struct OverlayUICoordinatorTests {
    @Test
    func closedTopBarRepositionsBeforeEnablingDirectInteraction() {
        let plan = OverlayUICoordinator.interactionUpdatePlan(
            requestedInteractive: false,
            status: .closed,
            mode: .topBar
        )

        #expect(plan == .repositionThenSetInteractive(true))
    }

    @Test
    func closedNotchDoesNotForceFrameSync() {
        let plan = OverlayUICoordinator.interactionUpdatePlan(
            requestedInteractive: false,
            status: .closed,
            mode: .notch
        )

        #expect(plan == .setInteractive(false))
    }
}
