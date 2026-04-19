import Foundation
import Testing
@testable import OpenIslandCore

struct HermesHookInstallerTests {
    @Test
    func pluginYAMLContainsManagedMarker() {
        let yaml = HermesHookInstaller.pluginYAML()
        #expect(yaml.contains(HermesHookInstaller.managedMarker))
        #expect(yaml.contains("name: open-island"))
    }

    @Test
    func pluginInitShellsOutToHookBinaryWithHermesSource() {
        let python = HermesHookInstaller.pluginInitPython(hookBinaryPath: "/usr/local/bin/OpenIslandHooks")
        #expect(python.contains("\"/usr/local/bin/OpenIslandHooks\""))
        #expect(python.contains("--source"))
        #expect(python.contains("\"hermes\""))
        #expect(python.contains("def register(ctx"))
        #expect(python.contains("on_session_start"))
        #expect(python.contains("pre_tool_call"))
        #expect(python.contains("post_tool_call"))
        #expect(python.contains("on_session_end"))
    }

    @Test
    func isManagedPluginRecognizesMarker() {
        let managed = Data(HermesHookInstaller.pluginYAML().utf8)
        #expect(HermesHookInstaller.isManagedPlugin(pluginYAMLData: managed))

        let foreign = Data("name: some-other-plugin\n".utf8)
        #expect(!HermesHookInstaller.isManagedPlugin(pluginYAMLData: foreign))

        #expect(!HermesHookInstaller.isManagedPlugin(pluginYAMLData: nil))
    }

    @Test
    func installCreatesPluginFilesAndManifest() throws {
        let (hermesDir, hookBinaryURL) = try makeTempHermesEnvironment()
        defer { try? FileManager.default.removeItem(at: hermesDir.deletingLastPathComponent()) }

        let managedBinaryURL = hermesDir
            .appendingPathComponent("managed-bin")
            .appendingPathComponent("OpenIslandHooks")
        let manager = HermesHookInstallationManager(
            hermesDirectory: hermesDir,
            managedHooksBinaryURL: managedBinaryURL
        )

        let status = try manager.install(hooksBinaryURL: hookBinaryURL)

        #expect(status.managedHooksPresent)
        #expect(FileManager.default.fileExists(atPath: status.pluginYAMLURL.path))
        #expect(FileManager.default.fileExists(atPath: status.pluginInitURL.path))
        #expect(FileManager.default.fileExists(atPath: status.manifestURL.path))

        let manifest = try #require(status.manifest)
        #expect(manifest.hookBinaryPath == managedBinaryURL.standardizedFileURL.path)

        let yamlContents = try String(contentsOf: status.pluginYAMLURL)
        #expect(yamlContents.contains(HermesHookInstaller.managedMarker))
    }

    @Test
    func installIsIdempotent() throws {
        let (hermesDir, hookBinaryURL) = try makeTempHermesEnvironment()
        defer { try? FileManager.default.removeItem(at: hermesDir.deletingLastPathComponent()) }

        let managedBinaryURL = hermesDir
            .appendingPathComponent("managed-bin")
            .appendingPathComponent("OpenIslandHooks")
        let manager = HermesHookInstallationManager(
            hermesDirectory: hermesDir,
            managedHooksBinaryURL: managedBinaryURL
        )

        _ = try manager.install(hooksBinaryURL: hookBinaryURL)
        let rerun = try manager.install(hooksBinaryURL: hookBinaryURL)

        #expect(rerun.managedHooksPresent)
        #expect(rerun.manifest != nil)
    }

    @Test
    func uninstallRemovesManagedPluginOnly() throws {
        let (hermesDir, hookBinaryURL) = try makeTempHermesEnvironment()
        defer { try? FileManager.default.removeItem(at: hermesDir.deletingLastPathComponent()) }

        let managedBinaryURL = hermesDir
            .appendingPathComponent("managed-bin")
            .appendingPathComponent("OpenIslandHooks")
        let manager = HermesHookInstallationManager(
            hermesDirectory: hermesDir,
            managedHooksBinaryURL: managedBinaryURL
        )

        _ = try manager.install(hooksBinaryURL: hookBinaryURL)
        let afterUninstall = try manager.uninstall()

        #expect(!afterUninstall.managedHooksPresent)
        #expect(!FileManager.default.fileExists(atPath: afterUninstall.pluginDirectory.path))
    }

    @Test
    func uninstallSkipsForeignPluginDirectory() throws {
        let (hermesDir, hookBinaryURL) = try makeTempHermesEnvironment()
        defer { try? FileManager.default.removeItem(at: hermesDir.deletingLastPathComponent()) }
        _ = hookBinaryURL

        let managedBinaryURL = hermesDir
            .appendingPathComponent("managed-bin")
            .appendingPathComponent("OpenIslandHooks")
        let manager = HermesHookInstallationManager(
            hermesDirectory: hermesDir,
            managedHooksBinaryURL: managedBinaryURL
        )

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: manager.pluginDirectory, withIntermediateDirectories: true)
        let foreignYAML = manager.pluginDirectory.appendingPathComponent("plugin.yaml")
        try Data("name: user-plugin\nversion: 0.1.0\n".utf8).write(to: foreignYAML)

        let status = try manager.uninstall()

        #expect(!status.managedHooksPresent)
        #expect(status.hasForeignPluginDirectory)
        #expect(fileManager.fileExists(atPath: foreignYAML.path))
    }

    @Test
    func installRefusesToClobberForeignPluginDirectory() throws {
        let (hermesDir, hookBinaryURL) = try makeTempHermesEnvironment()
        defer { try? FileManager.default.removeItem(at: hermesDir.deletingLastPathComponent()) }

        let managedBinaryURL = hermesDir
            .appendingPathComponent("managed-bin")
            .appendingPathComponent("OpenIslandHooks")
        let manager = HermesHookInstallationManager(
            hermesDirectory: hermesDir,
            managedHooksBinaryURL: managedBinaryURL
        )

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: manager.pluginDirectory, withIntermediateDirectories: true)
        let foreignYAML = manager.pluginDirectory.appendingPathComponent("plugin.yaml")
        try Data("name: user-plugin\nversion: 0.1.0\n".utf8).write(to: foreignYAML)

        #expect(throws: HermesHookInstallationError.self) {
            _ = try manager.install(hooksBinaryURL: hookBinaryURL)
        }
    }

    private func makeTempHermesEnvironment() throws -> (hermesDir: URL, hookBinaryURL: URL) {
        let fileManager = FileManager.default
        let baseDir = fileManager.temporaryDirectory
            .appendingPathComponent("open-island-hermes-tests-\(UUID().uuidString)", isDirectory: true)
        let hermesDir = baseDir.appendingPathComponent(".hermes", isDirectory: true)
        let binaryDir = baseDir.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: hermesDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: binaryDir, withIntermediateDirectories: true)

        let hookBinaryURL = binaryDir.appendingPathComponent("OpenIslandHooks")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: hookBinaryURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookBinaryURL.path)

        return (hermesDir, hookBinaryURL)
    }
}
