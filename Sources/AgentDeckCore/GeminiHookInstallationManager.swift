import Foundation

public struct GeminiHookInstallationStatus: Equatable, Sendable {
    public var geminiDirectory: URL
    public var settingsURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: GeminiHookInstallerManifest?

    public init(
        geminiDirectory: URL,
        settingsURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: GeminiHookInstallerManifest?
    ) {
        self.geminiDirectory = geminiDirectory
        self.settingsURL = settingsURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
    }
}

public final class GeminiHookInstallationManager: @unchecked Sendable {
    public let geminiDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        geminiDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.geminiDirectory = geminiDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> GeminiHookInstallationStatus {
        let settingsURL = geminiDirectory.appendingPathComponent("settings.json")
        let manifestURL = geminiDirectory.appendingPathComponent(GeminiHookInstallerManifest.fileName)
        let resolvedBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)
        let settingsData = try? Data(contentsOf: settingsURL)
        let manifest = try loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand ?? resolvedBinaryURL.map { GeminiHookInstaller.hookCommand(for: $0.path) }
        let uninstallMutation = try GeminiHookInstaller.uninstallSettingsJSON(
            existingData: settingsData,
            managedCommand: managedCommand
        )

        return GeminiHookInstallationStatus(
            geminiDirectory: geminiDirectory,
            settingsURL: settingsURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedBinaryURL,
            managedHooksPresent: uninstallMutation.managedHooksPresent,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> GeminiHookInstallationStatus {
        try fileManager.createDirectory(at: geminiDirectory, withIntermediateDirectories: true)

        let settingsURL = geminiDirectory.appendingPathComponent("settings.json")
        let manifestURL = geminiDirectory.appendingPathComponent(GeminiHookInstallerManifest.fileName)
        let existingSettings = try? Data(contentsOf: settingsURL)
        let installedBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = GeminiHookInstaller.hookCommand(for: installedBinaryURL.path)
        let mutation = try GeminiHookInstaller.installSettingsJSON(
            existingData: existingSettings,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: settingsURL.path) {
            try backupFile(at: settingsURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: settingsURL, options: .atomic)
        }

        let manifest = GeminiHookInstallerManifest(hookCommand: command)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> GeminiHookInstallationStatus {
        let settingsURL = geminiDirectory.appendingPathComponent("settings.json")
        let manifestURL = geminiDirectory.appendingPathComponent(GeminiHookInstallerManifest.fileName)
        let manifest = try loadManifest(at: manifestURL)
        let existingSettings = try? Data(contentsOf: settingsURL)
        let mutation = try GeminiHookInstaller.uninstallSettingsJSON(
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

    private func loadManifest(at url: URL) throws -> GeminiHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GeminiHookInstallerManifest.self, from: data)
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
