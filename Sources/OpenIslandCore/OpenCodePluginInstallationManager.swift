import Foundation

public struct OpenCodePluginInstallationStatus: Equatable, Sendable {
    public var openCodeConfigDirectory: URL
    public var pluginsDirectory: URL
    public var configURL: URL
    public var pluginFileURL: URL
    public var manifestURL: URL
    public var pluginFilePresent: Bool
    public var pluginRegistered: Bool
    public var manifest: OpenCodePluginInstallerManifest?

    public var isInstalled: Bool {
        pluginFilePresent && pluginRegistered
    }

    public init(
        openCodeConfigDirectory: URL,
        pluginsDirectory: URL,
        configURL: URL,
        pluginFileURL: URL,
        manifestURL: URL,
        pluginFilePresent: Bool,
        pluginRegistered: Bool,
        manifest: OpenCodePluginInstallerManifest?
    ) {
        self.openCodeConfigDirectory = openCodeConfigDirectory
        self.pluginsDirectory = pluginsDirectory
        self.configURL = configURL
        self.pluginFileURL = pluginFileURL
        self.manifestURL = manifestURL
        self.pluginFilePresent = pluginFilePresent
        self.pluginRegistered = pluginRegistered
        self.manifest = manifest
    }
}

public struct OpenCodePluginInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-opencode-plugin-install.json"

    public var pluginPath: String
    public var installedAt: Date

    public init(pluginPath: String, installedAt: Date = .now) {
        self.pluginPath = pluginPath
        self.installedAt = installedAt
    }
}

public final class OpenCodePluginInstallationManager: @unchecked Sendable {
    public static let pluginFileName = "open-island.js"

    public let openCodeConfigDirectory: URL
    private let fileManager: FileManager

    public init(
        openCodeConfigDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.openCodeConfigDirectory = openCodeConfigDirectory
        self.fileManager = fileManager
    }

    private var pluginsDirectory: URL {
        openCodeConfigDirectory.appendingPathComponent("plugins", isDirectory: true)
    }

    private var pluginFileURL: URL {
        pluginsDirectory.appendingPathComponent(Self.pluginFileName)
    }

    private var configURL: URL {
        openCodeConfigDirectory.appendingPathComponent("config.json")
    }

    private var manifestURL: URL {
        openCodeConfigDirectory.appendingPathComponent(OpenCodePluginInstallerManifest.fileName)
    }

    public func status() throws -> OpenCodePluginInstallationStatus {
        let pluginPresent = fileManager.fileExists(atPath: pluginFileURL.path)
        let registered = isPluginRegistered()
        let manifest = try loadManifest()

        return OpenCodePluginInstallationStatus(
            openCodeConfigDirectory: openCodeConfigDirectory,
            pluginsDirectory: pluginsDirectory,
            configURL: configURL,
            pluginFileURL: pluginFileURL,
            manifestURL: manifestURL,
            pluginFilePresent: pluginPresent,
            pluginRegistered: registered,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(pluginSourceData: Data) throws -> OpenCodePluginInstallationStatus {
        try update(pluginSourceData: pluginSourceData)
        return try status()
    }

    @discardableResult
    public func uninstall() throws -> OpenCodePluginInstallationStatus {
        try update(pluginSourceData: nil)
        return try status()
    }

    private func update(pluginSourceData: Data?) throws {
        ConfigurationTransaction.installationLock.lock()
        defer { ConfigurationTransaction.installationLock.unlock() }
        let config = try ConfigurationTransaction.File(configURL)
        let plugin = try ConfigurationTransaction.File(pluginFileURL)
        let manifestFile = try ConfigurationTransaction.File(manifestURL)
        var json = try configuration(from: config.original)
        let reference = pluginFileURL.absoluteString
        var plugins = json["plugin"] as? [String] ?? []
        // Only this exact managed path is ours. Same-named plugins elsewhere belong to the user.
        plugins.removeAll { $0 == reference || $0 == "file://\(pluginFileURL.path)" }
        if pluginSourceData != nil { plugins.append(reference) }
        if plugins.isEmpty { json.removeValue(forKey: "plugin") } else { json["plugin"] = plugins }
        let output = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        _ = try configuration(from: output)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = try pluginSourceData.map { _ in
            try encoder.encode(OpenCodePluginInstallerManifest(pluginPath: pluginFileURL.path))
        }
        try ConfigurationTransaction.apply([
            .init(file: plugin, contents: pluginSourceData),
            .init(file: config, contents: config.original == nil && pluginSourceData == nil ? nil : output),
            .init(file: manifestFile, contents: manifest)
        ], recoveryRoot: openCodeConfigDirectory)
    }

    private func configuration(from data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["plugin"] == nil || json["plugin"] is [String] else {
            throw ConfigurationError.invalidFormat(configURL.path)
        }
        return json
    }

    private func isPluginRegistered() -> Bool {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? configuration(from: data),
              let plugins = json["plugin"] as? [String] else { return false }
        return plugins.contains(pluginFileURL.absoluteString) || plugins.contains("file://\(pluginFileURL.path)")
    }

    // MARK: - Helpers

    private func loadManifest() throws -> OpenCodePluginInstallerManifest? {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OpenCodePluginInstallerManifest.self, from: data)
    }

}
