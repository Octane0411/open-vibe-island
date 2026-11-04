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

struct DSHPluginInstallationManagerTests {
    private let source = Data("export function apply(ctx) {}\n".utf8)

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

        #expect(try manager.install(pluginSourceData: source).isCurrent)
        #expect(try manager.install(pluginSourceData: Data("export function apply(ctx) { return ctx }\n".utf8)).isCurrent)
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
        try manager.install(pluginSourceData: source)
        try manager.install(pluginSourceData: source)
        try manager.uninstall()
        #expect(try config(at: directory) == ["private": true] as NSDictionary)

        try manager.install(pluginSourceData: source)
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
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source) }
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
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source) }
        #expect(!FileManager.default.fileExists(atPath: absent.path))
        for invalid in [Data(), Data([0xff]), Data(" \n".utf8)] {
            #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: invalid) }
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
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source) }
        #expect(throws: DSHPluginInstallationError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: manager.configURL) == before)
        if kind == "bundle" { #expect(try Data(contentsOf: manager.pluginFileURL) == source) }
    }

    @Test(arguments: [0, DSHPluginInstallerManifest.currentVersion + 1])
    func unsupportedManifestVersionsCannotClaimOwnership(version: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true], to: directory)
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
        var manifest = try #require(manager.install(pluginSourceData: source).manifest)
        manifest.version = version
        try JSONEncoder().encode(manifest).write(to: manager.manifestURL)
        let before = try Data(contentsOf: manager.configURL)
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source) }
        #expect(throws: DSHPluginInstallationError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: manager.configURL) == before)
        #expect(try Data(contentsOf: manager.pluginFileURL) == source)
    }

    @Test(arguments: ["config", "node_modules", "bundle", "plugin", "manifest", "ancestor"])
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
        case "node_modules": target = manager.pluginsDirectory
        case "bundle": target = manager.pluginDirectory
        case "plugin": target = manager.pluginFileURL
        case "manifest": target = manager.manifestURL
        default: target = directory.appendingPathComponent("linked", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        let effectiveManager = kind == "ancestor"
            ? DSHPluginInstallationManager(dshProfileDirectory: target.appendingPathComponent("profile"))
            : manager
        #expect(throws: DSHPluginInstallationError.self) { try effectiveManager.install(pluginSourceData: source) }
        #expect(throws: DSHPluginInstallationError.self) { try effectiveManager.uninstall() }
        #expect(try Data(contentsOf: sentinel) == Data("untouched".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path) == ["sentinel"])
    }

    @Test(arguments: ["modified", "extra", "missing"])
    func changedManagedBundleIsPreserved(kind: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeConfig(["private": true], to: directory)
        let manager = DSHPluginInstallationManager(dshProfileDirectory: directory)
        try manager.install(pluginSourceData: source)
        switch kind {
        case "modified": try Data("user changes".utf8).write(to: manager.pluginFileURL)
        case "extra": try Data("user file".utf8).write(to: manager.pluginDirectory.appendingPathComponent("keep.txt"))
        default: try FileManager.default.removeItem(at: manager.pluginFileURL)
        }
        let before = try Data(contentsOf: manager.configURL)
        #expect(try !manager.status().isCurrent)
        #expect(throws: DSHPluginInstallationError.self) { try manager.install(pluginSourceData: source) }
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
            try manager.install(pluginSourceData: source)
        }
        #expect(try Data(contentsOf: manager.configURL) == edited)
        #expect(!FileManager.default.fileExists(atPath: manager.pluginDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: manager.manifestURL.path))
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
        try manager.install(pluginSourceData: source)
        let originalConfig = try Data(contentsOf: manager.configURL)
        let originalManifest = try Data(contentsOf: manager.manifestURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        #expect(throws: (any Error).self) {
            try manager.install(pluginSourceData: Data("export function apply() { return 2 }\n".utf8))
        }
        #expect(try Data(contentsOf: manager.pluginFileURL) == source)
        #expect(try Data(contentsOf: manager.configURL) == originalConfig)
        #expect(try Data(contentsOf: manager.manifestURL) == originalManifest)
        #expect(try manager.status().isCurrent)
    }
}
