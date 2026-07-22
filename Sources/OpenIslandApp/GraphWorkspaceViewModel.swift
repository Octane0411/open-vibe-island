import AppKit
import Foundation
import Observation
import OpenIslandCore
import SwiftUI

enum GraphWorkspaceEntryPoint {
    static let windowID = "graph-workspace"
    static let label = "Graph Workspace"
    static let shortcutKey: KeyEquivalent = "g"
}

enum GraphWorkspaceMode: String, CaseIterable, Identifiable {
    case definition = "Definition"
    case run = "Run"
    case history = "History"

    var id: String { rawValue }
}

enum GraphWorkspaceCommand: String, CaseIterable, Sendable {
    case createRun = "create_run"
    case start
    case step
    case run
    case pauseLocal = "pause_local"
    case cancelRun = "cancel_run"
    case cancelNode = "cancel_node"
    case retryNode = "retry_node"
    case openLogs = "open_logs"
    case inspectHistory = "inspect_history"
    case export
}

struct GraphWorkspaceCommandDecision: Equatable, Sendable {
    let command: GraphWorkspaceCommand
    let isEnabled: Bool
    let reasonCode: String
}

enum GraphWorkspaceCommandPolicy {
    static func decision(
        _ command: GraphWorkspaceCommand,
        document: GraphDefinitionDocument?,
        inspection: GraphRunInspection?,
        selectedNodeID: String?,
        isOrchestrating: Bool
    ) -> GraphWorkspaceCommandDecision {
        switch command {
        case .createRun:
            return decision(
                command,
                enabled: document?.nodes.isEmpty == false,
                denial: "definition_has_no_nodes"
            )
        case .start:
            return decision(
                command,
                enabled: inspection != nil
                    && inspection?.summary.persistedState.isTerminal == false,
                denial: "run_unavailable_or_terminal"
            )
        case .step, .run:
            return decision(
                command,
                enabled: inspection != nil
                    && inspection?.summary.persistedState.isTerminal == false
                    && !isOrchestrating,
                denial: isOrchestrating
                    ? "orchestration_already_running"
                    : "run_unavailable_or_terminal"
            )
        case .pauseLocal:
            return decision(
                command,
                enabled: isOrchestrating,
                denial: "local_orchestration_not_running"
            )
        case .cancelRun:
            return decision(
                command,
                enabled: inspection != nil
                    && inspection?.summary.persistedState.isTerminal == false,
                denial: "run_unavailable_or_terminal"
            )
        case .cancelNode:
            guard let selectedNodeID,
                  let node = inspection?.nodes.first(where: {
                      $0.id == selectedNodeID
                  }) else {
                return decision(
                    command,
                    enabled: false,
                    denial: "node_not_selected"
                )
            }
            return decision(
                command,
                enabled: !node.reconciledState.isTerminal,
                denial: "node_already_terminal"
            )
        case .retryNode:
            guard let selectedNodeID,
                  let attempt = inspection?.attempts
                    .filter({ $0.nodeID == selectedNodeID })
                    .max(by: { $0.ordinal < $1.ordinal }) else {
                return decision(
                    command,
                    enabled: false,
                    denial: "retry_requires_attempt"
                )
            }
            let retryPolicy = inspection?.scheduling?.currentPolicy?.retryPolicy
                ?? document?.schedulerPolicy.retryPolicy
            let category = attempt.statusReason ?? "execution_failure"
            let categoryAllowed = retryPolicy.map {
                !$0.nonRetryableFailureCategories.contains(category)
                    && ($0.retryableFailureCategories.isEmpty
                        || $0.retryableFailureCategories.contains(category))
                    && attempt.ordinal < $0.maximumAttempts
            } ?? false
            return decision(
                command,
                enabled: [.failed, .interrupted, .orphaned]
                    .contains(attempt.reconciledState) && categoryAllowed,
                denial: "retry_policy_denied"
            )
        case .openLogs:
            return decision(
                command,
                enabled: inspection != nil && selectedNodeID != nil,
                denial: "node_not_selected"
            )
        case .inspectHistory, .export:
            return decision(
                command,
                enabled: inspection != nil,
                denial: "run_not_selected"
            )
        }
    }

    private static func decision(
        _ command: GraphWorkspaceCommand,
        enabled: Bool,
        denial: String
    ) -> GraphWorkspaceCommandDecision {
        GraphWorkspaceCommandDecision(
            command: command,
            isEnabled: enabled,
            reasonCode: enabled ? "allowed" : denial
        )
    }
}

@MainActor
@Observable
final class GraphWorkspaceViewModel {
    static let lastDocumentPathKey = "graph.workspace.lastDocumentPath"
    static let lastRunIDKey = "graph.workspace.lastRunID"
    static let lastModeKey = "graph.workspace.lastMode"

    var mode: GraphWorkspaceMode = .definition {
        didSet { defaults.set(mode.rawValue, forKey: Self.lastModeKey) }
    }
    var document: GraphDefinitionDocument?
    var documentURL: URL?
    var inspection: GraphRunInspection?
    var runs: [GraphRunInspectionSummary] = []
    var history: GraphInspectionEventPage?
    var explanation: GraphCausalExplanation?
    var selectedNodeIDs: Set<String> = []
    var logPage: GraphProcessLogPage?
    var selectedLogChannel: GraphProcessLogChannel = .stdout
    var isFollowingLogs = true
    var isShowingLogs = false
    var isLoading = false
    var isOrchestrating = false
    var lastCommandResult: GraphWorkspaceCommandResult?
    var errorMessage: String?

    @ObservationIgnored private let service: any GraphWorkspaceServicing
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var revisionTask: Task<Void, Never>?
    @ObservationIgnored private var orchestrationTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration: UInt64 = 0
    @ObservationIgnored private var hasStarted = false

    init(
        service: any GraphWorkspaceServicing,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.lastModeKey),
           let restored = GraphWorkspaceMode(rawValue: raw) {
            mode = restored
        }
    }

    deinit {
        revisionTask?.cancel()
        orchestrationTask?.cancel()
    }

    var selectedNodeID: String? { selectedNodeIDs.sorted().first }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        isLoading = true
        Task {
            await restore()
            let revisions = await service.revisions()
            revisionTask = Task { [weak self] in
                for await _ in revisions {
                    guard !Task.isCancelled else { break }
                    await self?.refreshRunAndHistory()
                }
            }
            isLoading = false
        }
    }

    func stop() {
        revisionTask?.cancel()
        revisionTask = nil
        pauseOrchestration()
    }

    func restoreState() async {
        await restore()
    }

    func decision(_ command: GraphWorkspaceCommand)
        -> GraphWorkspaceCommandDecision
    {
        GraphWorkspaceCommandPolicy.decision(
            command,
            document: document,
            inspection: inspection,
            selectedNodeID: selectedNodeID,
            isOrchestrating: isOrchestrating
        )
    }

    func newDocument() {
        pauseOrchestration()
        let newDocument = GraphDefinitionDocument.empty()
        document = newDocument
        documentURL = nil
        inspection = nil
        history = nil
        explanation = nil
        selectedNodeIDs = []
        mode = .definition
        defaults.removeObject(forKey: Self.lastDocumentPathKey)
        defaults.removeObject(forKey: Self.lastRunIDKey)
        acceptedLocalAction("new_definition")
    }

    func openDocument(url: URL) async {
        do {
            let loaded = try await service.loadDocument(url: url)
            document = loaded
            documentURL = url
            selectedNodeIDs = Set(loaded.nodes.first.map { [$0.id] } ?? [])
            mode = .definition
            defaults.set(url.path, forKey: Self.lastDocumentPathKey)
            acceptedLocalAction("definition_opened")
        } catch {
            rejectLocalAction("definition_open_failed", error)
        }
    }

    func saveDocument(url: URL? = nil) async {
        guard let document else {
            return rejectLocalAction(
                "definition_missing",
                GraphDefinitionDocumentError.missingGraphID
            )
        }
        guard let destination = url ?? documentURL else {
            return rejectLocalAction(
                "definition_destination_missing",
                CocoaError(.fileNoSuchFile)
            )
        }
        do {
            try await service.saveDocument(document, url: destination)
            documentURL = destination
            defaults.set(destination.path, forKey: Self.lastDocumentPathKey)
            acceptedLocalAction("definition_saved")
        } catch {
            rejectLocalAction("definition_save_failed", error)
        }
    }

    func validateDocument() {
        do {
            try document?.validate()
            acceptedLocalAction("definition_valid")
        } catch {
            rejectLocalAction("definition_invalid", error)
        }
    }

    func addNode() {
        guard var document else { return }
        let existing = Set(document.nodes.map(\.id))
        var ordinal = document.nodes.count + 1
        var nodeID = "node-\(ordinal)"
        while existing.contains(nodeID) {
            ordinal += 1
            nodeID = "node-\(ordinal)"
        }
        do {
            let specification = GraphLocalProcessSpecification(
                executable: "/usr/bin/true"
            )
            try GraphDefinitionDocumentEditor.addNode(
                GraphDefinitionDocumentNode(
                    id: nodeID,
                    name: "Node \(ordinal)",
                    requiredCapabilities: ["local-process"],
                    specification: try specification.immutableSpecification(),
                    workspace: GraphExecutionWorkspaceContext(
                        root: FileManager.default.currentDirectoryPath
                    ),
                    timeoutPolicy: GraphExecutionTimeoutPolicy(
                        executionSeconds: 300,
                        cancellationAcknowledgementSeconds: 10
                    )
                ),
                to: &document,
                position: GraphCanvasPoint(
                    x: Double(ordinal - 1) * 260,
                    y: 0
                ),
                modifiedAt: Date(),
                modifiedBy: NSUserName()
            )
            self.document = document
            selectedNodeIDs = [nodeID]
            acceptedLocalAction("node_added", nodeIDs: [nodeID])
        } catch {
            rejectLocalAction("node_add_rejected", error)
        }
    }

    func updateSelectedNode(name: String, description: String) {
        guard var document, let nodeID = selectedNodeID else { return }
        do {
            try GraphDefinitionDocumentEditor.renameNode(
                id: nodeID,
                name: name,
                description: description,
                in: &document,
                modifiedAt: Date(),
                modifiedBy: NSUserName()
            )
            self.document = document
        } catch {
            rejectLocalAction("node_edit_rejected", error)
        }
    }

    func updateSelectedNodeExecution(
        capabilities: [String],
        executionSeconds: UInt64
    ) {
        guard var document,
              let nodeID = selectedNodeID,
              let index = document.nodes.firstIndex(where: {
                  $0.id == nodeID
              }) else { return }
        document.nodes[index].requiredCapabilities = capabilities.sorted()
        document.nodes[index].timeoutPolicy = GraphExecutionTimeoutPolicy(
            executionSeconds: executionSeconds,
            cancellationAcknowledgementSeconds: document.nodes[index]
                .timeoutPolicy.cancellationAcknowledgementSeconds
        )
        document.metadata.modifiedAt = Date()
        document.metadata.modifiedBy = NSUserName()
        do {
            try document.validate()
            self.document = document
        } catch {
            rejectLocalAction("node_execution_edit_rejected", error)
        }
    }

    func deleteSelection() {
        guard var document, !selectedNodeIDs.isEmpty else { return }
        do {
            for nodeID in selectedNodeIDs.sorted() {
                try GraphDefinitionDocumentEditor.removeNode(
                    id: nodeID,
                    from: &document,
                    modifiedAt: Date(),
                    modifiedBy: NSUserName()
                )
            }
            let removed = selectedNodeIDs.sorted()
            selectedNodeIDs = []
            self.document = document
            acceptedLocalAction("selection_deleted", nodeIDs: removed)
        } catch {
            rejectLocalAction("selection_delete_rejected", error)
        }
    }

    func connectSelectedNodes() {
        guard var document, selectedNodeIDs.count == 2 else { return }
        let ordered = selectedNodeIDs.sorted()
        do {
            try GraphDefinitionDocumentEditor.addEdge(
                GraphDefinitionEdge(
                    sourceNodeID: ordered[0],
                    targetNodeID: ordered[1]
                ),
                to: &document,
                modifiedAt: Date(),
                modifiedBy: NSUserName()
            )
            self.document = document
            acceptedLocalAction("dependency_added", nodeIDs: ordered)
        } catch {
            rejectLocalAction("dependency_add_rejected", error)
        }
    }

    func removeEdge(_ edgeID: String) {
        guard var document else { return }
        do {
            try GraphDefinitionDocumentEditor.removeEdge(
                id: edgeID,
                from: &document,
                modifiedAt: Date(),
                modifiedBy: NSUserName()
            )
            self.document = document
            acceptedLocalAction("dependency_removed")
        } catch {
            rejectLocalAction("dependency_remove_rejected", error)
        }
    }

    func moveNode(_ nodeID: String, to position: GraphCanvasPoint) {
        guard var document else { return }
        do {
            try GraphDefinitionDocumentEditor.setPosition(
                nodeID: nodeID,
                position: position,
                in: &document,
                modifiedAt: Date(),
                modifiedBy: NSUserName()
            )
            self.document = document
        } catch {
            rejectLocalAction("layout_update_rejected", error)
        }
    }

    func automaticLayout() {
        guard var document else { return }
        do {
            try GraphDefinitionDocumentEditor.applyAutomaticLayout(
                to: &document,
                modifiedAt: Date(),
                modifiedBy: NSUserName()
            )
            self.document = document
            acceptedLocalAction("automatic_layout_applied")
        } catch {
            rejectLocalAction("automatic_layout_rejected", error)
        }
    }

    func selectNode(_ nodeID: String, extending: Bool = false) {
        if extending {
            if selectedNodeIDs.contains(nodeID) {
                selectedNodeIDs.remove(nodeID)
            } else {
                selectedNodeIDs.insert(nodeID)
            }
        } else {
            selectedNodeIDs = [nodeID]
        }
        if mode == .history { Task { await refreshExplanation() } }
    }

    func createRun() async {
        let policy = decision(.createRun)
        guard policy.isEnabled, let document else {
            return rejectedPolicy(policy)
        }
        let runID = "\(document.graphID)-\(UUID().uuidString.lowercased())"
        let result = await service.createRun(
            document: document,
            runID: runID,
            occurredAt: Date()
        )
        apply(result)
        if result.accepted {
            defaults.set(runID, forKey: Self.lastRunIDKey)
            mode = .run
            await refreshRunAndHistory()
        }
    }

    func startRun() async {
        let policy = decision(.start)
        guard policy.isEnabled, let runID = inspection?.summary.runID else {
            return rejectedPolicy(policy)
        }
        apply(await service.startRun(runID: runID, occurredAt: Date()))
        await refreshRunAndHistory()
    }

    func step() async {
        let policy = decision(.step)
        guard policy.isEnabled, let runID = inspection?.summary.runID else {
            return rejectedPolicy(policy)
        }
        apply(await service.step(runID: runID, occurredAt: Date()))
        await refreshRunAndHistory()
    }

    func run() {
        let policy = decision(.run)
        guard policy.isEnabled, let runID = inspection?.summary.runID else {
            return rejectedPolicy(policy)
        }
        isOrchestrating = true
        orchestrationTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<1_000 {
                guard !Task.isCancelled else { break }
                let result = await service.step(
                    runID: runID,
                    occurredAt: Date()
                )
                apply(result)
                await refreshRunAndHistory()
                if isShowingLogs, isFollowingLogs {
                    await refreshLogs()
                }
                if inspection?.summary.persistedState.isTerminal == true
                    || !result.accepted {
                    break
                }
                if inspection?.nodes.contains(where: {
                    $0.reconciledState == .running
                }) == true {
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            isOrchestrating = false
            orchestrationTask = nil
        }
    }

    func pauseOrchestration() {
        orchestrationTask?.cancel()
        orchestrationTask = nil
        isOrchestrating = false
        acceptedLocalAction("local_orchestration_paused")
    }

    func waitForLocalOrchestration() async {
        await orchestrationTask?.value
    }

    func cancelRun() async {
        let policy = decision(.cancelRun)
        guard policy.isEnabled, let runID = inspection?.summary.runID else {
            return rejectedPolicy(policy)
        }
        apply(await service.cancel(
            runID: runID,
            nodeID: nil,
            occurredAt: Date()
        ))
        await refreshRunAndHistory()
    }

    func cancelSelectedNode() async {
        let policy = decision(.cancelNode)
        guard policy.isEnabled,
              let runID = inspection?.summary.runID,
              let nodeID = selectedNodeID else {
            return rejectedPolicy(policy)
        }
        apply(await service.cancel(
            runID: runID,
            nodeID: nodeID,
            occurredAt: Date()
        ))
        await refreshRunAndHistory()
    }

    func retrySelectedNode() async {
        let policy = decision(.retryNode)
        guard policy.isEnabled,
              let runID = inspection?.summary.runID,
              let nodeID = selectedNodeID else {
            return rejectedPolicy(policy)
        }
        apply(await service.retry(
            runID: runID,
            nodeID: nodeID,
            occurredAt: Date()
        ))
        await refreshRunAndHistory()
    }

    func openLogs() async {
        let policy = decision(.openLogs)
        guard policy.isEnabled else { return rejectedPolicy(policy) }
        isShowingLogs = true
        await refreshLogs()
    }

    func refreshLogs() async {
        guard let runID = inspection?.summary.runID,
              let nodeID = selectedNodeID else { return }
        do {
            logPage = try await service.logs(runID: runID, nodeID: nodeID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func inspectHistory() async {
        let policy = decision(.inspectHistory)
        guard policy.isEnabled else { return rejectedPolicy(policy) }
        mode = .history
        await refreshRunAndHistory()
    }

    func exportRun(url: URL) async {
        let policy = decision(.export)
        guard policy.isEnabled, let runID = inspection?.summary.runID else {
            return rejectedPolicy(policy)
        }
        do {
            try await service.exportRun(runID: runID, url: url)
            acceptedLocalAction("run_exported")
        } catch {
            rejectLocalAction("run_export_failed", error)
        }
    }

    func openRun(_ runID: String) async {
        defaults.set(runID, forKey: Self.lastRunIDKey)
        mode = .run
        await refreshRunAndHistory()
    }

    func refreshRunAndHistory() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        do {
            let listed = try await service.listRuns()
            guard generation == refreshGeneration else { return }
            runs = listed
            guard let runID = defaults.string(forKey: Self.lastRunIDKey),
                  listed.contains(where: { $0.runID == runID }) else {
                inspection = nil
                history = nil
                explanation = nil
                return
            }
            async let inspected = service.inspect(runID: runID)
            async let events = service.history(runID: runID)
            let (newInspection, newHistory) = try await (inspected, events)
            guard generation == refreshGeneration else { return }
            inspection = newInspection
            history = newHistory
            await refreshExplanation()
        } catch {
            guard generation == refreshGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func refreshExplanation() async {
        guard let runID = inspection?.summary.runID else { return }
        do {
            explanation = try await service.explain(
                runID: runID,
                nodeID: selectedNodeID
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        let restoredMode = mode
        if let path = defaults.string(forKey: Self.lastDocumentPathKey),
           FileManager.default.fileExists(atPath: path) {
            await openDocument(url: URL(fileURLWithPath: path))
        } else {
            document = GraphDefinitionDocument.empty()
        }
        await refreshRunAndHistory()
        if inspection != nil {
            mode = restoredMode
        }
    }

    private func apply(_ result: GraphWorkspaceCommandResult) {
        lastCommandResult = result
        errorMessage = result.accepted
            ? nil : result.diagnostics.joined(separator: "\n")
    }

    private func acceptedLocalAction(
        _ reasonCode: String,
        nodeIDs: [String] = []
    ) {
        apply(
            GraphWorkspaceCommandResult(
                accepted: true,
                reasonCode: reasonCode,
                streamVersion: inspection?.summary.streamVersion,
                runID: inspection?.summary.runID,
                nodeIDs: nodeIDs,
                diagnostics: [],
                suggestedRefresh: .none
            )
        )
    }

    private func rejectLocalAction(_ reasonCode: String, _ error: Error) {
        apply(.rejected(reasonCode, diagnostic: error.localizedDescription))
    }

    private func rejectedPolicy(_ decision: GraphWorkspaceCommandDecision) {
        apply(
            .rejected(
                decision.reasonCode,
                runID: inspection?.summary.runID,
                nodeIDs: [selectedNodeID].compactMap { $0 },
                diagnostic: "Command rejected: \(decision.reasonCode)"
            )
        )
    }
}
