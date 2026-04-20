import Testing
@testable import AgentDeckApp

struct HarnessRuntimeMonitorTests {
    @Test
    func derivesTimingSummaryFromTimelineEvents() {
        let events = [
            HarnessRuntimeEvent(
                category: "milestone",
                name: "applicationDidFinishLaunching",
                message: nil,
                offsetSeconds: 0.001
            ),
            HarnessRuntimeEvent(
                category: "milestone",
                name: "bootstrapStarted",
                message: nil,
                offsetSeconds: 0.010
            ),
            HarnessRuntimeEvent(
                category: "milestone",
                name: "bridgeSkipped",
                message: "Deterministic harness mode active.",
                offsetSeconds: 0.020
            ),
            HarnessRuntimeEvent(
                category: "milestone",
                name: "modelStarted",
                message: nil,
                offsetSeconds: 0.030
            ),
            HarnessRuntimeEvent(
                category: "milestone",
                name: "scenarioLoaded",
                message: "Approval Card",
                offsetSeconds: 0.040
            ),
            HarnessRuntimeEvent(
                category: "milestone",
                name: "overlayPresented",
                message: "Approval Card",
                offsetSeconds: 0.050
            ),
            HarnessRuntimeEvent(
                category: "milestone",
                name: "controlCenterConfigured",
                message: "hidden",
                offsetSeconds: 0.060
            ),
            HarnessRuntimeEvent(
                category: "milestone",
                name: "bootstrapCompleted",
                message: nil,
                offsetSeconds: 0.070
            ),
            HarnessRuntimeEvent(
                category: "milestone",
                name: "captureScheduled",
                message: "1.000s",
                offsetSeconds: 0.080
            ),
            HarnessRuntimeEvent(
                category: "milestone",
                name: "captureStarted",
                message: nil,
                offsetSeconds: 1.080
            ),
            HarnessRuntimeEvent(
                category: "log",
                name: "lastActionMessage",
                message: "Loaded debug scenario: Approval Card.",
                offsetSeconds: 1.100
            ),
        ]

        let artifacts = HarnessRuntimeArtifacts.make(
            events: events,
            logPath: "runtime.log",
            timelinePath: "timeline.json",
            launchToCaptureSeconds: 1.08
        )

        #expect(artifacts.eventCount == events.count)
        #expect(artifacts.latestMessage == "Loaded debug scenario: Approval Card.")
        #expect(artifacts.launchCompleted)
        #expect(artifacts.milestones.map(\.name).contains("bridgeSkipped"))
        #expect(artifacts.timings.bootstrapSeconds == 0.070)
        #expect(artifacts.timings.scenarioLoadSeconds == 0.040)
        #expect(artifacts.timings.overlayPresentedSeconds == 0.050)
        #expect(artifacts.timings.captureStartedSeconds == 1.080)
        #expect(artifacts.timings.launchToCaptureSeconds == 1.08)
    }

    @Test
    func launchIsIncompleteWithoutBootstrapCompleted() {
        let artifacts = HarnessRuntimeArtifacts.make(
            events: [
                HarnessRuntimeEvent(
                    category: "milestone",
                    name: "applicationDidFinishLaunching",
                    message: nil,
                    offsetSeconds: 0.001
                ),
                HarnessRuntimeEvent(
                    category: "log",
                    name: "lastActionMessage",
                    message: "Waiting for agent hook events...",
                    offsetSeconds: 0.010
                ),
            ],
            logPath: "runtime.log",
            timelinePath: "timeline.json",
            launchToCaptureSeconds: 1.0
        )

        #expect(!artifacts.launchCompleted)
        #expect(artifacts.timings.bootstrapSeconds == nil)
    }
}
