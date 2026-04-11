import AppKit
import Combine
import OSLog
import SwiftUI
import OpenIslandCore

private let overlayDragLogger = Logger(
    subsystem: "app.openisland.dev",
    category: "OverlayDrag"
)
private let overlayDragDebugKey = "overlay.debug.drag"

private func overlayDragLoggingEnabled() -> Bool {
    UserDefaults.standard.bool(forKey: overlayDragDebugKey)
}

private func overlayDragLog(_ message: String) {
    guard overlayDragLoggingEnabled() else {
        return
    }

    overlayDragLogger.notice("\(message, privacy: .public)")
}

private func overlayDragPointDescription(_ point: NSPoint) -> String {
    "(\(Int(point.x.rounded())), \(Int(point.y.rounded())))"
}

private func overlayDragRectDescription(_ rect: NSRect) -> String {
    NSStringFromRect(rect)
}

@MainActor
final class OverlayPanelController {
    struct CloseTransitionContext {
        let surfaceOffset: CGSize
    }

    struct OpenedTopBarHeaderDragTransition: Equatable {
        let immediatePanelOrigin: NSPoint
        let continuedDragStartMouse: NSPoint
        let continuedDragStartPanelOrigin: NSPoint
    }

    enum TopBarDragReleaseAction: Equatable {
        case persistDraggedPosition
        case endClosedTopBarPress
        case handlePillClick
    }

    enum OpenedTopBarHeaderDragPlan: Equatable {
        case waitForThreshold
        case startClosedPillDrag
        case continueClosedPillDrag
    }

    private static let topBarOpenedHeaderDragHeight: CGFloat = 30

    private static let minimumOpenedPanelWidth: CGFloat = 680
    private static let maximumOpenedPanelWidth: CGFloat = 740
    private static let openedPanelWidthFactor: CGFloat = 0.46
    private static let preferredNotificationPanelWidth: CGFloat = 620
    private static let openedContentWidthPadding: CGFloat = 28
    private static let openedContentBottomPadding: CGFloat = 0
    /// Must match `IslandPanelView.maxSessionListHeight` — the AutoHeightScrollView cap.
    private static let maxSessionListHeight: CGFloat = 560
    private static let maxVisibleSessionRows: Int = 6
    private static let openedRowSpacing: CGFloat = 6
    // Content padding (8) + scroll padding (4) + view chrome: outerBottomPadding (14) + header-content gap (12)
    private static let openedContentVerticalInsets: CGFloat = 38
    private static let openedEmptyStateHeight: CGFloat = 108
    private static let approvalCardHeight: CGFloat = 288
    private static let questionCardHeight: CGFloat = 110
    // Completion card chrome breakdown (everything except the scrollable text):
    // openedContent vertical padding: 24, card container padding: 28,
    // card VStack spacing: 14, card header (title+prompt): ~50,
    // completionBody header ("You:"/Done row): ~42, divider: 1,
    // text area vertical padding: 28  →  total ≈ 187
    private static let completionCardChromeHeight: CGFloat = 187
    private static let completionCardMinHeight: CGFloat = 210
    private static let completionCardMaxHeight: CGFloat = 400
    private static let hiddenIdleEdgeHoverHitHeight: CGFloat = 8

    private var panel: NotchPanel?
    private var eventMonitors = NotchEventMonitors()
    private var hoverTimer: DispatchWorkItem?
    private var hoverCancelGrace: DispatchWorkItem?
    private var isPressingClosedTopBarPill = false
    private var hasDeferredPlacementRefreshDuringClosedTopBarPress = false
    weak var model: AppModel?
    private(set) var notchRect: NSRect = .zero

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var hasAttachedPanel: Bool {
        panel != nil
    }

    nonisolated static func shouldActivatePanel(for reason: NotchOpenReason?) -> Bool {
        reason == .click
    }

    nonisolated static func normalizedPreferredScreenID(
        _ selectionID: String?
    ) -> String? {
        guard let selectionID, selectionID != OverlayDisplayOption.automaticID else {
            return nil
        }
        return selectionID
    }

    nonisolated static func acceptsDirectMouseInteraction(
        status: NotchStatus,
        mode: OverlayPlacementMode
    ) -> Bool {
        status == .opened || (status == .closed && mode == .topBar)
    }

    nonisolated static func shouldEventMonitorHandleClosedSurfaceClick(
        status: NotchStatus,
        mode: OverlayPlacementMode,
        panelIgnoresMouseEvents: Bool
    ) -> Bool {
        guard status == .closed else { return false }
        if mode != .topBar {
            return true
        }
        return panelIgnoresMouseEvents
    }

    nonisolated static func shouldArmClosedSurfaceHoverOpen(
        status: NotchStatus,
        mode: OverlayPlacementMode,
        isPressingClosedTopBarPill: Bool
    ) -> Bool {
        guard status == .closed else { return false }
        if mode != .topBar {
            return true
        }
        return !isPressingClosedTopBarPill
    }

    nonisolated static func canDragOpenedTopBarHeader(
        status: NotchStatus,
        mode: OverlayPlacementMode,
        openReason: NotchOpenReason?
    ) -> Bool {
        status == .opened && mode == .topBar && openReason == .hover
    }

    nonisolated static func openedTopBarHeaderDragRect(
        contentRect: NSRect,
        headerHeight: CGFloat,
        trailingControlWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> NSRect {
        let clampedHeaderHeight = max(0, min(headerHeight, contentRect.height))
        let headerRect = NSRect(
            x: contentRect.minX,
            y: contentRect.maxY - clampedHeaderHeight,
            width: contentRect.width,
            height: clampedHeaderHeight
        )

        let safeHorizontalPadding = max(0, horizontalPadding)
        let safeTrailingControlWidth = max(0, trailingControlWidth)
        let dragMinX = headerRect.minX + safeHorizontalPadding
        let dragMaxX = headerRect.maxX - safeHorizontalPadding - safeTrailingControlWidth
        let dragWidth = max(0, dragMaxX - dragMinX)

        return NSRect(
            x: dragMinX,
            y: headerRect.minY,
            width: dragWidth,
            height: headerRect.height
        )
    }

    nonisolated static func shouldCaptureOpenedTopBarHeaderDrag(
        status: NotchStatus,
        mode: OverlayPlacementMode,
        openReason: NotchOpenReason?,
        point: NSPoint,
        contentRect: NSRect,
        headerHeight: CGFloat,
        trailingControlWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> Bool {
        guard canDragOpenedTopBarHeader(
            status: status,
            mode: mode,
            openReason: openReason
        ) else {
            return false
        }

        let dragRect = openedTopBarHeaderDragRect(
            contentRect: contentRect,
            headerHeight: headerHeight,
            trailingControlWidth: trailingControlWidth,
            horizontalPadding: horizontalPadding
        )
        return dragRect.contains(point)
    }

    nonisolated static func shouldCaptureTopBarDragLayerHit(
        capturesClosedTopBarPill: Bool,
        capturesOpenedHeaderDrag: Bool
    ) -> Bool {
        capturesClosedTopBarPill || capturesOpenedHeaderDrag
    }

    nonisolated static func normalizeEventPointForOverlayGeometry(
        _ point: NSPoint,
        viewHeight: CGFloat
    ) -> NSPoint {
        guard viewHeight > 0 else {
            return point
        }

        return NSPoint(
            x: point.x,
            y: max(0, min(viewHeight, viewHeight - point.y))
        )
    }

    nonisolated static func openedTopBarHeaderDragPlan(
        startedFromOpenedTopBarHeader: Bool,
        didTransitionToClosedPill: Bool,
        dragDistance: CGFloat,
        threshold: CGFloat
    ) -> OpenedTopBarHeaderDragPlan {
        guard startedFromOpenedTopBarHeader else {
            return .continueClosedPillDrag
        }

        if didTransitionToClosedPill {
            return .continueClosedPillDrag
        }

        if dragDistance >= threshold {
            return .startClosedPillDrag
        }

        return .waitForThreshold
    }

    nonisolated static func openedTopBarHeaderDragTransition(
        originalDragStartMouse: NSPoint,
        currentMouse: NSPoint,
        collapsedPillOrigin: NSPoint
    ) -> OpenedTopBarHeaderDragTransition {
        let dx = currentMouse.x - originalDragStartMouse.x
        let dy = currentMouse.y - originalDragStartMouse.y

        return OpenedTopBarHeaderDragTransition(
            immediatePanelOrigin: NSPoint(
                x: collapsedPillOrigin.x + dx,
                y: collapsedPillOrigin.y + dy
            ),
            continuedDragStartMouse: originalDragStartMouse,
            continuedDragStartPanelOrigin: collapsedPillOrigin
        )
    }

    nonisolated static func shouldEndClosedTopBarPressAfterDrag(
        startedFromOpenedTopBarHeader: Bool,
        didTransitionToClosedPill: Bool
    ) -> Bool {
        !startedFromOpenedTopBarHeader || didTransitionToClosedPill
    }

    nonisolated static func topBarDragReleaseActions(
        didMove: Bool,
        startedFromOpenedTopBarHeader: Bool,
        didTransitionToClosedPill: Bool
    ) -> [TopBarDragReleaseAction] {
        var actions: [TopBarDragReleaseAction] = []

        if didMove {
            actions.append(.persistDraggedPosition)
        } else if !startedFromOpenedTopBarHeader {
            actions.append(.handlePillClick)
        }

        if shouldEndClosedTopBarPressAfterDrag(
            startedFromOpenedTopBarHeader: startedFromOpenedTopBarHeader,
            didTransitionToClosedPill: didTransitionToClosedPill
        ) {
            actions.append(.endClosedTopBarPress)
        }

        return actions
    }

    func availableDisplayOptions() -> [OverlayDisplayOption] {
        OverlayDisplayResolver.availableDisplayOptions()
    }

    func ensurePanel(model: AppModel, preferredScreenID: String?) {
        self.model = model
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        positionPanel(panel, preferredScreenID: preferredScreenID, animated: false)
        panel.orderFrontRegardless()
        let mode = placementDiagnostics(preferredScreenID: preferredScreenID)?.mode ?? .notch
        let interactive = Self.acceptsDirectMouseInteraction(
            status: model.notchStatus,
            mode: mode
        )
        panel.ignoresMouseEvents = !interactive
        panel.acceptsMouseMovedEvents = interactive
        startEventMonitoring()
    }

    func show(model: AppModel, preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        self.model = model
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        let diagnostics = positionPanel(panel, preferredScreenID: preferredScreenID, animated: true)
        presentPanel(panel, activates: Self.shouldActivatePanel(for: model.notchOpenReason))
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        startEventMonitoring()
        return diagnostics
    }

    func hide() {
        panel?.ignoresMouseEvents = true
        panel?.acceptsMouseMovedEvents = false
    }

    func setInteractive(_ interactive: Bool) {
        guard let panel else {
            return
        }

        panel.ignoresMouseEvents = !interactive
        panel.acceptsMouseMovedEvents = interactive

        if interactive {
            presentPanel(panel, activates: Self.shouldActivatePanel(for: model?.notchOpenReason))
        }
    }

    func reposition(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        guard let panel else {
            return placementDiagnostics(preferredScreenID: preferredScreenID)
        }

        return positionPanel(panel, preferredScreenID: preferredScreenID, animated: true)
    }

    func placementDiagnostics(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        let panelSize = panel?.frame.size ?? OverlayDisplayResolver.defaultPanelSize
        return OverlayDisplayResolver.diagnostics(preferredScreenID: preferredScreenID, panelSize: panelSize)
    }

    func topBarCloseTransitionContext(preferredScreenID: String?) -> CloseTransitionContext? {
        guard let model,
              let panel,
              let screen = resolveTargetScreen(preferredScreenID: preferredScreenID) else {
            return nil
        }

        let strategy = placementStrategy(for: screen)
        guard strategy == .topBar else {
            return nil
        }

        let closedWidth = closedPanelWidth(for: model, on: screen)
        let closedHeight = screen.islandClosedHeight
        let targetClosedShadowInsets = IslandChromeMetrics.panelShadowInsets(
            usesOpenedVisualState: false
        )
        let targetClosedPanelFrame = strategy.frame(
            anchor: pillAnchor(on: screen),
            size: NSSize(
                width: closedWidth + (targetClosedShadowInsets.horizontal * 2),
                height: closedHeight + targetClosedShadowInsets.bottom
            ),
            screenVisibleFrame: screen.visibleFrame
        )

        return CloseTransitionContext(
            surfaceOffset: strategy.closeTransitionSurfaceOffset(
                currentPanelFrame: panel.frame,
                targetClosedPanelFrame: targetClosedPanelFrame,
                closedSurfaceSize: NSSize(width: closedWidth, height: closedHeight),
                targetClosedShadowInsets: targetClosedShadowInsets
            )
        )
    }

    // MARK: - Panel creation

    private func makePanel(model: AppModel) -> NotchPanel {
        let screen = resolveTargetScreen() ?? NSScreen.main
        let windowFrame = screen.map { panelFrame(for: model, on: $0) } ?? .zero

        let panel = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .statusBar
        panel.sharingType = .readOnly
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = true

        let hostingView = NotchHostingView(rootView: IslandPanelView(model: model))
        hostingView.notchController = self
        panel.contentView = hostingView

        computeNotchRect(screen: resolveTargetScreen())
        return panel
    }

    // MARK: - Positioning

    @discardableResult
    private func positionPanel(
        _ panel: NSPanel,
        preferredScreenID: String?,
        animated: Bool
    ) -> OverlayPlacementDiagnostics? {
        guard let screen = resolveTargetScreen(preferredScreenID: preferredScreenID) else {
            return nil
        }

        let windowFrame = panelFrame(for: model, on: screen)

        // Always set the panel frame instantly — no AppKit animation.
        // All visual transitions (shape, size, opacity, corner radius) are
        // driven by SwiftUI's .animation() modifier on the content view.
        // Mixing NSAnimationContext with SwiftUI spring animations caused
        // visible jank because the two systems have different timing curves,
        // durations, and start times (AppKit was deferred by one runloop).
        if panel.frame != windowFrame {
            panel.setFrame(windowFrame, display: true)
        }
        computeNotchRect(screen: screen)

        return OverlayDisplayResolver.diagnostics(
            preferredScreenID: preferredScreenID,
            panelSize: panel.frame.size
        )
    }

    private func presentPanel(_ panel: NSPanel, activates: Bool) {
        if activates {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func computeNotchRect(screen: NSScreen?) {
        guard let screen else {
            notchRect = .zero
            return
        }

        let notchSize = screen.notchSize
        let anchor = pillAnchor(on: screen)
        let notchX = anchor.x - notchSize.width / 2
        let notchY = anchor.y - notchSize.height

        notchRect = NSRect(x: notchX, y: notchY, width: notchSize.width, height: notchSize.height)
    }

    /// Returns the closed-pill anchor `(centerX, topY)` in Cocoa screen
    /// coordinates for the given screen.
    ///
    /// - On `.notch` screens: always horizontally centered at the top of the
    ///   physical display (current behavior, ignores any saved position).
    /// - On `.topBar` screens: uses the user-dragged position from
    ///   `OverlayPillPositionStore` if present, otherwise falls back to
    ///   horizontally centered with an 18pt gap below the menu bar.
    private func pillAnchor(on screen: NSScreen) -> NSPoint {
        let strategy = placementStrategy(for: screen)
        let storedTopBarAnchor: NSPoint?
        if strategy == .topBar {
            storedTopBarAnchor = OverlayPillPositionStore.load(
                for: screenID(for: screen),
                on: screen,
                closedWidth: currentClosedWidth(on: screen)
            )
        } else {
            storedTopBarAnchor = nil
        }

        return strategy.resolvedAnchor(
            screenFrame: screen.frame,
            screenVisibleFrame: screen.visibleFrame,
            storedTopBarAnchor: storedTopBarAnchor
        )
    }

    private func resolveTargetScreen(preferredScreenID: String? = nil) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        let preferredSelectionID = Self.normalizedPreferredScreenID(
            preferredScreenID ?? model?.overlayDisplaySelectionID
        )

        guard let selection = OverlayScreenSelectionResolver.resolve(
            preferredScreenID: preferredSelectionID,
            screens: screens.map { screen in
                OverlayScreenSelectionCandidate(
                    id: screenID(for: screen),
                    isNotched: OverlayDisplayResolver.placementMode(for: screen) == .notch,
                    isMain: screen == NSScreen.main
                )
            }
        ) else {
            return nil
        }

        return screens.first(where: { screenID(for: $0) == selection.screenID })
    }

    private func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return screen.localizedName
    }

    // MARK: - Drag-to-reposition pill (external displays only)

    /// Whether the pill is currently eligible for drag-to-move. Only true when
    /// the panel is closed AND the current target screen is in topBar mode
    /// (i.e. not the built-in notch screen). Notch screens never allow drag.
    func canDragPillNow() -> Bool {
        guard model?.notchStatus == .closed else { return false }
        guard let screen = resolveTargetScreen() else { return false }
        return placementStrategy(for: screen) == .topBar
    }

    func shouldCaptureOpenedTopBarHeaderDrag(at pointInView: NSPoint, in bounds: NSRect) -> Bool {
        guard let model else {
            return false
        }

        guard let contentRect = contentRect(for: model, in: bounds),
              contentRect.contains(pointInView) else {
            return false
        }

        let mode = model.overlayPlacementDiagnostics?.mode
            ?? placementDiagnostics(preferredScreenID: nil)?.mode
            ?? .notch

        let dragRect = Self.openedTopBarHeaderDragRect(
            contentRect: contentRect,
            headerHeight: Self.topBarOpenedHeaderDragHeight,
            trailingControlWidth: IslandPanelView.topBarOpenedHeaderTrailingControlWidth,
            horizontalPadding: IslandPanelView.topBarOpenedHeaderHorizontalPadding
        )
        let captures = Self.shouldCaptureOpenedTopBarHeaderDrag(
            status: model.notchStatus,
            mode: mode,
            openReason: model.notchOpenReason,
            point: pointInView,
            contentRect: contentRect,
            headerHeight: Self.topBarOpenedHeaderDragHeight,
            trailingControlWidth: IslandPanelView.topBarOpenedHeaderTrailingControlWidth,
            horizontalPadding: IslandPanelView.topBarOpenedHeaderHorizontalPadding
        )
        overlayDragLog(
            "openedHeaderCapture=\(captures) status=\(String(describing: model.notchStatus)) reason=\(String(describing: model.notchOpenReason)) mode=\(mode.rawValue) point=\(overlayDragPointDescription(pointInView)) contentRect=\(overlayDragRectDescription(contentRect)) dragRect=\(overlayDragRectDescription(dragRect))"
        )
        return captures
    }

    func shouldCaptureTopBarDragLayerHit(at pointInView: NSPoint, in bounds: NSRect) -> Bool {
        Self.shouldCaptureTopBarDragLayerHit(
            capturesClosedTopBarPill: canDragPillNow(),
            capturesOpenedHeaderDrag: shouldCaptureOpenedTopBarHeaderDrag(
                at: pointInView,
                in: bounds
            )
        )
    }

    /// Called by the hosting view while the user drags the pill. Moves the
    /// panel without triggering our own `positionPanel` path (which would
    /// reset the frame back to the stored anchor).
    func moveDraggedPanel(to origin: NSPoint) {
        overlayDragLog("moveDraggedPanel origin=\(overlayDragPointDescription(origin))")
        panel?.setFrameOrigin(origin)
    }

    func beginClosedTopBarPress() {
        isPressingClosedTopBarPill = true
        hasDeferredPlacementRefreshDuringClosedTopBarPress = false
        cancelHoverOpenImmediately()
    }

    func beginOpenedTopBarHeaderDrag() {
        guard let model else {
            return
        }

        let beforePanelFrame = panel.map { overlayDragRectDescription($0.frame) } ?? "nil"
        overlayDragLog(
            "beginOpenedTopBarHeaderDrag before status=\(String(describing: model.notchStatus)) reason=\(String(describing: model.notchOpenReason)) panelFrame=\(beforePanelFrame)"
        )
        model.beginTopBarHoverDrag()
        beginClosedTopBarPress()
        let afterPanelFrame = panel.map { overlayDragRectDescription($0.frame) } ?? "nil"
        overlayDragLog(
            "beginOpenedTopBarHeaderDrag after status=\(String(describing: model.notchStatus)) reason=\(String(describing: model.notchOpenReason)) panelFrame=\(afterPanelFrame)"
        )
    }

    func endClosedTopBarPress() {
        isPressingClosedTopBarPill = false
        let shouldRefreshPlacement = hasDeferredPlacementRefreshDuringClosedTopBarPress
        hasDeferredPlacementRefreshDuringClosedTopBarPress = false

        if shouldRefreshPlacement {
            model?.refreshOverlayPlacement()
        }
    }

    func isClosedTopBarPointerInteractionActive() -> Bool {
        isPressingClosedTopBarPill
    }

    func deferPlacementRefreshUntilClosedTopBarPointerRelease() {
        guard isPressingClosedTopBarPill else {
            return
        }

        hasDeferredPlacementRefreshDuringClosedTopBarPress = true
    }

    /// Called by the hosting view after a drag finishes. Persists the new
    /// pill anchor for whichever screen the panel now lives on, and refreshes
    /// the hover hit-test rect.
    func persistDraggedPillPosition() {
        guard let panel else { return }
        let frame = panel.frame
        let center = NSPoint(x: frame.midX, y: frame.maxY)

        // Find the screen that currently contains the panel's center. Fall
        // back to the previously resolved target screen if the panel ended up
        // between screens.
        let hostScreen = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: frame.midX, y: (frame.minY + frame.maxY) / 2))
        } ?? resolveTargetScreen()

        guard let screen = hostScreen,
              placementStrategy(for: screen) == .topBar else {
            // Dragged onto a notch screen — ignore; notch screens always
            // center on the physical notch.
            computeNotchRect(screen: resolveTargetScreen())
            return
        }

        OverlayPillPositionStore.save(
            center,
            for: screenID(for: screen),
            on: screen,
            closedWidth: currentClosedWidth(on: screen)
        )
        computeNotchRect(screen: screen)
    }

    /// Called by the hosting view when the user taps the pill without
    /// dragging. Mirrors the SwiftUI `onTapGesture` behavior that normally
    /// fires in closed state.
    func handlePillClickFromDragLayer() {
        guard let model, model.notchStatus == .closed else { return }
        model.notchOpen(reason: .click)
    }

    // MARK: - Mouse event monitoring

    private func startEventMonitoring() {
        if model?.disablesOverlayEventMonitoringDuringHarness == true {
            return
        }

        guard !eventMonitors.isActive else { return }

        eventMonitors.start { [weak self] location in
            self?.handleMouseMoved(location)
        } mouseDownHandler: { [weak self] location in
            self?.handleMouseDown(location)
        }
    }

    private func handleMouseMoved(_ screenLocation: NSPoint) {
        guard let model else { return }

        let inClosedSurfaceArea = isPointInClosedSurfaceArea(screenLocation)
        let mode = model.overlayPlacementDiagnostics?.mode
            ?? placementDiagnostics(preferredScreenID: nil)?.mode
            ?? .notch

        if Self.shouldArmClosedSurfaceHoverOpen(
            status: model.notchStatus,
            mode: mode,
            isPressingClosedTopBarPill: isPressingClosedTopBarPill
        ) {
            if inClosedSurfaceArea {
                scheduleHoverOpen()
            } else {
                cancelHoverOpen()
            }
        }

        if model.shouldAutoCollapseOnMouseLeave {
            if isPointInExpandedArea(screenLocation) {
                model.notePointerInsideIslandSurface()
            } else {
                model.handlePointerExitedIslandSurface()
            }
        }
    }

    private func handleMouseDown(_ screenLocation: NSPoint) {
        guard let model else { return }

        let inClosedSurfaceArea = isPointInClosedSurfaceArea(screenLocation)
        let mode = model.overlayPlacementDiagnostics?.mode
            ?? placementDiagnostics(preferredScreenID: nil)?.mode
            ?? .notch

        if model.notchStatus == .closed && inClosedSurfaceArea {
            let panelIgnoresMouseEvents = panel?.ignoresMouseEvents ?? true
            guard Self.shouldEventMonitorHandleClosedSurfaceClick(
                status: model.notchStatus,
                mode: mode,
                panelIgnoresMouseEvents: panelIgnoresMouseEvents
            ) else {
                return
            }
            cancelHoverOpenImmediately()
            model.notchOpen(reason: .click)
        } else if model.notchStatus == .opened {
            if !isPointInExpandedArea(screenLocation) {
                model.notchClose()
                repostMouseDown(at: screenLocation)
            }
        }
    }

    /// Grace period before a hover-open timer is cancelled.  Prevents
    /// mouse jitter at the notch edge from resetting the delay.
    private static let hoverCancelGracePeriod: TimeInterval = 0.1

    private func scheduleHoverOpen() {
        // Mouse re-entered during grace period — just revoke the cancel.
        hoverCancelGrace?.cancel()
        hoverCancelGrace = nil

        guard let model else { return }

        if model.showsIdleEdgeWhenCollapsed {
            performHoverOpen(model)
            return
        }

        guard hoverTimer == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self, let model = self.model else { return }
            self.performHoverOpen(model)
            self.hoverTimer = nil
        }

        hoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + AppModel.hoverOpenDelay, execute: item)
    }

    private func performHoverOpen(_ model: AppModel) {
        guard model.notchStatus == .closed else { return }

        if model.hapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(
                NSHapticFeedbackManager.FeedbackPattern.alignment,
                performanceTime: .now
            )
        }

        model.notchOpen(reason: .hover)
    }

    private func cancelHoverOpen() {
        guard hoverTimer != nil else { return }

        // Don't cancel immediately — allow a short grace period so that
        // mouse jitter at the notch edge doesn't restart the timer.
        guard hoverCancelGrace == nil else { return }

        let grace = DispatchWorkItem { [weak self] in
            self?.hoverTimer?.cancel()
            self?.hoverTimer = nil
            self?.hoverCancelGrace = nil
        }

        hoverCancelGrace = grace
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.hoverCancelGracePeriod,
            execute: grace
        )
    }

    /// Cancel without grace period — used for click-to-open where the
    /// hover timer must not fire after the click already opened the panel.
    private func cancelHoverOpenImmediately() {
        hoverCancelGrace?.cancel()
        hoverCancelGrace = nil
        hoverTimer?.cancel()
        hoverTimer = nil
    }

    // MARK: - Hit testing geometry

    func isPointInClosedSurfaceArea(_ screenPoint: NSPoint) -> Bool {
        guard let model else { return false }

        if let closedSurfaceRect = closedSurfaceRect(for: model) {
            return closedSurfaceRect.contains(screenPoint)
        }

        let expandedNotch = notchRect.insetBy(dx: -20, dy: -10)
        return expandedNotch.contains(screenPoint)
    }

    func isPointInExpandedArea(_ screenPoint: NSPoint) -> Bool {
        guard let model, model.notchStatus == .opened else {
            return isPointInClosedSurfaceArea(screenPoint)
        }

        guard let panel else {
            return false
        }

        // The window is always at opened size, but the visible content area
        // is the inner content rect (excluding shadow insets).
        guard let contentRect = contentRect(for: model, in: panel.frame) else {
            return false
        }

        return contentRect.contains(screenPoint)
    }

    func openedPanelWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return 820 }
        return min(
            max(screen.visibleFrame.width * Self.openedPanelWidthFactor, Self.minimumOpenedPanelWidth),
            min(Self.maximumOpenedPanelWidth, screen.visibleFrame.width - 32)
        )
    }

    func notificationPanelWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else {
            return Self.preferredNotificationPanelWidth
        }

        return min(Self.preferredNotificationPanelWidth, screen.visibleFrame.width - 32)
    }

    func contentRect(for model: AppModel, in bounds: NSRect) -> NSRect? {
        let insets = panelShadowInsets(for: model)
        return NSRect(
            x: bounds.minX + insets.horizontal,
            y: bounds.minY + insets.bottom,
            width: max(0, bounds.width - (insets.horizontal * 2)),
            height: max(0, bounds.height - insets.bottom)
        )
    }

    nonisolated static func closedSurfaceRect(
        notchRect: NSRect,
        closedWidth: CGFloat
    ) -> NSRect {
        NSRect(
            x: notchRect.midX - closedWidth / 2,
            y: notchRect.minY,
            width: closedWidth,
            height: notchRect.height
        )
    }

    nonisolated static func hiddenIdleEdgeHoverRect(
        notchRect: NSRect,
        closedWidth: CGFloat,
        hoverHitHeight: CGFloat
    ) -> NSRect {
        let cx = notchRect.midX
        let effectiveHeight = min(notchRect.height, max(1, hoverHitHeight))
        return NSRect(
            x: cx - closedWidth / 2,
            y: notchRect.maxY - effectiveHeight,
            width: closedWidth,
            height: effectiveHeight
        )
    }

    nonisolated static func closedPanelWidth(
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        liveSessionCount: Int,
        hasAttention: Bool,
        notchStatus: NotchStatus,
        showsIdleEdgeWhenCollapsed: Bool
    ) -> CGFloat {
        let popWidth = notchStatus == .popping ? 18 : 0

        guard !showsIdleEdgeWhenCollapsed else {
            return notchWidth + CGFloat(popWidth)
        }

        guard liveSessionCount > 0 else {
            return notchWidth
        }

        let sideWidth = max(0, notchHeight - 12) + 10
        let digits = max(1, "\(liveSessionCount)".count)
        let countBadgeWidth = CGFloat(26 + max(0, digits - 1) * 8)
        let leftWidth = sideWidth + 8 + (hasAttention ? 18 : 0)
        let rightWidth = max(sideWidth, countBadgeWidth)
        let expansionWidth = leftWidth + rightWidth + 16 + (hasAttention ? 6 : 0)
        return notchWidth + expansionWidth + CGFloat(popWidth)
    }

    private func closedSurfaceRect(for model: AppModel) -> NSRect? {
        guard let screen = resolveTargetScreen() else {
            return nil
        }

        let strategy = placementStrategy(for: screen)
        let anchor = pillAnchor(on: screen)
        let closedWidth = closedPanelWidth(for: model, on: screen)
        let closedHeight = screen.islandClosedHeight
        return strategy.closedHitRect(
            anchor: anchor,
            closedWidth: closedWidth,
            closedHeight: closedHeight
        )
    }

    private func panelFrame(for model: AppModel?, on screen: NSScreen) -> NSRect {
        let size = panelSize(for: model, on: screen)
        let strategy = placementStrategy(for: screen)
        return strategy.frame(
            anchor: pillAnchor(on: screen),
            size: size,
            screenVisibleFrame: screen.visibleFrame
        )
    }

    private func placementStrategy(for screen: NSScreen) -> OverlayPlacementStrategy {
        OverlayPlacementStrategy(mode: OverlayDisplayResolver.placementMode(for: screen))
    }

    /// Always returns the maximum (opened) panel size so the window never
    /// needs to resize.  All visual transitions are driven purely by SwiftUI
    /// inside this fixed-size window.
    private func panelSize(for model: AppModel?, on screen: NSScreen) -> CGSize {
        let insets = panelShadowInsets(for: model)
        let openedHeaderAllowance = OverlayClosedShellMetrics.openedHeaderAllowance(
            forClosedHeight: screen.islandClosedHeight
        )

        guard let model else {
            return CGSize(
                width: openedPanelWidth(for: screen) + Self.openedContentWidthPadding + (insets.horizontal * 2),
                height: openedHeaderAllowance + Self.openedEmptyStateHeight + Self.openedContentBottomPadding + insets.bottom
            )
        }

        switch model.notchStatus {
        case .opened:
            let panelWidth = model.showsNotificationCard
                ? notificationPanelWidth(for: screen)
                : openedPanelWidth(for: screen)
            return CGSize(
                width: panelWidth + Self.openedContentWidthPadding + (insets.horizontal * 2),
                height: openedHeaderAllowance + openedContentHeight(for: model) + Self.openedContentBottomPadding + insets.bottom
            )
        case .closed, .popping:
            return CGSize(
                width: closedPanelWidth(for: model, on: screen) + (insets.horizontal * 2),
                height: screen.islandClosedHeight + insets.bottom
            )
        }
    }

    private func panelShadowInsets(for model: AppModel?) -> (horizontal: CGFloat, bottom: CGFloat) {
        let usesOpenedInsets = model.map { $0.notchStatus == .opened || $0.isOverlayCloseTransitionPending } ?? true
        return IslandChromeMetrics.panelShadowInsets(usesOpenedVisualState: usesOpenedInsets)
    }

    private func closedPanelWidth(for model: AppModel, on screen: NSScreen) -> CGFloat {
        let baseClosedWidth = screen.notchSize.width
        let closedHeight = screen.islandClosedHeight
        let mode = OverlayDisplayResolver.placementMode(for: screen)
        let metrics = OverlayClosedShellMetrics.forMode(
            mode,
            closedHeight: closedHeight
        )
        let spotlightSession = model.surfacedSessions.first(where: { $0.phase.requiresAttention })
            ?? model.surfacedSessions.first(where: { $0.phase == .running })
            ?? model.surfacedSessions.first
        return metrics.closedSurfaceWidth(
            baseClosedWidth: baseClosedWidth,
            liveCount: model.liveSessionCount,
            hasAttention: spotlightSession?.phase.requiresAttention == true,
            isPopping: model.notchStatus == .popping
        )
    }

    private func currentClosedWidth(on screen: NSScreen) -> CGFloat {
        guard let model else {
            return screen.notchSize.width
        }
        return closedPanelWidth(for: model, on: screen)
    }

    private func openedContentHeight(for model: AppModel) -> CGFloat {
        let now = Date.now
        let visibleSessions = openedVisibleSessions(
            sessions: model.islandListSessions
        )

        if visibleSessions.isEmpty {
            return Self.openedEmptyStateHeight
        }

        let actionableID = model.islandSurface.sessionID
        let isNotificationMode = model.notchOpenReason == .notification && actionableID != nil

        if isNotificationMode {
            // Use SwiftUI-measured height when available (accurate after first render).
            if model.measuredNotificationContentHeight > 0 {
                return model.measuredNotificationContentHeight + 28
            }
            // First render: estimate from the actionable session's content so the
            // initial window is close to the final size. This avoids a large blank
            // panel flash (the previous 500pt fallback) and reduces the chance of
            // a measurement→reposition cycle.
            if let actionableID,
               let session = model.state.session(id: actionableID) {
                let rowHeight = session.estimatedIslandRowHeight(at: now)
                let bodyHeight = actionableBodyHeight(for: session, model: model)
                return rowHeight + bodyHeight + Self.openedContentVerticalInsets
            }
            return 300
        }

        let rowHeights = visibleSessions.map { session -> CGFloat in
            if session.id == actionableID {
                return session.estimatedIslandRowHeight(at: now)
                    + actionableBodyHeight(for: session, model: model)
            }
            return session.estimatedIslandRowHeight(at: now)
        }

        let rowsHeight = rowHeights.reduce(CGFloat.zero, +)
        let spacingHeight = CGFloat(max(0, rowHeights.count - 1)) * Self.openedRowSpacing
        let listHeight = rowsHeight + spacingHeight
        // Cap to match AutoHeightScrollView's maxHeight in IslandPanelView.
        let cappedListHeight = min(listHeight, Self.maxSessionListHeight)
        return cappedListHeight + Self.openedContentVerticalInsets
    }

    /// Additional height for the actionable session's inline action area.
    private func actionableBodyHeight(for session: AgentSession, model: AppModel) -> CGFloat {
        switch session.phase {
        case .waitingForApproval:
            return Self.approvalCardHeight - 44
        case .waitingForAnswer:
            return questionCardHeight(for: session.questionPrompt) - 44
        case .completed:
            return completionBodyHeight(for: session)
        case .running:
            return 0
        }
    }

    /// Height of the inline completion expansion area (not the old full-card height).
    private func completionBodyHeight(for session: AgentSession) -> CGFloat {
        let headerHeight: CGFloat = 44

        let text = (session.lastAssistantMessageText ?? session.summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return headerHeight
        }

        let availableWidth = Self.preferredNotificationPanelWidth - 96
        let font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let markdownHeight = min(260, ceil(textSize.height) + 20)
        return headerHeight + 1 + markdownHeight
    }

    private func questionCardHeight(for prompt: QuestionPrompt?) -> CGFloat {
        Self.questionCardHeight
    }

    private func completionCardHeight(for model: AppModel) -> CGFloat {
        guard let session = model.activeIslandCardSession else {
            return Self.completionCardMinHeight
        }

        let text = (session.lastAssistantMessageText ?? session.summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Estimate text height using NSString measurement with the actual font.
        // Available text width ≈ notificationPanelWidth - card horizontal chrome
        // Card chrome: openedContent padding (18*2) + card padding (16*2) + text padding (14*2) = 96
        let availableWidth = Self.preferredNotificationPanelWidth - 96
        let font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )

        let estimatedHeight = Self.completionCardChromeHeight + ceil(textSize.height)
        // Use a smaller minimum to avoid blank space when content is short
        let minHeight: CGFloat = Self.completionCardChromeHeight + 20
        return min(Self.completionCardMaxHeight, max(minHeight, estimatedHeight))
    }

    private func openedVisibleSessions(sessions: [AgentSession]) -> [AgentSession] {
        Array(sessions.prefix(Self.maxVisibleSessionRows))
    }

    // MARK: - Event reposting

    private func repostMouseDown(at screenPoint: NSPoint) {
        let flippedY = NSScreen.main.map { $0.frame.height - screenPoint.y } ?? screenPoint.y

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: screenPoint.x, y: flippedY),
            mouseButton: .left
        ) else { return }

        event.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard let upEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: CGPoint(x: screenPoint.x, y: flippedY),
                mouseButton: .left
            ) else { return }
            upEvent.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - NotchPanel

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - NotchHostingView

private let pillDragThreshold: CGFloat = 4

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var notchController: OverlayPanelController?

    // Drag tracking state for topBar-mode pill repositioning.
    private var dragStartMouse: NSPoint?
    private var dragStartPanelOrigin: NSPoint?
    private var isTrackingPillDrag = false
    private var didMovePillWhileTracking = false
    private var dragStartedFromOpenedTopBarHeader = false
    private var didTransitionOpenedHeaderDragToClosedPill = false

    override var isOpaque: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let rawDownPointInView = convert(event.locationInWindow, from: nil)
        let downPointInView = OverlayPanelController.normalizeEventPointForOverlayGeometry(
            rawDownPointInView,
            viewHeight: bounds.height
        )
        let canDragClosedPill = notchController?.canDragPillNow() == true
        let canDragOpenedHeader = notchController?.shouldCaptureOpenedTopBarHeaderDrag(
            at: downPointInView,
            in: bounds
        ) == true
        let notchStatusDescription = notchController?.model.map { String(describing: $0.notchStatus) } ?? "nil"
        let openReasonDescription = notchController?.model.map { String(describing: $0.notchOpenReason) } ?? "nil"
        overlayDragLog(
            "mouseDown entry rawPoint=\(overlayDragPointDescription(rawDownPointInView)) normalizedPoint=\(overlayDragPointDescription(downPointInView)) canDragClosedPill=\(canDragClosedPill) canDragOpenedHeader=\(canDragOpenedHeader) status=\(notchStatusDescription) reason=\(openReasonDescription)"
        )

        // On external displays (topBar mode) with a closed pill, take over
        // mouse handling so we can implement drag-to-reposition + click-to-open.
        // On the built-in notch screen, or when opened, fall through to the
        // legacy SwiftUI-driven behavior.
        if canDragClosedPill, let window {
            window.makeKey()
            notchController?.beginClosedTopBarPress()
            dragStartMouse = NSEvent.mouseLocation
            dragStartPanelOrigin = window.frame.origin
            isTrackingPillDrag = true
            didMovePillWhileTracking = false
            dragStartedFromOpenedTopBarHeader = false
            didTransitionOpenedHeaderDragToClosedPill = false
            overlayDragLog(
                "mouseDown closedPill startMouse=\(overlayDragPointDescription(dragStartMouse ?? .zero)) panelOrigin=\(overlayDragPointDescription(dragStartPanelOrigin ?? .zero))"
            )
            return
        }

        if canDragOpenedHeader, let window {
            window.makeKey()
            dragStartMouse = NSEvent.mouseLocation
            dragStartPanelOrigin = window.frame.origin
            isTrackingPillDrag = true
            didMovePillWhileTracking = false
            dragStartedFromOpenedTopBarHeader = true
            didTransitionOpenedHeaderDragToClosedPill = false
            overlayDragLog(
                "mouseDown openedHeader point=\(overlayDragPointDescription(downPointInView)) startMouse=\(overlayDragPointDescription(dragStartMouse ?? .zero)) panelOrigin=\(overlayDragPointDescription(dragStartPanelOrigin ?? .zero)) frame=\(overlayDragRectDescription(window.frame))"
            )
            return
        }

        // Ensure the panel is key before SwiftUI processes the click.
        // With nonactivatingPanel, hover-opened panels aren't key, so
        // SwiftUI Button may consume the first click for key acquisition
        // instead of firing its action.
        overlayDragLog("mouseDown fallbackToSwiftUI point=\(overlayDragPointDescription(downPointInView))")
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingPillDrag,
              let start = dragStartMouse,
              let originAtStart = dragStartPanelOrigin else {
            overlayDragLog(
                "mouseDragged ignoredWithoutTracking point=\(overlayDragPointDescription(convert(event.locationInWindow, from: nil)))"
            )
            super.mouseDragged(with: event)
            return
        }

        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        let dragDistance = hypot(dx, dy)

        let plan = OverlayPanelController.openedTopBarHeaderDragPlan(
            startedFromOpenedTopBarHeader: dragStartedFromOpenedTopBarHeader,
            didTransitionToClosedPill: didTransitionOpenedHeaderDragToClosedPill,
            dragDistance: dragDistance,
            threshold: pillDragThreshold
        )
        let formattedDragDistance = String(format: "%.2f", dragDistance)
        overlayDragLog(
            "mouseDragged plan=\(String(describing: plan)) startMouse=\(overlayDragPointDescription(start)) currentMouse=\(overlayDragPointDescription(current)) panelOrigin=\(overlayDragPointDescription(originAtStart)) distance=\(formattedDragDistance) transitioned=\(didTransitionOpenedHeaderDragToClosedPill)"
        )

        switch plan {
        case .waitForThreshold:
            return
        case .startClosedPillDrag:
            notchController?.beginOpenedTopBarHeaderDrag()
            dragStartMouse = current
            if let window {
                let transition = OverlayPanelController.openedTopBarHeaderDragTransition(
                    originalDragStartMouse: start,
                    currentMouse: current,
                    collapsedPillOrigin: window.frame.origin
                )
                dragStartMouse = transition.continuedDragStartMouse
                dragStartPanelOrigin = transition.continuedDragStartPanelOrigin
                notchController?.moveDraggedPanel(to: transition.immediatePanelOrigin)
                overlayDragLog(
                    "mouseDragged transitionedToClosedPill immediateOrigin=\(overlayDragPointDescription(transition.immediatePanelOrigin)) continuedStartMouse=\(overlayDragPointDescription(transition.continuedDragStartMouse)) continuedPanelOrigin=\(overlayDragPointDescription(transition.continuedDragStartPanelOrigin)) windowFrame=\(overlayDragRectDescription(window.frame))"
                )
            }
            didMovePillWhileTracking = true
            didTransitionOpenedHeaderDragToClosedPill = true
            return
        case .continueClosedPillDrag:
            break
        }

        if !didMovePillWhileTracking && dragDistance < pillDragThreshold {
            return
        }

        didMovePillWhileTracking = true
        notchController?.moveDraggedPanel(
            to: NSPoint(x: originAtStart.x + dx, y: originAtStart.y + dy)
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingPillDrag else {
            overlayDragLog(
                "mouseUp ignoredWithoutTracking point=\(overlayDragPointDescription(convert(event.locationInWindow, from: nil)))"
            )
            super.mouseUp(with: event)
            return
        }

        let didMove = didMovePillWhileTracking
        let startedFromOpenedHeader = dragStartedFromOpenedTopBarHeader
        let didTransitionToClosedPill = didTransitionOpenedHeaderDragToClosedPill
        isTrackingPillDrag = false
        dragStartMouse = nil
        dragStartPanelOrigin = nil
        didMovePillWhileTracking = false
        dragStartedFromOpenedTopBarHeader = false
        didTransitionOpenedHeaderDragToClosedPill = false

        overlayDragLog(
            "mouseUp didMove=\(didMove) startedFromOpenedHeader=\(startedFromOpenedHeader) transitionedToClosedPill=\(didTransitionToClosedPill)"
        )

        for action in OverlayPanelController.topBarDragReleaseActions(
            didMove: didMove,
            startedFromOpenedTopBarHeader: startedFromOpenedHeader,
            didTransitionToClosedPill: didTransitionToClosedPill
        ) {
            switch action {
            case .persistDraggedPosition:
                notchController?.persistDraggedPillPosition()
            case .endClosedTopBarPress:
                notchController?.endClosedTopBarPress()
            case .handlePillClick:
                notchController?.handlePillClickFromDragLayer()
            }
        }
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparency()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller = notchController,
              let model = controller.model else {
            return nil
        }

        guard let contentRect = controller.contentRect(for: model, in: bounds),
              contentRect.contains(point) else {
            return nil
        }

        // On external displays in closed state, take over hit testing so our
        // mouseDown override (drag vs click) runs instead of SwiftUI's inner
        // NSHostingView subtree swallowing the event. Without this, tapping
        // the pill lands on a SwiftUI-managed subview and mouseDown never
        // bubbles up to NotchHostingView.
        if controller.shouldCaptureTopBarDragLayerHit(
            at: point,
            in: bounds
        ) {
            overlayDragLog("hitTest captured point=\(overlayDragPointDescription(point))")
            return self
        }

        return super.hitTest(point)
    }

    private func convertToScreen(_ viewPoint: NSPoint) -> NSPoint {
        guard let window else { return viewPoint }
        let windowPoint = convert(viewPoint, to: nil)
        return window.convertPoint(toScreen: windowPoint)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparency()
    }

    private func configureTransparency() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        // NSHostingView wraps content in internal NSScrollViews.
        // SwiftUI may recreate them when the view tree changes (e.g.
        // AutoHeightScrollView toggling between scroll/non-scroll mode),
        // so we must re-disable on every layout pass.
        // Guard: only modify properties when they differ to avoid
        // triggering additional layout passes that could loop.
        disableInternalScrollers(in: self)
    }

    private func disableInternalScrollers(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            return
        }
        for child in view.subviews {
            disableInternalScrollers(in: child)
        }
    }
}

// MARK: - NotchEventMonitors

@MainActor
final class NotchEventMonitors {
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var lastMoveTime: TimeInterval = 0

    var isActive: Bool { globalMoveMonitor != nil }

    func start(
        mouseMoveHandler: @MainActor @escaping @Sendable (NSPoint) -> Void,
        mouseDownHandler: @MainActor @escaping @Sendable (NSPoint) -> Void
    ) {
        let throttleInterval: TimeInterval = 0.05

        nonisolated(unsafe) var sharedLastMove: TimeInterval = 0

        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastMove >= throttleInterval else { return }
            sharedLastMove = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseMoveHandler(location) }
        }

        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastMove >= throttleInterval else { return event }
            sharedLastMove = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseMoveHandler(location) }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDownHandler(location) }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDownHandler(location) }
            return event
        }
    }

    func stop() {
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = localMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localClickMonitor { NSEvent.removeMonitor(m) }
        globalMoveMonitor = nil
        localMoveMonitor = nil
        globalClickMonitor = nil
        localClickMonitor = nil
    }
}

// MARK: - NSScreen notch size helper

extension NSScreen {
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            // Non-notch screen: tight floating pill that fits exactly
            // icon (12pt) + gap (6) + count badge (~26) + horizontal
            // padding (~12) ≈ 56pt wide.
            return CGSize(width: 56, height: 22)
        }

        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = frame.width - leftPadding - rightPadding + 4

        return CGSize(width: notchWidth, height: notchHeight)
    }

    var topStatusBarHeight: CGFloat {
        let reservedTopInset = max(0, frame.maxY - visibleFrame.maxY)
        if reservedTopInset > 0 {
            return reservedTopInset
        }

        if safeAreaInsets.top > 0 {
            return safeAreaInsets.top
        }

        return 24
    }

    var islandClosedHeight: CGFloat {
        NSScreen.computeIslandClosedHeight(
            safeAreaInsetsTop: safeAreaInsets.top,
            topStatusBarHeight: topStatusBarHeight
        )
    }

    /// Pure helper so the height selection logic can be unit-tested without real screen hardware.
    ///
    /// On notch screens, clamp to `min(safeAreaInsetsTop, topStatusBarHeight)`: the island
    /// must not exceed the menu bar reserved area, and must not exceed the physical notch
    /// height — e.g. MacBook Air M2 notch ≈ 34 pt while menu bar reserved ≈ 37 pt, so
    /// the island should be 34 pt to sit flush with the notch bottom.
    /// On non-notch screens (`safeAreaInsetsTop == 0`), use a compact 22pt pill height
    /// that matches `notchSize.height` — the closed pill only shows an icon + count badge
    /// so it doesn't need to fill the full menu-bar strip.
    static func computeIslandClosedHeight(
        safeAreaInsetsTop: CGFloat,
        topStatusBarHeight: CGFloat
    ) -> CGFloat {
        if safeAreaInsetsTop > 0 {
            return min(safeAreaInsetsTop, topStatusBarHeight)
        }
        return 22
    }
}
