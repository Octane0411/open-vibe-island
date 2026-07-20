import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphExecutionStateTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 10_000)

    func testValidHeartbeatKeepsAttemptRunning() {
        let process = processIdentity()
        let attempt = makeAttempt(
            state: .running,
            processIdentity: process
        )
        let input = makeInput(
            attempts: [attempt],
            heartbeats: [
                ExecutorHeartbeat(
                    attemptID: attempt.id,
                    processIdentity: process,
                    observedAt: observedAt.addingTimeInterval(-10),
                    validUntil: observedAt.addingTimeInterval(10)
                ),
            ]
        )

        let result = GraphExecutionReconciler.reconcile(input)

        XCTAssertEqual(result.attempts[0].state, .running)
        XCTAssertEqual(result.nodes[0].state, .running)
        XCTAssertEqual(result.run.state, .running)
    }

    func testTerminalEventOutranksExitAndHeartbeat() {
        let process = processIdentity()
        let attempt = makeAttempt(
            state: .running,
            processIdentity: process
        )
        let input = makeInput(
            attempts: [attempt],
            processExits: [
                ProcessExit(
                    attemptID: attempt.id,
                    processIdentity: process,
                    observedAt: observedAt.addingTimeInterval(-2),
                    exitCode: 1
                ),
            ],
            heartbeats: [
                ExecutorHeartbeat(
                    attemptID: attempt.id,
                    processIdentity: process,
                    observedAt: observedAt.addingTimeInterval(-1),
                    validUntil: observedAt.addingTimeInterval(10)
                ),
            ],
            events: [
                ExecutionEvent(
                    id: "event-completed",
                    graphRunID: "run",
                    nodeID: "node",
                    attemptID: attempt.id,
                    sequence: 2,
                    occurredAt: observedAt.addingTimeInterval(-3),
                    kind: .attemptCompleted
                ),
            ]
        )

        let result = GraphExecutionReconciler.reconcile(input)

        XCTAssertEqual(result.attempts[0].state, .completed)
        XCTAssertEqual(result.nodes[0].state, .completed)
        XCTAssertEqual(result.run.state, .completed)
    }

    func testProcessExitOutranksLiveHeartbeatAndRequiresTerminalEventForSuccess() {
        let process = processIdentity()
        let attempt = makeAttempt(
            state: .running,
            processIdentity: process
        )
        let input = makeInput(
            attempts: [attempt],
            processExits: [
                ProcessExit(
                    attemptID: attempt.id,
                    processIdentity: process,
                    observedAt: observedAt.addingTimeInterval(-4),
                    exitCode: 0
                ),
            ],
            heartbeats: [
                ExecutorHeartbeat(
                    attemptID: attempt.id,
                    processIdentity: process,
                    observedAt: observedAt.addingTimeInterval(-5),
                    validUntil: observedAt.addingTimeInterval(30)
                ),
            ]
        )

        let result = GraphExecutionReconciler.reconcile(input)

        XCTAssertEqual(result.attempts[0].state, .interrupted)
        XCTAssertEqual(
            result.attempts[0].statusReason,
            "Process exited with code 0 without a terminal execution event."
        )
    }

    func testUnsupportedRunningClaimsBecomeInterruptedOrOrphaned() {
        let unidentified = makeAttempt(id: "unidentified", nodeID: "one")
        let identified = makeAttempt(
            id: "identified",
            nodeID: "two",
            processIdentity: processIdentity()
        )
        let input = makeInput(
            nodes: [
                makeNode(id: "one"),
                makeNode(id: "two"),
            ],
            attempts: [unidentified, identified]
        )

        let result = GraphExecutionReconciler.reconcile(input)
        let states = Dictionary(
            uniqueKeysWithValues: result.attempts.map {
                ($0.id, $0.state)
            }
        )

        XCTAssertEqual(states["unidentified"], .interrupted)
        XCTAssertEqual(states["identified"], .orphaned)
    }

    func testEventOrderingIsDeterministicAcrossInputOrder() {
        let attempt = makeAttempt()
        let completed = ExecutionEvent(
            id: "event-a",
            graphRunID: "run",
            nodeID: "node",
            attemptID: attempt.id,
            sequence: 2,
            occurredAt: observedAt,
            kind: .attemptCompleted
        )
        let failed = ExecutionEvent(
            id: "event-b",
            graphRunID: "run",
            nodeID: "node",
            attemptID: attempt.id,
            sequence: 2,
            occurredAt: observedAt,
            kind: .attemptFailed
        )

        let forward = GraphExecutionReconciler.reconcile(
            makeInput(attempts: [attempt], events: [completed, failed])
        )
        let reversed = GraphExecutionReconciler.reconcile(
            makeInput(attempts: [attempt], events: [failed, completed])
        )

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.attempts[0].state, .failed)
    }

    private func makeInput(
        nodes: [GraphNode]? = nil,
        attempts: [ExecutionAttempt],
        processExits: [ProcessExit] = [],
        heartbeats: [ExecutorHeartbeat] = [],
        events: [ExecutionEvent] = []
    ) -> ExecutionReconciliationInput {
        let resolvedNodes = nodes ?? [makeNode()]

        return ExecutionReconciliationInput(
            run: GraphRun(
                id: "run",
                graphID: "graph",
                state: .running,
                nodeIDs: resolvedNodes.map(\.id),
                createdAt: observedAt.addingTimeInterval(-100),
                updatedAt: observedAt.addingTimeInterval(-50),
                startedAt: observedAt.addingTimeInterval(-100)
            ),
            nodes: resolvedNodes,
            attempts: attempts,
            processExits: processExits,
            heartbeats: heartbeats,
            events: events,
            observedAt: observedAt
        )
    }

    private func makeNode(id: String = "node") -> GraphNode {
        GraphNode(
            id: id,
            graphRunID: "run",
            title: id,
            state: .running,
            updatedAt: observedAt.addingTimeInterval(-50)
        )
    }

    private func makeAttempt(
        id: String = "attempt",
        nodeID: String = "node",
        state: ReconciledExecutionState = .running,
        processIdentity: ProcessIdentity? = nil
    ) -> ExecutionAttempt {
        ExecutionAttempt(
            id: id,
            graphRunID: "run",
            nodeID: nodeID,
            ordinal: 1,
            state: state,
            processIdentity: processIdentity,
            createdAt: observedAt.addingTimeInterval(-100),
            updatedAt: observedAt.addingTimeInterval(-50),
            startedAt: observedAt.addingTimeInterval(-100)
        )
    }

    private func processIdentity() -> ProcessIdentity {
        ProcessIdentity(
            hostID: "host",
            launchID: "launch",
            processID: 42,
            startedAt: observedAt.addingTimeInterval(-100)
        )
    }
}
