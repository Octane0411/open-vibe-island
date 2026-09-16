import Foundation
import Testing
@testable import OpenIslandCore

struct HermesHooksTests {
    private let hookCommand = "/usr/local/bin/OpenIslandHooks --source hermes"

    // MARK: - Payload decoding

    @Test
    func decodesCanonicalPayload() throws {
        let json = """
        {
          "hook_event_name": "post_llm_call",
          "session_id": "sess-123",
          "cwd": "/Users/dev/project",
          "tool_name": null,
          "tool_input": null,
          "extra": {
            "user_message": "fix the bug",
            "assistant_response": "done",
            "model": "gpt-5",
            "platform": "tui"
          }
        }
        """
        let payload = try HermesHookPayload.decode(Data(json.utf8))

        #expect(payload.hookEventName == .postLLMCall)
        #expect(payload.sessionID == "sess-123")
        #expect(payload.cwd == "/Users/dev/project")
        #expect(payload.toolName == nil)
        #expect(payload.userMessage == "fix the bug")
        #expect(payload.assistantResponse == "done")
        #expect(payload.extraValue(forKey: "model") == "gpt-5")
        #expect(payload.extraValue(forKey: "platform") == "tui")
    }

    @Test
    func decodesSessionLifecyclePayloadsWithoutExtra() throws {
        let json = """
        {"hook_event_name": "on_session_start", "session_id": "s1", "cwd": "/tmp"}
        """
        let payload = try HermesHookPayload.decode(Data(json.utf8))

        #expect(payload.hookEventName == .onSessionStart)
        #expect(payload.extra == nil)
        #expect(payload.implicitSummary == "Started Hermes session in tmp.")
    }

    @Test
    func missingSessionIDFallsBackToUnknown() throws {
        let json = """
        {"hook_event_name": "subagent_stop", "cwd": "/tmp"}
        """
        let payload = try HermesHookPayload.decode(Data(json.utf8))
        #expect(payload.sessionID == "unknown")
    }

    // MARK: - Summaries and metadata

    @Test
    func postLLMCallSummaryPrefersAssistantResponse() throws {
        let payload = HermesHookPayload(
            hookEventName: .postLLMCall,
            sessionID: "s1",
            cwd: "/work",
            extra: .object(["assistant_response": .string("Build passed.")])
        )
        #expect(payload.implicitSummary == "Build passed.")
    }

    @Test
    func subagentStopSummaryIncludesRole() {
        let payload = HermesHookPayload(
            hookEventName: .subagentStop,
            sessionID: "s1",
            cwd: "/work",
            extra: .object(["child_role": .string("leaf")])
        )
        #expect(payload.implicitSummary == "Hermes subagent (leaf) finished in work.")
    }

    @Test
    func defaultMetadataCarriesPromptsAndModel() {
        let payload = HermesHookPayload(
            hookEventName: .postLLMCall,
            sessionID: "s1",
            cwd: "/work",
            extra: .object([
                "user_message": .string("hello"),
                "assistant_response": .string("hi there"),
                "model": .string("gpt-5"),
            ])
        )

        let metadata = payload.defaultHermesMetadata
        #expect(metadata.lastUserPrompt == "hello")
        #expect(metadata.lastAssistantMessage == "hi there")
        #expect(metadata.model == "gpt-5")
        #expect(!metadata.isEmpty)
    }

    @Test
    func defaultMetadataKeepsLongAssistantResponseForCompletionCard() {
        let longResponse = String(repeating: "PR body line.\n", count: 1200)
        let payload = HermesHookPayload(
            hookEventName: .postLLMCall,
            sessionID: "s1",
            cwd: "/work",
            extra: .object([
                "user_message": .string("ship it"),
                "assistant_response": .string(longResponse),
            ])
        )

        let metadata = payload.defaultHermesMetadata
        #expect(metadata.lastAssistantMessage?.contains("PR body line.") == true)
        #expect(metadata.lastAssistantMessage?.contains("\n") == true)
        #expect(metadata.lastAssistantMessage?.count ?? 0 > 110)
    }

    @Test
    func defaultMetadataKeepsBeginningOfOverlongResponse() {
        // A response longer than the 20000-char cap must keep the BEGINNING
        // (summary/overview), not the tail. The completion card shows the start.
        let prefix = "完成。汇总：这是开头的内容，应该被保留。\n\n"
        let longResponse = prefix + String(repeating: "填充内容一行。\n", count: 3500)
        let payload = HermesHookPayload(
            hookEventName: .postLLMCall,
            sessionID: "s1",
            cwd: "/work",
            extra: .object([
                "user_message": .string("ship it"),
                "assistant_response": .string(longResponse),
            ])
        )

        let metadata = payload.defaultHermesMetadata
        #expect(metadata.lastAssistantMessage?.hasPrefix("完成。汇总") == true)
        #expect(metadata.lastAssistantMessage?.contains("开头的内容") == true)
        #expect(metadata.lastAssistantMessage?.hasSuffix("…") == true)
    }

    // MARK: - Installer: fresh file

    @Test
    func installIntoEmptyConfigAppendsHooksBlock() throws {
        let mutation = try HermesHookInstaller.installConfigYAML(existingData: nil, hookCommand: hookCommand)

        #expect(mutation.changed)
        #expect(mutation.managedHooksPresent)

        let text = String(decoding: mutation.contents!, as: UTF8.self)
        for event in ["on_session_start", "on_session_end", "post_llm_call", "subagent_stop", "pre_tool_call", "pre_approval_request"] {
            #expect(text.contains("  \(event):"))
        }
        #expect(text.contains("--source hermes"))
    }

    // MARK: - Installer: existing file with other top-level keys

    @Test
    func installPreservesSurroundingConfigKeys() throws {
        let existing = """
        model: gpt-5
        agent:
          max_iterations: 100
        display:
          bell_on_complete: true
        """
        let mutation = try HermesHookInstaller.installConfigYAML(
            existingData: Data(existing.utf8),
            hookCommand: hookCommand
        )

        #expect(mutation.changed)
        let text = String(decoding: mutation.contents!, as: UTF8.self)
        #expect(text.contains("model: gpt-5"))
        #expect(text.contains("max_iterations: 100"))
        #expect(text.contains("bell_on_complete: true"))
        #expect(text.hasSuffix("\n"))
        // hooks block appended at the end
        #expect(text.range(of: "hooks:")!.lowerBound > text.range(of: "bell_on_complete")!.lowerBound)
    }

    // MARK: - Installer: merge into existing hooks block

    @Test
    func installMergesIntoExistingHooksBlockPreservingUnmanagedEntries() throws {
        let existing = """
        hooks:
          on_session_start:
            - command: '/usr/bin/echo my-custom-hook'
              timeout: 5
        display:
          bell_on_complete: true
        """
        let mutation = try HermesHookInstaller.installConfigYAML(
            existingData: Data(existing.utf8),
            hookCommand: hookCommand
        )

        #expect(mutation.changed)
        let text = String(decoding: mutation.contents!, as: UTF8.self)
        // Unmanaged entry preserved
        #expect(text.contains("my-custom-hook"))
        // All managed events present
        for event in ["on_session_start", "on_session_end", "post_llm_call", "subagent_stop", "pre_tool_call", "pre_approval_request"] {
            #expect(text.contains("  \(event):"))
        }
        #expect(text.contains("bell_on_complete: true"))
        // hooks block stays before the display block
        #expect(text.range(of: "hooks:")!.lowerBound < text.range(of: "display:")!.lowerBound)
    }

    @Test
    func installIsIdempotent() throws {
        let existing = "model: gpt-5\n"
        let first = try HermesHookInstaller.installConfigYAML(
            existingData: Data(existing.utf8),
            hookCommand: hookCommand
        )
        let second = try HermesHookInstaller.installConfigYAML(
            existingData: first.contents,
            hookCommand: hookCommand
        )

        #expect(!second.changed)
    }

    // MARK: - Installer: existing Open Island hooks (stale path)

    @Test
    func installReplacesStaleManagedCommand() throws {
        let staleCommand = "'/old/path/OpenIslandHooks' --source hermes"
        let existing = """
        hooks:
          post_llm_call:
            - command: \(shellQuoted(staleCommand))
        """
        let mutation = try HermesHookInstaller.installConfigYAML(
            existingData: Data(existing.utf8),
            hookCommand: hookCommand
        )

        let text = String(decoding: mutation.contents!, as: UTF8.self)
        #expect(!text.contains("/old/path/OpenIslandHooks"))
        #expect(text.contains("--source hermes"))
    }

    // MARK: - Uninstall

    @Test
    func uninstallRemovesWholeBlockWhenOnlyManagedHooksPresent() throws {
        let installed = try HermesHookInstaller.installConfigYAML(
            existingData: Data("model: gpt-5\n".utf8),
            hookCommand: hookCommand
        )
        let mutation = try HermesHookInstaller.uninstallConfigYAML(
            existingData: installed.contents,
            managedCommand: hookCommand
        )

        #expect(mutation.changed)
        #expect(!mutation.managedHooksPresent)

        let text = String(decoding: mutation.contents!, as: UTF8.self)
        #expect(text == "model: gpt-5\n")
        #expect(!text.contains("hooks:"))
    }

    @Test
    func uninstallPreservesUnmanagedHooksAndOtherKeys() throws {
        let existing = """
        model: gpt-5
        hooks:
          on_session_start:
            - command: '/usr/bin/echo mine'
        """
        let installed = try HermesHookInstaller.installConfigYAML(
            existingData: Data(existing.utf8),
            hookCommand: hookCommand
        )
        let mutation = try HermesHookInstaller.uninstallConfigYAML(
            existingData: installed.contents,
            managedCommand: hookCommand
        )

        #expect(mutation.changed)
        #expect(!mutation.managedHooksPresent)

        let text = String(decoding: mutation.contents!, as: UTF8.self)
        #expect(text.contains("model: gpt-5"))
        #expect(text.contains("'/usr/bin/echo mine'"))
    }

    // MARK: - Command recognition

    @Test
    func recognizesOpenIslandHermesCommands() {
        #expect(HermesHookInstaller.isOpenIslandHermesHookCommand("'/app/OpenIslandHooks' --source hermes"))
        #expect(HermesHookInstaller.isOpenIslandHermesHookCommand("'/app/VibeIslandHooks' --source hermes"))
        #expect(!HermesHookInstaller.isOpenIslandHermesHookCommand("'/app/OpenIslandHooks' --source gemini"))
        #expect(!HermesHookInstaller.isOpenIslandHermesHookCommand("'/usr/bin/echo hi'"))
    }

    // MARK: - YAML round-trip

    @Test
    func installQuotesOnlyTheBinaryPath() throws {
        let raw = "/Applications/Open Island.app/Contents/Helpers/OpenIslandHooks --source hermes"
        let installed = try HermesHookInstaller.installConfigYAML(
            existingData: Data("model: gpt-5\n".utf8),
            hookCommand: raw
        )
        let text = String(decoding: installed.contents!, as: UTF8.self)

        // YAML layer keeps the shell layer literal: the shell quote around the
        // binary survives, `--source hermes` stays outside it, and the space
        // inside the path is escaped by the shell layer only.
        #expect(text.contains("command: '''/Applications/Open Island.app/Contents/Helpers/OpenIslandHooks'' --source hermes'"))
    }

    @Test
    func installExtendsNonStandardEventIndentWithoutDuplicateKeys() throws {
        let existing = """
        model: gpt-5
        hooks:
            post_llm_call:
              - command: '/usr/bin/echo mine'
        """
        let installed = try HermesHookInstaller.installConfigYAML(
            existingData: Data(existing.utf8),
            hookCommand: hookCommand
        )
        let text = String(decoding: installed.contents!, as: UTF8.self)

        #expect(text.contains("echo mine"))
        #expect(text.components(separatedBy: "post_llm_call:").count - 1 == 1)
        #expect(text.contains("    on_session_start:"))
        #expect(!text.contains("\n  on_session_start:"))
    }

    @Test
    func installExtendsQuotedEventKeyWithoutDuplicateKey() throws {
        let existing = """
        hooks:
          \"post_llm_call\":
            - command: '/usr/bin/echo mine'
        """
        let installed = try HermesHookInstaller.installConfigYAML(
            existingData: Data(existing.utf8),
            hookCommand: hookCommand
        )
        let text = String(decoding: installed.contents!, as: UTF8.self)

        #expect(text.components(separatedBy: "post_llm_call").count - 1 == 1)
        #expect(text.contains("echo mine"))
        #expect(text.contains("on_session_start:"))
    }

    @Test
    func installLeavesInlineValuedEventVerbatim() throws {
        let existing = """
        hooks:
          post_llm_call: []
        """
        let installed = try HermesHookInstaller.installConfigYAML(
            existingData: Data(existing.utf8),
            hookCommand: hookCommand
        )
        let text = String(decoding: installed.contents!, as: UTF8.self)

        #expect(text.contains("post_llm_call: []"))
        #expect(!text.contains("post_llm_call:\n    - command:"))
        #expect(text.contains("on_session_start:"))
    }

    @Test
    func bareDashLineIsAnEntryBoundary() throws {
        let existing = """
        hooks:
          post_llm_call:
            -
            - command: '/usr/bin/echo mine'
        """
        let installed = try HermesHookInstaller.installConfigYAML(
            existingData: Data(existing.utf8),
            hookCommand: hookCommand
        )
        let text = String(decoding: installed.contents!, as: UTF8.self)
        #expect(text.contains("echo mine"))

        let uninstalled = try HermesHookInstaller.uninstallConfigYAML(
            existingData: installed.contents,
            managedCommand: hookCommand
        )
        let uninstalledText = String(decoding: uninstalled.contents!, as: UTF8.self)
        #expect(uninstalledText.contains("-\n"))
        #expect(uninstalledText.contains("echo mine"))
    }

    @Test
    func installLeavesMappingValuedEventVerbatim() throws {
        let existing = """
        hooks:
          post_llm_call:
            command: '/usr/bin/echo mine'
        """
        let installed = try HermesHookInstaller.installConfigYAML(
            existingData: Data(existing.utf8),
            hookCommand: hookCommand
        )
        let text = String(decoding: installed.contents!, as: UTF8.self)

        #expect(text.contains("command: '/usr/bin/echo mine'"))
        // The mapping-valued event keeps its body; no list entry is mixed in
        // under it.
        #expect(!text.contains("echo mine'\n    - command:"))
        #expect(text.contains("on_session_start:"))
    }

    @Test
    func installReplacesLegacyWholeCommandQuoteWithPathQuote() throws {
        // Pre-fix blocks quoted the whole command; a re-install migrates the
        // entry to the path-only quote form.
        let legacy = """
        hooks:
          post_llm_call:
            - command: '/Applications/Open Island.app/Contents/Helpers/OpenIslandHooks --source hermes'
        """
        let installed = try HermesHookInstaller.installConfigYAML(
            existingData: Data(legacy.utf8),
            hookCommand: hookCommand
        )
        let text = String(decoding: installed.contents!, as: UTF8.self)

        #expect(!text.contains("Helpers/OpenIslandHooks --source hermes' --source hermes"))
        #expect(text.components(separatedBy: "post_llm_call:").count - 1 == 1)
        #expect(text.contains("command: '''/usr/local/bin/OpenIslandHooks'' --source hermes'"))
    }

    // MARK: - Realistic Application Support path (regression: paths with
    // spaces must survive the YAML/shell double quoting so the hook runs).

    @Test
    func installHandlesApplicationSupportPathWithSpaces() throws {
        let managedPath = "/Users/dev/Library/Application Support/OpenIsland/bin/OpenIslandHooks"
        let installed = try HermesHookInstaller.installConfigYAML(
            existingData: Data("model: gpt-5\n".utf8),
            hookCommand: HermesHookInstaller.hookCommand(for: managedPath)
        )
        let text = String(decoding: installed.contents!, as: UTF8.self)
        #expect(text.contains("--source hermes"))
        #expect(text.contains(managedPath))
        #expect(try HermesHookInstaller.configYAMLHasOpenIslandHooks(existingData: installed.contents))
    }

    @Test
    func installIsIdempotentForApplicationSupportPathWithSpaces() throws {
        let managedPath = "/Users/dev/Library/Application Support/OpenIsland/bin/OpenIslandHooks"
        let command = HermesHookInstaller.hookCommand(for: managedPath)
        let first = try HermesHookInstaller.installConfigYAML(
            existingData: Data("model: gpt-5\n".utf8),
            hookCommand: command
        )
        let second = try HermesHookInstaller.installConfigYAML(
            existingData: first.contents,
            hookCommand: command
        )
        #expect(!second.changed)
    }

    // MARK: - Externally folded command scalars (regression: an editor or
    // YAML tool can wrap the command onto continuation lines; detection
    // must still recognize the entry).

    @Test
    func detectsFoldedCommandScalar() throws {
        let folded = """
        hooks:
          post_llm_call:
            - command: '''/Users/user/Library/Application Support/OpenIsland/bin/OpenIslandHooks''
                --source hermes'
          pre_tool_call:
            - command: '''/Users/user/Library/Application Support/OpenIsland/bin/OpenIslandHooks''
                --source hermes'
        model: gpt-5
        """
        #expect(try HermesHookInstaller.configYAMLHasOpenIslandHooks(existingData: Data(folded.utf8)))
    }

    @Test
    func uninstallRemovesApplicationSupportPathWithSpaces() throws {
        let managedPath = "/Users/dev/Library/Application Support/OpenIsland/bin/OpenIslandHooks"
        let command = HermesHookInstaller.hookCommand(for: managedPath)
        let installed = try HermesHookInstaller.installConfigYAML(
            existingData: Data("model: gpt-5\n".utf8),
            hookCommand: command
        )
        let mutation = try HermesHookInstaller.uninstallConfigYAML(
            existingData: installed.contents,
            managedCommand: command
        )

        #expect(mutation.changed)
        #expect(!mutation.managedHooksPresent)
        let text = String(decoding: mutation.contents!, as: UTF8.self)
        #expect(text == "model: gpt-5\n")
        #expect(!text.contains("Application Support"))
    }

    // MARK: - HITL

    @Test
    func clarifyPreToolCallBecomesQuestionPrompt() throws {
        let json = """
        {
          "hook_event_name": "pre_tool_call",
          "session_id": "s-hitl",
          "cwd": "/work",
          "tool_name": "clarify",
          "tool_input": {
            "questions": [
              {
                "question": "Which deployment target?",
                "header": "deploy",
                "options": [
                  {"label": "staging", "description": "QA cluster"},
                  {"label": "prod", "description": "production"}
                ]
              }
            ]
          }
        }
        """
        let payload = try HermesHookPayload.decode(Data(json.utf8))

        let prompt = try #require(payload.hitlQuestionPrompt)
        #expect(prompt.title == "Which deployment target?")
        #expect(prompt.questions.count == 1)
        #expect(prompt.questions[0].options.count == 3) // 2 + synthesized Other
        #expect(prompt.questions[0].options[2].label == "Other")
    }

    @Test
    func nonClarifyPreToolCallIsNotAQuestion() throws {
        let json = """
        {
          "hook_event_name": "pre_tool_call",
          "session_id": "s1",
          "cwd": "/work",
          "tool_name": "terminal",
          "tool_input": {"command": "ls"}
        }
        """
        let payload = try HermesHookPayload.decode(Data(json.utf8))

        #expect(payload.hitlQuestionPrompt == nil)
        #expect(payload.implicitSummary == "Hermes is running terminal in work.")
    }

    @Test
    func preApprovalRequestBecomesPermissionCard() throws {
        let json = """
        {
          "hook_event_name": "pre_approval_request",
          "session_id": "s-approval",
          "cwd": "/work",
          "tool_name": "terminal",
          "extra": {
            "command": "rm -rf build",
            "description": "Delete build directory",
            "tool_call_id": "call-42"
          }
        }
        """
        let payload = try HermesHookPayload.decode(Data(json.utf8))

        let request = try #require(payload.hitlPermissionRequest)
        #expect(request.title == "Delete build directory")
        #expect(request.summary == "Command: rm -rf build")
        #expect(request.toolUseID == "call-42")
        #expect(request.primaryActionTitle == "Approve")
        #expect(payload.implicitSummary == "Hermes is waiting for approval in work.")
    }

    private func shellQuoted(_ command: String) -> String {
        "'\(command)'"
    }
}
