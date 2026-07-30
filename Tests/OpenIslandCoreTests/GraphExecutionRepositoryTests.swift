import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphExecutionRepositoryTests: XCTestCase {
    func testStaleSnapshotReplaysSubsequentEvents() async throws {
        let store = InMemoryGraphExecutionEventStore()
        let firstThree = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
        ]
        _ = try await store.append(
            firstThree,
            to: "run",
            expectedVersion: 0
        )
        let snapshotProjection = try GraphExecutionProjector.replay(
            runID: "run",
            events: firstThree
        ).projection
        let snapshotStore = InMemoryGraphExecutionSnapshotStore(
            snapshots: [snapshot(for: snapshotProjection)]
        )
        _ = try await store.append(
            [graphTestAttemptStarting()],
            to: "run",
            expectedVersion: 3
        )
        let repository = DefaultGraphExecutionRepository(
            eventStore: store,
            snapshotStore: snapshotStore,
            evidenceSource: UnavailableProcessEvidenceSource()
        )

        let result = try await repository.load(
            runID: "run",
            observedAt: graphTestTime.addingTimeInterval(100)
        )

        XCTAssertEqual(result.snapshotDisposition, .stale)
        XCTAssertEqual(result.streamVersion, 4)
        XCTAssertEqual(
            result.persistedProjection.attempts[0].state,
            .running
        )
        XCTAssertEqual(
            result.reconciledState?.attempts[0].state,
            .interrupted
        )
    }

    func testUnavailableEvidenceReturnsProjectionAndConservativeState() async throws {
        let result = try await loadRunningRepository(
            evidence: .unavailable(reason: "offline")
        )

        XCTAssertEqual(
            result.persistedProjection.attempts[0].state,
            .running
        )
        XCTAssertEqual(
            result.reconciledState?.attempts[0].state,
            .orphaned
        )
        XCTAssertEqual(
            result.evidenceOutcome,
            .unavailable(reason: "offline")
        )
    }

    func testAdapterFailureDoesNotMutateHistory() async throws {
        let result = try await loadRunningRepository(
            evidence: .adapterFailed(reason: "probe crashed")
        )

        XCTAssertEqual(result.streamVersion, 5)
        XCTAssertEqual(
            result.persistedProjection.attempts[0].state,
            .running
        )
        XCTAssertEqual(
            result.reconciledState?.attempts[0].state,
            .orphaned
        )
    }

    func testIdentityMismatchIsNotAcceptedAsLiveEvidence() async throws {
        let mismatch = ExecutorHeartbeat(
            attemptID: "attempt",
            processIdentity: ProcessIdentity(
                hostID: "test-host",
                launchID: "other",
                processID: 99,
                startedAt: graphTestTime
            ),
            observedAt: graphTestTime.addingTimeInterval(50),
            validUntil: graphTestTime.addingTimeInterval(200)
        )
        let result = try await loadRunningRepository(
            evidence: .identityMismatch(
                GraphProcessEvidence(heartbeats: [mismatch]),
                reason: "launch identity differs"
            )
        )

        XCTAssertEqual(
            result.reconciledState?.attempts[0].state,
            .orphaned
        )
    }

    func testAvailableHeartbeatKeepsMatchingAttemptRunning() async throws {
        let heartbeat = ExecutorHeartbeat(
            attemptID: "attempt",
            processIdentity: graphTestProcess,
            observedAt: graphTestTime.addingTimeInterval(50),
            validUntil: graphTestTime.addingTimeInterval(200)
        )
        let result = try await loadRunningRepository(
            evidence: .available(
                GraphProcessEvidence(heartbeats: [heartbeat])
            )
        )

        XCTAssertEqual(
            result.reconciledState?.attempts[0].state,
            .running
        )
    }

    func testMatchingProcessExitInterruptsAttempt() async throws {
        let exit = ProcessExit(
            attemptID: "attempt",
            processIdentity: graphTestProcess,
            observedAt: graphTestTime.addingTimeInterval(50),
            exitCode: 0
        )
        let result = try await loadRunningRepository(
            evidence: .available(
                GraphProcessEvidence(processExits: [exit])
            )
        )

        XCTAssertEqual(
            result.reconciledState?.attempts[0].state,
            .interrupted
        )
    }

    func testRepeatedLoadsAreIdenticalAndDoNotAppendEvents() async throws {
        let store = try await runningStore()
        let repository = DefaultGraphExecutionRepository(
            eventStore: store,
            snapshotStore: InMemoryGraphExecutionSnapshotStore(),
            evidenceSource: StaticProcessEvidenceSource(
                outcome: .unavailable(reason: "offline")
            )
        )
        let observedAt = graphTestTime.addingTimeInterval(100)

        let first = try await repository.load(
            runID: "run",
            observedAt: observedAt
        )
        let second = try await repository.load(
            runID: "run",
            observedAt: observedAt
        )
        let stream = try await store.read(
            runID: "run",
            afterVersion: 0
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(stream.currentVersion, 5)
    }

    private func loadRunningRepository(
        evidence: GraphProcessEvidenceOutcome
    ) async throws -> GraphExecutionRepositoryLoadResult {
        let repository = DefaultGraphExecutionRepository(
            eventStore: try await runningStore(),
            snapshotStore: InMemoryGraphExecutionSnapshotStore(),
            evidenceSource: StaticProcessEvidenceSource(
                outcome: evidence
            )
        )

        return try await repository.load(
            runID: "run",
            observedAt: graphTestTime.addingTimeInterval(100)
        )
    }

    private func runningStore() async throws
        -> InMemoryGraphExecutionEventStore
    {
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            [
                graphTestRunCreated(),
                graphTestNodeRegistered(),
                graphTestAttemptCreated(),
                graphTestAttemptStarting(),
                graphTestProcessObserved(),
            ],
            to: "run",
            expectedVersion: 0
        )
        return store
    }

    private func snapshot(
        for projection: GraphExecutionProjection
    ) -> GraphExecutionSnapshot {
        GraphExecutionSnapshot(
            runID: projection.runID,
            streamVersion: projection.streamVersion,
            graphDefinitionVersion: projection
                .graphDefinitionVersion!,
            graphDefinitionDigest: projection.graphDefinitionDigest!,
            projectedState: projection,
            createdAt: graphTestTime.addingTimeInterval(10),
            createdBy: graphTestProducer,
            checkpointNamespace: projection.checkpointNamespace
        )
    }
}
