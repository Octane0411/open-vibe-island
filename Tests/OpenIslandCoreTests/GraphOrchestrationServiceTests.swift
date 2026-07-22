import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphOrchestrationServiceTests: XCTestCase {
    func testCompendiumRunsAllFourNodesAndPropagatesArtifacts()
        async throws
    {
        let context = try await OrchestrationContext.make()

        let result = try await context.service.run(
            GraphOrchestrationRunRequest(
                runID: "run",
                cycleLimit: 30,
                logicalTime: graphTestTime
            )
        )
        let projection = try await context.projection()

        XCTAssertEqual(result.status, .terminal)
        XCTAssertEqual(result.finalState, .completed)
        XCTAssertEqual(
            projection.attempts.map { "\($0.nodeID):\($0.state.rawValue)" },
            [
                "architect:completed",
                "graph:completed",
                "researcher:completed",
                "reviewer:completed",
            ]
        )
        XCTAssertEqual(projection.artifacts.count, 5)
        let reviewerInputs = try GraphArtifactInputResolver.resolve(
            nodeID: "reviewer",
            definition: context.definition,
            projection: projection
        )
        XCTAssertEqual(
            Set(reviewerInputs.map(\.producingNodeID)),
            Set(["architect", "researcher", "graph"])
        )
        XCTAssertTrue(
            projection.scheduling.claims.allSatisfy {
                $0.status == .released
            }
        )
    }

    func testRepeatedRunDoesNotDuplicateTerminalWork() async throws {
        let context = try await OrchestrationContext.make()
        _ = try await context.service.run(
            GraphOrchestrationRunRequest(
                runID: "run",
                cycleLimit: 30,
                logicalTime: graphTestTime
            )
        )
        let version = try await context.currentVersion()

        let repeated = try await context.service.run(
            GraphOrchestrationRunRequest(
                runID: "run",
                cycleLimit: 30,
                logicalTime: graphTestTime
            )
        )

        XCTAssertEqual(repeated.cycles.count, 1)
        XCTAssertEqual(repeated.cycles[0].persistedEventCount, 0)
        XCTAssertEqual(repeated.finalVersion, version)
    }

    func testStepIsBoundedAndDryRunHasNoWritesOrInvocations()
        async throws
    {
        let context = try await OrchestrationContext.make()
        let initialVersion = try await context.currentVersion()
        let dryRun = try await context.service.step(
            GraphOrchestrationStepRequest(
                runID: "run",
                logicalTime: graphTestTime,
                dryRun: true
            )
        )
        let afterDryRun = try await context.currentVersion()
        let step = try await context.service.step(
            GraphOrchestrationStepRequest(
                runID: "run",
                logicalTime: graphTestTime
            )
        )
        let projection = try await context.projection()

        XCTAssertEqual(dryRun.status, .proposed)
        XCTAssertEqual(dryRun.claimedNodeID, "architect")
        XCTAssertEqual(dryRun.executorInvocationCount, 0)
        XCTAssertEqual(initialVersion, afterDryRun)
        XCTAssertEqual(step.claimedNodeID, "architect")
        XCTAssertEqual(step.executorOperation, .start)
        XCTAssertEqual(step.executorInvocationCount, 2)
        XCTAssertEqual(projection.attempts.count, 1)
        XCTAssertEqual(projection.attempts.first?.state, .running)
    }

    func testRetryDelaySurvivesServiceRestart() async throws {
        let script = GraphDeterministicExecutionScript(
            attempts: [
                GraphDeterministicAttemptScript(
                    nodeID: "researcher",
                    attemptOrdinal: 1,
                    terminalOutcome: .retryableFailure,
                    failureCategory: "transient"
                ),
                GraphDeterministicAttemptScript(
                    nodeID: "researcher",
                    attemptOrdinal: 2,
                    terminalOutcome: .succeed,
                    artifactRoles: [.structuredResult]
                ),
            ]
        )
        let context = try await OrchestrationContext.make(script: script)
        let first = try await context.service.run(
            GraphOrchestrationRunRequest(
                runID: "run",
                cycleLimit: 30,
                logicalTime: graphTestTime
            )
        )
        let waiting = try await context.projection()
        let retry = try XCTUnwrap(
            waiting.scheduling.retries.first {
                $0.nodeID == "researcher"
            }
        )
        let restarted = context.makeService(script: script)
        let completed = try await restarted.run(
            GraphOrchestrationRunRequest(
                runID: "run",
                cycleLimit: 30,
                logicalTime: retry.eligibleAt
            )
        )
        let projection = try await context.projection()

        XCTAssertEqual(first.status, .stalled)
        XCTAssertEqual(retry.delaySeconds, 10)
        XCTAssertEqual(completed.finalState, .completed)
        XCTAssertEqual(
            projection.attempts.filter {
                $0.nodeID == "researcher"
            }.map(\.ordinal),
            [1, 2]
        )
    }

    func testNonRetryableFailureBlocksDownstreamAndFailsRun()
        async throws
    {
        let script = GraphDeterministicExecutionScript(
            attempts: [
                GraphDeterministicAttemptScript(
                    nodeID: "researcher",
                    attemptOrdinal: 1,
                    terminalOutcome: .nonRetryableFailure,
                    failureCategory: "invalid_input"
                ),
            ]
        )
        let context = try await OrchestrationContext.make(script: script)

        let result = try await context.service.run(
            GraphOrchestrationRunRequest(
                runID: "run",
                cycleLimit: 30,
                logicalTime: graphTestTime
            )
        )
        let projection = try await context.projection()
        let reconciled = try XCTUnwrap(
            GraphExecutionProjectionReconciler.reconcile(
                projection: projection,
                evidenceOutcome: .available(GraphProcessEvidence()),
                observedAt: graphTestTime
            )
        )

        XCTAssertEqual(result.finalState, .failed)
        XCTAssertEqual(
            reconciled.nodes.first { $0.id == "graph" }?.state,
            .blocked
        )
        XCTAssertEqual(
            reconciled.nodes.first { $0.id == "reviewer" }?.state,
            .blocked
        )
        XCTAssertTrue(
            projection.scheduling.records.contains {
                $0.eventType == GraphExecutionEventType
                    .retrySuppressed.rawValue
            }
        )
    }

    func testCancellationBeforeClaimDoesNotInvokeExecutor()
        async throws
    {
        let context = try await OrchestrationContext.make()
        _ = try await context.mutator.cancel(
            GraphCancelMutationRequest(
                runID: "run",
                nodeID: "architect",
                idempotencyKey: "cancel-before-claim",
                requestedBy: "test",
                occurredAt: graphTestTime,
                producer: graphTestProducer
            )
        )

        let cycle = try await context.service.step(
            GraphOrchestrationStepRequest(
                runID: "run",
                logicalTime: graphTestTime
            )
        )
        let projection = try await context.projection()

        XCTAssertEqual(cycle.executorInvocationCount, 0)
        XCTAssertEqual(
            projection.attempts.first?.state,
            .cancelled
        )
        XCTAssertTrue(projection.scheduling.claims.isEmpty)
    }

    func testCancellationAcknowledgementAndTimeoutAreDurable()
        async throws
    {
        let acknowledge = try await OrchestrationContext.make()
        _ = try await acknowledge.service.step(
            GraphOrchestrationStepRequest(
                runID: "run",
                logicalTime: graphTestTime
            )
        )
        _ = try await acknowledge.mutator.cancel(
            GraphCancelMutationRequest(
                runID: "run",
                nodeID: "architect",
                idempotencyKey: "cancel-running",
                requestedBy: "test",
                occurredAt: graphTestTime.addingTimeInterval(1),
                producer: graphTestProducer
            )
        )
        let cancelled = try await acknowledge.service.step(
            GraphOrchestrationStepRequest(
                runID: "run",
                logicalTime: graphTestTime.addingTimeInterval(1)
            )
        )
        let cancelledProjection = try await acknowledge.projection()

        XCTAssertEqual(cancelled.executorStatus, .cancelled)
        XCTAssertEqual(
            cancelledProjection.attempts.first?.state,
            .cancelled
        )
        XCTAssertEqual(
            cancelledProjection.scheduling.cancellations.first?.state,
            .acknowledged
        )

        let ignoreScript = GraphDeterministicExecutionScript(
            attempts: [
                GraphDeterministicAttemptScript(
                    nodeID: "architect",
                    attemptOrdinal: 1,
                    cancellationBehavior: .ignoreUntilTimeout
                ),
            ]
        )
        let ignore = try await OrchestrationContext.make(
            runID: "ignore",
            script: ignoreScript
        )
        _ = try await ignore.service.step(
            GraphOrchestrationStepRequest(
                runID: "ignore",
                logicalTime: graphTestTime
            )
        )
        _ = try await ignore.mutator.cancel(
            GraphCancelMutationRequest(
                runID: "ignore",
                nodeID: "architect",
                idempotencyKey: "cancel-ignore",
                requestedBy: "test",
                occurredAt: graphTestTime.addingTimeInterval(1),
                producer: graphTestProducer
            )
        )
        let waiting = try await ignore.service.step(
            GraphOrchestrationStepRequest(
                runID: "ignore",
                logicalTime: graphTestTime.addingTimeInterval(1)
            )
        )
        _ = try await ignore.service.step(
            GraphOrchestrationStepRequest(
                runID: "ignore",
                logicalTime: graphTestTime.addingTimeInterval(31)
            )
        )
        let timedOut = try await ignore.projection(runID: "ignore")

        XCTAssertEqual(waiting.status, .waitingForCancellation)
        XCTAssertTrue(
            timedOut.scheduling.timeouts.contains {
                $0.kind == .cancellationAcknowledgement
            }
        )
        XCTAssertEqual(timedOut.attempts.first?.state, .interrupted)
    }

    func testCrashAfterStartRequestRecoversWithoutDuplicateStart()
        async throws
    {
        let script = GraphDeterministicExecutionScript(
            attempts: [
                GraphDeterministicAttemptScript(
                    nodeID: "architect",
                    attemptOrdinal: 1,
                    crashPoint: .afterAttemptStartPersistence
                ),
            ]
        )
        let context = try await OrchestrationContext.make(script: script)
        let crashed = try await context.service.step(
            GraphOrchestrationStepRequest(
                runID: "run",
                logicalTime: graphTestTime
            )
        )
        let restarted = context.makeService(script: script)
        let recovered = try await restarted.step(
            GraphOrchestrationStepRequest(
                runID: "run",
                logicalTime: graphTestTime.addingTimeInterval(1)
            )
        )
        let stream = try await context.store.read(
            runID: "run",
            afterVersion: 0
        )

        XCTAssertEqual(crashed.status, .adapterUnavailable)
        XCTAssertEqual(recovered.executorOperation, .recover)
        XCTAssertEqual(
            stream.events.filter {
                $0.eventType == GraphExecutionEventType
                    .attemptStarting.rawValue
            }.count,
            1
        )
    }

    func testCrashAfterAdapterAcceptanceRecoversConservatively()
        async throws
    {
        let script = GraphDeterministicExecutionScript(
            attempts: [
                GraphDeterministicAttemptScript(
                    nodeID: "architect",
                    attemptOrdinal: 1,
                    crashPoint: .afterAcceptingStart
                ),
            ]
        )
        let context = try await OrchestrationContext.make(script: script)

        let accepted = try await context.service.step(
            GraphOrchestrationStepRequest(
                runID: "run",
                logicalTime: graphTestTime
            )
        )
        let restarted = context.makeService(script: script)
        let recovered = try await restarted.step(
            GraphOrchestrationStepRequest(
                runID: "run",
                logicalTime: graphTestTime.addingTimeInterval(1)
            )
        )
        let completed = try await restarted.run(
            GraphOrchestrationRunRequest(
                runID: "run",
                cycleLimit: 30,
                logicalTime: graphTestTime.addingTimeInterval(2)
            )
        )
        let stream = try await context.store.read(
            runID: "run",
            afterVersion: 0
        )

        XCTAssertEqual(accepted.executorStatus, .accepted)
        XCTAssertEqual(recovered.executorOperation, .recover)
        XCTAssertEqual(completed.finalState, .completed)
        XCTAssertEqual(
            stream.events.filter {
                $0.eventType == GraphExecutionEventType
                    .attemptStarting.rawValue
                    && $0.nodeID == "architect"
            }.count,
            1
        )
    }

    func testStaleExecutorObservationIsRejectedWithoutArtifacts()
        async throws
    {
        let script = GraphDeterministicExecutionScript(
            attempts: [
                GraphDeterministicAttemptScript(
                    nodeID: "architect",
                    attemptOrdinal: 1,
                    staleLeaseGenerationOffset: -1
                ),
            ]
        )
        let context = try await OrchestrationContext.make(script: script)

        await XCTAssertThrowsErrorAsync {
            try await context.service.step(
                GraphOrchestrationStepRequest(
                    runID: "run",
                    logicalTime: graphTestTime
                )
            )
        } verify: { error in
            XCTAssertEqual(
                error as? GraphOrchestrationError,
                .staleExecutor(.leaseGenerationMismatch)
            )
        }
        let projection = try await context.projection()

        XCTAssertTrue(projection.artifacts.isEmpty)
        XCTAssertTrue(
            projection.attempts.allSatisfy { !$0.state.isTerminal }
        )
    }

    func testStepRejectsOptimisticConcurrencyConflict() async throws {
        let context = try await OrchestrationContext.make()
        let version = try await context.currentVersion()

        await XCTAssertThrowsErrorAsync {
            try await context.service.step(
                GraphOrchestrationStepRequest(
                    runID: "run",
                    logicalTime: graphTestTime,
                    expectedVersion: version - 1
                )
            )
        } verify: { error in
            XCTAssertEqual(
                error as? GraphOrchestrationError,
                .optimisticConflict(
                    expected: version - 1,
                    actual: version
                )
            )
        }
    }

    func testLongRunningAttemptRenewsLeaseWithNextFencingGeneration()
        async throws
    {
        let script = GraphDeterministicExecutionScript(
            attempts: [
                GraphDeterministicAttemptScript(
                    nodeID: "architect",
                    attemptOrdinal: 1,
                    terminalOutcome: .remainRunning
                ),
            ]
        )
        let context = try await OrchestrationContext.make(script: script)
        _ = try await context.service.step(
            GraphOrchestrationStepRequest(
                runID: "run",
                logicalTime: graphTestTime
            )
        )

        let renewed = try await context.service.step(
            GraphOrchestrationStepRequest(
                runID: "run",
                logicalTime: graphTestTime.addingTimeInterval(31)
            )
        )
        let projection = try await context.projection()
        let claim = try XCTUnwrap(
            projection.scheduling.activeClaim(
                nodeID: "architect",
                at: graphTestTime.addingTimeInterval(31)
            )
        )

        XCTAssertEqual(renewed.executorOperation, .observe)
        XCTAssertEqual(renewed.executorStatus, .stillRunning)
        XCTAssertEqual(claim.leaseGeneration, 2)
        XCTAssertTrue(
            projection.scheduling.records.contains {
                $0.eventType == GraphExecutionEventType
                    .executorLeaseRenewed.rawValue
            }
        )
    }

    func testSQLiteProcessRestartResumesSameGraphWithoutDuplicateStart()
        async throws
    {
        let fixture = try SQLiteStoreFixture()
        defer { fixture.remove() }
        let definition = try loadCompendiumExecutableDefinition()
        let script = try loadCompendiumDeterministicScript()
        let firstStore = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        let mutator = DefaultGraphMutationService(
            eventStore: firstStore,
            readStore: firstStore
        )
        _ = try await mutator.create(
            GraphCreateRequest(
                runID: "sqlite-run",
                definition: definition,
                idempotencyKey: "sqlite-create",
                occurredAt: graphTestTime,
                producer: graphTestProducer
            )
        )
        _ = try await mutator.start(
            GraphStartRequest(
                runID: "sqlite-run",
                idempotencyKey: "sqlite-start",
                requestedBy: "test",
                occurredAt: graphTestTime,
                producer: graphTestProducer
            )
        )
        let firstService = makeOrchestrationService(
            store: firstStore,
            script: script
        )
        _ = try await firstService.step(
            GraphOrchestrationStepRequest(
                runID: "sqlite-run",
                logicalTime: graphTestTime
            )
        )

        let reopenedStore = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        let restartedService = makeOrchestrationService(
            store: reopenedStore,
            script: script
        )
        let completed = try await restartedService.run(
            GraphOrchestrationRunRequest(
                runID: "sqlite-run",
                cycleLimit: 30,
                logicalTime: graphTestTime.addingTimeInterval(1)
            )
        )
        let stream = try await reopenedStore.read(
            runID: "sqlite-run",
            afterVersion: 0
        )

        XCTAssertEqual(completed.finalState, .completed)
        XCTAssertEqual(
            stream.events.filter {
                $0.eventType == GraphExecutionEventType
                    .attemptStarting.rawValue
                    && $0.nodeID == "architect"
            }.count,
            1
        )
    }

    func testSuccessfulExecutionReplaysByteIdenticallyAndDiffExplainsRun()
        async throws
    {
        let context = try await OrchestrationContext.make()
        let initialStream = try await context.store.read(
            runID: "run",
            afterVersion: 0
        )
        let initialBoundary = try XCTUnwrap(
            initialStream.events.last?.streamSequence
        )
        _ = try await context.service.run(
            GraphOrchestrationRunRequest(
                runID: "run",
                cycleLimit: 30,
                logicalTime: graphTestTime
            )
        )
        let terminalStream = try await context.store.read(
            runID: "run",
            afterVersion: 0
        )
        let first = try GraphExecutionProjector.replay(
            runID: "run",
            events: terminalStream.events
        ).projection
        let second = try GraphExecutionProjector.replay(
            runID: "run",
            events: terminalStream.events
        ).projection
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let firstBytes = try encoder.encode(first)
        let secondBytes = try encoder.encode(second)
        let inspector = DefaultGraphTemporalInspector(
            readStore: context.store,
            snapshotStore: InMemoryGraphExecutionSnapshotStore()
        )
        let diff = try await inspector.diff(
            left: GraphTemporalReference(
                runID: "run",
                boundary: .sequence(initialBoundary)
            ),
            right: GraphTemporalReference(runID: "run")
        )
        let completedNodes = Set(
            diff.changes.filter {
                $0.category == .node
                    && $0.field == "persisted_state"
                    && $0.right == ReconciledExecutionState.completed.rawValue
            }.map(\.entityID)
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(firstBytes, secondBytes)
        XCTAssertEqual(
            completedNodes,
            Set(["architect", "researcher", "graph", "reviewer"])
        )
        XCTAssertTrue(
            diff.changes.contains {
                $0.category == .run
                    && $0.field == "persisted_state"
                    && $0.right == ReconciledExecutionState.completed.rawValue
            }
        )
        XCTAssertTrue(
            diff.changes.contains { $0.category == .artifact }
        )
        XCTAssertTrue(
            diff.changes.contains { $0.category == .eventRange }
        )
    }
}

private struct OrchestrationContext {
    let runID: String
    let store: InMemoryGraphExecutionEventStore
    let definition: GraphExecutableDefinition
    let mutator: DefaultGraphMutationService
    let service: DefaultGraphOrchestrationService

    static func make(
        runID: String = "run",
        script: GraphDeterministicExecutionScript? = nil
    ) async throws -> OrchestrationContext {
        let store = InMemoryGraphExecutionEventStore()
        let definition = try loadCompendiumExecutableDefinition()
        let mutator = DefaultGraphMutationService(
            eventStore: store,
            readStore: store
        )
        _ = try await mutator.create(
            GraphCreateRequest(
                runID: runID,
                definition: definition,
                idempotencyKey: "create-\(runID)",
                occurredAt: graphTestTime,
                producer: graphTestProducer
            )
        )
        _ = try await mutator.start(
            GraphStartRequest(
                runID: runID,
                idempotencyKey: "start-\(runID)",
                requestedBy: "test",
                occurredAt: graphTestTime,
                producer: graphTestProducer
            )
        )
        let selectedScript = try script
            ?? loadCompendiumDeterministicScript()
        let context = OrchestrationContext(
            runID: runID,
            store: store,
            definition: definition,
            mutator: mutator,
            service: makeService(
                store: store,
                script: selectedScript
            )
        )
        return context
    }

    func makeService(
        script: GraphDeterministicExecutionScript
    ) -> DefaultGraphOrchestrationService {
        Self.makeService(store: store, script: script)
    }

    func currentVersion() async throws -> UInt64 {
        try await store.read(runID: runID, afterVersion: 0)
            .currentVersion
    }

    func projection(
        runID: String? = nil
    ) async throws -> GraphExecutionProjection {
        let selectedRunID = runID ?? self.runID
        let stream = try await store.read(
            runID: selectedRunID,
            afterVersion: 0
        )
        return try GraphExecutionProjector.replay(
            runID: selectedRunID,
            events: stream.events
        ).projection
    }

    private static func makeService(
        store: InMemoryGraphExecutionEventStore,
        script: GraphDeterministicExecutionScript
    ) -> DefaultGraphOrchestrationService {
        makeOrchestrationService(store: store, script: script)
    }
}

private func makeOrchestrationService(
    store: any GraphExecutionEventStore,
    script: GraphDeterministicExecutionScript
) -> DefaultGraphOrchestrationService {
    DefaultGraphOrchestrationService(
        eventStore: store,
        schedulingRepository: DefaultGraphSchedulingRepository(
            eventStore: store
        ),
        executorRepository: DefaultGraphExecutorRepository(
            eventStore: store
        ),
        executor: DeterministicGraphExecutor(script: script),
        producer: graphTestProducer
    )
}
