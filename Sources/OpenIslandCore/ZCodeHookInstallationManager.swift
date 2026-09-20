import Foundation

public struct ZCodeHookInstallationStatus: Equatable, Sendable, Codable {
    public var zcodeDirectory: URL
    public var configURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: ZCodeHookInstallerManifest?

    public init(
        zcodeDirectory: URL,
        configURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: ZCodeHookInstallerManifest?
    ) {
        self.zcodeDirectory = zcodeDirectory
        self.configURL = configURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
    }
}

public final class ZCodeHookInstallationManager: @unchecked Sendable {
    public static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".zcode/cli", isDirectory: true)

    public let zcodeDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        zcodeDirectory: URL = ZCodeHookInstallationManager.defaultDirectory,
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.zcodeDirectory = zcodeDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> ZCodeHookInstallationStatus {
        let configURL = zcodeDirectory.appendingPathComponent("config.json")
        let manifestURL = zcodeDirectory.appendingPathComponent(ZCodeHookInstallerManifest.fileName)
        let resolvedBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)
        let configData = try? Data(contentsOf: configURL)
        let manifest = try loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand
            ?? resolvedBinaryURL.map { ZCodeHookInstaller.hookCommand(for: $0.path) }

        let managedPresent: Bool
        if let configData {
            managedPresent = try ZCodeHookInstaller.uninstallConfigJSON(
                existingData: configData,
                managedCommand: managedCommand
            ).managedHooksPresent
        } else {
            managedPresent = false
        }

        return ZCodeHookInstallationStatus(
            zcodeDirectory: zcodeDirectory,
            configURL: configURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedBinaryURL,
            managedHooksPresent: managedPresent,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> ZCodeHookInstallationStatus {
        try fileManager.createDirectory(at: zcodeDirectory, withIntermediateDirectories: true)

        let configURL = zcodeDirectory.appendingPathComponent("config.json")
        let manifestURL = zcodeDirectory.appendingPathComponent(ZCodeHookInstallerManifest.fileName)
        let existingData = try? Data(contentsOf: configURL)
        let installedBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = ZCodeHookInstaller.hookCommand(for: installedBinaryURL.path)
        let mutation = try ZCodeHookInstaller.installConfigJSON(
            existingData: existingData,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: configURL, options: .atomic)
        }

        let manifest = ZCodeHookInstallerManifest(hookCommand: command)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> ZCodeHookInstallationStatus {
        let configURL = zcodeDirectory.appendingPathComponent("config.json")
        let manifestURL = zcodeDirectory.appendingPathComponent(ZCodeHookInstallerManifest.fileName)
        let manifest = try loadManifest(at: manifestURL)
        let existingData = try? Data(contentsOf: configURL)

        let mutation = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: existingData,
            managedCommand: manifest?.hookCommand
        )

        if mutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: configURL, options: .atomic)
        } else if fileManager.fileExists(atPath: configURL.path) {
            try fileManager.removeItem(at: configURL)
        }

        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        return try status()
    }

    private func loadManifest(at url: URL) throws -> ZCodeHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ZCodeHookInstallerManifest.self, from: data)
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
