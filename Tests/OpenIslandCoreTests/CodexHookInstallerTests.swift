import Foundation
import Testing
@testable import OpenIslandCore

/// Pins `CodexHookInstaller` behavior across the two install modes, since
/// the event set and per-event timeouts it writes directly determine
/// whether Codex will block on Open Island for PreToolUse approvals.
struct CodexHookInstallerTests {
    private static let hookCommand = "'/tmp/oi/OpenIslandHooks'"

    // MARK: - Event set per mode

    @Test
    func notifyOnlyRegistersHistoricalEventsOnly() throws {
        let mutation = try CodexHookInstaller.installHooksJSON(
            existingData: nil,
            hookCommand: Self.hookCommand,
            mode: .notifyOnly
        )

        let hooks = try hooksObject(from: mutation)

        #expect(Set(hooks.keys) == ["SessionStart", "UserPromptSubmit", "Stop"])
        for entry in try managedEntries(in: hooks) {
            #expect(entry["timeout"] as? Int == CodexHookInstaller.managedTimeout)
        }
    }

    @Test
    func fullControlAddsPreAndPostToolUse() throws {
        let mutation = try CodexHookInstaller.installHooksJSON(
            existingData: nil,
            hookCommand: Self.hookCommand,
            mode: .fullControl
        )

        let hooks = try hooksObject(from: mutation)

        #expect(Set(hooks.keys) == [
            "SessionStart", "UserPromptSubmit", "Stop",
            "PreToolUse", "PostToolUse",
        ])

        let preToolUseEntry = try singleManagedEntry(in: hooks, event: "PreToolUse")
        // PreToolUse blocks Codex on the user's approval decision; Codex
        // sigkills the hook at this timeout, so 1h is intentional.
        #expect(preToolUseEntry["timeout"] as? Int == CodexHookInstaller.managedPreToolUseTimeout)

        let postToolUseEntry = try singleManagedEntry(in: hooks, event: "PostToolUse")
        #expect(postToolUseEntry["timeout"] as? Int == CodexHookInstaller.managedTimeout)
    }

    // MARK: - Mode switching

    @Test
    func switchingFullControlToNotifyOnlyDropsPreAndPostToolUse() throws {
        let initial = try CodexHookInstaller.installHooksJSON(
            existingData: nil,
            hookCommand: Self.hookCommand,
            mode: .fullControl
        )

        let downgraded = try CodexHookInstaller.installHooksJSON(
            existingData: initial.contents,
            hookCommand: Self.hookCommand,
            mode: .notifyOnly
        )

        let hooks = try hooksObject(from: downgraded)
        #expect(Set(hooks.keys) == ["SessionStart", "UserPromptSubmit", "Stop"])
    }

    @Test
    func switchingNotifyOnlyToFullControlAddsPreAndPostToolUse() throws {
        let initial = try CodexHookInstaller.installHooksJSON(
            existingData: nil,
            hookCommand: Self.hookCommand,
            mode: .notifyOnly
        )

        let upgraded = try CodexHookInstaller.installHooksJSON(
            existingData: initial.contents,
            hookCommand: Self.hookCommand,
            mode: .fullControl
        )

        let hooks = try hooksObject(from: upgraded)
        #expect(hooks["PreToolUse"] != nil)
        #expect(hooks["PostToolUse"] != nil)
        // SessionStart/etc must survive the upgrade with exactly one
        // managed entry (not duplicated from the initial install).
        for event in ["SessionStart", "UserPromptSubmit", "Stop"] {
            let managed = try managedHooks(in: hooks, event: event, command: Self.hookCommand)
            #expect(managed.count == 1)
        }
    }

    @Test
    func repeatedInstallAtSameModeIsIdempotent() throws {
        let first = try CodexHookInstaller.installHooksJSON(
            existingData: nil,
            hookCommand: Self.hookCommand,
            mode: .fullControl
        )
        let second = try CodexHookInstaller.installHooksJSON(
            existingData: first.contents,
            hookCommand: Self.hookCommand,
            mode: .fullControl
        )

        #expect(first.contents == second.contents)
        #expect(second.changed == false)
    }

    // MARK: - Uninstall covers all modes

    @Test
    func uninstallRemovesEntriesWrittenByFullControlEvenIfCurrentlyNotifyOnly() throws {
        // Simulate a user that installed under fullControl, then we
        // pretend the preference was rolled back to notifyOnly on disk
        // (e.g., previous manifest lost). Uninstall must still clean
        // PreToolUse/PostToolUse — the enumeration is mode-agnostic.
        let installed = try CodexHookInstaller.installHooksJSON(
            existingData: nil,
            hookCommand: Self.hookCommand,
            mode: .fullControl
        )

        let uninstalled = try CodexHookInstaller.uninstallHooksJSON(
            existingData: installed.contents,
            managedCommand: Self.hookCommand
        )

        // The whole hooks.json gets removed because nothing is left.
        #expect(uninstalled.contents == nil)
        #expect(uninstalled.hasRemainingHooks == false)
    }

    @Test
    func uninstallPreservesUnrelatedHooks() throws {
        let otherHook: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": "/opt/other-tool/hook",
                "timeout": 30,
            ]]
        ]
        let seed: [String: Any] = [
            "hooks": [
                "PreToolUse": [otherHook],
            ]
        ]
        let seedData = try JSONSerialization.data(withJSONObject: seed)

        let installed = try CodexHookInstaller.installHooksJSON(
            existingData: seedData,
            hookCommand: Self.hookCommand,
            mode: .fullControl
        )

        let uninstalled = try CodexHookInstaller.uninstallHooksJSON(
            existingData: installed.contents,
            managedCommand: Self.hookCommand
        )

        let hooks = try hooksObject(from: uninstalled)
        // The other tool's PreToolUse entry must survive both install
        // and uninstall.
        #expect(hooks["PreToolUse"] != nil)
    }

    // MARK: - Manifest mode

    @Test
    func manifestDefaultsToNotifyOnlyWhenDecodingLegacyPayload() throws {
        // A manifest serialized before this feature shipped has no
        // `installMode` field. It must decode and report
        // `.notifyOnly` via `effectiveInstallMode`.
        let legacyJSON = """
        {
            "hookCommand": "'/tmp/oi/OpenIslandHooks'",
            "enabledCodexHooksFeature": true,
            "installedAt": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(CodexHookInstallerManifest.self, from: legacyJSON)

        #expect(manifest.installMode == nil)
        #expect(manifest.effectiveInstallMode == .notifyOnly)
    }

    // MARK: - Helpers

    private func hooksObject(from mutation: CodexHookFileMutation) throws -> [String: Any] {
        let data = try #require(mutation.contents)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(root?["hooks"] as? [String: Any])
    }

    private func managedEntries(in hooks: [String: Any]) throws -> [[String: Any]] {
        var collected: [[String: Any]] = []
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                let inner = (group["hooks"] as? [[String: Any]]) ?? []
                for entry in inner where (entry["command"] as? String) == Self.hookCommand {
                    collected.append(entry)
                }
            }
        }
        return collected
    }

    private func managedHooks(in hooks: [String: Any], event: String, command: String) throws -> [[String: Any]] {
        let groups = (hooks[event] as? [[String: Any]]) ?? []
        return groups.flatMap { group -> [[String: Any]] in
            let inner = (group["hooks"] as? [[String: Any]]) ?? []
            return inner.filter { ($0["command"] as? String) == command }
        }
    }

    private func singleManagedEntry(in hooks: [String: Any], event: String) throws -> [String: Any] {
        let managed = try managedHooks(in: hooks, event: event, command: Self.hookCommand)
        #expect(managed.count == 1)
        return try #require(managed.first)
    }
}
