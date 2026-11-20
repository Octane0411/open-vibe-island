import XCTest
@testable import OpenIslandCore

final class GraphSchedulingProtocolTests: XCTestCase {
    func testCancellationBeforeClaimIsIdempotentAndTerminal()
        async throws
    {
        let context = try await schedulingRepositoryContext()
        let request = GraphCancellationCommandRequest(
            runID: context.runID,
            nodeID: "architect",
            requestID: "cancel-before-claim",
            requestedBy: "operator",
            reason: "No longer needed",
            expectedVersion: 2,
            logicalTime: context.time,
            producer: graphTestProducer,
            recordedAt: context.time
        )

        let requested = try await context.repository.requestCancellation(
            request
        )
        let duplicate = try await context.repository.requestCancellation(
            request
        )
        XCTAssertEqual(duplicate.appendResult.appendedCount, 0)
        XCTAssertEqual(
            requested.projection.scheduling.cancellations.first?.state,
            .requested
        )

        let terminal = try await context.repository
            .declareCancellationTerminal(
                GraphCancellationTerminalRequest(
                    runID: context.runID,
                    requestID: request.requestID,
                    expectedVersion: requested.appendResult.newVersion,
                    logicalTime: context.time.addingTimeInterval(1),
                    reason: "Cancelled before ownership",
                    producer: graphTestProducer,
                    recordedAt: context.time.addingTimeInterval(1)
                )
            )
        XCTAssertEqual(terminal.projection.attempts.count, 1)
        XCTAssertEqual(terminal.projection.attempts.first?.ordinal, 1)
        XCTAssertEqual(terminal.projection.attempts.first?.state, .cancelled)

        let repeated = try await context.repository
            .declareCancellationTerminal(
                GraphCancellationTerminalRequest(
                    runID: context.runID,
                    requestID: request.requestID,
                    expectedVersion: requested.appendResult.newVersion,
                    logicalTime: context.time.addingTimeInterval(1),
                    reason: "Cancelled before ownership",
                    producer: graphTestProducer,
                    recordedAt: context.time.addingTimeInterval(1)
                )
            )
        XCTAssertEqual(repeated.appendResult.appendedCount, 0)
    }

    func testClaimedCancellationRequiresOwnerAcknowledgement()
        async throws
    {
        let owned = try await claimedContext(leaseDuration: 30)
        let cancellation = try await owned.context.repository
            .requestCancellation(
                GraphCancellationCommandRequest(
                    runID: owned.context.runID,
                    nodeID: "architect",
                    attemptID: owned.attemptID,
                    requestID: "cancel-owned",
                    requestedBy: "operator",
                    expectedVersion: owned.version,
                    logicalTime: owned.context.time.addingTimeInterval(1),
                    producer: graphTestProducer,
                    recordedAt: owned.context.time.addingTimeInterval(1)
                )
            )
        let acknowledged = try await owned.context.repository
            .acknowledgeCancellation(
                GraphCancellationAcknowledgementRequest(
                    runID: owned.context.runID,
                    requestID: "cancel-owned",
                    claimID: owned.claim.id,
                    executorID: owned.claim.executorID,
                    expectedVersion: cancellation.appendResult.newVersion,
                    logicalTime: owned.context.time.addingTimeInterval(2),
                    producer: graphTestProducer,
                    recordedAt: owned.context.time.addingTimeInterval(2)
                )
            )
        XCTAssertEqual(
            acknowledged.projection.scheduling.cancellations.first?.state,
            .acknowledged
        )
        let duplicateAcknowledgement = try await owned.context.repository
            .acknowledgeCancellation(
                GraphCancellationAcknowledgementRequest(
                    runID: owned.context.runID,
                    requestID: "cancel-owned",
                    claimID: owned.claim.id,
                    executorID: owned.claim.executorID,
                    expectedVersion: cancellation.appendResult.newVersion,
                    logicalTime: owned.context.time.addingTimeInterval(2),
                    producer: graphTestProducer,
                    recordedAt: owned.context.time.addingTimeInterval(2)
                )
            )
        XCTAssertEqual(
            duplicateAcknowledgement.appendResult.appendedCount,
            0
        )

        let terminal = try await owned.context.repository
            .declareCancellationTerminal(
                GraphCancellationTerminalRequest(
                    runID: owned.context.runID,
                    requestID: "cancel-owned",
                    expectedVersion: acknowledged.appendResult.newVersion,
                    logicalTime: owned.context.time.addingTimeInterval(3),
                    producer: graphTestProducer,
                    recordedAt: owned.context.time.addingTimeInterval(3)
                )
            )
        XCTAssertEqual(terminal.projection.attempts.first?.state, .cancelled)
        XCTAssertEqual(
            terminal.projection.scheduling.claims.first?.status,
            .released
        )
    }

    func testStaleOwnerCannotAcknowledgeAfterLeaseExpiry()
        async throws
    {
        let owned = try await claimedContext(leaseDuration: 2)
        let cancellation = try await owned.context.repository
            .requestCancellation(
                GraphCancellationCommandRequest(
                    runID: owned.context.runID,
                    nodeID: "architect",
                    attemptID: owned.attemptID,
                    requestID: "cancel-stale",
                    requestedBy: "operator",
                    expectedVersion: owned.version,
                    logicalTime: owned.context.time.addingTimeInterval(1),
                    producer: graphTestProducer,
                    recordedAt: owned.context.time.addingTimeInterval(1)
                )
            )

        await XCTAssertThrowsErrorAsync {
            try await owned.context.repository.acknowledgeCancellation(
                GraphCancellationAcknowledgementRequest(
                    runID: owned.context.runID,
                    requestID: "cancel-stale",
                    claimID: owned.claim.id,
                    executorID: owned.claim.executorID,
                    expectedVersion: cancellation.appendResult.newVersion,
                    logicalTime: owned.context.time.addingTimeInterval(3),
                    producer: graphTestProducer,
                    recordedAt: owned.context.time.addingTimeInterval(3)
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
            XCTAssertEqual(reason, .staleCancellationAcknowledgement)
        }
    }

    func testExpiredOwnerDoesNotPreventTerminalCancellation()
        async throws
    {
        let owned = try await claimedContext(leaseDuration: 2)
        let cancellation = try await owned.context.repository
            .requestCancellation(
                GraphCancellationCommandRequest(
                    runID: owned.context.runID,
                    nodeID: "architect",
                    attemptID: owned.attemptID,
                    requestID: "cancel-expired-owner",
                    requestedBy: "operator",
                    expectedVersion: owned.version,
                    logicalTime: owned.context.time.addingTimeInterval(1),
                    producer: graphTestProducer,
                    recordedAt: owned.context.time.addingTimeInterval(1)
                )
            )
        let terminal = try await owned.context.repository
            .declareCancellationTerminal(
                GraphCancellationTerminalRequest(
                    runID: owned.context.runID,
                    requestID: "cancel-expired-owner",
                    expectedVersion: cancellation.appendResult.newVersion,
                    logicalTime: owned.context.time.addingTimeInterval(3),
                    reason: "owner unavailable after lease expiry",
                    producer: graphTestProducer,
                    recordedAt: owned.context.time.addingTimeInterval(3)
                )
            )

        XCTAssertEqual(terminal.projection.attempts.first?.state, .cancelled)
        XCTAssertEqual(
            terminal.projection.scheduling.claims.first?.status,
            .expired
        )
    }

    func testTimeoutKindsAreDurableAndLeaseTimeoutDoesNotEndAttempt()
        async throws
    {
        let owned = try await claimedContext(leaseDuration: 2)
        let deadline = owned.context.time.addingTimeInterval(2)
        let decision = GraphTimeoutDecision(
            timeoutID: "lease-timeout",
            runID: owned.context.runID,
            nodeID: "architect",
            attemptID: owned.attemptID,
            claimID: owned.claim.id,
            kind: .lease,
            deadline: deadline,
            declaredAt: deadline,
            reason: .timeoutRecorded
        )
        let timedOut = try await owned.context.repository.recordTimeout(
            GraphTimeoutCommandRequest(
                decision: decision,
                expectedVersion: owned.version,
                producer: graphTestProducer,
                recordedAt: deadline
            )
        )

        XCTAssertEqual(
            timedOut.projection.scheduling.timeouts,
            [decision]
        )
        XCTAssertEqual(
            timedOut.projection.scheduling.claims.first?.status,
            .expired
        )
        XCTAssertEqual(timedOut.projection.attempts.first?.state, .pending)

        let duplicate = try await owned.context.repository.recordTimeout(
            GraphTimeoutCommandRequest(
                decision: decision,
                expectedVersion: owned.version,
                producer: graphTestProducer,
                recordedAt: deadline
            )
        )
        XCTAssertEqual(duplicate.appendResult.appendedCount, 0)
    }

    func testEveryTimeoutCategoryIsRecordedAsAnExplicitDecision()
        async throws
    {
        let context = try await schedulingRepositoryContext()
        var expectedVersion: UInt64 = 2
        let kinds: [GraphTimeoutKind] = [
            .claimAcquisition,
            .attemptExecution,
            .cancellationAcknowledgement,
            .retryDelay,
        ]

        for (offset, kind) in kinds.enumerated() {
            let deadline = context.time.addingTimeInterval(
                Double(offset + 1)
            )
            let result = try await context.repository.recordTimeout(
                GraphTimeoutCommandRequest(
                    decision: GraphTimeoutDecision(
                        timeoutID: "timeout-\(kind.rawValue)",
                        runID: context.runID,
                        nodeID: "architect",
                        attemptID: nil,
                        claimID: nil,
                        kind: kind,
                        deadline: deadline,
                        declaredAt: deadline,
                        reason: .timeoutRecorded
                    ),
                    expectedVersion: expectedVersion,
                    producer: graphTestProducer,
                    recordedAt: deadline
                )
            )
            expectedVersion = result.appendResult.newVersion
        }

        let stream = try await context.store.read(
            runID: context.runID,
            afterVersion: 0
        )
        let projection = try GraphExecutionProjector.replay(
            runID: context.runID,
            events: stream.events
        ).projection
        XCTAssertEqual(
            Set(projection.scheduling.timeouts.map(\.kind)),
            Set(kinds)
        )
    }

    func testCancellationAfterProcessExitBeforeTerminalEventIsAccepted()
        async throws
    {
        let owned = try await claimedContext(leaseDuration: 30)
        let identity = ProcessIdentity(
            hostID: "host-worker-a",
            launchID: "launch-after-claim",
            processID: 551,
            startedAt: owned.context.time.addingTimeInterval(2)
        )
        let facts = [
            GraphExecutionEventEnvelope(
                id: "attempt-starting-before-cancel",
                runID: owned.context.runID,
                nodeID: "architect",
                attemptID: owned.attemptID,
                streamSequence: owned.version + 1,
                occurredAt: owned.context.time.addingTimeInterval(2),
                recordedAt: owned.context.time.addingTimeInterval(2),
                producer: graphTestProducer,
                payload: .attemptStarting(GraphAttemptStartingPayload())
            ),
            GraphExecutionEventEnvelope(
                id: "process-observed-before-cancel",
                runID: owned.context.runID,
                nodeID: "architect",
                attemptID: owned.attemptID,
                streamSequence: owned.version + 2,
                occurredAt: owned.context.time.addingTimeInterval(3),
                recordedAt: owned.context.time.addingTimeInterval(3),
                producer: graphTestProducer,
                payload: .processIdentityObserved(
                    GraphProcessIdentityObservedPayload(
                        processIdentity: identity
                    )
                )
            ),
            GraphExecutionEventEnvelope(
                id: "process-exit-before-cancel",
                runID: owned.context.runID,
                nodeID: "architect",
                attemptID: owned.attemptID,
                streamSequence: owned.version + 3,
                occurredAt: owned.context.time.addingTimeInterval(4),
                recordedAt: owned.context.time.addingTimeInterval(4),
                producer: graphTestProducer,
                payload: .processExitObserved(
                    GraphProcessExitObservedPayload(
                        processIdentity: identity,
                        exitCode: 143,
                        reason: "owner exited before terminal declaration"
                    )
                )
            ),
        ]
        let appended = try await owned.context.store.append(
            facts,
            to: owned.context.runID,
            expectedVersion: owned.version
        )
        let cancelled = try await owned.context.repository
            .requestCancellation(
                GraphCancellationCommandRequest(
                    runID: owned.context.runID,
                    nodeID: "architect",
                    attemptID: owned.attemptID,
                    requestID: "cancel-after-process-exit",
                    requestedBy: "operator",
                    expectedVersion: appended.newVersion,
                    logicalTime: owned.context.time.addingTimeInterval(5),
                    producer: graphTestProducer,
                    recordedAt: owned.context.time.addingTimeInterval(5)
                )
            )

        XCTAssertEqual(
            cancelled.projection.scheduling.cancellations.first?.state,
            .requested
        )
        XCTAssertEqual(
            cancelled.projection.attempts.first?.state,
            .running
        )
    }

    func testRetryDecisionCreatesStrictlyMonotonicAttemptOrdinal()
        async throws
    {
        let owned = try await claimedContext(leaseDuration: 30)
        let released = try await owned.context.repository.releaseClaim(
            GraphExecutorClaimReleaseRequest(
                runID: owned.context.runID,
                claimID: owned.claim.id,
                executorID: owned.claim.executorID,
                expectedGeneration: 1,
                expectedVersion: owned.version,
                logicalTime: owned.context.time.addingTimeInterval(1),
                producer: graphTestProducer,
                recordedAt: owned.context.time.addingTimeInterval(1)
            )
        )
        let failure = GraphExecutionEventEnvelope(
            id: "attempt-one-failed",
            runID: owned.context.runID,
            nodeID: "architect",
            attemptID: owned.attemptID,
            streamSequence: released.appendResult.newVersion + 1,
            occurredAt: owned.context.time.addingTimeInterval(2),
            recordedAt: owned.context.time.addingTimeInterval(2),
            producer: graphTestProducer,
            payload: .attemptFailed(
                GraphAttemptTerminalPayload(reason: "transient")
            )
        )
        _ = try await owned.context.store.append(
            [failure],
            to: owned.context.runID,
            expectedVersion: released.appendResult.newVersion
        )
        let failedVersion = failure.streamSequence
        let retryEvaluation = try await owned.context.repository
            .evaluateAndAppend(
                GraphSchedulerEvaluationRequest(
                    runID: owned.context.runID,
                    expectedVersion: failedVersion,
                    definition: owned.context.definition,
                    policy: owned.context.policy,
                    logicalTime: owned.context.time.addingTimeInterval(3),
                    availableExecutors: [owned.executor],
                    failureCategoriesByAttemptID: [
                        owned.attemptID: "transient",
                    ],
                    producer: graphTestProducer,
                    recordedAt: owned.context.time.addingTimeInterval(3)
                )
            )
        let evaluationID = try XCTUnwrap(
            retryEvaluation.projection.scheduling
                .completedEvaluationIDs.last
        )
        let retryClaim = try await owned.context.repository.attemptClaim(
            GraphExecutorClaimRequest(
                runID: owned.context.runID,
                nodeID: "architect",
                claimID: "claim-retry",
                executor: owned.executor,
                evaluationID: evaluationID,
                expectedVersion: retryEvaluation.appendResult.newVersion,
                logicalTime: owned.context.time.addingTimeInterval(3),
                leaseDurationSeconds: 30,
                producer: graphTestProducer,
                recordedAt: owned.context.time.addingTimeInterval(3)
            )
        )

        XCTAssertEqual(retryClaim.claim?.attemptOrdinal, 2)
        let stream = try await owned.context.store.read(
            runID: owned.context.runID,
            afterVersion: 0
        )
        let projection = try GraphExecutionProjector.replay(
            runID: owned.context.runID,
            events: stream.events
        ).projection
        XCTAssertEqual(projection.attempts.map(\.ordinal), [1, 2])
        XCTAssertEqual(
            projection.scheduling.retries.map(\.nextAttemptOrdinal),
            [2]
        )
    }
}

private struct ClaimedSchedulingContext {
    let context: SchedulingRepositoryContext
    let claim: GraphExecutorClaim
    let attemptID: String
    let version: UInt64
    let executor: GraphExecutorCapabilities
}

private func claimedContext(
    leaseDuration: UInt64
) async throws -> ClaimedSchedulingContext {
    let context = try await schedulingRepositoryContext()
    let executor = GraphExecutorCapabilities(
        executorID: "worker-a",
        capabilityIdentity: "research-worker",
        capabilities: ["research-planning"],
        hostID: "host-worker-a"
    )
    let evaluation = try await context.repository.evaluateAndAppend(
        context.evaluationRequest(expectedVersion: 2)
    )
    let evaluationID = try XCTUnwrap(
        evaluation.projection.scheduling.completedEvaluationIDs.first
    )
    let claimed = try await context.repository.attemptClaim(
        context.claimRequest(
            claimID: "claim-a",
            evaluationID: evaluationID,
            expectedVersion: evaluation.appendResult.newVersion,
            executorID: executor.executorID,
            leaseDurationSeconds: leaseDuration
        )
    )
    let claim = try XCTUnwrap(claimed.claim)
    let stream = try await context.store.read(
        runID: context.runID,
        afterVersion: 0
    )
    let projection = try GraphExecutionProjector.replay(
        runID: context.runID,
        events: stream.events
    ).projection
    return ClaimedSchedulingContext(
        context: context,
        claim: claim,
        attemptID: try XCTUnwrap(projection.attempts.first?.id),
        version: claimed.appendResult.newVersion,
        executor: executor
    )
}
