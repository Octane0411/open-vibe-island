import CryptoKit
import Foundation

public enum TerminalGraphEnvironmentValueKind:
    String,
    Codable,
    Sendable
{
    case identifier
    case path
    case endpoint
    case port
    case unknown
}

public struct TerminalGraphEnvironmentEntry:
    Equatable,
    Codable,
    Sendable
{
    public let name: String
    public let kind: TerminalGraphEnvironmentValueKind
    public let value: String?
    public let redacted: Bool
    public let redactionReason: GraphRedactionReason?

    public init(
        name: String,
        kind: TerminalGraphEnvironmentValueKind,
        value: String?,
        redacted: Bool,
        redactionReason: GraphRedactionReason? = nil
    ) {
        self.name = name
        self.kind = kind
        self.value = value
        self.redacted = redacted
        self.redactionReason = redactionReason
    }
}

public struct TerminalGraphEnvironmentContext:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let detected: Bool
    public let nodeID: String?
    public let workspaceID: String?
    public let projectID: String?
    public let groupID: String?
    public let externalContextID: String?
    public let projectRoot: String?
    public let worktreeRoot: String?
    public let values: [TerminalGraphEnvironmentEntry]

    public init(
        schemaVersion: Int = 1,
        detected: Bool,
        nodeID: String? = nil,
        workspaceID: String? = nil,
        projectID: String? = nil,
        groupID: String? = nil,
        externalContextID: String? = nil,
        projectRoot: String? = nil,
        worktreeRoot: String? = nil,
        values: [TerminalGraphEnvironmentEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.detected = detected
        self.nodeID = nodeID
        self.workspaceID = workspaceID
        self.projectID = projectID
        self.groupID = groupID
        self.externalContextID = externalContextID
        self.projectRoot = projectRoot
        self.worktreeRoot = worktreeRoot
        self.values = values.sorted { $0.name < $1.name }
    }
}

public enum TerminalGraphEnvironmentDiscovery {
    private static let recognized: [String: TerminalGraphEnvironmentValueKind] = [
        "TG_NODE_ID": .identifier,
        "TG_WORKSPACE_ID": .identifier,
        "TG_PROJECT_ID": .identifier,
        "TG_GROUP_ID": .identifier,
        "TG_EXTERNAL_CONTEXT_ID": .identifier,
        "TG_PROJECT_ROOT": .path,
        "TG_WORKTREE_ROOT": .path,
        "TG_MCP_URL": .endpoint,
        "TG_PORT_IN": .port,
        "TG_PORT_OUT": .port,
    ]

    public static func discover(
        environment: [String: String]
    ) -> TerminalGraphEnvironmentContext {
        let terminalValues = environment
            .filter { $0.key.hasPrefix("TG_") }
            .sorted { $0.key < $1.key }
        var entries: [TerminalGraphEnvironmentEntry] = []

        for (name, rawValue) in terminalValues {
            let kind = recognized[name] ?? .unknown
            entries.append(
                sanitizedEntry(
                    name: name,
                    rawValue: rawValue,
                    kind: kind
                )
            )
        }

        let byName = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.name, $0) }
        )
        return TerminalGraphEnvironmentContext(
            detected: !terminalValues.isEmpty,
            nodeID: byName["TG_NODE_ID"]?.value,
            workspaceID: byName["TG_WORKSPACE_ID"]?.value,
            projectID: byName["TG_PROJECT_ID"]?.value,
            groupID: byName["TG_GROUP_ID"]?.value,
            externalContextID:
                byName["TG_EXTERNAL_CONTEXT_ID"]?.value,
            projectRoot: byName["TG_PROJECT_ROOT"]?.value,
            worktreeRoot: byName["TG_WORKTREE_ROOT"]?.value,
            values: entries
        )
    }

    private static func sanitizedEntry(
        name: String,
        rawValue: String,
        kind: TerminalGraphEnvironmentValueKind
    ) -> TerminalGraphEnvironmentEntry {
        if secretLike(name) {
            return TerminalGraphEnvironmentEntry(
                name: name,
                kind: kind,
                value: nil,
                redacted: true,
                redactionReason: .credentialBearingValue
            )
        }
        let singleLine = rawValue
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        guard !singleLine.isEmpty, singleLine.count <= 512 else {
            return TerminalGraphEnvironmentEntry(
                name: name,
                kind: kind,
                value: nil,
                redacted: true,
                redactionReason: .sensitiveByDefault
            )
        }
        if kind == .unknown,
           singleLine.hasPrefix("/") || containsCredentials(singleLine) {
            return TerminalGraphEnvironmentEntry(
                name: name,
                kind: kind,
                value: nil,
                redacted: true,
                redactionReason: .sensitiveByDefault
            )
        }
        let value: String

        switch kind {
        case .path:
            value = normalizedPath(singleLine)
        case .endpoint:
            guard let sanitized = sanitizedEndpoint(singleLine) else {
                return TerminalGraphEnvironmentEntry(
                    name: name,
                    kind: kind,
                    value: nil,
                    redacted: true,
                    redactionReason: .credentialBearingValue
                )
            }
            value = sanitized
        case .identifier, .port, .unknown:
            value = singleLine
        }

        return TerminalGraphEnvironmentEntry(
            name: name,
            kind: kind,
            value: value,
            redacted: false
        )
    }

    private static func secretLike(_ name: String) -> Bool {
        let upper = name.uppercased()
        return [
            "TOKEN",
            "SECRET",
            "PASSWORD",
            "CREDENTIAL",
            "AUTH",
            "PRIVATE_KEY",
            "API_KEY",
        ].contains { upper.contains($0) }
    }

    private static func sanitizedEndpoint(
        _ value: String
    ) -> String? {
        guard var components = URLComponents(string: value),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string
    }

    private static func containsCredentials(_ value: String) -> Bool {
        guard let components = URLComponents(string: value) else {
            return false
        }
        return components.user != nil || components.password != nil
    }

    private static func normalizedPath(_ value: String) -> String {
        URL(fileURLWithPath: value)
            .standardizedFileURL
            .path
    }
}

public struct GraphRepositoryPath:
    Equatable,
    Codable,
    Sendable
{
    public let value: String?
    public let redacted: Bool

    public init(value: String?, redacted: Bool) {
        self.value = value
        self.redacted = redacted
    }
}

public struct GraphRepositoryContext:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public var id: String {
        repositoryIdentity
    }

    public let schemaVersion: Int
    public let repositoryIdentity: String
    public let canonicalProjectRoot: GraphRepositoryPath
    public let worktreeRoot: GraphRepositoryPath
    public let branch: String?
    public let commit: String?
    public let isDirty: Bool?
    public let externalContextID: String?
    public let sourceProjectAssociation: String?

    public init(
        schemaVersion: Int = 1,
        repositoryIdentity: String,
        canonicalProjectRoot: GraphRepositoryPath,
        worktreeRoot: GraphRepositoryPath,
        branch: String?,
        commit: String?,
        isDirty: Bool?,
        externalContextID: String?,
        sourceProjectAssociation: String?
    ) {
        self.schemaVersion = schemaVersion
        self.repositoryIdentity = repositoryIdentity
        self.canonicalProjectRoot = canonicalProjectRoot
        self.worktreeRoot = worktreeRoot
        self.branch = branch
        self.commit = commit
        self.isDirty = isDirty
        self.externalContextID = externalContextID
        self.sourceProjectAssociation = sourceProjectAssociation
    }
}

public struct GraphWorkspaceContext:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let workspaceID: String?
    public let externalContextID: String?
    public let selectedRepositoryIdentity: String?
    public let repositories: [GraphRepositoryContext]

    public init(
        schemaVersion: Int = 1,
        workspaceID: String?,
        externalContextID: String?,
        selectedRepositoryIdentity: String?,
        repositories: [GraphRepositoryContext]
    ) {
        self.schemaVersion = schemaVersion
        self.workspaceID = workspaceID
        self.externalContextID = externalContextID
        self.selectedRepositoryIdentity = selectedRepositoryIdentity
        self.repositories = repositories.sorted {
            $0.repositoryIdentity < $1.repositoryIdentity
        }
    }
}

public struct GraphCLIExecutionContext:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let terminalGraph: TerminalGraphEnvironmentContext
    public let workspace: GraphWorkspaceContext?

    public init(
        schemaVersion: Int = 1,
        terminalGraph: TerminalGraphEnvironmentContext,
        workspace: GraphWorkspaceContext?
    ) {
        self.schemaVersion = schemaVersion
        self.terminalGraph = terminalGraph
        self.workspace = workspace
    }
}

public protocol GraphRepositoryContextResolving: Sendable {
    func resolve(
        workingDirectory: String,
        exposePaths: Bool,
        externalContextID: String?,
        sourceProjectAssociation: String?
    ) -> GraphRepositoryContext?
}

public struct GitGraphRepositoryContextResolver:
    GraphRepositoryContextResolving,
    Sendable
{
    public init() {}

    public func resolve(
        workingDirectory: String,
        exposePaths: Bool,
        externalContextID: String?,
        sourceProjectAssociation: String?
    ) -> GraphRepositoryContext? {
        guard let worktree = git(
            ["rev-parse", "--show-toplevel"],
            in: workingDirectory
        ) else {
            return nil
        }
        let normalizedWorktree = normalize(worktree)
        let commonGitDirectory = git(
            ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            in: normalizedWorktree
        )
        let canonicalRoot: String

        if let commonGitDirectory {
            let normalizedCommon = normalize(commonGitDirectory)
            canonicalRoot = URL(fileURLWithPath: normalizedCommon)
                .lastPathComponent == ".git"
                ? URL(fileURLWithPath: normalizedCommon)
                    .deletingLastPathComponent().path
                : normalizedWorktree
        } else {
            canonicalRoot = normalizedWorktree
        }
        let remote = git(
            ["config", "--get", "remote.origin.url"],
            in: normalizedWorktree
        )
        let identitySource = sanitizedRepositoryLocator(remote)
            ?? canonicalRoot
        let identity = stableIdentifier(identitySource)
        let branch = git(
            ["symbolic-ref", "--short", "-q", "HEAD"],
            in: normalizedWorktree
        )
        let commit = git(
            ["rev-parse", "HEAD"],
            in: normalizedWorktree
        )
        let status = git(
            ["status", "--porcelain", "--untracked-files=normal"],
            in: normalizedWorktree,
            allowEmpty: true
        )

        return GraphRepositoryContext(
            repositoryIdentity: identity,
            canonicalProjectRoot: GraphRepositoryPath(
                value: exposePaths ? canonicalRoot : nil,
                redacted: !exposePaths
            ),
            worktreeRoot: GraphRepositoryPath(
                value: exposePaths ? normalizedWorktree : nil,
                redacted: !exposePaths
            ),
            branch: branch,
            commit: commit,
            isDirty: status.map { !$0.isEmpty },
            externalContextID: boundedIntegrationValue(
                externalContextID
            ),
            sourceProjectAssociation: boundedIntegrationValue(
                sourceProjectAssociation
            )
        )
    }

    private func git(
        _ arguments: [String],
        in directory: String,
        allowEmpty: Bool = false
    ) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let value = String(
                decoding: data,
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return allowEmpty || !value.isEmpty ? value : nil
        } catch {
            return nil
        }
    }

    private func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func sanitizedRepositoryLocator(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }
        if var components = URLComponents(string: value),
           components.scheme != nil {
            components.user = nil
            components.password = nil
            components.query = nil
            components.fragment = nil
            return components.string
        }
        if let separator = value.firstIndex(of: "@"),
           value.contains(":") {
            return String(value[value.index(after: separator)...])
        }
        return value
    }
}

public enum GraphCLIContextDiscovery {
    public static func discover(
        environment: [String: String],
        workingDirectory: String,
        repositoryResolver: any GraphRepositoryContextResolving =
            GitGraphRepositoryContextResolver()
    ) -> GraphCLIExecutionContext {
        let terminalGraph = TerminalGraphEnvironmentDiscovery.discover(
            environment: environment
        )
        let repository = repositoryResolver.resolve(
            workingDirectory:
                terminalGraph.worktreeRoot
                    ?? terminalGraph.projectRoot
                    ?? workingDirectory,
            exposePaths: terminalGraph.worktreeRoot != nil
                || terminalGraph.projectRoot != nil,
            externalContextID: terminalGraph.externalContextID,
            sourceProjectAssociation: terminalGraph.projectID
        )
        let workspace = repository.map {
            GraphWorkspaceContext(
                workspaceID: terminalGraph.workspaceID,
                externalContextID: terminalGraph.externalContextID,
                selectedRepositoryIdentity: $0.repositoryIdentity,
                repositories: [$0]
            )
        }
        return GraphCLIExecutionContext(
            terminalGraph: terminalGraph,
            workspace: workspace
        )
    }
}

public enum GraphIntegrationPortKind: String, Codable, Sendable {
    case stream
    case signal
    case state
}

public enum GraphIntegrationPortDirection:
    String,
    Codable,
    Sendable
{
    case input
    case output
}

public enum GraphIntegrationSemanticType:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case eventHistory = "stream.event_history"
    case logRecords = "stream.log_records"
    case jsonlRecords = "stream.jsonl_records"
    case refreshSignal = "signal.refresh"
    case selectSignal = "signal.select"
    case openSignal = "signal.open"
    case focusSignal = "signal.focus"
    case completionSignal = "signal.completion"
    case currentRunSummary = "state.current_run_summary"
    case selectedRun = "state.selected_run"
    case selectedCheckpoint = "state.selected_checkpoint"
    case workspaceContext = "state.workspace_context"
}

public struct GraphIntegrationPort:
    Equatable,
    Codable,
    Sendable
{
    public let id: String
    public let kind: GraphIntegrationPortKind
    public let direction: GraphIntegrationPortDirection
    public let semanticType: GraphIntegrationSemanticType
    public let label: String

    public init(
        id: String,
        kind: GraphIntegrationPortKind,
        direction: GraphIntegrationPortDirection,
        semanticType: GraphIntegrationSemanticType,
        label: String
    ) {
        self.id = id
        self.kind = kind
        self.direction = direction
        self.semanticType = semanticType
        self.label = label
    }
}

public struct GraphWorkspaceLayoutHint:
    Equatable,
    Codable,
    Sendable
{
    public let column: Int
    public let row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

public struct GraphWorkspaceSuggestedTerminal:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public let externalMappingKey: String
    public let label: String
    public let command: [String]
    public let startupCommand: [String]?
    public let repositoryIdentity: String?
    public let worktreeRoot: GraphRepositoryPath?
    public let logicalGroup: String
    public let graphRunID: String
    public let graphNodeID: String?
    public let ports: [GraphIntegrationPort]
    public let layout: GraphWorkspaceLayoutHint
    public let sensitivity: GraphArtifactSensitivity
}

public enum GraphWorkspaceConnectionIntent:
    String,
    Codable,
    Sendable
{
    case dependency
    case provenance
    case selection
    case completion
}

public struct GraphWorkspaceSuggestedConnection:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public let id: String
    public let fromMappingKey: String
    public let toMappingKey: String
    public let intent: GraphWorkspaceConnectionIntent
    public let outputSemanticType: GraphIntegrationSemanticType
    public let inputSemanticType: GraphIntegrationSemanticType
    public let label: String
}

public struct GraphTerminalWorkspacePlan:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let planID: String
    public let graphRunID: String
    public let graphDefinitionVersion: String?
    public let graphDefinitionDigest: String?
    public let authority: String
    public let workspaceContext: GraphWorkspaceContext?
    public let terminals: [GraphWorkspaceSuggestedTerminal]
    public let connections: [GraphWorkspaceSuggestedConnection]

    public init(
        schemaVersion: Int = 1,
        planID: String,
        graphRunID: String,
        graphDefinitionVersion: String?,
        graphDefinitionDigest: String?,
        authority: String = "openisland",
        workspaceContext: GraphWorkspaceContext?,
        terminals: [GraphWorkspaceSuggestedTerminal],
        connections: [GraphWorkspaceSuggestedConnection]
    ) {
        self.schemaVersion = schemaVersion
        self.planID = planID
        self.graphRunID = graphRunID
        self.graphDefinitionVersion = graphDefinitionVersion
        self.graphDefinitionDigest = graphDefinitionDigest
        self.authority = authority
        self.workspaceContext = workspaceContext
        self.terminals = terminals.sorted { $0.id < $1.id }
        self.connections = connections.sorted { $0.id < $1.id }
    }
}

public enum GraphTerminalWorkspacePlanBuilder {
    public static func build(
        inspection: GraphRunInspection,
        workspaceContext: GraphWorkspaceContext?
    ) -> GraphTerminalWorkspacePlan {
        let repository = workspaceContext?.repositories.first {
            $0.repositoryIdentity
                == workspaceContext?.selectedRepositoryIdentity
        }
        let nodes = inspection.nodes.sorted { $0.id < $1.id }
        let levels = dependencyLevels(nodes)
        let grouped = Dictionary(grouping: nodes) {
            levels[$0.id] ?? 0
        }
        var rowByNode: [String: Int] = [:]

        for level in grouped.keys.sorted() {
            for (row, node) in (grouped[level] ?? [])
                .sorted(by: { $0.id < $1.id }).enumerated() {
                rowByNode[node.id] = row
            }
        }
        let terminals = nodes.map { node in
            let mappingKey = externalMappingKey(
                runID: inspection.summary.runID,
                entityKind: "node",
                entityID: node.id
            )
            return GraphWorkspaceSuggestedTerminal(
                id: "terminal-\(mappingKey)",
                externalMappingKey: mappingKey,
                label: node.title,
                command: [
                    "openisland",
                    "graph",
                    "inspect",
                    inspection.summary.runID,
                    "--node",
                    node.id,
                    "--output",
                    "json",
                ],
                startupCommand: nil,
                repositoryIdentity: repository?.repositoryIdentity,
                worktreeRoot: repository?.worktreeRoot,
                logicalGroup: inspection.summary.graphID,
                graphRunID: inspection.summary.runID,
                graphNodeID: node.id,
                ports: defaultPorts(nodeID: node.id),
                layout: GraphWorkspaceLayoutHint(
                    column: levels[node.id] ?? 0,
                    row: rowByNode[node.id] ?? 0
                ),
                sensitivity: sensitivity(
                    for: node.id,
                    artifacts: inspection.artifacts
                )
            )
        }
        let byNode = Dictionary(
            uniqueKeysWithValues: terminals.compactMap {
                terminal in terminal.graphNodeID.map {
                    ($0, terminal.externalMappingKey)
                }
            }
        )
        var connections: [GraphWorkspaceSuggestedConnection] = []

        for node in nodes {
            guard let target = byNode[node.id] else {
                continue
            }
            for dependency in node.dependencyNodeIDs.sorted() {
                guard let source = byNode[dependency] else {
                    continue
                }
                let key = stableIdentifier(
                    "\(inspection.summary.runID)|dependency|\(dependency)|\(node.id)"
                )
                connections.append(
                    GraphWorkspaceSuggestedConnection(
                        id: "connection-\(key)",
                        fromMappingKey: source,
                        toMappingKey: target,
                        intent: .dependency,
                        outputSemanticType: .currentRunSummary,
                        inputSemanticType: .selectedRun,
                        label: "dependency"
                    )
                )
            }
        }

        return GraphTerminalWorkspacePlan(
            planID: "workspace-plan-\(stableIdentifier(inspection.summary.runID))",
            graphRunID: inspection.summary.runID,
            graphDefinitionVersion:
                inspection.graphDefinitionVersion,
            graphDefinitionDigest:
                inspection.graphDefinitionDigest?.value,
            workspaceContext: workspaceContext,
            terminals: terminals,
            connections: connections
        )
    }

    private static func defaultPorts(
        nodeID: String
    ) -> [GraphIntegrationPort] {
        [
            GraphIntegrationPort(
                id: "\(nodeID)-refresh",
                kind: .signal,
                direction: .input,
                semanticType: .refreshSignal,
                label: "Refresh"
            ),
            GraphIntegrationPort(
                id: "\(nodeID)-selection",
                kind: .state,
                direction: .input,
                semanticType: .selectedRun,
                label: "Selected run"
            ),
            GraphIntegrationPort(
                id: "\(nodeID)-history",
                kind: .stream,
                direction: .output,
                semanticType: .eventHistory,
                label: "Event history"
            ),
            GraphIntegrationPort(
                id: "\(nodeID)-summary",
                kind: .state,
                direction: .output,
                semanticType: .currentRunSummary,
                label: "Run summary"
            ),
            GraphIntegrationPort(
                id: "\(nodeID)-completion",
                kind: .signal,
                direction: .output,
                semanticType: .completionSignal,
                label: "Completion"
            ),
        ]
    }

    private static func dependencyLevels(
        _ nodes: [GraphNodeInspection]
    ) -> [String: Int] {
        var levels = Dictionary(
            uniqueKeysWithValues: nodes.map { ($0.id, 0) }
        )

        for _ in 0..<nodes.count {
            var changed = false
            for node in nodes {
                let proposed = (node.dependencyNodeIDs.compactMap {
                    levels[$0]
                }.max() ?? -1) + 1
                if proposed > (levels[node.id] ?? 0) {
                    levels[node.id] = proposed
                    changed = true
                }
            }
            if !changed {
                break
            }
        }
        return levels
    }

    private static func sensitivity(
        for nodeID: String,
        artifacts: [GraphArtifactInspection]
    ) -> GraphArtifactSensitivity {
        let ranking: [GraphArtifactSensitivity: Int] = [
            .unspecified: 0,
            .internalUse: 1,
            .confidential: 2,
            .restricted: 3,
            .redacted: 4,
        ]
        return artifacts
            .filter { $0.producingNodeID == nodeID }
            .map(\.sensitivity)
            .max {
                (ranking[$0] ?? 0) < (ranking[$1] ?? 0)
            } ?? .unspecified
    }
}

public struct GraphExternalEntityMapping:
    Equatable,
    Codable,
    Sendable
{
    public let openIslandMappingKey: String
    public let externalEntityID: String

    public init(
        openIslandMappingKey: String,
        externalEntityID: String
    ) {
        self.openIslandMappingKey = openIslandMappingKey
        self.externalEntityID = externalEntityID
    }
}

public struct GraphVisualizationSynchronizationRequest:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let plan: GraphTerminalWorkspacePlan
    public let existingMappings: [GraphExternalEntityMapping]

    public init(
        schemaVersion: Int = 1,
        plan: GraphTerminalWorkspacePlan,
        existingMappings: [GraphExternalEntityMapping]
    ) {
        self.schemaVersion = schemaVersion
        self.plan = plan
        self.existingMappings = existingMappings.sorted {
            $0.openIslandMappingKey < $1.openIslandMappingKey
        }
    }
}

public struct GraphVisualizationSynchronizationResult:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let mappings: [GraphExternalEntityMapping]
    public let diagnostics: [String]

    public init(
        schemaVersion: Int = 1,
        mappings: [GraphExternalEntityMapping],
        diagnostics: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.mappings = mappings.sorted {
            $0.openIslandMappingKey < $1.openIslandMappingKey
        }
        self.diagnostics = diagnostics.sorted()
    }
}

public protocol GraphVisualizationSynchronizationAdapter: Sendable {
    func synchronize(
        _ request: GraphVisualizationSynchronizationRequest
    ) async throws -> GraphVisualizationSynchronizationResult
}

private func stableIdentifier(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.prefix(10).map { String(format: "%02x", $0) }
        .joined()
}

private func externalMappingKey(
    runID: String,
    entityKind: String,
    entityID: String
) -> String {
    "openisland-\(stableIdentifier("\(runID)|\(entityKind)|\(entityID)"))"
}

private func boundedIntegrationValue(
    _ value: String?,
    limit: Int = 256
) -> String? {
    guard let value else {
        return nil
    }
    let singleLine = value
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
    guard singleLine.count <= limit else {
        return nil
    }
    return singleLine
}
