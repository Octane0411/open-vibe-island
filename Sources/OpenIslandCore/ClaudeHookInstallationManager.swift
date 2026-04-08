import Foundation

public struct ClaudeHookInstallationStatus: Equatable, Sendable {
    public var claudeDirectory: URL
    public var settingsURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var hasClaudeIslandHooks: Bool
    public var manifest: ClaudeHookInstallerManifest?

    public init(
        claudeDirectory: URL,
        settingsURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        hasClaudeIslandHooks: Bool,
        manifest: ClaudeHookInstallerManifest?
    ) {
        self.claudeDirectory = claudeDirectory
        self.settingsURL = settingsURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.hasClaudeIslandHooks = hasClaudeIslandHooks
        self.manifest = manifest
    }
}

public final class ClaudeHookInstallationManager: @unchecked Sendable {
    public let claudeDirectory: URL
    public let managedHooksBinaryURL: URL
    /// The `--source` value passed to the hooks binary (e.g. "claude", "qoder", "factory", "codebuddy").
    public let hookSource: String
    private let fileManager: FileManager

    public init(
        claudeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        hookSource: String = "claude",
        fileManager: FileManager = .default
    ) {
        self.claudeDirectory = claudeDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.hookSource = hookSource
        self.fileManager = fileManager
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> ClaudeHookInstallationStatus {
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let manifestURL = resolvedManifestURL()
        let resolvedHooksBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)

        let settingsData = try? Data(contentsOf: settingsURL)
        let manifest = try loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand ?? resolvedHooksBinaryURL.map { ClaudeHookInstaller.hookCommand(for: $0.path, source: hookSource) }
        let uninstallMutation = try ClaudeHookInstaller.uninstallSettingsJSON(
            existingData: settingsData,
            managedCommand: managedCommand
        )

        return ClaudeHookInstallationStatus(
            claudeDirectory: claudeDirectory,
            settingsURL: settingsURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedHooksBinaryURL,
            managedHooksPresent: uninstallMutation.managedHooksPresent,
            hasClaudeIslandHooks: uninstallMutation.hasClaudeIslandHooks,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> ClaudeHookInstallationStatus {
        try fileManager.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let manifestURL = claudeDirectory.appendingPathComponent(ClaudeHookInstallerManifest.fileName)
        let legacyManifestURL = claudeDirectory.appendingPathComponent(ClaudeHookInstallerManifest.legacyFileName)
        let existingSettings = try? Data(contentsOf: settingsURL)
        let installedHooksBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = ClaudeHookInstaller.hookCommand(for: installedHooksBinaryURL.path, source: hookSource)
        let mutation = try ClaudeHookInstaller.installSettingsJSON(
            existingData: existingSettings,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: settingsURL.path) {
            try backupFile(at: settingsURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: settingsURL, options: .atomic)
        }

        let manifest = ClaudeHookInstallerManifest(hookCommand: command)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        if fileManager.fileExists(atPath: legacyManifestURL.path) {
            try fileManager.removeItem(at: legacyManifestURL)
        }

        return try status(hooksBinaryURL: installedHooksBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> ClaudeHookInstallationStatus {
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let manifestURL = resolvedManifestURL()
        let primaryManifestURL = claudeDirectory.appendingPathComponent(ClaudeHookInstallerManifest.fileName)
        let legacyManifestURL = claudeDirectory.appendingPathComponent(ClaudeHookInstallerManifest.legacyFileName)
        let manifest = try loadManifest(at: manifestURL)
        let existingSettings = try? Data(contentsOf: settingsURL)
        let mutation = try ClaudeHookInstaller.uninstallSettingsJSON(
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

        for candidate in [primaryManifestURL, legacyManifestURL] where fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }

        return try status()
    }

    private func loadManifest(at url: URL) throws -> ClaudeHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClaudeHookInstallerManifest.self, from: data)
    }

    private func resolvedManifestURL() -> URL {
        let primaryURL = claudeDirectory.appendingPathComponent(ClaudeHookInstallerManifest.fileName)
        if fileManager.fileExists(atPath: primaryURL.path) {
            return primaryURL
        }

        let legacyURL = claudeDirectory.appendingPathComponent(ClaudeHookInstallerManifest.legacyFileName)
        return fileManager.fileExists(atPath: legacyURL.path) ? legacyURL : primaryURL
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
