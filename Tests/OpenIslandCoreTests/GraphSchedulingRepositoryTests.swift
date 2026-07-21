import XCTest
@testable import OpenIslandCore

final class GraphSchedulingRepositoryTests: XCTestCase {
    func testEvaluationClaimRenewalAndReleaseAreDurable()
        async throws
    {
        let context = try await schedulingRepositoryContext()
        let evaluation = try await context.repository.evaluateAndAppend(
            context.evaluationRequest(expectedVersion: 2)
        )
        let evaluationID = try XCTUnwrap(
            evaluation.projection.scheduling.completedEvaluationIDs.first
        )
        let claimRequest = context.claimRequest(
            claimID: "claim-a",
            evaluationID: evaluationID,
            expectedVersion: evaluation.appendResult.newVersion,
            executorID: "worker-a"
        )

        let claimed = try await context.repository.attemptClaim(
            claimRequest
        )
        let claim = try XCTUnwrap(claimed.claim)
        XCTAssertEqual(claimed.outcome, .granted)
        XCTAssertEqual(claim.attemptOrdinal, 1)
        XCTAssertEqual(claim.leaseGeneration, 1)

        let repeated = try await context.repository.attemptClaim(
            claimRequest
        )
        XCTAssertEqual(repeated.outcome, .deduplicated)
        XCTAssertEqual(repeated.claim, claim)

        let renewed = try await context.repository.renewLease(
            GraphExecutorLeaseRenewalRequest(
                runID: context.runID,
                claimID: claim.id,
                executorID: claim.executorID,
                expectedGeneration: 1,
                expectedVersion: claimed.appendResult.newVersion,
                logicalTime: context.time.addingTimeInterval(10),
                leaseDurationSeconds: 60,
                producer: graphTestProducer,
                recordedAt: context.time.addingTimeInterval(10)
            )
        )
        let renewedClaim = try XCTUnwrap(
            renewed.projection.scheduling.claims.first?.claim
        )
        XCTAssertEqual(renewedClaim.leaseGeneration, 2)

        let released = try await context.repository.releaseClaim(
            GraphExecutorClaimReleaseRequest(
                runID: context.runID,
                claimID: claim.id,
                executorID: claim.executorID,
                expectedGeneration: 2,
                expectedVersion: renewed.appendResult.newVersion,
                logicalTime: context.time.addingTimeInterval(20),
                producer: graphTestProducer,
                recordedAt: context.time.addingTimeInterval(20)
            )
        )
        XCTAssertEqual(
            released.projection.scheduling.claims.first?.status,
            .released
        )

        let repeatedRelease = try await context.repository.releaseClaim(
            GraphExecutorClaimReleaseRequest(
                runID: context.runID,
                claimID: claim.id,
                executorID: claim.executorID,
                expectedGeneration: 2,
                expectedVersion: renewed.appendResult.newVersion,
                logicalTime: context.time.addingTimeInterval(20),
                producer: graphTestProducer,
                recordedAt: context.time.addingTimeInterval(20)
            )
        )
        XCTAssertEqual(repeatedRelease.appendResult.appendedCount, 0)
    }

    func testCompetingClaimsProduceExactlyOneWinner() async throws {
        let context = try await schedulingRepositoryContext()
        let evaluation = try await context.repository.evaluateAndAppend(
            context.evaluationRequest(expectedVersion: 2)
        )
        let evaluationID = try XCTUnwrap(
            evaluation.projection.scheduling.completedEvaluationIDs.first
        )
        let expected = evaluation.appendResult.newVersion
        let repository = context.repository
        let first = context.claimRequest(
            claimID: "claim-a",
            evaluationID: evaluationID,
            expectedVersion: expected,
            executorID: "worker-a"
        )
        let second = context.claimRequest(
            claimID: "claim-b",
            evaluationID: evaluationID,
            expectedVersion: expected,
            executorID: "worker-b"
        )

        let outcomes = await withTaskGroup(
            of: Result<GraphExecutorClaimResult, Error>.self
        ) { group in
            group.addTask {
                do {
                    return .success(
                        try await repository.attemptClaim(first)
                    )
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                do {
                    return .success(
                        try await repository.attemptClaim(second)
                    )
                } catch {
                    return .failure(error)
                }
            }
            var results: [Result<GraphExecutorClaimResult, Error>] = []
            for await result in group { results.append(result) }
            return results
        }
        let winners = outcomes.compactMap { try? $0.get() }.filter {
            $0.outcome == .granted
        }
        let conflicts = outcomes.compactMap { result -> GraphSchedulingConflictReason? in
            switch result {
            case let .success(value):
                return value.conflictReason
            case let .failure(error):
                guard case let GraphSchedulingRepositoryError.conflict(
                    reason,
                    _,
                    _,
                    _
                ) = error else {
                    return nil
                }
                return reason
            }
        }
        let stream = try await context.store.read(
            runID: context.runID,
            afterVersion: 0
        )
        let projection = try GraphExecutionProjector.replay(
            runID: context.runID,
            events: stream.events
        ).projection

        XCTAssertEqual(winners.count, 1)
        XCTAssertEqual(
            conflicts.count,
            1
        )
        if let reason = conflicts.first {
            XCTAssertTrue(
                reason == .expectedVersionConflict
                    || reason == .existingActiveClaim
            )
        }
        XCTAssertEqual(
            projection.scheduling.claims.filter { $0.status == .active }.count,
            1
        )
    }

    func testExpiredLeaseAllowsTakeoverAndRejectsStaleRenewal()
        async throws
    {
        let context = try await schedulingRepositoryContext()
        let evaluation = try await context.repository.evaluateAndAppend(
            context.evaluationRequest(expectedVersion: 2)
        )
        let evaluationID = try XCTUnwrap(
            evaluation.projection.scheduling.completedEvaluationIDs.first
        )
        let first = try await context.repository.attemptClaim(
            context.claimRequest(
                claimID: "claim-a",
                evaluationID: evaluationID,
                expectedVersion: evaluation.appendResult.newVersion,
                executorID: "worker-a",
                leaseDurationSeconds: 5
            )
        )
        let firstClaim = try XCTUnwrap(first.claim)

        await XCTAssertThrowsErrorAsync {
            try await context.repository.renewLease(
                GraphExecutorLeaseRenewalRequest(
                    runID: context.runID,
                    claimID: firstClaim.id,
                    executorID: firstClaim.executorID,
                    expectedGeneration: 1,
                    expectedVersion: first.appendResult.newVersion,
                    logicalTime: context.time.addingTimeInterval(6),
                    leaseDurationSeconds: 30,
                    producer: graphTestProducer,
                    recordedAt: context.time.addingTimeInterval(6)
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
            XCTAssertEqual(reason, .leaseExpired)
        }

        let takeover = try await context.repository.attemptClaim(
            context.claimRequest(
                claimID: "claim-b",
                evaluationID: evaluationID,
                expectedVersion: first.appendResult.newVersion,
                executorID: "worker-b",
                logicalTime: context.time.addingTimeInterval(6)
            )
        )
        XCTAssertEqual(takeover.outcome, .granted)
        XCTAssertEqual(takeover.claim?.attemptOrdinal, 1)

        let stream = try await context.store.read(
            runID: context.runID,
            afterVersion: 0
        )
        let projection = try GraphExecutionProjector.replay(
            runID: context.runID,
            events: stream.events
        ).projection
        XCTAssertEqual(
            projection.scheduling.claims.first {
                $0.claim.id == firstClaim.id
            }?.status,
            .expired
        )
        XCTAssertEqual(
            projection.scheduling.activeClaim(
                nodeID: "architect",
                at: context.time.addingTimeInterval(6)
            )?.id,
            "claim-b"
        )
    }

    func testContradictoryClaimIdentityAndLeaseGenerationFail()
        async throws
    {
        let context = try await schedulingRepositoryContext()
        let evaluation = try await context.repository.evaluateAndAppend(
            context.evaluationRequest(expectedVersion: 2)
        )
        let evaluationID = try XCTUnwrap(
            evaluation.projection.scheduling.completedEvaluationIDs.first
        )
        let first = try await context.repository.attemptClaim(
            context.claimRequest(
                claimID: "claim-a",
                evaluationID: evaluationID,
                expectedVersion: evaluation.appendResult.newVersion,
                executorID: "worker-a"
            )
        )

        await XCTAssertThrowsErrorAsync {
            try await context.repository.attemptClaim(
                context.claimRequest(
                    claimID: "claim-a",
                    evaluationID: evaluationID,
                    expectedVersion: first.appendResult.newVersion,
                    executorID: "worker-b"
                )
            )
        } verify: { error in
            assertSchedulingConflict(error, .claimIdentityCollision)
        }

        await XCTAssertThrowsErrorAsync {
            try await context.repository.renewLease(
                GraphExecutorLeaseRenewalRequest(
                    runID: context.runID,
                    claimID: "claim-a",
                    executorID: "worker-a",
                    expectedGeneration: 9,
                    expectedVersion: first.appendResult.newVersion,
                    logicalTime: context.time.addingTimeInterval(1),
                    leaseDurationSeconds: 60,
                    producer: graphTestProducer,
                    recordedAt: context.time.addingTimeInterval(1)
                )
            )
        } verify: { error in
            assertSchedulingConflict(error, .leaseGenerationMismatch)
        }
    }
}

private struct SchedulingRepositoryContext {
    let runID = "claim-run"
    let time = Date(timeIntervalSince1970: 200_000)
    let digest = GraphContentDigest(
        algorithm: "sha256",
        value: "claim-graph-v1"
    )
    let store: InMemoryGraphExecutionEventStore
    let repository: DefaultGraphSchedulingRepository

    var definition: GraphSchedulingDefinition {
        GraphSchedulingDefinition(
            graphID: "claim-graph",
            version: "1",
            digest: digest,
            nodes: [
                GraphSchedulingDefinitionNode(
                    id: "architect",
                    title: "Architect",
                    requiredCapabilities: ["research-planning"]
                ),
            ]
        )
    }

    var policy: GraphSchedulerPolicy {
        GraphSchedulerPolicy(
            policyID: "claim-policy",
            version: "1",
            retryPolicy: GraphRetryPolicy(
                maximumAttempts: 3,
                retryableFailureCategories: ["transient"]
            )
        )
    }

    func evaluationRequest(
        expectedVersion: UInt64
    ) -> GraphSchedulerEvaluationRequest {
        GraphSchedulerEvaluationRequest(
            runID: runID,
            expectedVersion: expectedVersion,
            definition: definition,
            policy: policy,
            logicalTime: time,
            availableExecutors: [executor("worker-a")],
            producer: graphTestProducer,
            recordedAt: time
        )
    }

    func claimRequest(
        claimID: String,
        evaluationID: String,
        expectedVersion: UInt64,
        executorID: String,
        leaseDurationSeconds: UInt64 = 60,
        logicalTime: Date? = nil
    ) -> GraphExecutorClaimRequest {
        GraphExecutorClaimRequest(
            runID: runID,
            nodeID: "architect",
            claimID: claimID,
            executor: executor(executorID),
            evaluationID: evaluationID,
            expectedVersion: expectedVersion,
            logicalTime: logicalTime ?? time,
            leaseDurationSeconds: leaseDurationSeconds,
            producer: graphTestProducer,
            recordedAt: logicalTime ?? time
        )
    }

    private func executor(_ id: String) -> GraphExecutorCapabilities {
        GraphExecutorCapabilities(
            executorID: id,
            capabilityIdentity: "research-worker",
            capabilities: ["research-planning"],
            hostID: "host-\(id)"
        )
    }
}

private func schedulingRepositoryContext()
    async throws -> SchedulingRepositoryContext
{
    let store = InMemoryGraphExecutionEventStore()
    let context = SchedulingRepositoryContext(
        store: store,
        repository: DefaultGraphSchedulingRepository(eventStore: store)
    )
    let events = [
        GraphExecutionEventEnvelope(
            id: "claim-run-created",
            runID: context.runID,
            streamSequence: 1,
            occurredAt: context.time,
            recordedAt: context.time,
            producer: graphTestProducer,
            payload: .runCreated(
                GraphRunCreatedPayload(
                    graphID: context.definition.graphID,
                    graphDefinitionVersion: context.definition.version,
                    graphDefinitionDigest: context.digest,
                    nodeIDs: ["architect"]
                )
            )
        ),
        GraphExecutionEventEnvelope(
            id: "claim-node-created",
            runID: context.runID,
            nodeID: "architect",
            streamSequence: 2,
            occurredAt: context.time,
            recordedAt: context.time,
            producer: graphTestProducer,
            payload: .nodeRegistered(
                GraphNodeRegisteredPayload(title: "Architect")
            )
        ),
    ]
    _ = try await store.append(
        events,
        to: context.runID,
        expectedVersion: 0
    )
    return context
}

private func assertSchedulingConflict(
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
        return XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
    XCTAssertEqual(reason, expected, file: file, line: line)
}
