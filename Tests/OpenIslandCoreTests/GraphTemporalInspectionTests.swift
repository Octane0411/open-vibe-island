import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphTemporalInspectionTests: XCTestCase {
    func testListAndInspectUseDeterministicReconciledState() async throws {
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestAttemptStarting(),
        ]
        let store = try await populatedStore(events)
        let inspector = makeInspector(store: store)

        let first = try await inspector.listRuns(state: nil, limit: 10)
        let second = try await inspector.listRuns(state: nil, limit: 10)
        let inspection = try await inspector.inspect(
            runID: "run",
            includeArtifacts: false,
            includeDiagnostics: true
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.runID), ["run"])
        XCTAssertEqual(first.first?.reconciledState, .interrupted)
        XCTAssertEqual(inspection.nodes.first?.reconciledState, .interrupted)
        XCTAssertEqual(
            inspection.attempts.first?.statusReason,
            "The attempt was running without recoverable process identity."
        )
    }

    func testEventPagesFilterAndAdvanceThroughRawHistory() async throws {
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestAttemptStarting(),
            graphTestProcessObserved(),
        ]
        let store = try await populatedStore(events)
        let inspector = makeInspector(store: store, pageSize: 2)
        let page = try await inspector.eventPage(
            runID: "run",
            filter: GraphInspectionEventFilter(
                nodeID: "node",
                eventTypes: [
                    GraphExecutionEventType.attemptCreated.rawValue,
                    GraphExecutionEventType.processIdentityObserved.rawValue,
                ],
                limit: 2
            )
        )

        XCTAssertEqual(
            page.events.map(\.eventType),
            [
                GraphExecutionEventType.attemptCreated.rawValue,
                GraphExecutionEventType.processIdentityObserved.rawValue,
            ]
        )
        XCTAssertEqual(page.scannedThroughSequence, 5)
        XCTAssertFalse(page.hasMore)
    }

    func testEventPageCursorStopsAtLastExaminedMatch() async throws {
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestAttemptStarting(),
            graphTestProcessObserved(),
        ]
        let store = try await populatedStore(events)
        let inspector = makeInspector(store: store, pageSize: 5)

        let first = try await inspector.eventPage(
            runID: "run",
            filter: GraphInspectionEventFilter(limit: 2)
        )
        let second = try await inspector.eventPage(
            runID: "run",
            filter: GraphInspectionEventFilter(
                afterSequence: first.scannedThroughSequence,
                limit: 10
            )
        )

        XCTAssertEqual(first.events.map(\.streamSequence), [1, 2])
        XCTAssertEqual(first.scannedThroughSequence, 2)
        XCTAssertTrue(first.hasMore)
        XCTAssertEqual(second.events.map(\.streamSequence), [3, 4, 5])
    }

    func testReplayToSequenceIsIdempotentAndDoesNotWriteSnapshot()
        async throws
    {
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestAttemptStarting(),
        ]
        let store = try await populatedStore(events)
        let snapshots = InMemoryGraphExecutionSnapshotStore()
        let inspector = DefaultGraphTemporalInspector(
            readStore: store,
            snapshotStore: snapshots
        )
        let reference = GraphTemporalReference(
            runID: "run",
            boundary: .sequence(3)
        )

        let first = try await inspector.replay(
            reference: reference,
            evidenceMode: .withoutLiveEvidence
        )
        let second = try await inspector.replay(
            reference: reference,
            evidenceMode: .withoutLiveEvidence
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.boundary, 3)
        XCTAssertEqual(first.projected.attempts.first?.state, .pending)
        let persistedSnapshot = await snapshots.loadLatest(
            runID: "run"
        )
        XCTAssertNil(persistedSnapshot)
    }

    func testNamedCheckpointResolvesToHistoricalBoundary() async throws {
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestAttemptStarting(),
        ]
        let projection = try GraphExecutionProjector.replay(
            runID: "run",
            events: Array(events.prefix(3))
        ).projection
        var checkpointProjection = projection
        checkpointProjection.namedCheckpoints = [
            GraphCheckpointReference(
                checkpointID: "before-start",
                runID: "run",
                streamVersion: 3,
                namespace: "root"
            ),
        ]
        let snapshot = graphTestSnapshot(for: checkpointProjection)
        let store = try await populatedStore(events)
        let inspector = DefaultGraphTemporalInspector(
            readStore: store,
            snapshotStore: InMemoryGraphExecutionSnapshotStore(
                snapshots: [snapshot]
            )
        )

        let checkpoints = try await inspector.checkpoints(runID: "run")
        let replay = try await inspector.replay(
            reference: GraphTemporalReference(
                runID: "run",
                boundary: .checkpoint("before-start")
            ),
            evidenceMode: .withoutLiveEvidence
        )

        XCTAssertEqual(checkpoints.map(\.checkpointID), ["before-start"])
        XCTAssertEqual(replay.boundary, 3)
        XCTAssertEqual(replay.snapshotDisposition, .current)
        XCTAssertEqual(replay.projected.attempts.first?.state, .pending)
    }

    func testIncompatibleSnapshotIsBypassed() async throws {
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
        ]
        let projection = try GraphExecutionProjector.replay(
            runID: "run",
            events: events
        ).projection
        let snapshot = graphTestSnapshot(
            for: projection,
            schemaVersion: GraphExecutionSchema.snapshotVersion + 1
        )
        let store = try await populatedStore(events)
        let inspector = DefaultGraphTemporalInspector(
            readStore: store,
            snapshotStore: InMemoryGraphExecutionSnapshotStore(
                snapshots: [snapshot]
            )
        )

        let replay = try await inspector.replay(
            reference: GraphTemporalReference(runID: "run"),
            evidenceMode: .withoutLiveEvidence
        )

        XCTAssertEqual(replay.snapshotDisposition, .incompatible)
        XCTAssertEqual(replay.replayedEventCount, 2)
        XCTAssertEqual(replay.projected.nodes.map(\.id), ["node"])
    }

    func testDiffIgnoresTimestampsAsStandaloneChanges() async throws {
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestAttemptStarting(),
        ]
        let store = try await populatedStore(events)
        let inspector = makeInspector(store: store)
        let diff = try await inspector.diff(
            left: GraphTemporalReference(
                runID: "run",
                boundary: .sequence(3)
            ),
            right: GraphTemporalReference(runID: "run")
        )

        XCTAssertTrue(
            diff.changes.contains {
                $0.category == .attempt
                    && $0.field == "persisted_state"
                    && $0.left == "pending"
                    && $0.right == "running"
            }
        )
        XCTAssertFalse(
            diff.changes.contains {
                $0.field.localizedCaseInsensitiveContains("time")
                    || $0.field.localizedCaseInsensitiveContains("date")
            }
        )
        XCTAssertEqual(
            diff.changes,
            diff.changes.sorted(by: temporalChangeOrder)
        )
    }

    func testArtifactInspectionAlwaysRedactsStorageLocator()
        async throws
    {
        let artifact = GraphArtifactReference(
            id: "artifact",
            contentDigest: GraphContentDigest(
                algorithm: "sha256",
                value: "content"
            ),
            mediaType: "application/json",
            logicalRole: "research-output",
            producingRunID: "run",
            producingNodeID: "node",
            producingAttemptID: "attempt",
            createdAt: graphTestTime.addingTimeInterval(4),
            storage: GraphArtifactStorageLocator(
                scheme: "file",
                opaqueReference: "/private/research/secret.json"
            ),
            sensitivity: .confidential
        )
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
            graphTestAttemptCreated(),
            graphTestEvent(
                id: "artifact-event",
                sequence: 4,
                nodeID: "node",
                attemptID: "attempt",
                payload: .artifactRecorded(
                    GraphArtifactRecordedPayload(artifact: artifact)
                )
            ),
        ]
        let store = try await populatedStore(events)
        let inspector = makeInspector(store: store)

        let artifacts = try await inspector.artifacts(runID: "run")
        let encoded = try JSONEncoder().encode(artifacts)
        let output = String(decoding: encoded, as: UTF8.self)

        XCTAssertEqual(artifacts.first?.storageScheme, "file")
        XCTAssertEqual(
            artifacts.first?.redactions.first?.field,
            "storage.opaqueReference"
        )
        XCTAssertFalse(output.contains("/private/research"))
    }

    func testCausalExplanationFindsTransitiveBlockingChain()
        async throws
    {
        let events = blockingGraphEvents()
        let store = InMemoryGraphExecutionEventStore()
        _ = try await store.append(
            events,
            to: "blocked-run",
            expectedVersion: 0
        )
        let inspector = makeInspector(store: store)

        let explanation = try await inspector.explain(
            runID: "blocked-run",
            nodeID: "reviewer"
        )

        XCTAssertEqual(explanation.state, .blocked)
        XCTAssertEqual(
            explanation.causalPredecessorNodeIDs,
            ["architect", "graph"]
        )
        XCTAssertEqual(
            explanation.blockingDependencyNodeIDs,
            ["architect", "graph"]
        )
        XCTAssertTrue(
            explanation.reasons.contains {
                $0.code == .dependencyInterrupted
                    && $0.subjectID == "architect"
            }
        )
        XCTAssertEqual(explanation.shortestCausalChain.count, 3)
        XCTAssertEqual(
            explanation.readinessRequirements,
            ["Dependency graph must reach completed state."]
        )
    }

    private func makeInspector(
        store: InMemoryGraphExecutionEventStore,
        pageSize: Int = 500
    ) -> DefaultGraphTemporalInspector {
        DefaultGraphTemporalInspector(
            readStore: store,
            snapshotStore: InMemoryGraphExecutionSnapshotStore(),
            pageSize: pageSize
        )
    }

    private func populatedStore(
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

    private func blockingGraphEvents()
        -> [GraphExecutionEventEnvelope]
    {
        let producer = GraphExecutionProducer(
            id: "inspection-tests",
            kind: .test
        )

        func event(
            id: String,
            sequence: UInt64,
            nodeID: String? = nil,
            attemptID: String? = nil,
            payload: GraphExecutionEventPayload
        ) -> GraphExecutionEventEnvelope {
            GraphExecutionEventEnvelope(
                id: id,
                runID: "blocked-run",
                nodeID: nodeID,
                attemptID: attemptID,
                streamSequence: sequence,
                occurredAt: graphTestTime.addingTimeInterval(
                    Double(sequence)
                ),
                recordedAt: graphTestTime.addingTimeInterval(
                    Double(sequence)
                ),
                producer: producer,
                payload: payload
            )
        }

        return [
            event(
                id: "run",
                sequence: 1,
                payload: .runCreated(
                    GraphRunCreatedPayload(
                        graphID: "blocked-graph",
                        graphDefinitionVersion: "1",
                        graphDefinitionDigest: graphTestDigest,
                        nodeIDs: ["architect", "graph", "reviewer"]
                    )
                )
            ),
            event(
                id: "architect-node",
                sequence: 2,
                nodeID: "architect",
                payload: .nodeRegistered(
                    GraphNodeRegisteredPayload(title: "Architect")
                )
            ),
            event(
                id: "graph-node",
                sequence: 3,
                nodeID: "graph",
                payload: .nodeRegistered(
                    GraphNodeRegisteredPayload(
                        title: "Graph",
                        dependencyNodeIDs: ["architect"]
                    )
                )
            ),
            event(
                id: "reviewer-node",
                sequence: 4,
                nodeID: "reviewer",
                payload: .nodeRegistered(
                    GraphNodeRegisteredPayload(
                        title: "Reviewer",
                        dependencyNodeIDs: ["graph"]
                    )
                )
            ),
            event(
                id: "architect-attempt",
                sequence: 5,
                nodeID: "architect",
                attemptID: "architect-1",
                payload: .attemptCreated(
                    GraphAttemptCreatedPayload(ordinal: 1)
                )
            ),
            event(
                id: "architect-start",
                sequence: 6,
                nodeID: "architect",
                attemptID: "architect-1",
                payload: .attemptStarting(
                    GraphAttemptStartingPayload()
                )
            ),
            event(
                id: "architect-stop",
                sequence: 7,
                nodeID: "architect",
                attemptID: "architect-1",
                payload: .attemptInterrupted(
                    GraphAttemptTerminalPayload(reason: "stopped")
                )
            ),
        ]
    }
}

private func temporalChangeOrder(
    _ lhs: GraphTemporalChange,
    _ rhs: GraphTemporalChange
) -> Bool {
    if lhs.category != rhs.category {
        return lhs.category.rawValue < rhs.category.rawValue
    }
    if lhs.entityID != rhs.entityID {
        return lhs.entityID < rhs.entityID
    }
    return lhs.field < rhs.field
}
