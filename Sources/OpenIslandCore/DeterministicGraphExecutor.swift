import CryptoKit
import Foundation

public enum GraphDeterministicTerminalOutcome:
    String,
    Codable,
    Sendable
{
    case succeed
    case retryableFailure = "retryable_failure"
    case nonRetryableFailure = "non_retryable_failure"
    case remainRunning = "remain_running"
    case interrupted
}

public enum GraphDeterministicCancellationBehavior:
    String,
    Codable,
    Sendable
{
    case acknowledge
    case ignoreUntilTimeout = "ignore_until_timeout"
}

public enum GraphDeterministicCrashPoint: String, Codable, Sendable {
    case afterAttemptStartPersistence = "after_attempt_start_persistence"
    case afterAcceptingStart = "after_accepting_start"
}

public struct GraphDeterministicAttemptScript:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public var id: String { "\(nodeID)#\(attemptOrdinal)" }

    public let nodeID: String
    public let attemptOrdinal: Int
    public let runningPollCount: Int
    public let terminalOutcome: GraphDeterministicTerminalOutcome
    public let failureCategory: String?
    public let cancellationBehavior: GraphDeterministicCancellationBehavior
    public let crashPoint: GraphDeterministicCrashPoint?
    public let artifactRoles: [GraphArtifactRole]
    public let duplicateObservations: Bool
    public let staleLeaseGenerationOffset: Int

    public init(
        nodeID: String,
        attemptOrdinal: Int,
        runningPollCount: Int = 0,
        terminalOutcome: GraphDeterministicTerminalOutcome = .succeed,
        failureCategory: String? = nil,
        cancellationBehavior: GraphDeterministicCancellationBehavior =
            .acknowledge,
        crashPoint: GraphDeterministicCrashPoint? = nil,
        artifactRoles: [GraphArtifactRole] = [.nodeOutput],
        duplicateObservations: Bool = false,
        staleLeaseGenerationOffset: Int = 0
    ) {
        self.nodeID = nodeID
        self.attemptOrdinal = attemptOrdinal
        self.runningPollCount = max(0, runningPollCount)
        self.terminalOutcome = terminalOutcome
        self.failureCategory = failureCategory
        self.cancellationBehavior = cancellationBehavior
        self.crashPoint = crashPoint
        self.artifactRoles = artifactRoles.sorted {
            $0.rawValue < $1.rawValue
        }
        self.duplicateObservations = duplicateObservations
        self.staleLeaseGenerationOffset = min(
            0,
            staleLeaseGenerationOffset
        )
    }
}

public struct GraphDeterministicExecutionScript:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let attempts: [GraphDeterministicAttemptScript]

    public init(
        schemaVersion: Int = 1,
        attempts: [GraphDeterministicAttemptScript]
    ) {
        self.schemaVersion = schemaVersion
        self.attempts = attempts.sorted {
            if $0.nodeID != $1.nodeID {
                return $0.nodeID < $1.nodeID
            }
            return $0.attemptOrdinal < $1.attemptOrdinal
        }
    }

    public func attempt(
        nodeID: String,
        ordinal: Int
    ) -> GraphDeterministicAttemptScript {
        attempts.first {
            $0.nodeID == nodeID && $0.attemptOrdinal == ordinal
        } ?? GraphDeterministicAttemptScript(
            nodeID: nodeID,
            attemptOrdinal: ordinal
        )
    }
}

public struct DeterministicGraphExecutor:
    GraphExecutorAdapter,
    Sendable
{
    public let capabilities: GraphExecutorCapabilities
    public let script: GraphDeterministicExecutionScript

    public init(
        executorID: String = "openisland.deterministic",
        capabilityIdentity: String = "deterministic-v1",
        capabilities: [String] = ["compendium"],
        script: GraphDeterministicExecutionScript
    ) {
        self.capabilities = GraphExecutorCapabilities(
            executorID: executorID,
            capabilityIdentity: capabilityIdentity,
            capabilities: capabilities,
            hostID: "in-process"
        )
        self.script = script
    }

    public func prepare(
        _ request: GraphExecutorPrepareRequest
    ) async throws -> GraphExecutorPrepareResponse {
        GraphExecutorPrepareResponse(
            observation: observation(
                operation: .prepare,
                status: .accepted,
                context: request.context
            )
        )
    }

    public func start(
        _ request: GraphExecutorStartRequest
    ) async throws -> GraphExecutorStartResponse {
        let attempt = scriptedAttempt(request.context)
        if attempt.crashPoint == .afterAttemptStartPersistence {
            throw GraphExecutorAdapterError.simulatedCrash(
                GraphDeterministicCrashPoint
                    .afterAttemptStartPersistence.rawValue
            )
        }
        return GraphExecutorStartResponse(
            observation: observation(
                operation: .start,
                status: attempt.crashPoint == .afterAcceptingStart
                    ? .accepted
                    : .started,
                context: request.context,
                script: attempt
            )
        )
    }

    public func observe(
        _ request: GraphExecutorObserveRequest
    ) async throws -> GraphExecutorObserveResponse {
        let attempt = scriptedAttempt(request.context)
        let status: GraphExecutorResponseStatus
        let failure: GraphExecutorFailure?
        if request.context.priorObservationCount
            < attempt.runningPollCount {
            status = .stillRunning
            failure = nil
        } else {
            (status, failure) = terminalStatus(attempt)
        }
        return GraphExecutorObserveResponse(
            observation: observation(
                operation: .observe,
                status: status,
                context: request.context,
                script: attempt,
                failure: failure
            )
        )
    }

    public func requestCancellation(
        _ request: GraphExecutorCancellationRequest
    ) async throws -> GraphExecutorCancellationResponse {
        let attempt = scriptedAttempt(request.context)
        return GraphExecutorCancellationResponse(
            observation: observation(
                operation: .requestCancellation,
                status: attempt.cancellationBehavior == .acknowledge
                    ? .cancelled
                    : .stillRunning,
                context: request.context,
                script: attempt
            )
        )
    }

    public func collectResult(
        _ request: GraphExecutorCollectResultRequest
    ) async throws -> GraphExecutorCollectResultResponse {
        let attempt = scriptedAttempt(request.context)
        let (status, failure) = terminalStatus(attempt)
        let artifacts = status == .succeeded
            ? attempt.artifactRoles.map {
                artifact(role: $0, context: request.context)
            }
            : []
        return GraphExecutorCollectResultResponse(
            observation: observation(
                operation: .collectResult,
                status: status,
                context: request.context,
                script: attempt,
                failure: failure,
                artifacts: artifacts
            )
        )
    }

    public func cleanup(
        _ request: GraphExecutorCleanupRequest
    ) async throws -> GraphExecutorCleanupResponse {
        GraphExecutorCleanupResponse(
            observation: observation(
                operation: .cleanup,
                status: .accepted,
                context: request.context
            )
        )
    }

    public func recover(
        _ request: GraphExecutorRecoverRequest
    ) async throws -> GraphExecutorRecoverResponse {
        GraphExecutorRecoverResponse(
            observation: observation(
                operation: .recover,
                status: .started,
                context: request.context,
                script: scriptedAttempt(request.context)
            )
        )
    }

    private func scriptedAttempt(
        _ context: GraphExecutorCommandContext
    ) -> GraphDeterministicAttemptScript {
        script.attempt(
            nodeID: context.identity.nodeID,
            ordinal: context.identity.attemptOrdinal
        )
    }

    private func terminalStatus(
        _ attempt: GraphDeterministicAttemptScript
    ) -> (GraphExecutorResponseStatus, GraphExecutorFailure?) {
        switch attempt.terminalOutcome {
        case .succeed:
            (.succeeded, nil)
        case .retryableFailure:
            (
                .failed,
                GraphExecutorFailure(
                    category: attempt.failureCategory ?? "transient",
                    retryable: true
                )
            )
        case .nonRetryableFailure:
            (
                .failed,
                GraphExecutorFailure(
                    category: attempt.failureCategory ?? "invalid_input",
                    retryable: false
                )
            )
        case .remainRunning:
            (.stillRunning, nil)
        case .interrupted:
            (.interrupted, nil)
        }
    }

    private func observation(
        operation: GraphExecutorOperation,
        status: GraphExecutorResponseStatus,
        context: GraphExecutorCommandContext,
        script: GraphDeterministicAttemptScript? = nil,
        failure: GraphExecutorFailure? = nil,
        artifacts: [GraphExecutorProducedArtifact] = []
    ) -> GraphExecutorObservation {
        let scripted = script ?? scriptedAttempt(context)
        let identity = fencedIdentity(
            context.identity,
            generationOffset: scripted.staleLeaseGenerationOffset
        )
        let count = scripted.duplicateObservations
            ? 0
            : context.priorObservationCount
        let material = [
            identity.runID,
            identity.nodeID,
            String(identity.attemptOrdinal),
            identity.claimID,
            String(identity.leaseGeneration),
            operation.rawValue,
            String(count),
            status.rawValue,
        ].joined(separator: "|")
        return GraphExecutorObservation(
            id: "det-\(DefaultGraphMutationService.stableID(material))",
            operation: operation,
            identity: identity,
            status: status,
            observedAt: context.logicalTime,
            failure: failure,
            artifacts: artifacts
        )
    }

    private func fencedIdentity(
        _ identity: GraphExecutorInteractionIdentity,
        generationOffset: Int
    ) -> GraphExecutorInteractionIdentity {
        let generation = generationOffset < 0
            ? identity.leaseGeneration
                .subtractingReportingOverflow(
                    UInt64(-generationOffset)
                ).partialValue
            : identity.leaseGeneration
        return GraphExecutorInteractionIdentity(
            runID: identity.runID,
            nodeID: identity.nodeID,
            attemptID: identity.attemptID,
            attemptOrdinal: identity.attemptOrdinal,
            claimID: identity.claimID,
            leaseGeneration: generation,
            executorID: identity.executorID
        )
    }

    private func artifact(
        role: GraphArtifactRole,
        context: GraphExecutorCommandContext
    ) -> GraphExecutorProducedArtifact {
        let material = [
            context.identity.runID,
            context.identity.nodeID,
            String(context.identity.attemptOrdinal),
            context.specification.operation,
            role.rawValue,
            context.inputArtifacts.map(\.id).joined(separator: ","),
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return GraphExecutorProducedArtifact(
            contentDigest: GraphContentDigest(
                algorithm: "sha256",
                value: digest
            ),
            mediaType: "application/json",
            role: role,
            storage: GraphArtifactStorageLocator(
                scheme: "deterministic",
                opaqueReference: digest
            )
        )
    }
}
