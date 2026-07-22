import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphDefinitionValidatorTests: XCTestCase {
    func testValidExecutableGraphHasNoErrors() throws {
        let document = makeDocument(nodes: [deterministicNode(id: "verify")])
        let diagnostics = GraphDefinitionValidator.validate(
            document,
            context: GraphDefinitionValidationContext(
                availableCapabilities: ["deterministic"]
            )
        )

        XCTAssertFalse(diagnostics.contains { $0.severity == .error })
    }

    func testStructuralExecutionInputArtifactAndPolicyTaxonomy() throws {
        let invalidRetry = try JSONDecoder().decode(
            GraphRetryPolicy.self,
            from: Data(#"""
            {
              "schemaVersion":1,
              "maximumAttempts":0,
              "retryableFailureCategories":[],
              "nonRetryableFailureCategories":[],
              "initialBackoffSeconds":10,
              "backoffMultiplier":2,
              "maximumBackoffSeconds":1,
              "jitterBasisPoints":0,
              "jitterSeed":"test",
              "timeoutBehavior":"retry",
              "cancellationBehavior":"suppress",
              "dependencyFailureBehavior":"fail_closed"
            }
            """#.utf8)
        )
        let invalidTimeout = try JSONDecoder().decode(
            GraphExecutionTimeoutPolicy.self,
            from: Data(#"""
            {
              "executionSeconds":0,
              "cancellationAcknowledgementSeconds":0
            }
            """#.utf8)
        )
        let process = GraphLocalProcessSpecification(
            executable: "relative-tool",
            workingDirectory: "../outside"
        )
        var first = GraphDefinitionDocumentNode(
            id: "bad id",
            name: "Broken",
            nodeType: .localProcess,
            requiredCapabilities: ["missing-capability"],
            executorKind: .supervisedLocalProcess,
            specification: try process.immutableSpecification(),
            workspace: .init(),
            inputs: [
                GraphNodeInputDefinition(
                    id: "required-input",
                    name: "Required",
                    mediaType: "application/json"
                ),
            ],
            outputs: [
                GraphNodeOutputDefinition(
                    id: "first-output",
                    name: "First",
                    role: .nodeOutput,
                    relativePath: "../escape.json",
                    mediaType: "application/json"
                ),
                GraphNodeOutputDefinition(
                    id: "second-output",
                    name: "Second",
                    role: .nodeOutput,
                    relativePath: "",
                    mediaType: "text/plain"
                ),
            ],
            retryConfiguration: .init(
                inheritsGraphDefault: false,
                override: invalidRetry
            ),
            timeoutPolicy: invalidTimeout,
            timeoutConfiguration: .init(
                inheritsGraphDefault: false,
                executionSeconds: 0,
                cancellationAcknowledgementSeconds: 0,
                claimSeconds: 0
            )
        )
        first.specification = GraphImmutableExecutionSpecification(
            adapterKind: GraphLocalProcessSpecification.adapterKind,
            operation: GraphLocalProcessSpecification.operation,
            parameters: first.specification.parameters
        )
        let generic = GraphDefinitionDocumentNode(
            id: "generic",
            name: "Unbound",
            nodeType: .genericAgent,
            requiredCapabilities: ["agent"],
            executorKind: .unboundAgent,
            specification: .init(adapterKind: "generic_agent", operation: "unbound"),
            timeoutPolicy: .init(
                executionSeconds: 30,
                cancellationAcknowledgementSeconds: 5
            )
        )
        var document = makeDocument(
            name: "",
            nodes: [first, generic],
            edges: [
                GraphDefinitionEdge(
                    edgeID: "self",
                    sourceNodeID: "generic",
                    targetNodeID: "generic"
                ),
                GraphDefinitionEdge(
                    edgeID: "unknown",
                    sourceNodeID: "missing",
                    targetNodeID: "generic"
                ),
            ]
        )
        document.graphInputs = [
            GraphDefinitionInput(
                id: "secret",
                name: "Secret",
                dataType: .text,
                isSensitive: true,
                defaultValue: .string("must-not-persist")
            ),
        ]
        document.graphOutputs = [
            GraphDefinitionOutput(
                id: "dangling",
                name: "Dangling",
                sourceNodeID: "generic",
                sourceOutputID: "missing"
            ),
        ]

        let diagnostics = GraphDefinitionValidator.validate(
            document,
            context: GraphDefinitionValidationContext(
                availableCapabilities: ["local-process"],
                availableExecutablePaths: [],
                availableDirectoryPaths: [],
                immutableDefinitionDigest: GraphContentDigest(
                    algorithm: "sha256",
                    value: "immutable"
                )
            )
        )
        let codes = Set(diagnostics.map(\.code))

        XCTAssertTrue(codes.isSuperset(of: [
            .missingGraphName,
            .invalidNodeID,
            .selfDependency,
            .unknownNodeReference,
            .executableNotAbsolute,
            .invalidWorkingDirectory,
            .missingRequiredInput,
            .invalidArtifactPath,
            .artifactPathEscapesWorkspace,
            .outputRoleCollision,
            .invalidRetryPolicy,
            .invalidTimeoutPolicy,
            .unsupportedExecutorKind,
            .impossibleCapabilityRequirements,
            .danglingBinding,
            .sensitiveLiteral,
            .immutableDefinitionMutationAttempt,
        ]))
    }

    func testCycleDuplicateTypedPortsAndDisconnectedNodesAreDiagnosed() {
        var source = deterministicNode(id: "source")
        source.outputs[0].mediaType = "application/json"
        var target = deterministicNode(id: "target")
        target.inputs = [
            GraphNodeInputDefinition(
                id: "target-input",
                name: "Target",
                mediaType: "text/plain"
            ),
        ]
        let detached = deterministicNode(id: "detached")
        let typed = GraphDefinitionEdge(
            edgeID: "typed",
            sourceNodeID: "source",
            targetNodeID: "target",
            portType: .artifact,
            sourceOutputID: "node-output",
            targetInputID: "target-input"
        )
        let document = makeDocument(
            nodes: [source, target, detached],
            edges: [
                typed,
                GraphDefinitionEdge(
                    edgeID: "typed-copy",
                    sourceNodeID: "source",
                    targetNodeID: "target",
                    portType: .artifact,
                    sourceOutputID: "node-output",
                    targetInputID: "target-input"
                ),
                GraphDefinitionEdge(
                    sourceNodeID: "target",
                    targetNodeID: "source"
                ),
            ]
        )
        let codes = Set(GraphDefinitionValidator.validate(document).map(\.code))

        XCTAssertTrue(codes.contains(.duplicateEdge))
        XCTAssertTrue(codes.contains(.cycle))
        XCTAssertTrue(codes.contains(.incompatibleTypedPorts))
        XCTAssertTrue(codes.contains(.multipleProviders))
        XCTAssertTrue(codes.contains(.unreachableNode))
    }

    func testLocalProcessArgumentTokensDistinguishInputsFromOutputs() throws {
        let output = GraphLocalProcessArtifactDeclaration(
            relativePath: "artifacts/result.json",
            mediaType: "application/json",
            role: .structuredResult
        )
        let invalidProcess = GraphLocalProcessSpecification(
            executable: "/usr/bin/true",
            arguments: [
                "${artifact:node_output}",
                "${artifact:structured_result}",
            ],
            outputArtifacts: [output]
        )
        var node = GraphDefinitionDocumentNode(
            id: "transform",
            name: "Transform",
            nodeType: .localProcess,
            requiredCapabilities: ["local-process"],
            executorKind: .supervisedLocalProcess,
            specification: try invalidProcess.immutableSpecification(),
            workspace: .init(
                root: "/tmp",
                writableRelativePaths: ["artifacts"]
            ),
            inputArtifactRoles: [.nodeOutput],
            outputs: [
                GraphNodeOutputDefinition(
                    id: "result",
                    name: "Result",
                    role: .structuredResult,
                    relativePath: "artifacts/result.json",
                    mediaType: "application/json"
                ),
            ],
            timeoutPolicy: GraphExecutionTimeoutPolicy(
                executionSeconds: 30,
                cancellationAcknowledgementSeconds: 5
            )
        )

        var diagnostics = GraphDefinitionValidator.validate(
            makeDocument(nodes: [node])
        )
        XCTAssertTrue(diagnostics.contains { $0.code == .invalidArgumentToken })

        let validProcess = GraphLocalProcessSpecification(
            executable: "/usr/bin/true",
            arguments: [
                "${input:node_output}",
                "${artifact:structured_result}",
            ],
            outputArtifacts: [output]
        )
        node.specification = try validProcess.immutableSpecification()
        diagnostics = GraphDefinitionValidator.validate(
            makeDocument(nodes: [node])
        )
        XCTAssertFalse(diagnostics.contains { $0.code == .invalidArgumentToken })
    }
}

private func makeDocument(
    name: String = "Validator Test",
    nodes: [GraphDefinitionDocumentNode],
    edges: [GraphDefinitionEdge] = []
) -> GraphDefinitionDocument {
    GraphDefinitionDocument(
        graphID: "validator-test",
        definitionVersion: "1",
        name: name,
        nodes: nodes,
        edges: edges,
        schedulerPolicy: GraphSchedulerPolicy(
            policyID: "validator-policy",
            version: "1",
            retryPolicy: GraphRetryPolicy(
                maximumAttempts: 2,
                retryableFailureCategories: ["timeout"]
            )
        ),
        metadata: GraphDefinitionDocumentMetadata(
            createdAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: 1),
            createdBy: "test",
            modifiedBy: "test"
        )
    )
}

private func deterministicNode(id: String) -> GraphDefinitionDocumentNode {
    GraphDefinitionDocumentNode(
        id: id,
        name: id.capitalized,
        nodeType: .deterministicTest,
        requiredCapabilities: ["deterministic"],
        executorKind: .deterministicTest,
        specification: GraphImmutableExecutionSpecification(
            adapterKind: "deterministic",
            operation: "test"
        ),
        outputs: [
            GraphNodeOutputDefinition(
                id: "node-output",
                name: "Node Output",
                role: .nodeOutput,
                relativePath: "artifacts/\(id).json",
                mediaType: "application/json"
            ),
        ],
        timeoutPolicy: GraphExecutionTimeoutPolicy(
            executionSeconds: 30,
            cancellationAcknowledgementSeconds: 5
        )
    )
}
