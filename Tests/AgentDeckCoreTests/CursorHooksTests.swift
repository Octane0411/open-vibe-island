import Foundation
import Testing
@testable import AgentDeckCore

struct CursorHooksTests {
    @Test
    func cursorHookPayloadDecodesFromJSON() throws {
        let json = """
        {
            "hook_event_name": "beforeShellExecution",
            "conversation_id": "conv-123",
            "generation_id": "gen-456",
            "workspace_roots": ["/Users/test/project"],
            "command": "npm test",
            "cwd": "/Users/test/project"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(CursorHookPayload.self, from: json)
        #expect(payload.hookEventName == .beforeShellExecution)
        #expect(payload.conversationId == "conv-123")
        #expect(payload.generationId == "gen-456")
        #expect(payload.workspaceRoots == ["/Users/test/project"])
        #expect(payload.command == "npm test")
        #expect(payload.cwd == "/Users/test/project")
        #expect(payload.sessionID == "conv-123")
        #expect(payload.isBlockingHook == true)
    }

    @Test
    func cursorHookPayloadDecodesStopEvent() throws {
        let json = """
        {
            "hook_event_name": "stop",
            "conversation_id": "conv-789",
            "generation_id": "gen-012",
            "workspace_roots": ["/Users/test/project"],
            "status": "completed"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(CursorHookPayload.self, from: json)
        #expect(payload.hookEventName == .stop)
        #expect(payload.status == "completed")
        #expect(payload.isBlockingHook == false)
    }

    @Test
    func cursorHookDirectiveEncodesToJSON() throws {
        let directive = CursorHookDirective(continue: true, permission: .allow)
        let data = try JSONEncoder().encode(directive)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(object["continue"] as? Bool == true)
        #expect(object["permission"] as? String == "allow")
    }

    @Test
    func cursorHookDirectiveDenyEncodesToJSON() throws {
        let directive = CursorHookDirective(
            continue: true,
            permission: .deny,
            agentMessage: "Denied by Agent Deck."
        )
        let data = try JSONEncoder().encode(directive)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(object["permission"] as? String == "deny")
        #expect(object["agentMessage"] as? String == "Denied by Agent Deck.")
    }

    @Test
    func cursorHookInstallerInstallsIntoEmptyFile() throws {
        let mutation = try CursorHookInstaller.installHooksJSON(
            existingData: nil,
            hookCommand: "/usr/local/bin/AgentDeckHooks --source cursor"
        )

        #expect(mutation.changed == true)
        #expect(mutation.managedHooksPresent == true)

        let data = try #require(mutation.contents)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = object["hooks"] as! [String: Any]

        #expect(hooks.keys.contains("beforeShellExecution"))
        #expect(hooks.keys.contains("beforeMCPExecution"))
        #expect(hooks.keys.contains("stop"))

        let shellEntries = hooks["beforeShellExecution"] as! [[String: Any]]
        #expect(shellEntries.count == 1)
        #expect(shellEntries[0]["command"] as? String == "/usr/local/bin/AgentDeckHooks --source cursor")
    }

    @Test
    func cursorHookInstallerPreservesExistingHooks() throws {
        let existing = """
        {
            "version": 1,
            "hooks": {
                "beforeShellExecution": [
                    { "command": "/usr/local/bin/my-custom-hook" }
                ]
            }
        }
        """.data(using: .utf8)!

        let mutation = try CursorHookInstaller.installHooksJSON(
            existingData: existing,
            hookCommand: "/usr/local/bin/AgentDeckHooks --source cursor"
        )

        let data = try #require(mutation.contents)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = object["hooks"] as! [String: Any]
        let shellEntries = hooks["beforeShellExecution"] as! [[String: Any]]

        #expect(shellEntries.count == 2)
        #expect(shellEntries[0]["command"] as? String == "/usr/local/bin/my-custom-hook")
        #expect(shellEntries[1]["command"] as? String == "/usr/local/bin/AgentDeckHooks --source cursor")
    }

    @Test
    func cursorHookInstallerUninstallsCleanly() throws {
        let installed = try CursorHookInstaller.installHooksJSON(
            existingData: nil,
            hookCommand: "/usr/local/bin/AgentDeckHooks --source cursor"
        )

        let uninstalled = try CursorHookInstaller.uninstallHooksJSON(
            existingData: installed.contents,
            managedCommand: "/usr/local/bin/AgentDeckHooks --source cursor"
        )

        #expect(uninstalled.changed == true)
        #expect(uninstalled.managedHooksPresent == true)
        #expect(uninstalled.contents == nil)
    }

    @Test
    func cursorHookInstallationManagerRoundTripsInstallAndUninstall() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-deck-cursor-hooks-\(UUID().uuidString)", isDirectory: true)
        let cursorDirectory = rootURL.appendingPathComponent(".cursor", isDirectory: true)
        let managedHooksBinaryURL = rootURL
            .appendingPathComponent("managed", isDirectory: true)
            .appendingPathComponent("AgentDeckHooks")
        let manager = CursorHookInstallationManager(
            cursorDirectory: cursorDirectory,
            managedHooksBinaryURL: managedHooksBinaryURL
        )
        let hooksBinaryURL = rootURL
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("AgentDeckHooks")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: hooksBinaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cursor-hook".utf8).write(to: hooksBinaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hooksBinaryURL.path)

        let installStatus = try manager.install(hooksBinaryURL: hooksBinaryURL)
        #expect(installStatus.managedHooksPresent == true)
        #expect(FileManager.default.fileExists(atPath: cursorDirectory.appendingPathComponent("hooks.json").path))
        #expect(FileManager.default.fileExists(atPath: cursorDirectory.appendingPathComponent(CursorHookInstallerManifest.fileName).path))

        let hooksData = try Data(contentsOf: cursorDirectory.appendingPathComponent("hooks.json"))
        let hooksObject = try JSONSerialization.jsonObject(with: hooksData) as! [String: Any]
        let hooks = hooksObject["hooks"] as! [String: Any]
        #expect(hooks.keys.count == 6)

        let uninstallStatus = try manager.uninstall()
        #expect(uninstallStatus.managedHooksPresent == false)
        #expect(!FileManager.default.fileExists(atPath: cursorDirectory.appendingPathComponent(CursorHookInstallerManifest.fileName).path))
    }

    @Test
    func cursorPayloadConvenienceProperties() {
        let payload = CursorHookPayload(
            hookEventName: .beforeShellExecution,
            conversationId: "conv-test",
            generationId: "gen-test",
            workspaceRoots: ["/Users/test/my-project"],
            command: "npm run build",
            cwd: "/Users/test/my-project"
        )

        #expect(payload.workspaceName == "my-project")
        #expect(payload.sessionTitle == "Cursor \u{00B7} my-project")
        #expect(payload.primaryWorkspaceRoot == "/Users/test/my-project")
        #expect(payload.permissionRequestTitle == "Allow shell command")
        #expect(payload.permissionRequestSummary == "npm run build")
        #expect(payload.defaultJumpTarget.terminalApp == "Cursor")
        #expect(payload.defaultJumpTarget.workingDirectory == "/Users/test/my-project")
        #expect(payload.defaultCursorMetadata.initialUserPrompt == nil)
        #expect(payload.defaultCursorMetadata.lastUserPrompt == nil)
    }

    @Test
    func cursorHookPayloadDecodesWithObjectAttachments() throws {
        let json = """
        {
            "hook_event_name": "beforeSubmitPrompt",
            "conversation_id": "conv-attach",
            "generation_id": "gen-attach",
            "workspace_roots": ["/Users/test/project"],
            "prompt": "Fix the bug",
            "attachments": [
                {"type": "rule", "file_path": "CLAUDE.md"},
                {"type": "file", "file_path": "src/main.ts"}
            ],
            "model": "claude-4.6-opus",
            "session_id": "conv-attach",
            "composer_mode": "agent",
            "user_email": "test@example.com"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(CursorHookPayload.self, from: json)
        #expect(payload.hookEventName == .beforeSubmitPrompt)
        #expect(payload.prompt == "Fix the bug")
        #expect(payload.attachments?.count == 2)
        #expect(payload.attachments?[0].type == "rule")
        #expect(payload.attachments?[0].filePath == "CLAUDE.md")
        #expect(payload.model == "claude-4.6-opus")
        #expect(payload.promptPreview == "Fix the bug")
    }

    @Test
    func cursorTranscriptReaderExtractsPromptWithUserQueryTag() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-transcript-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let entry = """
        {"role":"user","message":{"content":[{"type":"text","text":"<image_files>\\nSome image context\\n</image_files><user_query>\\n修复这个bug\\n</user_query>"}]}}
        """
        try entry.write(to: tempFile, atomically: true, encoding: .utf8)

        let prompt = CursorTranscriptReader.initialUserPrompt(at: tempFile.path)
        #expect(prompt == "修复这个bug")
    }

    @Test
    func cursorTranscriptReaderExtractsPlainPrompt() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-transcript-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let entry = """
        {"role":"user","message":{"content":[{"type":"text","text":"Add dark mode support to the settings page"}]}}
        """
        try entry.write(to: tempFile, atomically: true, encoding: .utf8)

        let prompt = CursorTranscriptReader.initialUserPrompt(at: tempFile.path)
        #expect(prompt == "Add dark mode support to the settings page")
    }

    @Test
    func cursorTranscriptReaderReturnsNilForMissingFile() {
        let prompt = CursorTranscriptReader.initialUserPrompt(at: "/nonexistent/path.jsonl")
        #expect(prompt == nil)
    }

    @Test
    func cursorTranscriptReaderClipsLongPrompts() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-transcript-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let longText = String(repeating: "word ", count: 100)
        let entry = """
        {"role":"user","message":{"content":[{"type":"text","text":"\(longText)"}]}}
        """
        try entry.write(to: tempFile, atomically: true, encoding: .utf8)

        let prompt = CursorTranscriptReader.initialUserPrompt(at: tempFile.path)
        #expect(prompt != nil)
        #expect((prompt?.count ?? 0) <= 201)
    }
}
