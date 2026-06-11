import Testing
@testable import OpenIslandApp

struct NotchHeaderUsageLayoutTests {
    @Test
    func unavailableRightLaneKeepsAllUsageProvidersVisibleOnLeft() {
        let distribution = NotchHeaderUsageLayout.distribution(
            providerCount: 2,
            rightUsageWidth: 0
        )

        #expect(distribution == NotchHeaderUsageDistribution(leftCount: 2, rightCount: 0))
    }

    @Test
    func availableRightLaneSplitsTwoProvidersAcrossBothSides() {
        let distribution = NotchHeaderUsageLayout.distribution(
            providerCount: 2,
            rightUsageWidth: 80
        )

        #expect(distribution == NotchHeaderUsageDistribution(leftCount: 1, rightCount: 1))
    }
}
