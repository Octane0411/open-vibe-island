import AppKit
import Combine
import SwiftUI
import OpenIslandCore

@MainActor
final class OverlayPanelController {
    private static let minimumOpenedPanelWidth: CGFloat = 680
    private static let maximumOpenedPanelWidth: CGFloat = 740
    private static let openedPanelWidthFactor: CGFloat = 0.46
    private static let preferredNotificationPanelWidth: CGFloat = 620
    private static let openedContentWidthPadding: CGFloat = 28
    private static let openedContentBottomPadding: CGFloat = 14
    private static let maxVisibleSessionRows: Int = 6
    private static let openedExpandedRowHeight: CGFloat = 76
    private static let openedCollapsedRowHeight: CGFloat = 44
    private static let openedHiddenRowHeight: CGFloat = 42
    private static let openedRowSpacing: CGFloat = 4
    private static let openedContentVerticalInsets: CGFloat = 28
    private static let openedEmptyStateHeight: CGFloat = 108
    private static let approvalCardHeight: CGFloat = 288
    private static let simpleQuestionCardHeight: CGFloat = 248
    private static let structuredQuestionCardBaseHeight: CGFloat = 312
    private static let structuredQuestionCardPerQuestionHeight: CGFloat = 82
    private static let structuredQuestionCardMaximumHeight: CGFloat = 448
    private static let completionCardHeight: CGFloat = 214

    private var panel: NotchPanel?
    private var eventMonitors = NotchEventMonitors()
    private var hoverTimer: DispatchWorkItem?
    weak var model: AppModel?
    private(set) var notchRect: NSRect = .zero

    var isVisible: Bool {
        panel?.isVisible == true
    }

    nonisolated static func shouldActivatePanel(for reason: NotchOpenReason?) -> Bool {
        reason == .click
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
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
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
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = panelAnimationDuration(for: model?.notchStatus)
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(windowFrame, display: true)
            }
        } else {
            panel.setFrame(windowFrame, display: true)
        }
        computeNotchRect(screen: screen)

        return OverlayDisplayResolver.diagnostics(
            preferredScreenID: preferredScreenID,
            panelSize: panel.frame.size
        )
    }

    private func panelAnimationDuration(for status: NotchStatus?) -> TimeInterval {
        switch status {
        case .opened:
            0.34
        case .closed, .popping:
            0.26
        case nil:
            0
        }
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
        let screenFrame = screen.frame
        let notchX = screenFrame.midX - notchSize.width / 2
        let notchY = screenFrame.maxY - notchSize.height
        notchRect = NSRect(x: notchX, y: notchY, width: notchSize.width, height: notchSize.height)
    }

    private func resolveTargetScreen(preferredScreenID: String? = nil) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let preferredScreenID,
           let screen = screens.first(where: { screenID(for: $0) == preferredScreenID }) {
            return screen
        }

        if let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }

        return NSScreen.main ?? screens[0]
    }

    private func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return screen.localizedName
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

        if model.notchStatus == .closed && inClosedSurfaceArea {
            scheduleHoverOpen()
        } else if model.notchStatus == .closed && !inClosedSurfaceArea {
            cancelHoverOpen()
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

        if model.notchStatus == .closed && inClosedSurfaceArea {
            cancelHoverOpen()
            model.notchOpen(reason: .click)
        } else if model.notchStatus == .opened {
            if !isPointInExpandedArea(screenLocation) {
                model.notchClose()
                repostMouseDown(at: screenLocation)
            }
        }
    }

    private func scheduleHoverOpen() {
        guard hoverTimer == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self, let model = self.model else { return }
            if model.notchStatus == .closed {
                model.notchOpen(reason: .hover)
            }
            self.hoverTimer = nil
        }

        hoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + AppModel.hoverOpenDelay, execute: item)
    }

    private func cancelHoverOpen() {
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

        return panel.frame.contains(screenPoint)
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
        for panelFrame: NSRect,
        shadowInsets: (horizontal: CGFloat, bottom: CGFloat)
    ) -> NSRect {
        NSRect(
            x: panelFrame.minX + shadowInsets.horizontal,
            y: panelFrame.minY + shadowInsets.bottom,
            width: max(0, panelFrame.width - (shadowInsets.horizontal * 2)),
            height: max(0, panelFrame.height - shadowInsets.bottom)
        )
    }

    private func closedSurfaceRect(for model: AppModel) -> NSRect? {
        guard let panel else {
            return nil
        }

        return Self.closedSurfaceRect(
            for: panel.frame,
            shadowInsets: panelShadowInsets(for: model)
        )
    }

    private func panelFrame(for model: AppModel?, on screen: NSScreen) -> NSRect {
        let size = panelSize(for: model, on: screen)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func panelSize(for model: AppModel?, on screen: NSScreen) -> CGSize {
        let insets = panelShadowInsets(for: model)

        guard let model else {
            return CGSize(
                width: openedPanelWidth(for: screen) + Self.openedContentWidthPadding + (insets.horizontal * 2),
                height: screen.notchSize.height + Self.openedEmptyStateHeight + Self.openedContentBottomPadding + insets.bottom
            )
        }

        switch model.notchStatus {
        case .opened:
            let panelWidth = model.showsNotificationCard
                ? notificationPanelWidth(for: screen)
                : openedPanelWidth(for: screen)
            return CGSize(
                width: panelWidth + Self.openedContentWidthPadding + (insets.horizontal * 2),
                height: screen.notchSize.height + openedContentHeight(for: model) + Self.openedContentBottomPadding + insets.bottom
            )
        case .closed, .popping:
            return CGSize(
                width: closedPanelWidth(for: model, on: screen) + (insets.horizontal * 2),
                height: screen.islandClosedHeight + insets.bottom
            )
        }
    }

    private func panelShadowInsets(for model: AppModel?) -> (horizontal: CGFloat, bottom: CGFloat) {
        switch model?.notchStatus {
        case .opened, nil:
            return (
                horizontal: IslandChromeMetrics.openedShadowHorizontalInset,
                bottom: IslandChromeMetrics.openedShadowBottomInset
            )
        case .closed, .popping:
            return (
                horizontal: IslandChromeMetrics.closedShadowHorizontalInset,
                bottom: IslandChromeMetrics.closedShadowBottomInset
            )
        }
    }

    private func closedPanelWidth(for model: AppModel, on screen: NSScreen) -> CGFloat {
        let notchWidth = screen.notchSize.width
        let notchHeight = screen.islandClosedHeight
        let spotlightSession = model.surfacedSessions.first(where: { $0.phase.requiresAttention })
            ?? model.surfacedSessions.first(where: { $0.phase == .running })
            ?? model.surfacedSessions.first
        let hasClosedPresence = model.liveSessionCount > 0

        guard hasClosedPresence else {
            return notchWidth
        }

        let sideWidth = max(0, notchHeight - 12) + 10
        let digits = max(1, "\(model.liveSessionCount)".count)
        let countBadgeWidth = CGFloat(18 + max(0, digits - 1) * 7)
        let hasAttention = spotlightSession?.phase.requiresAttention == true
        let leftWidth = sideWidth + 8 + (hasAttention ? 18 : 0)
        let rightWidth = max(sideWidth, countBadgeWidth)
        let expansionWidth = leftWidth + rightWidth + 16 + (hasAttention ? 6 : 0)
        let popWidth = model.notchStatus == .popping ? 18 : 0
        return notchWidth + expansionWidth + CGFloat(popWidth)
    }

    private func openedContentHeight(for model: AppModel) -> CGFloat {
        if model.showsNotificationCard {
            switch model.islandSurface {
            case .approvalCard:
                return Self.approvalCardHeight
            case .questionCard:
                return questionCardHeight(for: model.activeIslandCardSession?.questionPrompt)
            case .completionCard:
                return Self.completionCardHeight
            case .sessionList:
                break
            }
        }

        let now = Date.now
        let presentation = openedSessionListPresentation(
            sessions: model.islandListSessions,
            referenceDate: now
        )

        if presentation.visibleSessions.isEmpty {
            return Self.openedEmptyStateHeight
        }

        var rowHeights = presentation.visibleSessions.map { session in
            session.islandPresence(at: now) == .inactive
                ? Self.openedCollapsedRowHeight
                : Self.openedExpandedRowHeight
        }

        if presentation.hiddenSessionCount > 0 {
            rowHeights.append(Self.openedHiddenRowHeight)
        }

        let rowsHeight = rowHeights.reduce(CGFloat.zero, +)
        let spacingHeight = CGFloat(max(0, rowHeights.count - 1)) * Self.openedRowSpacing
        return rowsHeight + spacingHeight + Self.openedContentVerticalInsets
    }

    private func questionCardHeight(for prompt: QuestionPrompt?) -> CGFloat {
        guard let prompt else {
            return Self.simpleQuestionCardHeight
        }

        let structuredQuestionCount = prompt.questions.count
        guard structuredQuestionCount > 0 else {
            return Self.simpleQuestionCardHeight
        }

        let questionBlocksHeight = CGFloat(structuredQuestionCount) * Self.structuredQuestionCardPerQuestionHeight
        return min(
            Self.structuredQuestionCardMaximumHeight,
            Self.structuredQuestionCardBaseHeight + questionBlocksHeight
        )
    }

    private func openedSessionListPresentation(
        sessions: [AgentSession],
        referenceDate: Date
    ) -> (visibleSessions: [AgentSession], hiddenSessionCount: Int) {
        guard sessions.count > Self.maxVisibleSessionRows else {
            return (sessions, 0)
        }

        let activeSessions = sessions.filter { $0.islandPresence(at: referenceDate) != .inactive }
        let inactiveSessions = sessions.filter { $0.islandPresence(at: referenceDate) == .inactive }
        let contentSlots = max(0, Self.maxVisibleSessionRows - 1)

        var visibleSessions = Array(activeSessions.prefix(contentSlots))

        if visibleSessions.count < contentSlots {
            let remainingSlots = contentSlots - visibleSessions.count
            visibleSessions.append(contentsOf: inactiveSessions.prefix(remainingSlots))
        }

        let hiddenSessionCount = max(0, sessions.count - visibleSessions.count)
        return (visibleSessions, hiddenSessionCount)
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

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var notchController: OverlayPanelController?

    override var isOpaque: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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

        return super.hitTest(point) ?? self
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
            return CGSize(width: 224, height: 38)
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
        topStatusBarHeight
    }
}
