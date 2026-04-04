import AppKit
import Testing
@testable import OpenIslandApp

@MainActor
struct AppModelControlCenterTests {
    @Test
    func showControlCenterCreatesDebugWindowWhenNoWindowIsOpen() {
        _ = NSApplication.shared
        closeDebugWindows()
        defer { closeDebugWindows() }

        let model = AppModel()

        #expect(debugWindow() == nil)

        model.showControlCenter()

        let window = debugWindow()
        #expect(window != nil)
        #expect(window?.isVisible == true)
    }

    private func debugWindow() -> NSWindow? {
        NSApp.windows.first(where: { $0.title == "Open Island Debug" })
    }

    private func closeDebugWindows() {
        for window in NSApp.windows where window.title == "Open Island Debug" {
            window.close()
        }
    }
}
