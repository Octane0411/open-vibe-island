import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphMutationServiceTests: XCTestCase {
    func testCreateIsInactiveDurableAndIdempotent() async throws {
        let context = try MutationContext()

        let first = try await context.service.create(context.createRequest)
        let second = try await context.service.create(context.createRequest)
        let projection = try await context.projection()

        XCTAssertEqual(first.status, .applied)
        XCTAssertEqual(first.streamVersion, 5)
        XCTAssertEqual(second.status, .deduplicated)
        XCTAssertEqual(projection.run?.state, .pending)
        XCTAssertNil(projection.runStartRequestedAt)
        XCTAssertEqual(projection.executableDefinition, context.definition)
    }

    func testCreateRejectsConflictingIdempotencyReuse() async throws {
        let context = try MutationContext()
        _ = try await context.service.create(context.createRequest)
        let other = GraphCreateRequest(
            runID: "other-run",
            definition: context.definition,
            idempotencyKey: "create-key",
            occurredAt: graphTestTime,
            producer: graphTestProducer
        )

        await XCTAssertThrowsErrorAsync(
            try await context.service.create(other)
        ) { error in
            XCTAssertEqual(
                error as? GraphMutationError,
                .idempotencyConflict("create-key")
            )
        }
    }

    func testStartMakesArchitectSchedulableAndIsIdempotent()
        async throws
    {
        let context = try MutationContext()
        _ = try await context.service.create(context.createRequest)
        let request = context.startRequest

        let first = try await context.service.start(request)
        let second = try await context.service.start(request)
        let projection = try await context.projection()
        let reconciled = try XCTUnwrap(
            GraphExecutionProjectionReconciler.reconcile(
                projection: projection,
                evidenceOutcome: .available(GraphProcessEvidence()),
                observedAt: graphTestTime
            )
        )
        let decision = GraphScheduler.evaluate(
            GraphSchedulingInput(
                definition: context.definition.scheduling,
                projectedState: projection,
                reconciledState: reconciled,
                policy: context.definition.schedulerPolicy,
                logicalTime: graphTestTime,
                availableExecutors: [context.executor]
            )
        )

        XCTAssertEqual(first.status, .applied)
        XCTAssertEqual(second.status, .deduplicated)
        XCTAssertEqual(projection.run?.state, .ready)
        XCTAssertEqual(decision.phasesByNodeID["architect"], .claimable)
        XCTAssertEqual(decision.phasesByNodeID["researcher"], .pending)
    }

    func testDryRunWritesNothing() async throws {
        let context = try MutationContext()
        let request = GraphCreateRequest(
            runID: "run",
            definition: context.definition,
            idempotencyKey: "create-key",
            dryRun: true,
            occurredAt: graphTestTime,
            producer: graphTestProducer
        )

        let report = try await context.service.create(request)
        let descriptor = await context.store.streamDescriptor(
            runID: "run"
        )

        XCTAssertEqual(report.status, .proposed)
        XCTAssertEqual(report.eventTypes.count, 5)
        XCTAssertNil(descriptor)
    }

    func testExpectedVersionConflictIsStable() async throws {
        let context = try MutationContext()
        _ = try await context.service.create(context.createRequest)
        let request = GraphStartRequest(
            runID: "run",
            idempotencyKey: "start-key",
            expectedVersion: 4,
            requestedBy: "test",
            occurredAt: graphTestTime,
            producer: graphTestProducer
        )

        await XCTAssertThrowsErrorAsync(
            try await context.service.start(request)
        ) { error in
            XCTAssertEqual(
                error as? GraphMutationError,
                .optimisticConflict(expected: 4, actual: 5)
            )
        }
    }

    func testRetryPolicyAndCancellationRequestsAreDurable()
        async throws
    {
        let context = try MutationContext()
        _ = try await context.service.create(context.createRequest)
        _ = try await context.service.start(context.startRequest)
        try await context.appendFailedArchitect(category: "transient")
        let version = try await context.currentVersion()

        let retry = try await context.service.retry(
            GraphRetryMutationRequest(
                runID: "run",
                nodeID: "architect",
                idempotencyKey: "retry-key",
                expectedVersion: version,
                requestedBy: "test",
                occurredAt: graphTestTime.addingTimeInterval(2),
                producer: graphTestProducer
            )
        )
        let cancel = try await context.service.cancel(
            GraphCancelMutationRequest(
                runID: "run",
                nodeID: "researcher",
                idempotencyKey: "cancel-key",
                requestedBy: "test",
                occurredAt: graphTestTime.addingTimeInterval(3),
                producer: graphTestProducer
            )
        )
        let projection = try await context.projection()

        XCTAssertEqual(retry.status, .applied)
        XCTAssertEqual(cancel.status, .applied)
        XCTAssertEqual(projection.retryRequestIDs.count, 1)
        XCTAssertEqual(
            projection.scheduling.cancellations.map(\.nodeID),
            ["researcher"]
        )
    }
}

private struct MutationContext {
    let store = InMemoryGraphExecutionEventStore()
    let service: DefaultGraphMutationService
    let definition: GraphExecutableDefinition
    let executor = GraphExecutorCapabilities(
        executorID: "deterministic",
        capabilityIdentity: "deterministic-v1",
        capabilities: ["compendium"]
    )

    init() throws {
        definition = try loadCompendiumExecutableDefinition()
        service = DefaultGraphMutationService(
            eventStore: store,
            readStore: store
        )
    }

    var createRequest: GraphCreateRequest {
        GraphCreateRequest(
            runID: "run",
            definition: definition,
            idempotencyKey: "create-key",
            occurredAt: graphTestTime,
            producer: graphTestProducer
        )
    }

    var startRequest: GraphStartRequest {
        GraphStartRequest(
            runID: "run",
            idempotencyKey: "start-key",
            requestedBy: "test",
            occurredAt: graphTestTime,
            producer: graphTestProducer
        )
    }

    func currentVersion() async throws -> UInt64 {
        try await store.read(runID: "run", afterVersion: 0)
            .currentVersion
    }

    func projection() async throws -> GraphExecutionProjection {
        let stream = try await store.read(runID: "run", afterVersion: 0)
        return try GraphExecutionProjector.replay(
            runID: "run",
            events: stream.events
        ).projection
    }

    func appendFailedArchitect(category: String) async throws {
        let version = try await currentVersion()
        let attemptID = "architect-attempt-1"
        let events = [
            GraphExecutionEventEnvelope(
                id: attemptID,
                runID: "run",
                nodeID: "architect",
                attemptID: attemptID,
                streamSequence: version + 1,
                occurredAt: graphTestTime,
                recordedAt: graphTestTime,
                producer: graphTestProducer,
                payload: .attemptCreated(
                    GraphAttemptCreatedPayload(ordinal: 1)
                )
            ),
            GraphExecutionEventEnvelope(
                id: "architect-failed",
                runID: "run",
                nodeID: "architect",
                attemptID: attemptID,
                streamSequence: version + 2,
                occurredAt: graphTestTime.addingTimeInterval(1),
                recordedAt: graphTestTime.addingTimeInterval(1),
                producer: graphTestProducer,
                payload: .attemptFailed(
                    GraphAttemptTerminalPayload(reason: category)
                )
            ),
        ]
        _ = try await store.append(
            events,
            to: "run",
            expectedVersion: version
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw.")
    } catch {
        errorHandler(error)
    }
}
