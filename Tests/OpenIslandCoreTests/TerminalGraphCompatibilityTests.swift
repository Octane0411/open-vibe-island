import Foundation
import XCTest
@testable import OpenIslandCore

final class TerminalGraphCompatibilityTests: XCTestCase {
    func testAbsentTerminalGraphEnvironmentIsOptional() {
        let context = TerminalGraphEnvironmentDiscovery.discover(
            environment: ["PATH": "/usr/bin"]
        )

        XCTAssertFalse(context.detected)
        XCTAssertNil(context.nodeID)
        XCTAssertTrue(context.values.isEmpty)
    }

    func testRepresentativeEnvironmentIsSanitizedAndPreserved() {
        let context = TerminalGraphEnvironmentDiscovery.discover(
            environment: [
                "TG_NODE_ID": "node-7",
                "TG_WORKSPACE_ID": "workspace",
                "TG_PROJECT_ROOT": "/tmp/project/../project",
                "TG_MCP_URL": "http://user:password@127.0.0.1:4317/api?token=secret",
                "TG_FUTURE_MODE": "spatial",
                "TG_API_TOKEN": "must-not-escape",
            ]
        )
        let values = Dictionary(
            uniqueKeysWithValues: context.values.map {
                ($0.name, $0)
            }
        )

        XCTAssertTrue(context.detected)
        XCTAssertEqual(context.nodeID, "node-7")
        XCTAssertEqual(context.workspaceID, "workspace")
        XCTAssertEqual(context.projectRoot, "/tmp/project")
        XCTAssertEqual(
            values["TG_MCP_URL"]?.value,
            "http://127.0.0.1:4317/api"
        )
        XCTAssertEqual(values["TG_FUTURE_MODE"]?.value, "spatial")
        XCTAssertNil(values["TG_API_TOKEN"]?.value)
        XCTAssertTrue(values["TG_API_TOKEN"]?.redacted == true)
    }

    func testMalformedEnvironmentValuesAreBoundedWithoutFailure() {
        let context = TerminalGraphEnvironmentDiscovery.discover(
            environment: [
                "TG_MCP_URL": "not a URL with credentials",
                "TG_FUTURE_VALUE": String(repeating: "x", count: 2_000),
                "TG_GROUP_ID": "group\nwith-control",
            ]
        )
        let values = Dictionary(
            uniqueKeysWithValues: context.values.map {
                ($0.name, $0)
            }
        )

        XCTAssertTrue(context.detected)
        XCTAssertNil(values["TG_MCP_URL"]?.value)
        XCTAssertNil(values["TG_FUTURE_VALUE"]?.value)
        XCTAssertEqual(values["TG_GROUP_ID"]?.value, "group with-control")
    }

    func testGitContextDistinguishesIdentityAndRedactedPaths() {
        let resolver = GitGraphRepositoryContextResolver()
        let directory = FileManager.default.currentDirectoryPath
        let visible = resolver.resolve(
            workingDirectory: directory,
            exposePaths: true,
            externalContextID: "workspace",
            sourceProjectAssociation: "project"
        )
        let redacted = resolver.resolve(
            workingDirectory: directory,
            exposePaths: false,
            externalContextID: "workspace",
            sourceProjectAssociation: "project"
        )

        XCTAssertNotNil(visible)
        XCTAssertEqual(
            visible?.repositoryIdentity,
            redacted?.repositoryIdentity
        )
        XCTAssertNotNil(visible?.canonicalProjectRoot.value)
        XCTAssertNotNil(visible?.worktreeRoot.value)
        XCTAssertNil(redacted?.canonicalProjectRoot.value)
        XCTAssertTrue(redacted?.canonicalProjectRoot.redacted == true)
        XCTAssertFalse(visible?.commit?.isEmpty ?? true)
    }

    func testMultiProjectWorkspaceRepresentationIsDeterministic() {
        let first = repositoryContext(
            identity: "repository-b",
            path: "/tmp/b"
        )
        let second = repositoryContext(
            identity: "repository-a",
            path: "/tmp/a"
        )
        let workspace = GraphWorkspaceContext(
            workspaceID: "workspace",
            externalContextID: "external",
            selectedRepositoryIdentity: "repository-b",
            repositories: [first, second]
        )

        XCTAssertEqual(
            workspace.repositories.map(\.repositoryIdentity),
            ["repository-a", "repository-b"]
        )
        XCTAssertEqual(
            workspace.selectedRepositoryIdentity,
            "repository-b"
        )
    }

    func testWorkspacePlanUsesStableMappingsAndNeutralPorts()
        async throws
    {
        let inspection = try await inspectionFixture()
        let workspace = GraphWorkspaceContext(
            workspaceID: "workspace",
            externalContextID: "external",
            selectedRepositoryIdentity: "repository",
            repositories: [
                repositoryContext(
                    identity: "repository",
                    path: "/tmp/worktree"
                ),
            ]
        )

        let first = GraphTerminalWorkspacePlanBuilder.build(
            inspection: inspection,
            workspaceContext: workspace
        )
        let second = GraphTerminalWorkspacePlanBuilder.build(
            inspection: inspection,
            workspaceContext: workspace
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.authority, "openisland")
        XCTAssertEqual(first.terminals.count, 1)
        XCTAssertEqual(
            first.terminals.first?.command,
            [
                "openisland",
                "graph",
                "inspect",
                "run",
                "--node",
                "node",
                "--output",
                "json",
            ]
        )
        XCTAssertTrue(
            first.terminals.first?.ports.contains {
                $0.kind == .stream
                    && $0.semanticType == .eventHistory
            } == true
        )
        XCTAssertFalse(
            first.terminals.first?.ports.contains {
                $0.id.contains("/tmp")
            } == true
        )
    }

    func testSynchronizationRequestSortsExternalMappings() async throws {
        let plan = GraphTerminalWorkspacePlanBuilder.build(
            inspection: try await inspectionFixture(),
            workspaceContext: nil
        )
        let request = GraphVisualizationSynchronizationRequest(
            plan: plan,
            existingMappings: [
                GraphExternalEntityMapping(
                    openIslandMappingKey: "z",
                    externalEntityID: "external-z"
                ),
                GraphExternalEntityMapping(
                    openIslandMappingKey: "a",
                    externalEntityID: "external-a"
                ),
            ]
        )

        XCTAssertEqual(
            request.existingMappings.map(\.openIslandMappingKey),
            ["a", "z"]
        )
        XCTAssertEqual(
            request.plan.graphRunID,
            "run"
        )
    }

    func testTerminalWorkspacePlanExportIncludesContextAndNoSecrets()
        async throws
    {
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            terminalGraphEvents(),
            to: "run",
            expectedVersion: 0
        )
        let stdout = CompatibilityOutputSink()
        let context = GraphCLIExecutionContext(
            terminalGraph: TerminalGraphEnvironmentDiscovery.discover(
                environment: [
                    "TG_NODE_ID": "terminal-node",
                    "TG_API_TOKEN": "private-token",
                ]
            ),
            workspace: nil
        )
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: store,
                snapshotStore: InMemoryGraphExecutionSnapshotStore()
            ),
            stdout: stdout,
            stderr: CompatibilityOutputSink(),
            context: context
        )

        let code = await runner.run(
            arguments: [
                "graph",
                "export",
                "run",
                "--format",
                "terminal-workspace-plan",
            ]
        )
        let output = stdout.consume()

        XCTAssertEqual(code, .success)
        XCTAssertTrue(
            output.contains("\"authority\":\"openisland\"")
        )
        XCTAssertTrue(
            output.contains("\"recordType\"") == false
        )
        XCTAssertTrue(
            output.contains("\"terminalGraph\"")
        )
        XCTAssertFalse(output.contains("private-token"))
    }

    func testCLITelemetryIsBoundedAndPrivacySafe() async throws {
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            terminalGraphEvents(),
            to: "run",
            expectedVersion: 0
        )
        let telemetry = CapturingGraphCLITelemetrySink()
        let context = GraphCLIExecutionContext(
            terminalGraph: TerminalGraphEnvironmentDiscovery.discover(
                environment: [
                    "TG_NODE_ID": "node",
                    "TG_PROJECT_ROOT": "/private/project",
                    "TG_API_TOKEN": "private-token",
                ]
            ),
            workspace: nil
        )
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: store,
                snapshotStore: InMemoryGraphExecutionSnapshotStore()
            ),
            stdout: CompatibilityOutputSink(),
            stderr: CompatibilityOutputSink(),
            context: context,
            telemetry: telemetry,
            clock: SequenceGraphCLIClock(
                values: [1_000_000, 6_000_000]
            ),
            isOutputTTY: false
        )

        let code = await runner.run(
            arguments: [
                "graph",
                "history",
                "run",
                "--output",
                "jsonl",
                "--limit",
                "2",
            ]
        )
        let record = try XCTUnwrap(telemetry.records().first)
        let encoded = String(
            decoding: try JSONEncoder().encode(record),
            as: UTF8.self
        )

        XCTAssertEqual(code, .success)
        XCTAssertEqual(record.command, "graph.history")
        XCTAssertEqual(record.outputMode, .jsonl)
        XCTAssertEqual(record.durationMilliseconds, 5)
        XCTAssertEqual(record.eventCount, 2)
        XCTAssertTrue(record.terminalGraphDetected)
        XCTAssertTrue(record.pipedOutput)
        XCTAssertFalse(encoded.contains("private-token"))
        XCTAssertFalse(encoded.contains("/private/project"))
        XCTAssertFalse(encoded.contains("--limit"))
    }

    private func inspectionFixture() async throws -> GraphRunInspection {
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            terminalGraphEvents(),
            to: "run",
            expectedVersion: 0
        )
        return try await DefaultGraphTemporalInspector(
            readStore: store,
            snapshotStore: InMemoryGraphExecutionSnapshotStore()
        ).inspect(
            runID: "run",
            includeArtifacts: true,
            includeDiagnostics: false
        )
    }

    private func repositoryContext(
        identity: String,
        path: String
    ) -> GraphRepositoryContext {
        GraphRepositoryContext(
            repositoryIdentity: identity,
            canonicalProjectRoot: GraphRepositoryPath(
                value: path,
                redacted: false
            ),
            worktreeRoot: GraphRepositoryPath(
                value: path,
                redacted: false
            ),
            branch: "feature",
            commit: "abc",
            isDirty: false,
            externalContextID: "external",
            sourceProjectAssociation: identity
        )
    }
}

private final class CompatibilityOutputSink:
    GraphCLIOutputSink,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var data = Data()

    func write(_ data: Data) -> GraphCLIWriteResult {
        lock.lock()
        self.data.append(data)
        lock.unlock()
        return .written
    }

    func consume() -> String {
        lock.lock()
        let result = String(decoding: data, as: UTF8.self)
        data.removeAll()
        lock.unlock()
        return result
    }
}

private final class CapturingGraphCLITelemetrySink:
    GraphCLITelemetrySink,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage: [GraphCLITelemetryRecord] = []

    func record(_ record: GraphCLITelemetryRecord) {
        lock.lock()
        storage.append(record)
        lock.unlock()
    }

    func records() -> [GraphCLITelemetryRecord] {
        lock.lock()
        let result = storage
        lock.unlock()
        return result
    }
}

private final class SequenceGraphCLIClock:
    GraphCLIMonotonicClock,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [UInt64]

    init(values: [UInt64]) {
        self.values = values
    }

    func nowNanoseconds() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? 0 : values.removeFirst()
    }
}

private func terminalGraphEvents() -> [GraphExecutionEventEnvelope] {
    [
        graphTestRunCreated(),
        graphTestNodeRegistered(),
        graphTestAttemptCreated(),
        graphTestAttemptStarting(),
    ]
}
