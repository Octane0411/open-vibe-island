import Foundation

public struct CatPawHookInstallationStatus: Equatable, Sendable {
    public var catPawDirectory: URL
    public var settingsURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: CatPawHookInstallerManifest?

    public init(
        catPawDirectory: URL,
        settingsURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: CatPawHookInstallerManifest?
    ) {
        self.catPawDirectory = catPawDirectory
        self.settingsURL = settingsURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
    }
}

/// Manages installation of Open Island hooks into CatPaw's settings.json.
///
/// CatPaw stores its configuration under `~/.catpaw/` with a `settings.json` file
/// that uses the same hook format as Claude Code.
public final class CatPawHookInstallationManager: @unchecked Sendable {
    public let catPawDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        catPawDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".catpaw", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.catPawDirectory = catPawDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> CatPawHookInstallationStatus {
        let settingsURL = catPawDirectory.appendingPathComponent("settings.json")
        let manifestURL = catPawDirectory.appendingPathComponent(CatPawHookInstallerManifest.fileName)
        let resolvedBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)

        let settingsData = try? Data(contentsOf: settingsURL)
        let manifest = try loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand
            ?? resolvedBinaryURL.map { CatPawHookInstaller.hookCommand(for: $0.path) }
        let uninstallMutation = try CatPawHookInstaller.uninstallSettingsJSON(
            existingData: settingsData,
            managedCommand: managedCommand
        )

        return CatPawHookInstallationStatus(
            catPawDirectory: catPawDirectory,
            settingsURL: settingsURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedBinaryURL,
            managedHooksPresent: uninstallMutation.managedHooksPresent,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> CatPawHookInstallationStatus {
        try fileManager.createDirectory(at: catPawDirectory, withIntermediateDirectories: true)

        let settingsURL = catPawDirectory.appendingPathComponent("settings.json")
        let manifestURL = catPawDirectory.appendingPathComponent(CatPawHookInstallerManifest.fileName)
        let existingSettings = try? Data(contentsOf: settingsURL)
        let installedBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = CatPawHookInstaller.hookCommand(for: installedBinaryURL.path)
        let mutation = try CatPawHookInstaller.installSettingsJSON(
            existingData: existingSettings,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: settingsURL.path) {
            try backupFile(at: settingsURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: settingsURL, options: .atomic)
        }

        let manifest = CatPawHookInstallerManifest(hookCommand: command)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> CatPawHookInstallationStatus {
        let settingsURL = catPawDirectory.appendingPathComponent("settings.json")
        let manifestURL = catPawDirectory.appendingPathComponent(CatPawHookInstallerManifest.fileName)
        let manifest = try loadManifest(at: manifestURL)
        let existingSettings = try? Data(contentsOf: settingsURL)
        let mutation = try CatPawHookInstaller.uninstallSettingsJSON(
            existingData: existingSettings,
            managedCommand: manifest?.hookCommand
        )

        if mutation.changed, fileManager.fileExists(atPath: settingsURL.path) {
            try backupFile(at: settingsURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: settingsURL, options: .atomic)
        } else if fileManager.fileExists(atPath: settingsURL.path) {
            try fileManager.removeItem(at: settingsURL)
        }

        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        return try status()
    }

    // MARK: - Private helpers

    private func loadManifest(at url: URL) throws -> CatPawHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CatPawHookInstallerManifest.self, from: data)
    }

    private func resolvedHooksBinaryURL(explicitURL: URL?) -> URL? {
        if let explicitURL { return explicitURL.standardizedFileURL }
        guard fileManager.isExecutableFile(atPath: managedHooksBinaryURL.path) else { return nil }
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

