import AppKit

struct OverlayDisplayOption: Identifiable, Equatable, Codable, Sendable {
    static let automaticID = "automatic"

    let id: String
    let title: String
    let subtitle: String
    let isAvailable: Bool

    init(id: String, title: String, subtitle: String, isAvailable: Bool = true) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isAvailable = isAvailable
    }
}

struct OverlayDisplayPreferenceReconciliation: Equatable, Codable, Sendable {
    let selectionID: String
    let selectionTitle: String?
    let displayOptions: [OverlayDisplayOption]
}

enum OverlayDisplayPreferencePolicy {
    static let preferenceDefaultsKey = "overlay.display.preference"
    static let preferenceTitleDefaultsKey = "overlay.display.preference.title"
    private static let legacyDisplayIDPrefix = "display-"

    /// Legacy preferences stored a transient `CGDirectDisplayID` and cannot
    /// be matched safely after a hotplug. New preferences use a stable display
    /// UUID (or the resolver's explicit fallback identifier).
    static func restoredSelectionID(from storedSelectionID: String?) -> String {
        guard let storedSelectionID,
              !storedSelectionID.isEmpty,
              !storedSelectionID.hasPrefix(legacyDisplayIDPrefix) else {
            return OverlayDisplayOption.automaticID
        }

        return storedSelectionID
    }

    /// Keeps the persisted user preference separate from the currently
    /// available displays. When the preferred display is disconnected, a
    /// disabled placeholder keeps the Picker selection intact while placement
    /// temporarily falls back to another screen.
    static func reconcile(
        availableOptions: [OverlayDisplayOption],
        selectionID: String,
        rememberedSelectionTitle: String?
    ) -> OverlayDisplayPreferenceReconciliation {
        guard selectionID != OverlayDisplayOption.automaticID else {
            return OverlayDisplayPreferenceReconciliation(
                selectionID: selectionID,
                selectionTitle: nil,
                displayOptions: availableOptions
            )
        }

        if let selectedOption = availableOptions.first(where: { $0.id == selectionID }) {
            return OverlayDisplayPreferenceReconciliation(
                selectionID: selectionID,
                selectionTitle: selectedOption.title,
                displayOptions: availableOptions
            )
        }

        let unavailableOption = OverlayDisplayOption(
            id: selectionID,
            title: rememberedSelectionTitle ?? selectionID,
            subtitle: "Unavailable",
            isAvailable: false
        )
        return OverlayDisplayPreferenceReconciliation(
            selectionID: selectionID,
            selectionTitle: rememberedSelectionTitle,
            displayOptions: availableOptions + [unavailableOption]
        )
    }
}

enum OverlayPlacementMode: String, Equatable {
    case notch = "Notch area"
    case topBar = "Top bar fallback"
    case bottomBar = "Bottom bar"
}

/// Which screen edge the island is pinned to. `.top` is the classic notch /
/// top-bar placement. `.bottom` parks the island on the lower edge, resting
/// on the Dock when it is visible, for people who find the top of the
/// screen out of reach on a large external display.
enum OverlayEdge: String, CaseIterable, Equatable, Sendable {
    case top
    case bottom

    static let defaultsKey = "overlay.edge"

    static func restored(from rawValue: String?) -> OverlayEdge {
        guard let rawValue, let edge = OverlayEdge(rawValue: rawValue) else {
            return .top
        }
        return edge
    }
}

/// Pure geometry for pinning the overlay to either screen edge. Kept free of
/// `NSScreen` so it can be unit-tested with plain rects.
enum OverlayEdgeGeometry {
    /// Origin of the (always opened-size) panel window.
    static func panelOrigin(
        edge: OverlayEdge,
        screenFrame: NSRect,
        visibleFrame: NSRect,
        panelSize: NSSize
    ) -> NSPoint {
        let x = screenFrame.midX - panelSize.width / 2
        switch edge {
        case .top:
            return NSPoint(x: x, y: screenFrame.maxY - panelSize.height)
        case .bottom:
            // visibleFrame.minY already sits above a visible Dock and equals
            // screenFrame.minY when the Dock is hidden or on another edge.
            return NSPoint(x: x, y: visibleFrame.minY)
        }
    }

    /// Screen-space rect of the closed island strip (the "notch" slot the
    /// closed pill is centred on and the hover hot-zone grows from).
    static func anchorRect(
        edge: OverlayEdge,
        screenFrame: NSRect,
        visibleFrame: NSRect,
        size: NSSize
    ) -> NSRect {
        let x = screenFrame.midX - size.width / 2
        switch edge {
        case .top:
            return NSRect(x: x, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
        case .bottom:
            return NSRect(x: x, y: visibleFrame.minY, width: size.width, height: size.height)
        }
    }

    /// The visible island area inside the panel bounds, excluding the shadow
    /// margin. The margin sits on the side facing away from the screen edge.
    static func contentRect(
        edge: OverlayEdge,
        bounds: NSRect,
        horizontalInset: CGFloat,
        shadowInset: CGFloat
    ) -> NSRect {
        let width = max(0, bounds.width - (horizontalInset * 2))
        let height = max(0, bounds.height - shadowInset)
        switch edge {
        case .top:
            return NSRect(x: bounds.minX + horizontalInset, y: bounds.minY + shadowInset, width: width, height: height)
        case .bottom:
            return NSRect(x: bounds.minX + horizontalInset, y: bounds.minY, width: width, height: height)
        }
    }
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

    static func diagnostics(
        preferredScreenID: String?,
        panelSize: NSSize,
        edge: OverlayEdge = .top
    ) -> OverlayPlacementDiagnostics? {
        guard let resolvedScreen = resolveScreen(preferredScreenID: preferredScreenID) else {
            return nil
        }

        let screen = resolvedScreen.screen
        let overlayFrame = frame(for: screen, panelSize: panelSize, edge: edge)

        return OverlayPlacementDiagnostics(
            targetScreenID: screenID(for: screen),
            targetScreenName: screen.localizedName,
            selectionSummary: resolvedScreen.selectionSummary,
            mode: placementMode(for: screen, edge: edge),
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            overlayFrame: overlayFrame
        )
    }

    private static func frame(for screen: NSScreen, panelSize: NSSize, edge: OverlayEdge) -> NSRect {
        let width = min(panelSize.width, screen.visibleFrame.width - 64)
        let height = panelSize.height
        let x = screen.frame.midX - (width / 2)

        let y: CGFloat
        switch placementMode(for: screen, edge: edge) {
        case .notch:
            y = screen.frame.maxY - height
        case .topBar:
            y = screen.visibleFrame.maxY - height - 18
        case .bottomBar:
            y = screen.visibleFrame.minY
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

    private static func placementMode(for screen: NSScreen, edge: OverlayEdge = .top) -> OverlayPlacementMode {
        if edge == .bottom {
            return .bottomBar
        }
        return isNotched(screen) ? .notch : .topBar
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
    /// The origin is not stable across display rearrangement. If it changes,
    /// the preference remains unavailable until that display is reselected;
    /// it is not discarded automatically because a temporary disconnect must
    /// preserve the user's intent.
    private static func fallbackScreenID(for screen: NSScreen) -> String {
        let width = Int(screen.frame.width.rounded())
        let height = Int(screen.frame.height.rounded())
        let originX = Int(screen.frame.origin.x.rounded())
        let originY = Int(screen.frame.origin.y.rounded())
        return "fallback-\(screen.localizedName)-\(width)x\(height)@\(originX),\(originY)"
    }
}
