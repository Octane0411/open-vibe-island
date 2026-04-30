import Foundation

public enum NotchWidgetKind: String, Codable, CaseIterable, Sendable {
    case none
    case sessionCount
    case projectChip
    case agentToolIcon
    case dollarSpentToday
}

public struct NotchWidgetConfig: Codable, Equatable, Sendable {
    public var rightSlot: NotchWidgetKind
    public var centerSlotExternal: NotchWidgetKind

    public init(rightSlot: NotchWidgetKind, centerSlotExternal: NotchWidgetKind) {
        self.rightSlot = rightSlot
        self.centerSlotExternal = centerSlotExternal
    }

    public static let `default` = NotchWidgetConfig(
        rightSlot: .sessionCount,
        centerSlotExternal: .none
    )
}
