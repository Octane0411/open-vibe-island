import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphExecutionReplayTests: XCTestCase {
    func testNormalReplayBuildsRunNodeAttemptAndArtifact() throws {
        let artifact = GraphArtifactReference(
            id: "artifact",
            contentDigest: GraphContentDigest(
                algorithm: "sha256",
                value: "artifact-digest"
            ),
            mediaType: "application/json",
            logicalRole: "result",
            producingRunID: "run",
            producingNodeID: "node",
            producingAttemptID: "attempt",
            createdAt: graphTestTime.addingTimeInterval(6),
            storage: GraphArtifactStorageLocator(
                scheme: "openisland-artifact",
                opaqueReference: "artifact"
            ),
            sensitivity: .internalUse
        )
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestAttemptStarting(),
            graphTestProcessObserved(),
            graphTestEvent(
                id: "event-6",
                sequence: 6,
                nodeID: "node",
                attemptID: "attempt",
                payload: .artifactRecorded(
                    GraphArtifactRecordedPayload(artifact: artifact)
                )
            ),
            graphTestEvent(
                id: "event-7",
                sequence: 7,
                nodeID: "node",
                attemptID: "attempt",
                payload: .attemptCompleted(
                    GraphAttemptTerminalPayload(
                        artifactIDs: ["artifact"]
                    )
                )
            ),
        ]

        let result = try GraphExecutionProjector.replay(
            runID: "run",
            events: events.reversed()
        )

        XCTAssertEqual(result.projection.streamVersion, 7)
        XCTAssertEqual(result.projection.run?.graphID, "graph")
        XCTAssertEqual(result.projection.nodes[0].state, .completed)
        XCTAssertEqual(result.projection.attempts[0].state, .completed)
        XCTAssertEqual(result.projection.artifacts, [artifact])
        XCTAssertEqual(result.replayedEventCount, 7)
    }

    func testExactDuplicateReplayIsIdempotent() throws {
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestNodeRegistered(),
        ]

        let result = try GraphExecutionProjector.replay(
            runID: "run",
            events: events
        )

        XCTAssertEqual(result.projection.streamVersion, 2)
        XCTAssertEqual(result.projection.nodes.count, 1)
        XCTAssertEqual(result.duplicateEventCount, 1)
    }

    func testAttemptOrdinalRegressionIsRejected() throws {
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestAttemptCreated(
                sequence: 4,
                attemptID: "retry",
                ordinal: 1
            ),
        ]

        XCTAssertThrowsError(
            try GraphExecutionProjector.replay(
                runID: "run",
                events: events
            )
        ) {
            XCTAssertEqual(
                $0 as? GraphExecutionReplayError,
                .attemptOrdinalRegression(
                    nodeID: "node",
                    previous: 1,
                    proposed: 1
                )
            )
        }
    }

    func testProcessIdentityChangeIsRejected() throws {
        let changed = ProcessIdentity(
            hostID: "test-host",
            launchID: "different-launch",
            processID: 43,
            startedAt: graphTestTime.addingTimeInterval(5)
        )
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestProcessObserved(sequence: 4),
            graphTestProcessObserved(
                sequence: 5,
                process: changed
            ),
        ]

        XCTAssertThrowsError(
            try GraphExecutionProjector.replay(
                runID: "run",
                events: events
            )
        ) {
            XCTAssertEqual(
                $0 as? GraphExecutionReplayError,
                .processIdentityChanged(attemptID: "attempt")
            )
        }
    }

    func testTerminalAttemptCannotRegress() throws {
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestEvent(
                id: "event-4",
                sequence: 4,
                nodeID: "node",
                attemptID: "attempt",
                payload: .attemptCompleted(
                    GraphAttemptTerminalPayload()
                )
            ),
            graphTestAttemptStarting(sequence: 5),
        ]

        XCTAssertThrowsError(
            try GraphExecutionProjector.replay(
                runID: "run",
                events: events
            )
        ) {
            XCTAssertEqual(
                $0 as? GraphExecutionReplayError,
                .terminalAttemptRegression(attemptID: "attempt")
            )
        }
    }

    func testUnknownFutureEventIsRetainedAndAdvancesVersion() throws {
        let future = graphTestEvent(
            id: "future",
            sequence: 2,
            payloadVersion: 99,
            payload: .unknown(
                eventType: "graph.future.event",
                body: .object(["value": .string("preserved")])
            )
        )

        let result = try GraphExecutionProjector.replay(
            runID: "run",
            events: [graphTestRunCreated(), future]
        )

        XCTAssertEqual(result.projection.streamVersion, 2)
        XCTAssertEqual(result.projection.unknownEvents, [future])
        XCTAssertEqual(
            result.diagnostics.map(\.category),
            [.unknownEvent]
        )
    }

    func testSequenceGapIsRejectedByProjector() {
        XCTAssertThrowsError(
            try GraphExecutionProjector.replay(
                runID: "run",
                events: [
                    graphTestRunCreated(),
                    graphTestNodeRegistered(sequence: 3),
                ]
            )
        ) {
            XCTAssertEqual(
                $0 as? GraphExecutionReplayError,
                .sequenceGap(expected: 2, actual: 3)
            )
        }
    }
}
