import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeServerAutoResponseTests {
    @Test
    func updateAutoResponseRulesStoresSnapshot() async throws {
        let server = BridgeServer()
        let rule = AutoResponseRule(
            name: "Allow All",
            ruleType: .permission,
            conditions: RuleConditions(),
            action: .allow
        )

        server.updateAutoResponseRules([rule])
        let stored = server.testingAutoResponseRulesSnapshot()

        #expect(stored == [rule])
    }
}
