import Foundation
import XCTest
@testable import OpenIslandCore

final class DeterministicGraphExecutorTests: XCTestCase {
    func testCommittedScriptProducesDeterministicArtifacts()
        async throws
    {
        let executor = DeterministicGraphExecutor(
            script: try loadCompendiumDeterministicScript()
        )
        let context = try executorContext(nodeID: "architect")

        let prepared = try await executor.prepare(
            GraphExecutorPrepareRequest(context: context)
        ).observation
        let started = try await executor.start(
            GraphExecutorStartRequest(context: context)
        ).observation
        let observed = try await executor.observe(
            GraphExecutorObserveRequest(context: context)
        ).observation
        let result = try await executor.collectResult(
            GraphExecutorCollectResultRequest(context: context)
        ).observation
        let repeated = try await executor.collectResult(
            GraphExecutorCollectResultRequest(context: context)
        ).observation

        XCTAssertEqual(prepared.status, .accepted)
        XCTAssertEqual(started.status, .started)
        XCTAssertEqual(observed.status, .succeeded)
        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.artifacts.count, 1)
        XCTAssertEqual(result, repeated)
    }

    func testLogicalPollsControlRunningWithoutSleeps() async throws {
        let executor = DeterministicGraphExecutor(
            script: GraphDeterministicExecutionScript(
                attempts: [
                    GraphDeterministicAttemptScript(
                        nodeID: "architect",
                        attemptOrdinal: 1,
                        runningPollCount: 2
                    ),
                ]
            )
        )

        let first = try await executor.observe(
            GraphExecutorObserveRequest(
                context: try executorContext(priorObservationCount: 0)
            )
        ).observation
        let second = try await executor.observe(
            GraphExecutorObserveRequest(
                context: try executorContext(priorObservationCount: 1)
            )
        ).observation
        let terminal = try await executor.observe(
            GraphExecutorObserveRequest(
                context: try executorContext(priorObservationCount: 2)
            )
        ).observation

        XCTAssertEqual(first.status, .stillRunning)
        XCTAssertEqual(second.status, .stillRunning)
        XCTAssertEqual(terminal.status, .succeeded)
    }

    func testScriptedFailuresCancellationCrashDuplicateAndStale()
        async throws
    {
        let scripts = [
            GraphDeterministicAttemptScript(
                nodeID: "retry",
                attemptOrdinal: 1,
                terminalOutcome: .retryableFailure,
                failureCategory: "transient"
            ),
            GraphDeterministicAttemptScript(
                nodeID: "cancel",
                attemptOrdinal: 1,
                cancellationBehavior: .acknowledge
            ),
            GraphDeterministicAttemptScript(
                nodeID: "ignore",
                attemptOrdinal: 1,
                cancellationBehavior: .ignoreUntilTimeout
            ),
            GraphDeterministicAttemptScript(
                nodeID: "crash",
                attemptOrdinal: 1,
                crashPoint: .afterAttemptStartPersistence
            ),
            GraphDeterministicAttemptScript(
                nodeID: "stale",
                attemptOrdinal: 1,
                duplicateObservations: true,
                staleLeaseGenerationOffset: -1
            ),
        ]
        let executor = DeterministicGraphExecutor(
            script: GraphDeterministicExecutionScript(attempts: scripts)
        )
        let retry = try await executor.observe(
            GraphExecutorObserveRequest(
                context: try executorContext(nodeID: "retry")
            )
        ).observation
        let cancelled = try await executor.requestCancellation(
            GraphExecutorCancellationRequest(
                context: try executorContext(nodeID: "cancel"),
                cancellationRequestID: "cancel"
            )
        ).observation
        let ignored = try await executor.requestCancellation(
            GraphExecutorCancellationRequest(
                context: try executorContext(nodeID: "ignore"),
                cancellationRequestID: "ignore"
            )
        ).observation
        let staleFirst = try await executor.observe(
            GraphExecutorObserveRequest(
                context: try executorContext(
                    nodeID: "stale",
                    priorObservationCount: 0
                )
            )
        ).observation
        let staleDuplicate = try await executor.observe(
            GraphExecutorObserveRequest(
                context: try executorContext(
                    nodeID: "stale",
                    priorObservationCount: 1
                )
            )
        ).observation

        XCTAssertEqual(retry.failure?.retryable, true)
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(ignored.status, .stillRunning)
        XCTAssertEqual(staleFirst.id, staleDuplicate.id)
        XCTAssertEqual(staleFirst.identity.leaseGeneration, 0)
        do {
            _ = try await executor.start(
                GraphExecutorStartRequest(
                    context: try executorContext(nodeID: "crash")
                )
            )
            XCTFail("Expected scripted crash.")
        } catch let error as GraphExecutorAdapterError {
            XCTAssertEqual(
                error,
                .simulatedCrash("after_attempt_start_persistence")
            )
        }
    }
}

private func executorContext(
    nodeID: String = "architect",
    priorObservationCount: Int = 0
) throws -> GraphExecutorCommandContext {
    let definition = try loadCompendiumExecutableDefinition()
    let execution = definition.execution(for: "architect")!
    return GraphExecutorCommandContext(
        identity: GraphExecutorInteractionIdentity(
            runID: "run",
            nodeID: nodeID,
            attemptID: "\(nodeID)-attempt-1",
            attemptOrdinal: 1,
            claimID: "\(nodeID)-claim-1",
            leaseGeneration: 1,
            executorID: "openisland.deterministic"
        ),
        capabilityRequirement: execution.capabilityRequirement,
        specification: execution.specification,
        workspace: execution.workspace,
        environmentAllowlist: execution.environmentAllowlist,
        inputArtifacts: [],
        cancellation: nil,
        timeoutPolicy: execution.timeoutPolicy,
        correlation: GraphExecutorCorrelationMetadata(
            correlationID: "test"
        ),
        priorObservationCount: priorObservationCount,
        logicalTime: graphTestTime
    )
}
