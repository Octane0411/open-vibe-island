import Foundation

public struct PiExtensionInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-pi-extension-install.json"
    public static let currentVersion = 3

    public var agent: PiAgentVariant
    public var extensionPath: String
    public var version: Int?

    public init(
        agent: PiAgentVariant,
        extensionPath: String,
        version: Int? = Self.currentVersion
    ) {
        self.agent = agent
        self.extensionPath = extensionPath
        self.version = version
    }
}

public struct PiExtensionInstallationStatus: Equatable, Sendable {
    public var agent: PiAgentVariant
    public var agentDirectory: URL
    public var extensionsDirectory: URL
    public var extensionURL: URL
    public var manifestURL: URL
    public var extensionFilePresent: Bool
    public var manifest: PiExtensionInstallerManifest?

    public var isInstalled: Bool {
        extensionFilePresent
            && manifest?.agent == agent
            && manifest?.extensionPath == extensionURL.path
    }

    public var isCurrent: Bool {
        isInstalled && manifest?.version == PiExtensionInstallerManifest.currentVersion
    }

    public init(
        agent: PiAgentVariant,
        agentDirectory: URL,
        extensionsDirectory: URL,
        extensionURL: URL,
        manifestURL: URL,
        extensionFilePresent: Bool,
        manifest: PiExtensionInstallerManifest?
    ) {
        self.agent = agent
        self.agentDirectory = agentDirectory
        self.extensionsDirectory = extensionsDirectory
        self.extensionURL = extensionURL
        self.manifestURL = manifestURL
        self.extensionFilePresent = extensionFilePresent
        self.manifest = manifest
    }
}

public enum PiExtensionInstallationError: LocalizedError, Equatable {
    case invalidSourceEncoding
    case missingAgentPlaceholder

    public var errorDescription: String? {
        switch self {
        case .invalidSourceEncoding:
            "The bundled Pi extension is not valid UTF-8."
        case .missingAgentPlaceholder:
            "The bundled Pi extension is missing its agent placeholder."
        }
    }
}

public final class PiExtensionInstallationManager: @unchecked Sendable {
    public static let extensionFileName = "open-island.ts"
    public static let agentPlaceholder = "__OPEN_ISLAND_PI_SOURCE__"

    public let agent: PiAgentVariant
    public let agentDirectory: URL
    private let fileManager: FileManager

    public init(
        agent: PiAgentVariant,
        agentDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.agent = agent
        self.agentDirectory = agentDirectory ?? Self.defaultAgentDirectory(for: agent)
        self.fileManager = fileManager
    }

    public static func defaultAgentDirectory(for agent: PiAgentVariant) -> URL {
        let directoryName = agent == .pi ? ".pi" : ".omp"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
    }

    public var extensionsDirectory: URL {
        agentDirectory.appendingPathComponent("extensions", isDirectory: true)
    }

    public var extensionURL: URL {
        extensionsDirectory.appendingPathComponent(Self.extensionFileName)
    }

    public var manifestURL: URL {
        agentDirectory.appendingPathComponent(PiExtensionInstallerManifest.fileName)
    }

    public func status() throws -> PiExtensionInstallationStatus {
        PiExtensionInstallationStatus(
            agent: agent,
            agentDirectory: agentDirectory,
            extensionsDirectory: extensionsDirectory,
            extensionURL: extensionURL,
            manifestURL: manifestURL,
            extensionFilePresent: fileManager.fileExists(atPath: extensionURL.path),
            manifest: try loadManifest()
        )
    }

    @discardableResult
    public func install(extensionSourceData: Data) throws -> PiExtensionInstallationStatus {
        guard var source = String(data: extensionSourceData, encoding: .utf8) else {
            throw PiExtensionInstallationError.invalidSourceEncoding
        }
        guard source.contains(Self.agentPlaceholder) else {
            throw PiExtensionInstallationError.missingAgentPlaceholder
        }

        source = source.replacingOccurrences(of: Self.agentPlaceholder, with: agent.rawValue)
        try fileManager.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)
        try Data(source.utf8).write(to: extensionURL, options: .atomic)

        let manifest = PiExtensionInstallerManifest(agent: agent, extensionPath: extensionURL.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return try status()
    }

    @discardableResult
    public func uninstall() throws -> PiExtensionInstallationStatus {
        if fileManager.fileExists(atPath: extensionURL.path) {
            try fileManager.removeItem(at: extensionURL)
        }
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
        return try status()
    }

    private func loadManifest() throws -> PiExtensionInstallerManifest? {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        return try JSONDecoder().decode(
            PiExtensionInstallerManifest.self,
            from: Data(contentsOf: manifestURL)
        )
    }
}
