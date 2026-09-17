import Foundation
import Testing
@testable import OpenIslandCore

struct ZCodeHooksTests {
    private var command: String {
        ZCodeHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
    }

    private func managedHookDictionary(data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test
    func installIntoMissingConfigEnablesHooksAndRegistersLifecycleEvents() throws {
        let mutation = try ZCodeHookInstaller.installConfigJSON(
            existingData: nil,
            hookCommand: command
        )

        #expect(mutation.changed)
        #expect(mutation.managedHooksPresent)
        let root = try managedHookDictionary(data: try #require(mutation.contents))

        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(hooks["enabled"] as? Bool == true)

        let events = try #require(hooks["events"] as? [String: Any])
        #expect(Set(events.keys) == ["SessionStart", "UserPromptSubmit", "Stop"])

        let groups = try #require(events["Stop"] as? [[String: Any]])
        #expect(groups.count == 1)
        let hooksList = try #require(groups[0]["hooks"] as? [[String: Any]])
        #expect(hooksList.count == 1)
        #expect(hooksList[0]["type"] as? String == "command")
        #expect(hooksList[0]["command"] as? String == command)
    }

    @Test
    func installPreservesUnrelatedUserHooksAndConfigKeys() throws {
        let existing = """
        {
          "provider" : "glm",
          "hooks" : {
            "events" : {
              "PostToolUse" : [
                {
                  "matcher" : "Bash",
                  "hooks" : [ { "type" : "command", "command" : "prettier --write" } ]
                }
              ]
            }
          }
        }
        """
        let mutation = try ZCodeHookInstaller.installConfigJSON(
            existingData: Data(existing.utf8),
            hookCommand: command
        )

        let root = try managedHookDictionary(data: try #require(mutation.contents))
        #expect(root["provider"] as? String == "glm")

        let hooks = try #require(root["hooks"] as? [String: Any])
        let events = try #require(hooks["events"] as? [String: Any])
        let postToolUseGroups = try #require(events["PostToolUse"] as? [[String: Any]])
        #expect(postToolUseGroups.count == 1)
        #expect(postToolUseGroups[0]["matcher"] as? String == "Bash")

        let userHooks = try #require(postToolUseGroups[0]["hooks"] as? [[String: Any]])
        #expect(userHooks.count == 1)
        #expect(userHooks[0]["command"] as? String == "prettier --write")
    }

    @Test
    func installIsIdempotentAndReplacesStaleManagedCommand() throws {
        let first = try ZCodeHookInstaller.installConfigJSON(existingData: nil, hookCommand: command)
        let contents = try #require(first.contents)
        let staleCommand = ZCodeHookInstaller.hookCommand(for: "/old/path/OpenIslandHooks")
        let second = try ZCodeHookInstaller.installConfigJSON(
            existingData: contents,
            hookCommand: staleCommand
        )

        let root = try managedHookDictionary(data: try #require(second.contents))
        let hooks = try #require(root["hooks"] as? [String: Any])
        let events = try #require(hooks["events"] as? [String: Any])
        let stopGroups = try #require(events["Stop"] as? [[String: Any]])
        #expect(stopGroups.count == 1)

        let serialized = String(decoding: try #require(second.contents), as: UTF8.self)
        #expect(!serialized.contains(command))
    }

    @Test
    func uninstallRemovesManagedHooksAndPreservesUserEntries() throws {
        let installed = try ZCodeHookInstaller.installConfigJSON(
            existingData: Data("""
            {
              "provider" : "glm",
              "hooks" : {
                "events" : {
                  "PostToolUse" : [
                    {
                      "matcher" : "Bash",
                      "hooks" : [ { "type" : "command", "command" : "prettier --write" } ]
                    }
                  ]
                }
              }
            }
            """.utf8),
            hookCommand: command
        )

        let mutation = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: try #require(installed.contents),
            managedCommand: command
        )

        #expect(mutation.changed)
        #expect(mutation.managedHooksPresent)
        let root = try managedHookDictionary(data: try #require(mutation.contents))
        #expect(root["provider"] as? String == "glm")

        let events = try #require((root["hooks"] as? [String: Any])?["events"] as? [String: Any])
        #expect(Array(events.keys) == ["PostToolUse"])
    }

    @Test
    func uninstallWithoutManagedHooksLeavesConfigUntouched() throws {
        let existing = Data("""
        {
          "provider" : "glm"
        }
        """.utf8)

        let mutation = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: existing,
            managedCommand: command
        )

        #expect(!mutation.changed)
        #expect(!mutation.managedHooksPresent)
        #expect(mutation.contents == existing)
    }

    @Test
    func uninstallOfMissingConfigIsANoOp() throws {
        let mutation = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: nil,
            managedCommand: command
        )

        #expect(!mutation.changed)
        #expect(!mutation.managedHooksPresent)
        #expect(mutation.contents == nil)
    }

    @Test
    func uninstallRecognizesLegacyManagedCommands() throws {
        let legacy = Data("""
        {
          "hooks" : {
            "enabled" : true,
            "events" : {
              "Stop" : [
                {
                  "hooks" : [
                    { "type" : "command", "command" : "/old/OpenIslandHooks --source zcode" }
                  ]
                }
              ]
            }
          }
        }
        """.utf8)

        let mutation = try ZCodeHookInstaller.uninstallConfigJSON(
            existingData: legacy,
            managedCommand: nil
        )

        #expect(mutation.changed)
        #expect(mutation.contents == nil)
    }

    @Test
    func managerRoundTripOnDisk() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zcode-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let binaryURL = tempDirectory.appendingPathComponent("OpenIslandHooks")
        let manager = ZCodeHookInstallationManager(
            zcodeDirectory: tempDirectory,
            managedHooksBinaryURL: binaryURL,
            fileManager: .default
        )

        // ManagedHooksBinary.install requires an executable source binary.
        try "#!/bin/sh\n".write(to: binaryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)

        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        do {
            let status = try manager.install(hooksBinaryURL: binaryURL)
            #expect(status.managedHooksPresent)
            #expect(status.manifest?.hookCommand == ZCodeHookInstaller.hookCommand(for: binaryURL.path))
        }

        do {
            let status = try manager.status()
            #expect(status.managedHooksPresent)
        }

        do {
            let status = try manager.uninstall()
            #expect(!status.managedHooksPresent)
            #expect(!FileManager.default.fileExists(atPath: status.manifestURL.path))
        }
    }

    @Test
    func decodesZcodeSessionStartPayload() throws {
        let json = """
        {
          "session_id" : "sess_7f6e70e1",
          "hook_event_name" : "SessionStart",
          "cwd" : "/Users/dev/project",
          "timestamp" : "2026-09-17T10:00:00.000Z",
          "agent_type" : "zcode",
          "permission_mode" : "default",
          "transcript_path" : "/tmp/zcode-claude-hook-abc/transcript.jsonl"
        }
        """
        let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: Data(json.utf8))

        #expect(payload.sessionID == "sess_7f6e70e1")
        #expect(payload.hookEventName == .sessionStart)
        #expect(payload.cwd == "/Users/dev/project")
        #expect(payload.agentType == "zcode")
        #expect(payload.permissionMode == .default)
    }

    @Test
    func decodesZcodeStopPayloadWithLastAssistantMessage() throws {
        let json = """
        {
          "session_id" : "sess_7f6e70e1",
          "hook_event_name" : "Stop",
          "cwd" : "/Users/dev/project",
          "last_assistant_message" : "Done. All tests pass.",
          "stop_hook_active" : false
        }
        """
        let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: Data(json.utf8))

        #expect(payload.hookEventName == .stop)
        #expect(payload.lastAssistantMessage == "Done. All tests pass.")
        #expect(payload.stopHookActive == false)
    }

    @Test
    func resolvedAgentToolMapsZcodeSource() {
        var payload = ClaudeHookPayload(
            cwd: "/Users/dev/project",
            hookEventName: .sessionStart,
            sessionID: "sess_7f6e70e1"
        )
        payload.hookSource = "zcode"

        #expect(payload.resolvedAgentTool == .zcode)
        #expect(payload.resolvedAgentTool.displayName == "ZCode")
        #expect(payload.resolvedAgentTool.isClaudeCodeFork == false)
    }
}
