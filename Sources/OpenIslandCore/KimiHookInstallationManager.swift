import Foundation

public struct KimiHookInstallationStatus: Equatable, Sendable {
    public var kimiDirectory: URL
    public var configURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: KimiHookInstallerManifest?

    public init(
        kimiDirectory: URL,
        configURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: KimiHookInstallerManifest?
    ) {
        self.kimiDirectory = kimiDirectory
        self.configURL = configURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
    }
}

public final class KimiHookInstallationManager: @unchecked Sendable {
    public let kimiDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        kimiDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.kimiDirectory = kimiDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> KimiHookInstallationStatus {
        let configURL = kimiDirectory.appendingPathComponent("config.toml")
        let manifestURL = kimiDirectory.appendingPathComponent(KimiHookInstallerManifest.fileName)
        let resolvedBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)
        let configContents = (try? String(contentsOf: configURL, encoding: .utf8))
        let manifest = try loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand
            ?? resolvedBinaryURL.map { KimiHookInstaller.hookCommand(for: $0.path) }

        let managedPresent = configContents.map { contents in
            KimiHookInstaller.uninstallConfigTOML(
                existingContents: contents,
                managedCommand: managedCommand
            ).changed
        } ?? false

        return KimiHookInstallationStatus(
            kimiDirectory: kimiDirectory,
            configURL: configURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedBinaryURL,
            managedHooksPresent: managedPresent,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> KimiHookInstallationStatus {
        try fileManager.createDirectory(at: kimiDirectory, withIntermediateDirectories: true)

        let configURL = kimiDirectory.appendingPathComponent("config.toml")
        let manifestURL = kimiDirectory.appendingPathComponent(KimiHookInstallerManifest.fileName)
        let existingContents = try? String(contentsOf: configURL, encoding: .utf8)
        let installedBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = KimiHookInstaller.hookCommand(for: installedBinaryURL.path)
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: existingContents,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: configURL, atomically: true, encoding: .utf8)
        }

        let manifest = KimiHookInstallerManifest(hookCommand: command)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> KimiHookInstallationStatus {
        let configURL = kimiDirectory.appendingPathComponent("config.toml")
        let manifestURL = kimiDirectory.appendingPathComponent(KimiHookInstallerManifest.fileName)
        let manifest = try loadManifest(at: manifestURL)
        let existingContents = try? String(contentsOf: configURL, encoding: .utf8)

        let mutation = KimiHookInstaller.uninstallConfigTOML(
            existingContents: existingContents,
            managedCommand: manifest?.hookCommand
        )

        if mutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: configURL, atomically: true, encoding: .utf8)
        } else if fileManager.fileExists(atPath: configURL.path) {
            try fileManager.removeItem(at: configURL)
        }

        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        return try status()
    }

    private func loadManifest(at url: URL) throws -> KimiHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(KimiHookInstallerManifest.self, from: data)
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
