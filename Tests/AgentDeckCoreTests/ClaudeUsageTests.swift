import Foundation
import Testing
@testable import AgentDeckCore

struct ClaudeUsageTests {
    @Test
    func claudeUsageLoaderParsesCachedRateLimits() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-deck-claude-usage-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("agent-deck-rl.json")

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
            .appendingPathComponent("agent-deck-claude-usage-iso-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("agent-deck-rl.json")

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
            .appendingPathComponent("agent-deck-claude-usage-candidates-\(UUID().uuidString)", isDirectory: true)
        let currentCacheURL = rootURL.appendingPathComponent("agent-deck-rl.json")
        let legacyCacheURL = rootURL.appendingPathComponent("agent-deck-rl.json")

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
            .appendingPathComponent("agent-deck-claude-status-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".agent-deck", isDirectory: true)
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
            .appendingPathComponent("agent-deck-claude-repair-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".agent-deck", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let legacyScriptDirectory = rootURL
            .appendingPathComponent(".agent-deck", isDirectory: true)
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
            .appendingPathComponent("agent-deck-claude-uninstall-broken-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".agent-deck", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let legacyScriptDirectory = rootURL
            .appendingPathComponent(".agent-deck", isDirectory: true)
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
            .appendingPathComponent("agent-deck-claude-conflict-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".agent-deck", isDirectory: true)
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
    func claudeStatusLineInstallationManagerWrapsExistingCustomStatusLine() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-deck-claude-wrap-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".agent-deck", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let manager = ClaudeStatusLineInstallationManager(
            claudeDirectory: claudeDirectory,
            scriptDirectoryURL: scriptDirectory
        )
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let originalCommand = "/usr/local/bin/custom-status --flag"
        let originalStatusLine: [String: Any] = [
            "type": "command",
            "command": originalCommand,
            "padding": 0,
        ]

        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try JSONSerialization.data(
            withJSONObject: [
                "theme": "dark",
                "statusLine": originalStatusLine,
            ],
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: settingsURL, options: .atomic)

        let wrapped = try manager.installAsWrapper()

        #expect(wrapped.managedStatusLineInstalled)
        #expect(wrapped.managedStatusLineIsWrapper)
        #expect(wrapped.statusLineCommand == wrapped.scriptURL.path)

        let delegateURL = scriptDirectory
            .appendingPathComponent(ClaudeStatusLineInstallationManager.wrappedDelegateScriptName)
        #expect(FileManager.default.fileExists(atPath: wrapped.scriptURL.path))
        #expect(FileManager.default.fileExists(atPath: delegateURL.path))

        let wrapperContents = try String(contentsOf: wrapped.scriptURL, encoding: .utf8)
        #expect(wrapperContents.contains(wrapped.cacheURL.path))
        #expect(wrapperContents.contains(delegateURL.path))

        let delegateContents = try String(contentsOf: delegateURL, encoding: .utf8)
        #expect(delegateContents.contains(originalCommand))

        let settingsAfterInstall = try jsonObject(from: Data(contentsOf: settingsURL))
        let savedOriginal = settingsAfterInstall[openIslandOriginalStatusLineKey] as? [String: Any]
        #expect(savedOriginal?["command"] as? String == originalCommand)
        #expect((settingsAfterInstall["statusLine"] as? [String: Any])?["command"] as? String == wrapped.scriptURL.path)

        let uninstalled = try manager.uninstall()
        #expect(!uninstalled.managedStatusLineInstalled)
        #expect(!uninstalled.managedStatusLineIsWrapper)
        #expect(!FileManager.default.fileExists(atPath: wrapped.scriptURL.path))
        #expect(!FileManager.default.fileExists(atPath: delegateURL.path))

        let settingsAfterUninstall = try jsonObject(from: Data(contentsOf: settingsURL))
        #expect(settingsAfterUninstall[openIslandOriginalStatusLineKey] == nil)
        let restored = settingsAfterUninstall["statusLine"] as? [String: Any]
        #expect(restored?["command"] as? String == originalCommand)
        #expect(restored?["padding"] as? Int == 0)
    }

    @Test
    func claudeStatusLineInstallAutoFallsBackToWrapperViaHandler() throws {
        // Simulates HookInstallationCoordinator's catch-and-fall-back behavior.
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-deck-claude-fallback-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".agent-deck", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let manager = ClaudeStatusLineInstallationManager(
            claudeDirectory: claudeDirectory,
            scriptDirectoryURL: scriptDirectory
        )
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")

        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try JSONSerialization.data(
            withJSONObject: [
                "statusLine": ["type": "command", "command": "/usr/local/bin/custom-status"],
            ],
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: settingsURL, options: .atomic)

        let finalStatus: ClaudeStatusLineInstallationStatus
        do {
            finalStatus = try manager.install()
        } catch ClaudeStatusLineInstallationError.existingStatusLineConflict {
            finalStatus = try manager.installAsWrapper()
        }

        #expect(finalStatus.managedStatusLineIsWrapper)
        #expect(finalStatus.managedStatusLineInstalled)
    }
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}
