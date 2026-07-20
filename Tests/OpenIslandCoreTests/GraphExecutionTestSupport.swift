import Foundation
import XCTest
@testable import OpenIslandCore

let graphTestTime = Date(timeIntervalSince1970: 30_000)
let graphTestProducer = GraphExecutionProducer(
    id: "graph-tests",
    kind: .test,
    instanceID: "test-process"
)
let graphTestDigest = GraphContentDigest(
    algorithm: "sha256",
    value: "graph-digest"
)
let graphTestProcess = ProcessIdentity(
    hostID: "test-host",
    launchID: "test-launch",
    processID: 42,
    startedAt: graphTestTime.addingTimeInterval(3)
)

func graphTestEvent(
    id: String,
    sequence: UInt64,
    nodeID: String? = nil,
    attemptID: String? = nil,
    occurredAt: Date? = nil,
    payloadVersion: Int = 1,
    payload: GraphExecutionEventPayload
) -> GraphExecutionEventEnvelope {
    GraphExecutionEventEnvelope(
        id: id,
        runID: "run",
        nodeID: nodeID,
        attemptID: attemptID,
        streamSequence: sequence,
        occurredAt: occurredAt
            ?? graphTestTime.addingTimeInterval(Double(sequence)),
        recordedAt: graphTestTime.addingTimeInterval(
            Double(sequence) + 0.5
        ),
        producer: graphTestProducer,
        correlationID: "run-correlation",
        causationID: sequence > 1 ? "event-\(sequence - 1)" : nil,
        payloadVersion: payloadVersion,
        payload: payload
    )
}

func graphTestRunCreated(
    sequence: UInt64 = 1
) -> GraphExecutionEventEnvelope {
    graphTestEvent(
        id: "event-\(sequence)",
        sequence: sequence,
        payload: .runCreated(
            GraphRunCreatedPayload(
                graphID: "graph",
                graphDefinitionVersion: "1",
                graphDefinitionDigest: graphTestDigest,
                nodeIDs: ["node"]
            )
        )
    )
}

func graphTestNodeRegistered(
    sequence: UInt64 = 2
) -> GraphExecutionEventEnvelope {
    graphTestEvent(
        id: "event-\(sequence)",
        sequence: sequence,
        nodeID: "node",
        payload: .nodeRegistered(
            GraphNodeRegisteredPayload(
                title: "Node",
                executorID: "executor"
            )
        )
    )
}

func graphTestAttemptCreated(
    sequence: UInt64 = 3,
    attemptID: String = "attempt",
    ordinal: Int = 1
) -> GraphExecutionEventEnvelope {
    graphTestEvent(
        id: "event-\(sequence)",
        sequence: sequence,
        nodeID: "node",
        attemptID: attemptID,
        payload: .attemptCreated(
            GraphAttemptCreatedPayload(
                ordinal: ordinal,
                executorID: "executor"
            )
        )
    )
}

func graphTestAttemptStarting(
    sequence: UInt64 = 4,
    attemptID: String = "attempt"
) -> GraphExecutionEventEnvelope {
    graphTestEvent(
        id: "event-\(sequence)",
        sequence: sequence,
        nodeID: "node",
        attemptID: attemptID,
        payload: .attemptStarting(
            GraphAttemptStartingPayload()
        )
    )
}

func graphTestProcessObserved(
    sequence: UInt64 = 5,
    attemptID: String = "attempt",
    process: ProcessIdentity = graphTestProcess
) -> GraphExecutionEventEnvelope {
    graphTestEvent(
        id: "event-\(sequence)",
        sequence: sequence,
        nodeID: "node",
        attemptID: attemptID,
        payload: .processIdentityObserved(
            GraphProcessIdentityObservedPayload(
                processIdentity: process
            )
        )
    )
}

func graphTestSnapshot(
    for projection: GraphExecutionProjection,
    schemaVersion: Int = GraphExecutionSchema.snapshotVersion,
    streamVersion: UInt64? = nil,
    graphDefinitionDigest: GraphContentDigest? = nil
) -> GraphExecutionSnapshot {
    GraphExecutionSnapshot(
        schemaVersion: schemaVersion,
        runID: projection.runID,
        streamVersion: streamVersion ?? projection.streamVersion,
        graphDefinitionVersion: projection.graphDefinitionVersion!,
        graphDefinitionDigest: graphDefinitionDigest
            ?? projection.graphDefinitionDigest!,
        projectedState: projection,
        createdAt: graphTestTime.addingTimeInterval(100),
        createdBy: graphTestProducer,
        checkpointNamespace: projection.checkpointNamespace,
        namedCheckpoints: projection.namedCheckpoints
    )
}

func loadStaleCompendiumFixture()
    throws -> ExecutionReconciliationInput
{
    let url = try XCTUnwrap(
        Bundle.module.url(
            forResource: "stale-compendium-runtime",
            withExtension: "json",
            subdirectory: "Fixtures"
        )
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    return try decoder.decode(
        ExecutionReconciliationInput.self,
        from: Data(contentsOf: url)
    )
}

func staleCompendiumEvents(
    from input: ExecutionReconciliationInput
) -> [GraphExecutionEventEnvelope] {
    let producer = GraphExecutionProducer(
        id: "stale-compendium-import",
        kind: .importer
    )
    let nodeByAttempt = Dictionary(
        uniqueKeysWithValues: input.attempts.map {
            ($0.id, $0.nodeID)
        }
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
                        dependencyNodeIDs: node.dependencyNodeIDs,
                        executorID: node.executorID
                    )
                )
            )
        )
    }

    for attempt in input.attempts.sorted(by: { $0.id < $1.id }) {
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
                occurredAt: attempt.startedAt ?? attempt.createdAt,
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
                    occurredAt:
                        identity.startedAt ?? attempt.createdAt,
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
        guard let nodeID = nodeByAttempt[heartbeat.attemptID] else {
            continue
        }
        events.append(
            envelope(
                id: "compendium-heartbeat-\(index)",
                nodeID: nodeID,
                attemptID: heartbeat.attemptID,
                occurredAt: heartbeat.observedAt,
                payload: .heartbeatObserved(
                    GraphHeartbeatObservedPayload(
                        processIdentity: heartbeat.processIdentity,
                        validUntil: heartbeat.validUntil
                    )
                )
            )
        )
    }

    for (index, exit) in input.processExits.enumerated() {
        guard let nodeID = nodeByAttempt[exit.attemptID] else {
            continue
        }
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

struct StaticProcessEvidenceSource: ProcessEvidenceSource {
    let outcome: GraphProcessEvidenceOutcome

    func evidence(
        for request: GraphProcessEvidenceRequest
    ) async -> GraphProcessEvidenceOutcome {
        outcome
    }
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    verify: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw.")
    } catch {
        verify(error)
    }
}
