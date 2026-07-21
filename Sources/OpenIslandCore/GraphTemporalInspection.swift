import Foundation

public enum GraphInspectionError: Error, Equatable, Sendable {
    case runNotFound(String)
    case checkpointNotFound(runID: String, checkpointID: String)
    case invalidBoundary(runID: String, requested: UInt64, head: UInt64)
    case incompatibleSchema(String)
    case corruptHistory(String)
    case persistence(String)
    case evidenceUnavailable(String)
}

extension GraphInspectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .runNotFound(runID):
            "Graph run \(runID) was not found."
        case let .checkpointNotFound(runID, checkpointID):
            "Checkpoint \(checkpointID) was not found in run \(runID)."
        case let .invalidBoundary(runID, requested, head):
            "Run \(runID) cannot replay to sequence \(requested); its head is \(head)."
        case let .incompatibleSchema(message):
            "Incompatible graph schema: \(message)"
        case let .corruptHistory(message):
            "Corrupt graph history: \(message)"
        case let .persistence(message):
            "Graph persistence failure: \(message)"
        case let .evidenceUnavailable(message):
            "Required process evidence is unavailable: \(message)"
        }
    }
}

public enum GraphReplayBoundaryKind: String, Codable, Sendable {
    case head
    case sequence
    case checkpoint
}

public struct GraphReplayBoundary: Equatable, Codable, Sendable {
    public let kind: GraphReplayBoundaryKind
    public let sequence: UInt64?
    public let checkpointID: String?

    public init(
        kind: GraphReplayBoundaryKind,
        sequence: UInt64? = nil,
        checkpointID: String? = nil
    ) {
        self.kind = kind
        self.sequence = sequence
        self.checkpointID = checkpointID
    }

    public static let head = GraphReplayBoundary(kind: .head)

    public static func sequence(_ value: UInt64) -> GraphReplayBoundary {
        GraphReplayBoundary(kind: .sequence, sequence: value)
    }

    public static func checkpoint(_ id: String) -> GraphReplayBoundary {
        GraphReplayBoundary(kind: .checkpoint, checkpointID: id)
    }
}

public struct GraphTemporalReference: Equatable, Codable, Sendable {
    public let runID: String
    public let boundary: GraphReplayBoundary

    public init(
        runID: String,
        boundary: GraphReplayBoundary = .head
    ) {
        self.runID = runID
        self.boundary = boundary
    }
}

public enum GraphInspectionEvidenceMode: String, Codable, Sendable {
    case configured
    case withoutLiveEvidence
    case requireAvailable
}

public struct GraphEvidenceInspection: Equatable, Codable, Sendable {
    public let status: String
    public let reason: String?

    public init(status: String, reason: String?) {
        self.status = status
        self.reason = reason
    }
}

public enum GraphRedactionReason: String, Codable, Sendable {
    case sensitiveByDefault = "sensitive_by_default"
    case sensitivityClassification = "sensitivity_classification"
    case credentialBearingValue = "credential_bearing_value"
    case unsupportedPayload = "unsupported_payload"
}

public struct GraphRedactionRecord: Equatable, Codable, Sendable {
    public let field: String
    public let reason: GraphRedactionReason

    public init(field: String, reason: GraphRedactionReason) {
        self.field = field
        self.reason = reason
    }
}

public struct GraphArtifactInspection:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let schemaVersion: Int
    public let id: String
    public let digestAlgorithm: String
    public let digest: String
    public let mediaType: String
    public let logicalRole: String
    public let producingRunID: String
    public let producingNodeID: String
    public let producingAttemptID: String
    public let createdAt: Date
    public let storageScheme: String
    public let sensitivity: GraphArtifactSensitivity
    public let redactions: [GraphRedactionRecord]

    public init(reference: GraphArtifactReference) {
        schemaVersion = reference.schemaVersion
        id = reference.id
        digestAlgorithm = reference.contentDigest.algorithm
        digest = reference.contentDigest.value
        mediaType = reference.mediaType
        logicalRole = reference.logicalRole
        producingRunID = reference.producingRunID
        producingNodeID = reference.producingNodeID
        producingAttemptID = reference.producingAttemptID
        createdAt = reference.createdAt
        storageScheme = reference.storage.scheme
        sensitivity = reference.sensitivity
        redactions = [
            GraphRedactionRecord(
                field: "storage.opaqueReference",
                reason: reference.sensitivity == .unspecified
                    ? .sensitiveByDefault
                    : .sensitivityClassification
            ),
        ]
    }
}

public struct GraphRunInspectionSummary:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public var id: String {
        runID
    }

    public let runID: String
    public let graphID: String
    public let persistedState: ReconciledExecutionState
    public let reconciledState: ReconciledExecutionState
    public let streamVersion: UInt64
    public let nodeCount: Int
    public let attemptCount: Int
    public let artifactCount: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let snapshotDisposition: GraphSnapshotDisposition
    public let evidence: GraphEvidenceInspection
}

public struct GraphNodeInspection:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public let title: String
    public let dependencyNodeIDs: [String]
    public let executorID: String?
    public let persistedState: ReconciledExecutionState
    public let reconciledState: ReconciledExecutionState
    public let activeAttemptID: String?
    public let updatedAt: Date
}

public struct GraphAttemptInspection:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public let nodeID: String
    public let ordinal: Int
    public let persistedState: ReconciledExecutionState
    public let reconciledState: ReconciledExecutionState
    public let hasProcessIdentity: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let startedAt: Date?
    public let finishedAt: Date?
    public let statusReason: String?
}

public struct GraphExecutorClaimInspection:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public let nodeID: String
    public let attemptOrdinal: Int
    public let executorID: String
    public let executorCapabilityIdentity: String
    public let grantedSequence: UInt64
    public let leaseStart: Date
    public let leaseExpiry: Date
    public let leaseGeneration: UInt64
    public let status: GraphExecutorClaimStatus
    public let statusChangedAt: Date
    public let reason: GraphSchedulingReasonCode
    public let hostIdentityPresent: Bool

    public init(record: GraphExecutorClaimRecord) {
        id = record.claim.id
        nodeID = record.claim.nodeID
        attemptOrdinal = record.claim.attemptOrdinal
        executorID = record.claim.executorID
        executorCapabilityIdentity =
            record.claim.executorCapabilityIdentity
        grantedSequence = record.claim.grantedSequence
        leaseStart = record.claim.leaseStart
        leaseExpiry = record.claim.leaseExpiry
        leaseGeneration = record.claim.leaseGeneration
        status = record.status
        statusChangedAt = record.statusChangedAt
        reason = record.reason
        hostIdentityPresent = record.claim.hostID != nil
    }
}

public struct GraphSchedulingInspection: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let latestEvaluation: GraphSchedulerEvaluationPayload?
    public let currentPolicy: GraphSchedulerPolicy?
    public let activeClaims: [GraphExecutorClaimInspection]
    public let claimHistory: [GraphExecutorClaimInspection]
    public let retries: [GraphRetryRecord]
    public let pendingCancellations: [GraphCancellationRecord]
    public let cancellationHistory: [GraphCancellationRecord]
    public let timeouts: [GraphTimeoutDecision]
    public let reasonCodes: [GraphSchedulingReasonCode]
    public let records: [GraphSchedulingRecord]

    public init(
        schemaVersion: Int,
        latestEvaluation: GraphSchedulerEvaluationPayload?,
        currentPolicy: GraphSchedulerPolicy?,
        activeClaims: [GraphExecutorClaimInspection],
        claimHistory: [GraphExecutorClaimInspection],
        retries: [GraphRetryRecord],
        pendingCancellations: [GraphCancellationRecord],
        cancellationHistory: [GraphCancellationRecord],
        timeouts: [GraphTimeoutDecision],
        reasonCodes: [GraphSchedulingReasonCode],
        records: [GraphSchedulingRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.latestEvaluation = latestEvaluation
        self.currentPolicy = currentPolicy
        self.activeClaims = activeClaims
        self.claimHistory = claimHistory
        self.retries = retries
        self.pendingCancellations = pendingCancellations
        self.cancellationHistory = cancellationHistory
        self.timeouts = timeouts
        self.reasonCodes = reasonCodes
        self.records = records
    }

    public init(
        projection: GraphSchedulingProjection,
        terminalNodeIDs: Set<String>
    ) {
        schemaVersion = GraphSchedulingSchema.definitionVersion
        latestEvaluation = projection.evaluations.max {
            if $0.logicalTime != $1.logicalTime {
                return $0.logicalTime < $1.logicalTime
            }
            return $0.evaluationID < $1.evaluationID
        }
        currentPolicy = latestEvaluation?.schedulerPolicy
        claimHistory = projection.claims
            .map(GraphExecutorClaimInspection.init)
            .sorted(by: claimInspectionIsOrderedBefore)
        activeClaims = claimHistory.filter { $0.status == .active }
        retries = projection.retries.sorted {
            if $0.nodeID != $1.nodeID {
                return $0.nodeID < $1.nodeID
            }
            return $0.nextAttemptOrdinal < $1.nextAttemptOrdinal
        }
        cancellationHistory = projection.cancellations.sorted {
            if $0.nodeID != $1.nodeID {
                return $0.nodeID < $1.nodeID
            }
            return $0.id < $1.id
        }
        pendingCancellations = cancellationHistory.filter {
            !terminalNodeIDs.contains($0.nodeID)
        }
        timeouts = projection.timeouts.sorted {
            if $0.declaredAt != $1.declaredAt {
                return $0.declaredAt < $1.declaredAt
            }
            return $0.id < $1.id
        }
        reasonCodes = Array(
            Set(projection.records.compactMap(\.reason))
        ).sorted { $0.rawValue < $1.rawValue }
        records = projection.records.sorted {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.id < $1.id
        }
    }
}

private func claimInspectionIsOrderedBefore(
    _ lhs: GraphExecutorClaimInspection,
    _ rhs: GraphExecutorClaimInspection
) -> Bool {
    if lhs.grantedSequence != rhs.grantedSequence {
        return lhs.grantedSequence < rhs.grantedSequence
    }
    return lhs.id < rhs.id
}

public struct GraphRunInspection:
    Equatable,
    Codable,
    Sendable
{
    public let summary: GraphRunInspectionSummary
    public let nodes: [GraphNodeInspection]
    public let attempts: [GraphAttemptInspection]
    public let checkpoints: [GraphCheckpointReference]
    public let artifacts: [GraphArtifactInspection]
    public let artifactsIncluded: Bool
    public let parentRunID: String?
    public let parentCheckpoint: GraphCheckpointReference?
    public let checkpointNamespace: String
    public let graphDefinitionVersion: String?
    public let graphDefinitionDigest: GraphContentDigest?
    public let scheduling: GraphSchedulingInspection?
    public let replayDiagnostics: [GraphReplayDiagnostic]
    public let repositoryDiagnostics: [GraphRepositoryDiagnostic]

    public init(
        summary: GraphRunInspectionSummary,
        nodes: [GraphNodeInspection],
        attempts: [GraphAttemptInspection],
        checkpoints: [GraphCheckpointReference],
        artifacts: [GraphArtifactInspection],
        artifactsIncluded: Bool,
        parentRunID: String?,
        parentCheckpoint: GraphCheckpointReference?,
        checkpointNamespace: String,
        graphDefinitionVersion: String?,
        graphDefinitionDigest: GraphContentDigest?,
        scheduling: GraphSchedulingInspection? = nil,
        replayDiagnostics: [GraphReplayDiagnostic],
        repositoryDiagnostics: [GraphRepositoryDiagnostic]
    ) {
        self.summary = summary
        self.nodes = nodes
        self.attempts = attempts
        self.checkpoints = checkpoints
        self.artifacts = artifacts
        self.artifactsIncluded = artifactsIncluded
        self.parentRunID = parentRunID
        self.parentCheckpoint = parentCheckpoint
        self.checkpointNamespace = checkpointNamespace
        self.graphDefinitionVersion = graphDefinitionVersion
        self.graphDefinitionDigest = graphDefinitionDigest
        self.scheduling = scheduling
        self.replayDiagnostics = replayDiagnostics
        self.repositoryDiagnostics = repositoryDiagnostics
    }
}

public struct GraphInspectionEventFilter:
    Equatable,
    Sendable
{
    public let nodeID: String?
    public let attemptID: String?
    public let eventTypes: Set<String>
    public let since: Date?
    public let until: Date?
    public let afterSequence: UInt64
    public let limit: Int

    public init(
        nodeID: String? = nil,
        attemptID: String? = nil,
        eventTypes: Set<String> = [],
        since: Date? = nil,
        until: Date? = nil,
        afterSequence: UInt64 = 0,
        limit: Int = 100
    ) {
        self.nodeID = nodeID
        self.attemptID = attemptID
        self.eventTypes = eventTypes
        self.since = since
        self.until = until
        self.afterSequence = afterSequence
        self.limit = max(1, min(limit, 10_000))
    }

    public func matches(_ event: GraphExecutionEventEnvelope) -> Bool {
        if let nodeID, event.nodeID != nodeID {
            return false
        }
        if let attemptID, event.attemptID != attemptID {
            return false
        }
        if !eventTypes.isEmpty, !eventTypes.contains(event.eventType) {
            return false
        }
        if let since, event.occurredAt < since {
            return false
        }
        if let until, event.occurredAt > until {
            return false
        }
        return true
    }
}

public struct GraphInspectionEventRecord:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let schemaVersion: Int
    public let id: String
    public let runID: String
    public let nodeID: String?
    public let attemptID: String?
    public let streamSequence: UInt64
    public let occurredAt: Date
    public let recordedAt: Date
    public let eventType: String
    public let factClass: GraphExecutionEventFactClass
    public let producerID: String
    public let correlationID: String?
    public let causationID: String?
    public let payloadVersion: Int
    public let redactions: [GraphRedactionRecord]

    public init(event: GraphExecutionEventEnvelope) {
        schemaVersion = event.schemaVersion
        id = event.id
        runID = event.runID
        nodeID = event.nodeID
        attemptID = event.attemptID
        streamSequence = event.streamSequence
        occurredAt = event.occurredAt
        recordedAt = event.recordedAt
        eventType = event.eventType
        factClass = event.factClass
        producerID = event.producer.id
        correlationID = event.correlationID
        causationID = event.causationID
        payloadVersion = event.payloadVersion

        switch event.payload {
        case .artifactRecorded:
            redactions = [
                GraphRedactionRecord(
                    field: "payload.artifact.storage.opaqueReference",
                    reason: .sensitiveByDefault
                ),
            ]
        case .unknown:
            redactions = [
                GraphRedactionRecord(
                    field: "payload",
                    reason: .unsupportedPayload
                ),
            ]
        default:
            redactions = []
        }
    }
}

public struct GraphInspectionEventPage:
    Equatable,
    Codable,
    Sendable
{
    public let runID: String
    public let headVersion: UInt64
    public let scannedThroughSequence: UInt64
    public let hasMore: Bool
    public let events: [GraphInspectionEventRecord]
}

public enum GraphCausalSubjectKind: String, Codable, Sendable {
    case run
    case node
    case attempt
    case dependency
    case event
    case evidence
}

public enum GraphCausalReasonCode: String, Codable, CaseIterable, Sendable {
    case runTerminalDeclaration = "run_terminal_declaration"
    case runDerivedFromNode = "run_derived_from_node"
    case attemptTerminalDeclaration = "attempt_terminal_declaration"
    case matchingProcessExit = "matching_process_exit"
    case validHeartbeat = "valid_heartbeat"
    case missingProcessIdentity = "missing_process_identity"
    case missingExecutorEvidence = "missing_executor_evidence"
    case evidenceUnavailable = "evidence_unavailable"
    case evidenceStale = "evidence_stale"
    case evidencePermissionDenied = "evidence_permission_denied"
    case evidenceAdapterFailed = "evidence_adapter_failed"
    case evidenceIdentityMismatch = "evidence_identity_mismatch"
    case dependencyFailed = "dependency_failed"
    case dependencyInterrupted = "dependency_interrupted"
    case dependencyOrphaned = "dependency_orphaned"
    case dependencyBlocked = "dependency_blocked"
    case dependencyCancelled = "dependency_cancelled"
    case dependencyPending = "dependency_pending"
    case dependencyRunning = "dependency_running"
    case dependencyMissing = "dependency_missing"
    case dependenciesCompleted = "dependencies_completed"
    case noExecutionAttempt = "no_execution_attempt"
    case unknownEventIgnored = "unknown_event_ignored"
    case persistedState = "persisted_state"
}

public enum GraphCausalEdgeKind: String, Codable, Sendable {
    case caused
    case blocked
    case observed
    case derived
    case ignored
}

public struct GraphCausalReason:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public let code: GraphCausalReasonCode
    public let subjectKind: GraphCausalSubjectKind
    public let subjectID: String
    public let state: ReconciledExecutionState?
    public let message: String
    public let supportingEventID: String?
    public let dependencyNodeID: String?
}

public struct GraphCausalEdge: Equatable, Codable, Sendable {
    public let fromReasonID: String
    public let toReasonID: String
    public let kind: GraphCausalEdgeKind
}

public struct GraphCausalExplanation:
    Equatable,
    Codable,
    Sendable
{
    public let runID: String
    public let nodeID: String?
    public let state: ReconciledExecutionState
    public let summary: String
    public let reasons: [GraphCausalReason]
    public let edges: [GraphCausalEdge]
    public let shortestCausalChain: [String]
    public let causalPredecessorNodeIDs: [String]
    public let blockingDependencyNodeIDs: [String]
    public let readinessRequirements: [String]
    public let schedulerReasons: [GraphSchedulingReasonCode]?
    public let ignoredInputs: [GraphCausalReason]
}

public struct GraphTemporalReplayResult: Equatable, Sendable {
    public let runID: String
    public let boundary: UInt64
    public let headVersion: UInt64
    public let projected: GraphExecutionProjection
    public let reconciled: ExecutionReconciliationResult?
    public let snapshotDisposition: GraphSnapshotDisposition
    public let snapshotStreamVersion: UInt64?
    public let replayedEventCount: Int
    public let evidence: GraphEvidenceInspection
    public let replayDiagnostics: [GraphReplayDiagnostic]
    public let repositoryDiagnostics: [GraphRepositoryDiagnostic]
}

public enum GraphTemporalChangeCategory: String, Codable, Sendable {
    case graphDefinition = "graph_definition"
    case run
    case node
    case attempt
    case eventRange = "event_range"
    case artifact
    case evidence
    case reconciliation
    case causalExplanation = "causal_explanation"
    case scheduler
    case claim
    case retry
    case cancellation
    case timeout
}

public struct GraphTemporalChange:
    Equatable,
    Codable,
    Sendable
{
    public let category: GraphTemporalChangeCategory
    public let entityID: String
    public let field: String
    public let left: String?
    public let right: String?
}

public struct GraphTemporalDiffResult:
    Equatable,
    Codable,
    Sendable
{
    public let left: GraphTemporalReference
    public let right: GraphTemporalReference
    public let leftBoundary: UInt64
    public let rightBoundary: UInt64
    public let changes: [GraphTemporalChange]
}

public protocol GraphTemporalInspecting: Sendable {
    func listRuns(
        state: ReconciledExecutionState?,
        limit: Int
    ) async throws -> [GraphRunInspectionSummary]

    func inspect(
        runID: String,
        includeArtifacts: Bool,
        includeDiagnostics: Bool
    ) async throws -> GraphRunInspection

    func eventPage(
        runID: String,
        filter: GraphInspectionEventFilter
    ) async throws -> GraphInspectionEventPage

    func checkpoints(
        runID: String
    ) async throws -> [GraphCheckpointReference]

    func replay(
        reference: GraphTemporalReference,
        evidenceMode: GraphInspectionEvidenceMode
    ) async throws -> GraphTemporalReplayResult

    func diff(
        left: GraphTemporalReference,
        right: GraphTemporalReference
    ) async throws -> GraphTemporalDiffResult

    func explain(
        runID: String,
        nodeID: String?
    ) async throws -> GraphCausalExplanation

    func causalPredecessors(
        runID: String,
        nodeID: String
    ) async throws -> [String]

    func blockingDependencies(
        runID: String,
        nodeID: String
    ) async throws -> [String]

    func artifacts(
        runID: String
    ) async throws -> [GraphArtifactInspection]
}

public struct DefaultGraphTemporalInspector:
    GraphTemporalInspecting,
    Sendable
{
    private let readStore: any GraphExecutionReadStore
    private let snapshotStore: any GraphExecutionSnapshotReadStore
    private let evidenceSource: any ProcessEvidenceSource
    private let pageSize: Int

    public init(
        readStore: any GraphExecutionReadStore,
        snapshotStore: any GraphExecutionSnapshotReadStore,
        evidenceSource: any ProcessEvidenceSource =
            UnavailableProcessEvidenceSource(),
        pageSize: Int = 500
    ) {
        self.readStore = readStore
        self.snapshotStore = snapshotStore
        self.evidenceSource = evidenceSource
        self.pageSize = max(1, min(pageSize, 10_000))
    }

    public func listRuns(
        state: ReconciledExecutionState? = nil,
        limit: Int = 100
    ) async throws -> [GraphRunInspectionSummary] {
        let descriptors = try await mappedPersistence {
            try await readStore.listStreams()
        }
        var summaries: [GraphRunInspectionSummary] = []

        for descriptor in descriptors {
            let replay = try await load(
                reference: GraphTemporalReference(
                    runID: descriptor.runID
                ),
                evidenceMode: .withoutLiveEvidence
            )
            guard let summary = makeSummary(replay) else {
                continue
            }
            if state == nil || summary.reconciledState == state {
                summaries.append(summary)
            }
        }

        return Array(
            summaries
                .sorted {
                    if $0.updatedAt != $1.updatedAt {
                        return $0.updatedAt > $1.updatedAt
                    }
                    return $0.runID < $1.runID
                }
                .prefix(max(1, min(limit, 10_000)))
        )
    }

    public func inspect(
        runID: String,
        includeArtifacts: Bool = false,
        includeDiagnostics: Bool = false
    ) async throws -> GraphRunInspection {
        let replay = try await load(
            reference: GraphTemporalReference(runID: runID),
            evidenceMode: .withoutLiveEvidence
        )
        guard let summary = makeSummary(replay) else {
            throw GraphInspectionError.corruptHistory(
                "Run \(runID) has no run-created projection."
            )
        }
        let reconciledNodes = Dictionary(
            uniqueKeysWithValues:
                (replay.reconciled?.nodes ?? []).map { ($0.id, $0) }
        )
        let reconciledAttempts = Dictionary(
            uniqueKeysWithValues:
                (replay.reconciled?.attempts ?? []).map { ($0.id, $0) }
        )
        let nodes = replay.projected.nodes.map { node in
            GraphNodeInspection(
                id: node.id,
                title: node.title,
                dependencyNodeIDs: node.dependencyNodeIDs.sorted(),
                executorID: node.executorID,
                persistedState: node.state,
                reconciledState: reconciledNodes[node.id]?.state
                    ?? node.state,
                activeAttemptID:
                    reconciledNodes[node.id]?.activeAttemptID
                        ?? node.activeAttemptID,
                updatedAt: reconciledNodes[node.id]?.updatedAt
                    ?? node.updatedAt
            )
        }.sorted { $0.id < $1.id }
        let attempts = replay.projected.attempts.map { attempt in
            let reconciled = reconciledAttempts[attempt.id]
            return GraphAttemptInspection(
                id: attempt.id,
                nodeID: attempt.nodeID,
                ordinal: attempt.ordinal,
                persistedState: attempt.state,
                reconciledState: reconciled?.state ?? attempt.state,
                hasProcessIdentity: attempt.processIdentity != nil,
                createdAt: attempt.createdAt,
                updatedAt: reconciled?.updatedAt ?? attempt.updatedAt,
                startedAt: reconciled?.startedAt ?? attempt.startedAt,
                finishedAt: reconciled?.finishedAt ?? attempt.finishedAt,
                statusReason:
                    bounded(reconciled?.statusReason ?? attempt.statusReason)
            )
        }.sorted(by: attemptIsOrderedBefore)

        return GraphRunInspection(
            summary: summary,
            nodes: nodes,
            attempts: attempts,
            checkpoints: replay.projected.namedCheckpoints.sorted(
                by: checkpointIsOrderedBefore
            ),
            artifacts: includeArtifacts
                ? replay.projected.artifacts.map(GraphArtifactInspection.init)
                    .sorted { $0.id < $1.id }
                : [],
            artifactsIncluded: includeArtifacts,
            parentRunID: replay.projected.parentRunID,
            parentCheckpoint: replay.projected.parentCheckpoint,
            checkpointNamespace: replay.projected.checkpointNamespace,
            graphDefinitionVersion:
                replay.projected.graphDefinitionVersion,
            graphDefinitionDigest:
                replay.projected.graphDefinitionDigest,
            scheduling: GraphSchedulingInspection(
                projection: replay.projected.scheduling,
                terminalNodeIDs: Set(
                    nodes.filter { $0.reconciledState.isTerminal }.map(\.id)
                )
            ),
            replayDiagnostics:
                includeDiagnostics ? replay.replayDiagnostics : [],
            repositoryDiagnostics:
                includeDiagnostics ? replay.repositoryDiagnostics : []
        )
    }

    public func eventPage(
        runID: String,
        filter: GraphInspectionEventFilter
    ) async throws -> GraphInspectionEventPage {
        let descriptor = try await requireStream(runID)
        var cursor = filter.afterSequence
        var selected: [GraphInspectionEventRecord] = []
        var hasMore = cursor < descriptor.currentVersion

        while hasMore, selected.count < filter.limit {
            let rawPage = try await mappedPersistence {
                try await readStore.readPage(
                    runID: runID,
                    afterVersion: cursor,
                    limit: min(pageSize, filter.limit - selected.count + 64)
                )
            }

            guard !rawPage.events.isEmpty else {
                break
            }

            var scannedThrough = cursor

            for event in rawPage.events {
                scannedThrough = event.streamSequence

                if filter.matches(event) {
                    selected.append(
                        GraphInspectionEventRecord(event: event)
                    )
                    if selected.count == filter.limit {
                        break
                    }
                }
            }

            cursor = scannedThrough
            hasMore = cursor < descriptor.currentVersion
        }

        return GraphInspectionEventPage(
            runID: runID,
            headVersion: descriptor.currentVersion,
            scannedThroughSequence: cursor,
            hasMore: hasMore,
            events: selected
        )
    }

    public func checkpoints(
        runID: String
    ) async throws -> [GraphCheckpointReference] {
        let result = try await load(
            reference: GraphTemporalReference(runID: runID),
            evidenceMode: .withoutLiveEvidence
        )
        return result.projected.namedCheckpoints.sorted(
            by: checkpointIsOrderedBefore
        )
    }

    public func replay(
        reference: GraphTemporalReference,
        evidenceMode: GraphInspectionEvidenceMode =
            .withoutLiveEvidence
    ) async throws -> GraphTemporalReplayResult {
        try await load(
            reference: reference,
            evidenceMode: evidenceMode
        )
    }

    public func diff(
        left: GraphTemporalReference,
        right: GraphTemporalReference
    ) async throws -> GraphTemporalDiffResult {
        let leftResult = try await load(
            reference: left,
            evidenceMode: .withoutLiveEvidence
        )
        let rightResult = try await load(
            reference: right,
            evidenceMode: .withoutLiveEvidence
        )
        let leftEventIDs = try await eventIDs(
            runID: left.runID,
            through: leftResult.boundary
        )
        let rightEventIDs = try await eventIDs(
            runID: right.runID,
            through: rightResult.boundary
        )
        var changes: [GraphTemporalChange] = []

        appendChange(
            category: .graphDefinition,
            entityID: left.runID,
            field: "version",
            left: leftResult.projected.graphDefinitionVersion,
            right: rightResult.projected.graphDefinitionVersion,
            to: &changes
        )
        appendChange(
            category: .graphDefinition,
            entityID: left.runID,
            field: "digest",
            left: leftResult.projected.graphDefinitionDigest?.value,
            right: rightResult.projected.graphDefinitionDigest?.value,
            to: &changes
        )
        appendChange(
            category: .run,
            entityID: left.runID,
            field: "persisted_state",
            left: leftResult.projected.run?.state.rawValue,
            right: rightResult.projected.run?.state.rawValue,
            to: &changes
        )
        appendChange(
            category: .reconciliation,
            entityID: left.runID,
            field: "run_state",
            left: leftResult.reconciled?.run.state.rawValue,
            right: rightResult.reconciled?.run.state.rawValue,
            to: &changes
        )
        appendChange(
            category: .evidence,
            entityID: left.runID,
            field: "status",
            left: leftResult.evidence.status,
            right: rightResult.evidence.status,
            to: &changes
        )

        compareNodes(
            left: leftResult,
            right: rightResult,
            changes: &changes
        )
        compareAttempts(
            left: leftResult,
            right: rightResult,
            changes: &changes
        )
        compareArtifacts(
            left: leftResult.projected.artifacts,
            right: rightResult.projected.artifacts,
            changes: &changes
        )
        compareScheduling(
            left: leftResult.projected.scheduling,
            right: rightResult.projected.scheduling,
            changes: &changes
        )

        let leftOnly = leftEventIDs.subtracting(rightEventIDs).sorted()
        let rightOnly = rightEventIDs.subtracting(leftEventIDs).sorted()
        appendChange(
            category: .eventRange,
            entityID: left.runID == right.runID
                ? left.runID
                : "\(left.runID)|\(right.runID)",
            field: "event_ids",
            left: leftOnly.isEmpty ? nil : leftOnly.joined(separator: ","),
            right:
                rightOnly.isEmpty ? nil : rightOnly.joined(separator: ","),
            to: &changes
        )

        let nodeIDs = Set(leftResult.projected.nodes.map(\.id))
            .intersection(rightResult.projected.nodes.map(\.id))
            .sorted()
        for nodeID in nodeIDs {
            let leftExplanation = explanation(
                result: leftResult,
                nodeID: nodeID,
                events: []
            )
            let rightExplanation = explanation(
                result: rightResult,
                nodeID: nodeID,
                events: []
            )
            appendChange(
                category: .causalExplanation,
                entityID: nodeID,
                field: "reason_codes",
                left: leftExplanation.reasons.map(\.code.rawValue)
                    .joined(separator: ","),
                right: rightExplanation.reasons.map(\.code.rawValue)
                    .joined(separator: ","),
                to: &changes
            )
        }

        changes.sort(by: changeIsOrderedBefore)
        return GraphTemporalDiffResult(
            left: left,
            right: right,
            leftBoundary: leftResult.boundary,
            rightBoundary: rightResult.boundary,
            changes: changes
        )
    }

    public func explain(
        runID: String,
        nodeID: String? = nil
    ) async throws -> GraphCausalExplanation {
        let result = try await load(
            reference: GraphTemporalReference(runID: runID),
            evidenceMode: .withoutLiveEvidence
        )
        if let nodeID,
           !result.projected.nodes.contains(where: { $0.id == nodeID }) {
            throw GraphInspectionError.corruptHistory(
                "Run \(runID) has no node \(nodeID)."
            )
        }
        let events = try await allEvents(
            runID: runID,
            through: result.boundary
        )
        return explanation(
            result: result,
            nodeID: nodeID,
            events: events
        )
    }

    public func causalPredecessors(
        runID: String,
        nodeID: String
    ) async throws -> [String] {
        let result = try await load(
            reference: GraphTemporalReference(runID: runID),
            evidenceMode: .withoutLiveEvidence
        )
        return predecessorIDs(
            nodeID: nodeID,
            nodes: result.reconciled?.nodes
                ?? result.projected.nodes
        )
    }

    public func blockingDependencies(
        runID: String,
        nodeID: String
    ) async throws -> [String] {
        let result = try await load(
            reference: GraphTemporalReference(runID: runID),
            evidenceMode: .withoutLiveEvidence
        )
        let nodes = result.reconciled?.nodes ?? result.projected.nodes
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return predecessorIDs(nodeID: nodeID, nodes: nodes).filter {
            byID[$0]?.state.preventsDependentExecution == true
                || byID[$0] == nil
        }
    }

    public func artifacts(
        runID: String
    ) async throws -> [GraphArtifactInspection] {
        let result = try await load(
            reference: GraphTemporalReference(runID: runID),
            evidenceMode: .withoutLiveEvidence
        )
        return result.projected.artifacts
            .map(GraphArtifactInspection.init)
            .sorted { $0.id < $1.id }
    }

    private func load(
        reference: GraphTemporalReference,
        evidenceMode: GraphInspectionEvidenceMode
    ) async throws -> GraphTemporalReplayResult {
        let descriptor = try await requireStream(reference.runID)
        let boundary = try await resolveBoundary(
            reference,
            head: descriptor.currentVersion
        )
        var diagnostics: [GraphRepositoryDiagnostic] = []
        let snapshotLoad = await loadSnapshot(
            runID: reference.runID,
            through: boundary,
            diagnostics: &diagnostics
        )
        var snapshot = snapshotLoad.snapshot
        var snapshotDisposition = snapshotLoad.disposition

        if let loadedSnapshot = snapshot,
           loadedSnapshot.streamVersion > boundary {
            diagnostics.append(
                GraphRepositoryDiagnostic(
                    category: .snapshot,
                    message: "Snapshot is ahead of the requested replay boundary and was bypassed."
                )
            )
            snapshotDisposition = .aheadOfStream
            snapshot = nil
        } else if let loadedSnapshot = snapshot,
                  loadedSnapshot.streamVersion < boundary {
            snapshotDisposition = .stale
        }

        let events = try await events(
            runID: reference.runID,
            after: snapshot?.streamVersion ?? 0,
            through: boundary
        )
        let replay: GraphExecutionReplayResult

        do {
            replay = try GraphExecutionProjector.replay(
                runID: reference.runID,
                events: events,
                initialProjection: snapshot?.projectedState
            )
        } catch let error as GraphExecutionReplayError {
            throw mappedReplay(error)
        } catch {
            throw GraphInspectionError.corruptHistory(
                error.localizedDescription
            )
        }
        guard replay.projection.run != nil else {
            throw GraphInspectionError.corruptHistory(
                "Run \(reference.runID) has no run-created event."
            )
        }

        diagnostics.append(
            GraphRepositoryDiagnostic(
                category: .replay,
                message: "Replayed \(replay.replayedEventCount) event(s) through stream version \(replay.projection.streamVersion)."
            )
        )
        let observedAt = stableObservedAt(
            projection: replay.projection,
            events: events
        )
        let evidenceOutcome = await evidence(
            mode: evidenceMode,
            boundary: boundary,
            head: descriptor.currentVersion,
            projection: replay.projection,
            observedAt: observedAt
        )
        if evidenceMode == .requireAvailable {
            guard case .available = evidenceOutcome else {
                throw GraphInspectionError.evidenceUnavailable(
                    evidenceReason(evidenceOutcome)
                        ?? evidenceOutcome.status
                )
            }
        }
        diagnostics.append(
            GraphRepositoryDiagnostic(
                category: .evidence,
                message: "Process evidence status: \(evidenceOutcome.status)."
            )
        )
        let reconciled = GraphExecutionProjectionReconciler.reconcile(
            projection: replay.projection,
            evidenceOutcome: evidenceOutcome,
            observedAt: observedAt
        )

        if let reconciled {
            diagnostics.append(
                GraphRepositoryDiagnostic(
                    category: .reconciliation,
                    message: "Reconciled run to \(reconciled.run.state.rawValue)."
                )
            )
        }

        return GraphTemporalReplayResult(
            runID: reference.runID,
            boundary: boundary,
            headVersion: descriptor.currentVersion,
            projected: replay.projection,
            reconciled: reconciled,
            snapshotDisposition: snapshotDisposition,
            snapshotStreamVersion: snapshot?.streamVersion,
            replayedEventCount: replay.replayedEventCount,
            evidence: GraphEvidenceInspection(
                status: evidenceOutcome.status,
                reason: bounded(evidenceReason(evidenceOutcome))
            ),
            replayDiagnostics: replay.diagnostics,
            repositoryDiagnostics: diagnostics
        )
    }

    private func requireStream(
        _ runID: String
    ) async throws -> GraphExecutionStreamDescriptor {
        let descriptor = try await mappedPersistence {
            try await readStore.streamDescriptor(runID: runID)
        }
        guard let descriptor else {
            throw GraphInspectionError.runNotFound(runID)
        }
        return descriptor
    }

    private func resolveBoundary(
        _ reference: GraphTemporalReference,
        head: UInt64
    ) async throws -> UInt64 {
        let boundary: UInt64

        switch reference.boundary.kind {
        case .head:
            boundary = head
        case .sequence:
            guard let sequence = reference.boundary.sequence else {
                throw GraphInspectionError.invalidBoundary(
                    runID: reference.runID,
                    requested: 0,
                    head: head
                )
            }
            boundary = sequence
        case .checkpoint:
            guard let checkpointID =
                    reference.boundary.checkpointID else {
                throw GraphInspectionError.checkpointNotFound(
                    runID: reference.runID,
                    checkpointID: "<missing>"
                )
            }
            let headResult = try await load(
                reference: GraphTemporalReference(
                    runID: reference.runID,
                    boundary: .sequence(head)
                ),
                evidenceMode: .withoutLiveEvidence
            )
            guard let checkpoint =
                    headResult.projected.namedCheckpoints.first(
                        where: { $0.checkpointID == checkpointID }
                    ) else {
                throw GraphInspectionError.checkpointNotFound(
                    runID: reference.runID,
                    checkpointID: checkpointID
                )
            }
            boundary = checkpoint.streamVersion
        }

        guard boundary <= head else {
            throw GraphInspectionError.invalidBoundary(
                runID: reference.runID,
                requested: boundary,
                head: head
            )
        }
        return boundary
    }

    private func loadSnapshot(
        runID: String,
        through boundary: UInt64,
        diagnostics: inout [GraphRepositoryDiagnostic]
    ) async -> (
        snapshot: GraphExecutionSnapshot?,
        disposition: GraphSnapshotDisposition
    ) {
        do {
            guard let snapshot = try await snapshotStore.loadLatest(
                runID: runID,
                throughVersion: boundary
            ) else {
                return (nil, .missing)
            }
            guard snapshot.schemaVersion
                    == GraphExecutionSchema.snapshotVersion else {
                diagnostics.append(
                    GraphRepositoryDiagnostic(
                        category: .snapshot,
                        message: "Snapshot schema is incompatible and was bypassed."
                    )
                )
                return (nil, .incompatible)
            }
            guard snapshot.runID == runID,
                  snapshot.projectedState.runID == runID,
                  snapshot.streamVersion
                    == snapshot.projectedState.streamVersion,
                  snapshot.graphDefinitionVersion
                    == snapshot.projectedState.graphDefinitionVersion,
                  snapshot.graphDefinitionDigest
                    == snapshot.projectedState.graphDefinitionDigest else {
                diagnostics.append(
                    GraphRepositoryDiagnostic(
                        category: .snapshot,
                        message: "Snapshot metadata is internally inconsistent and was bypassed."
                    )
                )
                return (nil, .corrupt)
            }
            return (
                snapshot,
                snapshot.streamVersion == boundary ? .current : .stale
            )
        } catch {
            diagnostics.append(
                GraphRepositoryDiagnostic(
                    category: .snapshot,
                    message: "Snapshot load failed and full replay was used: \(bounded(error.localizedDescription) ?? "unknown error")"
                )
            )
            return (nil, .corrupt)
        }
    }

    private func events(
        runID: String,
        after: UInt64,
        through boundary: UInt64
    ) async throws -> [GraphExecutionEventEnvelope] {
        var cursor = after
        var result: [GraphExecutionEventEnvelope] = []

        while cursor < boundary {
            let page = try await mappedPersistence {
                try await readStore.readPage(
                    runID: runID,
                    afterVersion: cursor,
                    limit: pageSize
                )
            }
            let boundedEvents = page.events.filter {
                $0.streamSequence <= boundary
            }
            guard !boundedEvents.isEmpty else {
                throw GraphInspectionError.corruptHistory(
                    "Run \(runID) cannot advance replay after sequence \(cursor)."
                )
            }
            result.append(contentsOf: boundedEvents)
            cursor = boundedEvents.last!.streamSequence
        }

        return result
    }

    private func allEvents(
        runID: String,
        through boundary: UInt64
    ) async throws -> [GraphExecutionEventEnvelope] {
        try await events(runID: runID, after: 0, through: boundary)
    }

    private func eventIDs(
        runID: String,
        through boundary: UInt64
    ) async throws -> Set<String> {
        Set(
            try await allEvents(runID: runID, through: boundary)
                .map(\.id)
        )
    }

    private func evidence(
        mode: GraphInspectionEvidenceMode,
        boundary: UInt64,
        head: UInt64,
        projection: GraphExecutionProjection,
        observedAt: Date
    ) async -> GraphProcessEvidenceOutcome {
        guard mode != .withoutLiveEvidence else {
            return .unavailable(
                reason: "Live process evidence was disabled for deterministic inspection."
            )
        }
        guard boundary == head else {
            return .unavailable(
                reason: "Historical replay does not apply current live process evidence."
            )
        }
        return await evidenceSource.evidence(
            for: GraphProcessEvidenceRequest(
                runID: projection.runID,
                attempts: projection.attempts,
                observedAt: observedAt
            )
        )
    }

    private func makeSummary(
        _ result: GraphTemporalReplayResult
    ) -> GraphRunInspectionSummary? {
        guard let run = result.projected.run else {
            return nil
        }
        return GraphRunInspectionSummary(
            runID: run.id,
            graphID: run.graphID,
            persistedState: run.state,
            reconciledState: result.reconciled?.run.state ?? run.state,
            streamVersion: result.boundary,
            nodeCount: result.projected.nodes.count,
            attemptCount: result.projected.attempts.count,
            artifactCount: result.projected.artifacts.count,
            createdAt: run.createdAt,
            updatedAt: result.reconciled?.run.updatedAt ?? run.updatedAt,
            snapshotDisposition: result.snapshotDisposition,
            evidence: result.evidence
        )
    }

    private func explanation(
        result: GraphTemporalReplayResult,
        nodeID: String?,
        events: [GraphExecutionEventEnvelope]
    ) -> GraphCausalExplanation {
        let reconciled = result.reconciled
        let nodes = reconciled?.nodes ?? result.projected.nodes
        let attempts = reconciled?.attempts ?? result.projected.attempts
        let nodeByID = Dictionary(
            uniqueKeysWithValues: nodes.map { ($0.id, $0) }
        )
        let state: ReconciledExecutionState
        let subjectID: String
        var reasons: [GraphCausalReason] = []
        var edges: [GraphCausalEdge] = []
        var requirements: [String] = []
        var shortest: [String] = []

        if let nodeID, let node = nodeByID[nodeID] {
            state = node.state
            subjectID = nodeID
            let attempt = attempts
                .filter { $0.nodeID == nodeID }
                .max(by: attemptIsOrderedBefore)
            let primary = primaryNodeReason(
                node: node,
                attempt: attempt,
                nodeByID: nodeByID,
                events: events,
                evidence: result.evidence
            )
            reasons.append(primary)
            shortest.append(primary.id)

            if state == .blocked {
                let path = shortestBlockingPath(
                    from: nodeID,
                    nodeByID: nodeByID
                )
                var previous = primary.id
                for dependencyID in path.dropFirst() {
                    let dependency = nodeByID[dependencyID]
                    let reason = dependencyReason(
                        nodeID: dependencyID,
                        state: dependency?.state
                    )
                    reasons.append(reason)
                    edges.append(
                        GraphCausalEdge(
                            fromReasonID: reason.id,
                            toReasonID: previous,
                            kind: .blocked
                        )
                    )
                    shortest.append(reason.id)
                    previous = reason.id
                }
            }

            requirements = readinessRequirements(
                node: node,
                nodeByID: nodeByID
            )
        } else {
            let run = reconciled?.run ?? result.projected.run!
            state = run.state
            subjectID = run.id
            let event = events.last {
                $0.eventType
                    == GraphExecutionEventType
                        .runTerminalStateRecorded.rawValue
            }
            let sourceNode = nodes.first {
                $0.state == state && state != .pending
            }
            let code: GraphCausalReasonCode =
                event == nil ? .runDerivedFromNode : .runTerminalDeclaration
            let reason = GraphCausalReason(
                id: reasonID(code, subjectID),
                code: code,
                subjectKind: .run,
                subjectID: subjectID,
                state: state,
                message: event == nil
                    ? "Run state is derived from reconciled node state\(sourceNode.map { " \($0.id)" } ?? "")."
                    : "An authoritative run terminal event established this state.",
                supportingEventID: event?.id,
                dependencyNodeID: sourceNode?.id
            )
            reasons.append(reason)
            shortest.append(reason.id)
        }

        var ignored: [GraphCausalReason] = []
        for event in result.projected.unknownEvents {
            ignored.append(
                GraphCausalReason(
                    id: reasonID(.unknownEventIgnored, event.id),
                    code: .unknownEventIgnored,
                    subjectKind: .event,
                    subjectID: event.id,
                    state: nil,
                    message: "Unknown event \(event.eventType) was retained without applying semantics.",
                    supportingEventID: event.id,
                    dependencyNodeID: nil
                )
            )
        }
        if let evidenceReason = evidenceCausalReason(
            result.evidence,
            subjectID: subjectID
        ) {
            ignored.append(evidenceReason)
        }

        reasons = uniqueReasons(reasons).sorted { $0.id < $1.id }
        ignored = uniqueReasons(ignored).sorted { $0.id < $1.id }
        edges.sort {
            if $0.fromReasonID != $1.fromReasonID {
                return $0.fromReasonID < $1.fromReasonID
            }
            if $0.toReasonID != $1.toReasonID {
                return $0.toReasonID < $1.toReasonID
            }
            return $0.kind.rawValue < $1.kind.rawValue
        }
        let predecessors = nodeID.map {
            predecessorIDs(nodeID: $0, nodes: nodes)
        } ?? []
        let blockers = predecessors.filter {
            nodeByID[$0]?.state.preventsDependentExecution == true
                || nodeByID[$0] == nil
        }
        let summary = nodeID.map {
            "Node \($0) is \(state.rawValue): \(reasons.first?.message ?? "no causal detail available")"
        } ?? "Run \(result.runID) is \(state.rawValue): \(reasons.first?.message ?? "no causal detail available")"

        return GraphCausalExplanation(
            runID: result.runID,
            nodeID: nodeID,
            state: state,
            summary: summary,
            reasons: reasons,
            edges: edges,
            shortestCausalChain: shortest,
            causalPredecessorNodeIDs: predecessors,
            blockingDependencyNodeIDs: blockers,
            readinessRequirements: requirements,
            schedulerReasons: Array(
                Set(
                    result.projected.scheduling.records
                        .filter { nodeID == nil || $0.nodeID == nodeID }
                        .compactMap(\.reason)
                )
            ).sorted { $0.rawValue < $1.rawValue },
            ignoredInputs: ignored
        )
    }

    private func primaryNodeReason(
        node: GraphNode,
        attempt: ExecutionAttempt?,
        nodeByID: [String: GraphNode],
        events: [GraphExecutionEventEnvelope],
        evidence: GraphEvidenceInspection
    ) -> GraphCausalReason {
        if node.state == .blocked {
            let blocker = node.dependencyNodeIDs.sorted().first {
                nodeByID[$0]?.state.preventsDependentExecution == true
                    || nodeByID[$0] == nil
            }
            return GraphCausalReason(
                id: reasonID(.dependencyBlocked, node.id),
                code: .dependencyBlocked,
                subjectKind: .node,
                subjectID: node.id,
                state: node.state,
                message: blocker.map {
                    "Dependency \($0) prevents this node from running."
                } ?? "A dependency prevents this node from running.",
                supportingEventID: nil,
                dependencyNodeID: blocker
            )
        }
        if node.state == .ready {
            return GraphCausalReason(
                id: reasonID(.dependenciesCompleted, node.id),
                code: .dependenciesCompleted,
                subjectKind: .node,
                subjectID: node.id,
                state: node.state,
                message: "All required dependencies are completed.",
                supportingEventID: nil,
                dependencyNodeID: nil
            )
        }
        guard let attempt else {
            return GraphCausalReason(
                id: reasonID(.noExecutionAttempt, node.id),
                code: .noExecutionAttempt,
                subjectKind: .node,
                subjectID: node.id,
                state: node.state,
                message: node.dependencyNodeIDs.isEmpty
                    ? "No execution attempt has been created."
                    : "No attempt exists and dependencies are not all completed.",
                supportingEventID: nil,
                dependencyNodeID: nil
            )
        }
        let terminalEvent = events.last {
            $0.attemptID == attempt.id
                && [
                    GraphExecutionEventType.attemptCompleted.rawValue,
                    GraphExecutionEventType.attemptFailed.rawValue,
                    GraphExecutionEventType.attemptInterrupted.rawValue,
                    GraphExecutionEventType.attemptOrphaned.rawValue,
                    GraphExecutionEventType.attemptCancelled.rawValue,
                ].contains($0.eventType)
        }
        if let terminalEvent {
            return GraphCausalReason(
                id: reasonID(.attemptTerminalDeclaration, attempt.id),
                code: .attemptTerminalDeclaration,
                subjectKind: .attempt,
                subjectID: attempt.id,
                state: attempt.state,
                message: "An authoritative attempt terminal event established this state.",
                supportingEventID: terminalEvent.id,
                dependencyNodeID: nil
            )
        }
        let exitEvent = events.last {
            $0.attemptID == attempt.id
                && $0.eventType
                    == GraphExecutionEventType.processExitObserved.rawValue
        }
        if let exitEvent, attempt.state == .interrupted {
            return GraphCausalReason(
                id: reasonID(.matchingProcessExit, attempt.id),
                code: .matchingProcessExit,
                subjectKind: .attempt,
                subjectID: attempt.id,
                state: attempt.state,
                message: "A matching process exit was observed without a terminal workflow declaration.",
                supportingEventID: exitEvent.id,
                dependencyNodeID: nil
            )
        }
        if attempt.state == .orphaned {
            return GraphCausalReason(
                id: reasonID(.missingExecutorEvidence, attempt.id),
                code: .missingExecutorEvidence,
                subjectKind: .attempt,
                subjectID: attempt.id,
                state: attempt.state,
                message: "The recorded process identity has no matching current executor evidence.",
                supportingEventID: nil,
                dependencyNodeID: nil
            )
        }
        if attempt.state == .interrupted, !attemptHasIdentity(attempt) {
            return GraphCausalReason(
                id: reasonID(.missingProcessIdentity, attempt.id),
                code: .missingProcessIdentity,
                subjectKind: .attempt,
                subjectID: attempt.id,
                state: attempt.state,
                message: "The running attempt had no recoverable process identity.",
                supportingEventID: nil,
                dependencyNodeID: nil
            )
        }
        if attempt.state == .running {
            return GraphCausalReason(
                id: reasonID(.validHeartbeat, attempt.id),
                code: .validHeartbeat,
                subjectKind: .attempt,
                subjectID: attempt.id,
                state: attempt.state,
                message: "Current evidence supports the running attempt.",
                supportingEventID: nil,
                dependencyNodeID: nil
            )
        }
        return GraphCausalReason(
            id: reasonID(.persistedState, attempt.id),
            code: .persistedState,
            subjectKind: .attempt,
            subjectID: attempt.id,
            state: attempt.state,
            message: "The state is derived from persisted attempt history.",
            supportingEventID: nil,
            dependencyNodeID: nil
        )
    }

    private func dependencyReason(
        nodeID: String,
        state: ReconciledExecutionState?
    ) -> GraphCausalReason {
        let code: GraphCausalReasonCode
        switch state {
        case .failed:
            code = .dependencyFailed
        case .interrupted:
            code = .dependencyInterrupted
        case .orphaned:
            code = .dependencyOrphaned
        case .blocked:
            code = .dependencyBlocked
        case .cancelled:
            code = .dependencyCancelled
        case .running:
            code = .dependencyRunning
        case .pending, .ready:
            code = .dependencyPending
        case .completed:
            code = .dependenciesCompleted
        case nil:
            code = .dependencyMissing
        }
        return GraphCausalReason(
            id: reasonID(code, nodeID),
            code: code,
            subjectKind: .dependency,
            subjectID: nodeID,
            state: state,
            message: state.map {
                "Dependency \(nodeID) is \($0.rawValue)."
            } ?? "Dependency \(nodeID) is missing from the graph projection.",
            supportingEventID: nil,
            dependencyNodeID: nodeID
        )
    }

    private func evidenceCausalReason(
        _ evidence: GraphEvidenceInspection,
        subjectID: String
    ) -> GraphCausalReason? {
        let code: GraphCausalReasonCode
        switch evidence.status {
        case "unavailable":
            code = .evidenceUnavailable
        case "stale":
            code = .evidenceStale
        case "permission_denied":
            code = .evidencePermissionDenied
        case "adapter_failed":
            code = .evidenceAdapterFailed
        case "identity_mismatch":
            code = .evidenceIdentityMismatch
        default:
            return nil
        }
        return GraphCausalReason(
            id: reasonID(code, subjectID),
            code: code,
            subjectKind: .evidence,
            subjectID: subjectID,
            state: nil,
            message: evidence.reason
                ?? "Process evidence status is \(evidence.status).",
            supportingEventID: nil,
            dependencyNodeID: nil
        )
    }

    private func shortestBlockingPath(
        from nodeID: String,
        nodeByID: [String: GraphNode]
    ) -> [String] {
        var path = [nodeID]
        var current = nodeID
        var visited = Set([nodeID])

        while let node = nodeByID[current] {
            guard let next = node.dependencyNodeIDs.sorted().first(
                where: {
                    nodeByID[$0]?.state.preventsDependentExecution == true
                        || nodeByID[$0] == nil
                }
            ), !visited.contains(next) else {
                break
            }
            path.append(next)
            visited.insert(next)
            current = next
        }
        return path
    }

    private func predecessorIDs(
        nodeID: String,
        nodes: [GraphNode]
    ) -> [String] {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var result = Set<String>()
        var pending = byID[nodeID]?.dependencyNodeIDs.sorted() ?? []

        while let next = pending.first {
            pending.removeFirst()
            guard result.insert(next).inserted else {
                continue
            }
            pending.append(contentsOf: byID[next]?.dependencyNodeIDs ?? [])
            pending.sort()
        }
        return result.sorted()
    }

    private func readinessRequirements(
        node: GraphNode,
        nodeByID: [String: GraphNode]
    ) -> [String] {
        if node.state == .ready || node.state == .running
            || node.state == .completed {
            return []
        }
        if node.dependencyNodeIDs.isEmpty {
            return ["Create an execution attempt for node \(node.id)."]
        }
        return node.dependencyNodeIDs.sorted().compactMap { dependencyID in
            guard nodeByID[dependencyID]?.state != .completed else {
                return nil
            }
            return "Dependency \(dependencyID) must reach completed state."
        }
    }

    private func compareNodes(
        left: GraphTemporalReplayResult,
        right: GraphTemporalReplayResult,
        changes: inout [GraphTemporalChange]
    ) {
        let leftNodes = Dictionary(
            uniqueKeysWithValues: left.projected.nodes.map { ($0.id, $0) }
        )
        let rightNodes = Dictionary(
            uniqueKeysWithValues: right.projected.nodes.map { ($0.id, $0) }
        )
        let leftReconciled = Dictionary(
            uniqueKeysWithValues:
                (left.reconciled?.nodes ?? []).map { ($0.id, $0) }
        )
        let rightReconciled = Dictionary(
            uniqueKeysWithValues:
                (right.reconciled?.nodes ?? []).map { ($0.id, $0) }
        )

        for id in Set(leftNodes.keys).union(rightNodes.keys).sorted() {
            appendChange(
                category: .node,
                entityID: id,
                field: "presence",
                left: leftNodes[id] == nil ? nil : "present",
                right: rightNodes[id] == nil ? nil : "present",
                to: &changes
            )
            appendChange(
                category: .node,
                entityID: id,
                field: "persisted_state",
                left: leftNodes[id]?.state.rawValue,
                right: rightNodes[id]?.state.rawValue,
                to: &changes
            )
            appendChange(
                category: .reconciliation,
                entityID: id,
                field: "node_state",
                left: leftReconciled[id]?.state.rawValue,
                right: rightReconciled[id]?.state.rawValue,
                to: &changes
            )
            appendChange(
                category: .node,
                entityID: id,
                field: "dependencies",
                left: leftNodes[id]?.dependencyNodeIDs.sorted()
                    .joined(separator: ","),
                right: rightNodes[id]?.dependencyNodeIDs.sorted()
                    .joined(separator: ","),
                to: &changes
            )
        }
    }

    private func compareAttempts(
        left: GraphTemporalReplayResult,
        right: GraphTemporalReplayResult,
        changes: inout [GraphTemporalChange]
    ) {
        let leftAttempts = Dictionary(
            uniqueKeysWithValues: left.projected.attempts.map {
                ($0.id, $0)
            }
        )
        let rightAttempts = Dictionary(
            uniqueKeysWithValues: right.projected.attempts.map {
                ($0.id, $0)
            }
        )
        let leftReconciled = Dictionary(
            uniqueKeysWithValues:
                (left.reconciled?.attempts ?? []).map { ($0.id, $0) }
        )
        let rightReconciled = Dictionary(
            uniqueKeysWithValues:
                (right.reconciled?.attempts ?? []).map { ($0.id, $0) }
        )

        for id in Set(leftAttempts.keys).union(rightAttempts.keys).sorted() {
            appendChange(
                category: .attempt,
                entityID: id,
                field: "presence",
                left: leftAttempts[id] == nil ? nil : "present",
                right: rightAttempts[id] == nil ? nil : "present",
                to: &changes
            )
            appendChange(
                category: .attempt,
                entityID: id,
                field: "persisted_state",
                left: leftAttempts[id]?.state.rawValue,
                right: rightAttempts[id]?.state.rawValue,
                to: &changes
            )
            appendChange(
                category: .reconciliation,
                entityID: id,
                field: "attempt_state",
                left: leftReconciled[id]?.state.rawValue,
                right: rightReconciled[id]?.state.rawValue,
                to: &changes
            )
            appendChange(
                category: .attempt,
                entityID: id,
                field: "ordinal",
                left: leftAttempts[id].map { String($0.ordinal) },
                right: rightAttempts[id].map { String($0.ordinal) },
                to: &changes
            )
        }
    }

    private func compareArtifacts(
        left: [GraphArtifactReference],
        right: [GraphArtifactReference],
        changes: inout [GraphTemporalChange]
    ) {
        let leftArtifacts = Dictionary(
            uniqueKeysWithValues: left.map { ($0.id, $0) }
        )
        let rightArtifacts = Dictionary(
            uniqueKeysWithValues: right.map { ($0.id, $0) }
        )

        for id in Set(leftArtifacts.keys).union(rightArtifacts.keys).sorted() {
            appendChange(
                category: .artifact,
                entityID: id,
                field: "digest",
                left: leftArtifacts[id]?.contentDigest.value,
                right: rightArtifacts[id]?.contentDigest.value,
                to: &changes
            )
            appendChange(
                category: .artifact,
                entityID: id,
                field: "producer_attempt",
                left: leftArtifacts[id]?.producingAttemptID,
                right: rightArtifacts[id]?.producingAttemptID,
                to: &changes
            )
        }
    }

    private func compareScheduling(
        left: GraphSchedulingProjection,
        right: GraphSchedulingProjection,
        changes: inout [GraphTemporalChange]
    ) {
        appendChange(
            category: .scheduler,
            entityID: "latest",
            field: "completed_evaluation",
            left: left.records.last {
                $0.eventType
                    == GraphExecutionEventType
                        .schedulerCycleCompleted.rawValue
            }?.evaluationID,
            right: right.records.last {
                $0.eventType
                    == GraphExecutionEventType
                        .schedulerCycleCompleted.rawValue
            }?.evaluationID,
            to: &changes
        )

        let leftClaims = Dictionary(
            uniqueKeysWithValues: left.claims.map { ($0.claim.id, $0) }
        )
        let rightClaims = Dictionary(
            uniqueKeysWithValues: right.claims.map { ($0.claim.id, $0) }
        )
        for id in Set(leftClaims.keys).union(rightClaims.keys).sorted() {
            appendChange(
                category: .claim,
                entityID: id,
                field: "status",
                left: leftClaims[id]?.status.rawValue,
                right: rightClaims[id]?.status.rawValue,
                to: &changes
            )
            appendChange(
                category: .claim,
                entityID: id,
                field: "lease_generation",
                left: leftClaims[id].map {
                    String($0.claim.leaseGeneration)
                },
                right: rightClaims[id].map {
                    String($0.claim.leaseGeneration)
                },
                to: &changes
            )
            appendChange(
                category: .claim,
                entityID: id,
                field: "lease_expiry",
                left: leftClaims[id].map {
                    graphInspectionDateString($0.claim.leaseExpiry)
                },
                right: rightClaims[id].map {
                    graphInspectionDateString($0.claim.leaseExpiry)
                },
                to: &changes
            )
        }

        let leftRetries = Dictionary(
            uniqueKeysWithValues: left.retries.map {
                ("\($0.nodeID):\($0.nextAttemptOrdinal)", $0)
            }
        )
        let rightRetries = Dictionary(
            uniqueKeysWithValues: right.retries.map {
                ("\($0.nodeID):\($0.nextAttemptOrdinal)", $0)
            }
        )
        for id in Set(leftRetries.keys).union(rightRetries.keys).sorted() {
            appendChange(
                category: .retry,
                entityID: id,
                field: "eligible_at",
                left: leftRetries[id].map {
                    graphInspectionDateString($0.eligibleAt)
                },
                right: rightRetries[id].map {
                    graphInspectionDateString($0.eligibleAt)
                },
                to: &changes
            )
        }

        let leftCancellations = Dictionary(
            uniqueKeysWithValues: left.cancellations.map { ($0.id, $0) }
        )
        let rightCancellations = Dictionary(
            uniqueKeysWithValues: right.cancellations.map { ($0.id, $0) }
        )
        for id in Set(leftCancellations.keys)
            .union(rightCancellations.keys).sorted() {
            appendChange(
                category: .cancellation,
                entityID: id,
                field: "state",
                left: leftCancellations[id]?.state.rawValue,
                right: rightCancellations[id]?.state.rawValue,
                to: &changes
            )
        }

        let leftTimeouts = Dictionary(
            uniqueKeysWithValues: left.timeouts.map { ($0.id, $0) }
        )
        let rightTimeouts = Dictionary(
            uniqueKeysWithValues: right.timeouts.map { ($0.id, $0) }
        )
        for id in Set(leftTimeouts.keys).union(rightTimeouts.keys).sorted() {
            appendChange(
                category: .timeout,
                entityID: id,
                field: "kind",
                left: leftTimeouts[id]?.kind.rawValue,
                right: rightTimeouts[id]?.kind.rawValue,
                to: &changes
            )
            appendChange(
                category: .timeout,
                entityID: id,
                field: "deadline",
                left: leftTimeouts[id].map {
                    graphInspectionDateString($0.deadline)
                },
                right: rightTimeouts[id].map {
                    graphInspectionDateString($0.deadline)
                },
                to: &changes
            )
        }
    }

    private func appendChange(
        category: GraphTemporalChangeCategory,
        entityID: String,
        field: String,
        left: String?,
        right: String?,
        to changes: inout [GraphTemporalChange]
    ) {
        guard left != right else {
            return
        }
        changes.append(
            GraphTemporalChange(
                category: category,
                entityID: entityID,
                field: field,
                left: left,
                right: right
            )
        )
    }

    private func stableObservedAt(
        projection: GraphExecutionProjection,
        events: [GraphExecutionEventEnvelope]
    ) -> Date {
        let eventDate = events.reduce(Date(timeIntervalSince1970: 0)) {
            max($0, max($1.occurredAt, $1.recordedAt))
        }
        return max(
            eventDate,
            projection.run?.updatedAt
                ?? Date(timeIntervalSince1970: 0)
        )
    }

    private func evidenceReason(
        _ outcome: GraphProcessEvidenceOutcome
    ) -> String? {
        switch outcome {
        case .available:
            nil
        case let .unavailable(reason),
             let .stale(_, reason),
             let .permissionDenied(reason),
             let .adapterFailed(reason),
             let .identityMismatch(_, reason):
            reason
        }
    }

    private func mappedPersistence<Value: Sendable>(
        _ operation: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operation()
        } catch let error as GraphExecutionPersistenceError {
            switch error {
            case let .unsupportedSchemaVersion(artifact, found, supported):
                throw GraphInspectionError.incompatibleSchema(
                    "\(artifact) version \(found), supported \(supported)"
                )
            case let .corruptRecord(message):
                throw GraphInspectionError.corruptHistory(message)
            default:
                throw GraphInspectionError.persistence(
                    error.localizedDescription
                )
            }
        } catch let error as GraphInspectionError {
            throw error
        } catch {
            throw GraphInspectionError.persistence(
                error.localizedDescription
            )
        }
    }

    private func mappedReplay(
        _ error: GraphExecutionReplayError
    ) -> GraphInspectionError {
        switch error {
        case let .unsupportedEnvelopeSchema(found, supported):
            .incompatibleSchema(
                "event envelope version \(found), supported \(supported)"
            )
        case let .unsupportedPayloadSchema(eventType, found, supported):
            .incompatibleSchema(
                "\(eventType) payload version \(found), supported \(supported)"
            )
        default:
            .corruptHistory(error.localizedDescription)
        }
    }
}

private func bounded(_ value: String?, limit: Int = 512) -> String? {
    guard let value else {
        return nil
    }
    let singleLine = value
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
    guard singleLine.count > limit else {
        return singleLine
    }
    return String(singleLine.prefix(limit))
}

private func graphInspectionDateString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func attemptIsOrderedBefore(
    _ lhs: ExecutionAttempt,
    _ rhs: ExecutionAttempt
) -> Bool {
    if lhs.nodeID != rhs.nodeID {
        return lhs.nodeID < rhs.nodeID
    }
    if lhs.ordinal != rhs.ordinal {
        return lhs.ordinal < rhs.ordinal
    }
    return lhs.id < rhs.id
}

private func attemptIsOrderedBefore(
    _ lhs: GraphAttemptInspection,
    _ rhs: GraphAttemptInspection
) -> Bool {
    if lhs.nodeID != rhs.nodeID {
        return lhs.nodeID < rhs.nodeID
    }
    if lhs.ordinal != rhs.ordinal {
        return lhs.ordinal < rhs.ordinal
    }
    return lhs.id < rhs.id
}

private func checkpointIsOrderedBefore(
    _ lhs: GraphCheckpointReference,
    _ rhs: GraphCheckpointReference
) -> Bool {
    if lhs.streamVersion != rhs.streamVersion {
        return lhs.streamVersion < rhs.streamVersion
    }
    return lhs.checkpointID < rhs.checkpointID
}

private func changeIsOrderedBefore(
    _ lhs: GraphTemporalChange,
    _ rhs: GraphTemporalChange
) -> Bool {
    if lhs.category != rhs.category {
        return lhs.category.rawValue < rhs.category.rawValue
    }
    if lhs.entityID != rhs.entityID {
        return lhs.entityID < rhs.entityID
    }
    return lhs.field < rhs.field
}

private func reasonID(
    _ code: GraphCausalReasonCode,
    _ subjectID: String
) -> String {
    "\(code.rawValue):\(subjectID)"
}

private func uniqueReasons(
    _ reasons: [GraphCausalReason]
) -> [GraphCausalReason] {
    var byID: [String: GraphCausalReason] = [:]
    for reason in reasons {
        byID[reason.id] = reason
    }
    return Array(byID.values)
}

private func attemptHasIdentity(_ attempt: ExecutionAttempt) -> Bool {
    attempt.processIdentity != nil
}
