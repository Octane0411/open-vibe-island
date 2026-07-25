import Foundation
import OpenIslandCore

/// Deterministic `AgentSession` (and usage) fixtures shared by the appearance
/// previews (AB-305) and the debug scenario harness (AB-326).
///
/// AB-326 promoted this from a `private enum` inside `AppearanceSettingsPane`
/// to a module-internal namespace so `IslandDebugScenario` can reuse the exact
/// same payloads instead of hand-rolling parallel copies. Two rules keep the
/// set honest and reproducible:
///
/// 1. **Injected clock.** Every date is an offset from a caller-supplied `now`.
///    Nothing here reads `Date()`/`.now`, so a given `now` produces a byte-for-byte
///    identical fixture — the property the snapshot harness (T09) leans on.
/// 2. **Stable identities.** Every `UUID` (`PermissionRequest`, `QuestionPrompt`,
///    `QuestionOption`) is derived from a seed string via ``stableID(_:)`` rather
///    than `UUID()`, so `AgentSession` equality holds across calls and the
///    fixtures never carry invented data shapes — only real model fields.
///
/// Every fixture is `origin: .demo`.
enum AppearancePreviewFixtures {
    // MARK: - Deterministic identity

    /// A reproducible `UUID` seeded from a string. The first 16 UTF-8 bytes of
    /// the seed (zero-padded) become the UUID bytes, so the same seed always
    /// yields the same id — which is what lets whole `AgentSession`s (with their
    /// nested `PermissionRequest` / `QuestionPrompt` UUIDs) compare equal across
    /// two fixture builds.
    static func stableID(_ seed: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in seed.utf8.enumerated() where index < 16 {
            bytes[index] = byte
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - Baseline session set (AB-305)

    /// The original five-state baseline the appearance previews render. One per
    /// live state — running, needs-approval, needs-answer, recently-completed
    /// (`done`) and stale-completed (`idle`) — spread across agents and projects
    /// so agent/project grouping forms multiple sections, and time-stamped so the
    /// recent vs. stale completed rows land on opposite sides of the staleness cut.
    ///
    /// AB-326: the running row now carries `cursorMetadata` so the narration
    /// layer (AB-321) resolves it to "Editing AppModel.swift", and the approval /
    /// question payloads carry stable ids so the whole set is deterministic.
    static func sessions(now: Date, lang: LanguageManager) -> [AgentSession] {
        // Attention order first (needs-approval, needs-answer, running, done,
        // idle) — `IslandSessionSectioning` leaves `.attention` untouched, so
        // this array *is* the attention ordering.
        [
            AgentSession(
                id: "preview-approval",
                title: "Codex · open-island",
                tool: .codex,
                origin: .demo,
                attachmentState: .attached,
                phase: .waitingForApproval,
                summary: lang.t("settings.appearance.preview.approveShellCommand"),
                updatedAt: now.addingTimeInterval(-90),
                permissionRequest: PermissionRequest(
                    id: stableID("preview-approval-permission"),
                    title: lang.t("approval.toolPermissionRequested"),
                    summary: lang.t("settings.appearance.preview.approveShellCommand"),
                    affectedPath: "Sources/OpenIslandApp/Views/SettingsView.swift",
                    primaryActionTitle: "Allow",
                    secondaryActionTitle: "Deny"
                ),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "codex ~/open-island",
                    terminalSessionID: "preview-approval"
                )
            ),
            AgentSession(
                id: "preview-answer",
                title: "Claude · open-island",
                tool: .claudeCode,
                origin: .demo,
                attachmentState: .attached,
                phase: .waitingForAnswer,
                summary: lang.t("settings.appearance.preview.waitingForAnswer"),
                updatedAt: now.addingTimeInterval(-150),
                questionPrompt: QuestionPrompt(
                    id: stableID("preview-answer-prompt"),
                    title: lang.t("settings.appearance.preview.waitingForAnswer"),
                    questions: [
                        QuestionPromptItem(
                            question: lang.t("settings.appearance.preview.waitingForAnswer"),
                            header: "",
                            options: [
                                QuestionOption(id: stableID("preview-answer-ship"), label: "Ship it"),
                                QuestionOption(id: stableID("preview-answer-revise"), label: "Revise"),
                            ]
                        )
                    ]
                ),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "claude ~/open-island",
                    terminalSessionID: "preview-answer"
                )
            ),
            AgentSession(
                id: "preview-running",
                title: "Cursor · website",
                tool: .cursor,
                origin: .demo,
                attachmentState: .attached,
                phase: .running,
                summary: lang.t("settings.appearance.preview.editingSessionListPreview"),
                updatedAt: now.addingTimeInterval(-30),
                jumpTarget: JumpTarget(
                    terminalApp: "Cursor",
                    workspaceName: "website",
                    paneTitle: "cursor ~/website",
                    terminalSessionID: "preview-running"
                ),
                // AB-326 item 11: currentTool + preview drive the narration layer
                // (`AgentSession.narratedActivity`) to render "Editing AppModel.swift".
                cursorMetadata: CursorSessionMetadata(
                    currentTool: "Edit",
                    currentToolInputPreview: "Sources/OpenIslandApp/AppModel.swift"
                )
            ),
            AgentSession(
                id: "preview-done",
                title: "Gemini · docs",
                tool: .geminiCLI,
                origin: .demo,
                attachmentState: .attached,
                phase: .completed,
                summary: lang.t("settings.appearance.preview.replyAvailable"),
                updatedAt: now.addingTimeInterval(-45),
                jumpTarget: JumpTarget(
                    terminalApp: "WezTerm",
                    workspaceName: "docs",
                    paneTitle: "gemini ~/docs",
                    terminalSessionID: "preview-done"
                )
            ),
            AgentSession(
                id: "preview-idle",
                title: "Codex · open-island",
                tool: .codex,
                origin: .demo,
                attachmentState: .attached,
                phase: .completed,
                summary: lang.t("settings.appearance.preview.completedEarlier"),
                updatedAt: now.addingTimeInterval(-25 * 60),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "codex ~/open-island",
                    terminalSessionID: "preview-idle"
                )
            ),
        ]
    }

    // MARK: - Empty state (AB-326 item 10)

    /// Explicit zero-session state, so the empty scaffold can be exercised
    /// without smuggling in a "happens to be empty right now" list.
    static let empty: [AgentSession] = []

    // MARK: - Completion outcomes (AB-326 items 1–2)

    /// Claude turn that ended via Ctrl-C — `outcome: .interrupted` refines the
    /// `.completed` phase so tint/glyph/label can tell it apart from a clean
    /// success. Workspace `niche-radar`, finished 4m ago.
    static func completedInterrupted(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-completed-interrupted",
            title: "Claude · niche-radar",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            outcome: .interrupted,
            summary: "Stopped mid-refactor before the extraction finished.",
            updatedAt: now.addingTimeInterval(-4 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "niche-radar",
                paneTitle: "claude ~/niche-radar",
                terminalSessionID: "fixture-completed-interrupted"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                initialUserPrompt: "Extract the ranking heuristics into their own module.",
                lastUserPrompt: "^C",
                lastAssistantMessage: "Interrupted while moving the scorer — no files were left half-written."
            )
        )
    }

    /// Codex turn that ended in failure — `outcome: .failed`. Workspace
    /// `open-vibe-island`, finished 9m ago.
    static func completedFailed(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-completed-failed",
            title: "Codex · open-vibe-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            outcome: .failed,
            summary: "Build failed: 2 errors in BridgeServer.swift.",
            updatedAt: now.addingTimeInterval(-9 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-vibe-island",
                paneTitle: "codex ~/open-vibe-island",
                terminalSessionID: "fixture-completed-failed"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Wire the new usage envelope through the bridge.",
                lastUserPrompt: "Wire the new usage envelope through the bridge.",
                lastAssistantMessage: "swift build exited non-zero — BridgeServer.swift has two type errors I could not resolve."
            )
        )
    }

    // MARK: - Duplicate-workspace trio (AB-326 item 3)

    /// Three sessions that all collide on workspace `the-automator`, exercising
    /// AB-323's list-level disambiguation:
    ///
    /// - `[0]` Claude on `feat/bridge-auth` (running) → unique branch suffix.
    /// - `[1]` Claude on `main` (running, three subagents) → unique branch suffix.
    /// - `[2]` Codex, no branch, updated 12m ago → recency fallback (branch is
    ///   Claude-only ground truth, so a Codex row can never claim one).
    static func duplicateWorkspaceTrio(now: Date) -> [AgentSession] {
        [
            AgentSession(
                id: "fixture-trio-claude-bridge-auth",
                title: "Claude · the-automator",
                tool: .claudeCode,
                origin: .demo,
                attachmentState: .attached,
                phase: .running,
                summary: "Adding the bridge auth handshake.",
                updatedAt: now.addingTimeInterval(-30),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "the-automator",
                    paneTitle: "claude ~/the-automator",
                    terminalSessionID: "fixture-trio-bridge-auth"
                ),
                claudeMetadata: ClaudeSessionMetadata(
                    lastUserPrompt: "Add token rotation to the bridge auth path.",
                    currentTool: "Edit",
                    currentToolInputPreview: "Sources/OpenIslandCore/BridgeServer.swift",
                    worktreeBranch: "feat/bridge-auth"
                )
            ),
            AgentSession(
                id: "fixture-trio-claude-main",
                title: "Claude · the-automator",
                tool: .claudeCode,
                origin: .demo,
                attachmentState: .attached,
                phase: .running,
                summary: "Running the release checklist.",
                updatedAt: now.addingTimeInterval(-52),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "the-automator",
                    paneTitle: "claude ~/the-automator",
                    terminalSessionID: "fixture-trio-main"
                ),
                claudeMetadata: ClaudeSessionMetadata(
                    lastUserPrompt: "Kick off the release checklist across the sub-tasks.",
                    currentTool: "Task",
                    worktreeBranch: "main",
                    activeSubagents: [
                        ClaudeSubagentInfo(
                            agentID: "trio-sub-1",
                            agentType: "Explore",
                            taskDescription: "Audit the changelog since the last tag",
                            startedAt: now.addingTimeInterval(-40)
                        ),
                        ClaudeSubagentInfo(
                            agentID: "trio-sub-2",
                            agentType: "general-purpose",
                            taskDescription: "Verify the notarization credentials",
                            startedAt: now.addingTimeInterval(-64)
                        ),
                        ClaudeSubagentInfo(
                            agentID: "trio-sub-3",
                            agentType: "Plan",
                            taskDescription: "Draft the bilingual release notes",
                            startedAt: now.addingTimeInterval(-12)
                        ),
                    ]
                )
            ),
            AgentSession(
                id: "fixture-trio-codex",
                title: "Codex · the-automator",
                tool: .codex,
                origin: .demo,
                attachmentState: .attached,
                phase: .completed,
                summary: "Regenerated the fixtures earlier.",
                updatedAt: now.addingTimeInterval(-12 * 60),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "the-automator",
                    paneTitle: "codex ~/the-automator",
                    terminalSessionID: "fixture-trio-codex"
                ),
                codexMetadata: CodexSessionMetadata(
                    initialUserPrompt: "Regenerate the preview fixtures.",
                    lastUserPrompt: "Regenerate the preview fixtures.",
                    lastAssistantMessage: "Fixtures regenerated and committed."
                )
            ),
        ]
    }

    // MARK: - Permission: shell command (AB-326 item 4)

    /// Claude asking to run a shell command. The command text rides in
    /// `claudeMetadata.currentToolInputPreview` (which `currentCommandPreviewText`
    /// surfaces as the hero's `$ …` line); the request carries a summary line, an
    /// `affectedPath`, and two real `addRules` suggestions whose `displayLabel`s
    /// read as scoped "allow running swift build …" buttons.
    static func permissionCommand(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-permission-command",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Claude wants to run a release build of the hooks binary.",
            updatedAt: now.addingTimeInterval(-14),
            permissionRequest: PermissionRequest(
                id: stableID("fixture-permission-command"),
                title: "Run shell command",
                summary: "Claude wants to run a release build of the hooks binary.",
                affectedPath: "~/Developer/open-vibe-island",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny",
                toolName: "Bash",
                suggestedUpdates: [
                    .addRules(
                        destination: .projectSettings,
                        rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "swift build")],
                        behavior: .allow
                    ),
                    .addRules(
                        destination: .userSettings,
                        rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "swift build")],
                        behavior: .allow
                    ),
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-vibe-island",
                paneTitle: "claude ~/open-vibe-island",
                terminalSessionID: "fixture-permission-command"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Build the hooks binary in release mode.",
                currentTool: "Bash",
                currentToolInputPreview: "swift build -c release --product OpenIslandHooks"
            )
        )
    }

    // MARK: - Permission: inline diff (AB-326 item 5)

    /// Claude asking to edit `AGENTS.md`, carrying a `fileDiffSource` whose
    /// old/new text differ on several lines so `PermissionDiff.compute` yields a
    /// real (>3-line) inline diff in the approval hero.
    static func permissionDiff(now: Date) -> AgentSession {
        let oldText = """
        ## Verification

        - Run swift build after each change.
        - Summarize what changed.
        - Commit on the feature branch.
        """
        let newText = """
        ## Verification

        - Run swift build and swift test after each change.
        - Capture a harness smoke run for any UI-affecting change.
        - Summarize what changed, calling out verification gaps.
        - Commit on the feature branch.
        """

        return AgentSession(
            id: "fixture-permission-diff",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Claude wants to edit AGENTS.md.",
            updatedAt: now.addingTimeInterval(-11),
            permissionRequest: PermissionRequest(
                id: stableID("fixture-permission-diff"),
                title: "Edit file",
                summary: "Claude wants to edit AGENTS.md.",
                affectedPath: "AGENTS.md",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny",
                toolName: "Edit",
                suggestedUpdates: [
                    .addRules(
                        destination: .projectSettings,
                        rules: [ClaudePermissionRuleValue(toolName: "Edit", ruleContent: "AGENTS.md")],
                        behavior: .allow
                    ),
                ],
                fileDiffSource: PermissionFileDiffSource(oldText: oldText, newText: newText)
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-vibe-island",
                paneTitle: "claude ~/open-vibe-island",
                terminalSessionID: "fixture-permission-diff"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Tighten the verification section of AGENTS.md.",
                currentTool: "Edit"
            )
        )
    }

    // MARK: - Permission: terminal-only (AB-326 item 6)

    /// Codex permission that can only be answered in the terminal. `Codex`
    /// requests set `requiresTerminalApproval: true`, so the hero swaps its
    /// Deny/Allow buttons for a "respond in terminal" CTA.
    static func codexTerminalApproval(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-codex-terminal-approval",
            title: "Codex · open-vibe-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Codex wants to run: git push origin main",
            updatedAt: now.addingTimeInterval(-16),
            permissionRequest: PermissionRequest(
                id: stableID("fixture-codex-terminal-approval"),
                title: "Approve command",
                summary: "Codex wants to run: git push origin main",
                affectedPath: "~/Developer/open-vibe-island",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny",
                toolName: "shell",
                requiresTerminalApproval: true
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "open-vibe-island",
                paneTitle: "codex ~/open-vibe-island",
                terminalSessionID: "fixture-codex-terminal-approval",
                codexThreadID: "fixture-codex-thread"
            ),
            codexMetadata: CodexSessionMetadata(
                lastUserPrompt: "Push the release commit.",
                currentTool: "shell",
                currentCommandPreview: "git push origin main"
            )
        )
    }

    // MARK: - Question: multi-question conformance set (AB-326 item 7)

    /// The shared conformance question set — headers `Auth` / `Scope` and the
    /// `Auth` question text are copied verbatim across every conformance fixture,
    /// so the same prompt exercises single-select (with per-option descriptions)
    /// and multi-select (with a freeform "Other") in one card.
    static func conformanceQuestions() -> [QuestionPromptItem] {
        [
            QuestionPromptItem(
                question: "Which auth method should the bridge use?",
                header: "Auth",
                options: [
                    QuestionOption(
                        id: stableID("conformance-auth-oauth"),
                        label: "OAuth 2.0",
                        description: "Delegated tokens that rotate automatically."
                    ),
                    QuestionOption(
                        id: stableID("conformance-auth-apikey"),
                        label: "API key",
                        description: "A single shared secret stored in the keychain."
                    ),
                    QuestionOption(
                        id: stableID("conformance-auth-mtls"),
                        label: "mTLS",
                        description: "A client certificate per machine."
                    ),
                ],
                multiSelect: false
            ),
            QuestionPromptItem(
                question: "Which surfaces should the bridge expose?",
                header: "Scope",
                options: [
                    QuestionOption(id: stableID("conformance-scope-socket"), label: "Local socket"),
                    QuestionOption(id: stableID("conformance-scope-loopback"), label: "Loopback HTTP"),
                    QuestionOption(id: stableID("conformance-scope-ssh"), label: "SSH tunnel"),
                    QuestionOption(
                        id: stableID("conformance-scope-other"),
                        label: "Other",
                        allowsFreeform: true
                    ),
                ],
                multiSelect: true
            ),
        ]
    }

    /// Claude waiting on the two-question conformance prompt.
    static func questionMulti(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-question-multi",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForAnswer,
            summary: "Claude needs two decisions before wiring the bridge.",
            updatedAt: now.addingTimeInterval(-19),
            questionPrompt: QuestionPrompt(
                id: stableID("fixture-question-multi"),
                title: "Bridge configuration",
                questions: conformanceQuestions()
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-vibe-island",
                paneTitle: "claude ~/open-vibe-island",
                terminalSessionID: "fixture-question-multi"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Design the local bridge transport.",
                currentTool: "AskUserQuestion"
            )
        )
    }

    // MARK: - Subagents + tasks (AB-326 item 8)

    /// Running Claude session fanned out across three subagents (Explore /
    /// general-purpose / Plan) with a five-item task list (two completed, one
    /// in progress, two pending) so the row's orchestration detail is fully
    /// exercised.
    static func subagentsAndTasks(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-subagents-tasks",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .running,
            summary: "Coordinating the overlay redesign rollout.",
            updatedAt: now.addingTimeInterval(-6),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-vibe-island",
                paneTitle: "claude ~/open-vibe-island",
                terminalSessionID: "fixture-subagents-tasks"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Drive the redesign tickets in parallel.",
                currentTool: "Task",
                activeSubagents: [
                    ClaudeSubagentInfo(
                        agentID: "subagent-explore",
                        agentType: "Explore",
                        taskDescription: "Map the theme token surface",
                        startedAt: now.addingTimeInterval(-42)
                    ),
                    ClaudeSubagentInfo(
                        agentID: "subagent-general",
                        agentType: "general-purpose",
                        taskDescription: "Port the session rows to Poured 2.0",
                        startedAt: now.addingTimeInterval(-75)
                    ),
                    ClaudeSubagentInfo(
                        agentID: "subagent-plan",
                        agentType: "Plan",
                        taskDescription: "Sequence the Flight Deck follow-ups",
                        startedAt: now.addingTimeInterval(-8)
                    ),
                ],
                activeTasks: [
                    ClaudeTaskInfo(id: "task-1", title: "Palette + material tokens", status: .completed),
                    ClaudeTaskInfo(id: "task-2", title: "Closed-pill ambient states", status: .completed),
                    ClaudeTaskInfo(id: "task-3", title: "Header + meters + scaffold", status: .inProgress),
                    ClaudeTaskInfo(id: "task-4", title: "Session rows", status: .pending),
                    ClaudeTaskInfo(id: "task-5", title: "Permission hero + conformance", status: .pending),
                ]
            )
        )
    }

    // MARK: - Usage meters (AB-326 item 9)

    /// Fixture usage providers exposed for the header meter path. Claude carries
    /// two windows (`5h` 34%, `7d` 78%); Codex carries one (`7d` 92%). Reset
    /// times are offsets from `now` so the "resets in …" readouts stay stable.
    /// Stage 2 injects these into the settings preview header; the debug
    /// `usageMeters` scenario feeds them to the live overlay header.
    static func usageProviders(now: Date) -> [UsageProviderPresentation] {
        [
            UsageProviderPresentation(
                id: "claude",
                title: "Claude",
                windows: [
                    UsageWindowPresentation(
                        id: "claude-5h",
                        label: "5h",
                        usedPercentage: 34,
                        resetsAt: now.addingTimeInterval(2 * 3_600 + 10 * 60)
                    ),
                    UsageWindowPresentation(
                        id: "claude-7d",
                        label: "7d",
                        usedPercentage: 78,
                        resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3_600)
                    ),
                ]
            ),
            UsageProviderPresentation(
                id: "codex",
                title: "Codex",
                windows: [
                    UsageWindowPresentation(
                        id: "codex-7d",
                        label: "7d",
                        usedPercentage: 92,
                        resetsAt: now.addingTimeInterval(19 * 3_600)
                    ),
                ]
            ),
        ]
    }
}

// MARK: - Appearance preview scenarios (AB-326 stage 2)

/// The scenarios the Settings appearance session-list preview can render. Each
/// case maps — through the pure ``AppearancePreviewFixtures/scenarioContent(_:now:lang:)``
/// resolver — to a fixture session set, an optional actionable session id (so a
/// permission / question / completion *card* renders rather than a collapsed
/// row), and optional usage providers (only the ``meters`` case populates the
/// header meters).
enum AppearancePreviewScenario: String, CaseIterable, Identifiable, Sendable {
    case list
    case permissionCommand
    case permissionDiff
    case codexApproval
    case questionMulti
    case subagents
    case completedVariants
    case duplicates
    case meters
    case empty

    var id: String { rawValue }

    /// Localization key for the picker label (en / zh-Hans / zh-Hant).
    var labelKey: String {
        "settings.appearance.previewScenario.\(rawValue)"
    }
}

/// The resolved inputs a scenario feeds into the session-list preview stage.
struct AppearancePreviewScenarioContent {
    /// The fixture sessions the preview lists.
    let sessions: [AgentSession]

    /// The session whose actionable (approval / question / completion) card the
    /// preview should expand. `nil` for the plain list / duplicates / meters /
    /// empty scenarios, where no single row is the hero.
    let actionableSessionID: String?

    /// Usage providers injected into the preview header. Non-`nil` only for the
    /// `meters` scenario; every other scenario keeps the header's default
    /// (headerless) behaviour.
    let usageProviders: [UsageProviderPresentation]?
}

extension AppearancePreviewFixtures {
    /// Pure scenario → preview-content mapping. Deterministic for a given `now`
    /// (it only composes the `now`-injected fixtures above), so the picker and
    /// its unit test resolve identical content.
    static func scenarioContent(
        _ scenario: AppearancePreviewScenario,
        now: Date,
        lang: LanguageManager
    ) -> AppearancePreviewScenarioContent {
        switch scenario {
        case .list:
            return AppearancePreviewScenarioContent(
                sessions: sessions(now: now, lang: lang),
                actionableSessionID: nil,
                usageProviders: nil
            )
        case .permissionCommand:
            let session = permissionCommand(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [session],
                actionableSessionID: session.id,
                usageProviders: nil
            )
        case .permissionDiff:
            let session = permissionDiff(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [session],
                actionableSessionID: session.id,
                usageProviders: nil
            )
        case .codexApproval:
            let session = codexTerminalApproval(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [session],
                actionableSessionID: session.id,
                usageProviders: nil
            )
        case .questionMulti:
            let session = questionMulti(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [session],
                actionableSessionID: session.id,
                usageProviders: nil
            )
        case .subagents:
            let session = subagentsAndTasks(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [session],
                actionableSessionID: session.id,
                usageProviders: nil
            )
        case .completedVariants:
            // Both outcomes in one list. `actionableSessionID` can only expand
            // one row (the scaffold keys a single hero), so the interrupted card
            // opens fully while the failed row stays outcome-differentiated but
            // collapsed — the two treatments are visible side by side.
            let interrupted = completedInterrupted(now: now)
            let failed = completedFailed(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [interrupted, failed],
                actionableSessionID: interrupted.id,
                usageProviders: nil
            )
        case .duplicates:
            return AppearancePreviewScenarioContent(
                sessions: duplicateWorkspaceTrio(now: now),
                actionableSessionID: nil,
                usageProviders: nil
            )
        case .meters:
            return AppearancePreviewScenarioContent(
                sessions: sessions(now: now, lang: lang),
                actionableSessionID: nil,
                usageProviders: usageProviders(now: now)
            )
        case .empty:
            return AppearancePreviewScenarioContent(
                sessions: empty,
                actionableSessionID: nil,
                usageProviders: nil
            )
        }
    }
}
