import AppKit

/// Stable identifier for an `NSScreen`, used as the persistence key for
/// per-screen overlay state (e.g. pill anchor position) and for matching
/// user-selected displays across screen-parameter changes.
///
/// Prefers `NSScreenNumber` (the CoreGraphics display ID) for stability
/// across localization and display-hardware reconnection; falls back to the
/// human-readable `localizedName` only when the device description is
/// unavailable (extremely rare).
///
/// All overlay subsystems (panel controller, display resolver, SwiftUI
/// island view) derive screen IDs through this single helper so that a
/// persisted key written by one code path is readable by every other path.
enum OverlayScreenIdentity {
    /// Returns a stable string identifier for the given screen.
    static func id(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return screen.localizedName
    }
}
