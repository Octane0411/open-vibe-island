import AppKit
import SwiftUI

@MainActor
final class ControlCenterWindowController: NSWindowController, NSWindowDelegate {
    init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Agent Deck Debug"
        window.center()
        window.minSize = NSSize(width: 940, height: 580)
        window.setContentSize(NSSize(width: 980, height: 640))
        window.contentViewController = NSHostingController(rootView: ControlCenterView(model: model))
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else {
            return
        }

        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
    }
}
