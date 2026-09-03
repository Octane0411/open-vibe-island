import Foundation
import Testing
@testable import OpenIslandCore

struct HookHealthCheckTests {
    /// Creates a temp `.claude` directory containing `settings.json` with the
    /// given hook commands, plus an executable stand-in for the hooks binary.
    private func makeClaudeFixture(
        commands: [String],
        root: URL
    ) throws -> (claudeDirectory: URL, hooksBinaryURL: URL) {
        let claudeDirectory = root.appendingPathComponent(".claude", isDirectory: true)
        let hooksBinaryURL = root
            .appendingPathComponent("managed", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")

        try FileManager.default.createDirectory(at: hooksBinaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hook".utf8).write(to: hooksBinaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hooksBinaryURL.path)

        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let groups = commands.map { ["hooks": [["type": "command", "command": $0]]] }
        let settings: [String: Any] = ["hooks": ["SessionStart": groups]]
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            .write(to: claudeDirectory.appendingPathComponent("settings.json"), options: .atomic)

        return (claudeDirectory, hooksBinaryURL)
    }

    /// A unique, unused scratch directory. Not created here — the fixture
    /// helpers create what they need under it, and each test removes the whole
    /// tree in a `defer`.
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-health-\(UUID().uuidString)", isDirectory: true)
    }

    /// Whether the report carries a `hooksMissing` issue, ignoring its path.
    /// Several tests assert only on presence or absence.
    private func reportsHooksMissing(_ report: HookHealthReport) -> Bool {
        report.issues.contains(where: { issue in
            if case .hooksMissing = issue { return true }
            return false
        })
    }

    /// The regression this PR fixes: a leftover hook from the closed-source app
    /// occupies the config, ours are gone, and the user did ask for ours. That
    /// has to surface as a repairable error rather than a clean bill of health.
    @Test
    func claudeHealthReportsHooksMissingWhenUserAskedForThemAndOnlyForeignHooksRemain() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = try makeClaudeFixture(
            commands: ["/bin/sh -c '\"$HOME/.vibe-island/bin/vibe-island-bridge\" --source claude'"],
            root: root
        )

        let report = HookHealthCheck.checkClaude(
            claudeDirectory: fixture.claudeDirectory,
            hooksBinaryURL: fixture.hooksBinaryURL,
            expectsInstalledHooks: true
        )

        let settingsPath = fixture.claudeDirectory.appendingPathComponent("settings.json").path
        #expect(report.issues.contains(.hooksMissing(configPath: settingsPath)))
        #expect(!report.isHealthy)
        #expect(report.repairableIssues.contains(.hooksMissing(configPath: settingsPath)))
    }

    /// The user turned these hooks off on purpose — an empty config is correct,
    /// and reporting it would let auto-repair reinstall them behind their back.
    @Test
    func claudeHealthStaysQuietAboutMissingHooksWhenUserDidNotAskForThem() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = try makeClaudeFixture(
            commands: ["/usr/local/bin/some-other-tool --hook"],
            root: root
        )

        let report = HookHealthCheck.checkClaude(
            claudeDirectory: fixture.claudeDirectory,
            hooksBinaryURL: fixture.hooksBinaryURL,
            expectsInstalledHooks: false
        )

        #expect(!reportsHooksMissing(report))
        #expect(report.isHealthy)
    }

    /// The healthy case, guarding against a check that fires unconditionally.
    @Test
    func claudeHealthDoesNotReportHooksMissingWhenOurHooksArePresent() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = try makeClaudeFixture(
            commands: ["'/Applications/Open Island.app/Contents/Helpers/OpenIslandHooks' --source claude"],
            root: root
        )

        let report = HookHealthCheck.checkClaude(
            claudeDirectory: fixture.claudeDirectory,
            hooksBinaryURL: fixture.hooksBinaryURL,
            expectsInstalledHooks: true
        )

        #expect(!reportsHooksMissing(report))
    }

    /// Malformed JSON already has its own issue, and re-installing over a file
    /// we cannot parse would not fix anything.
    @Test
    func claudeHealthPrefersMalformedJSONOverHooksMissing() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let claudeDirectory = root.appendingPathComponent(".claude", isDirectory: true)
        let hooksBinaryURL = root
            .appendingPathComponent("managed", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")
        try FileManager.default.createDirectory(at: hooksBinaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hook".utf8).write(to: hooksBinaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hooksBinaryURL.path)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data("{ not json".utf8).write(to: settingsURL, options: .atomic)

        let report = HookHealthCheck.checkClaude(
            claudeDirectory: claudeDirectory,
            hooksBinaryURL: hooksBinaryURL,
            expectsInstalledHooks: true
        )

        #expect(report.issues.contains(.configMalformedJSON(path: settingsURL.path)))
        #expect(!reportsHooksMissing(report))
    }

    /// Codex reaches the same conclusion through a different config file, so it
    /// gets its own case rather than relying on the Claude path's coverage.
    @Test
    func codexHealthReportsHooksMissingWhenUserAskedForThem() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let codexDirectory = root.appendingPathComponent(".codex", isDirectory: true)
        let hooksBinaryURL = root
            .appendingPathComponent("managed", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")
        try FileManager.default.createDirectory(at: hooksBinaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("hook".utf8).write(to: hooksBinaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hooksBinaryURL.path)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)

        let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        let hooks: [String: Any] = [
            "hooks": ["SessionStart": [["hooks": [["type": "command", "command": "/usr/local/bin/other --hook"]]]]],
        ]
        try JSONSerialization.data(withJSONObject: hooks, options: [.prettyPrinted, .sortedKeys])
            .write(to: hooksURL, options: .atomic)

        let report = HookHealthCheck.checkCodex(
            codexDirectory: codexDirectory,
            hooksBinaryURL: hooksBinaryURL,
            expectsInstalledHooks: true
        )

        #expect(report.issues.contains(.hooksMissing(configPath: hooksURL.path)))
    }
}
