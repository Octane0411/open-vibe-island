import Foundation
import Testing
@testable import OpenIslandCore

/// WorkBuddy surface display identity and source routing.
struct WorkBuddySurfaceTests {
    @Test
    func workBuddySurfaceIdentity() {
        #expect(AgentTool.workBuddy.displayName == "WorkBuddy")
        #expect(AgentTool.workBuddy.shortName == "WB")
        #expect(AgentTool.workBuddy.isClaudeCodeFork)
        #expect(AgentIdentifier(rawValue: "workBuddy") == .workBuddy)
    }

    @Test
    func resolvedAgentToolMapsWorkBuddySource() {
        var payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        )
        payload.hookSource = "workbuddy"
        #expect(payload.resolvedAgentTool == .workBuddy)
        // Unknown sources still fall back to Claude Code.
        payload.hookSource = "something-else"
        #expect(payload.resolvedAgentTool == .claudeCode)
    }
}

/// Installation coverage for the WorkBuddy Claude-Code-fork surface. Runs
/// entirely against temporary directories — never touches the user's real
/// `~/.workbuddy` configuration.
struct WorkBuddyHooksInstallationTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("workbuddy-install-\(UUID().uuidString)", isDirectory: true)
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
    func installsWorkBuddyHooksWithDedicatedSource() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let workBuddy = home.appendingPathComponent(".workbuddy", isDirectory: true)
        // Pre-existing user keys must survive the managed install untouched.
        let settingsURL = workBuddy.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: workBuddy, withIntermediateDirectories: true)
        try Data(#"{"aicodingPluginSettingsMigrationVersion":1,"enabledPlugins":{},"providers":{}}"#.utf8)
            .write(to: settingsURL)

        let manager = ClaudeHookInstallationManager(
            claudeDirectory: workBuddy,
            managedHooksBinaryURL: workBuddy.appendingPathComponent("bin").appendingPathComponent("OpenIslandHooks"),
            hookSource: "workbuddy"
        )
        let binaryURL = try makeHooksBinary(in: home)

        try manager.install(hooksBinaryURL: binaryURL)

        let settings = try String(contentsOf: settingsURL, encoding: .utf8)
        #expect(settings.contains("--source workbuddy"))
        #expect(settings.contains("enabledPlugins"))
        #expect(settings.contains("providers"))
        #expect(try manager.status().managedHooksPresent)
    }

    @Test
    func uninstallRemovesManagedHooks() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let workBuddy = home.appendingPathComponent(".workbuddy", isDirectory: true)
        let manager = ClaudeHookInstallationManager(
            claudeDirectory: workBuddy,
            managedHooksBinaryURL: workBuddy.appendingPathComponent("bin").appendingPathComponent("OpenIslandHooks"),
            hookSource: "workbuddy"
        )
        let binaryURL = try makeHooksBinary(in: home)

        try manager.install(hooksBinaryURL: binaryURL)
        try manager.uninstall()

        #expect(!(try manager.status().managedHooksPresent))
        // Install created the settings file (it did not exist before), so
        // uninstall removes it entirely.
        #expect(!FileManager.default.fileExists(
            atPath: workBuddy.appendingPathComponent("settings.json").path
        ))
    }
}
