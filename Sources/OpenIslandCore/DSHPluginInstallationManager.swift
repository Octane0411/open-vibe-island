import CryptoKit
import Foundation

public struct DSHPluginInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-dsh-plugin-install.json"
    public static let currentVersion = 2

    public var version: Int
    public var pluginPath: String
    public var fileDigests: [String: String]
    public var createdDsh: Bool
    public var createdProfile: Bool
    public var createdBundles: Bool
}

public struct DSHPluginInstallationStatus: Equatable, Sendable {
    public var dshProfileDirectory: URL
    public var configURL: URL
    public var pluginsDirectory: URL
    public var pluginDirectory: URL
    public var pluginFileURL: URL
    public var clientFileURL: URL
    public var manifestURL: URL
    public var pluginFilePresent: Bool
    public var clientFilePresent: Bool
    public var pluginRegistered: Bool
    public var manifest: DSHPluginInstallerManifest?
    public var managedFilesIntact: Bool

    public var isInstalled: Bool {
        pluginFilePresent && pluginRegistered && managedFilesIntact && manifest != nil
    }

    public var isCurrent: Bool {
        isInstalled && clientFilePresent && manifest?.version == DSHPluginInstallerManifest.currentVersion
    }
}

public enum DSHPluginInstallationError: LocalizedError, Equatable {
    case profileNotInitialized(String)
    case invalidConfiguration
    case invalidSource
    case configurationChanged
    case unsafePath(String)
    case unownedInstallation(String)
    case modifiedInstallation(String)

    public var errorDescription: String? {
        switch self {
        case let .profileNotInitialized(path):
            "DSH profile is not initialized at \(path). Start DSH with this profile first."
        case .invalidConfiguration:
            "DSH package.json must contain an object with an optional dsh.profile.bundles string array."
        case .invalidSource:
            "The DSH host and client plugin sources must both be nonempty UTF-8 JavaScript."
        case .configurationChanged:
            "The DSH profile configuration changed during installation. Retry with the latest configuration."
        case let .unsafePath(path):
            "Refusing to use a symbolic link or unexpected file type at \(path)."
        case let .unownedInstallation(path):
            "Refusing to change an unowned DSH plugin installation at \(path)."
        case let .modifiedInstallation(path):
            "The managed DSH plugin was modified at \(path). Preserve or remove it manually before retrying."
        }
    }
}

/// Installs a local Cordis bundle into an existing DSH profile.
/// The profile manifest selects the bundle through dsh.profile.bundles.
/// User YAML patches and package dependencies are never changed.
public final class DSHPluginInstallationManager: @unchecked Sendable {
    public static let pluginFileName = "open-island-dsh.js"
    public static let clientFileName = "open-island-dsh-client.js"
    public static let bundleName = "open-island-dsh"
    public static var defaultProfileDirectory: URL {
        let home = ProcessInfo.processInfo.environment["DSH_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh", isDirectory: true)
        return home.appendingPathComponent("profiles/web", isDirectory: true)
    }

    public let dshProfileDirectory: URL
    private let fileManager: FileManager
    private static func managedFileNames(for version: Int) -> Set<String> {
        switch version {
        case 1: [pluginFileName, "package.json", "cordis.patch.yml"]
        case 2: [pluginFileName, clientFileName, "package.json", "cordis.patch.yml"]
        default: []
        }
    }

    private static var managedFileNames: Set<String> {
        managedFileNames(for: DSHPluginInstallerManifest.currentVersion)
    }

    public init(
        dshProfileDirectory: URL = DSHPluginInstallationManager.defaultProfileDirectory,
        fileManager: FileManager = .default
    ) {
        self.dshProfileDirectory = dshProfileDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    public var configURL: URL { dshProfileDirectory.appendingPathComponent("package.json") }
    public var pluginsDirectory: URL { dshProfileDirectory.appendingPathComponent("node_modules", isDirectory: true) }
    public var pluginDirectory: URL { pluginsDirectory.appendingPathComponent(Self.bundleName, isDirectory: true) }
    public var pluginFileURL: URL { pluginDirectory.appendingPathComponent(Self.pluginFileName) }
    public var clientFileURL: URL { pluginDirectory.appendingPathComponent(Self.clientFileName) }
    public var manifestURL: URL { dshProfileDirectory.appendingPathComponent(DSHPluginInstallerManifest.fileName) }

    public func status() throws -> DSHPluginInstallationStatus {
        try validatePaths()
        let config = try readConfiguration(required: false).object
        let manifest = try loadManifest()
        let intact = try manifest.map { try filesAreIntact($0) } ?? false
        return DSHPluginInstallationStatus(
            dshProfileDirectory: dshProfileDirectory,
            configURL: configURL,
            pluginsDirectory: pluginsDirectory,
            pluginDirectory: pluginDirectory,
            pluginFileURL: pluginFileURL,
            clientFileURL: clientFileURL,
            manifestURL: manifestURL,
            pluginFilePresent: exists(pluginFileURL),
            clientFilePresent: exists(clientFileURL),
            pluginRegistered: try bundles(in: config).contains(Self.bundleName),
            manifest: manifest,
            managedFilesIntact: intact
        )
    }

    @discardableResult
    public func install(pluginSourceData: Data, clientSourceData: Data) throws -> DSHPluginInstallationStatus {
        for data in [pluginSourceData, clientSourceData] {
            guard let source = String(data: data, encoding: .utf8),
                  !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DSHPluginInstallationError.invalidSource
            }
        }
        try validatePaths()
        let configuration = try readConfiguration(required: true)
        var config = configuration.object
        let existingManifest = try loadManifest()
        try requireOwnership(manifest: existingManifest, config: config)

        var dsh = config["dsh"] as? [String: Any] ?? [:]
        var profile = dsh["profile"] as? [String: Any] ?? [:]
        var selectedBundles = try bundles(in: config)
        let files = try bundleFiles(pluginSourceData: pluginSourceData, clientSourceData: clientSourceData)
        let manifest = DSHPluginInstallerManifest(
            version: DSHPluginInstallerManifest.currentVersion,
            pluginPath: pluginFileURL.path,
            fileDigests: files.mapValues(Self.digest),
            createdDsh: existingManifest?.createdDsh ?? (config["dsh"] == nil),
            createdProfile: existingManifest?.createdProfile ?? (dsh["profile"] == nil),
            createdBundles: existingManifest?.createdBundles ?? (profile["bundles"] == nil)
        )
        if !selectedBundles.contains(Self.bundleName) { selectedBundles.append(Self.bundleName) }
        profile["bundles"] = selectedBundles
        dsh["profile"] = profile
        config["dsh"] = dsh
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var replacements = files.keys.sorted().map { (pluginDirectory.appendingPathComponent($0), files[$0]) }
        replacements.append((manifestURL, try encoder.encode(manifest)))
        // Register last so a failed file write cannot activate an incomplete bundle.
        replacements.append((configURL, try encode(config)))
        try apply(replacements, expectedConfiguration: configuration.data)
        return try status()
    }

    @discardableResult
    public func uninstall() throws -> DSHPluginInstallationStatus {
        try validatePaths()
        let configuration = try readConfiguration(required: false)
        var config = configuration.object
        guard let manifest = try loadManifest() else {
            try requireOwnership(manifest: nil, config: config)
            return try status()
        }
        try requireOwnership(manifest: manifest, config: config)
        if var dsh = config["dsh"] as? [String: Any],
           var profile = dsh["profile"] as? [String: Any] {
            let remaining = try bundles(in: config).filter { $0 != Self.bundleName }
            if remaining.isEmpty && manifest.createdBundles {
                profile.removeValue(forKey: "bundles")
            } else if profile["bundles"] != nil {
                profile["bundles"] = remaining
            }
            if profile.isEmpty && manifest.createdProfile {
                dsh.removeValue(forKey: "profile")
            } else {
                dsh["profile"] = profile
            }
            if dsh.isEmpty && manifest.createdDsh {
                config.removeValue(forKey: "dsh")
            } else {
                config["dsh"] = dsh
            }
        }
        var replacements: [(URL, Data?)] = []
        // Unregister before removing the managed files.
        if exists(configURL) { replacements.append((configURL, try encode(config))) }
        replacements += manifest.fileDigests.keys.sorted().map { (pluginDirectory.appendingPathComponent($0), nil) }
        replacements.append((manifestURL, nil))
        try apply(replacements, expectedConfiguration: configuration.data)
        try removeDirectoryIfEmpty(pluginDirectory)
        return try status()
    }

    private func bundles(in config: [String: Any]) throws -> [String] {
        guard let rawDsh = config["dsh"] else { return [] }
        guard let dsh = rawDsh as? [String: Any] else { throw DSHPluginInstallationError.invalidConfiguration }
        guard let rawProfile = dsh["profile"] else { return [] }
        guard let profile = rawProfile as? [String: Any] else { throw DSHPluginInstallationError.invalidConfiguration }
        guard let rawBundles = profile["bundles"] else { return [] }
        guard let bundles = rawBundles as? [String] else { throw DSHPluginInstallationError.invalidConfiguration }
        return bundles
    }

    private func readConfiguration(required: Bool) throws -> (object: [String: Any], data: Data?) {
        guard exists(configURL) else {
            if required { throw DSHPluginInstallationError.profileNotInitialized(dshProfileDirectory.path) }
            return ([:], nil)
        }
        let data = try Data(contentsOf: configURL)
        let config: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw DSHPluginInstallationError.invalidConfiguration
            }
            config = object
        } catch is DecodingError {
            throw DSHPluginInstallationError.invalidConfiguration
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == 3840 {
            throw DSHPluginInstallationError.invalidConfiguration
        }
        _ = try bundles(in: config)
        return (config, data)
    }

    private func loadManifest() throws -> DSHPluginInstallerManifest? {
        guard exists(manifestURL) else { return nil }
        guard let manifest = try? JSONDecoder().decode(DSHPluginInstallerManifest.self, from: Data(contentsOf: manifestURL)),
              manifest.version > 0,
              manifest.version <= DSHPluginInstallerManifest.currentVersion,
              manifest.pluginPath == pluginFileURL.path,
              Set(manifest.fileDigests.keys) == Self.managedFileNames(for: manifest.version) else {
            throw DSHPluginInstallationError.unownedInstallation(manifestURL.path)
        }
        return manifest
    }

    private func requireOwnership(manifest: DSHPluginInstallerManifest?, config: [String: Any]) throws {
        guard let manifest else {
            guard !exists(pluginDirectory), !(try bundles(in: config)).contains(Self.bundleName) else {
                throw DSHPluginInstallationError.unownedInstallation(pluginDirectory.path)
            }
            return
        }
        // A removed bundle can be repaired, but never replace a changed or partially removed bundle.
        guard try !exists(pluginDirectory) || filesAreIntact(manifest) else {
            throw DSHPluginInstallationError.modifiedInstallation(pluginDirectory.path)
        }
    }

    private func filesAreIntact(_ manifest: DSHPluginInstallerManifest) throws -> Bool {
        guard exists(pluginDirectory) else { return false }
        let names = try fileManager.contentsOfDirectory(atPath: pluginDirectory.path)
        guard Set(names) == Self.managedFileNames(for: manifest.version) else { return false }
        for name in names {
            let url = pluginDirectory.appendingPathComponent(name)
            try validateType(url, directory: false)
            guard Self.digest(try Data(contentsOf: url)) == manifest.fileDigests[name] else { return false }
        }
        return true
    }

    private func bundleFiles(pluginSourceData: Data, clientSourceData: Data) throws -> [String: Data] {
        let package: [String: Any] = [
            "name": Self.bundleName,
            "version": "1.0.0",
            "private": true,
            "type": "module",
            "main": "./\(Self.pluginFileName)",
            "exports": [
                ".": "./\(Self.pluginFileName)",
                "./client": "./\(Self.clientFileName)",
                "./package.json": "./package.json",
            ],
            "dsh": [
                "bundle": ["patch": "./cordis.patch.yml"],
                "client": [
                    "platform": "web",
                    "inject": [
                        "@deepseek-ai/dsh-client-connection",
                        "@deepseek-ai/dsh-api-session-controller",
                        "@deepseek-ai/dsh-client-ui-workspace",
                        "@deepseek-ai/dsh-client-ui-conversation",
                    ],
                ],
            ],
            "engines": ["dsh": ">=0.2.1-rc.3 <0.3.0", "node": ">=22.19"],
        ]
        // JSON is a supported YAML subset and avoids quoting filesystem paths by hand.
        let patch: [[String: Any]] = [["insert": [[
            "id": "open-island",
            "name": pluginFileURL.absoluteString,
        ]]]]
        return [
            Self.pluginFileName: pluginSourceData,
            Self.clientFileName: clientSourceData,
            "package.json": try encode(package),
            "cordis.patch.yml": try JSONSerialization.data(withJSONObject: patch, options: [.prettyPrinted, .sortedKeys]),
        ]
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func encode(_ config: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
    }

    private func exists(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    private func validateType(_ url: URL, directory: Bool) throws {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return }
        let expected: FileAttributeType = directory ? .typeDirectory : .typeRegular
        guard attributes[.type] as? FileAttributeType == expected else {
            throw DSHPluginInstallationError.unsafePath(url.path)
        }
    }

    private func validatePaths() throws {
        // macOS standardizes /private/var back to /var, including temporary URLs.
        // Permit only the fixed OS aliases, never a link in the user's managed tree.
        var ancestor = dshProfileDirectory
        while ancestor.path != "/" {
            let linkTarget = try? fileManager.destinationOfSymbolicLink(atPath: ancestor.path)
            let isSystemAlias = ["/var", "/tmp", "/etc"].contains(ancestor.path)
                && (linkTarget == "private\(ancestor.path)" || linkTarget == "/private\(ancestor.path)")
            if !isSystemAlias { try validateType(ancestor, directory: true) }
            ancestor = ancestor.deletingLastPathComponent()
        }
        try validateType(configURL, directory: false)
        try validateType(pluginsDirectory, directory: true)
        try validateType(pluginDirectory, directory: true)
        try validateType(manifestURL, directory: false)
        for name in Self.managedFileNames {
            try validateType(pluginDirectory.appendingPathComponent(name), directory: false)
        }
    }

    private func apply(_ replacements: [(URL, Data?)], expectedConfiguration: Data?) throws {
        try requireUnchangedConfiguration(expectedConfiguration)
        let originals = try replacements.map { (url, _) in
            (url, exists(url) ? try Data(contentsOf: url) : nil)
        }
        let hadPluginDirectory = exists(pluginDirectory)
        let hadPluginsDirectory = exists(pluginsDirectory)
        var completedCount = 0
        do {
            if replacements.contains(where: { $0.0.deletingLastPathComponent() == pluginDirectory && $0.1 != nil }) {
                try fileManager.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
            }
            for (url, data) in replacements {
                if url == configURL { try requireUnchangedConfiguration(expectedConfiguration) }
                if let data { try data.write(to: url, options: .atomic) }
                else if exists(url) { try fileManager.removeItem(at: url) }
                completedCount += 1
            }
        } catch {
            // Restore only files we changed, never an untouched concurrent config edit.
            for (url, data) in originals.prefix(completedCount).reversed() {
                if let data { try? data.write(to: url, options: .atomic) }
                else if exists(url) { try? fileManager.removeItem(at: url) }
            }
            if !hadPluginDirectory { try? removeDirectoryIfEmpty(pluginDirectory) }
            if !hadPluginsDirectory { try? removeDirectoryIfEmpty(pluginsDirectory) }
            throw error
        }
    }

    private func requireUnchangedConfiguration(_ expected: Data?) throws {
        try validatePaths()
        let current = exists(configURL) ? try Data(contentsOf: configURL) : nil
        guard current == expected else { throw DSHPluginInstallationError.configurationChanged }
    }

    private func removeDirectoryIfEmpty(_ url: URL) throws {
        if exists(url), try fileManager.contentsOfDirectory(atPath: url.path).isEmpty {
            try fileManager.removeItem(at: url)
        }
    }
}
