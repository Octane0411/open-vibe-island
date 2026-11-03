import Foundation
import Testing
@testable import OpenIslandCore

/// Qoder CN surface display identity and source routing.
struct QoderCNSurfaceTests {
    @Test
    func qoderCNSurfaceIdentity() {
        #expect(AgentTool.qoderCN.displayName == "Qoder CN")
        #expect(AgentTool.qoderCN.shortName == "QDCN")
        #expect(AgentTool.qoderCN.isClaudeCodeFork)
        #expect(AgentIdentifier(rawValue: "qoderCN") == .qoderCN)
    }

    @Test
    func resolvedAgentToolMapsQoderCNSource() {
        var payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        )
        payload.hookSource = "qoder-cn"
        #expect(payload.resolvedAgentTool == .qoderCN)
        // Unknown sources still fall back to Claude Code.
        payload.hookSource = "something-else"
        #expect(payload.resolvedAgentTool == .claudeCode)
    }
}

/// Installation coverage for the Qoder CN Claude-Code-fork surface. Runs
/// entirely against temporary directories — never touches the user's real
/// `~/.qoder-cn` configuration.
struct QoderCNHooksInstallationTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qoder-cn-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeHooksBinary(in directory: URL) throws -> URL {
        let binaryURL = directory.appendingPathComponent("OpenIslandHooks")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
        return binaryURL
    }

    @Test
    func installsQoderCNHooksWithDedicatedSource() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let qoderCN = home.appendingPathComponent(".qoder-cn", isDirectory: true)
        // Pre-existing user keys must survive the managed install untouched.
        let settingsURL = qoderCN.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: qoderCN, withIntermediateDirectories: true)
        try Data(#"{"aicodingPluginSettingsMigrationVersion":1,"enabledPlugins":{},"providers":{}}"#.utf8)
            .write(to: settingsURL)

        let manager = ClaudeHookInstallationManager(
            claudeDirectory: qoderCN,
            managedHooksBinaryURL: qoderCN.appendingPathComponent("bin").appendingPathComponent("OpenIslandHooks"),
            hookSource: "qoder-cn"
        )
        let binaryURL = try makeHooksBinary(in: home)

        try manager.install(hooksBinaryURL: binaryURL)

        let settings = try String(contentsOf: settingsURL, encoding: .utf8)
        #expect(settings.contains("--source qoder-cn"))
        #expect(settings.contains("enabledPlugins"))
        #expect(settings.contains("providers"))
        #expect(try manager.status().managedHooksPresent)
    }

    @Test
    func uninstallRemovesManagedHooks() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let qoderCN = home.appendingPathComponent(".qoder-cn", isDirectory: true)
        let manager = ClaudeHookInstallationManager(
            claudeDirectory: qoderCN,
            managedHooksBinaryURL: qoderCN.appendingPathComponent("bin").appendingPathComponent("OpenIslandHooks"),
            hookSource: "qoder-cn"
        )
        let binaryURL = try makeHooksBinary(in: home)

        try manager.install(hooksBinaryURL: binaryURL)
        try manager.uninstall()

        #expect(!(try manager.status().managedHooksPresent))
        // Install created the settings file (it did not exist before), so
        // uninstall removes it entirely.
        #expect(!FileManager.default.fileExists(
            atPath: qoderCN.appendingPathComponent("settings.json").path
        ))
    }
}
