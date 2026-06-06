import AppKit
import ApplicationServices
import CoreGraphics

/// Detects when the overlay's target display is in a native fullscreen space.
enum FullscreenDisplayDetection {
    private static let coverageTolerance: CGFloat = 12
    private static let minimumScreenCoverage: CGFloat = 0.92
    private static let ourProcessID = ProcessInfo.processInfo.processIdentifier

    static func isOverlayScreenInFullscreen(preferredScreenID: String?) -> Bool {
        guard let screen = resolveScreen(preferredScreenID: preferredScreenID) else {
            return false
        }
        return isScreenDisplayingFullscreenContent(screen)
    }

    static func isScreenDisplayingFullscreenContent(_ screen: NSScreen) -> Bool {
        // Managed space type is authoritative: maximized apps (e.g. Chrome at
        // full display height) are not native fullscreen and must not trigger hide.
        if let type = CGSSpaceQuery.currentSpaceType(on: displayUUID(for: screen)) {
            return type.isFullscreen
        }

        // Fallback only when CGS is unavailable (e.g. SPI failure).
        return frontmostAppHasFullscreenWindow(on: screen)
    }

    private static func resolveScreen(preferredScreenID: String?) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let preferredScreenID,
           let screen = screens.first(where: { screenID(for: $0) == preferredScreenID }) {
            return screen
        }

        return NSScreen.main ?? screens[0]
    }

    private static func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return screen.localizedName
    }

    private static func displayUUID(for screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }

        let displayID = CGDirectDisplayID(number.uint32Value)
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).takeRetainedValue()
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String?
    }

    // MARK: - Accessibility

    private static func frontmostAppHasFullscreenWindow(on screen: NSScreen) -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ourProcessID else {
            return false
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        let candidateWindows = axCandidateWindows(from: appElement)

        for window in candidateWindows where axWindowIsFullscreen(window, on: screen) {
            return true
        }

        return false
    }

    private static func axCandidateWindows(from appElement: AXUIElement) -> [AXUIElement] {
        var windows: [AXUIElement] = []

        if let focused = copyAXElementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement) {
            windows.append(focused)
        }

        if let main = copyAXElementAttribute(kAXMainWindowAttribute as CFString, from: appElement) {
            if !windows.contains(where: { $0 == main }) {
                windows.append(main)
            }
        }

        if let listed = copyAXElementArrayAttribute(kAXWindowsAttribute as CFString, from: appElement) {
            for window in listed where !windows.contains(where: { $0 == window }) {
                windows.append(window)
            }
        }

        return windows
    }

    private static func axWindowIsFullscreen(_ window: AXUIElement, on screen: NSScreen) -> Bool {
        guard copyAXBoolAttribute("AXFullScreen", from: window) == true else {
            return false
        }
        return axWindowCoversScreen(window, on: screen)
    }

    private static func axWindowCoversScreen(_ window: AXUIElement, on screen: NSScreen) -> Bool {
        guard let position = copyAXPointAttribute(kAXPositionAttribute as CFString, from: window),
              let size = copyAXSizeAttribute(kAXSizeAttribute as CFString, from: window) else {
            return false
        }

        let windowFrame = CGRect(origin: position, size: size)
        return windowFrameCoversScreen(windowFrame, screen: screen)
    }

    private static func copyAXElementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let elementValue = value else {
            return nil
        }
        return (elementValue as! AXUIElement)
    }

    private static func copyAXElementArrayAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let array = value as? [AXUIElement],
              !array.isEmpty else {
            return nil
        }
        return array
    }

    private static func copyAXBoolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private static func copyAXPointAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              AXValueGetType(value as! AXValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private static func copyAXSizeAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              AXValueGetType(value as! AXValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private static func windowFrameCoversScreen(_ windowFrame: CGRect, screen: NSScreen) -> Bool {
        let screenFrame = screen.frame
        let intersection = screenFrame.intersection(windowFrame)
        guard !intersection.isNull else { return false }

        let coverage = (intersection.width * intersection.height) / (screenFrame.width * screenFrame.height)
        guard coverage >= minimumScreenCoverage else { return false }

        let widthOK = windowFrame.width >= screenFrame.width - coverageTolerance
        let heightOK = windowFrame.height >= screenFrame.height - coverageTolerance
        return widthOK && heightOK
    }

}
