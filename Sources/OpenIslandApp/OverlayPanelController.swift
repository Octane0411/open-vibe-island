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

    /// Fade the panel out, then call completion so the caller can snap state.
    func fadeOutAndClose(
        duration: TimeInterval,
        completion: @escaping @MainActor () -> Void
    ) {
        guard let panel else {
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in completion() }
        })
    }

    /// Restore panel alpha after a fade-out close.
    func restoreAlpha() {
        panel?.alphaValue = 1
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
        let usesOpenedInsets = model.map { $0.notchStatus == .opened || $0.isOverlayCloseTransitionPending } ?? true

        if usesOpenedInsets {
            return (
                horizontal: IslandChromeMetrics.openedShadowHorizontalInset,
                bottom: IslandChromeMetrics.openedShadowBottomInset
            )
        }

        return (
            horizontal: IslandChromeMetrics.closedShadowHorizontalInset,
            bottom: IslandChromeMetrics.closedShadowBottomInset
        )
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
        let countBadgeWidth = CGFloat(26 + max(0, digits - 1) * 8)
        let hasAttention = spotlightSession?.phase.requiresAttention == true
        let leftWidth = sideWidth + 8 + (hasAttention ? 18 : 0)
        let rightWidth = max(sideWidth, countBadgeWidth)
        let expansionWidth = leftWidth + rightWidth + 16 + (hasAttention ? 6 : 0)
        let popWidth = model.notchStatus == .popping ? 18 : 0
        return notchWidth + expansionWidth + CGFloat(popWidth)
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
            // First render: use generous height so content isn't clipped.
            // SwiftUI will measure actual height and trigger a resize.
            return 500
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
            return completionBodyHeight(for: session, model: model)
        case .running:
            return 0
        }
    }

    /// Height of the inline completion expansion area (not the old full-card height).
    private func completionBodyHeight(for session: AgentSession, model: AppModel) -> CGFloat {
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
        // Reply input: divider (1) + input bar padding+content (~52)
        let replyInputHeight: CGFloat = TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled) ? 53 : 0
        return headerHeight + 1 + markdownHeight + replyInputHeight
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

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var notchController: OverlayPanelController?

    override var isOpaque: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        // Ensure the panel is key before SwiftUI processes the click.
        // With nonactivatingPanel, hover-opened panels aren't key, so
        // SwiftUI Button may consume the first click for key acquisition
        // instead of firing its action.
        window?.makeKey()
        super.mouseDown(with: event)
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

    override func layout() {
        super.layout()
        // NSHostingView wraps content in internal NSScrollViews.
        // SwiftUI may recreate them when the view tree changes (e.g.
        // AutoHeightScrollView toggling between scroll/non-scroll mode),
        // so we must re-disable on every layout pass.
        disableInternalScrollers(in: self)
    }

    private func disableInternalScrollers(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.scrollerStyle = .overlay
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
    /// On non-notch screens (`safeAreaInsetsTop == 0`), use `topStatusBarHeight` directly.
    static func computeIslandClosedHeight(
        safeAreaInsetsTop: CGFloat,
        topStatusBarHeight: CGFloat
    ) -> CGFloat {
        if safeAreaInsetsTop > 0 {
            return min(safeAreaInsetsTop, topStatusBarHeight)
        }
        return topStatusBarHeight
    }
}
