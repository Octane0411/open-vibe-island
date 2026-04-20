import Foundation

public struct CursorHookInstallationStatus: Equatable, Sendable {
    public var cursorDirectory: URL
    public var hooksURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: CursorHookInstallerManifest?

    public init(
        cursorDirectory: URL,
        hooksURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: CursorHookInstallerManifest?
    ) {
        self.cursorDirectory = cursorDirectory
        self.hooksURL = hooksURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
    }
}

public final class CursorHookInstallationManager: @unchecked Sendable {
    public let cursorDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        cursorDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.cursorDirectory = cursorDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> CursorHookInstallationStatus {
        let hooksURL = cursorDirectory.appendingPathComponent("hooks.json")
        let manifestURL = cursorDirectory.appendingPathComponent(CursorHookInstallerManifest.fileName)
        let resolvedBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)

        let hooksData = try? Data(contentsOf: hooksURL)
        let manifest = try loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand ?? resolvedBinaryURL.map { CursorHookInstaller.hookCommand(for: $0.path) }
        let uninstallMutation = try CursorHookInstaller.uninstallHooksJSON(
            existingData: hooksData,
            managedCommand: managedCommand
        )

        return CursorHookInstallationStatus(
            cursorDirectory: cursorDirectory,
            hooksURL: hooksURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedBinaryURL,
            managedHooksPresent: uninstallMutation.managedHooksPresent,
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> CursorHookInstallationStatus {
        try fileManager.createDirectory(at: cursorDirectory, withIntermediateDirectories: true)

        let hooksURL = cursorDirectory.appendingPathComponent("hooks.json")
        let manifestURL = cursorDirectory.appendingPathComponent(CursorHookInstallerManifest.fileName)
        let existingHooks = try? Data(contentsOf: hooksURL)
        let installedBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = CursorHookInstaller.hookCommand(for: installedBinaryURL.path)
        let mutation = try CursorHookInstaller.installHooksJSON(
            existingData: existingHooks,
            hookCommand: command
        )

        if mutation.changed, fileManager.fileExists(atPath: hooksURL.path) {
            try backupFile(at: hooksURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: hooksURL, options: .atomic)
        }

        let manifest = CursorHookInstallerManifest(hookCommand: command)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> CursorHookInstallationStatus {
        let hooksURL = cursorDirectory.appendingPathComponent("hooks.json")
        let manifestURL = cursorDirectory.appendingPathComponent(CursorHookInstallerManifest.fileName)
        let manifest = try loadManifest(at: manifestURL)
        let existingHooks = try? Data(contentsOf: hooksURL)
        let mutation = try CursorHookInstaller.uninstallHooksJSON(
            existingData: existingHooks,
            managedCommand: manifest?.hookCommand
        )

        if mutation.changed, fileManager.fileExists(atPath: hooksURL.path) {
            try backupFile(at: hooksURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: hooksURL, options: .atomic)
        } else if fileManager.fileExists(atPath: hooksURL.path) {
            try fileManager.removeItem(at: hooksURL)
        }

        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        return try status()
    }

    private func loadManifest(at url: URL) throws -> CursorHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CursorHookInstallerManifest.self, from: data)
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
