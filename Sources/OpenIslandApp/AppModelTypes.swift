import AppKit
import CoreGraphics
import Foundation

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason: Equatable {
    case click
    case hover
    case notification
    case boot
}

enum TrackedEventIngress {
    case bridge
    case rollout
}

enum IslandClosedDisplayStyle: String, CaseIterable, Identifiable {
    case minimal
    case detailed

    var id: String { rawValue }
}

enum IslandClosedHeaderLayout {
    static func sideWidth(notchHeight: CGFloat) -> CGFloat {
        max(0, notchHeight - 16)
    }

    static func leftLaneWidth(notchHeight: CGFloat, hasAttention: Bool) -> CGFloat {
        sideWidth(notchHeight: notchHeight) + (hasAttention ? 18 : 0)
    }

    static func badgeWidth(
        indicatorCount: Int,
        displayStyle: IslandClosedDisplayStyle,
        countLabel: String?
    ) -> CGFloat {
        let numberWidth = measuredTextWidth(
            "\(indicatorCount)",
            font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        )
        let baseWidth = numberWidth + 4
        guard displayStyle == .detailed else {
            return baseWidth
        }

        let detailLabelWidth = measuredTextWidth(
            countLabel ?? "",
            font: NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        )
        return baseWidth + detailLabelWidth + 4
    }

    static func edgeLaneWidth(
        notchHeight: CGFloat,
        indicatorCount: Int,
        hasAttention: Bool,
        displayStyle: IslandClosedDisplayStyle,
        countLabel: String?
    ) -> CGFloat {
        max(
            leadingContentWidth(
                notchHeight: notchHeight,
                hasAttention: hasAttention,
                displayStyle: displayStyle,
                detailText: nil
            ),
            trailingBadgeWidth(
                notchHeight: notchHeight,
                indicatorCount: indicatorCount,
                displayStyle: displayStyle,
                countLabel: countLabel
            )
        )
    }

    static func detailTextWidth(_ text: String?, displayStyle: IslandClosedDisplayStyle) -> CGFloat {
        guard displayStyle == .detailed, let text, !text.isEmpty else {
            return 0
        }

        return min(56, measuredTextWidth(text, font: NSFont.systemFont(ofSize: 10.5, weight: .semibold)))
    }

    static func leadingContentWidth(
        notchHeight: CGFloat,
        hasAttention: Bool,
        displayStyle: IslandClosedDisplayStyle,
        detailText: String?
    ) -> CGFloat {
        let iconClusterWidth = leftLaneWidth(notchHeight: notchHeight, hasAttention: hasAttention)
        let detailWidth = detailTextWidth(detailText, displayStyle: displayStyle)
        guard detailWidth > 0 else {
            return iconClusterWidth
        }

        return iconClusterWidth + 5 + detailWidth
    }

    static func trailingBadgeWidth(
        notchHeight: CGFloat,
        indicatorCount: Int,
        displayStyle: IslandClosedDisplayStyle,
        countLabel: String?
    ) -> CGFloat {
        max(
            sideWidth(notchHeight: notchHeight),
            badgeWidth(
                indicatorCount: indicatorCount,
                displayStyle: displayStyle,
                countLabel: countLabel
            )
        )
    }

    static func horizontalPadding(displayStyle: IslandClosedDisplayStyle) -> CGFloat {
        displayStyle == .detailed ? 18 : 18
    }

    static func centerSpacing(displayStyle: IslandClosedDisplayStyle) -> CGFloat {
        displayStyle == .detailed ? 45 : 25
    }

    static func expansionWidth(
        notchHeight: CGFloat,
        indicatorCount: Int,
        hasAttention: Bool,
        displayStyle: IslandClosedDisplayStyle,
        detailText: String?,
        countLabel: String?
    ) -> CGFloat {
        let leadingWidth = leadingContentWidth(
            notchHeight: notchHeight,
            hasAttention: hasAttention,
            displayStyle: displayStyle,
            detailText: detailText
        )
        let trailingWidth = trailingBadgeWidth(
            notchHeight: notchHeight,
            indicatorCount: indicatorCount,
            displayStyle: displayStyle,
            countLabel: countLabel
        )
        return leadingWidth + trailingWidth + centerSpacing(displayStyle: displayStyle) + (horizontalPadding(displayStyle: displayStyle) * 2)
    }

    private static func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else {
            return 0
        }

        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
