import Testing
@testable import OpenIslandApp

struct OverlayScreenSelectionResolverTests {
    @Test
    func automaticPolicyUsesIslandOnNotchedScreen() {
        let mode = OverlayPresentationPolicy.automaticIslandWhenNotched
            .resolvePresentationMode(screenCapability: .notched)

        #expect(mode == .island)
    }

    @Test
    func automaticPolicyUsesPillOnPlainScreen() {
        let mode = OverlayPresentationPolicy.automaticIslandWhenNotched
            .resolvePresentationMode(screenCapability: .plain)

        #expect(mode == .pill)
    }

    @Test
    func alwaysIslandForcesIslandOnPlainScreen() {
        let mode = OverlayPresentationPolicy.alwaysIsland
            .resolvePresentationMode(screenCapability: .plain)

        #expect(mode == .island)
    }

    @Test
    func alwaysPillForcesPillOnNotchedScreen() {
        let mode = OverlayPresentationPolicy.alwaysPill
            .resolvePresentationMode(screenCapability: .notched)

        #expect(mode == .pill)
    }

    @Test
    func automaticPrefersNotchedScreenOverMainDisplay() {
        let resolved = OverlayScreenSelectionResolver.resolve(
            preferredScreenID: nil,
            screens: [
                OverlayScreenSelectionCandidate(
                    id: "display-external",
                    isNotched: false,
                    isMain: true
                ),
                OverlayScreenSelectionCandidate(
                    id: "display-built-in",
                    isNotched: true,
                    isMain: false
                )
            ]
        )

        #expect(resolved?.screenID == "display-built-in")
        #expect(resolved?.selectionSummary == "automatic")
    }

    @Test
    func missingManualSelectionFallsBackToNotchedScreen() {
        let resolved = OverlayScreenSelectionResolver.resolve(
            preferredScreenID: "display-missing",
            screens: [
                OverlayScreenSelectionCandidate(
                    id: "display-external",
                    isNotched: false,
                    isMain: true
                ),
                OverlayScreenSelectionCandidate(
                    id: "display-built-in",
                    isNotched: true,
                    isMain: false
                )
            ]
        )

        #expect(resolved?.screenID == "display-built-in")
        #expect(resolved?.selectionSummary == "manual missing, auto fallback")
    }

    @Test
    func missingManualSelectionFallsBackToMainDisplayWhenNoNotchedScreen() {
        let resolved = OverlayScreenSelectionResolver.resolve(
            preferredScreenID: "display-missing",
            screens: [
                OverlayScreenSelectionCandidate(
                    id: "display-external",
                    isNotched: false,
                    isMain: true
                ),
                OverlayScreenSelectionCandidate(
                    id: "display-sidecar",
                    isNotched: false,
                    isMain: false
                )
            ]
        )

        #expect(resolved?.screenID == "display-external")
        #expect(resolved?.selectionSummary == "manual missing, main fallback")
    }
}
