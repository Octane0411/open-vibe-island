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

    /// ZCode builds the hook environment itself and stamps `ZCODE_*`
    /// runtime identifiers into it, but does not inherit
    /// `__CFBundleIdentifier` from the desktop app. The runtime context must
    /// still tag the session as "ZCode.app" (jump-back + liveness) from the
    /// ZCode variables alone, and a plain terminal environment must not be
    /// misclassified.
    @Test
    func runtimeContextTagsZcodeAppFromZcodeEnvSignals() throws {
        let payload = try JSONDecoder().decode(
            ClaudeHookPayload.self,
            from: Data(#"{"cwd": "/tmp", "hook_event_name": "SessionStart", "session_id": "s-env"}"#.utf8)
        )

        let realZcodeEnv: [String: String] = [
            "ZCODE_SESSION_ID": "sess_demo",
            "ZCODE_APP_VERSION": "3.14.4",
            "CLAUDE_SESSION_ID": "sess_demo",
            "ZCODE_PROJECT_DIR": "/tmp",
        ]
        #expect(payload.withRuntimeContext(environment: realZcodeEnv).terminalApp == "ZCode.app")

        let terminalEnv: [String: String] = [
            "TERM_PROGRAM": "ghostty",
            "GHOSTTY_RESOURCES_DIR": "/Applications/Ghostty.app/Contents/Resources",
        ]
        #expect(payload.withRuntimeContext(environment: terminalEnv).terminalApp == "Ghostty")
    }

    /// Jump targets for desktop-app agents carry an app-specific deep link
    /// so clicking focuses the exact conversation instead of only activating
    /// the desktop app or its workspace.
    @Test
    func jumpTargetCarriesAppDeepLinks() throws {
        let decoder = JSONDecoder()

        var workbuddy = try decoder.decode(
            ClaudeHookPayload.self,
            from: Data(#"{"cwd": "/Users/x/proj", "hook_event_name": "SessionStart", "session_id": "wb-session-1"}"#.utf8)
        )
        workbuddy.hookSource = "workbuddy"
        #expect(workbuddy.defaultJumpTarget.appDeepLinkURL == "workbuddy://chat/wb-session-1")

        var zcode = try decoder.decode(
            ClaudeHookPayload.self,
            from: Data(#"{"cwd": "/Users/x/my proj", "hook_event_name": "SessionStart", "session_id": "zc-1"}"#.utf8)
        )
        zcode.hookSource = "zcode"
        #expect(zcode.defaultJumpTarget.appDeepLinkURL == "zcode://workspace/open?path=%2FUsers%2Fx%2Fmy%20proj")
        #expect(zcode.defaultJumpTarget.appConversationID == "zc-1")

        let claude = try decoder.decode(
            ClaudeHookPayload.self,
            from: Data(#"{"cwd": "/tmp", "hook_event_name": "SessionStart", "session_id": "c-1"}"#.utf8)
        )
        #expect(claude.defaultJumpTarget.appDeepLinkURL == nil)
        #expect(claude.defaultJumpTarget.appConversationID == nil)
    }

    /// ZCode sessions often run in deep subdirectories of a project (agent
    /// run dirs). The deep link must target the git project root so ZCode
    /// focuses the real workspace window instead of prompting to trust an
    /// ephemeral inner folder.
    @Test
    func zcodeDeepLinkTargetsProjectRootNotSessionCWD() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("zcode-deeplink-\(UUID().uuidString)", isDirectory: true)
        let runDir = projectRoot
            .appendingPathComponent(".state/governance/GOV06-G/run-20260929", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)

        var payload = try JSONDecoder().decode(
            ClaudeHookPayload.self,
            from: Data(#"{"cwd": "\#(runDir.path)", "hook_event_name": "SessionStart", "session_id": "zc-run"}"#.utf8)
        )
        payload.hookSource = "zcode"

        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let expectedRoot = projectRoot.path.addingPercentEncoding(withAllowedCharacters: unreserved)!
        #expect(payload.defaultJumpTarget.appDeepLinkURL == "zcode://workspace/open?path=\(expectedRoot)")
    }

    // MARK: - Real-world ZCode payload compatibility

    /// Regression: a real ZCode PreToolUse payload (captured from the ZCode
    /// client) carries ZCode-specific values on Claude-schema fields —
    /// `permission_mode: "yolo"` and extra camelCase keys. The payload must
    /// decode instead of failing the whole hook, with unknown enum values
    /// treated as absent.
    @Test
    func claudePayloadDecodesRealZcodePreToolUsePayload() throws {
        let realZcodePayloadJSON = """
        {
          "cwd": "/tmp",
          "hookEventName": "PreToolUse",
          "mode": "yolo",
          "riskLevel": "high",
          "sessionId": "sess_9c28e78f-1ef6-4afd-b62c-627cb86886ee",
          "sideEffectScope": "system",
          "timestamp": "2026-09-29T14:08:10.360Z",
          "toolCallId": "call_46ceed94c5dd4fcba342d706",
          "toolInput": { "command": "echo hook-test-done", "description": "Echo hook test message" },
          "toolName": "Bash",
          "traceId": "50996fe3-7581-43a7-8627-0254fb5cbb0d",
          "turnId": "turn_2f690dde-0dc7-43f4-9a8b-c80b01601588",
          "hook_event_name": "PreToolUse",
          "permission_mode": "yolo",
          "session_id": "sess_9c28e78f-1ef6-4afd-b62c-627cb86886ee",
          "transcript_path": "/var/folders/transcript.jsonl",
          "transcriptPath": "/var/folders/transcript.jsonl",
          "tool_name": "Bash",
          "tool_input": { "command": "echo hook-test-done", "description": "Echo hook test message" },
          "tool_use_id": "call_46ceed94c5dd4fcba342d706"
        }
        """

        let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: Data(realZcodePayloadJSON.utf8))

        #expect(payload.hookEventName == .preToolUse)
        #expect(payload.sessionID == "sess_9c28e78f-1ef6-4afd-b62c-627cb86886ee")
        #expect(payload.toolName == "Bash")
        #expect(payload.toolInput != nil)
        #expect(payload.transcriptPath == "/var/folders/transcript.jsonl")
        // "yolo" is not a Claude permission mode — decodes as absent.
        #expect(payload.permissionMode == nil)
    }

    /// ZCode's PostToolUseFailure puts an object in `error_details` and its
    /// own shape in `permission_suggestions`; both must degrade to absent
    /// instead of failing the payload.
    @Test
    func claudePayloadToleratesForkSpecificSchemaDrift() throws {
        let json = """
        {
          "cwd": "/tmp",
          "hook_event_name": "PostToolUseFailure",
          "session_id": "s-fork-1",
          "error": "command not found",
          "error_details": { "code": 127, "stderr": "not found" },
          "permission_suggestions": { "rows": [{ "tool": "Bash" }] }
        }
        """

        let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: Data(json.utf8))

        #expect(payload.hookEventName == .postToolUseFailure)
        #expect(payload.error == "command not found")
        #expect(payload.errorDetails == nil)
        #expect(payload.permissionSuggestions == nil)
    }
}
