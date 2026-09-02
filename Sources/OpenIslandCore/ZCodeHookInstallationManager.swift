import Foundation

public struct ZCodeHookInstallationStatus: Equatable, Sendable {
    public var zcodeDirectory: URL
    public var configURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    /// Managed entries exist in `config.json` in any format (current
    /// `process`-type or legacy `command`-type).
    public var managedHooksPresent: Bool
    /// Managed entries exist in the current `process`-type format for every
    /// lifecycle event. `false` with `managedHooksPresent == true` means a
    /// legacy install that the manager should re-install (migrate).
    public var currentFormatHooksPresent: Bool
    public var manifest: ZCodeHookInstallerManifest?

    public init(
        zcodeDirectory: URL,
        configURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        currentFormatHooksPresent: Bool = false,
        manifest: ZCodeHookInstallerManifest?
    ) {
        self.zcodeDirectory = zcodeDirectory
        self.configURL = configURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.currentFormatHooksPresent = currentFormatHooksPresent
        self.manifest = manifest
    }
}

/// Installs Open Island's managed hooks into ZCode's `~/.zcode/cli/config.json`.
///
/// ZCode snapshots hook configuration when a session starts, so installs and
/// uninstalls only affect sessions launched afterwards. The manifest records
/// the prior `hooks.enabled` value so uninstall can faithfully restore the
/// user's pre-install state.
public final class ZCodeHookInstallationManager: @unchecked Sendable {
    public let zcodeDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        zcodeDirectory: URL = ZCodeHookInstallationManager.defaultDirectory(),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.zcodeDirectory = zcodeDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public static func defaultDirectory() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".zcode/cli")
    }

    public static var defaultConfigURL: URL {
        defaultDirectory().appendingPathComponent("config.json")
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> ZCodeHookInstallationStatus {
        let configURL = Self.defaultConfigURL(in: zcodeDirectory)
        let manifestURL = zcodeDirectory.appendingPathComponent(ZCodeHookInstallerManifest.fileName)
        let resolvedHooksBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)

        let configData = try? Data(contentsOf: configURL)
        let manifest = try loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand ?? resolvedHooksBinaryURL.map { ZCodeHookInstaller.processCommand(for: $0.path) }
        let uninstallMutation = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: configData,
            managedCommand: managedCommand,
            hooksEnabledBeforeInstall: manifest?.hooksEnabledBeforeInstall
        )
        // Format detection runs against the binary this machine would
        // install, not the manifest's recorded command: a legacy manifest
        // (quoted command-type string) must not mask a pending migration.
        let currentCommand = resolvedHooksBinaryURL.map { ZCodeHookInstaller.processCommand(for: $0.path) }

        return ZCodeHookInstallationStatus(
            zcodeDirectory: zcodeDirectory,
            configURL: configURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedHooksBinaryURL,
            managedHooksPresent: uninstallMutation.managedHooksPresent,
            currentFormatHooksPresent: currentCommand.map {
                ZCodeHookInstaller.containsCurrentFormatHooks(existingData: configData, hookCommand: $0)
            } ?? false,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> ZCodeHookInstallationStatus {
        try fileManager.createDirectory(at: zcodeDirectory, withIntermediateDirectories: true)

        let configURL = Self.defaultConfigURL(in: zcodeDirectory)
        let manifestURL = zcodeDirectory.appendingPathComponent(ZCodeHookInstallerManifest.fileName)
        let existingConfig = try? Data(contentsOf: configURL)
        let installedHooksBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = ZCodeHookInstaller.processCommand(for: installedHooksBinaryURL.path)
        let mutation = try ZCodeHookInstaller.installConfigJSON(
            existingData: existingConfig,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: configURL, options: .atomic)
        }

        let manifest = ZCodeHookInstallerManifest(
            hookCommand: command,
            hooksEnabledBeforeInstall: mutation.hooksEnabledBefore
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedHooksBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> ZCodeHookInstallationStatus {
        let configURL = Self.defaultConfigURL(in: zcodeDirectory)
        let manifestURL = zcodeDirectory.appendingPathComponent(ZCodeHookInstallerManifest.fileName)
        let manifest = try loadManifest(at: manifestURL)
        let existingConfig = try? Data(contentsOf: configURL)
        let mutation = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: existingConfig,
            managedCommand: manifest?.hookCommand,
            hooksEnabledBeforeInstall: manifest?.hooksEnabledBeforeInstall
        )

        if mutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: configURL, options: .atomic)
        } else if fileManager.fileExists(atPath: configURL.path) {
            // contents == nil means the config ended up empty — the whole
            // file only held Open Island's hooks, so remove it entirely.
            try fileManager.removeItem(at: configURL)
        }

        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        return try status()
    }

    private static func defaultConfigURL(in directory: URL) -> URL {
        directory.appendingPathComponent("config.json")
    }

    private func loadManifest(at url: URL) throws -> ZCodeHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

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
