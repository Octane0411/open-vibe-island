import Foundation

/// Compatibility result produced by the recovered prototype executor.
public struct AgentTaskExecutionResult: Sendable {
    public let output: String

    public init(output: String) {
        self.output = output
    }
}

public enum AgentGraphExecutionError: LocalizedError, Sendable {
    case cyclicGraph
    case stalledGraph

    public var errorDescription: String? {
        switch self {
        case .cyclicGraph:
            return "The task graph contains a dependency cycle."
        case .stalledGraph:
            return "The task graph cannot make further progress."
        }
    }
}

/// Recovered in-memory executor.
///
/// This actor remains useful for simulation and migration tests. It is not
/// authoritative for process lifecycle because it has no attempt identity,
/// heartbeat, exit, or replay boundary.
public actor AgentGraphExecutor {
    public typealias NodeRunner = @Sendable (
        AgentTaskNode,
        [AgentTaskNode]
    ) async throws -> AgentTaskExecutionResult

    public typealias GraphUpdateHandler = @Sendable (
        AgentTaskGraph
    ) async -> Void

    private var graph: AgentTaskGraph
    private let maximumParallelTasks: Int
    private let runner: NodeRunner

    public init(
        graph: AgentTaskGraph,
        maximumParallelTasks: Int = 3,
        runner: @escaping NodeRunner
    ) {
        self.graph = graph
        self.maximumParallelTasks = max(1, maximumParallelTasks)
        self.runner = runner
    }

    public func snapshot() -> AgentTaskGraph {
        graph
    }

    public func execute(
        onUpdate: @escaping GraphUpdateHandler = { _ in }
    ) async throws -> AgentTaskGraph {
        guard !graph.containsCycle() else {
            throw AgentGraphExecutionError.cyclicGraph
        }

        graph.refreshSchedulingStates()
        await onUpdate(graph)

        while graph.nodes.contains(where: {
            !$0.state.isTerminal
        }) {
            let readyNodes = graph.nodes
                .filter { $0.state == .ready }
                .prefix(maximumParallelTasks)

            guard !readyNodes.isEmpty else {
                graph.refreshSchedulingStates()

                if graph.nodes.contains(where: { $0.state == .ready }) {
                    continue
                }

                throw AgentGraphExecutionError.stalledGraph
            }

            let batch = Array(readyNodes)

            for node in batch {
                updateNode(node.id) {
                    $0.state = .running
                    $0.startedAt = .now
                    $0.errorMessage = nil
                }
            }

            await onUpdate(graph)

            let results = await withTaskGroup(
                of: NodeOutcome.self,
                returning: [NodeOutcome].self
            ) { group in
                for node in batch {
                    let dependencies = graph.dependencies(of: node.id)
                    let runner = self.runner

                    group.addTask {
                        do {
                            let result = try await runner(
                                node,
                                dependencies
                            )
                            return .success(
                                nodeID: node.id,
                                result: result
                            )
                        } catch {
                            return .failure(
                                nodeID: node.id,
                                message: error.localizedDescription
                            )
                        }
                    }
                }

                var outcomes: [NodeOutcome] = []

                for await outcome in group {
                    outcomes.append(outcome)
                }

                return outcomes
            }

            for outcome in results {
                switch outcome {
                case let .success(nodeID, result):
                    updateNode(nodeID) {
                        $0.state = .completed
                        $0.output = result.output
                        $0.completedAt = .now
                    }

                case let .failure(nodeID, message):
                    updateNode(nodeID) {
                        $0.state = .failed
                        $0.errorMessage = message
                        $0.completedAt = .now
                    }
                }
            }

            graph.refreshSchedulingStates()
            await onUpdate(graph)
        }

        return graph
    }

    private func updateNode(
        _ nodeID: UUID,
        mutation: (inout AgentTaskNode) -> Void
    ) {
        guard let index = graph.nodes.firstIndex(where: {
            $0.id == nodeID
        }) else {
            return
        }

        mutation(&graph.nodes[index])
        graph.updatedAt = .now
    }
}

private enum NodeOutcome: Sendable {
    case success(
        nodeID: UUID,
        result: AgentTaskExecutionResult
    )
    case failure(
        nodeID: UUID,
        message: String
    )
}

private extension AgentTaskNodeState {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .pending, .blocked, .ready, .running:
            return false
        }
    }
}
