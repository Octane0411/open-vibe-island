import Foundation
import SQLite3
import XCTest
@testable import OpenIslandCore

final class GraphExecutionDurabilityInvariantTests: XCTestCase {
    func testRepositoryLoadsEmptyStreamWithoutInventingState() async throws {
        let store = InMemoryGraphExecutionEventStore()
        let repository = DefaultGraphExecutionRepository(
            eventStore: store,
            snapshotStore: InMemoryGraphExecutionSnapshotStore(),
            evidenceSource: UnavailableProcessEvidenceSource()
        )

        let result = try await repository.load(
            runID: "empty",
            observedAt: graphTestTime
        )
        let stream = try await store.read(
            runID: "empty",
            afterVersion: 0
        )

        XCTAssertEqual(result.streamVersion, 0)
        XCTAssertNil(result.persistedProjection.run)
        XCTAssertNil(result.reconciledState)
        XCTAssertEqual(stream.events, [])
    }

    func testIncompatibleSnapshotFallsBackToFullReplay() async throws {
        let events = baseRunningEvents()
        let projection = try GraphExecutionProjector.replay(
            runID: "run",
            events: events
        ).projection
        let result = try await repositoryResult(
            events: events,
            snapshots: [
                graphTestSnapshot(
                    for: projection,
                    schemaVersion: 99
                ),
            ]
        )

        XCTAssertEqual(result.snapshotDisposition, .incompatible)
        XCTAssertEqual(result.persistedProjection, projection)
    }

    func testCorruptSnapshotFallsBackToFullReplay() async throws {
        let events = baseRunningEvents()
        let store = try await eventStore(events)
        let repository = DefaultGraphExecutionRepository(
            eventStore: store,
            snapshotStore: ThrowingSnapshotStore(),
            evidenceSource: UnavailableProcessEvidenceSource()
        )

        let result = try await repository.load(
            runID: "run",
            observedAt: graphTestTime.addingTimeInterval(100)
        )

        XCTAssertEqual(result.snapshotDisposition, .corrupt)
        XCTAssertEqual(result.streamVersion, UInt64(events.count))
    }

    func testSnapshotAheadOfStreamIsBypassed() async throws {
        let fiveEvents = baseRunningEvents()
        let projection = try GraphExecutionProjector.replay(
            runID: "run",
            events: fiveEvents
        ).projection
        let fourEvents = Array(fiveEvents.prefix(4))
        let result = try await repositoryResult(
            events: fourEvents,
            snapshots: [graphTestSnapshot(for: projection)]
        )

        XCTAssertEqual(result.snapshotDisposition, .aheadOfStream)
        XCTAssertEqual(result.streamVersion, 4)
        XCTAssertNil(
            result.persistedProjection.attempts[0].processIdentity
        )
    }

    func testSnapshotsDoNotChangeFinalProjection() async throws {
        let events = baseRunningEvents()
        let prefix = Array(events.prefix(3))
        let prefixProjection = try GraphExecutionProjector.replay(
            runID: "run",
            events: prefix
        ).projection

        let withoutSnapshot = try await repositoryResult(events: events)
        let withSnapshot = try await repositoryResult(
            events: events,
            snapshots: [graphTestSnapshot(for: prefixProjection)]
        )

        XCTAssertEqual(
            withoutSnapshot.persistedProjection,
            withSnapshot.persistedProjection
        )
        XCTAssertEqual(
            withoutSnapshot.reconciledState,
            withSnapshot.reconciledState
        )
    }

    func testStaleHeartbeatDoesNotKeepAttemptRunning() async throws {
        let stale = ExecutorHeartbeat(
            attemptID: "attempt",
            processIdentity: graphTestProcess,
            observedAt: graphTestTime.addingTimeInterval(10),
            validUntil: graphTestTime.addingTimeInterval(20)
        )
        let result = try await repositoryResult(
            events: baseRunningEvents(),
            evidence: .stale(
                GraphProcessEvidence(heartbeats: [stale]),
                reason: "lease expired"
            )
        )

        XCTAssertEqual(
            result.reconciledState?.attempts[0].state,
            .orphaned
        )
    }

    func testValidRetryOrdinalsRemainMonotonic() throws {
        let events = generatedRetryEvents(attemptCount: 10)

        let projection = try GraphExecutionProjector.replay(
            runID: "run",
            events: events
        ).projection

        XCTAssertEqual(
            projection.attempts.map(\.ordinal),
            Array(1...10)
        )
        XCTAssertEqual(
            projection.attempts.map(\.state),
            Array(repeating: .completed, count: 10)
        )
    }

    func testGeneratedReplayIsDeterministicAndDuplicateIdempotent() throws {
        for attemptCount in 1...20 {
            let events = generatedRetryEvents(
                attemptCount: attemptCount
            )
            let forward = try GraphExecutionProjector.replay(
                runID: "run",
                events: events
            )
            let reverse = try GraphExecutionProjector.replay(
                runID: "run",
                events: events.reversed()
            )
            let duplicated = try GraphExecutionProjector.replay(
                runID: "run",
                events: events.flatMap { [$0, $0] }
            )

            XCTAssertEqual(forward.projection, reverse.projection)
            XCTAssertEqual(forward.projection, duplicated.projection)
            XCTAssertEqual(
                duplicated.duplicateEventCount,
                events.count
            )
        }
    }

    func testGeneratedStreamVersionsNeverDecrease() async throws {
        let store = InMemoryGraphExecutionEventStore()
        let events = generatedRetryEvents(attemptCount: 8)
        var observedVersions: [UInt64] = []

        for event in events {
            let result = try await store.append(
                [event],
                to: "run",
                expectedVersion: UInt64(observedVersions.count)
            )
            observedVersions.append(result.newVersion)
        }

        XCTAssertEqual(
            observedVersions,
            Array(1...UInt64(events.count))
        )
    }

    func testReplayFromEveryValidAttemptBoundaryMatchesFullReplay() throws {
        let events = generatedRetryEvents(attemptCount: 8)
        let full = try GraphExecutionProjector.replay(
            runID: "run",
            events: events
        ).projection

        for boundary in stride(
            from: 2,
            through: events.count,
            by: 3
        ) {
            let prefix = Array(events.prefix(boundary))
            let suffix = Array(events.dropFirst(boundary))
            let initial = try GraphExecutionProjector.replay(
                runID: "run",
                events: prefix
            ).projection
            let resumed = try GraphExecutionProjector.replay(
                runID: "run",
                events: suffix,
                initialProjection: initial
            ).projection

            XCTAssertEqual(resumed, full)
        }
    }

    func testDependencyReconciliationReachesStableFixedPoint() throws {
        let input = try loadStaleCompendiumFixture()
        let first = GraphExecutionReconciler.reconcile(input)
        let second = GraphExecutionReconciler.reconcile(
            ExecutionReconciliationInput(
                run: first.run,
                nodes: first.nodes,
                attempts: first.attempts,
                observedAt: input.observedAt
            )
        )

        XCTAssertEqual(first, second)
    }

    func testConcurrentSQLiteWritersProduceOneConflict() async throws {
        let fixture = try SQLiteStoreFixture()
        defer { fixture.remove() }
        let firstStore = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        let secondStore = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        let firstEvent = graphTestRunCreated()
        let secondEvent = GraphExecutionEventEnvelope(
            id: "competing-event",
            runID: "run",
            streamSequence: 1,
            occurredAt: graphTestTime,
            recordedAt: graphTestTime,
            producer: graphTestProducer,
            payload: .runCreated(
                GraphRunCreatedPayload(
                    graphID: "graph",
                    graphDefinitionVersion: "1",
                    graphDefinitionDigest: graphTestDigest,
                    nodeIDs: ["node"]
                )
            )
        )
        let firstTask = Task {
            try await firstStore.append(
                [firstEvent],
                to: "run",
                expectedVersion: 0
            )
        }
        let secondTask = Task {
            try await secondStore.append(
                [secondEvent],
                to: "run",
                expectedVersion: 0
            )
        }
        let outcomes = await [
            appendOutcome(firstTask),
            appendOutcome(secondTask),
        ]

        XCTAssertEqual(
            outcomes.filter { $0 == "success" }.count,
            1
        )
        XCTAssertEqual(
            outcomes.filter { $0 == "version_conflict" }.count,
            1
        )
    }

    func testSQLiteReportsCorruptEventPayload() async throws {
        let fixture = try SQLiteStoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        _ = try await store.append(
            [graphTestRunCreated()],
            to: "run",
            expectedVersion: 0
        )
        try corruptEventJSON(at: fixture.path)

        await XCTAssertThrowsErrorAsync {
            try await store.read(runID: "run", afterVersion: 0)
        } verify: {
            guard let persistenceError =
                    $0 as? GraphExecutionPersistenceError else {
                return XCTFail("Expected corrupt-record error, got \($0).")
            }

            guard case .corruptRecord = persistenceError else {
                return XCTFail("Expected corrupt-record error, got \($0).")
            }
        }
    }

    func testArtifactProvenanceRoundTripsThroughSQLiteAndReplay() async throws {
        let fixture = try SQLiteStoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        let artifact = GraphArtifactReference(
            id: "artifact",
            contentDigest: GraphContentDigest(
                algorithm: "sha256",
                value: "content"
            ),
            mediaType: "text/markdown",
            logicalRole: "handoff",
            producingRunID: "run",
            producingNodeID: "node",
            producingAttemptID: "attempt",
            createdAt: graphTestTime,
            storage: GraphArtifactStorageLocator(
                scheme: "vault",
                opaqueReference: "artifact-reference"
            ),
            sensitivity: .confidential
        )
        var events = Array(baseRunningEvents().prefix(3))
        events.append(
            graphTestEvent(
                id: "artifact-event",
                sequence: 4,
                nodeID: "node",
                attemptID: "attempt",
                payload: .artifactRecorded(
                    GraphArtifactRecordedPayload(artifact: artifact)
                )
            )
        )
        _ = try await store.append(
            events,
            to: "run",
            expectedVersion: 0
        )

        let stream = try await store.read(
            runID: "run",
            afterVersion: 0
        )
        let replay = try GraphExecutionProjector.replay(
            runID: "run",
            events: stream.events
        )

        XCTAssertEqual(replay.projection.artifacts, [artifact])
    }

    func testCompletedParallelWriteSurvivesSiblingFailure() throws {
        let artifact = GraphArtifactReference(
            id: "parallel-output",
            contentDigest: GraphContentDigest(
                algorithm: "sha256",
                value: "parallel-content"
            ),
            mediaType: "application/json",
            logicalRole: "worker-output",
            producingRunID: "run",
            producingNodeID: "worker-a",
            producingAttemptID: "attempt-a",
            createdAt: graphTestTime,
            storage: GraphArtifactStorageLocator(
                scheme: "artifact",
                opaqueReference: "parallel-output"
            )
        )
        let events: [GraphExecutionEventEnvelope] = [
            graphTestEvent(
                id: "parallel-1",
                sequence: 1,
                payload: .runCreated(
                    GraphRunCreatedPayload(
                        graphID: "parallel",
                        graphDefinitionVersion: "1",
                        graphDefinitionDigest: graphTestDigest,
                        nodeIDs: ["worker-a", "worker-b"]
                    )
                )
            ),
            graphTestEvent(
                id: "parallel-2",
                sequence: 2,
                nodeID: "worker-a",
                payload: .nodeRegistered(
                    GraphNodeRegisteredPayload(title: "Worker A")
                )
            ),
            graphTestEvent(
                id: "parallel-3",
                sequence: 3,
                nodeID: "worker-b",
                payload: .nodeRegistered(
                    GraphNodeRegisteredPayload(title: "Worker B")
                )
            ),
            graphTestEvent(
                id: "parallel-4",
                sequence: 4,
                nodeID: "worker-a",
                attemptID: "attempt-a",
                payload: .attemptCreated(
                    GraphAttemptCreatedPayload(ordinal: 1)
                )
            ),
            graphTestEvent(
                id: "parallel-5",
                sequence: 5,
                nodeID: "worker-b",
                attemptID: "attempt-b",
                payload: .attemptCreated(
                    GraphAttemptCreatedPayload(ordinal: 1)
                )
            ),
            graphTestEvent(
                id: "parallel-6",
                sequence: 6,
                nodeID: "worker-a",
                attemptID: "attempt-a",
                payload: .artifactRecorded(
                    GraphArtifactRecordedPayload(artifact: artifact)
                )
            ),
            graphTestEvent(
                id: "parallel-7",
                sequence: 7,
                nodeID: "worker-a",
                attemptID: "attempt-a",
                payload: .attemptCompleted(
                    GraphAttemptTerminalPayload(
                        artifactIDs: [artifact.id]
                    )
                )
            ),
            graphTestEvent(
                id: "parallel-8",
                sequence: 8,
                nodeID: "worker-b",
                attemptID: "attempt-b",
                payload: .attemptFailed(
                    GraphAttemptTerminalPayload(
                        reason: "Sibling failed."
                    )
                )
            ),
        ]

        let projection = try GraphExecutionProjector.replay(
            runID: "run",
            events: events
        ).projection
        let states = Dictionary(
            uniqueKeysWithValues: projection.attempts.map {
                ($0.id, $0.state)
            }
        )

        XCTAssertEqual(states["attempt-a"], .completed)
        XCTAssertEqual(states["attempt-b"], .failed)
        XCTAssertEqual(projection.artifacts, [artifact])
    }

    func testCheckpointForkAndHumanInterruptFactsSurviveReplay() throws {
        let parent = GraphCheckpointReference(
            checkpointID: "checkpoint-7",
            runID: "parent-run",
            streamVersion: 7,
            namespace: "research/subgraph"
        )
        let request = GraphHumanInterruptRequestedPayload(
            requestID: "approval",
            requestSchemaID: "approval.v1",
            requestArtifactID: "request-artifact",
            requiredDecisionCount: 2
        )
        let resolution = GraphHumanInterruptResolvedPayload(
            requestID: "approval",
            resolution: .approved,
            decidedBy: "operator",
            responseArtifactID: "response-artifact"
        )
        let events = [
            graphTestEvent(
                id: "checkpoint-1",
                sequence: 1,
                payload: .runCreated(
                    GraphRunCreatedPayload(
                        graphID: "fork",
                        graphDefinitionVersion: "2",
                        graphDefinitionDigest: graphTestDigest,
                        nodeIDs: [],
                        parentRunID: "parent-run",
                        parentCheckpoint: parent,
                        checkpointNamespace: "research/fork"
                    )
                )
            ),
            graphTestEvent(
                id: "checkpoint-2",
                sequence: 2,
                payload: .humanInterruptRequested(request)
            ),
            graphTestEvent(
                id: "checkpoint-3",
                sequence: 3,
                payload: .humanInterruptResolved(resolution)
            ),
        ]

        let projection = try GraphExecutionProjector.replay(
            runID: "run",
            events: events
        ).projection

        XCTAssertEqual(projection.parentRunID, "parent-run")
        XCTAssertEqual(projection.parentCheckpoint, parent)
        XCTAssertEqual(
            projection.checkpointNamespace,
            "research/fork"
        )
        XCTAssertEqual(
            projection.humanInterrupts[0].state,
            .resolved
        )
        XCTAssertEqual(
            projection.humanInterrupts[0].resolution,
            resolution
        )
    }

    func testSQLiteRestartProducesIdenticalRepositoryResult() async throws {
        let fixture = try SQLiteStoreFixture()
        defer { fixture.remove() }
        let firstStore = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        _ = try await firstStore.append(
            baseRunningEvents(),
            to: "run",
            expectedVersion: 0
        )
        let evidence = StaticProcessEvidenceSource(
            outcome: .unavailable(reason: "offline")
        )
        let firstRepository = DefaultGraphExecutionRepository(
            eventStore: firstStore,
            snapshotStore: firstStore,
            evidenceSource: evidence
        )
        let observedAt = graphTestTime.addingTimeInterval(100)
        let first = try await firstRepository.load(
            runID: "run",
            observedAt: observedAt
        )
        let reopened = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        let secondRepository = DefaultGraphExecutionRepository(
            eventStore: reopened,
            snapshotStore: reopened,
            evidenceSource: evidence
        )

        let second = try await secondRepository.load(
            runID: "run",
            observedAt: observedAt
        )

        XCTAssertEqual(first, second)
    }

    func testInjectableSnapshotPolicyCreatesReusableCache() async throws {
        let store = try await eventStore(baseRunningEvents())
        let snapshotStore = InMemoryGraphExecutionSnapshotStore()
        let evidence = StaticProcessEvidenceSource(
            outcome: .unavailable(reason: "offline")
        )
        let creatingRepository = DefaultGraphExecutionRepository(
            eventStore: store,
            snapshotStore: snapshotStore,
            evidenceSource: evidence,
            snapshotPolicy: EventCountGraphExecutionSnapshotPolicy(
                minimumReplayedEventCount: 1
            )
        )
        let observedAt = graphTestTime.addingTimeInterval(100)

        let created = try await creatingRepository.load(
            runID: "run",
            observedAt: observedAt
        )
        let readingRepository = DefaultGraphExecutionRepository(
            eventStore: store,
            snapshotStore: snapshotStore,
            evidenceSource: evidence
        )
        let reloaded = try await readingRepository.load(
            runID: "run",
            observedAt: observedAt
        )

        XCTAssertEqual(created.snapshotDisposition, .created)
        XCTAssertEqual(reloaded.snapshotDisposition, .current)
        XCTAssertEqual(
            created.persistedProjection,
            reloaded.persistedProjection
        )
        XCTAssertEqual(
            created.reconciledState,
            reloaded.reconciledState
        )
    }

    func testStaleCompendiumFixtureLoadsThroughRepository() async throws {
        let input = try loadStaleCompendiumFixture()
        let events = compendiumEvents(from: input)
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            events,
            to: input.run.id,
            expectedVersion: 0
        )
        let repository = DefaultGraphExecutionRepository(
            eventStore: store,
            snapshotStore: InMemoryGraphExecutionSnapshotStore(),
            evidenceSource: UnavailableProcessEvidenceSource()
        )
        let result = try await repository.load(
            runID: input.run.id,
            observedAt: input.observedAt
        )
        let states = Dictionary(
            uniqueKeysWithValues: result.reconciledState!.nodes.map {
                ($0.id, $0.state)
            }
        )

        XCTAssertEqual(states["architect"], .interrupted)
        XCTAssertEqual(states["researcher"], .orphaned)
        XCTAssertEqual(states["graph"], .blocked)
        XCTAssertEqual(states["reviewer"], .blocked)
        XCTAssertEqual(
            result.reconciledState?.run.state,
            .interrupted
        )
    }

    private func repositoryResult(
        events: [GraphExecutionEventEnvelope],
        snapshots: [GraphExecutionSnapshot] = [],
        evidence: GraphProcessEvidenceOutcome =
            .unavailable(reason: "offline"),
        observedAt: Date = graphTestTime.addingTimeInterval(100)
    ) async throws -> GraphExecutionRepositoryLoadResult {
        let store = try await eventStore(events)
        let repository = DefaultGraphExecutionRepository(
            eventStore: store,
            snapshotStore: InMemoryGraphExecutionSnapshotStore(
                snapshots: snapshots
            ),
            evidenceSource: StaticProcessEvidenceSource(
                outcome: evidence
            )
        )

        return try await repository.load(
            runID: "run",
            observedAt: observedAt
        )
    }

    private func eventStore(
        _ events: [GraphExecutionEventEnvelope]
    ) async throws -> InMemoryGraphExecutionEventStore {
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            events,
            to: "run",
            expectedVersion: 0
        )
        return store
    }

    private func baseRunningEvents()
        -> [GraphExecutionEventEnvelope]
    {
        [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestAttemptStarting(),
            graphTestProcessObserved(),
        ]
    }

    private func generatedRetryEvents(
        attemptCount: Int
    ) -> [GraphExecutionEventEnvelope] {
        var events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
        ]
        var sequence: UInt64 = 3

        for ordinal in 1...attemptCount {
            let attemptID = "attempt-\(ordinal)"
            events.append(
                graphTestAttemptCreated(
                    sequence: sequence,
                    attemptID: attemptID,
                    ordinal: ordinal
                )
            )
            sequence += 1
            events.append(
                graphTestAttemptStarting(
                    sequence: sequence,
                    attemptID: attemptID
                )
            )
            sequence += 1
            events.append(
                graphTestEvent(
                    id: "event-\(sequence)",
                    sequence: sequence,
                    nodeID: "node",
                    attemptID: attemptID,
                    payload: .attemptCompleted(
                        GraphAttemptTerminalPayload()
                    )
                )
            )
            sequence += 1
        }

        return events
    }

    private func compendiumEvents(
        from input: ExecutionReconciliationInput
    ) -> [GraphExecutionEventEnvelope] {
        let producer = GraphExecutionProducer(
            id: "stale-compendium-import",
            kind: .importer
        )
        var sequence: UInt64 = 1

        func envelope(
            id: String,
            nodeID: String? = nil,
            attemptID: String? = nil,
            occurredAt: Date,
            payload: GraphExecutionEventPayload
        ) -> GraphExecutionEventEnvelope {
            defer { sequence += 1 }
            return GraphExecutionEventEnvelope(
                id: id,
                runID: input.run.id,
                nodeID: nodeID,
                attemptID: attemptID,
                streamSequence: sequence,
                occurredAt: occurredAt,
                recordedAt: input.observedAt,
                producer: producer,
                payload: payload
            )
        }

        var events = [
            envelope(
                id: "compendium-run",
                occurredAt: input.run.createdAt,
                payload: .runCreated(
                    GraphRunCreatedPayload(
                        graphID: input.run.graphID,
                        graphDefinitionVersion: "fixture-1",
                        graphDefinitionDigest: GraphContentDigest(
                            algorithm: "sha256",
                            value: "stale-compendium-fixture"
                        ),
                        nodeIDs: input.run.nodeIDs
                    )
                )
            ),
        ]

        for node in input.nodes {
            events.append(
                envelope(
                    id: "compendium-node-\(node.id)",
                    nodeID: node.id,
                    occurredAt: node.updatedAt,
                    payload: .nodeRegistered(
                        GraphNodeRegisteredPayload(
                            title: node.title,
                            dependencyNodeIDs:
                                node.dependencyNodeIDs,
                            executorID: node.executorID
                        )
                    )
                )
            )
        }

        for attempt in input.attempts.sorted(by: {
            $0.id < $1.id
        }) {
            events.append(
                envelope(
                    id: "compendium-attempt-\(attempt.id)",
                    nodeID: attempt.nodeID,
                    attemptID: attempt.id,
                    occurredAt: attempt.createdAt,
                    payload: .attemptCreated(
                        GraphAttemptCreatedPayload(
                            ordinal: attempt.ordinal
                        )
                    )
                )
            )
            events.append(
                envelope(
                    id: "compendium-start-\(attempt.id)",
                    nodeID: attempt.nodeID,
                    attemptID: attempt.id,
                    occurredAt: attempt.startedAt
                        ?? attempt.createdAt,
                    payload: .attemptStarting(
                        GraphAttemptStartingPayload()
                    )
                )
            )

            if let identity = attempt.processIdentity {
                events.append(
                    envelope(
                        id: "compendium-process-\(attempt.id)",
                        nodeID: attempt.nodeID,
                        attemptID: attempt.id,
                        occurredAt: identity.startedAt
                            ?? attempt.createdAt,
                        payload: .processIdentityObserved(
                            GraphProcessIdentityObservedPayload(
                                processIdentity: identity
                            )
                        )
                    )
                )
            }
        }

        for (index, heartbeat) in input.heartbeats.enumerated() {
            let nodeID = input.attempts.first {
                $0.id == heartbeat.attemptID
            }!.nodeID
            events.append(
                envelope(
                    id: "compendium-heartbeat-\(index)",
                    nodeID: nodeID,
                    attemptID: heartbeat.attemptID,
                    occurredAt: heartbeat.observedAt,
                    payload: .heartbeatObserved(
                        GraphHeartbeatObservedPayload(
                            processIdentity:
                                heartbeat.processIdentity,
                            validUntil: heartbeat.validUntil
                        )
                    )
                )
            )
        }

        for (index, exit) in input.processExits.enumerated() {
            let nodeID = input.attempts.first {
                $0.id == exit.attemptID
            }!.nodeID
            events.append(
                envelope(
                    id: "compendium-exit-\(index)",
                    nodeID: nodeID,
                    attemptID: exit.attemptID,
                    occurredAt: exit.observedAt,
                    payload: .processExitObserved(
                        GraphProcessExitObservedPayload(
                            processIdentity: exit.processIdentity,
                            exitCode: exit.exitCode,
                            signal: exit.signal,
                            reason: exit.reason
                        )
                    )
                )
            )
        }

        return events
    }

    private func appendOutcome(
        _ task: Task<GraphExecutionAppendResult, Error>
    ) async -> String {
        do {
            _ = try await task.value
            return "success"
        } catch GraphExecutionPersistenceError
            .expectedVersionConflict {
            return "version_conflict"
        } catch {
            return "unexpected"
        }
    }

    private func corruptEventJSON(at path: String) throws {
        var database: OpaquePointer?

        guard sqlite3_open_v2(
            path,
            &database,
            SQLITE_OPEN_READWRITE,
            nil
        ) == SQLITE_OK, let database else {
            throw GraphExecutionPersistenceError.storageFailure(
                "Unable to open corruption fixture."
            )
        }

        defer { sqlite3_close(database) }

        guard sqlite3_exec(
            database,
            """
            UPDATE graph_execution_events
            SET event_json = x'7B'
            WHERE event_id = 'event-1';
            """,
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw GraphExecutionPersistenceError.storageFailure(
                "Unable to corrupt event fixture."
            )
        }
    }
}

private struct ThrowingSnapshotStore: GraphExecutionSnapshotStore {
    func loadLatest(
        runID: String
    ) async throws -> GraphExecutionSnapshot? {
        throw GraphExecutionPersistenceError.corruptRecord(
            "Injected corrupt snapshot."
        )
    }

    func save(_ snapshot: GraphExecutionSnapshot) async throws {}
}
