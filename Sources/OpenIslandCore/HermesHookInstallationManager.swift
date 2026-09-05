import Foundation

public struct HermesHookInstallationStatus: Codable, Equatable, Sendable {
    public var hermesDirectory: URL
    public var configURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: HermesHookInstallationManifest?

    public init(
        hermesDirectory: URL,
        configURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: HermesHookInstallationManifest?
    ) {
        self.hermesDirectory = hermesDirectory
        self.configURL = configURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
    }
}

public final class HermesHookInstallationManager: @unchecked Sendable {
    public let hermesDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        hermesDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.hermesDirectory = hermesDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> HermesHookInstallationStatus {
        let configURL = hermesDirectory.appendingPathComponent("config.yaml")
        let manifestURL = hermesDirectory.appendingPathComponent(HermesHookInstallationManifest.fileName)
        let resolvedBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)
        let configData = try? Data(contentsOf: configURL)
        let manifest = try loadManifest(at: manifestURL)
        let managedHooksPresent = try HermesHookInstaller.configYAMLHasOpenIslandHooks(existingData: configData)

        return HermesHookInstallationStatus(
            hermesDirectory: hermesDirectory,
            configURL: configURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedBinaryURL,
            managedHooksPresent: managedHooksPresent,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> HermesHookInstallationStatus {
        try fileManager.createDirectory(at: hermesDirectory, withIntermediateDirectories: true)

        let configURL = hermesDirectory.appendingPathComponent("config.yaml")
        let manifestURL = hermesDirectory.appendingPathComponent(HermesHookInstallationManifest.fileName)
        let existingConfig = try? Data(contentsOf: configURL)
        let installedBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = HermesHookInstaller.hookCommand(for: installedBinaryURL.path)
        let mutation = try HermesHookInstaller.installConfigYAML(
            existingData: existingConfig,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: configURL, options: .atomic)
        }

        let manifest = HermesHookInstallationManifest(hookCommand: command)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> HermesHookInstallationStatus {
        let configURL = hermesDirectory.appendingPathComponent("config.yaml")
        let manifestURL = hermesDirectory.appendingPathComponent(HermesHookInstallationManifest.fileName)
        let manifest = try loadManifest(at: manifestURL)
        let existingConfig = try? Data(contentsOf: configURL)
        let mutation = try HermesHookInstaller.uninstallConfigYAML(
            existingData: existingConfig,
            managedCommand: manifest?.hookCommand
        )

        if mutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: configURL, options: .atomic)
        }

        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        return try status()
    }

    private func loadManifest(at url: URL) throws -> HermesHookInstallationManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HermesHookInstallationManifest.self, from: data)
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

    private func backupFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backupURL = url.appendingPathExtension("backup.\(timestamp)")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: url, to: backupURL)
    }
}
