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
    func runningCodexSessionShowsActiveSubagentAsCurrentAction() {
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
                lastUserPrompt: "Use a subagent for research.",
                activeSubagents: [
                    CodexSubagentInfo(
                        agentID: "subagent-1",
                        agentType: "explorer",
                        nickname: "Ada"
                    )
                ]
            )
        )

        #expect(session.spotlightActivityLineText == "Subagent")
        #expect(session.spotlightStatusLabel == "Live · Subagent")
        #expect(session.displayCurrentToolName == "Subagent")
        #expect(session.spotlightSubagentLabel == "Subagents (1)")
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
}
