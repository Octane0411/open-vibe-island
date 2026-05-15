import AppKit

struct OverlayDisplayOption: Identifiable, Equatable {
    static let automaticID = "automatic"

    let id: String
    let title: String
    let subtitle: String
}

enum OverlayPlacementMode: String, Equatable {
    case notch = "Notch area"
    case topBar = "Top bar fallback"
}

struct OverlayPlacementDiagnostics {
    let targetScreenID: String
    let targetScreenName: String
    let selectionSummary: String
    let mode: OverlayPlacementMode
    let screenFrame: NSRect
    let visibleFrame: NSRect
    let safeAreaInsets: NSEdgeInsets
    let overlayFrame: NSRect

    var targetDescription: String {
        "\(targetScreenName) · \(selectionSummary)"
    }

    var modeDescription: String {
        mode.rawValue
    }

    var screenFrameDescription: String {
        Self.format(screenFrame)
    }

    var visibleFrameDescription: String {
        Self.format(visibleFrame)
    }

    var overlayFrameDescription: String {
        Self.format(overlayFrame)
    }

    var safeAreaDescription: String {
        "top \(Int(safeAreaInsets.top)) · left \(Int(safeAreaInsets.left)) · bottom \(Int(safeAreaInsets.bottom)) · right \(Int(safeAreaInsets.right))"
    }

    private static func format(_ rect: NSRect) -> String {
        let originX = Int(rect.origin.x.rounded())
        let originY = Int(rect.origin.y.rounded())
        let width = Int(rect.size.width.rounded())
        let height = Int(rect.size.height.rounded())
        return "{{\(originX), \(originY)}, {\(width), \(height)}}"
    }
}

enum OverlayDisplayResolver {
    static let defaultPanelSize = NSSize(width: 708, height: 514)

    static func availableDisplayOptions() -> [OverlayDisplayOption] {
        NSScreen.screens.map { screen in
            OverlayDisplayOption(
                id: screenID(for: screen),
                title: screen.localizedName,
                subtitle: "\(screenKindDescription(for: screen)) · \(Int(screen.frame.width))×\(Int(screen.frame.height))"
            )
        }
    }

    static func diagnostics(preferredScreenID: String?, panelSize: NSSize) -> OverlayPlacementDiagnostics? {
        guard let resolvedScreen = resolveScreen(preferredScreenID: preferredScreenID) else {
            return nil
        }

        let screen = resolvedScreen.screen
        let overlayFrame = frame(for: screen, panelSize: panelSize)

        return OverlayPlacementDiagnostics(
            targetScreenID: screenID(for: screen),
            targetScreenName: screen.localizedName,
            selectionSummary: resolvedScreen.selectionSummary,
            mode: placementMode(for: screen),
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            overlayFrame: overlayFrame
        )
    }

    private static func frame(for screen: NSScreen, panelSize: NSSize) -> NSRect {
        let width = min(panelSize.width, screen.visibleFrame.width - 64)
        let height = panelSize.height
        let x = screen.frame.midX - (width / 2)

        let y: CGFloat
        switch placementMode(for: screen) {
        case .notch:
            y = screen.frame.maxY - height
        case .topBar:
            y = screen.visibleFrame.maxY - height - 18
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private static func resolveScreen(preferredScreenID: String?) -> (screen: NSScreen, selectionSummary: String)? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return nil
        }

        if let preferredScreenID,
           let explicitScreen = screens.first(where: { screenID(for: $0) == preferredScreenID }) {
            return (explicitScreen, "manual")
        }

        if preferredScreenID != nil {
            if let notchScreen = screens.first(where: isNotched) {
                return (notchScreen, "manual missing, auto fallback")
            }

            if let mainScreen = NSScreen.main {
                return (mainScreen, "manual missing, main fallback")
            }

            return (screens[0], "manual missing, first-display fallback")
        }

        if let notchScreen = screens.first(where: isNotched) {
            return (notchScreen, "automatic")
        }

        if let mainScreen = NSScreen.main {
            return (mainScreen, "automatic")
        }

        return (screens[0], "automatic")
    }

    private static func placementMode(for screen: NSScreen) -> OverlayPlacementMode {
        isNotched(screen) ? .notch : .topBar
    }

    private static func isNotched(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
            || screen.auxiliaryTopLeftArea?.isEmpty == false
            || screen.auxiliaryTopRightArea?.isEmpty == false
    }

    private static func screenKindDescription(for screen: NSScreen) -> String {
        placementMode(for: screen) == .notch ? "Built-in notch" : "Top-bar fallback"
    }

    /// Returns a string that identifies the physical display backing `screen`
    /// stably across reconnects.
    ///
    /// Uses `CGDisplayCreateUUIDFromDisplayID` so the value survives the
    /// `CGDirectDisplayID` churn that happens on hotplug / sleep / arrangement
    /// changes — without this, a reassigned `CGDirectDisplayID` could silently
    /// route the overlay to a different physical monitor than the one the user
    /// picked. Falls back to a `localizedName + frame` composite when macOS
    /// can't issue a UUID (some AirPlay / virtual displays).
    static func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return fallbackScreenID(for: screen)
        }

        let displayID = number.uint32Value
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let cfString = CFUUIDCreateString(nil, uuid) {
            return cfString as String
        }

        return fallbackScreenID(for: screen)
    }

    /// Disambiguates identical displays (e.g. two AirPlay receivers with the
    /// same model name and resolution) by appending the arrangement origin.
    /// The origin is not stable across display rearrangement, but a mismatched
    /// preference will self-heal through the existing
    /// `validSelectionIDs.contains` check in `refreshOverlayDisplayConfiguration()`.
    private static func fallbackScreenID(for screen: NSScreen) -> String {
        let width = Int(screen.frame.width.rounded())
        let height = Int(screen.frame.height.rounded())
        let originX = Int(screen.frame.origin.x.rounded())
        let originY = Int(screen.frame.origin.y.rounded())
        return "fallback-\(screen.localizedName)-\(width)x\(height)@\(originX),\(originY)"
    }
}
