import CoreGraphics

/// Legacy chrome constants, retained purely as the Classic drift pin.
///
/// AB-320 routed the last production call sites (`IslandPanelView`'s content
/// padding and hover scale) through the active theme's `IslandMetricsTokens`,
/// so nothing in the app reads these any more. `IslandThemeTokensTests` still
/// compares `IslandThemeTokens.classic.metrics` against them, which is the
/// point: they are the record of what "no visual change" means.
enum IslandChromeMetrics {
    static let openedShadowHorizontalInset: CGFloat = 18
    static let openedShadowBottomInset: CGFloat = 22
    static let closedShadowHorizontalInset: CGFloat = 12
    static let closedShadowBottomInset: CGFloat = 14
    static let closedHoverScale: CGFloat = 1.028
}
