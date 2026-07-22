import Foundation

public enum GraphExecutionSchema {
    public static let eventEnvelopeVersion = 1
    public static let eventPayloadVersion = 1
    public static let snapshotVersion = 1
    public static let artifactReferenceVersion = 1
}

public enum GraphExecutionProducerKind: String, Codable, Sendable {
    case application
    case executor
    case processAdapter
    case importer
    case user
    case test
}

public struct GraphExecutionProducer: Equatable, Codable, Sendable {
    public let id: String
    public let kind: GraphExecutionProducerKind
    public let instanceID: String?

    public init(
        id: String,
        kind: GraphExecutionProducerKind,
        instanceID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.instanceID = instanceID
    }
}

public struct GraphExecutionTelemetryContext: Equatable, Codable, Sendable {
    public let traceID: String?
    public let spanID: String?
    public let traceFlags: String?
    public let traceState: String?
    public let attributes: [String: String]

    public init(
        traceID: String? = nil,
        spanID: String? = nil,
        traceFlags: String? = nil,
        traceState: String? = nil,
        attributes: [String: String] = [:]
    ) {
        self.traceID = traceID
        self.spanID = spanID
        self.traceFlags = traceFlags
        self.traceState = traceState
        self.attributes = attributes
    }
}

public struct GraphExecutionIntegrityMetadata: Equatable, Codable, Sendable {
    public let digestAlgorithm: String
    public let digest: String
    public let signatureAlgorithm: String?
    public let signature: String?

    public init(
        digestAlgorithm: String,
        digest: String,
        signatureAlgorithm: String? = nil,
        signature: String? = nil
    ) {
        self.digestAlgorithm = digestAlgorithm
        self.digest = digest
        self.signatureAlgorithm = signatureAlgorithm
        self.signature = signature
    }
}

public struct GraphContentDigest: Equatable, Codable, Sendable {
    public let algorithm: String
    public let value: String

    public init(algorithm: String, value: String) {
        self.algorithm = algorithm
        self.value = value
    }
}

public struct GraphArtifactStorageLocator: Equatable, Codable, Sendable {
    public let scheme: String
    public let opaqueReference: String

    public init(scheme: String, opaqueReference: String) {
        self.scheme = scheme
        self.opaqueReference = opaqueReference
    }
}

public enum GraphArtifactSensitivity: String, Codable, Sendable {
    case unspecified
    case internalUse
    case confidential
    case restricted
    case redacted
}

public struct GraphArtifactReference: Equatable, Identifiable, Codable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let contentDigest: GraphContentDigest
    public let mediaType: String
    public let logicalRole: String
    public let producingRunID: String
    public let producingNodeID: String
    public let producingAttemptID: String
    public let producingAttemptOrdinal: Int?
    public let producingClaimID: String?
    public let createdAt: Date
    public let storage: GraphArtifactStorageLocator
    public let sensitivity: GraphArtifactSensitivity

    public init(
        schemaVersion: Int = GraphExecutionSchema.artifactReferenceVersion,
        id: String,
        contentDigest: GraphContentDigest,
        mediaType: String,
        logicalRole: String,
        producingRunID: String,
        producingNodeID: String,
        producingAttemptID: String,
        producingAttemptOrdinal: Int? = nil,
        producingClaimID: String? = nil,
        createdAt: Date,
        storage: GraphArtifactStorageLocator,
        sensitivity: GraphArtifactSensitivity = .unspecified
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.contentDigest = contentDigest
        self.mediaType = mediaType
        self.logicalRole = logicalRole
        self.producingRunID = producingRunID
        self.producingNodeID = producingNodeID
        self.producingAttemptID = producingAttemptID
        self.producingAttemptOrdinal = producingAttemptOrdinal
        self.producingClaimID = producingClaimID
        self.createdAt = createdAt
        self.storage = storage
        self.sensitivity = sensitivity
    }
}

public struct GraphCheckpointReference: Equatable, Codable, Sendable {
    public let checkpointID: String
    public let runID: String
    public let streamVersion: UInt64
    public let namespace: String

    public init(
        checkpointID: String,
        runID: String,
        streamVersion: UInt64,
        namespace: String
    ) {
        self.checkpointID = checkpointID
        self.runID = runID
        self.streamVersion = streamVersion
        self.namespace = namespace
    }
}

public struct GraphRunCreatedPayload: Equatable, Codable, Sendable {
    public let graphID: String
    public let graphDefinitionVersion: String
    public let graphDefinitionDigest: GraphContentDigest
    public let nodeIDs: [String]
    public let parentRunID: String?
    public let parentCheckpoint: GraphCheckpointReference?
    public let checkpointNamespace: String
    public let clientIdempotencyKey: String?
    public let requestFingerprint: GraphContentDigest?
    public let executableDefinition: GraphExecutableDefinition?

    public init(
        graphID: String,
        graphDefinitionVersion: String,
        graphDefinitionDigest: GraphContentDigest,
        nodeIDs: [String],
        parentRunID: String? = nil,
        parentCheckpoint: GraphCheckpointReference? = nil,
        checkpointNamespace: String = "root",
        clientIdempotencyKey: String? = nil,
        requestFingerprint: GraphContentDigest? = nil,
        executableDefinition: GraphExecutableDefinition? = nil
    ) {
        self.graphID = graphID
        self.graphDefinitionVersion = graphDefinitionVersion
        self.graphDefinitionDigest = graphDefinitionDigest
        self.nodeIDs = nodeIDs
        self.parentRunID = parentRunID
        self.parentCheckpoint = parentCheckpoint
        self.checkpointNamespace = checkpointNamespace
        self.clientIdempotencyKey = clientIdempotencyKey
        self.requestFingerprint = requestFingerprint
        self.executableDefinition = executableDefinition
    }
}

public struct GraphRunStartRequestedPayload: Equatable, Codable, Sendable {
    public let requestID: String
    public let clientIdempotencyKey: String
    public let requestedBy: String

    public init(
        requestID: String,
        clientIdempotencyKey: String,
        requestedBy: String
    ) {
        self.requestID = requestID
        self.clientIdempotencyKey = clientIdempotencyKey
        self.requestedBy = requestedBy
    }
}

public struct GraphRetryRequestedPayload: Equatable, Codable, Sendable {
    public let requestID: String
    public let clientIdempotencyKey: String
    public let requestedBy: String

    public init(
        requestID: String,
        clientIdempotencyKey: String,
        requestedBy: String
    ) {
        self.requestID = requestID
        self.clientIdempotencyKey = clientIdempotencyKey
        self.requestedBy = requestedBy
    }
}

public struct GraphNodeRegisteredPayload: Equatable, Codable, Sendable {
    public let title: String
    public let dependencyNodeIDs: [String]
    public let executorID: String?
    public let definitionVersion: String

    public init(
        title: String,
        dependencyNodeIDs: [String] = [],
        executorID: String? = nil,
        definitionVersion: String = "1"
    ) {
        self.title = title
        self.dependencyNodeIDs = dependencyNodeIDs
        self.executorID = executorID
        self.definitionVersion = definitionVersion
    }
}

public struct GraphAttemptCreatedPayload: Equatable, Codable, Sendable {
    public let ordinal: Int
    public let executorID: String?

    public init(ordinal: Int, executorID: String? = nil) {
        self.ordinal = ordinal
        self.executorID = executorID
    }
}

public struct GraphAttemptStartingPayload: Equatable, Codable, Sendable {
    public let reason: String?
    public let identity: GraphExecutorInteractionIdentity?

    public init(
        reason: String? = nil,
        identity: GraphExecutorInteractionIdentity? = nil
    ) {
        self.reason = reason
        self.identity = identity
    }
}

public struct GraphExecutorObservationPayload:
    Equatable,
    Codable,
    Sendable
{
    public let observation: GraphExecutorObservation

    public init(observation: GraphExecutorObservation) {
        self.observation = observation
    }
}

public struct GraphProcessIdentityObservedPayload: Equatable, Codable, Sendable {
    public let processIdentity: ProcessIdentity

    public init(processIdentity: ProcessIdentity) {
        self.processIdentity = processIdentity
    }
}

public struct GraphHeartbeatObservedPayload: Equatable, Codable, Sendable {
    public let processIdentity: ProcessIdentity
    public let validUntil: Date

    public init(
        processIdentity: ProcessIdentity,
        validUntil: Date
    ) {
        self.processIdentity = processIdentity
        self.validUntil = validUntil
    }
}

public struct GraphProcessExitObservedPayload: Equatable, Codable, Sendable {
    public let processIdentity: ProcessIdentity
    public let exitCode: Int32?
    public let signal: Int32?
    public let reason: String?

    public init(
        processIdentity: ProcessIdentity,
        exitCode: Int32? = nil,
        signal: Int32? = nil,
        reason: String? = nil
    ) {
        self.processIdentity = processIdentity
        self.exitCode = exitCode
        self.signal = signal
        self.reason = reason
    }
}

public struct GraphAttemptTerminalPayload: Equatable, Codable, Sendable {
    public let reason: String?
    public let artifactIDs: [String]

    public init(
        reason: String? = nil,
        artifactIDs: [String] = []
    ) {
        self.reason = reason
        self.artifactIDs = artifactIDs
    }
}

public struct GraphArtifactRecordedPayload: Equatable, Codable, Sendable {
    public let artifact: GraphArtifactReference

    public init(artifact: GraphArtifactReference) {
        self.artifact = artifact
    }
}

public enum GraphHumanInterruptResolution: String, Codable, Sendable {
    case approved
    case rejected
    case modified
    case delegated
    case additionalEvidenceRequested
}

public struct GraphHumanInterruptRequestedPayload: Equatable, Codable, Sendable {
    public let requestID: String
    public let requestSchemaID: String
    public let requestArtifactID: String?
    public let expiresAt: Date?
    public let requiredDecisionCount: Int

    public init(
        requestID: String,
        requestSchemaID: String,
        requestArtifactID: String? = nil,
        expiresAt: Date? = nil,
        requiredDecisionCount: Int = 1
    ) {
        self.requestID = requestID
        self.requestSchemaID = requestSchemaID
        self.requestArtifactID = requestArtifactID
        self.expiresAt = expiresAt
        self.requiredDecisionCount = requiredDecisionCount
    }
}

public struct GraphHumanInterruptResolvedPayload: Equatable, Codable, Sendable {
    public let requestID: String
    public let resolution: GraphHumanInterruptResolution
    public let decidedBy: String
    public let responseArtifactID: String?

    public init(
        requestID: String,
        resolution: GraphHumanInterruptResolution,
        decidedBy: String,
        responseArtifactID: String? = nil
    ) {
        self.requestID = requestID
        self.resolution = resolution
        self.decidedBy = decidedBy
        self.responseArtifactID = responseArtifactID
    }
}

public struct GraphRunTerminalPayload: Equatable, Codable, Sendable {
    public let state: ReconciledExecutionState
    public let reason: String?

    public init(
        state: ReconciledExecutionState,
        reason: String? = nil
    ) {
        self.state = state
        self.reason = reason
    }
}

public enum GraphExecutionEventType: String, CaseIterable, Codable, Sendable {
    case runCreated = "graph.run.created"
    case runStartRequested = "graph.run.start.requested"
    case nodeRegistered = "graph.node.registered"
    case attemptCreated = "graph.attempt.created"
    case attemptStarting = "graph.attempt.starting"
    case processIdentityObserved = "graph.process.identity.observed"
    case heartbeatObserved = "graph.executor.heartbeat.observed"
    case processExitObserved = "graph.process.exit.observed"
    case executorObservationRecorded =
        "graph.executor.observation.recorded"
    case attemptCompleted = "graph.attempt.completed"
    case attemptFailed = "graph.attempt.failed"
    case attemptInterrupted = "graph.attempt.interrupted"
    case attemptOrphaned = "graph.attempt.orphaned"
    case attemptCancelled = "graph.attempt.cancelled"
    case artifactRecorded = "graph.artifact.recorded"
    case humanInterruptRequested = "graph.human_interrupt.requested"
    case humanInterruptResolved = "graph.human_interrupt.resolved"
    case runTerminalStateRecorded = "graph.run.terminal.recorded"
    case schedulerEvaluationRecorded = "graph.scheduler.evaluation.recorded"
    case nodeBecameRunnable = "graph.scheduler.node.runnable"
    case nodeSchedulingDeferred = "graph.scheduler.node.deferred"
    case executorClaimRequested = "graph.executor.claim.requested"
    case executorClaimGranted = "graph.executor.claim.granted"
    case executorClaimRejected = "graph.executor.claim.rejected"
    case executorLeaseRenewed = "graph.executor.lease.renewed"
    case executorLeaseExpired = "graph.executor.lease.expired"
    case executorClaimReleased = "graph.executor.claim.released"
    case retryScheduled = "graph.scheduler.retry.scheduled"
    case retryRequested = "graph.retry.requested"
    case retrySuppressed = "graph.scheduler.retry.suppressed"
    case cancellationRequested = "graph.cancellation.requested"
    case cancellationAcknowledged = "graph.cancellation.acknowledged"
    case timeoutDeclared = "graph.scheduler.timeout.declared"
    case dependencyFailurePropagated =
        "graph.scheduler.dependency_failure.propagated"
    case schedulerCycleCompleted = "graph.scheduler.cycle.completed"
}

public enum GraphExecutionEventFactClass: String, Codable, Sendable {
    case decision
    case command
    case observation
    case declaration
    case metadata
}

public enum GraphJSONValue: Equatable, Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([GraphJSONValue])
    case object([String: GraphJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([GraphJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(
                try container.decode([String: GraphJSONValue].self)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

public enum GraphExecutionEventPayload: Equatable, Sendable {
    case runCreated(GraphRunCreatedPayload)
    case runStartRequested(GraphRunStartRequestedPayload)
    case nodeRegistered(GraphNodeRegisteredPayload)
    case attemptCreated(GraphAttemptCreatedPayload)
    case attemptStarting(GraphAttemptStartingPayload)
    case processIdentityObserved(GraphProcessIdentityObservedPayload)
    case heartbeatObserved(GraphHeartbeatObservedPayload)
    case processExitObserved(GraphProcessExitObservedPayload)
    case executorObservationRecorded(GraphExecutorObservationPayload)
    case attemptCompleted(GraphAttemptTerminalPayload)
    case attemptFailed(GraphAttemptTerminalPayload)
    case attemptInterrupted(GraphAttemptTerminalPayload)
    case attemptOrphaned(GraphAttemptTerminalPayload)
    case attemptCancelled(GraphAttemptTerminalPayload)
    case artifactRecorded(GraphArtifactRecordedPayload)
    case humanInterruptRequested(GraphHumanInterruptRequestedPayload)
    case humanInterruptResolved(GraphHumanInterruptResolvedPayload)
    case runTerminalStateRecorded(GraphRunTerminalPayload)
    case schedulerEvaluationRecorded(GraphSchedulerEvaluationPayload)
    case nodeBecameRunnable(GraphNodeSchedulingPayload)
    case nodeSchedulingDeferred(GraphNodeSchedulingPayload)
    case executorClaimRequested(GraphExecutorClaimPayload)
    case executorClaimGranted(GraphExecutorClaimPayload)
    case executorClaimRejected(GraphExecutorClaimRejectedPayload)
    case executorLeaseRenewed(GraphExecutorClaimPayload)
    case executorLeaseExpired(GraphExecutorLeaseEndedPayload)
    case executorClaimReleased(GraphExecutorLeaseEndedPayload)
    case retryScheduled(GraphRetryScheduledPayload)
    case retryRequested(GraphRetryRequestedPayload)
    case retrySuppressed(GraphRetrySuppressedPayload)
    case cancellationRequested(GraphCancellationRequestedPayload)
    case cancellationAcknowledged(GraphCancellationAcknowledgedPayload)
    case timeoutDeclared(GraphTimeoutDeclaredPayload)
    case dependencyFailurePropagated(
        GraphDependencyFailurePropagatedPayload
    )
    case schedulerCycleCompleted(GraphSchedulerCycleCompletedPayload)
    case unknown(eventType: String, body: GraphJSONValue)

    public var eventType: String {
        switch self {
        case .runCreated:
            GraphExecutionEventType.runCreated.rawValue
        case .runStartRequested:
            GraphExecutionEventType.runStartRequested.rawValue
        case .nodeRegistered:
            GraphExecutionEventType.nodeRegistered.rawValue
        case .attemptCreated:
            GraphExecutionEventType.attemptCreated.rawValue
        case .attemptStarting:
            GraphExecutionEventType.attemptStarting.rawValue
        case .processIdentityObserved:
            GraphExecutionEventType.processIdentityObserved.rawValue
        case .heartbeatObserved:
            GraphExecutionEventType.heartbeatObserved.rawValue
        case .processExitObserved:
            GraphExecutionEventType.processExitObserved.rawValue
        case .executorObservationRecorded:
            GraphExecutionEventType.executorObservationRecorded.rawValue
        case .attemptCompleted:
            GraphExecutionEventType.attemptCompleted.rawValue
        case .attemptFailed:
            GraphExecutionEventType.attemptFailed.rawValue
        case .attemptInterrupted:
            GraphExecutionEventType.attemptInterrupted.rawValue
        case .attemptOrphaned:
            GraphExecutionEventType.attemptOrphaned.rawValue
        case .attemptCancelled:
            GraphExecutionEventType.attemptCancelled.rawValue
        case .artifactRecorded:
            GraphExecutionEventType.artifactRecorded.rawValue
        case .humanInterruptRequested:
            GraphExecutionEventType.humanInterruptRequested.rawValue
        case .humanInterruptResolved:
            GraphExecutionEventType.humanInterruptResolved.rawValue
        case .runTerminalStateRecorded:
            GraphExecutionEventType.runTerminalStateRecorded.rawValue
        case .schedulerEvaluationRecorded:
            GraphExecutionEventType.schedulerEvaluationRecorded.rawValue
        case .nodeBecameRunnable:
            GraphExecutionEventType.nodeBecameRunnable.rawValue
        case .nodeSchedulingDeferred:
            GraphExecutionEventType.nodeSchedulingDeferred.rawValue
        case .executorClaimRequested:
            GraphExecutionEventType.executorClaimRequested.rawValue
        case .executorClaimGranted:
            GraphExecutionEventType.executorClaimGranted.rawValue
        case .executorClaimRejected:
            GraphExecutionEventType.executorClaimRejected.rawValue
        case .executorLeaseRenewed:
            GraphExecutionEventType.executorLeaseRenewed.rawValue
        case .executorLeaseExpired:
            GraphExecutionEventType.executorLeaseExpired.rawValue
        case .executorClaimReleased:
            GraphExecutionEventType.executorClaimReleased.rawValue
        case .retryScheduled:
            GraphExecutionEventType.retryScheduled.rawValue
        case .retryRequested:
            GraphExecutionEventType.retryRequested.rawValue
        case .retrySuppressed:
            GraphExecutionEventType.retrySuppressed.rawValue
        case .cancellationRequested:
            GraphExecutionEventType.cancellationRequested.rawValue
        case .cancellationAcknowledged:
            GraphExecutionEventType.cancellationAcknowledged.rawValue
        case .timeoutDeclared:
            GraphExecutionEventType.timeoutDeclared.rawValue
        case .dependencyFailurePropagated:
            GraphExecutionEventType.dependencyFailurePropagated.rawValue
        case .schedulerCycleCompleted:
            GraphExecutionEventType.schedulerCycleCompleted.rawValue
        case let .unknown(eventType, _):
            eventType
        }
    }

    public var factClass: GraphExecutionEventFactClass {
        switch self {
        case .attemptStarting,
             .runStartRequested,
             .retryRequested,
             .humanInterruptRequested,
             .executorClaimRequested,
             .cancellationRequested:
            .command
        case .processIdentityObserved,
             .heartbeatObserved,
             .processExitObserved,
             .executorObservationRecorded:
            .observation
        case .attemptCompleted,
             .attemptFailed,
             .attemptInterrupted,
             .attemptOrphaned,
             .attemptCancelled,
             .humanInterruptResolved,
             .runTerminalStateRecorded,
             .executorClaimGranted,
             .executorClaimRejected,
             .executorLeaseRenewed,
             .executorLeaseExpired,
             .executorClaimReleased,
             .cancellationAcknowledged,
             .schedulerCycleCompleted:
            .declaration
        case .schedulerEvaluationRecorded,
             .nodeBecameRunnable,
             .nodeSchedulingDeferred,
             .retryScheduled,
             .retrySuppressed,
             .timeoutDeclared,
             .dependencyFailurePropagated:
            .decision
        case .runCreated,
             .nodeRegistered,
             .attemptCreated,
             .artifactRecorded,
             .unknown:
            .metadata
        }
    }
}

public struct GraphExecutionEventEnvelope: Equatable, Identifiable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let runID: String
    public let nodeID: String?
    public let attemptID: String?
    public let streamSequence: UInt64
    public let occurredAt: Date
    public let recordedAt: Date
    public let producer: GraphExecutionProducer
    public let correlationID: String?
    public let causationID: String?
    public let telemetryContext: GraphExecutionTelemetryContext?
    public let payloadVersion: Int
    public let payload: GraphExecutionEventPayload
    public let integrity: GraphExecutionIntegrityMetadata?

    public init(
        schemaVersion: Int = GraphExecutionSchema.eventEnvelopeVersion,
        id: String,
        runID: String,
        nodeID: String? = nil,
        attemptID: String? = nil,
        streamSequence: UInt64,
        occurredAt: Date,
        recordedAt: Date,
        producer: GraphExecutionProducer,
        correlationID: String? = nil,
        causationID: String? = nil,
        telemetryContext: GraphExecutionTelemetryContext? = nil,
        payloadVersion: Int = GraphExecutionSchema.eventPayloadVersion,
        payload: GraphExecutionEventPayload,
        integrity: GraphExecutionIntegrityMetadata? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.runID = runID
        self.nodeID = nodeID
        self.attemptID = attemptID
        self.streamSequence = streamSequence
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.producer = producer
        self.correlationID = correlationID
        self.causationID = causationID
        self.telemetryContext = telemetryContext
        self.payloadVersion = payloadVersion
        self.payload = payload
        self.integrity = integrity
    }

    public var eventType: String {
        payload.eventType
    }

    public var factClass: GraphExecutionEventFactClass {
        payload.factClass
    }
}

extension GraphExecutionEventEnvelope: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case runID
        case nodeID
        case attemptID
        case streamSequence
        case occurredAt
        case recordedAt
        case eventType
        case producer
        case correlationID
        case causationID
        case telemetryContext
        case payloadVersion
        case payload
        case integrity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        runID = try container.decode(String.self, forKey: .runID)
        nodeID = try container.decodeIfPresent(String.self, forKey: .nodeID)
        attemptID = try container.decodeIfPresent(
            String.self,
            forKey: .attemptID
        )
        streamSequence = try container.decode(
            UInt64.self,
            forKey: .streamSequence
        )
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
        producer = try container.decode(
            GraphExecutionProducer.self,
            forKey: .producer
        )
        correlationID = try container.decodeIfPresent(
            String.self,
            forKey: .correlationID
        )
        causationID = try container.decodeIfPresent(
            String.self,
            forKey: .causationID
        )
        telemetryContext = try container.decodeIfPresent(
            GraphExecutionTelemetryContext.self,
            forKey: .telemetryContext
        )
        payloadVersion = try container.decode(
            Int.self,
            forKey: .payloadVersion
        )
        integrity = try container.decodeIfPresent(
            GraphExecutionIntegrityMetadata.self,
            forKey: .integrity
        )

        let eventType = try container.decode(
            String.self,
            forKey: .eventType
        )
        let payloadDecoder = try container.superDecoder(forKey: .payload)
        payload = try Self.decodePayload(
            eventType: eventType,
            from: payloadDecoder
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(runID, forKey: .runID)
        try container.encodeIfPresent(nodeID, forKey: .nodeID)
        try container.encodeIfPresent(attemptID, forKey: .attemptID)
        try container.encode(streamSequence, forKey: .streamSequence)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(recordedAt, forKey: .recordedAt)
        try container.encode(eventType, forKey: .eventType)
        try container.encode(producer, forKey: .producer)
        try container.encodeIfPresent(
            correlationID,
            forKey: .correlationID
        )
        try container.encodeIfPresent(causationID, forKey: .causationID)
        try container.encodeIfPresent(
            telemetryContext,
            forKey: .telemetryContext
        )
        try container.encode(payloadVersion, forKey: .payloadVersion)
        try container.encodeIfPresent(integrity, forKey: .integrity)

        let payloadEncoder = container.superEncoder(forKey: .payload)
        try Self.encodePayload(payload, to: payloadEncoder)
    }

    private static func decodePayload(
        eventType: String,
        from decoder: Decoder
    ) throws -> GraphExecutionEventPayload {
        switch GraphExecutionEventType(rawValue: eventType) {
        case .runCreated:
            return .runCreated(try GraphRunCreatedPayload(from: decoder))
        case .runStartRequested:
            return .runStartRequested(
                try GraphRunStartRequestedPayload(from: decoder)
            )
        case .nodeRegistered:
            return .nodeRegistered(
                try GraphNodeRegisteredPayload(from: decoder)
            )
        case .attemptCreated:
            return .attemptCreated(
                try GraphAttemptCreatedPayload(from: decoder)
            )
        case .attemptStarting:
            return .attemptStarting(
                try GraphAttemptStartingPayload(from: decoder)
            )
        case .processIdentityObserved:
            return .processIdentityObserved(
                try GraphProcessIdentityObservedPayload(from: decoder)
            )
        case .heartbeatObserved:
            return .heartbeatObserved(
                try GraphHeartbeatObservedPayload(from: decoder)
            )
        case .processExitObserved:
            return .processExitObserved(
                try GraphProcessExitObservedPayload(from: decoder)
            )
        case .executorObservationRecorded:
            return .executorObservationRecorded(
                try GraphExecutorObservationPayload(from: decoder)
            )
        case .attemptCompleted:
            return .attemptCompleted(
                try GraphAttemptTerminalPayload(from: decoder)
            )
        case .attemptFailed:
            return .attemptFailed(
                try GraphAttemptTerminalPayload(from: decoder)
            )
        case .attemptInterrupted:
            return .attemptInterrupted(
                try GraphAttemptTerminalPayload(from: decoder)
            )
        case .attemptOrphaned:
            return .attemptOrphaned(
                try GraphAttemptTerminalPayload(from: decoder)
            )
        case .attemptCancelled:
            return .attemptCancelled(
                try GraphAttemptTerminalPayload(from: decoder)
            )
        case .artifactRecorded:
            return .artifactRecorded(
                try GraphArtifactRecordedPayload(from: decoder)
            )
        case .humanInterruptRequested:
            return .humanInterruptRequested(
                try GraphHumanInterruptRequestedPayload(from: decoder)
            )
        case .humanInterruptResolved:
            return .humanInterruptResolved(
                try GraphHumanInterruptResolvedPayload(from: decoder)
            )
        case .runTerminalStateRecorded:
            return .runTerminalStateRecorded(
                try GraphRunTerminalPayload(from: decoder)
            )
        case .schedulerEvaluationRecorded:
            return .schedulerEvaluationRecorded(
                try GraphSchedulerEvaluationPayload(from: decoder)
            )
        case .nodeBecameRunnable:
            return .nodeBecameRunnable(
                try GraphNodeSchedulingPayload(from: decoder)
            )
        case .nodeSchedulingDeferred:
            return .nodeSchedulingDeferred(
                try GraphNodeSchedulingPayload(from: decoder)
            )
        case .executorClaimRequested:
            return .executorClaimRequested(
                try GraphExecutorClaimPayload(from: decoder)
            )
        case .executorClaimGranted:
            return .executorClaimGranted(
                try GraphExecutorClaimPayload(from: decoder)
            )
        case .executorClaimRejected:
            return .executorClaimRejected(
                try GraphExecutorClaimRejectedPayload(from: decoder)
            )
        case .executorLeaseRenewed:
            return .executorLeaseRenewed(
                try GraphExecutorClaimPayload(from: decoder)
            )
        case .executorLeaseExpired:
            return .executorLeaseExpired(
                try GraphExecutorLeaseEndedPayload(from: decoder)
            )
        case .executorClaimReleased:
            return .executorClaimReleased(
                try GraphExecutorLeaseEndedPayload(from: decoder)
            )
        case .retryScheduled:
            return .retryScheduled(
                try GraphRetryScheduledPayload(from: decoder)
            )
        case .retryRequested:
            return .retryRequested(
                try GraphRetryRequestedPayload(from: decoder)
            )
        case .retrySuppressed:
            return .retrySuppressed(
                try GraphRetrySuppressedPayload(from: decoder)
            )
        case .cancellationRequested:
            return .cancellationRequested(
                try GraphCancellationRequestedPayload(from: decoder)
            )
        case .cancellationAcknowledged:
            return .cancellationAcknowledged(
                try GraphCancellationAcknowledgedPayload(from: decoder)
            )
        case .timeoutDeclared:
            return .timeoutDeclared(
                try GraphTimeoutDeclaredPayload(from: decoder)
            )
        case .dependencyFailurePropagated:
            return .dependencyFailurePropagated(
                try GraphDependencyFailurePropagatedPayload(
                    from: decoder
                )
            )
        case .schedulerCycleCompleted:
            return .schedulerCycleCompleted(
                try GraphSchedulerCycleCompletedPayload(from: decoder)
            )
        case nil:
            return .unknown(
                eventType: eventType,
                body: try GraphJSONValue(from: decoder)
            )
        }
    }

    private static func encodePayload(
        _ payload: GraphExecutionEventPayload,
        to encoder: Encoder
    ) throws {
        switch payload {
        case let .runCreated(value):
            try value.encode(to: encoder)
        case let .runStartRequested(value):
            try value.encode(to: encoder)
        case let .nodeRegistered(value):
            try value.encode(to: encoder)
        case let .attemptCreated(value):
            try value.encode(to: encoder)
        case let .attemptStarting(value):
            try value.encode(to: encoder)
        case let .processIdentityObserved(value):
            try value.encode(to: encoder)
        case let .heartbeatObserved(value):
            try value.encode(to: encoder)
        case let .processExitObserved(value):
            try value.encode(to: encoder)
        case let .executorObservationRecorded(value):
            try value.encode(to: encoder)
        case let .attemptCompleted(value):
            try value.encode(to: encoder)
        case let .attemptFailed(value):
            try value.encode(to: encoder)
        case let .attemptInterrupted(value):
            try value.encode(to: encoder)
        case let .attemptOrphaned(value):
            try value.encode(to: encoder)
        case let .attemptCancelled(value):
            try value.encode(to: encoder)
        case let .artifactRecorded(value):
            try value.encode(to: encoder)
        case let .humanInterruptRequested(value):
            try value.encode(to: encoder)
        case let .humanInterruptResolved(value):
            try value.encode(to: encoder)
        case let .runTerminalStateRecorded(value):
            try value.encode(to: encoder)
        case let .schedulerEvaluationRecorded(value):
            try value.encode(to: encoder)
        case let .nodeBecameRunnable(value):
            try value.encode(to: encoder)
        case let .nodeSchedulingDeferred(value):
            try value.encode(to: encoder)
        case let .executorClaimRequested(value):
            try value.encode(to: encoder)
        case let .executorClaimGranted(value):
            try value.encode(to: encoder)
        case let .executorClaimRejected(value):
            try value.encode(to: encoder)
        case let .executorLeaseRenewed(value):
            try value.encode(to: encoder)
        case let .executorLeaseExpired(value):
            try value.encode(to: encoder)
        case let .executorClaimReleased(value):
            try value.encode(to: encoder)
        case let .retryScheduled(value):
            try value.encode(to: encoder)
        case let .retryRequested(value):
            try value.encode(to: encoder)
        case let .retrySuppressed(value):
            try value.encode(to: encoder)
        case let .cancellationRequested(value):
            try value.encode(to: encoder)
        case let .cancellationAcknowledged(value):
            try value.encode(to: encoder)
        case let .timeoutDeclared(value):
            try value.encode(to: encoder)
        case let .dependencyFailurePropagated(value):
            try value.encode(to: encoder)
        case let .schedulerCycleCompleted(value):
            try value.encode(to: encoder)
        case let .unknown(_, body):
            try body.encode(to: encoder)
        }
    }
}
