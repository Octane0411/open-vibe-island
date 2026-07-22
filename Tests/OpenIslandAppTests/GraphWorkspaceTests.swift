import Foundation
import XCTest
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
final class GraphWorkspaceTests: XCTestCase {
    func testEntryPointConfigurationIsDiscoverableAndAccessible() throws {
        XCTAssertEqual(GraphWorkspaceEntryPoint.label, "Graph Workspace")
        XCTAssertEqual(GraphWorkspaceEntryPoint.windowID, "graph-workspace")
        XCTAssertEqual(GraphWorkspaceEntryPoint.shortcutKey, "g")

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let islandSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/OpenIslandApp/Views/IslandPanelView.swift"
            ),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/OpenIslandApp/OpenIslandApp.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(islandSource.contains("GraphWorkspaceEntryPoint.label"))
        XCTAssertTrue(islandSource.contains(".accessibilityLabel(GraphWorkspaceEntryPoint.label)"))
        XCTAssertTrue(appSource.contains("CommandGroup(after: .windowArrangement)"))
        XCTAssertTrue(appSource.contains("CommandGroup(after: .newItem)"))
        XCTAssertTrue(appSource.contains("modifiers: [.command, .shift]"))
    }

    func testRepeatedActivationUsesStableWindowOpenerAndFocusPath() {
        let model = AppModel()
        var activations = 0
        model.openGraphWorkspaceWindow = { activations += 1 }

        model.showGraphWorkspace()
        model.showGraphWorkspace()

        XCTAssertEqual(activations, 2)
    }

    func testEmptyWorkspaceDefinitionRunAndHistoryModesWork() async throws {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument()

        XCTAssertEqual(viewModel.mode, .definition)
        XCTAssertEqual(viewModel.document?.nodes.count, 0)
        XCTAssertFalse(viewModel.decision(.createRun).isEnabled)

        viewModel.addNode()
        XCTAssertEqual(viewModel.document?.nodes.count, 1)
        XCTAssertTrue(viewModel.decision(.createRun).isEnabled)

        await viewModel.createRun()
        XCTAssertEqual(viewModel.mode, .run)
        XCTAssertNotNil(viewModel.inspection)
        XCTAssertTrue(viewModel.lastCommandResult?.accepted == true)
        XCTAssertGreaterThan(viewModel.lastCommandResult?.streamVersion ?? 0, 0)

        await viewModel.startRun()
        viewModel.run()
        await viewModel.waitForLocalOrchestration()
        XCTAssertEqual(
            viewModel.inspection?.summary.reconciledState,
            .completed
        )

        await viewModel.inspectHistory()
        XCTAssertEqual(viewModel.mode, .history)
        XCTAssertFalse(viewModel.history?.events.isEmpty ?? true)
        XCTAssertNotNil(viewModel.explanation)
    }

    func testTypedPolicyDenialsArePresentedWithoutStateFabrication() async throws {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument()

        let decision = viewModel.decision(.retryNode)
        XCTAssertFalse(decision.isEnabled)
        XCTAssertEqual(decision.reasonCode, "retry_requires_attempt")

        await viewModel.retrySelectedNode()
        XCTAssertEqual(
            viewModel.lastCommandResult?.reasonCode,
            "retry_requires_attempt"
        )
        XCTAssertNil(viewModel.inspection)
    }

    func testDocumentAndRunSelectionRestoreAcrossViewModelRestart() async throws {
        let fixture = try WorkspaceTestFixture()
        let first = fixture.viewModel()
        first.newDocument()
        first.addNode()
        let documentURL = fixture.root.appendingPathComponent("restored.json")
        await first.saveDocument(url: documentURL)
        await first.createRun()
        let runID = try XCTUnwrap(first.inspection?.summary.runID)

        let restarted = fixture.viewModel()
        await restarted.restoreState()

        XCTAssertEqual(restarted.documentURL, documentURL)
        XCTAssertEqual(restarted.document?.nodes.count, 1)
        XCTAssertEqual(restarted.inspection?.summary.runID, runID)
        XCTAssertEqual(restarted.mode, .run)
    }

    func testLayoutEditingDoesNotMutateExistingRunDefinition() async throws {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument()
        viewModel.addNode()
        await viewModel.createRun()
        let digest = viewModel.inspection?.graphDefinitionDigest
        let nodeID = try XCTUnwrap(viewModel.document?.nodes.first?.id)

        viewModel.moveNode(nodeID, to: GraphCanvasPoint(x: 700, y: 320))
        await viewModel.refreshRunAndHistory()

        XCTAssertEqual(viewModel.inspection?.graphDefinitionDigest, digest)
    }

    func testDocumentLifecycleTracksDirtySaveReopenAndRecentDocuments()
        async throws
    {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument(
            request: GraphNewDocumentRequest(
                name: "Authored Graph",
                graphID: "authored-graph",
                definitionVersion: "1",
                description: "Lifecycle test",
                workspaceDirectory: fixture.root.path
            )
        )

        XCTAssertTrue(viewModel.isDirty)
        XCTAssertEqual(viewModel.document?.name, "Authored Graph")
        let url = fixture.root.appendingPathComponent("authored.openisland-graph.json")
        await viewModel.saveDocument(url: url)
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertEqual(viewModel.recentDocumentURLs.first, url)

        viewModel.addNode()
        XCTAssertTrue(viewModel.isDirty)
        await viewModel.revertDocument()
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertEqual(viewModel.document?.nodes.count, 0)

        let restarted = fixture.viewModel()
        await restarted.openDocument(url: url)
        XCTAssertEqual(restarted.document?.graphID, "authored-graph")
        XCTAssertFalse(restarted.isDirty)
        XCTAssertEqual(restarted.recentDocumentURLs.first, url)
    }

    func testExternalModificationPreventsSilentOverwrite() async throws {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument()
        let url = fixture.root.appendingPathComponent("conflict.json")
        await viewModel.saveDocument(url: url)
        viewModel.addNode()
        try Data("external-change".utf8).write(to: url, options: .atomic)

        await viewModel.refreshExternalModificationState()
        XCTAssertTrue(viewModel.hasExternalModification)
        await viewModel.saveDocument()

        XCTAssertEqual(viewModel.lastCommandResult?.reasonCode, "definition_save_failed")
        XCTAssertTrue(viewModel.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("external-change".utf8))
    }

    func testUnsavedCloseSupportsCancelAndDiscard() async throws {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument()

        viewModel.requestCloseDocument()
        XCTAssertEqual(viewModel.closeState, .confirmationRequired)
        await viewModel.resolveCloseDocument(.cancel)
        XCTAssertNotNil(viewModel.document)
        XCTAssertEqual(viewModel.closeState, .idle)

        viewModel.requestCloseDocument()
        await viewModel.resolveCloseDocument(.discard)
        XCTAssertNil(viewModel.document)
        XCTAssertFalse(viewModel.isDirty)
    }

    func testAuthoringUndoRedoAndDefinitionDraftVersioning() async throws {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument()
        viewModel.addNode()
        XCTAssertEqual(viewModel.document?.nodes.count, 1)
        viewModel.undo()
        XCTAssertEqual(viewModel.document?.nodes.count, 0)
        viewModel.redo()
        XCTAssertEqual(viewModel.document?.nodes.count, 1)

        await viewModel.createRun()
        XCTAssertEqual(viewModel.associatedRunCount, 1)
        viewModel.updateSelectedNode(name: "Renamed", description: "")
        XCTAssertTrue(viewModel.isDraft)
        XCTAssertEqual(viewModel.document?.nodes.first?.id, "node-1")

        viewModel.createNewDefinitionVersion()
        XCTAssertEqual(viewModel.document?.definitionVersion, "2")
        XCTAssertFalse(viewModel.isDraft)
        XCTAssertEqual(viewModel.associatedRunCount, 0)
    }

    func testNodePaletteCreatesExplicitExecutableAndReferenceTypes() throws {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument()

        for type in GraphDefinitionNodeType.allCases {
            viewModel.addNode(type: type)
        }

        XCTAssertEqual(
            Set(viewModel.document?.nodes.map(\.nodeType) ?? []),
            Set(GraphDefinitionNodeType.allCases)
        )
        XCTAssertEqual(
            viewModel.document?.nodes.filter(\.nodeType.isExecutable).count,
            3
        )
        XCTAssertEqual(
            try viewModel.document?.executableDefinition().scheduling.nodes.count,
            3
        )
    }

    func testCompleteLocalProcessNodeAuthoringPreservesIdentityAndUndo()
        throws
    {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument()
        viewModel.addNode(type: .localProcess)
        let stableID = try XCTUnwrap(viewModel.selectedNodeID)

        viewModel.updateSelectedNodeIdentity(
            name: "Generate",
            description: "Create the source artifact",
            tags: ["fixture", "authoring"]
        )
        viewModel.updateSelectedNodeCapabilities(
            required: ["local-process", "filesystem-write"],
            preferred: ["arm64"],
            executorKind: .supervisedLocalProcess,
            platformConstraints: ["macOS"]
        )
        viewModel.updateSelectedLocalProcess(
            executable: "/usr/bin/printf",
            arguments: ["%s", "payload"],
            workingDirectory: ".",
            inheritedEnvironment: .allowlisted,
            stdin: .closed,
            environmentAllowlist: ["LANG", "PATH"],
            workspaceRoot: fixture.root.path
        )
        viewModel.addSelectedNodeArgument()
        viewModel.updateSelectedNodeArgument(at: 2, value: "tail")
        viewModel.moveSelectedNodeArgument(from: 2, offset: -1)
        viewModel.removeSelectedNodeArgument(at: 2)
        viewModel.addSelectedNodeInput()
        viewModel.addSelectedNodeOutput()

        var input = try XCTUnwrap(viewModel.selectedNode?.inputs.first)
        input.name = "Source"
        input.mediaType = "application/json"
        input.binding = GraphNodeInputBinding(
            kind: .fileReference,
            fileReference: "inputs/source.json"
        )
        viewModel.updateSelectedNodeInput(input)
        var output = try XCTUnwrap(viewModel.selectedNode?.outputs.first)
        output.name = "Generated Document"
        output.relativePath = "artifacts/generated.json"
        output.mediaType = "application/json"
        output.maximumBytes = 2 * 1_024 * 1_024
        output.sensitivity = .confidential
        output.downstreamVisibility = .directDependents
        viewModel.updateSelectedNodeOutput(output)

        let retry = GraphRetryPolicy(
            maximumAttempts: 4,
            retryableFailureCategories: ["timeout"],
            initialBackoffSeconds: 2,
            maximumBackoffSeconds: 20,
            timeoutBehavior: .retry
        )
        viewModel.updateSelectedNodeRetry(
            GraphNodeRetryConfiguration(
                inheritsGraphDefault: false,
                override: retry
            )
        )
        viewModel.updateSelectedNodeTimeout(
            GraphNodeTimeoutConfiguration(
                inheritsGraphDefault: false,
                executionSeconds: 45,
                cancellationAcknowledgementSeconds: 7,
                claimSeconds: 11
            )
        )

        let node = try XCTUnwrap(viewModel.selectedNode)
        let process = try GraphLocalProcessSpecification(
            immutableSpecification: node.specification
        )
        XCTAssertEqual(node.id, stableID)
        XCTAssertEqual(node.name, "Generate")
        XCTAssertEqual(node.tags, ["authoring", "fixture"])
        XCTAssertEqual(process.executable, "/usr/bin/printf")
        XCTAssertEqual(process.arguments, ["%s", "tail"])
        XCTAssertEqual(node.environmentAllowlist, ["LANG", "PATH"])
        XCTAssertEqual(node.inputs.first?.binding?.fileReference, "inputs/source.json")
        XCTAssertEqual(process.outputArtifacts.first?.stableID, output.id)
        XCTAssertEqual(process.outputArtifacts.first?.required, true)
        XCTAssertEqual(node.timeoutPolicy.executionSeconds, 45)
        XCTAssertEqual(
            try viewModel.document?.executableDefinition().schedulerPolicy
                .retryPolicy(for: stableID).maximumAttempts,
            4
        )

        let encoded = try GraphDefinitionDocumentCodec.encode(
            XCTUnwrap(viewModel.document)
        )
        let reopened = try GraphDefinitionDocumentCodec.decode(encoded)
        XCTAssertEqual(reopened.nodes.first?.id, stableID)
        XCTAssertEqual(reopened.nodes.first?.outputs.first?.id, output.id)

        viewModel.undo()
        XCTAssertNotEqual(viewModel.selectedNode?.timeoutPolicy.executionSeconds, 45)
        viewModel.redo()
        XCTAssertEqual(viewModel.selectedNode?.timeoutPolicy.executionSeconds, 45)
    }

    func testTypedArtifactConnectionBindsStablePortsAndSupportsUndoDelete()
        throws
    {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument()
        viewModel.addNode(type: .localProcess)
        let sourceID = try XCTUnwrap(viewModel.selectedNodeID)
        viewModel.addSelectedNodeOutput()
        var output = try XCTUnwrap(viewModel.selectedNode?.outputs.first)
        output.mediaType = "application/json"
        viewModel.updateSelectedNodeOutput(output)

        viewModel.addNode(type: .localProcess)
        let targetID = try XCTUnwrap(viewModel.selectedNodeID)
        viewModel.addSelectedNodeInput()
        var input = try XCTUnwrap(viewModel.selectedNode?.inputs.first)
        input.mediaType = "application/json"
        viewModel.updateSelectedNodeInput(input)

        let decision = viewModel.connectNodes(
            sourceNodeID: sourceID,
            targetNodeID: targetID,
            portType: .artifact,
            sourceOutputID: output.id,
            targetInputID: input.id
        )

        XCTAssertTrue(decision.isAllowed)
        let edge = try XCTUnwrap(viewModel.selectedEdge)
        XCTAssertEqual(edge.sourceOutputID, output.id)
        XCTAssertEqual(edge.targetInputID, input.id)
        let target = try XCTUnwrap(viewModel.document?.nodes.first {
            $0.id == targetID
        })
        XCTAssertEqual(target.inputs.first?.binding?.sourceNodeID, sourceID)
        XCTAssertEqual(target.inputs.first?.binding?.sourceOutputID, output.id)
        XCTAssertEqual(target.inputArtifactRoles, [output.role])

        var optionalEdge = edge
        optionalEdge.isRequired = false
        viewModel.updateSelectedEdge(optionalEdge)
        XCTAssertEqual(viewModel.selectedEdge?.isRequired, false)

        let duplicate = viewModel.connectNodes(
            sourceNodeID: sourceID,
            targetNodeID: targetID,
            portType: .artifact,
            sourceOutputID: output.id,
            targetInputID: input.id
        )
        XCTAssertEqual(duplicate.rejection, .duplicateEdge)

        viewModel.undo()
        XCTAssertEqual(viewModel.selectedEdge?.isRequired, true)
        viewModel.undo()
        XCTAssertTrue(viewModel.document?.edges.isEmpty == true)
        viewModel.redo()
        XCTAssertEqual(viewModel.document?.edges.count, 1)
        viewModel.selectEdge(try XCTUnwrap(viewModel.document?.edges.first?.id))
        viewModel.deleteSelection()
        XCTAssertTrue(viewModel.document?.edges.isEmpty == true)
    }

    func testConnectionPathsRejectSelfCycleVisualAndMediaMismatch() throws {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument()
        viewModel.addNode(type: .localProcess)
        let first = try XCTUnwrap(viewModel.selectedNodeID)
        viewModel.addSelectedNodeOutput()
        let output = try XCTUnwrap(viewModel.selectedNode?.outputs.first)
        viewModel.addNode(type: .localProcess)
        let second = try XCTUnwrap(viewModel.selectedNodeID)
        viewModel.addSelectedNodeInput()
        var input = try XCTUnwrap(viewModel.selectedNode?.inputs.first)
        input.mediaType = "text/plain"
        viewModel.updateSelectedNodeInput(input)

        XCTAssertEqual(
            viewModel.connectNodes(sourceNodeID: first, targetNodeID: first)
                .rejection,
            .selfEdge
        )
        XCTAssertEqual(
            viewModel.connectNodes(
                sourceNodeID: first,
                targetNodeID: second,
                portType: .artifact,
                sourceOutputID: output.id,
                targetInputID: input.id
            ).rejection,
            .incompatibleMediaType
        )
        XCTAssertTrue(
            viewModel.connectNodes(sourceNodeID: first, targetNodeID: second)
                .isAllowed
        )
        XCTAssertEqual(
            viewModel.connectNodes(sourceNodeID: second, targetNodeID: first)
                .rejection,
            .cycle
        )

        viewModel.addNode(type: .annotation)
        let annotation = try XCTUnwrap(viewModel.selectedNodeID)
        XCTAssertEqual(
            viewModel.connectNodes(sourceNodeID: annotation, targetNodeID: first)
                .rejection,
            .nonExecutableDependency
        )
    }

    func testKeyboardDependencyWorkflowUsesSameValidatedConnectionPath() throws {
        let fixture = try WorkspaceTestFixture()
        let viewModel = fixture.viewModel()
        viewModel.newDocument()
        viewModel.addNode(type: .localProcess)
        let source = try XCTUnwrap(viewModel.selectedNodeID)
        viewModel.addNode(type: .localProcess)
        let target = try XCTUnwrap(viewModel.selectedNodeID)

        viewModel.beginDependencyCreation(from: source)
        viewModel.completeDependencyCreation(to: target)

        XCTAssertNil(viewModel.dependencySourceNodeID)
        XCTAssertEqual(viewModel.document?.edges.count, 1)
        XCTAssertEqual(viewModel.selectedEdge?.sourceNodeID, source)
        XCTAssertEqual(viewModel.selectedEdge?.targetNodeID, target)
    }
}

private struct WorkspaceTestFixture {
    let root: URL
    let defaults: UserDefaults
    let service: GraphWorkspaceService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defaults = try XCTUnwrap(
            UserDefaults(suiteName: "GraphWorkspaceTests-\(UUID().uuidString)")
        )
        service = try GraphWorkspaceService.inMemory(
            rootURL: root.appendingPathComponent("runtime", isDirectory: true)
        )
    }

    @MainActor
    func viewModel() -> GraphWorkspaceViewModel {
        GraphWorkspaceViewModel(service: service, defaults: defaults)
    }
}
