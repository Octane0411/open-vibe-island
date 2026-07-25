import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import OpenIslandCore

@MainActor
final class OverlayPanelController {
    private static let preferredNotchOpenedPanelWidth: CGFloat = 540
    private static let preferredTopBarOpenedPanelWidth: CGFloat = 520
    private static let openedContentWidthPadding: CGFloat = 0
    private static let openedContentBottomPadding: CGFloat = 0
    /// Small cushion added on top of the SwiftUI-measured content height
    /// (AB-228). The measured value can land a couple of points short of
    /// what's actually needed depending on which padding/inset layer the
    /// measuring `GeometryReader` sits under; a few points of headroom here
    /// is far cheaper to reason about than chasing that discrepancy, and
    /// erring tall avoids reintroducing clipping.
    private static let measuredContentSafetyPadding: CGFloat = 8
    /// Height used only while sessions list is empty, or before the opened
    /// surface has been measured for the first time. This is a fixed UI
    /// constant (the empty-state/placeholder layout doesn't vary with agent
    /// content), unlike the old per-phase estimates it used to sit next to.
    private static let openedEmptyStateHeight: CGFloat = 108

    private var panel: NotchPanel?
    private var eventMonitors = NotchEventMonitors()
    private var keyCommandMonitor: Any?
    private var hoverTimer: DispatchWorkItem?
    private var hoverCancelGrace: DispatchWorkItem?
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
        // `.stationary` keeps the overlay pinned during the macOS Sonoma+
        // "click wallpaper to reveal desktop" gesture (and Mission Control
        // / Show Desktop). Without it the panel slides off-screen with the
        // user's other windows — on built-in notch displays it disappears
        // below the menu bar, and on external displays it falls out of the
        // top bar entirely.
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]
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

    /// Picks the screen to anchor the overlay to.
    ///
    /// Priority: persisted manual preference (matched via the stable
    /// `OverlayDisplayResolver.screenID` so a hotplug-reassigned
    /// `CGDirectDisplayID` can't silently re-target the wrong monitor) →
    /// first notched screen → `NSScreen.main` → first available screen.
    /// Returns `nil` only when no displays are connected.
    private func resolveTargetScreen(preferredScreenID: String? = nil) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let preferredScreenID,
           let screen = screens.first(where: { OverlayDisplayResolver.screenID(for: $0) == preferredScreenID }) {
            return screen
        }

        if let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }

        return NSScreen.main ?? screens[0]
    }

    // MARK: - Mouse event monitoring

    private func startEventMonitoring() {
        if model?.disablesOverlayEventMonitoringDuringHarness == true {
            return
        }

        if keyCommandMonitor == nil {
            keyCommandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handleOverlayKeyDown(event) else { return event }
                return nil
            }
        }

        guard !eventMonitors.isActive else { return }

        eventMonitors.start { [weak self] location in
            self?.handleMouseMoved(location)
        } mouseDownHandler: { [weak self] location in
            self?.handleMouseDown(location)
        }
    }

    // MARK: - Keyboard shortcuts (AB-227)

    /// Handles keyboard shortcuts on the visible approval/question card.
    /// Returns `true` when the event was fully handled (the caller swallows
    /// it); `false` lets it continue through normal AppKit dispatch.
    ///
    /// Focus guard: while a text field on the card is being edited (Reply /
    /// "Other" freeform fields), everything except Esc passes through
    /// untouched so typing digits or pressing Enter behaves like normal
    /// text entry — see `ReplyTextField`'s own IME-safe Enter handling.
    private func handleOverlayKeyDown(_ event: NSEvent) -> Bool {
        guard let model, model.isOverlayVisible,
              let panel, panel.isKeyWindow else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Plain Esc only — leave modified combos (e.g. ⌘⌥Esc Force Quit)
        // alone rather than reinterpreting them as "close the overlay".
        if event.keyCode == UInt16(kVK_Escape), flags.isEmpty {
            model.notchClose()
            return true
        }

        guard !(panel.firstResponder is NSText) else {
            return false
        }

        let characters = event.charactersIgnoringModifiers?.lowercased()

        if flags.contains(.command), characters == "y" {
            return flags.contains(.shift)
                ? handleAlwaysAllowShortcut(model)
                : handleApprovalShortcut(model, action: .allowOnce)
        }

        if flags.contains(.command), characters == "n" {
            return handleApprovalShortcut(model, action: .deny)
        }

        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            return model.overlay.handleQuestionSubmitKey()
        }

        if let characters, characters.count == 1,
           let digit = Int(characters), (1...9).contains(digit) {
            return model.overlay.handleQuestionOptionKey(digit - 1)
        }

        return false
    }

    private func handleApprovalShortcut(_ model: AppModel, action: ApprovalAction) -> Bool {
        guard let session = model.activeIslandCardSession, session.phase == .waitingForApproval,
              session.permissionRequest?.requiresTerminalApproval != true else {
            return false
        }
        model.approvePermission(for: session.id, action: action)
        return true
    }

    /// AB-235: prefers the first of Claude's actual `suggestedUpdates` (the
    /// scoped always-allow options rendered as stacked buttons on the card)
    /// so the shortcut applies the same real, correctly-scoped rule a click
    /// would. Falls back to synthesizing the original generic session-scoped
    /// rule when the request carried no suggestions (e.g. non-Claude agents),
    /// so the shortcut keeps working exactly as it did before AB-235.
    private func handleAlwaysAllowShortcut(_ model: AppModel) -> Bool {
        guard let session = model.activeIslandCardSession,
              session.phase == .waitingForApproval,
              let permissionRequest = session.permissionRequest,
              !permissionRequest.requiresTerminalApproval else {
            return false
        }

        if let firstSuggestedUpdate = permissionRequest.suggestedUpdates.first {
            model.approvePermission(for: session.id, action: .allowWithUpdates([firstSuggestedUpdate]))
            return true
        }

        guard let toolName = permissionRequest.toolName else {
            return false
        }

        let rule = ClaudePermissionRuleValue(toolName: toolName)
        let update = ClaudePermissionUpdate.addRules(destination: .session, rules: [rule], behavior: .allow)
        model.approvePermission(for: session.id, action: .allowWithUpdates([update]))
        return true
    }

    private func handleMouseMoved(_ screenLocation: NSPoint) {
        guard let model else { return }

        let inClosedSurfaceArea = isPointInClosedSurfaceArea(screenLocation)

        if model.notchStatus == .closed && inClosedSurfaceArea {
            scheduleHoverOpen()
        } else if model.notchStatus == .closed && !inClosedSurfaceArea {
            cancelHoverOpen()
        }

        let shouldTrackNotificationPointer = model.notchStatus == .opened
            && model.notchOpenReason == .notification
            && model.showsNotificationCard

        if shouldTrackNotificationPointer || model.shouldAutoCollapseOnMouseLeave {
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

        guard model != nil else { return }

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
            return Self.rectContainsIncludingEdges(closedSurfaceRect, point: screenPoint)
        }

        let expandedNotch = notchRect.insetBy(dx: -20, dy: -10)
        return Self.rectContainsIncludingEdges(expandedNotch, point: screenPoint)
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

        return Self.rectContainsIncludingEdges(contentRect, point: screenPoint)
    }

    func openedPanelWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return Self.preferredTopBarOpenedPanelWidth }
        let preferredWidth = screen.safeAreaInsets.top > 0
            ? Self.preferredNotchOpenedPanelWidth
            : Self.preferredTopBarOpenedPanelWidth
        return max(IslandChromeLayout.minimumContentWidth, min(preferredWidth, screen.visibleFrame.width - 32))
    }

    func contentRect(for model: AppModel, in bounds: NSRect) -> NSRect? {
        IslandChromeLayout.contentRect(in: bounds, metrics: chromeMetrics(for: model))
    }

    nonisolated static func closedSurfaceRect(
        notchRect: NSRect,
        closedWidth: CGFloat
    ) -> NSRect {
        let cx = notchRect.midX
        return NSRect(
            x: cx - closedWidth / 2,
            y: notchRect.minY,
            width: closedWidth,
            height: notchRect.height
        )
    }

    nonisolated static func rectContainsIncludingEdges(_ rect: NSRect, point: NSPoint) -> Bool {
        point.x >= rect.minX
            && point.x <= rect.maxX
            && point.y >= rect.minY
            && point.y <= rect.maxY
    }

    /// Extra hit-area width reserved on a notched display when the
    /// notch-lane label (AB-241) is showing. Sized generously (rather than
    /// tracking the live label's exact rendered width) — the same "fixed,
    /// generous hit-area" approach already used for the external layout's
    /// fluid pill below — so hover/click keeps working over the label
    /// without this controller needing to duplicate `V6ClosedPill`'s text
    /// measurement.
    nonisolated static let notchLaneLabelHitAreaBonus: CGFloat = 200

    /// Hit-area width of the v6 closed pill.
    ///
    /// - On a MacBook (physical notch present) the pill is locked to
    ///   `44 + notchWidth + 44`, per the v6 design spec, plus
    ///   `notchLaneLabelHitAreaBonus` when the notch-lane label is showing.
    /// - On an external display the width is content-driven; we return a
    ///   generous fixed hit-area so hover / click detection works without
    ///   the controller having to introspect live session state.
    nonisolated static func closedPanelWidth(
        notchWidth: CGFloat,
        isNotchedDisplay: Bool,
        notchStatus: NotchStatus,
        includesNotchLaneLabel: Bool = false
    ) -> CGFloat {
        let popBonus: CGFloat = notchStatus == .popping ? 18 : 0
        if isNotchedDisplay {
            let labelBonus: CGFloat = includesNotchLaneLabel ? notchLaneLabelHitAreaBonus : 0
            return notchWidth + 88 + labelBonus + popBonus
        }
        return 360 + popBonus
    }

    private func closedSurfaceRect(for model: AppModel) -> NSRect? {
        guard let screen = resolveTargetScreen() else {
            return nil
        }

        let closedWidth = closedPanelWidth(for: model, on: screen)
        return Self.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
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

    /// Always returns the maximum (opened) panel size so the window never
    /// needs to resize.  All visual transitions are driven purely by SwiftUI
    /// inside this fixed-size window.
    private func panelSize(for model: AppModel?, on screen: NSScreen) -> CGSize {
        // Use at least the empty-state height so the window doesn't shrink
        // when sessions come and go while opened.
        let contentHeight = model.map { max(openedContentHeight(for: $0), Self.openedEmptyStateHeight) }
            ?? Self.openedEmptyStateHeight

        return IslandChromeLayout.windowSize(
            preferredContentWidth: openedPanelWidth(for: screen) + Self.openedContentWidthPadding,
            contentHeight: screen.notchSize.height + contentHeight + Self.openedContentBottomPadding,
            metrics: chromeMetrics(for: model),
            availableWidth: screen.visibleFrame.width
        )
    }

    /// Chrome metrics of the active theme (AB-299). With Classic active these
    /// equal the legacy `IslandChromeMetrics` statics (pinned by
    /// `IslandThemeTokensTests`), so the computed panel frames are identical to
    /// before the token layer existed. Falls back to Classic when there's no
    /// model yet (early sizing during panel creation).
    private func chromeMetrics(for model: AppModel?) -> IslandMetricsTokens {
        (model?.islandTheme.tokens ?? .classic).metrics
    }

    private func closedPanelWidth(for model: AppModel, on screen: NSScreen) -> CGFloat {
        let notchWidth = screen.notchSize.width
        let isNotched = screen.safeAreaInsets.top > 0
        return Self.closedPanelWidth(
            notchWidth: notchWidth,
            isNotchedDisplay: isNotched,
            notchStatus: model.notchStatus,
            includesNotchLaneLabel: isNotched && model.islandClosedLabel() != nil
        )
    }

    /// Opened-surface content height, driven entirely by SwiftUI measurement
    /// (AB-228). This used to hand-estimate a height per session phase
    /// (~15 constants covering row height, approval/question/completion body
    /// height, markdown text measured via `NSString.boundingRect`, ...) that
    /// had to be kept in lockstep with `IslandPanelView`'s actual layout by
    /// hand, and diverged whenever real content (long commands, wrapped
    /// markdown, many todos, long question lists) didn't match the estimate
    /// — causing clipped content or dead space below it.
    ///
    /// `IslandPanelView.openedContent` now measures its own real, rendered
    /// height via a `GeometryReader`/`PreferenceKey` (the same mechanism
    /// already used for notification cards) and publishes it to
    /// `AppModel.measuredOpenedContentHeight` /
    /// `measuredNotificationContentHeight`. This method just reads that
    /// measured value back.
    private func openedContentHeight(for model: AppModel) -> CGFloat {
        guard !model.islandListSessions.isEmpty else {
            return Self.openedEmptyStateHeight
        }

        let isNotificationMode = model.notchOpenReason == .notification && model.islandSurface.sessionID != nil
        let measured = isNotificationMode
            ? model.measuredNotificationContentHeight
            : model.measuredOpenedContentHeight

        guard measured > 0 else {
            // Not measured yet (first frame after the surface/content
            // changed, before SwiftUI has laid out and reported a height).
            // Fall back to the empty-state floor; the measured-height
            // `didSet` debounce corrects this with a follow-up reposition as
            // soon as layout completes, matching how notification cards
            // already behaved before this change.
            return Self.openedEmptyStateHeight
        }

        return measured + Self.measuredContentSafetyPadding
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
    /// Simulated notch width used on non-notch (external) displays.
    /// Sized close to a real MacBook notch (~200pt) so the closed island
    /// doesn't feel disproportionately wide when the black rectangle is
    /// fully visible (not hidden behind a physical notch).
    static let externalDisplayNotchWidth: CGFloat = 190
    static let externalDisplayNotchHeight: CGFloat = 38

    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(
                width: Self.externalDisplayNotchWidth,
                height: Self.externalDisplayNotchHeight
            )
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
    /// On notch screens, use `safeAreaInsetsTop` directly — the island must match the
    /// physical notch height exactly so it sits flush with the notch bottom edge.
    /// Previously this used `min(safeAreaInsetsTop, topStatusBarHeight)`, but when the
    /// menu bar reserved area is smaller than the notch (e.g. auto-hide menu bar, or
    /// certain display configurations), the island ended up shorter than the physical
    /// notch, leaving a visible gap.
    /// On non-notch screens (`safeAreaInsetsTop == 0`), use `topStatusBarHeight` directly.
    static func computeIslandClosedHeight(
        safeAreaInsetsTop: CGFloat,
        topStatusBarHeight: CGFloat
    ) -> CGFloat {
        if safeAreaInsetsTop > 0 {
            return safeAreaInsetsTop
        }
        return topStatusBarHeight
    }
}
