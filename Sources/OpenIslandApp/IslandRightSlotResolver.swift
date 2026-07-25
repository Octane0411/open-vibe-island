import Foundation
import OpenIslandCore

// MARK: - Attention kind

/// Which flavour of attention the closed pill's right slot is reporting.
///
/// Kept distinct from `SessionPhase` on purpose: the right slot collapses *all*
/// waiting sessions into one badge, so it needs a single verdict for the group
/// rather than a per-session phase. Permission outranks question — an approval
/// blocks the agent's next tool call, an unanswered question only blocks the
/// conversation (SPEC-poured §A3/A4, SPEC-flight-deck §Slot-1 `.seg warn/caution`).
enum IslandAttentionKind: String, Equatable, Hashable, Sendable {
    case permission
    case question
}

// MARK: - Right-slot selection

/// Pure derivation of the closed island's right-slot content (AB-322 Part B).
///
/// Same shape as ``IslandClosedLabelResolver``: every input is an argument, so
/// the priority ladder can be pinned by unit tests without standing up an
/// overlay, a usage cache or the wall clock. `AppModel.islandClosedRightSlotContent()`
/// is a thin adapter that feeds this live state.
///
/// ## Priority ladder
///
/// 1. **attention** — any session waiting outranks everything. The pill's whole
///    job in that state is "you are the blocker".
/// 2. **task counter** — the spotlight session's todo / subagent fan-out, so a
///    long run reads as progress rather than an opaque spinner.
/// 3. **usage** — only once the worst window is *critical*
///    (``usageAlertThreshold``); below that it is noise, not news.
/// 4. **user preference** — the shipped `.count` / `.agents` / none rendering.
///
/// The first three deliberately override the user's `islandRightSlot`
/// preference (including `.none`): the preference chooses the *resting*
/// content, not whether the island is allowed to report that it is blocked.
enum IslandRightSlotResolver {

    /// Usage percentage at or above which the closed pill starts reporting the
    /// worst window in the right slot.
    ///
    /// **Reconciliation note.** The specs disagree on where "critical" starts:
    /// Poured (§I) and Instrument put the critical dial/tag at `>= 90`, while
    /// Flight Deck's usage tape (§Slot-2) draws a caution tick at `70` and a red
    /// tick at `90`. Rather than let the *content selection* differ per theme —
    /// which would make the pill say different things depending on skin — the
    /// threshold is one cross-theme constant at **90**, matching the already
    /// shipped `isCritical: window.usedPercentage >= 90` in every usage gauge.
    /// Themes remain free to style the badge differently below/above their own
    /// caution marks.
    static let usageAlertThreshold: Double = 90

    // MARK: Inputs

    /// How many surfaced sessions are waiting, and on what.
    struct AttentionReading: Equatable, Sendable {
        /// Sessions — never requests — currently in an attention phase. A single
        /// session with three queued approvals is still one blocked agent.
        var count: Int
        /// Whether at least one of them is waiting for an approval.
        var hasPermission: Bool

        init(count: Int = 0, hasPermission: Bool = false) {
            self.count = count
            self.hasPermission = hasPermission
        }
    }

    /// The spotlight session's in-flight work.
    struct TaskReading: Equatable, Sendable {
        /// Only a running session narrates progress — a finished or waiting one
        /// would leave a frozen counter on the pill.
        var isRunning: Bool
        var completed: Int
        var total: Int
        var subagents: Int

        init(isRunning: Bool = false, completed: Int = 0, total: Int = 0, subagents: Int = 0) {
            self.isRunning = isRunning
            self.completed = completed
            self.total = total
            self.subagents = subagents
        }

        /// There is something to count: a todo list, a subagent fan-out, or both.
        var hasWorkToReport: Bool { total > 0 || subagents > 0 }
    }

    /// The worst rate-limit window across every visible provider.
    struct UsageReading: Equatable, Sendable {
        /// Raw percentage — the threshold compares against this, *not* the
        /// rounded display value, so `89.6%` stays quiet even though it renders
        /// as `90%`.
        var percent: Double
        /// The window's short label (`5h`, `7d`, `weekly`).
        var windowLabel: String
        /// The provider it belongs to (`Claude`, `Codex`).
        var providerTitle: String

        init(percent: Double, windowLabel: String, providerTitle: String) {
            self.percent = percent
            self.windowLabel = windowLabel
            self.providerTitle = providerTitle
        }
    }

    // MARK: Decision

    /// The closed pill's right-slot payload, or `nil` when nothing outranks a
    /// `.none` preference.
    ///
    /// - Parameters:
    ///   - attention: waiting-session counts and kind for the surfaced set.
    ///   - spotlightTasks: the spotlight session's todo / subagent progress.
    ///   - worstUsage: the worst usage window across providers, or `nil` when
    ///     usage is hidden / unavailable.
    ///   - preferred: what the user's `islandRightSlot` preference resolves to
    ///     (`.count(n)`, `.agents(cells)` or `nil`).
    static func content(
        attention: AttentionReading,
        spotlightTasks: TaskReading,
        worstUsage: UsageReading?,
        preferred: IslandRightSlotContent?
    ) -> IslandRightSlotContent? {
        if attention.count > 0 {
            return .attentionCount(
                count: attention.count,
                kind: attention.hasPermission ? .permission : .question
            )
        }

        if spotlightTasks.isRunning, spotlightTasks.hasWorkToReport {
            return .taskCounter(
                completed: spotlightTasks.completed,
                total: spotlightTasks.total,
                subagents: spotlightTasks.subagents
            )
        }

        if let usage = worstUsage, usage.percent >= usageAlertThreshold {
            return .usage(
                percent: Int(usage.percent.rounded()),
                windowLabel: usage.windowLabel,
                providerTitle: usage.providerTitle
            )
        }

        return preferred
    }

    // MARK: Readings from live state

    /// Waiting sessions in the surfaced set. Counts *sessions*, so the badge
    /// answers "how many agents are stuck on me", not "how many dialogs exist".
    static func attentionReading(for sessions: [AgentSession]) -> AttentionReading {
        let waiting = sessions.filter { $0.phase.requiresAttention }
        return AttentionReading(
            count: waiting.count,
            hasPermission: waiting.contains { $0.phase == .waitingForApproval }
        )
    }

    /// The spotlight session's todo list and subagent fan-out. Non-Claude
    /// sessions (no `claudeMetadata`) simply report nothing to count.
    static func taskReading(for spotlight: AgentSession?) -> TaskReading {
        guard let session = spotlight else { return TaskReading() }
        let tasks = session.claudeMetadata?.activeTasks ?? []
        return TaskReading(
            isRunning: session.phase == .running,
            completed: tasks.filter { $0.status == .completed }.count,
            total: tasks.count,
            subagents: session.claudeMetadata?.activeSubagents.count ?? 0
        )
    }

    /// The single worst window across every provider — the one number a pill
    /// this small can honestly show. Ties keep the first provider's window so
    /// the badge doesn't flicker between equal readings.
    static func worstUsage(in providers: [UsageProviderPresentation]) -> UsageReading? {
        var worst: UsageReading?
        for provider in providers {
            for window in provider.windows where window.usedPercentage > (worst?.percent ?? -1) {
                worst = UsageReading(
                    percent: window.usedPercentage,
                    windowLabel: window.label,
                    providerTitle: provider.title
                )
            }
        }
        return worst
    }
}
