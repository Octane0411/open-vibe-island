import Foundation

public enum GraphLocalProcessEnvironmentInheritance:
    String,
    Codable,
    Sendable
{
    case none
    case allowlisted
}

public enum GraphLocalProcessStdinPolicy: String, Codable, Sendable {
    case closed
    case nullDevice = "null_device"
}

public struct GraphLocalProcessLogPolicy: Equatable, Codable, Sendable {
    public let maximumBytesPerStream: Int
    public let sensitiveEnvironmentKeys: [String]

    public init(
        maximumBytesPerStream: Int = 8 * 1_024 * 1_024,
        sensitiveEnvironmentKeys: [String] = []
    ) {
        self.maximumBytesPerStream = max(1_024, maximumBytesPerStream)
        self.sensitiveEnvironmentKeys = sensitiveEnvironmentKeys.sorted()
    }
}

public struct GraphLocalProcessArtifactDeclaration:
    Equatable,
    Codable,
    Sendable
{
    public let identifier: String?
    public let relativePath: String
    public let mediaType: String
    public let role: GraphArtifactRole
    public let sensitivity: GraphArtifactSensitivity
    public let maximumBytes: Int
    public let isRequired: Bool?
    public let downstreamVisibility: GraphArtifactDownstreamVisibility?

    public var stableID: String { identifier ?? "output-\(role.rawValue)" }
    public var required: Bool { isRequired ?? true }

    public init(
        identifier: String? = nil,
        relativePath: String,
        mediaType: String,
        role: GraphArtifactRole,
        sensitivity: GraphArtifactSensitivity = .internalUse,
        maximumBytes: Int = 64 * 1_024 * 1_024,
        isRequired: Bool = true,
        downstreamVisibility: GraphArtifactDownstreamVisibility = .graph
    ) {
        self.identifier = identifier
        self.relativePath = relativePath
        self.mediaType = mediaType
        self.role = role
        self.sensitivity = sensitivity
        self.maximumBytes = max(1, maximumBytes)
        self.isRequired = isRequired
        self.downstreamVisibility = downstreamVisibility
    }
}

public struct GraphLocalProcessSpecification:
    Equatable,
    Codable,
    Sendable
{
    public static let adapterKind = "local_process"
    public static let operation = "execute"

    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String
    public let environment: [String: String]
    public let inheritedEnvironment: GraphLocalProcessEnvironmentInheritance
    public let stdin: GraphLocalProcessStdinPolicy
    public let outputArtifacts: [GraphLocalProcessArtifactDeclaration]
    public let retryableExitCodes: [Int32]
    public let logPolicy: GraphLocalProcessLogPolicy

    public init(
        executable: String,
        arguments: [String] = [],
        workingDirectory: String = ".",
        environment: [String: String] = [:],
        inheritedEnvironment: GraphLocalProcessEnvironmentInheritance = .none,
        stdin: GraphLocalProcessStdinPolicy = .nullDevice,
        outputArtifacts: [GraphLocalProcessArtifactDeclaration] = [],
        retryableExitCodes: [Int32] = [],
        logPolicy: GraphLocalProcessLogPolicy = GraphLocalProcessLogPolicy()
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.inheritedEnvironment = inheritedEnvironment
        self.stdin = stdin
        self.outputArtifacts = outputArtifacts.sorted {
            if $0.role != $1.role {
                return $0.role.rawValue < $1.role.rawValue
            }
            return $0.relativePath < $1.relativePath
        }
        self.retryableExitCodes = retryableExitCodes.sorted()
        self.logPolicy = logPolicy
    }

    public init(
        immutableSpecification: GraphImmutableExecutionSpecification
    ) throws {
        guard immutableSpecification.adapterKind == Self.adapterKind,
              immutableSpecification.operation == Self.operation else {
            throw GraphLocalProcessSpecificationError.unsupportedAdapter(
                immutableSpecification.adapterKind,
                immutableSpecification.operation
            )
        }
        let data = try JSONEncoder().encode(
            immutableSpecification.parameters
        )
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    public func immutableSpecification() throws
        -> GraphImmutableExecutionSpecification
    {
        let data = try JSONEncoder().encode(self)
        let parameters = try JSONDecoder().decode(
            [String: GraphJSONValue].self,
            from: data
        )
        return GraphImmutableExecutionSpecification(
            adapterKind: Self.adapterKind,
            operation: Self.operation,
            parameters: parameters
        )
    }
}

public enum GraphLocalProcessSpecificationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedAdapter(String, String)
    case executableMustBeAbsolute(String)
    case executableUnavailable(String)
    case shellExecutionRequiresSeparatePolicy(String)
    case workspaceRootRequired
    case workspaceUnavailable(String)
    case workingDirectoryEscapesWorkspace(String)
    case workingDirectoryUnavailable(String)
    case environmentNotAllowed(String)
    case sensitiveEnvironmentValue(String)
    case duplicateArtifactRole(String)
    case artifactPathInvalid(String)
    case artifactPathNotWritable(String)
    case inputArtifactUnavailable(String)
    case unknownArgumentToken(String)
}

extension GraphLocalProcessSpecificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedAdapter(adapter, operation):
            "Unsupported process adapter \(adapter)/\(operation)."
        case let .executableMustBeAbsolute(path):
            "Executable path must be absolute: \(path)."
        case let .executableUnavailable(path):
            "Executable is unavailable or not executable: \(path)."
        case let .shellExecutionRequiresSeparatePolicy(path):
            "Shell execution requires a separately classified adapter: \(path)."
        case .workspaceRootRequired:
            "Local process execution requires a workspace root."
        case let .workspaceUnavailable(path):
            "Workspace is unavailable: \(path)."
        case let .workingDirectoryEscapesWorkspace(path):
            "Working directory escapes the workspace: \(path)."
        case let .workingDirectoryUnavailable(path):
            "Working directory is unavailable: \(path)."
        case let .environmentNotAllowed(key):
            "Environment key is not allowlisted: \(key)."
        case let .sensitiveEnvironmentValue(key):
            "Sensitive environment key \(key) must be inherited, not embedded."
        case let .duplicateArtifactRole(role):
            "Output artifact role is declared more than once: \(role)."
        case let .artifactPathInvalid(path):
            "Artifact path is invalid or escapes the workspace: \(path)."
        case let .artifactPathNotWritable(path):
            "Artifact path is outside declared writable locations: \(path)."
        case let .inputArtifactUnavailable(role):
            "Input artifact is unavailable for role \(role)."
        case let .unknownArgumentToken(token):
            "Unknown structured argument token: \(token)."
        }
    }
}

public struct GraphResolvedLocalProcessSpecification: Sendable {
    public let specification: GraphLocalProcessSpecification
    public let executableURL: URL
    public let arguments: [String]
    public let workspaceURL: URL
    public let workingDirectoryURL: URL
    public let environment: [String: String]
    public let artifactURLs: [GraphArtifactRole: URL]
    public let redactionValues: [String]
}

public enum GraphLocalProcessSpecificationResolver {
    public static func resolve(
        _ specification: GraphLocalProcessSpecification,
        context: GraphExecutorCommandContext,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> GraphResolvedLocalProcessSpecification {
        let executableURL = URL(fileURLWithPath: specification.executable)
            .standardizedFileURL
        guard executableURL.path.hasPrefix("/") else {
            throw GraphLocalProcessSpecificationError
                .executableMustBeAbsolute(specification.executable)
        }
        let shells = ["/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/env"]
        guard !shells.contains(executableURL.path) else {
            throw GraphLocalProcessSpecificationError
                .shellExecutionRequiresSeparatePolicy(executableURL.path)
        }
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw GraphLocalProcessSpecificationError
                .executableUnavailable(executableURL.path)
        }
        guard let root = context.workspace.root, !root.isEmpty else {
            throw GraphLocalProcessSpecificationError.workspaceRootRequired
        }
        let workspaceURL = URL(fileURLWithPath: root, isDirectory: true)
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: workspaceURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw GraphLocalProcessSpecificationError
                .workspaceUnavailable(workspaceURL.path)
        }
        let workingDirectoryURL = workspaceURL
            .appendingPathComponent(specification.workingDirectory, isDirectory: true)
            .standardizedFileURL
        guard contains(workingDirectoryURL, in: workspaceURL) else {
            throw GraphLocalProcessSpecificationError
                .workingDirectoryEscapesWorkspace(specification.workingDirectory)
        }
        guard fileManager.fileExists(
            atPath: workingDirectoryURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw GraphLocalProcessSpecificationError
                .workingDirectoryUnavailable(workingDirectoryURL.path)
        }

        let allowed = Set(context.environmentAllowlist)
        for key in specification.environment.keys where !allowed.contains(key) {
            throw GraphLocalProcessSpecificationError.environmentNotAllowed(key)
        }
        for key in specification.logPolicy.sensitiveEnvironmentKeys
            where specification.environment[key] != nil {
            throw GraphLocalProcessSpecificationError
                .sensitiveEnvironmentValue(key)
        }
        var environment = specification.environment
        if specification.inheritedEnvironment == .allowlisted {
            for key in allowed where environment[key] == nil {
                environment[key] = processEnvironment[key]
            }
        }

        let groupedRoles = Dictionary(
            grouping: specification.outputArtifacts,
            by: \.role
        )
        if let duplicate = groupedRoles.first(where: { $0.value.count > 1 }) {
            throw GraphLocalProcessSpecificationError
                .duplicateArtifactRole(duplicate.key.rawValue)
        }
        var artifactURLs: [GraphArtifactRole: URL] = [:]
        for declaration in specification.outputArtifacts {
            guard !declaration.relativePath.isEmpty,
                  !declaration.relativePath.hasPrefix("/") else {
                throw GraphLocalProcessSpecificationError
                    .artifactPathInvalid(declaration.relativePath)
            }
            let output = workspaceURL
                .appendingPathComponent(declaration.relativePath)
                .standardizedFileURL
            guard contains(output, in: workspaceURL) else {
                throw GraphLocalProcessSpecificationError
                    .artifactPathInvalid(declaration.relativePath)
            }
            let writable = context.workspace.writableRelativePaths.contains {
                writablePath in
                let writableURL = workspaceURL
                    .appendingPathComponent(writablePath, isDirectory: true)
                    .standardizedFileURL
                return contains(output, in: writableURL)
                    || output == writableURL
            }
            guard writable else {
                throw GraphLocalProcessSpecificationError
                    .artifactPathNotWritable(declaration.relativePath)
            }
            artifactURLs[declaration.role] = output
        }

        let arguments = try specification.arguments.map { argument in
            try resolveArgument(
                argument,
                context: context,
                workspaceURL: workspaceURL,
                artifactURLs: artifactURLs
            )
        }
        let redactions = specification.logPolicy.sensitiveEnvironmentKeys
            .compactMap { environment[$0] }
            .filter { !$0.isEmpty }
        return GraphResolvedLocalProcessSpecification(
            specification: specification,
            executableURL: executableURL,
            arguments: arguments,
            workspaceURL: workspaceURL,
            workingDirectoryURL: workingDirectoryURL,
            environment: environment,
            artifactURLs: artifactURLs,
            redactionValues: redactions
        )
    }

    private static func resolveArgument(
        _ argument: String,
        context: GraphExecutorCommandContext,
        workspaceURL: URL,
        artifactURLs: [GraphArtifactRole: URL]
    ) throws -> String {
        guard argument.hasPrefix("${"), argument.hasSuffix("}") else {
            return argument
        }
        if argument == "${workspace}" {
            return workspaceURL.path
        }
        if argument.hasPrefix("${artifact:") {
            let roleValue = String(argument.dropFirst(11).dropLast())
            guard let role = GraphArtifactRole(rawValue: roleValue),
                  let url = artifactURLs[role] else {
                throw GraphLocalProcessSpecificationError
                    .unknownArgumentToken(argument)
            }
            return url.path
        }
        if argument.hasPrefix("${input:") {
            let role = String(argument.dropFirst(8).dropLast())
            guard let artifact = context.inputArtifacts.first(where: {
                $0.logicalRole == role && $0.storage.scheme == "file"
            }) else {
                throw GraphLocalProcessSpecificationError
                    .inputArtifactUnavailable(role)
            }
            return artifact.storage.opaqueReference
        }
        throw GraphLocalProcessSpecificationError.unknownArgumentToken(argument)
    }

    private static func contains(_ child: URL, in parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return childPath == parentPath
            || childPath.hasPrefix(parentPath.hasSuffix("/")
                ? parentPath : parentPath + "/")
    }
}

public struct LocalProcessExecutionConfirmationPolicy:
    GraphExecutionConfirmationPolicy,
    Sendable
{
    public init() {}

    public func permits(
        operation: GraphExecutorOperation,
        context: GraphExecutorCommandContext
    ) -> Bool {
        context.specification.adapterKind
            == GraphLocalProcessSpecification.adapterKind
    }
}
