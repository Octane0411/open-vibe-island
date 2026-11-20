import XCTest
@testable import OpenIslandCore

final class GraphSchedulerTests: XCTestCase {
    func testSchedulerIsDeterministicAndSelectsOnlyRootNode() {
        let fixture = schedulingFixture()
        let first = GraphScheduler.evaluate(fixture.input)
        let second = GraphScheduler.evaluate(fixture.input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.phasesByNodeID["architect"], .claimable)
        XCTAssertEqual(first.reasonsByNodeID["architect"], .dependenciesSatisfied)
        XCTAssertEqual(first.phasesByNodeID["researcher"], .pending)
        XCTAssertEqual(first.phasesByNodeID["graph"], .pending)
        XCTAssertEqual(first.phasesByNodeID["reviewer"], .pending)
        XCTAssertEqual(
            first.reasonsByNodeID["reviewer"],
            .dependencyIncomplete
        )
    }

    func testSchedulerUsesFixedPointFailurePropagation() {
        var fixture = schedulingFixture()
        fixture.projection.nodes[0].state = .failed
        fixture.reconciled.nodes[0].state = .failed
        fixture.reconciled.nodes[1].state = .blocked
        fixture.reconciled.nodes[2].state = .blocked
        fixture.reconciled.nodes[3].state = .blocked
        fixture.projection.attempts = [
            ExecutionAttempt(
                id: "architect-attempt-1",
                graphRunID: "compendium-run",
                nodeID: "architect",
                ordinal: 1,
                state: .failed,
                createdAt: fixture.time,
                updatedAt: fixture.time,
                finishedAt: fixture.time,
                statusReason: "fatal"
            ),
        ]
        fixture.reconciled.attempts = fixture.projection.attempts
        fixture.policy = GraphSchedulerPolicy(
            policyID: "compendium-policy",
            version: "1",
            retryPolicy: GraphRetryPolicy(
                maximumAttempts: 1,
                retryableFailureCategories: ["execution_failure"]
            )
        )

        let result = GraphScheduler.evaluate(fixture.input)

        XCTAssertEqual(result.phasesByNodeID["architect"], .terminal)
        XCTAssertEqual(result.phasesByNodeID["researcher"], .blocked)
        XCTAssertEqual(result.phasesByNodeID["graph"], .blocked)
        XCTAssertEqual(result.phasesByNodeID["reviewer"], .blocked)
        XCTAssertEqual(
            result.reasonsByNodeID["reviewer"],
            .dependencyFailed
        )
        XCTAssertEqual(
            result.proposedEvents.filter {
                $0.payload.eventType
                    == GraphExecutionEventType
                        .dependencyFailurePropagated.rawValue
            }.count,
            3
        )
    }

    func testRetryBackoffIsDurableAndDeterministic() throws {
        var fixture = schedulingFixture()
        let failed = ExecutionAttempt(
            id: "architect-attempt-1",
            graphRunID: "compendium-run",
            nodeID: "architect",
            ordinal: 1,
            state: .failed,
            createdAt: fixture.time,
            updatedAt: fixture.time,
            finishedAt: fixture.time,
            statusReason: "temporary"
        )
        fixture.projection.attempts = [failed]
        fixture.reconciled.attempts = [failed]
        fixture.projection.nodes[0].state = .failed
        fixture.reconciled.nodes[0].state = .failed
        fixture.failureCategories = [failed.id: "transient"]
        fixture.policy = GraphSchedulerPolicy(
            policyID: "compendium-policy",
            version: "1",
            retryPolicy: GraphRetryPolicy(
                maximumAttempts: 3,
                retryableFailureCategories: ["transient"],
                initialBackoffSeconds: 10,
                jitterBasisPoints: 1_000,
                jitterSeed: "fixture-seed"
            )
        )

        let first = GraphScheduler.evaluate(fixture.input)
        let second = GraphScheduler.evaluate(fixture.input)
        let payload = try XCTUnwrap(
            first.proposedEvents.compactMap { event -> GraphRetryRecord? in
                guard case let .retryScheduled(value) = event.payload else {
                    return nil
                }
                return value.retry
            }.first
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.phasesByNodeID["architect"], .retryWaiting)
        XCTAssertEqual(payload.nextAttemptOrdinal, 2)
        XCTAssertGreaterThanOrEqual(payload.delaySeconds, 10)
        XCTAssertEqual(
            payload.eligibleAt,
            fixture.time.addingTimeInterval(
                TimeInterval(payload.delaySeconds)
            )
        )
    }

    func testCapabilityAndDefinitionMismatchesAreExplicit() {
        var fixture = schedulingFixture()
        fixture.executors = []
        let unavailable = GraphScheduler.evaluate(fixture.input)
        XCTAssertEqual(unavailable.phasesByNodeID["architect"], .ready)
        XCTAssertEqual(
            unavailable.reasonsByNodeID["architect"],
            .executorCapabilityUnavailable
        )

        fixture.definition = GraphSchedulingDefinition(
            graphID: "dose-compendium",
            version: "different",
            digest: fixture.digest,
            nodes: fixture.definition.nodes
        )
        let mismatch = GraphScheduler.evaluate(fixture.input)
        XCTAssertEqual(mismatch.phasesByNodeID["architect"], .blocked)
        XCTAssertEqual(
            mismatch.reasonsByNodeID["architect"],
            .graphDefinitionMismatch
        )
    }

    func testCompletedEvaluationMakesSchedulerIdempotent() {
        var fixture = schedulingFixture()
        let first = GraphScheduler.evaluate(fixture.input)
        fixture.projection.scheduling.completedEvaluationIDs = [
            first.evaluationID,
        ]

        let repeated = GraphScheduler.evaluate(fixture.input)

        XCTAssertTrue(repeated.proposedEvents.isEmpty)
        XCTAssertTrue(repeated.phasesByNodeID.isEmpty)
    }

    func testSchedulingEventsReplayAndSurviveSnapshotRoundTrip()
        throws
    {
        let fixture = schedulingFixture(nodeIDs: ["architect"])
        let base = baseHistory(fixture: fixture)
        let baseReplay = try GraphExecutionProjector.replay(
            runID: "compendium-run",
            events: base
        )
        let input = GraphSchedulingInput(
            definition: fixture.definition,
            projectedState: baseReplay.projection,
            reconciledState: fixture.reconciled,
            policy: fixture.policy,
            logicalTime: fixture.time,
            availableExecutors: fixture.executors
        )
        let decision = GraphScheduler.evaluate(input)
        let events = base + decision.proposedEvents.enumerated().map {
            index, proposal in
            GraphExecutionEventEnvelope(
                id: proposal.id,
                runID: "compendium-run",
                nodeID: proposal.nodeID,
                attemptID: proposal.attemptID,
                streamSequence: UInt64(base.count + index + 1),
                occurredAt: proposal.occurredAt,
                recordedAt: proposal.occurredAt,
                producer: graphTestProducer,
                payload: proposal.payload
            )
        }

        let replay = try GraphExecutionProjector.replay(
            runID: "compendium-run",
            events: events
        )
        let data = try JSONEncoder().encode(replay.projection)
        let decoded = try JSONDecoder().decode(
            GraphExecutionProjection.self,
            from: data
        )

        XCTAssertEqual(decoded, replay.projection)
        XCTAssertEqual(
            replay.projection.scheduling.completedEvaluationIDs,
            [decision.evaluationID]
        )
        XCTAssertEqual(
            replay.projection.scheduling.records.last?.eventType,
            GraphExecutionEventType.schedulerCycleCompleted.rawValue
        )
        XCTAssertEqual(
            replay.projection.scheduling.records.first?.factClass,
            .decision
        )
    }
}

private struct SchedulingFixture {
    var definition: GraphSchedulingDefinition
    var projection: GraphExecutionProjection
    var reconciled: ExecutionReconciliationResult
    var policy: GraphSchedulerPolicy
    var executors: [GraphExecutorCapabilities]
    var failureCategories: [String: String]
    let time: Date
    let digest: GraphContentDigest

    var input: GraphSchedulingInput {
        GraphSchedulingInput(
            definition: definition,
            projectedState: projection,
            reconciledState: reconciled,
            policy: policy,
            logicalTime: time,
            availableExecutors: executors,
            failureCategoriesByAttemptID: failureCategories
        )
    }
}

private func schedulingFixture(
    nodeIDs: [String] = [
        "architect",
        "researcher",
        "graph",
        "reviewer",
    ]
) -> SchedulingFixture {
    let time = Date(timeIntervalSince1970: 100_000)
    let digest = GraphContentDigest(
        algorithm: "sha256",
        value: "compendium-scheduling-v1"
    )
    let allDefinitions = [
        GraphSchedulingDefinitionNode(
            id: "architect",
            title: "Architect",
            requiredCapabilities: ["research-planning"]
        ),
        GraphSchedulingDefinitionNode(
            id: "researcher",
            title: "Researcher",
            dependencyNodeIDs: ["architect"],
            requiredCapabilities: ["web-research"]
        ),
        GraphSchedulingDefinitionNode(
            id: "graph",
            title: "Graph Engineer",
            dependencyNodeIDs: ["researcher"],
            requiredCapabilities: ["swift-graph"]
        ),
        GraphSchedulingDefinitionNode(
            id: "reviewer",
            title: "Reviewer",
            dependencyNodeIDs: ["graph"],
            requiredCapabilities: ["independent-review"]
        ),
    ]
    let definitions = allDefinitions.filter { nodeIDs.contains($0.id) }
    let nodes = definitions.map {
        GraphNode(
            id: $0.id,
            graphRunID: "compendium-run",
            title: $0.title,
            dependencyNodeIDs: $0.dependencyNodeIDs,
            state: $0.dependencyNodeIDs.isEmpty ? .ready : .pending,
            updatedAt: time
        )
    }
    let run = GraphRun(
        id: "compendium-run",
        graphID: "dose-compendium",
        nodeIDs: nodeIDs,
        createdAt: time,
        updatedAt: time
    )
    let projection = GraphExecutionProjection(
        runID: run.id,
        streamVersion: UInt64(1 + definitions.count),
        run: run,
        nodes: nodes,
        graphDefinitionVersion: "1",
        graphDefinitionDigest: digest
    )
    return SchedulingFixture(
        definition: GraphSchedulingDefinition(
            graphID: run.graphID,
            version: "1",
            digest: digest,
            nodes: definitions
        ),
        projection: projection,
        reconciled: ExecutionReconciliationResult(
            run: run,
            nodes: nodes,
            attempts: []
        ),
        policy: GraphSchedulerPolicy(
            policyID: "compendium-policy",
            version: "1",
            retryPolicy: GraphRetryPolicy(
                maximumAttempts: 3,
                retryableFailureCategories: ["execution_failure"]
            )
        ),
        executors: definitions.map {
            GraphExecutorCapabilities(
                executorID: "executor-\($0.id)",
                capabilityIdentity: "capability-\($0.id)",
                capabilities: $0.requiredCapabilities
            )
        },
        failureCategories: [:],
        time: time,
        digest: digest
    )
}

private func baseHistory(
    fixture: SchedulingFixture
) -> [GraphExecutionEventEnvelope] {
    var events = [
        GraphExecutionEventEnvelope(
            id: "compendium-run-created",
            runID: "compendium-run",
            streamSequence: 1,
            occurredAt: fixture.time,
            recordedAt: fixture.time,
            producer: graphTestProducer,
            payload: .runCreated(
                GraphRunCreatedPayload(
                    graphID: fixture.definition.graphID,
                    graphDefinitionVersion: fixture.definition.version,
                    graphDefinitionDigest: fixture.digest,
                    nodeIDs: fixture.definition.nodes.map(\.id)
                )
            )
        ),
    ]
    for (index, node) in fixture.definition.nodes.enumerated() {
        events.append(
            GraphExecutionEventEnvelope(
                id: "compendium-node-\(node.id)",
                runID: "compendium-run",
                nodeID: node.id,
                streamSequence: UInt64(index + 2),
                occurredAt: fixture.time,
                recordedAt: fixture.time,
                producer: graphTestProducer,
                payload: .nodeRegistered(
                    GraphNodeRegisteredPayload(
                        title: node.title,
                        dependencyNodeIDs: node.dependencyNodeIDs
                    )
                )
            )
        )
    }
    return events
}
