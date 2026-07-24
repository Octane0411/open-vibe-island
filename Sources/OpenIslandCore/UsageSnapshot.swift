import Foundation

/// One rate-limit window, normalized across providers.
///
/// Providers report windows in their own shape — Claude Code caches fixed
/// `five_hour` / `seven_day` entries, Codex rollouts carry `primary` /
/// `secondary` entries whose length comes from the payload. Everything
/// downstream (island pill, settings summary) only needs this shape, so new
/// providers plug in by conforming to `UsageSnapshotSummarizing` rather than by
/// adding another branch at every display site.
public struct UsageWindowSummary: Equatable, Sendable, Identifiable {
    /// Provider-local window key (`5h`, `primary`, …).
    public let key: String
    /// Short human label rendered on the pill (`5h`, `7d`, `1d 12h`, …).
    public let label: String
    public let usedPercentage: Double
    public let resetsAt: Date?

    public init(key: String, label: String, usedPercentage: Double, resetsAt: Date?) {
        self.key = key
        self.label = label
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    public var id: String { key }

    public var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }

    /// True once the window's reset time has passed.
    ///
    /// Usage caches are only rewritten while the harness runs — Claude Code
    /// writes on each turn, Codex on each rollout append. So a window past its
    /// reset is not "current usage at 10%", it is a number from the previous
    /// window that nothing has refreshed yet.
    public func hasReset(by referenceDate: Date) -> Bool {
        guard let resetsAt else {
            return false
        }

        return resetsAt <= referenceDate
    }
}

/// A provider-agnostic view of one usage cache.
public protocol UsageSnapshotSummarizing: Sendable {
    /// Windows in display order, or empty when the cache holds nothing usable.
    var windowSummaries: [UsageWindowSummary] { get }
    /// When the underlying cache was last written, if known.
    var summarizedAt: Date? { get }
}

extension UsageSnapshotSummarizing {
    /// Windows that still describe current usage — rolled-over windows are
    /// dropped rather than shown with their stale percentage.
    public func liveWindowSummaries(at referenceDate: Date) -> [UsageWindowSummary] {
        windowSummaries.filter { !$0.hasReset(by: referenceDate) }
    }
}

extension ClaudeUsageSnapshot: UsageSnapshotSummarizing {
    public var windowSummaries: [UsageWindowSummary] {
        var summaries: [UsageWindowSummary] = []

        if let fiveHour {
            summaries.append(
                UsageWindowSummary(
                    key: "5h",
                    label: "5h",
                    usedPercentage: fiveHour.usedPercentage,
                    resetsAt: fiveHour.resetsAt
                )
            )
        }

        if let sevenDay {
            summaries.append(
                UsageWindowSummary(
                    key: "7d",
                    label: "7d",
                    usedPercentage: sevenDay.usedPercentage,
                    resetsAt: sevenDay.resetsAt
                )
            )
        }

        return summaries
    }

    public var summarizedAt: Date? { cachedAt }
}

extension CodexUsageSnapshot: UsageSnapshotSummarizing {
    public var windowSummaries: [UsageWindowSummary] {
        windows.map { window in
            UsageWindowSummary(
                key: window.key,
                label: window.label,
                usedPercentage: window.usedPercentage,
                resetsAt: window.resetsAt
            )
        }
    }

    public var summarizedAt: Date? { capturedAt }
}
