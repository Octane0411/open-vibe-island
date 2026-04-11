import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeUsageTests {
    @Test
    func claudeUsageLoaderParsesCachedRateLimits() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-usage-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("open-island-rl.json")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let payload = """
        {
          "five_hour": {
            "used_percentage": 42,
            "resets_at": 1760000000
          },
          "seven_day": {
            "used_percentage": 17.5,
            "resets_at": 1760500000
          }
        }
        """
        try payload.write(to: cacheURL, atomically: true, encoding: .utf8)

        let snapshot = try ClaudeUsageLoader.load(from: cacheURL)

        #expect(snapshot?.fiveHour?.roundedUsedPercentage == 42)
        #expect(snapshot?.sevenDay?.roundedUsedPercentage == 18)
        #expect(snapshot?.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(snapshot?.cachedAt != nil)
    }

    @Test
    func claudeUsageLoaderParsesUtilizationPayloadWithISO8601ResetDates() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-usage-iso-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("open-island-rl.json")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let payload = """
        {
          "five_hour": {
            "utilization": 0,
            "resets_at": null
          },
          "seven_day": {
            "utilization": 23,
            "resets_at": "2026-02-09T12:00:00.462679+00:00"
          }
        }
        """
        try payload.write(to: cacheURL, atomically: true, encoding: .utf8)

        let snapshot = try ClaudeUsageLoader.load(from: cacheURL)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        #expect(snapshot?.fiveHour?.roundedUsedPercentage == 0)
        #expect(snapshot?.fiveHour?.resetsAt == nil)
        #expect(snapshot?.sevenDay?.roundedUsedPercentage == 23)
        #expect(snapshot?.sevenDay?.resetsAt == formatter.date(from: "2026-02-09T12:00:00.462679+00:00"))
    }

    @Test
    func claudeUsageLoaderPrefersMostRecentLegacyOrCurrentCache() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-usage-candidates-\(UUID().uuidString)", isDirectory: true)
        let currentCacheURL = rootURL.appendingPathComponent("open-island-rl.json")
        let legacyCacheURL = rootURL.appendingPathComponent("vibe-island-rl.json")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        {
          "five_hour": {
            "used_percentage": 11,
            "resets_at": 1760000000
          }
        }
        """.write(to: legacyCacheURL, atomically: true, encoding: .utf8)
        try """
        {
          "five_hour": {
            "used_percentage": 77,
            "resets_at": 1760000100
          }
        }
        """.write(to: currentCacheURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_760_000_100)],
            ofItemAtPath: legacyCacheURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_760_000_200)],
            ofItemAtPath: currentCacheURL.path
        )

        let snapshot = try ClaudeUsageLoader.load(from: [legacyCacheURL, currentCacheURL])

        #expect(snapshot?.fiveHour?.roundedUsedPercentage == 77)
    }

    @Test
    func claudeStatusLineInstallationManagerInstallsManagedScriptWithoutOverwritingCustomCommand() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-status-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".open-island", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let manager = ClaudeStatusLineInstallationManager(
            claudeDirectory: claudeDirectory,
            scriptDirectoryURL: scriptDirectory
        )

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let installed = try manager.install()

        #expect(installed.managedStatusLineInstalled)
        #expect(installed.statusLineCommand == installed.scriptURL.path)
        #expect(FileManager.default.fileExists(atPath: installed.scriptURL.path))

        let settingsObject = try jsonObject(from: Data(contentsOf: installed.settingsURL))
        let statusLine = settingsObject["statusLine"] as? [String: Any]
        #expect(statusLine?["command"] as? String == installed.scriptURL.path)
        #expect(statusLine?["type"] as? String == "command")

        let scriptContents = try String(contentsOf: installed.scriptURL, encoding: .utf8)
        #expect(scriptContents.contains(installed.cacheURL.path))
        #expect(scriptContents.contains(".rate_limits // empty"))

        let uninstalled = try manager.uninstall()
        #expect(!uninstalled.managedStatusLineInstalled)
        #expect(!FileManager.default.fileExists(atPath: installed.scriptURL.path))
    }

    @Test
    func claudeStatusLineInstallationManagerRepairsMissingLegacyManagedScript() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-repair-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".open-island", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let legacyScriptDirectory = rootURL
            .appendingPathComponent(".vibe-island", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let manager = ClaudeStatusLineInstallationManager(
            claudeDirectory: claudeDirectory,
            scriptDirectoryURL: scriptDirectory,
            legacyScriptDirectoryURL: legacyScriptDirectory
        )
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let legacyScriptURL = legacyScriptDirectory.appendingPathComponent(ClaudeStatusLineInstallationManager.legacyManagedScriptName)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsData = try JSONSerialization.data(
            withJSONObject: [
                "statusLine": [
                    "type": "command",
                    "command": legacyScriptURL.path,
                ],
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        try settingsData.write(to: settingsURL, options: .atomic)

        let brokenStatus = try manager.status()
        #expect(brokenStatus.managedStatusLineConfigured)
        #expect(!brokenStatus.managedStatusLineInstalled)
        #expect(brokenStatus.managedStatusLineNeedsRepair)
        #expect(!brokenStatus.hasConflictingStatusLine)

        let repairedStatus = try manager.install()
        #expect(repairedStatus.managedStatusLineConfigured)
        #expect(repairedStatus.managedStatusLineInstalled)
        #expect(!repairedStatus.managedStatusLineNeedsRepair)
        #expect(repairedStatus.statusLineCommand == repairedStatus.scriptURL.path)
        #expect(FileManager.default.fileExists(atPath: repairedStatus.scriptURL.path))
    }

    @Test
    func claudeStatusLineInstallationManagerUninstallsBrokenManagedConfiguration() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-uninstall-broken-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".open-island", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let legacyScriptDirectory = rootURL
            .appendingPathComponent(".vibe-island", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let manager = ClaudeStatusLineInstallationManager(
            claudeDirectory: claudeDirectory,
            scriptDirectoryURL: scriptDirectory,
            legacyScriptDirectoryURL: legacyScriptDirectory
        )
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let legacyScriptURL = legacyScriptDirectory.appendingPathComponent(ClaudeStatusLineInstallationManager.legacyManagedScriptName)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsData = try JSONSerialization.data(
            withJSONObject: [
                "statusLine": [
                    "type": "command",
                    "command": legacyScriptURL.path,
                ],
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        try settingsData.write(to: settingsURL, options: .atomic)

        let uninstalledStatus = try manager.uninstall()
        #expect(!uninstalledStatus.managedStatusLineConfigured)
        #expect(!uninstalledStatus.managedStatusLineInstalled)
        #expect(!uninstalledStatus.managedStatusLineNeedsRepair)
        #expect(!uninstalledStatus.hasStatusLine)
    }

    @Test
    func claudeStatusLineInstallationManagerRejectsExistingCustomStatusLine() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-conflict-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".open-island", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let manager = ClaudeStatusLineInstallationManager(
            claudeDirectory: claudeDirectory,
            scriptDirectoryURL: scriptDirectory
        )
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsData = try JSONSerialization.data(
            withJSONObject: [
                "theme": "dark",
                "statusLine": [
                    "type": "command",
                    "command": "/usr/local/bin/custom-status",
                ],
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        try settingsData.write(to: settingsURL, options: .atomic)

        let status = try manager.status()
        #expect(status.hasConflictingStatusLine)
        #expect(status.statusLineCommand == "/usr/local/bin/custom-status")

        do {
            _ = try manager.install()
            Issue.record("Expected install to reject an existing custom status line")
        } catch let error as ClaudeStatusLineInstallationError {
            switch error {
            case let .existingStatusLineConflict(command):
                #expect(command == "/usr/local/bin/custom-status")
            default:
                Issue.record("Unexpected Claude status line error: \(error)")
            }
        }
    }

    @Test
    func claudeStatusLineInstallationManagerWrapsExistingCommandOnReplace() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-wrap-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".open-island", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let manager = ClaudeStatusLineInstallationManager(
            claudeDirectory: claudeDirectory,
            scriptDirectoryURL: scriptDirectory
        )
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let originalCommand = "node ~/.claude/plugins/claude-hud/dist/index.js"
        let settingsData = try JSONSerialization.data(
            withJSONObject: [
                "theme": "dark",
                "statusLine": [
                    "type": "command",
                    "command": originalCommand,
                ],
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        try settingsData.write(to: settingsURL, options: .atomic)

        // Install with replacingExisting — should wrap the original command.
        let installed = try manager.install(replacingExisting: true)
        #expect(installed.managedStatusLineInstalled)

        // Verify the generated script contains the wrapped command marker.
        let scriptContents = try String(contentsOf: installed.scriptURL, encoding: .utf8)
        #expect(scriptContents.contains(ClaudeStatusLineInstallationManager.wrappedCommandMarker + originalCommand))
        // The script should pipe to the original command instead of using jq default output.
        #expect(scriptContents.contains("echo \"$input\" | \(originalCommand)"))
        #expect(!scriptContents.contains("jq -r"))

        // Re-install (repair) should preserve the wrapped command.
        let reinstalled = try manager.install()
        let reinstalledScript = try String(contentsOf: reinstalled.scriptURL, encoding: .utf8)
        #expect(reinstalledScript.contains(ClaudeStatusLineInstallationManager.wrappedCommandMarker + originalCommand))

        // Uninstall should restore the original command in settings.json.
        let uninstalled = try manager.uninstall()
        #expect(!uninstalled.managedStatusLineInstalled)
        #expect(!uninstalled.managedStatusLineConfigured)

        let restoredData = try Data(contentsOf: settingsURL)
        let restoredSettings = try jsonObject(from: restoredData)
        let restoredStatusLine = restoredSettings["statusLine"] as? [String: Any]
        #expect(restoredStatusLine?["command"] as? String == originalCommand)
        #expect(restoredSettings["theme"] as? String == "dark")
    }
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}
