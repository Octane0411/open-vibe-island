import Foundation

public struct HermesHookInstallationStatus: Equatable, Sendable {
    public var hermesDirectory: URL
    public var pluginDirectory: URL
    public var pluginYAMLURL: URL
    public var pluginInitURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var hasForeignPluginDirectory: Bool
    public var manifest: HermesHookInstallerManifest?

    public init(
        hermesDirectory: URL,
        pluginDirectory: URL,
        pluginYAMLURL: URL,
        pluginInitURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        hasForeignPluginDirectory: Bool,
        manifest: HermesHookInstallerManifest?
    ) {
        self.hermesDirectory = hermesDirectory
        self.pluginDirectory = pluginDirectory
        self.pluginYAMLURL = pluginYAMLURL
        self.pluginInitURL = pluginInitURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.hasForeignPluginDirectory = hasForeignPluginDirectory
        self.manifest = manifest
    }
}

public final class HermesHookInstallationManager: @unchecked Sendable {
    public let hermesDirectory: URL
    public let pluginDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        hermesDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.hermesDirectory = hermesDirectory
        self.pluginDirectory = hermesDirectory
            .appendingPathComponent("plugins", isDirectory: true)
            .appendingPathComponent(HermesHookInstaller.pluginDirectoryName, isDirectory: true)
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> HermesHookInstallationStatus {
        let pluginYAMLURL = pluginDirectory.appendingPathComponent("plugin.yaml")
        let pluginInitURL = pluginDirectory.appendingPathComponent("__init__.py")
        let manifestURL = pluginDirectory.appendingPathComponent(HermesHookInstallerManifest.fileName)
        let resolvedBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)
        let manifest = try loadManifest(at: manifestURL)

        let pluginDirectoryExists = fileManager.fileExists(atPath: pluginDirectory.path)
        let yamlData = try? Data(contentsOf: pluginYAMLURL)
        let isManaged = HermesHookInstaller.isManagedPlugin(pluginYAMLData: yamlData)
        let managedHooksPresent = pluginDirectoryExists
            && isManaged
            && fileManager.fileExists(atPath: pluginInitURL.path)
        let hasForeignPluginDirectory = pluginDirectoryExists && !isManaged

        return HermesHookInstallationStatus(
            hermesDirectory: hermesDirectory,
            pluginDirectory: pluginDirectory,
            pluginYAMLURL: pluginYAMLURL,
            pluginInitURL: pluginInitURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedBinaryURL,
            managedHooksPresent: managedHooksPresent,
            hasForeignPluginDirectory: hasForeignPluginDirectory,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> HermesHookInstallationStatus {
        try fileManager.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)

        let installedBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )

        let pluginYAMLURL = pluginDirectory.appendingPathComponent("plugin.yaml")
        let pluginInitURL = pluginDirectory.appendingPathComponent("__init__.py")
        let manifestURL = pluginDirectory.appendingPathComponent(HermesHookInstallerManifest.fileName)

        // If a foreign plugin lives at this path, refuse to clobber it. The
        // caller can clean it up manually or pass a different directory.
        if fileManager.fileExists(atPath: pluginYAMLURL.path) {
            let yamlData = try? Data(contentsOf: pluginYAMLURL)
            if !HermesHookInstaller.isManagedPlugin(pluginYAMLData: yamlData) {
                throw HermesHookInstallationError.foreignPluginAtPath(pluginDirectory.path)
            }
        }

        let assets = HermesHookInstaller.renderPluginAssets(hookBinaryPath: installedBinaryURL.path)

        try assets.pluginYAML.write(to: pluginYAMLURL, options: .atomic)
        try assets.pluginInit.write(to: pluginInitURL, options: .atomic)

        let manifest = HermesHookInstallerManifest(hookBinaryPath: installedBinaryURL.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> HermesHookInstallationStatus {
        let pluginYAMLURL = pluginDirectory.appendingPathComponent("plugin.yaml")

        guard fileManager.fileExists(atPath: pluginDirectory.path) else {
            return try status()
        }

        let yamlData = try? Data(contentsOf: pluginYAMLURL)
        guard HermesHookInstaller.isManagedPlugin(pluginYAMLData: yamlData) else {
            // Do not touch a user-authored plugin at the same path.
            return try status()
        }

        try fileManager.removeItem(at: pluginDirectory)

        // Also remove the containing `plugins` directory only when it is empty,
        // to avoid leaving our breadcrumbs behind in user `.hermes` trees.
        let pluginsRoot = pluginDirectory.deletingLastPathComponent()
        if fileManager.fileExists(atPath: pluginsRoot.path),
           let contents = try? fileManager.contentsOfDirectory(at: pluginsRoot, includingPropertiesForKeys: nil),
           contents.isEmpty {
            try? fileManager.removeItem(at: pluginsRoot)
        }

        return try status()
    }

    private func loadManifest(at url: URL) throws -> HermesHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HermesHookInstallerManifest.self, from: data)
    }

    private func resolvedHooksBinaryURL(explicitURL: URL?) -> URL? {
        if let explicitURL {
            return explicitURL.standardizedFileURL
        }

        guard fileManager.isExecutableFile(atPath: managedHooksBinaryURL.path) else {
            return nil
        }

        return managedHooksBinaryURL
    }
}

public enum HermesHookInstallationError: Error, LocalizedError {
    case foreignPluginAtPath(String)

    public var errorDescription: String? {
        switch self {
        case let .foreignPluginAtPath(path):
            return "A non-Open-Island plugin already exists at \(path). Remove it manually or use a different plugin directory before installing."
        }
    }
}
