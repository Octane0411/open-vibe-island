import CryptoKit
import Foundation

public enum GraphSchedulingSchema {
    public static let definitionVersion = 1
    public static let policyVersion = 1
    public static let claimVersion = 1
    public static let cancellationVersion = 1
    public static let timeoutVersion = 1
}

public struct GraphSchedulingDefinitionNode:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public let title: String
    public let dependencyNodeIDs: [String]
    public let requiredCapabilities: [String]

    public init(
        id: String,
        title: String,
        dependencyNodeIDs: [String] = [],
        requiredCapabilities: [String] = []
    ) {
        self.id = id
        self.title = title
        self.dependencyNodeIDs = dependencyNodeIDs.sorted()
        self.requiredCapabilities = requiredCapabilities.sorted()
    }
}

public struct GraphSchedulingDefinition: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let graphID: String
    public let version: String
    public let digest: GraphContentDigest
    public let nodes: [GraphSchedulingDefinitionNode]

    public init(
        schemaVersion: Int = GraphSchedulingSchema.definitionVersion,
        graphID: String,
        version: String,
        digest: GraphContentDigest,
        nodes: [GraphSchedulingDefinitionNode]
    ) {
        self.schemaVersion = schemaVersion
        self.graphID = graphID
        self.version = version
        self.digest = digest
        self.nodes = nodes.sorted { $0.id < $1.id }
    }
}

public struct GraphExecutorCapabilities: Equatable, Codable, Sendable {
    public let executorID: String
    public let capabilityIdentity: String
    public let capabilities: [String]
    public let hostID: String?

    public init(
        executorID: String,
        capabilityIdentity: String,
        capabilities: [String],
        hostID: String? = nil
    ) {
        self.executorID = executorID
        self.capabilityIdentity = capabilityIdentity
        self.capabilities = capabilities.sorted()
        self.hostID = hostID
    }

    public func satisfies(_ required: [String]) -> Bool {
        Set(required).isSubset(of: Set(capabilities))
    }
}

public enum GraphRetryTimeoutBehavior: String, Codable, Sendable {
    case retry
    case suppress
}

public enum GraphRetryCancellationBehavior: String, Codable, Sendable {
    case suppress
    case retryAfterAcknowledgement = "retry_after_acknowledgement"
}

public enum GraphDependencyFailureBehavior: String, Codable, Sendable {
    case failClosed = "fail_closed"
    case allowIndependent = "allow_independent"
}

public struct GraphRetryPolicy: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let maximumAttempts: Int
    public let retryableFailureCategories: [String]
    public let nonRetryableFailureCategories: [String]
    public let initialBackoffSeconds: UInt64
    public let backoffMultiplier: UInt64
    public let maximumBackoffSeconds: UInt64
    public let jitterBasisPoints: UInt16
    public let jitterSeed: String
    public let timeoutBehavior: GraphRetryTimeoutBehavior
    public let cancellationBehavior: GraphRetryCancellationBehavior
    public let dependencyFailureBehavior: GraphDependencyFailureBehavior

    public init(
        schemaVersion: Int = GraphSchedulingSchema.policyVersion,
        maximumAttempts: Int,
        retryableFailureCategories: [String],
        nonRetryableFailureCategories: [String] = [],
        initialBackoffSeconds: UInt64 = 0,
        backoffMultiplier: UInt64 = 2,
        maximumBackoffSeconds: UInt64 = 3_600,
        jitterBasisPoints: UInt16 = 0,
        jitterSeed: String = "openisland",
        timeoutBehavior: GraphRetryTimeoutBehavior = .retry,
        cancellationBehavior: GraphRetryCancellationBehavior = .suppress,
        dependencyFailureBehavior: GraphDependencyFailureBehavior = .failClosed
    ) {
        self.schemaVersion = schemaVersion
        self.maximumAttempts = max(1, maximumAttempts)
        self.retryableFailureCategories = retryableFailureCategories.sorted()
        self.nonRetryableFailureCategories = nonRetryableFailureCategories.sorted()
        self.initialBackoffSeconds = initialBackoffSeconds
        self.backoffMultiplier = max(1, backoffMultiplier)
        self.maximumBackoffSeconds = max(
            initialBackoffSeconds,
            maximumBackoffSeconds
        )
        self.jitterBasisPoints = min(jitterBasisPoints, 10_000)
        self.jitterSeed = jitterSeed
        self.timeoutBehavior = timeoutBehavior
        self.cancellationBehavior = cancellationBehavior
        self.dependencyFailureBehavior = dependencyFailureBehavior
    }

    public func delaySeconds(
        runID: String,
        nodeID: String,
        nextAttemptOrdinal: Int
    ) -> UInt64 {
        let exponent = max(0, nextAttemptOrdinal - 2)
        var base = initialBackoffSeconds

        for _ in 0..<exponent {
            let multiplied = base.multipliedReportingOverflow(
                by: backoffMultiplier
            )
            base = multiplied.overflow
                ? maximumBackoffSeconds
                : min(multiplied.partialValue, maximumBackoffSeconds)
        }

        guard jitterBasisPoints > 0, base > 0 else {
            return base
        }
        let material = "\(jitterSeed)|\(runID)|\(nodeID)|\(nextAttemptOrdinal)"
        let digest = SHA256.hash(data: Data(material.utf8))
        let value = digest.prefix(8).reduce(UInt64(0)) {
            ($0 << 8) | UInt64($1)
        }
        let window = base.multipliedReportingOverflow(
            by: UInt64(jitterBasisPoints)
        ).partialValue / 10_000
        guard window > 0 else {
            return base
        }
        return min(
            maximumBackoffSeconds,
            base + (value % (window + 1))
        )
    }
}

public struct GraphSchedulerPolicy: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let policyID: String
    public let version: String
    public let retryPolicy: GraphRetryPolicy
    public let defaultLeaseDurationSeconds: UInt64
    public let claimAcquisitionTimeoutSeconds: UInt64
    public let attemptExecutionTimeoutSeconds: UInt64
    public let cancellationAcknowledgementTimeoutSeconds: UInt64
    public let allowExpiredLeaseTakeover: Bool
    public let schedulingEnabled: Bool

    public init(
        schemaVersion: Int = GraphSchedulingSchema.policyVersion,
        policyID: String,
        version: String,
        retryPolicy: GraphRetryPolicy,
        defaultLeaseDurationSeconds: UInt64 = 60,
        claimAcquisitionTimeoutSeconds: UInt64 = 30,
        attemptExecutionTimeoutSeconds: UInt64 = 3_600,
        cancellationAcknowledgementTimeoutSeconds: UInt64 = 30,
        allowExpiredLeaseTakeover: Bool = true,
        schedulingEnabled: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.policyID = policyID
        self.version = version
        self.retryPolicy = retryPolicy
        self.defaultLeaseDurationSeconds = max(1, defaultLeaseDurationSeconds)
        self.claimAcquisitionTimeoutSeconds = max(
            1,
            claimAcquisitionTimeoutSeconds
        )
        self.attemptExecutionTimeoutSeconds = max(
            1,
            attemptExecutionTimeoutSeconds
        )
        self.cancellationAcknowledgementTimeoutSeconds = max(
            1,
            cancellationAcknowledgementTimeoutSeconds
        )
        self.allowExpiredLeaseTakeover = allowExpiredLeaseTakeover
        self.schedulingEnabled = schedulingEnabled
    }
}

public enum GraphSchedulingReasonCode:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case dependenciesSatisfied = "dependencies_satisfied"
    case dependencyFailed = "dependency_failed"
    case dependencyCancelled = "dependency_cancelled"
    case dependencyIncomplete = "dependency_incomplete"
    case existingActiveClaim = "existing_active_claim"
    case leaseExpired = "lease_expired"
    case retryAllowed = "retry_allowed"
    case retryExhausted = "retry_exhausted"
    case retryBackoffActive = "retry_backoff_active"
    case cancellationPending = "cancellation_pending"
    case terminalAttemptExists = "terminal_attempt_exists"
    case executorCapabilityUnavailable = "executor_capability_unavailable"
    case graphDefinitionMismatch = "graph_definition_mismatch"
    case schedulerPolicyDenied = "scheduler_policy_denied"
    case runTerminal = "run_terminal"
    case claimGranted = "claim_granted"
    case claimRejected = "claim_rejected"
    case claimReleased = "claim_released"
    case leaseRenewed = "lease_renewed"
    case cancellationAcknowledged = "cancellation_acknowledged"
    case timeoutRecorded = "timeout_recorded"
    case retryNotApplicable = "retry_not_applicable"
}

public enum GraphNodeSchedulingPhase: String, Codable, Sendable {
    case pending
    case blocked
    case ready
    case claimable
    case claimed
    case running
    case retryWaiting = "retry_waiting"
    case cancellationPending = "cancellation_pending"
    case terminal
}

public enum GraphExecutorClaimStatus: String, Codable, Sendable {
    case active
    case expired
    case released
}

public struct GraphExecutorClaim:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let schemaVersion: Int
    public let runID: String
    public let nodeID: String
    public let attemptOrdinal: Int
    public let id: String
    public let executorID: String
    public let executorCapabilityIdentity: String
    public let grantedSequence: UInt64
    public let leaseStart: Date
    public let leaseExpiry: Date
    public let leaseGeneration: UInt64
    public let hostID: String?

    public init(
        schemaVersion: Int = GraphSchedulingSchema.claimVersion,
        runID: String,
        nodeID: String,
        attemptOrdinal: Int,
        claimID: String,
        executorID: String,
        executorCapabilityIdentity: String,
        grantedSequence: UInt64,
        leaseStart: Date,
        leaseExpiry: Date,
        leaseGeneration: UInt64 = 1,
        hostID: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.nodeID = nodeID
        self.attemptOrdinal = attemptOrdinal
        id = claimID
        self.executorID = executorID
        self.executorCapabilityIdentity = executorCapabilityIdentity
        self.grantedSequence = grantedSequence
        self.leaseStart = leaseStart
        self.leaseExpiry = leaseExpiry
        self.leaseGeneration = leaseGeneration
        self.hostID = hostID
    }

    public func isValid(at logicalTime: Date) -> Bool {
        leaseStart <= logicalTime && logicalTime < leaseExpiry
    }
}

public struct GraphExecutorClaimRecord: Equatable, Codable, Sendable {
    public var claim: GraphExecutorClaim
    public var status: GraphExecutorClaimStatus
    public var statusChangedAt: Date
    public var reason: GraphSchedulingReasonCode

    public init(
        claim: GraphExecutorClaim,
        status: GraphExecutorClaimStatus = .active,
        statusChangedAt: Date,
        reason: GraphSchedulingReasonCode = .claimGranted
    ) {
        self.claim = claim
        self.status = status
        self.statusChangedAt = statusChangedAt
        self.reason = reason
    }
}

public struct GraphRetryRecord: Equatable, Codable, Sendable {
    public let nodeID: String
    public let failedAttemptID: String
    public let failedAttemptOrdinal: Int
    public let nextAttemptOrdinal: Int
    public let failureCategory: String
    public let scheduledAt: Date
    public let eligibleAt: Date
    public let delaySeconds: UInt64
    public let policy: GraphRetryPolicy
    public let reason: GraphSchedulingReasonCode
}

public enum GraphCancellationState: String, Codable, Sendable {
    case requested
    case acknowledged
}

public struct GraphCancellationRecord:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let schemaVersion: Int
    public let id: String
    public let runID: String
    public let nodeID: String
    public let attemptID: String?
    public let claimID: String?
    public let requestedBy: String
    public let requestedAt: Date
    public let reason: String?
    public var state: GraphCancellationState
    public var acknowledgedAt: Date?
    public var acknowledgedByExecutorID: String?

    public init(
        schemaVersion: Int = GraphSchedulingSchema.cancellationVersion,
        requestID: String,
        runID: String,
        nodeID: String,
        attemptID: String?,
        claimID: String?,
        requestedBy: String,
        requestedAt: Date,
        reason: String?,
        state: GraphCancellationState = .requested,
        acknowledgedAt: Date? = nil,
        acknowledgedByExecutorID: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        id = requestID
        self.runID = runID
        self.nodeID = nodeID
        self.attemptID = attemptID
        self.claimID = claimID
        self.requestedBy = requestedBy
        self.requestedAt = requestedAt
        self.reason = reason
        self.state = state
        self.acknowledgedAt = acknowledgedAt
        self.acknowledgedByExecutorID = acknowledgedByExecutorID
    }
}

public enum GraphTimeoutKind: String, Codable, Sendable {
    case claimAcquisition = "claim_acquisition"
    case lease
    case attemptExecution = "attempt_execution"
    case cancellationAcknowledgement = "cancellation_acknowledgement"
    case retryDelay = "retry_delay"
}

public struct GraphTimeoutDecision:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let schemaVersion: Int
    public let id: String
    public let runID: String
    public let nodeID: String
    public let attemptID: String?
    public let claimID: String?
    public let kind: GraphTimeoutKind
    public let deadline: Date
    public let declaredAt: Date
    public let reason: GraphSchedulingReasonCode

    public init(
        schemaVersion: Int = GraphSchedulingSchema.timeoutVersion,
        timeoutID: String,
        runID: String,
        nodeID: String,
        attemptID: String?,
        claimID: String?,
        kind: GraphTimeoutKind,
        deadline: Date,
        declaredAt: Date,
        reason: GraphSchedulingReasonCode = .timeoutRecorded
    ) {
        self.schemaVersion = schemaVersion
        id = timeoutID
        self.runID = runID
        self.nodeID = nodeID
        self.attemptID = attemptID
        self.claimID = claimID
        self.kind = kind
        self.deadline = deadline
        self.declaredAt = declaredAt
        self.reason = reason
    }
}

public struct GraphSchedulingRecord:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public let sequence: UInt64
    public let eventType: String
    public let factClass: GraphExecutionEventFactClass
    public let nodeID: String?
    public let attemptID: String?
    public let evaluationID: String?
    public let reason: GraphSchedulingReasonCode?
    public let occurredAt: Date
}

public struct GraphSchedulingProjection: Equatable, Codable, Sendable {
    public var evaluations: [GraphSchedulerEvaluationPayload]
    public var records: [GraphSchedulingRecord]
    public var claims: [GraphExecutorClaimRecord]
    public var retries: [GraphRetryRecord]
    public var cancellations: [GraphCancellationRecord]
    public var timeouts: [GraphTimeoutDecision]
    public var completedEvaluationIDs: [String]

    public init(
        evaluations: [GraphSchedulerEvaluationPayload] = [],
        records: [GraphSchedulingRecord] = [],
        claims: [GraphExecutorClaimRecord] = [],
        retries: [GraphRetryRecord] = [],
        cancellations: [GraphCancellationRecord] = [],
        timeouts: [GraphTimeoutDecision] = [],
        completedEvaluationIDs: [String] = []
    ) {
        self.evaluations = evaluations
        self.records = records
        self.claims = claims
        self.retries = retries
        self.cancellations = cancellations
        self.timeouts = timeouts
        self.completedEvaluationIDs = completedEvaluationIDs
    }

    public func activeClaim(
        nodeID: String,
        attemptOrdinal: Int? = nil,
        at logicalTime: Date? = nil
    ) -> GraphExecutorClaim? {
        claims
            .filter {
                $0.claim.nodeID == nodeID
                    && $0.status == .active
                    && (attemptOrdinal == nil
                        || $0.claim.attemptOrdinal == attemptOrdinal)
                    && (logicalTime == nil
                        || $0.claim.isValid(at: logicalTime!))
            }
            .map(\.claim)
            .max {
                if $0.leaseGeneration != $1.leaseGeneration {
                    return $0.leaseGeneration < $1.leaseGeneration
                }
                return $0.id < $1.id
            }
    }

    public func pendingCancellation(
        nodeID: String
    ) -> GraphCancellationRecord? {
        cancellations
            .filter { $0.nodeID == nodeID }
            .max {
                if $0.requestedAt != $1.requestedAt {
                    return $0.requestedAt < $1.requestedAt
                }
                return $0.id < $1.id
            }
    }
}

public struct GraphSchedulerEvaluationPayload:
    Equatable,
    Codable,
    Sendable
{
    public let evaluationID: String
    public let graphDefinitionVersion: String
    public let graphDefinitionDigest: GraphContentDigest
    public let schedulerPolicyID: String
    public let schedulerPolicyVersion: String
    public let logicalTime: Date
    public let availableCapabilityIdentities: [String]
}

public struct GraphNodeSchedulingPayload:
    Equatable,
    Codable,
    Sendable
{
    public let evaluationID: String
    public let phase: GraphNodeSchedulingPhase
    public let reason: GraphSchedulingReasonCode
    public let attemptOrdinal: Int?
    public let eligibleAt: Date?
}

public struct GraphExecutorClaimPayload: Equatable, Codable, Sendable {
    public let claim: GraphExecutorClaim
    public let reason: GraphSchedulingReasonCode
}

public struct GraphExecutorClaimRejectedPayload:
    Equatable,
    Codable,
    Sendable
{
    public let claimID: String
    public let nodeID: String
    public let attemptOrdinal: Int
    public let executorID: String
    public let reason: GraphSchedulingReasonCode
    public let conflictingClaimID: String?
}

public struct GraphExecutorLeaseEndedPayload:
    Equatable,
    Codable,
    Sendable
{
    public let claimID: String
    public let leaseGeneration: UInt64
    public let reason: GraphSchedulingReasonCode
}

public struct GraphRetryScheduledPayload: Equatable, Codable, Sendable {
    public let retry: GraphRetryRecord
}

public struct GraphRetrySuppressedPayload: Equatable, Codable, Sendable {
    public let failedAttemptID: String
    public let failedAttemptOrdinal: Int
    public let failureCategory: String
    public let policy: GraphRetryPolicy
    public let reason: GraphSchedulingReasonCode
}

public struct GraphCancellationRequestedPayload:
    Equatable,
    Codable,
    Sendable
{
    public let cancellation: GraphCancellationRecord
}

public struct GraphCancellationAcknowledgedPayload:
    Equatable,
    Codable,
    Sendable
{
    public let requestID: String
    public let claimID: String?
    public let executorID: String
    public let acknowledgedAt: Date
}

public struct GraphTimeoutDeclaredPayload: Equatable, Codable, Sendable {
    public let timeout: GraphTimeoutDecision
}

public struct GraphDependencyFailurePropagatedPayload:
    Equatable,
    Codable,
    Sendable
{
    public let evaluationID: String
    public let dependencyNodeID: String
    public let reason: GraphSchedulingReasonCode
}

public struct GraphSchedulerCycleCompletedPayload:
    Equatable,
    Codable,
    Sendable
{
    public let evaluationID: String
    public let proposedDecisionCount: Int
}

public struct GraphSchedulingProposedEvent: Equatable, Sendable {
    public let id: String
    public let nodeID: String?
    public let attemptID: String?
    public let occurredAt: Date
    public let payload: GraphExecutionEventPayload
}

public struct GraphSchedulingDecision: Equatable, Sendable {
    public let evaluationID: String
    public let logicalTime: Date
    public let proposedEvents: [GraphSchedulingProposedEvent]
    public let phasesByNodeID: [String: GraphNodeSchedulingPhase]
    public let reasonsByNodeID: [String: GraphSchedulingReasonCode]
}

public struct GraphSchedulingInput: Equatable, Sendable {
    public let definition: GraphSchedulingDefinition
    public let projectedState: GraphExecutionProjection
    public let reconciledState: ExecutionReconciliationResult
    public let policy: GraphSchedulerPolicy
    public let logicalTime: Date
    public let availableExecutors: [GraphExecutorCapabilities]
    public let existingClaims: [GraphExecutorClaimRecord]
    public let existingLeases: [GraphExecutorClaim]
    public let failureCategoriesByAttemptID: [String: String]

    public init(
        definition: GraphSchedulingDefinition,
        projectedState: GraphExecutionProjection,
        reconciledState: ExecutionReconciliationResult,
        policy: GraphSchedulerPolicy,
        logicalTime: Date,
        availableExecutors: [GraphExecutorCapabilities],
        existingClaims: [GraphExecutorClaimRecord]? = nil,
        existingLeases: [GraphExecutorClaim]? = nil,
        failureCategoriesByAttemptID: [String: String] = [:]
    ) {
        self.definition = definition
        self.projectedState = projectedState
        self.reconciledState = reconciledState
        self.policy = policy
        self.logicalTime = logicalTime
        self.availableExecutors = availableExecutors.sorted {
            if $0.capabilityIdentity != $1.capabilityIdentity {
                return $0.capabilityIdentity < $1.capabilityIdentity
            }
            return $0.executorID < $1.executorID
        }
        self.existingClaims = existingClaims
            ?? projectedState.scheduling.claims
        self.existingLeases = existingLeases
            ?? projectedState.scheduling.claims.map(\.claim)
        self.failureCategoriesByAttemptID = failureCategoriesByAttemptID
    }
}

public enum GraphScheduler {
    public static func evaluate(
        _ input: GraphSchedulingInput
    ) -> GraphSchedulingDecision {
        let evaluationID = stableID(
            [
                input.projectedState.runID,
                input.definition.graphID,
                input.definition.version,
                input.definition.digest.value,
                input.policy.policyID,
                input.policy.version,
                iso8601(input.logicalTime),
                input.availableExecutors
                    .map(\.capabilityIdentity)
                    .joined(separator: ","),
            ].joined(separator: "|")
        )
        guard !input.projectedState.scheduling.completedEvaluationIDs
            .contains(evaluationID) else {
            return GraphSchedulingDecision(
                evaluationID: evaluationID,
                logicalTime: input.logicalTime,
                proposedEvents: [],
                phasesByNodeID: [:],
                reasonsByNodeID: [:]
            )
        }

        let state = schedulingStates(input)
        var proposals: [GraphSchedulingProposedEvent] = []
        let evaluation = GraphSchedulerEvaluationPayload(
            evaluationID: evaluationID,
            graphDefinitionVersion: input.definition.version,
            graphDefinitionDigest: input.definition.digest,
            schedulerPolicyID: input.policy.policyID,
            schedulerPolicyVersion: input.policy.version,
            logicalTime: input.logicalTime,
            availableCapabilityIdentities: input.availableExecutors
                .map(\.capabilityIdentity)
        )
        proposals.append(
            proposal(
                evaluationID: evaluationID,
                key: "evaluation",
                occurredAt: input.logicalTime,
                payload: .schedulerEvaluationRecorded(evaluation)
            )
        )

        for node in input.definition.nodes {
            guard let result = state[node.id] else { continue }
            let latestAttempt = latestAttempt(
                nodeID: node.id,
                attempts: input.reconciledState.attempts
            )

            if let retry = retryProposal(
                input: input,
                node: node,
                latestAttempt: latestAttempt,
                evaluationID: evaluationID
            ) {
                proposals.append(retry)
            }

            if result.phase == .blocked,
               let dependencyID = firstFailedDependency(
                    node,
                    states: state
               ) {
                proposals.append(
                    proposal(
                        evaluationID: evaluationID,
                        key: "dependency|\(node.id)|\(dependencyID)",
                        nodeID: node.id,
                        occurredAt: input.logicalTime,
                        payload: .dependencyFailurePropagated(
                            GraphDependencyFailurePropagatedPayload(
                                evaluationID: evaluationID,
                                dependencyNodeID: dependencyID,
                                reason: result.reason
                            )
                        )
                    )
                )
            }

            let payload = GraphNodeSchedulingPayload(
                evaluationID: evaluationID,
                phase: result.phase,
                reason: result.reason,
                attemptOrdinal: result.attemptOrdinal,
                eligibleAt: result.eligibleAt
            )
            proposals.append(
                proposal(
                    evaluationID: evaluationID,
                    key: "node|\(node.id)|\(result.phase.rawValue)",
                    nodeID: node.id,
                    attemptID: latestAttempt?.id,
                    occurredAt: input.logicalTime,
                    payload: result.phase == .claimable
                        ? .nodeBecameRunnable(payload)
                        : .nodeSchedulingDeferred(payload)
                )
            )
        }

        proposals.append(
            proposal(
                evaluationID: evaluationID,
                key: "completed",
                occurredAt: input.logicalTime,
                payload: .schedulerCycleCompleted(
                    GraphSchedulerCycleCompletedPayload(
                        evaluationID: evaluationID,
                        proposedDecisionCount: proposals.count
                    )
                )
            )
        )
        return GraphSchedulingDecision(
            evaluationID: evaluationID,
            logicalTime: input.logicalTime,
            proposedEvents: proposals,
            phasesByNodeID: state.mapValues(\.phase),
            reasonsByNodeID: state.mapValues(\.reason)
        )
    }

    private struct NodeResult {
        let phase: GraphNodeSchedulingPhase
        let reason: GraphSchedulingReasonCode
        let attemptOrdinal: Int?
        let eligibleAt: Date?
    }

    private static func schedulingStates(
        _ input: GraphSchedulingInput
    ) -> [String: NodeResult] {
        let projectedRun = input.projectedState.run
        let definitionMatches = projectedRun?.graphID == input.definition.graphID
            && input.projectedState.graphDefinitionVersion
                == input.definition.version
            && input.projectedState.graphDefinitionDigest
                == input.definition.digest
        let reconciledNodes = Dictionary(
            uniqueKeysWithValues: input.reconciledState.nodes.map {
                ($0.id, $0)
            }
        )
        var results: [String: NodeResult] = [:]

        for _ in 0...input.definition.nodes.count {
            var changed = false
            for node in input.definition.nodes {
                let result = evaluateNode(
                    node,
                    input: input,
                    definitionMatches: definitionMatches,
                    reconciledNode: reconciledNodes[node.id],
                    dependencyResults: results
                )
                if results[node.id]?.phase != result.phase
                    || results[node.id]?.reason != result.reason
                    || results[node.id]?.eligibleAt != result.eligibleAt {
                    results[node.id] = result
                    changed = true
                }
            }
            if !changed { break }
        }
        return results
    }

    private static func evaluateNode(
        _ node: GraphSchedulingDefinitionNode,
        input: GraphSchedulingInput,
        definitionMatches: Bool,
        reconciledNode: GraphNode?,
        dependencyResults: [String: NodeResult]
    ) -> NodeResult {
        let latest = latestAttempt(
            nodeID: node.id,
            attempts: input.reconciledState.attempts
        )
        let nextOrdinal = (latest?.ordinal ?? 0) + 1

        guard definitionMatches else {
            return NodeResult(
                phase: .blocked,
                reason: .graphDefinitionMismatch,
                attemptOrdinal: nextOrdinal,
                eligibleAt: nil
            )
        }
        guard input.policy.schedulingEnabled else {
            return NodeResult(
                phase: .pending,
                reason: .schedulerPolicyDenied,
                attemptOrdinal: nextOrdinal,
                eligibleAt: nil
            )
        }
        guard input.projectedState.run?.state.isTerminal != true else {
            return NodeResult(
                phase: .terminal,
                reason: .runTerminal,
                attemptOrdinal: latest?.ordinal,
                eligibleAt: nil
            )
        }
        if let latest, latest.state == .completed || latest.state == .cancelled {
            return NodeResult(
                phase: .terminal,
                reason: .terminalAttemptExists,
                attemptOrdinal: latest.ordinal,
                eligibleAt: nil
            )
        }
        if input.projectedState.scheduling.pendingCancellation(
            nodeID: node.id
        ) != nil {
            return NodeResult(
                phase: .cancellationPending,
                reason: .cancellationPending,
                attemptOrdinal: latest?.ordinal,
                eligibleAt: nil
            )
        }

        for dependencyID in node.dependencyNodeIDs {
            if let dependency = dependencyResults[dependencyID] {
                if dependency.phase == .blocked
                    || dependency.phase == .terminal
                        && reconciledState(
                            dependencyID,
                            input.reconciledState.nodes
                        ) != .completed {
                    let state = reconciledState(
                        dependencyID,
                        input.reconciledState.nodes
                    )
                    return NodeResult(
                        phase: .blocked,
                        reason: state == .cancelled
                            ? .dependencyCancelled
                            : .dependencyFailed,
                        attemptOrdinal: nextOrdinal,
                        eligibleAt: nil
                    )
                }
            }
            guard reconciledState(
                dependencyID,
                input.reconciledState.nodes
            ) == .completed else {
                return NodeResult(
                    phase: .pending,
                    reason: .dependencyIncomplete,
                    attemptOrdinal: nextOrdinal,
                    eligibleAt: nil
                )
            }
        }

        if let latest, latest.state == .running {
            if let claim = activeClaim(
                nodeID: node.id,
                ordinal: latest.ordinal,
                claims: input.existingClaims,
                time: input.logicalTime
            ) {
                return NodeResult(
                    phase: .running,
                    reason: .existingActiveClaim,
                    attemptOrdinal: claim.attemptOrdinal,
                    eligibleAt: claim.leaseExpiry
                )
            }
            return NodeResult(
                phase: .ready,
                reason: .leaseExpired,
                attemptOrdinal: latest.ordinal,
                eligibleAt: input.logicalTime
            )
        }
        if let claim = activeClaim(
            nodeID: node.id,
            ordinal: latest?.ordinal ?? nextOrdinal,
            claims: input.existingClaims,
            time: input.logicalTime
        ) {
            return NodeResult(
                phase: .claimed,
                reason: .existingActiveClaim,
                attemptOrdinal: claim.attemptOrdinal,
                eligibleAt: claim.leaseExpiry
            )
        }

        if let retry = input.projectedState.scheduling.retries
            .filter({ $0.nodeID == node.id })
            .max(by: { $0.nextAttemptOrdinal < $1.nextAttemptOrdinal }),
           retry.nextAttemptOrdinal == nextOrdinal,
           input.logicalTime < retry.eligibleAt {
            return NodeResult(
                phase: .retryWaiting,
                reason: .retryBackoffActive,
                attemptOrdinal: nextOrdinal,
                eligibleAt: retry.eligibleAt
            )
        }
        if let latest,
           latest.state == .failed
                || latest.state == .interrupted
                || latest.state == .orphaned {
            let failureCategory = input.failureCategoriesByAttemptID[latest.id]
                ?? "execution_failure"
            guard retryAllowed(
                policy: input.policy.retryPolicy,
                failureCategory: failureCategory,
                failedOrdinal: latest.ordinal
            ) else {
                return NodeResult(
                    phase: .terminal,
                    reason: .retryExhausted,
                    attemptOrdinal: latest.ordinal,
                    eligibleAt: nil
                )
            }
            let delay = input.policy.retryPolicy.delaySeconds(
                runID: input.projectedState.runID,
                nodeID: node.id,
                nextAttemptOrdinal: nextOrdinal
            )
            let eligibleAt = input.logicalTime.addingTimeInterval(
                TimeInterval(delay)
            )
            if input.logicalTime < eligibleAt {
                return NodeResult(
                    phase: .retryWaiting,
                    reason: .retryBackoffActive,
                    attemptOrdinal: nextOrdinal,
                    eligibleAt: eligibleAt
                )
            }
        }

        guard input.availableExecutors.contains(where: {
            $0.satisfies(node.requiredCapabilities)
        }) else {
            return NodeResult(
                phase: .ready,
                reason: .executorCapabilityUnavailable,
                attemptOrdinal: nextOrdinal,
                eligibleAt: nil
            )
        }
        return NodeResult(
            phase: .claimable,
            reason: .dependenciesSatisfied,
            attemptOrdinal: nextOrdinal,
            eligibleAt: input.logicalTime
        )
    }

    private static func retryProposal(
        input: GraphSchedulingInput,
        node: GraphSchedulingDefinitionNode,
        latestAttempt: ExecutionAttempt?,
        evaluationID: String
    ) -> GraphSchedulingProposedEvent? {
        guard let attempt = latestAttempt,
              attempt.state == .failed
                || attempt.state == .interrupted
                || attempt.state == .orphaned else {
            return nil
        }
        let nextOrdinal = attempt.ordinal + 1
        guard !input.projectedState.scheduling.retries.contains(where: {
            $0.nodeID == node.id
                && $0.nextAttemptOrdinal == nextOrdinal
        }) else {
            return nil
        }
        let category = input.failureCategoriesByAttemptID[attempt.id]
            ?? "execution_failure"
        let policy = input.policy.retryPolicy

        if retryAllowed(
            policy: policy,
            failureCategory: category,
            failedOrdinal: attempt.ordinal
        ) {
            let delay = policy.delaySeconds(
                runID: input.projectedState.runID,
                nodeID: node.id,
                nextAttemptOrdinal: nextOrdinal
            )
            let retry = GraphRetryRecord(
                nodeID: node.id,
                failedAttemptID: attempt.id,
                failedAttemptOrdinal: attempt.ordinal,
                nextAttemptOrdinal: nextOrdinal,
                failureCategory: category,
                scheduledAt: input.logicalTime,
                eligibleAt: input.logicalTime.addingTimeInterval(
                    TimeInterval(delay)
                ),
                delaySeconds: delay,
                policy: policy,
                reason: .retryAllowed
            )
            return proposal(
                evaluationID: evaluationID,
                key: "retry|\(node.id)|\(nextOrdinal)",
                nodeID: node.id,
                attemptID: attempt.id,
                occurredAt: input.logicalTime,
                payload: .retryScheduled(
                    GraphRetryScheduledPayload(retry: retry)
                )
            )
        }
        return proposal(
            evaluationID: evaluationID,
            key: "retry-suppressed|\(node.id)|\(attempt.ordinal)",
            nodeID: node.id,
            attemptID: attempt.id,
            occurredAt: input.logicalTime,
            payload: .retrySuppressed(
                GraphRetrySuppressedPayload(
                    failedAttemptID: attempt.id,
                    failedAttemptOrdinal: attempt.ordinal,
                    failureCategory: category,
                    policy: policy,
                    reason: .retryExhausted
                )
            )
        )
    }

    private static func retryAllowed(
        policy: GraphRetryPolicy,
        failureCategory: String,
        failedOrdinal: Int
    ) -> Bool {
        failedOrdinal < policy.maximumAttempts
            && !policy.nonRetryableFailureCategories.contains(
                failureCategory
            )
            && (policy.retryableFailureCategories.isEmpty
                || policy.retryableFailureCategories.contains(
                    failureCategory
                ))
    }

    private static func activeClaim(
        nodeID: String,
        ordinal: Int,
        claims: [GraphExecutorClaimRecord],
        time: Date
    ) -> GraphExecutorClaim? {
        claims
            .filter {
                $0.claim.nodeID == nodeID
                    && $0.claim.attemptOrdinal == ordinal
                    && $0.status == .active
                    && $0.claim.isValid(at: time)
            }
            .map(\.claim)
            .max { $0.id < $1.id }
    }

    private static func latestAttempt(
        nodeID: String,
        attempts: [ExecutionAttempt]
    ) -> ExecutionAttempt? {
        attempts.filter { $0.nodeID == nodeID }.max {
            if $0.ordinal != $1.ordinal {
                return $0.ordinal < $1.ordinal
            }
            return $0.id < $1.id
        }
    }

    private static func reconciledState(
        _ nodeID: String,
        _ nodes: [GraphNode]
    ) -> ReconciledExecutionState? {
        nodes.first { $0.id == nodeID }?.state
    }

    private static func firstFailedDependency(
        _ node: GraphSchedulingDefinitionNode,
        states: [String: NodeResult]
    ) -> String? {
        node.dependencyNodeIDs.sorted().first {
            guard let phase = states[$0]?.phase else { return true }
            return phase == .blocked || phase == .terminal
        }
    }

    private static func proposal(
        evaluationID: String,
        key: String,
        nodeID: String? = nil,
        attemptID: String? = nil,
        occurredAt: Date,
        payload: GraphExecutionEventPayload
    ) -> GraphSchedulingProposedEvent {
        GraphSchedulingProposedEvent(
            id: "schedule-\(stableID("\(evaluationID)|\(key)"))",
            nodeID: nodeID,
            attemptID: attemptID,
            occurredAt: occurredAt,
            payload: payload
        )
    }

    package static func stableID(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(24)
            .description
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
