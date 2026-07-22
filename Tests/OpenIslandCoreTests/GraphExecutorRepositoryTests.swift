import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphExecutorRepositoryTests: XCTestCase {
    func testFencedStartObservationArtifactAndTerminalDeclaration()
        async throws
    {
        let context = try await ExecutorRepositoryContext.make()
        let started = try await context.repository.recordStartRequest(
            context.startCommand()
        )
        let observation = context.observation(
            status: .succeeded,
            operation: .collectResult,
            observedAt: context.time.addingTimeInterval(1),
            artifacts: [context.outputArtifact]
        )
        let observed = try await context.repository.recordObservation(
            GraphExecutorObservationCommand(
                observation: observation,
                expectedVersion: started.appendResult.newVersion,
                producer: graphTestProducer,
                correlationID: "execute"
            )
        )
        let terminal = try await context.repository.declareTerminal(
            GraphExecutorTerminalDeclaration(
                identity: context.identity,
                observationID: observation.id,
                state: .completed,
                expectedVersion: observed.appendResult.newVersion,
                logicalTime: context.time.addingTimeInterval(2),
                producer: graphTestProducer,
                correlationID: "execute"
            )
        )

        XCTAssertEqual(terminal.projection.run?.state, .ready)
        XCTAssertEqual(
            terminal.projection.attempts.first?.state,
            .completed
        )
        XCTAssertEqual(terminal.projection.artifacts.count, 1)
        XCTAssertEqual(
            terminal.projection.artifacts.first?.producingClaimID,
            context.identity.claimID
        )
        XCTAssertEqual(
            terminal.projection.scheduling.claims.first?.status,
            .released
        )
    }

    func testCompletionBeforeDurableStartIsRejected() async throws {
        let context = try await ExecutorRepositoryContext.make()
        let observation = context.observation(
            status: .succeeded,
            operation: .collectResult,
            observedAt: context.time.addingTimeInterval(1)
        )
        let observed = try await context.repository.recordObservation(
            GraphExecutorObservationCommand(
                observation: observation,
                expectedVersion: context.version,
                producer: graphTestProducer,
                correlationID: "execute"
            )
        )

        await assertExecutorError(.completionBeforeStart) {
            try await context.repository.declareTerminal(
                GraphExecutorTerminalDeclaration(
                    identity: context.identity,
                    observationID: observation.id,
                    state: .completed,
                    expectedVersion: observed.appendResult.newVersion,
                    logicalTime: context.time.addingTimeInterval(2),
                    producer: graphTestProducer,
                    correlationID: "execute"
                )
            )
        }
    }

    func testDuplicateObservationIsIdempotent() async throws {
        let context = try await ExecutorRepositoryContext.make()
        let started = try await context.repository.recordStartRequest(
            context.startCommand()
        )
        let observation = context.observation(
            status: .stillRunning,
            operation: .observe,
            observedAt: context.time.addingTimeInterval(1)
        )
        let command = GraphExecutorObservationCommand(
            observation: observation,
            expectedVersion: started.appendResult.newVersion,
            producer: graphTestProducer,
            correlationID: "execute"
        )
        let first = try await context.repository.recordObservation(command)
        let duplicate = try await context.repository.recordObservation(
            GraphExecutorObservationCommand(
                observation: observation,
                expectedVersion: first.appendResult.newVersion,
                producer: graphTestProducer,
                correlationID: "execute"
            )
        )

        XCTAssertEqual(first.appendResult.appendedCount, 1)
        XCTAssertEqual(duplicate.appendResult.appendedCount, 0)
        XCTAssertEqual(duplicate.appendResult.deduplicatedCount, 1)
    }

    func testWrongLeaseGenerationAndExecutorAreRejected()
        async throws
    {
        let context = try await ExecutorRepositoryContext.make()
        let wrongGeneration = context.identity(
            generation: context.identity.leaseGeneration + 1
        )
        let wrongExecutor = context.identity(executorID: "other")

        await assertExecutorError(.leaseGenerationMismatch) {
            try await context.repository.recordStartRequest(
                context.startCommand(identity: wrongGeneration)
            )
        }
        await assertExecutorError(.executorMismatch) {
            try await context.repository.recordStartRequest(
                context.startCommand(identity: wrongExecutor)
            )
        }
    }

    func testAcceptedProcessIdentityBecomesAuthoritativeHistory() async throws {
        let context = try await ExecutorRepositoryContext.make()
        let started = try await context.repository.recordStartRequest(
            context.startCommand()
        )
        let process = ProcessIdentity(
            hostID: "test-host",
            launchID: "durable-launch",
            processID: 812,
            startedAt: context.time
        )
        let observation = context.observation(
            status: .started,
            operation: .start,
            observedAt: context.time.addingTimeInterval(1),
            processIdentity: process
        )
        let recorded = try await context.repository.recordObservation(
            GraphExecutorObservationCommand(
                observation: observation,
                expectedVersion: started.appendResult.newVersion,
                producer: graphTestProducer,
                correlationID: "execute"
            )
        )

        XCTAssertEqual(recorded.appendResult.appendedCount, 2)
        XCTAssertEqual(
            recorded.projection.attempts.first?.processIdentity,
            process
        )
        let stream = try await context.store.read(
            runID: "run",
            afterVersion: 0
        )
        XCTAssertTrue(stream.events.contains {
            $0.eventType == GraphExecutionEventType
                .processIdentityObserved.rawValue
        })
    }

    func testStaleClaimCannotPublishAfterLeaseTakeover() async throws {
        let context = try await ExecutorRepositoryContext.make(
            leaseDuration: 5
        )
        let takeoverTime = context.time.addingTimeInterval(6)
        let replacement = try await context.takeOver(at: takeoverTime)
        let staleObservation = context.observation(
            status: .succeeded,
            operation: .collectResult,
            observedAt: takeoverTime
        )

        await assertExecutorError(.claimInactive) {
            try await context.repository.recordObservation(
                GraphExecutorObservationCommand(
                    observation: staleObservation,
                    expectedVersion: replacement.version,
                    producer: graphTestProducer,
                    correlationID: "stale"
                )
            )
        }
        XCTAssertNotEqual(replacement.claim.id, context.identity.claimID)
    }
}

private struct ExecutorRepositoryContext {
    let store: InMemoryGraphExecutionEventStore
    let schedulingRepository: DefaultGraphSchedulingRepository
    let repository: DefaultGraphExecutorRepository
    let definition: GraphExecutableDefinition
    let executor: GraphExecutorCapabilities
    let identity: GraphExecutorInteractionIdentity
    let version: UInt64
    let time: Date
    let leaseDuration: UInt64

    static func make(
        leaseDuration: UInt64 = 60
    ) async throws -> ExecutorRepositoryContext {
        let store = InMemoryGraphExecutionEventStore()
        let definition = try loadCompendiumExecutableDefinition()
        let mutator = DefaultGraphMutationService(
            eventStore: store,
            readStore: store
        )
        _ = try await mutator.create(
            GraphCreateRequest(
                runID: "run",
                definition: definition,
                idempotencyKey: "create",
                occurredAt: graphTestTime,
                producer: graphTestProducer
            )
        )
        _ = try await mutator.start(
            GraphStartRequest(
                runID: "run",
                idempotencyKey: "start",
                requestedBy: "test",
                occurredAt: graphTestTime,
                producer: graphTestProducer
            )
        )
        let scheduling = DefaultGraphSchedulingRepository(
            eventStore: store
        )
        let executor = GraphExecutorCapabilities(
            executorID: "deterministic",
            capabilityIdentity: "deterministic-v1",
            capabilities: ["compendium"]
        )
        let evaluated = try await scheduling.evaluateAndAppend(
            GraphSchedulerEvaluationRequest(
                runID: "run",
                expectedVersion: 6,
                definition: definition.scheduling,
                policy: definition.schedulerPolicy,
                logicalTime: graphTestTime,
                availableExecutors: [executor],
                producer: graphTestProducer,
                recordedAt: graphTestTime
            )
        )
        let evaluationID = try XCTUnwrap(
            evaluated.projection.scheduling.records.last(where: {
                $0.eventType == GraphExecutionEventType
                    .schedulerCycleCompleted.rawValue
            })?.evaluationID
        )
        let claimed = try await scheduling.attemptClaim(
            GraphExecutorClaimRequest(
                runID: "run",
                nodeID: "architect",
                claimID: "claim-1",
                executor: executor,
                evaluationID: evaluationID,
                expectedVersion: evaluated.appendResult.newVersion,
                logicalTime: graphTestTime,
                leaseDurationSeconds: leaseDuration,
                producer: graphTestProducer,
                recordedAt: graphTestTime
            )
        )
        let claim = try XCTUnwrap(claimed.claim)
        let projection = try await Self.projection(store)
        let attempt = try XCTUnwrap(
            projection.attempts.first { $0.nodeID == "architect" }
        )
        return ExecutorRepositoryContext(
            store: store,
            schedulingRepository: scheduling,
            repository: DefaultGraphExecutorRepository(
                eventStore: store
            ),
            definition: definition,
            executor: executor,
            identity: GraphExecutorInteractionIdentity(
                runID: "run",
                nodeID: "architect",
                attemptID: attempt.id,
                attemptOrdinal: attempt.ordinal,
                claimID: claim.id,
                leaseGeneration: claim.leaseGeneration,
                executorID: claim.executorID
            ),
            version: claimed.appendResult.newVersion,
            time: graphTestTime,
            leaseDuration: leaseDuration
        )
    }

    var outputArtifact: GraphExecutorProducedArtifact {
        GraphExecutorProducedArtifact(
            contentDigest: GraphContentDigest(
                algorithm: "sha256",
                value: "artifact-digest"
            ),
            mediaType: "application/json",
            role: .nodeOutput,
            storage: GraphArtifactStorageLocator(
                scheme: "deterministic",
                opaqueReference: "artifact-digest"
            )
        )
    }

    func identity(
        generation: UInt64? = nil,
        executorID: String? = nil
    ) -> GraphExecutorInteractionIdentity {
        GraphExecutorInteractionIdentity(
            runID: identity.runID,
            nodeID: identity.nodeID,
            attemptID: identity.attemptID,
            attemptOrdinal: identity.attemptOrdinal,
            claimID: identity.claimID,
            leaseGeneration: generation ?? identity.leaseGeneration,
            executorID: executorID ?? identity.executorID
        )
    }

    func startCommand(
        identity: GraphExecutorInteractionIdentity? = nil
    ) -> GraphExecutorStartCommand {
        GraphExecutorStartCommand(
            identity: identity ?? self.identity,
            expectedVersion: version,
            logicalTime: time,
            producer: graphTestProducer,
            correlationID: "execute"
        )
    }

    func observation(
        status: GraphExecutorResponseStatus,
        operation: GraphExecutorOperation,
        observedAt: Date,
        processIdentity: ProcessIdentity? = nil,
        artifacts: [GraphExecutorProducedArtifact] = []
    ) -> GraphExecutorObservation {
        GraphExecutorObservation(
            id: "observation-\(operation.rawValue)-\(status.rawValue)",
            operation: operation,
            identity: identity,
            status: status,
            observedAt: observedAt,
            processIdentity: processIdentity,
            artifacts: artifacts
        )
    }

    func takeOver(
        at logicalTime: Date
    ) async throws -> (claim: GraphExecutorClaim, version: UInt64) {
        let projected = try await Self.projection(store)
        let evaluated = try await schedulingRepository.evaluateAndAppend(
            GraphSchedulerEvaluationRequest(
                runID: "run",
                expectedVersion: projected.streamVersion,
                definition: definition.scheduling,
                policy: definition.schedulerPolicy,
                logicalTime: logicalTime,
                availableExecutors: [executor],
                producer: graphTestProducer,
                recordedAt: logicalTime
            )
        )
        let evaluationID = try XCTUnwrap(
            evaluated.projection.scheduling.records.last(where: {
                $0.eventType == GraphExecutionEventType
                    .schedulerCycleCompleted.rawValue
            })?.evaluationID
        )
        let result = try await schedulingRepository.attemptClaim(
            GraphExecutorClaimRequest(
                runID: "run",
                nodeID: "architect",
                claimID: "claim-2",
                executor: executor,
                evaluationID: evaluationID,
                expectedVersion: evaluated.appendResult.newVersion,
                logicalTime: logicalTime,
                leaseDurationSeconds: leaseDuration,
                producer: graphTestProducer,
                recordedAt: logicalTime
            )
        )
        return (try XCTUnwrap(result.claim), result.appendResult.newVersion)
    }

    private static func projection(
        _ store: InMemoryGraphExecutionEventStore
    ) async throws -> GraphExecutionProjection {
        let stream = try await store.read(runID: "run", afterVersion: 0)
        return try GraphExecutionProjector.replay(
            runID: "run",
            events: stream.events
        ).projection
    }
}

private func assertExecutorError<T>(
    _ expected: GraphExecutorFencingReason,
    operation: () async throws -> T
) async {
    do {
        _ = try await operation()
        XCTFail("Expected executor fencing rejection.")
    } catch let error as GraphExecutorRepositoryError {
        guard case let .rejected(reason, _) = error else {
            return XCTFail("Expected rejection, found \(error).")
        }
        XCTAssertEqual(reason, expected)
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
}
