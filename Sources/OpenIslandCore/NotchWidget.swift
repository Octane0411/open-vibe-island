import Foundation

public enum NotchWidgetKind: String, Codable, CaseIterable, Sendable {
    case none
    case sessionCount
    case projectChip
    case agentToolIcon
    case dollarSpentToday
}

public struct NotchWidgetConfig: Codable, Equatable, Sendable {
    // Closed notch
    public var closedLeft2: NotchWidgetKind
    public var closedRight1: NotchWidgetKind
    public var closedRight2: NotchWidgetKind
    public var centerSlotExternal: NotchWidgetKind

    // Expanded notch
    public var expandedLeft2: NotchWidgetKind
    public var expandedRight1: NotchWidgetKind
    public var expandedRight2: NotchWidgetKind

    public init(
        closedLeft2: NotchWidgetKind = .none,
        closedRight1: NotchWidgetKind = .sessionCount,
        closedRight2: NotchWidgetKind = .none,
        centerSlotExternal: NotchWidgetKind = .none,
        expandedLeft2: NotchWidgetKind = .none,
        expandedRight1: NotchWidgetKind = .none,
        expandedRight2: NotchWidgetKind = .dollarSpentToday
    ) {
        self.closedLeft2 = closedLeft2
        self.closedRight1 = closedRight1
        self.closedRight2 = closedRight2
        self.centerSlotExternal = centerSlotExternal
        self.expandedLeft2 = expandedLeft2
        self.expandedRight1 = expandedRight1
        self.expandedRight2 = expandedRight2
    }

    public static let `default` = NotchWidgetConfig()

    // Backwards-compat decode: legacy persisted JSON used `rightSlot` instead
    // of `closedRight1`. Map it transparently so users don't lose their pick.
    private enum CodingKeys: String, CodingKey {
        case closedLeft2, closedRight1, closedRight2, centerSlotExternal
        case expandedLeft2, expandedRight1, expandedRight2
        case rightSlot   // legacy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyRight = try c.decodeIfPresent(NotchWidgetKind.self, forKey: .rightSlot)
        self.closedLeft2 = try c.decodeIfPresent(NotchWidgetKind.self, forKey: .closedLeft2) ?? .none
        self.closedRight1 = try c.decodeIfPresent(NotchWidgetKind.self, forKey: .closedRight1)
            ?? legacyRight
            ?? .sessionCount
        self.closedRight2 = try c.decodeIfPresent(NotchWidgetKind.self, forKey: .closedRight2) ?? .none
        self.centerSlotExternal = try c.decodeIfPresent(NotchWidgetKind.self, forKey: .centerSlotExternal) ?? .none
        self.expandedLeft2 = try c.decodeIfPresent(NotchWidgetKind.self, forKey: .expandedLeft2) ?? .none
        self.expandedRight1 = try c.decodeIfPresent(NotchWidgetKind.self, forKey: .expandedRight1) ?? .none
        self.expandedRight2 = try c.decodeIfPresent(NotchWidgetKind.self, forKey: .expandedRight2) ?? .dollarSpentToday
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(closedLeft2, forKey: .closedLeft2)
        try c.encode(closedRight1, forKey: .closedRight1)
        try c.encode(closedRight2, forKey: .closedRight2)
        try c.encode(centerSlotExternal, forKey: .centerSlotExternal)
        try c.encode(expandedLeft2, forKey: .expandedLeft2)
        try c.encode(expandedRight1, forKey: .expandedRight1)
        try c.encode(expandedRight2, forKey: .expandedRight2)
    }
}
