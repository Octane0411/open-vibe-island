import Foundation
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

struct StaticProcessEvidenceSource: ProcessEvidenceSource {
    let outcome: GraphProcessEvidenceOutcome

    func evidence(
        for request: GraphProcessEvidenceRequest
    ) async -> GraphProcessEvidenceOutcome {
        outcome
    }
}
