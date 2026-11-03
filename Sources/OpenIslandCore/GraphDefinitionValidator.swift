import Foundation

public enum GraphValidationSeverity: String, Codable, CaseIterable, Sendable {
    case error
    case warning
}

public enum GraphValidationCode: String, Codable, CaseIterable, Sendable {
    case emptyGraph = "empty_graph"
    case missingGraphName = "missing_graph_name"
    case duplicateNodeID = "duplicate_node_id"
    case invalidNodeID = "invalid_node_id"
    case cycle
    case selfDependency = "self_dependency"
    case duplicateEdge = "duplicate_edge"
    case unknownNodeReference = "unknown_node_reference"
    case missingExecutionSpecification = "missing_execution_specification"
    case executableMissing = "executable_missing"
    case executableNotAbsolute = "executable_not_absolute"
    case invalidArgumentToken = "invalid_argument_token"
    case invalidWorkingDirectory = "invalid_working_directory"
    case invalidArtifactPath = "invalid_artifact_path"
    case artifactPathEscapesWorkspace = "artifact_path_escapes_workspace"
    case missingRequiredInput = "missing_required_input"
    case incompatibleTypedPorts = "incompatible_typed_ports"
    case sourceOutputNotDeclared = "source_output_not_declared"
    case danglingBinding = "dangling_binding"
    case multipleProviders = "multiple_providers"
    case outputRoleCollision = "output_role_collision"
    case invalidRetryPolicy = "invalid_retry_policy"
    case invalidTimeoutPolicy = "invalid_timeout_policy"
    case unsupportedExecutorKind = "unsupported_executor_kind"
    case noTerminalNode = "no_terminal_or_output_node"
    case unreachableNode = "unreachable_node"
    case impossibleCapabilityRequirements = "impossible_capability_requirements"
    case immutableDefinitionMutationAttempt = "immutable_definition_mutation_attempt"
    case sensitiveLiteral = "sensitive_literal"
}

public enum GraphValidationTargetKind: String, Codable, Sendable {
    case graph
    case node
    case edge
    case graphInput = "graph_input"
    case graphOutput = "graph_output"
}

public struct GraphValidationTarget: Equatable, Codable, Sendable {
    public let kind: GraphValidationTargetKind
    public let id: String?

    public init(kind: GraphValidationTargetKind, id: String? = nil) {
        self.kind = kind
        self.id = id
    }
}

public struct GraphValidationDiagnostic:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public var id: String {
        "\(severity.rawValue):\(code.rawValue):\(target.kind.rawValue):\(target.id ?? "graph")"
    }

    public let severity: GraphValidationSeverity
    public let code: GraphValidationCode
    public let target: GraphValidationTarget
    public let message: String
    public let suggestedAction: String

    public init(
        severity: GraphValidationSeverity,
        code: GraphValidationCode,
        target: GraphValidationTarget,
        message: String,
        suggestedAction: String
    ) {
        self.severity = severity
        self.code = code
        self.target = target
        self.message = message
        self.suggestedAction = suggestedAction
    }
}

public struct GraphDefinitionValidationContext: Equatable, Sendable {
    public var supportedExecutors: Set<GraphDefinitionExecutorKind>
    public var availableCapabilities: Set<String>?
    public var availableExecutablePaths: Set<String>?
    public var availableDirectoryPaths: Set<String>?
    public var resolvedGraphInputIDs: Set<String>
    public var immutableDefinitionDigest: GraphContentDigest?

    public init(
        supportedExecutors: Set<GraphDefinitionExecutorKind> = [
            .supervisedLocalProcess,
            .deterministicTest,
        ],
        availableCapabilities: Set<String>? = nil,
        availableExecutablePaths: Set<String>? = nil,
        availableDirectoryPaths: Set<String>? = nil,
        resolvedGraphInputIDs: Set<String> = [],
        immutableDefinitionDigest: GraphContentDigest? = nil
    ) {
        self.supportedExecutors = supportedExecutors
        self.availableCapabilities = availableCapabilities
        self.availableExecutablePaths = availableExecutablePaths
        self.availableDirectoryPaths = availableDirectoryPaths
        self.resolvedGraphInputIDs = resolvedGraphInputIDs
        self.immutableDefinitionDigest = immutableDefinitionDigest
    }
}

public enum GraphDefinitionValidator {
    public static func validate(
        _ document: GraphDefinitionDocument,
        context: GraphDefinitionValidationContext = .init()
    ) -> [GraphValidationDiagnostic] {
        var result: [GraphValidationDiagnostic] = []
        func append(
            _ severity: GraphValidationSeverity,
            _ code: GraphValidationCode,
            _ target: GraphValidationTarget,
            _ message: String,
            _ action: String
        ) {
            result.append(
                GraphValidationDiagnostic(
                    severity: severity,
                    code: code,
                    target: target,
                    message: message,
                    suggestedAction: action
                )
            )
        }

        if document.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            append(.error, .missingGraphName, .init(kind: .graph),
                   "The graph has no name.", "Enter a graph name in the graph inspector.")
        }
        let executableNodes = document.nodes.filter(\.nodeType.isExecutable)
        if executableNodes.isEmpty {
            append(.error, .emptyGraph, .init(kind: .graph),
                   "The graph has no executable nodes.", "Add a Local Process or Deterministic Test node.")
        }

        let groupedIDs = Dictionary(grouping: document.nodes, by: \.id)
        for (id, nodes) in groupedIDs where nodes.count > 1 {
            append(.error, .duplicateNodeID, .init(kind: .node, id: id),
                   "Node ID \(id) is duplicated.", "Assign a unique stable node ID.")
        }
        for node in document.nodes where !isValidIdentifier(node.id) {
            append(.error, .invalidNodeID, .init(kind: .node, id: node.id),
                   "Node ID \(node.id) contains unsupported characters.",
                   "Use letters, numbers, period, underscore, or hyphen.")
        }

        let known = Set(document.nodes.map(\.id))
        let semanticEdges = Dictionary(grouping: document.edges) {
            "\($0.sourceNodeID)|\($0.targetNodeID)|\($0.portType.rawValue)|\($0.sourceOutputID ?? "")|\($0.targetInputID ?? "")"
        }
        for (_, edges) in semanticEdges where edges.count > 1 {
            let edge = edges[0]
            append(.error, .duplicateEdge, .init(kind: .edge, id: edge.id),
                   "The same connection is declared more than once.", "Delete the duplicate connection.")
        }
        for edge in document.edges {
            let target = GraphValidationTarget(kind: .edge, id: edge.id)
            if edge.sourceNodeID == edge.targetNodeID {
                append(.error, .selfDependency, target,
                       "A node cannot depend on itself.", "Choose a different destination.")
            }
            if !known.contains(edge.sourceNodeID) || !known.contains(edge.targetNodeID) {
                append(.error, .unknownNodeReference, target,
                       "The connection references a node that does not exist.", "Delete or reconnect the edge.")
                continue
            }
            if edge.portType != .dependency {
                validateTypedEdge(edge, document: document, append: append)
            }
        }
        if document.topologicalNodeIDs() == nil {
            append(.error, .cycle, .init(kind: .graph),
                   "Graph connections contain a cycle.", "Remove one dependency from the cycle.")
        }

        for node in executableNodes {
            validateExecutableNode(node, document: document, context: context, append: append)
        }
        validateGraphInputs(document, context: context, append: append)
        validateGraphOutputs(document, append: append)
        validateReachability(document, append: append)

        if let immutable = context.immutableDefinitionDigest,
           let current = try? document.semanticDigest(), current != immutable {
            append(.error, .immutableDefinitionMutationAttempt, .init(kind: .graph),
                   "This semantic edit differs from the immutable definition used by an existing run.",
                   "Create a new definition version before creating another run.")
        }

        return result.sorted {
            if $0.severity != $1.severity { return $0.severity.rawValue < $1.severity.rawValue }
            if $0.code != $1.code { return $0.code.rawValue < $1.code.rawValue }
            return ($0.target.id ?? "") < ($1.target.id ?? "")
        }
    }

    private static func validateExecutableNode(
        _ node: GraphDefinitionDocumentNode,
        document: GraphDefinitionDocument,
        context: GraphDefinitionValidationContext,
        append: (GraphValidationSeverity, GraphValidationCode, GraphValidationTarget, String, String) -> Void
    ) {
        let target = GraphValidationTarget(kind: .node, id: node.id)
        if node.specification.adapterKind.isEmpty || node.specification.operation.isEmpty {
            append(.error, .missingExecutionSpecification, target,
                   "Node \(node.name) has no execution specification.", "Configure the node's executor.")
        }
        if !node.nodeType.isRunnable || !context.supportedExecutors.contains(node.executorKind) {
            append(.error, .unsupportedExecutorKind, target,
                   "Executor \(node.executorKind.displayName) is not runnable in this workspace.",
                   "Choose an executor configured and supported by this workspace.")
        }
        if let available = context.availableCapabilities,
           !Set(node.requiredCapabilities).isSubset(of: available) {
            append(.error, .impossibleCapabilityRequirements, target,
                   "No available executor satisfies all required capabilities.",
                   "Change required capabilities or choose a compatible executor.")
        }
        if node.timeoutPolicy.executionSeconds < 1
            || node.timeoutPolicy.cancellationAcknowledgementSeconds < 1
            || node.timeoutConfiguration.claimSeconds < 1 {
            append(.error, .invalidTimeoutPolicy, target,
                   "Timeout values must be greater than zero.", "Set valid execution, cancellation, and claim timeouts.")
        }
        let retry = node.retryConfiguration.effective(
            graphDefault: document.schedulerPolicy.retryPolicy
        )
        if retry.maximumAttempts < 1
            || retry.maximumBackoffSeconds < retry.initialBackoffSeconds {
            append(.error, .invalidRetryPolicy, target,
                   "Retry attempts or backoff bounds are invalid.", "Correct the retry policy in the node inspector.")
        }
        validateInputs(node, document: document, append: append)
        validateOutputs(node, append: append)

        guard node.nodeType == .localProcess else { return }
        guard let process = try? GraphLocalProcessSpecification(
            immutableSpecification: node.specification
        ) else {
            append(.error, .missingExecutionSpecification, target,
                   "The local-process specification cannot be decoded.", "Reconfigure the Execution section.")
            return
        }
        if process.executable.isEmpty {
            append(.error, .executableMissing, target,
                   "No executable is selected.", "Choose an executable file.")
        } else if !process.executable.hasPrefix("/") {
            append(.error, .executableNotAbsolute, target,
                   "Executable paths must be absolute.", "Choose the executable with the file picker.")
        } else if let available = context.availableExecutablePaths,
                  !available.contains(process.executable) {
            append(.error, .executableMissing, target,
                   "The configured executable is unavailable.", "Choose an executable that exists and is runnable.")
        }
        if process.workingDirectory.hasPrefix("/") || pathEscapes(process.workingDirectory) {
            append(.error, .invalidWorkingDirectory, target,
                   "The working directory must stay inside the workspace.", "Use a relative working directory without '..'.")
        }
        if node.workspace.root?.isEmpty != false {
            append(.error, .invalidWorkingDirectory, target,
                   "A local process requires a workspace directory.", "Choose a workspace directory.")
        } else if let available = context.availableDirectoryPaths,
                  let root = node.workspace.root,
                  !available.contains(root) {
            append(.error, .invalidWorkingDirectory, target,
                   "The configured workspace is unavailable.", "Choose an existing workspace directory.")
        }
        validateLocalProcessArguments(
            process,
            node: node,
            target: target,
            append: append
        )
    }

    private static func validateLocalProcessArguments(
        _ process: GraphLocalProcessSpecification,
        node: GraphDefinitionDocumentNode,
        target: GraphValidationTarget,
        append: (
            GraphValidationSeverity,
            GraphValidationCode,
            GraphValidationTarget,
            String,
            String
        ) -> Void
    ) {
        let outputRoles = Set(process.outputArtifacts.map(\.role))
        let inputRoles = Set(node.inputArtifactRoles)
        let invalid = process.arguments.filter { argument in
            guard argument.hasPrefix("${"), argument.hasSuffix("}") else {
                return false
            }
            if argument == "${workspace}" { return false }
            if argument.hasPrefix("${artifact:") {
                let value = String(argument.dropFirst(11).dropLast())
                guard let role = GraphArtifactRole(rawValue: value) else {
                    return true
                }
                return !outputRoles.contains(role)
            }
            if argument.hasPrefix("${input:") {
                let value = String(argument.dropFirst(8).dropLast())
                guard let role = GraphArtifactRole(rawValue: value) else {
                    return true
                }
                return !inputRoles.contains(role)
            }
            return true
        }
        guard !invalid.isEmpty else { return }
        append(
            .error,
            .invalidArgumentToken,
            target,
            "Arguments reference unavailable runtime paths: \(invalid.joined(separator: ", ")).",
            "Use ${input:role} for upstream artifacts and ${artifact:role} for outputs declared by this node."
        )
    }

    private static func validateInputs(
        _ node: GraphDefinitionDocumentNode,
        document: GraphDefinitionDocument,
        append: (GraphValidationSeverity, GraphValidationCode, GraphValidationTarget, String, String) -> Void
    ) {
        for input in node.inputs {
            let target = GraphValidationTarget(kind: .node, id: node.id)
            let incoming = document.edges.filter {
                $0.targetNodeID == node.id && $0.targetInputID == input.id
            }
            if input.isRequired && input.binding == nil && incoming.isEmpty {
                append(.error, .missingRequiredInput, target,
                       "Required input \(input.name) has no binding.", "Connect an output or configure another input source.")
            }
            if !input.allowsMultiple && incoming.count > 1 {
                append(.error, .multipleProviders, target,
                       "Input \(input.name) has multiple providers.", "Keep one provider or allow a collection.")
            }
            if let binding = input.binding {
                switch binding.kind {
                case .upstreamArtifact, .upstreamArtifactCollection:
                    guard let sourceID = binding.sourceNodeID,
                          let outputID = binding.sourceOutputID,
                          document.nodes.first(where: { $0.id == sourceID })?
                            .outputs.contains(where: { $0.id == outputID }) == true else {
                        append(.error, .danglingBinding, target,
                               "Input \(input.name) references a missing upstream output.", "Reconnect the input.")
                        continue
                    }
                case .graphInput:
                    if !document.graphInputs.contains(where: {
                        $0.id == binding.graphInputID
                    }) {
                        append(.error, .danglingBinding, target,
                               "Input \(input.name) references a missing graph input.", "Choose an existing graph input.")
                    }
                case .fileReference, .staticLiteral, .secretReference:
                    break
                }
            }
        }
    }

    private static func validateOutputs(
        _ node: GraphDefinitionDocumentNode,
        append: (GraphValidationSeverity, GraphValidationCode, GraphValidationTarget, String, String) -> Void
    ) {
        let grouped = Dictionary(grouping: node.outputs, by: \.role)
        for (_, values) in grouped where values.count > 1 {
            append(.error, .outputRoleCollision, .init(kind: .node, id: node.id),
                   "Runtime artifact roles must be unique within a node.", "Assign a distinct runtime role to each output.")
        }
        for output in node.outputs {
            if output.relativePath.isEmpty || output.relativePath.hasPrefix("/") {
                append(.error, .invalidArtifactPath, .init(kind: .node, id: node.id),
                       "Output \(output.name) needs a relative path.", "Choose a path inside the workspace.")
            } else if pathEscapes(output.relativePath) {
                append(.error, .artifactPathEscapesWorkspace, .init(kind: .node, id: node.id),
                       "Output \(output.name) escapes the workspace.", "Remove '..' path components.")
            }
        }
    }

    private static func validateTypedEdge(
        _ edge: GraphDefinitionEdge,
        document: GraphDefinitionDocument,
        append: (GraphValidationSeverity, GraphValidationCode, GraphValidationTarget, String, String) -> Void
    ) {
        let target = GraphValidationTarget(kind: .edge, id: edge.id)
        guard let source = document.nodes.first(where: { $0.id == edge.sourceNodeID }),
              let outputID = edge.sourceOutputID,
              let output = source.outputs.first(where: { $0.id == outputID }) else {
            append(.error, .sourceOutputNotDeclared, target,
                   "The connection has no declared source output.", "Choose a source output in the connection inspector.")
            return
        }
        guard let destination = document.nodes.first(where: { $0.id == edge.targetNodeID }),
              let inputID = edge.targetInputID,
              let input = destination.inputs.first(where: { $0.id == inputID }) else {
            append(.error, .danglingBinding, target,
                   "The connection has no declared target input.", "Choose a target input in the connection inspector.")
            return
        }
        if output.portType != edge.portType || input.portType != edge.portType
            || (edge.portType == .artifact
                && !mediaTypesAreCompatible(output.mediaType, input.mediaType)) {
            append(.error, .incompatibleTypedPorts, target,
                   "The selected ports are not type-compatible.", "Choose matching port and media types.")
        }
    }

    private static func validateGraphInputs(
        _ document: GraphDefinitionDocument,
        context: GraphDefinitionValidationContext,
        append: (GraphValidationSeverity, GraphValidationCode, GraphValidationTarget, String, String) -> Void
    ) {
        for input in document.graphInputs {
            let target = GraphValidationTarget(kind: .graphInput, id: input.id)
            if input.isSensitive && input.defaultValue != nil {
                append(.error, .sensitiveLiteral, target,
                       "Sensitive graph inputs cannot persist literal defaults.", "Use a secret reference at run creation.")
            }
            if input.isRequired && input.defaultValue == nil
                && !context.resolvedGraphInputIDs.contains(input.id) {
                append(.error, .missingRequiredInput, target,
                       "Required graph input \(input.name) is unresolved.", "Provide a value in Create Run.")
            }
        }
    }

    private static func validateGraphOutputs(
        _ document: GraphDefinitionDocument,
        append: (GraphValidationSeverity, GraphValidationCode, GraphValidationTarget, String, String) -> Void
    ) {
        for output in document.graphOutputs {
            guard document.nodes.first(where: { $0.id == output.sourceNodeID })?
                .outputs.contains(where: { $0.id == output.sourceOutputID }) == true else {
                append(.error, .danglingBinding, .init(kind: .graphOutput, id: output.id),
                       "Graph output \(output.name) references a missing node output.", "Choose a declared node output.")
                continue
            }
        }
        let executable = document.nodes.filter(\.nodeType.isExecutable)
        let outgoing = Set(document.edges.map(\.sourceNodeID))
        if !executable.isEmpty && executable.allSatisfy({ outgoing.contains($0.id) })
            && document.graphOutputs.isEmpty {
            append(.warning, .noTerminalNode, .init(kind: .graph),
                   "The graph has no terminal node or declared graph output.", "Declare a graph output or remove the trailing dependency.")
        }
    }

    private static func validateReachability(
        _ document: GraphDefinitionDocument,
        append: (GraphValidationSeverity, GraphValidationCode, GraphValidationTarget, String, String) -> Void
    ) {
        let executable = document.nodes.filter(\.nodeType.isExecutable)
        let incoming = Set(document.edges.map(\.targetNodeID))
        let roots = executable.filter { !incoming.contains($0.id) }.map(\.id).sorted()
        guard let primary = roots.first else { return }
        var reached: Set<String> = [primary]
        var changed = true
        while changed {
            changed = false
            for edge in document.edges where reached.contains(edge.sourceNodeID) {
                if reached.insert(edge.targetNodeID).inserted { changed = true }
            }
        }
        for node in executable where !reached.contains(node.id) {
            append(.warning, .unreachableNode, .init(kind: .node, id: node.id),
                   "Node \(node.name) is disconnected from the primary component.", "Connect it or keep it as an intentional independent component.")
        }
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
                || ".-_".unicodeScalars.contains($0)
        }
    }

    private static func pathEscapes(_ value: String) -> Bool {
        value.split(separator: "/").contains("..")
    }

    private static func mediaTypesAreCompatible(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs == "*/*" || rhs == "*/*"
            || lhs == "application/octet-stream"
            || rhs == "application/octet-stream"
    }
}
