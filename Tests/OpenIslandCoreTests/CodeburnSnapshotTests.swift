import Foundation
import Testing
@testable import OpenIslandCore

struct CodeburnSnapshotTests {
    @Test
    func parsesValidStatusJSON() throws {
        let json = """
        { "today": { "cost": 3.42, "currency": "USD" },
          "month": { "cost": 87.10, "currency": "USD" } }
        """.data(using: .utf8)!

        let snapshot = try CodeburnSnapshot.parse(statusJSON: json)
        #expect(snapshot.todayCost == 3.42)
        #expect(snapshot.currency == "USD")
    }

    @Test
    func missingTodayCostThrows() {
        let json = "{}".data(using: .utf8)!
        #expect(throws: CodeburnSnapshot.ParseError.self) {
            _ = try CodeburnSnapshot.parse(statusJSON: json)
        }
    }

    @Test
    func malformedJSONThrows() {
        let json = "not json".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try CodeburnSnapshot.parse(statusJSON: json)
        }
    }
}
