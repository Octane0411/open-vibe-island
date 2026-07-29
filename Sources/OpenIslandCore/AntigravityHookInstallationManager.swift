import Foundation

public struct AntigravityHookInstallationStatus: Equatable, Sendable {
    public var antigravityDirectory: URL
    public var settingsURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: AntigravityHookInstallerManifest?

    public init(
        antigravityDirectory: URL,
        settingsURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: AntigravityHookInstallerManifest?
    ) {
        self.antigravityDirectory = antigravityDirectory
        self.settingsURL = settingsURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
    }
}

public typealias GeminiHookInstallationStatus = AntigravityHookInstallationStatus

public final class AntigravityHookInstallationManager: @unchecked Sendable {
    public let antigravityDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public static func defaultAntigravityDirectory(fileManager: FileManager = .default) -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        let primary = home.appendingPathComponent(".antigravity", isDirectory: true)
        let fallback = home.appendingPathComponent(".gemini", isDirectory: true)

        if fileManager.fileExists(atPath: primary.path) {
            return primary
        } else if fileManager.fileExists(atPath: fallback.path) {
            return fallback
        }
        return primary
    }

    public init(
        antigravityDirectory: URL? = nil,
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.antigravityDirectory = antigravityDirectory ?? Self.defaultAntigravityDirectory(fileManager: fileManager)
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> AntigravityHookInstallationStatus {
        let settingsURL = antigravityDirectory.appendingPathComponent("settings.json")
        let manifestURL = antigravityDirectory.appendingPathComponent(AntigravityHookInstallerManifest.fileName)
        let resolvedBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)
        let settingsData = try? Data(contentsOf: settingsURL)
        let manifest = try loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand ?? resolvedBinaryURL.map { AntigravityHookInstaller.hookCommand(for: $0.path) }
        let uninstallMutation = try AntigravityHookInstaller.uninstallSettingsJSON(
            existingData: settingsData,
            managedCommand: managedCommand
        )

        return AntigravityHookInstallationStatus(
            antigravityDirectory: antigravityDirectory,
            settingsURL: settingsURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedBinaryURL,
            managedHooksPresent: uninstallMutation.managedHooksPresent,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> AntigravityHookInstallationStatus {
        try fileManager.createDirectory(at: antigravityDirectory, withIntermediateDirectories: true)

        let settingsURL = antigravityDirectory.appendingPathComponent("settings.json")
        let manifestURL = antigravityDirectory.appendingPathComponent(AntigravityHookInstallerManifest.fileName)
        let existingSettings = try? Data(contentsOf: settingsURL)
        let installedBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = AntigravityHookInstaller.hookCommand(for: installedBinaryURL.path)
        let mutation = try AntigravityHookInstaller.installSettingsJSON(
            existingData: existingSettings,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: settingsURL.path) {
            try backupFile(at: settingsURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: settingsURL, options: .atomic)
        }

        let manifest = AntigravityHookInstallerManifest(hookCommand: command)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> AntigravityHookInstallationStatus {
        let settingsURL = antigravityDirectory.appendingPathComponent("settings.json")
        let manifestURL = antigravityDirectory.appendingPathComponent(AntigravityHookInstallerManifest.fileName)
        let manifest = try loadManifest(at: manifestURL)
        let existingSettings = try? Data(contentsOf: settingsURL)
        let mutation = try AntigravityHookInstaller.uninstallSettingsJSON(
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

    private func loadManifest(at url: URL) throws -> AntigravityHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AntigravityHookInstallerManifest.self, from: data)
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

public typealias GeminiHookInstallationManager = AntigravityHookInstallationManager
