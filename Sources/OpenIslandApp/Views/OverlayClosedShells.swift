import SwiftUI

extension OverlayClosedShellMetrics {
    enum LayoutFamily: Equatable {
        case notch
        case floatingPill
    }

    var layoutFamily: LayoutFamily {
        isFloatingPill ? .floatingPill : .notch
    }
}

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
    let sideWidth: CGFloat
    let closedNotchWidth: CGFloat
    let closedHeight: CGFloat
    let countBadgeWidth: CGFloat
    let isPopping: Bool
    @ViewBuilder let icon: () -> IconView
    @ViewBuilder let attention: () -> AttentionView
    @ViewBuilder let badge: () -> BadgeView

    var body: some View {
        HStack(spacing: 0) {
            if hasClosedPresence {
                HStack(spacing: 4) {
                    icon()
                    if hasAttention {
                        attention()
                    }
                }
                .frame(width: sideWidth + 8 + (hasAttention ? 18 : 0))
            }

            if !hasClosedPresence {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: closedNotchWidth - 20)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: closedNotchWidth - NotchShape.closedTopRadius + (isPopping ? 18 : 0))
            }

            if hasClosedPresence {
                badge()
                    .frame(width: max(sideWidth, countBadgeWidth))
            }
        }
        .frame(height: closedHeight)
    }
}
