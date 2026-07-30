import Foundation
import Testing
@testable import OpenIslandApp

struct CodexUsagePresentationTests {
    @Test
    func codexHeaderSelectsHighestUsageWindowButDisplaysRemainingPercentage() {
        let provider = UsageProviderPresentation(
            id: "codex",
            title: "Codex",
            windows: [
                UsageWindowPresentation(
                    id: "codex-5h",
                    label: "5h",
                    displayPercentage: 100,
                    severityPercentage: 0,
                    resetsAt: nil
                ),
                UsageWindowPresentation(
                    id: "codex-7d",
                    label: "7d",
                    displayPercentage: 75,
                    severityPercentage: 25,
                    resetsAt: nil
                ),
            ]
        )

        #expect(provider.peakWindowLabel == "7d")
        #expect(provider.peakUsedPercentage == 25)
        #expect(provider.peakUsagePercentage == 75)
    }
}
