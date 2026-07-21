import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphCLITests: XCTestCase {
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
