import Foundation
import Testing
@testable import OpenIslandCore

struct ConfigurationSafetyTests {
    @Test
    func failedInstallRestoresOriginalConfigurationAndPlugin() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let plugins = root.appendingPathComponent("plugins")
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.json")
        let plugin = plugins.appendingPathComponent("open-island.js")
        let original = Data(#"{"model":"keep me"}"#.utf8)
        try original.write(to: config)
        try Data("original plugin".utf8).write(to: plugin)
        let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: root,
            fileManager: FailingPermissionsFileManager(path: config.path))
        #expect(throws: (any Error).self) { try manager.install(pluginSourceData: Data("replacement plugin".utf8)) }
        #expect(try Data(contentsOf: config) == original)
        #expect(try Data(contentsOf: plugin) == Data("original plugin".utf8))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(OpenCodePluginInstallerManifest.fileName).path))
        let recovery = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".open-island-recovery-") })
        #expect(FileManager.default.fileExists(atPath: recovery.appendingPathComponent("manifest.json").path))
        let attributes = try FileManager.default.attributesOfItem(atPath: recovery.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test
    func openCodeRoundTripPreservesUnrelatedSettingsAndSameNamedPlugins() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.json")
        try Data(#"{"model":"private/model","plugin":["file:///other/open-island.js","other-plugin"]}"#.utf8).write(to: config)
        let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: root)
        _ = try manager.install(pluginSourceData: Data("plugin".utf8))
        _ = try manager.install(pluginSourceData: Data("plugin".utf8))
        let installed = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        #expect((installed["plugin"] as? [String])?.count == 3)
        _ = try manager.uninstall()
        let removed = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        #expect(removed["model"] as? String == "private/model")
        #expect(removed["plugin"] as? [String] == ["file:///other/open-island.js", "other-plugin"])
    }

    @Test
    func codexDetectsConcurrentEditBeforeInstallingHelper() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.toml")
        try Data("model = 'original'".utf8).write(to: config)
        let source = root.appendingPathComponent("source")
        try Data("helper".utf8).write(to: source)
        let installed = root.appendingPathComponent("bin/helper")
        let manager = CodexHookInstallationManager(codexDirectory: root, managedHooksBinaryURL: installed, featureKeyProvider: {
            try! Data("model = 'concurrent edit'".utf8).write(to: config)
            return .current
        })
        #expect(throws: (any Error).self) { try manager.install(hooksBinaryURL: source) }
        #expect(try String(contentsOf: config, encoding: .utf8) == "model = 'concurrent edit'")
        #expect(!FileManager.default.fileExists(atPath: installed.path))
    }

    @Test(arguments: ["[features] # enabled features\nhooks = false\n", "[features]\nhooks = false\n[features]\n", "invalid = ["]) 
    func codexConfigurationIsValidatedBeforeAnyWrites(_ input: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.toml")
        try Data(input.utf8).write(to: config)
        let source = root.appendingPathComponent("source")
        try Data("helper".utf8).write(to: source)
        let installed = root.appendingPathComponent("bin/helper")
        let manager = CodexHookInstallationManager(codexDirectory: root, managedHooksBinaryURL: installed, featureKeyProvider: { .current })
        if input.contains("# enabled features") {
            _ = try manager.install(hooksBinaryURL: source)
            let output = try String(contentsOf: config, encoding: .utf8)
            #expect(output.contains("[features] # enabled features"))
            #expect(output.components(separatedBy: "[features]").count == 2)
            #expect(output.contains("hooks = true"))
        } else {
            #expect(throws: (any Error).self) { try manager.install(hooksBinaryURL: source) }
            #expect(try Data(contentsOf: config) == Data(input.utf8))
            #expect(!FileManager.default.fileExists(atPath: installed.path))
        }
    }

    @Test(arguments: ["{broken", "[]", #"{"plugin": 3}"#])
    func invalidOpenCodeConfigurationIsPreserved(_ input: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.json")
        let original = Data(input.utf8)
        try original.write(to: config)
        let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: root)
        #expect(throws: (any Error).self) { try manager.install(pluginSourceData: Data("plugin".utf8)) }
        #expect(try Data(contentsOf: config) == original)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("plugins/open-island.js").path))
        #expect(throws: (any Error).self) { try manager.uninstall() }
        #expect(try Data(contentsOf: config) == original)
    }
}

private final class FailingPermissionsFileManager: FileManager, @unchecked Sendable {
    private let failurePath: String
    private var didFail = false
    init(path: String) { failurePath = path; super.init() }
    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        if path == failurePath && !didFail {
            didFail = true
            throw CocoaError(.fileWriteUnknown)
        }
        try super.setAttributes(attributes, ofItemAtPath: path)
    }
}
