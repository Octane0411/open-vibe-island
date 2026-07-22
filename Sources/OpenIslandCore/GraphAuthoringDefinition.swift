import Foundation

public enum GraphDefinitionNodeType: String, Codable, CaseIterable, Sendable {
    case localProcess = "local_process"
    case deterministicTest = "deterministic_test"
    case genericAgent = "generic_agent"
    case input
    case output
    case annotation

    public var isExecutable: Bool {
        switch self {
        case .localProcess, .deterministicTest, .genericAgent:
            true
        case .input, .output, .annotation:
            false
        }
    }

    public var isRunnable: Bool {
        self == .localProcess || self == .deterministicTest
    }
}

public enum GraphDefinitionExecutorKind: String, Codable, CaseIterable, Sendable {
    case supervisedLocalProcess = "local_process"
    case deterministicTest = "deterministic"
    case unboundAgent = "generic_agent"
    case none

    public var displayName: String {
        switch self {
        case .supervisedLocalProcess: "Supervised Local Process"
        case .deterministicTest: "Deterministic Test Executor"
        case .unboundAgent: "Generic Agent (not configured)"
        case .none: "No Executor"
        }
    }
}

public enum GraphDefinitionPortType: String, Codable, CaseIterable, Sendable {
    case dependency
    case artifact
    case stream
    case signal
}

public enum GraphNodeInputBindingKind: String, Codable, CaseIterable, Sendable {
    case graphInput = "graph_input"
    case upstreamArtifact = "upstream_artifact"
    case upstreamArtifactCollection = "upstream_artifact_collection"
    case staticLiteral = "static_literal"
    case fileReference = "file_reference"
    case secretReference = "secret_reference"
}

public struct GraphNodeInputBinding: Equatable, Codable, Sendable {
    public var kind: GraphNodeInputBindingKind
    public var graphInputID: String?
    public var sourceNodeID: String?
    public var sourceOutputID: String?
    public var literalValue: GraphJSONValue?
    public var fileReference: String?
    public var secretReference: String?

    public init(
        kind: GraphNodeInputBindingKind,
        graphInputID: String? = nil,
        sourceNodeID: String? = nil,
        sourceOutputID: String? = nil,
        literalValue: GraphJSONValue? = nil,
        fileReference: String? = nil,
        secretReference: String? = nil
    ) {
        self.kind = kind
        self.graphInputID = graphInputID
        self.sourceNodeID = sourceNodeID
        self.sourceOutputID = sourceOutputID
        self.literalValue = literalValue
        self.fileReference = fileReference
        self.secretReference = secretReference
    }
}

public struct GraphNodeInputDefinition:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public var name: String
    public var portType: GraphDefinitionPortType
    public var mediaType: String
    public var isRequired: Bool
    public var allowsMultiple: Bool
    public var binding: GraphNodeInputBinding?

    public init(
        id: String,
        name: String,
        portType: GraphDefinitionPortType = .artifact,
        mediaType: String = "application/octet-stream",
        isRequired: Bool = true,
        allowsMultiple: Bool = false,
        binding: GraphNodeInputBinding? = nil
    ) {
        self.id = id
        self.name = name
        self.portType = portType
        self.mediaType = mediaType
        self.isRequired = isRequired
        self.allowsMultiple = allowsMultiple
        self.binding = binding
    }
}

public enum GraphArtifactDownstreamVisibility: String, Codable, Sendable {
    case graph
    case directDependents = "direct_dependents"
    case privateToNode = "private_to_node"
}

public struct GraphNodeOutputDefinition:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public var name: String
    public var portType: GraphDefinitionPortType
    public var role: GraphArtifactRole
    public var relativePath: String
    public var mediaType: String
    public var isRequired: Bool
    public var maximumBytes: Int
    public var sensitivity: GraphArtifactSensitivity
    public var downstreamVisibility: GraphArtifactDownstreamVisibility

    public init(
        id: String,
        name: String,
        portType: GraphDefinitionPortType = .artifact,
        role: GraphArtifactRole = .nodeOutput,
        relativePath: String,
        mediaType: String = "application/octet-stream",
        isRequired: Bool = true,
        maximumBytes: Int = 64 * 1_024 * 1_024,
        sensitivity: GraphArtifactSensitivity = .internalUse,
        downstreamVisibility: GraphArtifactDownstreamVisibility = .graph
    ) {
        self.id = id
        self.name = name
        self.portType = portType
        self.role = role
        self.relativePath = relativePath
        self.mediaType = mediaType
        self.isRequired = isRequired
        self.maximumBytes = max(1, maximumBytes)
        self.sensitivity = sensitivity
        self.downstreamVisibility = downstreamVisibility
    }
}

public struct GraphNodeRetryConfiguration: Equatable, Codable, Sendable {
    public var inheritsGraphDefault: Bool
    public var override: GraphRetryPolicy?

    public init(
        inheritsGraphDefault: Bool = true,
        override: GraphRetryPolicy? = nil
    ) {
        self.inheritsGraphDefault = inheritsGraphDefault
        self.override = override
    }

    public func effective(graphDefault: GraphRetryPolicy) -> GraphRetryPolicy {
        inheritsGraphDefault ? graphDefault : (override ?? graphDefault)
    }
}

public struct GraphNodeTimeoutConfiguration: Equatable, Codable, Sendable {
    public var inheritsGraphDefault: Bool
    public var executionSeconds: UInt64
    public var cancellationAcknowledgementSeconds: UInt64
    public var claimSeconds: UInt64

    public init(
        inheritsGraphDefault: Bool = true,
        executionSeconds: UInt64 = 300,
        cancellationAcknowledgementSeconds: UInt64 = 10,
        claimSeconds: UInt64 = 30
    ) {
        self.inheritsGraphDefault = inheritsGraphDefault
        self.executionSeconds = executionSeconds
        self.cancellationAcknowledgementSeconds = cancellationAcknowledgementSeconds
        self.claimSeconds = claimSeconds
    }
}

public enum GraphDefinitionDataType: String, Codable, CaseIterable, Sendable {
    case text
    case json
    case fileReference = "file_reference"
    case directoryReference = "directory_reference"
    case artifactReference = "artifact_reference"
    case number
    case boolean
}

public struct GraphDefinitionInput:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public var name: String
    public var dataType: GraphDefinitionDataType
    public var isRequired: Bool
    public var isSensitive: Bool
    public var defaultValue: GraphJSONValue?

    public init(
        id: String,
        name: String,
        dataType: GraphDefinitionDataType,
        isRequired: Bool = true,
        isSensitive: Bool = false,
        defaultValue: GraphJSONValue? = nil
    ) {
        self.id = id
        self.name = name
        self.dataType = dataType
        self.isRequired = isRequired
        self.isSensitive = isSensitive
        self.defaultValue = defaultValue
    }
}

public struct GraphDefinitionOutput:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public var name: String
    public var sourceNodeID: String
    public var sourceOutputID: String

    public init(
        id: String,
        name: String,
        sourceNodeID: String,
        sourceOutputID: String
    ) {
        self.id = id
        self.name = name
        self.sourceNodeID = sourceNodeID
        self.sourceOutputID = sourceOutputID
    }
}
