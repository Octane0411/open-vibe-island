import Foundation
import XCTest
@testable import OpenIslandCore

final class SupervisedLocalProcessExecutorTests: XCTestCase {
    func testSuccessfulExecutionCapturesBothStreamsAndDeclaredArtifact() async throws {
        let fixture = try LocalProcessTestFixture()
        let context = try fixture.context(
            arguments: [
                "--role", "architect",
                "--output", "${artifact:node_output}",
                "--stderr",
            ],
            outputs: [fixture.output(role: .nodeOutput)]
        )
        let executor = fixture.executor()
        let prepared = try await executor.prepare(.init(context: context))
        XCTAssertEqual(prepared.observation.status, .accepted)
        let started = try await executor.start(.init(context: context))
            .observation
        XCTAssertEqual(started.status, .started)
        let launchID = try XCTUnwrap(started.processIdentity?.launchID)
        await executor.waitForExit(launchRecordID: launchID)
        let observed = try await executor.observe(.init(context: context))
            .observation
        XCTAssertEqual(observed.status, .succeeded)
        let collected = try await executor.collectResult(.init(context: context))
            .observation
        XCTAssertEqual(collected.status, .succeeded)
        XCTAssertEqual(
            Set(collected.artifacts.map(\.role)),
            Set([.nodeOutput, .executionLog])
        )
        let logs = try await executor.logs(launchRecordID: launchID)
        XCTAssertTrue(logs.entries.contains { $0.channel == .stdout })
        XCTAssertTrue(logs.entries.contains { $0.channel == .stderr })
        XCTAssertTrue(logs.entries.map(\.text).joined().contains("architect"))
        let output = try Data(
            contentsOf: fixture.workspace
                .appendingPathComponent("artifacts/output.json")
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
        XCTAssertEqual(json["agent"] as? String, "architect")
    }

    func testNonzeroExitIsClassifiedByRetryPolicy() async throws {
        let fixture = try LocalProcessTestFixture()
        let context = try fixture.context(
            arguments: ["--failure-code", "23"],
            retryableExitCodes: [23]
        )
        let executor = fixture.executor()
        _ = try await executor.prepare(.init(context: context))
        let started = try await executor.start(.init(context: context)).observation
        await executor.waitForExit(
            launchRecordID: try XCTUnwrap(started.processIdentity?.launchID)
        )
        let observed = try await executor.observe(.init(context: context))
            .observation
        XCTAssertEqual(observed.status, .failed)
        XCTAssertEqual(observed.failure?.category, "process_exit_23")
        XCTAssertEqual(observed.failure?.retryable, true)
    }

    func testCancellationSignalsOnlyMatchingProcessAndCleanupIsIdempotent() async throws {
        let fixture = try LocalProcessTestFixture()
        let context = try fixture.context(
            arguments: ["--wait-for-cancellation"]
        )
        let executor = fixture.executor()
        _ = try await executor.prepare(.init(context: context))
        let started = try await executor.start(.init(context: context)).observation
        let launchID = try XCTUnwrap(started.processIdentity?.launchID)
        let first = try await executor.requestCancellation(
            .init(context: context, cancellationRequestID: "cancel")
        ).observation
        XCTAssertTrue([.stillRunning, .cancelled].contains(first.status))
        await executor.waitForExit(launchRecordID: launchID)
        let second = try await executor.requestCancellation(
            .init(context: context, cancellationRequestID: "cancel")
        ).observation
        XCTAssertEqual(second.status, .cancelled)
        let firstCleanup = try await executor.cleanup(.init(context: context))
        XCTAssertEqual(firstCleanup.observation.status, .accepted)
        let secondCleanup = try await executor.cleanup(.init(context: context))
        XCTAssertEqual(secondCleanup.observation.status, .accepted)
    }

    func testCancellationEscalatesAtLogicalDeadline() async throws {
        let fixture = try LocalProcessTestFixture()
        var context = try fixture.context(
            arguments: ["--wait-for-cancellation", "--ignore-term"],
            cancellationAcknowledgementSeconds: 1
        )
        let executor = fixture.executor()
        _ = try await executor.prepare(.init(context: context))
        let started = try await executor.start(.init(context: context)).observation
        let launchID = try XCTUnwrap(started.processIdentity?.launchID)
        let becameReady = try await executor.waitForLog(
            launchRecordID: launchID,
            containing: "waiting for cancellation"
        )
        XCTAssertTrue(becameReady)
        _ = try await executor.requestCancellation(
            .init(context: context, cancellationRequestID: "cancel")
        )
        context = fixture.replacingTime(
            context,
            with: context.logicalTime.addingTimeInterval(2)
        )
        let response = try await executor.requestCancellation(
            .init(context: context, cancellationRequestID: "cancel")
        ).observation
        XCTAssertTrue([.stillRunning, .cancelled].contains(response.status))
        await executor.waitForExit(launchRecordID: launchID)
        let stored = try await executor.launchRecord(
            id: launchID
        )
        let record = try XCTUnwrap(stored)
        XCTAssertNotNil(record.cancellationEscalatedAt)
    }

    func testDuplicateStartReturnsSameDurableProcess() async throws {
        let fixture = try LocalProcessTestFixture()
        let context = try fixture.context(
            arguments: ["--wait-for-cancellation"]
        )
        let executor = fixture.executor()
        _ = try await executor.prepare(.init(context: context))
        let first = try await executor.start(.init(context: context)).observation
        let second = try await executor.start(.init(context: context)).observation
        XCTAssertEqual(first.processIdentity, second.processIdentity)
        _ = try await executor.cleanup(.init(context: context))
    }

    func testRecoveryAfterAcceptedSpawnUsesDurableIdentity() async throws {
        let fixture = try LocalProcessTestFixture()
        let context = try fixture.context(
            arguments: ["--wait-for-cancellation"]
        )
        let crashing = fixture.executor(crashPoint: .afterSpawnAcceptance)
        _ = try await crashing.prepare(.init(context: context))
        do {
            _ = try await crashing.start(.init(context: context))
            XCTFail("Expected the injected crash boundary")
        } catch GraphExecutorAdapterError.simulatedCrash {
        }
        let restarted = fixture.executor()
        let recovered = try await restarted.recover(.init(context: context))
            .observation
        XCTAssertEqual(recovered.status, .started)
        XCTAssertNotNil(recovered.processIdentity?.processID)
        _ = try await restarted.cleanup(.init(context: context))
    }

    func testCrashBeforeSpawnRecoversByLaunchingExactlyOnce() async throws {
        let fixture = try LocalProcessTestFixture()
        let context = try fixture.context()
        let crashing = fixture.executor(crashPoint: .beforeSpawn)
        _ = try await crashing.prepare(.init(context: context))
        do {
            _ = try await crashing.start(.init(context: context))
            XCTFail("Expected the injected crash boundary")
        } catch GraphExecutorAdapterError.simulatedCrash {
        }
        let restarted = fixture.executor()
        let recovered = try await restarted.recover(.init(context: context))
            .observation
        XCTAssertEqual(recovered.status, .started)
        await restarted.waitForExit(
            launchRecordID: try XCTUnwrap(recovered.processIdentity?.launchID)
        )
    }

    func testRecoveryAfterProcessExitDoesNotRelaunch() async throws {
        let fixture = try LocalProcessTestFixture()
        let context = try fixture.context(arguments: ["--role", "architect"])
        let original = fixture.executor()
        _ = try await original.prepare(.init(context: context))
        let started = try await original.start(.init(context: context))
            .observation
        let launchID = try XCTUnwrap(started.processIdentity?.launchID)
        await original.waitForExit(launchRecordID: launchID)

        let restarted = fixture.executor()
        let recovered = try await restarted.recover(.init(context: context))
            .observation
        let records = try await fixture.store.records()

        XCTAssertEqual(recovered.status, .succeeded)
        XCTAssertEqual(recovered.processIdentity?.launchID, launchID)
        XCTAssertEqual(records.count, 1)
    }

    func testStaleLeaseGenerationIsRejected() async throws {
        let fixture = try LocalProcessTestFixture()
        let generationTwo = try fixture.context(leaseGeneration: 2)
        let generationOne = try fixture.context(leaseGeneration: 1)
        let executor = fixture.executor()
        _ = try await executor.prepare(.init(context: generationTwo))
        let response = try await executor.observe(.init(context: generationOne))
            .observation
        XCTAssertEqual(response.status, .staleClaim)
    }

    func testIdentityMismatchSimulationIsConservative() async throws {
        let fixture = try LocalProcessTestFixture()
        let context = try fixture.context(
            arguments: ["--wait-for-cancellation"]
        )
        let executor = fixture.executor(
            inspector: FixedProcessInspector(.identityMismatch)
        )
        _ = try await executor.prepare(.init(context: context))
        let response = try await executor.start(.init(context: context))
            .observation
        XCTAssertEqual(response.status, .started)
        let observed = try await executor.observe(.init(context: context))
            .observation
        XCTAssertEqual(observed.status, .identityMismatch)
        let pid = try XCTUnwrap(response.processIdentity?.processID)
        Darwin.kill(pid, SIGKILL)
    }

    func testLargeAndInvalidUTF8OutputUsesBoundedFallbackLog() async throws {
        let fixture = try LocalProcessTestFixture()
        let context = try fixture.context(
            arguments: ["--large-output", "65536", "--invalid-utf8"],
            maximumLogBytes: 4_096
        )
        let executor = fixture.executor()
        _ = try await executor.prepare(.init(context: context))
        let started = try await executor.start(.init(context: context)).observation
        let launchID = try XCTUnwrap(started.processIdentity?.launchID)
        await executor.waitForExit(launchRecordID: launchID)
        let logs = try await executor.logs(launchRecordID: launchID)
        XCTAssertTrue(logs.truncatedChannels.contains(.stdout))
        XCTAssertLessThanOrEqual(
            logs.entries.filter { $0.channel == .stdout }.reduce(0) {
                $0 + $1.data.count
            },
            4_096
        )
        XCTAssertTrue(logs.entries.contains { $0.usedUTF8Fallback })
    }

    func testUndeclaredOutputFileIsNotCollectedAsArtifact() async throws {
        let fixture = try LocalProcessTestFixture()
        let undeclared = fixture.workspace
            .appendingPathComponent("artifacts/undeclared.json")
        let context = try fixture.context(arguments: [
            "--role", "architect", "--output", undeclared.path,
        ])
        let executor = fixture.executor()
        _ = try await executor.prepare(.init(context: context))
        let started = try await executor.start(.init(context: context))
            .observation
        await executor.waitForExit(
            launchRecordID: try XCTUnwrap(started.processIdentity?.launchID)
        )
        let collected = try await executor.collectResult(
            .init(context: context)
        ).observation

        XCTAssertTrue(FileManager.default.fileExists(atPath: undeclared.path))
        XCTAssertEqual(collected.artifacts.map(\.role), [.executionLog])
    }

    func testSpecificationRejectsUnsafeWorkspaceEnvironmentAndArtifacts() throws {
        let fixture = try LocalProcessTestFixture()
        XCTAssertThrowsError(
            try fixture.context(
                workingDirectory: "../outside"
            ).resolvedSpecification()
        )
        XCTAssertThrowsError(
            try fixture.context(
                environment: ["NOT_ALLOWED": "value"]
            ).resolvedSpecification()
        )
        XCTAssertThrowsError(
            try fixture.context(
                outputs: [
                    .init(
                        relativePath: "../outside.json",
                        mediaType: "application/json",
                        role: .nodeOutput
                    ),
                ]
            ).resolvedSpecification()
        )
    }
}

private struct FixedProcessInspector: GraphProcessInspecting {
    let classification: GraphProcessRecoveryClassification

    init(_ classification: GraphProcessRecoveryClassification) {
        self.classification = classification
    }

    func classify(
        _ identity: GraphDurableProcessIdentity
    ) -> GraphProcessRecoveryClassification {
        classification
    }
}

private struct LocalProcessTestFixture {
    let root: URL
    let workspace: URL
    let runtime: URL
    let store: GraphLocalProcessLaunchStore
    let executable: String

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        workspace = root.appendingPathComponent("workspace", isDirectory: true)
        runtime = root.appendingPathComponent("runtime", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("artifacts", isDirectory: true),
            withIntermediateDirectories: true
        )
        store = try GraphLocalProcessLaunchStore(rootURL: runtime)
        executable = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath
        ).appendingPathComponent(
            ".build/debug/OpenIslandProcessFixtureAgent"
        ).path
    }

    func executor(
        inspector: any GraphProcessInspecting = DarwinGraphProcessInspector(),
        crashPoint: GraphLocalProcessCrashPoint? = nil
    ) -> SupervisedLocalProcessExecutor {
        SupervisedLocalProcessExecutor(
            executorInstanceID: UUID().uuidString,
            launchStore: store,
            inspector: inspector,
            crashPoint: crashPoint
        )
    }

    func output(
        role: GraphArtifactRole
    ) -> GraphLocalProcessArtifactDeclaration {
        GraphLocalProcessArtifactDeclaration(
            relativePath: "artifacts/output.json",
            mediaType: "application/json",
            role: role,
            maximumBytes: 1_024 * 1_024
        )
    }

    func context(
        arguments: [String] = [],
        workingDirectory: String = ".",
        environment: [String: String] = [:],
        outputs: [GraphLocalProcessArtifactDeclaration] = [],
        retryableExitCodes: [Int32] = [],
        maximumLogBytes: Int = 1_024 * 1_024,
        cancellationAcknowledgementSeconds: UInt64 = 1,
        leaseGeneration: UInt64 = 1
    ) throws -> GraphExecutorCommandContext {
        let specification = GraphLocalProcessSpecification(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            outputArtifacts: outputs,
            retryableExitCodes: retryableExitCodes,
            logPolicy: GraphLocalProcessLogPolicy(
                maximumBytesPerStream: maximumLogBytes
            )
        )
        return GraphExecutorCommandContext(
            identity: GraphExecutorInteractionIdentity(
                runID: "run",
                nodeID: "node",
                attemptID: "attempt",
                attemptOrdinal: 1,
                claimID: "claim",
                leaseGeneration: leaseGeneration,
                executorID: "openisland.local-process"
            ),
            capabilityRequirement: ["local-process"],
            specification: try specification.immutableSpecification(),
            workspace: GraphExecutionWorkspaceContext(
                root: workspace.path,
                writableRelativePaths: ["artifacts"]
            ),
            environmentAllowlist: ["ALLOWED"],
            inputArtifacts: [],
            cancellation: nil,
            timeoutPolicy: GraphExecutionTimeoutPolicy(
                executionSeconds: 30,
                cancellationAcknowledgementSeconds:
                    cancellationAcknowledgementSeconds
            ),
            correlation: GraphExecutorCorrelationMetadata(
                correlationID: "correlation"
            ),
            priorObservationCount: 0,
            logicalTime: Date(timeIntervalSince1970: 50_000)
        )
    }

    func replacingTime(
        _ context: GraphExecutorCommandContext,
        with time: Date
    ) -> GraphExecutorCommandContext {
        GraphExecutorCommandContext(
            identity: context.identity,
            capabilityRequirement: context.capabilityRequirement,
            specification: context.specification,
            workspace: context.workspace,
            environmentAllowlist: context.environmentAllowlist,
            inputArtifacts: context.inputArtifacts,
            cancellation: context.cancellation,
            timeoutPolicy: context.timeoutPolicy,
            correlation: context.correlation,
            priorObservationCount: context.priorObservationCount,
            logicalTime: time
        )
    }
}

private extension GraphExecutorCommandContext {
    func resolvedSpecification() throws -> GraphResolvedLocalProcessSpecification {
        try GraphLocalProcessSpecificationResolver.resolve(
            GraphLocalProcessSpecification(
                immutableSpecification: specification
            ),
            context: self
        )
    }
}
