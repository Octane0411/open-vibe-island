import Foundation
import XCTest
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
final class UIAuthoredGraphEndToEndTests: XCTestCase {
    func testBlankGraphBecomesDurableThreeProcessRunWithCLIParity()
        async throws
    {
        let fixture = try UIAuthoredGraphFixture(name: "three-process")
        let viewModel = fixture.viewModel()
        viewModel.newDocument(request: fixture.blankRequest(name: "Three Process"))

        let generate = try addLocalStage(
            "generate",
            outputRole: .nodeOutput,
            inputRole: nil,
            fixture: fixture,
            viewModel: viewModel
        )
        let transform = try addLocalStage(
            "transform",
            outputRole: .structuredResult,
            inputRole: .nodeOutput,
            fixture: fixture,
            viewModel: viewModel
        )
        let verify = try addLocalStage(
            "verify",
            outputRole: .diagnostic,
            inputRole: .structuredResult,
            fixture: fixture,
            viewModel: viewModel
        )
        try connectArtifact(generate, transform, viewModel: viewModel)
        try connectArtifact(transform, verify, viewModel: viewModel)

        try await saveCloseReopenValidate(
            viewModel: viewModel,
            documentURL: fixture.documentURL
        )
        try await executeToCompletion(viewModel: viewModel)

        XCTAssertEqual(
            viewModel.inspection?.summary.persistedState,
            .completed
        )
        XCTAssertGreaterThanOrEqual(viewModel.inspection?.artifacts.count ?? 0, 3)
        XCTAssertTrue(fixture.artifactExists("generate.json"))
        XCTAssertTrue(fixture.artifactExists("transform.json"))
        XCTAssertTrue(fixture.artifactExists("verify.json"))

        viewModel.selectNode(generate.nodeID)
        await viewModel.openLogs()
        XCTAssertTrue(
            viewModel.logPage?.entries.map(\.text).joined()
                .contains("role=generate") == true
        )

        let runID = try XCTUnwrap(viewModel.inspection?.summary.runID)
        try fixture.assertCLIState(runID: runID, expectedState: "completed")
        let restarted = GraphWorkspaceViewModel(
            service: try fixture.restartedService(),
            defaults: fixture.defaults
        )
        await restarted.restoreState()
        XCTAssertEqual(restarted.inspection?.summary.runID, runID)
        XCTAssertEqual(restarted.inspection?.summary.persistedState, .completed)
    }

    func testCompendiumFillIsBuiltFromBlankThroughAuthoringCommands()
        async throws
    {
        let fixture = try UIAuthoredGraphFixture(name: "compendium-fill")
        let viewModel = fixture.viewModel()
        viewModel.newDocument(request: fixture.blankRequest(name: "Compendium Fill"))

        let architect = try addLocalStage(
            "architect",
            outputRole: .nodeOutput,
            inputRole: nil,
            fixture: fixture,
            viewModel: viewModel
        )
        let researcher = try addLocalStage(
            "researcher",
            outputRole: .structuredResult,
            inputRole: .nodeOutput,
            fixture: fixture,
            viewModel: viewModel
        )
        let graph = try addLocalStage(
            "graph",
            outputRole: .diagnostic,
            inputRole: .structuredResult,
            fixture: fixture,
            viewModel: viewModel
        )
        let reviewer = try addLocalStage(
            "reviewer",
            outputRole: .structuredResult,
            inputRole: .diagnostic,
            fixture: fixture,
            viewModel: viewModel
        )
        try connectArtifact(architect, researcher, viewModel: viewModel)
        try connectArtifact(researcher, graph, viewModel: viewModel)
        try connectArtifact(graph, reviewer, viewModel: viewModel)

        XCTAssertEqual(viewModel.document?.name, "Compendium Fill")
        XCTAssertEqual(viewModel.document?.nodes.count, 4)
        XCTAssertEqual(viewModel.document?.edges.count, 3)
        try await saveCloseReopenValidate(
            viewModel: viewModel,
            documentURL: fixture.documentURL
        )
        try await executeToCompletion(viewModel: viewModel)

        XCTAssertEqual(
            viewModel.inspection?.summary.persistedState,
            .completed
        )
        XCTAssertEqual(
            Set(viewModel.inspection?.nodes.map(\.persistedState) ?? []),
            [.completed]
        )
        let reviewerData = try Data(
            contentsOf: fixture.artifactURL("reviewer.json")
        )
        let reviewerResult = try XCTUnwrap(
            JSONSerialization.jsonObject(with: reviewerData)
                as? [String: Any]
        )
        XCTAssertEqual(reviewerResult["verdict"] as? String, "pass")
        XCTAssertEqual(reviewerResult["inputCount"] as? Int, 1)
    }

    private func addLocalStage(
        _ name: String,
        outputRole: GraphArtifactRole,
        inputRole: GraphArtifactRole?,
        fixture: UIAuthoredGraphFixture,
        viewModel: GraphWorkspaceViewModel
    ) throws -> AuthoredStage {
        viewModel.addNode(type: .localProcess)
        let nodeID = try XCTUnwrap(viewModel.selectedNodeID)
        viewModel.updateSelectedNodeIdentity(
            name: name.capitalized,
            description: "UI-authored \(name) process",
            tags: ["ui-authored", "local-process"]
        )
        var inputID: String?
        if let inputRole {
            viewModel.addSelectedNodeInput()
            var input = try XCTUnwrap(viewModel.selectedNode?.inputs.first)
            input.name = inputRole.rawValue
            input.mediaType = "application/json"
            viewModel.updateSelectedNodeInput(input)
            inputID = input.id
        }
        viewModel.addSelectedNodeOutput()
        var output = try XCTUnwrap(viewModel.selectedNode?.outputs.first)
        output.name = outputRole.rawValue
        output.role = outputRole
        output.relativePath = "artifacts/\(name).json"
        output.mediaType = "application/json"
        viewModel.updateSelectedNodeOutput(output)

        var arguments = ["--role", name]
        if let inputRole {
            arguments += ["--input", "${input:\(inputRole.rawValue)}"]
        }
        arguments += ["--output", "${artifact:\(outputRole.rawValue)}"]
        if inputRole == nil { arguments.append("--stderr") }
        viewModel.updateSelectedLocalProcess(
            executable: fixture.executableURL.path,
            arguments: arguments,
            workingDirectory: ".",
            inheritedEnvironment: .none,
            stdin: .nullDevice,
            environmentAllowlist: [],
            workspaceRoot: fixture.workspaceURL.path
        )
        return AuthoredStage(
            nodeID: nodeID,
            inputID: inputID,
            outputID: output.id
        )
    }

    private func connectArtifact(
        _ source: AuthoredStage,
        _ target: AuthoredStage,
        viewModel: GraphWorkspaceViewModel
    ) throws {
        let decision = viewModel.connectNodes(
            sourceNodeID: source.nodeID,
            targetNodeID: target.nodeID,
            portType: .artifact,
            sourceOutputID: source.outputID,
            targetInputID: try XCTUnwrap(target.inputID)
        )
        XCTAssertTrue(decision.isAllowed, decision.message)
    }

    private func saveCloseReopenValidate(
        viewModel: GraphWorkspaceViewModel,
        documentURL: URL
    ) async throws {
        viewModel.validateDocument()
        XCTAssertFalse(viewModel.validationDiagnostics.contains {
            $0.severity == .error
        })
        await viewModel.saveDocument(url: documentURL)
        XCTAssertFalse(viewModel.isDirty)
        viewModel.requestCloseDocument()
        XCTAssertNil(viewModel.document)
        await viewModel.openDocument(url: documentURL)
        XCTAssertNotNil(viewModel.document)
        await viewModel.refreshValidation()
        XCTAssertFalse(viewModel.validationDiagnostics.contains {
            $0.severity == .error
        })
    }

    private func executeToCompletion(
        viewModel: GraphWorkspaceViewModel
    ) async throws {
        await viewModel.prepareCreateRun()
        XCTAssertTrue(viewModel.isShowingCreateRunSheet)
        await viewModel.confirmCreateRun()
        XCTAssertTrue(
            viewModel.lastCommandResult?.accepted == true,
            "create=\(String(describing: viewModel.lastCommandResult)) error=\(String(describing: viewModel.errorMessage))"
        )
        await viewModel.startRun()
        XCTAssertTrue(
            viewModel.lastCommandResult?.accepted == true,
            "start=\(String(describing: viewModel.lastCommandResult)) error=\(String(describing: viewModel.errorMessage)) state=\(String(describing: viewModel.inspection?.summary.persistedState))"
        )
        viewModel.run()
        await viewModel.waitForLocalOrchestration()
        XCTAssertEqual(
            viewModel.inspection?.summary.persistedState,
            .completed,
            "last=\(String(describing: viewModel.lastCommandResult)) error=\(String(describing: viewModel.errorMessage)) events=\(viewModel.history?.events.suffix(10).map(\.eventType) ?? [])"
        )
    }
}

private struct AuthoredStage {
    let nodeID: String
    let inputID: String?
    let outputID: String
}

private struct UIAuthoredGraphFixture {
    let rootURL: URL
    let workspaceURL: URL
    let runtimeURL: URL
    let databasePath: String
    let documentURL: URL
    let executableURL: URL
    let defaults: UserDefaults
    let service: GraphWorkspaceService

    init(name: String) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        runtimeURL = rootURL.appendingPathComponent("runtime", isDirectory: true)
        databasePath = rootURL.appendingPathComponent("graph.sqlite").path
        documentURL = rootURL.appendingPathComponent("\(name).openisland-graph.json")
        executableURL = try GraphWorkspaceBundledFixtures.fixtureExecutableURL()
        defaults = try XCTUnwrap(
            UserDefaults(suiteName: "UIAuthoredGraph-\(UUID().uuidString)")
        )
        try FileManager.default.createDirectory(
            at: workspaceURL.appendingPathComponent("artifacts", isDirectory: true),
            withIntermediateDirectories: true
        )
        let store = try SQLiteGraphExecutionStore(databasePath: databasePath)
        let launchStore = try GraphLocalProcessLaunchStore(rootURL: runtimeURL)
        service = GraphWorkspaceService(
            eventStore: store,
            readStore: store,
            snapshotStore: store,
            processExecutor: SupervisedLocalProcessExecutor(
                launchStore: launchStore
            ),
            launchStore: launchStore
        )
    }

    @MainActor
    func viewModel() -> GraphWorkspaceViewModel {
        GraphWorkspaceViewModel(service: service, defaults: defaults)
    }

    func blankRequest(name: String) -> GraphNewDocumentRequest {
        GraphNewDocumentRequest(
            template: .blank,
            name: name,
            graphID: name.lowercased().replacingOccurrences(of: " ", with: "-"),
            definitionVersion: "1",
            description: "Built through Graph Workspace authoring commands",
            workspaceDirectory: workspaceURL.path
        )
    }

    func restartedService() throws -> GraphWorkspaceService {
        let store = try SQLiteGraphExecutionStore(databasePath: databasePath)
        let launchStore = try GraphLocalProcessLaunchStore(rootURL: runtimeURL)
        return GraphWorkspaceService(
            eventStore: store,
            readStore: store,
            snapshotStore: store,
            processExecutor: SupervisedLocalProcessExecutor(
                launchStore: launchStore
            ),
            launchStore: launchStore
        )
    }

    func artifactURL(_ name: String) -> URL {
        workspaceURL.appendingPathComponent("artifacts/\(name)")
    }

    func artifactExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: artifactURL(name).path)
    }

    func assertCLIState(runID: String, expectedState: String) throws {
        let cliURL = executableURL.deletingLastPathComponent()
            .appendingPathComponent("openisland")
        let process = Process()
        process.executableURL = cliURL
        process.arguments = [
            "graph", "inspect", runID,
            "--include-artifacts",
            "--output", "json",
            "--no-color",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["OPENISLAND_GRAPH_DATABASE_PATH"] = databasePath
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(
            decoding: stdout.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let error = String(
            decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        XCTAssertEqual(process.terminationStatus, 0, error)
        XCTAssertTrue(output.contains(runID))
        XCTAssertTrue(output.contains(expectedState))
    }
}
