import Testing
@testable import OpenIslandApp

struct OverlayUICoordinatorTests {
    @Test
    @MainActor
    func presentationPolicyDefaultsToAutomaticIslandWhenNotched() {
        let coordinator = OverlayUICoordinator()

        #expect(OverlayPresentationPolicy.defaultValue == .automaticIslandWhenNotched)
        #expect(coordinator.overlayPresentationPolicy == .automaticIslandWhenNotched)
    }

    @Test
    func persistedPresentationPolicyRoundTripsRawValue() {
        let raw = OverlayPresentationPolicy.alwaysPill.rawValue
        let restored = OverlayPresentationPolicy(rawValue: raw)

        #expect(restored == .alwaysPill)
    }

    @Test
    @MainActor
    func applyingDisplayOptionsPreservesMissingManualSelection() {
        let coordinator = OverlayUICoordinator()

        coordinator.overlayDisplaySelectionID = "display-external"
        coordinator.applyOverlayDisplayOptions([
            OverlayDisplayOption(
                id: "display-built-in",
                title: "Built-in Retina Display",
                subtitle: "Built-in notch · 3024×1964"
            )
        ])

        #expect(coordinator.overlayDisplaySelectionID == "display-external")
        #expect(coordinator.overlayDisplayOptions.map(\.id) == ["display-built-in"])
    }

    @Test
    func hoverOpenedTopBarDragStartClosesImmediately() {
        let plan = OverlayUICoordinator.dragStartPlan(
            status: .opened,
            mode: .topBar,
            openReason: .hover
        )

        #expect(plan == .closeImmediatelyForDrag)
    }

    @Test
    func clickOpenedTopBarDragStartDoesNotCloseImmediately() {
        let plan = OverlayUICoordinator.dragStartPlan(
            status: .opened,
            mode: .topBar,
            openReason: .click
        )

        #expect(plan == .keepCurrentState)
    }

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
