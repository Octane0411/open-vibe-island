import AppKit
import Foundation

/// Detects whether any application window is in macOS native fullscreen
/// (Spaces fullscreen) on a given screen.
///
/// macOS does not expose a public "is in fullscreen Space" API for other
/// apps' windows. We approximate it by enumerating on-screen windows on the
/// normal layer (`kCGWindowLayer == 0`) and checking whether any of them
/// match the screen's full `frame` (including the menu bar area). When an
/// app is in native fullscreen on its own Space, its window covers the
/// entire screen — including the area normally reserved for the menu bar
/// and notch — which is something only fullscreen windows do.
///
/// Notifications used to drive re-evaluation:
/// - `NSWorkspace.activeSpaceDidChangeNotification` — fires when the user
///   enters or leaves a fullscreen Space.
/// - `NSWorkspace.didActivateApplicationNotification` — fires when the
///   frontmost app changes (covers app-switching while in fullscreen).
/// - `NSApplication.didChangeScreenParametersNotification` — fires on
///   display configuration changes.
@MainActor
final class FullscreenWindowMonitor {
    /// Called whenever the fullscreen state may have changed. Recipients
    /// should call `isFullscreenActive(on:)` to read the current value.
    var onChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    /// Window IDs we should ignore when scanning — typically the overlay's
    /// own panel(s). Refreshed on each query via the `excludingWindowIDs`
    /// parameter, so the property is unused; reserved for future use.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let mainCenter = NotificationCenter.default

        let spaceObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.notifyChange() }
        }

        let activateObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.notifyChange() }
        }

        let screenObserver = mainCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.notifyChange() }
        }

        observers = [spaceObserver, activateObserver, screenObserver]
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let mainCenter = NotificationCenter.default
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            mainCenter.removeObserver(observer)
        }
        observers.removeAll()
        isStarted = false
    }

    private func notifyChange() {
        onChange?()
    }

    /// Returns `true` when there is at least one on-screen normal-layer
    /// window whose bounds match the supplied screen's full frame —
    /// the signature of a macOS native fullscreen Space.
    ///
    /// `excludingWindowIDs` is used to skip Open Island's own panels so
    /// the overlay never counts itself as fullscreen.
    func isFullscreenActive(on screen: NSScreen, excludingWindowIDs: Set<CGWindowID>) -> Bool {
        Self.isFullscreenActive(on: screen, excludingWindowIDs: excludingWindowIDs)
    }

    nonisolated static func isFullscreenActive(
        on screen: NSScreen,
        excludingWindowIDs: Set<CGWindowID>
    ) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else {
            return false
        }

        let screenFrameCG = convertToCGCoordinates(screen.frame)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for info in windowInfoList {
            // Skip the overlay's own windows.
            if let windowNumber = info[kCGWindowNumber as String] as? CGWindowID,
               excludingWindowIDs.contains(windowNumber) {
                continue
            }

            // Open Island runs as a single process; skip any window owned by
            // ourselves regardless of layer (defensive for future windows).
            if let pid = info[kCGWindowOwnerPID as String] as? Int32,
               pid == ownPID {
                continue
            }

            // Only consider windows on the normal user layer. Fullscreen apps'
            // primary content windows live on layer 0; menu bars, status items,
            // overlays, etc. live on higher layers.
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 {
                continue
            }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            // A window in a native fullscreen Space covers the entire screen
            // frame, including the menu bar / notch region. Allow ~1pt slack
            // for floating-point rounding.
            if rectsApproximatelyEqual(rect, screenFrameCG, tolerance: 1.5) {
                return true
            }
        }
        return false
    }

    /// CGWindow bounds use a Y-flipped origin (top-left of the primary
    /// display is (0, 0), Y grows downward). Convert an `NSScreen.frame`
    /// from AppKit coordinates (bottom-left origin) to CGWindow space.
    nonisolated private static func convertToCGCoordinates(_ frame: NSRect) -> CGRect {
        guard let primary = NSScreen.screens.first else {
            return frame
        }
        let primaryHeight = primary.frame.height
        return CGRect(
            x: frame.origin.x,
            y: primaryHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    nonisolated private static func rectsApproximatelyEqual(
        _ a: CGRect,
        _ b: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance
            && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.size.width - b.size.width) <= tolerance
            && abs(a.size.height - b.size.height) <= tolerance
    }
}
