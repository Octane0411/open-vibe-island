import AppKit
import Foundation
import Observation
import OpenIslandCore

@MainActor
@Observable
final class OverlayUICoordinator {

    private static let notificationSurfaceAutoCollapseDelay: TimeInterval = 10

    var notchStatus: NotchStatus = .closed
    var notchOpenReason: NotchOpenReason?
    var islandSurface: IslandSurface = .sessionList()
    var isOverlayVisible: Bool { notchStatus != .closed }

    var overlayDisplayOptions: [OverlayDisplayOption] = []
    var overlayPlacementDiagnostics: OverlayPlacementDiagnostics?

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

    @ObservationIgnored
    private var lastMeasuredNotificationSessionID: String?

    /// Kept for API compatibility; always false now that the window never
    /// resizes and close transitions are pure SwiftUI.
    var isCloseTransitionPending: Bool { false }

    func noteNotificationHeightMeasured(for sessionID: String?) {
        lastMeasuredNotificationSessionID = sessionID
    }

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

    // MARK: - Initialization

    func restoreDisplayPreference() {
        overlayDisplaySelectionID = UserDefaults.standard.string(
            forKey: "overlay.display.preference"
        ) ?? OverlayDisplayOption.automaticID
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
        let resolvedSurface: IslandSurface
        if surface.sessionID == nil,
           let attentionSession = appModel?.surfacedSessions.first(where: { $0.phase.requiresAttention }) {
            resolvedSurface = .sessionList(actionableSessionID: attentionSession.id)
        } else {
            resolvedSurface = surface
        }

        transitionOverlay(
            to: .opened,
            reason: reason,
            surface: resolvedSurface,
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
                // Preserve measuredNotificationContentHeight; cleared in transitionOverlay
                // only when a different session's card opens.
            }
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

        // Clear stale height only when a genuinely different session's card opens.
        if let newSessionID = surface.sessionID {
            if newSessionID != lastMeasuredNotificationSessionID {
                appModel?.measuredNotificationContentHeight = 0
            }
            lastMeasuredNotificationSessionID = newSessionID
        }

        islandSurface = surface
        notchOpenReason = reason
        notchStatus = status
        overlayPanelController.setInteractive(interactive)

        if status == .opened, let appModel {
            overlayPlacementDiagnostics = overlayPanelController.show(
                model: appModel,
                preferredScreenID: preferredOverlayScreenID
            )

            // Deferred reposition: give SwiftUI one runloop pass to report the
            // measured height before correcting the panel size.
            let capturedGeneration = overlayTransitionGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.overlayTransitionGeneration == capturedGeneration,
                      self.notchStatus == .opened else { return }
                self.overlayPlacementDiagnostics = self.overlayPanelController.reposition(
                    preferredScreenID: self.preferredOverlayScreenID
                )
            }
        }

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

    func refreshOverlayDisplayConfiguration() {
        overlayDisplayOptions = overlayPanelController.availableDisplayOptions()

        let validSelectionIDs = Set(overlayDisplayOptions.map(\.id))
        if !validSelectionIDs.contains(overlayDisplaySelectionID) {
            overlayDisplaySelectionID = OverlayDisplayOption.automaticID
            return
        }

        refreshOverlayPlacement()
    }

    func refreshOverlayPlacement() {
        overlayPlacementDiagnostics = overlayPanelController.reposition(
            preferredScreenID: preferredOverlayScreenID
        )
    }

    func refreshOverlayPlacementIfVisible() {
        refreshOverlayPlacement()
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
        let interactive = snapshot.notchStatus == .opened
        overlayPanelController.setInteractive(interactive)

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
            defaults.removeObject(forKey: "overlay.display.preference")
        } else {
            defaults.set(overlayDisplaySelectionID, forKey: "overlay.display.preference")
        }
    }
}
