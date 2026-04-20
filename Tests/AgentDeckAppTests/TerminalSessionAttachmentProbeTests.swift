import Foundation
import Testing
@testable import AgentDeckApp
import AgentDeckCore

struct TerminalSessionAttachmentProbeTests {
    @Test
    func ghosttyKeepsOnlyNewestSessionAttachedPerSnapshot() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let older = ghosttySession(
            id: "older",
            updatedAt: now.addingTimeInterval(-60),
            phase: .completed,
            terminalSessionID: "ghostty-1"
        )
        let newer = ghosttySession(
            id: "newer",
            updatedAt: now,
            phase: .running,
            terminalSessionID: "ghostty-1"
        )

        let updates = probe.attachmentStates(
            for: [older, newer],
            ghosttyAvailability: .available(
                [.init(sessionID: "ghostty-1", workingDirectory: "/tmp/worktree", title: "codex ~/tmp/worktree")],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(updates["newer"] == .attached)
        #expect(updates["older"] == .stale)
    }

    @Test
    func ghosttyStableIdentifierPreventsWorkingDirectoryFallbackMatches() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = ghosttySession(
            id: "session-1",
            updatedAt: now.addingTimeInterval(-30),
            phase: .running,
            terminalSessionID: "ghostty-stale",
            paneTitle: "codex ~/tmp/worktree"
        )

        let updates = probe.attachmentStates(
            for: [session],
            ghosttyAvailability: .available(
                [.init(sessionID: "ghostty-active", workingDirectory: "/tmp/worktree", title: "codex ~/tmp/worktree")],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(updates["session-1"] == .stale)
    }

    @Test
    func ghosttyRehomesMisbindingWhenRecordedTerminalIsAlreadyClaimed() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let primary = ghosttySession(
            id: "primary",
            updatedAt: now,
            phase: .running,
            terminalSessionID: "ghostty-1",
            workingDirectory: "/tmp/worktree"
        )
        let rehomed = ghosttySession(
            id: "rehomed",
            updatedAt: now.addingTimeInterval(-30),
            phase: .completed,
            terminalSessionID: "ghostty-1",
            paneTitle: "codex ~/tmp/worktree",
            workingDirectory: "/tmp/personal",
            workspaceName: "worktree"
        )

        let resolutions = probe.sessionResolutions(
            for: [primary, rehomed],
            ghosttyAvailability: .available(
                [
                    .init(sessionID: "ghostty-1", workingDirectory: "/tmp/worktree", title: "codex ~/tmp/worktree"),
                    .init(sessionID: "ghostty-2", workingDirectory: "/tmp/personal", title: "codex ~/tmp/personal"),
                ],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(resolutions["primary"]?.attachmentState == .attached)
        #expect(resolutions["rehomed"]?.attachmentState == .attached)
        #expect(resolutions["rehomed"]?.correctedJumpTarget?.terminalSessionID == "ghostty-2")
        #expect(resolutions["rehomed"]?.correctedJumpTarget?.paneTitle == "codex ~/tmp/personal")
        #expect(resolutions["rehomed"]?.correctedJumpTarget?.workspaceName == "personal")
    }

    @Test
    func ghosttyRehomesFromTitleWorkspaceWhenJumpTargetDirectoryIsWrong() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let primary = ghosttySession(
            id: "primary",
            updatedAt: now,
            phase: .running,
            terminalSessionID: "ghostty-1",
            workingDirectory: "/tmp/agent-deck",
            workspaceName: "agent-deck"
        )
        let rehomed = AgentSession(
            id: "rehomed",
            title: "Codex · claude-research",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Summary",
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "agent-deck",
                paneTitle: "codex ~/tmp/agent-deck",
                workingDirectory: "/tmp/agent-deck",
                terminalSessionID: "ghostty-1"
            )
        )

        let resolutions = probe.sessionResolutions(
            for: [primary, rehomed],
            ghosttyAvailability: .available(
                [
                    .init(sessionID: "ghostty-1", workingDirectory: "/tmp/agent-deck", title: "codex ~/tmp/agent-deck"),
                    .init(sessionID: "ghostty-2", workingDirectory: "/tmp/claude-research", title: "codex ~/tmp/claude-research"),
                ],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(resolutions["primary"]?.attachmentState == .attached)
        #expect(resolutions["rehomed"]?.attachmentState == .attached)
        #expect(resolutions["rehomed"]?.correctedJumpTarget?.terminalSessionID == "ghostty-2")
        #expect(resolutions["rehomed"]?.correctedJumpTarget?.workspaceName == "claude-research")
        #expect(resolutions["rehomed"]?.correctedJumpTarget?.workingDirectory == "/tmp/claude-research")
    }

    @Test
    func explicitTerminalMissDropsRecentlyAttachedSessionOutOfLiveState() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = terminalSession(
            id: "session-1",
            updatedAt: now.addingTimeInterval(-30),
            phase: .running,
            tty: "/dev/ttys001",
            codexMetadata: CodexSessionMetadata(currentTool: "Bash")
        )

        let updates = probe.attachmentStates(
            for: [session],
            ghosttyAvailability: .available([] as [TerminalSessionAttachmentProbe.GhosttyTerminalSnapshot], appIsRunning: false),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: true),
            now: now
        )

        #expect(updates["session-1"] == .stale)
    }

    @Test
    func unavailableGhosttyProbeRetainsRecentGraceState() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = ghosttySession(
            id: "session-1",
            updatedAt: now.addingTimeInterval(-30),
            phase: .running,
            terminalSessionID: "ghostty-1"
        )

        let updates = probe.attachmentStates(
            for: [session],
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(updates["session-1"] == .attached)
    }

    @Test
    func coldStartProbeDoesNotReviveRecentSessionWithoutAuthoritativeTerminalData() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = ghosttySession(
            id: "session-1",
            updatedAt: now.addingTimeInterval(-30),
            phase: .running,
            terminalSessionID: "ghostty-1"
        )

        let report = probe.sessionResolutionReport(
            for: [session],
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            allowRecentAttachmentGrace: false,
            now: now
        )

        #expect(report.isAuthoritative == false)
        #expect(report.resolutions["session-1"]?.attachmentState == .stale)
    }

    @Test
    func unavailableGhosttyProbeStillAttachesActiveCompletedCodexSession() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = ghosttySession(
            id: "session-1",
            updatedAt: now.addingTimeInterval(-600),
            phase: .completed,
            terminalSessionID: "ghostty-stale"
        )

        let updates = probe.attachmentStates(
            for: [session],
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: [
                .init(tool: .codex, sessionID: "session-1", workingDirectory: "/tmp/worktree", terminalTTY: "/dev/ttys000"),
            ],
            now: now
        )

        #expect(updates["session-1"] == .attached)
    }

    @Test
    func unavailableGhosttyProbeStillAttachesActiveClaudeSession() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = AgentSession(
            id: "claude-session",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Recovered Claude session",
            updatedAt: now.addingTimeInterval(-600),
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "agent-deck",
                paneTitle: "Claude e45d5e87",
                workingDirectory: "/tmp/agent-deck"
            )
        )

        let updates = probe.attachmentStates(
            for: [session],
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: [
                .init(tool: .claudeCode, sessionID: nil, workingDirectory: "/tmp/agent-deck", terminalTTY: "/dev/ttys002"),
            ],
            now: now
        )

        #expect(updates["claude-session"] == .attached)
    }

    @Test
    func activeClaudeProcessDoesNotAttachAmbiguousSameDirectorySessionsWithoutStrongerSignals() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let currentSession = AgentSession(
            id: "claude-current",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Current session",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "agent-deck",
                paneTitle: "Claude current",
                workingDirectory: "/tmp/agent-deck"
            )
        )
        let olderSession = AgentSession(
            id: "claude-older",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Older session",
            updatedAt: now.addingTimeInterval(-18 * 3_600),
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "agent-deck",
                paneTitle: "Claude older",
                workingDirectory: "/tmp/agent-deck"
            )
        )

        let updates = probe.attachmentStates(
            for: [currentSession, olderSession],
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: [
                .init(tool: .claudeCode, sessionID: nil, workingDirectory: "/tmp/agent-deck", terminalTTY: "/dev/ttys002"),
            ],
            now: now
        )

        #expect(updates["claude-current"] != .attached)
        #expect(updates["claude-older"] != .attached)
    }

    @Test
    func activeClaudeProcessMatchesExactSessionIDBeforeWorkingDirectoryFallback() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let resumedSession = AgentSession(
            id: "9df061a9-6836-4ccb-b83b-aea3196eca43",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Resumed session",
            updatedAt: now.addingTimeInterval(-18 * 3_600),
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "agent-deck",
                paneTitle: "Claude resumed",
                workingDirectory: "/tmp/agent-deck"
            )
        )
        let newerSession = AgentSession(
            id: "claude-current",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Current session",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "agent-deck",
                paneTitle: "Claude current",
                workingDirectory: "/tmp/agent-deck"
            )
        )

        let updates = probe.attachmentStates(
            for: [resumedSession, newerSession],
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: [
                .init(
                    tool: .claudeCode,
                    sessionID: "9df061a9-6836-4ccb-b83b-aea3196eca43",
                    workingDirectory: "/tmp/agent-deck",
                    terminalTTY: "/dev/ttys002"
                ),
            ],
            now: now
        )

        #expect(updates["9df061a9-6836-4ccb-b83b-aea3196eca43"] == .attached)
        #expect(updates["claude-current"] != .attached)
    }

    @Test
    func ghosttyExactMatchPrefersRunningClaudeSessionOverNewerCompletedSession() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let runningSession = AgentSession(
            id: "claude-running",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .running,
            summary: "Running Claude",
            updatedAt: now.addingTimeInterval(-120),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "agent-deck",
                paneTitle: "claude --dangerously ~/p/agent-deck",
                workingDirectory: "/tmp/agent-deck",
                terminalSessionID: "ghostty-claude"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/claude-running.jsonl",
                currentTool: "Task"
            )
        )
        let completedSession = AgentSession(
            id: "claude-completed",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Completed Claude",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "agent-deck",
                paneTitle: "claude --dangerously ~/p/agent-deck",
                workingDirectory: "/tmp/agent-deck",
                terminalSessionID: "ghostty-claude"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/claude-completed.jsonl",
                lastAssistantMessage: "Done."
            )
        )

        let updates = probe.attachmentStates(
            for: [completedSession, runningSession],
            ghosttyAvailability: .available(
                [.init(sessionID: "ghostty-claude", workingDirectory: "/tmp/agent-deck", title: "claude --dangerously ~/p/agent-deck")],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(updates["claude-running"] == .attached)
        #expect(updates["claude-completed"] != .attached)
    }

    @Test
    func activeClaudeProcessCanFallbackToUniqueTTYMatch() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let currentSession = AgentSession(
            id: "claude-current",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Current session",
            updatedAt: now.addingTimeInterval(-600),
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "agent-deck",
                paneTitle: "Claude current",
                workingDirectory: "/tmp/agent-deck",
                terminalTTY: "/dev/ttys002"
            )
        )
        let olderSession = AgentSession(
            id: "claude-older",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Older session",
            updatedAt: now.addingTimeInterval(-18 * 3_600),
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "agent-deck",
                paneTitle: "Claude older",
                workingDirectory: "/tmp/agent-deck",
                terminalTTY: "/dev/ttys099"
            )
        )

        let updates = probe.attachmentStates(
            for: [currentSession, olderSession],
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: [
                .init(tool: .claudeCode, sessionID: nil, workingDirectory: "/tmp/agent-deck", terminalTTY: "/dev/ttys002"),
            ],
            now: now
        )

        #expect(updates["claude-current"] == .attached)
        #expect(updates["claude-older"] != .attached)
    }

    @Test
    func unknownTerminalSessionRehomesToGhosttyFromWorkingDirectory() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = AgentSession(
            id: "claude-session",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .running,
            summary: "Running Task tool",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "agent-deck",
                paneTitle: "Claude 12345678",
                workingDirectory: "/tmp/agent-deck"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/session.jsonl",
                currentTool: "Task"
            )
        )

        let resolutions = probe.sessionResolutions(
            for: [session],
            ghosttyAvailability: .available(
                [.init(sessionID: "ghostty-1", workingDirectory: "/tmp/agent-deck", title: "claude ~/tmp/agent-deck")],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(resolutions["claude-session"]?.attachmentState == .attached)
        #expect(resolutions["claude-session"]?.correctedJumpTarget?.terminalApp == "Ghostty")
        #expect(resolutions["claude-session"]?.correctedJumpTarget?.terminalSessionID == "ghostty-1")
        #expect(resolutions["claude-session"]?.correctedJumpTarget?.workingDirectory == "/tmp/agent-deck")
    }

    @Test
    func activeCodexSessionRehomesToRemainingGhosttySnapshot() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let primary = ghosttySession(
            id: "primary",
            updatedAt: now,
            phase: .running,
            terminalSessionID: "ghostty-1",
            workingDirectory: "/tmp/agent-deck"
        )
        let activeButMisbinding = ghosttySession(
            id: "active-rehomed",
            updatedAt: now.addingTimeInterval(-30),
            phase: .running,
            terminalSessionID: "ghostty-frontmost",
            workingDirectory: "/tmp/agent-deck"
        )

        let resolutions = probe.sessionResolutions(
            for: [primary, activeButMisbinding],
            ghosttyAvailability: .available(
                [
                    .init(sessionID: "ghostty-1", workingDirectory: "/tmp/agent-deck", title: "codex ~/tmp/agent-deck"),
                    .init(sessionID: "ghostty-2", workingDirectory: "/tmp/agent-deck", title: "codex ~/tmp/agent-deck"),
                ],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: [
                .init(tool: .codex, sessionID: "primary", workingDirectory: "/tmp/agent-deck", terminalTTY: "/dev/ttys000"),
                .init(tool: .codex, sessionID: "active-rehomed", workingDirectory: "/tmp/agent-deck", terminalTTY: "/dev/ttys001"),
            ],
            now: now
        )

        #expect(resolutions["primary"]?.attachmentState == .attached)
        #expect(resolutions["active-rehomed"]?.attachmentState == .attached)
        #expect(resolutions["active-rehomed"]?.correctedJumpTarget?.terminalSessionID == "ghostty-2")
    }

    @Test
    func activeCodexSessionBeatsStaleExactGhosttyBinding() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let primary = ghosttySession(
            id: "primary",
            updatedAt: now,
            phase: .running,
            terminalSessionID: "ghostty-1",
            workingDirectory: "/tmp/agent-deck"
        )
        let activeRehomed = ghosttySession(
            id: "active-rehomed",
            updatedAt: now.addingTimeInterval(-30),
            phase: .running,
            terminalSessionID: "ghostty-frontmost",
            workingDirectory: "/tmp/agent-deck"
        )
        let staleExact = ghosttySession(
            id: "stale-exact",
            updatedAt: now.addingTimeInterval(-18 * 3_600),
            phase: .completed,
            terminalSessionID: "ghostty-2",
            workingDirectory: "/tmp/agent-deck"
        )

        let resolutions = probe.sessionResolutions(
            for: [primary, activeRehomed, staleExact],
            ghosttyAvailability: .available(
                [
                    .init(sessionID: "ghostty-1", workingDirectory: "/tmp/agent-deck", title: "codex ~/tmp/agent-deck"),
                    .init(sessionID: "ghostty-2", workingDirectory: "/tmp/agent-deck", title: "codex ~/tmp/agent-deck"),
                ],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: [
                .init(tool: .codex, sessionID: "primary", workingDirectory: "/tmp/agent-deck", terminalTTY: "/dev/ttys000"),
                .init(tool: .codex, sessionID: "active-rehomed", workingDirectory: "/tmp/agent-deck", terminalTTY: "/dev/ttys001"),
            ],
            now: now
        )

        #expect(resolutions["primary"]?.attachmentState == .attached)
        #expect(resolutions["active-rehomed"]?.attachmentState == .attached)
        #expect(resolutions["active-rehomed"]?.correctedJumpTarget?.terminalSessionID == "ghostty-2")
        #expect(resolutions["stale-exact"]?.attachmentState != .attached)
    }

    @Test
    func claudeSessionIDPrefixInGhosttyTitleBeatsSameDirectoryCodexSession() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let codexSession = ghosttySession(
            id: "codex-session",
            updatedAt: now,
            phase: .running,
            terminalSessionID: "ghostty-codex",
            workingDirectory: "/tmp/agent-deck"
        )
        let claudeSession = AgentSession(
            id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .running,
            summary: "Running Claude",
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "agent-deck",
                paneTitle: "Claude e45d5e87",
                workingDirectory: "/tmp/agent-deck"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/e45d5e87.jsonl",
                currentTool: "Task"
            )
        )

        let resolutions = probe.sessionResolutions(
            for: [codexSession, claudeSession],
            ghosttyAvailability: .available(
                [
                    .init(sessionID: "ghostty-codex", workingDirectory: "/tmp/agent-deck", title: "codex ~/tmp/agent-deck"),
                    .init(sessionID: "ghostty-claude", workingDirectory: "/tmp/agent-deck", title: "agent-deck · hi · e45d5e87-66d0-4f"),
                ],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: [
                .init(tool: .codex, sessionID: "codex-session", workingDirectory: "/tmp/agent-deck", terminalTTY: "/dev/ttys000"),
                .init(tool: .claudeCode, sessionID: nil, workingDirectory: "/tmp/agent-deck", terminalTTY: "/dev/ttys002"),
            ],
            now: now
        )

        #expect(resolutions["codex-session"]?.attachmentState == .attached)
        #expect(resolutions["e45d5e87-66d0-4f67-8399-6ebc02f3d453"]?.attachmentState == .attached)
        #expect(resolutions["e45d5e87-66d0-4f67-8399-6ebc02f3d453"]?.correctedJumpTarget?.terminalSessionID == "ghostty-claude")
        #expect(resolutions["e45d5e87-66d0-4f67-8399-6ebc02f3d453"]?.correctedJumpTarget?.paneTitle == "agent-deck · hi · e45d5e87-66d0-4f")
    }

    @Test
    func claudePrefixClaimOverridesMisbindingRecordedGhosttySessionID() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let misboundCodexSession = ghosttySession(
            id: "misbound-codex",
            updatedAt: now,
            phase: .running,
            terminalSessionID: "ghostty-claude",
            paneTitle: "agent-deck · hi · e45d5e87-66d0-4f",
            workingDirectory: "/tmp/agent-deck"
        )
        let claudeSession = AgentSession(
            id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
            title: "Claude · agent-deck",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .running,
            summary: "Running Claude",
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "agent-deck",
                paneTitle: "Claude e45d5e87",
                workingDirectory: "/tmp/agent-deck"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/e45d5e87.jsonl",
                currentTool: "Task"
            )
        )

        let resolutions = probe.sessionResolutions(
            for: [misboundCodexSession, claudeSession],
            ghosttyAvailability: .available(
                [
                    .init(sessionID: "ghostty-claude", workingDirectory: "/tmp/agent-deck", title: "agent-deck · hi · e45d5e87-66d0-4f"),
                    .init(sessionID: "ghostty-codex", workingDirectory: "/tmp/agent-deck", title: "codex ~/tmp/agent-deck"),
                ],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: [
                .init(tool: .codex, sessionID: "misbound-codex", workingDirectory: "/tmp/agent-deck", terminalTTY: "/dev/ttys001"),
                .init(tool: .claudeCode, sessionID: nil, workingDirectory: "/tmp/agent-deck", terminalTTY: "/dev/ttys002"),
            ],
            now: now
        )

        #expect(resolutions["e45d5e87-66d0-4f67-8399-6ebc02f3d453"]?.attachmentState == .attached)
        #expect(resolutions["e45d5e87-66d0-4f67-8399-6ebc02f3d453"]?.correctedJumpTarget?.terminalSessionID == "ghostty-claude")
        #expect(resolutions["misbound-codex"]?.attachmentState == .attached)
        #expect(resolutions["misbound-codex"]?.correctedJumpTarget?.terminalSessionID == "ghostty-codex")
    }

    @Test
    func activeCodexSessionWithoutJumpTargetCanAttachFromProcessWorkingDirectory() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = AgentSession(
            id: "active-no-jump-target",
            title: "Codex · agent-deck",
            tool: .codex,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Finished",
            updatedAt: now
        )

        let resolutions = probe.sessionResolutions(
            for: [session],
            ghosttyAvailability: .available(
                [.init(sessionID: "ghostty-codex", workingDirectory: "/tmp/agent-deck", title: "codex ~/tmp/agent-deck")],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: [
                .init(tool: .codex, sessionID: "active-no-jump-target", workingDirectory: "/tmp/VIBE-island", terminalTTY: "/dev/ttys012"),
            ],
            now: now
        )

        #expect(resolutions["active-no-jump-target"]?.attachmentState == .attached)
        #expect(resolutions["active-no-jump-target"]?.correctedJumpTarget?.terminalSessionID == "ghostty-codex")
        #expect(resolutions["active-no-jump-target"]?.correctedJumpTarget?.workingDirectory == "/tmp/agent-deck")
    }

    @Test
    func ghosttySessionListRegressionOnlyKeepsLiveLookingTabsAttached() {
        let now = Date(timeIntervalSince1970: 10_000)
        let probe = TerminalSessionAttachmentProbe()
        let sessions = [
            ghosttySession(
                id: "019d540b-0985-7913-9ad1-0e87f12c918f",
                updatedAt: now.addingTimeInterval(-30),
                phase: .running,
                terminalSessionID: "8B3E80D7-26C5-457E-A390-2F0B8B584EF2",
                paneTitle: "codex ~/p/agent-deck",
                workingDirectory: "/Users/wangruobing/personal/agent-deck",
                workspaceName: "agent-deck"
            ),
            ghosttySession(
                id: "019d52de-0a11-7053-adf2-76f106393e42",
                updatedAt: now.addingTimeInterval(-18 * 3_600),
                phase: .completed,
                terminalSessionID: "448D7E28-24FB-46F1-9504-C252F97926C1",
                paneTitle: "codex ~/p/agent-deck",
                workingDirectory: "/Users/wangruobing/personal/agent-deck",
                workspaceName: "agent-deck"
            ),
            ghosttySession(
                id: "019d52dd-8e5a-7602-b618-3f4ec447ac72",
                updatedAt: now.addingTimeInterval(-18 * 3_600),
                phase: .completed,
                terminalSessionID: "1FF8D5F5-7C34-4CC7-BF93-4F67DA197E5D",
                paneTitle: "codex ~/p/agent-deck",
                workingDirectory: "/Users/wangruobing/personal/agent-deck",
                workspaceName: "agent-deck"
            ),
            ghosttySession(
                id: "019d52ee-55b3-7712-9c3b-b2d9c038e04d",
                updatedAt: now.addingTimeInterval(-18 * 3_600),
                phase: .completed,
                terminalSessionID: "BAA8EBC8-DC99-4720-9F14-A6BAF55DFC62",
                paneTitle: "codex ~/p/agent-deck",
                workingDirectory: "/Users/wangruobing/personal/agent-deck",
                workspaceName: "agent-deck"
            ),
            ghosttySession(
                id: "019d51f5-0234-7ec3-9494-8b0e4d1b670e",
                updatedAt: now.addingTimeInterval(-18 * 3_600),
                phase: .completed,
                terminalSessionID: "DD5A5488-E789-4326-BA5C-6A0BDFB0A51F",
                paneTitle: "codex ~/p/agent-deck",
                workingDirectory: "/Users/wangruobing/personal/agent-deck",
                workspaceName: "agent-deck"
            ),
            AgentSession(
                id: "session-approval",
                title: "Codex · agent-deck",
                tool: .codex,
                origin: .live,
                attachmentState: .attached,
                phase: .waitingForApproval,
                summary: "Approval needed",
                updatedAt: now.addingTimeInterval(-18 * 3_600),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "agent-deck",
                    paneTitle: "codex ~/p/agent-deck",
                    workingDirectory: "/Users/wangruobing/personal/agent-deck",
                    terminalSessionID: "ghostty-approval"
                ),
                codexMetadata: CodexSessionMetadata(
                    currentTool: "exec_command",
                    currentCommandPreview: "head -5000 ControlCenterView.swift"
                )
            ),
        ]

        let updates = probe.attachmentStates(
            for: sessions,
            ghosttyAvailability: .available(
                [
                    .init(
                        sessionID: "8B3E80D7-26C5-457E-A390-2F0B8B584EF2",
                        workingDirectory: "/Users/wangruobing/personal/agent-deck",
                        title: "codex ~/p/agent-deck"
                    ),
                    .init(
                        sessionID: "448D7E28-24FB-46F1-9504-C252F97926C1",
                        workingDirectory: "/Users/wangruobing/personal/agent-deck",
                        title: "codex ~/p/agent-deck"
                    ),
                    .init(
                        sessionID: "1FF8D5F5-7C34-4CC7-BF93-4F67DA197E5D",
                        workingDirectory: "/Users/wangruobing/personal/agent-deck",
                        title: "~/p/agent-deck"
                    ),
                    .init(
                        sessionID: "BAA8EBC8-DC99-4720-9F14-A6BAF55DFC62",
                        workingDirectory: "/Users/wangruobing/personal/agent-deck",
                        title: "~/p/agent-deck"
                    ),
                    .init(
                        sessionID: "DD5A5488-E789-4326-BA5C-6A0BDFB0A51F",
                        workingDirectory: "/Users/wangruobing/personal/agent-deck",
                        title: "~/p/agent-deck"
                    ),
                ],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(updates["019d540b-0985-7913-9ad1-0e87f12c918f"] == .attached)
        #expect(updates["019d52de-0a11-7053-adf2-76f106393e42"] == .attached)
        #expect(updates["019d52dd-8e5a-7602-b618-3f4ec447ac72"] == .detached)
        #expect(updates["019d52ee-55b3-7712-9c3b-b2d9c038e04d"] == .detached)
        #expect(updates["019d51f5-0234-7ec3-9494-8b0e4d1b670e"] == .detached)
        #expect(updates["session-approval"] == .detached)
    }

    @Test
    func ghosttyPlainShellTitleDoesNotFallbackAttachOlderSessionByDirectory() {
        let now = Date(timeIntervalSince1970: 2_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = AgentSession(
            id: "older-shell-session",
            title: "Codex · agent-deck",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Finished",
            updatedAt: now.addingTimeInterval(-18 * 3_600),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "agent-deck",
                paneTitle: "codex ~/p/agent-deck",
                workingDirectory: "/tmp/agent-deck"
            )
        )

        let updates = probe.attachmentStates(
            for: [session],
            ghosttyAvailability: .available(
                [.init(sessionID: "ghostty-shell", workingDirectory: "/tmp/agent-deck", title: "~/p/agent-deck")],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(updates["older-shell-session"] == .detached)
    }

    private func ghosttySession(
        id: String,
        updatedAt: Date,
        phase: SessionPhase,
        terminalSessionID: String,
        paneTitle: String = "codex ~/tmp/worktree",
        workingDirectory: String = "/tmp/worktree",
        workspaceName: String = "worktree",
        codexMetadata: CodexSessionMetadata? = nil
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(workspaceName)",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "Summary",
            updatedAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspaceName,
                paneTitle: paneTitle,
                workingDirectory: workingDirectory,
                terminalSessionID: terminalSessionID
            ),
            codexMetadata: codexMetadata
        )
    }

    private func terminalSession(
        id: String,
        updatedAt: Date,
        phase: SessionPhase,
        tty: String,
        codexMetadata: CodexSessionMetadata? = nil
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "Summary",
            updatedAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workspaceName: "worktree",
                paneTitle: "codex ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalTTY: tty
            ),
            codexMetadata: codexMetadata
        )
    }
}
