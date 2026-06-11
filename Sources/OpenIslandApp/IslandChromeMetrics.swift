import CoreGraphics

enum IslandChromeMetrics {
    static let openedShadowHorizontalInset: CGFloat = 18
    static let openedShadowBottomInset: CGFloat = 22
    static let closedShadowHorizontalInset: CGFloat = 12
    static let closedShadowBottomInset: CGFloat = 14
    static let closedHoverScale: CGFloat = 1.028
    static let closedNotchedHorizontalReserve: CGFloat = 88
    static let closedNotchedReserveScale: CGFloat = 0.8

    static func closedNotchedWidth(physicalNotchWidth: CGFloat) -> CGFloat {
        physicalNotchWidth + (closedNotchedHorizontalReserve * closedNotchedReserveScale)
    }
}
