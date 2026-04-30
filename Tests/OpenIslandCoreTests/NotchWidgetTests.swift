import Foundation
import Testing
@testable import OpenIslandCore

struct NotchWidgetTests {
    @Test
    func defaultConfigPreservesLegacyBehavior() {
        let config = NotchWidgetConfig.default
        #expect(config.rightSlot == .sessionCount)
        #expect(config.centerSlotExternal == .none)
    }

    @Test
    func configRoundTripsThroughJSON() throws {
        let original = NotchWidgetConfig(rightSlot: .projectChip, centerSlotExternal: .dollarSpentToday)
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
}
