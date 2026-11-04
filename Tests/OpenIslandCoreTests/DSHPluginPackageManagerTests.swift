import Foundation
import Testing
@testable import OpenIslandCore

@Suite(.enabled(if: ProcessInfo.processInfo.environment["OPEN_ISLAND_RUN_PNPM_INTEGRATION"] == "1", "Set OPEN_ISLAND_RUN_PNPM_INTEGRATION=1 with pnpm on PATH"))
struct DSHPluginPackageManagerTests {
    @Test
    func declaredStablePackageSurvivesRealOfflineDependencyReconciliation() throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let root = parent.appendingPathComponent("oi-dsh-pnpm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            precondition(root.deletingLastPathComponent() == parent && root.lastPathComponent.hasPrefix("oi-dsh-pnpm-"))
            try? FileManager.default.removeItem(at: root)
        }
        try Data("{\"name\":\"isolated-open-island-profile\",\"private\":true,\"keep\":true,\"dsh\":{\"profile\":{\"bundles\":[]}}}".utf8).write(to: root.appendingPathComponent("package.json"))
        try Data("node-linker=hoisted\n".utf8).write(to: root.appendingPathComponent(".npmrc"))
        let manager = DSHPluginInstallationManager(dshProfileDirectory: root)
        let host = Data("export function apply() {}\n".utf8)
        let client = Data("window.__ModuleLoader__.load({id:'open-island-dsh',factory:()=>({apply(){}})})\n".utf8)
        #expect(try manager.install(pluginSourceData: host, clientSourceData: client).isCurrent)
        let slot = root.appendingPathComponent("node_modules/open-island-dsh")
        let canonical = manager.pluginDirectory.resolvingSymlinksInPath()
        try #require(slot.resolvingSymlinksInPath() == canonical)
        try #require((try FileManager.default.attributesOfItem(atPath: slot.path)[.type] as? FileAttributeType) == .typeSymbolicLink)
        // Simulate removal of package-manager materialization, not owned source.
        try FileManager.default.removeItem(at: slot)
        #expect(try Data(contentsOf: manager.pluginFileURL) == host)
        try run(["pnpm", "install", "--offline", "--ignore-scripts", "--no-frozen-lockfile"], in: root)
        #expect(slot.resolvingSymlinksInPath() == canonical)
        #expect(try manager.status().isCurrent)
        #expect(try Data(contentsOf: manager.pluginFileURL) == host)
        #expect(try Data(contentsOf: manager.clientFileURL) == client)
        try run(["node", "--input-type=module", "-e", "import {createRequire} from 'node:module'\nconst r=createRequire(process.cwd()+'/package.json')\nr.resolve('open-island-dsh')\nr.resolve('open-island-dsh/client')"], in: root)
        #expect(try !manager.uninstall().isInstalled)
        #expect(!FileManager.default.fileExists(atPath: slot.path))
        let config = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manager.configURL)) as? [String: Any])
        #expect(config["keep"] as? Bool == true)
        #expect((config["dependencies"] as? [String: String])?[DSHPluginInstallationManager.bundleName] == nil)
    }

    private func run(_ arguments: [String], in root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["CI"] = "true"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let diagnostics = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        try #require(process.terminationStatus == 0, Comment(rawValue: diagnostics))
    }
}
