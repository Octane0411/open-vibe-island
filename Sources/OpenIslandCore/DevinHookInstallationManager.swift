import Foundation

public struct DevinHookInstallationStatus: Equatable, Sendable {
    public var devinDirectory: URL
    public var configURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: DevinHookInstallationManifest?

    public init(
        devinDirectory: URL,
        configURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: DevinHookInstallationManifest?
    ) {
        self.devinDirectory = devinDirectory
        self.configURL = configURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
    }
}

public final class DevinHookInstallationManager: @unchecked Sendable {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/devin", isDirectory: true)
    }

    public let devinDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        devinDirectory: URL = DevinHookInstallationManager.defaultDirectory,
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.devinDirectory = devinDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> DevinHookInstallationStatus {
        let configURL = devinDirectory.appendingPathComponent("config.json")
        let manifestURL = devinDirectory.appendingPathComponent(DevinHookInstallationManifest.fileName)
        let resolvedHooksBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)
        let configData = try? Data(contentsOf: configURL)
        let manifest = try loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand
            ?? resolvedHooksBinaryURL.map { DevinHookInstaller.hookCommand(for: $0.path) }
        let mutation = try DevinHookInstaller.uninstallConfigJSON(
            existingData: configData,
            managedCommand: managedCommand
        )

        return DevinHookInstallationStatus(
            devinDirectory: devinDirectory,
            configURL: configURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedHooksBinaryURL,
            managedHooksPresent: mutation.managedHooksPresent,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> DevinHookInstallationStatus {
        try fileManager.createDirectory(at: devinDirectory, withIntermediateDirectories: true)

        let configURL = devinDirectory.appendingPathComponent("config.json")
        let manifestURL = devinDirectory.appendingPathComponent(DevinHookInstallationManifest.fileName)
        let existingConfig = try? Data(contentsOf: configURL)
        let installedHooksBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = DevinHookInstaller.hookCommand(for: installedHooksBinaryURL.path)
        let mutation = try DevinHookInstaller.installConfigJSON(
            existingData: existingConfig,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }
        if let contents = mutation.contents {
            try contents.write(to: configURL, options: .atomic)
        }

        let manifest = DevinHookInstallationManifest(hookCommand: command)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedHooksBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> DevinHookInstallationStatus {
        let configURL = devinDirectory.appendingPathComponent("config.json")
        let manifestURL = devinDirectory.appendingPathComponent(DevinHookInstallationManifest.fileName)
        let manifest = try loadManifest(at: manifestURL)
        let existingConfig = try? Data(contentsOf: configURL)
        let mutation = try DevinHookInstaller.uninstallConfigJSON(
            existingData: existingConfig,
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

    private func loadManifest(at url: URL) throws -> DevinHookInstallationManifest? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DevinHookInstallationManifest.self, from: data)
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
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
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
