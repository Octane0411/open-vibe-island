import Foundation
import Testing
@testable import OpenIslandApp

struct HarnessLaunchConfigurationTests {
    @Test
    func defaultsMatchNormalAppLaunch() {
        let configuration = HarnessLaunchConfiguration(environment: [:])

        #expect(configuration.scenario == nil)
        #expect(!configuration.disablesOverlayEventMonitoring)
        #expect(!configuration.presentOverlay)
        #expect(configuration.shouldStartBridge)
        #expect(configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }

    @Test
    func harnessScenariosDisableOverlayEventMonitoring() {
        let closed = HarnessLaunchConfiguration(
            environment: ["OPEN_ISLAND_HARNESS_SCENARIO": "closed"]
        )
        let opened = HarnessLaunchConfiguration(
            environment: ["OPEN_ISLAND_HARNESS_SCENARIO": "sessionList"]
        )

        #expect(closed.disablesOverlayEventMonitoring)
        #expect(opened.disablesOverlayEventMonitoring)
    }

    @Test
    func interactiveHarnessKeepsOverlayEventMonitoringEnabled() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "OPEN_ISLAND_HARNESS_SCENARIO": "closed",
                "OPEN_ISLAND_HARNESS_INTERACTIVE": "1",
            ]
        )

        #expect(!configuration.disablesOverlayEventMonitoring)
    }

    @Test
    func parsesScenarioFlagsAndAutoExit() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "OPEN_ISLAND_HARNESS_SCENARIO": "approvalcard",
                "OPEN_ISLAND_HARNESS_PRESENT_OVERLAY": "true",
                "OPEN_ISLAND_HARNESS_START_BRIDGE": "no",
                "OPEN_ISLAND_HARNESS_BOOT_ANIMATION": "off",
                "OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS": "1.5",
                "OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS": "2.5",
                "OPEN_ISLAND_HARNESS_ARTIFACT_DIR": "/tmp/open-island-artifacts",
            ]
        )

        #expect(configuration.scenario == .approvalCard)
        #expect(configuration.presentOverlay)
        #expect(!configuration.shouldStartBridge)
        #expect(!configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == 1.5)
        #expect(configuration.autoExitAfter == 2.5)
        #expect(configuration.artifactDirectoryURL?.path == "/tmp/open-island-artifacts")
    }

    @Test
    func ignoresInvalidInputs() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "OPEN_ISLAND_HARNESS_SCENARIO": "missing",
                "OPEN_ISLAND_HARNESS_PRESENT_OVERLAY": "unexpected",
                "OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS": "0",
                "OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS": "-1",
                "OPEN_ISLAND_HARNESS_ARTIFACT_DIR": "   ",
            ]
        )

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }
}
