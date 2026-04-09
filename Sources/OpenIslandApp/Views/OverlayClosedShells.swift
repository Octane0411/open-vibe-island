import SwiftUI

struct TopBarClosedShell<IconView: View, AttentionView: View, BadgeView: View>: View {
    let hasClosedPresence: Bool
    let hasAttention: Bool
    let closedHeight: CGFloat
    let horizontalPadding: CGFloat
    let spacing: CGFloat
    @ViewBuilder let icon: () -> IconView
    @ViewBuilder let attention: () -> AttentionView
    @ViewBuilder let badge: () -> BadgeView

    var body: some View {
        HStack(spacing: spacing) {
            icon()
            if hasClosedPresence {
                if hasAttention {
                    attention()
                }
                badge()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: closedHeight)
    }
}

struct NotchClosedShell<IconView: View, AttentionView: View, BadgeView: View>: View {
    let hasClosedPresence: Bool
    let hasAttention: Bool
    let liveCount: Int
    let closedNotchWidth: CGFloat
    let closedHeight: CGFloat
    let isPopping: Bool
    @ViewBuilder let icon: () -> IconView
    @ViewBuilder let attention: () -> AttentionView
    @ViewBuilder let badge: () -> BadgeView

    private var sideWidth: CGFloat {
        max(0, closedHeight - 12) + 10
    }

    private var countBadgeWidth: CGFloat {
        let digits = max(1, "\(liveCount)".count)
        return CGFloat(26 + max(0, digits - 1) * 8)
    }

    private var leftLaneWidth: CGFloat {
        sideWidth + 8 + (hasAttention ? 18 : 0)
    }

    private var centerLaneWidth: CGFloat {
        closedNotchWidth - NotchShape.closedTopRadius + (isPopping ? 18 : 0)
    }

    private var rightLaneWidth: CGFloat {
        max(sideWidth, countBadgeWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            if hasClosedPresence {
                HStack(spacing: 4) {
                    icon()
                    if hasAttention {
                        attention()
                    }
                }
                .frame(width: leftLaneWidth)
            }

            if !hasClosedPresence {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: closedNotchWidth - 20)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: centerLaneWidth)
            }

            if hasClosedPresence {
                badge()
                    .frame(width: rightLaneWidth)
            }
        }
        .frame(height: closedHeight)
    }
}
