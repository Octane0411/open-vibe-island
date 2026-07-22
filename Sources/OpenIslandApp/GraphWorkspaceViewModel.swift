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
            let retryPolicy = inspection?.scheduling?.currentPolicy?
                .retryPolicy(for: selectedNodeID)
                ?? document?.schedulerPolicy.retryPolicy(for: selectedNodeID)
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
    static let recentDocumentPathsKey = "graph.workspace.recentDocumentPaths"

    var mode: GraphWorkspaceMode = .definition {
        didSet { defaults.set(mode.rawValue, forKey: Self.lastModeKey) }
    }
    var document: GraphDefinitionDocument?
    var documentURL: URL?
    var documentFileState: GraphDocumentFileState?
    var lastSavedDocument: GraphDefinitionDocument?
    var recentDocumentURLs: [URL] = []
    var closeState: GraphDocumentCloseState = .idle
    var hasExternalModification = false
    var associatedRunCount = 0
    var isDraft = false
    var defaultNodeWorkspaceDirectory: String?
    var defaultNodeTimeoutSeconds: UInt64 = 300
    var defaultNodeExecutorKind = GraphLocalProcessSpecification.adapterKind
    var inspection: GraphRunInspection?
    var runs: [GraphRunInspectionSummary] = []
    var history: GraphInspectionEventPage?
    var explanation: GraphCausalExplanation?
    var selectedNodeIDs: Set<String> = []
    var selectedEdgeID: String?
    var dependencySourceNodeID: String?
    var connectionGuidance: String?
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
    @ObservationIgnored private var undoSnapshots: [GraphAuthoringUndoSnapshot] = []
    @ObservationIgnored private var redoSnapshots: [GraphAuthoringUndoSnapshot] = []
    @ObservationIgnored private var undoCoalescingKey: String?

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
        recentDocumentURLs = defaults.stringArray(
            forKey: Self.recentDocumentPathsKey
        )?.map(URL.init(fileURLWithPath:)) ?? []
    }

    deinit {
        revisionTask?.cancel()
        orchestrationTask?.cancel()
    }

    var selectedNodeID: String? { selectedNodeIDs.sorted().first }
    var selectedEdge: GraphDefinitionEdge? {
        guard let selectedEdgeID else { return nil }
        return document?.edges.first { $0.id == selectedEdgeID }
    }
    var isDirty: Bool {
        guard let document else { return false }
        return document != lastSavedDocument
    }
    var canUndo: Bool { !undoSnapshots.isEmpty }
    var canRedo: Bool { !redoSnapshots.isEmpty }

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

    func newDocument(
        request: GraphNewDocumentRequest = .defaults()
    ) {
        pauseOrchestration()
        var newDocument = GraphDefinitionDocument.empty(graphID: request.graphID)
        newDocument.name = request.name
        newDocument.definitionVersion = request.definitionVersion
        newDocument.description = request.description
        newDocument.schedulerPolicy = GraphSchedulerPolicy(
            policyID: "\(request.graphID)-policy",
            version: request.definitionVersion,
            retryPolicy: GraphRetryPolicy(
                maximumAttempts: request.defaultRetryMaximumAttempts,
                retryableFailureCategories: [
                    "execution_failure",
                    "process_exit_unobserved",
                    "timeout",
                ],
                nonRetryableFailureCategories: [
                    "artifact_collection_failure",
                    "invalid_process_specification",
                ]
            ),
            attemptExecutionTimeoutSeconds: request.defaultExecutionTimeoutSeconds,
            cancellationAcknowledgementTimeoutSeconds: 10
        )
        defaultNodeWorkspaceDirectory = request.workspaceDirectory
        defaultNodeTimeoutSeconds = request.defaultExecutionTimeoutSeconds
        defaultNodeExecutorKind = request.defaultExecutorKind
        document = newDocument
        documentURL = nil
        documentFileState = nil
        lastSavedDocument = nil
        hasExternalModification = false
        associatedRunCount = 0
        isDraft = false
        inspection = nil
        history = nil
        explanation = nil
        selectedNodeIDs = []
        selectedEdgeID = nil
        resetUndoHistory()
        mode = .definition
        defaults.removeObject(forKey: Self.lastDocumentPathKey)
        defaults.removeObject(forKey: Self.lastRunIDKey)
        acceptedLocalAction("new_definition")
    }

    func openDocument(url: URL) async {
        do {
            let loaded = try await service.loadDocument(url: url)
            let fileState = try await service.documentFileState(url: url)
            document = loaded
            documentURL = url
            documentFileState = fileState
            lastSavedDocument = loaded
            hasExternalModification = false
            associatedRunCount = try await service.associatedRunCount(
                graphID: loaded.graphID,
                definitionVersion: loaded.definitionVersion
            )
            isDraft = false
            selectedNodeIDs = Set(loaded.nodes.first.map { [$0.id] } ?? [])
            selectedEdgeID = nil
            resetUndoHistory()
            mode = .definition
            defaults.set(url.path, forKey: Self.lastDocumentPathKey)
            recordRecentDocument(url)
            acceptedLocalAction("definition_opened")
        } catch {
            rejectLocalAction("definition_open_failed", error)
        }
    }

    func openBundledCompendium() {
        do {
            let loaded = try GraphWorkspaceBundledFixtures.loadCompendium()
            document = loaded
            documentURL = nil
            documentFileState = nil
            lastSavedDocument = nil
            associatedRunCount = 0
            isDraft = false
            selectedNodeIDs = Set(loaded.nodes.first.map { [$0.id] } ?? [])
            selectedEdgeID = nil
            resetUndoHistory()
            mode = .definition
            acceptedLocalAction("compendium_definition_opened")
        } catch {
            rejectLocalAction("compendium_definition_open_failed", error)
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
            let expectedDigest = destination == documentURL
                ? documentFileState?.contentDigest : nil
            let savedState = try await service.saveDocument(
                document,
                url: destination,
                expectedContentDigest: expectedDigest
            )
            documentURL = destination
            documentFileState = savedState
            lastSavedDocument = document
            hasExternalModification = false
            defaults.set(destination.path, forKey: Self.lastDocumentPathKey)
            recordRecentDocument(destination)
            acceptedLocalAction("definition_saved")
        } catch {
            rejectLocalAction("definition_save_failed", error)
        }
    }

    func saveAsDocument(url: URL) async {
        await saveDocument(url: url)
    }

    func refreshExternalModificationState() async {
        guard let documentURL, let documentFileState else {
            hasExternalModification = false
            return
        }
        do {
            hasExternalModification = try await service.documentFileState(
                url: documentURL
            ).contentDigest != documentFileState.contentDigest
        } catch {
            hasExternalModification = true
        }
    }

    func revertDocument() async {
        guard let documentURL else { return }
        await openDocument(url: documentURL)
        if errorMessage == nil {
            acceptedLocalAction("definition_reverted")
        }
    }

    func requestCloseDocument() {
        if isDirty {
            closeState = .confirmationRequired
        } else {
            closeDocumentDiscardingChanges()
        }
    }

    func resolveCloseDocument(
        _ choice: GraphUnsavedCloseChoice,
        saveURL: URL? = nil
    ) async {
        switch choice {
        case .save:
            await saveDocument(url: saveURL)
            if !isDirty { closeDocumentDiscardingChanges() }
        case .discard:
            closeDocumentDiscardingChanges()
        case .cancel:
            closeState = .idle
        }
    }

    func createNewDefinitionVersion() {
        guard var document else { return }
        registerUndo(coalescingKey: nil)
        document.definitionVersion = GraphDefinitionVersioning.nextVersion(
            after: document.definitionVersion
        )
        document.metadata.modifiedAt = Date()
        document.metadata.modifiedBy = NSUserName()
        self.document = document
        associatedRunCount = 0
        isDraft = false
        acceptedLocalAction("definition_version_created")
    }

    func undo() {
        guard let snapshot = undoSnapshots.popLast(),
              let current = authoringSnapshot else { return }
        redoSnapshots.append(current)
        restore(snapshot)
        undoCoalescingKey = nil
        acceptedLocalAction("authoring_undo")
    }

    func redo() {
        guard let snapshot = redoSnapshots.popLast(),
              let current = authoringSnapshot else { return }
        undoSnapshots.append(current)
        restore(snapshot)
        undoCoalescingKey = nil
        acceptedLocalAction("authoring_redo")
    }

    func validateDocument() {
        do {
            try document?.validate()
            acceptedLocalAction("definition_valid")
        } catch {
            rejectLocalAction("definition_invalid", error)
        }
    }

    func updateGraphIdentity(name: String, description: String) {
        guard var document else { return }
        registerUndo(coalescingKey: "graph-identity")
        document.name = name
        document.description = description
        document.metadata.modifiedAt = Date()
        document.metadata.modifiedBy = NSUserName()
        self.document = document
        markSemanticMutation()
    }

    func addNode(type: GraphDefinitionNodeType = .localProcess) {
        guard var document else { return }
        registerUndo(coalescingKey: nil)
        let existing = Set(document.nodes.map(\.id))
        var ordinal = document.nodes.count + 1
        var nodeID = "node-\(ordinal)"
        while existing.contains(nodeID) {
            ordinal += 1
            nodeID = "node-\(ordinal)"
        }
        do {
            let definition = try defaultNodeDefinition(
                id: nodeID,
                ordinal: ordinal,
                type: type
            )
            try GraphDefinitionDocumentEditor.addNode(
                definition,
                to: &document,
                position: GraphCanvasPoint(
                    x: Double(ordinal - 1) * 260,
                    y: 0
                ),
                modifiedAt: Date(),
                modifiedBy: NSUserName()
            )
            self.document = document
            markSemanticMutation()
            selectedNodeIDs = [nodeID]
            selectedEdgeID = nil
            acceptedLocalAction("node_added", nodeIDs: [nodeID])
        } catch {
            rejectLocalAction("node_add_rejected", error)
        }
    }

    func updateSelectedNode(name: String, description: String) {
        guard var document, let nodeID = selectedNodeID else { return }
        registerUndo(coalescingKey: "identity:\(nodeID)")
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
            markSemanticMutation()
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
        registerUndo(coalescingKey: "execution:\(nodeID)")
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
            markSemanticMutation()
        } catch {
            rejectLocalAction("node_execution_edit_rejected", error)
        }
    }

    func updateSelectedNodeIdentity(
        name: String,
        description: String,
        tags: [String]
    ) {
        mutateSelectedNode(coalescingKey: "identity") { node, _ in
            node.name = name
            node.description = description
            node.tags = tags.sorted()
        }
    }

    func updateSelectedNodeType(_ type: GraphDefinitionNodeType) {
        guard let nodeID = selectedNodeID,
              let ordinal = document?.nodes.firstIndex(where: { $0.id == nodeID })
        else { return }
        do {
            let replacement = try defaultNodeDefinition(
                id: nodeID,
                ordinal: ordinal + 1,
                type: type
            )
            mutateSelectedNode(coalescingKey: nil) { node, _ in
                let identity = (node.name, node.description, node.tags)
                node = replacement
                node.name = identity.0
                node.description = identity.1
                node.tags = identity.2
            }
        } catch {
            rejectLocalAction("node_type_edit_rejected", error)
        }
    }

    func updateSelectedNodeCapabilities(
        required: [String],
        preferred: [String],
        executorKind: GraphDefinitionExecutorKind,
        platformConstraints: [String]
    ) {
        mutateSelectedNode(coalescingKey: "capabilities") { node, _ in
            node.requiredCapabilities = required.sorted()
            node.preferredCapabilities = preferred.sorted()
            node.executorKind = executorKind
            node.platformConstraints = platformConstraints.sorted()
        }
    }

    func updateSelectedLocalProcess(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        inheritedEnvironment: GraphLocalProcessEnvironmentInheritance,
        stdin: GraphLocalProcessStdinPolicy,
        environmentAllowlist: [String],
        workspaceRoot: String?
    ) {
        mutateSelectedNode(coalescingKey: "local-process") { node, _ in
            guard node.nodeType == .localProcess else { return }
            let existing = (try? GraphLocalProcessSpecification(
                immutableSpecification: node.specification
            )) ?? GraphLocalProcessSpecification(executable: "/usr/bin/true")
            let process = GraphLocalProcessSpecification(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: existing.environment,
                inheritedEnvironment: inheritedEnvironment,
                stdin: stdin,
                outputArtifacts: node.outputs.map(Self.processDeclaration),
                retryableExitCodes: existing.retryableExitCodes,
                logPolicy: existing.logPolicy
            )
            if let specification = try? process.immutableSpecification() {
                node.specification = specification
            }
            node.environmentAllowlist = environmentAllowlist.sorted()
            node.workspace = GraphExecutionWorkspaceContext(
                root: workspaceRoot,
                writableRelativePaths: node.outputs.compactMap {
                    let path = URL(fileURLWithPath: $0.relativePath)
                        .deletingLastPathComponent().path
                    return path == "." ? "" : path
                }.filter { !$0.isEmpty }
            )
        }
    }

    func addSelectedNodeArgument() {
        guard let process = selectedLocalProcessSpecification else { return }
        updateSelectedLocalProcess(
            executable: process.executable,
            arguments: process.arguments + [""],
            workingDirectory: process.workingDirectory,
            inheritedEnvironment: process.inheritedEnvironment,
            stdin: process.stdin,
            environmentAllowlist: selectedNode?.environmentAllowlist ?? [],
            workspaceRoot: selectedNode?.workspace.root
        )
    }

    func updateSelectedNodeArgument(at index: Int, value: String) {
        guard let process = selectedLocalProcessSpecification,
              process.arguments.indices.contains(index) else { return }
        var arguments = process.arguments
        arguments[index] = value
        replaceSelectedProcessArguments(arguments, process: process)
    }

    func removeSelectedNodeArgument(at index: Int) {
        guard let process = selectedLocalProcessSpecification,
              process.arguments.indices.contains(index) else { return }
        var arguments = process.arguments
        arguments.remove(at: index)
        replaceSelectedProcessArguments(arguments, process: process)
    }

    func moveSelectedNodeArgument(from index: Int, offset: Int) {
        guard let process = selectedLocalProcessSpecification else { return }
        let destination = index + offset
        guard process.arguments.indices.contains(index),
              process.arguments.indices.contains(destination) else { return }
        var arguments = process.arguments
        arguments.swapAt(index, destination)
        replaceSelectedProcessArguments(arguments, process: process)
    }

    func addSelectedNodeInput() {
        mutateSelectedNode(coalescingKey: nil) { node, _ in
            let id = Self.nextStableID(prefix: "input", existing: node.inputs.map(\.id))
            node.inputs.append(
                GraphNodeInputDefinition(id: id, name: "Input \(node.inputs.count + 1)")
            )
            node.inputs.sort { $0.id < $1.id }
        }
    }

    func updateSelectedNodeInput(_ input: GraphNodeInputDefinition) {
        mutateSelectedNode(coalescingKey: "input:\(input.id)") { node, _ in
            guard let index = node.inputs.firstIndex(where: { $0.id == input.id }) else {
                return
            }
            node.inputs[index] = input
        }
    }

    func removeSelectedNodeInput(_ inputID: String) {
        mutateSelectedNode(coalescingKey: nil) { node, _ in
            node.inputs.removeAll { $0.id == inputID }
        }
    }

    func addSelectedNodeOutput() {
        mutateSelectedNode(coalescingKey: nil) { node, _ in
            let used = Set(node.outputs.map(\.role))
            let role = GraphArtifactRole.allCases.first { !used.contains($0) }
                ?? .nodeOutput
            let id = Self.nextStableID(prefix: "output", existing: node.outputs.map(\.id))
            node.outputs.append(
                GraphNodeOutputDefinition(
                    id: id,
                    name: "Output \(node.outputs.count + 1)",
                    role: role,
                    relativePath: "artifacts/\(node.id)-\(id).json",
                    mediaType: "application/json"
                )
            )
            node.outputs.sort { $0.id < $1.id }
            Self.synchronizeProcessOutputs(&node)
        }
    }

    func updateSelectedNodeOutput(_ output: GraphNodeOutputDefinition) {
        mutateSelectedNode(coalescingKey: "output:\(output.id)") { node, _ in
            guard let index = node.outputs.firstIndex(where: { $0.id == output.id }) else {
                return
            }
            node.outputs[index] = output
            Self.synchronizeProcessOutputs(&node)
        }
    }

    func removeSelectedNodeOutput(_ outputID: String) {
        mutateSelectedNode(coalescingKey: nil) { node, _ in
            node.outputs.removeAll { $0.id == outputID }
            Self.synchronizeProcessOutputs(&node)
        }
    }

    func updateSelectedNodeRetry(_ configuration: GraphNodeRetryConfiguration) {
        mutateSelectedNode(coalescingKey: "retry") { node, _ in
            node.retryConfiguration = configuration
        }
    }

    func updateSelectedNodeTimeout(
        _ configuration: GraphNodeTimeoutConfiguration
    ) {
        mutateSelectedNode(coalescingKey: "timeout") { node, document in
            node.timeoutConfiguration = configuration
            let execution = configuration.inheritsGraphDefault
                ? document.schedulerPolicy.attemptExecutionTimeoutSeconds
                : max(1, configuration.executionSeconds)
            let cancellation = configuration.inheritsGraphDefault
                ? document.schedulerPolicy.cancellationAcknowledgementTimeoutSeconds
                : max(1, configuration.cancellationAcknowledgementSeconds)
            node.timeoutPolicy = GraphExecutionTimeoutPolicy(
                executionSeconds: execution,
                cancellationAcknowledgementSeconds: cancellation
            )
        }
    }

    var selectedNode: GraphDefinitionDocumentNode? {
        guard let selectedNodeID else { return nil }
        return document?.nodes.first { $0.id == selectedNodeID }
    }

    var selectedLocalProcessSpecification: GraphLocalProcessSpecification? {
        guard let node = selectedNode,
              node.nodeType == .localProcess else { return nil }
        return try? GraphLocalProcessSpecification(
            immutableSpecification: node.specification
        )
    }

    func deleteSelection() {
        if let selectedEdgeID {
            removeEdge(selectedEdgeID)
            return
        }
        guard var document, !selectedNodeIDs.isEmpty else { return }
        registerUndo(coalescingKey: nil)
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
            selectedEdgeID = nil
            self.document = document
            markSemanticMutation()
            acceptedLocalAction("selection_deleted", nodeIDs: removed)
        } catch {
            rejectLocalAction("selection_delete_rejected", error)
        }
    }

    func connectSelectedNodes() {
        guard selectedNodeIDs.count == 2 else { return }
        let ordered = selectedNodeIDs.sorted()
        _ = connectNodes(sourceNodeID: ordered[0], targetNodeID: ordered[1])
    }

    @discardableResult
    func connectNodes(
        sourceNodeID: String,
        targetNodeID: String,
        portType: GraphDefinitionPortType = .dependency,
        sourceOutputID: String? = nil,
        targetInputID: String? = nil,
        isRequired: Bool = true
    ) -> GraphConnectionDecision {
        guard var document else {
            return .rejected(.sourceMissing, "No graph document is open.")
        }
        let resolvedSourceOutputID = sourceOutputID ?? (portType == .dependency
            ? nil : document.nodes.first { $0.id == sourceNodeID }?
                .outputs.first { $0.portType == portType }?.id)
        let resolvedTargetInputID = targetInputID ?? (portType == .dependency
            ? nil : document.nodes.first { $0.id == targetNodeID }?
                .inputs.first { $0.portType == portType }?.id)
        let decision = GraphConnectionEvaluator.evaluate(
            document: document,
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            portType: portType,
            sourceOutputID: resolvedSourceOutputID,
            targetInputID: resolvedTargetInputID
        )
        guard decision.isAllowed else {
            connectionGuidance = decision.message
            apply(.rejected(
                decision.rejection?.rawValue ?? "connection_rejected",
                nodeIDs: [sourceNodeID, targetNodeID],
                diagnostic: decision.message
            ))
            return decision
        }
        registerUndo(coalescingKey: nil)
        do {
            let edge = GraphDefinitionEdge(
                sourceNodeID: sourceNodeID,
                targetNodeID: targetNodeID,
                portType: portType,
                sourceOutputID: resolvedSourceOutputID,
                targetInputID: resolvedTargetInputID,
                isRequired: isRequired
            )
            try GraphDefinitionDocumentEditor.addEdge(
                edge,
                to: &document,
                modifiedAt: Date(),
                modifiedBy: NSUserName()
            )
            synchronizeArtifactBindings(in: &document)
            self.document = document
            selectedNodeIDs = []
            selectedEdgeID = edge.id
            dependencySourceNodeID = nil
            connectionGuidance = "Connected \(sourceNodeID) to \(targetNodeID)."
            markSemanticMutation()
            acceptedLocalAction(
                portType == .dependency ? "dependency_added" : "typed_connection_added",
                nodeIDs: [sourceNodeID, targetNodeID]
            )
            return .allowed
        } catch {
            rejectLocalAction("dependency_add_rejected", error)
            return .rejected(.cycle, error.localizedDescription)
        }
    }

    func removeEdge(_ edgeID: String) {
        guard var document else { return }
        registerUndo(coalescingKey: nil)
        do {
            try GraphDefinitionDocumentEditor.removeEdge(
                id: edgeID,
                from: &document,
                modifiedAt: Date(),
                modifiedBy: NSUserName()
            )
            synchronizeArtifactBindings(in: &document)
            self.document = document
            selectedEdgeID = nil
            markSemanticMutation()
            acceptedLocalAction("dependency_removed")
        } catch {
            rejectLocalAction("dependency_remove_rejected", error)
        }
    }

    func updateSelectedEdge(_ updated: GraphDefinitionEdge) {
        guard var document,
              let selectedEdgeID,
              let index = document.edges.firstIndex(where: { $0.id == selectedEdgeID })
        else { return }
        var candidate = document
        candidate.edges.remove(at: index)
        let decision = GraphConnectionEvaluator.evaluate(
            document: candidate,
            sourceNodeID: updated.sourceNodeID,
            targetNodeID: updated.targetNodeID,
            portType: updated.portType,
            sourceOutputID: updated.sourceOutputID,
            targetInputID: updated.targetInputID
        )
        guard decision.isAllowed else {
            connectionGuidance = decision.message
            return
        }
        registerUndo(coalescingKey: "edge:\(selectedEdgeID)")
        document.edges[index] = updated
        document.edges.sort { $0.id < $1.id }
        synchronizeArtifactBindings(in: &document)
        document.metadata.modifiedAt = Date()
        document.metadata.modifiedBy = NSUserName()
        self.document = document
        markSemanticMutation()
    }

    func beginDependencyCreation(from nodeID: String) {
        dependencySourceNodeID = nodeID
        connectionGuidance = "Choose a downstream target for \(nodeID)."
    }

    func completeDependencyCreation(to nodeID: String) {
        guard let source = dependencySourceNodeID else {
            beginDependencyCreation(from: nodeID)
            return
        }
        _ = connectNodes(sourceNodeID: source, targetNodeID: nodeID)
    }

    func cancelDependencyCreation() {
        dependencySourceNodeID = nil
        connectionGuidance = nil
    }

    func canConnect(
        sourceNodeID: String,
        targetNodeID: String,
        portType: GraphDefinitionPortType = .dependency
    ) -> GraphConnectionDecision {
        guard let document else {
            return .rejected(.sourceMissing, "No graph document is open.")
        }
        let sourceOutputID = portType == .dependency ? nil : document.nodes
            .first { $0.id == sourceNodeID }?.outputs
            .first { $0.portType == portType }?.id
        let targetInputID = portType == .dependency ? nil : document.nodes
            .first { $0.id == targetNodeID }?.inputs
            .first { $0.portType == portType }?.id
        return GraphConnectionEvaluator.evaluate(
            document: document,
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            portType: portType,
            sourceOutputID: sourceOutputID,
            targetInputID: targetInputID
        )
    }

    func moveNode(_ nodeID: String, to position: GraphCanvasPoint) {
        guard var document else { return }
        registerUndo(coalescingKey: "move:\(nodeID)")
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
        registerUndo(coalescingKey: nil)
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
        undoCoalescingKey = nil
        selectedEdgeID = nil
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

    func selectEdge(_ edgeID: String) {
        selectedNodeIDs = []
        selectedEdgeID = edgeID
        undoCoalescingKey = nil
    }

    func selectCanvas() {
        selectedNodeIDs = []
        selectedEdgeID = nil
        undoCoalescingKey = nil
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
            associatedRunCount += 1
            isDraft = false
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
                    $0.persistedState == .running
                }) == true,
                   let nodeID = inspection?.nodes.first(where: {
                       $0.persistedState == .running
                   })?.id {
                    await service.waitForProcessChange(
                        runID: runID,
                        nodeID: nodeID
                    )
                } else {
                    await service.waitForRetryEligibility(runID: runID)
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
            document = nil
            lastSavedDocument = nil
            documentFileState = nil
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

    private func defaultNodeDefinition(
        id: String,
        ordinal: Int,
        type: GraphDefinitionNodeType
    ) throws -> GraphDefinitionDocumentNode {
        let specification: GraphImmutableExecutionSpecification
        let executorKind: GraphDefinitionExecutorKind
        let capabilities: [String]
        let outputs: [GraphNodeOutputDefinition]
        switch type {
        case .localProcess:
            specification = try GraphLocalProcessSpecification(
                executable: "/usr/bin/true"
            ).immutableSpecification()
            executorKind = .supervisedLocalProcess
            capabilities = ["local-process"]
            outputs = []
        case .deterministicTest:
            specification = GraphImmutableExecutionSpecification(
                adapterKind: "deterministic",
                operation: "test",
                parameters: ["artifactRole": .string(GraphArtifactRole.nodeOutput.rawValue)]
            )
            executorKind = .deterministicTest
            capabilities = ["deterministic"]
            outputs = [
                GraphNodeOutputDefinition(
                    id: "output-node",
                    name: "Node Output",
                    role: .nodeOutput,
                    relativePath: "artifacts/\(id).json",
                    mediaType: "application/json"
                ),
            ]
        case .genericAgent:
            specification = GraphImmutableExecutionSpecification(
                adapterKind: "generic_agent",
                operation: "unbound"
            )
            executorKind = .unboundAgent
            capabilities = ["agent"]
            outputs = []
        case .input, .output, .annotation:
            specification = GraphImmutableExecutionSpecification(
                adapterKind: "reference",
                operation: type.rawValue
            )
            executorKind = .none
            capabilities = []
            outputs = []
        }
        return GraphDefinitionDocumentNode(
            id: id,
            name: "\(typeDisplayName(type)) \(ordinal)",
            nodeType: type,
            requiredCapabilities: capabilities,
            executorKind: executorKind,
            specification: specification,
            workspace: GraphExecutionWorkspaceContext(
                root: defaultNodeWorkspaceDirectory
                    ?? FileManager.default.currentDirectoryPath
            ),
            outputs: outputs,
            timeoutPolicy: GraphExecutionTimeoutPolicy(
                executionSeconds: defaultNodeTimeoutSeconds,
                cancellationAcknowledgementSeconds: 10
            ),
            timeoutConfiguration: GraphNodeTimeoutConfiguration(
                executionSeconds: defaultNodeTimeoutSeconds,
                cancellationAcknowledgementSeconds: 10
            )
        )
    }

    private func typeDisplayName(_ type: GraphDefinitionNodeType) -> String {
        switch type {
        case .localProcess: "Local Process"
        case .deterministicTest: "Deterministic Test"
        case .genericAgent: "Generic Agent"
        case .input: "Input"
        case .output: "Output"
        case .annotation: "Annotation"
        }
    }

    private func mutateSelectedNode(
        coalescingKey: String?,
        _ mutation: (inout GraphDefinitionDocumentNode, GraphDefinitionDocument) -> Void
    ) {
        guard var document,
              let nodeID = selectedNodeID,
              let index = document.nodes.firstIndex(where: { $0.id == nodeID })
        else { return }
        registerUndo(
            coalescingKey: coalescingKey.map { "\($0):\(nodeID)" }
        )
        var node = document.nodes[index]
        mutation(&node, document)
        document.nodes[index] = node
        document.metadata.modifiedAt = Date()
        document.metadata.modifiedBy = NSUserName()
        self.document = document
        markSemanticMutation()
    }

    private func replaceSelectedProcessArguments(
        _ arguments: [String],
        process: GraphLocalProcessSpecification
    ) {
        updateSelectedLocalProcess(
            executable: process.executable,
            arguments: arguments,
            workingDirectory: process.workingDirectory,
            inheritedEnvironment: process.inheritedEnvironment,
            stdin: process.stdin,
            environmentAllowlist: selectedNode?.environmentAllowlist ?? [],
            workspaceRoot: selectedNode?.workspace.root
        )
    }

    private static func processDeclaration(
        _ output: GraphNodeOutputDefinition
    ) -> GraphLocalProcessArtifactDeclaration {
        GraphLocalProcessArtifactDeclaration(
            identifier: output.id,
            relativePath: output.relativePath,
            mediaType: output.mediaType,
            role: output.role,
            sensitivity: output.sensitivity,
            maximumBytes: output.maximumBytes,
            isRequired: output.isRequired,
            downstreamVisibility: output.downstreamVisibility
        )
    }

    private static func synchronizeProcessOutputs(
        _ node: inout GraphDefinitionDocumentNode
    ) {
        guard node.nodeType == .localProcess,
              let process = try? GraphLocalProcessSpecification(
                immutableSpecification: node.specification
              ) else { return }
        node.specification = (try? GraphLocalProcessSpecification(
            executable: process.executable,
            arguments: process.arguments,
            workingDirectory: process.workingDirectory,
            environment: process.environment,
            inheritedEnvironment: process.inheritedEnvironment,
            stdin: process.stdin,
            outputArtifacts: node.outputs.map(processDeclaration),
            retryableExitCodes: process.retryableExitCodes,
            logPolicy: process.logPolicy
        ).immutableSpecification()) ?? node.specification
        let writable = node.outputs.map {
            URL(fileURLWithPath: $0.relativePath)
                .deletingLastPathComponent().path
        }.filter { !$0.isEmpty && $0 != "." }
        node.workspace = GraphExecutionWorkspaceContext(
            root: node.workspace.root,
            writableRelativePaths: writable
        )
    }

    private static func nextStableID(
        prefix: String,
        existing: [String]
    ) -> String {
        let values = Set(existing)
        var ordinal = values.count + 1
        while values.contains("\(prefix)-\(ordinal)") { ordinal += 1 }
        return "\(prefix)-\(ordinal)"
    }

    private func synchronizeArtifactBindings(
        in document: inout GraphDefinitionDocument
    ) {
        for nodeIndex in document.nodes.indices {
            for inputIndex in document.nodes[nodeIndex].inputs.indices {
                let binding = document.nodes[nodeIndex].inputs[inputIndex].binding
                if binding?.kind == .upstreamArtifact
                    || binding?.kind == .upstreamArtifactCollection {
                    document.nodes[nodeIndex].inputs[inputIndex].binding = nil
                }
            }
        }
        for edge in document.edges where edge.portType == .artifact {
            guard let sourceOutputID = edge.sourceOutputID,
                  let targetInputID = edge.targetInputID,
                  let targetIndex = document.nodes.firstIndex(where: {
                      $0.id == edge.targetNodeID
                  }),
                  let inputIndex = document.nodes[targetIndex].inputs.firstIndex(where: {
                      $0.id == targetInputID
                  }) else { continue }
            let allowsMultiple = document.nodes[targetIndex]
                .inputs[inputIndex].allowsMultiple
            document.nodes[targetIndex].inputs[inputIndex].binding =
                GraphNodeInputBinding(
                    kind: allowsMultiple
                        ? .upstreamArtifactCollection : .upstreamArtifact,
                    sourceNodeID: edge.sourceNodeID,
                    sourceOutputID: sourceOutputID
                )
        }
        for nodeIndex in document.nodes.indices {
            let nodeID = document.nodes[nodeIndex].id
            let incoming = document.edges.filter {
                $0.targetNodeID == nodeID && $0.portType == .artifact
            }
            guard !incoming.isEmpty else { continue }
            let roles = incoming.compactMap { edge -> GraphArtifactRole? in
                guard let source = document.nodes.first(where: {
                    $0.id == edge.sourceNodeID
                }), let outputID = edge.sourceOutputID else { return nil }
                return source.outputs.first { $0.id == outputID }?.role
            }
            document.nodes[nodeIndex].inputArtifactRoles = Array(Set(roles))
                .sorted { $0.rawValue < $1.rawValue }
        }
    }

    private var authoringSnapshot: GraphAuthoringUndoSnapshot? {
        guard let document else { return nil }
        return GraphAuthoringUndoSnapshot(
            document: document,
            selectedNodeIDs: selectedNodeIDs,
            selectedEdgeID: selectedEdgeID
        )
    }

    private func registerUndo(coalescingKey: String?) {
        guard let snapshot = authoringSnapshot else { return }
        if let coalescingKey, undoCoalescingKey == coalescingKey {
            return
        }
        undoSnapshots.append(snapshot)
        if undoSnapshots.count > 200 {
            undoSnapshots.removeFirst(undoSnapshots.count - 200)
        }
        redoSnapshots.removeAll()
        undoCoalescingKey = coalescingKey
    }

    private func restore(_ snapshot: GraphAuthoringUndoSnapshot) {
        document = snapshot.document
        selectedNodeIDs = snapshot.selectedNodeIDs
        selectedEdgeID = snapshot.selectedEdgeID
        isDraft = associatedRunCount > 0
    }

    private func resetUndoHistory() {
        undoSnapshots.removeAll()
        redoSnapshots.removeAll()
        undoCoalescingKey = nil
    }

    private func markSemanticMutation() {
        if associatedRunCount > 0 { isDraft = true }
    }

    private func closeDocumentDiscardingChanges() {
        pauseOrchestration()
        document = nil
        documentURL = nil
        documentFileState = nil
        lastSavedDocument = nil
        hasExternalModification = false
        associatedRunCount = 0
        isDraft = false
        selectedNodeIDs = []
        selectedEdgeID = nil
        closeState = .idle
        resetUndoHistory()
        defaults.removeObject(forKey: Self.lastDocumentPathKey)
        mode = .definition
        acceptedLocalAction("definition_closed")
    }

    private func recordRecentDocument(_ url: URL) {
        recentDocumentURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentDocumentURLs.insert(url.standardizedFileURL, at: 0)
        recentDocumentURLs = Array(recentDocumentURLs.prefix(10))
        defaults.set(
            recentDocumentURLs.map(\.path),
            forKey: Self.recentDocumentPathsKey
        )
    }
}
