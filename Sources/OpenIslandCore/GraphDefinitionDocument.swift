import CryptoKit
import Foundation

public enum GraphDefinitionDocumentSchema {
    public static let currentVersion = 1
    public static let layoutVersion = 1
}

public struct GraphDefinitionDocumentMetadata:
    Equatable,
    Codable,
    Sendable
{
    public let createdAt: Date
    public var modifiedAt: Date
    public let createdBy: String
    public var modifiedBy: String

    public init(
        createdAt: Date,
        modifiedAt: Date,
        createdBy: String,
        modifiedBy: String
    ) {
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.createdBy = createdBy
        self.modifiedBy = modifiedBy
    }
}

public struct GraphSourceRepositoryContext:
    Equatable,
    Codable,
    Sendable
{
    public let repositoryPath: String?
    public let remoteURL: String?
    public let revision: String?

    public init(
        repositoryPath: String? = nil,
        remoteURL: String? = nil,
        revision: String? = nil
    ) {
        self.repositoryPath = repositoryPath
        self.remoteURL = remoteURL
        self.revision = revision
    }
}

public struct GraphCanvasPoint: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct GraphNodeLayoutMetadata:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public var id: String { nodeID }
    public let nodeID: String
    public var position: GraphCanvasPoint
    public var groupID: String?

    public init(
        nodeID: String,
        position: GraphCanvasPoint,
        groupID: String? = nil
    ) {
        self.nodeID = nodeID
        self.position = position
        self.groupID = groupID
    }
}

public struct GraphLayoutMetadata: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public var nodes: [GraphNodeLayoutMetadata]
    public var zoom: Double
    public var pan: GraphCanvasPoint

    public init(
        schemaVersion: Int = GraphDefinitionDocumentSchema.layoutVersion,
        nodes: [GraphNodeLayoutMetadata] = [],
        zoom: Double = 1,
        pan: GraphCanvasPoint = GraphCanvasPoint(x: 0, y: 0)
    ) {
        self.schemaVersion = schemaVersion
        self.nodes = nodes.sorted { $0.nodeID < $1.nodeID }
        self.zoom = min(2.5, max(0.25, zoom))
        self.pan = pan
    }

    public func position(nodeID: String) -> GraphCanvasPoint? {
        nodes.first { $0.nodeID == nodeID }?.position
    }
}

public struct GraphDefinitionDocumentNode:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public var name: String
    public var description: String
    public var nodeType: GraphDefinitionNodeType
    public var tags: [String]
    public var requiredCapabilities: [String]
    public var preferredCapabilities: [String]
    public var executorKind: GraphDefinitionExecutorKind
    public var platformConstraints: [String]
    public var specification: GraphImmutableExecutionSpecification
    public var workspace: GraphExecutionWorkspaceContext
    public var environmentAllowlist: [String]
    public var inputArtifactRoles: [GraphArtifactRole]
    public var inputs: [GraphNodeInputDefinition]
    public var outputs: [GraphNodeOutputDefinition]
    public var retryConfiguration: GraphNodeRetryConfiguration
    public var timeoutPolicy: GraphExecutionTimeoutPolicy
    public var timeoutConfiguration: GraphNodeTimeoutConfiguration

    public init(
        id: String,
        name: String,
        description: String = "",
        nodeType: GraphDefinitionNodeType? = nil,
        tags: [String] = [],
        requiredCapabilities: [String],
        preferredCapabilities: [String] = [],
        executorKind: GraphDefinitionExecutorKind? = nil,
        platformConstraints: [String] = [],
        specification: GraphImmutableExecutionSpecification,
        workspace: GraphExecutionWorkspaceContext = .init(),
        environmentAllowlist: [String] = [],
        inputArtifactRoles: [GraphArtifactRole] = [.nodeOutput],
        inputs: [GraphNodeInputDefinition] = [],
        outputs: [GraphNodeOutputDefinition] = [],
        retryConfiguration: GraphNodeRetryConfiguration = .init(),
        timeoutPolicy: GraphExecutionTimeoutPolicy,
        timeoutConfiguration: GraphNodeTimeoutConfiguration? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        let inferredType = nodeType ?? Self.inferNodeType(specification)
        self.nodeType = inferredType
        self.tags = tags.sorted()
        self.requiredCapabilities = requiredCapabilities.sorted()
        self.preferredCapabilities = preferredCapabilities.sorted()
        self.executorKind = executorKind
            ?? Self.inferExecutorKind(specification, nodeType: inferredType)
        self.platformConstraints = platformConstraints.sorted()
        self.specification = specification
        self.workspace = workspace
        self.environmentAllowlist = environmentAllowlist.sorted()
        self.inputArtifactRoles = inputArtifactRoles.sorted {
            $0.rawValue < $1.rawValue
        }
        self.inputs = inputs.sorted { $0.id < $1.id }
        self.outputs = outputs.isEmpty
            ? Self.inferOutputs(specification) : outputs.sorted { $0.id < $1.id }
        self.retryConfiguration = retryConfiguration
        self.timeoutPolicy = timeoutPolicy
        self.timeoutConfiguration = timeoutConfiguration
            ?? GraphNodeTimeoutConfiguration(
                executionSeconds: timeoutPolicy.executionSeconds,
                cancellationAcknowledgementSeconds:
                    timeoutPolicy.cancellationAcknowledgementSeconds
            )
    }

    private static func inferNodeType(
        _ specification: GraphImmutableExecutionSpecification
    ) -> GraphDefinitionNodeType {
        switch specification.adapterKind {
        case GraphLocalProcessSpecification.adapterKind: .localProcess
        case "deterministic": .deterministicTest
        case "generic_agent": .genericAgent
        default: .genericAgent
        }
    }

    private static func inferExecutorKind(
        _ specification: GraphImmutableExecutionSpecification,
        nodeType: GraphDefinitionNodeType
    ) -> GraphDefinitionExecutorKind {
        switch specification.adapterKind {
        case GraphLocalProcessSpecification.adapterKind: .supervisedLocalProcess
        case "deterministic": .deterministicTest
        case "openai_compatible": .openAICompatible
        case "generic_agent": .unboundAgent
        default: nodeType.isExecutable ? .unboundAgent : .none
        }
    }

    private static func inferOutputs(
        _ specification: GraphImmutableExecutionSpecification
    ) -> [GraphNodeOutputDefinition] {
        guard specification.adapterKind == GraphLocalProcessSpecification.adapterKind,
              let process = try? GraphLocalProcessSpecification(
                immutableSpecification: specification
              ) else { return [] }
        return process.outputArtifacts.map { declaration in
            GraphNodeOutputDefinition(
                id: declaration.stableID,
                name: declaration.role.rawValue,
                role: declaration.role,
                relativePath: declaration.relativePath,
                mediaType: declaration.mediaType,
                isRequired: declaration.required,
                maximumBytes: declaration.maximumBytes,
                sensitivity: declaration.sensitivity,
                downstreamVisibility: declaration.downstreamVisibility ?? .graph
            )
        }.sorted { $0.id < $1.id }
    }
}

extension GraphDefinitionDocumentNode {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case nodeType
        case tags
        case requiredCapabilities
        case preferredCapabilities
        case executorKind
        case platformConstraints
        case specification
        case workspace
        case environmentAllowlist
        case inputArtifactRoles
        case inputs
        case outputs
        case retryConfiguration
        case timeoutPolicy
        case timeoutConfiguration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let specification = try container.decode(
            GraphImmutableExecutionSpecification.self,
            forKey: .specification
        )
        let timeoutPolicy = try container.decode(
            GraphExecutionTimeoutPolicy.self,
            forKey: .timeoutPolicy
        )
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            description: try container.decodeIfPresent(
                String.self,
                forKey: .description
            ) ?? "",
            nodeType: try container.decodeIfPresent(
                GraphDefinitionNodeType.self,
                forKey: .nodeType
            ),
            tags: try container.decodeIfPresent(
                [String].self,
                forKey: .tags
            ) ?? [],
            requiredCapabilities: try container.decode(
                [String].self,
                forKey: .requiredCapabilities
            ),
            preferredCapabilities: try container.decodeIfPresent(
                [String].self,
                forKey: .preferredCapabilities
            ) ?? [],
            executorKind: try container.decodeIfPresent(
                GraphDefinitionExecutorKind.self,
                forKey: .executorKind
            ),
            platformConstraints: try container.decodeIfPresent(
                [String].self,
                forKey: .platformConstraints
            ) ?? [],
            specification: specification,
            workspace: try container.decodeIfPresent(
                GraphExecutionWorkspaceContext.self,
                forKey: .workspace
            ) ?? .init(),
            environmentAllowlist: try container.decodeIfPresent(
                [String].self,
                forKey: .environmentAllowlist
            ) ?? [],
            inputArtifactRoles: try container.decodeIfPresent(
                [GraphArtifactRole].self,
                forKey: .inputArtifactRoles
            ) ?? [.nodeOutput],
            inputs: try container.decodeIfPresent(
                [GraphNodeInputDefinition].self,
                forKey: .inputs
            ) ?? [],
            outputs: try container.decodeIfPresent(
                [GraphNodeOutputDefinition].self,
                forKey: .outputs
            ) ?? [],
            retryConfiguration: try container.decodeIfPresent(
                GraphNodeRetryConfiguration.self,
                forKey: .retryConfiguration
            ) ?? .init(),
            timeoutPolicy: timeoutPolicy,
            timeoutConfiguration: try container.decodeIfPresent(
                GraphNodeTimeoutConfiguration.self,
                forKey: .timeoutConfiguration
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(nodeType, forKey: .nodeType)
        try container.encode(tags.sorted(), forKey: .tags)
        try container.encode(requiredCapabilities.sorted(), forKey: .requiredCapabilities)
        try container.encode(preferredCapabilities.sorted(), forKey: .preferredCapabilities)
        try container.encode(executorKind, forKey: .executorKind)
        try container.encode(platformConstraints.sorted(), forKey: .platformConstraints)
        try container.encode(specification, forKey: .specification)
        try container.encode(workspace, forKey: .workspace)
        try container.encode(environmentAllowlist.sorted(), forKey: .environmentAllowlist)
        try container.encode(inputArtifactRoles, forKey: .inputArtifactRoles)
        try container.encode(inputs.sorted { $0.id < $1.id }, forKey: .inputs)
        try container.encode(outputs.sorted { $0.id < $1.id }, forKey: .outputs)
        try container.encode(retryConfiguration, forKey: .retryConfiguration)
        try container.encode(timeoutPolicy, forKey: .timeoutPolicy)
        try container.encode(timeoutConfiguration, forKey: .timeoutConfiguration)
    }
}

public struct GraphDefinitionEdge:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public var id: String { edgeID }
    public let edgeID: String
    public var sourceNodeID: String
    public var targetNodeID: String
    public var portType: GraphDefinitionPortType
    public var sourceOutputID: String?
    public var targetInputID: String?
    public var isRequired: Bool

    public init(
        edgeID: String? = nil,
        sourceNodeID: String,
        targetNodeID: String,
        portType: GraphDefinitionPortType = .dependency,
        sourceOutputID: String? = nil,
        targetInputID: String? = nil,
        isRequired: Bool = true
    ) {
        self.edgeID = edgeID ?? Self.stableID(
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            portType: portType,
            sourceOutputID: sourceOutputID,
            targetInputID: targetInputID
        )
        self.sourceNodeID = sourceNodeID
        self.targetNodeID = targetNodeID
        self.portType = portType
        self.sourceOutputID = sourceOutputID
        self.targetInputID = targetInputID
        self.isRequired = isRequired
    }

    private static func stableID(
        sourceNodeID: String,
        targetNodeID: String,
        portType: GraphDefinitionPortType,
        sourceOutputID: String?,
        targetInputID: String?
    ) -> String {
        [
            sourceNodeID,
            targetNodeID,
            portType.rawValue,
            sourceOutputID ?? "none",
            targetInputID ?? "none",
        ].joined(separator: "->")
    }

    private enum CodingKeys: String, CodingKey {
        case edgeID
        case sourceNodeID
        case targetNodeID
        case portType
        case sourceOutputID
        case targetInputID
        case isRequired
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            edgeID: try container.decodeIfPresent(String.self, forKey: .edgeID),
            sourceNodeID: try container.decode(String.self, forKey: .sourceNodeID),
            targetNodeID: try container.decode(String.self, forKey: .targetNodeID),
            portType: try container.decodeIfPresent(
                GraphDefinitionPortType.self,
                forKey: .portType
            ) ?? .dependency,
            sourceOutputID: try container.decodeIfPresent(
                String.self,
                forKey: .sourceOutputID
            ),
            targetInputID: try container.decodeIfPresent(
                String.self,
                forKey: .targetInputID
            ),
            isRequired: try container.decodeIfPresent(
                Bool.self,
                forKey: .isRequired
            ) ?? true
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(edgeID, forKey: .edgeID)
        try container.encode(sourceNodeID, forKey: .sourceNodeID)
        try container.encode(targetNodeID, forKey: .targetNodeID)
        try container.encode(portType, forKey: .portType)
        try container.encodeIfPresent(sourceOutputID, forKey: .sourceOutputID)
        try container.encodeIfPresent(targetInputID, forKey: .targetInputID)
        try container.encode(isRequired, forKey: .isRequired)
    }
}

public struct GraphDefinitionDocument: Equatable, Sendable {
    public let schemaVersion: Int
    public var graphID: String
    public var definitionVersion: String
    public var name: String
    public var description: String
    public var graphInputs: [GraphDefinitionInput]
    public var graphOutputs: [GraphDefinitionOutput]
    public var nodes: [GraphDefinitionDocumentNode]
    public var edges: [GraphDefinitionEdge]
    public var schedulerPolicy: GraphSchedulerPolicy
    public var policyReferences: [String]
    public var layout: GraphLayoutMetadata
    public var metadata: GraphDefinitionDocumentMetadata
    public var sourceRepository: GraphSourceRepositoryContext?
    public var extensionFields: [String: GraphJSONValue]

    public init(
        schemaVersion: Int = GraphDefinitionDocumentSchema.currentVersion,
        graphID: String,
        definitionVersion: String,
        name: String,
        description: String = "",
        graphInputs: [GraphDefinitionInput] = [],
        graphOutputs: [GraphDefinitionOutput] = [],
        nodes: [GraphDefinitionDocumentNode],
        edges: [GraphDefinitionEdge],
        schedulerPolicy: GraphSchedulerPolicy,
        policyReferences: [String] = [],
        layout: GraphLayoutMetadata = GraphLayoutMetadata(),
        metadata: GraphDefinitionDocumentMetadata,
        sourceRepository: GraphSourceRepositoryContext? = nil,
        extensionFields: [String: GraphJSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.graphID = graphID
        self.definitionVersion = definitionVersion
        self.name = name
        self.description = description
        self.graphInputs = graphInputs.sorted { $0.id < $1.id }
        self.graphOutputs = graphOutputs.sorted { $0.id < $1.id }
        self.nodes = nodes.sorted { $0.id < $1.id }
        self.edges = edges.sorted { $0.id < $1.id }
        self.schedulerPolicy = schedulerPolicy
        self.policyReferences = policyReferences.sorted()
        self.layout = layout
        self.metadata = metadata
        self.sourceRepository = sourceRepository
        self.extensionFields = extensionFields
    }

    public static func empty(
        graphID: String = UUID().uuidString.lowercased(),
        now: Date = Date(),
        author: String = NSUserName()
    ) -> GraphDefinitionDocument {
        GraphDefinitionDocument(
            graphID: graphID,
            definitionVersion: "1",
            name: "Untitled Graph",
            nodes: [],
            edges: [],
            schedulerPolicy: GraphSchedulerPolicy(
                policyID: "default-local-policy",
                version: "1",
                retryPolicy: GraphRetryPolicy(
                    maximumAttempts: 2,
                    retryableFailureCategories: [
                        "execution_failure",
                        "process_exit_unobserved",
                        "timeout",
                    ],
                    nonRetryableFailureCategories: [
                        "artifact_collection_failure",
                        "invalid_process_specification",
                    ]
                )
            ),
            metadata: GraphDefinitionDocumentMetadata(
                createdAt: now,
                modifiedAt: now,
                createdBy: author,
                modifiedBy: author
            )
        )
    }

    public func validate() throws {
        guard schemaVersion <= GraphDefinitionDocumentSchema.currentVersion else {
            throw GraphDefinitionDocumentError.unsupportedSchema(schemaVersion)
        }
        guard !graphID.isEmpty else {
            throw GraphDefinitionDocumentError.missingGraphID
        }
        let nodeIDs = nodes.map(\.id)
        guard Set(nodeIDs).count == nodeIDs.count else {
            throw GraphDefinitionDocumentError.duplicateNodeID(
                Dictionary(grouping: nodeIDs, by: { $0 })
                    .first { $0.value.count > 1 }?.key ?? "unknown"
            )
        }
        guard nodes.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }) else {
            throw GraphDefinitionDocumentError.invalidNode
        }
        let edgeIDs = edges.map(\.id)
        guard Set(edgeIDs).count == edgeIDs.count else {
            throw GraphDefinitionDocumentError.duplicateEdge(
                Dictionary(grouping: edgeIDs, by: { $0 })
                    .first { $0.value.count > 1 }?.key ?? "unknown"
            )
        }
        let known = Set(nodeIDs)
        for edge in edges {
            guard edge.sourceNodeID != edge.targetNodeID else {
                throw GraphDefinitionDocumentError.selfDependency(
                    edge.sourceNodeID
                )
            }
            guard known.contains(edge.sourceNodeID) else {
                throw GraphDefinitionDocumentError.unknownNodeReference(
                    edge.sourceNodeID
                )
            }
            guard known.contains(edge.targetNodeID) else {
                throw GraphDefinitionDocumentError.unknownNodeReference(
                    edge.targetNodeID
                )
            }
        }
        let layoutIDs = layout.nodes.map(\.nodeID)
        guard Set(layoutIDs).count == layoutIDs.count,
              Set(layoutIDs).isSubset(of: known) else {
            throw GraphDefinitionDocumentError.invalidLayout
        }
        guard topologicalNodeIDs() != nil else {
            throw GraphDefinitionDocumentError.cycle
        }
        for node in nodes {
            if node.specification.adapterKind
                == GraphLocalProcessSpecification.adapterKind {
                let specification = try GraphLocalProcessSpecification(
                    immutableSpecification: node.specification
                )
                for key in specification.environment.keys
                    where Self.isSensitiveKey(key) {
                    throw GraphDefinitionDocumentError.embeddedSecret(key)
                }
                for key in specification.logPolicy.sensitiveEnvironmentKeys
                    where specification.environment[key] != nil {
                    throw GraphDefinitionDocumentError.embeddedSecret(key)
                }
            }
        }
        try executableDefinition().validate()
    }

    public func executableDefinition() throws -> GraphExecutableDefinition {
        let digest = try semanticDigest()
        let executableNodes = nodes.filter(\.nodeType.isExecutable)
        let executableNodeIDs = Set(executableNodes.map(\.id))
        var nodeRetryPolicies = schedulerPolicy.nodeRetryPolicies ?? [:]
        for node in executableNodes where !node.retryConfiguration.inheritsGraphDefault {
            nodeRetryPolicies[node.id] = node.retryConfiguration.effective(
                graphDefault: schedulerPolicy.retryPolicy
            )
        }
        let executablePolicy = GraphSchedulerPolicy(
            schemaVersion: schedulerPolicy.schemaVersion,
            policyID: schedulerPolicy.policyID,
            version: schedulerPolicy.version,
            retryPolicy: schedulerPolicy.retryPolicy,
            nodeRetryPolicies: nodeRetryPolicies.isEmpty ? nil : nodeRetryPolicies,
            defaultLeaseDurationSeconds: schedulerPolicy.defaultLeaseDurationSeconds,
            claimAcquisitionTimeoutSeconds: schedulerPolicy.claimAcquisitionTimeoutSeconds,
            attemptExecutionTimeoutSeconds: schedulerPolicy.attemptExecutionTimeoutSeconds,
            cancellationAcknowledgementTimeoutSeconds:
                schedulerPolicy.cancellationAcknowledgementTimeoutSeconds,
            allowExpiredLeaseTakeover: schedulerPolicy.allowExpiredLeaseTakeover,
            schedulingEnabled: schedulerPolicy.schedulingEnabled
        )
        let schedulingNodes = executableNodes.map { node in
            GraphSchedulingDefinitionNode(
                id: node.id,
                title: node.name,
                dependencyNodeIDs: edges.filter {
                    $0.targetNodeID == node.id
                        && executableNodeIDs.contains($0.sourceNodeID)
                        && [.dependency, .artifact].contains($0.portType)
                }.map(\.sourceNodeID),
                requiredCapabilities: node.requiredCapabilities
            )
        }
        return GraphExecutableDefinition(
            scheduling: GraphSchedulingDefinition(
                graphID: graphID,
                version: definitionVersion,
                digest: digest,
                nodes: schedulingNodes
            ),
            schedulerPolicy: executablePolicy,
            executions: executableNodes.map { node in
                GraphNodeExecutionDefinition(
                    nodeID: node.id,
                    capabilityRequirement: node.requiredCapabilities,
                    specification: node.specification,
                    workspace: node.workspace,
                    environmentAllowlist: node.environmentAllowlist,
                    inputArtifactRoles: node.inputArtifactRoles,
                    timeoutPolicy: node.timeoutPolicy
                )
            }
        )
    }

    public func semanticDigest() throws -> GraphContentDigest {
        let semantic = GraphDefinitionSemanticContent(
            graphID: graphID,
            definitionVersion: definitionVersion,
            graphInputs: graphInputs,
            graphOutputs: graphOutputs,
            nodes: nodes,
            edges: edges,
            schedulerPolicy: schedulerPolicy,
            policyReferences: policyReferences,
            sourceRepository: sourceRepository
        )
        let data = try GraphDefinitionDocumentCodec.encoder().encode(semantic)
        return GraphContentDigest(
            algorithm: "sha256",
            value: SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }

    public func topologicalNodeIDs() -> [String]? {
        var incoming = Dictionary(
            uniqueKeysWithValues: nodes.map { ($0.id, 0) }
        )
        var outgoing: [String: [String]] = [:]
        for edge in edges {
            incoming[edge.targetNodeID, default: 0] += 1
            outgoing[edge.sourceNodeID, default: []].append(edge.targetNodeID)
        }
        var ready = incoming.filter { $0.value == 0 }.map(\.key).sorted()
        var result: [String] = []
        while !ready.isEmpty {
            let nodeID = ready.removeFirst()
            result.append(nodeID)
            for dependent in outgoing[nodeID, default: []].sorted() {
                incoming[dependent, default: 0] -= 1
                if incoming[dependent] == 0 {
                    ready.append(dependent)
                    ready.sort()
                }
            }
        }
        return result.count == nodes.count ? result : nil
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return ["secret", "password", "api_key", "access_token", "private_key"]
            .contains { normalized.contains($0) }
    }
}

extension GraphDefinitionDocument: Codable {
    private static let knownKeys: Set<String> = [
        "schemaVersion", "graphID", "definitionVersion", "name",
        "description", "graphInputs", "graphOutputs", "nodes", "edges", "schedulerPolicy",
        "policyReferences", "layout", "metadata", "sourceRepository",
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: GraphDocumentCodingKey.self)
        func key(_ value: String) -> GraphDocumentCodingKey {
            GraphDocumentCodingKey(stringValue: value)!
        }
        schemaVersion = try container.decode(Int.self, forKey: key("schemaVersion"))
        graphID = try container.decode(String.self, forKey: key("graphID"))
        definitionVersion = try container.decode(
            String.self,
            forKey: key("definitionVersion")
        )
        name = try container.decode(String.self, forKey: key("name"))
        description = try container.decodeIfPresent(
            String.self,
            forKey: key("description")
        ) ?? ""
        graphInputs = try container.decodeIfPresent(
            [GraphDefinitionInput].self,
            forKey: key("graphInputs")
        )?.sorted { $0.id < $1.id } ?? []
        graphOutputs = try container.decodeIfPresent(
            [GraphDefinitionOutput].self,
            forKey: key("graphOutputs")
        )?.sorted { $0.id < $1.id } ?? []
        nodes = try container.decode(
            [GraphDefinitionDocumentNode].self,
            forKey: key("nodes")
        ).sorted { $0.id < $1.id }
        edges = try container.decode(
            [GraphDefinitionEdge].self,
            forKey: key("edges")
        ).sorted { $0.id < $1.id }
        schedulerPolicy = try container.decode(
            GraphSchedulerPolicy.self,
            forKey: key("schedulerPolicy")
        )
        policyReferences = try container.decodeIfPresent(
            [String].self,
            forKey: key("policyReferences")
        )?.sorted() ?? []
        layout = try container.decodeIfPresent(
            GraphLayoutMetadata.self,
            forKey: key("layout")
        ) ?? GraphLayoutMetadata()
        metadata = try container.decode(
            GraphDefinitionDocumentMetadata.self,
            forKey: key("metadata")
        )
        sourceRepository = try container.decodeIfPresent(
            GraphSourceRepositoryContext.self,
            forKey: key("sourceRepository")
        )
        extensionFields = try Dictionary(
            uniqueKeysWithValues: container.allKeys.compactMap { codingKey in
                guard !Self.knownKeys.contains(codingKey.stringValue) else {
                    return nil
                }
                return (
                    codingKey.stringValue,
                    try container.decode(GraphJSONValue.self, forKey: codingKey)
                )
            }
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: GraphDocumentCodingKey.self)
        func key(_ value: String) -> GraphDocumentCodingKey {
            GraphDocumentCodingKey(stringValue: value)!
        }
        try container.encode(schemaVersion, forKey: key("schemaVersion"))
        try container.encode(graphID, forKey: key("graphID"))
        try container.encode(definitionVersion, forKey: key("definitionVersion"))
        try container.encode(name, forKey: key("name"))
        try container.encode(description, forKey: key("description"))
        try container.encode(graphInputs.sorted { $0.id < $1.id }, forKey: key("graphInputs"))
        try container.encode(graphOutputs.sorted { $0.id < $1.id }, forKey: key("graphOutputs"))
        try container.encode(nodes.sorted { $0.id < $1.id }, forKey: key("nodes"))
        try container.encode(edges.sorted { $0.id < $1.id }, forKey: key("edges"))
        try container.encode(schedulerPolicy, forKey: key("schedulerPolicy"))
        try container.encode(policyReferences.sorted(), forKey: key("policyReferences"))
        try container.encode(layout, forKey: key("layout"))
        try container.encode(metadata, forKey: key("metadata"))
        try container.encodeIfPresent(sourceRepository, forKey: key("sourceRepository"))
        for (name, value) in extensionFields where !Self.knownKeys.contains(name) {
            try container.encode(value, forKey: key(name))
        }
    }
}

private struct GraphDocumentCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private struct GraphDefinitionSemanticContent: Codable {
    let graphID: String
    let definitionVersion: String
    let graphInputs: [GraphDefinitionInput]
    let graphOutputs: [GraphDefinitionOutput]
    let nodes: [GraphDefinitionDocumentNode]
    let edges: [GraphDefinitionEdge]
    let schedulerPolicy: GraphSchedulerPolicy
    let policyReferences: [String]
    let sourceRepository: GraphSourceRepositoryContext?
}

public enum GraphDefinitionDocumentError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case missingGraphID
    case invalidNode
    case duplicateNodeID(String)
    case unknownNodeReference(String)
    case selfDependency(String)
    case duplicateEdge(String)
    case cycle
    case invalidLayout
    case nodeNotFound(String)
    case edgeNotFound(String)
    case embeddedSecret(String)
}

extension GraphDefinitionDocumentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "Graph document schema \(version) is unsupported."
        case .missingGraphID:
            "Graph document requires a stable graph ID."
        case .invalidNode:
            "Every graph node requires a stable ID and name."
        case let .duplicateNodeID(id):
            "Graph document contains duplicate node ID \(id)."
        case let .unknownNodeReference(id):
            "Graph edge references unknown node \(id)."
        case let .selfDependency(id):
            "Node \(id) cannot depend on itself."
        case let .duplicateEdge(id):
            "Graph document contains duplicate edge \(id)."
        case .cycle:
            "Graph dependencies must form a directed acyclic graph."
        case .invalidLayout:
            "Graph layout references invalid or duplicate nodes."
        case let .nodeNotFound(id):
            "Graph node \(id) was not found."
        case let .edgeNotFound(id):
            "Graph edge \(id) was not found."
        case let .embeddedSecret(key):
            "Graph definitions cannot embed sensitive value \(key)."
        }
    }
}

public enum GraphDefinitionDocumentEditor {
    public static func addNode(
        _ node: GraphDefinitionDocumentNode,
        to document: inout GraphDefinitionDocument,
        position: GraphCanvasPoint? = nil,
        modifiedAt: Date,
        modifiedBy: String
    ) throws {
        guard !document.nodes.contains(where: { $0.id == node.id }) else {
            throw GraphDefinitionDocumentError.duplicateNodeID(node.id)
        }
        document.nodes.append(node)
        document.nodes.sort { $0.id < $1.id }
        if let position {
            document.layout.nodes.append(
                GraphNodeLayoutMetadata(nodeID: node.id, position: position)
            )
            document.layout.nodes.sort { $0.nodeID < $1.nodeID }
        }
        touch(&document, at: modifiedAt, by: modifiedBy)
        try document.validate()
    }

    public static func removeNode(
        id: String,
        from document: inout GraphDefinitionDocument,
        modifiedAt: Date,
        modifiedBy: String
    ) throws {
        guard document.nodes.contains(where: { $0.id == id }) else {
            throw GraphDefinitionDocumentError.nodeNotFound(id)
        }
        document.nodes.removeAll { $0.id == id }
        document.edges.removeAll {
            $0.sourceNodeID == id || $0.targetNodeID == id
        }
        document.layout.nodes.removeAll { $0.nodeID == id }
        touch(&document, at: modifiedAt, by: modifiedBy)
        try document.validate()
    }

    public static func renameNode(
        id: String,
        name: String,
        description: String,
        in document: inout GraphDefinitionDocument,
        modifiedAt: Date,
        modifiedBy: String
    ) throws {
        guard let index = document.nodes.firstIndex(where: { $0.id == id }) else {
            throw GraphDefinitionDocumentError.nodeNotFound(id)
        }
        document.nodes[index].name = name
        document.nodes[index].description = description
        touch(&document, at: modifiedAt, by: modifiedBy)
        try document.validate()
    }

    public static func addEdge(
        _ edge: GraphDefinitionEdge,
        to document: inout GraphDefinitionDocument,
        modifiedAt: Date,
        modifiedBy: String
    ) throws {
        guard !document.edges.contains(where: { $0.id == edge.id }) else {
            throw GraphDefinitionDocumentError.duplicateEdge(edge.id)
        }
        document.edges.append(edge)
        document.edges.sort { $0.id < $1.id }
        do {
            try document.validate()
        } catch {
            document.edges.removeAll { $0.id == edge.id }
            throw error
        }
        touch(&document, at: modifiedAt, by: modifiedBy)
    }

    public static func removeEdge(
        id: String,
        from document: inout GraphDefinitionDocument,
        modifiedAt: Date,
        modifiedBy: String
    ) throws {
        guard document.edges.contains(where: { $0.id == id }) else {
            throw GraphDefinitionDocumentError.edgeNotFound(id)
        }
        document.edges.removeAll { $0.id == id }
        touch(&document, at: modifiedAt, by: modifiedBy)
        try document.validate()
    }

    public static func setPosition(
        nodeID: String,
        position: GraphCanvasPoint,
        in document: inout GraphDefinitionDocument,
        modifiedAt: Date,
        modifiedBy: String
    ) throws {
        guard document.nodes.contains(where: { $0.id == nodeID }) else {
            throw GraphDefinitionDocumentError.nodeNotFound(nodeID)
        }
        if let index = document.layout.nodes.firstIndex(where: {
            $0.nodeID == nodeID
        }) {
            document.layout.nodes[index].position = position
        } else {
            document.layout.nodes.append(
                GraphNodeLayoutMetadata(nodeID: nodeID, position: position)
            )
            document.layout.nodes.sort { $0.nodeID < $1.nodeID }
        }
        touch(&document, at: modifiedAt, by: modifiedBy)
    }

    public static func applyAutomaticLayout(
        to document: inout GraphDefinitionDocument,
        modifiedAt: Date,
        modifiedBy: String
    ) throws {
        guard let order = document.topologicalNodeIDs() else {
            throw GraphDefinitionDocumentError.cycle
        }
        var depth: [String: Int] = [:]
        for nodeID in order {
            let dependencies = document.edges.filter {
                $0.targetNodeID == nodeID
            }.map(\.sourceNodeID)
            depth[nodeID] = dependencies.map { depth[$0, default: 0] + 1 }
                .max() ?? 0
        }
        let grouped = Dictionary(grouping: order) { depth[$0, default: 0] }
        document.layout.nodes = grouped.keys.sorted().flatMap { column in
            grouped[column, default: []].sorted().enumerated().map {
                index, nodeID in
                GraphNodeLayoutMetadata(
                    nodeID: nodeID,
                    position: GraphCanvasPoint(
                        x: Double(column) * 280,
                        y: Double(index) * 150
                    )
                )
            }
        }.sorted { $0.nodeID < $1.nodeID }
        touch(&document, at: modifiedAt, by: modifiedBy)
    }

    private static func touch(
        _ document: inout GraphDefinitionDocument,
        at date: Date,
        by author: String
    ) {
        document.metadata.modifiedAt = date
        document.metadata.modifiedBy = author
    }
}

public enum GraphDefinitionDocumentCodec {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(
        _ document: GraphDefinitionDocument
    ) throws -> Data {
        try document.validate()
        return try encoder().encode(document)
    }

    public static func decode(_ data: Data) throws
        -> GraphDefinitionDocument
    {
        let document = try decoder().decode(
            GraphDefinitionDocument.self,
            from: data
        )
        try document.validate()
        return document
    }

    public static func load(url: URL) throws -> GraphDefinitionDocument {
        try decode(Data(contentsOf: url))
    }

    public static func save(
        _ document: GraphDefinitionDocument,
        to url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encode(document).write(to: url, options: .atomic)
    }
}
