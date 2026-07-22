import Foundation
import OpenIslandCore

enum GraphWorkspaceRefreshBehavior: String, Codable, Sendable {
    case none
    case refreshRun = "refresh_run"
    case refreshHistory = "refresh_history"
    case refreshAll = "refresh_all"
}

struct GraphWorkspaceCommandResult: Equatable, Codable, Sendable {
    let accepted: Bool
    let reasonCode: String
    let streamVersion: UInt64?
    let runID: String?
    let nodeIDs: [String]
    let diagnostics: [String]
    let suggestedRefresh: GraphWorkspaceRefreshBehavior

    static func rejected(
        _ reasonCode: String,
        runID: String? = nil,
        nodeIDs: [String] = [],
        diagnostic: String
    ) -> GraphWorkspaceCommandResult {
        GraphWorkspaceCommandResult(
            accepted: false,
            reasonCode: reasonCode,
            streamVersion: nil,
            runID: runID,
            nodeIDs: nodeIDs.sorted(),
            diagnostics: [diagnostic],
            suggestedRefresh: .none
        )
    }
}

protocol GraphWorkspaceServicing: Sendable {
    func revisions() async -> AsyncStream<UInt64>
    func loadDocument(url: URL) async throws -> GraphDefinitionDocument
    func saveDocument(_ document: GraphDefinitionDocument, url: URL) async throws
    func createRun(
        document: GraphDefinitionDocument,
        runID: String,
        occurredAt: Date
    ) async -> GraphWorkspaceCommandResult
    func startRun(runID: String, occurredAt: Date) async
        -> GraphWorkspaceCommandResult
    func step(runID: String, occurredAt: Date) async
        -> GraphWorkspaceCommandResult
    func retry(runID: String, nodeID: String, occurredAt: Date) async
        -> GraphWorkspaceCommandResult
    func cancel(runID: String, nodeID: String?, occurredAt: Date) async
        -> GraphWorkspaceCommandResult
    func inspect(runID: String) async throws -> GraphRunInspection
    func listRuns() async throws -> [GraphRunInspectionSummary]
    func history(runID: String) async throws -> GraphInspectionEventPage
    func explain(runID: String, nodeID: String?) async throws
        -> GraphCausalExplanation
    func logs(runID: String, nodeID: String) async throws
        -> GraphProcessLogPage
    func exportRun(runID: String, url: URL) async throws
}

actor GraphWorkspaceService: GraphWorkspaceServicing {
    private let mutator: any GraphMutating
    private let orchestrator: any GraphOrchestrating
    private let inspector: any GraphTemporalInspecting
    private let processExecutor: SupervisedLocalProcessExecutor
    private let launchStore: GraphLocalProcessLaunchStore
    private var revision: UInt64 = 0
    private var revisionObservers: [UUID: AsyncStream<UInt64>.Continuation] = [:]

    init(
        eventStore: any GraphExecutionEventStore,
        readStore: any GraphExecutionReadStore,
        snapshotStore: any GraphExecutionSnapshotReadStore,
        processExecutor: SupervisedLocalProcessExecutor,
        launchStore: GraphLocalProcessLaunchStore
    ) {
        mutator = DefaultGraphMutationService(
            eventStore: eventStore,
            readStore: readStore
        )
        orchestrator = DefaultGraphOrchestrationService(
            eventStore: eventStore,
            schedulingRepository: DefaultGraphSchedulingRepository(
                eventStore: eventStore
            ),
            executorRepository: DefaultGraphExecutorRepository(
                eventStore: eventStore
            ),
            executor: processExecutor,
            confirmationPolicy: LocalProcessExecutionConfirmationPolicy()
        )
        inspector = DefaultGraphTemporalInspector(
            readStore: readStore,
            snapshotStore: snapshotStore,
            evidenceSource: GraphLocalProcessEvidenceSource(
                launchStore: launchStore
            )
        )
        self.processExecutor = processExecutor
        self.launchStore = launchStore
    }

    static func live() throws -> GraphWorkspaceService {
        let databasePath = try SQLiteGraphExecutionStore.defaultDatabasePath()
        let store = try SQLiteGraphExecutionStore(databasePath: databasePath)
        let launchStore = try GraphLocalProcessLaunchStore(
            rootURL: GraphLocalProcessLaunchStore.defaultRootURL()
        )
        let executor = SupervisedLocalProcessExecutor(
            launchStore: launchStore
        )
        return GraphWorkspaceService(
            eventStore: store,
            readStore: store,
            snapshotStore: store,
            processExecutor: executor,
            launchStore: launchStore
        )
    }

    static func inMemory(
        rootURL: URL
    ) throws -> GraphWorkspaceService {
        let store = InMemoryGraphExecutionEventStore()
        let launchStore = try GraphLocalProcessLaunchStore(rootURL: rootURL)
        let executor = SupervisedLocalProcessExecutor(
            launchStore: launchStore
        )
        return GraphWorkspaceService(
            eventStore: store,
            readStore: store,
            snapshotStore: InMemoryGraphExecutionSnapshotStore(),
            processExecutor: executor,
            launchStore: launchStore
        )
    }

    func revisions() -> AsyncStream<UInt64> {
        let id = UUID()
        return AsyncStream { continuation in
            revisionObservers[id] = continuation
            continuation.yield(revision)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeRevisionObserver(id) }
            }
        }
    }

    func loadDocument(url: URL) throws -> GraphDefinitionDocument {
        try GraphDefinitionDocumentCodec.load(url: url)
    }

    func saveDocument(
        _ document: GraphDefinitionDocument,
        url: URL
    ) throws {
        try GraphDefinitionDocumentCodec.save(document, to: url)
    }

    func createRun(
        document: GraphDefinitionDocument,
        runID: String,
        occurredAt: Date
    ) async -> GraphWorkspaceCommandResult {
        do {
            try document.validate()
            let report = try await mutator.create(
                GraphCreateRequest(
                    runID: runID,
                    definition: try document.executableDefinition(),
                    idempotencyKey: "workspace-create-\(runID)",
                    occurredAt: occurredAt,
                    producer: workspaceProducer
                )
            )
            emitRevision()
            return result(report, reasonCode: "run_created")
        } catch {
            return .rejected(
                "run_create_rejected",
                runID: runID,
                diagnostic: error.localizedDescription
            )
        }
    }

    func startRun(
        runID: String,
        occurredAt: Date
    ) async -> GraphWorkspaceCommandResult {
        do {
            let report = try await mutator.start(
                GraphStartRequest(
                    runID: runID,
                    idempotencyKey: "workspace-start-\(runID)",
                    requestedBy: NSUserName(),
                    occurredAt: occurredAt,
                    producer: workspaceProducer
                )
            )
            emitRevision()
            return result(report, reasonCode: "run_start_requested")
        } catch {
            return .rejected(
                "run_start_rejected",
                runID: runID,
                diagnostic: error.localizedDescription
            )
        }
    }

    func step(
        runID: String,
        occurredAt: Date
    ) async -> GraphWorkspaceCommandResult {
        do {
            let report = try await orchestrator.step(
                GraphOrchestrationStepRequest(
                    runID: runID,
                    logicalTime: occurredAt
                )
            )
            emitRevision()
            return GraphWorkspaceCommandResult(
                accepted: report.status != .adapterUnavailable,
                reasonCode: report.policyDenials.first?.rawValue
                    ?? report.status.rawValue,
                streamVersion: report.streamVersion,
                runID: report.runID,
                nodeIDs: [report.claimedNodeID].compactMap { $0 },
                diagnostics: [
                    report.executorStatus?.rawValue,
                    report.executorOperation?.rawValue,
                ].compactMap { $0 },
                suggestedRefresh: .refreshAll
            )
        } catch {
            return .rejected(
                "orchestration_step_rejected",
                runID: runID,
                diagnostic: error.localizedDescription
            )
        }
    }

    func retry(
        runID: String,
        nodeID: String,
        occurredAt: Date
    ) async -> GraphWorkspaceCommandResult {
        do {
            let report = try await mutator.retry(
                GraphRetryMutationRequest(
                    runID: runID,
                    nodeID: nodeID,
                    idempotencyKey: "workspace-retry-\(UUID().uuidString)",
                    requestedBy: NSUserName(),
                    occurredAt: occurredAt,
                    producer: workspaceProducer
                )
            )
            emitRevision()
            return result(report, reasonCode: "retry_requested")
        } catch {
            return .rejected(
                "retry_rejected",
                runID: runID,
                nodeIDs: [nodeID],
                diagnostic: error.localizedDescription
            )
        }
    }

    func cancel(
        runID: String,
        nodeID: String?,
        occurredAt: Date
    ) async -> GraphWorkspaceCommandResult {
        do {
            let report = try await mutator.cancel(
                GraphCancelMutationRequest(
                    runID: runID,
                    nodeID: nodeID,
                    idempotencyKey: "workspace-cancel-\(UUID().uuidString)",
                    requestedBy: NSUserName(),
                    reason: "graph_workspace",
                    occurredAt: occurredAt,
                    producer: workspaceProducer
                )
            )
            emitRevision()
            return result(report, reasonCode: "cancellation_requested")
        } catch {
            return .rejected(
                "cancellation_rejected",
                runID: runID,
                nodeIDs: [nodeID].compactMap { $0 },
                diagnostic: error.localizedDescription
            )
        }
    }

    func inspect(runID: String) async throws -> GraphRunInspection {
        try await inspector.inspect(
            runID: runID,
            includeArtifacts: true,
            includeDiagnostics: true
        )
    }

    func listRuns() async throws -> [GraphRunInspectionSummary] {
        try await inspector.listRuns(state: nil, limit: 250)
    }

    func history(runID: String) async throws -> GraphInspectionEventPage {
        try await inspector.eventPage(
            runID: runID,
            filter: GraphInspectionEventFilter(limit: 2_000)
        )
    }

    func explain(
        runID: String,
        nodeID: String?
    ) async throws -> GraphCausalExplanation {
        try await inspector.explain(runID: runID, nodeID: nodeID)
    }

    func logs(
        runID: String,
        nodeID: String
    ) async throws -> GraphProcessLogPage {
        let records = try await launchStore.records().filter {
            $0.identity.runID == runID && $0.identity.nodeID == nodeID
        }
        guard let record = records.max(by: {
            if $0.identity.attemptOrdinal != $1.identity.attemptOrdinal {
                return $0.identity.attemptOrdinal < $1.identity.attemptOrdinal
            }
            return $0.preparedAt < $1.preparedAt
        }) else {
            throw GraphLocalProcessRuntimeError.launchRecordMissing(
                "\(runID)/\(nodeID)"
            )
        }
        return try await processExecutor.logs(
            launchRecordID: record.id,
            limit: 5_000
        )
    }

    func exportRun(runID: String, url: URL) async throws {
        let inspection = try await inspect(runID: runID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(inspection).write(to: url, options: .atomic)
    }

    private var workspaceProducer: GraphExecutionProducer {
        GraphExecutionProducer(
            id: "openisland.graph-workspace",
            kind: .application
        )
    }

    private func result(
        _ report: GraphMutationReport,
        reasonCode: String
    ) -> GraphWorkspaceCommandResult {
        GraphWorkspaceCommandResult(
            accepted: report.status != .proposed,
            reasonCode: reasonCode,
            streamVersion: report.streamVersion,
            runID: report.runID,
            nodeIDs: report.nodeIDs,
            diagnostics: report.eventTypes,
            suggestedRefresh: .refreshAll
        )
    }

    private func emitRevision() {
        revision &+= 1
        revisionObservers.values.forEach { $0.yield(revision) }
    }

    private func removeRevisionObserver(_ id: UUID) {
        revisionObservers.removeValue(forKey: id)
    }
}

actor UnavailableGraphWorkspaceService: GraphWorkspaceServicing {
    private let message: String

    init(message: String) { self.message = message }

    func revisions() -> AsyncStream<UInt64> {
        AsyncStream { $0.yield(0); $0.finish() }
    }

    func loadDocument(url: URL) throws -> GraphDefinitionDocument { throw error }
    func saveDocument(_ document: GraphDefinitionDocument, url: URL) throws { throw error }
    func createRun(document: GraphDefinitionDocument, runID: String, occurredAt: Date) -> GraphWorkspaceCommandResult { rejected(runID) }
    func startRun(runID: String, occurredAt: Date) -> GraphWorkspaceCommandResult { rejected(runID) }
    func step(runID: String, occurredAt: Date) -> GraphWorkspaceCommandResult { rejected(runID) }
    func retry(runID: String, nodeID: String, occurredAt: Date) -> GraphWorkspaceCommandResult { rejected(runID, nodeID) }
    func cancel(runID: String, nodeID: String?, occurredAt: Date) -> GraphWorkspaceCommandResult { rejected(runID, nodeID) }
    func inspect(runID: String) throws -> GraphRunInspection { throw error }
    func listRuns() throws -> [GraphRunInspectionSummary] { throw error }
    func history(runID: String) throws -> GraphInspectionEventPage { throw error }
    func explain(runID: String, nodeID: String?) throws -> GraphCausalExplanation { throw error }
    func logs(runID: String, nodeID: String) throws -> GraphProcessLogPage { throw error }
    func exportRun(runID: String, url: URL) throws { throw error }

    private var error: NSError {
        NSError(
            domain: "OpenIsland.GraphWorkspace",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func rejected(
        _ runID: String,
        _ nodeID: String? = nil
    ) -> GraphWorkspaceCommandResult {
        .rejected(
            "workspace_unavailable",
            runID: runID,
            nodeIDs: [nodeID].compactMap { $0 },
            diagnostic: message
        )
    }
}
