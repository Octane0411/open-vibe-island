import Darwin
import Foundation
import XCTest
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
final class CompendiumLocalProcessEndToEndTests: XCTestCase {
    func testFourRealProcessesCompletePropagateAndRecoverAcrossRestart()
        async throws
    {
        let fixture = try CompendiumEndToEndFixture()
        let viewModel = try await fixture.preparedViewModel()

        XCTAssertEqual(viewModel.document?.nodes.map(\.id), [
            "architect", "graph", "researcher", "reviewer",
        ])
        XCTAssertEqual(viewModel.document?.edges.count, 3)
        viewModel.validateDocument()
        XCTAssertEqual(viewModel.lastCommandResult?.reasonCode, "definition_valid")

        await viewModel.createRun()
        await viewModel.startRun()
        viewModel.run()
        await viewModel.waitForLocalOrchestration()

        XCTAssertEqual(
            viewModel.inspection?.summary.persistedState,
            .completed,
            "last=\(String(describing: viewModel.lastCommandResult)) error=\(String(describing: viewModel.errorMessage)) history=\(viewModel.history?.events.suffix(8).map(\.eventType) ?? [])"
        )
        XCTAssertEqual(
            Set(viewModel.inspection?.nodes.map(\.persistedState) ?? []),
            [.completed]
        )
        let records = try await fixture.launchStore.records()
        XCTAssertEqual(records.count, 4)
        XCTAssertTrue(records.allSatisfy { $0.exit?.terminationStatus == 0 })
        XCTAssertTrue(records.allSatisfy {
            $0.identity.process.processID != nil
                && $0.identity.birthIdentity != nil
                && !$0.identity.invocationDigest.isEmpty
                && !$0.identity.executableIdentity.isEmpty
        })

        let reviewerData = try Data(
            contentsOf: fixture.workspaceURL
                .appendingPathComponent("artifacts/reviewer.json")
        )
        let reviewer = try XCTUnwrap(
            JSONSerialization.jsonObject(with: reviewerData)
                as? [String: Any]
        )
        XCTAssertEqual(reviewer["verdict"] as? String, "pass")
        XCTAssertEqual(reviewer["inputCount"] as? Int, 3)

        viewModel.selectNode("architect")
        await viewModel.openLogs()
        XCTAssertTrue(
            viewModel.logPage?.entries.map(\.text).joined()
                .contains("role=architect") == true
        )
        await viewModel.inspectHistory()
        XCTAssertFalse(viewModel.history?.events.isEmpty ?? true)
        XCTAssertNotNil(viewModel.explanation)

        let exportURL = fixture.rootURL.appendingPathComponent("run-export.json")
        await viewModel.exportRun(url: exportURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

        let runID = try XCTUnwrap(viewModel.inspection?.summary.runID)
        try fixture.assertCLIState(runID: runID, expectedState: "completed")

        let restarted = try fixture.restartedService()
        let restartedViewModel = GraphWorkspaceViewModel(
            service: restarted,
            defaults: fixture.defaults
        )
        await restartedViewModel.restoreState()
        XCTAssertEqual(
            restartedViewModel.inspection?.summary.runID,
            runID
        )
        XCTAssertEqual(
            restartedViewModel.inspection?.summary.persistedState,
            .completed
        )
        restartedViewModel.selectNode("architect")
        await restartedViewModel.openLogs()
        XCTAssertFalse(restartedViewModel.logPage?.entries.isEmpty ?? true)
    }

    func testRetryableProcessFailureIsRetriedThroughWorkspacePolicy()
        async throws
    {
        let fixture = try CompendiumEndToEndFixture()
        var document = fixture.document
        try appendArguments(
            [
                "--fail-once-directory", "${workspace}",
                "--failure-code", "23",
            ],
            nodeID: "researcher",
            document: &document
        )
        let viewModel = try await fixture.preparedViewModel(document: document)
        await viewModel.createRun()
        await viewModel.startRun()

        try await fixture.launchAndFinish(nodeID: "architect", viewModel: viewModel)
        try await fixture.launchAndFinish(nodeID: "researcher", viewModel: viewModel)
        XCTAssertEqual(
            viewModel.inspection?.nodes.first { $0.id == "researcher" }?
                .persistedState,
            .failed
        )
        viewModel.selectNode("researcher")
        XCTAssertTrue(viewModel.decision(.retryNode).isEnabled)

        await viewModel.retrySelectedNode()
        XCTAssertEqual(
            viewModel.lastCommandResult?.reasonCode,
            "retry_requested"
        )
        viewModel.run()
        await viewModel.waitForLocalOrchestration()

        XCTAssertEqual(
            viewModel.inspection?.summary.persistedState,
            .completed,
            "last=\(String(describing: viewModel.lastCommandResult)) error=\(String(describing: viewModel.errorMessage)) retries=\(viewModel.inspection?.scheduling?.retries ?? []) history=\(viewModel.history?.events.suffix(12).map(\.eventType) ?? [])"
        )
        XCTAssertEqual(
            viewModel.inspection?.attempts
                .filter { $0.nodeID == "researcher" }.count,
            2
        )
    }

    func testNonRetryableFailureBlocksDownstreamNodes() async throws {
        let fixture = try CompendiumEndToEndFixture()
        var document = fixture.document
        try appendArguments(
            ["--failure-code", "42"],
            nodeID: "researcher",
            document: &document
        )
        let viewModel = try await fixture.preparedViewModel(document: document)
        await viewModel.createRun()
        await viewModel.startRun()
        viewModel.run()
        await viewModel.waitForLocalOrchestration()

        XCTAssertEqual(
            viewModel.inspection?.nodes.first { $0.id == "researcher" }?
                .persistedState,
            .failed
        )
        XCTAssertEqual(
            viewModel.inspection?.nodes.first { $0.id == "graph" }?
                .reconciledState,
            .blocked
        )
        XCTAssertEqual(
            viewModel.inspection?.nodes.first { $0.id == "reviewer" }?
                .reconciledState,
            .blocked
        )
    }

    func testWorkspaceCancellationTerminatesOwnedProcessAndNotUnrelatedProcess()
        async throws
    {
        let fixture = try CompendiumEndToEndFixture()
        var document = fixture.document
        try replaceArguments(
            ["--role", "architect", "--wait-for-cancellation"],
            nodeID: "architect",
            document: &document
        )
        let viewModel = try await fixture.preparedViewModel(document: document)
        await viewModel.createRun()
        await viewModel.startRun()
        let record = try await fixture.launch(
            nodeID: "architect",
            viewModel: viewModel
        )
        let ready = try await fixture.executor.waitForLog(
            launchRecordID: record.id,
            containing: "waiting for cancellation"
        )
        XCTAssertTrue(ready)

        let unrelated = Process()
        unrelated.executableURL = fixture.executableURL
        unrelated.arguments = [
            "--role", "unrelated", "--wait-for-cancellation",
        ]
        unrelated.standardOutput = FileHandle.nullDevice
        unrelated.standardError = FileHandle.nullDevice
        try unrelated.run()
        defer {
            if unrelated.isRunning { unrelated.terminate() }
            unrelated.waitUntilExit()
        }

        viewModel.selectNode("architect")
        await viewModel.cancelSelectedNode()
        XCTAssertEqual(
            viewModel.lastCommandResult?.reasonCode,
            "cancellation_requested"
        )
        await viewModel.step()
        await fixture.executor.waitForExit(launchRecordID: record.id)
        await viewModel.step()

        XCTAssertTrue(unrelated.isRunning)
        XCTAssertEqual(
            viewModel.inspection?.nodes.first { $0.id == "architect" }?
                .persistedState,
            .cancelled
        )
        let terminatedPID = try XCTUnwrap(record.identity.process.processID)
        XCTAssertEqual(Darwin.kill(terminatedPID, 0), -1)
        if let groupID = record.identity.processGroupID {
            XCTAssertEqual(groupID, terminatedPID)
            XCTAssertEqual(Darwin.kill(-groupID, 0), -1)
        }
    }

    func testExecutionTimeoutInterruptsAndCleansUpRealProcess() async throws {
        let fixture = try CompendiumEndToEndFixture()
        var document = fixture.document
        try replaceArguments(
            ["--role", "architect", "--wait-for-cancellation"],
            nodeID: "architect",
            document: &document
        )
        let index = try XCTUnwrap(
            document.nodes.firstIndex { $0.id == "architect" }
        )
        document.nodes[index].timeoutPolicy = GraphExecutionTimeoutPolicy(
            executionSeconds: 1,
            cancellationAcknowledgementSeconds: 1
        )
        let viewModel = try await fixture.preparedViewModel(document: document)
        await viewModel.createRun()
        await viewModel.startRun()
        let record = try await fixture.launch(
            nodeID: "architect",
            viewModel: viewModel
        )
        let ready = try await fixture.executor.waitForLog(
            launchRecordID: record.id,
            containing: "waiting for cancellation"
        )
        XCTAssertTrue(ready)
        let runID = try XCTUnwrap(viewModel.inspection?.summary.runID)

        let timedOut = await fixture.service.step(
            runID: runID,
            occurredAt: Date().addingTimeInterval(2)
        )
        await fixture.executor.waitForExit(launchRecordID: record.id)
        await viewModel.refreshRunAndHistory()

        XCTAssertTrue(
            timedOut.accepted,
            "\(timedOut.reasonCode): \(timedOut.diagnostics)"
        )
        XCTAssertEqual(
            viewModel.inspection?.attempts.first { $0.nodeID == "architect" }?
                .persistedState,
            .interrupted
        )
        XCTAssertTrue(
            viewModel.inspection?.scheduling?.timeouts.contains(where: {
                $0.kind == .attemptExecution
            }) == true
        )
    }
}

private struct CompendiumEndToEndFixture {
    let rootURL: URL
    let workspaceURL: URL
    let runtimeURL: URL
    let databasePath: String
    let documentURL: URL
    let executableURL: URL
    let defaults: UserDefaults
    let launchStore: GraphLocalProcessLaunchStore
    let executor: SupervisedLocalProcessExecutor
    let service: GraphWorkspaceService
    let document: GraphDefinitionDocument

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent(
            "workspace",
            isDirectory: true
        )
        runtimeURL = rootURL.appendingPathComponent(
            "runtime",
            isDirectory: true
        )
        databasePath = rootURL.appendingPathComponent("graph.sqlite").path
        documentURL = rootURL.appendingPathComponent("compendium.json")
        executableURL = try GraphWorkspaceBundledFixtures.fixtureExecutableURL()
        defaults = try XCTUnwrap(
            UserDefaults(suiteName: "CompendiumE2E-\(UUID().uuidString)")
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        launchStore = try GraphLocalProcessLaunchStore(rootURL: runtimeURL)
        executor = SupervisedLocalProcessExecutor(launchStore: launchStore)
        let store = try SQLiteGraphExecutionStore(databasePath: databasePath)
        service = GraphWorkspaceService(
            eventStore: store,
            readStore: store,
            snapshotStore: store,
            processExecutor: executor,
            launchStore: launchStore
        )
        document = try GraphWorkspaceBundledFixtures.loadCompendium(
            executableURL: executableURL,
            workspaceURL: workspaceURL
        )
    }

    @MainActor
    func preparedViewModel(
        document: GraphDefinitionDocument? = nil
    ) async throws -> GraphWorkspaceViewModel {
        let selected = document ?? self.document
        try GraphDefinitionDocumentCodec.save(selected, to: documentURL)
        let viewModel = GraphWorkspaceViewModel(
            service: service,
            defaults: defaults
        )
        await viewModel.openDocument(url: documentURL)
        return viewModel
    }

    func restartedService() throws -> GraphWorkspaceService {
        let store = try SQLiteGraphExecutionStore(databasePath: databasePath)
        let restartedLaunchStore = try GraphLocalProcessLaunchStore(
            rootURL: runtimeURL
        )
        let restartedExecutor = SupervisedLocalProcessExecutor(
            launchStore: restartedLaunchStore
        )
        return GraphWorkspaceService(
            eventStore: store,
            readStore: store,
            snapshotStore: store,
            processExecutor: restartedExecutor,
            launchStore: restartedLaunchStore
        )
    }

    @MainActor
    func launch(
        nodeID: String,
        viewModel: GraphWorkspaceViewModel
    ) async throws -> GraphLocalProcessLaunchRecord {
        for _ in 0..<40 {
            await viewModel.step()
            if let record = try await launchStore.records()
                .filter({
                    $0.identity.runID == viewModel.inspection?.summary.runID
                        && $0.identity.nodeID == nodeID
                })
                .max(by: {
                    $0.identity.attemptOrdinal < $1.identity.attemptOrdinal
                }) {
                return record
            }
        }
        throw GraphLocalProcessRuntimeError.launchRecordMissing(nodeID)
    }

    @MainActor
    func launchAndFinish(
        nodeID: String,
        viewModel: GraphWorkspaceViewModel
    ) async throws {
        let record = try await launch(nodeID: nodeID, viewModel: viewModel)
        await executor.waitForExit(launchRecordID: record.id)
        for _ in 0..<10 {
            await viewModel.step()
            if let state = viewModel.inspection?.nodes.first(where: {
                $0.id == nodeID
            })?.persistedState, state.isTerminal {
                return
            }
        }
        throw GraphLocalProcessRuntimeError.launchRecordConflict(nodeID)
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
        let errorOutput = String(
            decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        XCTAssertEqual(process.terminationStatus, 0, errorOutput)
        XCTAssertTrue(output.contains(runID))
        XCTAssertTrue(output.contains(expectedState))
    }
}

private func appendArguments(
    _ arguments: [String],
    nodeID: String,
    document: inout GraphDefinitionDocument
) throws {
    guard let index = document.nodes.firstIndex(where: { $0.id == nodeID }) else {
        throw GraphDefinitionDocumentError.nodeNotFound(nodeID)
    }
    let source = try GraphLocalProcessSpecification(
        immutableSpecification: document.nodes[index].specification
    )
    document.nodes[index].specification = try GraphLocalProcessSpecification(
        executable: source.executable,
        arguments: source.arguments + arguments,
        workingDirectory: source.workingDirectory,
        environment: source.environment,
        inheritedEnvironment: source.inheritedEnvironment,
        stdin: source.stdin,
        outputArtifacts: source.outputArtifacts,
        retryableExitCodes: source.retryableExitCodes,
        logPolicy: source.logPolicy
    ).immutableSpecification()
    try document.validate()
}

private func replaceArguments(
    _ arguments: [String],
    nodeID: String,
    document: inout GraphDefinitionDocument
) throws {
    guard let index = document.nodes.firstIndex(where: { $0.id == nodeID }) else {
        throw GraphDefinitionDocumentError.nodeNotFound(nodeID)
    }
    let source = try GraphLocalProcessSpecification(
        immutableSpecification: document.nodes[index].specification
    )
    document.nodes[index].specification = try GraphLocalProcessSpecification(
        executable: source.executable,
        arguments: arguments,
        workingDirectory: source.workingDirectory,
        environment: source.environment,
        inheritedEnvironment: source.inheritedEnvironment,
        stdin: source.stdin,
        outputArtifacts: source.outputArtifacts,
        retryableExitCodes: source.retryableExitCodes,
        logPolicy: source.logPolicy
    ).immutableSpecification()
    try document.validate()
}
