import Foundation

/// Recovered graph-prototype state.
///
/// This type remains a compatibility model while authoritative execution
/// lifecycle moves into the run/attempt/process model. New adapters should
/// not persist process truth in this enum.
public enum AgentTaskNodeState: String, Codable, CaseIterable, Sendable {
    case pending
    case blocked
    case ready
    case running
    case completed
    case failed
    case cancelled
}

public enum AgentExecutionKind: String, Codable, CaseIterable, Sendable {
    case codex
    case gemini
    case openCode
    case ollama
    case openClaw
    case human
}

public struct AgentTaskNode: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var instructions: String
    public var executionKind: AgentExecutionKind
    public var agentProfile: String?
    public var state: AgentTaskNodeState
    public var output: String?
    public var errorMessage: String?
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        instructions: String,
        executionKind: AgentExecutionKind,
        agentProfile: String? = nil,
        state: AgentTaskNodeState = .pending,
        output: String? = nil,
        errorMessage: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.instructions = instructions
        self.executionKind = executionKind
        self.agentProfile = agentProfile
        self.state = state
        self.output = output
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public struct AgentTaskEdge: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let sourceNodeID: UUID
    public let destinationNodeID: UUID

    public init(
        id: UUID = UUID(),
        sourceNodeID: UUID,
        destinationNodeID: UUID
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.destinationNodeID = destinationNodeID
    }
}

public struct AgentTaskGraph: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var nodes: [AgentTaskNode]
    public var edges: [AgentTaskEdge]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        nodes: [AgentTaskNode] = [],
        edges: [AgentTaskEdge] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.nodes = nodes
        self.edges = edges
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func dependencies(of nodeID: UUID) -> [AgentTaskNode] {
        let dependencyIDs = edges
            .filter { $0.destinationNodeID == nodeID }
            .map(\.sourceNodeID)

        return nodes.filter { dependencyIDs.contains($0.id) }
    }

    public func dependents(of nodeID: UUID) -> [AgentTaskNode] {
        let dependentIDs = edges
            .filter { $0.sourceNodeID == nodeID }
            .map(\.destinationNodeID)

        return nodes.filter { dependentIDs.contains($0.id) }
    }

    public func node(withID nodeID: UUID) -> AgentTaskNode? {
        nodes.first { $0.id == nodeID }
    }

    public func isReady(_ node: AgentTaskNode) -> Bool {
        guard node.state == .pending
                || node.state == .blocked
                || node.state == .ready else {
            return false
        }

        let dependencies = dependencies(of: node.id)
        return dependencies.allSatisfy { $0.state == .completed }
    }

    public func containsCycle() -> Bool {
        var visiting: Set<UUID> = []
        var visited: Set<UUID> = []

        func visit(_ nodeID: UUID) -> Bool {
            if visiting.contains(nodeID) {
                return true
            }

            if visited.contains(nodeID) {
                return false
            }

            visiting.insert(nodeID)

            for dependent in dependents(of: nodeID) {
                if visit(dependent.id) {
                    return true
                }
            }

            visiting.remove(nodeID)
            visited.insert(nodeID)
            return false
        }

        return nodes.contains { visit($0.id) }
    }

    public mutating func refreshSchedulingStates() {
        for index in nodes.indices {
            switch nodes[index].state {
            case .completed, .failed, .cancelled, .running:
                continue

            case .pending, .blocked, .ready:
                let dependencies = dependencies(of: nodes[index].id)

                if dependencies.contains(where: {
                    $0.state == .failed || $0.state == .cancelled
                }) {
                    nodes[index].state = .blocked
                } else if dependencies.allSatisfy({
                    $0.state == .completed
                }) {
                    nodes[index].state = .ready
                } else {
                    nodes[index].state = .blocked
                }
            }
        }

        updatedAt = .now
    }
}
