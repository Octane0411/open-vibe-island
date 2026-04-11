import AppKit
import Testing
@testable import OpenIslandApp

struct OverlayPanelControllerTests {
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
    func hiddenIdleEdgeClosedWidthStaysAtNotchWidth() {
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            notchHeight: 38,
            liveSessionCount: 3,
            hasAttention: true,
            notchStatus: .closed,
            showsIdleEdgeWhenCollapsed: true
        )

        #expect(width == 224)
    }

    @Test
    func regularClosedWidthStillIncludesSessionIndicators() {
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            notchHeight: 38,
            liveSessionCount: 3,
            hasAttention: true,
            notchStatus: .closed,
            showsIdleEdgeWhenCollapsed: false
        )

        #expect(width == 344)
    }

    @Test
    func hiddenIdleEdgeHoverRectAnchorsToTopOfClosedArea() {
        let notchRect = NSRect(x: 400, y: 1_000, width: 224, height: 38)

        let rect = OverlayPanelController.hiddenIdleEdgeHoverRect(
            notchRect: notchRect,
            closedWidth: 224,
            hoverHitHeight: 8
        )

        #expect(rect.minX == 400)
        #expect(rect.maxY == notchRect.maxY)
        #expect(rect.height == 8)
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

    @Test
    func closedTopBarAllowsDirectMouseInteraction() {
        #expect(
            OverlayPanelController.acceptsDirectMouseInteraction(
                status: .closed,
                mode: .topBar
            )
        )
    }

    @Test
    func closedNotchKeepsPassiveMouseInteraction() {
        #expect(
            !OverlayPanelController.acceptsDirectMouseInteraction(
                status: .closed,
                mode: .notch
            )
        )
    }

    @Test
    func hoverOpenedTopBarAllowsHeaderDrag() {
        #expect(
            OverlayPanelController.canDragOpenedTopBarHeader(
                status: .opened,
                mode: .topBar,
                openReason: .hover
            )
        )
    }

    @Test
    func clickOpenedTopBarDoesNotAllowHeaderDrag() {
        #expect(
            !OverlayPanelController.canDragOpenedTopBarHeader(
                status: .opened,
                mode: .topBar,
                openReason: .click
            )
        )
    }

    @Test
    func hoverOpenedNotchDoesNotAllowHeaderDrag() {
        #expect(
            !OverlayPanelController.canDragOpenedTopBarHeader(
                status: .opened,
                mode: .notch,
                openReason: .hover
            )
        )
    }

    @Test
    func openedTopBarHeaderLeftAreaCanStartDrag() {
        let contentRect = NSRect(x: 18, y: 14, width: 700, height: 500)
        let dragRect = OverlayPanelController.openedTopBarHeaderDragRect(
            contentRect: contentRect,
            headerHeight: 30,
            trailingControlWidth: IslandPanelView.topBarOpenedHeaderTrailingControlWidth,
            horizontalPadding: IslandPanelView.topBarOpenedHeaderHorizontalPadding
        )

        #expect(dragRect.contains(NSPoint(x: 56, y: 498)))
    }

    @Test
    func openedTopBarHeaderControlButtonsAreaCannotStartDrag() {
        let contentRect = NSRect(x: 18, y: 14, width: 700, height: 500)
        let dragRect = OverlayPanelController.openedTopBarHeaderDragRect(
            contentRect: contentRect,
            headerHeight: 30,
            trailingControlWidth: IslandPanelView.topBarOpenedHeaderTrailingControlWidth,
            horizontalPadding: IslandPanelView.topBarOpenedHeaderHorizontalPadding
        )

        #expect(!dragRect.contains(NSPoint(x: 686, y: 498)))
    }

    @Test
    func openedTopBarHeaderBelowAreaCannotStartDrag() {
        let contentRect = NSRect(x: 18, y: 14, width: 700, height: 500)
        let dragRect = OverlayPanelController.openedTopBarHeaderDragRect(
            contentRect: contentRect,
            headerHeight: 30,
            trailingControlWidth: IslandPanelView.topBarOpenedHeaderTrailingControlWidth,
            horizontalPadding: IslandPanelView.topBarOpenedHeaderHorizontalPadding
        )

        #expect(!dragRect.contains(NSPoint(x: 56, y: 476)))
    }

    @Test
    func hoverOpenedTopBarHeaderHitIsCapturedByDragLayer() {
        let contentRect = NSRect(x: 18, y: 14, width: 700, height: 500)

        let shouldCapture = OverlayPanelController.shouldCaptureOpenedTopBarHeaderDrag(
            status: .opened,
            mode: .topBar,
            openReason: .hover,
            point: NSPoint(x: 56, y: 498),
            contentRect: contentRect,
            headerHeight: 30,
            trailingControlWidth: IslandPanelView.topBarOpenedHeaderTrailingControlWidth,
            horizontalPadding: IslandPanelView.topBarOpenedHeaderHorizontalPadding
        )

        #expect(shouldCapture)
    }

    @Test
    func hoverOpenedTopBarControlButtonsHitIsNotCapturedByDragLayer() {
        let contentRect = NSRect(x: 18, y: 14, width: 700, height: 500)

        let shouldCapture = OverlayPanelController.shouldCaptureOpenedTopBarHeaderDrag(
            status: .opened,
            mode: .topBar,
            openReason: .hover,
            point: NSPoint(x: 686, y: 498),
            contentRect: contentRect,
            headerHeight: 30,
            trailingControlWidth: IslandPanelView.topBarOpenedHeaderTrailingControlWidth,
            horizontalPadding: IslandPanelView.topBarOpenedHeaderHorizontalPadding
        )

        #expect(!shouldCapture)
    }

    @Test
    func clickOpenedTopBarHeaderHitIsNotCapturedByDragLayer() {
        let contentRect = NSRect(x: 18, y: 14, width: 700, height: 500)

        let shouldCapture = OverlayPanelController.shouldCaptureOpenedTopBarHeaderDrag(
            status: .opened,
            mode: .topBar,
            openReason: .click,
            point: NSPoint(x: 56, y: 498),
            contentRect: contentRect,
            headerHeight: 30,
            trailingControlWidth: IslandPanelView.topBarOpenedHeaderTrailingControlWidth,
            horizontalPadding: IslandPanelView.topBarOpenedHeaderHorizontalPadding
        )

        #expect(!shouldCapture)
    }

    @Test
    func eventMonitorDefersClosedTopBarClicksWhenPanelIsInteractive() {
        #expect(
            !OverlayPanelController.shouldEventMonitorHandleClosedSurfaceClick(
                status: .closed,
                mode: .topBar,
                panelIgnoresMouseEvents: false
            )
        )
    }

    @Test
    func automaticSelectionDoesNotBecomeManualTarget() {
        #expect(
            OverlayPanelController.normalizedPreferredScreenID(
                OverlayDisplayOption.automaticID
            ) == nil
        )
        #expect(
            OverlayPanelController.normalizedPreferredScreenID(
                "display-external"
            ) == "display-external"
        )
    }

    @Test
    func closedTopBarPressSuppressesHoverOpen() {
        #expect(
            !OverlayPanelController.shouldArmClosedSurfaceHoverOpen(
                status: .closed,
                mode: .topBar,
                isPressingClosedTopBarPill: true
            )
        )
    }

    @Test
    func closedTopBarWithoutPressStillAllowsHoverOpen() {
        #expect(
            OverlayPanelController.shouldArmClosedSurfaceHoverOpen(
                status: .closed,
                mode: .topBar,
                isPressingClosedTopBarPill: false
            )
        )
    }

    @Test
    func closedNotchPressDoesNotSuppressHoverOpen() {
        #expect(
            OverlayPanelController.shouldArmClosedSurfaceHoverOpen(
                status: .closed,
                mode: .notch,
                isPressingClosedTopBarPill: true
            )
        )
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
    func islandClosedHeightFallsBackToCompactPillOnNonNotchScreen() {
        // Non-notch screen: safeAreaInsets.top == 0, use a compact 22pt pill height.
        // The closed pill only shows an icon + count badge so it doesn't need the
        // full menu-bar strip height.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 0, topStatusBarHeight: 24)
        #expect(height == 22)
    }

    @Test
    func topBarOpenedHeaderAllowanceUsesMinimumThirtyPoints() {
        let closedHeight = NSScreen.computeIslandClosedHeight(
            safeAreaInsetsTop: 0,
            topStatusBarHeight: 24
        )
        let metrics = OverlayClosedShellMetrics.forMode(
            .topBar,
            closedHeight: closedHeight
        )

        #expect(metrics.openedHeaderHeight == 30)
    }

    @Test
    func closedSurfaceRectPreservesCompactTopBarPillHeight() {
        let notchRect = NSRect(x: 600, y: 980, width: 120, height: 22)
        let closedWidth: CGFloat = 64

        let rect = OverlayPanelController.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )

        #expect(rect.height == 22)
        #expect(rect.midX == notchRect.midX)
    }
}
