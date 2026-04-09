struct OverlayScreenSelectionCandidate: Equatable {
    let id: String
    let isNotched: Bool
    let isMain: Bool
}

struct OverlayScreenSelection: Equatable {
    let screenID: String
    let selectionSummary: String
}

enum OverlayScreenSelectionResolver {
    static func resolve(
        preferredScreenID: String?,
        screens: [OverlayScreenSelectionCandidate]
    ) -> OverlayScreenSelection? {
        guard !screens.isEmpty else {
            return nil
        }

        if let preferredScreenID,
           screens.contains(where: { $0.id == preferredScreenID }) {
            return OverlayScreenSelection(
                screenID: preferredScreenID,
                selectionSummary: "manual"
            )
        }

        if preferredScreenID != nil {
            if let notchScreen = screens.first(where: \.isNotched) {
                return OverlayScreenSelection(
                    screenID: notchScreen.id,
                    selectionSummary: "manual missing, auto fallback"
                )
            }

            if let mainScreen = screens.first(where: \.isMain) {
                return OverlayScreenSelection(
                    screenID: mainScreen.id,
                    selectionSummary: "manual missing, main fallback"
                )
            }

            return OverlayScreenSelection(
                screenID: screens[0].id,
                selectionSummary: "manual missing, first-display fallback"
            )
        }

        if let notchScreen = screens.first(where: \.isNotched) {
            return OverlayScreenSelection(
                screenID: notchScreen.id,
                selectionSummary: "automatic"
            )
        }

        if let mainScreen = screens.first(where: \.isMain) {
            return OverlayScreenSelection(
                screenID: mainScreen.id,
                selectionSummary: "automatic"
            )
        }

        return OverlayScreenSelection(
            screenID: screens[0].id,
            selectionSummary: "automatic"
        )
    }
}
