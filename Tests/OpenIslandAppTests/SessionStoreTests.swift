import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct SessionStoreTests {

    // MARK: - Helpers

    private func makeStore() -> SessionStore {
        SessionStore()
    }

    private static let t0 = Date(timeIntervalSince1970: 1_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_001_000)

    // MARK: - 1. applySessionStartedCreatesSession

    @Test
    func applySessionStartedCreatesSession() {
        let store = makeStore()
        let t = Self.t0

        let claudeMeta = ClaudeSessionMetadata(
            transcriptPath: "/tmp/session.jsonl",
            initialUserPrompt: "Write tests",
            lastUserPrompt: "Write tests",
            lastAssistantMessage: "Done",
            currentTool: "Bash",
            currentToolInputPreview: "swift test",
            model: "claude-opus-4",
            worktreeBranch: "feat/tests",
            customTitle: "My Session",
            activeSubagents: [],
            activeTasks: []
        )
        let jump = JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "main",
            paneTitle: "claude ~/project",
            workingDirectory: "/tmp/project",
            terminalSessionID: "ghostty-1",
            terminalTTY: "/dev/ttys001"
        )
        let payload = SessionStarted(
            sessionID: "sess-1",
            title: "My Session",
            tool: .claudeCode,
            origin: .live,
            initialPhase: .running,
            summary: "Working on tests",
            timestamp: t,
            jumpTarget: jump,
            claudeMetadata: claudeMeta,
            isRemote: false
        )

        store.applyHookEvent(.sessionStarted(payload))

        let s = store.session(id: "sess-1")
        #expect(s != nil)
        #expect(s?.id == "sess-1")
        #expect(s?.tool == .claudeCode)
        #expect(s?.phase == .running)
        #expect(s?.summary == "Working on tests")
        #expect(s?.startedAt == t)
        #expect(s?.lastActivityAt == t)
        #expect(s?.processState == .alive)
        #expect(s?.customTitle == "My Session")
        #expect(s?.transcriptPath == "/tmp/session.jsonl")
        #expect(s?.workingDirectory == "/tmp/project")
        #expect(s?.terminal?.app == "Ghostty")
        #expect(s?.terminal?.tty == "/dev/ttys001")
        #expect(s?.terminal?.terminalSessionID == "ghostty-1")
        #expect(s?.metadata.initialPrompt == "Write tests")
        #expect(s?.metadata.currentTool == "Bash")
        #expect(s?.metadata.model == "claude-opus-4")
        #expect(s?.metadata.worktreeBranch == "feat/tests")
        #expect(s?.isRemote == false)
        #expect(s?.origin == .live)
    }

    // MARK: - 2. applyActivityUpdatedUpdatesPhaseAndSummary

    @Test
    func applyActivityUpdatedUpdatesPhaseAndSummary() {
        let store = makeStore()
        let t0 = Self.t0
        let t1 = Self.t1

        // First create the session
        let started = SessionStarted(
            sessionID: "sess-2",
            title: "Session 2",
            tool: .claudeCode,
            summary: "Starting",
            timestamp: t0
        )
        store.applyHookEvent(.sessionStarted(started))
        let originalStartedAt = store.session(id: "sess-2")?.startedAt

        // Now send an activity update
        let activity = SessionActivityUpdated(
            sessionID: "sess-2",
            summary: "Still working",
            phase: .running,
            timestamp: t1
        )
        store.applyHookEvent(.activityUpdated(activity))

        let s = store.session(id: "sess-2")
        #expect(s?.phase == .running)
        #expect(s?.summary == "Still working")
        #expect(s?.lastActivityAt == t1)
        // startedAt must be preserved from the original event
        #expect(s?.startedAt == originalStartedAt)
        #expect(s?.startedAt == t0)
    }

    // MARK: - 3. hookEventCreatesSessionIfNotExists

    @Test
    func hookEventCreatesSessionIfNotExists() {
        let store = makeStore()
        let t = Self.t0

        // Send activityUpdated for a session that has never been started
        let activity = SessionActivityUpdated(
            sessionID: "unknown-sess",
            summary: "Doing something",
            phase: .running,
            timestamp: t
        )
        store.applyHookEvent(.activityUpdated(activity))

        let s = store.session(id: "unknown-sess")
        #expect(s != nil, "Session must be auto-created for unknown ID")
        #expect(s?.phase == .running)
        #expect(s?.processState == .alive)
    }

    // MARK: - 4. restoreFromTranscriptsCreatesSession

    @Test
    func restoreFromTranscriptsCreatesSession() {
        let store = makeStore()
        let t0 = Self.t0
        let t1 = Self.t1

        let transcript = DiscoveredTranscript(
            sessionID: "transcript-1",
            transcriptPath: "/tmp/transcript-1.jsonl",
            workingDirectory: "/tmp/myproject",
            startedAt: t0,
            lastActivityAt: t1,
            customTitle: "My Custom Title",
            initialPrompt: "Initial task",
            lastPrompt: "Last task",
            lastAssistantMessage: "I finished",
            model: "claude-3-5-sonnet"
        )

        store.restoreFromTranscripts([transcript])

        let s = store.session(id: "transcript-1")
        #expect(s != nil)
        #expect(s?.processState == .unknown)
        #expect(s?.phase == .completed)
        #expect(s?.customTitle == "My Custom Title")
        #expect(s?.displayName == "My Custom Title")
        #expect(s?.transcriptPath == "/tmp/transcript-1.jsonl")
        #expect(s?.workingDirectory == "/tmp/myproject")
        #expect(s?.startedAt == t0)
        #expect(s?.lastActivityAt == t1)
        #expect(s?.metadata.initialPrompt == "Initial task")
        #expect(s?.metadata.model == "claude-3-5-sonnet")
    }

    // MARK: - 5. hookEventDoesNotOverwriteTranscriptStartedAt

    @Test
    func hookEventDoesNotOverwriteTranscriptStartedAt() {
        let store = makeStore()
        let originalStart = Self.t0
        let hookTime = Self.t1   // later time from a live hook event

        // Restore from transcript first
        let transcript = DiscoveredTranscript(
            sessionID: "shared-sess",
            transcriptPath: "/tmp/shared.jsonl",
            startedAt: originalStart,
            lastActivityAt: originalStart
        )
        store.restoreFromTranscripts([transcript])

        // Now a live hook event arrives for the same session
        let started = SessionStarted(
            sessionID: "shared-sess",
            title: "Shared Session",
            tool: .claudeCode,
            summary: "Live now",
            timestamp: hookTime
        )
        store.applyHookEvent(.sessionStarted(started))

        let s = store.session(id: "shared-sess")
        #expect(s?.startedAt == originalStart, "Hook event must preserve the earlier startedAt from transcript restore")
        #expect(s?.processState == .alive)
        #expect(s?.phase == .running)
    }

    // MARK: - 6. pruneRemovesInvisibleSessions

    @Test
    func pruneRemovesInvisibleSessions() {
        let store = makeStore()
        let now = Self.t0
        // Long ago — outside the 20-minute grace period
        let longAgo = now.addingTimeInterval(-(25 * 60))

        // Create the old completed session via restoreFromTranscripts so that
        // processState is .unknown (not .alive) — making it prunable once the
        // grace period has elapsed.
        let oldTranscript = DiscoveredTranscript(
            sessionID: "old-sess",
            transcriptPath: "/tmp/old.jsonl",
            startedAt: longAgo,
            lastActivityAt: longAgo
        )
        store.restoreFromTranscripts([oldTranscript])

        // Session that is currently waiting for approval — must survive pruning
        let activeSession = SessionStarted(
            sessionID: "active-sess",
            title: "Active",
            tool: .claudeCode,
            initialPhase: .waitingForApproval,
            summary: "Needs approval",
            timestamp: now
        )
        store.applyHookEvent(.sessionStarted(activeSession))

        #expect(store.sessions.count == 2)

        // Prune at 'now' — the old completed session (processState=.unknown,
        // lastActivityAt outside grace period) should be removed; the
        // waitingForApproval session should remain (requiresAttention=true).
        store.pruneInvisibleSessions(at: now)

        #expect(store.sessions["old-sess"] == nil, "Expired completed session must be pruned")
        #expect(store.sessions["active-sess"] != nil, "Session waiting for approval must survive pruning")
    }
}
