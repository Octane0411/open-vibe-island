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
    func alwaysPillUsesTopBarPlacementModeOnNotchedScreen() {
        let mode = OverlayPresentationPolicy.alwaysPill
            .resolvePlacementMode(screenCapability: .notched)

        #expect(mode == .topBar)
    }

    @Test
    func alwaysIslandUsesNotchPlacementModeOnPlainScreen() {
        let mode = OverlayPresentationPolicy.alwaysIsland
            .resolvePlacementMode(screenCapability: .plain)

        #expect(mode == .notch)
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

    @Test
    func emptyScreenArrayReturnsNil() {
        let resolved = OverlayScreenSelectionResolver.resolve(
            preferredScreenID: nil,
            screens: []
        )

        #expect(resolved == nil)
    }

    @Test
    func emptyScreenArrayWithManualPreferenceReturnsNil() {
        // Even when a manual preference is set, an empty screen list must
        // return nil rather than crashing on `screens[0]`.
        let resolved = OverlayScreenSelectionResolver.resolve(
            preferredScreenID: "display-missing",
            screens: []
        )

        #expect(resolved == nil)
    }

    @Test
    func missingManualFallsBackToFirstDisplayWhenNoNotchedAndNoMain() {
        // Covers the "manual missing, first-display fallback" branch — a
        // degenerate case where no screen claims `isMain` (e.g. during a
        // transient display reconfiguration). The resolver must still
        // return a valid screen rather than nil.
        let resolved = OverlayScreenSelectionResolver.resolve(
            preferredScreenID: "display-missing",
            screens: [
                OverlayScreenSelectionCandidate(
                    id: "display-a",
                    isNotched: false,
                    isMain: false
                ),
                OverlayScreenSelectionCandidate(
                    id: "display-b",
                    isNotched: false,
                    isMain: false
                )
            ]
        )

        #expect(resolved?.screenID == "display-a")
        #expect(resolved?.selectionSummary == "manual missing, first-display fallback")
    }

    @Test
    func automaticFallsBackToMainDisplayWhenNoNotchedScreen() {
        // Covers the `automatic` branch that prefers the main display when
        // no notched screen is available.
        let resolved = OverlayScreenSelectionResolver.resolve(
            preferredScreenID: nil,
            screens: [
                OverlayScreenSelectionCandidate(
                    id: "display-sidecar",
                    isNotched: false,
                    isMain: false
                ),
                OverlayScreenSelectionCandidate(
                    id: "display-external",
                    isNotched: false,
                    isMain: true
                )
            ]
        )

        #expect(resolved?.screenID == "display-external")
        #expect(resolved?.selectionSummary == "automatic")
    }

    @Test
    func automaticFallsBackToFirstDisplayWhenNoNotchedAndNoMain() {
        // Covers the final `automatic` fallback path that returns the first
        // candidate when no screen is notched and none claim `isMain`.
        let resolved = OverlayScreenSelectionResolver.resolve(
            preferredScreenID: nil,
            screens: [
                OverlayScreenSelectionCandidate(
                    id: "display-a",
                    isNotched: false,
                    isMain: false
                ),
                OverlayScreenSelectionCandidate(
                    id: "display-b",
                    isNotched: false,
                    isMain: false
                )
            ]
        )

        #expect(resolved?.screenID == "display-a")
        #expect(resolved?.selectionSummary == "automatic")
    }
}
