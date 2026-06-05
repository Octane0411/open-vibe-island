import Foundation

public struct PiExtensionInstallationStatus: Equatable, Codable, Sendable {
    public var piConfigDirectory: URL
    public var extensionsDirectory: URL
    public var extensionFileURL: URL
    public var manifestURL: URL
    public var extensionFilePresent: Bool
    public var manifest: PiExtensionInstallerManifest?

    public var isInstalled: Bool {
        extensionFilePresent
    }

    public init(
        piConfigDirectory: URL,
        extensionsDirectory: URL,
        extensionFileURL: URL,
        manifestURL: URL,
        extensionFilePresent: Bool,
        manifest: PiExtensionInstallerManifest?
    ) {
        self.piConfigDirectory = piConfigDirectory
        self.extensionsDirectory = extensionsDirectory
        self.extensionFileURL = extensionFileURL
        self.manifestURL = manifestURL
        self.extensionFilePresent = extensionFilePresent
        self.manifest = manifest
    }
}

public struct PiExtensionInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-pi-extension-install.json"

    public var extensionPath: String
    public var installedAt: Date

    public init(extensionPath: String, installedAt: Date = .now) {
        self.extensionPath = extensionPath
        self.installedAt = installedAt
    }
}

public final class PiExtensionInstallationManager: @unchecked Sendable {
    public static let extensionFileName = "open-island.ts"

    public let piConfigDirectory: URL
    private let fileManager: FileManager

    public init(
        piConfigDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.piConfigDirectory = piConfigDirectory
        self.fileManager = fileManager
    }

    private var extensionsDirectory: URL {
        piConfigDirectory.appendingPathComponent("extensions", isDirectory: true)
    }

    private var extensionFileURL: URL {
        extensionsDirectory.appendingPathComponent(Self.extensionFileName)
    }

    private var manifestURL: URL {
        piConfigDirectory.appendingPathComponent(PiExtensionInstallerManifest.fileName)
    }

    public func status() throws -> PiExtensionInstallationStatus {
        PiExtensionInstallationStatus(
            piConfigDirectory: piConfigDirectory,
            extensionsDirectory: extensionsDirectory,
            extensionFileURL: extensionFileURL,
            manifestURL: manifestURL,
            extensionFilePresent: fileManager.fileExists(atPath: extensionFileURL.path),
            manifest: try loadManifest()
        )
    }

    @discardableResult
    public func install(extensionSourceData: Data) throws -> PiExtensionInstallationStatus {
        try fileManager.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: extensionFileURL.path) {
            try backupFile(at: extensionFileURL)
        }

        try extensionSourceData.write(to: extensionFileURL, options: .atomic)

        let manifest = PiExtensionInstallerManifest(extensionPath: extensionFileURL.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status()
    }

    @discardableResult
    public func uninstall() throws -> PiExtensionInstallationStatus {
        if fileManager.fileExists(atPath: extensionFileURL.path) {
            try fileManager.removeItem(at: extensionFileURL)
        }

        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        return try status()
    }

    private func loadManifest() throws -> PiExtensionInstallerManifest? {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PiExtensionInstallerManifest.self, from: data)
    }

    private func backupFile(at url: URL) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).backup.\(stamp)")
        try fileManager.copyItem(at: url, to: backupURL)
    }
}
