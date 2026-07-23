import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct AgentSessionPresentationTests {
    @Test
    func attachedCompletedSessionStaysActiveWhileRecent() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_199),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "codex ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            )
        )

        #expect(session.islandPresence(at: referenceDate) == .active)
    }

    @Test
    func attachedCompletedSessionCollapsesWhenOld() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_201),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "codex ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Initial prompt",
                lastUserPrompt: "Follow-up prompt",
                lastAssistantMessage: "Last assistant message"
            )
        )

        #expect(session.islandPresence(at: referenceDate) == .inactive)
        #expect(session.spotlightShowsDetailLines(at: referenceDate) == false)
    }

    @Test
    func detachedCompletedSessionCanStillCollapseToInactive() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .detached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_801)
        )

        #expect(session.islandPresence(at: referenceDate) == .inactive)
        #expect(session.spotlightShowsDetailLines(at: referenceDate) == false)
    }

    @Test
    func detachedCompletedSessionStaysActiveWithinTwentyMinutes() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .detached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_199),
            codexMetadata: CodexSessionMetadata(
                lastUserPrompt: "Follow-up prompt",
                lastAssistantMessage: "Last assistant message"
            )
        )

        #expect(session.islandPresence(at: referenceDate) == .active)
        #expect(session.spotlightShowsDetailLines(at: referenceDate))
    }

    @Test
    func completionReplyRecipientCoversEveryAgentTool() {
        let expectedNames: [(AgentTool, String)] = [
            (.claudeCode, "Claude"),
            (.codex, "Codex"),
            (.geminiCLI, "Gemini"),
            (.openCode, "OpenCode"),
            (.qoder, "Qoder"),
            (.qwenCode, "Qwen Code"),
            (.factory, "Factory"),
            (.codebuddy, "CodeBuddy"),
            (.cursor, "Cursor"),
            (.kimiCLI, "Kimi"),
        ]
        #expect(expectedNames.map { $0.0.rawValue }.sorted() == AgentTool.allCases.map(\.rawValue).sorted())

        for (tool, expectedName) in expectedNames {
            let session = AgentSession(
                id: "\(tool.rawValue)-session",
                title: "\(expectedName) · worktree",
                tool: tool,
                phase: .completed,
                summary: "Ready",
                updatedAt: .now
            )

            #expect(session.completionReplyRecipientName == expectedName)
        }
    }

    @Test
    func completedSessionBecomesV8StaleAfterFiveMinutes() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-301)
        )

        #expect(session.isStaleCompletedForIsland(at: referenceDate))
        #expect(session.islandPresence(at: referenceDate) == .active)
    }

    @Test
    func completedSessionDoesNotBecomeV8StaleWhenThresholdIsNever() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-86_400)
        )

        #expect(!session.isStaleCompletedForIsland(
            at: referenceDate,
            threshold: IslandCompletedStaleThreshold.never.seconds
        ))
    }

    @Test
    func nonCompletedSessionsDoNotBecomeV8Stale() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: referenceDate.addingTimeInterval(-3_600)
        )

        #expect(!session.isStaleCompletedForIsland(at: referenceDate))
    }

    @Test
    func liveHeadlineUsesLatestPromptForAttachedSession() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "codex ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Start by fixing the island hover behavior.",
                lastUserPrompt: "Now make the overlay height fit the content.",
                lastAssistantMessage: "Updating the layout logic."
            )
        )

        // Headline uses initial prompt (session topic), prompt line uses latest
        #expect(session.spotlightHeadlineText == "worktree · Start by fixing the island hover behavior.")
        #expect(session.spotlightPromptLineText == "You: Now make the overlay height fit the content.")
    }

    @Test
    func detachedSessionHeadlineShowsInitialPrompt() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .detached,
            phase: .completed,
            summary: "Done",
            updatedAt: Date.now.addingTimeInterval(-30),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Start by fixing the island hover behavior.",
                lastUserPrompt: "Now make the overlay height fit the content.",
                lastAssistantMessage: "Updating the layout logic."
            )
        )

        #expect(session.spotlightHeadlineText == "worktree · Start by fixing the island hover behavior.")
        #expect(session.spotlightPromptLineText == "You: Now make the overlay height fit the content.")
    }

    @Test
    func completedSessionShowsDifferentHeadlineAndPrompt() {
        let now = Date.now
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Done",
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "codex ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Commit the README change.",
                lastUserPrompt: "Also confirm the worktree status.",
                lastAssistantMessage: "Committed and verified."
            )
        )

        #expect(session.spotlightHeadlineText == "worktree · Commit the README change.")
        #expect(session.spotlightPromptLineText == "You: Also confirm the worktree status.")
        #expect(session.notificationHeaderPromptLineText == nil)
    }

    @Test
    func runningCodexSessionWithoutToolShowsThinkingBesidePrompt() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Thinking.",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            codexMetadata: CodexSessionMetadata(
                lastUserPrompt: "Align the Codex statuses."
            )
        )

        #expect(session.spotlightPromptLineText == "You: Align the Codex statuses.")
        #expect(session.spotlightActivityLineText == "Thinking")
        #expect(session.displayCurrentToolName == nil)
    }

    @Test
    func runningCodexSessionKeepsWriteStdinAsInput() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running input.",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            codexMetadata: CodexSessionMetadata(
                lastUserPrompt: "Continue the command.",
                currentTool: "write_stdin",
                currentCommandPreview: "y"
            )
        )

        #expect(session.spotlightActivityLineText == "Input y")
        #expect(session.spotlightStatusLabel == "Live · Input")
        #expect(session.displayCurrentToolName == "Input")
    }

    @Test
    func runningCodexSessionDisplaysWebSearchAction() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running web search.",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            codexMetadata: CodexSessionMetadata(
                lastUserPrompt: "Check the Codex repo.",
                currentTool: "web_search",
                currentCommandPreview: "Codex rollout ResponseItem"
            )
        )

        #expect(session.spotlightActivityLineText == "Search Codex rollout ResponseItem")
        #expect(session.spotlightStatusLabel == "Live · Search")
        #expect(session.spotlightSecondaryText == "Running Search")
        #expect(session.displayCurrentToolName == "Search")
    }

    @Test
    func codexChildThreadIsRecognizedAsSubagent() {
        let session = AgentSession(
            id: "child",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: .now,
            codexMetadata: CodexSessionMetadata(parentThreadID: "parent")
        )

        #expect(session.isSubagentSession)
    }

    @Test
    func codexDesktopRootWorkspaceUsesRolloutRepositoryPath() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · /",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Thinking",
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "/",
                paneTitle: "Codex",
                workingDirectory: "/",
                codexThreadID: "session-1"
            ),
            codexMetadata: CodexSessionMetadata(
                workspacePath: "/Users/aditya/Developer/projects/open-vibe-island"
            )
        )

        #expect(session.spotlightWorkspaceName == "open-vibe-island")
        #expect(session.spotlightHeadlineText == "open-vibe-island")
    }

    @Test
    func usageProviderSelectionFollowsActiveHarnessAndAllowsInspectionOverride() {
        let available = UsageProvider.allCases

        // Every harness selects its own provider; harnesses without one fall
        // back to the first pill that has data.
        for tool in AgentTool.allCases {
            let expected = UsageProvider(tool: tool) ?? available.first
            #expect(
                UsageProviderSelection.selected(
                    available: available,
                    activeTool: tool,
                    override: nil
                ) == expected,
                "\(tool.rawValue) selected the wrong usage provider"
            )
        }

        // A manual pick from the dropdown outranks the active harness.
        for provider in available {
            #expect(
                UsageProviderSelection.selected(
                    available: available,
                    activeTool: .codex,
                    override: provider
                ) == provider
            )
        }

        // An override for a provider without data is ignored.
        #expect(
            UsageProviderSelection.selected(
                available: [.codex],
                activeTool: nil,
                override: .claude
            ) == .codex
        )
        #expect(
            UsageProviderSelection.selected(
                available: [],
                activeTool: .claudeCode,
                override: .claude
            ) == nil
        )
    }

    @Test
    func usageProviderMapsOnlyFirstPartyHarnesses() {
        #expect(UsageProvider(tool: .claudeCode) == .claude)
        #expect(UsageProvider(tool: .codex) == .codex)
        #expect(UsageProvider(tool: nil) == nil)

        // Claude Code forks share the hook format but bill their own vendors,
        // so they must not adopt Claude's usage windows.
        let unmapped = AgentTool.allCases.filter { $0 != .claudeCode && $0 != .codex }
        for tool in unmapped {
            #expect(UsageProvider(tool: tool) == nil, "\(tool.rawValue) should not map to a usage provider")
        }

        // Every provider round-trips through its raw identifier.
        for provider in UsageProvider.allCases {
            #expect(UsageProvider(rawValue: provider.id) == provider)
        }
    }

    @Test
    func usageProviderRegistryIsSelfConsistent() {
        for provider in UsageProvider.allCases {
            #expect(provider.title.isEmpty == false)
            #expect(provider.shortTitle.isEmpty == false)
            #expect(provider.pollInterval > .zero)

            // A provider is either toggleable in Settings (key + label) or
            // gated by its install state — never half of each.
            #expect((provider.optInDefaultsKey == nil) == (provider.optInLabelKey == nil))
        }

        // Identifiers and labels stay distinct so pills and defaults keys
        // cannot shadow each other.
        #expect(Set(UsageProvider.allCases.map(\.id)).count == UsageProvider.allCases.count)
        #expect(Set(UsageProvider.allCases.map(\.shortTitle)).count == UsageProvider.allCases.count)
        #expect(Set(UsageProvider.optional.compactMap(\.optInDefaultsKey)).count == UsageProvider.optional.count)

        #expect(UsageProvider.optional.allSatisfy { $0.optInDefaultsKey != nil })
        #expect(UsageProvider.optional.contains(.codex))
        // Claude usage is gated by installing the status line bridge instead.
        #expect(UsageProvider.optional.contains(.claude) == false)
    }

    @Test
    func usageSnapshotsNormalizeIntoProviderAgnosticWindows() {
        let resetsAt = Date(timeIntervalSince1970: 20_000)
        let claude = ClaudeUsageSnapshot(
            fiveHour: ClaudeUsageWindow(usedPercentage: 42.4, resetsAt: resetsAt),
            sevenDay: ClaudeUsageWindow(usedPercentage: 91.6, resetsAt: nil),
            cachedAt: Date(timeIntervalSince1970: 10_000)
        )

        #expect(claude.windowSummaries.map(\.label) == ["5h", "7d"])
        #expect(claude.windowSummaries.map(\.roundedUsedPercentage) == [42, 92])
        #expect(claude.windowSummaries.first?.resetsAt == resetsAt)
        #expect(claude.summarizedAt == Date(timeIntervalSince1970: 10_000))

        // A snapshot with only one window still normalizes cleanly.
        let partial = ClaudeUsageSnapshot(
            fiveHour: nil,
            sevenDay: ClaudeUsageWindow(usedPercentage: 5, resetsAt: nil)
        )
        #expect(partial.windowSummaries.map(\.key) == ["7d"])

        let codex = CodexUsageSnapshot(
            sourceFilePath: "/tmp/rollout.jsonl",
            capturedAt: Date(timeIntervalSince1970: 30_000),
            windows: [
                CodexUsageWindow(
                    key: "primary",
                    label: "5h",
                    usedPercentage: 12.5,
                    leftPercentage: 87.5,
                    windowMinutes: 300,
                    resetsAt: resetsAt
                ),
                CodexUsageWindow(
                    key: "secondary",
                    label: "7d",
                    usedPercentage: 60,
                    leftPercentage: 40,
                    windowMinutes: 10_080,
                    resetsAt: nil
                ),
            ]
        )

        #expect(codex.windowSummaries.map(\.key) == ["primary", "secondary"])
        #expect(codex.windowSummaries.map(\.label) == ["5h", "7d"])
        #expect(codex.windowSummaries.map(\.roundedUsedPercentage) == [13, 60])
        #expect(codex.summarizedAt == Date(timeIntervalSince1970: 30_000))

        // Peak selection drives the collapsed pill for either provider.
        let claudeStatus = UsageProviderStatus(
            provider: .claude,
            windows: claude.windowSummaries,
            capturedAt: claude.summarizedAt
        )
        #expect(claudeStatus.peakWindowLabel == "7d")
        #expect(claudeStatus.peakUsagePercentage == 92)

        let codexStatus = UsageProviderStatus(
            provider: .codex,
            windows: codex.windowSummaries,
            capturedAt: codex.summarizedAt
        )
        #expect(codexStatus.peakWindowLabel == "7d")
        #expect(codexStatus.peakUsagePercentage == 60)
        #expect(codexStatus.shortTitle == UsageProvider.codex.shortTitle)
    }

    @Test
    func injectedContextAndInternalApprovalPayloadStayOutOfSessionRows() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Done",
            updatedAt: .now,
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "<recommended_plugins>internal setup</recommended_plugins>",
                lastUserPrompt: """
                # Files mentioned by the user:
                ## screenshot.png

                ## My request for Codex:
                Fix the session list.
                """,
                lastAssistantMessage: #"{"risk_level":"low","outcome":"allow","rationale":"internal"}"#
            )
        )

        #expect(session.spotlightHeadlineText == "worktree")
        #expect(session.spotlightPromptLineText == "You: Fix the session list.")
        #expect(session.spotlightActivityLineText == "Completed")

        var attachmentOnlySession = session
        attachmentOnlySession.codexMetadata?.lastUserPrompt = """
        # Files mentioned by the user:
        ## screenshot.png
        """
        #expect(attachmentOnlySession.spotlightPromptLineText == nil)
    }
}
