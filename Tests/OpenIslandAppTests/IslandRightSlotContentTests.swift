import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-322 Part B — the closed pill's right-slot priority ladder.
///
/// The ladder is the whole point of the ticket: attention → task counter →
/// critical usage → the user's resting preference. Every case here is
/// given/when/then against the pure `IslandRightSlotResolver`, so nothing
/// depends on an overlay, a usage cache or the wall clock.
struct IslandRightSlotResolverTests {

    // MARK: - Priority ladder

    /// Permission outranks question: an approval blocks the agent's next tool
    /// call, an unanswered question only blocks the conversation.
    @Test
    func permissionBeatsQuestionWhenBothAreWaiting() {
        let content = IslandRightSlotResolver.content(
            attention: .init(count: 2, hasPermission: true),
            spotlightTasks: .init(),
            worstUsage: nil,
            preferred: .count(5)
        )
        #expect(content == .attentionCount(count: 2, kind: .permission))
    }

    /// With nobody waiting on an approval, the badge speaks the question kind.
    @Test
    func questionKindWhenNoApprovalIsPending() {
        let content = IslandRightSlotResolver.content(
            attention: .init(count: 1, hasPermission: false),
            spotlightTasks: .init(),
            worstUsage: nil,
            preferred: .count(5)
        )
        #expect(content == .attentionCount(count: 1, kind: .question))
    }

    /// Any attention outranks a busy task list — the pill's job while blocked
    /// is to say "you are the blocker", not to narrate progress.
    @Test
    func anyAttentionBeatsTaskCounter() {
        let content = IslandRightSlotResolver.content(
            attention: .init(count: 1, hasPermission: false),
            spotlightTasks: .init(isRunning: true, completed: 2, total: 5, subagents: 3),
            worstUsage: .init(percent: 99, windowLabel: "5h", providerTitle: "Claude"),
            preferred: .count(4)
        )
        #expect(content == .attentionCount(count: 1, kind: .question))
    }

    /// Tasks outrank usage: what the agent is doing right now beats a rate
    /// limit that will still be there in a minute.
    @Test
    func taskCounterBeatsUsage() {
        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(isRunning: true, completed: 2, total: 5, subagents: 0),
            worstUsage: .init(percent: 97, windowLabel: "7d", providerTitle: "Claude"),
            preferred: .count(1)
        )
        #expect(content == .taskCounter(completed: 2, total: 5, subagents: 0))
    }

    /// A pure subagent fan-out with no todo list still counts as work to report.
    @Test
    func taskCounterIsEmittedForSubagentsWithoutTasks() {
        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(isRunning: true, completed: 0, total: 0, subagents: 3),
            worstUsage: nil,
            preferred: .count(1)
        )
        #expect(content == .taskCounter(completed: 0, total: 0, subagents: 3))
    }

    /// Nothing to count → the ladder falls through to the preference.
    @Test
    func taskCounterIsSkippedWhenThereIsNoWorkToReport() {
        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(isRunning: true, completed: 0, total: 0, subagents: 0),
            worstUsage: nil,
            preferred: .count(2)
        )
        #expect(content == .count(2))
    }

    /// A finished / waiting spotlight would leave a frozen counter on the pill,
    /// so only a running session narrates progress.
    @Test
    func taskCounterRequiresARunningSpotlight() {
        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(isRunning: false, completed: 2, total: 5, subagents: 3),
            worstUsage: nil,
            preferred: .count(2)
        )
        #expect(content == .count(2))
    }

    /// Below the threshold usage is noise, not news.
    @Test
    func usageBelowThresholdIsNotReported() {
        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: .init(percent: 89.4, windowLabel: "5h", providerTitle: "Claude"),
            preferred: .count(3)
        )
        #expect(content == .count(3))
    }

    /// Exactly at the threshold the badge appears — the comparison is `>=`.
    @Test
    func usageAtThresholdIsReported() {
        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: .init(percent: 90.0, windowLabel: "5h", providerTitle: "Claude"),
            preferred: .count(3)
        )
        #expect(content == .usage(percent: 90, windowLabel: "5h", providerTitle: "Claude"))
    }

    /// The threshold reads the raw percentage, not the rounded display value —
    /// `89.6%` renders as "90%" but is still below the line, so it stays quiet
    /// rather than flickering the badge on and off around the boundary.
    @Test
    func usageThresholdComparesRawPercentageNotTheRoundedOne() {
        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: .init(percent: 89.6, windowLabel: "5h", providerTitle: "Claude"),
            preferred: nil
        )
        #expect(content == nil)
    }

    /// The reported percentage is rounded for display.
    @Test
    func usagePercentIsRoundedForDisplay() {
        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: .init(percent: 96.7, windowLabel: "weekly", providerTitle: "Codex"),
            preferred: nil
        )
        #expect(content == .usage(percent: 97, windowLabel: "weekly", providerTitle: "Codex"))
    }

    /// Quiet state: the user's preference is what's left.
    @Test
    func fallsThroughToTheUserPreference() {
        let quiet = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: .init(percent: 12, windowLabel: "5h", providerTitle: "Claude"),
            preferred: .count(4)
        )
        #expect(quiet == .count(4))

        let grid = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: nil,
            preferred: .agents([.session(color: .red, state: .running)])
        )
        #expect(grid == .agents([.session(color: .red, state: .running)]))

        let off = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: nil,
            preferred: nil
        )
        #expect(off == nil)
    }

    /// A `.none` preference silences the *resting* content, not a blocked
    /// agent — the pill must still be able to report that it needs the user.
    @Test
    func attentionOverridesANonePreference() {
        let content = IslandRightSlotResolver.content(
            attention: .init(count: 3, hasPermission: true),
            spotlightTasks: .init(),
            worstUsage: nil,
            preferred: nil
        )
        #expect(content == .attentionCount(count: 3, kind: .permission))
    }

    // MARK: - Readings from live state

    /// The badge counts blocked *sessions*. Three sessions, two of them
    /// waiting, is `2` — not the number of sessions, and not the number of
    /// pending requests.
    @Test
    func attentionReadingCountsWaitingSessions() {
        let sessions = [
            makeSession(id: "run", phase: .running),
            makeSession(
                id: "approve",
                phase: .waitingForApproval,
                permissionRequest: PermissionRequest(title: "edit", summary: "edit", affectedPath: "/tmp/x")
            ),
            makeSession(id: "ask", phase: .waitingForAnswer),
        ]

        let reading = IslandRightSlotResolver.attentionReading(for: sessions)
        #expect(reading.count == 2)
        #expect(reading.hasPermission)
    }

    /// Only questions pending → the group verdict is `.question`.
    @Test
    func attentionReadingReportsQuestionWhenNoApprovalIsPending() {
        let reading = IslandRightSlotResolver.attentionReading(for: [
            makeSession(id: "ask", phase: .waitingForAnswer),
            makeSession(id: "run", phase: .running),
        ])
        #expect(reading.count == 1)
        #expect(reading.hasPermission == false)
    }

    /// `completed` counts `.completed` statuses in `activeTasks`; `total` is
    /// every task; `subagents` is the fan-out width.
    @Test
    func taskReadingCountsCompletedStatusesAndSubagents() {
        var session = makeSession(id: "s", phase: .running)
        session.claudeMetadata = ClaudeSessionMetadata(
            activeSubagents: [
                ClaudeSubagentInfo(agentID: "a"),
                ClaudeSubagentInfo(agentID: "b"),
            ],
            activeTasks: [
                ClaudeTaskInfo(id: "1", title: "one", status: .completed),
                ClaudeTaskInfo(id: "2", title: "two", status: .inProgress),
                ClaudeTaskInfo(id: "3", title: "three", status: .pending),
                ClaudeTaskInfo(id: "4", title: "four", status: .completed),
            ]
        )

        let reading = IslandRightSlotResolver.taskReading(for: session)
        #expect(reading.isRunning)
        #expect(reading.completed == 2)
        #expect(reading.total == 4)
        #expect(reading.subagents == 2)
        #expect(reading.hasWorkToReport)
    }

    /// A non-Claude (or metadata-less) session simply has nothing to count.
    @Test
    func taskReadingIsEmptyWithoutMetadata() {
        var session = makeSession(id: "s", phase: .running)
        session.claudeMetadata = nil

        let reading = IslandRightSlotResolver.taskReading(for: session)
        #expect(reading.hasWorkToReport == false)
        #expect(IslandRightSlotResolver.taskReading(for: nil).hasWorkToReport == false)
    }

    /// The worst window wins across *all* providers, carrying its own labels.
    @Test
    func worstUsagePicksTheHighestWindowAcrossProviders() {
        let providers = [
            UsageProviderPresentation(id: "claude", title: "Claude", windows: [
                UsageWindowPresentation(id: "claude-5h", label: "5h", usedPercentage: 41, resetsAt: nil),
                UsageWindowPresentation(id: "claude-7d", label: "7d", usedPercentage: 88, resetsAt: nil),
            ]),
            UsageProviderPresentation(id: "codex", title: "Codex", windows: [
                UsageWindowPresentation(id: "codex-weekly", label: "weekly", usedPercentage: 93, resetsAt: nil),
            ]),
        ]

        let worst = IslandRightSlotResolver.worstUsage(in: providers)
        #expect(worst == .init(percent: 93, windowLabel: "weekly", providerTitle: "Codex"))
        #expect(IslandRightSlotResolver.worstUsage(in: []) == nil)
    }

    // MARK: - Themed fallback rendering

    /// Every new kind degrades to a number the shipped count badge can draw —
    /// a theme without a dedicated rendering must never show a blank slot.
    @Test
    func newKindsDegradeToACountBadgeValue() {
        #expect(IslandRightSlotContent.count(4).fallbackBadgeCount == 4)
        #expect(IslandRightSlotContent.attentionCount(count: 2, kind: .permission).fallbackBadgeCount == 2)
        #expect(IslandRightSlotContent.taskCounter(completed: 2, total: 5, subagents: 3).fallbackBadgeCount == 5)
        // Pure fan-out: no todo list, so the badge shows the subagent width
        // instead of a bare "×0".
        #expect(IslandRightSlotContent.taskCounter(completed: 0, total: 0, subagents: 3).fallbackBadgeCount == 3)
        #expect(IslandRightSlotContent.usage(percent: 93, windowLabel: "7d", providerTitle: "Claude").fallbackBadgeCount == 93)
        // The grid keeps its own rendering.
        #expect(IslandRightSlotContent.agents([]).fallbackBadgeCount == nil)
    }

    /// The pill reserves the width of the number it will actually draw, so the
    /// new kinds share the badge's width math.
    @MainActor
    @Test
    func intrinsicWidthOfNewKindsMatchesTheirBadgeWidth() {
        #expect(
            V6RightSlotView.intrinsicWidth(of: .attentionCount(count: 2, kind: .permission))
                == V6RightSlotView.intrinsicWidth(of: .count(2))
        )
        #expect(
            V6RightSlotView.intrinsicWidth(of: .usage(percent: 93, windowLabel: "7d", providerTitle: "Claude"))
                == V6RightSlotView.intrinsicWidth(of: .count(93))
        )
    }

    // MARK: - helpers

    private func makeSession(
        id: String,
        phase: SessionPhase,
        permissionRequest: PermissionRequest? = nil
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · \(id)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            firstSeenAt: Date(timeIntervalSince1970: 1_000),
            permissionRequest: permissionRequest,
            claudeMetadata: ClaudeSessionMetadata(transcriptPath: "/tmp/\(id).jsonl")
        )
        session.isProcessAlive = true
        session.isHookManaged = true
        return session
    }
}

/// The `AppModel` side of AB-322 Part B: the adapter feeds live state into the
/// resolver, so what the agents are doing outranks the resting preference.
@MainActor
struct IslandRightSlotAdapterTests {

    @Test
    func waitingSessionOverridesTheAgentsGridPreference() {
        let model = AppModel()
        // Pin the preference on *both* display profiles: which one is active
        // resolves from the attached screens asynchronously, so setting only
        // `islandRightSlot` would land in whichever bucket happened to be
        // active at that instant.
        setRightSlotPreference(.agents, on: model)

        let now = Date.now
        model.state = SessionState(sessions: [
            makeSession(id: "run", phase: .running, at: now),
            makeSession(
                id: "approve",
                phase: .waitingForApproval,
                at: now,
                permissionRequest: PermissionRequest(title: "edit", summary: "edit", affectedPath: "/tmp/x")
            ),
        ])

        #expect(model.islandClosedRightSlotContent() == .attentionCount(count: 1, kind: .permission))

        // The preference itself is untouched — it still resolves to the grid.
        guard case .agents(let cells)? = model.islandPreferredRightSlotContent() else {
            Issue.record("Expected the preference to still resolve to .agents")
            return
        }
        #expect(cells.count == 2)
    }

    @Test
    func runningSpotlightWithTasksReportsProgress() {
        let model = AppModel()
        setRightSlotPreference(.count, on: model)

        let now = Date.now
        var session = makeSession(id: "run", phase: .running, at: now)
        session.claudeMetadata = ClaudeSessionMetadata(
            transcriptPath: "/tmp/run.jsonl",
            activeSubagents: [ClaudeSubagentInfo(agentID: "a")],
            activeTasks: [
                ClaudeTaskInfo(id: "1", title: "one", status: .completed),
                ClaudeTaskInfo(id: "2", title: "two", status: .pending),
            ]
        )
        model.state = SessionState(sessions: [session])

        #expect(model.islandClosedRightSlotContent() == .taskCounter(completed: 1, total: 2, subagents: 1))
    }

    /// Quiet state with no tasks and no usage cache: the preference wins, i.e.
    /// the shipped `.count` / `.agents` behaviour is unchanged.
    @Test
    func quietStateStillRendersThePreference() {
        let model = AppModel()
        setRightSlotPreference(.count, on: model)

        let now = Date.now
        model.state = SessionState(sessions: [
            makeSession(id: "run", phase: .running, at: now),
            makeSession(id: "run-2", phase: .running, at: now),
        ])

        #expect(model.islandClosedRightSlotContent() == .count(2))
    }

    private func setRightSlotPreference(_ slot: IslandRightSlot, on model: AppModel) {
        model.updateAppearancePreferences(for: .notch) { $0.rightSlot = slot }
        model.updateAppearancePreferences(for: .topBar) { $0.rightSlot = slot }
    }

    private func makeSession(
        id: String,
        phase: SessionPhase,
        at date: Date,
        permissionRequest: PermissionRequest? = nil
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · \(id)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: date,
            firstSeenAt: date,
            permissionRequest: permissionRequest,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: id,
                paneTitle: "claude ~/\(id)",
                workingDirectory: "/tmp/\(id)",
                terminalSessionID: "ghostty-\(id)"
            ),
            claudeMetadata: ClaudeSessionMetadata(transcriptPath: "/tmp/\(id).jsonl")
        )
        session.isProcessAlive = true
        session.isHookManaged = true
        return session
    }
}
