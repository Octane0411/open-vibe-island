import Foundation

public enum GraphReplayDiagnosticSeverity: String, Codable, Sendable {
    case information
    case warning
}

public enum GraphReplayDiagnosticCategory: String, Codable, Sendable {
    case exactDuplicate
    case unknownEvent
    case snapshotBoundary
}

public struct GraphReplayDiagnostic: Equatable, Codable, Sendable {
    public let severity: GraphReplayDiagnosticSeverity
    public let category: GraphReplayDiagnosticCategory
    public let message: String
    public let eventID: String?
    public let streamSequence: UInt64?

    public init(
        severity: GraphReplayDiagnosticSeverity,
        category: GraphReplayDiagnosticCategory,
        message: String,
        eventID: String? = nil,
        streamSequence: UInt64? = nil
    ) {
        self.severity = severity
        self.category = category
        self.message = message
        self.eventID = eventID
        self.streamSequence = streamSequence
    }
}

public enum GraphExecutionReplayError: Error, Equatable, Sendable {
    case eventIDCollision(eventID: String)
    case sequenceGap(expected: UInt64, actual: UInt64)
    case sequenceConflict(sequence: UInt64)
    case unsupportedEnvelopeSchema(found: Int, supported: Int)
    case unsupportedPayloadSchema(
        eventType: String,
        found: Int,
        supported: Int
    )
    case runIDMismatch(expected: String, actual: String)
    case duplicateRunCreation
    case missingRun(eventID: String)
    case missingNode(nodeID: String)
    case duplicateNode(nodeID: String)
    case missingAttempt(attemptID: String)
    case duplicateAttempt(attemptID: String)
    case attemptOrdinalRegression(
        nodeID: String,
        previous: Int,
        proposed: Int
    )
    case processIdentityChanged(attemptID: String)
    case terminalAttemptRegression(attemptID: String)
    case invalidTerminalRunState(ReconciledExecutionState)
    case terminalRunRegression(runID: String)
    case artifactProvenanceMismatch(artifactID: String)
    case artifactIDCollision(artifactID: String)
    case interruptIDCollision(requestID: String)
    case missingInterrupt(requestID: String)
    case interruptAlreadyResolved(requestID: String)
    case claimIDCollision(claimID: String)
    case duplicateActiveClaim(nodeID: String, attemptOrdinal: Int)
    case missingClaim(claimID: String)
    case claimGenerationMismatch(
        claimID: String,
        expected: UInt64,
        actual: UInt64
    )
    case retryOrdinalConflict(nodeID: String, ordinal: Int)
    case cancellationIDCollision(requestID: String)
    case missingCancellation(requestID: String)
    case cancellationAlreadyAcknowledged(requestID: String)
    case timeoutIDCollision(timeoutID: String)
    case invalidSnapshot(String)
}

extension GraphExecutionReplayError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .eventIDCollision(eventID):
            "Event ID \(eventID) has contradictory content."
        case let .sequenceGap(expected, actual):
            "Replay expected sequence \(expected), found \(actual)."
        case let .sequenceConflict(sequence):
            "Replay found contradictory events at sequence \(sequence)."
        case let .unsupportedEnvelopeSchema(found, supported):
            "Event envelope schema \(found) exceeds supported version \(supported)."
        case let .unsupportedPayloadSchema(eventType, found, supported):
            "Payload \(eventType) schema \(found) exceeds supported version \(supported)."
        case let .runIDMismatch(expected, actual):
            "Replay expected run \(expected), found \(actual)."
        case .duplicateRunCreation:
            "A run may only be created once."
        case let .missingRun(eventID):
            "Event \(eventID) requires a run-created event."
        case let .missingNode(nodeID):
            "Graph node \(nodeID) is not registered."
        case let .duplicateNode(nodeID):
            "Graph node \(nodeID) is already registered."
        case let .missingAttempt(attemptID):
            "Execution attempt \(attemptID) does not exist."
        case let .duplicateAttempt(attemptID):
            "Execution attempt \(attemptID) already exists."
        case let .attemptOrdinalRegression(nodeID, previous, proposed):
            "Node \(nodeID) attempt ordinal must exceed \(previous), found \(proposed)."
        case let .processIdentityChanged(attemptID):
            "Attempt \(attemptID) changed process identity without migration."
        case let .terminalAttemptRegression(attemptID):
            "Terminal attempt \(attemptID) cannot transition again."
        case let .invalidTerminalRunState(state):
            "State \(state.rawValue) is not an authoritative run terminal declaration."
        case let .terminalRunRegression(runID):
            "Terminal run \(runID) cannot transition again."
        case let .artifactProvenanceMismatch(artifactID):
            "Artifact \(artifactID) provenance does not match its event envelope."
        case let .artifactIDCollision(artifactID):
            "Artifact ID \(artifactID) was reused with different metadata."
        case let .interruptIDCollision(requestID):
            "Human interrupt \(requestID) was requested more than once."
        case let .missingInterrupt(requestID):
            "Human interrupt \(requestID) does not exist."
        case let .interruptAlreadyResolved(requestID):
            "Human interrupt \(requestID) is already resolved."
        case let .claimIDCollision(claimID):
            "Executor claim ID \(claimID) has contradictory content."
        case let .duplicateActiveClaim(nodeID, ordinal):
            "Node \(nodeID) attempt \(ordinal) already has an active claim."
        case let .missingClaim(claimID):
            "Executor claim \(claimID) does not exist."
        case let .claimGenerationMismatch(claimID, expected, actual):
            "Executor claim \(claimID) expected generation \(expected), found \(actual)."
        case let .retryOrdinalConflict(nodeID, ordinal):
            "Node \(nodeID) has contradictory retry state for attempt \(ordinal)."
        case let .cancellationIDCollision(requestID):
            "Cancellation request ID \(requestID) has contradictory content."
        case let .missingCancellation(requestID):
            "Cancellation request \(requestID) does not exist."
        case let .cancellationAlreadyAcknowledged(requestID):
            "Cancellation request \(requestID) was already acknowledged."
        case let .timeoutIDCollision(timeoutID):
            "Timeout decision ID \(timeoutID) has contradictory content."
        case let .invalidSnapshot(message):
            "Invalid graph execution snapshot: \(message)"
        }
    }
}

public enum GraphHumanInterruptState: String, Codable, Sendable {
    case pending
    case resolved
}

public struct GraphHumanInterruptRecord: Equatable, Identifiable, Codable, Sendable {
    public var id: String {
        request.requestID
    }

    public let runID: String
    public let nodeID: String?
    public let attemptID: String?
    public let requestedAt: Date
    public let request: GraphHumanInterruptRequestedPayload
    public var state: GraphHumanInterruptState
    public var resolvedAt: Date?
    public var resolution: GraphHumanInterruptResolvedPayload?

    public init(
        runID: String,
        nodeID: String?,
        attemptID: String?,
        requestedAt: Date,
        request: GraphHumanInterruptRequestedPayload,
        state: GraphHumanInterruptState = .pending,
        resolvedAt: Date? = nil,
        resolution: GraphHumanInterruptResolvedPayload? = nil
    ) {
        self.runID = runID
        self.nodeID = nodeID
        self.attemptID = attemptID
        self.requestedAt = requestedAt
        self.request = request
        self.state = state
        self.resolvedAt = resolvedAt
        self.resolution = resolution
    }
}

public struct GraphExecutionProjection: Equatable, Codable, Sendable {
    public let runID: String
    public var streamVersion: UInt64
    public var run: GraphRun?
    public var nodes: [GraphNode]
    public var attempts: [ExecutionAttempt]
    public var processExits: [ProcessExit]
    public var heartbeats: [ExecutorHeartbeat]
    public var executionEvents: [ExecutionEvent]
    public var artifacts: [GraphArtifactReference]
    public var humanInterrupts: [GraphHumanInterruptRecord]
    public var unknownEvents: [GraphExecutionEventEnvelope]
    public var graphDefinitionVersion: String?
    public var graphDefinitionDigest: GraphContentDigest?
    public var checkpointNamespace: String
    public var parentRunID: String?
    public var parentCheckpoint: GraphCheckpointReference?
    public var namedCheckpoints: [GraphCheckpointReference]
    public var scheduling: GraphSchedulingProjection

    public init(
        runID: String,
        streamVersion: UInt64 = 0,
        run: GraphRun? = nil,
        nodes: [GraphNode] = [],
        attempts: [ExecutionAttempt] = [],
        processExits: [ProcessExit] = [],
        heartbeats: [ExecutorHeartbeat] = [],
        executionEvents: [ExecutionEvent] = [],
        artifacts: [GraphArtifactReference] = [],
        humanInterrupts: [GraphHumanInterruptRecord] = [],
        unknownEvents: [GraphExecutionEventEnvelope] = [],
        graphDefinitionVersion: String? = nil,
        graphDefinitionDigest: GraphContentDigest? = nil,
        checkpointNamespace: String = "root",
        parentRunID: String? = nil,
        parentCheckpoint: GraphCheckpointReference? = nil,
        namedCheckpoints: [GraphCheckpointReference] = [],
        scheduling: GraphSchedulingProjection =
            GraphSchedulingProjection()
    ) {
        self.runID = runID
        self.streamVersion = streamVersion
        self.run = run
        self.nodes = nodes
        self.attempts = attempts
        self.processExits = processExits
        self.heartbeats = heartbeats
        self.executionEvents = executionEvents
        self.artifacts = artifacts
        self.humanInterrupts = humanInterrupts
        self.unknownEvents = unknownEvents
        self.graphDefinitionVersion = graphDefinitionVersion
        self.graphDefinitionDigest = graphDefinitionDigest
        self.checkpointNamespace = checkpointNamespace
        self.parentRunID = parentRunID
        self.parentCheckpoint = parentCheckpoint
        self.namedCheckpoints = namedCheckpoints
        self.scheduling = scheduling
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case streamVersion
        case run
        case nodes
        case attempts
        case processExits
        case heartbeats
        case executionEvents
        case artifacts
        case humanInterrupts
        case unknownEvents
        case graphDefinitionVersion
        case graphDefinitionDigest
        case checkpointNamespace
        case parentRunID
        case parentCheckpoint
        case namedCheckpoints
        case scheduling
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        runID = try values.decode(String.self, forKey: .runID)
        streamVersion = try values.decode(UInt64.self, forKey: .streamVersion)
        run = try values.decodeIfPresent(GraphRun.self, forKey: .run)
        nodes = try values.decode([GraphNode].self, forKey: .nodes)
        attempts = try values.decode(
            [ExecutionAttempt].self,
            forKey: .attempts
        )
        processExits = try values.decode(
            [ProcessExit].self,
            forKey: .processExits
        )
        heartbeats = try values.decode(
            [ExecutorHeartbeat].self,
            forKey: .heartbeats
        )
        executionEvents = try values.decode(
            [ExecutionEvent].self,
            forKey: .executionEvents
        )
        artifacts = try values.decode(
            [GraphArtifactReference].self,
            forKey: .artifacts
        )
        humanInterrupts = try values.decode(
            [GraphHumanInterruptRecord].self,
            forKey: .humanInterrupts
        )
        unknownEvents = try values.decode(
            [GraphExecutionEventEnvelope].self,
            forKey: .unknownEvents
        )
        graphDefinitionVersion = try values.decodeIfPresent(
            String.self,
            forKey: .graphDefinitionVersion
        )
        graphDefinitionDigest = try values.decodeIfPresent(
            GraphContentDigest.self,
            forKey: .graphDefinitionDigest
        )
        checkpointNamespace = try values.decode(
            String.self,
            forKey: .checkpointNamespace
        )
        parentRunID = try values.decodeIfPresent(
            String.self,
            forKey: .parentRunID
        )
        parentCheckpoint = try values.decodeIfPresent(
            GraphCheckpointReference.self,
            forKey: .parentCheckpoint
        )
        namedCheckpoints = try values.decode(
            [GraphCheckpointReference].self,
            forKey: .namedCheckpoints
        )
        scheduling = try values.decodeIfPresent(
            GraphSchedulingProjection.self,
            forKey: .scheduling
        ) ?? GraphSchedulingProjection()
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(runID, forKey: .runID)
        try values.encode(streamVersion, forKey: .streamVersion)
        try values.encodeIfPresent(run, forKey: .run)
        try values.encode(nodes, forKey: .nodes)
        try values.encode(attempts, forKey: .attempts)
        try values.encode(processExits, forKey: .processExits)
        try values.encode(heartbeats, forKey: .heartbeats)
        try values.encode(executionEvents, forKey: .executionEvents)
        try values.encode(artifacts, forKey: .artifacts)
        try values.encode(humanInterrupts, forKey: .humanInterrupts)
        try values.encode(unknownEvents, forKey: .unknownEvents)
        try values.encodeIfPresent(
            graphDefinitionVersion,
            forKey: .graphDefinitionVersion
        )
        try values.encodeIfPresent(
            graphDefinitionDigest,
            forKey: .graphDefinitionDigest
        )
        try values.encode(
            checkpointNamespace,
            forKey: .checkpointNamespace
        )
        try values.encodeIfPresent(parentRunID, forKey: .parentRunID)
        try values.encodeIfPresent(
            parentCheckpoint,
            forKey: .parentCheckpoint
        )
        try values.encode(namedCheckpoints, forKey: .namedCheckpoints)
        try values.encode(scheduling, forKey: .scheduling)
    }
}

public struct GraphExecutionReplayResult: Equatable, Sendable {
    public let projection: GraphExecutionProjection
    public let diagnostics: [GraphReplayDiagnostic]
    public let replayedEventCount: Int
    public let duplicateEventCount: Int

    public init(
        projection: GraphExecutionProjection,
        diagnostics: [GraphReplayDiagnostic],
        replayedEventCount: Int,
        duplicateEventCount: Int
    ) {
        self.projection = projection
        self.diagnostics = diagnostics
        self.replayedEventCount = replayedEventCount
        self.duplicateEventCount = duplicateEventCount
    }
}

public enum GraphExecutionProjector {
    public static func replay(
        runID: String,
        events: [GraphExecutionEventEnvelope],
        initialProjection: GraphExecutionProjection? = nil
    ) throws -> GraphExecutionReplayResult {
        var projection = try validatedInitialProjection(
            runID: runID,
            projection: initialProjection
        )
        var diagnostics: [GraphReplayDiagnostic] = []
        var seenByID: [String: GraphExecutionEventEnvelope] = [:]
        var seenBySequence: [UInt64: GraphExecutionEventEnvelope] = [:]
        var duplicateCount = 0
        var replayedCount = 0
        let ordered = events.sorted(by: eventIsOrderedBefore)

        for event in ordered {
            guard event.runID == runID else {
                throw GraphExecutionReplayError.runIDMismatch(
                    expected: runID,
                    actual: event.runID
                )
            }

            if let existing = seenByID[event.id] {
                guard existing == event else {
                    throw GraphExecutionReplayError.eventIDCollision(
                        eventID: event.id
                    )
                }

                duplicateCount += 1
                diagnostics.append(
                    GraphReplayDiagnostic(
                        severity: .information,
                        category: .exactDuplicate,
                        message: "Ignored exact duplicate event delivery.",
                        eventID: event.id,
                        streamSequence: event.streamSequence
                    )
                )
                continue
            }

            if let existing = seenBySequence[event.streamSequence] {
                if existing == event {
                    duplicateCount += 1
                    continue
                }

                throw GraphExecutionReplayError.sequenceConflict(
                    sequence: event.streamSequence
                )
            }

            let expectedSequence = projection.streamVersion + 1

            guard event.streamSequence == expectedSequence else {
                if event.streamSequence <= projection.streamVersion {
                    throw GraphExecutionReplayError.sequenceConflict(
                        sequence: event.streamSequence
                    )
                }

                throw GraphExecutionReplayError.sequenceGap(
                    expected: expectedSequence,
                    actual: event.streamSequence
                )
            }

            guard event.schemaVersion
                    <= GraphExecutionSchema.eventEnvelopeVersion else {
                throw GraphExecutionReplayError
                    .unsupportedEnvelopeSchema(
                        found: event.schemaVersion,
                        supported: GraphExecutionSchema.eventEnvelopeVersion
                    )
            }

            if event.payloadVersion
                > GraphExecutionSchema.eventPayloadVersion {
                guard case .unknown = event.payload else {
                    throw GraphExecutionReplayError
                        .unsupportedPayloadSchema(
                            eventType: event.eventType,
                            found: event.payloadVersion,
                            supported: GraphExecutionSchema
                                .eventPayloadVersion
                        )
                }
            }

            try apply(event, to: &projection)
            projection.streamVersion = event.streamSequence
            seenByID[event.id] = event
            seenBySequence[event.streamSequence] = event
            replayedCount += 1

            if case .unknown = event.payload {
                diagnostics.append(
                    GraphReplayDiagnostic(
                        severity: .warning,
                        category: .unknownEvent,
                        message: "Retained unknown event without applying semantics.",
                        eventID: event.id,
                        streamSequence: event.streamSequence
                    )
                )
            }
        }

        normalizeProjection(&projection)

        return GraphExecutionReplayResult(
            projection: projection,
            diagnostics: diagnostics,
            replayedEventCount: replayedCount,
            duplicateEventCount: duplicateCount
        )
    }

    private static func validatedInitialProjection(
        runID: String,
        projection: GraphExecutionProjection?
    ) throws -> GraphExecutionProjection {
        guard let projection else {
            return GraphExecutionProjection(runID: runID)
        }

        guard projection.runID == runID else {
            throw GraphExecutionReplayError.invalidSnapshot(
                "Projection run ID \(projection.runID) does not match \(runID)."
            )
        }

        return projection
    }

    private static func apply(
        _ event: GraphExecutionEventEnvelope,
        to projection: inout GraphExecutionProjection
    ) throws {
        switch event.payload {
        case let .runCreated(payload):
            guard projection.run == nil else {
                throw GraphExecutionReplayError.duplicateRunCreation
            }

            projection.run = GraphRun(
                id: event.runID,
                graphID: payload.graphID,
                state: .pending,
                nodeIDs: payload.nodeIDs,
                createdAt: event.occurredAt,
                updatedAt: event.occurredAt
            )
            projection.graphDefinitionVersion =
                payload.graphDefinitionVersion
            projection.graphDefinitionDigest =
                payload.graphDefinitionDigest
            projection.checkpointNamespace =
                payload.checkpointNamespace
            projection.parentRunID = payload.parentRunID
            projection.parentCheckpoint = payload.parentCheckpoint

        case let .nodeRegistered(payload):
            try requireRun(event: event, projection: projection)
            let nodeID = try requireNodeID(event)

            guard !projection.nodes.contains(where: {
                $0.id == nodeID
            }) else {
                throw GraphExecutionReplayError.duplicateNode(
                    nodeID: nodeID
                )
            }

            projection.nodes.append(
                GraphNode(
                    id: nodeID,
                    graphRunID: event.runID,
                    title: payload.title,
                    dependencyNodeIDs: payload.dependencyNodeIDs,
                    executorID: payload.executorID,
                    state: .pending,
                    updatedAt: event.occurredAt
                )
            )

        case let .attemptCreated(payload):
            try requireRun(event: event, projection: projection)
            let nodeID = try requireNodeID(event)
            let attemptID = try requireAttemptID(event)
            try requireNode(nodeID, projection: projection)

            guard !projection.attempts.contains(where: {
                $0.id == attemptID
            }) else {
                throw GraphExecutionReplayError.duplicateAttempt(
                    attemptID: attemptID
                )
            }

            let previousOrdinal = projection.attempts
                .filter { $0.nodeID == nodeID }
                .map(\.ordinal)
                .max() ?? 0

            guard payload.ordinal == previousOrdinal + 1 else {
                throw GraphExecutionReplayError.attemptOrdinalRegression(
                    nodeID: nodeID,
                    previous: previousOrdinal,
                    proposed: payload.ordinal
                )
            }

            projection.attempts.append(
                ExecutionAttempt(
                    id: attemptID,
                    graphRunID: event.runID,
                    nodeID: nodeID,
                    ordinal: payload.ordinal,
                    state: .pending,
                    createdAt: event.occurredAt,
                    updatedAt: event.occurredAt
                )
            )

        case let .attemptStarting(payload):
            let attemptIndex = try requireAttemptIndex(
                event: event,
                projection: projection
            )
            try requireNonterminalAttempt(
                projection.attempts[attemptIndex]
            )
            projection.attempts[attemptIndex].state = .running
            projection.attempts[attemptIndex].startedAt =
                projection.attempts[attemptIndex].startedAt
                    ?? event.occurredAt
            projection.attempts[attemptIndex].updatedAt =
                event.occurredAt
            projection.attempts[attemptIndex].statusReason =
                payload.reason
            updateNode(
                for: projection.attempts[attemptIndex],
                state: .running,
                at: event.occurredAt,
                projection: &projection
            )

            if projection.run?.startedAt == nil {
                projection.run?.startedAt = event.occurredAt
            }

            projection.run?.state = .running
            projection.run?.updatedAt = event.occurredAt
            projection.executionEvents.append(
                executionEvent(
                    from: event,
                    kind: .attemptStarted,
                    reason: payload.reason
                )
            )

        case let .processIdentityObserved(payload):
            let index = try requireAttemptIndex(
                event: event,
                projection: projection
            )
            try assignProcessIdentity(
                payload.processIdentity,
                attemptIndex: index,
                projection: &projection
            )

        case let .heartbeatObserved(payload):
            let index = try requireAttemptIndex(
                event: event,
                projection: projection
            )
            try assignProcessIdentity(
                payload.processIdentity,
                attemptIndex: index,
                projection: &projection
            )
            projection.heartbeats.append(
                ExecutorHeartbeat(
                    attemptID: projection.attempts[index].id,
                    processIdentity: payload.processIdentity,
                    observedAt: event.occurredAt,
                    validUntil: payload.validUntil
                )
            )

        case let .processExitObserved(payload):
            let index = try requireAttemptIndex(
                event: event,
                projection: projection
            )
            try assignProcessIdentity(
                payload.processIdentity,
                attemptIndex: index,
                projection: &projection
            )
            projection.processExits.append(
                ProcessExit(
                    attemptID: projection.attempts[index].id,
                    processIdentity: payload.processIdentity,
                    observedAt: event.occurredAt,
                    exitCode: payload.exitCode,
                    signal: payload.signal,
                    reason: payload.reason
                )
            )

        case let .attemptCompleted(payload):
            try applyTerminalAttempt(
                event,
                payload: payload,
                state: .completed,
                kind: .attemptCompleted,
                projection: &projection
            )
        case let .attemptFailed(payload):
            try applyTerminalAttempt(
                event,
                payload: payload,
                state: .failed,
                kind: .attemptFailed,
                projection: &projection
            )
        case let .attemptInterrupted(payload):
            try applyTerminalAttempt(
                event,
                payload: payload,
                state: .interrupted,
                kind: .attemptInterrupted,
                projection: &projection
            )
        case let .attemptOrphaned(payload):
            try applyTerminalAttempt(
                event,
                payload: payload,
                state: .orphaned,
                kind: .attemptOrphaned,
                projection: &projection
            )
        case let .attemptCancelled(payload):
            try applyTerminalAttempt(
                event,
                payload: payload,
                state: .cancelled,
                kind: .attemptCancelled,
                projection: &projection
            )

        case let .artifactRecorded(payload):
            let artifact = payload.artifact

            guard artifact.producingRunID == event.runID,
                  artifact.producingNodeID == event.nodeID,
                  artifact.producingAttemptID == event.attemptID else {
                throw GraphExecutionReplayError
                    .artifactProvenanceMismatch(
                        artifactID: artifact.id
                    )
            }

            _ = try requireAttemptIndex(
                event: event,
                projection: projection
            )

            if let existing = projection.artifacts.first(where: {
                $0.id == artifact.id
            }) {
                guard existing == artifact else {
                    throw GraphExecutionReplayError
                        .artifactIDCollision(artifactID: artifact.id)
                }
            } else {
                projection.artifacts.append(artifact)
            }

        case let .humanInterruptRequested(payload):
            try requireRun(event: event, projection: projection)

            guard !projection.humanInterrupts.contains(where: {
                $0.id == payload.requestID
            }) else {
                throw GraphExecutionReplayError.interruptIDCollision(
                    requestID: payload.requestID
                )
            }

            projection.humanInterrupts.append(
                GraphHumanInterruptRecord(
                    runID: event.runID,
                    nodeID: event.nodeID,
                    attemptID: event.attemptID,
                    requestedAt: event.occurredAt,
                    request: payload
                )
            )

        case let .humanInterruptResolved(payload):
            guard let index = projection.humanInterrupts.firstIndex(
                where: { $0.id == payload.requestID }
            ) else {
                throw GraphExecutionReplayError.missingInterrupt(
                    requestID: payload.requestID
                )
            }

            guard projection.humanInterrupts[index].state == .pending else {
                throw GraphExecutionReplayError.interruptAlreadyResolved(
                    requestID: payload.requestID
                )
            }

            projection.humanInterrupts[index].state = .resolved
            projection.humanInterrupts[index].resolvedAt =
                event.occurredAt
            projection.humanInterrupts[index].resolution = payload

        case let .runTerminalStateRecorded(payload):
            try requireRun(event: event, projection: projection)

            guard payload.state == .completed
                    || payload.state == .failed
                    || payload.state == .interrupted
                    || payload.state == .orphaned
                    || payload.state == .cancelled else {
                throw GraphExecutionReplayError.invalidTerminalRunState(
                    payload.state
                )
            }

            if projection.run?.state.isTerminal == true {
                throw GraphExecutionReplayError.terminalRunRegression(
                    runID: event.runID
                )
            }

            projection.run?.state = payload.state
            projection.run?.updatedAt = event.occurredAt
            projection.run?.finishedAt = event.occurredAt
            projection.executionEvents.append(
                executionEvent(
                    from: event,
                    kind: runEventKind(for: payload.state),
                    reason: payload.reason
                )
            )

        case .schedulerEvaluationRecorded,
             .nodeBecameRunnable,
             .nodeSchedulingDeferred,
             .executorClaimRequested,
             .executorClaimGranted,
             .executorClaimRejected,
             .executorLeaseRenewed,
             .executorLeaseExpired,
             .executorClaimReleased,
             .retryScheduled,
             .retrySuppressed,
             .cancellationRequested,
             .cancellationAcknowledged,
             .timeoutDeclared,
             .dependencyFailurePropagated,
             .schedulerCycleCompleted:
            try applyScheduling(event, projection: &projection)

        case .unknown:
            projection.unknownEvents.append(event)
        }
    }

    private static func applyScheduling(
        _ event: GraphExecutionEventEnvelope,
        projection: inout GraphExecutionProjection
    ) throws {
        try requireRun(event: event, projection: projection)
        var evaluationID: String?
        var reason: GraphSchedulingReasonCode?

        switch event.payload {
        case let .schedulerEvaluationRecorded(payload):
            evaluationID = payload.evaluationID
            if !projection.scheduling.evaluations.contains(where: {
                $0.evaluationID == payload.evaluationID
            }) {
                projection.scheduling.evaluations.append(payload)
            }

        case let .nodeBecameRunnable(payload),
             let .nodeSchedulingDeferred(payload):
            _ = try requireNodeID(event)
            evaluationID = payload.evaluationID
            reason = payload.reason

        case let .executorClaimRequested(payload):
            try validateClaimEnvelope(payload.claim, event: event)
            reason = payload.reason

        case let .executorClaimGranted(payload):
            try validateClaimEnvelope(payload.claim, event: event)
            let claim = payload.claim

            if let existing = projection.scheduling.claims.first(
                where: { $0.claim.id == claim.id }
            ) {
                guard existing.claim == claim else {
                    throw GraphExecutionReplayError.claimIDCollision(
                        claimID: claim.id
                    )
                }
            } else {
                guard !projection.scheduling.claims.contains(where: {
                    $0.claim.nodeID == claim.nodeID
                        && $0.claim.attemptOrdinal == claim.attemptOrdinal
                        && $0.status == .active
                }) else {
                    throw GraphExecutionReplayError.duplicateActiveClaim(
                        nodeID: claim.nodeID,
                        attemptOrdinal: claim.attemptOrdinal
                    )
                }
                projection.scheduling.claims.append(
                    GraphExecutorClaimRecord(
                        claim: claim,
                        statusChangedAt: event.occurredAt,
                        reason: payload.reason
                    )
                )
            }
            reason = payload.reason

        case let .executorClaimRejected(payload):
            _ = try requireNodeID(event)
            reason = payload.reason

        case let .executorLeaseRenewed(payload):
            let renewed = payload.claim
            guard let index = projection.scheduling.claims.firstIndex(
                where: { $0.claim.id == renewed.id }
            ) else {
                throw GraphExecutionReplayError.missingClaim(
                    claimID: renewed.id
                )
            }
            let current = projection.scheduling.claims[index].claim
            guard projection.scheduling.claims[index].status == .active,
                  renewed.runID == current.runID,
                  renewed.nodeID == current.nodeID,
                  renewed.attemptOrdinal == current.attemptOrdinal,
                  renewed.executorID == current.executorID,
                  renewed.executorCapabilityIdentity
                    == current.executorCapabilityIdentity,
                  renewed.hostID == current.hostID,
                  renewed.grantedSequence == current.grantedSequence,
                  renewed.leaseGeneration == current.leaseGeneration + 1
            else {
                throw GraphExecutionReplayError.claimGenerationMismatch(
                    claimID: renewed.id,
                    expected: current.leaseGeneration + 1,
                    actual: renewed.leaseGeneration
                )
            }
            projection.scheduling.claims[index].claim = renewed
            projection.scheduling.claims[index].statusChangedAt =
                event.occurredAt
            projection.scheduling.claims[index].reason = payload.reason
            reason = payload.reason

        case let .executorLeaseExpired(payload):
            try endClaim(
                payload,
                status: .expired,
                at: event.occurredAt,
                projection: &projection
            )
            reason = payload.reason

        case let .executorClaimReleased(payload):
            try endClaim(
                payload,
                status: .released,
                at: event.occurredAt,
                projection: &projection
            )
            reason = payload.reason

        case let .retryScheduled(payload):
            let retry = payload.retry
            guard retry.nodeID == event.nodeID else {
                throw GraphExecutionReplayError.missingNode(
                    nodeID: retry.nodeID
                )
            }
            if let existing = projection.scheduling.retries.first(
                where: {
                    $0.nodeID == retry.nodeID
                        && $0.nextAttemptOrdinal
                            == retry.nextAttemptOrdinal
                }
            ) {
                guard existing == retry else {
                    throw GraphExecutionReplayError.retryOrdinalConflict(
                        nodeID: retry.nodeID,
                        ordinal: retry.nextAttemptOrdinal
                    )
                }
            } else {
                projection.scheduling.retries.append(retry)
            }
            reason = retry.reason

        case let .retrySuppressed(payload):
            reason = payload.reason

        case let .cancellationRequested(payload):
            let cancellation = payload.cancellation
            guard cancellation.runID == event.runID,
                  cancellation.nodeID == event.nodeID,
                  cancellation.attemptID == event.attemptID else {
                throw GraphExecutionReplayError.cancellationIDCollision(
                    requestID: cancellation.id
                )
            }
            if let existing = projection.scheduling.cancellations.first(
                where: { $0.id == cancellation.id }
            ) {
                guard existing == cancellation else {
                    throw GraphExecutionReplayError
                        .cancellationIDCollision(
                            requestID: cancellation.id
                        )
                }
            } else {
                projection.scheduling.cancellations.append(cancellation)
            }
            reason = .cancellationPending

        case let .cancellationAcknowledged(payload):
            guard let index = projection.scheduling.cancellations
                .firstIndex(where: { $0.id == payload.requestID }) else {
                throw GraphExecutionReplayError.missingCancellation(
                    requestID: payload.requestID
                )
            }
            guard projection.scheduling.cancellations[index].state
                    == .requested else {
                throw GraphExecutionReplayError
                    .cancellationAlreadyAcknowledged(
                        requestID: payload.requestID
                    )
            }
            guard projection.scheduling.cancellations[index].claimID
                    == payload.claimID else {
                throw GraphExecutionReplayError.claimIDCollision(
                    claimID: payload.claimID ?? "unclaimed"
                )
            }
            projection.scheduling.cancellations[index].state =
                .acknowledged
            projection.scheduling.cancellations[index].acknowledgedAt =
                payload.acknowledgedAt
            projection.scheduling.cancellations[index]
                .acknowledgedByExecutorID = payload.executorID
            reason = .cancellationAcknowledged

        case let .timeoutDeclared(payload):
            if let existing = projection.scheduling.timeouts.first(
                where: { $0.id == payload.timeout.id }
            ) {
                guard existing == payload.timeout else {
                    throw GraphExecutionReplayError.timeoutIDCollision(
                        timeoutID: payload.timeout.id
                    )
                }
            } else {
                projection.scheduling.timeouts.append(payload.timeout)
            }
            reason = payload.timeout.reason

        case let .dependencyFailurePropagated(payload):
            evaluationID = payload.evaluationID
            reason = payload.reason

        case let .schedulerCycleCompleted(payload):
            evaluationID = payload.evaluationID
            if !projection.scheduling.completedEvaluationIDs.contains(
                payload.evaluationID
            ) {
                projection.scheduling.completedEvaluationIDs.append(
                    payload.evaluationID
                )
            }

        default:
            return
        }

        projection.scheduling.records.append(
            GraphSchedulingRecord(
                id: event.id,
                sequence: event.streamSequence,
                eventType: event.eventType,
                factClass: event.factClass,
                nodeID: event.nodeID,
                attemptID: event.attemptID,
                evaluationID: evaluationID,
                reason: reason,
                occurredAt: event.occurredAt
            )
        )
    }

    private static func validateClaimEnvelope(
        _ claim: GraphExecutorClaim,
        event: GraphExecutionEventEnvelope
    ) throws {
        guard claim.runID == event.runID,
              claim.nodeID == event.nodeID else {
            throw GraphExecutionReplayError.claimIDCollision(
                claimID: claim.id
            )
        }
    }

    private static func endClaim(
        _ payload: GraphExecutorLeaseEndedPayload,
        status: GraphExecutorClaimStatus,
        at occurredAt: Date,
        projection: inout GraphExecutionProjection
    ) throws {
        guard let index = projection.scheduling.claims.firstIndex(
            where: { $0.claim.id == payload.claimID }
        ) else {
            throw GraphExecutionReplayError.missingClaim(
                claimID: payload.claimID
            )
        }
        let claim = projection.scheduling.claims[index].claim
        guard claim.leaseGeneration == payload.leaseGeneration else {
            throw GraphExecutionReplayError.claimGenerationMismatch(
                claimID: payload.claimID,
                expected: claim.leaseGeneration,
                actual: payload.leaseGeneration
            )
        }
        projection.scheduling.claims[index].status = status
        projection.scheduling.claims[index].statusChangedAt = occurredAt
        projection.scheduling.claims[index].reason = payload.reason
    }

    private static func applyTerminalAttempt(
        _ event: GraphExecutionEventEnvelope,
        payload: GraphAttemptTerminalPayload,
        state: ReconciledExecutionState,
        kind: ExecutionEventKind,
        projection: inout GraphExecutionProjection
    ) throws {
        let index = try requireAttemptIndex(
            event: event,
            projection: projection
        )
        try requireNonterminalAttempt(projection.attempts[index])
        projection.attempts[index].state = state
        projection.attempts[index].updatedAt = event.occurredAt
        projection.attempts[index].finishedAt = event.occurredAt
        projection.attempts[index].statusReason = payload.reason
        updateNode(
            for: projection.attempts[index],
            state: state,
            at: event.occurredAt,
            projection: &projection
        )
        projection.executionEvents.append(
            executionEvent(
                from: event,
                kind: kind,
                reason: payload.reason
            )
        )
    }

    private static func requireRun(
        event: GraphExecutionEventEnvelope,
        projection: GraphExecutionProjection
    ) throws {
        guard projection.run != nil else {
            throw GraphExecutionReplayError.missingRun(
                eventID: event.id
            )
        }
    }

    private static func requireNodeID(
        _ event: GraphExecutionEventEnvelope
    ) throws -> String {
        guard let nodeID = event.nodeID else {
            throw GraphExecutionReplayError.missingNode(
                nodeID: "<missing>"
            )
        }

        return nodeID
    }

    private static func requireAttemptID(
        _ event: GraphExecutionEventEnvelope
    ) throws -> String {
        guard let attemptID = event.attemptID else {
            throw GraphExecutionReplayError.missingAttempt(
                attemptID: "<missing>"
            )
        }

        return attemptID
    }

    private static func requireNode(
        _ nodeID: String,
        projection: GraphExecutionProjection
    ) throws {
        guard projection.nodes.contains(where: {
            $0.id == nodeID
        }) else {
            throw GraphExecutionReplayError.missingNode(nodeID: nodeID)
        }
    }

    private static func requireAttemptIndex(
        event: GraphExecutionEventEnvelope,
        projection: GraphExecutionProjection
    ) throws -> Int {
        let attemptID = try requireAttemptID(event)

        guard let index = projection.attempts.firstIndex(where: {
            $0.id == attemptID
        }) else {
            throw GraphExecutionReplayError.missingAttempt(
                attemptID: attemptID
            )
        }

        if let nodeID = event.nodeID,
           projection.attempts[index].nodeID != nodeID {
            throw GraphExecutionReplayError.missingAttempt(
                attemptID: attemptID
            )
        }

        return index
    }

    private static func requireNonterminalAttempt(
        _ attempt: ExecutionAttempt
    ) throws {
        guard !attempt.state.isTerminal else {
            throw GraphExecutionReplayError.terminalAttemptRegression(
                attemptID: attempt.id
            )
        }
    }

    private static func assignProcessIdentity(
        _ identity: ProcessIdentity,
        attemptIndex: Int,
        projection: inout GraphExecutionProjection
    ) throws {
        if let existing = projection.attempts[attemptIndex]
            .processIdentity,
           existing != identity {
            throw GraphExecutionReplayError.processIdentityChanged(
                attemptID: projection.attempts[attemptIndex].id
            )
        }

        projection.attempts[attemptIndex].processIdentity = identity
    }

    private static func updateNode(
        for attempt: ExecutionAttempt,
        state: ReconciledExecutionState,
        at timestamp: Date,
        projection: inout GraphExecutionProjection
    ) {
        guard let index = projection.nodes.firstIndex(where: {
            $0.id == attempt.nodeID
        }) else {
            return
        }

        projection.nodes[index].state = state
        projection.nodes[index].activeAttemptID = attempt.id
        projection.nodes[index].updatedAt = timestamp
    }

    private static func executionEvent(
        from event: GraphExecutionEventEnvelope,
        kind: ExecutionEventKind,
        reason: String?
    ) -> ExecutionEvent {
        ExecutionEvent(
            id: event.id,
            graphRunID: event.runID,
            nodeID: event.nodeID,
            attemptID: event.attemptID,
            sequence: event.streamSequence,
            occurredAt: event.occurredAt,
            kind: kind,
            reason: reason
        )
    }

    private static func runEventKind(
        for state: ReconciledExecutionState
    ) -> ExecutionEventKind {
        switch state {
        case .completed:
            .runCompleted
        case .failed:
            .runFailed
        case .interrupted, .orphaned:
            .runInterrupted
        case .cancelled:
            .runCancelled
        case .pending, .ready, .running, .blocked:
            .runInterrupted
        }
    }

    private static func eventIsOrderedBefore(
        _ lhs: GraphExecutionEventEnvelope,
        _ rhs: GraphExecutionEventEnvelope
    ) -> Bool {
        if lhs.streamSequence != rhs.streamSequence {
            return lhs.streamSequence < rhs.streamSequence
        }

        return lhs.id < rhs.id
    }

    private static func normalizeProjection(
        _ projection: inout GraphExecutionProjection
    ) {
        projection.nodes.sort { $0.id < $1.id }
        projection.attempts.sort {
            if $0.nodeID != $1.nodeID {
                return $0.nodeID < $1.nodeID
            }

            if $0.ordinal != $1.ordinal {
                return $0.ordinal < $1.ordinal
            }

            return $0.id < $1.id
        }
        projection.processExits.sort {
            if $0.observedAt != $1.observedAt {
                return $0.observedAt < $1.observedAt
            }

            return $0.attemptID < $1.attemptID
        }
        projection.heartbeats.sort {
            if $0.observedAt != $1.observedAt {
                return $0.observedAt < $1.observedAt
            }

            return $0.attemptID < $1.attemptID
        }
        projection.executionEvents.sort {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }

            return $0.id < $1.id
        }
        projection.artifacts.sort { $0.id < $1.id }
        projection.humanInterrupts.sort { $0.id < $1.id }
        projection.unknownEvents.sort(by: eventIsOrderedBefore)
        projection.namedCheckpoints.sort {
            if $0.streamVersion != $1.streamVersion {
                return $0.streamVersion < $1.streamVersion
            }

            return $0.checkpointID < $1.checkpointID
        }
        projection.scheduling.records.sort {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.id < $1.id
        }
        projection.scheduling.evaluations.sort {
            $0.evaluationID < $1.evaluationID
        }
        projection.scheduling.claims.sort {
            if $0.claim.nodeID != $1.claim.nodeID {
                return $0.claim.nodeID < $1.claim.nodeID
            }
            if $0.claim.attemptOrdinal != $1.claim.attemptOrdinal {
                return $0.claim.attemptOrdinal
                    < $1.claim.attemptOrdinal
            }
            return $0.claim.id < $1.claim.id
        }
        projection.scheduling.retries.sort {
            if $0.nodeID != $1.nodeID {
                return $0.nodeID < $1.nodeID
            }
            return $0.nextAttemptOrdinal < $1.nextAttemptOrdinal
        }
        projection.scheduling.cancellations.sort { $0.id < $1.id }
        projection.scheduling.timeouts.sort { $0.id < $1.id }
        projection.scheduling.completedEvaluationIDs = Array(
            Set(projection.scheduling.completedEvaluationIDs)
        ).sorted()
    }
}
