import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphCLIStreamingInvariantTests: XCTestCase {
    func testExitCodeContractIsStable() {
        XCTAssertEqual(GraphCLIExitCode.success.rawValue, 0)
        XCTAssertEqual(GraphCLIExitCode.invalidArguments.rawValue, 2)
        XCTAssertEqual(GraphCLIExitCode.notFound.rawValue, 3)
        XCTAssertEqual(GraphCLIExitCode.incompatibleSchema.rawValue, 4)
        XCTAssertEqual(GraphCLIExitCode.corruptHistory.rawValue, 5)
        XCTAssertEqual(GraphCLIExitCode.persistenceFailure.rawValue, 6)
        XCTAssertEqual(GraphCLIExitCode.evidenceUnavailable.rawValue, 7)
        XCTAssertEqual(GraphCLIExitCode.partialResult.rawValue, 8)
        XCTAssertEqual(GraphCLIExitCode.optimisticConflict.rawValue, 9)
        XCTAssertEqual(GraphCLIExitCode.policyDenied.rawValue, 10)
        XCTAssertEqual(GraphCLIExitCode.staleExecutor.rawValue, 11)
        XCTAssertEqual(GraphCLIExitCode.adapterUnavailable.rawValue, 12)
        XCTAssertEqual(GraphCLIExitCode.executionTerminalFailure.rawValue, 13)
        XCTAssertEqual(GraphCLIExitCode.cancellation.rawValue, 14)
        XCTAssertEqual(GraphCLIExitCode.interrupted.rawValue, 130)
    }

    func testEveryCommandSupportsTextJSONAndJSONL() async throws {
        let harness = try await commandHarness()
        let commands = [
            ["graph", "list"],
            ["graph", "inspect", "run", "--include-artifacts"],
            ["graph", "history", "run", "--limit", "5"],
            ["graph", "explain", "run", "node"],
            ["graph", "checkpoint", "list", "run"],
            [
                "graph",
                "replay",
                "run",
                "--dry-run",
                "--checkpoint",
                "before-start",
            ],
            ["graph", "diff", "run#before-start", "run"],
            ["graph", "export", "run", "--format", "json"],
        ]

        for command in commands {
            for mode in GraphCLIOutputMode.allCases {
                let arguments = command + ["--output", mode.rawValue]
                let code = await harness.runner.run(
                    arguments: arguments
                )
                let stdout = harness.stdout.consume()
                let stderr = harness.stderr.consume()

                XCTAssertEqual(
                    code,
                    .success,
                    "\(arguments.joined(separator: " ")) failed: \(stderr)"
                )
                XCTAssertFalse(stdout.isEmpty)
                XCTAssertTrue(stderr.isEmpty)
                XCTAssertFalse(stdout.contains("\u{001B}["))

                switch mode {
                case .text:
                    break
                case .json:
                    let object = try XCTUnwrap(
                        JSONSerialization.jsonObject(
                            with: Data(stdout.utf8)
                        ) as? [String: Any]
                    )
                    XCTAssertEqual(
                        object["schemaVersion"] as? Int,
                        GraphCLIOutputSchema.currentVersion
                    )
                case .jsonl:
                    for line in stdout.split(separator: "\n") {
                        let object = try XCTUnwrap(
                            JSONSerialization.jsonObject(
                                with: Data(line.utf8)
                            ) as? [String: Any]
                        )
                        XCTAssertEqual(
                            object["schemaVersion"] as? Int,
                            GraphCLIOutputSchema.currentVersion
                        )
                    }
                }
            }
        }
    }

    func testCLIHistoryFilteringAndLimitAreDeterministic()
        async throws
    {
        let harness = try await commandHarness()
        let arguments = [
            "graph",
            "history",
            "run",
            "--node",
            "node",
            "--attempt",
            "attempt",
            "--event-type",
            GraphExecutionEventType.attemptStarting.rawValue,
            "--after-sequence",
            "2",
            "--since",
            "1970-01-01T08:20:00Z",
            "--until",
            "1970-01-01T09:00:00Z",
            "--limit",
            "1",
            "--output",
            "json",
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
        let result = try XCTUnwrap(object["result"] as? [[String: Any]])

        XCTAssertEqual(first, second)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(
            result.first?["eventType"] as? String,
            GraphExecutionEventType.attemptStarting.rawValue
        )
    }

    func testCheckpointNotFoundUsesExitThree() async throws {
        let harness = try await commandHarness()
        let code = await harness.runner.run(
            arguments: [
                "graph",
                "replay",
                "run",
                "--dry-run",
                "--checkpoint",
                "missing",
                "--output",
                "json",
            ]
        )

        XCTAssertEqual(code, .notFound)
        XCTAssertTrue(harness.stdout.consume().isEmpty)
        XCTAssertTrue(
            harness.stderr.consume().contains("error[not_found]")
        )
    }

    func testQuietModeExecutesWithoutSuccessOutput() async throws {
        let harness = try await commandHarness()
        let code = await harness.runner.run(
            arguments: [
                "graph",
                "inspect",
                "run",
                "--quiet",
                "--output",
                "json",
            ]
        )

        XCTAssertEqual(code, .success)
        XCTAssertTrue(harness.stdout.consume().isEmpty)
        XCTAssertTrue(harness.stderr.consume().isEmpty)
    }

    func testCorruptHistoryUsesExitFiveAndKeepsStdoutClean()
        async
    {
        let stdout = InvariantOutputSink()
        let stderr = InvariantOutputSink()
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: CorruptGraphReadStore(),
                snapshotStore: EmptyGraphSnapshotReadStore()
            ),
            stdout: stdout,
            stderr: stderr
        )

        let code = await runner.run(
            arguments: [
                "graph",
                "replay",
                "run",
                "--dry-run",
                "--output",
                "json",
            ]
        )

        XCTAssertEqual(code, .corruptHistory)
        XCTAssertTrue(stdout.consume().isEmpty)
        XCTAssertTrue(
            stderr.consume().contains("error[corrupt_history]")
        )
    }

    func testPersistenceAndRequiredEvidenceExitCategories()
        async throws
    {
        let persistenceStdout = InvariantOutputSink()
        let persistenceStderr = InvariantOutputSink()
        let persistenceRunner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: FailingGraphReadStore(),
                snapshotStore: EmptyGraphSnapshotReadStore()
            ),
            stdout: persistenceStdout,
            stderr: persistenceStderr
        )
        let persistenceCode = await persistenceRunner.run(
            arguments: ["graph", "list", "--output", "json"]
        )

        XCTAssertEqual(persistenceCode, .persistenceFailure)
        XCTAssertTrue(persistenceStdout.consume().isEmpty)
        XCTAssertTrue(
            persistenceStderr.consume().contains(
                "error[persistence_failure]"
            )
        )

        let harness = try await commandHarness()
        let evidenceCode = await harness.runner.run(
            arguments: [
                "graph",
                "replay",
                "run",
                "--dry-run",
                "--require-live-evidence",
                "--output",
                "json",
            ]
        )

        XCTAssertEqual(evidenceCode, .evidenceUnavailable)
        XCTAssertTrue(harness.stdout.consume().isEmpty)
        XCTAssertTrue(
            harness.stderr.consume().contains(
                "error[evidence_unavailable]"
            )
        )
    }

    func testUnknownEventAndSnapshotBypassDiagnosticsReachCLI()
        async throws
    {
        let events = commandEvents() + [
            graphTestEvent(
                id: "future-event",
                sequence: 6,
                payloadVersion: 7,
                payload: .unknown(
                    eventType: "graph.future.observed",
                    body: .object(["mode": .string("future")])
                )
            ),
        ]
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            events,
            to: "run",
            expectedVersion: 0
        )
        let projection = try GraphExecutionProjector.replay(
            runID: "run",
            events: Array(events.prefix(3))
        ).projection
        let incompatible = graphTestSnapshot(
            for: projection,
            schemaVersion: GraphExecutionSchema.snapshotVersion + 1
        )
        let stdout = InvariantOutputSink()
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: store,
                snapshotStore: InMemoryGraphExecutionSnapshotStore(
                    snapshots: [incompatible]
                )
            ),
            stdout: stdout,
            stderr: InvariantOutputSink()
        )
        let arguments = [
            "graph",
            "replay",
            "run",
            "--dry-run",
            "--without-live-evidence",
            "--include-diagnostics",
            "--output",
            "json",
        ]

        let firstCode = await runner.run(arguments: arguments)
        XCTAssertEqual(firstCode, .success)
        let first = stdout.consume()
        let secondCode = await runner.run(arguments: arguments)
        XCTAssertEqual(secondCode, .success)
        let second = stdout.consume()

        XCTAssertEqual(first, second)
        XCTAssertTrue(
            first.contains("\"snapshotDisposition\":\"incompatible\"")
        )
        XCTAssertTrue(first.contains("\"category\":\"unknownEvent\""))
        XCTAssertTrue(first.contains("graph.future.observed"))
    }

    func testDiffOutputIsDeterministicAcrossRepeatedInvocations()
        async throws
    {
        let harness = try await commandHarness()
        let arguments = [
            "graph",
            "diff",
            "run@3",
            "run",
            "--output",
            "json",
        ]

        let firstCode = await harness.runner.run(arguments: arguments)
        XCTAssertEqual(firstCode, .success)
        let first = harness.stdout.consume()
        let secondCode = await harness.runner.run(arguments: arguments)
        XCTAssertEqual(secondCode, .success)
        let second = harness.stdout.consume()

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.contains("\"category\":\"attempt\""))
        XCTAssertFalse(first.contains("updatedAt"))
    }

    func testArtifactMetadataIsSafeThroughCLI() async throws {
        let artifact = GraphArtifactReference(
            id: "artifact",
            contentDigest: GraphContentDigest(
                algorithm: "sha256",
                value: "digest"
            ),
            mediaType: "text/markdown",
            logicalRole: "compendium",
            producingRunID: "run",
            producingNodeID: "node",
            producingAttemptID: "attempt",
            createdAt: graphTestTime.addingTimeInterval(5),
            storage: GraphArtifactStorageLocator(
                scheme: "https",
                opaqueReference:
                    "https://user:password@example.invalid/private?token=secret"
            ),
            sensitivity: .restricted
        )
        let events = commandEvents() + [
            graphTestEvent(
                id: "artifact-event",
                sequence: 6,
                nodeID: "node",
                attemptID: "attempt",
                payload: .artifactRecorded(
                    GraphArtifactRecordedPayload(artifact: artifact)
                )
            ),
        ]
        let harness = try await commandHarness(events: events)

        let code = await harness.runner.run(
            arguments: [
                "graph",
                "inspect",
                "run",
                "--include-artifacts",
                "--output",
                "json",
            ]
        )
        XCTAssertEqual(code, .success)
        let output = harness.stdout.consume()

        XCTAssertTrue(output.contains("\"id\":\"artifact\""))
        XCTAssertTrue(
            output.contains("storage.opaqueReference")
        )
        XCTAssertFalse(output.contains("password"))
        XCTAssertFalse(output.contains("token=secret"))
        XCTAssertFalse(output.contains("/private"))
    }

    func testLargeHistoryJSONLWritesOneBoundedRecordAtATime()
        async throws
    {
        let eventCount = 5_000
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            largeHistoryEvents(count: eventCount),
            to: "large-run",
            expectedVersion: 0
        )
        let output = CountingGraphCLIOutputSink()
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: store,
                snapshotStore: InMemoryGraphExecutionSnapshotStore(),
                pageSize: 64
            ),
            stdout: output,
            stderr: InvariantOutputSink(),
            isOutputTTY: false
        )

        let code = await runner.run(
            arguments: [
                "graph",
                "history",
                "large-run",
                "--output",
                "jsonl",
                "--limit",
                String(eventCount),
            ]
        )

        XCTAssertEqual(code, .success)
        XCTAssertEqual(output.writeCount, eventCount)
        XCTAssertLessThan(output.maximumWriteSize, 4_096)
    }

    func testRealUnixPipeAndBrokenPipeBehavior() async throws {
        let eventCount = 250
        let fixture = try await binaryFixture(
            events: largeHistoryEvents(count: eventCount)
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let countResult = try runShell(
            """
            OPENISLAND_GRAPH_DATABASE_PATH=\(shellQuote(fixture.database.path)) \
            \(shellQuote(fixture.binary.path)) graph history large-run --output jsonl --limit \(eventCount) \
            | /usr/bin/wc -l
            """
        )
        let brokenPipeResult = try runShell(
            """
            set -o pipefail
            OPENISLAND_GRAPH_DATABASE_PATH=\(shellQuote(fixture.database.path)) \
            \(shellQuote(fixture.binary.path)) graph history large-run --output jsonl --limit \(eventCount) \
            | /usr/bin/head -n 1
            """
        )

        XCTAssertEqual(countResult.status, 0, countResult.stderr)
        XCTAssertEqual(
            countResult.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines),
            String(eventCount)
        )
        XCTAssertEqual(
            brokenPipeResult.status,
            0,
            brokenPipeResult.stderr
        )
        XCTAssertEqual(
            brokenPipeResult.stdout.split(separator: "\n").count,
            1
        )
    }

    func testSIGINTUsesStableExit130() async throws {
        let fixture = try await binaryFixture(
            events: largeHistoryEvents(count: 10_000)
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let process = Process()
        let blockedOutput = Pipe()
        process.executableURL = fixture.binary
        process.arguments = [
            "graph",
            "history",
            "large-run",
            "--output",
            "jsonl",
            "--limit",
            "10000",
        ]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["OPENISLAND_GRAPH_DATABASE_PATH": fixture.database.path]
        ) { _, new in new }
        process.standardOutput = blockedOutput
        process.standardError = FileHandle.nullDevice

        try process.run()
        try await Task.sleep(for: .milliseconds(150))
        process.interrupt()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 130)
    }

    func testStaleCompendiumFixtureReconcilesThroughCLI()
        async throws
    {
        let fixture = try loadStaleCompendiumFixture()
        let events = staleCompendiumEvents(from: fixture)
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            events,
            to: fixture.run.id,
            expectedVersion: 0
        )
        let stdout = InvariantOutputSink()
        let runner = GraphCLICommandRunner(
            inspector: DefaultGraphTemporalInspector(
                readStore: store,
                snapshotStore: InMemoryGraphExecutionSnapshotStore()
            ),
            stdout: stdout,
            stderr: InvariantOutputSink()
        )

        let code = await runner.run(
            arguments: [
                "graph",
                "inspect",
                fixture.run.id,
                "--output",
                "json",
            ]
        )
        XCTAssertEqual(code, .success)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(stdout.consume().utf8)
            ) as? [String: Any]
        )
        let result = try XCTUnwrap(object["result"] as? [String: Any])
        let nodes = try XCTUnwrap(result["nodes"] as? [[String: Any]])
        let states: [String: String] = Dictionary(
            uniqueKeysWithValues: nodes.compactMap { node in
                guard let id = node["id"] as? String,
                      let state = node["reconciledState"] as? String
                else {
                    return nil
                }
                return (id, state)
            }
        )

        XCTAssertEqual(states["architect"], "interrupted")
        XCTAssertEqual(states["researcher"], "orphaned")
        XCTAssertEqual(states["graph"], "blocked")
        XCTAssertEqual(states["reviewer"], "blocked")
    }

    private func commandHarness(
        events: [GraphExecutionEventEnvelope] = commandEvents()
    ) async throws -> InvariantHarness {
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            events,
            to: "run",
            expectedVersion: 0
        )
        let prefix = try GraphExecutionProjector.replay(
            runID: "run",
            events: Array(events.prefix(3))
        ).projection
        var checkpointProjection = prefix
        checkpointProjection.namedCheckpoints = [
            GraphCheckpointReference(
                checkpointID: "before-start",
                runID: "run",
                streamVersion: 3,
                namespace: "root"
            ),
        ]
        let stdout = InvariantOutputSink()
        let stderr = InvariantOutputSink()
        return InvariantHarness(
            runner: GraphCLICommandRunner(
                inspector: DefaultGraphTemporalInspector(
                    readStore: store,
                    snapshotStore:
                        InMemoryGraphExecutionSnapshotStore(
                            snapshots: [
                                graphTestSnapshot(
                                    for: checkpointProjection
                                ),
                            ]
                        ),
                    pageSize: 2
                ),
                stdout: stdout,
                stderr: stderr
            ),
            stdout: stdout,
            stderr: stderr
        )
    }

    private func binaryFixture(
        events: [GraphExecutionEventEnvelope]
    ) async throws -> BinaryFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let database = directory.appendingPathComponent("graph.sqlite")
        let store = try SQLiteGraphExecutionStore(
            databasePath: database.path
        )
        _ = try await store.append(
            events,
            to: "large-run",
            expectedVersion: 0
        )
        return BinaryFixture(
            directory: directory,
            database: database,
            binary: try locateOpenIslandBinary()
        )
    }

    private func locateOpenIslandBinary() throws -> URL {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/debug/openisland"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(
                    ".build/arm64-apple-macosx/debug/openisland"
                ),
        ]
        return try XCTUnwrap(
            candidates.first {
                FileManager.default.isExecutableFile(atPath: $0.path)
            }
        )
    }

    private func runShell(
        _ command: String
    ) throws -> (
        status: Int32,
        stdout: String,
        stderr: String
    ) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: outputData, as: UTF8.self),
            String(decoding: errorData, as: UTF8.self)
        )
    }
}

private struct InvariantHarness {
    let runner: GraphCLICommandRunner
    let stdout: InvariantOutputSink
    let stderr: InvariantOutputSink
}

private struct BinaryFixture {
    let directory: URL
    let database: URL
    let binary: URL
}

private final class InvariantOutputSink:
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
        data.removeAll(keepingCapacity: true)
        lock.unlock()
        return result
    }
}

private final class CountingGraphCLIOutputSink:
    GraphCLIOutputSink,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var count = 0
    private var maximum = 0

    var writeCount: Int {
        lock.lock()
        let result = count
        lock.unlock()
        return result
    }

    var maximumWriteSize: Int {
        lock.lock()
        let result = maximum
        lock.unlock()
        return result
    }

    func write(_ data: Data) -> GraphCLIWriteResult {
        lock.lock()
        count += 1
        maximum = max(maximum, data.count)
        lock.unlock()
        return .written
    }
}

private struct CorruptGraphReadStore: GraphExecutionReadStore {
    func listStreams() async throws -> [GraphExecutionStreamDescriptor] {
        [GraphExecutionStreamDescriptor(runID: "run", currentVersion: 3)]
    }

    func streamDescriptor(
        runID: String
    ) async throws -> GraphExecutionStreamDescriptor? {
        runID == "run"
            ? GraphExecutionStreamDescriptor(
                runID: "run",
                currentVersion: 3
            )
            : nil
    }

    func readPage(
        runID: String,
        afterVersion: UInt64,
        limit: Int
    ) async throws -> GraphExecutionEventPage {
        GraphExecutionEventPage(
            runID: "run",
            afterVersion: 0,
            currentVersion: 3,
            events: [
                graphTestRunCreated(),
                graphTestNodeRegistered(sequence: 3),
            ],
            hasMore: false
        )
    }
}

private struct EmptyGraphSnapshotReadStore:
    GraphExecutionSnapshotReadStore
{
    func loadLatest(
        runID: String,
        throughVersion: UInt64
    ) async throws -> GraphExecutionSnapshot? {
        nil
    }
}

private struct FailingGraphReadStore: GraphExecutionReadStore {
    func listStreams() async throws -> [GraphExecutionStreamDescriptor] {
        throw GraphExecutionPersistenceError.storageFailure(
            "fixture unavailable"
        )
    }

    func streamDescriptor(
        runID: String
    ) async throws -> GraphExecutionStreamDescriptor? {
        throw GraphExecutionPersistenceError.storageFailure(
            "fixture unavailable"
        )
    }

    func readPage(
        runID: String,
        afterVersion: UInt64,
        limit: Int
    ) async throws -> GraphExecutionEventPage {
        throw GraphExecutionPersistenceError.storageFailure(
            "fixture unavailable"
        )
    }
}

private func commandEvents() -> [GraphExecutionEventEnvelope] {
    [
        graphTestRunCreated(),
        graphTestNodeRegistered(),
        graphTestAttemptCreated(),
        graphTestAttemptStarting(),
        graphTestProcessObserved(),
    ]
}

private func largeHistoryEvents(
    count: Int
) -> [GraphExecutionEventEnvelope] {
    guard count >= 1 else {
        return []
    }
    let producer = GraphExecutionProducer(
        id: "large-history-test",
        kind: .test
    )
    var events = [
        GraphExecutionEventEnvelope(
            id: "large-1",
            runID: "large-run",
            streamSequence: 1,
            occurredAt: graphTestTime,
            recordedAt: graphTestTime,
            producer: producer,
            payload: .runCreated(
                GraphRunCreatedPayload(
                    graphID: "large",
                    graphDefinitionVersion: "1",
                    graphDefinitionDigest: graphTestDigest,
                    nodeIDs: []
                )
            )
        ),
    ]
    guard count > 1 else {
        return events
    }
    for sequence in 2...count {
        events.append(
            GraphExecutionEventEnvelope(
                id: "large-\(sequence)",
                runID: "large-run",
                streamSequence: UInt64(sequence),
                occurredAt: graphTestTime.addingTimeInterval(
                    Double(sequence)
                ),
                recordedAt: graphTestTime.addingTimeInterval(
                    Double(sequence)
                ),
                producer: producer,
                payload: .unknown(
                    eventType: "graph.test.stream_record",
                    body: .object([
                        "sequence": .number(Double(sequence)),
                    ])
                )
            )
        )
    }
    return events
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
