import Foundation

public struct GraphExecutionSnapshot: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let runID: String
    public let streamVersion: UInt64
    public let graphDefinitionVersion: String
    public let graphDefinitionDigest: GraphContentDigest
    public let projectedState: GraphExecutionProjection
    public let createdAt: Date
    public let createdBy: GraphExecutionProducer
    public let integrity: GraphExecutionIntegrityMetadata?
    public let checkpointNamespace: String
    public let namedCheckpoints: [GraphCheckpointReference]

    public init(
        schemaVersion: Int = GraphExecutionSchema.snapshotVersion,
        runID: String,
        streamVersion: UInt64,
        graphDefinitionVersion: String,
        graphDefinitionDigest: GraphContentDigest,
        projectedState: GraphExecutionProjection,
        createdAt: Date,
        createdBy: GraphExecutionProducer,
        integrity: GraphExecutionIntegrityMetadata? = nil,
        checkpointNamespace: String,
        namedCheckpoints: [GraphCheckpointReference] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.streamVersion = streamVersion
        self.graphDefinitionVersion = graphDefinitionVersion
        self.graphDefinitionDigest = graphDefinitionDigest
        self.projectedState = projectedState
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.integrity = integrity
        self.checkpointNamespace = checkpointNamespace
        self.namedCheckpoints = namedCheckpoints
    }
}

public protocol GraphExecutionSnapshotStore: Sendable {
    func loadLatest(runID: String) async throws -> GraphExecutionSnapshot?
    func save(_ snapshot: GraphExecutionSnapshot) async throws
}

public actor InMemoryGraphExecutionSnapshotStore:
    GraphExecutionSnapshotStore
{
    package var snapshots: [String: [GraphExecutionSnapshot]]

    public init(snapshots: [GraphExecutionSnapshot] = []) {
        self.snapshots = Dictionary(
            grouping: snapshots,
            by: \.runID
        )
    }

    public func loadLatest(
        runID: String
    ) -> GraphExecutionSnapshot? {
        snapshots[runID]?.max {
            if $0.streamVersion != $1.streamVersion {
                return $0.streamVersion < $1.streamVersion
            }

            return $0.createdAt < $1.createdAt
        }
    }

    public func save(
        _ snapshot: GraphExecutionSnapshot
    ) throws {
        var runSnapshots = snapshots[snapshot.runID] ?? []

        if let existing = runSnapshots.first(where: {
            $0.streamVersion == snapshot.streamVersion
        }) {
            guard existing == snapshot else {
                throw GraphExecutionPersistenceError.corruptRecord(
                    "Snapshot \(snapshot.runID)@\(snapshot.streamVersion) already exists with different content."
                )
            }

            return
        }

        runSnapshots.append(snapshot)
        snapshots[snapshot.runID] = runSnapshots
    }
}

public protocol GraphExecutionSnapshotPolicy: Sendable {
    func shouldCreateSnapshot(
        replayedEventCount: Int,
        streamVersion: UInt64
    ) -> Bool
}

public struct NeverGraphExecutionSnapshotPolicy:
    GraphExecutionSnapshotPolicy
{
    public init() {}

    public func shouldCreateSnapshot(
        replayedEventCount: Int,
        streamVersion: UInt64
    ) -> Bool {
        false
    }
}

public struct EventCountGraphExecutionSnapshotPolicy:
    GraphExecutionSnapshotPolicy
{
    public let minimumReplayedEventCount: Int

    public init(minimumReplayedEventCount: Int) {
        self.minimumReplayedEventCount = max(
            1,
            minimumReplayedEventCount
        )
    }

    public func shouldCreateSnapshot(
        replayedEventCount: Int,
        streamVersion: UInt64
    ) -> Bool {
        replayedEventCount >= minimumReplayedEventCount
            && streamVersion > 0
    }
}

public struct GraphProcessEvidence: Equatable, Codable, Sendable {
    public var processExits: [ProcessExit]
    public var heartbeats: [ExecutorHeartbeat]

    public init(
        processExits: [ProcessExit] = [],
        heartbeats: [ExecutorHeartbeat] = []
    ) {
        self.processExits = processExits
        self.heartbeats = heartbeats
    }
}

public enum GraphProcessEvidenceOutcome: Equatable, Codable, Sendable {
    case available(GraphProcessEvidence)
    case unavailable(reason: String)
    case stale(GraphProcessEvidence, reason: String)
    case permissionDenied(reason: String)
    case adapterFailed(reason: String)
    case identityMismatch(GraphProcessEvidence, reason: String)

    public var status: String {
        switch self {
        case .available:
            "available"
        case .unavailable:
            "unavailable"
        case .stale:
            "stale"
        case .permissionDenied:
            "permission_denied"
        case .adapterFailed:
            "adapter_failed"
        case .identityMismatch:
            "identity_mismatch"
        }
    }
}

public struct GraphProcessEvidenceRequest: Equatable, Sendable {
    public let runID: String
    public let attempts: [ExecutionAttempt]
    public let observedAt: Date

    public init(
        runID: String,
        attempts: [ExecutionAttempt],
        observedAt: Date
    ) {
        self.runID = runID
        self.attempts = attempts
        self.observedAt = observedAt
    }
}

public protocol ProcessEvidenceSource: Sendable {
    func evidence(
        for request: GraphProcessEvidenceRequest
    ) async -> GraphProcessEvidenceOutcome
}

public struct UnavailableProcessEvidenceSource:
    ProcessEvidenceSource
{
    public let reason: String

    public init(reason: String = "No process evidence adapter configured.") {
        self.reason = reason
    }

    public func evidence(
        for request: GraphProcessEvidenceRequest
    ) async -> GraphProcessEvidenceOutcome {
        .unavailable(reason: reason)
    }
}

public enum GraphTelemetryOperation: String, Codable, CaseIterable, Sendable {
    case repositoryLoad = "openisland.graph.repository.load"
    case eventAppend = "openisland.graph.event.append"
    case eventReplay = "openisland.graph.event.replay"
    case snapshotLoad = "openisland.graph.snapshot.load"
    case reconciliation = "openisland.graph.reconciliation"
    case processEvidenceQuery = "openisland.graph.process_evidence.query"
}

public enum GraphTelemetryPhase: String, Codable, Sendable {
    case started
    case completed
    case failed
}

public enum GraphTelemetryAttribute {
    public static let runID = "openisland.graph.run.id"
    public static let nodeID = "openisland.graph.node.id"
    public static let attemptID = "openisland.graph.attempt.id"
    public static let executorID = "openisland.graph.executor.id"
    public static let eventType = "openisland.graph.event.type"
    public static let streamVersion = "openisland.graph.stream.version"
    public static let replayCount = "openisland.graph.replay.count"
    public static let reconciliationResult =
        "openisland.graph.reconciliation.result"
    public static let errorCategory = "error.type"
}

public struct GraphTelemetryRecord: Equatable, Codable, Sendable {
    public let operation: GraphTelemetryOperation
    public let phase: GraphTelemetryPhase
    public let attributes: [String: String]

    public init(
        operation: GraphTelemetryOperation,
        phase: GraphTelemetryPhase,
        attributes: [String: String]
    ) {
        self.operation = operation
        self.phase = phase
        self.attributes = attributes
    }
}

public protocol GraphExecutionTelemetrySink: Sendable {
    func record(_ record: GraphTelemetryRecord) async
}

public struct NoopGraphExecutionTelemetrySink:
    GraphExecutionTelemetrySink
{
    public init() {}

    public func record(_ record: GraphTelemetryRecord) async {}
}

public enum GraphSnapshotDisposition: String, Codable, Sendable {
    case missing
    case current
    case stale
    case incompatible
    case corrupt
    case aheadOfStream
    case created
}

public enum GraphRepositoryDiagnosticCategory: String, Codable, Sendable {
    case snapshot
    case replay
    case evidence
    case reconciliation
}

public struct GraphRepositoryDiagnostic: Equatable, Codable, Sendable {
    public let category: GraphRepositoryDiagnosticCategory
    public let message: String

    public init(
        category: GraphRepositoryDiagnosticCategory,
        message: String
    ) {
        self.category = category
        self.message = message
    }
}

public struct GraphExecutionRepositoryLoadResult:
    Equatable,
    Sendable
{
    public let runID: String
    public let streamVersion: UInt64
    public let persistedProjection: GraphExecutionProjection
    public let reconciledState: ExecutionReconciliationResult?
    public let snapshotDisposition: GraphSnapshotDisposition
    public let replayDiagnostics: [GraphReplayDiagnostic]
    public let evidenceOutcome: GraphProcessEvidenceOutcome
    public let diagnostics: [GraphRepositoryDiagnostic]

    public init(
        runID: String,
        streamVersion: UInt64,
        persistedProjection: GraphExecutionProjection,
        reconciledState: ExecutionReconciliationResult?,
        snapshotDisposition: GraphSnapshotDisposition,
        replayDiagnostics: [GraphReplayDiagnostic],
        evidenceOutcome: GraphProcessEvidenceOutcome,
        diagnostics: [GraphRepositoryDiagnostic]
    ) {
        self.runID = runID
        self.streamVersion = streamVersion
        self.persistedProjection = persistedProjection
        self.reconciledState = reconciledState
        self.snapshotDisposition = snapshotDisposition
        self.replayDiagnostics = replayDiagnostics
        self.evidenceOutcome = evidenceOutcome
        self.diagnostics = diagnostics
    }
}

public enum GraphExecutionProjectionReconciler {
    public static func reconcile(
        projection: GraphExecutionProjection,
        evidenceOutcome: GraphProcessEvidenceOutcome,
        observedAt: Date
    ) -> ExecutionReconciliationResult? {
        guard let run = projection.run else {
            return nil
        }

        var processExits = projection.processExits
        var heartbeats = projection.heartbeats

        switch evidenceOutcome {
        case let .available(evidence),
             let .stale(evidence, _):
            processExits.append(contentsOf: evidence.processExits)
            heartbeats.append(contentsOf: evidence.heartbeats)
        case .unavailable,
             .permissionDenied,
             .adapterFailed,
             .identityMismatch:
            break
        }

        return GraphExecutionReconciler.reconcile(
            ExecutionReconciliationInput(
                run: run,
                nodes: projection.nodes,
                attempts: projection.attempts,
                processExits: processExits,
                heartbeats: heartbeats,
                events: projection.executionEvents,
                observedAt: observedAt
            )
        )
    }
}

public protocol GraphExecutionRepository: Sendable {
    func load(
        runID: String,
        observedAt: Date
    ) async throws -> GraphExecutionRepositoryLoadResult
}

public struct DefaultGraphExecutionRepository:
    GraphExecutionRepository,
    Sendable
{
    private let eventStore: any GraphExecutionEventStore
    private let snapshotStore: any GraphExecutionSnapshotStore
    private let evidenceSource: any ProcessEvidenceSource
    private let snapshotPolicy: any GraphExecutionSnapshotPolicy
    private let snapshotProducer: GraphExecutionProducer
    private let telemetry: any GraphExecutionTelemetrySink

    public init(
        eventStore: any GraphExecutionEventStore,
        snapshotStore: any GraphExecutionSnapshotStore,
        evidenceSource: any ProcessEvidenceSource,
        snapshotPolicy: any GraphExecutionSnapshotPolicy =
            NeverGraphExecutionSnapshotPolicy(),
        snapshotProducer: GraphExecutionProducer =
            GraphExecutionProducer(
                id: "openisland.graph.repository",
                kind: .application
            ),
        telemetry: any GraphExecutionTelemetrySink =
            NoopGraphExecutionTelemetrySink()
    ) {
        self.eventStore = eventStore
        self.snapshotStore = snapshotStore
        self.evidenceSource = evidenceSource
        self.snapshotPolicy = snapshotPolicy
        self.snapshotProducer = snapshotProducer
        self.telemetry = telemetry
    }

    public func load(
        runID: String,
        observedAt: Date
    ) async throws -> GraphExecutionRepositoryLoadResult {
        await telemetry.record(
            telemetryRecord(
                operation: .repositoryLoad,
                phase: .started,
                runID: runID
            )
        )

        var diagnostics: [GraphRepositoryDiagnostic] = []
        let snapshotLoad = await loadSnapshot(
            runID: runID,
            diagnostics: &diagnostics
        )
        var snapshot = snapshotLoad.snapshot
        var disposition = snapshotLoad.disposition
        var stream = try await eventStore.read(
            runID: runID,
            afterVersion: snapshot?.streamVersion ?? 0
        )

        if let loadedSnapshot = snapshot,
           loadedSnapshot.streamVersion > stream.currentVersion {
            diagnostics.append(
                GraphRepositoryDiagnostic(
                    category: .snapshot,
                    message: "Snapshot is ahead of the event stream and was bypassed."
                )
            )
            disposition = .aheadOfStream
            stream = try await eventStore.read(
                runID: runID,
                afterVersion: 0
            )
            snapshot = nil
        } else if snapshot != nil, !stream.events.isEmpty {
            disposition = .stale
            diagnostics.append(
                GraphRepositoryDiagnostic(
                    category: .snapshot,
                    message: "Replayed events written after the snapshot boundary."
                )
            )
        }

        await telemetry.record(
            telemetryRecord(
                operation: .eventReplay,
                phase: .started,
                runID: runID,
                streamVersion: stream.currentVersion
            )
        )
        let replay = try GraphExecutionProjector.replay(
            runID: runID,
            events: stream.events,
            initialProjection: snapshot?.projectedState
        )
        diagnostics.append(
            GraphRepositoryDiagnostic(
                category: .replay,
                message: "Replayed \(replay.replayedEventCount) event(s) through stream version \(replay.projection.streamVersion)."
            )
        )
        await telemetry.record(
            GraphTelemetryRecord(
                operation: .eventReplay,
                phase: .completed,
                attributes: [
                    GraphTelemetryAttribute.runID: runID,
                    GraphTelemetryAttribute.streamVersion:
                        String(replay.projection.streamVersion),
                    GraphTelemetryAttribute.replayCount:
                        String(replay.replayedEventCount),
                ]
            )
        )

        let evidenceRequest = GraphProcessEvidenceRequest(
            runID: runID,
            attempts: replay.projection.attempts,
            observedAt: observedAt
        )
        await telemetry.record(
            telemetryRecord(
                operation: .processEvidenceQuery,
                phase: .started,
                runID: runID
            )
        )
        let evidenceOutcome = await evidenceSource.evidence(
            for: evidenceRequest
        )
        diagnostics.append(
            GraphRepositoryDiagnostic(
                category: .evidence,
                message: "Process evidence status: \(evidenceOutcome.status)."
            )
        )
        await telemetry.record(
            GraphTelemetryRecord(
                operation: .processEvidenceQuery,
                phase: .completed,
                attributes: [
                    GraphTelemetryAttribute.runID: runID,
                    GraphTelemetryAttribute.reconciliationResult:
                        evidenceOutcome.status,
                ]
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
            await telemetry.record(
                GraphTelemetryRecord(
                    operation: .reconciliation,
                    phase: .completed,
                    attributes: [
                        GraphTelemetryAttribute.runID: runID,
                        GraphTelemetryAttribute.reconciliationResult:
                            reconciled.run.state.rawValue,
                    ]
                )
            )
        }

        if snapshotPolicy.shouldCreateSnapshot(
            replayedEventCount: replay.replayedEventCount,
            streamVersion: replay.projection.streamVersion
        ), let newSnapshot = makeSnapshot(
            projection: replay.projection,
            createdAt: observedAt
        ) {
            try await snapshotStore.save(newSnapshot)
            disposition = .created
            diagnostics.append(
                GraphRepositoryDiagnostic(
                    category: .snapshot,
                    message: "Created snapshot at stream version \(newSnapshot.streamVersion)."
                )
            )
        }

        await telemetry.record(
            telemetryRecord(
                operation: .repositoryLoad,
                phase: .completed,
                runID: runID,
                streamVersion: replay.projection.streamVersion
            )
        )

        return GraphExecutionRepositoryLoadResult(
            runID: runID,
            streamVersion: replay.projection.streamVersion,
            persistedProjection: replay.projection,
            reconciledState: reconciled,
            snapshotDisposition: disposition,
            replayDiagnostics: replay.diagnostics,
            evidenceOutcome: evidenceOutcome,
            diagnostics: diagnostics
        )
    }

    private func loadSnapshot(
        runID: String,
        diagnostics: inout [GraphRepositoryDiagnostic]
    ) async -> (
        snapshot: GraphExecutionSnapshot?,
        disposition: GraphSnapshotDisposition
    ) {
        await telemetry.record(
            telemetryRecord(
                operation: .snapshotLoad,
                phase: .started,
                runID: runID
            )
        )

        do {
            guard let snapshot = try await snapshotStore.loadLatest(
                runID: runID
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
                  snapshot.projectedState.streamVersion
                    == snapshot.streamVersion,
                  snapshot.projectedState.graphDefinitionVersion
                    == snapshot.graphDefinitionVersion,
                  snapshot.projectedState.graphDefinitionDigest
                    == snapshot.graphDefinitionDigest else {
                diagnostics.append(
                    GraphRepositoryDiagnostic(
                        category: .snapshot,
                        message: "Snapshot metadata is internally inconsistent and was bypassed."
                    )
                )
                return (nil, .corrupt)
            }

            return (snapshot, .current)
        } catch {
            diagnostics.append(
                GraphRepositoryDiagnostic(
                    category: .snapshot,
                    message: "Snapshot load failed and full replay was used: \(error.localizedDescription)"
                )
            )
            return (nil, .corrupt)
        }
    }

    private func makeSnapshot(
        projection: GraphExecutionProjection,
        createdAt: Date
    ) -> GraphExecutionSnapshot? {
        guard let graphDefinitionVersion =
                projection.graphDefinitionVersion,
              let graphDefinitionDigest =
                projection.graphDefinitionDigest else {
            return nil
        }

        return GraphExecutionSnapshot(
            runID: projection.runID,
            streamVersion: projection.streamVersion,
            graphDefinitionVersion: graphDefinitionVersion,
            graphDefinitionDigest: graphDefinitionDigest,
            projectedState: projection,
            createdAt: createdAt,
            createdBy: snapshotProducer,
            checkpointNamespace: projection.checkpointNamespace,
            namedCheckpoints: projection.namedCheckpoints
        )
    }

    private func telemetryRecord(
        operation: GraphTelemetryOperation,
        phase: GraphTelemetryPhase,
        runID: String,
        streamVersion: UInt64? = nil
    ) -> GraphTelemetryRecord {
        var attributes = [
            GraphTelemetryAttribute.runID: runID,
        ]

        if let streamVersion {
            attributes[GraphTelemetryAttribute.streamVersion] =
                String(streamVersion)
        }

        return GraphTelemetryRecord(
            operation: operation,
            phase: phase,
            attributes: attributes
        )
    }
}
