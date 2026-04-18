/// Plain-value description of a single attached display, used as input to
/// `OverlayScreenSelectionResolver`. It intentionally avoids `NSScreen`
/// so the resolver stays pure and unit-testable.
struct OverlayScreenSelectionCandidate: Equatable {
    /// Stable identifier produced by `OverlayScreenIdentity.id(for:)`.
    let id: String
    /// Whether the screen advertises a physical notch (i.e. is a built-in
    /// MacBook display whose `safeAreaInsets.top > 0`).
    let isNotched: Bool
    /// Whether this display is the current main / primary display.
    let isMain: Bool
}

/// Result of resolving a display for the overlay to attach to.
///
/// - `screenID`: identifier of the chosen display.
/// - `selectionSummary`: human-readable path tag used for diagnostics and
///   log correlation. One of: `"manual"`, `"manual missing, auto
///   fallback"`, `"manual missing, main fallback"`, `"manual missing,
///   first-display fallback"`, `"automatic"`.
struct OverlayScreenSelection: Equatable {
    let screenID: String
    let selectionSummary: String
}

/// Pure policy for picking which attached display should host the
/// overlay. Given a user preference and the current set of screens, it
/// returns the resolved display plus a tag describing which branch was
/// taken. Having this as a value-only resolver lets
/// `OverlayUICoordinator` reason about selection without instantiating
/// screen mocks, and keeps the fallback behavior covered by unit tests.
///
/// Decision order:
/// 1. If the user has a `preferredScreenID` and it matches an attached
///    display → return it verbatim (`"manual"`).
/// 2. If the user has a preference but it is missing → fall back to the
///    first notched screen, then to the main display, then to the first
///    attached display, tagging each path distinctly so drops can be
///    detected from logs.
/// 3. If there is no preference → prefer the notched screen, then the
///    main display, then the first attached display — all tagged as
///    `"automatic"`.
///
/// An empty `screens` array short-circuits to `nil` so callers do not
/// accidentally index into it.
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
