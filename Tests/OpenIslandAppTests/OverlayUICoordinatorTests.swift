import Testing
@testable import OpenIslandApp

struct OverlayUICoordinatorTests {
    @Test
    func openedTopBarCloseDefersFrameSyncWhenPanelExists() {
        let plan = OverlayUICoordinator.closeTransitionPlan(
            previousStatus: .opened,
            targetStatus: .closed,
            mode: .topBar,
            hasPanel: true
        )

        #expect(plan == .deferTopBarFrameSync)
    }

    @Test
    func closedTopBarWithoutPanelDoesNotDeferFrameSync() {
        let plan = OverlayUICoordinator.closeTransitionPlan(
            previousStatus: .opened,
            targetStatus: .closed,
            mode: .topBar,
            hasPanel: false
        )

        #expect(plan == .immediate)
    }

    @Test
    func closedTopBarPointerInteractionDefersPlacementRefresh() {
        let plan = OverlayUICoordinator.placementRefreshPlan(
            status: .closed,
            defersForClosedTopBarPointerInteraction: true
        )

        #expect(plan == .deferred)
    }

    @Test
    func openedOverlayStillRefreshesDuringPointerInteraction() {
        let plan = OverlayUICoordinator.placementRefreshPlan(
            status: .opened,
            defersForClosedTopBarPointerInteraction: true
        )

        #expect(plan == .refresh)
    }

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
