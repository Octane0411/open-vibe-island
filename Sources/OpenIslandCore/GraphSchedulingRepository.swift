import Foundation

public enum GraphSchedulingConflictReason:
    String,
    Codable,
    Sendable
{
    case expectedVersionConflict = "expected_version_conflict"
    case graphDefinitionMismatch = "graph_definition_mismatch"
    case schedulerEvaluationMissing = "scheduler_evaluation_missing"
    case nodeNotClaimable = "node_not_claimable"
    case existingActiveClaim = "existing_active_claim"
    case claimIdentityCollision = "claim_identity_collision"
    case executorCapabilityUnavailable =
        "executor_capability_unavailable"
    case leaseGenerationMismatch = "lease_generation_mismatch"
    case leaseExpired = "lease_expired"
    case claimNotFound = "claim_not_found"
    case claimAlreadyReleased = "claim_already_released"
    case cancellationPending = "cancellation_pending"
    case cancellationNotFound = "cancellation_not_found"
    case cancellationAlreadyAcknowledged =
        "cancellation_already_acknowledged"
    case staleCancellationAcknowledgement =
        "stale_cancellation_acknowledgement"
    case retryBackoffActive = "retry_backoff_active"
    case retryExhausted = "retry_exhausted"
    case runTerminal = "run_terminal"
    case attemptTerminal = "attempt_terminal"
    case invalidRequest = "invalid_request"
}

public enum GraphSchedulingRepositoryError:
    Error,
    Equatable,
    Sendable
{
    case conflict(
        reason: GraphSchedulingConflictReason,
        message: String,
        expectedVersion: UInt64?,
        actualVersion: UInt64?
    )
    case corruptHistory(String)
    case persistence(String)
}

extension GraphSchedulingRepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .conflict(reason, message, expected, actual):
            let versions = expected.map { expected in
                " expected=\(expected) actual=\(actual.map(String.init) ?? "unknown")"
            } ?? ""
            return "Scheduling conflict \(reason.rawValue): \(message)\(versions)"
        case let .corruptHistory(message):
            return "Scheduling history is corrupt: \(message)"
        case let .persistence(message):
            return "Scheduling persistence failed: \(message)"
        }
    }
}

public struct GraphSchedulerEvaluationRequest: Equatable, Sendable {
    public let runID: String
    public let expectedVersion: UInt64
    public let definition: GraphSchedulingDefinition
    public let policy: GraphSchedulerPolicy
    public let logicalTime: Date
    public let availableExecutors: [GraphExecutorCapabilities]
    public let failureCategoriesByAttemptID: [String: String]
    public let producer: GraphExecutionProducer
    public let recordedAt: Date

    public init(
        runID: String,
        expectedVersion: UInt64,
        definition: GraphSchedulingDefinition,
        policy: GraphSchedulerPolicy,
        logicalTime: Date,
        availableExecutors: [GraphExecutorCapabilities],
        failureCategoriesByAttemptID: [String: String] = [:],
        producer: GraphExecutionProducer,
        recordedAt: Date
    ) {
        self.runID = runID
        self.expectedVersion = expectedVersion
        self.definition = definition
        self.policy = policy
        self.logicalTime = logicalTime
        self.availableExecutors = availableExecutors
        self.failureCategoriesByAttemptID = failureCategoriesByAttemptID
        self.producer = producer
        self.recordedAt = recordedAt
    }
}

public struct GraphExecutorClaimRequest: Equatable, Sendable {
    public let runID: String
    public let nodeID: String
    public let claimID: String
    public let executor: GraphExecutorCapabilities
    public let evaluationID: String
    public let expectedVersion: UInt64
    public let logicalTime: Date
    public let leaseDurationSeconds: UInt64
    public let producer: GraphExecutionProducer
    public let recordedAt: Date

    public init(
        runID: String,
        nodeID: String,
        claimID: String,
        executor: GraphExecutorCapabilities,
        evaluationID: String,
        expectedVersion: UInt64,
        logicalTime: Date,
        leaseDurationSeconds: UInt64,
        producer: GraphExecutionProducer,
        recordedAt: Date
    ) {
        self.runID = runID
        self.nodeID = nodeID
        self.claimID = claimID
        self.executor = executor
        self.evaluationID = evaluationID
        self.expectedVersion = expectedVersion
        self.logicalTime = logicalTime
        self.leaseDurationSeconds = max(1, leaseDurationSeconds)
        self.producer = producer
        self.recordedAt = recordedAt
    }
}

public enum GraphExecutorClaimOutcome: String, Codable, Sendable {
    case granted
    case rejected
    case deduplicated
}

public struct GraphExecutorClaimResult: Equatable, Sendable {
    public let outcome: GraphExecutorClaimOutcome
    public let claim: GraphExecutorClaim?
    public let conflictingClaimID: String?
    public let appendResult: GraphExecutionAppendResult
    public let conflictReason: GraphSchedulingConflictReason?
}

public struct GraphExecutorLeaseRenewalRequest: Equatable, Sendable {
    public let runID: String
    public let claimID: String
    public let executorID: String
    public let expectedGeneration: UInt64
    public let expectedVersion: UInt64
    public let logicalTime: Date
    public let leaseDurationSeconds: UInt64
    public let producer: GraphExecutionProducer
    public let recordedAt: Date

    public init(
        runID: String,
        claimID: String,
        executorID: String,
        expectedGeneration: UInt64,
        expectedVersion: UInt64,
        logicalTime: Date,
        leaseDurationSeconds: UInt64,
        producer: GraphExecutionProducer,
        recordedAt: Date
    ) {
        self.runID = runID
        self.claimID = claimID
        self.executorID = executorID
        self.expectedGeneration = expectedGeneration
        self.expectedVersion = expectedVersion
        self.logicalTime = logicalTime
        self.leaseDurationSeconds = max(1, leaseDurationSeconds)
        self.producer = producer
        self.recordedAt = recordedAt
    }
}

public struct GraphExecutorClaimReleaseRequest: Equatable, Sendable {
    public let runID: String
    public let claimID: String
    public let executorID: String
    public let expectedGeneration: UInt64
    public let expectedVersion: UInt64
    public let logicalTime: Date
    public let producer: GraphExecutionProducer
    public let recordedAt: Date

    public init(
        runID: String,
        claimID: String,
        executorID: String,
        expectedGeneration: UInt64,
        expectedVersion: UInt64,
        logicalTime: Date,
        producer: GraphExecutionProducer,
        recordedAt: Date
    ) {
        self.runID = runID
        self.claimID = claimID
        self.executorID = executorID
        self.expectedGeneration = expectedGeneration
        self.expectedVersion = expectedVersion
        self.logicalTime = logicalTime
        self.producer = producer
        self.recordedAt = recordedAt
    }
}

public struct GraphCancellationCommandRequest: Equatable, Sendable {
    public let runID: String
    public let nodeID: String
    public let attemptID: String?
    public let requestID: String
    public let requestedBy: String
    public let reason: String?
    public let expectedVersion: UInt64
    public let logicalTime: Date
    public let producer: GraphExecutionProducer
    public let recordedAt: Date

    public init(
        runID: String,
        nodeID: String,
        attemptID: String? = nil,
        requestID: String,
        requestedBy: String,
        reason: String? = nil,
        expectedVersion: UInt64,
        logicalTime: Date,
        producer: GraphExecutionProducer,
        recordedAt: Date
    ) {
        self.runID = runID
        self.nodeID = nodeID
        self.attemptID = attemptID
        self.requestID = requestID
        self.requestedBy = requestedBy
        self.reason = reason
        self.expectedVersion = expectedVersion
        self.logicalTime = logicalTime
        self.producer = producer
        self.recordedAt = recordedAt
    }
}

public struct GraphCancellationAcknowledgementRequest:
    Equatable,
    Sendable
{
    public let runID: String
    public let requestID: String
    public let claimID: String?
    public let executorID: String
    public let expectedVersion: UInt64
    public let logicalTime: Date
    public let producer: GraphExecutionProducer
    public let recordedAt: Date

    public init(
        runID: String,
        requestID: String,
        claimID: String?,
        executorID: String,
        expectedVersion: UInt64,
        logicalTime: Date,
        producer: GraphExecutionProducer,
        recordedAt: Date
    ) {
        self.runID = runID
        self.requestID = requestID
        self.claimID = claimID
        self.executorID = executorID
        self.expectedVersion = expectedVersion
        self.logicalTime = logicalTime
        self.producer = producer
        self.recordedAt = recordedAt
    }
}

public struct GraphCancellationTerminalRequest: Equatable, Sendable {
    public let runID: String
    public let requestID: String
    public let expectedVersion: UInt64
    public let logicalTime: Date
    public let reason: String?
    public let producer: GraphExecutionProducer
    public let recordedAt: Date

    public init(
        runID: String,
        requestID: String,
        expectedVersion: UInt64,
        logicalTime: Date,
        reason: String? = nil,
        producer: GraphExecutionProducer,
        recordedAt: Date
    ) {
        self.runID = runID
        self.requestID = requestID
        self.expectedVersion = expectedVersion
        self.logicalTime = logicalTime
        self.reason = reason
        self.producer = producer
        self.recordedAt = recordedAt
    }
}

public struct GraphTimeoutCommandRequest: Equatable, Sendable {
    public let decision: GraphTimeoutDecision
    public let expectedVersion: UInt64
    public let producer: GraphExecutionProducer
    public let recordedAt: Date

    public init(
        decision: GraphTimeoutDecision,
        expectedVersion: UInt64,
        producer: GraphExecutionProducer,
        recordedAt: Date
    ) {
        self.decision = decision
        self.expectedVersion = expectedVersion
        self.producer = producer
        self.recordedAt = recordedAt
    }
}

public struct GraphSchedulingTransactionResult: Equatable, Sendable {
    public let appendResult: GraphExecutionAppendResult
    public let projection: GraphExecutionProjection
}

public protocol GraphSchedulingRepository: Sendable {
    func evaluateAndAppend(
        _ request: GraphSchedulerEvaluationRequest
    ) async throws -> GraphSchedulingTransactionResult

    func attemptClaim(
        _ request: GraphExecutorClaimRequest
    ) async throws -> GraphExecutorClaimResult

    func renewLease(
        _ request: GraphExecutorLeaseRenewalRequest
    ) async throws -> GraphSchedulingTransactionResult

    func releaseClaim(
        _ request: GraphExecutorClaimReleaseRequest
    ) async throws -> GraphSchedulingTransactionResult

    func requestCancellation(
        _ request: GraphCancellationCommandRequest
    ) async throws -> GraphSchedulingTransactionResult

    func acknowledgeCancellation(
        _ request: GraphCancellationAcknowledgementRequest
    ) async throws -> GraphSchedulingTransactionResult

    func declareCancellationTerminal(
        _ request: GraphCancellationTerminalRequest
    ) async throws -> GraphSchedulingTransactionResult

    func recordTimeout(
        _ request: GraphTimeoutCommandRequest
    ) async throws -> GraphSchedulingTransactionResult
}

public struct DefaultGraphSchedulingRepository:
    GraphSchedulingRepository,
    Sendable
{
    private let eventStore: any GraphExecutionEventStore

    public init(eventStore: any GraphExecutionEventStore) {
        self.eventStore = eventStore
    }

    public func evaluateAndAppend(
        _ request: GraphSchedulerEvaluationRequest
    ) async throws -> GraphSchedulingTransactionResult {
        let loaded = try await load(runID: request.runID)
        try requireVersion(
            request.expectedVersion,
            actual: loaded.stream.currentVersion,
            runID: request.runID
        )
        guard let reconciled = GraphExecutionProjectionReconciler.reconcile(
            projection: loaded.projection,
            evidenceOutcome: .available(GraphProcessEvidence()),
            observedAt: request.logicalTime
        ) else {
            throw GraphSchedulingRepositoryError.corruptHistory(
                "Run \(request.runID) has no run projection."
            )
        }
        let decision = GraphScheduler.evaluate(
            GraphSchedulingInput(
                definition: request.definition,
                projectedState: loaded.projection,
                reconciledState: reconciled,
                policy: request.policy,
                logicalTime: request.logicalTime,
                availableExecutors: request.availableExecutors,
                failureCategoriesByAttemptID:
                    request.failureCategoriesByAttemptID
            )
        )
        guard !decision.proposedEvents.isEmpty else {
            return GraphSchedulingTransactionResult(
                appendResult: GraphExecutionAppendResult(
                    previousVersion: loaded.stream.currentVersion,
                    newVersion: loaded.stream.currentVersion,
                    appendedCount: 0,
                    deduplicatedCount: 0
                ),
                projection: loaded.projection
            )
        }
        let envelopes = envelopes(
            proposals: decision.proposedEvents,
            runID: request.runID,
            startingAfter: loaded.stream.currentVersion,
            producer: request.producer,
            recordedAt: request.recordedAt,
            correlationID: decision.evaluationID
        )
        let append = try await append(
            envelopes,
            runID: request.runID,
            expectedVersion: request.expectedVersion
        )
        return GraphSchedulingTransactionResult(
            appendResult: append,
            projection: try replay(
                runID: request.runID,
                events: loaded.stream.events + envelopes
            )
        )
    }

    public func attemptClaim(
        _ request: GraphExecutorClaimRequest
    ) async throws -> GraphExecutorClaimResult {
        let loaded = try await load(runID: request.runID)

        if let existing = loaded.projection.scheduling.claims.first(
            where: { $0.claim.id == request.claimID }
        ) {
            guard existing.claim.executorID == request.executor.executorID,
                  existing.claim.nodeID == request.nodeID else {
                throw conflict(
                    .claimIdentityCollision,
                    "Claim ID \(request.claimID) is already associated with another owner.",
                    expected: request.expectedVersion,
                    actual: loaded.stream.currentVersion
                )
            }
            return GraphExecutorClaimResult(
                outcome: .deduplicated,
                claim: existing.claim,
                conflictingClaimID: nil,
                appendResult: GraphExecutionAppendResult(
                    previousVersion: loaded.stream.currentVersion,
                    newVersion: loaded.stream.currentVersion,
                    appendedCount: 0,
                    deduplicatedCount: 1
                ),
                conflictReason: nil
            )
        }

        try requireVersion(
            request.expectedVersion,
            actual: loaded.stream.currentVersion,
            runID: request.runID
        )
        guard loaded.projection.run?.state.isTerminal != true else {
            throw conflict(
                .runTerminal,
                "Terminal runs cannot grant executor claims."
            )
        }
        guard loaded.projection.scheduling.pendingCancellation(
            nodeID: request.nodeID
        ) == nil else {
            throw conflict(
                .cancellationPending,
                "Node \(request.nodeID) has a pending cancellation."
            )
        }
        guard let runnable = loaded.projection.scheduling.records.last(
            where: {
                $0.nodeID == request.nodeID
                    && $0.evaluationID == request.evaluationID
                    && $0.eventType
                        == GraphExecutionEventType
                            .nodeBecameRunnable.rawValue
            }
        ), runnable.reason == .dependenciesSatisfied else {
            throw conflict(
                .schedulerEvaluationMissing,
                "No matching runnable decision exists for node \(request.nodeID)."
            )
        }
        guard let evaluation = loaded.projection.scheduling.evaluations
            .first(where: {
                $0.evaluationID == request.evaluationID
            }),
            evaluation.availableCapabilityIdentities.contains(
                request.executor.capabilityIdentity
            ) else {
            throw conflict(
                .executorCapabilityUnavailable,
                "Executor capability \(request.executor.capabilityIdentity) was not available for the scheduler evaluation."
            )
        }

        let latestAttempt = loaded.projection.attempts
            .filter { $0.nodeID == request.nodeID }
            .max { $0.ordinal < $1.ordinal }
        let attemptOrdinal: Int
        let attemptID: String
        let createAttempt: Bool

        if let latestAttempt, !latestAttempt.state.isTerminal {
            attemptOrdinal = latestAttempt.ordinal
            attemptID = latestAttempt.id
            createAttempt = false
        } else if let latestAttempt {
            let next = latestAttempt.ordinal + 1
            guard let retry = loaded.projection.scheduling.retries.first(
                where: {
                    $0.nodeID == request.nodeID
                        && $0.nextAttemptOrdinal == next
                }
            ) else {
                throw conflict(
                    .attemptTerminal,
                    "Terminal attempt \(latestAttempt.id) has no durable retry decision."
                )
            }
            guard request.logicalTime >= retry.eligibleAt else {
                throw conflict(
                    .retryBackoffActive,
                    "Retry is not eligible until \(retry.eligibleAt)."
                )
            }
            attemptOrdinal = next
            attemptID = stableAttemptID(
                runID: request.runID,
                nodeID: request.nodeID,
                ordinal: next
            )
            createAttempt = true
        } else {
            attemptOrdinal = 1
            attemptID = stableAttemptID(
                runID: request.runID,
                nodeID: request.nodeID,
                ordinal: 1
            )
            createAttempt = true
        }

        var prefix: [GraphExecutionEventEnvelope] = []
        var nextSequence = loaded.stream.currentVersion + 1

        for record in loaded.projection.scheduling.claims
            where record.claim.nodeID == request.nodeID
                && record.claim.attemptOrdinal == attemptOrdinal
                && record.status == .active {
            if record.claim.isValid(at: request.logicalTime) {
                return try await rejectClaim(
                    request,
                    attemptOrdinal: attemptOrdinal,
                    attemptID: attemptID,
                    conflictingClaimID: record.claim.id,
                    loaded: loaded
                )
            }
            prefix.append(
                envelope(
                    id: "claim-expired-\(record.claim.id)-\(record.claim.leaseGeneration)",
                    runID: request.runID,
                    nodeID: request.nodeID,
                    attemptID: attemptID,
                    sequence: nextSequence,
                    occurredAt: request.logicalTime,
                    recordedAt: request.recordedAt,
                    producer: request.producer,
                    correlationID: request.claimID,
                    payload: .executorLeaseExpired(
                        GraphExecutorLeaseEndedPayload(
                            claimID: record.claim.id,
                            leaseGeneration:
                                record.claim.leaseGeneration,
                            reason: .leaseExpired
                        )
                    )
                )
            )
            nextSequence += 1
        }

        if createAttempt {
            prefix.append(
                envelope(
                    id: attemptID,
                    runID: request.runID,
                    nodeID: request.nodeID,
                    attemptID: attemptID,
                    sequence: nextSequence,
                    occurredAt: request.logicalTime,
                    recordedAt: request.recordedAt,
                    producer: request.producer,
                    correlationID: attemptID,
                    payload: .attemptCreated(
                        GraphAttemptCreatedPayload(
                            ordinal: attemptOrdinal,
                            executorID: nil
                        )
                    )
                )
            )
            nextSequence += 1
        }

        let grantedSequence = nextSequence + 1
        let claim = GraphExecutorClaim(
            runID: request.runID,
            nodeID: request.nodeID,
            attemptOrdinal: attemptOrdinal,
            claimID: request.claimID,
            executorID: request.executor.executorID,
            executorCapabilityIdentity:
                request.executor.capabilityIdentity,
            grantedSequence: grantedSequence,
            leaseStart: request.logicalTime,
            leaseExpiry: request.logicalTime.addingTimeInterval(
                TimeInterval(request.leaseDurationSeconds)
            ),
            hostID: request.executor.hostID
        )
        let payload = GraphExecutorClaimPayload(
            claim: claim,
            reason: .claimGranted
        )
        prefix.append(
            envelope(
                id: "claim-request-\(request.claimID)",
                runID: request.runID,
                nodeID: request.nodeID,
                attemptID: attemptID,
                sequence: nextSequence,
                occurredAt: request.logicalTime,
                recordedAt: request.recordedAt,
                producer: request.producer,
                correlationID: request.claimID,
                payload: .executorClaimRequested(payload)
            )
        )
        prefix.append(
            envelope(
                id: "claim-grant-\(request.claimID)",
                runID: request.runID,
                nodeID: request.nodeID,
                attemptID: attemptID,
                sequence: grantedSequence,
                occurredAt: request.logicalTime,
                recordedAt: request.recordedAt,
                producer: request.producer,
                correlationID: request.claimID,
                payload: .executorClaimGranted(payload)
            )
        )
        let append = try await append(
            prefix,
            runID: request.runID,
            expectedVersion: request.expectedVersion
        )
        return GraphExecutorClaimResult(
            outcome: .granted,
            claim: claim,
            conflictingClaimID: nil,
            appendResult: append,
            conflictReason: nil
        )
    }

    public func renewLease(
        _ request: GraphExecutorLeaseRenewalRequest
    ) async throws -> GraphSchedulingTransactionResult {
        let loaded = try await load(runID: request.runID)
        guard let currentRecord = loaded.projection.scheduling.claims
            .first(where: { $0.claim.id == request.claimID }) else {
            throw conflict(
                .claimNotFound,
                "Claim \(request.claimID) does not exist."
            )
        }
        let current = currentRecord.claim
        let targetGeneration = request.expectedGeneration + 1
        let targetExpiry = request.logicalTime.addingTimeInterval(
            TimeInterval(request.leaseDurationSeconds)
        )

        if current.leaseGeneration == targetGeneration,
           current.executorID == request.executorID,
           current.leaseStart == request.logicalTime,
           current.leaseExpiry == targetExpiry {
            return unchanged(loaded)
        }
        try requireVersion(
            request.expectedVersion,
            actual: loaded.stream.currentVersion,
            runID: request.runID
        )
        guard currentRecord.status == .active,
              current.executorID == request.executorID else {
            throw conflict(
                .claimAlreadyReleased,
                "Claim \(request.claimID) is not owned by the requester."
            )
        }
        guard current.leaseGeneration == request.expectedGeneration else {
            throw conflict(
                .leaseGenerationMismatch,
                "Lease generation does not match current ownership."
            )
        }
        guard request.logicalTime < current.leaseExpiry else {
            throw conflict(
                .leaseExpired,
                "Expired leases cannot be renewed."
            )
        }
        let renewed = GraphExecutorClaim(
            runID: current.runID,
            nodeID: current.nodeID,
            attemptOrdinal: current.attemptOrdinal,
            claimID: current.id,
            executorID: current.executorID,
            executorCapabilityIdentity:
                current.executorCapabilityIdentity,
            grantedSequence: current.grantedSequence,
            leaseStart: request.logicalTime,
            leaseExpiry: targetExpiry,
            leaseGeneration: targetGeneration,
            hostID: current.hostID
        )
        let event = envelope(
            id: "lease-renew-\(current.id)-\(targetGeneration)",
            runID: request.runID,
            nodeID: current.nodeID,
            attemptID: attemptID(
                nodeID: current.nodeID,
                ordinal: current.attemptOrdinal,
                projection: loaded.projection
            ),
            sequence: loaded.stream.currentVersion + 1,
            occurredAt: request.logicalTime,
            recordedAt: request.recordedAt,
            producer: request.producer,
            correlationID: current.id,
            payload: .executorLeaseRenewed(
                GraphExecutorClaimPayload(
                    claim: renewed,
                    reason: .leaseRenewed
                )
            )
        )
        return try await appendTransaction(
            [event],
            loaded: loaded,
            expectedVersion: request.expectedVersion
        )
    }

    public func releaseClaim(
        _ request: GraphExecutorClaimReleaseRequest
    ) async throws -> GraphSchedulingTransactionResult {
        let loaded = try await load(runID: request.runID)
        guard let record = loaded.projection.scheduling.claims.first(
            where: { $0.claim.id == request.claimID }
        ) else {
            throw conflict(
                .claimNotFound,
                "Claim \(request.claimID) does not exist."
            )
        }
        if record.status == .released {
            return unchanged(loaded)
        }
        try requireVersion(
            request.expectedVersion,
            actual: loaded.stream.currentVersion,
            runID: request.runID
        )
        guard record.status == .active,
              record.claim.executorID == request.executorID else {
            throw conflict(
                .claimAlreadyReleased,
                "Claim \(request.claimID) is not active for this owner."
            )
        }
        guard record.claim.leaseGeneration
                == request.expectedGeneration else {
            throw conflict(
                .leaseGenerationMismatch,
                "Lease generation does not match current ownership."
            )
        }
        let event = envelope(
            id: "claim-release-\(record.claim.id)-\(record.claim.leaseGeneration)",
            runID: request.runID,
            nodeID: record.claim.nodeID,
            attemptID: attemptID(
                nodeID: record.claim.nodeID,
                ordinal: record.claim.attemptOrdinal,
                projection: loaded.projection
            ),
            sequence: loaded.stream.currentVersion + 1,
            occurredAt: request.logicalTime,
            recordedAt: request.recordedAt,
            producer: request.producer,
            correlationID: record.claim.id,
            payload: .executorClaimReleased(
                GraphExecutorLeaseEndedPayload(
                    claimID: record.claim.id,
                    leaseGeneration: record.claim.leaseGeneration,
                    reason: .claimReleased
                )
            )
        )
        return try await appendTransaction(
            [event],
            loaded: loaded,
            expectedVersion: request.expectedVersion
        )
    }

    public func requestCancellation(
        _ request: GraphCancellationCommandRequest
    ) async throws -> GraphSchedulingTransactionResult {
        let loaded = try await load(runID: request.runID)
        if let existing = loaded.projection.scheduling.cancellations
            .first(where: { $0.id == request.requestID }) {
            guard existing.runID == request.runID,
                  existing.nodeID == request.nodeID,
                  (request.attemptID == nil
                    || existing.attemptID == request.attemptID),
                  existing.requestedBy == request.requestedBy,
                  existing.requestedAt == request.logicalTime,
                  existing.reason == request.reason else {
                throw conflict(
                    .invalidRequest,
                    "Cancellation ID \(request.requestID) has contradictory content."
                )
            }
            return unchanged(loaded)
        }
        try requireVersion(
            request.expectedVersion,
            actual: loaded.stream.currentVersion,
            runID: request.runID
        )
        guard loaded.projection.run?.state.isTerminal != true else {
            throw conflict(
                .runTerminal,
                "Terminal runs cannot be cancelled again."
            )
        }
        guard loaded.projection.nodes.contains(where: {
            $0.id == request.nodeID
        }) else {
            throw conflict(
                .invalidRequest,
                "Node \(request.nodeID) is not registered."
            )
        }
        let latestAttempt = loaded.projection.attempts
            .filter { $0.nodeID == request.nodeID }
            .max { $0.ordinal < $1.ordinal }
        if let requestAttemptID = request.attemptID,
           requestAttemptID != latestAttempt?.id {
            throw conflict(
                .invalidRequest,
                "Cancellation attempt does not match the latest node attempt."
            )
        }
        guard latestAttempt?.state.isTerminal != true else {
            throw conflict(
                .attemptTerminal,
                "A terminal attempt cannot receive a cancellation request."
            )
        }
        let claim = loaded.projection.scheduling.claims
            .filter {
                $0.claim.nodeID == request.nodeID
                    && $0.status == .active
            }
            .max {
                $0.claim.leaseGeneration < $1.claim.leaseGeneration
            }?.claim
        let cancellation = GraphCancellationRecord(
            requestID: request.requestID,
            runID: request.runID,
            nodeID: request.nodeID,
            attemptID: latestAttempt?.id,
            claimID: claim?.id,
            requestedBy: request.requestedBy,
            requestedAt: request.logicalTime,
            reason: request.reason
        )
        let event = envelope(
            id: "cancellation-request-\(request.requestID)",
            runID: request.runID,
            nodeID: request.nodeID,
            attemptID: latestAttempt?.id,
            sequence: loaded.stream.currentVersion + 1,
            occurredAt: request.logicalTime,
            recordedAt: request.recordedAt,
            producer: request.producer,
            correlationID: request.requestID,
            payload: .cancellationRequested(
                GraphCancellationRequestedPayload(
                    cancellation: cancellation
                )
            )
        )
        return try await appendTransaction(
            [event],
            loaded: loaded,
            expectedVersion: request.expectedVersion
        )
    }

    public func acknowledgeCancellation(
        _ request: GraphCancellationAcknowledgementRequest
    ) async throws -> GraphSchedulingTransactionResult {
        let loaded = try await load(runID: request.runID)
        guard let cancellation = loaded.projection.scheduling
            .cancellations.first(where: {
                $0.id == request.requestID
            }) else {
            throw conflict(
                .cancellationNotFound,
                "Cancellation \(request.requestID) does not exist."
            )
        }
        if cancellation.state == .acknowledged {
            guard cancellation.claimID == request.claimID,
                  cancellation.acknowledgedByExecutorID
                    == request.executorID,
                  cancellation.acknowledgedAt == request.logicalTime else {
                throw conflict(
                    .staleCancellationAcknowledgement,
                    "Cancellation was acknowledged by another owner."
                )
            }
            return unchanged(loaded)
        }
        try requireVersion(
            request.expectedVersion,
            actual: loaded.stream.currentVersion,
            runID: request.runID
        )
        guard let claimID = cancellation.claimID,
              claimID == request.claimID,
              let claimRecord = loaded.projection.scheduling.claims
                .first(where: { $0.claim.id == claimID }),
              claimRecord.status == .active,
              claimRecord.claim.executorID == request.executorID,
              claimRecord.claim.isValid(at: request.logicalTime) else {
            throw conflict(
                .staleCancellationAcknowledgement,
                "Only the current valid claim owner may acknowledge cancellation."
            )
        }
        let event = envelope(
            id: "cancellation-ack-\(request.requestID)",
            runID: request.runID,
            nodeID: cancellation.nodeID,
            attemptID: cancellation.attemptID,
            sequence: loaded.stream.currentVersion + 1,
            occurredAt: request.logicalTime,
            recordedAt: request.recordedAt,
            producer: request.producer,
            correlationID: request.requestID,
            payload: .cancellationAcknowledged(
                GraphCancellationAcknowledgedPayload(
                    requestID: request.requestID,
                    claimID: request.claimID,
                    executorID: request.executorID,
                    acknowledgedAt: request.logicalTime
                )
            )
        )
        return try await appendTransaction(
            [event],
            loaded: loaded,
            expectedVersion: request.expectedVersion
        )
    }

    public func declareCancellationTerminal(
        _ request: GraphCancellationTerminalRequest
    ) async throws -> GraphSchedulingTransactionResult {
        let loaded = try await load(runID: request.runID)
        if loaded.stream.events.contains(where: {
            $0.id == "cancellation-terminal-\(request.requestID)"
        }) {
            return unchanged(loaded)
        }
        guard let cancellation = loaded.projection.scheduling
            .cancellations.first(where: {
                $0.id == request.requestID
            }) else {
            throw conflict(
                .cancellationNotFound,
                "Cancellation \(request.requestID) does not exist."
            )
        }
        try requireVersion(
            request.expectedVersion,
            actual: loaded.stream.currentVersion,
            runID: request.runID
        )
        if cancellation.claimID != nil,
           cancellation.state != .acknowledged {
            throw conflict(
                .cancellationPending,
                "Claimed cancellation must be acknowledged before terminal declaration."
            )
        }
        var events: [GraphExecutionEventEnvelope] = []
        var sequence = loaded.stream.currentVersion + 1
        var attempt = cancellation.attemptID.flatMap { id in
            loaded.projection.attempts.first { $0.id == id }
        }

        if attempt == nil {
            let ordinal = (loaded.projection.attempts
                .filter { $0.nodeID == cancellation.nodeID }
                .map(\.ordinal)
                .max() ?? 0) + 1
            let id = stableAttemptID(
                runID: request.runID,
                nodeID: cancellation.nodeID,
                ordinal: ordinal
            )
            events.append(
                envelope(
                    id: id,
                    runID: request.runID,
                    nodeID: cancellation.nodeID,
                    attemptID: id,
                    sequence: sequence,
                    occurredAt: request.logicalTime,
                    recordedAt: request.recordedAt,
                    producer: request.producer,
                    correlationID: request.requestID,
                    payload: .attemptCreated(
                        GraphAttemptCreatedPayload(ordinal: ordinal)
                    )
                )
            )
            attempt = ExecutionAttempt(
                id: id,
                graphRunID: request.runID,
                nodeID: cancellation.nodeID,
                ordinal: ordinal,
                createdAt: request.logicalTime,
                updatedAt: request.logicalTime
            )
            sequence += 1
        }
        guard let terminalAttempt = attempt else {
            throw GraphSchedulingRepositoryError.corruptHistory(
                "Cancellation has no attempt."
            )
        }
        guard !terminalAttempt.state.isTerminal else {
            if terminalAttempt.state == .cancelled {
                return unchanged(loaded)
            }
            throw conflict(
                .attemptTerminal,
                "Attempt \(terminalAttempt.id) already has another terminal result."
            )
        }

        if let claimID = cancellation.claimID,
           let claim = loaded.projection.scheduling.claims.first(
                where: {
                    $0.claim.id == claimID && $0.status == .active
                }
           )?.claim {
            events.append(
                envelope(
                    id: "claim-release-\(claim.id)-\(claim.leaseGeneration)",
                    runID: request.runID,
                    nodeID: claim.nodeID,
                    attemptID: terminalAttempt.id,
                    sequence: sequence,
                    occurredAt: request.logicalTime,
                    recordedAt: request.recordedAt,
                    producer: request.producer,
                    correlationID: request.requestID,
                    payload: .executorClaimReleased(
                        GraphExecutorLeaseEndedPayload(
                            claimID: claim.id,
                            leaseGeneration: claim.leaseGeneration,
                            reason: .claimReleased
                        )
                    )
                )
            )
            sequence += 1
        }
        events.append(
            envelope(
                id: "cancellation-terminal-\(request.requestID)",
                runID: request.runID,
                nodeID: cancellation.nodeID,
                attemptID: terminalAttempt.id,
                sequence: sequence,
                occurredAt: request.logicalTime,
                recordedAt: request.recordedAt,
                producer: request.producer,
                correlationID: request.requestID,
                payload: .attemptCancelled(
                    GraphAttemptTerminalPayload(reason: request.reason)
                )
            )
        )
        return try await appendTransaction(
            events,
            loaded: loaded,
            expectedVersion: request.expectedVersion
        )
    }

    public func recordTimeout(
        _ request: GraphTimeoutCommandRequest
    ) async throws -> GraphSchedulingTransactionResult {
        let loaded = try await load(runID: request.decision.runID)
        if let existing = loaded.projection.scheduling.timeouts.first(
            where: { $0.id == request.decision.id }
        ) {
            guard existing == request.decision else {
                throw conflict(
                    .invalidRequest,
                    "Timeout ID \(request.decision.id) has contradictory content."
                )
            }
            return unchanged(loaded)
        }
        try requireVersion(
            request.expectedVersion,
            actual: loaded.stream.currentVersion,
            runID: request.decision.runID
        )
        guard request.decision.declaredAt >= request.decision.deadline else {
            throw conflict(
                .invalidRequest,
                "A timeout cannot be declared before its durable deadline."
            )
        }
        var events = [
            envelope(
                id: "timeout-\(request.decision.id)",
                runID: request.decision.runID,
                nodeID: request.decision.nodeID,
                attemptID: request.decision.attemptID,
                sequence: loaded.stream.currentVersion + 1,
                occurredAt: request.decision.declaredAt,
                recordedAt: request.recordedAt,
                producer: request.producer,
                correlationID: request.decision.id,
                payload: .timeoutDeclared(
                    GraphTimeoutDeclaredPayload(
                        timeout: request.decision
                    )
                )
            ),
        ]
        if request.decision.kind == .lease,
           let claimID = request.decision.claimID,
           let claim = loaded.projection.scheduling.claims.first(
                where: {
                    $0.claim.id == claimID && $0.status == .active
                }
           )?.claim {
            guard request.decision.declaredAt >= claim.leaseExpiry else {
                throw conflict(
                    .invalidRequest,
                    "Lease timeout precedes the current lease expiry."
                )
            }
            events.append(
                envelope(
                    id: "claim-expired-\(claim.id)-\(claim.leaseGeneration)",
                    runID: request.decision.runID,
                    nodeID: claim.nodeID,
                    attemptID: request.decision.attemptID,
                    sequence: loaded.stream.currentVersion + 2,
                    occurredAt: request.decision.declaredAt,
                    recordedAt: request.recordedAt,
                    producer: request.producer,
                    correlationID: request.decision.id,
                    payload: .executorLeaseExpired(
                        GraphExecutorLeaseEndedPayload(
                            claimID: claim.id,
                            leaseGeneration: claim.leaseGeneration,
                            reason: .leaseExpired
                        )
                    )
                )
            )
        }
        return try await appendTransaction(
            events,
            loaded: loaded,
            expectedVersion: request.expectedVersion
        )
    }

    private func rejectClaim(
        _ request: GraphExecutorClaimRequest,
        attemptOrdinal: Int,
        attemptID: String,
        conflictingClaimID: String,
        loaded: LoadedSchedulingHistory
    ) async throws -> GraphExecutorClaimResult {
        let placeholder = GraphExecutorClaim(
            runID: request.runID,
            nodeID: request.nodeID,
            attemptOrdinal: attemptOrdinal,
            claimID: request.claimID,
            executorID: request.executor.executorID,
            executorCapabilityIdentity:
                request.executor.capabilityIdentity,
            grantedSequence: 0,
            leaseStart: request.logicalTime,
            leaseExpiry: request.logicalTime,
            hostID: request.executor.hostID
        )
        let requestEvent = envelope(
            id: "claim-request-\(request.claimID)",
            runID: request.runID,
            nodeID: request.nodeID,
            attemptID: attemptID,
            sequence: loaded.stream.currentVersion + 1,
            occurredAt: request.logicalTime,
            recordedAt: request.recordedAt,
            producer: request.producer,
            correlationID: request.claimID,
            payload: .executorClaimRequested(
                GraphExecutorClaimPayload(
                    claim: placeholder,
                    reason: .claimRejected
                )
            )
        )
        let rejection = envelope(
            id: "claim-reject-\(request.claimID)",
            runID: request.runID,
            nodeID: request.nodeID,
            attemptID: attemptID,
            sequence: loaded.stream.currentVersion + 2,
            occurredAt: request.logicalTime,
            recordedAt: request.recordedAt,
            producer: request.producer,
            correlationID: request.claimID,
            payload: .executorClaimRejected(
                GraphExecutorClaimRejectedPayload(
                    claimID: request.claimID,
                    nodeID: request.nodeID,
                    attemptOrdinal: attemptOrdinal,
                    executorID: request.executor.executorID,
                    reason: .existingActiveClaim,
                    conflictingClaimID: conflictingClaimID
                )
            )
        )
        let append = try await append(
            [requestEvent, rejection],
            runID: request.runID,
            expectedVersion: request.expectedVersion
        )
        return GraphExecutorClaimResult(
            outcome: .rejected,
            claim: nil,
            conflictingClaimID: conflictingClaimID,
            appendResult: append,
            conflictReason: .existingActiveClaim
        )
    }

    private struct LoadedSchedulingHistory {
        let stream: GraphExecutionEventStream
        let projection: GraphExecutionProjection
    }

    private func load(
        runID: String
    ) async throws -> LoadedSchedulingHistory {
        do {
            let stream = try await eventStore.read(
                runID: runID,
                afterVersion: 0
            )
            return LoadedSchedulingHistory(
                stream: stream,
                projection: try replay(
                    runID: runID,
                    events: stream.events
                )
            )
        } catch let error as GraphExecutionReplayError {
            throw GraphSchedulingRepositoryError.corruptHistory(
                error.localizedDescription
            )
        } catch let error as GraphExecutionPersistenceError {
            throw mappedPersistence(error)
        } catch {
            throw GraphSchedulingRepositoryError.persistence(
                error.localizedDescription
            )
        }
    }

    private func appendTransaction(
        _ events: [GraphExecutionEventEnvelope],
        loaded: LoadedSchedulingHistory,
        expectedVersion: UInt64
    ) async throws -> GraphSchedulingTransactionResult {
        let appendResult = try await append(
            events,
            runID: loaded.stream.runID,
            expectedVersion: expectedVersion
        )
        return GraphSchedulingTransactionResult(
            appendResult: appendResult,
            projection: try replay(
                runID: loaded.stream.runID,
                events: loaded.stream.events + events
            )
        )
    }

    private func append(
        _ events: [GraphExecutionEventEnvelope],
        runID: String,
        expectedVersion: UInt64
    ) async throws -> GraphExecutionAppendResult {
        do {
            return try await eventStore.append(
                events,
                to: runID,
                expectedVersion: expectedVersion
            )
        } catch let error as GraphExecutionPersistenceError {
            throw mappedPersistence(error)
        } catch {
            throw GraphSchedulingRepositoryError.persistence(
                error.localizedDescription
            )
        }
    }

    private func replay(
        runID: String,
        events: [GraphExecutionEventEnvelope]
    ) throws -> GraphExecutionProjection {
        do {
            return try GraphExecutionProjector.replay(
                runID: runID,
                events: events
            ).projection
        } catch {
            throw GraphSchedulingRepositoryError.corruptHistory(
                error.localizedDescription
            )
        }
    }

    private func requireVersion(
        _ expected: UInt64,
        actual: UInt64,
        runID: String
    ) throws {
        guard expected == actual else {
            throw conflict(
                .expectedVersionConflict,
                "Run \(runID) changed concurrently.",
                expected: expected,
                actual: actual
            )
        }
    }

    private func mappedPersistence(
        _ error: GraphExecutionPersistenceError
    ) -> GraphSchedulingRepositoryError {
        if case let .expectedVersionConflict(_, expected, actual) = error {
            return conflict(
                .expectedVersionConflict,
                error.localizedDescription,
                expected: expected,
                actual: actual
            )
        }
        return .persistence(error.localizedDescription)
    }

    private func conflict(
        _ reason: GraphSchedulingConflictReason,
        _ message: String,
        expected: UInt64? = nil,
        actual: UInt64? = nil
    ) -> GraphSchedulingRepositoryError {
        .conflict(
            reason: reason,
            message: message,
            expectedVersion: expected,
            actualVersion: actual
        )
    }

    private func unchanged(
        _ loaded: LoadedSchedulingHistory
    ) -> GraphSchedulingTransactionResult {
        GraphSchedulingTransactionResult(
            appendResult: GraphExecutionAppendResult(
                previousVersion: loaded.stream.currentVersion,
                newVersion: loaded.stream.currentVersion,
                appendedCount: 0,
                deduplicatedCount: 1
            ),
            projection: loaded.projection
        )
    }

    private func envelopes(
        proposals: [GraphSchedulingProposedEvent],
        runID: String,
        startingAfter version: UInt64,
        producer: GraphExecutionProducer,
        recordedAt: Date,
        correlationID: String
    ) -> [GraphExecutionEventEnvelope] {
        proposals.enumerated().map { index, proposal in
            envelope(
                id: proposal.id,
                runID: runID,
                nodeID: proposal.nodeID,
                attemptID: proposal.attemptID,
                sequence: version + UInt64(index) + 1,
                occurredAt: proposal.occurredAt,
                recordedAt: recordedAt,
                producer: producer,
                correlationID: correlationID,
                payload: proposal.payload
            )
        }
    }

    private func envelope(
        id: String,
        runID: String,
        nodeID: String? = nil,
        attemptID: String? = nil,
        sequence: UInt64,
        occurredAt: Date,
        recordedAt: Date,
        producer: GraphExecutionProducer,
        correlationID: String,
        payload: GraphExecutionEventPayload
    ) -> GraphExecutionEventEnvelope {
        GraphExecutionEventEnvelope(
            id: id,
            runID: runID,
            nodeID: nodeID,
            attemptID: attemptID,
            streamSequence: sequence,
            occurredAt: occurredAt,
            recordedAt: recordedAt,
            producer: producer,
            correlationID: correlationID,
            payload: payload
        )
    }

    private func stableAttemptID(
        runID: String,
        nodeID: String,
        ordinal: Int
    ) -> String {
        "attempt-\(GraphScheduler.stableID("\(runID)|\(nodeID)|\(ordinal)"))"
    }

    private func attemptID(
        nodeID: String,
        ordinal: Int,
        projection: GraphExecutionProjection
    ) -> String? {
        projection.attempts.first {
            $0.nodeID == nodeID && $0.ordinal == ordinal
        }?.id
    }
}
