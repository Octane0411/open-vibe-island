import Foundation
import Testing
@testable import OpenIslandCore

struct NotchWidgetTests {
    @Test
    func defaultConfigPreservesLegacyBehavior() {
        let config = NotchWidgetConfig.default
        #expect(config.closedRight1 == .sessionCount)
        #expect(config.centerSlotExternal == .none)
        #expect(config.expandedRight2 == .dollarSpentToday)
    }

    @Test
    func configRoundTripsThroughJSON() throws {
        let original = NotchWidgetConfig(
            closedLeft2: .agentToolIcon,
            closedRight1: .projectChip,
            closedRight2: .none,
            centerSlotExternal: .dollarSpentToday,
            expandedLeft2: .none,
            expandedRight1: .agentToolIcon,
            expandedRight2: .dollarSpentToday
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotchWidgetConfig.self, from: encoded)
        #expect(decoded == original)
    }

    @Test
    func widgetKindHasStableRawValues() {
        #expect(NotchWidgetKind.none.rawValue == "none")
        #expect(NotchWidgetKind.sessionCount.rawValue == "sessionCount")
        #expect(NotchWidgetKind.projectChip.rawValue == "projectChip")
        #expect(NotchWidgetKind.agentToolIcon.rawValue == "agentToolIcon")
        #expect(NotchWidgetKind.dollarSpentToday.rawValue == "dollarSpentToday")
    }

    @Test
    func decodesLegacyRightSlotKey() throws {
        // Old persisted shape from before the slot expansion.
        let legacy = #"{"rightSlot":"projectChip","centerSlotExternal":"none"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NotchWidgetConfig.self, from: legacy)
        #expect(decoded.closedRight1 == .projectChip)
        #expect(decoded.closedLeft2 == .none)
        #expect(decoded.closedRight2 == .none)
        #expect(decoded.centerSlotExternal == .none)
        #expect(decoded.expandedLeft2 == .none)
        #expect(decoded.expandedRight1 == .none)
        #expect(decoded.expandedRight2 == .dollarSpentToday)
    }
}
