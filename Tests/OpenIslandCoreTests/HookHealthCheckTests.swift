import Foundation
import Testing
@testable import OpenIslandCore

struct HookHealthCheckTests {
    // MARK: - Claude

    @Test
    func claudeReportsNotInstalledWhenConfigHasOnlyThirdPartyHooks() throws {
        let env = try TempEnv()
        defer { env.cleanup() }

        try env.writeBinary("OpenIslandHooks", at: env.binaryURL)
        try env.writeJSON([
            "hooks": [
                "Stop": [
                    [
                        "hooks": [
                            ["type": "command", "command": "$HOME/.vibe-island/bin/vibe-island-bridge --source claude"],
                        ],
                    ],
                ],
            ],
        ], at: env.claudeSettingsURL)

        let report = HookHealthCheck.checkClaude(
            claudeDirectory: env.claudeDirURL,
            hooksBinaryURL: env.binaryURL,
            managedHooksBinaryURL: env.binaryURL
        )

        #expect(report.errors.contains { issue in
            if case .notInstalled = issue { return true }
            return false
        })
        #expect(!report.isHealthy)
    }

    @Test
    func claudeReportsNotInstalledWhenSettingsMissingButDirExists() throws {
        let env = try TempEnv()
        defer { env.cleanup() }

        try env.writeBinary("OpenIslandHooks", at: env.binaryURL)
        // Create only the .claude directory, no settings.json.

        let report = HookHealthCheck.checkClaude(
            claudeDirectory: env.claudeDirURL,
            hooksBinaryURL: env.binaryURL,
            managedHooksBinaryURL: env.binaryURL
        )

        #expect(report.errors.contains { issue in
            if case .notInstalled = issue { return true }
            return false
        })
    }

    @Test
    func claudeIsHealthyWhenOpenIslandHooksPresent() throws {
        let env = try TempEnv()
        defer { env.cleanup() }

        try env.writeBinary("OpenIslandHooks", at: env.binaryURL)
        try env.writeJSON([
            "hooks": [
                "Stop": [
                    [
                        "hooks": [
                            ["type": "command", "command": "'\(env.binaryURL.path)' --source claude"],
                        ],
                    ],
                ],
            ],
        ], at: env.claudeSettingsURL)
        // A manifest must exist or a .manifestMissing issue would fire — but
        // that's not the focus of this test, so write a minimal one.
        try env.writeJSON(["version": 1], at: env.claudeManifestURL)

        let report = HookHealthCheck.checkClaude(
            claudeDirectory: env.claudeDirURL,
            hooksBinaryURL: env.binaryURL,
            managedHooksBinaryURL: env.binaryURL
        )

        #expect(report.isHealthy, "Expected healthy report; got issues: \(report.issues)")
        #expect(!report.errors.contains { issue in
            if case .notInstalled = issue { return true }
            return false
        })
    }

    @Test
    func claudeSkipsNotInstalledWhenConfigDirAbsent() throws {
        let env = try TempEnv(createConfigDirs: false)
        defer { env.cleanup() }

        try env.writeBinary("OpenIslandHooks", at: env.binaryURL)

        let report = HookHealthCheck.checkClaude(
            claudeDirectory: env.claudeDirURL,
            hooksBinaryURL: env.binaryURL,
            managedHooksBinaryURL: env.binaryURL
        )

        #expect(!report.errors.contains { issue in
            if case .notInstalled = issue { return true }
            return false
        }, "Should not nag users who aren't running Claude Code at all")
    }

    @Test
    func claudeSkipsNotInstalledWhenConfigMalformed() throws {
        let env = try TempEnv()
        defer { env.cleanup() }

        try env.writeBinary("OpenIslandHooks", at: env.binaryURL)
        try Data("{ this is not json".utf8).write(to: env.claudeSettingsURL)

        let report = HookHealthCheck.checkClaude(
            claudeDirectory: env.claudeDirURL,
            hooksBinaryURL: env.binaryURL,
            managedHooksBinaryURL: env.binaryURL
        )

        #expect(report.errors.contains { issue in
            if case .configMalformedJSON = issue { return true }
            return false
        })
        // Don't pile on a confusing notInstalled when we couldn't even parse the file.
        #expect(!report.errors.contains { issue in
            if case .notInstalled = issue { return true }
            return false
        })
    }

    // MARK: - Codex

    @Test
    func codexReportsNotInstalledWhenConfigDirExistsWithoutOurHooks() throws {
        let env = try TempEnv()
        defer { env.cleanup() }

        try env.writeBinary("OpenIslandHooks", at: env.binaryURL)
        try env.writeJSON([
            "hooks": [
                "Stop": [
                    [
                        "hooks": [
                            ["type": "command", "command": "/some/other/binary"],
                        ],
                    ],
                ],
            ],
        ], at: env.codexHooksURL)

        let report = HookHealthCheck.checkCodex(
            codexDirectory: env.codexDirURL,
            hooksBinaryURL: env.binaryURL,
            managedHooksBinaryURL: env.binaryURL
        )

        #expect(report.errors.contains { issue in
            if case .notInstalled = issue { return true }
            return false
        })
    }

    // MARK: - Issue properties

    @Test
    func notInstalledIssueIsErrorAndAutoRepairable() {
        let issue = HookHealthReport.Issue.notInstalled(configPath: "/x/y")
        #expect(issue.severity == .error)
        #expect(issue.isAutoRepairable)
    }
}

// MARK: - Test fixtures

private struct TempEnv {
    let rootURL: URL
    let claudeDirURL: URL
    let codexDirURL: URL
    let binaryURL: URL

    var claudeSettingsURL: URL { claudeDirURL.appendingPathComponent("settings.json") }
    var claudeManifestURL: URL { claudeDirURL.appendingPathComponent(ClaudeHookInstallerManifest.fileName) }
    var codexHooksURL: URL { codexDirURL.appendingPathComponent("hooks.json") }

    init(createConfigDirs: Bool = true) throws {
        let fm = FileManager.default
        rootURL = fm.temporaryDirectory.appendingPathComponent("OpenIslandHookHealthCheckTests-\(UUID().uuidString)", isDirectory: true)
        claudeDirURL = rootURL.appendingPathComponent(".claude", isDirectory: true)
        codexDirURL = rootURL.appendingPathComponent(".codex", isDirectory: true)
        binaryURL = rootURL.appendingPathComponent("bin/OpenIslandHooks")

        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: binaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if createConfigDirs {
            try fm.createDirectory(at: claudeDirURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: codexDirURL, withIntermediateDirectories: true)
        }
    }

    func writeBinary(_ name: String, at url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func writeJSON(_ object: Any, at url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        try data.write(to: url)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
