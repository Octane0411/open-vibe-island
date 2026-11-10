import AppKit
import Testing
@testable import OpenIslandApp

@MainActor
@Suite(.serialized)
struct IslandPointerInteractionTests {
    private func makeModel() -> AppModel {
        _ = NSApplication.shared
        let model = AppModel()
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.overlay.overlayPanelController.pointerLocationProvider = { NSPoint(x: -10_000, y: -10_000) }
        model.overlay.overlayPanelController.modifierFlagsProvider = { [] }
        return model
    }

    @Test
    func closedWindowIsCompactAndOnlyVisiblePixelsCaptureClicks() throws {
        let model = makeModel()
        let controller = model.overlay.overlayPanelController
        defer { controller.shutDown() }
        controller.ensurePanel(model: model, preferredScreenID: nil)
        let rect = try #require(controller.visibleSurfaceRect())
        let frame = try #require(controller.windowFrame)
        #expect(frame.height == rect.height + IslandChromeMetrics.openedShadowBottomInset)
        #expect(frame.width == rect.width + 2 * IslandChromeMetrics.openedShadowHorizontalInset)
        controller.updatePointerInteraction(at: NSPoint(x: rect.midX, y: rect.midY))
        #expect(!controller.isIgnoringMouseEvents)
        for point in [NSPoint(x: rect.minX - 5, y: rect.midY),
                      NSPoint(x: rect.midX, y: rect.minY - 5),
                      NSPoint(x: rect.minX + 0.5, y: rect.minY + 0.5)] {
            controller.updatePointerInteraction(at: point)
            #expect(controller.isIgnoringMouseEvents)
        }
        controller.updatePointerInteraction(at: NSPoint(x: rect.midX, y: rect.midY), modifiers: .option)
        #expect(controller.isIgnoringMouseEvents)
    }

    @Test
    func browserClickNeverOpensIslandAndOutsideClickDismissesWithoutReposting() throws {
        let model = makeModel()
        let controller = model.overlay.overlayPanelController
        defer { controller.shutDown() }
        controller.ensurePanel(model: model, preferredScreenID: nil)
        let closed = try #require(controller.visibleSurfaceRect())
        controller.handleMouseDown(NSPoint(x: closed.midX, y: closed.midY))
        #expect(model.notchStatus == .closed)
        // An observation from another window must not claim an island drag.
        controller.updatePointerInteraction(at: NSPoint(x: closed.midX, y: closed.minY - 5))
        #expect(controller.isIgnoringMouseEvents)
        model.notchOpen(reason: .click)
        let opened = try #require(controller.visibleSurfaceRect())
        let outside = NSPoint(x: opened.minX - 5, y: opened.midY)
        controller.updatePointerInteraction(at: outside)
        #expect(controller.isIgnoringMouseEvents)
        controller.handleMouseDown(outside)
        #expect(model.notchStatus == .closed)
        #expect(controller.isIgnoringMouseEvents)
    }

    @Test
    func firstPillClickOpensOnceAndItsReleaseCannotPressExpandedControls() throws {
        let model = makeModel()
        let controller = model.overlay.overlayPanelController
        defer { controller.shutDown() }
        controller.ensurePanel(model: model, preferredScreenID: nil)
        let rect = try #require(controller.visibleSurfaceRect())
        let frame = try #require(controller.windowFrame)
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: rect.midX - frame.minX, y: rect.midY - frame.minY),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        #expect(controller.panelReceivedMouseDown(event))
        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .click)
        let opened = try #require(controller.visibleSurfaceRect())
        let outside = NSPoint(x: opened.midX, y: opened.minY - 10)
        controller.updatePointerInteraction(at: outside)
        #expect(!controller.isIgnoringMouseEvents) // finish the owned press/drag
        controller.pointerSequenceEnded(at: outside)
        #expect(controller.isIgnoringMouseEvents)
    }

    @Test
    func openedShadowsAndRoundedCornersPassThroughWithoutBlockingKeyboardFocus() throws {
        let model = makeModel()
        let controller = model.overlay.overlayPanelController
        defer { controller.shutDown() }
        controller.ensurePanel(model: model, preferredScreenID: nil)
        model.notchOpen(reason: .click)
        let rect = try #require(controller.visibleSurfaceRect())
        controller.updatePointerInteraction(at: NSPoint(x: rect.midX, y: rect.midY))
        #expect(!controller.isIgnoringMouseEvents)
        controller.updatePointerInteraction(at: NSPoint(x: rect.maxX - 0.5, y: rect.minY + 0.5))
        #expect(controller.isIgnoringMouseEvents)
        controller.updatePointerInteraction(at: NSPoint(x: rect.midX, y: rect.midY), modifiers: .option)
        #expect(controller.isIgnoringMouseEvents)
        controller.updatePointerInteraction(at: NSPoint(x: rect.midX, y: rect.midY))
        #expect(!controller.isIgnoringMouseEvents)
    }

    @Test
    func hitShapesWorkOnDisplaysWithNegativeCoordinates() {
        let rect = NSRect(x: -1600, y: -400, width: 140, height: 24)
        #expect(OverlayPanelController.surfaceContains(NSPoint(x: rect.midX, y: rect.midY), in: rect, openedTopProfile: nil))
        #expect(!OverlayPanelController.surfaceContains(NSPoint(x: rect.midX, y: rect.minY - 1), in: rect, openedTopProfile: nil))
        #expect(!OverlayPanelController.surfaceContains(NSPoint(x: rect.minX + 0.1, y: rect.minY + 0.1), in: rect, openedTopProfile: nil))
    }
    @Test
    func closeCompactsBackingAndReopenCancelsPendingContraction() async throws {
        let model = makeModel()
        let controller = model.overlay.overlayPanelController
        defer { controller.shutDown() }
        controller.ensurePanel(model: model, preferredScreenID: nil)
        let compact = try #require(controller.windowFrame)
        model.notchOpen(reason: .click)
        #expect((controller.windowFrame?.height ?? 0) > compact.height)
        model.notchClose()
        try await Task.sleep(for: .milliseconds(450))
        #expect(controller.windowFrame?.height == compact.height)
        model.notchOpen(reason: .click)
        model.notchClose()
        model.notchOpen(reason: .click)
        try await Task.sleep(for: .milliseconds(450))
        #expect(model.notchStatus == .opened)
        #expect((controller.windowFrame?.height ?? 0) > compact.height)
    }

    @Test
    func hoverIsOptInAndChecksPointerIntentAgainBeforeOpening() async throws {
        let key = "app.hoverToOpenEnabled"
        let old = UserDefaults.standard.object(forKey: key)
        defer {
            if let old { UserDefaults.standard.set(old, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let model = makeModel()
        let controller = model.overlay.overlayPanelController
        defer { controller.shutDown() }
        controller.ensurePanel(model: model, preferredScreenID: nil)
        let rect = try #require(controller.visibleSurfaceRect())
        let inside = NSPoint(x: rect.midX, y: rect.midY)
        controller.pointerLocationProvider = { inside }
        model.hoverToOpenEnabled = false
        controller.handleMouseMoved(inside)
        try await Task.sleep(for: .milliseconds(550))
        #expect(model.notchStatus == .closed)
        model.hoverToOpenEnabled = true
        controller.handleMouseMoved(inside)
        controller.pointerLocationProvider = { NSPoint(x: -10_000, y: -10_000) }
        try await Task.sleep(for: .milliseconds(550))
        #expect(model.notchStatus == .closed)
        controller.pointerLocationProvider = { inside }
        controller.handleMouseMoved(inside)
        try await Task.sleep(for: .milliseconds(550))
        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .hover)
    }

}
