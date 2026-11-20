import XCTest
@testable import OpenIslandCore

final class AgentTaskGraphTests: XCTestCase {
    func testRootNodesBecomeReady() {
        let root = AgentTaskNode(
            title: "Research",
            instructions: "Research the problem.",
            executionKind: .gemini
        )

        let dependent = AgentTaskNode(
            title: "Implement",
            instructions: "Implement the result.",
            executionKind: .codex
        )

        var graph = AgentTaskGraph(
            title: "Test",
            nodes: [root, dependent],
            edges: [
                AgentTaskEdge(
                    sourceNodeID: root.id,
                    destinationNodeID: dependent.id
                ),
            ]
        )

        graph.refreshSchedulingStates()

        XCTAssertEqual(
            graph.node(withID: root.id)?.state,
            .ready
        )

        XCTAssertEqual(
            graph.node(withID: dependent.id)?.state,
            .blocked
        )
    }

    func testCompletedDependencyUnblocksDependentNode() {
        var root = AgentTaskNode(
            title: "Research",
            instructions: "Research.",
            executionKind: .gemini
        )
        root.state = .completed

        let dependent = AgentTaskNode(
            title: "Implement",
            instructions: "Implement.",
            executionKind: .codex
        )

        var graph = AgentTaskGraph(
            title: "Test",
            nodes: [root, dependent],
            edges: [
                AgentTaskEdge(
                    sourceNodeID: root.id,
                    destinationNodeID: dependent.id
                ),
            ]
        )

        graph.refreshSchedulingStates()

        XCTAssertEqual(
            graph.node(withID: dependent.id)?.state,
            .ready
        )
    }

    func testCycleDetection() {
        let first = AgentTaskNode(
            title: "First",
            instructions: "",
            executionKind: .ollama
        )

        let second = AgentTaskNode(
            title: "Second",
            instructions: "",
            executionKind: .ollama
        )

        let graph = AgentTaskGraph(
            title: "Cycle",
            nodes: [first, second],
            edges: [
                AgentTaskEdge(
                    sourceNodeID: first.id,
                    destinationNodeID: second.id
                ),
                AgentTaskEdge(
                    sourceNodeID: second.id,
                    destinationNodeID: first.id
                ),
            ]
        )

        XCTAssertTrue(graph.containsCycle())
    }

    func testExecutorRunsDependencyChain() async throws {
        let research = AgentTaskNode(
            title: "Research",
            instructions: "Research.",
            executionKind: .gemini
        )

        let implementation = AgentTaskNode(
            title: "Implementation",
            instructions: "Implement.",
            executionKind: .codex
        )

        let review = AgentTaskNode(
            title: "Review",
            instructions: "Review.",
            executionKind: .ollama
        )

        let graph = AgentTaskGraph(
            title: "Pipeline",
            nodes: [research, implementation, review],
            edges: [
                AgentTaskEdge(
                    sourceNodeID: research.id,
                    destinationNodeID: implementation.id
                ),
                AgentTaskEdge(
                    sourceNodeID: implementation.id,
                    destinationNodeID: review.id
                ),
            ]
        )

        let executor = AgentGraphExecutor(graph: graph) {
            node,
            dependencies in

            AgentTaskExecutionResult(
                output: "\(node.title): \(dependencies.count) inputs"
            )
        }

        let completed = try await executor.execute()

        XCTAssertTrue(
            completed.nodes.allSatisfy {
                $0.state == .completed
            }
        )
    }
}
