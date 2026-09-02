import Foundation
import Testing
@testable import OpenIslandCore

struct ZCodeHooksTests {
    private let command = ZCodeHookInstaller.processCommand(for: "/opt/open-island/OpenIslandHooks")

    private func hookEntry(in json: [String: Any], event: String) -> [String: Any]? {
        guard let hooks = json["hooks"] as? [String: Any],
              let events = hooks["events"] as? [String: Any],
              let groups = events[event] as? [[String: Any]] else {
            return nil
        }
        return groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .first { entry in
                let arguments = (entry["args"] as? [Any])?.compactMap { $0 as? String } ?? []
                return ((entry["command"] as? String ?? "") + " " + arguments.joined(separator: " "))
                    .contains("--source zcode")
            }
    }

    private func decodedRoot(_ data: Data?) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try #require(data))
        return try #require(object as? [String: Any])
    }

    @Test
    func installIntoEmptyConfigWritesEnabledHooksWithLifecycleEvents() throws {
        let mutation = try ZCodeHookInstaller.installConfigJSON(existingData: nil, hookCommand: command)

        #expect(mutation.changed)
        #expect(mutation.managedHooksPresent)
        #expect(mutation.hooksEnabledBefore == nil)

        let root = try decodedRoot(mutation.contents)
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(hooks["enabled"] as? Bool == true)

        for event in ["SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest"] {
            let entry = try #require(hookEntry(in: root, event: event))
            #expect(entry["type"] as? String == "process")
            #expect(entry["command"] as? String == command)
            #expect(entry["args"] as? [String] == ["--source", "zcode"])
            #expect(entry["enabled"] as? Bool == true)
            #expect(entry["timeoutMs"] != nil)
        }

        // Low-noise footprint: per-tool events are not installed.
        let events = try #require((root["hooks"] as? [String: Any])?["events"] as? [String: Any])
        #expect(events["PreToolUse"] == nil)
        #expect(events["PostToolUse"] == nil)
    }

    @Test
    func installSetsEnabledTrueAndRecordsPriorState() throws {
        let existing = Data("{\"plugins\": {\"enabled\": {}}}".utf8)
        let mutation = try ZCodeHookInstaller.installConfigJSON(existingData: existing, hookCommand: command)

        let root = try decodedRoot(mutation.contents)
        #expect(mutation.hooksEnabledBefore == nil)
        let plugins = try #require(root["plugins"] as? [String: Any])
        #expect(plugins["enabled"] != nil)

        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(hooks["enabled"] as? Bool == true)
    }

    @Test
    func installPreservesUserHooksAndRecordsEnabledTrue() throws {
        let userConfig: [String: Any] = [
            "model": ["providerId": "builtin:bigmodel-coding-plan"],
            "hooks": [
                "enabled": true,
                "events": [
                    "PreToolUse": [[
                        "matcher": "Write",
                        "hooks": [["type": "command", "command": "/usr/bin/lint.sh"]],
                    ]],
                ],
            ],
        ]
        let existing = try JSONSerialization.data(withJSONObject: userConfig)

        let mutation = try ZCodeHookInstaller.installConfigJSON(existingData: existing, hookCommand: command)
        let root = try decodedRoot(mutation.contents)

        #expect(mutation.hooksEnabledBefore == true)

        let events = try #require((root["hooks"] as? [String: Any])?["events"] as? [String: Any])
        let userGroups = try #require(events["PreToolUse"] as? [[String: Any]])
        let userHooks = userGroups.compactMap { $0["hooks"] as? [[String: Any]] }.flatMap { $0 }
        #expect(userHooks.contains { ($0["command"] as? String) == "/usr/bin/lint.sh" })
        #expect(userGroups.first?["matcher"] as? String == "Write")

        let managedPreToolUse = hookEntry(in: root, event: "PreToolUse")
        #expect(managedPreToolUse == nil)
    }

    @Test
    func installReplacesStaleManagedEntries() throws {
        let staleCommand = "'/old/path/OpenIslandHooks' --source zcode"
        let userConfig: [String: Any] = [
            "hooks": [
                "enabled": true,
                "events": [
                    "Stop": [["hooks": [["type": "command", "command": staleCommand]]]],
                ],
            ],
        ]
        let existing = try JSONSerialization.data(withJSONObject: userConfig)

        let mutation = try ZCodeHookInstaller.installConfigJSON(existingData: existing, hookCommand: command)
        let root = try decodedRoot(mutation.contents)

        let stopEntry = try #require(hookEntry(in: root, event: "Stop"))
        #expect(stopEntry["type"] as? String == "process")
        #expect(stopEntry["command"] as? String == command)

        let groups = try #require(
            ((root["hooks"] as? [String: Any])?["events"] as? [String: Any])?["Stop"] as? [[String: Any]]
        )
        #expect(groups.count == 1)
    }

    @Test
    func uninstallRemovesManagedHooksAndRestoresAbsentEnabledState() throws {
        let install = try ZCodeHookInstaller.installConfigJSON(existingData: nil, hookCommand: command)
        let installed = try #require(install.contents)

        let uninstall = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: installed,
            managedCommand: command,
            hooksEnabledBeforeInstall: install.hooksEnabledBefore
        )

        #expect(uninstall.changed)
        // "managedHooksPresent" mirrors Claude's uninstall semantic: managed
        // hooks were found on disk and removed by this mutation.
        #expect(uninstall.managedHooksPresent)
        // The config held nothing but the managed hooks, so the result is
        // empty and the manager deletes the file.
        #expect(uninstall.contents == nil)

        // A follow-up pass over the cleaned state reports nothing left.
        let second = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: uninstall.contents,
            managedCommand: command,
            hooksEnabledBeforeInstall: install.hooksEnabledBefore
        )
        #expect(!second.changed)
        #expect(!second.managedHooksPresent)
    }

    @Test
    func uninstallKeepsUserHooksAndEnabledFlag() throws {
        let userConfig: [String: Any] = [
            "hooks": [
                "enabled": true,
                "events": [
                    "PreToolUse": [["hooks": [["type": "command", "command": "/usr/bin/lint.sh"]]]],
                ],
            ],
        ]
        let existing = try JSONSerialization.data(withJSONObject: userConfig)
        let install = try ZCodeHookInstaller.installConfigJSON(existingData: existing, hookCommand: command)
        let installed = try #require(install.contents)

        let uninstall = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: installed,
            managedCommand: command,
            hooksEnabledBeforeInstall: install.hooksEnabledBefore
        )

        let root = try decodedRoot(uninstall.contents)
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(hooks["enabled"] as? Bool == true)

        let events = try #require(hooks["events"] as? [String: Any])
        let userGroups = try #require(events["PreToolUse"] as? [[String: Any]])
        let userHooks = userGroups.compactMap { $0["hooks"] as? [[String: Any]] }.flatMap { $0 }
        #expect(userHooks.contains { ($0["command"] as? String) == "/usr/bin/lint.sh" })
        #expect(events["SessionStart"] == nil)
        #expect(events["Stop"] == nil)
    }

    @Test
    func uninstallRemovesEnabledFlagWhenUserHadNone() throws {
        let userConfig: [String: Any] = [
            "plugins": ["enabledPlugins": [:]],
        ]
        let existing = try JSONSerialization.data(withJSONObject: userConfig)
        let install = try ZCodeHookInstaller.installConfigJSON(existingData: existing, hookCommand: command)
        let installed = try #require(install.contents)

        let uninstall = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: installed,
            managedCommand: command,
            hooksEnabledBeforeInstall: install.hooksEnabledBefore
        )

        let root = try decodedRoot(uninstall.contents)
        #expect(root["hooks"] == nil)
        #expect(root["plugins"] != nil)
    }

    @Test
    func uninstallCoversLegacyVibeIslandCommands() throws {
        let legacyConfig: [String: Any] = [
            "hooks": [
                "enabled": true,
                "events": [
                    "Stop": [["hooks": [["type": "command", "command": "'/old/VibeIslandHooks' --source zcode"]]]],
                ],
            ],
        ]
        let existing = try JSONSerialization.data(withJSONObject: legacyConfig)

        let uninstall = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: existing,
            managedCommand: command,
            hooksEnabledBeforeInstall: nil
        )

        #expect(uninstall.changed)
        #expect(uninstall.managedHooksPresent)
        // The legacy config held nothing but the managed hook, so the whole
        // file empties out.
        #expect(uninstall.contents == nil)
    }

    @Test
    func currentFormatDetectionDistinguishesLegacyInstalls() throws {
        // A legacy install (shell-quoted command-type entries, as written
        // before the process-type migration) is managed but not current.
        let legacyCommand = "'/opt/open-island/OpenIslandHooks' --source zcode"
        let legacyConfig: [String: Any] = [
            "hooks": [
                "enabled": true,
                "events": [
                    "SessionStart": [["hooks": [["type": "command", "command": legacyCommand]]]],
                    "UserPromptSubmit": [["hooks": [["type": "command", "command": legacyCommand]]]],
                    "Stop": [["hooks": [["type": "command", "command": legacyCommand]]]],
                    "PermissionRequest": [["matcher": "*", "hooks": [["type": "command", "command": legacyCommand]]]],
                ],
            ],
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyConfig)
        #expect(!ZCodeHookInstaller.containsCurrentFormatHooks(existingData: legacyData, hookCommand: command))

        // Re-installing over the legacy config migrates every event to the
        // process type and reports the current format.
        let mutation = try ZCodeHookInstaller.installConfigJSON(existingData: legacyData, hookCommand: command)
        #expect(ZCodeHookInstaller.containsCurrentFormatHooks(existingData: mutation.contents, hookCommand: command))
        #expect(!ZCodeHookInstaller.containsCurrentFormatHooks(existingData: nil, hookCommand: command))

        // Uninstalling removes even the legacy entries (marker-based
        // detection), leaving no current-format hooks behind.
        let uninstall = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: legacyData,
            managedCommand: command,
            hooksEnabledBeforeInstall: nil
        )
        #expect(uninstall.managedHooksPresent)
        #expect(!ZCodeHookInstaller.containsCurrentFormatHooks(existingData: uninstall.contents, hookCommand: command))
    }

    @Test
    func uninstallOnConfigWithoutHooksIsNoop() throws {
        let existing = Data("{\"plugins\": {}}".utf8)
        let uninstall = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: existing,
            managedCommand: command,
            hooksEnabledBeforeInstall: nil
        )

        #expect(!uninstall.changed)
        #expect(!uninstall.managedHooksPresent)
    }

    @Test
    func roundTripManagerStatusDetectsManagedHooks() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("zcode-hooks-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let sourceBinaryURL = directory.appendingPathComponent("OpenIslandHooks-source")
        try Data("#!/bin/sh\n".utf8).write(to: sourceBinaryURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sourceBinaryURL.path)

        let managedBinaryURL = directory.appendingPathComponent("managed/OpenIslandHooks")
        let manager = ZCodeHookInstallationManager(
            zcodeDirectory: directory,
            managedHooksBinaryURL: managedBinaryURL,
            fileManager: fileManager
        )

        let afterInstall = try manager.install(hooksBinaryURL: sourceBinaryURL)
        #expect(afterInstall.managedHooksPresent)
        #expect(afterInstall.currentFormatHooksPresent)
        #expect(afterInstall.manifest != nil)
        #expect(afterInstall.manifest?.hooksEnabledBeforeInstall == nil)

        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: ZCodeHooksTests.configURL(in: directory))) as? [String: Any]
        let hooks = try #require(config?["hooks"] as? [String: Any])
        #expect(hooks["enabled"] as? Bool == true)

        let afterUninstall = try manager.uninstall()
        #expect(!afterUninstall.managedHooksPresent)
        #expect(!afterUninstall.currentFormatHooksPresent)
        #expect(afterUninstall.manifest == nil)
    }

    private static func configURL(in directory: URL) -> URL {
        directory.appendingPathComponent("config.json")
    }
}
