import AppKit
import Testing
@testable import OpenIslandApp

struct OverlayPanelControllerTests {
    @Test
    func legacyDisplayPreferenceResetsToAutomatic() {
        #expect(
            OverlayDisplayPreferencePolicy.restoredSelectionID(from: "display-69733248")
                == OverlayDisplayOption.automaticID
        )
    }

    @Test
    func missingDisplayPreferenceDefaultsToAutomatic() {
        #expect(
            OverlayDisplayPreferencePolicy.restoredSelectionID(from: nil)
                == OverlayDisplayOption.automaticID
        )
        #expect(
            OverlayDisplayPreferencePolicy.restoredSelectionID(from: "")
                == OverlayDisplayOption.automaticID
        )
    }

    @Test
    func stableDisplayPreferenceSurvivesRestore() {
        let displayUUID = "7A4C9F42-40FD-4EB4-B189-27F55385629C"

        #expect(
            OverlayDisplayPreferencePolicy.restoredSelectionID(from: displayUUID)
                == displayUUID
        )
    }

    @Test
    func disconnectedDisplayPreferenceRemainsSelected() {
        let displayUUID = "7A4C9F42-40FD-4EB4-B189-27F55385629C"
        let builtIn = OverlayDisplayOption(
            id: "built-in",
            title: "Built-in Display",
            subtitle: "Built-in notch"
        )

        let result = OverlayDisplayPreferencePolicy.reconcile(
            availableOptions: [builtIn],
            selectionID: displayUUID,
            rememberedSelectionTitle: "External Display"
        )

        #expect(result.selectionID == displayUUID)
        #expect(result.selectionTitle == "External Display")
        #expect(result.displayOptions.count == 2)
        #expect(result.displayOptions.last?.id == displayUUID)
        #expect(result.displayOptions.last?.title == "External Display")
        #expect(result.displayOptions.last?.isAvailable == false)
    }

    @Test
    func reconnectedDisplayReplacesUnavailablePlaceholder() {
        let displayUUID = "7A4C9F42-40FD-4EB4-B189-27F55385629C"
        let external = OverlayDisplayOption(
            id: displayUUID,
            title: "External Display",
            subtitle: "Top-bar fallback"
        )

        let result = OverlayDisplayPreferencePolicy.reconcile(
            availableOptions: [external],
            selectionID: displayUUID,
            rememberedSelectionTitle: "External Display"
        )

        #expect(result.selectionID == displayUUID)
        #expect(result.selectionTitle == "External Display")
        #expect(result.displayOptions == [external])
        #expect(result.displayOptions[0].isAvailable)
    }

    @Test
    func automaticPreferenceDoesNotCreateUnavailablePlaceholder() {
        let result = OverlayDisplayPreferencePolicy.reconcile(
            availableOptions: [],
            selectionID: OverlayDisplayOption.automaticID,
            rememberedSelectionTitle: "External Display"
        )

        #expect(result.selectionID == OverlayDisplayOption.automaticID)
        #expect(result.selectionTitle == nil)
        #expect(result.displayOptions.isEmpty)
    }

    @Test
    func closedSurfaceRectCentersOnNotch() {
        let notchRect = NSRect(x: 200, y: 900, width: 200, height: 38)
        let closedWidth: CGFloat = 320

        let rect = OverlayPanelController.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )

        // Centered on notch midX (300), width 320
        #expect(rect.minX == 140)
        #expect(rect.minY == 900)
        #expect(rect.width == 320)
        #expect(rect.height == 38)
    }

    @Test
    func closedSurfaceRectHitTestingBoundary() {
        let notchRect = NSRect(x: 400, y: 1_000, width: 200, height: 38)
        let closedWidth: CGFloat = 420

        let rect = OverlayPanelController.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )

        #expect(rect.contains(NSPoint(x: rect.minX + 2, y: rect.midY)))
        #expect(rect.contains(NSPoint(x: rect.maxX - 2, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.minX - 1, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.maxX + 1, y: rect.midY)))
    }

    @Test
    func edgeInclusiveHitTestingTreatsMaxBoundaryAsInside() {
        let rect = NSRect(x: 100, y: 200, width: 224, height: 8)
        #expect(OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 150, y: 208)))
        #expect(OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 324, y: 205)))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 325, y: 205)))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 150, y: 209)))
    }

    @Test
    func notchedDisplayClosedWidthWrapsPhysicalNotchWithFixedReserve() {
        // v6 MacBook layout: outer width = 44 + physical notch + 44.
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            isNotchedDisplay: true,
            notchStatus: .closed
        )
        #expect(width == CGFloat(224 + 88))
    }

    @Test
    func externalDisplayClosedWidthUsesFixedHitArea() {
        // v6 external layout: fluid in SwiftUI, but the controller uses a
        // generous fixed hit-area so hover/click works without knowing the
        // live content width.
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 0,
            isNotchedDisplay: false,
            notchStatus: .closed
        )
        #expect(width == CGFloat(360))
    }

    @Test
    func poppingStatusAddsHoverBudget() {
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            isNotchedDisplay: true,
            notchStatus: .popping
        )
        #expect(width == CGFloat(224 + 88 + 18))
    }

    @Test
    func clickOpensActivateThePanel() {
        #expect(OverlayPanelController.shouldActivatePanel(for: .click))
    }

    @Test
    func passiveOpensDoNotActivateThePanel() {
        #expect(!OverlayPanelController.shouldActivatePanel(for: .hover))
        #expect(!OverlayPanelController.shouldActivatePanel(for: .notification))
        #expect(!OverlayPanelController.shouldActivatePanel(for: .boot))
        #expect(!OverlayPanelController.shouldActivatePanel(for: nil))
    }

    /// Verifies the default behavior keeps the overlay in fullscreen-capable all-Spaces mode.
    @Test
    func collectionBehaviorIncludesFullscreenAuxiliaryByDefault() {
        let behavior = OverlayPanelController.collectionBehavior(hideFullscreen: false)

        #expect(behavior.contains(.fullScreenAuxiliary))
        #expect(behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.ignoresCycle))
        #expect(behavior.contains(.stationary))
    }

    /// Verifies fullscreen hiding removes the flags that make the overlay follow fullscreen Spaces.
    @Test
    func collectionBehaviorExcludesFullscreenAuxiliaryWhenFullscreenHidingIsEnabled() {
        let behavior = OverlayPanelController.collectionBehavior(hideFullscreen: true)

        #expect(!behavior.contains(.fullScreenAuxiliary))
        #expect(!behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.ignoresCycle))
        #expect(behavior.contains(.stationary))
    }

    // MARK: - islandClosedHeight

    @Test
    func islandClosedHeightClampsToNotchHeightWhenSmallerThanMenuBar() {
        // Simulates MacBook Air M2: physical notch ≈ 34 pt, menu bar reserved ≈ 37 pt.
        // Must return 34 (the smaller value) so the island sits flush with the notch.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 34, topStatusBarHeight: 37)
        #expect(height == 34)
    }

    @Test
    func islandClosedHeightUsesNotchHeightEvenWhenMenuBarIsShorter() {
        // When menu bar reserved < notch (e.g. auto-hide menu bar), the island must
        // still match the physical notch height to avoid a visible gap.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 37, topStatusBarHeight: 34)
        #expect(height == 37)
    }

    @Test
    func islandClosedHeightFallsBackToMenuBarHeightOnNonNotchScreen() {
        // Non-notch screen: safeAreaInsets.top == 0, fall back to topStatusBarHeight.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 0, topStatusBarHeight: 24)
        #expect(height == 24)
    }
}
