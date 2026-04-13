import AppKit
import Foundation
import Observation
import OpenIslandCore

@MainActor
@Observable
final class OverlayUICoordinator {
    private static let overlayDisplayPreferenceDefaultsKey = "overlay.display.preference"
    private static let overlayPresentationPolicyDefaultsKey = "overlay.presentation.policy"

    enum InteractionUpdatePlan: Equatable {
        case setInteractive(Bool)
        case repositionThenSetInteractive(Bool)
    }

    enum PlacementRefreshPlan: Equatable {
        case refresh
        case deferred
    }

    enum CloseTransitionPlan: Equatable {
        case immediate
        case deferTopBarFrameSync
    }

    enum DragStartPlan: Equatable {
        case keepCurrentState
        case closeImmediatelyForDrag
    }

    private static let notificationSurfaceAutoCollapseDelay: TimeInterval = 10

    var notchStatus: NotchStatus = .closed
    var notchOpenReason: NotchOpenReason?
    var islandSurface: IslandSurface = .sessionList()
    var isOverlayVisible: Bool { notchStatus != .closed }

    var overlayDisplayOptions: [OverlayDisplayOption] = []
    var overlayPlacementDiagnostics: OverlayPlacementDiagnostics?
    var overlayPresentationPolicy = OverlayPresentationPolicy.defaultValue {
        didSet {
            guard overlayPresentationPolicy != oldValue else {
                return
            }
            persistOverlayPresentationPolicy()
            refreshOverlayPlacement()
        }
    }

    var overlayDisplaySelectionID = OverlayDisplayOption.automaticID {
        didSet {
            guard overlayDisplaySelectionID != oldValue else {
                return
            }
            persistOverlayDisplayPreference()
            refreshOverlayPlacement()
        }
    }

    @ObservationIgnored
    weak var appModel: AppModel?

    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    @ObservationIgnored
    var activeIslandCardSessionAccessor: (() -> AgentSession?)?

    @ObservationIgnored
    var isSoundMutedAccessor: (() -> Bool)?

    @ObservationIgnored
    var ignoresPointerExitAccessor: (() -> Bool)?

    @ObservationIgnored
    var harnessRuntimeMonitor: HarnessRuntimeMonitor?

    @ObservationIgnored
    let overlayPanelController = OverlayPanelController()

    @ObservationIgnored
    private var overlayTransitionGeneration: UInt64 = 0

    @ObservationIgnored
    private var notificationAutoCollapseTask: Task<Void, Never>?

    @ObservationIgnored
    private var autoCollapseSurfaceHasBeenEntered = false

    var isCloseTransitionPending = false
    var closeTransitionSurfaceOffset: CGSize = .zero

    private var activeIslandCardSession: AgentSession? {
        activeIslandCardSessionAccessor?()
    }

    private var isSoundMuted: Bool {
        isSoundMutedAccessor?() ?? false
    }

    private var ignoresPointerExitDuringHarness: Bool {
        ignoresPointerExitAccessor?() ?? false
    }

    private var preferredOverlayScreenID: String? {
        overlayDisplaySelectionID == OverlayDisplayOption.automaticID
            ? nil
            : overlayDisplaySelectionID
    }

    @ObservationIgnored
    private var screenObserver: Any?

    @ObservationIgnored
    private var activeAppObserver: Any?

    nonisolated static func interactionUpdatePlan(
        requestedInteractive: Bool,
        status: NotchStatus,
        mode: OverlayPlacementMode
    ) -> InteractionUpdatePlan {
        let effectiveInteractive = requestedInteractive || OverlayPanelController.acceptsDirectMouseInteraction(
            status: status,
            mode: mode
        )
        if effectiveInteractive && status == .closed && mode == .topBar {
            return .repositionThenSetInteractive(true)
        }
        return .setInteractive(effectiveInteractive)
    }

    nonisolated static func placementRefreshPlan(
        status: NotchStatus,
        defersForClosedTopBarPointerInteraction: Bool
    ) -> PlacementRefreshPlan {
        if status == .closed && defersForClosedTopBarPointerInteraction {
            return .deferred
        }

        return .refresh
    }

    nonisolated static func closeTransitionPlan(
        previousStatus: NotchStatus,
        targetStatus: NotchStatus,
        mode: OverlayPlacementMode,
        hasPanel: Bool
    ) -> CloseTransitionPlan {
        guard previousStatus == .opened,
              targetStatus == .closed,
              mode == .topBar,
              hasPanel else {
            return .immediate
        }

        return .deferTopBarFrameSync
    }

    nonisolated static func dragStartPlan(
        status: NotchStatus,
        mode: OverlayPlacementMode,
        openReason: NotchOpenReason?
    ) -> DragStartPlan {
        if status == .opened && mode == .topBar && openReason == .hover {
            return .closeImmediatelyForDrag
        }

        return .keepCurrentState
    }

    // MARK: - Initialization

    func restoreDisplayPreference() {
        let defaults = UserDefaults.standard
        overlayDisplaySelectionID = defaults.string(
            forKey: Self.overlayDisplayPreferenceDefaultsKey
        ) ?? OverlayDisplayOption.automaticID
        overlayPresentationPolicy = defaults.string(
            forKey: Self.overlayPresentationPolicyDefaultsKey
        )
        .flatMap(OverlayPresentationPolicy.init(rawValue:))
        ?? .defaultValue
        startScreenMonitoring()
    }

    private func startScreenMonitoring() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshOverlayDisplayConfiguration()
            }
        }

        activeAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.preferredOverlayScreenID == nil else { return }
                self.refreshOverlayPlacement()
            }
        }
    }

    // MARK: - Overlay transitions

    func toggleOverlay() {
        if notchStatus == .closed {
            notchOpen(reason: .click)
        } else {
            notchClose()
        }
    }

    func notchOpen(reason: NotchOpenReason, surface: IslandSurface = .sessionList()) {
        transitionOverlay(
            to: .opened,
            reason: reason,
            surface: surface,
            interactive: true,
            beforeTransition: nil,
            afterStateChange: { [weak self] in
                guard let self else { return }
                self.autoCollapseSurfaceHasBeenEntered = false
                self.updateNotificationAutoCollapse()
            },
            onPlacementResolved: { [weak self] in
                guard let self, let overlayPlacementDiagnostics else { return }
                self.onStatusMessage?("Overlay showing on \(overlayPlacementDiagnostics.targetScreenName) as \(overlayPlacementDiagnostics.modeDescription.lowercased()).")
            }
        )
    }

    func notchClose() {
        transitionOverlay(
            to: .closed,
            reason: nil,
            surface: .sessionList(),
            interactive: false,
            beforeTransition: { [weak self] in
                self?.notificationAutoCollapseTask?.cancel()
                self?.notificationAutoCollapseTask = nil
            },
            afterStateChange: { [weak self] in
                self?.autoCollapseSurfaceHasBeenEntered = false
                self?.appModel?.measuredNotificationContentHeight = 0
            }
        )
    }

    func beginTopBarHoverDrag() {
        let placementMode = overlayPlacementDiagnostics?.mode
            ?? overlayPanelController.placementDiagnostics(
                preferredScreenID: preferredOverlayScreenID
            )?.mode
            ?? .notch

        guard Self.dragStartPlan(
            status: notchStatus,
            mode: placementMode,
            openReason: notchOpenReason
        ) == .closeImmediatelyForDrag else {
            return
        }

        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil
        autoCollapseSurfaceHasBeenEntered = false
        appModel?.measuredNotificationContentHeight = 0
        overlayTransitionGeneration &+= 1
        clearCloseTransitionState()

        islandSurface = .sessionList()
        notchOpenReason = nil
        notchStatus = .closed

        applyInteractionUpdatePlan(
            requestedInteractive: false,
            status: .closed,
            mode: placementMode
        )
    }

    /// Coordinates overlay transitions.
    ///
    /// The window stays at a fixed (opened) size at all times.  All visual
    /// transitions — shape morphing, content fade, corner radius — are
    /// driven purely by SwiftUI `.animation()` modifiers reacting to
    /// `notchStatus` changes.  No AppKit animation, no window resize.
    private func transitionOverlay(
        to status: NotchStatus,
        reason: NotchOpenReason?,
        surface: IslandSurface,
        interactive: Bool,
        beforeTransition: (() -> Void)?,
        afterStateChange: (() -> Void)? = nil,
        onPlacementResolved: (() -> Void)? = nil
    ) {
        beforeTransition?()

        overlayTransitionGeneration &+= 1
        let capturedGeneration = overlayTransitionGeneration

        let previousStatus = notchStatus

        // Reset measured notification height when the surface changes so stale
        // measurements from a previous notification don't mis-size the new one.
        if surface != islandSurface {
            appModel?.measuredNotificationContentHeight = 0
        }
        let placementMode = overlayPlacementDiagnostics?.mode
            ?? overlayPanelController.placementDiagnostics(
                preferredScreenID: preferredOverlayScreenID
            )?.mode
            ?? .notch
        let closeTransitionPlan = Self.closeTransitionPlan(
            previousStatus: previousStatus,
            targetStatus: status,
            mode: placementMode,
            hasPanel: overlayPanelController.hasAttachedPanel
        )
        let deferredTopBarCloseContext = closeTransitionPlan == .deferTopBarFrameSync
            ? overlayPanelController.topBarCloseTransitionContext(
                preferredScreenID: preferredOverlayScreenID
            )
            : nil

        if status == .opened {
            clearCloseTransitionState()
        } else if let deferredTopBarCloseContext {
            isCloseTransitionPending = true
            closeTransitionSurfaceOffset = deferredTopBarCloseContext.surfaceOffset
        } else {
            clearCloseTransitionState()
        }

        islandSurface = surface
        notchOpenReason = reason
        notchStatus = status

        if status == .opened, let appModel {
            applyInteractionUpdatePlan(
                requestedInteractive: interactive,
                status: status,
                mode: placementMode
            )
            overlayPlacementDiagnostics = overlayPanelController.show(
                model: appModel,
                preferredScreenID: preferredOverlayScreenID
            )
            afterStateChange?()
            onPlacementResolved?()
            return
        }

        if deferredTopBarCloseContext != nil {
            overlayPanelController.setInteractive(false)
            afterStateChange?()

            DispatchQueue.main.asyncAfter(
                deadline: .now() + IslandChromeMetrics.closeTransitionDuration
            ) { [weak self] in
                guard let self, self.overlayTransitionGeneration == capturedGeneration else { return }
                self.overlayPlacementDiagnostics = self.overlayPanelController.reposition(
                    preferredScreenID: self.preferredOverlayScreenID
                )
                self.clearCloseTransitionState()
                self.overlayPanelController.setInteractive(true)
                onPlacementResolved?()
            }
            return
        }

        applyInteractionUpdatePlan(
            requestedInteractive: interactive,
            status: status,
            mode: placementMode
        )
        afterStateChange?()
        onPlacementResolved?()
    }

    func notchPop() {
        guard notchStatus == .closed else { return }
        islandSurface = .sessionList()
        notchStatus = .popping
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard self?.notchStatus == .popping else { return }
            self?.notchStatus = .closed
        }
    }

    func performBootAnimation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.notchOpen(reason: .boot, surface: .sessionList())
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard self?.notchOpenReason == .boot else { return }
                self?.notchClose()
            }
        }
    }

    func ensureOverlayPanel() {
        guard let appModel else { return }
        overlayPanelController.ensurePanel(model: appModel, preferredScreenID: preferredOverlayScreenID)
    }

    // Legacy compatibility
    func showOverlay() { notchOpen(reason: .click, surface: .sessionList()) }
    func hideOverlay() { notchClose() }

    /// Transition from notification mode (single session) to full session list.
    /// - Parameter clearExpansion: If true, clears the actionable session's expansion
    ///   (used for completion notifications which are informational only).
    func expandNotificationToSessionList(clearExpansion: Bool = false) {
        if clearExpansion {
            islandSurface = .sessionList()
        }
        // When not clearing, keep actionableSessionID so approval/question expansion persists
        notchOpenReason = .click
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil
        refreshOverlayPlacementIfVisible()
    }

    // MARK: - Display configuration

    func applyOverlayDisplayOptions(_ options: [OverlayDisplayOption]) {
        overlayDisplayOptions = options
        refreshOverlayPlacement()
    }

    func refreshOverlayDisplayConfiguration() {
        applyOverlayDisplayOptions(overlayPanelController.availableDisplayOptions())
    }

    func refreshOverlayPlacement() {
        guard !isCloseTransitionPending else {
            return
        }
        overlayPlacementDiagnostics = overlayPanelController.reposition(
            preferredScreenID: preferredOverlayScreenID
        )
    }

    func refreshOverlayPlacementIfVisible() {
        switch Self.placementRefreshPlan(
            status: notchStatus,
            defersForClosedTopBarPointerInteraction: overlayPanelController.isClosedTopBarPointerInteractionActive()
        ) {
        case .refresh:
            refreshOverlayPlacement()
        case .deferred:
            overlayPanelController.deferPlacementRefreshUntilClosedTopBarPointerRelease()
        }
    }

    // MARK: - Pointer tracking

    var shouldAutoCollapseOnMouseLeave: Bool {
        if ignoresPointerExitDuringHarness {
            return false
        }

        guard notchStatus == .opened else {
            return false
        }

        if notchOpenReason == .hover && !islandSurface.isNotificationCard {
            return true
        }

        return notchOpenReason == .notification
            && islandSurface.autoDismissesWhenPresentedAsNotification(session: activeIslandCardSession)
    }

    var autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry: Bool {
        guard notchOpenReason == .notification else { return false }
        // If the session was removed from state (e.g. by process monitoring),
        // default to requiring prior surface entry — prevents the notification
        // from closing immediately on pointer exit before the user sees it.
        guard let session = activeIslandCardSession else { return true }
        return islandSurface.autoDismissesWhenPresentedAsNotification(session: session)
    }

    var showsNotificationCard: Bool {
        islandSurface.isNotificationCard
    }

    func notePointerInsideIslandSurface() {
        guard shouldAutoCollapseOnMouseLeave else {
            return
        }

        autoCollapseSurfaceHasBeenEntered = true
    }

    func handlePointerExitedIslandSurface() {
        guard shouldAutoCollapseOnMouseLeave else {
            return
        }

        guard !autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry
                || autoCollapseSurfaceHasBeenEntered else {
            return
        }

        notchClose()
    }

    // MARK: - Notification surfaces

    func presentNotificationSurface(_ surface: IslandSurface) {
        guard surface.isNotificationCard else {
            return
        }

        NotificationSoundService.playNotification(isMuted: isSoundMuted)
        notchOpen(reason: .notification, surface: surface)
    }

    func reconcileIslandSurfaceAfterStateChange() {
        guard islandSurface.isNotificationCard else {
            return
        }

        let session = activeIslandCardSession
        guard islandSurface.matchesCurrentState(of: session) else {
            if notchOpenReason == .notification {
                notchClose()
            } else {
                islandSurface = .sessionList()
            }
            return
        }

        updateNotificationAutoCollapse()
    }

    func dismissNotificationSurfaceIfPresent(for sessionID: String) {
        guard islandSurface.sessionID == sessionID,
              notchOpenReason == .notification else {
            return
        }

        notchClose()
    }

    func dismissOverlayForJump() {
        guard isOverlayVisible else {
            return
        }

        notchClose()
    }

    private func updateNotificationAutoCollapse() {
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil

        guard notchStatus == .opened,
              notchOpenReason == .notification,
              islandSurface.autoDismissesWhenPresentedAsNotification(session: activeIslandCardSession) else {
            return
        }

        notificationAutoCollapseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.notificationSurfaceAutoCollapseDelay))
            } catch {
                // Task was cancelled (e.g. a new event reset the timer).
                // Do NOT proceed — the replacement task owns the new timer.
                return
            }

            guard let self,
                  self.notchStatus == .opened,
                  self.notchOpenReason == .notification,
                  self.islandSurface.autoDismissesWhenPresentedAsNotification(session: self.activeIslandCardSession) else {
                return
            }

            self.notchClose()
        }
    }

    // MARK: - Debug snapshots (overlay portion)

    func applyOverlayState(from snapshot: IslandDebugSnapshot, presentOverlay: Bool, autoCollapseNotificationCards: Bool) {
        notificationAutoCollapseTask?.cancel()
        notificationAutoCollapseTask = nil
        autoCollapseSurfaceHasBeenEntered = false
        clearCloseTransitionState()

        islandSurface = snapshot.islandSurface
        notchStatus = snapshot.notchStatus
        notchOpenReason = snapshot.notchOpenReason

        if autoCollapseNotificationCards {
            updateNotificationAutoCollapse()
        }

        guard presentOverlay, let appModel else {
            return
        }

        // Immediate interactivity update.
        let placementMode = overlayPlacementDiagnostics?.mode
            ?? overlayPanelController.placementDiagnostics(
                preferredScreenID: preferredOverlayScreenID
            )?.mode
            ?? .notch
        let interactive = OverlayPanelController.acceptsDirectMouseInteraction(
            status: snapshot.notchStatus,
            mode: placementMode
        )
        applyInteractionUpdatePlan(
            requestedInteractive: interactive,
            status: snapshot.notchStatus,
            mode: placementMode
        )

        // Defer AppKit panel animation to the next run-loop iteration.
        overlayTransitionGeneration &+= 1
        let capturedGeneration = overlayTransitionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.overlayTransitionGeneration == capturedGeneration else { return }
            switch snapshot.notchStatus {
            case .opened:
                self.overlayPlacementDiagnostics = self.overlayPanelController.show(
                    model: appModel,
                    preferredScreenID: self.preferredOverlayScreenID
                )
            case .closed, .popping:
                self.refreshOverlayPlacement()
            }
            self.harnessRuntimeMonitor?.recordMilestone("overlayPresented", message: snapshot.title)
        }
    }

    // MARK: - Persistence

    private func persistOverlayDisplayPreference() {
        let defaults = UserDefaults.standard
        if overlayDisplaySelectionID == OverlayDisplayOption.automaticID {
            defaults.removeObject(forKey: Self.overlayDisplayPreferenceDefaultsKey)
        } else {
            defaults.set(
                overlayDisplaySelectionID,
                forKey: Self.overlayDisplayPreferenceDefaultsKey
            )
        }
    }

    private func persistOverlayPresentationPolicy() {
        let defaults = UserDefaults.standard
        if overlayPresentationPolicy == .defaultValue {
            defaults.removeObject(forKey: Self.overlayPresentationPolicyDefaultsKey)
        } else {
            defaults.set(
                overlayPresentationPolicy.rawValue,
                forKey: Self.overlayPresentationPolicyDefaultsKey
            )
        }
    }

    private func applyInteractionUpdatePlan(
        requestedInteractive: Bool,
        status: NotchStatus,
        mode: OverlayPlacementMode
    ) {
        switch Self.interactionUpdatePlan(
            requestedInteractive: requestedInteractive,
            status: status,
            mode: mode
        ) {
        case .setInteractive(let interactive):
            overlayPanelController.setInteractive(interactive)
        case .repositionThenSetInteractive(let interactive):
            overlayPlacementDiagnostics = overlayPanelController.reposition(
                preferredScreenID: preferredOverlayScreenID
            )
            overlayPanelController.setInteractive(interactive)
        }
    }

    private func clearCloseTransitionState() {
        isCloseTransitionPending = false
        closeTransitionSurfaceOffset = .zero
    }
}
