import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-323 — duplicate-workspace disambiguation (branch / recency).
struct SessionDisambiguationTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000)

    // MARK: - Fixtures

    private static func session(
        id: String,
        tool: AgentTool,
        workspace: String,
        branch: String? = nil,
        phase: SessionPhase = .running,
        outcome: SessionOutcome = .success,
        summary: String = "Working",
        prompt: String? = nil,
        ageSeconds: TimeInterval,
        permissionRequest: PermissionRequest? = nil,
        questionPrompt: QuestionPrompt? = nil,
        subagents: [ClaudeSubagentInfo] = []
    ) -> AgentSession {
        let claudeMetadata: ClaudeSessionMetadata? = {
            guard tool == .claudeCode else { return nil }
            return ClaudeSessionMetadata(
                initialUserPrompt: prompt,
                worktreeBranch: branch,
                activeSubagents: subagents
            )
        }()

        let codexMetadata: CodexSessionMetadata? = {
            guard tool == .codex else { return nil }
            return CodexSessionMetadata(initialUserPrompt: prompt)
        }()

        return AgentSession(
            id: id,
            title: "\(tool.displayName) · \(workspace)",
            tool: tool,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            outcome: outcome,
            summary: summary,
            updatedAt: now.addingTimeInterval(-ageSeconds),
            permissionRequest: permissionRequest,
            questionPrompt: questionPrompt,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspace,
                paneTitle: "\(tool.rawValue) ~/code/\(workspace)",
                workingDirectory: "/Users/dev/code/\(workspace)",
                terminalSessionID: "ghostty-\(id)"
            ),
            codexMetadata: codexMetadata,
            claudeMetadata: claudeMetadata
        )
    }

    // MARK: - Core rules

    @Test
    func threeIdenticalWorkspacesSplitByBranchAndRecency() {
        // BRIEF §1.4: "three identical `the-automator` rows with no
        // disambiguation" — the exact defect this helper exists to fix.
        let sessions = [
            Self.session(
                id: "claude-a",
                tool: .claudeCode,
                workspace: "the-automator",
                branch: "feat/bridge-auth",
                ageSeconds: 60
            ),
            Self.session(
                id: "claude-b",
                tool: .claudeCode,
                workspace: "the-automator",
                branch: "main",
                ageSeconds: 120
            ),
            Self.session(
                id: "codex-c",
                tool: .codex,
                workspace: "the-automator",
                ageSeconds: 12 * 60
            ),
        ]

        let result = SessionDisambiguation.disambiguators(for: sessions, now: Self.now)

        #expect(result["claude-a"] == "feat/bridge-auth")
        #expect(result["claude-b"] == "main")
        #expect(result["codex-c"] == "12m ago")
    }

    @Test
    func uniqueWorkspaceNamesGetNoDisambiguator() {
        let sessions = [
            Self.session(id: "a", tool: .claudeCode, workspace: "open-vibe-island", branch: "main", ageSeconds: 60),
            Self.session(id: "b", tool: .codex, workspace: "the-automator", ageSeconds: 120),
            Self.session(id: "c", tool: .geminiCLI, workspace: "niche-radar", ageSeconds: 180),
        ]

        let result = SessionDisambiguation.disambiguators(for: sessions, now: Self.now)

        #expect(result.isEmpty)
    }

    @Test
    func singleSessionIsNeverDisambiguated() {
        let sessions = [
            Self.session(
                id: "only",
                tool: .claudeCode,
                workspace: "the-automator",
                branch: "feat/bridge-auth",
                ageSeconds: 60
            )
        ]

        #expect(SessionDisambiguation.disambiguators(for: sessions, now: Self.now).isEmpty)
        #expect(SessionDisambiguation.disambiguator(for: sessions[0], in: sessions, now: Self.now) == nil)
    }

    @Test
    func collidedClaudeSessionsSharingABranchBothFallBackToRecency() {
        // A branch two rows agree on disambiguates nothing.
        let sessions = [
            Self.session(
                id: "claude-a",
                tool: .claudeCode,
                workspace: "the-automator",
                branch: "main",
                ageSeconds: 5 * 60
            ),
            Self.session(
                id: "claude-b",
                tool: .claudeCode,
                workspace: "the-automator",
                branch: "main",
                ageSeconds: 2 * 3_600
            ),
        ]

        let result = SessionDisambiguation.disambiguators(for: sessions, now: Self.now)

        #expect(result["claude-a"] == "5m ago")
        #expect(result["claude-b"] == "2h ago")
    }

    @Test
    func sharedBranchFallbackDoesNotDemoteASiblingWithAUniqueBranch() {
        let sessions = [
            Self.session(id: "a", tool: .claudeCode, workspace: "the-automator", branch: "main", ageSeconds: 60),
            Self.session(id: "b", tool: .claudeCode, workspace: "the-automator", branch: "main", ageSeconds: 3 * 86_400),
            Self.session(
                id: "c",
                tool: .claudeCode,
                workspace: "the-automator",
                branch: "fix/notch-hover",
                ageSeconds: 30
            ),
        ]

        let result = SessionDisambiguation.disambiguators(for: sessions, now: Self.now)

        #expect(result["a"] == "1m ago")
        #expect(result["b"] == "3d ago")
        #expect(result["c"] == "fix/notch-hover")
    }

    @Test
    func claudeSessionWithoutABranchUsesRecency() {
        let sessions = [
            Self.session(id: "a", tool: .claudeCode, workspace: "niche-radar", ageSeconds: 45),
            Self.session(
                id: "b",
                tool: .claudeCode,
                workspace: "niche-radar",
                branch: "feat/scoring",
                ageSeconds: 90
            ),
        ]

        let result = SessionDisambiguation.disambiguators(for: sessions, now: Self.now)

        #expect(result["a"] == "<1m ago")
        #expect(result["b"] == "feat/scoring")
    }

    // MARK: - Honesty gate

    @Test
    func codexSessionNeverShowsABranchEvenThoughItsHookComputesOne() {
        // `CodexHookPayload.worktreeBranch` resolves a real branch from `cwd`,
        // but nothing persists it onto the session — surfacing one would be
        // invented data (BRIEF §3, SPEC-flight-deck §6).
        let cwd = "/Users/dev/code/the-automator/.git/worktrees/feat+bridge-auth"
        #expect(WorkspaceNameResolver.worktreeBranch(for: cwd) == "feat/bridge-auth")

        let codex = AgentSession(
            id: "codex",
            title: "Codex · the-automator",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: Self.now.addingTimeInterval(-12 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "the-automator",
                paneTitle: "codex",
                workingDirectory: cwd,
                terminalSessionID: "ghostty-codex"
            )
        )
        let claude = Self.session(
            id: "claude",
            tool: .claudeCode,
            workspace: "the-automator",
            branch: "main",
            ageSeconds: 60
        )

        let result = SessionDisambiguation.disambiguators(for: [codex, claude], now: Self.now)

        #expect(SessionDisambiguation.branch(for: codex) == nil)
        #expect(result["codex"] == "12m ago")
        #expect(result["claude"] == "main")
    }

    @Test
    func nonClaudeAgentsAllFallBackToRecency() {
        let sessions = [
            Self.session(id: "gemini", tool: .geminiCLI, workspace: "niche-radar", ageSeconds: 60),
            Self.session(id: "cursor", tool: .cursor, workspace: "niche-radar", ageSeconds: 3_600),
        ]

        let result = SessionDisambiguation.disambiguators(for: sessions, now: Self.now)

        #expect(result["gemini"] == "1m ago")
        #expect(result["cursor"] == "1h ago")
    }

    // MARK: - Branch formatting

    @Test
    func branchesUnderTwentyFourCharactersRenderVerbatim() {
        let branch = "feat/bridge-auth-token" // 22
        #expect(branch.count == 22)
        #expect(SessionDisambiguation.displayBranch(branch) == branch)
    }

    @Test
    func longBranchesAreMiddleTruncatedKeepingTheLastSegment() {
        let branch = "feat/overlay/redesign-duplicate-workspace-disambiguation"
        let display = SessionDisambiguation.displayBranch(branch)

        #expect(display != branch)
        #expect(display.count < SessionDisambiguation.maxVerbatimBranchLength)
        #expect(display.hasSuffix("disambiguation"))
    }

    @Test
    func twentyFourCharacterBranchIsTruncated() {
        // "under 24 chars" is verbatim; at 24 the middle truncation kicks in.
        let branch = "feature/very-long-name-x"
        #expect(branch.count == SessionDisambiguation.maxVerbatimBranchLength)
        #expect(SessionDisambiguation.displayBranch(branch) != branch)
    }

    // MARK: - Headline integration

    @Test
    func headlineOmitsTheSuffixForUniqueNames() {
        // AB-323's intentional visible change: `(branch)` is no longer appended
        // unconditionally.
        let session = Self.session(
            id: "a",
            tool: .claudeCode,
            workspace: "open-vibe-island",
            branch: "feat/bridge-auth",
            prompt: "Wire the bridge auth handshake.",
            ageSeconds: 60
        )

        #expect(session.spotlightHeadlineText == "open-vibe-island · Wire the bridge auth handshake.")
    }

    @Test
    func headlineTakesItsSuffixFromTheSharedHelper() {
        let sessions = [
            Self.session(
                id: "a",
                tool: .claudeCode,
                workspace: "the-automator",
                branch: "feat/bridge-auth",
                prompt: "Wire the bridge auth handshake.",
                ageSeconds: 60
            ),
            Self.session(
                id: "b",
                tool: .codex,
                workspace: "the-automator",
                prompt: "Rerun the scoring backfill.",
                ageSeconds: 12 * 60
            ),
        ]
        let result = SessionDisambiguation.disambiguators(for: sessions, now: Self.now)

        #expect(
            sessions[0].spotlightHeadlineText(disambiguator: result["a"])
                == "the-automator (feat/bridge-auth) · Wire the bridge auth handshake."
        )
        #expect(
            sessions[1].spotlightHeadlineText(disambiguator: result["b"])
                == "the-automator (12m ago) · Rerun the scoring backfill."
        )
    }

    @Test
    func collisionKeyMatchesTheNameTheHeadlineRenders() {
        // No jump target and no `·` in the title: both the collision key and the
        // headline must fall back through the same chain.
        let makeSession = { (id: String, title: String) in
            AgentSession(
                id: id,
                title: title,
                tool: .claudeCode,
                origin: .live,
                phase: .running,
                summary: "Working",
                updatedAt: Self.now.addingTimeInterval(-60)
            )
        }

        let sessions = [
            makeSession("a", "Claude Code · the-automator"),
            makeSession("b", "the-automator"),
        ]

        #expect(sessions[0].spotlightDisplayName == "the-automator")
        #expect(sessions[1].spotlightDisplayName == "the-automator")

        let result = SessionDisambiguation.disambiguators(for: sessions, now: Self.now)
        #expect(result.count == 2)
        #expect(sessions[0].spotlightHeadlineText(disambiguator: result["a"]) == "the-automator (1m ago)")
    }

    @Test
    func titlelessSessionFallsBackToTheAgentDisplayName() {
        let sessions = [
            AgentSession(id: "a", title: "", tool: .claudeCode, phase: .running, summary: "Working", updatedAt: Self.now.addingTimeInterval(-60)),
            AgentSession(id: "b", title: "", tool: .claudeCode, phase: .running, summary: "Working", updatedAt: Self.now.addingTimeInterval(-3_600)),
        ]

        #expect(sessions[0].spotlightDisplayName == AgentTool.claudeCode.displayName)

        let result = SessionDisambiguation.disambiguators(for: sessions, now: Self.now)
        #expect(result["a"] == "1m ago")
        #expect(result["b"] == "1h ago")
    }

    // MARK: - BRIEF §4C / §5 realistic session set

    /// The list BRIEF §4C asks every mockup to render, using §5's mandated
    /// content: workspaces `open-vibe-island` / `the-automator` / `niche-radar`,
    /// agents claude / codex / gemini / cursor, a `swift build` permission, an
    /// `rtk grep` command, the bridge-auth question, and an AGENTS.md/CLAUDE.md
    /// completion. Two `the-automator` rows and two `niche-radar` rows collide.
    private static func briefSessionSet() -> [AgentSession] {
        [
            // Running with a live activity line.
            session(
                id: "s1",
                tool: .claudeCode,
                workspace: "open-vibe-island",
                branch: "feat/overlay-redesign",
                summary: "Editing AppModel.swift",
                prompt: "Redesign the overlay session list.",
                ageSeconds: 42
            ),
            // Waiting for permission (`swift build`).
            session(
                id: "s2",
                tool: .claudeCode,
                workspace: "the-automator",
                branch: "feat/bridge-auth",
                phase: .waitingForApproval,
                summary: "Run swift build",
                prompt: "Wire the bridge auth handshake.",
                ageSeconds: 102,
                permissionRequest: PermissionRequest(
                    title: "Run command",
                    summary: "Run `swift build` from this project",
                    affectedPath: "/Users/dev/code/the-automator"
                )
            ),
            // Waiting for an answer.
            session(
                id: "s3",
                tool: .claudeCode,
                workspace: "the-automator",
                branch: "main",
                phase: .waitingForAnswer,
                summary: "Which auth method should the bridge use?",
                prompt: "Pick the bridge auth method.",
                ageSeconds: 5 * 60
            ),
            // Completed success — the AGENTS.md/CLAUDE.md edit.
            session(
                id: "s4",
                tool: .codex,
                workspace: "niche-radar",
                phase: .completed,
                summary: "Updated AGENTS.md and CLAUDE.md",
                prompt: "Document the working agreement.",
                ageSeconds: 43 * 60
            ),
            // Completed interrupted.
            session(
                id: "s5",
                tool: .geminiCLI,
                workspace: "niche-radar",
                phase: .completed,
                outcome: .interrupted,
                summary: "rtk grep -rn \"fetch(\" packages/ui/src",
                prompt: "Find every fetch call in the UI package.",
                ageSeconds: 2 * 3_600 + 10 * 60
            ),
            // Running with subagents.
            session(
                id: "s6",
                tool: .cursor,
                workspace: "open-vibe-island",
                phase: .running,
                summary: "Reviewing the diff",
                prompt: "Review the redesign diff.",
                ageSeconds: 30
            ),
        ]
    }

    @Test
    func briefRealisticSessionSetDisambiguatesOnlyTheCollidedRows() {
        let sessions = Self.briefSessionSet()
        let result = SessionDisambiguation.disambiguators(for: sessions, now: Self.now)

        // `open-vibe-island` collides: one Claude with a branch, one Cursor.
        #expect(result["s1"] == "feat/overlay-redesign")
        #expect(result["s6"] == "<1m ago")

        // `the-automator` collides: two Claude sessions on distinct branches.
        #expect(result["s2"] == "feat/bridge-auth")
        #expect(result["s3"] == "main")

        // `niche-radar` collides: Codex + Gemini, neither can honestly show a
        // branch, so both read as recency.
        #expect(result["s4"] == "43m ago")
        #expect(result["s5"] == "2h ago")

        #expect(result.count == sessions.count)
    }

    @Test
    func briefSessionSetHeadlinesReadCleanlyWithTheirSuffixes() {
        let sessions = Self.briefSessionSet()
        let result = SessionDisambiguation.disambiguators(for: sessions, now: Self.now)

        #expect(
            sessions[1].spotlightHeadlineText(disambiguator: result["s2"])
                == "the-automator (feat/bridge-auth) · Wire the bridge auth handshake."
        )
        #expect(
            sessions[3].spotlightHeadlineText(disambiguator: result["s4"])
                == "niche-radar (43m ago) · Document the working agreement."
        )
        // Gemini carries no prompt in this fixture, so the headline is the
        // disambiguated name alone — still unambiguous against its sibling.
        #expect(
            sessions[4].spotlightHeadlineText(disambiguator: result["s5"])
                == "niche-radar (2h ago)"
        )
    }
}
