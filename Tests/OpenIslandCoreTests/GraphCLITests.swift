import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphCLITests: XCTestCase {
    func testParserRecognizesMutationCommandsAndSafetyOptions() throws {
        let arguments = [
            ["graph", "create", "definition.json", "--run-id", "run", "--idempotency-key", "create"],
            ["graph", "start", "run", "--idempotency-key", "start"],
            ["graph", "cancel", "run", "--node", "node", "--idempotency-key", "cancel"],
            ["graph", "retry", "run", "node", "--idempotency-key", "retry", "--expected-version", "9", "--dry-run"],
            ["graph", "step", "run", "--dry-run"],
            ["graph", "run", "run", "--cycle-limit", "20"],
        ]

        let invocations = try arguments.map { arguments in
            guard case let .invocation(value) = try GraphCLIParser.parse(
                arguments
            ) else {
                throw GraphCLIArgumentError.invalid("expected invocation")
            }
            return value
        }

        XCTAssertEqual(
            invocations.map(\.command.name),
            [
                "graph.create", "graph.start", "graph.cancel", "graph.retry",
                "graph.step", "graph.run",
            ]
        )
        XCTAssertEqual(invocations[3].expectedVersion, 9)
        XCTAssertEqual(invocations[3].dryRun, true)
        XCTAssertEqual(invocations[5].cycleLimit, 20)
    }

    func testMutationJSONOutputUsesSameStableEnvelope() async throws {
        let store = InMemoryGraphExecutionEventStore()
        let stdout = LockedGraphCLISink()
        let stderr = LockedGraphCLISink()
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: store,
                snapshotStore: InMemoryGraphExecutionSnapshotStore()
            ),
            mutator: DefaultGraphMutationService(
                eventStore: store,
                readStore: store
            ),
            definitionLoader: FixedDefinitionLoader(
                definition: try loadCompendiumExecutableDefinition()
            ),
            stdout: stdout,
            stderr: stderr
        )

        let code = await runner.run(
            arguments: [
                "graph", "create", "ignored.json",
                "--run-id", "cli-run",
                "--idempotency-key", "cli-create",
                "--logical-time", "1970-01-01T08:20:00Z",
                "--output", "json",
                "--no-color",
            ]
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(stdout.consume().utf8)
            ) as? [String: Any]
        )

        XCTAssertEqual(code, .success)
        XCTAssertEqual(object["command"] as? String, "graph.create")
        XCTAssertEqual(object["resultCount"] as? Int, 1)
        XCTAssertTrue(stderr.consume().isEmpty)
    }

    func testRunJSONLPreservesTerminalGraphCompatibleRecords()
        async throws
    {
        let store = InMemoryGraphExecutionEventStore()
        let stdout = LockedGraphCLISink()
        let stderr = LockedGraphCLISink()
        let mutator = DefaultGraphMutationService(
            eventStore: store,
            readStore: store
        )
        let orchestrator = DefaultGraphOrchestrationService(
            eventStore: store,
            schedulingRepository: DefaultGraphSchedulingRepository(
                eventStore: store
            ),
            executorRepository: DefaultGraphExecutorRepository(
                eventStore: store
            ),
            executor: DeterministicGraphExecutor(
                script: try loadCompendiumDeterministicScript()
            )
        )
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: store,
                snapshotStore: InMemoryGraphExecutionSnapshotStore()
            ),
            mutator: mutator,
            orchestrator: orchestrator,
            definitionLoader: FixedDefinitionLoader(
                definition: try loadCompendiumExecutableDefinition()
            ),
            stdout: stdout,
            stderr: stderr,
            isOutputTTY: false
        )
        let createCode = await runner.run(arguments: [
                "graph", "create", "ignored",
                "--run-id", "cli-execution",
                "--idempotency-key", "create",
                "--logical-time", "1970-01-01T08:20:00Z",
                "--quiet",
            ])
        XCTAssertEqual(createCode, .success)
        let startCode = await runner.run(arguments: [
                "graph", "start", "cli-execution",
                "--idempotency-key", "start",
                "--logical-time", "1970-01-01T08:20:00Z",
                "--quiet",
            ])
        XCTAssertEqual(startCode, .success)
        let code = await runner.run(arguments: [
            "graph", "run", "cli-execution",
            "--cycle-limit", "30",
            "--logical-time", "1970-01-01T08:20:00Z",
            "--output", "jsonl",
            "--emit-completion-record",
            "--no-color",
        ])
        let lines = stdout.consume().split(separator: "\n")

        XCTAssertEqual(code, .success)
        XCTAssertGreaterThan(lines.count, 1)
        for line in lines {
            XCTAssertNoThrow(
                try JSONSerialization.jsonObject(
                    with: Data(line.utf8)
                )
            )
        }
        XCTAssertTrue(
            lines.last?.contains("\"recordType\":\"completion\"") == true
        )
        XCTAssertTrue(stderr.consume().isEmpty)

        let exportCode = await runner.run(arguments: [
            "graph", "export", "cli-execution",
            "--format", "jsonl",
            "--output", "jsonl",
        ])
        let exportLines = stdout.consume().split(separator: "\n")
        let exportRecords = try exportLines.map {
            try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: Data($0.utf8)
                ) as? [String: Any]
            )
        }
        let payloads = exportRecords.compactMap {
            $0["payload"] as? [String: Any]
        }

        XCTAssertEqual(exportCode, .success)
        XCTAssertEqual(
            payloads.filter { $0["kind"] as? String == "node" }.count,
            4
        )
        XCTAssertEqual(
            payloads.filter { $0["kind"] as? String == "artifact" }.count,
            5
        )
    }

    func testFailedRunJSONLCompletionReportsTerminalFailure()
        async throws
    {
        let store = InMemoryGraphExecutionEventStore()
        let stdout = LockedGraphCLISink()
        let stderr = LockedGraphCLISink()
        let mutator = DefaultGraphMutationService(
            eventStore: store,
            readStore: store
        )
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: store,
                snapshotStore: InMemoryGraphExecutionSnapshotStore()
            ),
            mutator: mutator,
            orchestrator: DefaultGraphOrchestrationService(
                eventStore: store,
                schedulingRepository: DefaultGraphSchedulingRepository(
                    eventStore: store
                ),
                executorRepository: DefaultGraphExecutorRepository(
                    eventStore: store
                ),
                executor: DeterministicGraphExecutor(
                    script: GraphDeterministicExecutionScript(
                        attempts: [
                            GraphDeterministicAttemptScript(
                                nodeID: "architect",
                                attemptOrdinal: 1,
                                terminalOutcome: .nonRetryableFailure,
                                failureCategory: "invalid_input"
                            ),
                        ]
                    )
                )
            ),
            definitionLoader: FixedDefinitionLoader(
                definition: try loadCompendiumExecutableDefinition()
            ),
            stdout: stdout,
            stderr: stderr,
            isOutputTTY: false
        )
        let createCode = await runner.run(arguments: [
            "graph", "create", "ignored",
            "--run-id", "failed-run",
            "--idempotency-key", "create-failed",
            "--logical-time", "1970-01-01T08:20:00Z",
            "--quiet",
        ])
        let startCode = await runner.run(arguments: [
            "graph", "start", "failed-run",
            "--idempotency-key", "start-failed",
            "--logical-time", "1970-01-01T08:20:00Z",
            "--quiet",
        ])

        XCTAssertEqual(createCode, .success)
        XCTAssertEqual(startCode, .success)

        let code = await runner.run(arguments: [
            "graph", "run", "failed-run",
            "--cycle-limit", "30",
            "--logical-time", "1970-01-01T08:20:00Z",
            "--output", "jsonl",
            "--emit-completion-record",
        ])
        let completion = try XCTUnwrap(
            stdout.consume().split(separator: "\n").last
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(completion.utf8)
            ) as? [String: Any]
        )

        XCTAssertEqual(code, .executionTerminalFailure)
        XCTAssertEqual(object["recordType"] as? String, "completion")
        XCTAssertEqual(
            object["status"] as? String,
            GraphCLIExitCode.executionTerminalFailure.category
        )
        XCTAssertEqual(
            object["exitCode"] as? Int,
            Int(GraphCLIExitCode.executionTerminalFailure.rawValue)
        )
        XCTAssertTrue(stderr.consume().isEmpty)
    }

    func testParserRecognizesEveryReadOnlyCommand() throws {
        let arguments = [
            ["graph", "list"],
            ["graph", "inspect", "run"],
            ["graph", "history", "run"],
            ["graph", "explain", "run", "node"],
            ["graph", "checkpoint", "list", "run"],
            ["graph", "replay", "run", "--dry-run"],
            ["graph", "diff", "run@2", "run#checkpoint"],
            ["graph", "export", "run", "--format", "mermaid"],
        ]

        let names = try arguments.map { arguments -> String in
            guard case let .invocation(invocation) =
                    try GraphCLIParser.parse(arguments) else {
                return "help"
            }
            return invocation.command.name
        }

        XCTAssertEqual(
            names,
            [
                "graph.list",
                "graph.inspect",
                "graph.history",
                "graph.explain",
                "graph.checkpoint.list",
                "graph.replay",
                "graph.diff",
                "graph.export",
            ]
        )
    }

    func testJSONOutputIsVersionedDeterministicAndANSIFree()
        async throws
    {
        let harness = try await makeHarness()
        let arguments = [
            "graph",
            "inspect",
            "run",
            "--output",
            "json",
            "--include-diagnostics",
        ]

        let firstCode = await harness.runner.run(arguments: arguments)
        XCTAssertEqual(firstCode, .success)
        let first = harness.stdout.consume()
        let secondCode = await harness.runner.run(arguments: arguments)
        XCTAssertEqual(secondCode, .success)
        let second = harness.stdout.consume()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(first.utf8)
            ) as? [String: Any]
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            object["schemaVersion"] as? Int,
            GraphCLIOutputSchema.currentVersion
        )
        XCTAssertEqual(object["command"] as? String, "graph.inspect")
        XCTAssertFalse(first.contains("\u{001B}["))
        XCTAssertTrue(harness.stderr.consume().isEmpty)
    }

    func testHistoryJSONLStreamsWithoutSkippingPageBoundary()
        async throws
    {
        let harness = try await makeHarness()
        let code = await harness.runner.run(
            arguments: [
                "graph",
                "history",
                "run",
                "--output",
                "jsonl",
                "--limit",
                "5",
                "--emit-completion-record",
            ]
        )
        let lines = harness.stdout.consume()
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(code, .success)
        XCTAssertEqual(lines.count, 6)
        let sequences = try lines.dropLast().map { line -> Int in
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: Data(line.utf8)
                ) as? [String: Any]
            )
            let payload = try XCTUnwrap(
                object["payload"] as? [String: Any]
            )
            return try XCTUnwrap(payload["streamSequence"] as? Int)
        }
        XCTAssertEqual(sequences, [1, 2, 3, 4, 5])
        XCTAssertTrue(lines.last?.contains("\"recordType\":\"completion\"") == true)
    }

    func testInvalidArgumentsUseStderrAndLeaveStdoutEmpty() async {
        let stdout = LockedGraphCLISink()
        let stderr = LockedGraphCLISink()
        let inspector = DefaultGraphTemporalInspector(
            readStore: InMemoryGraphExecutionEventStore(),
            snapshotStore: InMemoryGraphExecutionSnapshotStore()
        )
        let runner = GraphCLICommandRunner(
            inspector: inspector,
            stdout: stdout,
            stderr: stderr
        )

        let code = await runner.run(
            arguments: ["graph", "replay", "run"]
        )

        XCTAssertEqual(code, .invalidArguments)
        XCTAssertTrue(stdout.consume().isEmpty)
        XCTAssertTrue(
            stderr.consume().hasPrefix("error[invalid_arguments]:")
        )
    }

    func testMissingRunUsesStableNotFoundExitCode() async {
        let stdout = LockedGraphCLISink()
        let stderr = LockedGraphCLISink()
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: InMemoryGraphExecutionEventStore(),
                snapshotStore: InMemoryGraphExecutionSnapshotStore()
            ),
            stdout: stdout,
            stderr: stderr
        )

        let code = await runner.run(
            arguments: [
                "graph",
                "inspect",
                "missing",
                "--output",
                "json",
            ]
        )

        XCTAssertEqual(code, .notFound)
        XCTAssertTrue(stdout.consume().isEmpty)
        XCTAssertTrue(stderr.consume().contains("error[not_found]"))
    }

    func testMermaidExportIsDeterministicAndEscapesLabels()
        async throws
    {
        let store = InMemoryGraphExecutionEventStore()
        var events = graphCLIEvents()
        events[1] = graphTestEvent(
            id: "event-2",
            sequence: 2,
            nodeID: "node",
            payload: .nodeRegistered(
                GraphNodeRegisteredPayload(
                    title: "Node \"quoted\" <private>",
                    executorID: "executor"
                )
            )
        )
        _ = try await store.append(
            events,
            to: "run",
            expectedVersion: 0
        )
        let stdout = LockedGraphCLISink()
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: store,
                snapshotStore: InMemoryGraphExecutionSnapshotStore()
            ),
            stdout: stdout,
            stderr: LockedGraphCLISink()
        )
        let arguments = [
            "graph",
            "export",
            "run",
            "--format",
            "mermaid",
        ]

        let firstCode = await runner.run(arguments: arguments)
        XCTAssertEqual(firstCode, .success)
        let first = stdout.consume()
        let secondCode = await runner.run(arguments: arguments)
        XCTAssertEqual(secondCode, .success)
        let second = stdout.consume()

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("flowchart TD\n"))
        XCTAssertTrue(first.contains("&quot;quoted&quot;"))
        XCTAssertTrue(first.contains("&lt;private&gt;"))
        XCTAssertFalse(first.contains("secret"))
    }

    func testBrokenPipeStopsStructuredStreamingSuccessfully()
        async throws
    {
        let harness = try await makeHarness(
            stdout: BrokenPipeGraphCLISink(afterWrites: 2)
        )

        let code = await harness.runner.run(
            arguments: [
                "graph",
                "history",
                "run",
                "--output",
                "jsonl",
                "--limit",
                "5",
            ]
        )

        XCTAssertEqual(code, .success)
        XCTAssertTrue(harness.stderr.consume().isEmpty)
    }

    func testUnsupportedOutputSchemaUsesExitFour() async throws {
        let harness = try await makeHarness()

        let code = await harness.runner.run(
            arguments: [
                "graph",
                "list",
                "--output",
                "json",
                "--schema-version",
                String(GraphCLIOutputSchema.currentVersion + 1),
            ]
        )

        XCTAssertEqual(code, .incompatibleSchema)
        XCTAssertTrue(harness.stdout.consume().isEmpty)
        XCTAssertTrue(
            harness.stderr.consume().contains(
                "error[incompatible_schema]"
            )
        )
    }

    private func makeHarness(
        stdout: any GraphCLIOutputSink = LockedGraphCLISink()
    ) async throws -> CLIHarness {
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            graphCLIEvents(),
            to: "run",
            expectedVersion: 0
        )
        let readableStdout = stdout as? LockedGraphCLISink
            ?? LockedGraphCLISink()
        let stderr = LockedGraphCLISink()
        return CLIHarness(
            runner: GraphCLICommandRunner(
                inspector: DefaultGraphTemporalInspector(
                    readStore: store,
                    snapshotStore:
                        InMemoryGraphExecutionSnapshotStore(),
                    pageSize: 2
                ),
                stdout: stdout,
                stderr: stderr
            ),
            stdout: readableStdout,
            stderr: stderr
        )
    }
}

private struct CLIHarness {
    let runner: GraphCLICommandRunner
    let stdout: LockedGraphCLISink
    let stderr: LockedGraphCLISink
}

private struct FixedDefinitionLoader: GraphExecutableDefinitionLoading {
    let definition: GraphExecutableDefinition

    func load(path: String) throws -> GraphExecutableDefinition {
        definition
    }
}

private final class LockedGraphCLISink:
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
        let value = String(decoding: data, as: UTF8.self)
        data.removeAll(keepingCapacity: true)
        lock.unlock()
        return value
    }
}

private final class BrokenPipeGraphCLISink:
    GraphCLIOutputSink,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var writes = 0
    private let afterWrites: Int

    init(afterWrites: Int) {
        self.afterWrites = afterWrites
    }

    func write(_ data: Data) -> GraphCLIWriteResult {
        lock.lock()
        defer { lock.unlock() }
        writes += 1
        return writes > afterWrites ? .brokenPipe : .written
    }
}

private func graphCLIEvents() -> [GraphExecutionEventEnvelope] {
    [
        graphTestRunCreated(),
        graphTestNodeRegistered(),
        graphTestAttemptCreated(),
        graphTestAttemptStarting(),
        graphTestProcessObserved(),
    ]
}
