import CoreGraphics

enum IslandChromeMetrics {
    static let closeTransitionDuration: Double = 0.3
    static let openedShadowHorizontalInset: CGFloat = 18
    static let openedShadowBottomInset: CGFloat = 22
    static let closedShadowHorizontalInset: CGFloat = 12
    static let closedShadowBottomInset: CGFloat = 14
    static let closedHoverScale: CGFloat = 1.028

    static func panelShadowInsets(
        usesOpenedVisualState: Bool
    ) -> (horizontal: CGFloat, bottom: CGFloat) {
        if usesOpenedVisualState {
            return (
                horizontal: openedShadowHorizontalInset,
                bottom: openedShadowBottomInset
            )
        }

        return (
            horizontal: closedShadowHorizontalInset,
            bottom: closedShadowBottomInset
        )
    }
}
