import Foundation
import Testing
@testable import OpenIslandApp

struct PerformancePolicyTests {
    @Test
    func idleUnifiedBarsDoesNotRequireAnimationTimeline() {
        #expect(UnifiedBars.Mode.idle.timelineInterval == nil)
    }

    @Test
    func activeUnifiedBarsDoNotRequireAnimationTimeline() {
        #expect(UnifiedBars.Mode.running.timelineInterval == nil)
        #expect(UnifiedBars.Mode.waiting.timelineInterval == nil)
    }

    @Test
    func activeUnifiedBarsUseCoreAnimationLayerAnimation() {
        #expect(!UnifiedBars.Mode.idle.usesLayerAnimation)
        #expect(UnifiedBars.Mode.running.usesLayerAnimation)
        #expect(UnifiedBars.Mode.waiting.usesLayerAnimation)
    }

    @MainActor
    @Test
    func monitoringPollIntervalBacksOffOutsideStartupResolution() {
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: true,
            hasTrackedLiveSessions: false
        ) == 2)
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true
        ) == 60)
        #expect(ProcessMonitoringCoordinator.monitoringPollInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: false
        ) == 300)
    }

    @MainActor
    @Test
    func codexDesktopProbeKeepsShortWakeCadenceWhileFullReconcileBacksOff() {
        #expect(ProcessMonitoringCoordinator.monitoringWakeInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: false
        ) == 2)
        #expect(ProcessMonitoringCoordinator.monitoringWakeInterval(
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true
        ) == 2)
    }

    @MainActor
    @Test
    func trackedSessionTransitionForcesFullReconcileBeforeIdleDeadline() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let idleDeadline = now.addingTimeInterval(300)

        #expect(!ProcessMonitoringCoordinator.shouldPerformFullMonitorReconcile(
            now: now,
            nextFullReconcileAt: idleDeadline,
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: false,
            hadTrackedLiveSessions: false
        ))
        #expect(ProcessMonitoringCoordinator.shouldPerformFullMonitorReconcile(
            now: now,
            nextFullReconcileAt: idleDeadline,
            isResolvingInitialLiveSessions: false,
            hasTrackedLiveSessions: true,
            hadTrackedLiveSessions: false
        ))
    }

    @Test
    func sessionDotDoesNotRequireSwiftUIAnimationTimeline() {
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .inactive,
            isActionable: false
        ) == nil)
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .active,
            isActionable: false
        ) == nil)
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .running,
            isActionable: false
        ) == nil)
        #expect(IslandSessionStateIndicator.animatedDot.timelineInterval(
            presence: .inactive,
            isActionable: true
        ) == nil)
    }

    @Test
    func activeSessionDotUsesCoreAnimationLayerAnimation() {
        #expect(!IslandSessionStateIndicator.animatedDot.usesLayerAnimation(
            presence: .inactive,
            isActionable: false
        ))
        #expect(IslandSessionStateIndicator.animatedDot.usesLayerAnimation(
            presence: .running,
            isActionable: false
        ))
        #expect(IslandSessionStateIndicator.animatedDot.usesLayerAnimation(
            presence: .inactive,
            isActionable: true
        ))
        #expect(!IslandSessionStateIndicator.bar.usesLayerAnimation(
            presence: .running,
            isActionable: false
        ))
    }
}
