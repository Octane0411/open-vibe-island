import CryptoKit
import Foundation

public struct DSHPluginInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-dsh-plugin-install.json"
    public static let currentVersion = 3

    public var version: Int
    public var pluginPath: String
    public var fileDigests: [String: String]
    public var createdDsh: Bool
    public var createdProfile: Bool
    public var createdBundles: Bool
    public var dependencySpecifier: String? = nil
    public var linkPath: String? = nil
    public var linkTarget: String? = nil
    public var createdDependencies: Bool? = nil
    public var createdPluginsDirectory: Bool? = nil
    public var createdNodeModulesDirectory: Bool? = nil
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
    public var dependencyRegistered: Bool = false
    public var managedLinkPresent: Bool = false

    public var isInstalled: Bool {
        pluginFilePresent && pluginRegistered && managedFilesIntact && manifest != nil
    }

    public var isCurrent: Bool {
        isInstalled && clientFilePresent && dependencyRegistered && managedLinkPresent
            && manifest?.dependencySpecifier != nil && manifest?.version == DSHPluginInstallerManifest.currentVersion
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
/// User YAML patches and unrelated dependencies are never changed.
/// The owned local link dependency keeps package-manager pruning away from the source.
public final class DSHPluginInstallationManager: @unchecked Sendable {
    public static let pluginFileName = "open-island-dsh.js"
    public static let clientFileName = "open-island-dsh-client.js"
    public static let bundleName = "open-island-dsh"
    public static let dependencySpecifier = "link:./open-island-plugins/open-island-dsh"
    public static var defaultProfileDirectory: URL {
        let home = ProcessInfo.processInfo.environment["DSH_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh", isDirectory: true)
        return home.appendingPathComponent("profiles/web", isDirectory: true)
    }

    public let dshProfileDirectory: URL
    private let fileManager: FileManager
    private enum Mutation {
        case file(URL, Data?)
        case directory(URL, present: Bool)
        case link(URL, target: String?)
        case prune(URL)

        var url: URL {
            switch self {
            case let .file(url, _), let .directory(url, _), let .link(url, _), let .prune(url): url
            }
        }
    }

    private enum Entry {
        case missing
        case file(Data)
        case directory(NSNumber?)
        case link(String)
    }
    private static func managedFileNames(for version: Int) -> Set<String> {
        switch version {
        case 1: [pluginFileName, "package.json", "cordis.patch.yml"]
        case 2, 3: [pluginFileName, clientFileName, "package.json", "cordis.patch.yml"]
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
    public var pluginsDirectory: URL { dshProfileDirectory.appendingPathComponent("open-island-plugins", isDirectory: true) }
    public var nodeModulesDirectory: URL { dshProfileDirectory.appendingPathComponent("node_modules", isDirectory: true) }
    public var linkedPluginURL: URL { nodeModulesDirectory.appendingPathComponent(Self.bundleName, isDirectory: true) }
    private var legacyPluginFileURL: URL { linkedPluginURL.appendingPathComponent(Self.pluginFileName) }
    public var pluginDirectory: URL { pluginsDirectory.appendingPathComponent(Self.bundleName, isDirectory: true) }
    public var pluginFileURL: URL { pluginDirectory.appendingPathComponent(Self.pluginFileName) }
    public var clientFileURL: URL { pluginDirectory.appendingPathComponent(Self.clientFileName) }
    public var manifestURL: URL { dshProfileDirectory.appendingPathComponent(DSHPluginInstallerManifest.fileName) }

    public func status() throws -> DSHPluginInstallationStatus {
        try validatePaths()
        let config = try readConfiguration(required: false).object
        let manifest = try loadManifest()
        let intact = try manifest.map { try filesAreIntact($0) } ?? false
        let installedDirectory = manifest.map(installationDirectory) ?? pluginDirectory
        return DSHPluginInstallationStatus(
            dshProfileDirectory: dshProfileDirectory,
            configURL: configURL,
            pluginsDirectory: pluginsDirectory,
            pluginDirectory: installedDirectory,
            pluginFileURL: installedDirectory.appendingPathComponent(Self.pluginFileName),
            clientFileURL: installedDirectory.appendingPathComponent(Self.clientFileName),
            manifestURL: manifestURL,
            pluginFilePresent: exists(installedDirectory.appendingPathComponent(Self.pluginFileName)),
            clientFilePresent: exists(installedDirectory.appendingPathComponent(Self.clientFileName)),
            pluginRegistered: try bundles(in: config).contains(Self.bundleName),
            manifest: manifest,
            managedFilesIntact: intact,
            dependencyRegistered: try dependencies(in: config)[Self.bundleName] as? String == Self.dependencySpecifier,
            managedLinkPresent: try isManagedLink()
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
            createdBundles: existingManifest?.createdBundles ?? (profile["bundles"] == nil),
            dependencySpecifier: Self.dependencySpecifier,
            linkPath: linkedPluginURL.path,
            linkTarget: pluginDirectory.path,
            createdDependencies: existingManifest?.createdDependencies ?? (config["dependencies"] == nil),
            createdPluginsDirectory: existingManifest?.createdPluginsDirectory ?? !exists(pluginsDirectory),
            createdNodeModulesDirectory: existingManifest?.createdNodeModulesDirectory ?? !exists(nodeModulesDirectory)
        )
        if !selectedBundles.contains(Self.bundleName) { selectedBundles.append(Self.bundleName) }
        profile["bundles"] = selectedBundles
        dsh["profile"] = profile
        config["dsh"] = dsh
        var dependencies = try dependencies(in: config)
        dependencies[Self.bundleName] = Self.dependencySpecifier
        config["dependencies"] = dependencies
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var mutations: [Mutation] = []
        for directory in [pluginsDirectory, pluginDirectory, nodeModulesDirectory] where !exists(directory) {
            mutations.append(.directory(directory, present: true))
        }
        mutations += files.keys.sorted().map { .file(pluginDirectory.appendingPathComponent($0), files[$0]) }
        if let old = existingManifest, old.dependencySpecifier == nil, exists(linkedPluginURL) {
            mutations += old.fileDigests.keys.sorted().map { .file(linkedPluginURL.appendingPathComponent($0), nil) }
            mutations.append(.directory(linkedPluginURL, present: false))
        }
        if try !isManagedLink() {
            mutations.append(.link(linkedPluginURL, target: "../open-island-plugins/open-island-dsh"))
        }
        mutations.append(.file(manifestURL, try encoder.encode(manifest)))
        // Register last so a failed filesystem migration cannot activate an incomplete bundle.
        mutations.append(.file(configURL, try encode(config)))
        try apply(mutations, expectedConfiguration: configuration.data)
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
        if manifest.dependencySpecifier != nil {
            var dependencies = try dependencies(in: config)
            dependencies.removeValue(forKey: Self.bundleName)
            if dependencies.isEmpty, manifest.createdDependencies == true {
                config.removeValue(forKey: "dependencies")
            } else if config["dependencies"] != nil {
                config["dependencies"] = dependencies
            }
        }
        var mutations: [Mutation] = []
        // Unregister before removing the owned link and source files.
        if exists(configURL) { mutations.append(.file(configURL, try encode(config))) }
        if manifest.dependencySpecifier != nil, exists(linkedPluginURL) {
            mutations.append(.link(linkedPluginURL, target: nil))
        }
        let directory = installationDirectory(manifest)
        mutations += manifest.fileDigests.keys.sorted().map { .file(directory.appendingPathComponent($0), nil) }
        if exists(directory) { mutations.append(.directory(directory, present: false)) }
        mutations.append(.file(manifestURL, nil))
        if manifest.createdPluginsDirectory == true { mutations.append(.prune(pluginsDirectory)) }
        if manifest.createdNodeModulesDirectory == true { mutations.append(.prune(nodeModulesDirectory)) }
        try apply(mutations, expectedConfiguration: configuration.data)
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
        _ = try dependencies(in: config)
        return (config, data)
    }

    private func dependencies(in config: [String: Any]) throws -> [String: Any] {
        guard let raw = config["dependencies"] else { return [:] }
        guard let dependencies = raw as? [String: Any] else { throw DSHPluginInstallationError.invalidConfiguration }
        return dependencies
    }

    private func installationDirectory(_ manifest: DSHPluginInstallerManifest) -> URL {
        manifest.pluginPath == legacyPluginFileURL.path ? linkedPluginURL : pluginDirectory
    }

    private func loadManifest() throws -> DSHPluginInstallerManifest? {
        guard exists(manifestURL) else { return nil }
        guard let manifest = try? JSONDecoder().decode(DSHPluginInstallerManifest.self, from: Data(contentsOf: manifestURL)),
              manifest.version > 0, manifest.version <= DSHPluginInstallerManifest.currentVersion,
              Set(manifest.fileDigests.keys) == Self.managedFileNames(for: manifest.version) else {
            throw DSHPluginInstallationError.unownedInstallation(manifestURL.path)
        }
        if manifest.pluginPath == legacyPluginFileURL.path {
            guard manifest.dependencySpecifier == nil, manifest.linkPath == nil, manifest.linkTarget == nil,
                  manifest.createdDependencies == nil, manifest.createdPluginsDirectory == nil,
                  manifest.createdNodeModulesDirectory == nil else {
                throw DSHPluginInstallationError.unownedInstallation(manifestURL.path)
            }
        } else {
            guard manifest.pluginPath == pluginFileURL.path, manifest.version == 3,
                  manifest.dependencySpecifier == Self.dependencySpecifier,
                  manifest.linkPath == linkedPluginURL.path, manifest.linkTarget == pluginDirectory.path,
                  manifest.createdDependencies != nil, manifest.createdPluginsDirectory != nil,
                  manifest.createdNodeModulesDirectory != nil else {
                throw DSHPluginInstallationError.unownedInstallation(manifestURL.path)
            }
        }
        return manifest
    }

    private func isManagedLink() throws -> Bool {
        guard fileType(linkedPluginURL) == .typeSymbolicLink else { return false }
        let target = try fileManager.destinationOfSymbolicLink(atPath: linkedPluginURL.path)
        // Do not normalize arbitrary symlink traversal through foreign path components.
        return target == pluginDirectory.path || target == "../open-island-plugins/open-island-dsh"
    }

    private func requireOwnership(manifest: DSHPluginInstallerManifest?, config: [String: Any]) throws {
        let dependency = try dependencies(in: config)[Self.bundleName]
        for section in ["devDependencies", "optionalDependencies", "peerDependencies"] {
            if (config[section] as? [String: Any])?[Self.bundleName] != nil {
                throw DSHPluginInstallationError.unownedInstallation(configURL.path)
            }
        }
        guard let manifest else {
            guard !exists(pluginDirectory), !exists(linkedPluginURL), dependency == nil,
                  !(try bundles(in: config)).contains(Self.bundleName) else {
                throw DSHPluginInstallationError.unownedInstallation(pluginDirectory.path)
            }
            return
        }
        let directory = installationDirectory(manifest)
        // Entirely removed owned packages may be repaired. Partial or edited packages may not.
        guard try !exists(directory) || filesAreIntact(manifest) else {
            throw DSHPluginInstallationError.modifiedInstallation(directory.path)
        }
        if manifest.dependencySpecifier != nil {
            guard dependency == nil || dependency as? String == Self.dependencySpecifier else {
                throw DSHPluginInstallationError.unownedInstallation(configURL.path)
            }
            guard try !exists(linkedPluginURL) || isManagedLink() else {
                throw DSHPluginInstallationError.unownedInstallation(linkedPluginURL.path)
            }
        } else {
            guard dependency == nil, !exists(pluginDirectory) else {
                throw DSHPluginInstallationError.unownedInstallation(pluginDirectory.path)
            }
        }
    }

    private func filesAreIntact(_ manifest: DSHPluginInstallerManifest) throws -> Bool {
        let directory = installationDirectory(manifest)
        guard fileType(directory) == .typeDirectory else { return false }
        let names = try fileManager.contentsOfDirectory(atPath: directory.path)
        guard Set(names) == Self.managedFileNames(for: manifest.version) else { return false }
        for name in names {
            let url = directory.appendingPathComponent(name)
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

    private func fileType(_ url: URL) -> FileAttributeType? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType
    }

    private func exists(_ url: URL) -> Bool { fileType(url) != nil }

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
        try validateType(nodeModulesDirectory, directory: true)
        try validateType(manifestURL, directory: false)
        if let type = fileType(linkedPluginURL) {
            guard type == .typeDirectory || type == .typeSymbolicLink else {
                throw DSHPluginInstallationError.unsafePath(linkedPluginURL.path)
            }
            if type == .typeSymbolicLink, try !isManagedLink() {
                throw DSHPluginInstallationError.unsafePath(linkedPluginURL.path)
            }
        }
        for name in Self.managedFileNames {
            try validateType(pluginDirectory.appendingPathComponent(name), directory: false)
            if fileType(linkedPluginURL) == .typeDirectory {
                try validateType(linkedPluginURL.appendingPathComponent(name), directory: false)
            }
        }
    }

    private func entry(at url: URL) throws -> Entry {
        switch fileType(url) {
        case nil: return .missing
        case .typeRegular: return .file(try Data(contentsOf: url))
        case .typeSymbolicLink: return .link(try fileManager.destinationOfSymbolicLink(atPath: url.path))
        case .typeDirectory:
            return .directory(try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        default: throw DSHPluginInstallationError.unsafePath(url.path)
        }
    }

    private func perform(_ mutation: Mutation) throws {
        let url = mutation.url
        switch mutation {
        case let .file(_, data):
            try validateType(url, directory: false)
            if let data { try data.write(to: url, options: .atomic) }
            else if exists(url) { try fileManager.removeItem(at: url) }
        case let .directory(_, present):
            try validateType(url, directory: true)
            if present {
                if !exists(url) { try fileManager.createDirectory(at: url, withIntermediateDirectories: false) }
            } else if exists(url) {
                guard try fileManager.contentsOfDirectory(atPath: url.path).isEmpty else {
                    throw DSHPluginInstallationError.modifiedInstallation(url.path)
                }
                try fileManager.removeItem(at: url)
            }
        case let .link(_, target):
            if let target {
                guard !exists(url) else { throw DSHPluginInstallationError.unownedInstallation(url.path) }
                try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: target)
            } else if exists(url) {
                guard try isManagedLink() else { throw DSHPluginInstallationError.unsafePath(url.path) }
                try fileManager.removeItem(at: url)
            }
        case .prune:
            try removeDirectoryIfEmpty(url)
        }
    }

    private func restore(_ original: Entry, at url: URL) throws {
        switch original {
        case .missing:
            if fileType(url) == .typeDirectory { try removeDirectoryIfEmpty(url) }
            else if exists(url) { try fileManager.removeItem(at: url) }
        case let .file(data):
            try validateType(url, directory: false)
            try data.write(to: url, options: .atomic)
        case let .link(target):
            if fileType(url) == .typeSymbolicLink {
                let current = try fileManager.destinationOfSymbolicLink(atPath: url.path)
                if current == target { return }
                try fileManager.removeItem(at: url)
            }
            guard !exists(url) else { throw DSHPluginInstallationError.unsafePath(url.path) }
            try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: target)
        case let .directory(permissions):
            if fileType(url) == .typeSymbolicLink { try fileManager.removeItem(at: url) }
            try validateType(url, directory: true)
            if !exists(url) {
                let attributes = permissions.map { [FileAttributeKey.posixPermissions: $0] }
                try fileManager.createDirectory(at: url, withIntermediateDirectories: false, attributes: attributes)
            }
        }
    }

    private func apply(_ mutations: [Mutation], expectedConfiguration: Data?) throws {
        try requireUnchangedConfiguration(expectedConfiguration)
        let originals = try mutations.map { try entry(at: $0.url) }
        var attempted = 0
        var writtenConfiguration: Data?
        do {
            for mutation in mutations {
                try validatePaths()
                if mutation.url == configURL { try requireUnchangedConfiguration(expectedConfiguration) }
                attempted += 1
                try perform(mutation)
                if case let .file(url, data) = mutation, url == configURL { writtenConfiguration = data }
            }
        } catch {
            // Undo only attempted mutations. A concurrent config edit is never restored over.
            for index in (0..<attempted).reversed() {
                let url = mutations[index].url
                if url == configURL, let writtenConfiguration,
                   (try? Data(contentsOf: configURL)) != writtenConfiguration { continue }
                try? restore(originals[index], at: url)
            }
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
