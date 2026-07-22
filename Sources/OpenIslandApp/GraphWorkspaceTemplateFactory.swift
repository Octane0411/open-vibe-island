import Foundation
import OpenIslandCore

enum GraphWorkspaceTemplateFactory {
    static func make(
        request: GraphNewDocumentRequest,
        executableURL: URL? = nil,
        workspaceURL: URL? = nil,
        now: Date = Date(),
        author: String = NSUserName()
    ) throws -> GraphDefinitionDocument {
        let workspace = try resolveWorkspace(
            request: request,
            workspaceURL: workspaceURL
        )
        let executable = try executableURL
            ?? (request.template == .compendiumFill
                || request.template == .localProcessExample
                ? GraphWorkspaceBundledFixtures.fixtureExecutableURL() : nil)
        let nodesAndEdges = try content(
            template: request.template,
            executableURL: executable,
            workspaceURL: workspace
        )
        var document = GraphDefinitionDocument(
            graphID: request.graphID,
            definitionVersion: request.definitionVersion,
            name: request.name,
            description: request.description.isEmpty
                ? request.template.summary : request.description,
            graphOutputs: nodesAndEdges.nodes.last.flatMap { node in
                node.outputs.first.map {
                    [GraphDefinitionOutput(
                        id: "graph-output",
                        name: "Result",
                        sourceNodeID: node.id,
                        sourceOutputID: $0.id
                    )]
                }
            } ?? [],
            nodes: nodesAndEdges.nodes,
            edges: nodesAndEdges.edges,
            schedulerPolicy: GraphSchedulerPolicy(
                policyID: "\(request.graphID)-policy",
                version: request.definitionVersion,
                retryPolicy: GraphRetryPolicy(
                    maximumAttempts: request.defaultRetryMaximumAttempts,
                    retryableFailureCategories: [
                        "execution_failure",
                        "process_exit_unobserved",
                        "timeout",
                    ],
                    nonRetryableFailureCategories: [
                        "artifact_collection_failure",
                        "invalid_process_specification",
                    ]
                ),
                attemptExecutionTimeoutSeconds:
                    request.defaultExecutionTimeoutSeconds,
                cancellationAcknowledgementTimeoutSeconds: 10
            ),
            layout: GraphLayoutMetadata(nodes: nodesAndEdges.layout),
            metadata: GraphDefinitionDocumentMetadata(
                createdAt: now,
                modifiedAt: now,
                createdBy: author,
                modifiedBy: author
            )
        )
        if request.template == .blank {
            document.graphOutputs = []
        } else {
            try document.validate()
        }
        return document
    }

    private static func resolveWorkspace(
        request: GraphNewDocumentRequest,
        workspaceURL: URL?
    ) throws -> URL? {
        guard request.template == .compendiumFill
                || request.template == .localProcessExample else {
            return workspaceURL
                ?? request.workspaceDirectory.map(URL.init(fileURLWithPath:))
        }
        let resolved: URL
        if let workspaceURL {
            resolved = workspaceURL
        } else if let path = request.workspaceDirectory {
            resolved = URL(fileURLWithPath: path)
        } else {
            resolved = try GraphWorkspaceBundledFixtures.templateWorkspaceURL(
                graphID: request.graphID
            )
        }
        try FileManager.default.createDirectory(
            at: resolved.appendingPathComponent("artifacts", isDirectory: true),
            withIntermediateDirectories: true
        )
        return resolved
    }

    private static func content(
        template: GraphWorkspaceTemplate,
        executableURL: URL?,
        workspaceURL: URL?
    ) throws -> (
        nodes: [GraphDefinitionDocumentNode],
        edges: [GraphDefinitionEdge],
        layout: [GraphNodeLayoutMetadata]
    ) {
        switch template {
        case .blank:
            return ([], [], [])
        case .linearPipeline:
            return deterministicDAG(
                nodes: ["prepare", "process", "verify"],
                edges: [("prepare", "process"), ("process", "verify")]
            )
        case .fanOutFanIn:
            return deterministicDAG(
                nodes: ["source", "branch-a", "branch-b", "merge"],
                edges: [
                    ("source", "branch-a"),
                    ("source", "branch-b"),
                    ("branch-a", "merge"),
                    ("branch-b", "merge"),
                ],
                positions: [
                    "source": .init(x: 0, y: 150),
                    "branch-a": .init(x: 300, y: 0),
                    "branch-b": .init(x: 300, y: 300),
                    "merge": .init(x: 600, y: 150),
                ]
            )
        case .reviewLoop:
            return deterministicDAG(
                nodes: ["draft", "review-a", "review-b", "revision", "final-review"],
                edges: [
                    ("draft", "review-a"),
                    ("draft", "review-b"),
                    ("review-a", "revision"),
                    ("review-b", "revision"),
                    ("revision", "final-review"),
                ],
                positions: [
                    "draft": .init(x: 0, y: 150),
                    "review-a": .init(x: 300, y: 0),
                    "review-b": .init(x: 300, y: 300),
                    "revision": .init(x: 600, y: 150),
                    "final-review": .init(x: 900, y: 150),
                ]
            )
        case .compendiumFill:
            guard let executableURL, let workspaceURL else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try localProcessDAG(
                executableURL: executableURL,
                workspaceURL: workspaceURL,
                stages: [
                    ("architect", .nodeOutput, []),
                    ("researcher", .structuredResult, [.nodeOutput]),
                    ("graph", .diagnostic, [.structuredResult]),
                    ("reviewer", .structuredResult, [
                        .nodeOutput, .structuredResult, .diagnostic,
                    ]),
                ]
            )
        case .localProcessExample:
            guard let executableURL, let workspaceURL else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try localProcessDAG(
                executableURL: executableURL,
                workspaceURL: workspaceURL,
                stages: [
                    ("generate", .nodeOutput, []),
                    ("transform", .structuredResult, [.nodeOutput]),
                    ("verify", .diagnostic, [.structuredResult]),
                ]
            )
        }
    }

    private static func deterministicDAG(
        nodes ids: [String],
        edges: [(String, String)],
        positions: [String: GraphCanvasPoint] = [:]
    ) -> (
        nodes: [GraphDefinitionDocumentNode],
        edges: [GraphDefinitionEdge],
        layout: [GraphNodeLayoutMetadata]
    ) {
        let nodes = ids.enumerated().map { index, id in
            GraphDefinitionDocumentNode(
                id: id,
                name: displayName(id),
                nodeType: .deterministicTest,
                requiredCapabilities: ["deterministic"],
                executorKind: .deterministicTest,
                specification: GraphImmutableExecutionSpecification(
                    adapterKind: "deterministic",
                    operation: "test",
                    parameters: [
                        "artifactRole": .string(GraphArtifactRole.nodeOutput.rawValue),
                    ]
                ),
                inputArtifactRoles: [],
                outputs: [GraphNodeOutputDefinition(
                    id: "output",
                    name: "Result",
                    role: .nodeOutput,
                    relativePath: "artifacts/\(id).json",
                    mediaType: "application/json"
                )],
                timeoutPolicy: .init(
                    executionSeconds: 60,
                    cancellationAcknowledgementSeconds: 5
                )
            )
        }
        return (
            nodes,
            edges.map {
                GraphDefinitionEdge(
                    sourceNodeID: $0.0,
                    targetNodeID: $0.1
                )
            },
            ids.enumerated().map { index, id in
                GraphNodeLayoutMetadata(
                    nodeID: id,
                    position: positions[id]
                        ?? GraphCanvasPoint(x: Double(index) * 300, y: 0)
                )
            }
        )
    }

    private static func localProcessDAG(
        executableURL: URL,
        workspaceURL: URL,
        stages: [(String, GraphArtifactRole, [GraphArtifactRole])]
    ) throws -> (
        nodes: [GraphDefinitionDocumentNode],
        edges: [GraphDefinitionEdge],
        layout: [GraphNodeLayoutMetadata]
    ) {
        var nodes: [GraphDefinitionDocumentNode] = []
        for (id, outputRole, inputRoles) in stages {
            let output = GraphNodeOutputDefinition(
                id: "output-\(outputRole.rawValue)",
                name: "Result",
                role: outputRole,
                relativePath: "artifacts/\(id).json",
                mediaType: "application/json",
                maximumBytes: 1_024 * 1_024
            )
            var arguments = ["--role", id]
            for role in inputRoles {
                arguments += ["--input", "${input:\(role.rawValue)}"]
            }
            arguments += ["--output", "${artifact:\(outputRole.rawValue)}"]
            if id == "architect" || id == "generate" {
                arguments.append("--stderr")
            }
            let process = GraphLocalProcessSpecification(
                executable: executableURL.path,
                arguments: arguments,
                outputArtifacts: [GraphLocalProcessArtifactDeclaration(
                    identifier: output.id,
                    relativePath: output.relativePath,
                    mediaType: output.mediaType,
                    role: output.role,
                    maximumBytes: output.maximumBytes
                )],
                retryableExitCodes: [23]
            )
            nodes.append(GraphDefinitionDocumentNode(
                id: id,
                name: displayName(id),
                nodeType: .localProcess,
                requiredCapabilities: ["local-process"],
                executorKind: .supervisedLocalProcess,
                specification: try process.immutableSpecification(),
                workspace: GraphExecutionWorkspaceContext(
                    root: workspaceURL.path,
                    writableRelativePaths: ["artifacts"]
                ),
                inputArtifactRoles: inputRoles,
                outputs: [output],
                timeoutPolicy: .init(
                    executionSeconds: 60,
                    cancellationAcknowledgementSeconds: 5
                )
            ))
        }
        let edges = zip(stages, stages.dropFirst()).map { source, target in
            GraphDefinitionEdge(
                sourceNodeID: source.0,
                targetNodeID: target.0
            )
        }
        let layout = stages.enumerated().map { index, stage in
            GraphNodeLayoutMetadata(
                nodeID: stage.0,
                position: GraphCanvasPoint(x: Double(index) * 300, y: 0)
            )
        }
        return (nodes, edges, layout)
    }

    private static func displayName(_ id: String) -> String {
        id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}
