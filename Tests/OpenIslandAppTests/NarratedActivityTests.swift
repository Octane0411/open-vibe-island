import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-321 — the narrated activity presentation layer.
///
/// BRIEF §1.2: the shipped UI renders internal state ("Mcp Playwright Browser
/// Evaluate ×4", `$ source ~/.nvm/nvm…`). These tests pin the translation of
/// tool identifier + command preview into a human sentence.
struct NarratedActivityTests {

    // MARK: - The three BRIEF-named examples (AC #3)

    @Test
    func briefExampleEditingProducesFileBasename() {
        let narration = ActivityNarrator.narrate(
            toolName: "Edit",
            preview: "/Users/abhishek/Developer/open-vibe-island/Sources/OpenIslandApp/AppModel.swift"
        )

        #expect(narration?.verb == "Editing")
        #expect(narration?.object == "AppModel.swift")
        #expect(narration?.text == "Editing AppModel.swift")
    }

    @Test
    func briefExampleMCPBrowserEvaluateProducesSentence() {
        let narration = ActivityNarrator.narrate(toolName: "mcp__playwright__browser_evaluate")

        #expect(narration?.verb == "Evaluating")
        #expect(narration?.object == "in the browser")
        #expect(narration?.text == "Evaluating in the browser")
    }

    @Test
    func briefExampleBashProducesRunningCommand() {
        let narration = ActivityNarrator.narrate(toolName: "Bash", preview: "swift build")

        #expect(narration?.verb == "Running")
        #expect(narration?.object == "swift build")
        #expect(narration?.text == "Running swift build")
    }

    // MARK: - Verb map rows (AC #2) — one raw-input example each

    @Test
    func editingRowCoversEveryEditingToolID() {
        let cases: [(String, String)] = [
            ("Edit", "src/App.swift"),
            ("Write", "docs/README.md"),
            ("MultiEdit", "Sources/OpenIslandCore/SessionState.swift"),
            ("apply_patch", "/tmp/worktree/Package.swift"),
            ("NotebookEdit", "notebooks/analysis.ipynb"),
        ]

        let expected = ["App.swift", "README.md", "SessionState.swift", "Package.swift", "analysis.ipynb"]

        for (index, entry) in cases.enumerated() {
            let narration = ActivityNarrator.narrate(toolName: entry.0, preview: entry.1)
            #expect(narration?.verb == "Editing", "\(entry.0) should narrate as Editing")
            #expect(narration?.object == expected[index], "\(entry.0) object mismatch")
        }
    }

    @Test
    func readingRowUsesFileBasename() {
        let narration = ActivityNarrator.narrate(
            toolName: "Read",
            preview: "/Users/a/Developer/open-vibe-island/Sources/OpenIslandCore/AgentEvent.swift"
        )

        #expect(narration?.text == "Reading AgentEvent.swift")
    }

    @Test
    func runningRowCoversBashExecCommandAndShell() {
        #expect(ActivityNarrator.narrate(toolName: "Bash", preview: "git status")?.text == "Running git status")
        #expect(ActivityNarrator.narrate(toolName: "exec_command", preview: "npm run dev")?.text == "Running npm run dev")
        #expect(ActivityNarrator.narrate(toolName: "shell", preview: "ls -la")?.text == "Running ls -la")
    }

    @Test
    func searchingRowQuotesThePattern() {
        #expect(ActivityNarrator.narrate(toolName: "Grep", preview: "currentToolName")?.text == "Searching \"currentToolName\"")
        #expect(ActivityNarrator.narrate(toolName: "Glob", preview: "**/*.swift")?.text == "Searching \"**/*.swift\"")
        #expect(ActivityNarrator.narrate(toolName: "web_search", preview: "swift 6 concurrency")?.text == "Searching \"swift 6 concurrency\"")
        #expect(ActivityNarrator.narrate(toolName: "tool_search", preview: "notebook")?.text == "Searching \"notebook\"")
        #expect(ActivityNarrator.narrate(toolName: "search", preview: "AppModel")?.text == "Searching \"AppModel\"")
    }

    @Test
    func searchingRowOmitsObjectWhenNoPattern() {
        let narration = ActivityNarrator.narrate(toolName: "Grep", preview: nil)

        #expect(narration?.object == nil)
        #expect(narration?.text == "Searching")
    }

    @Test
    func fetchingRowExtractsHostFromURL() {
        #expect(ActivityNarrator.narrate(toolName: "WebFetch", preview: "https://docs.swift.org/swift-book/index.html")?.text == "Fetching docs.swift.org")
        #expect(ActivityNarrator.narrate(toolName: "fetch", preview: "http://127.0.0.1:4747/")?.text == "Fetching 127.0.0.1")
    }

    @Test
    func orchestratingRowCountsActiveSubagents() {
        let narration = ActivityNarrator.narrate(
            toolName: "Task",
            preview: "Investigate the bridge regression",
            activeSubagentCount: 3
        )

        #expect(narration?.text == "Orchestrating 3 subagents")
    }

    @Test
    func orchestratingRowSingularizesOneSubagent() {
        #expect(ActivityNarrator.narrate(toolName: "spawn_agent", activeSubagentCount: 1)?.text == "Orchestrating 1 subagent")
    }

    @Test
    func orchestratingRowFallsBackToTheSubagentDescriptor() {
        let narration = ActivityNarrator.narrate(
            toolName: "Task",
            preview: "code-reviewer",
            activeSubagentCount: 0
        )

        #expect(narration?.text == "Orchestrating code-reviewer")
    }

    @Test
    func askingRowHasNoObject() {
        for tool in ["AskUserQuestion", "request_user_input"] {
            let narration = ActivityNarrator.narrate(toolName: tool, preview: "Which option do you want?")
            #expect(narration?.verb == "Asking")
            #expect(narration?.object == nil)
            #expect(narration?.text == "Asking")
        }
    }

    @Test
    func planningRowHasNoObject() {
        for tool in ["ExitPlanMode", "update_plan"] {
            let narration = ActivityNarrator.narrate(toolName: tool, preview: "Step 1 …")
            #expect(narration?.verb == "Planning")
            #expect(narration?.object == nil)
            #expect(narration?.text == "Planning")
        }
    }

    // MARK: - MCP identifiers (AC #2 · #4)

    @Test
    func mcpTitleCasedVariantNarratesTheSameAsTheRawIdentifier() {
        // The exact string BRIEF §1.2 calls out, minus the fake ×4 counter.
        let narration = ActivityNarrator.narrate(toolName: "Mcp Playwright Browser Evaluate")

        #expect(narration?.text == "Evaluating in the browser")
    }

    @Test
    func mcpLeadingVerbKeepsTheTrailingNounAsObject() {
        #expect(ActivityNarrator.narrate(toolName: "mcp__linear__create_issue")?.text == "Creating issue")
        #expect(ActivityNarrator.narrate(toolName: "mcp__github__pull_request_create")?.text == "Creating pull request")
    }

    @Test
    func mcpHyphenatedActionIsSplitIntoWords() {
        #expect(ActivityNarrator.narrate(toolName: "mcp__canva__get-design")?.text == "Reading design")
        #expect(ActivityNarrator.narrate(toolName: "mcp__canva__reply-to-comment")?.text == "Replying to comment")
    }

    @Test
    func mcpCamelCasedActionIsSplitIntoWords() {
        #expect(ActivityNarrator.narrate(toolName: "mcp__ide__getDiagnostics")?.text == "Reading diagnostics")
    }

    @Test
    func mcpWithoutContextTokensFallsBackToTheServerAsLocation() {
        #expect(ActivityNarrator.narrate(toolName: "mcp__canva__export")?.text == "Exporting in Canva")
        #expect(ActivityNarrator.narrate(toolName: "mcp__github__search")?.text == "Searching in GitHub")
    }

    @Test
    func mcpUnknownActionDerivesAGerund() {
        // "wobble" is in no lexicon — the last segment still becomes a verb.
        let narration = ActivityNarrator.narrate(toolName: "mcp__acme__widget_wobble")

        #expect(narration?.verb == "Wobbling")
        #expect(narration?.text == "Wobbling widget")
    }

    @Test
    func mcpNarrationNeverLeaksTheRawIdentifier() {
        let identifiers = [
            "mcp__playwright__browser_evaluate",
            "Mcp Playwright Browser Evaluate",
            "mcp__serena__find_symbol",
            "mcp__canva__get-design",
            "mcp__acme__widget_wobble",
        ]

        for identifier in identifiers {
            let text = ActivityNarrator.narrate(toolName: identifier)?.text ?? ""
            #expect(!text.isEmpty, "\(identifier) narrated to nothing")
            #expect(!text.lowercased().contains("mcp"), "\(identifier) leaked the raw identifier: \(text)")
            #expect(!text.contains("__"), "\(identifier) leaked the raw identifier: \(text)")
        }
    }

    // MARK: - Unknown tools (AC #2 fallback row)

    @Test
    func unknownToolFallsBackToTheHumanizedNounAndPreview() {
        let narration = ActivityNarrator.narrate(toolName: "context_compaction", preview: "transcript")

        // `currentToolDisplayName` already maps this id; narration reuses it.
        #expect(narration?.verb == "Compact")
        #expect(narration?.object == "transcript")
        #expect(narration?.text == "Compact transcript")
    }

    @Test
    func unknownUnmappedToolUsesHumanizedToolName() {
        let narration = ActivityNarrator.narrate(toolName: "weird_new_tool", preview: "payload")

        #expect(narration?.verb == "Weird New Tool")
        #expect(narration?.text == "Weird New Tool payload")
    }

    @Test
    func emptyOrMissingToolNameNarratesToNil() {
        #expect(ActivityNarrator.narrate(toolName: nil) == nil)
        #expect(ActivityNarrator.narrate(toolName: "") == nil)
        #expect(ActivityNarrator.narrate(toolName: "   ") == nil)
    }

    @Test
    func narrationNeverProducesAnEmptyVerb() {
        for tool in ["Edit", "Bash", "mcp__x__y", "totally_unknown", "_", "__"] {
            guard let narration = ActivityNarrator.narrate(toolName: tool) else { continue }
            #expect(!narration.verb.isEmpty, "\(tool) produced an empty verb")
            #expect(!narration.text.isEmpty, "\(tool) produced empty text")
        }
    }

    // MARK: - Forbidden output shapes (AC #4)

    @Test
    func previewLosesTheShellPromptPrefix() {
        let narration = ActivityNarrator.narrate(toolName: "Bash", preview: "$ source ~/.nvm/nvm.sh")

        #expect(narration?.object?.hasPrefix("$") == false)
        #expect(narration?.text == "Running source ~/.nvm/nvm.sh")
        #expect(narration?.text.hasPrefix("$ ") == false)
    }

    @Test
    func previewNewlinesCollapseIntoSingleSpaces() {
        let narration = ActivityNarrator.narrate(toolName: "Bash", preview: "swift build\n  --product   OpenIslandHooks")

        #expect(narration?.object == "swift build --product OpenIslandHooks")
    }

    @Test
    func narrationNeverAppendsAnInvocationCount() {
        // The old UI's "×4" was invented precision (BRIEF §3). Nothing in the
        // narration layer can produce it.
        let narration = ActivityNarrator.narrate(
            toolName: "mcp__playwright__browser_evaluate",
            preview: "() => document.title"
        )

        #expect(narration?.text.contains("×") == false)
    }

    // MARK: - Truncation (AC #4 · #5)

    @Test
    func longPathsMiddleTruncatePreservingTheBasename() {
        let path = "Sources/OpenIslandApp/Views/Island/FlightDeckSessionRow.swift"
        let truncated = ActivityNarrator.middleTruncated(path, maxLength: 40)

        #expect(truncated.count <= 40)
        #expect(truncated.contains("…"))
        #expect(truncated.hasSuffix("FlightDeckSessionRow.swift"))
        #expect(truncated == "Sources/…/FlightDeckSessionRow.swift")
    }

    @Test
    func longBasenamesMiddleTruncateOnWordBoundaries() {
        let name = "ExtremelyLongGeneratedFileNameForTesting.swift"
        let truncated = ActivityNarrator.middleTruncatedWord(name, maxLength: 30)

        #expect(truncated.count <= 30)
        #expect(truncated.contains("…"))
        // No mid-word cut: every retained fragment is a whole camel/dot chunk.
        let chunks = ActivityNarrator.wordChunks(name)
        for fragment in truncated.components(separatedBy: "…") where !fragment.isEmpty {
            var remainder = Substring(fragment)
            for chunk in chunks where remainder.hasPrefix(chunk) {
                remainder = remainder.dropFirst(chunk.count)
            }
            #expect(remainder.isEmpty, "\(fragment) is a mid-word cut of \(name)")
        }
    }

    @Test
    func objectMaxLengthIsConfigurable() {
        let path = "/a/b/c/d/e/f/VeryDeeplyNestedThing.swift"

        let wide = ActivityNarrator.narrate(toolName: "Edit", preview: path, maxObjectLength: 40)
        let narrow = ActivityNarrator.narrate(toolName: "Edit", preview: path, maxObjectLength: 12)

        #expect(wide?.object == "VeryDeeplyNestedThing.swift")
        #expect((narrow?.object?.count ?? .max) <= 12)
        #expect(narrow?.object?.contains("…") == true)
    }

    @Test
    func longCommandsTruncateOnAWordBoundary() {
        let command = "source ~/.nvm/nvm.sh && nvm use 20 && npm run dev --workspace packages/app"
        let narration = ActivityNarrator.narrate(toolName: "Bash", preview: command)

        let object = narration?.object ?? ""
        #expect(object.count <= 40)
        #expect(object.hasSuffix("…"))
        // The retained head is a prefix of the original command — no mid-word cut.
        let head = String(object.dropLast())
        #expect(command.hasPrefix(head))
        #expect(command.dropFirst(head.count).first == " ")
    }

    // MARK: - Parts stay separate (AC #1)

    @Test
    func verbAndObjectAreExposedSeparatelyAndJoined() {
        let narration = ActivityNarrator.narrate(toolName: "Edit", preview: "Sources/AppModel.swift")

        #expect(narration?.verb == "Editing")
        #expect(narration?.object == "AppModel.swift")
        #expect(narration?.text == "Editing AppModel.swift")
    }

    // MARK: - Session-level API (AC #1)

    @Test
    func sessionExposesNarratedActivityFromItsMetadata() {
        let session = AgentSession(
            id: "session-narrated-1",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .live,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            claudeMetadata: ClaudeSessionMetadata(
                currentTool: "Edit",
                currentToolInputPreview: "/Users/a/open-vibe-island/Sources/OpenIslandApp/AppModel.swift"
            )
        )

        #expect(session.narratedActivityLineText == "Editing AppModel.swift")
        #expect(session.narratedActivityLine?.verb == "Editing")
        #expect(session.narratedActivityLine?.object == "AppModel.swift")
    }

    @Test
    func sessionNarratesSubagentCountFromClaudeMetadata() {
        let session = AgentSession(
            id: "session-narrated-2",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .live,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            claudeMetadata: ClaudeSessionMetadata(
                currentTool: "Task",
                currentToolInputPreview: "Review the diff",
                activeSubagents: [
                    ClaudeSubagentInfo(agentID: "a"),
                    ClaudeSubagentInfo(agentID: "b"),
                    ClaudeSubagentInfo(agentID: "c"),
                ]
            )
        )

        #expect(session.narratedActivityLineText == "Orchestrating 3 subagents")
    }

    @Test
    func sessionWithoutACurrentToolHasNoNarration() {
        let session = AgentSession(
            id: "session-narrated-3",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 10_000)
        )

        #expect(session.narratedActivity == nil)
        #expect(session.narratedActivityLine == nil)
        #expect(session.narratedActivityLineText == nil)
    }

    // MARK: - Existing presentation is untouched (AC #7)

    @Test
    func existingSpotlightSurfacesKeepTheirShippedRendering() {
        let session = AgentSession(
            id: "session-narrated-4",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .live,
            phase: .running,
            summary: "Working",
            updatedAt: Date.now,
            claudeMetadata: ClaudeSessionMetadata(
                currentTool: "Edit",
                currentToolInputPreview: "/Users/a/AppModel.swift"
            )
        )

        // Classic / Annual / Instrument still see the noun + raw preview.
        #expect(AgentSession.currentToolDisplayName(for: "Edit") == "Edit")
        #expect(session.displayCurrentToolName == "Edit")
        #expect(session.spotlightSecondaryText == "Running Edit")
        #expect(session.spotlightActivityLineText == "Edit /Users/a/AppModel.swift")
    }

    // MARK: - Localization (AC #6)

    @Test
    func everyVerbLocalizesInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            for verb in NarrationVerb.allCases {
                let resolved = manager.t(verb.localizationKey)
                #expect(resolved != verb.localizationKey, "\(verb.localizationKey) is unlocalized in \(language)")
                #expect(!resolved.isEmpty)
            }
        }
    }

    @Test
    func chineseNarrationLocalizesTheVerbButNotTheObject() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let manager = LanguageManager()
        manager.language = .zhHans

        let narration = ActivityNarrator.narrate(toolName: "Edit", preview: "Sources/AppModel.swift")
        #expect(narration?.localizedVerb(manager) == "正在编辑")
        // The object is data — it stays byte-identical across locales.
        #expect(narration?.localizedText(manager) == "正在编辑 AppModel.swift")

        manager.language = .en
        #expect(narration?.localizedText(manager) == "Editing AppModel.swift")
    }

    @Test
    func derivedVerbsHaveNoTokenAndRenderInEnglish() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let manager = LanguageManager()
        manager.language = .zhHant

        let narration = ActivityNarrator.narrate(toolName: "mcp__acme__widget_wobble")
        #expect(narration?.verbToken == nil)
        #expect(narration?.localizedVerb(manager) == "Wobbling")
    }

    // MARK: - Gerund derivation

    @Test
    func gerundDerivationHandlesTheCommonEnglishShapes() {
        #expect(ActivityNarrator.gerund("evaluate") == "evaluating")
        #expect(ActivityNarrator.gerund("run") == "running")
        #expect(ActivityNarrator.gerund("read") == "reading")
        #expect(ActivityNarrator.gerund("click") == "clicking")
        #expect(ActivityNarrator.gerund("fill") == "filling")
        #expect(ActivityNarrator.gerund("ping") == "pinging")
        #expect(ActivityNarrator.gerund("wobble") == "wobbling")
    }
}
