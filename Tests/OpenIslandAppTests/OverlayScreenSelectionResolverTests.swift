import Testing
@testable import OpenIslandApp

struct OverlayScreenSelectionResolverTests {
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
}
