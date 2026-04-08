import AppKit
import ApplicationServices
import Foundation

struct HarnessArtifactReport: Codable {
    struct AccessibilitySummary: Codable {
        let labels: [String]
        let buttonLabels: [String]
        let textValues: [String]
    }

    struct AccessibilityNode: Codable {
        let typeName: String
        let role: String?
        let subrole: String?
        let label: String?
        let value: String?
        let children: [AccessibilityNode]
    }

    struct WindowArtifact: Codable {
        let kind: String
        let title: String
        let frame: RectSnapshot
        let imagePath: String
        let accessibilityPath: String?
        let accessibilitySummary: AccessibilitySummary?
    }

    struct RectSnapshot: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ rect: NSRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }
    }

    struct OverlaySnapshot: Codable {
        let screenID: String
        let screenName: String
        let selectionSummary: String
        let mode: String
        let screenFrame: RectSnapshot
        let visibleFrame: RectSnapshot
        let overlayFrame: RectSnapshot
        let safeAreaInsets: EdgeInsetsSnapshot
    }

    struct EdgeInsetsSnapshot: Codable {
        let top: Double
        let left: Double
        let bottom: Double
        let right: Double

        init(_ insets: NSEdgeInsets) {
            top = insets.top
            left = insets.left
            bottom = insets.bottom
            right = insets.right
        }
    }

    struct SessionSnapshot: Codable {
        let id: String
        let tool: String
        let phase: String
        let attachmentState: String
        let title: String
        let summary: String
    }

    let scenario: String?
    let presentOverlay: Bool
    let showedControlCenter: Bool
    let startedBridge: Bool
    let performedBootAnimation: Bool
    let capturedAt: Date
    let launchToCaptureSeconds: Double
    let windows: [WindowArtifact]
    let overlay: OverlaySnapshot?
    let sessionCount: Int
    let liveSessionCount: Int
    let attentionCount: Int
    let selectedSessionID: String?
    let islandSurface: String
    let notchStatus: String
    let runtime: HarnessRuntimeArtifacts?
    let sessions: [SessionSnapshot]
}

@MainActor
enum HarnessArtifactRecorder {
    static func record(
        configuration: HarnessLaunchConfiguration,
        model: AppModel,
        launchedAt: Date,
        runtimeMonitor: HarnessRuntimeMonitor? = nil,
        fileManager: FileManager = .default
    ) throws {
        guard let directoryURL = configuration.artifactDirectoryURL else {
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var windows: [HarnessArtifactReport.WindowArtifact] = []
        for window in orderedVisibleWindows() {
            guard let imageData = snapshotPNGData(for: window) else {
                continue
            }

            let imageName = imageFileName(for: window, ordinal: windows.count + 1)
            let imageURL = directoryURL.appendingPathComponent(imageName)
            try imageData.write(to: imageURL)

            let accessibilityFileName = accessibilityFileName(for: window, ordinal: windows.count + 1)
            let viewAccessibilitySnapshot = snapshotViewAccessibilityTree(for: window)
            let accessibilitySnapshot = snapshotAXTree(for: window) ?? viewAccessibilitySnapshot
            if let accessibilitySnapshot {
                let accessibilityURL = directoryURL.appendingPathComponent(accessibilityFileName)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(accessibilitySnapshot).write(to: accessibilityURL)
            }

            windows.append(
                HarnessArtifactReport.WindowArtifact(
                    kind: windowKind(for: window),
                    title: window.title,
                    frame: .init(window.frame),
                    imagePath: imageName,
                    accessibilityPath: accessibilitySnapshot == nil ? nil : accessibilityFileName,
                    accessibilitySummary: mergedAccessibilitySummary(
                        primary: accessibilitySnapshot,
                        secondary: viewAccessibilitySnapshot
                    )
                )
            )
        }

        let captureSeconds = Date().timeIntervalSince(launchedAt)
        let runtimeArtifacts = try runtimeMonitor?.writeArtifacts(
            to: directoryURL,
            launchToCaptureSeconds: captureSeconds,
            fileManager: fileManager
        )

        let report = HarnessArtifactReport(
            scenario: configuration.scenario?.rawValue,
            presentOverlay: configuration.presentOverlay,
            showedControlCenter: configuration.shouldShowControlCenter,
            startedBridge: configuration.shouldStartBridge,
            performedBootAnimation: configuration.shouldPerformBootAnimation,
            capturedAt: .now,
            launchToCaptureSeconds: captureSeconds,
            windows: windows,
            overlay: overlaySnapshot(from: model.overlayPlacementDiagnostics),
            sessionCount: model.sessions.count,
            liveSessionCount: model.liveSessionCount,
            attentionCount: model.liveAttentionCount,
            selectedSessionID: model.selectedSessionID,
            islandSurface: surfaceDescription(model.islandSurface),
            notchStatus: notchStatusDescription(model.notchStatus),
            runtime: runtimeArtifacts,
            sessions: model.sessions.map {
                HarnessArtifactReport.SessionSnapshot(
                    id: $0.id,
                    tool: $0.tool.rawValue,
                    phase: $0.phase.rawValue,
                    attachmentState: "tracked",
                    title: $0.displayName,
                    summary: $0.summary
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let reportURL = directoryURL.appendingPathComponent("report.json")
        try encoder.encode(report).write(to: reportURL)
    }

    private static func orderedVisibleWindows() -> [NSWindow] {
        NSApp.windows
            .filter { window in
                window.isVisible && recognizedWindowKind(for: window) != nil
            }
            .sorted { lhs, rhs in
                lhs.frame.maxY > rhs.frame.maxY
            }
    }

    private static func snapshotPNGData(for window: NSWindow) -> Data? {
        window.displayIfNeeded()
        guard let contentView = window.contentView else {
            return nil
        }

        contentView.layoutSubtreeIfNeeded()
        let bounds = contentView.bounds.integral
        guard bounds.width > 0,
              bounds.height > 0,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }

        bitmap.size = bounds.size
        contentView.cacheDisplay(in: bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func imageFileName(for window: NSWindow, ordinal: Int) -> String {
        let baseName: String
        switch recognizedWindowKind(for: window) ?? "window" {
        case "overlay":
            baseName = "overlay"
        case "control-center":
            baseName = "control-center"
        default:
            baseName = "window-\(ordinal)"
        }

        return "\(baseName).png"
    }

    private static func accessibilityFileName(for window: NSWindow, ordinal: Int) -> String {
        let baseName: String
        switch recognizedWindowKind(for: window) ?? "window" {
        case "overlay":
            baseName = "overlay"
        case "control-center":
            baseName = "control-center"
        default:
            baseName = "window-\(ordinal)"
        }

        return "\(baseName).ax.json"
    }

    private static func windowKind(for window: NSWindow) -> String {
        recognizedWindowKind(for: window) ?? "window"
    }

    private static func recognizedWindowKind(for window: NSWindow) -> String? {
        if window is NSPanel {
            return window.frame.width >= 120 ? "overlay" : nil
        }

        if window.title == "Open Island Debug" {
            return "control-center"
        }

        return nil
    }

    private static func overlaySnapshot(
        from diagnostics: OverlayPlacementDiagnostics?
    ) -> HarnessArtifactReport.OverlaySnapshot? {
        guard let diagnostics else {
            return nil
        }

        return HarnessArtifactReport.OverlaySnapshot(
            screenID: diagnostics.targetScreenID,
            screenName: diagnostics.targetScreenName,
            selectionSummary: diagnostics.selectionSummary,
            mode: diagnostics.mode.rawValue,
            screenFrame: .init(diagnostics.screenFrame),
            visibleFrame: .init(diagnostics.visibleFrame),
            overlayFrame: .init(diagnostics.overlayFrame),
            safeAreaInsets: .init(diagnostics.safeAreaInsets)
        )
    }

    private static func surfaceDescription(_ surface: IslandSurface) -> String {
        switch surface {
        case .sessionList(actionableSessionID: nil):
            "sessionList"
        case let .sessionList(actionableSessionID: sessionID?):
            "sessionList:actionable(\(sessionID))"
        }
    }

    private static func notchStatusDescription(_ status: NotchStatus) -> String {
        switch status {
        case .closed:
            "closed"
        case .opened:
            "opened"
        case .popping:
            "popping"
        }
    }

    private static func snapshotViewAccessibilityTree(for window: NSWindow) -> HarnessArtifactReport.AccessibilityNode? {
        window.displayIfNeeded()

        if let contentView = window.contentView,
            let node = snapshotAccessibilityNode(from: contentView, fallbackChildren: contentView.subviews) {
            return node
        }

        return snapshotAccessibilityNode(from: window, fallbackChildren: [])
    }

    private static func mergedAccessibilitySummary(
        primary: HarnessArtifactReport.AccessibilityNode?,
        secondary: HarnessArtifactReport.AccessibilityNode?
    ) -> HarnessArtifactReport.AccessibilitySummary? {
        let roots = [primary, secondary].compactMap { $0 }
        guard roots.isEmpty == false else {
            return nil
        }

        var labels = Set<String>()
        var buttonLabels = Set<String>()
        var textValues = Set<String>()

        for root in roots {
            collectAccessibilityStrings(
                from: root,
                labels: &labels,
                buttonLabels: &buttonLabels,
                textValues: &textValues
            )
        }

        return HarnessArtifactReport.AccessibilitySummary(
            labels: labels.sorted(),
            buttonLabels: buttonLabels.sorted(),
            textValues: textValues.sorted()
        )
    }

    private static func snapshotAccessibilityNode(
        from rawElement: Any,
        fallbackChildren: [Any] = [],
        depth: Int = 0
    ) -> HarnessArtifactReport.AccessibilityNode? {
        guard depth <= 16 else {
            return nil
        }

        if let object = rawElement as? NSObject {
            let viewChildren = (rawElement as? NSView)?.subviews ?? []
            let rawAccessibilityChildren = selectorArrayValue("accessibilityChildren", on: object) ?? []
            let rawChildren: [Any]
            if rawAccessibilityChildren.isEmpty == false {
                rawChildren = rawAccessibilityChildren
            } else if viewChildren.isEmpty == false {
                rawChildren = viewChildren
            } else {
                rawChildren = fallbackChildren
            }
            let children = rawChildren.compactMap {
                snapshotAccessibilityNode(from: $0, depth: depth + 1)
            }

            var label = selectorStringValue("accessibilityLabel", on: object)
            var value = selectorStringValue("accessibilityValue", on: object)
            var role = selectorStringValue("accessibilityRole", on: object)
            let subrole = selectorStringValue("accessibilitySubrole", on: object)

            if let button = rawElement as? NSButton {
                label = label ?? trimmedString(button.title)
                role = role ?? "AXButton"
            } else if let textField = rawElement as? NSTextField {
                value = value ?? trimmedString(textField.stringValue)
                role = role ?? "AXStaticText"
            } else if let control = rawElement as? NSControl {
                value = value ?? trimmedString(control.stringValue)
            }

            if label == nil,
               value == nil,
               role == nil,
               subrole == nil,
               children.isEmpty {
                return nil
            }

            return HarnessArtifactReport.AccessibilityNode(
                typeName: String(describing: type(of: rawElement)),
                role: role,
                subrole: subrole,
                label: label,
                value: value,
                children: children
            )
        }

        if let view = rawElement as? NSView {
            let children = view.subviews.compactMap {
                snapshotAccessibilityNode(from: $0, depth: depth + 1)
            }

            if children.isEmpty {
                return nil
            }

            return HarnessArtifactReport.AccessibilityNode(
                typeName: String(describing: type(of: rawElement)),
                role: nil,
                subrole: nil,
                label: nil,
                value: nil,
                children: children
            )
        }

        return nil
    }

    private static func snapshotAXTree(for window: NSWindow) -> HarnessArtifactReport.AccessibilityNode? {
        let applicationElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        guard let axWindows = copyAXElementArrayValue(
            of: applicationElement,
            attribute: kAXWindowsAttribute as CFString
        ) else {
            return nil
        }

        let targetFrame = window.frame
        let targetTitle = trimmedString(window.title)
        let matchingWindow = axWindows.min { lhs, rhs in
            axWindowScore(for: lhs, targetFrame: targetFrame, targetTitle: targetTitle)
                < axWindowScore(for: rhs, targetFrame: targetFrame, targetTitle: targetTitle)
        }

        guard let matchingWindow else {
            return nil
        }

        return snapshotAXNode(from: matchingWindow)
    }

    private static func axWindowScore(
        for element: AXUIElement,
        targetFrame: NSRect,
        targetTitle: String?
    ) -> CGFloat {
        let frame = axFrame(for: element) ?? .zero
        let title = copyStringValue(of: element, attribute: kAXTitleAttribute as CFString)

        var score = abs(frame.origin.x - targetFrame.origin.x)
            + abs(frame.origin.y - targetFrame.origin.y)
            + abs(frame.size.width - targetFrame.size.width)
            + abs(frame.size.height - targetFrame.size.height)

        if targetTitle != nil, targetTitle == title {
            score -= 1000
        }

        return score
    }

    private static func snapshotAXNode(
        from element: AXUIElement,
        depth: Int = 0
    ) -> HarnessArtifactReport.AccessibilityNode? {
        guard depth <= 16 else {
            return nil
        }

        let children = copyAXElementArrayValue(
            of: element,
            attribute: kAXChildrenAttribute as CFString
        )?.compactMap { snapshotAXNode(from: $0, depth: depth + 1) } ?? []

        let role = copyStringValue(of: element, attribute: kAXRoleAttribute as CFString)
        let subrole = copyStringValue(of: element, attribute: kAXSubroleAttribute as CFString)
        let label = firstNonEmpty(
            copyStringValue(of: element, attribute: kAXTitleAttribute as CFString),
            copyStringValue(of: element, attribute: kAXDescriptionAttribute as CFString),
            copyStringValue(of: element, attribute: kAXHelpAttribute as CFString)
        )
        let value = stringValue(
            from: copyAttributeValue(of: element, attribute: kAXValueAttribute as CFString)
        )

        if role == nil,
           subrole == nil,
           label == nil,
           value == nil,
           children.isEmpty {
            return nil
        }

        return HarnessArtifactReport.AccessibilityNode(
            typeName: "AXUIElement",
            role: role,
            subrole: subrole,
            label: label,
            value: value,
            children: children
        )
    }

    private static func accessibilitySummary(
        from root: HarnessArtifactReport.AccessibilityNode
    ) -> HarnessArtifactReport.AccessibilitySummary {
        var labels = Set<String>()
        var buttonLabels = Set<String>()
        var textValues = Set<String>()

        collectAccessibilityStrings(
            from: root,
            labels: &labels,
            buttonLabels: &buttonLabels,
            textValues: &textValues
        )

        return HarnessArtifactReport.AccessibilitySummary(
            labels: labels.sorted(),
            buttonLabels: buttonLabels.sorted(),
            textValues: textValues.sorted()
        )
    }

    private static func collectAccessibilityStrings(
        from node: HarnessArtifactReport.AccessibilityNode,
        labels: inout Set<String>,
        buttonLabels: inout Set<String>,
        textValues: inout Set<String>
    ) {
        if let label = trimmedString(node.label) {
            labels.insert(label)
            if node.role?.localizedCaseInsensitiveContains("button") == true {
                buttonLabels.insert(label)
            }
        }

        if let value = trimmedString(node.value) {
            textValues.insert(value)
        }

        for child in node.children {
            collectAccessibilityStrings(
                from: child,
                labels: &labels,
                buttonLabels: &buttonLabels,
                textValues: &textValues
            )
        }
    }

    private static func trimmedString(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringValue(from rawValue: Any?) -> String? {
        switch rawValue {
        case let string as String:
            return trimmedString(string)
        case let attributed as NSAttributedString:
            return trimmedString(attributed.string)
        case let number as NSNumber:
            return number.stringValue
        case let value?:
            return trimmedString(String(describing: value))
        case nil:
            return nil
        }
    }

    private static func selectorStringValue(_ selectorName: String, on object: NSObject) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else {
            return nil
        }

        return stringValue(from: object.perform(selector)?.takeUnretainedValue())
    }

    private static func selectorArrayValue(_ selectorName: String, on object: NSObject) -> [Any]? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else {
            return nil
        }

        return object.perform(selector)?.takeUnretainedValue() as? [Any]
    }

    private static func copyAttributeValue(
        of element: AXUIElement,
        attribute: CFString
    ) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }

        return value
    }

    private static func copyStringValue(
        of element: AXUIElement,
        attribute: CFString
    ) -> String? {
        stringValue(from: copyAttributeValue(of: element, attribute: attribute))
    }

    private static func copyAXElementArrayValue(
        of element: AXUIElement,
        attribute: CFString
    ) -> [AXUIElement]? {
        copyAttributeValue(of: element, attribute: attribute) as? [AXUIElement]
    }

    private static func axFrame(for element: AXUIElement) -> NSRect? {
        guard let positionRef = copyAttributeValue(
            of: element,
            attribute: kAXPositionAttribute as CFString
        ),
        let sizeRef = copyAttributeValue(
            of: element,
            attribute: kAXSizeAttribute as CFString
        ),
        CFGetTypeID(positionRef) == AXValueGetTypeID(),
        CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }

        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionValue) == .cgPoint,
              AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }

        return NSRect(origin: position, size: size)
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.first(where: { value in
            guard let value else {
                return false
            }
            return value.isEmpty == false
        }) ?? nil
    }
}
