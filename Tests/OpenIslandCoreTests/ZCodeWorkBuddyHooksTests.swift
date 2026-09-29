import Foundation
import Testing
@testable import OpenIslandCore

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}

struct ZCodeWorkBuddyHooksTests {
    private func makeHooksBinary(rootURL: URL) throws -> URL {
        let hooksBinaryURL = rootURL
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")
        try FileManager.default.createDirectory(at: hooksBinaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hook".utf8).write(to: hooksBinaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hooksBinaryURL.path)
        return hooksBinaryURL
    }

    // MARK: - ZCode

    @Test
    func zcodeHookInstallationManagerRoundTripsInstallAndUninstall() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-zcode-hooks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configDirectory = rootURL.appendingPathComponent("cli", isDirectory: true)
        let managedHooksBinaryURL = rootURL
            .appendingPathComponent("managed", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")
        let manager = ZCodeHookInstallationManager(
            configDirectory: configDirectory,
            managedHooksBinaryURL: managedHooksBinaryURL
        )
        let hooksBinaryURL = try makeHooksBinary(rootURL: rootURL)

        let installed = try manager.install(hooksBinaryURL: hooksBinaryURL)
        #expect(installed.managedHooksPresent)
        #expect(installed.hooksBinaryURL?.path == managedHooksBinaryURL.standardizedFileURL.path)
        #expect(installed.manifest?.hookCommand == ZCodeHookInstaller.hookCommand(for: managedHooksBinaryURL.path))

        let configObject = try jsonObject(from: Data(contentsOf: installed.settingsURL))
        let hooksObject = try #require(configObject["hooks"] as? [String: Any])
        #expect(hooksObject["enabled"] as? Bool == true)
        let eventsObject = try #require(hooksObject["events"] as? [String: Any])

        let expectedEvents = Set(ZCodeHookInstaller.eventSpecs.map(\.name))
        #expect(Set(eventsObject.keys) == expectedEvents)

        let permissionGroups = try #require(eventsObject["PermissionRequest"] as? [[String: Any]])
        #expect(permissionGroups.count == 1)
        #expect(permissionGroups[0]["matcher"] as? String == ".*")
        let permissionHooks = try #require(permissionGroups[0]["hooks"] as? [[String: Any]])
        #expect(permissionHooks[0]["command"] as? String == installed.manifest?.hookCommand)
        #expect(permissionHooks[0]["timeout"] as? Int == ZCodeHookInstaller.managedTimeout)

        let uninstalled = try manager.uninstall()
        #expect(!uninstalled.managedHooksPresent)
        #expect(!FileManager.default.fileExists(atPath: uninstalled.manifestURL.path))
    }

    @Test
    func zcodeInstallPreservesUnrelatedConfigAndUserHooks() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-zcode-preserve-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configDirectory = rootURL.appendingPathComponent("cli", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let configURL = configDirectory.appendingPathComponent("config.json")
        let userConfig = """
        {
          "hooks" : {
            "enabled" : true,
            "timeoutMs" : 120000,
            "maxOutputBytes" : 65536,
            "events" : {
              "PreToolUse" : [
                {
                  "matcher" : "Edit|Write",
                  "hooks" : [ { "type" : "command", "command" : "echo user-rule" } ]
                }
              ],
              "CustomEvent" : [
                {
                  "hooks" : [ { "type" : "command", "command" : "echo custom" } ]
                }
              ]
            }
          },
          "plugins" : {
            "enabledPlugins" : { "demo" : true }
          }
        }
        """
        try Data(userConfig.utf8).write(to: configURL)

        let manager = ZCodeHookInstallationManager(
            configDirectory: configDirectory,
            managedHooksBinaryURL: rootURL.appendingPathComponent("managed", isDirectory: true).appendingPathComponent("OpenIslandHooks")
        )
        _ = try manager.install(hooksBinaryURL: try makeHooksBinary(rootURL: rootURL))

        let configObject = try jsonObject(from: Data(contentsOf: configURL))
        let pluginsObject = try #require(configObject["plugins"] as? [String: Any])
        #expect((pluginsObject["enabledPlugins"] as? [String: Bool])?["demo"] == true)

        let hooksObject = try #require(configObject["hooks"] as? [String: Any])
        #expect(hooksObject["timeoutMs"] as? Int == 120000)
        #expect(hooksObject["maxOutputBytes"] as? Int == 65536)
        let eventsObject = try #require(hooksObject["events"] as? [String: Any])
        #expect(eventsObject["CustomEvent"] != nil)

        let preToolUseGroups = try #require(eventsObject["PreToolUse"] as? [[String: Any]])
        #expect(preToolUseGroups.count == 2)
        let allCommands = preToolUseGroups.flatMap { group -> [String] in
            (group["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
        }
        #expect(allCommands.contains("echo user-rule"))
        #expect(allCommands.contains { $0.contains("--source zcode") })

        // Uninstall removes only the managed entries.
        _ = try manager.uninstall()
        let cleanedObject = try jsonObject(from: Data(contentsOf: configURL))
        let cleanedHooks = try #require(cleanedObject["hooks"] as? [String: Any])
        let cleanedEvents = try #require(cleanedHooks["events"] as? [String: Any])
        #expect(cleanedEvents["PreToolUse"] != nil)
        let cleanedGroups = try #require(cleanedEvents["PreToolUse"] as? [[String: Any]])
        #expect(cleanedGroups.count == 1)
        let cleanedCommands = cleanedGroups.flatMap { group -> [String] in
            (group["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
        }
        #expect(cleanedCommands == ["echo user-rule"])
        #expect((cleanedObject["plugins"] as? [String: Any])?["enabledPlugins"] != nil)
    }

    @Test
    func zcodeInstallReplacesLegacyVibeIslandEntriesWithoutTouchingOtherSources() throws {
        let legacyConfig = """
        {
          "hooks" : {
            "enabled" : true,
            "events" : {
              "PreToolUse" : [
                {
                  "matcher" : ".*",
                  "hooks" : [
                    { "type" : "command", "command" : "'/Users/demo/.vibe-island/bin/vibe-island-bridge' --source zcode" },
                    { "type" : "command", "command" : "'/Users/demo/.vibe-island/bin/vibe-island-bridge' --source workbuddy" },
                    { "type" : "command", "command" : "'/Users/demo/.vibe-island/bin/vibe-island-bridge' --source claude" }
                  ]
                }
              ]
            }
          }
        }
        """

        let installMutation = try ZCodeHookInstaller.installConfigJSON(
            existingData: Data(legacyConfig.utf8),
            hookCommand: "'/managed/OpenIslandHooks' --source zcode"
        )
        var eventsObject = try #require(try jsonObject(from: installMutation.contents ?? Data())["hooks"] as? [String: Any])["events"] as? [String: Any]
        let groups = try #require(eventsObject?["PreToolUse"] as? [[String: Any]])
        let commands = groups.flatMap { group -> [String] in
            (group["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
        }
        #expect(!commands.contains { $0.contains("vibe-island-bridge' --source zcode") })
        #expect(commands.contains { $0.contains("vibe-island-bridge' --source workbuddy") })
        #expect(commands.contains { $0.contains("vibe-island-bridge' --source claude") })
        #expect(commands.contains { $0.contains("--source zcode") && $0.contains("OpenIslandHooks") })

        // Uninstall with no manifest only strips the zcode-sourced legacy
        // entries; other sources keep theirs.
        let uninstallMutation = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: installMutation.contents,
            managedCommand: nil
        )
        eventsObject = try #require(try jsonObject(from: uninstallMutation.contents ?? Data())["hooks"] as? [String: Any])["events"] as? [String: Any]
        #expect(eventsObject?["PreToolUse"] != nil)
        let remainingGroups = try #require(eventsObject?["PreToolUse"] as? [[String: Any]])
        let remainingCommands = remainingGroups.flatMap { group -> [String] in
            (group["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
        }
        #expect(remainingCommands.contains { $0.contains("--source workbuddy") })
        #expect(remainingCommands.contains { $0.contains("--source claude") })
        #expect(!remainingCommands.contains { $0.contains("--source zcode") })
    }

    // MARK: - WorkBuddy

    @Test
    func workbuddyManagerInstallsSubsetAndCleansLegacyEntries() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-workbuddy-hooks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let claudeDirectory = rootURL.appendingPathComponent(".workbuddy", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let legacySettings = """
        {
          "hooks" : {
            "PreToolUse" : [
              {
                "matcher" : "*",
                "hooks" : [
                  { "type" : "command", "command" : "/Users/demo/.vibe-island/bin/vibe-island-bridge --source workbuddy" }
                ]
              }
            ],
            "UserPromptSubmit" : [
              {
                "hooks" : [ { "type" : "command", "command" : "echo user-prompt-rule" } ]
              }
            ]
          },
          "http.proxy" : "http://127.0.0.1:7890"
        }
        """
        try Data(legacySettings.utf8).write(to: settingsURL)

        let manager = ClaudeHookInstallationManager(
            claudeDirectory: claudeDirectory,
            managedHooksBinaryURL: rootURL.appendingPathComponent("managed", isDirectory: true).appendingPathComponent("OpenIslandHooks"),
            hookSource: "workbuddy",
            hookEvents: ClaudeHookInstaller.workbuddyEventSpecs
        )
        let installed = try manager.install(hooksBinaryURL: try makeHooksBinary(rootURL: rootURL))
        #expect(installed.managedHooksPresent)

        let settingsObject = try jsonObject(from: Data(contentsOf: settingsURL))
        #expect(settingsObject["http.proxy"] as? String == "http://127.0.0.1:7890")
        let hooksObject = try #require(settingsObject["hooks"] as? [String: Any])
        #expect(Set(hooksObject.keys) == Set(ClaudeHookInstaller.workbuddyEventSpecs.map(\.name)))
        #expect(hooksObject["PermissionRequest"] == nil)

        let preToolUseGroups = try #require(hooksObject["PreToolUse"] as? [[String: Any]])
        let commands = preToolUseGroups.flatMap { group -> [String] in
            (group["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
        }
        #expect(!commands.contains { $0.contains("vibe-island-bridge") })
        #expect(commands.contains { $0.contains("--source workbuddy") && $0.contains("OpenIslandHooks") })

        let promptGroups = try #require(hooksObject["UserPromptSubmit"] as? [[String: Any]])
        let promptCommands = promptGroups.flatMap { group -> [String] in
            (group["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
        }
        #expect(promptCommands.contains("echo user-prompt-rule"))

        let uninstalled = try manager.uninstall()
        #expect(!uninstalled.managedHooksPresent)
        let cleanedObject = try jsonObject(from: Data(contentsOf: settingsURL))
        let cleanedHooks = cleanedObject["hooks"] as? [String: Any]
        let cleanedPromptGroups = cleanedHooks?["UserPromptSubmit"] as? [[String: Any]]
        #expect(cleanedPromptGroups?.count == 1)
        #expect(settingsObject["http.proxy"] != nil)
    }

    // MARK: - Payload routing

    @Test
    func resolvedAgentToolMapsZcodeAndWorkbuddySources() throws {
        let decoder = JSONDecoder()
        let baseJSON = #"{"cwd": "/tmp", "hook_event_name": "SessionStart", "session_id": "s1"}"#

        var zcodePayload = try decoder.decode(ClaudeHookPayload.self, from: Data(baseJSON.utf8))
        zcodePayload.hookSource = "zcode"
        #expect(zcodePayload.resolvedAgentTool == .zcode)

        var workbuddyPayload = try decoder.decode(ClaudeHookPayload.self, from: Data(baseJSON.utf8))
        workbuddyPayload.hookSource = "workbuddy"
        #expect(workbuddyPayload.resolvedAgentTool == .workbuddy)

        let unknownPayload = try decoder.decode(ClaudeHookPayload.self, from: Data(baseJSON.utf8))
        #expect(unknownPayload.resolvedAgentTool == .claudeCode)
    }
}
