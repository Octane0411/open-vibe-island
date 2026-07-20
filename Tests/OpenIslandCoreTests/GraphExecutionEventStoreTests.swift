import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphExecutionEventStoreTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 20_000)

    func testEmptyStreamStartsAtVersionZero() async throws {
        let store = InMemoryGraphExecutionEventStore()

        let stream = try await store.read(
            runID: "run",
            afterVersion: 0
        )

        XCTAssertEqual(stream.currentVersion, 0)
        XCTAssertEqual(stream.events, [])
    }

    func testAppendAndOrderedReadUseStreamSequence() async throws {
        let store = InMemoryGraphExecutionEventStore()
        let first = event(id: "one", sequence: 1)
        let second = event(id: "two", sequence: 2)

        let result = try await store.append(
            [second, first],
            to: "run",
            expectedVersion: 0
        )
        let stream = try await store.read(
            runID: "run",
            afterVersion: 0
        )

        XCTAssertEqual(result.newVersion, 2)
        XCTAssertEqual(stream.events.map(\.id), ["one", "two"])
    }

    func testExactDuplicateDeliveryIsIdempotent() async throws {
        let store = InMemoryGraphExecutionEventStore()
        let value = event(id: "one", sequence: 1)
        _ = try await store.append(
            [value],
            to: "run",
            expectedVersion: 0
        )

        let result = try await store.append(
            [value, value],
            to: "run",
            expectedVersion: 0
        )
        let stream = try await store.read(
            runID: "run",
            afterVersion: 0
        )

        XCTAssertEqual(result.appendedCount, 0)
        XCTAssertEqual(result.deduplicatedCount, 2)
        XCTAssertEqual(stream.events, [value])
    }

    func testEventIDReuseWithDifferentContentIsRejected() async throws {
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            [event(id: "same", sequence: 1)],
            to: "run",
            expectedVersion: 0
        )

        await XCTAssertThrowsErrorAsync {
            try await store.append(
                [
                    self.event(
                        id: "same",
                        sequence: 2,
                        payload: .attemptStarting(
                            GraphAttemptStartingPayload()
                        )
                    ),
                ],
                to: "run",
                expectedVersion: 1
            )
        } verify: {
            XCTAssertEqual(
                $0 as? GraphExecutionPersistenceError,
                .eventIDCollision(eventID: "same")
            )
        }
    }

    func testExpectedVersionConflictRejectsConcurrentWriter() async throws {
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            [event(id: "one", sequence: 1)],
            to: "run",
            expectedVersion: 0
        )

        await XCTAssertThrowsErrorAsync {
            try await store.append(
                [self.event(id: "two", sequence: 2)],
                to: "run",
                expectedVersion: 0
            )
        } verify: {
            XCTAssertEqual(
                $0 as? GraphExecutionPersistenceError,
                .expectedVersionConflict(
                    runID: "run",
                    expected: 0,
                    actual: 1
                )
            )
        }
    }

    func testSequenceGapIsRejected() async {
        let store = InMemoryGraphExecutionEventStore()

        await XCTAssertThrowsErrorAsync {
            try await store.append(
                [self.event(id: "two", sequence: 2)],
                to: "run",
                expectedVersion: 0
            )
        } verify: {
            XCTAssertEqual(
                $0 as? GraphExecutionPersistenceError,
                .sequenceGap(expected: 1, actual: 2)
            )
        }
    }

    func testEnvelopeRoundTripPreservesUnknownFutureEvent() throws {
        let original = event(
            id: "future",
            sequence: 1,
            payloadVersion: 9,
            payload: .unknown(
                eventType: "graph.future.quantum_checkpoint",
                body: .object([
                    "partition": .string("alpha"),
                    "writes": .number(3),
                ])
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(
            GraphExecutionEventEnvelope.self,
            from: data
        )

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(
            decoded.eventType,
            "graph.future.quantum_checkpoint"
        )
    }

    private func event(
        id: String,
        sequence: UInt64,
        payloadVersion: Int = 1,
        payload: GraphExecutionEventPayload = .attemptCreated(
            GraphAttemptCreatedPayload(ordinal: 1)
        )
    ) -> GraphExecutionEventEnvelope {
        GraphExecutionEventEnvelope(
            id: id,
            runID: "run",
            nodeID: "node",
            attemptID: "attempt",
            streamSequence: sequence,
            occurredAt: timestamp,
            recordedAt: timestamp.addingTimeInterval(1),
            producer: GraphExecutionProducer(
                id: "test",
                kind: .test
            ),
            correlationID: "correlation",
            causationID: sequence == 1 ? nil : "one",
            telemetryContext: GraphExecutionTelemetryContext(
                traceID: "trace",
                spanID: "span"
            ),
            payloadVersion: payloadVersion,
            payload: payload
        )
    }
}
