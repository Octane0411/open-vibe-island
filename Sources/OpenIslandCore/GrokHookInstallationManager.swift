import Foundation

public struct GrokHookInstallationStatus: Equatable, Sendable {
    public var grokDirectory: URL
    public var hooksDirectory: URL
    public var hooksURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: GrokHookInstallerManifest?

    public init(
        grokDirectory: URL,
        hooksDirectory: URL,
        hooksURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: GrokHookInstallerManifest?
    ) {
        self.grokDirectory = grokDirectory
        self.hooksDirectory = hooksDirectory
        self.hooksURL = hooksURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
    }
}

public final class GrokHookInstallationManager: @unchecked Sendable {
    public let grokDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        grokDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.grokDirectory = grokDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public var hooksDirectory: URL {
        grokDirectory.appendingPathComponent("hooks", isDirectory: true)
    }

    public var hooksURL: URL {
        hooksDirectory.appendingPathComponent(GrokHookInstaller.managedHooksFileName)
    }

    public var manifestURL: URL {
        grokDirectory.appendingPathComponent(GrokHookInstallerManifest.fileName)
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> GrokHookInstallationStatus {
        let resolvedBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)
        let hooksData = try? Data(contentsOf: hooksURL)
        // Corrupt/partial manifests must not block status reads — treat as absent.
        let manifest = loadManifest(at: manifestURL)
        let managedCommand = manifest?.hookCommand
            ?? resolvedBinaryURL.map { GrokHookInstaller.hookCommand(for: $0.path) }

        return GrokHookInstallationStatus(
            grokDirectory: grokDirectory,
            hooksDirectory: hooksDirectory,
            hooksURL: hooksURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedBinaryURL,
            managedHooksPresent: GrokHookInstaller.managedHooksPresent(
                in: hooksData,
                managedCommand: managedCommand
            ),
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> GrokHookInstallationStatus {
        try fileManager.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)

        let installedBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let command = GrokHookInstaller.hookCommand(for: installedBinaryURL.path)
        let existingData = try? Data(contentsOf: hooksURL)
        let mutation = try GrokHookInstaller.installHooksJSON(
            existingData: existingData,
            hookCommand: command
        )

        if mutation.changed {
            if fileManager.fileExists(atPath: hooksURL.path) {
                try backupFile(at: hooksURL)
            }
            if let contents = mutation.contents {
                try contents.write(to: hooksURL, options: .atomic)
            }
        }

        // Rewrite manifest whenever the command changes or the previous
        // file was missing/corrupt (loadManifest returns nil in both cases).
        let previousManifest = loadManifest(at: manifestURL)
        if previousManifest?.hookCommand != command {
            let manifest = GrokHookInstallerManifest(hookCommand: command)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        }

        return try status(hooksBinaryURL: installedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> GrokHookInstallationStatus {
        if fileManager.fileExists(atPath: hooksURL.path) {
            let existingData = try? Data(contentsOf: hooksURL)
            guard GrokHookInstaller.isOpenIslandOwnedManagedFile(existingData) else {
                throw GrokHookInstallerError.managedFileNotOwnedByOpenIsland
            }
            try backupFile(at: hooksURL)
            try fileManager.removeItem(at: hooksURL)
        }

        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        return try status()
    }

    /// Returns nil when the file is missing or unreadable/corrupt so status
    /// and reinstall can still proceed.
    private func loadManifest(at url: URL) -> GrokHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GrokHookInstallerManifest.self, from: data)
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
