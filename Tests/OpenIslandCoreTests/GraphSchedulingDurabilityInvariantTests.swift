import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphSchedulingDurabilityInvariantTests: XCTestCase {
    func testCompendiumFixtureAdvancesExactlyOneRunnableNodeAtATime()
        async throws
    {
        let definition = try loadCompendiumSchedulingDefinition()
        let store = InMemoryGraphExecutionEventStore()
        let runID = "compendium-success"
        let time = Date(timeIntervalSince1970: 400_000)
        let base = compendiumSchedulingBaseEvents(
            definition: definition,
            runID: runID,
            occurredAt: time
        )
        _ = try await store.append(base, to: runID, expectedVersion: 0)
        let repository = DefaultGraphSchedulingRepository(eventStore: store)
        let executors = compendiumExecutorCapabilities()
        let nodeOrder = ["architect", "researcher", "graph", "reviewer"]
        var version = UInt64(base.count)

        for (index, nodeID) in nodeOrder.enumerated() {
            let logicalTime = time.addingTimeInterval(Double(index * 10))
            let evaluationExpectedVersion = version
            let evaluation = try await repository.evaluateAndAppend(
                evaluationRequest(
                    runID: runID,
                    expectedVersion: evaluationExpectedVersion,
                    definition: definition,
                    logicalTime: logicalTime,
                    executors: executors
                )
            )
            version = evaluation.appendResult.newVersion
            XCTAssertEqual(
                runnableNodeIDs(evaluation.projection),
                [nodeID]
            )
            for blockedNodeID in nodeOrder.dropFirst(index + 1) {
                XCTAssertFalse(
                    runnableNodeIDs(evaluation.projection)
                        .contains(blockedNodeID)
                )
            }

            let duplicate = try await repository.evaluateAndAppend(
                evaluationRequest(
                    runID: runID,
                    expectedVersion: evaluationExpectedVersion,
                    definition: definition,
                    logicalTime: logicalTime,
                    executors: executors
                )
            )
            XCTAssertEqual(duplicate.appendResult.appendedCount, 0)

            let evaluationID = try latestEvaluationID(
                evaluation.projection
            )
            let executor = try XCTUnwrap(
                executors.first {
                    $0.satisfies(
                        definition.nodes.first { $0.id == nodeID }!
                            .requiredCapabilities
                    )
                }
            )
            let claimed = try await repository.attemptClaim(
                GraphExecutorClaimRequest(
                    runID: runID,
                    nodeID: nodeID,
                    claimID: "claim-\(nodeID)",
                    executor: executor,
                    evaluationID: evaluationID,
                    expectedVersion: version,
                    logicalTime: logicalTime,
                    leaseDurationSeconds: 60,
                    producer: graphTestProducer,
                    recordedAt: logicalTime
                )
            )
            version = claimed.appendResult.newVersion
            let claimedProjection = try await projection(
                store,
                runID: runID
            )
            let attempt = try XCTUnwrap(
                claimedProjection.attempts.first { $0.nodeID == nodeID }
            )
            let completion = try await appendAttemptTerminal(
                store: store,
                runID: runID,
                nodeID: nodeID,
                attemptID: attempt.id,
                expectedVersion: version,
                time: logicalTime.addingTimeInterval(1),
                payload: .attemptCompleted(
                    GraphAttemptTerminalPayload(reason: "fixture complete")
                )
            )
            version = completion.newVersion
            let claim = try XCTUnwrap(claimed.claim)
            let released = try await repository.releaseClaim(
                GraphExecutorClaimReleaseRequest(
                    runID: runID,
                    claimID: claim.id,
                    executorID: claim.executorID,
                    expectedGeneration: claim.leaseGeneration,
                    expectedVersion: version,
                    logicalTime: logicalTime.addingTimeInterval(2),
                    producer: graphTestProducer,
                    recordedAt: logicalTime.addingTimeInterval(2)
                )
            )
            version = released.appendResult.newVersion
        }

        let projected = try await projection(store, runID: runID)
        let reconciled = try XCTUnwrap(
            GraphExecutionProjectionReconciler.reconcile(
                projection: projected,
                evidenceOutcome: .available(GraphProcessEvidence()),
                observedAt: time.addingTimeInterval(100)
            )
        )
        XCTAssertEqual(reconciled.run.state, .completed)
        XCTAssertTrue(reconciled.nodes.allSatisfy { $0.state == .completed })
        XCTAssertEqual(
            projected.scheduling.claims.map(\.status),
            [.released, .released, .released, .released]
        )
    }

    func testRetryExhaustionAndCancellationBlockDownstreamFixedPoint()
        async throws
    {
        let definition = try loadCompendiumSchedulingDefinition()
        let time = Date(timeIntervalSince1970: 410_000)
        let failure = try await makeCompendiumContext(
            runID: "compendium-failure",
            definition: definition,
            time: time
        )
        let evaluation = try await failure.repository.evaluateAndAppend(
            evaluationRequest(
                runID: failure.runID,
                expectedVersion: failure.version,
                definition: definition,
                logicalTime: time,
                executors: failure.executors,
                maximumAttempts: 1
            )
        )
        let architect = try XCTUnwrap(
            failure.executors.first { $0.executorID == "architect-worker" }
        )
        let claimed = try await failure.repository.attemptClaim(
            GraphExecutorClaimRequest(
                runID: failure.runID,
                nodeID: "architect",
                claimID: "failed-architect-claim",
                executor: architect,
                evaluationID: try latestEvaluationID(evaluation.projection),
                expectedVersion: evaluation.appendResult.newVersion,
                logicalTime: time,
                leaseDurationSeconds: 60,
                producer: graphTestProducer,
                recordedAt: time
            )
        )
        let claimedProjection = try await projection(
            failure.store,
            runID: failure.runID
        )
        let failedAttempt = try XCTUnwrap(claimedProjection.attempts.first)
        let terminal = try await appendAttemptTerminal(
            store: failure.store,
            runID: failure.runID,
            nodeID: "architect",
            attemptID: failedAttempt.id,
            expectedVersion: claimed.appendResult.newVersion,
            time: time.addingTimeInterval(1),
            payload: .attemptFailed(
                GraphAttemptTerminalPayload(reason: "non-retryable")
            )
        )
        let exhausted = try await failure.repository.evaluateAndAppend(
            evaluationRequest(
                runID: failure.runID,
                expectedVersion: terminal.newVersion,
                definition: definition,
                logicalTime: time.addingTimeInterval(2),
                executors: failure.executors,
                maximumAttempts: 1,
                failures: [failedAttempt.id: "transient"]
            )
        )
        XCTAssertTrue(exhausted.projection.scheduling.retries.isEmpty)
        XCTAssertEqual(
            exhausted.projection.scheduling.records.filter {
                $0.eventType
                    == GraphExecutionEventType
                        .dependencyFailurePropagated.rawValue
            }.count,
            3
        )
        XCTAssertTrue(
            exhausted.projection.scheduling.records.contains {
                $0.nodeID == "architect" && $0.reason == .retryExhausted
            }
        )
        let failedReconciliation = try XCTUnwrap(
            GraphExecutionProjectionReconciler.reconcile(
                projection: exhausted.projection,
                evidenceOutcome: .available(GraphProcessEvidence()),
                observedAt: time.addingTimeInterval(2)
            )
        )
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: failedReconciliation.nodes.map {
                    ($0.id, $0.state)
                }
            ),
            [
                "architect": .failed,
                "researcher": .blocked,
                "graph": .blocked,
                "reviewer": .blocked,
            ]
        )

        let cancelled = try await makeCompendiumContext(
            runID: "compendium-cancelled",
            definition: definition,
            time: time
        )
        let cancellation = try await cancelled.repository
            .requestCancellation(
                GraphCancellationCommandRequest(
                    runID: cancelled.runID,
                    nodeID: "architect",
                    requestID: "cancel-compendium",
                    requestedBy: "operator",
                    expectedVersion: cancelled.version,
                    logicalTime: time,
                    producer: graphTestProducer,
                    recordedAt: time
                )
            )
        let terminalCancellation = try await cancelled.repository
            .declareCancellationTerminal(
                GraphCancellationTerminalRequest(
                    runID: cancelled.runID,
                    requestID: "cancel-compendium",
                    expectedVersion: cancellation.appendResult.newVersion,
                    logicalTime: time.addingTimeInterval(1),
                    producer: graphTestProducer,
                    recordedAt: time.addingTimeInterval(1)
                )
            )
        let afterCancellation = try await cancelled.repository
            .evaluateAndAppend(
                evaluationRequest(
                    runID: cancelled.runID,
                    expectedVersion:
                        terminalCancellation.appendResult.newVersion,
                    definition: definition,
                    logicalTime: time.addingTimeInterval(2),
                    executors: cancelled.executors
                )
            )
        XCTAssertTrue(runnableNodeIDs(afterCancellation.projection).isEmpty)
        let cancelledReconciliation = try XCTUnwrap(
            GraphExecutionProjectionReconciler.reconcile(
                projection: afterCancellation.projection,
                evidenceOutcome: .available(GraphProcessEvidence()),
                observedAt: time.addingTimeInterval(2)
            )
        )
        XCTAssertEqual(
            cancelledReconciliation.nodes.first {
                $0.id == "architect"
            }?.state,
            .cancelled
        )
        XCTAssertTrue(
            cancelledReconciliation.nodes.filter {
                $0.id != "architect"
            }.allSatisfy { $0.state == .blocked }
        )
    }

    func testSQLiteCompetingClaimsAndRestartPreserveOwnershipAndRetry()
        async throws
    {
        let database = try TemporarySchedulingDatabase()
        defer { database.remove() }
        let definition = try loadCompendiumSchedulingDefinition()
        let runID = "compendium-sqlite"
        let time = Date(timeIntervalSince1970: 420_000)
        let firstStore = try SQLiteGraphExecutionStore(
            databasePath: database.path
        )
        let base = compendiumSchedulingBaseEvents(
            definition: definition,
            runID: runID,
            occurredAt: time
        )
        _ = try await firstStore.append(
            base,
            to: runID,
            expectedVersion: 0
        )
        let firstRepository = DefaultGraphSchedulingRepository(
            eventStore: firstStore
        )
        let evaluation = try await firstRepository.evaluateAndAppend(
            evaluationRequest(
                runID: runID,
                expectedVersion: UInt64(base.count),
                definition: definition,
                logicalTime: time,
                executors: compendiumExecutorCapabilities(),
                initialBackoff: 30
            )
        )
        let evaluationID = try latestEvaluationID(evaluation.projection)
        let expectedVersion = evaluation.appendResult.newVersion
        let secondStore = try SQLiteGraphExecutionStore(
            databasePath: database.path
        )
        let repositories = [
            DefaultGraphSchedulingRepository(eventStore: firstStore),
            DefaultGraphSchedulingRepository(eventStore: secondStore),
        ]
        let owners = [
            GraphExecutorCapabilities(
                executorID: "worker-a",
                capabilityIdentity: "compendium-architect-v1",
                capabilities: [
                    "compendium-architecture",
                    "web-research-planning",
                ],
                hostID: "host-a"
            ),
            GraphExecutorCapabilities(
                executorID: "worker-b",
                capabilityIdentity: "compendium-architect-v1",
                capabilities: [
                    "compendium-architecture",
                    "web-research-planning",
                ],
                hostID: "host-b"
            ),
        ]

        let outcomes = await withTaskGroup(
            of: Result<GraphExecutorClaimResult, Error>.self
        ) { group in
            for index in repositories.indices {
                group.addTask {
                    do {
                        return .success(
                            try await repositories[index].attemptClaim(
                                GraphExecutorClaimRequest(
                                    runID: runID,
                                    nodeID: "architect",
                                    claimID: "sqlite-claim-\(index)",
                                    executor: owners[index],
                                    evaluationID: evaluationID,
                                    expectedVersion: expectedVersion,
                                    logicalTime: time,
                                    leaseDurationSeconds: 20,
                                    producer: graphTestProducer,
                                    recordedAt: time
                                )
                            )
                        )
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var results: [Result<GraphExecutorClaimResult, Error>] = []
            for await result in group { results.append(result) }
            return results
        }
        let winners = outcomes.compactMap { try? $0.get() }
            .filter { $0.outcome == .granted }
        XCTAssertEqual(winners.count, 1)
        let winner = try XCTUnwrap(winners.first)
        let winnerClaim = try XCTUnwrap(winner.claim)

        let restartedStore = try SQLiteGraphExecutionStore(
            databasePath: database.path
        )
        let restartedProjection = try await projection(
            restartedStore,
            runID: runID
        )
        XCTAssertEqual(
            restartedProjection.scheduling.activeClaim(
                nodeID: "architect",
                at: time.addingTimeInterval(1)
            ),
            winnerClaim
        )

        let restartedRepository = DefaultGraphSchedulingRepository(
            eventStore: restartedStore
        )
        let renewed = try await restartedRepository.renewLease(
            GraphExecutorLeaseRenewalRequest(
                runID: runID,
                claimID: winnerClaim.id,
                executorID: winnerClaim.executorID,
                expectedGeneration: 1,
                expectedVersion: winner.appendResult.newVersion,
                logicalTime: time.addingTimeInterval(5),
                leaseDurationSeconds: 20,
                producer: graphTestProducer,
                recordedAt: time.addingTimeInterval(5)
            )
        )
        let renewedClaim = try XCTUnwrap(
            renewed.projection.scheduling.claims.first {
                $0.claim.id == winnerClaim.id
            }?.claim
        )
        XCTAssertEqual(renewedClaim.leaseGeneration, 2)

        let takeoverOwner = GraphExecutorCapabilities(
            executorID: "worker-takeover",
            capabilityIdentity: "compendium-architect-v1",
            capabilities: [
                "compendium-architecture",
                "web-research-planning",
            ],
            hostID: "host-takeover"
        )
        let takeover = try await restartedRepository.attemptClaim(
            GraphExecutorClaimRequest(
                runID: runID,
                nodeID: "architect",
                claimID: "sqlite-takeover",
                executor: takeoverOwner,
                evaluationID: evaluationID,
                expectedVersion: renewed.appendResult.newVersion,
                logicalTime: time.addingTimeInterval(30),
                leaseDurationSeconds: 20,
                producer: graphTestProducer,
                recordedAt: time.addingTimeInterval(30)
            )
        )
        XCTAssertEqual(takeover.claim?.attemptOrdinal, 1)

        await XCTAssertThrowsErrorAsync {
            try await restartedRepository.renewLease(
                GraphExecutorLeaseRenewalRequest(
                    runID: runID,
                    claimID: winnerClaim.id,
                    executorID: winnerClaim.executorID,
                    expectedGeneration: 2,
                    expectedVersion: takeover.appendResult.newVersion,
                    logicalTime: time.addingTimeInterval(31),
                    leaseDurationSeconds: 20,
                    producer: graphTestProducer,
                    recordedAt: time.addingTimeInterval(31)
                )
            )
        } verify: { error in
            guard case let GraphSchedulingRepositoryError.conflict(
                reason,
                _,
                _,
                _
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(reason, .claimAlreadyReleased)
        }

        let takeoverClaim = try XCTUnwrap(takeover.claim)
        let released = try await restartedRepository.releaseClaim(
            GraphExecutorClaimReleaseRequest(
                runID: runID,
                claimID: takeoverClaim.id,
                executorID: takeoverClaim.executorID,
                expectedGeneration: 1,
                expectedVersion: takeover.appendResult.newVersion,
                logicalTime: time.addingTimeInterval(32),
                producer: graphTestProducer,
                recordedAt: time.addingTimeInterval(32)
            )
        )
        let attempt = try XCTUnwrap(
            released.projection.attempts.first {
                $0.nodeID == "architect"
            }
        )
        let failed = try await appendAttemptTerminal(
            store: restartedStore,
            runID: runID,
            nodeID: "architect",
            attemptID: attempt.id,
            expectedVersion: released.appendResult.newVersion,
            time: time.addingTimeInterval(33),
            payload: .attemptFailed(
                GraphAttemptTerminalPayload(reason: "transient")
            )
        )
        let retry = try await restartedRepository.evaluateAndAppend(
            evaluationRequest(
                runID: runID,
                expectedVersion: failed.newVersion,
                definition: definition,
                logicalTime: time.addingTimeInterval(34),
                executors: compendiumExecutorCapabilities(),
                initialBackoff: 30,
                failures: [attempt.id: "transient"]
            )
        )
        let recordedRetry = try XCTUnwrap(
            retry.projection.scheduling.retries.first
        )
        XCTAssertEqual(recordedRetry.nextAttemptOrdinal, 2)

        let retryRestart = try SQLiteGraphExecutionStore(
            databasePath: database.path
        )
        let restartedRetryProjection = try await projection(
            retryRestart,
            runID: runID
        )
        XCTAssertEqual(
            restartedRetryProjection.scheduling.retries.first,
            recordedRetry
        )
        XCTAssertEqual(
            restartedRetryProjection.scheduling.activeClaim(
                nodeID: "architect",
                at: time.addingTimeInterval(34)
            ),
            nil
        )
    }

    func testClaimCrashBoundariesLatestEvaluationAndGeneratedCollisions()
        async throws
    {
        let definition = try loadCompendiumSchedulingDefinition()
        let context = try await makeCompendiumContext(
            runID: "compendium-claim-boundaries",
            definition: definition,
            time: Date(timeIntervalSince1970: 425_000)
        )
        let firstEvaluation = try await context.repository.evaluateAndAppend(
            evaluationRequest(
                runID: context.runID,
                expectedVersion: context.version,
                definition: definition,
                logicalTime: context.time,
                executors: context.executors
            )
        )
        let firstEvaluationID = try latestEvaluationID(
            firstEvaluation.projection
        )
        let secondEvaluation = try await context.repository.evaluateAndAppend(
            evaluationRequest(
                runID: context.runID,
                expectedVersion: firstEvaluation.appendResult.newVersion,
                definition: definition,
                logicalTime: context.time.addingTimeInterval(1),
                executors: context.executors
            )
        )
        XCTAssertTrue(
            secondEvaluation.projection.scheduling.claims.isEmpty,
            "A crash before the claim append leaves no ownership fact."
        )
        let owner = try XCTUnwrap(
            context.executors.first {
                $0.executorID == "architect-worker"
            }
        )
        let restarted = DefaultGraphSchedulingRepository(
            eventStore: context.store
        )

        await XCTAssertThrowsErrorAsync {
            try await restarted.attemptClaim(
                GraphExecutorClaimRequest(
                    runID: context.runID,
                    nodeID: "architect",
                    claimID: "stale-evaluation-claim",
                    executor: owner,
                    evaluationID: firstEvaluationID,
                    expectedVersion:
                        secondEvaluation.appendResult.newVersion,
                    logicalTime: context.time.addingTimeInterval(1),
                    leaseDurationSeconds: 60,
                    producer: graphTestProducer,
                    recordedAt: context.time.addingTimeInterval(1)
                )
            )
        } verify: { error in
            assertSchedulingRepositoryConflict(
                error,
                .schedulerEvaluationMissing
            )
        }

        let request = GraphExecutorClaimRequest(
            runID: context.runID,
            nodeID: "architect",
            claimID: "durable-claim",
            executor: owner,
            evaluationID: try latestEvaluationID(
                secondEvaluation.projection
            ),
            expectedVersion: secondEvaluation.appendResult.newVersion,
            logicalTime: context.time.addingTimeInterval(1),
            leaseDurationSeconds: 60,
            producer: graphTestProducer,
            recordedAt: context.time.addingTimeInterval(1)
        )
        let claimed = try await restarted.attemptClaim(request)
        let afterCrash = DefaultGraphSchedulingRepository(
            eventStore: context.store
        )
        let redelivery = try await afterCrash.attemptClaim(request)
        XCTAssertEqual(redelivery.outcome, .deduplicated)
        XCTAssertEqual(redelivery.claim, claimed.claim)

        let mutations: [GraphExecutorClaimRequest] = [
            GraphExecutorClaimRequest(
                runID: context.runID,
                nodeID: "architect",
                claimID: "durable-claim",
                executor: GraphExecutorCapabilities(
                    executorID: owner.executorID,
                    capabilityIdentity: "different-capability",
                    capabilities: owner.capabilities,
                    hostID: owner.hostID
                ),
                evaluationID: request.evaluationID,
                expectedVersion: claimed.appendResult.newVersion,
                logicalTime: request.logicalTime,
                leaseDurationSeconds: 60,
                producer: graphTestProducer,
                recordedAt: request.recordedAt
            ),
            GraphExecutorClaimRequest(
                runID: context.runID,
                nodeID: "architect",
                claimID: "durable-claim",
                executor: GraphExecutorCapabilities(
                    executorID: owner.executorID,
                    capabilityIdentity: owner.capabilityIdentity,
                    capabilities: owner.capabilities,
                    hostID: "different-host"
                ),
                evaluationID: request.evaluationID,
                expectedVersion: claimed.appendResult.newVersion,
                logicalTime: request.logicalTime,
                leaseDurationSeconds: 60,
                producer: graphTestProducer,
                recordedAt: request.recordedAt
            ),
            GraphExecutorClaimRequest(
                runID: context.runID,
                nodeID: "architect",
                claimID: "durable-claim",
                executor: owner,
                evaluationID: request.evaluationID,
                expectedVersion: claimed.appendResult.newVersion,
                logicalTime: request.logicalTime.addingTimeInterval(1),
                leaseDurationSeconds: 60,
                producer: graphTestProducer,
                recordedAt: request.recordedAt
            ),
            GraphExecutorClaimRequest(
                runID: context.runID,
                nodeID: "architect",
                claimID: "durable-claim",
                executor: owner,
                evaluationID: request.evaluationID,
                expectedVersion: claimed.appendResult.newVersion,
                logicalTime: request.logicalTime,
                leaseDurationSeconds: 61,
                producer: graphTestProducer,
                recordedAt: request.recordedAt
            ),
        ]
        for mutation in mutations {
            await XCTAssertThrowsErrorAsync {
                try await afterCrash.attemptClaim(mutation)
            } verify: { error in
                assertSchedulingRepositoryConflict(
                    error,
                    .claimIdentityCollision
                )
            }
        }
    }

    func testFutureSchedulingEventsSnapshotsAndStaleFixtureRemainCompatible()
        async throws
    {
        let definition = try loadCompendiumSchedulingDefinition()
        let time = Date(timeIntervalSince1970: 430_000)
        let runID = "future-scheduling"
        var events = compendiumSchedulingBaseEvents(
            definition: definition,
            runID: runID,
            occurredAt: time
        )
        events.append(
            GraphExecutionEventEnvelope(
                id: "future-scheduler-event",
                runID: runID,
                streamSequence: UInt64(events.count + 1),
                occurredAt: time,
                recordedAt: time,
                producer: graphTestProducer,
                payloadVersion: 99,
                payload: .unknown(
                    eventType: "graph.scheduler.quantum.reserved",
                    body: .object(["reservation": .string("future")])
                )
            )
        )
        let futureProjection = try GraphExecutionProjector.replay(
            runID: runID,
            events: events
        ).projection
        XCTAssertEqual(futureProjection.unknownEvents.count, 1)
        XCTAssertTrue(futureProjection.scheduling.records.isEmpty)

        let encoded = try JSONEncoder().encode(futureProjection)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded)
                as? [String: Any]
        )
        object.removeValue(forKey: "scheduling")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let legacyProjection = try JSONDecoder().decode(
            GraphExecutionProjection.self,
            from: legacyData
        )
        XCTAssertEqual(
            legacyProjection.scheduling,
            GraphSchedulingProjection()
        )

        let stale = try loadStaleCompendiumFixture()
        let staleProjection = try GraphExecutionProjector.replay(
            runID: stale.run.id,
            events: staleCompendiumEvents(from: stale)
        ).projection
        let staleReconciled = try XCTUnwrap(
            GraphExecutionProjectionReconciler.reconcile(
                projection: staleProjection,
                evidenceOutcome: .available(GraphProcessEvidence()),
                observedAt: stale.observedAt
            )
        )
        let decision = GraphScheduler.evaluate(
            GraphSchedulingInput(
                definition: definition,
                projectedState: staleProjection,
                reconciledState: staleReconciled,
                policy: schedulingPolicy(),
                logicalTime: stale.observedAt,
                availableExecutors: compendiumExecutorCapabilities()
            )
        )
        XCTAssertTrue(
            decision.reasonsByNodeID.values.allSatisfy {
                $0 == .graphDefinitionMismatch
            }
        )
    }

    func testStructuredSchedulingInspectionIsByteStableAndVersioned()
        async throws
    {
        let definition = try loadCompendiumSchedulingDefinition()
        let context = try await makeCompendiumContext(
            runID: "compendium-inspection",
            definition: definition,
            time: Date(timeIntervalSince1970: 440_000)
        )
        let evaluation = try await context.repository.evaluateAndAppend(
            evaluationRequest(
                runID: context.runID,
                expectedVersion: context.version,
                definition: definition,
                logicalTime: context.time,
                executors: context.executors
            )
        )
        let owner = try XCTUnwrap(
            context.executors.first {
                $0.executorID == "architect-worker"
            }
        )
        let claim = try await context.repository.attemptClaim(
            GraphExecutorClaimRequest(
                runID: context.runID,
                nodeID: "architect",
                claimID: "inspection-claim",
                executor: owner,
                evaluationID: try latestEvaluationID(
                    evaluation.projection
                ),
                expectedVersion: evaluation.appendResult.newVersion,
                logicalTime: context.time,
                leaseDurationSeconds: 60,
                producer: graphTestProducer,
                recordedAt: context.time
            )
        )
        let cancellation = try await context.repository.requestCancellation(
            GraphCancellationCommandRequest(
                runID: context.runID,
                nodeID: "architect",
                requestID: "inspection-cancellation",
                requestedBy: "operator",
                expectedVersion: claim.appendResult.newVersion,
                logicalTime: context.time.addingTimeInterval(1),
                producer: graphTestProducer,
                recordedAt: context.time.addingTimeInterval(1)
            )
        )
        _ = try await context.repository.recordTimeout(
            GraphTimeoutCommandRequest(
                decision: GraphTimeoutDecision(
                    timeoutID: "inspection-timeout",
                    runID: context.runID,
                    nodeID: "graph",
                    attemptID: nil,
                    claimID: nil,
                    kind: .claimAcquisition,
                    deadline: context.time.addingTimeInterval(2),
                    declaredAt: context.time.addingTimeInterval(2)
                ),
                expectedVersion: cancellation.appendResult.newVersion,
                producer: graphTestProducer,
                recordedAt: context.time.addingTimeInterval(2)
            )
        )
        let stdout = SchedulingCLISink()
        let stderr = SchedulingCLISink()
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: context.store,
                snapshotStore: InMemoryGraphExecutionSnapshotStore()
            ),
            stdout: stdout,
            stderr: stderr
        )
        let currentArguments = [
            "graph",
            "inspect",
            context.runID,
            "--output",
            "json",
            "--schema-version",
            "2",
        ]
        let firstCode = await runner.run(arguments: currentArguments)
        XCTAssertEqual(firstCode, .success)
        let first = stdout.consume()
        let secondCode = await runner.run(arguments: currentArguments)
        XCTAssertEqual(secondCode, .success)
        let second = stdout.consume()
        XCTAssertEqual(first, second)
        let current = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(first.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(current["schemaVersion"] as? Int, 2)
        let currentResult = try XCTUnwrap(
            current["result"] as? [String: Any]
        )
        let scheduling = try XCTUnwrap(
            currentResult["scheduling"] as? [String: Any]
        )
        XCTAssertNotNil(scheduling["currentPolicy"])
        XCTAssertNotNil(scheduling["reasonCodes"])
        XCTAssertEqual(
            (scheduling["activeClaims"] as? [[String: Any]])?.count,
            1
        )
        XCTAssertEqual(
            (scheduling["claimHistory"] as? [[String: Any]])?.count,
            1
        )
        XCTAssertEqual(
            (scheduling["pendingCancellations"]
                as? [[String: Any]])?.count,
            1
        )
        XCTAssertEqual(
            (scheduling["timeouts"] as? [[String: Any]])?.count,
            1
        )

        let explainCode = await runner.run(
            arguments: [
                "graph",
                "explain",
                context.runID,
                "architect",
                "--output",
                "json",
                "--schema-version",
                "2",
            ]
        )
        XCTAssertEqual(explainCode, .success)
        let explanation = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(stdout.consume().utf8)
            ) as? [String: Any]
        )
        let explanationResult = try XCTUnwrap(
            explanation["result"] as? [String: Any]
        )
        XCTAssertEqual(
            explanationResult["schedulerReasons"] as? [String],
            [
                "cancellation_pending",
                "claim_granted",
                "dependencies_satisfied",
            ]
        )

        let legacyCode = await runner.run(
            arguments: [
                "graph",
                "inspect",
                context.runID,
                "--output",
                "json",
                "--schema-version",
                "1",
            ]
        )
        XCTAssertEqual(legacyCode, .success)
        let legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(stdout.consume().utf8)
            ) as? [String: Any]
        )
        XCTAssertEqual(legacy["schemaVersion"] as? Int, 1)
        let legacyResult = try XCTUnwrap(
            legacy["result"] as? [String: Any]
        )
        XCTAssertNil(legacyResult["scheduling"])
        XCTAssertTrue(stderr.consume().isEmpty)
    }
}

private struct CompendiumTestContext {
    let runID: String
    let time: Date
    let version: UInt64
    let store: InMemoryGraphExecutionEventStore
    let repository: DefaultGraphSchedulingRepository
    let executors: [GraphExecutorCapabilities]
}

private func makeCompendiumContext(
    runID: String,
    definition: GraphSchedulingDefinition,
    time: Date
) async throws -> CompendiumTestContext {
    let store = InMemoryGraphExecutionEventStore()
    let events = compendiumSchedulingBaseEvents(
        definition: definition,
        runID: runID,
        occurredAt: time
    )
    let appended = try await store.append(
        events,
        to: runID,
        expectedVersion: 0
    )
    return CompendiumTestContext(
        runID: runID,
        time: time,
        version: appended.newVersion,
        store: store,
        repository: DefaultGraphSchedulingRepository(eventStore: store),
        executors: compendiumExecutorCapabilities()
    )
}

private func schedulingPolicy(
    maximumAttempts: Int = 3,
    initialBackoff: UInt64 = 0
) -> GraphSchedulerPolicy {
    GraphSchedulerPolicy(
        policyID: "compendium-scheduling-policy",
        version: "1",
        retryPolicy: GraphRetryPolicy(
            maximumAttempts: maximumAttempts,
            retryableFailureCategories: ["transient"],
            nonRetryableFailureCategories: ["invalid_output"],
            initialBackoffSeconds: initialBackoff,
            backoffMultiplier: 2,
            maximumBackoffSeconds: 300,
            jitterBasisPoints: 500,
            jitterSeed: "compendium-fixture"
        ),
        defaultLeaseDurationSeconds: 60,
        claimAcquisitionTimeoutSeconds: 30,
        attemptExecutionTimeoutSeconds: 3_600,
        cancellationAcknowledgementTimeoutSeconds: 30
    )
}

private func evaluationRequest(
    runID: String,
    expectedVersion: UInt64,
    definition: GraphSchedulingDefinition,
    logicalTime: Date,
    executors: [GraphExecutorCapabilities],
    maximumAttempts: Int = 3,
    initialBackoff: UInt64 = 0,
    failures: [String: String] = [:]
) -> GraphSchedulerEvaluationRequest {
    GraphSchedulerEvaluationRequest(
        runID: runID,
        expectedVersion: expectedVersion,
        definition: definition,
        policy: schedulingPolicy(
            maximumAttempts: maximumAttempts,
            initialBackoff: initialBackoff
        ),
        logicalTime: logicalTime,
        availableExecutors: executors,
        failureCategoriesByAttemptID: failures,
        producer: graphTestProducer,
        recordedAt: logicalTime
    )
}

private func latestEvaluationID(
    _ projection: GraphExecutionProjection
) throws -> String {
    try XCTUnwrap(
        projection.scheduling.records.last {
            $0.eventType
                == GraphExecutionEventType.schedulerCycleCompleted.rawValue
        }?.evaluationID
    )
}

private func runnableNodeIDs(
    _ projection: GraphExecutionProjection
) -> [String] {
    guard let evaluationID = projection.scheduling.records.last(where: {
        $0.eventType
            == GraphExecutionEventType.schedulerCycleCompleted.rawValue
    })?.evaluationID else {
        return []
    }
    return projection.scheduling.records.filter {
        $0.evaluationID == evaluationID
            && $0.eventType
                == GraphExecutionEventType.nodeBecameRunnable.rawValue
    }.compactMap(\.nodeID).sorted()
}

private func projection(
    _ store: any GraphExecutionEventStore,
    runID: String
) async throws -> GraphExecutionProjection {
    let stream = try await store.read(runID: runID, afterVersion: 0)
    return try GraphExecutionProjector.replay(
        runID: runID,
        events: stream.events
    ).projection
}

private func appendAttemptTerminal(
    store: any GraphExecutionEventStore,
    runID: String,
    nodeID: String,
    attemptID: String,
    expectedVersion: UInt64,
    time: Date,
    payload: GraphExecutionEventPayload
) async throws -> GraphExecutionAppendResult {
    let events = [
        GraphExecutionEventEnvelope(
            id: "\(attemptID)-starting-\(expectedVersion)",
            runID: runID,
            nodeID: nodeID,
            attemptID: attemptID,
            streamSequence: expectedVersion + 1,
            occurredAt: time,
            recordedAt: time,
            producer: graphTestProducer,
            payload: .attemptStarting(GraphAttemptStartingPayload())
        ),
        GraphExecutionEventEnvelope(
            id: "\(attemptID)-terminal-\(expectedVersion)",
            runID: runID,
            nodeID: nodeID,
            attemptID: attemptID,
            streamSequence: expectedVersion + 2,
            occurredAt: time,
            recordedAt: time,
            producer: graphTestProducer,
            payload: payload
        ),
    ]
    return try await store.append(
        events,
        to: runID,
        expectedVersion: expectedVersion
    )
}

private final class TemporarySchedulingDatabase {
    let directory: URL
    let path: String

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openisland-scheduling-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        path = directory.appendingPathComponent("history.sqlite").path
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class SchedulingCLISink:
    GraphCLIOutputSink,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var data = Data()

    func write(_ value: Data) -> GraphCLIWriteResult {
        lock.lock()
        data.append(value)
        lock.unlock()
        return .written
    }

    func consume() -> String {
        lock.lock()
        let value = String(decoding: data, as: UTF8.self)
        data.removeAll(keepingCapacity: true)
        lock.unlock()
        return value
    }
}

private func assertSchedulingRepositoryConflict(
    _ error: Error,
    _ expected: GraphSchedulingConflictReason,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case let GraphSchedulingRepositoryError.conflict(
        reason,
        _,
        _,
        _
    ) = error else {
        return XCTFail(
            "Unexpected error: \(error)",
            file: file,
            line: line
        )
    }
    XCTAssertEqual(reason, expected, file: file, line: line)
}
