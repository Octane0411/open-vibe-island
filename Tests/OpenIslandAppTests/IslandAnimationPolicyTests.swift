import Foundation
import Testing
@testable import OpenIslandApp

struct IslandAnimationPolicyTests {
    @Test
    func panelFrameAnimationUsesVibeStyleTiming() {
        #expect(IslandAnimationPolicy.panelFrameBaseDuration == 0.55)
        #expect(IslandAnimationPolicy.panelFrameBaseCloseDuration == 0.75)
        #expect(IslandAnimationPolicy.panelFrameDuration(isClosing: false) == 0.55)
        #expect(IslandAnimationPolicy.panelFrameDuration(isClosing: true) == 0.75)
        #expect(IslandAnimationPolicy.panelFrameTimingControlPoints == (0.2, 0.8, 0.2, 1.0))
        #expect(IslandAnimationPolicy.frameAnimationDriver == .nativePanelAnimator)
    }

    @Test
    func panelFrameAnimationSpeedScalesOpenAndCloseDurations() {
        #expect(IslandAnimationPolicy.panelFrameDuration(isClosing: false, speed: .fast) < IslandAnimationPolicy.panelFrameDuration(isClosing: false))
        #expect(IslandAnimationPolicy.panelFrameDuration(isClosing: true, speed: .slow) > IslandAnimationPolicy.panelFrameDuration(isClosing: true))
        #expect(IslandAnimationPolicy.panelFrameDuration(isClosing: true, speed: .fast) > IslandAnimationPolicy.panelFrameDuration(isClosing: false, speed: .fast))
    }

    @Test
    func openedSurfaceStaysMountedThroughCloseFrameMorph() {
        #expect(openedSurfaceUnmountDelay(for: .normal) > IslandAnimationPolicy.panelFrameDuration(isClosing: true))
        #expect(openedSurfaceUnmountDelay(for: .slow) > openedSurfaceUnmountDelay(for: .fast))
    }

    @Test
    func openedSurfaceContentRevealsAfterFrameHasSafeWidth() {
        let revealDelay = IslandAnimationPolicy.openedContentRevealDelay(speed: .normal)
        let openDuration = IslandAnimationPolicy.panelFrameDuration(isClosing: false, speed: .normal)

        #expect(IslandAnimationPolicy.openingHeightLeadDuration <= revealDelay)
        #expect(revealDelay >= openDuration * 0.55)
        #expect(revealDelay < openDuration * 0.8)
    }

    @Test
    func openedSurfaceContentRevealDelayScalesWithAnimationSpeed() {
        #expect(IslandAnimationPolicy.openedContentRevealDelay(speed: .fast) < IslandAnimationPolicy.openedContentRevealDelay(speed: .normal))
        #expect(IslandAnimationPolicy.openedContentRevealDelay(speed: .slow) > IslandAnimationPolicy.openedContentRevealDelay(speed: .normal))
    }

    @Test
    func openingFrameInterpolationReachesTargetHeightBeforeFullWidth() {
        let start = CGRect(x: 100, y: 800, width: 300, height: 50)
        let target = CGRect(x: 0, y: 570, width: 680, height: 280)
        let revealRatio = IslandAnimationPolicy.openedContentRevealDelay(speed: .normal)
            / IslandAnimationPolicy.panelFrameDuration(isClosing: false, speed: .normal)

        let frameAtReveal = OverlayPanelController.interpolatedOpeningFrame(
            from: start,
            to: target,
            progress: revealRatio
        )

        #expect(frameAtReveal.height == target.height)
        #expect(frameAtReveal.width < target.width)
        #expect(frameAtReveal.maxY == start.maxY)
    }

    @Test
    func closingFrameInterpolationShrinksWidthAndHeightTogetherFromTopAnchor() {
        let start = CGRect(x: 0, y: 570, width: 680, height: 280)
        let target = CGRect(x: 193, y: 799, width: 294, height: 51)
        let half = OverlayPanelController.interpolatedClosingFrame(
            from: start,
            to: target,
            progress: 0.5
        )

        #expect(half.width < start.width)
        #expect(half.width > target.width)
        #expect(half.height < start.height)
        #expect(half.height > target.height)
        #expect(half.maxY == start.maxY)
    }

    @Test
    func closedSurfaceStaysVisibleAboveRetainedOpenedSurfaceDuringClose() {
        let closing = IslandSurfaceLayering(
            notchStatus: .closed,
            keepsOpenedSurfaceMounted: true,
            rendersClosedSurface: true
        )

        #expect(!closing.shouldRenderClosedSurface)
        #expect(closing.shouldRenderOpenedSurface)
        #expect(!closing.shouldRenderOpenedContent)
        #expect(closing.rendersClosedContentInOpenedSurface)
        #expect(closing.closedSurfaceZIndex < closing.openedSurfaceZIndex)
    }

    @Test
    func closingMorphUsesClosedPillShapeBeforeUnmountingOpenedSurface() {
        let closing = IslandSurfaceLayering(
            notchStatus: .closed,
            keepsOpenedSurfaceMounted: true,
            rendersClosedSurface: true
        )

        #expect(closing.openedSurfaceTopProfile(usesNotchAwareHeader: true) == .topBar)
        #expect(closing.openedSurfaceTopProfile(usesNotchAwareHeader: false) == .topBar)

        let opened = IslandSurfaceLayering(
            notchStatus: .opened,
            keepsOpenedSurfaceMounted: true,
            rendersClosedSurface: false
        )
        #expect(opened.openedSurfaceTopProfile(usesNotchAwareHeader: true) == .notch)
        #expect(opened.openedSurfaceTopProfile(usesNotchAwareHeader: false) == .topBar)
    }

    @Test
    func openedSurfaceContentOnlyMountsInOpenedState() {
        let opened = IslandSurfaceLayering(
            notchStatus: .opened,
            keepsOpenedSurfaceMounted: true,
            rendersClosedSurface: false,
            showsOpenedContent: true
        )
        let openedBeforeReveal = IslandSurfaceLayering(
            notchStatus: .opened,
            keepsOpenedSurfaceMounted: true,
            rendersClosedSurface: false,
            showsOpenedContent: false
        )
        let closing = IslandSurfaceLayering(
            notchStatus: .closed,
            keepsOpenedSurfaceMounted: true,
            rendersClosedSurface: true
        )

        #expect(opened.shouldRenderOpenedContent)
        #expect(!openedBeforeReveal.shouldRenderOpenedContent)
        #expect(!closing.shouldRenderOpenedContent)
    }

    @Test @MainActor
    func closedPillCanLockToMorphingPanelContentWidth() {
        #expect(V6ClosedPillGeometry.outerWidth(
            layout: .macbook,
            height: 34,
            label: nil,
            rightSlot: .count(3),
            physicalNotchWidth: 224,
            minWidth: 70,
            outerWidthOverride: 258
        ) == 258)

        #expect(V6ClosedPillGeometry.outerWidth(
            layout: .external,
            height: 34,
            label: "Codex",
            rightSlot: .count(3),
            physicalNotchWidth: 0,
            minWidth: 70,
            outerWidthOverride: 360
        ) == 360)
    }

    @Test
    func openedSurfaceStaysAboveClosedSurfaceWhileOpened() {
        let opened = IslandSurfaceLayering(
            notchStatus: .opened,
            keepsOpenedSurfaceMounted: true,
            rendersClosedSurface: false
        )

        #expect(!opened.shouldRenderClosedSurface)
        #expect(opened.openedSurfaceZIndex > opened.closedSurfaceZIndex)
    }

    @Test
    func hoverTimingUsesVibeStyleDelays() {
        #expect(IslandAnimationPolicy.hoverOpenDelay == 0.20)
        #expect(IslandAnimationPolicy.hoverCooldownDuration == 0.18)
        #expect(IslandAnimationPolicy.hoverSurfaceAutoCollapseDelay == 0.18)
    }

    @Test
    func hoverOpenIsBlockedDuringCooldown() {
        let now = Date(timeIntervalSince1970: 100)
        #expect(!IslandAnimationPolicy.canScheduleHoverOpen(now: now, cooldownUntil: now.addingTimeInterval(0.05)))
        #expect(IslandAnimationPolicy.canScheduleHoverOpen(now: now, cooldownUntil: now.addingTimeInterval(-0.01)))
    }
}
