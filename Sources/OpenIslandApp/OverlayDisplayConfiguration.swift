import AppKit

struct OverlayDisplayOption: Identifiable, Equatable {
    static let automaticID = "automatic"

    let id: String
    let title: String
    let subtitle: String
}

enum OverlayScreenCapability: Equatable {
    case notched
    case plain
}

enum OverlayPresentationPolicy: String, Equatable, CaseIterable {
    case alwaysIsland
    case automaticIslandWhenNotched
    case alwaysPill

    static let defaultValue = OverlayPresentationPolicy.automaticIslandWhenNotched
}

enum OverlayPresentationMode: Equatable {
    case island
    case pill

    private static let compactPillBaseSize = NSSize(width: 56, height: 22)

    var placementMode: OverlayPlacementMode {
        switch self {
        case .island:
            return .notch
        case .pill:
            return .topBar
        }
    }

    func closedBaseSize(physicalIslandBaseSize: NSSize) -> NSSize {
        switch self {
        case .island:
            return physicalIslandBaseSize
        case .pill:
            return Self.compactPillBaseSize
        }
    }
}

extension OverlayPresentationPolicy {
    func resolvePresentationMode(
        screenCapability: OverlayScreenCapability
    ) -> OverlayPresentationMode {
        switch self {
        case .alwaysIsland:
            return .island
        case .automaticIslandWhenNotched:
            return screenCapability == .notched ? .island : .pill
        case .alwaysPill:
            return .pill
        }
    }

    func resolvePlacementMode(
        screenCapability: OverlayScreenCapability
    ) -> OverlayPlacementMode {
        resolvePresentationMode(
            screenCapability: screenCapability
        ).placementMode
    }
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
    let screenCapability: OverlayScreenCapability
    let presentationPolicy: OverlayPresentationPolicy
    let presentationMode: OverlayPresentationMode
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

    var screenCapabilityDescription: String {
        switch screenCapability {
        case .notched:
            return "Notched"
        case .plain:
            return "Plain"
        }
    }

    var presentationPolicyDescription: String {
        switch presentationPolicy {
        case .alwaysIsland:
            return "Always island"
        case .automaticIslandWhenNotched:
            return "Island when notched"
        case .alwaysPill:
            return "Always pill"
        }
    }

    var presentationModeDescription: String {
        switch presentationMode {
        case .island:
            return "Island"
        case .pill:
            return "Pill"
        }
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
        presentationPolicy: OverlayPresentationPolicy
    ) -> OverlayPlacementDiagnostics? {
        guard let resolvedScreen = resolveScreen(preferredScreenID: preferredScreenID) else {
            return nil
        }

        let screen = resolvedScreen.screen
        let screenCapability = screenCapability(for: screen)
        let placementMode = presentationPolicy.resolvePlacementMode(
            screenCapability: screenCapability
        )
        let overlayFrame = frame(
            for: screen,
            panelSize: panelSize,
            placementMode: placementMode
        )

        return OverlayPlacementDiagnostics(
            targetScreenID: screenID(for: screen),
            targetScreenName: screen.localizedName,
            selectionSummary: resolvedScreen.selectionSummary,
            mode: placementMode,
            screenCapability: screenCapability,
            presentationPolicy: presentationPolicy,
            presentationMode: presentationPolicy.resolvePresentationMode(
                screenCapability: screenCapability
            ),
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            overlayFrame: overlayFrame
        )
    }

    private static func frame(
        for screen: NSScreen,
        panelSize: NSSize,
        placementMode: OverlayPlacementMode
    ) -> NSRect {
        let width = min(panelSize.width, screen.visibleFrame.width - 64)
        let height = panelSize.height
        let x = screen.frame.midX - (width / 2)

        let y: CGFloat
        switch placementMode {
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

        guard let selection = OverlayScreenSelectionResolver.resolve(
            preferredScreenID: preferredScreenID,
            screens: selectionCandidates(from: screens)
        ),
        let screen = screens.first(where: { screenID(for: $0) == selection.screenID }) else {
            return nil
        }

        return (screen, selection.selectionSummary)
    }

    static func placementMode(for screen: NSScreen) -> OverlayPlacementMode {
        screenCapability(for: screen) == .notched ? .notch : .topBar
    }

    static func screenCapability(for screen: NSScreen) -> OverlayScreenCapability {
        isNotched(screen) ? .notched : .plain
    }

    private static func isNotched(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
            || screen.auxiliaryTopLeftArea?.isEmpty == false
            || screen.auxiliaryTopRightArea?.isEmpty == false
    }

    private static func screenKindDescription(for screen: NSScreen) -> String {
        placementMode(for: screen) == .notch ? "Built-in notch" : "Top-bar fallback"
    }

    private static func selectionCandidates(from screens: [NSScreen]) -> [OverlayScreenSelectionCandidate] {
        screens.map { screen in
            OverlayScreenSelectionCandidate(
                id: screenID(for: screen),
                isNotched: isNotched(screen),
                isMain: screen == NSScreen.main
            )
        }
    }

    private static func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }

        return screen.localizedName
    }
}
