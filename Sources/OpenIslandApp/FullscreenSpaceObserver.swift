import AppKit
import Foundation

@MainActor
final class FullscreenSpaceObserver {
    /// Called when the set of fullscreen displays changes. Set BEFORE `start()`.
    var onChange: ((Set<CGDirectDisplayID>) -> Void)?

    private var lastValue: Set<CGDirectDisplayID> = []
    private var workspaceObserver: NSObjectProtocol?
    private var screenParamsObserver: NSObjectProtocol?

    // No deinit cleanup: this observer is held for the app's lifetime by AppModel.
    // The notification tokens capture `[weak self]` so no retain cycle exists; if a
    // future caller needs early teardown, call `stop()` explicitly.

    func start() {
        guard workspaceObserver == nil else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }

        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }

        // Initial sample so AppModel has a correct value before any space changes.
        recompute()
    }

    func stop() {
        if let token = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            workspaceObserver = nil
        }
        if let token = screenParamsObserver {
            NotificationCenter.default.removeObserver(token)
            screenParamsObserver = nil
        }
    }

    func recompute() {
        let value = currentFullscreenDisplays()
        guard value != lastValue else { return }
        lastValue = value
        onChange?(value)
    }

    // MARK: - Scan

    private func currentFullscreenDisplays() -> Set<CGDirectDisplayID> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // Layer-0 windows are regular app windows. Higher layers are status
        // bar / dock / system overlays.
        let appWindows = raw.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }

        // CGWindowList bounds are in CG (top-left origin) coordinates;
        // NSScreen.frame is bottom-left. Flip against the primary screen height.
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        var result: Set<CGDirectDisplayID> = []
        for screen in screens {
            guard let displayID = Self.displayID(for: screen) else { continue }
            let cgScreenFrame = CGRect(
                x: screen.frame.minX,
                y: primaryHeight - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            // Take the topmost (= first) layer-0 window whose bounds intersect
            // this screen's CG frame.
            let topWindow = appWindows.first { entry in
                guard let dict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                      let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else {
                    return false
                }
                return bounds.intersects(cgScreenFrame)
            }
            guard let dict = topWindow?[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else {
                continue
            }
            if Self.screenIsCovered(byTopWindowBounds: bounds, screenFrame: cgScreenFrame) {
                result.insert(displayID)
            }
        }
        return result
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    /// Pure helper: does the topmost layer-0 window bound completely cover
    /// the screen frame (i.e. extend across the menu-bar area too)?
    /// A ±1pt tolerance absorbs sub-pixel rounding in `CGWindowListCopyWindowInfo`.
    nonisolated static func screenIsCovered(byTopWindowBounds bounds: CGRect, screenFrame: CGRect) -> Bool {
        let widthDelta = abs(bounds.width - screenFrame.width)
        let heightDelta = abs(bounds.height - screenFrame.height)
        let originXDelta = abs(bounds.minX - screenFrame.minX)
        let originYDelta = abs(bounds.minY - screenFrame.minY)
        return widthDelta <= 1
            && heightDelta <= 1
            && originXDelta <= 1
            && originYDelta <= 1
    }
}
