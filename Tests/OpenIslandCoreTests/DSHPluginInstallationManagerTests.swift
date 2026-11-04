import CryptoKit
import Foundation
import Testing
@testable import OpenIslandCore

private final class ConfigEditingFileManager: FileManager, @unchecked Sendable {
    var onCreateDirectory: (() throws -> Void)?

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
        let edit = onCreateDirectory
        onCreateDirectory = nil
        try edit?()
    }
}

private final class LinkEditingFileManager: FileManager, @unchecked Sendable {
    var onCreateLink: (() throws -> Void)?
    var failRemoving: URL?

    override func createSymbolicLink(atPath path: String, withDestinationPath destination: String) throws {
        try super.createSymbolicLink(atPath: path, withDestinationPath: destination)
        let callback = onCreateLink
        onCreateLink = nil
        try callback?()
    }

    override func removeItem(at url: URL) throws {
        if failRemoving == url {
            failRemoving = nil
            throw CocoaError(.fileWriteUnknown)
        }
        try super.removeItem(at: url)
    }
}

struct DSHPluginInstallationManagerTests {
    private let source = Data("export function apply(ctx) {}\n".utf8)
    private let clientSource = Data("window.__ModuleLoader__.load({ id: 'open-island-dsh', factory: () => ({ apply() {} }) })\n".utf8)

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("dsh-installer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeConfig(_ object: Any, to directory: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
            .write(to: directory.appendingPathComponent("package.json"))
    }

    private func config(at directory: URL) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("package.json"))) as? NSDictionary)
    }

    private func legacyInstallation(in directory: URL, version: Int = 1) throws -> DSHPluginInstallationManager {
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
        var original = try #require(try config(at: directory) as? [String: Any])
        var dsh = original["dsh"] as? [String: Any] ?? [:]
        var profile = dsh["profile"] as? [String: Any] ?? [:]
        var bundles = profile["bundles"] as? [String] ?? []
        let createdDsh = original["dsh"] == nil
        let createdProfile = dsh["profile"] == nil
        let createdBundles = profile["bundles"] == nil
        bundles.append("open-island-dsh")
        profile["bundles"] = bundles
        dsh["profile"] = profile
        original["dsh"] = dsh
        try writeConfig(original, to: directory)
        let package: [String: Any] = [
            "name": "open-island-dsh", "version": "1.0.0", "private": true, "type": "module",
            "main": "./open-island-dsh.js", "exports": [".": "./open-island-dsh.js"],
            "dsh": ["bundle": ["patch": "./cordis.patch.yml"]],
            "engines": ["dsh": ">=0.2.1-rc.3 <0.3.0", "node": ">=22.19"],
        ]
        let legacyHost = manager.linkedPluginURL.appendingPathComponent(DSHPluginInstallationManager.pluginFileName)
        let patch = [["insert": [["id": "open-island", "name": legacyHost.absoluteString]]]]
        var files = [
            "open-island-dsh.js": source,
            "package.json": try JSONSerialization.data(withJSONObject: package, options: [.prettyPrinted, .sortedKeys]),
            "cordis.patch.yml": try JSONSerialization.data(withJSONObject: patch, options: [.prettyPrinted, .sortedKeys]),
        ]
        if version >= 2 { files[DSHPluginInstallationManager.clientFileName] = clientSource }
        try FileManager.default.createDirectory(at: manager.linkedPluginURL, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: manager.linkedPluginURL.appendingPathComponent(name)) }
        let manifest = DSHPluginInstallerManifest(
            version: version,
            pluginPath: legacyHost.path,
            fileDigests: files.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() },
            createdDsh: createdDsh,
            createdProfile: createdProfile,
            createdBundles: createdBundles
        )
        try JSONEncoder().encode(manifest).write(to: manager.manifestURL)
        return manager
    }

    private func snapshot(_ manager: DSHPluginInstallationManager) throws -> [String: Data] {
        var files: [String: Data] = [
            "profile": try Data(contentsOf: manager.configURL),
            "manifest": try Data(contentsOf: manager.manifestURL),
        ]
        let manifest = try JSONDecoder().decode(DSHPluginInstallerManifest.self, from: files["manifest"]!)
        let installedDirectory = URL(fileURLWithPath: manifest.pluginPath).deletingLastPathComponent()
        for name in try FileManager.default.contentsOfDirectory(atPath: installedDirectory.path) {
            files[name] = try Data(contentsOf: installedDirectory.appendingPathComponent(name))
        }
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: manager.linkedPluginURL.path) {
            files["link-target"] = Data(target.utf8)
        }
        return files
    }

    @Test(arguments: [true, false], [true, false])
    func legacyInstallCanUpgradeOrUninstallWithoutLosingProfileData(upgrade: Bool, existingContainers: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var original: [String: Any] = ["private": true, "dependencies": ["other": "1.2.3"]]
        if existingContainers {
            original["dsh"] = ["profile": ["bundles": [], "custom": "keep"], "custom": true]
        }
        try writeConfig(original, to: directory)
        let manager = try legacyInstallation(in: directory)
        let legacy = try manager.status()
        #expect(legacy.isInstalled)
        #expect(!legacy.isCurrent)
        #expect(!legacy.clientFilePresent)
        if upgrade {
            let upgraded = try manager.install(pluginSourceData: source, clientSourceData: clientSource)
            #expect(upgraded.isCurrent)
            #expect(upgraded.manifest?.createdDsh == legacy.manifest?.createdDsh)
            #expect(upgraded.manifest?.createdProfile == legacy.manifest?.createdProfile)
            #expect(upgraded.manifest?.createdBundles == legacy.manifest?.createdBundles)
            #expect(try Data(contentsOf: manager.clientFileURL) == clientSource)
            let installed = try config(at: directory)
            let dsh = try #require(installed["dsh"] as? NSDictionary)
            let profile = try #require(dsh["profile"] as? NSDictionary)
            #expect(profile["bundles"] as? [String] == ["open-island-dsh"])
        }
        try manager.uninstall()
        #expect(try config(at: directory) == original as NSDictionary)
        #expect(!FileManager.default.fileExists(atPath: manager.pluginDirectory.path))
    }

    @Test(arguments: ["client", "host", "manifest"])
    func legacyUpgradeRefusesUnownedClientOrChangedOwnership(kind: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true], to: directory)
        let manager = try legacyInstallation(in: directory)
        switch kind {
        case "client": try Data("unowned client".utf8).write(to: manager.linkedPluginURL.appendingPathComponent(DSHPluginInstallationManager.clientFileName))
        case "host": try Data("changed host".utf8).write(to: manager.linkedPluginURL.appendingPathComponent(DSHPluginInstallationManager.pluginFileName))
        default:
            var manifest = try #require(manager.status().manifest)
            manifest.fileDigests["unexpected.js"] = "unowned"
            try JSONEncoder().encode(manifest).write(to: manager.manifestURL)
        }
        let before = try snapshot(manager)
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source, clientSourceData: clientSource) }
        #expect(throws: DSHPluginInstallationError.self) { try manager.uninstall() }
        #expect(try snapshot(manager) == before)
    }

    @Test
    func failedLegacyUpgradeRestoresThreeFileOwnershipAndRemovesNewClient() throws {
        guard getuid() != 0 else { return }
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try writeConfig(["private": true], to: directory)
        let manager = try legacyInstallation(in: directory)
        let before = try snapshot(manager)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        #expect(throws: (any Error).self) {
            try manager.install(pluginSourceData: Data("changed host".utf8), clientSourceData: clientSource)
        }
        #expect(try snapshot(manager) == before)
        #expect(!FileManager.default.fileExists(atPath: manager.clientFileURL.path))
        #expect(try manager.status().isInstalled)
        #expect(try !manager.status().isCurrent)
    }

    @Test
    func lifecyclePreservesProfileConfigurationAndUserYaml() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original: [String: Any] = [
            "name": "my-dsh-profile",
            "dependencies": ["other-plugin": "file:../other"],
            "custom": ["enabled": true, "limit": 7],
            "dsh": ["profile": ["bundles": ["@deepseek-ai/dsh-base", "@other/open-island-dsh"], "custom": "keep"], "custom": false],
        ]
        try writeConfig(original, to: directory)
        let yaml = Data("# Keep formatting, expressions, and unrelated plugins\n- id: other\n  disabled: !!js false\n".utf8)
        let patchURL = directory.appendingPathComponent("cordis.patch.yml")
        try yaml.write(to: patchURL)
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)

        #expect(try manager.install(pluginSourceData: source, clientSourceData: clientSource).isCurrent)
        #expect(try manager.install(pluginSourceData: Data("export function apply(ctx) { return ctx }\n".utf8), clientSourceData: clientSource).isCurrent)
        let installed = try config(at: directory)
        let dsh = try #require(installed["dsh"] as? NSDictionary)
        let profile = try #require(dsh["profile"] as? NSDictionary)
        #expect(profile["bundles"] as? [String] == ["@deepseek-ai/dsh-base", "@other/open-island-dsh", "open-island-dsh"])
        #expect(try Data(contentsOf: patchURL) == yaml)
        let package = try config(at: manager.pluginDirectory)
        #expect(package["type"] as? String == "module")
        let generatedPatch = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manager.pluginDirectory.appendingPathComponent("cordis.patch.yml"))) as? [[String: Any]])
        let insert = try #require(generatedPatch.first?["insert"] as? [[String: Any]])
        #expect(insert.first?["name"] as? String == manager.pluginFileURL.absoluteString)

        #expect(try !manager.uninstall().isInstalled)
        #expect(try config(at: directory) == original as NSDictionary)
        #expect(try Data(contentsOf: patchURL) == yaml)
        #expect(!FileManager.default.fileExists(atPath: manager.pluginDirectory.path))
        #expect(try !manager.uninstall().isInstalled)
    }

    @Test
    func uninstallOnlyPrunesContainersCreatedByInstaller() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true], to: directory)
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
        try manager.install(pluginSourceData: source, clientSourceData: clientSource)
        try manager.install(pluginSourceData: source, clientSourceData: clientSource)
        try manager.uninstall()
        #expect(try config(at: directory) == ["private": true] as NSDictionary)

        try manager.install(pluginSourceData: source, clientSourceData: clientSource)
        var edited = try #require(try config(at: directory) as? [String: Any])
        edited["dsh"] = ["extra": "new", "profile": ["extra": [1, 2], "bundles": ["open-island-dsh", "new-plugin"]]]
        try writeConfig(edited, to: directory)
        try manager.uninstall()
        #expect(try config(at: directory) == ["private": true, "dsh": ["extra": "new", "profile": ["extra": [1, 2], "bundles": ["new-plugin"]]]] as NSDictionary)
    }

    @Test(arguments: ["broken", "[]", "null", "{\"dsh\":null}", "{\"dsh\":{\"profile\":[]}}", "{\"dsh\":{\"profile\":{\"bundles\":[1]}}}"])
    func malformedConfigurationNeverChangesFiles(input: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
        let original = Data(input.utf8)
        try original.write(to: manager.configURL)
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source, clientSourceData: clientSource) }
        #expect(throws: DSHPluginInstallationError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: manager.configURL) == original)
        #expect(!FileManager.default.fileExists(atPath: manager.pluginsDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: manager.manifestURL.path))
    }

    @Test
    func absentProfileAndInvalidSourceDoNotCreateFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let absent = directory.appendingPathComponent("absent", isDirectory: true)
        let manager = DSHPluginInstallationManager(dshProfileDirectory: absent)
        #expect(try !manager.status().isInstalled)
        #expect(try !manager.uninstall().isInstalled)
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source, clientSourceData: clientSource) }
        #expect(!FileManager.default.fileExists(atPath: absent.path))
        for invalid in [Data(), Data([0xff]), Data(" \n".utf8)] {
            #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: invalid, clientSourceData: clientSource) }
            #expect(throws: DSHPluginInstallationError.invalidSource) { try manager.install(pluginSourceData: source, clientSourceData: invalid) }
        }
    }

    @Test(arguments: ["bundle", "registration", "manifest"])
    func unownedInstallationsAreNeverAdoptedOrRemoved(kind: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
        try writeConfig(["private": true], to: directory)
        switch kind {
        case "bundle":
            try FileManager.default.createDirectory(at: manager.pluginDirectory, withIntermediateDirectories: true)
            try source.write(to: manager.pluginFileURL)
        case "registration":
            try writeConfig(["dsh": ["profile": ["bundles": ["open-island-dsh"]]]], to: directory)
        default:
            try Data("{\"pluginPath\":\"/outside/open-island-dsh.js\"}".utf8).write(to: manager.manifestURL)
        }
        let before = try Data(contentsOf: manager.configURL)
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source, clientSourceData: clientSource) }
        #expect(throws: DSHPluginInstallationError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: manager.configURL) == before)
        if kind == "bundle" { #expect(try Data(contentsOf: manager.pluginFileURL) == source) }
    }

    @Test(arguments: [true, false])
    func jumpOnlyV2InstallationCanUpgradeOrUninstallSafely(upgrade: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true, "unrelated": ["enabled": true]], to: directory)
        let manager = try legacyInstallation(in: directory, version: 2)
        #expect(try manager.status().isInstalled)
        #expect(try !manager.status().isCurrent)
        if upgrade {
            let replacement = Data("export function apply(ctx) { return ctx }\n".utf8)
            #expect(try manager.install(pluginSourceData: replacement, clientSourceData: clientSource).isCurrent)
            #expect(try Data(contentsOf: manager.pluginFileURL) == replacement)
            #expect(try config(at: directory)["unrelated"] as? NSDictionary == ["enabled": true] as NSDictionary)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: manager.linkedPluginURL.path) == "../open-island-plugins/open-island-dsh")
        } else {
            #expect(try !manager.uninstall().isInstalled)
            #expect(!FileManager.default.fileExists(atPath: manager.clientFileURL.path))
            #expect(try config(at: directory)["unrelated"] as? NSDictionary == ["enabled": true] as NSDictionary)
        }
    }

    @Test(arguments: [0, DSHPluginInstallerManifest.currentVersion + 1])
    func unsupportedManifestVersionsCannotClaimOwnership(version: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true], to: directory)
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
        var manifest = try #require(manager.install(pluginSourceData: source, clientSourceData: clientSource).manifest)
        manifest.version = version
        try JSONEncoder().encode(manifest).write(to: manager.manifestURL)
        let before = try Data(contentsOf: manager.configURL)
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source, clientSourceData: clientSource) }
        #expect(throws: DSHPluginInstallationError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: manager.configURL) == before)
        #expect(try Data(contentsOf: manager.pluginFileURL) == source)
    }

    @Test(arguments: ["config", "node_modules", "plugins", "link", "bundle", "plugin", "client", "manifest", "ancestor"])
    func symbolicLinksNeverRedirectWrites(kind: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profileDirectory = directory.appendingPathComponent("profile", isDirectory: true)
        let outside = directory.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let manager = DSHPluginInstallationManager(dshProfileDirectory: profileDirectory)
        let sentinel = outside.appendingPathComponent("sentinel")
        try Data("untouched".utf8).write(to: sentinel)
        if kind != "config" { try writeConfig(["private": true], to: profileDirectory) }
        let target: URL
        switch kind {
        case "config": target = manager.configURL
        case "node_modules": target = manager.nodeModulesDirectory
        case "plugins": target = manager.pluginsDirectory
        case "link": target = manager.linkedPluginURL
        case "bundle": target = manager.pluginDirectory
        case "plugin": target = manager.pluginFileURL
        case "client": target = manager.clientFileURL
        case "manifest": target = manager.manifestURL
        default: target = directory.appendingPathComponent("linked", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        let effectiveManager = kind == "ancestor"
            ? DSHPluginInstallationManager(dshProfileDirectory: target.appendingPathComponent("profile"))
            : manager
        #expect(throws: DSHPluginInstallationError.self) { try effectiveManager.install(pluginSourceData: source, clientSourceData: clientSource) }
        #expect(throws: DSHPluginInstallationError.self) { try effectiveManager.uninstall() }
        #expect(try Data(contentsOf: sentinel) == Data("untouched".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path) == ["sentinel"])
    }

    @Test(arguments: ["modified", "client", "extra", "missing", "missingClient"])
    func changedManagedBundleIsPreserved(kind: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true], to: directory)
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
        try manager.install(pluginSourceData: source, clientSourceData: clientSource)
        switch kind {
        case "modified": try Data("user changes".utf8).write(to: manager.pluginFileURL)
        case "client": try Data("user client changes".utf8).write(to: manager.clientFileURL)
        case "extra": try Data("user file".utf8).write(to: manager.pluginDirectory.appendingPathComponent("keep.txt"))
        case "missingClient": try FileManager.default.removeItem(at: manager.clientFileURL)
        default: try FileManager.default.removeItem(at: manager.pluginFileURL)
        }
        let before = try Data(contentsOf: manager.configURL)
        #expect(try !manager.status().isCurrent)
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source, clientSourceData: clientSource) }
        #expect(throws: DSHPluginInstallationError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: manager.configURL) == before)
        #expect(FileManager.default.fileExists(atPath: manager.manifestURL.path))
        #expect(FileManager.default.fileExists(atPath: manager.pluginDirectory.path))
    }

    @Test
    func concurrentConfigEditIsNotOverwrittenDuringFailureRollback() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true], to: directory)
        let edited = Data("{\"private\":true,\"concurrent\":\"keep\"}".utf8)
        let fileManager = ConfigEditingFileManager()
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory, fileManager: fileManager)
        fileManager.onCreateDirectory = {
            try edited.write(to: directory.appendingPathComponent("package.json"))
        }
        #expect(throws: DSHPluginInstallationError.configurationChanged) {
            try manager.install(pluginSourceData: source, clientSourceData: clientSource)
        }
        #expect(try Data(contentsOf: manager.configURL) == edited)
        #expect(!FileManager.default.fileExists(atPath: manager.pluginDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: manager.manifestURL.path))
    }

    @Test(arguments: [1, 2])
    func prunedLegacyPackageMigratesToDurableSourceAndDeclaredLink(version: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original: [String: Any] = ["private": true, "dependencies": ["other": "1.2.3"]]
        try writeConfig(original, to: directory)
        let manager = try legacyInstallation(in: directory, version: version)
        try FileManager.default.removeItem(at: manager.linkedPluginURL)
        #expect(try !manager.status().isInstalled)
        let repaired = try manager.install(pluginSourceData: source, clientSourceData: clientSource)
        #expect(repaired.isCurrent)
        #expect(repaired.dependencyRegistered && repaired.managedLinkPresent)
        #expect(try Data(contentsOf: manager.pluginFileURL) == source)
        #expect(try Data(contentsOf: manager.linkedPluginURL.appendingPathComponent(DSHPluginInstallationManager.clientFileName)) == clientSource)
        #expect(try config(at: directory)["dependencies"] as? NSDictionary == [
            "other": "1.2.3", "open-island-dsh": "link:./open-island-plugins/open-island-dsh"
        ] as NSDictionary)
        try manager.uninstall()
        #expect(try config(at: directory) == original as NSDictionary)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: manager.linkedPluginURL.path)) == nil)
        #expect(!FileManager.default.fileExists(atPath: manager.pluginDirectory.path))
    }

    @Test(arguments: ["fresh", "legacy", "owned"])
    func foreignDependencyIsNeverAdoptedOrOverwritten(kind: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true], to: directory)
        let manager: DSHPluginInstallationManager
        if kind == "legacy" { manager = try legacyInstallation(in: directory, version: 2) }
        else {
            manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
            if kind == "owned" { try manager.install(pluginSourceData: source, clientSourceData: clientSource) }
        }
        var edited = try #require(try config(at: directory) as? [String: Any])
        // Even the same spelling is not adopted without manifest ownership.
        edited["dependencies"] = ["open-island-dsh": kind == "owned" ? "file:../user-plugin" : "link:./open-island-plugins/open-island-dsh"]
        try writeConfig(edited, to: directory)
        let before = try Data(contentsOf: manager.configURL)
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source, clientSourceData: clientSource) }
        #expect(throws: DSHPluginInstallationError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: manager.configURL) == before)
        if kind == "owned" { #expect(try Data(contentsOf: manager.pluginFileURL) == source) }
        if kind == "legacy" { #expect(try Data(contentsOf: manager.linkedPluginURL.appendingPathComponent(DSHPluginInstallationManager.pluginFileName)) == source) }
    }

    @Test
    func missingManagedLinkRepairsAndPackageManagerLinkRecreationRemainsOwned() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true], to: directory)
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
        try manager.install(pluginSourceData: source, clientSourceData: clientSource)
        let before = try Data(contentsOf: manager.pluginFileURL)
        try FileManager.default.removeItem(at: manager.linkedPluginURL)
        let missing = try manager.status()
        #expect(missing.managedFilesIntact && !missing.isCurrent)
        #expect(try manager.install(pluginSourceData: source, clientSourceData: clientSource).isCurrent)
        #expect(try Data(contentsOf: manager.pluginFileURL) == before)
        try FileManager.default.removeItem(at: manager.linkedPluginURL)
        try FileManager.default.createSymbolicLink(atPath: manager.linkedPluginURL.path, withDestinationPath: manager.pluginDirectory.path)
        #expect(try manager.status().isCurrent)
        let sibling = manager.pluginsDirectory.appendingPathComponent("user-data")
        let module = manager.nodeModulesDirectory.appendingPathComponent("user-data")
        try Data("stable sibling".utf8).write(to: sibling)
        try Data("module sibling".utf8).write(to: module)
        var edited = try #require(try config(at: directory) as? [String: Any])
        edited["dependencies"] = ["open-island-dsh": DSHPluginInstallationManager.dependencySpecifier, "later-added": "2.0.0"]
        try writeConfig(edited, to: directory)
        try manager.uninstall()
        #expect(try config(at: directory)["dependencies"] as? NSDictionary == ["later-added": "2.0.0"] as NSDictionary)
        #expect(try Data(contentsOf: sibling) == Data("stable sibling".utf8))
        #expect(try Data(contentsOf: module) == Data("module sibling".utf8))
    }

    @Test(arguments: [false, true])
    func foreignResolutionSlotNeverRedirectsOwnedSourceWrites(realDirectory: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true], to: directory)
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
        try manager.install(pluginSourceData: source, clientSourceData: clientSource)
        try FileManager.default.removeItem(at: manager.linkedPluginURL)
        let outside = directory.appendingPathComponent("foreign")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let sentinel = outside.appendingPathComponent("keep")
        try Data("foreign".utf8).write(to: sentinel)
        if realDirectory { try FileManager.default.createDirectory(at: manager.linkedPluginURL, withIntermediateDirectories: false) }
        else { try FileManager.default.createSymbolicLink(at: manager.linkedPluginURL, withDestinationURL: outside) }
        let before = try Data(contentsOf: manager.configURL)
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: Data("new host".utf8), clientSourceData: clientSource) }
        #expect(throws: DSHPluginInstallationError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: manager.configURL) == before)
        #expect(try Data(contentsOf: manager.pluginFileURL) == source)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path) == ["keep"])
        #expect(try Data(contentsOf: sentinel) == Data("foreign".utf8))
    }

    @Test(arguments: [false, true])
    func migrationLinkFailureRestoresLegacyLayoutAndPreservesConcurrentConfiguration(concurrentEdit: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true, "dependencies": ["other": "1"]], to: directory)
        _ = try legacyInstallation(in: directory, version: 2)
        let fileManager = LinkEditingFileManager()
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory, fileManager: fileManager)
        let before = try snapshot(manager)
        let edited = Data("{\"private\":true,\"concurrent\":\"keep\"}".utf8)
        fileManager.onCreateLink = {
            if concurrentEdit { try edited.write(to: manager.configURL) }
            else { throw CocoaError(.fileWriteUnknown) }
        }
        #expect(throws: (any Error).self) { try manager.install(pluginSourceData: Data("new host".utf8), clientSourceData: clientSource) }
        var after = try snapshot(manager)
        if concurrentEdit {
            #expect(after["profile"] == edited)
            after["profile"] = before["profile"]
        }
        #expect(after == before)
        #expect(!FileManager.default.fileExists(atPath: manager.pluginsDirectory.path))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: manager.linkedPluginURL.path)) == nil)
    }

    @Test
    func uninstallFailureRestoresDependencySourceAndExactLink() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true], to: directory)
        let fileManager = LinkEditingFileManager()
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory, fileManager: fileManager)
        try manager.install(pluginSourceData: source, clientSourceData: clientSource)
        let before = try snapshot(manager)
        fileManager.failRemoving = manager.manifestURL
        #expect(throws: (any Error).self) { try manager.uninstall() }
        #expect(try snapshot(manager) == before)
        #expect(try manager.status().isCurrent)
    }

    @Test
    func failedUpgradeRestoresManagedFilesAndConfiguration() throws {
        // Root can write through POSIX mode restrictions, so this boundary is not reproducible there.
        guard getuid() != 0 else { return }
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try writeConfig(["private": true], to: directory)
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
        try manager.install(pluginSourceData: source, clientSourceData: clientSource)
        let originalConfig = try Data(contentsOf: manager.configURL)
        let originalManifest = try Data(contentsOf: manager.manifestURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        #expect(throws: (any Error).self) {
            try manager.install(pluginSourceData: Data("export function apply() { return 2 }\n".utf8), clientSourceData: Data("updated client\n".utf8))
        }
        #expect(try Data(contentsOf: manager.pluginFileURL) == source)
        #expect(try Data(contentsOf: manager.clientFileURL) == clientSource)
        #expect(try Data(contentsOf: manager.configURL) == originalConfig)
        #expect(try Data(contentsOf: manager.manifestURL) == originalManifest)
        #expect(try manager.status().isCurrent)
    }
}
