import Testing
@testable import OpenIslandApp

@Suite
struct UpdateCheckerTests {
    @Test
    func devBundleSkipsAutomaticSparkleUpdates() {
        #expect(UpdateChecker.shouldSkipAutomaticUpdates(bundleIdentifier: "app.openisland.dev"))
        #expect(UpdateChecker.shouldSkipAutomaticUpdates(bundleIdentifier: "app.openisland.dev.local"))
    }

    @Test
    func releaseBundleAllowsAutomaticSparkleUpdates() {
        #expect(!UpdateChecker.shouldSkipAutomaticUpdates(bundleIdentifier: "app.openisland"))
        #expect(!UpdateChecker.shouldSkipAutomaticUpdates(bundleIdentifier: nil))
    }
}
