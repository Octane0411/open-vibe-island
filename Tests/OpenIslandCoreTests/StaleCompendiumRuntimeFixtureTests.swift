import Foundation
import XCTest
@testable import OpenIslandCore

final class StaleCompendiumRuntimeFixtureTests: XCTestCase {
    func testStaleCompendiumRunReconcilesWithoutLiveProcessClaims() throws {
        let input = try loadStaleCompendiumFixture()

        let result = GraphExecutionReconciler.reconcile(input)
        let attemptStates = Dictionary(
            uniqueKeysWithValues: result.attempts.map {
                ($0.id, $0.state)
            }
        )
        let nodeStates = Dictionary(
            uniqueKeysWithValues: result.nodes.map {
                ($0.id, $0.state)
            }
        )

        XCTAssertEqual(
            attemptStates["architect-attempt-1"],
            .interrupted
        )
        XCTAssertEqual(
            attemptStates["researcher-attempt-1"],
            .orphaned
        )
        XCTAssertEqual(nodeStates["architect"], .interrupted)
        XCTAssertEqual(nodeStates["researcher"], .orphaned)
        XCTAssertEqual(nodeStates["graph"], .blocked)
        XCTAssertEqual(nodeStates["reviewer"], .blocked)
        XCTAssertEqual(result.run.state, .interrupted)
        XCTAssertFalse(result.nodes.contains { $0.state == .running })
    }
}
