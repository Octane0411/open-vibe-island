import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeUsageTests {
    @Test
    func fileChangeMonitorDeliversWritesWithoutContentPolling() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-file-monitor-\(UUID().uuidString)", isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("usage.json")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let signal = LockedSignal()
        let monitor = FileChangeMonitor(
            urls: [fileURL],
            queueLabel: "app.openisland.tests.file-monitor"
        ) { changedURL in
            if changedURL == fileURL {
                signal.fire()
            }
        }
        monitor.start()

        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()

        for _ in 0..<50 where !signal.didFire {
            try await Task.sleep(for: .milliseconds(20))
        }
        monitor.stop()

        #expect(signal.didFire)
    }

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
    func claudeStatusLineInstallationManagerWrapsExistingCustomStatusLine() throws {
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
            .appendingPathComponent("open-island-claude-fallback-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".open-island", isDirectory: true)
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

    // MARK: - Issue #671: wrapper must never wrap itself

    private struct StatusLineFixture {
        let rootURL: URL
        let claudeDirectory: URL
        let scriptDirectory: URL
        let settingsURL: URL
        let manager: ClaudeStatusLineInstallationManager

        var scriptURL: URL {
            scriptDirectory.appendingPathComponent(ClaudeStatusLineInstallationManager.managedScriptName)
        }

        var delegateURL: URL {
            scriptDirectory.appendingPathComponent(ClaudeStatusLineInstallationManager.wrappedDelegateScriptName)
        }

        init(_ name: String) throws {
            rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("open-island-claude-\(name)-\(UUID().uuidString)", isDirectory: true)
            claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
            scriptDirectory = rootURL
                .appendingPathComponent(".open-island", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
            settingsURL = claudeDirectory.appendingPathComponent("settings.json")
            manager = ClaudeStatusLineInstallationManager(
                claudeDirectory: claudeDirectory,
                scriptDirectoryURL: scriptDirectory
            )
            try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        }

        func writeSettings(_ settings: [String: Any]) throws {
            try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
                .write(to: settingsURL, options: .atomic)
        }

        func readSettings() throws -> [String: Any] {
            try jsonObject(from: Data(contentsOf: settingsURL))
        }

        /// Reproduces the on-disk state from issue #671: the live statusLine is our wrapper,
        /// the "original" backup is our wrapper spelled with `$HOME`, and the delegate script
        /// runs the wrapper — so every status-line refresh spawns an endless chain.
        func writePoisonedWrapper() throws {
            try writeSettings([
                "statusLine": ["type": "command", "command": scriptURL.path, "padding": 2],
                openIslandOriginalStatusLineKey: [
                    "type": "command",
                    "command": "$HOME/.open-island/bin/open-island-statusline",
                    "padding": 2,
                ],
            ])
            try ClaudeStatusLineInstallationManager
                .wrappedScript(cacheURL: rootURL.appendingPathComponent("rl.json"), delegateScriptURL: delegateURL)
                .write(to: scriptURL, atomically: true, encoding: .utf8)
            try ClaudeStatusLineInstallationManager
                .wrappedDelegateScript(originalCommand: "$HOME/.open-island/bin/open-island-statusline")
                .write(to: delegateURL, atomically: true, encoding: .utf8)
            for url in [scriptURL, delegateURL] {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }
    }

    @Test(arguments: [
        "$HOME/.open-island/bin/open-island-statusline",
        "${HOME}/.open-island/bin/open-island-statusline",
        "~/.open-island/bin/open-island-statusline",
        "bash \"$HOME/.open-island/bin/open-island-statusline\"",
        "/opt/homebrew/bin/bash ~/.vibe-island/bin/vibe-island-statusline",
    ])
    func claudeStatusLineRecognizesOwnScriptHoweverItIsSpelled(command: String) throws {
        let fixture = try StatusLineFixture("spelling")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try fixture.writeSettings(["statusLine": ["type": "command", "command": command]])

        let status = try fixture.manager.status()
        #expect(fixture.manager.isManagedStatusLineCommand(command))
        #expect(status.managedStatusLineConfigured)
        #expect(!status.hasConflictingStatusLine)

        // The pre-#671 failure: a home-relative spelling of our own script was treated as the
        // user's command and wrapped, so the delegate ended up calling the wrapper.
        #expect(throws: ClaudeStatusLineInstallationError.self) {
            try fixture.manager.installAsWrapper()
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.delegateURL.path))
        #expect(try fixture.readSettings()[openIslandOriginalStatusLineKey] == nil)
    }

    @Test
    func claudeStatusLineDoesNotMistakeUserCommandsForOwnScript() throws {
        let fixture = try StatusLineFixture("user-command")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        for command in ["/usr/local/bin/claude-hud", "~/.claude/statusline-command.sh", "bun run ccstatusline"] {
            #expect(!fixture.manager.isManagedStatusLineCommand(command), "\(command)")
        }
        #expect(!fixture.manager.isManagedStatusLineCommand(nil))
        #expect(!fixture.manager.isManagedStatusLineCommand(""))
    }

    @Test
    func claudeStatusLineInstallRepairsPoisonedWrapper() throws {
        let fixture = try StatusLineFixture("poisoned")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writePoisonedWrapper()

        let before = try fixture.manager.status()
        #expect(before.managedStatusLineIsWrapper)
        #expect(before.managedStatusLineIsPoisoned)
        #expect(before.managedStatusLineNeedsRepair)

        // This is the path HookInstallationCoordinator takes when it sees needsRepair.
        let repaired = try fixture.manager.install()
        #expect(repaired.managedStatusLineInstalled)
        #expect(!repaired.managedStatusLineIsWrapper)
        #expect(!repaired.managedStatusLineIsPoisoned)
        #expect(!repaired.managedStatusLineNeedsRepair)
        #expect(!FileManager.default.fileExists(atPath: fixture.delegateURL.path))

        let settings = try fixture.readSettings()
        #expect(settings[openIslandOriginalStatusLineKey] == nil)
        #expect((settings["statusLine"] as? [String: Any])?["command"] as? String == fixture.scriptURL.path)

        let script = try String(contentsOf: fixture.scriptURL, encoding: .utf8)
        #expect(!script.contains(fixture.delegateURL.path))
        #expect(script.contains("rate_limits"))
    }

    @Test
    func claudeStatusLineUninstallDoesNotRestorePoisonedOriginal() throws {
        let fixture = try StatusLineFixture("poisoned-uninstall")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writePoisonedWrapper()

        let uninstalled = try fixture.manager.uninstall()
        #expect(!uninstalled.managedStatusLineInstalled)
        #expect(!uninstalled.hasStatusLine)

        let settings = try fixture.readSettings()
        #expect(settings["statusLine"] == nil)
        #expect(settings[openIslandOriginalStatusLineKey] == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.scriptURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.delegateURL.path))
    }

    @Test
    func claudeStatusLineInstallRebuildsHealthyWrapperInsteadOfOrphaningIt() throws {
        let fixture = try StatusLineFixture("wrapper-repair")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let originalCommand = "/usr/local/bin/custom-status --flag"
        try fixture.writeSettings(["statusLine": ["type": "command", "command": originalCommand]])
        let wrapped = try fixture.manager.installAsWrapper()
        #expect(wrapped.managedStatusLineIsWrapper)
        #expect(!wrapped.managedStatusLineIsPoisoned)

        // Simulate a lost script (the case that triggers needsRepair → install()).
        try FileManager.default.removeItem(at: fixture.scriptURL)
        #expect(try fixture.manager.status().managedStatusLineNeedsRepair)

        let repaired = try fixture.manager.install()
        #expect(repaired.managedStatusLineInstalled)
        #expect(repaired.managedStatusLineIsWrapper)
        #expect(!repaired.managedStatusLineNeedsRepair)

        let script = try String(contentsOf: fixture.scriptURL, encoding: .utf8)
        #expect(script.contains(fixture.delegateURL.path))
        let delegate = try String(contentsOf: fixture.delegateURL, encoding: .utf8)
        #expect(delegate.contains(originalCommand))
        let saved = try fixture.readSettings()[openIslandOriginalStatusLineKey] as? [String: Any]
        #expect(saved?["command"] as? String == originalCommand)
    }

    @Test
    func claudeStatusLineWrapperScriptStopsReentrantSpawn() throws {
        // Even with the corrupted files from issue #671 on disk, running the wrapper must
        // terminate instead of forking wrapper → delegate → wrapper forever.
        let fixture = try StatusLineFixture("reentry")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try fixture.writePoisonedWrapper()
        // Point the delegate at the *real* wrapper path so the loop would actually run.
        try ClaudeStatusLineInstallationManager
            .wrappedDelegateScript(originalCommand: "\"\(fixture.scriptURL.path)\"")
            .write(to: fixture.delegateURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [fixture.scriptURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "OPEN_ISLAND_STATUSLINE_ACTIVE")
        process.environment = environment
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        stdin.fileHandleForWriting.write(Data("{}".utf8))
        try stdin.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            Issue.record("wrapper did not terminate: re-entry guard is not working")
        }
        #expect(process.terminationStatus == 0)
    }
}

private final class LockedSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    var didFire: Bool {
        lock.withLock { fired }
    }

    func fire() {
        lock.withLock { fired = true }
    }
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}
