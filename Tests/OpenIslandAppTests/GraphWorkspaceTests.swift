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
