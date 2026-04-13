import AppKit
import Testing
@testable import OpenIslandApp

struct OverlayUICoordinatorTests {
    @MainActor
    private func makeDefaultsSuite() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "OpenIslandAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @Test
    @MainActor
    func presentationPolicyDefaultsToAutomaticIslandWhenNotched() {
        let (defaults, suiteName) = makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = OverlayUICoordinator(defaults: defaults)

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
    func restoreDisplayPreferenceReadsPersistedPresentationPolicy() {
        let (defaults, suiteName) = makeDefaultsSuite()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(
            OverlayPresentationPolicy.alwaysPill.rawValue,
            forKey: OverlayUICoordinator.overlayPresentationPolicyDefaultsKey
        )

        let coordinator = OverlayUICoordinator(defaults: defaults)
        coordinator.restoreDisplayPreference(startMonitoring: false)

        #expect(coordinator.overlayPresentationPolicy == .alwaysPill)
    }

    @Test
    @MainActor
    func restoreDisplayPreferenceFallsBackToDefaultForInvalidPersistedPolicy() {
        let (defaults, suiteName) = makeDefaultsSuite()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(
            "invalid-policy",
            forKey: OverlayUICoordinator.overlayPresentationPolicyDefaultsKey
        )

        let coordinator = OverlayUICoordinator(defaults: defaults)
        coordinator.restoreDisplayPreference(startMonitoring: false)

        #expect(coordinator.overlayPresentationPolicy == .automaticIslandWhenNotched)
    }

    @Test
    @MainActor
    func settingNonDefaultPresentationPolicyPersistsRawValue() {
        let (defaults, suiteName) = makeDefaultsSuite()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = OverlayUICoordinator(defaults: defaults)
        coordinator.overlayPresentationPolicy = .alwaysIsland

        #expect(
            defaults.string(forKey: OverlayUICoordinator.overlayPresentationPolicyDefaultsKey)
            == OverlayPresentationPolicy.alwaysIsland.rawValue
        )
    }

    @Test
    @MainActor
    func settingDefaultPresentationPolicyClearsPersistedValue() {
        let (defaults, suiteName) = makeDefaultsSuite()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = OverlayUICoordinator(defaults: defaults)
        coordinator.overlayPresentationPolicy = .alwaysIsland
        coordinator.overlayPresentationPolicy = .defaultValue

        #expect(
            defaults.object(forKey: OverlayUICoordinator.overlayPresentationPolicyDefaultsKey) == nil
        )
    }

    @Test
    @MainActor
    func applyingDisplayOptionsPreservesMissingManualSelection() {
        let (defaults, suiteName) = makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = OverlayUICoordinator(defaults: defaults)

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
    func diagnosticsCarryResolvedPresentationMode() {
        let diagnostics = OverlayPlacementDiagnostics(
            targetScreenID: "display-1",
            targetScreenName: "Built-in Retina Display",
            selectionSummary: "automatic",
            mode: .notch,
            screenCapability: .notched,
            presentationPolicy: .alwaysPill,
            presentationMode: .pill,
            screenFrame: .zero,
            visibleFrame: .zero,
            safeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            overlayFrame: .zero
        )

        #expect(diagnostics.screenCapability == .notched)
        #expect(diagnostics.presentationPolicy == .alwaysPill)
        #expect(diagnostics.presentationMode == .pill)
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

    // MARK: - Observer lifecycle

    @Test
    @MainActor
    func stopScreenMonitoringIsIdempotentBeforeAndAfterStart() {
        let (defaults, suiteName) = makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = OverlayUICoordinator(defaults: defaults)

        // Safe before any monitoring has started.
        coordinator.stopScreenMonitoring()

        coordinator.restoreDisplayPreference(startMonitoring: true)

        // Safe to call once and then again.
        coordinator.stopScreenMonitoring()
        coordinator.stopScreenMonitoring()

        // Safe to restart after stop.
        coordinator.restoreDisplayPreference(startMonitoring: true)
        coordinator.stopScreenMonitoring()
    }

    @Test
    @MainActor
    func coordinatorDeinitsEvenWhileScreenMonitoringIsActive() {
        let (defaults, suiteName) = makeDefaultsSuite()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        weak var weakCoordinator: OverlayUICoordinator?
        do {
            let coordinator = OverlayUICoordinator(defaults: defaults)
            coordinator.restoreDisplayPreference(startMonitoring: true)
            weakCoordinator = coordinator
            // Do NOT call stopScreenMonitoring() — the observer box's own
            // deinit must clean up the NotificationCenter tokens so the
            // coordinator can be fully released without leaking.
        }

        #expect(weakCoordinator == nil)
    }
}
