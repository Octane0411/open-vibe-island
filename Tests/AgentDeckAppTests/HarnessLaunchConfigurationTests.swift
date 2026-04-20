import Foundation
import Testing
@testable import AgentDeckApp

struct HarnessLaunchConfigurationTests {
    @Test
    func defaultsMatchNormalAppLaunch() {
        let configuration = HarnessLaunchConfiguration(environment: [:])

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(configuration.shouldShowControlCenter)
        #expect(configuration.shouldStartBridge)
        #expect(configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }

    @Test
    func parsesScenarioFlagsAndAutoExit() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "AGENT_DECK_HARNESS_SCENARIO": "approvalcard",
                "AGENT_DECK_HARNESS_PRESENT_OVERLAY": "true",
                "AGENT_DECK_HARNESS_SHOW_CONTROL_CENTER": "0",
                "AGENT_DECK_HARNESS_START_BRIDGE": "no",
                "AGENT_DECK_HARNESS_BOOT_ANIMATION": "off",
                "AGENT_DECK_HARNESS_CAPTURE_DELAY_SECONDS": "1.5",
                "AGENT_DECK_HARNESS_AUTO_EXIT_SECONDS": "2.5",
                "AGENT_DECK_HARNESS_ARTIFACT_DIR": "/tmp/agent-deck-artifacts",
            ]
        )

        #expect(configuration.scenario == .approvalCard)
        #expect(configuration.presentOverlay)
        #expect(!configuration.shouldShowControlCenter)
        #expect(!configuration.shouldStartBridge)
        #expect(!configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == 1.5)
        #expect(configuration.autoExitAfter == 2.5)
        #expect(configuration.artifactDirectoryURL?.path == "/tmp/agent-deck-artifacts")
    }

    @Test
    func ignoresInvalidInputs() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "AGENT_DECK_HARNESS_SCENARIO": "missing",
                "AGENT_DECK_HARNESS_PRESENT_OVERLAY": "unexpected",
                "AGENT_DECK_HARNESS_CAPTURE_DELAY_SECONDS": "0",
                "AGENT_DECK_HARNESS_AUTO_EXIT_SECONDS": "-1",
                "AGENT_DECK_HARNESS_ARTIFACT_DIR": "   ",
            ]
        )

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }
}
