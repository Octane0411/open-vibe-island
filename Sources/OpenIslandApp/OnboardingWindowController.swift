import AppKit
import SwiftUI

/// AppKit host for the first-run onboarding window.
///
/// Uses an `NSWindowController` rather than a SwiftUI `Window` scene so the
/// window can be opened programmatically from `AppModel` on first launch,
/// before any SwiftUI view has had a chance to inject an `openWindow`
/// environment closure (SwiftUI `Window` scenes are lazy).
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = ""
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.setContentSize(NSSize(width: 820, height: 560))
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model))
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        model?.isOnboardingPresented = false
        window?.orderOut(nil)
    }
}
