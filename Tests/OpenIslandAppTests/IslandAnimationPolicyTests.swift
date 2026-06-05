import Foundation
import Testing
@testable import OpenIslandApp

struct IslandAnimationPolicyTests {
    @Test
    func panelFrameAnimationUsesVibeStyleTiming() {
        #expect(IslandAnimationPolicy.panelFrameDuration == 0.80)
        #expect(IslandAnimationPolicy.panelFrameDuration(isClosing: false) == 0.80)
        #expect(IslandAnimationPolicy.panelFrameDuration(isClosing: true) == 1.10)
        #expect(IslandAnimationPolicy.panelFrameTimingControlPoints == (0.2, 0.8, 0.2, 1.0))
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
