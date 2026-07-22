import Foundation

public enum GraphExecutorFencingReason:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case runMismatch = "run_mismatch"
    case nodeMismatch = "node_mismatch"
    case attemptMismatch = "attempt_mismatch"
    case attemptOrdinalMismatch = "attempt_ordinal_mismatch"
    case claimMismatch = "claim_mismatch"
    case executorMismatch = "executor_mismatch"
    case leaseGenerationMismatch = "lease_generation_mismatch"
    case leaseExpired = "lease_expired"
    case claimInactive = "claim_inactive"
    case attemptTerminal = "attempt_terminal"
    case completionBeforeStart = "completion_before_start"
    case observationMissing = "observation_missing"
    case observationConflict = "observation_conflict"
    case terminalStatusMismatch = "terminal_status_mismatch"
    case artifactProvenanceMismatch = "artifact_provenance_mismatch"
    case cancellationOwnerMismatch = "cancellation_owner_mismatch"
    case expectedVersionConflict = "expected_version_conflict"
}

public enum GraphExecutorRepositoryError: Error, Equatable, Sendable {
    case rejected(GraphExecutorFencingReason, String)
    case notFound(String)
    case persistence(String)
}

extension GraphExecutorRepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .rejected(reason, message):
            "Executor observation rejected [\(reason.rawValue)]: \(message)"
        case let .notFound(runID):
            "Graph run \(runID) was not found."
        case let .persistence(message):
            "Executor persistence failed: \(message)"
        }
    }
}

public struct GraphExecutorPersistenceResult: Equatable, Sendable {
    public let appendResult: GraphExecutionAppendResult
    public let projection: GraphExecutionProjection
}

public struct GraphExecutorStartCommand: Equatable, Sendable {
    public let identity: GraphExecutorInteractionIdentity
    public let expectedVersion: UInt64
    public let logicalTime: Date
    public let producer: GraphExecutionProducer
    public let correlationID: String

    public init(
        identity: GraphExecutorInteractionIdentity,
        expectedVersion: UInt64,
        logicalTime: Date,
        producer: GraphExecutionProducer,
        correlationID: String
    ) {
        self.identity = identity
        self.expectedVersion = expectedVersion
        self.logicalTime = logicalTime
        self.producer = producer
        self.correlationID = correlationID
    }
}

public struct GraphExecutorObservationCommand: Equatable, Sendable {
    public let observation: GraphExecutorObservation
    public let expectedVersion: UInt64
    public let producer: GraphExecutionProducer
    public let correlationID: String

    public init(
        observation: GraphExecutorObservation,
        expectedVersion: UInt64,
        producer: GraphExecutionProducer,
        correlationID: String
    ) {
        self.observation = observation
        self.expectedVersion = expectedVersion
        self.producer = producer
        self.correlationID = correlationID
    }
}

public struct GraphExecutorTerminalDeclaration: Equatable, Sendable {
    public let identity: GraphExecutorInteractionIdentity
    public let observationID: String
    public let state: ReconciledExecutionState
    public let reason: String?
    public let expectedVersion: UInt64
    public let logicalTime: Date
    public let producer: GraphExecutionProducer
    public let correlationID: String

    public init(
        identity: GraphExecutorInteractionIdentity,
        observationID: String,
        state: ReconciledExecutionState,
        reason: String? = nil,
        expectedVersion: UInt64,
        logicalTime: Date,
        producer: GraphExecutionProducer,
        correlationID: String
    ) {
        self.identity = identity
        self.observationID = observationID
        self.state = state
        self.reason = reason
        self.expectedVersion = expectedVersion
        self.logicalTime = logicalTime
        self.producer = producer
        self.correlationID = correlationID
    }
}

public struct GraphExecutorCancellationAcknowledgement:
    Equatable,
    Sendable
{
    public let identity: GraphExecutorInteractionIdentity
    public let requestID: String
    public let expectedVersion: UInt64
    public let logicalTime: Date
    public let producer: GraphExecutionProducer

    public init(
        identity: GraphExecutorInteractionIdentity,
        requestID: String,
        expectedVersion: UInt64,
        logicalTime: Date,
        producer: GraphExecutionProducer
    ) {
        self.identity = identity
        self.requestID = requestID
        self.expectedVersion = expectedVersion
        self.logicalTime = logicalTime
        self.producer = producer
    }
}

public protocol GraphExecutorPersisting: Sendable {
    func recordStartRequest(
        _ command: GraphExecutorStartCommand
    ) async throws -> GraphExecutorPersistenceResult

    func recordObservation(
        _ command: GraphExecutorObservationCommand
    ) async throws -> GraphExecutorPersistenceResult

    func declareTerminal(
        _ declaration: GraphExecutorTerminalDeclaration
    ) async throws -> GraphExecutorPersistenceResult

    func acknowledgeCancellation(
        _ acknowledgement: GraphExecutorCancellationAcknowledgement
    ) async throws -> GraphExecutorPersistenceResult
}

public struct DefaultGraphExecutorRepository:
    GraphExecutorPersisting,
    Sendable
{
    private let eventStore: any GraphExecutionEventStore

    public init(eventStore: any GraphExecutionEventStore) {
        self.eventStore = eventStore
    }

    public func recordStartRequest(
        _ command: GraphExecutorStartCommand
    ) async throws -> GraphExecutorPersistenceResult {
        let loaded = try await load(command.identity.runID)
        try requireVersion(command.expectedVersion, loaded.version)
        _ = try currentOwnership(
            command.identity,
            at: command.logicalTime,
            projection: loaded.projection
        )
        let eventID = startEventID(command.identity)
        if let existing = loaded.events.first(where: { $0.id == eventID }) {
            guard case let .attemptStarting(payload) = existing.payload,
                  payload.identity == command.identity else {
                throw rejected(
                    .observationConflict,
                    "start request identity conflicts with durable history."
                )
            }
            return unchanged(loaded)
        }
        guard let attempt = loaded.projection.attempts.first(where: {
            $0.id == command.identity.attemptID
        }), !attempt.state.isTerminal else {
            throw rejected(
                .attemptTerminal,
                "terminal attempts cannot be started."
            )
        }
        let event = envelope(
            id: eventID,
            identity: command.identity,
            sequence: loaded.version + 1,
            occurredAt: command.logicalTime,
            producer: command.producer,
            correlationID: command.correlationID,
            payload: .attemptStarting(
                GraphAttemptStartingPayload(
                    reason: "executor_start_requested",
                    identity: command.identity
                )
            )
        )
        return try await append([event], loaded: loaded)
    }

    public func recordObservation(
        _ command: GraphExecutorObservationCommand
    ) async throws -> GraphExecutorPersistenceResult {
        let observation = command.observation
        let loaded = try await load(observation.identity.runID)
        try requireVersion(command.expectedVersion, loaded.version)
        _ = try currentOwnership(
            observation.identity,
            at: observation.observedAt,
            projection: loaded.projection
        )
        if let existing = loaded.projection.executorObservations.first(
            where: { $0.id == observation.id }
        ) {
            guard existing == observation else {
                throw rejected(
                    .observationConflict,
                    "observation ID was reused with different content."
                )
            }
            return unchanged(loaded)
        }
        var events: [GraphExecutionEventEnvelope] = []
        if let processIdentity = observation.processIdentity,
           loaded.projection.attempts.first(where: {
               $0.id == observation.identity.attemptID
           })?.processIdentity != processIdentity {
            events.append(
                envelope(
                    id: "process-identity-\(processIdentity.launchID)",
                    identity: observation.identity,
                    sequence: loaded.version + 1,
                    occurredAt: observation.observedAt,
                    producer: command.producer,
                    correlationID: command.correlationID,
                    payload: .processIdentityObserved(
                        GraphProcessIdentityObservedPayload(
                            processIdentity: processIdentity
                        )
                    )
                )
            )
        }
        events.append(
            envelope(
                id: "executor-observation-\(observation.id)",
                identity: observation.identity,
                sequence: loaded.version + UInt64(events.count) + 1,
                occurredAt: observation.observedAt,
                producer: command.producer,
                correlationID: command.correlationID,
                payload: .executorObservationRecorded(
                    GraphExecutorObservationPayload(
                        observation: observation
                    )
                )
            )
        )
        for artifact in observation.artifacts {
            let reference = try artifactReference(
                artifact,
                observation: observation
            )
            events.append(
                envelope(
                    id: "artifact-event-\(reference.id)",
                    identity: observation.identity,
                    sequence: loaded.version
                        + UInt64(events.count) + 1,
                    occurredAt: observation.observedAt,
                    producer: command.producer,
                    correlationID: command.correlationID,
                    payload: .artifactRecorded(
                        GraphArtifactRecordedPayload(
                            artifact: reference
                        )
                    )
                )
            )
        }
        return try await append(events, loaded: loaded)
    }

    public func declareTerminal(
        _ declaration: GraphExecutorTerminalDeclaration
    ) async throws -> GraphExecutorPersistenceResult {
        let loaded = try await load(declaration.identity.runID)
        let terminalID = terminalEventID(declaration.identity)
        if let existing = loaded.events.first(where: {
            $0.id == terminalID
        }) {
            guard terminalState(existing.payload) == declaration.state else {
                throw rejected(
                    .observationConflict,
                    "terminal declaration conflicts with durable history."
                )
            }
            return unchanged(loaded)
        }
        try requireVersion(declaration.expectedVersion, loaded.version)
        guard [.completed, .failed, .interrupted, .orphaned, .cancelled]
            .contains(declaration.state) else {
            throw rejected(
                .terminalStatusMismatch,
                "requested state is not terminal."
            )
        }
        let claim = try currentOwnership(
            declaration.identity,
            at: declaration.logicalTime,
            projection: loaded.projection
        )
        guard let lifecycle = loaded.projection.attemptLifecycles.first(
            where: { $0.attemptID == declaration.identity.attemptID }
        ), [.startRequested, .started, .running, .cancellationRequested]
            .contains(lifecycle.phase) else {
            throw rejected(
                .completionBeforeStart,
                "terminal declaration requires a durable start request."
            )
        }
        guard let observation = loaded.projection.executorObservations.first(
            where: { $0.id == declaration.observationID }
        ) else {
            throw rejected(
                .observationMissing,
                "terminal declaration requires a durable observation."
            )
        }
        guard observation.identity == declaration.identity else {
            throw rejected(
                .claimMismatch,
                "terminal observation belongs to another execution identity."
            )
        }
        guard Self.state(for: observation.status) == declaration.state else {
            throw rejected(
                .terminalStatusMismatch,
                "observation status does not justify the declaration."
            )
        }
        let artifactIDs = loaded.projection.artifacts.filter {
            $0.producingAttemptID == declaration.identity.attemptID
                && $0.producingClaimID == declaration.identity.claimID
        }.map(\.id).sorted()
        let attemptTerminalPayload = GraphAttemptTerminalPayload(
            reason: declaration.reason ?? observation.failure?.category,
            artifactIDs: artifactIDs
        )
        let terminalEvent = envelope(
            id: terminalID,
            identity: declaration.identity,
            sequence: loaded.version + 1,
            occurredAt: declaration.logicalTime,
            producer: declaration.producer,
            correlationID: declaration.correlationID,
            payload: terminalPayload(
                state: declaration.state,
                payload: attemptTerminalPayload
            )
        )
        let releaseEvent = envelope(
            id: "claim-release-\(claim.id)-\(claim.leaseGeneration)",
            identity: declaration.identity,
            sequence: loaded.version + 2,
            occurredAt: declaration.logicalTime,
            producer: declaration.producer,
            correlationID: declaration.correlationID,
            payload: .executorClaimReleased(
                GraphExecutorLeaseEndedPayload(
                    claimID: claim.id,
                    leaseGeneration: claim.leaseGeneration,
                    reason: .claimReleased
                )
            )
        )
        return try await append(
            [terminalEvent, releaseEvent],
            loaded: loaded
        )
    }

    public func acknowledgeCancellation(
        _ acknowledgement: GraphExecutorCancellationAcknowledgement
    ) async throws -> GraphExecutorPersistenceResult {
        let loaded = try await load(acknowledgement.identity.runID)
        try requireVersion(acknowledgement.expectedVersion, loaded.version)
        _ = try currentOwnership(
            acknowledgement.identity,
            at: acknowledgement.logicalTime,
            projection: loaded.projection
        )
        guard let cancellation = loaded.projection.scheduling
            .cancellations.first(where: {
                $0.id == acknowledgement.requestID
            }), cancellation.claimID == acknowledgement.identity.claimID,
            cancellation.attemptID == acknowledgement.identity.attemptID
        else {
            throw rejected(
                .cancellationOwnerMismatch,
                "cancellation does not belong to this execution identity."
            )
        }
        if cancellation.state == .acknowledged {
            guard cancellation.acknowledgedByExecutorID
                    == acknowledgement.identity.executorID else {
                throw rejected(
                    .cancellationOwnerMismatch,
                    "another executor acknowledged cancellation."
                )
            }
            return unchanged(loaded)
        }
        let event = envelope(
            id: "cancellation-ack-\(acknowledgement.requestID)",
            identity: acknowledgement.identity,
            sequence: loaded.version + 1,
            occurredAt: acknowledgement.logicalTime,
            producer: acknowledgement.producer,
            correlationID: acknowledgement.requestID,
            payload: .cancellationAcknowledged(
                GraphCancellationAcknowledgedPayload(
                    requestID: acknowledgement.requestID,
                    claimID: acknowledgement.identity.claimID,
                    executorID: acknowledgement.identity.executorID,
                    acknowledgedAt: acknowledgement.logicalTime
                )
            )
        )
        return try await append([event], loaded: loaded)
    }

    private struct Loaded {
        let version: UInt64
        let events: [GraphExecutionEventEnvelope]
        let projection: GraphExecutionProjection
    }

    private func load(_ runID: String) async throws -> Loaded {
        do {
            let stream = try await eventStore.read(
                runID: runID,
                afterVersion: 0
            )
            guard !stream.events.isEmpty else {
                throw GraphExecutorRepositoryError.notFound(runID)
            }
            return Loaded(
                version: stream.currentVersion,
                events: stream.events,
                projection: try GraphExecutionProjector.replay(
                    runID: runID,
                    events: stream.events
                ).projection
            )
        } catch let error as GraphExecutorRepositoryError {
            throw error
        } catch {
            throw GraphExecutorRepositoryError.persistence(
                error.localizedDescription
            )
        }
    }

    private func currentOwnership(
        _ identity: GraphExecutorInteractionIdentity,
        at logicalTime: Date,
        projection: GraphExecutionProjection
    ) throws -> GraphExecutorClaim {
        guard projection.runID == identity.runID else {
            throw rejected(.runMismatch, "run identity does not match.")
        }
        guard let attempt = projection.attempts.first(where: {
            $0.id == identity.attemptID
        }) else {
            throw rejected(.attemptMismatch, "attempt does not exist.")
        }
        guard attempt.nodeID == identity.nodeID else {
            throw rejected(.nodeMismatch, "node identity does not match.")
        }
        guard attempt.ordinal == identity.attemptOrdinal else {
            throw rejected(
                .attemptOrdinalMismatch,
                "attempt ordinal does not match."
            )
        }
        guard let record = projection.scheduling.claims.first(where: {
            $0.claim.id == identity.claimID
        }) else {
            throw rejected(.claimMismatch, "claim does not exist.")
        }
        let claim = record.claim
        guard claim.nodeID == identity.nodeID,
              claim.attemptOrdinal == identity.attemptOrdinal else {
            throw rejected(.claimMismatch, "claim target does not match.")
        }
        guard claim.executorID == identity.executorID else {
            throw rejected(
                .executorMismatch,
                "executor is not the claim owner."
            )
        }
        guard claim.leaseGeneration == identity.leaseGeneration else {
            throw rejected(
                .leaseGenerationMismatch,
                "lease fencing token is stale."
            )
        }
        guard record.status == .active else {
            throw rejected(.claimInactive, "claim is not active.")
        }
        guard claim.isValid(at: logicalTime) else {
            throw rejected(.leaseExpired, "claim lease has expired.")
        }
        return claim
    }

    private func artifactReference(
        _ artifact: GraphExecutorProducedArtifact,
        observation: GraphExecutorObservation
    ) throws -> GraphArtifactReference {
        guard !artifact.contentDigest.value.isEmpty,
              artifact.storage.scheme != "inline" else {
            throw rejected(
                .artifactProvenanceMismatch,
                "artifacts must be content-addressed references."
            )
        }
        let identity = observation.identity
        let material = [
            identity.runID,
            identity.nodeID,
            identity.attemptID,
            identity.claimID,
            artifact.role.rawValue,
            artifact.contentDigest.value,
        ].joined(separator: "|")
        let id = "artifact-\(DefaultGraphMutationService.stableID(material))"
        return GraphArtifactReference(
            id: id,
            contentDigest: artifact.contentDigest,
            mediaType: artifact.mediaType,
            logicalRole: artifact.role.rawValue,
            producingRunID: identity.runID,
            producingNodeID: identity.nodeID,
            producingAttemptID: identity.attemptID,
            producingAttemptOrdinal: identity.attemptOrdinal,
            producingClaimID: identity.claimID,
            createdAt: observation.observedAt,
            storage: artifact.storage,
            sensitivity: artifact.sensitivity
        )
    }

    private func append(
        _ events: [GraphExecutionEventEnvelope],
        loaded: Loaded
    ) async throws -> GraphExecutorPersistenceResult {
        do {
            let result = try await eventStore.append(
                events,
                to: loaded.projection.runID,
                expectedVersion: loaded.version
            )
            return GraphExecutorPersistenceResult(
                appendResult: result,
                projection: try GraphExecutionProjector.replay(
                    runID: loaded.projection.runID,
                    events: loaded.events + events
                ).projection
            )
        } catch let error as GraphExecutionPersistenceError {
            if case let .expectedVersionConflict(_, expected, actual) = error {
                throw rejected(
                    .expectedVersionConflict,
                    "expected \(expected), found \(actual)."
                )
            }
            throw GraphExecutorRepositoryError.persistence(
                error.localizedDescription
            )
        } catch let error as GraphExecutorRepositoryError {
            throw error
        } catch {
            throw GraphExecutorRepositoryError.persistence(
                error.localizedDescription
            )
        }
    }

    private func unchanged(
        _ loaded: Loaded
    ) -> GraphExecutorPersistenceResult {
        GraphExecutorPersistenceResult(
            appendResult: GraphExecutionAppendResult(
                previousVersion: loaded.version,
                newVersion: loaded.version,
                appendedCount: 0,
                deduplicatedCount: 1
            ),
            projection: loaded.projection
        )
    }

    private func requireVersion(
        _ expected: UInt64,
        _ actual: UInt64
    ) throws {
        guard expected == actual else {
            throw rejected(
                .expectedVersionConflict,
                "expected \(expected), found \(actual)."
            )
        }
    }

    private func envelope(
        id: String,
        identity: GraphExecutorInteractionIdentity,
        sequence: UInt64,
        occurredAt: Date,
        producer: GraphExecutionProducer,
        correlationID: String,
        payload: GraphExecutionEventPayload
    ) -> GraphExecutionEventEnvelope {
        GraphExecutionEventEnvelope(
            id: id,
            runID: identity.runID,
            nodeID: identity.nodeID,
            attemptID: identity.attemptID,
            streamSequence: sequence,
            occurredAt: occurredAt,
            recordedAt: occurredAt,
            producer: producer,
            correlationID: correlationID,
            payload: payload
        )
    }

    private func startEventID(
        _ identity: GraphExecutorInteractionIdentity
    ) -> String {
        "attempt-start-request-\(identity.claimID)-\(identity.leaseGeneration)"
    }

    private func terminalEventID(
        _ identity: GraphExecutorInteractionIdentity
    ) -> String {
        "attempt-terminal-\(identity.claimID)-\(identity.leaseGeneration)"
    }

    private func terminalPayload(
        state: ReconciledExecutionState,
        payload: GraphAttemptTerminalPayload
    ) -> GraphExecutionEventPayload {
        switch state {
        case .completed:
            .attemptCompleted(payload)
        case .failed:
            .attemptFailed(payload)
        case .interrupted:
            .attemptInterrupted(payload)
        case .orphaned:
            .attemptOrphaned(payload)
        case .cancelled:
            .attemptCancelled(payload)
        case .pending, .ready, .running, .blocked:
            .attemptFailed(payload)
        }
    }

    private func terminalState(
        _ payload: GraphExecutionEventPayload
    ) -> ReconciledExecutionState? {
        switch payload {
        case .attemptCompleted:
            .completed
        case .attemptFailed:
            .failed
        case .attemptInterrupted:
            .interrupted
        case .attemptOrphaned:
            .orphaned
        case .attemptCancelled:
            .cancelled
        default:
            nil
        }
    }

    private static func state(
        for status: GraphExecutorResponseStatus
    ) -> ReconciledExecutionState? {
        switch status {
        case .succeeded:
            .completed
        case .failed:
            .failed
        case .cancelled:
            .cancelled
        case .interrupted:
            .interrupted
        default:
            nil
        }
    }

    private func rejected(
        _ reason: GraphExecutorFencingReason,
        _ message: String
    ) -> GraphExecutorRepositoryError {
        .rejected(reason, message)
    }
}
