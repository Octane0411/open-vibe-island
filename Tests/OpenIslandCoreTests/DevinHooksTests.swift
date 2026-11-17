import Foundation
import Testing
@testable import OpenIslandCore

struct DevinHooksTests {
    @Test
    func devinHookInstallationPreservesUserConfigAndHooks() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-devin-hooks-\(UUID().uuidString)", isDirectory: true)
        let devinDirectory = rootURL.appendingPathComponent(".config/devin", isDirectory: true)
        let managedHooksBinaryURL = rootURL
            .appendingPathComponent("managed", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")
        let manager = DevinHookInstallationManager(
            devinDirectory: devinDirectory,
            managedHooksBinaryURL: managedHooksBinaryURL
        )
        let hooksBinaryURL = rootURL
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("OpenIslandHooks")

        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(at: devinDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hooksBinaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("devin-hook".utf8).write(to: hooksBinaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hooksBinaryURL.path)

        let existing = """
        {
          "model": "devin-2",
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "exec",
                "hooks": [
                  { "type": "command", "command": "./scripts/check.sh" }
                ]
              }
            ]
          }
        }
        """
        try Data(existing.utf8).write(to: devinDirectory.appendingPathComponent("config.json"))

        let installed = try manager.install(hooksBinaryURL: hooksBinaryURL)
        #expect(installed.managedHooksPresent)
        #expect(installed.manifest?.hookCommand == DevinHookInstaller.hookCommand(for: managedHooksBinaryURL.path))

        let config = try jsonObject(from: Data(contentsOf: installed.configURL))
        #expect(config["model"] as? String == "devin-2")
        let hooks = try #require(config["hooks"] as? [String: Any])
        #expect(hooks["Stop"] != nil)
        #expect(hooks["PermissionRequest"] != nil)
        #expect(hooks["PostCompaction"] == nil)

        let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        let commands = preToolUse.flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
        #expect(commands.contains("./scripts/check.sh"))
        #expect(commands.contains { $0.contains("--source devin") })
        #expect(preToolUse.contains { $0["matcher"] == nil || ($0["matcher"] as? String)?.isEmpty == true })

        let uninstalled = try manager.uninstall()
        #expect(!uninstalled.managedHooksPresent)
        let remaining = try jsonObject(from: Data(contentsOf: uninstalled.configURL))
        #expect(remaining["model"] as? String == "devin-2")
        let remainingHooks = try #require(remaining["hooks"] as? [String: Any])
        #expect(remainingHooks["Stop"] == nil)
        let remainingPreTool = try #require(remainingHooks["PreToolUse"] as? [[String: Any]])
        let remainingCommands = remainingPreTool.flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
        #expect(remainingCommands == ["./scripts/check.sh"])
    }

    @Test
    func devinInstallerRejectsInvalidJSON() {
        let data = Data("not-json".utf8)
        #expect(throws: DevinHookInstallerError.invalidConfigJSON) {
            try DevinHookInstaller.installConfigJSON(existingData: data, hookCommand: "open-island --source devin")
        }
    }

    @Test
    func resolvedAgentToolMapsDevinSource() {
        var payload = ClaudeHookPayload(
            cwd: "/tmp",
            hookEventName: .sessionStart,
            sessionID: "s"
        )
        payload.hookSource = "devin"

        #expect(payload.resolvedAgentTool == .devin)
        #expect(payload.resolvedAgentTool.displayName == "Devin")
        #expect(payload.resolvedAgentTool.isClaudeCodeFork == false)
    }

    @Test
    func devinOutputEncoderWritesBlockDecision() throws {
        let output = try DevinHookOutputEncoder.standardOutput(
            for: .claudeHookDirective(
                .permissionRequest(.deny(message: "Permission denied in Open Island."))
            )
        )
        let object = try jsonObject(from: try #require(output))
        #expect(object["decision"] as? String == "block")
        #expect(object["reason"] as? String == "Permission denied in Open Island.")
    }
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}
