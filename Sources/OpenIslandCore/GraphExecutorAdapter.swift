import Foundation

public enum GraphExecutorOperation: String, Codable, CaseIterable, Sendable {
    case prepare
    case start
    case observe
    case requestCancellation = "request_cancellation"
    case collectResult = "collect_result"
    case cleanup
    case recover
}

public enum GraphExecutorResponseStatus:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case accepted
    case started
    case stillRunning = "still_running"
    case succeeded
    case failed
    case cancelled
    case interrupted
    case unavailable
    case rejected
    case identityMismatch = "identity_mismatch"
    case staleClaim = "stale_claim"
    case transientAdapterFailure = "transient_adapter_failure"

    public var isTerminalObservation: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .interrupted:
            true
        case .accepted, .started, .stillRunning, .unavailable,
             .rejected, .identityMismatch, .staleClaim,
             .transientAdapterFailure:
            false
        }
    }
}

public struct GraphExecutorInteractionIdentity:
    Equatable,
    Codable,
    Sendable
{
    public let runID: String
    public let nodeID: String
    public let attemptID: String
    public let attemptOrdinal: Int
    public let claimID: String
    public let leaseGeneration: UInt64
    public let executorID: String

    public init(
        runID: String,
        nodeID: String,
        attemptID: String,
        attemptOrdinal: Int,
        claimID: String,
        leaseGeneration: UInt64,
        executorID: String
    ) {
        self.runID = runID
        self.nodeID = nodeID
        self.attemptID = attemptID
        self.attemptOrdinal = attemptOrdinal
        self.claimID = claimID
        self.leaseGeneration = leaseGeneration
        self.executorID = executorID
    }
}

public struct GraphExecutorCorrelationMetadata:
    Equatable,
    Codable,
    Sendable
{
    public let correlationID: String
    public let causationID: String?
    public let attributes: [String: String]

    public init(
        correlationID: String,
        causationID: String? = nil,
        attributes: [String: String] = [:]
    ) {
        self.correlationID = correlationID
        self.causationID = causationID
        self.attributes = attributes
    }
}

public struct GraphExecutorCommandContext:
    Equatable,
    Codable,
    Sendable
{
    public let identity: GraphExecutorInteractionIdentity
    public let capabilityRequirement: [String]
    public let specification: GraphImmutableExecutionSpecification
    public let workspace: GraphExecutionWorkspaceContext
    public let environmentAllowlist: [String]
    public let inputArtifacts: [GraphArtifactReference]
    public let cancellation: GraphCancellationRecord?
    public let timeoutPolicy: GraphExecutionTimeoutPolicy
    public let correlation: GraphExecutorCorrelationMetadata
    public let priorObservationCount: Int
    public let logicalTime: Date

    public init(
        identity: GraphExecutorInteractionIdentity,
        capabilityRequirement: [String],
        specification: GraphImmutableExecutionSpecification,
        workspace: GraphExecutionWorkspaceContext,
        environmentAllowlist: [String],
        inputArtifacts: [GraphArtifactReference],
        cancellation: GraphCancellationRecord?,
        timeoutPolicy: GraphExecutionTimeoutPolicy,
        correlation: GraphExecutorCorrelationMetadata,
        priorObservationCount: Int,
        logicalTime: Date
    ) {
        self.identity = identity
        self.capabilityRequirement = capabilityRequirement.sorted()
        self.specification = specification
        self.workspace = workspace
        self.environmentAllowlist = environmentAllowlist.sorted()
        self.inputArtifacts = inputArtifacts.sorted { $0.id < $1.id }
        self.cancellation = cancellation
        self.timeoutPolicy = timeoutPolicy
        self.correlation = correlation
        self.priorObservationCount = priorObservationCount
        self.logicalTime = logicalTime
    }
}

public struct GraphExecutorFailure: Equatable, Codable, Sendable {
    public let category: String
    public let retryable: Bool

    public init(category: String, retryable: Bool) {
        self.category = category
        self.retryable = retryable
    }
}

public struct GraphExecutorProducedArtifact:
    Equatable,
    Codable,
    Sendable
{
    public let contentDigest: GraphContentDigest
    public let mediaType: String
    public let role: GraphArtifactRole
    public let storage: GraphArtifactStorageLocator
    public let sensitivity: GraphArtifactSensitivity

    public init(
        contentDigest: GraphContentDigest,
        mediaType: String,
        role: GraphArtifactRole,
        storage: GraphArtifactStorageLocator,
        sensitivity: GraphArtifactSensitivity = .internalUse
    ) {
        self.contentDigest = contentDigest
        self.mediaType = mediaType
        self.role = role
        self.storage = storage
        self.sensitivity = sensitivity
    }
}

public struct GraphExecutorObservation: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let operation: GraphExecutorOperation
    public let identity: GraphExecutorInteractionIdentity
    public let status: GraphExecutorResponseStatus
    public let observedAt: Date
    public let processIdentity: ProcessIdentity?
    public let failure: GraphExecutorFailure?
    public let artifacts: [GraphExecutorProducedArtifact]

    public init(
        schemaVersion: Int = GraphExecutionSchema.eventPayloadVersion,
        id: String,
        operation: GraphExecutorOperation,
        identity: GraphExecutorInteractionIdentity,
        status: GraphExecutorResponseStatus,
        observedAt: Date,
        processIdentity: ProcessIdentity? = nil,
        failure: GraphExecutorFailure? = nil,
        artifacts: [GraphExecutorProducedArtifact] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.operation = operation
        self.identity = identity
        self.status = status
        self.observedAt = observedAt
        self.processIdentity = processIdentity
        self.failure = failure
        self.artifacts = artifacts.sorted {
            if $0.role != $1.role {
                return $0.role.rawValue < $1.role.rawValue
            }
            return $0.contentDigest.value < $1.contentDigest.value
        }
    }
}

public struct GraphExecutorPrepareRequest: Equatable, Sendable {
    public let context: GraphExecutorCommandContext

    public init(context: GraphExecutorCommandContext) {
        self.context = context
    }
}

public struct GraphExecutorPrepareResponse: Equatable, Sendable {
    public let observation: GraphExecutorObservation

    public init(observation: GraphExecutorObservation) {
        self.observation = observation
    }
}

public struct GraphExecutorStartRequest: Equatable, Sendable {
    public let context: GraphExecutorCommandContext

    public init(context: GraphExecutorCommandContext) {
        self.context = context
    }
}

public struct GraphExecutorStartResponse: Equatable, Sendable {
    public let observation: GraphExecutorObservation

    public init(observation: GraphExecutorObservation) {
        self.observation = observation
    }
}

public struct GraphExecutorObserveRequest: Equatable, Sendable {
    public let context: GraphExecutorCommandContext

    public init(context: GraphExecutorCommandContext) {
        self.context = context
    }
}

public struct GraphExecutorObserveResponse: Equatable, Sendable {
    public let observation: GraphExecutorObservation

    public init(observation: GraphExecutorObservation) {
        self.observation = observation
    }
}

public struct GraphExecutorCancellationRequest: Equatable, Sendable {
    public let context: GraphExecutorCommandContext
    public let cancellationRequestID: String

    public init(
        context: GraphExecutorCommandContext,
        cancellationRequestID: String
    ) {
        self.context = context
        self.cancellationRequestID = cancellationRequestID
    }
}

public struct GraphExecutorCancellationResponse: Equatable, Sendable {
    public let observation: GraphExecutorObservation

    public init(observation: GraphExecutorObservation) {
        self.observation = observation
    }
}

public struct GraphExecutorCollectResultRequest: Equatable, Sendable {
    public let context: GraphExecutorCommandContext

    public init(context: GraphExecutorCommandContext) {
        self.context = context
    }
}

public struct GraphExecutorCollectResultResponse: Equatable, Sendable {
    public let observation: GraphExecutorObservation

    public init(observation: GraphExecutorObservation) {
        self.observation = observation
    }
}

public struct GraphExecutorCleanupRequest: Equatable, Sendable {
    public let context: GraphExecutorCommandContext

    public init(context: GraphExecutorCommandContext) {
        self.context = context
    }
}

public struct GraphExecutorCleanupResponse: Equatable, Sendable {
    public let observation: GraphExecutorObservation

    public init(observation: GraphExecutorObservation) {
        self.observation = observation
    }
}

public struct GraphExecutorRecoverRequest: Equatable, Sendable {
    public let context: GraphExecutorCommandContext

    public init(context: GraphExecutorCommandContext) {
        self.context = context
    }
}

public struct GraphExecutorRecoverResponse: Equatable, Sendable {
    public let observation: GraphExecutorObservation

    public init(observation: GraphExecutorObservation) {
        self.observation = observation
    }
}

public protocol GraphExecutorAdapter: Sendable {
    var capabilities: GraphExecutorCapabilities { get }

    func prepare(_ request: GraphExecutorPrepareRequest) async throws
        -> GraphExecutorPrepareResponse
    func start(_ request: GraphExecutorStartRequest) async throws
        -> GraphExecutorStartResponse
    func observe(_ request: GraphExecutorObserveRequest) async throws
        -> GraphExecutorObserveResponse
    func requestCancellation(
        _ request: GraphExecutorCancellationRequest
    ) async throws -> GraphExecutorCancellationResponse
    func collectResult(
        _ request: GraphExecutorCollectResultRequest
    ) async throws -> GraphExecutorCollectResultResponse
    func cleanup(_ request: GraphExecutorCleanupRequest) async throws
        -> GraphExecutorCleanupResponse
    func recover(_ request: GraphExecutorRecoverRequest) async throws
        -> GraphExecutorRecoverResponse
}

public enum GraphExecutorAdapterError: Error, Equatable, Sendable {
    case unavailable
    case unsupportedAdapter(String)
    case simulatedCrash(String)
    case invalidScript(String)
}

extension GraphExecutorAdapterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Executor adapter is unavailable."
        case let .unsupportedAdapter(kind):
            "Executor adapter \(kind) is not configured."
        case let .simulatedCrash(boundary):
            "Executor adapter crashed at \(boundary)."
        case let .invalidScript(message):
            "Deterministic executor script is invalid: \(message)"
        }
    }
}
