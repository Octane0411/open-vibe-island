import Foundation

public enum GraphExecutableDefinitionSchema {
    public static let currentVersion = 1
}

public enum GraphArtifactRole: String, Codable, CaseIterable, Sendable {
    case nodeOutput = "node_output"
    case executionLog = "execution_log"
    case structuredResult = "structured_result"
    case diagnostic
}

public struct GraphExecutionWorkspaceContext:
    Equatable,
    Codable,
    Sendable
{
    public let root: String?
    public let writableRelativePaths: [String]

    public init(
        root: String? = nil,
        writableRelativePaths: [String] = []
    ) {
        self.root = root
        self.writableRelativePaths = writableRelativePaths.sorted()
    }
}

public struct GraphExecutionTimeoutPolicy: Equatable, Codable, Sendable {
    public let executionSeconds: UInt64
    public let cancellationAcknowledgementSeconds: UInt64

    public init(
        executionSeconds: UInt64,
        cancellationAcknowledgementSeconds: UInt64
    ) {
        self.executionSeconds = max(1, executionSeconds)
        self.cancellationAcknowledgementSeconds = max(
            1,
            cancellationAcknowledgementSeconds
        )
    }
}

public struct GraphImmutableExecutionSpecification:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let adapterKind: String
    public let operation: String
    public let parameters: [String: GraphJSONValue]

    public init(
        schemaVersion: Int = GraphExecutableDefinitionSchema.currentVersion,
        adapterKind: String,
        operation: String,
        parameters: [String: GraphJSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.adapterKind = adapterKind
        self.operation = operation
        self.parameters = parameters
    }
}

public struct GraphNodeExecutionDefinition:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public var id: String { nodeID }

    public let nodeID: String
    public let capabilityRequirement: [String]
    public let specification: GraphImmutableExecutionSpecification
    public let workspace: GraphExecutionWorkspaceContext
    public let environmentAllowlist: [String]
    public let inputArtifactRoles: [GraphArtifactRole]
    public let timeoutPolicy: GraphExecutionTimeoutPolicy

    public init(
        nodeID: String,
        capabilityRequirement: [String],
        specification: GraphImmutableExecutionSpecification,
        workspace: GraphExecutionWorkspaceContext =
            GraphExecutionWorkspaceContext(),
        environmentAllowlist: [String] = [],
        inputArtifactRoles: [GraphArtifactRole] = [.nodeOutput],
        timeoutPolicy: GraphExecutionTimeoutPolicy
    ) {
        self.nodeID = nodeID
        self.capabilityRequirement = capabilityRequirement.sorted()
        self.specification = specification
        self.workspace = workspace
        self.environmentAllowlist = environmentAllowlist.sorted()
        self.inputArtifactRoles = inputArtifactRoles.sorted {
            $0.rawValue < $1.rawValue
        }
        self.timeoutPolicy = timeoutPolicy
    }
}

public enum GraphExecutableDefinitionError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case duplicateNodeID(String)
    case missingExecutionSpecification(String)
    case unknownExecutionNode(String)
    case capabilityMismatch(String)
}

extension GraphExecutableDefinitionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "Executable graph schema version \(version) is unsupported."
        case let .duplicateNodeID(nodeID):
            "Executable graph contains duplicate node \(nodeID)."
        case let .missingExecutionSpecification(nodeID):
            "Node \(nodeID) has no execution specification."
        case let .unknownExecutionNode(nodeID):
            "Execution specification references unknown node \(nodeID)."
        case let .capabilityMismatch(nodeID):
            "Node \(nodeID) capability requirements do not match scheduling."
        }
    }
}

public struct GraphExecutableDefinition: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let scheduling: GraphSchedulingDefinition
    public let schedulerPolicy: GraphSchedulerPolicy
    public let executions: [GraphNodeExecutionDefinition]

    public init(
        schemaVersion: Int = GraphExecutableDefinitionSchema.currentVersion,
        scheduling: GraphSchedulingDefinition,
        schedulerPolicy: GraphSchedulerPolicy,
        executions: [GraphNodeExecutionDefinition]
    ) {
        self.schemaVersion = schemaVersion
        self.scheduling = scheduling
        self.schedulerPolicy = schedulerPolicy
        self.executions = executions.sorted { $0.nodeID < $1.nodeID }
    }

    public func validate() throws {
        guard schemaVersion <= GraphExecutableDefinitionSchema.currentVersion
        else {
            throw GraphExecutableDefinitionError.unsupportedSchema(
                schemaVersion
            )
        }
        let schedulingIDs = scheduling.nodes.map(\.id)
        guard Set(schedulingIDs).count == schedulingIDs.count else {
            let duplicate = Dictionary(grouping: schedulingIDs, by: { $0 })
                .first { $0.value.count > 1 }?.key ?? "unknown"
            throw GraphExecutableDefinitionError.duplicateNodeID(duplicate)
        }
        let executionByNode = Dictionary(
            grouping: executions,
            by: \.nodeID
        )
        for node in scheduling.nodes {
            guard let matches = executionByNode[node.id], !matches.isEmpty else {
                throw GraphExecutableDefinitionError
                    .missingExecutionSpecification(node.id)
            }
            guard matches.count == 1 else {
                throw GraphExecutableDefinitionError.duplicateNodeID(node.id)
            }
            guard matches[0].capabilityRequirement
                    == node.requiredCapabilities else {
                throw GraphExecutableDefinitionError.capabilityMismatch(node.id)
            }
        }
        for execution in executions
            where !schedulingIDs.contains(execution.nodeID) {
            throw GraphExecutableDefinitionError
                .unknownExecutionNode(execution.nodeID)
        }
    }

    public func execution(
        for nodeID: String
    ) -> GraphNodeExecutionDefinition? {
        executions.first { $0.nodeID == nodeID }
    }
}
