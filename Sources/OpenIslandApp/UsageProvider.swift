import Foundation
import OpenIslandCore

/// Subscription-usage providers Open Island can surface in the opened header.
///
/// This is the single registry for anything provider-specific about usage:
/// labels, the harness whose sessions draw down the quota, and how the provider
/// is gated in Settings. Adding a provider means adding a case here plus a
/// snapshot source in `AppModel` — no new branches at the display sites.
///
/// Raw values are stable identifiers used for pill and window IDs and for the
/// opt-in defaults key, so they must not change once shipped.
enum UsageProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    /// Label shown on the usage pill when the header lane has room.
    var title: String {
        switch self {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        }
    }

    /// Abbreviated label used when the notch squeezes the header lane.
    var shortTitle: String {
        switch self {
        case .claude:
            "Cl"
        case .codex:
            "Cx"
        }
    }

    /// The provider whose quota this tool's sessions draw down.
    ///
    /// Claude Code forks (Qoder, Factory, CodeBuddy, Kimi, Qwen) reuse Claude
    /// Code's hook format but bill against their own vendors, so they map to no
    /// provider and leave the pill on whatever is already selected.
    init?(tool: AgentTool?) {
        switch tool {
        case .claudeCode:
            self = .claude
        case .codex:
            self = .codex
        default:
            return nil
        }
    }

    /// How often to re-read this provider's cache. Claude's status line
    /// rewrites its cache on every turn, so it is cheap to poll often; Codex
    /// usage means scanning rollout files, so it polls lazily.
    var pollInterval: Duration {
        switch self {
        case .claude:
            .seconds(5)
        case .codex:
            .seconds(120)
        }
    }

    // MARK: - Opt-in

    /// `UserDefaults` key gating this provider's passive polling.
    ///
    /// `nil` means the provider carries no toggle because it is gated by its
    /// own install state instead — Claude usage only exists once the user
    /// installs the managed status line bridge from Settings.
    var optInDefaultsKey: String? {
        switch self {
        case .claude:
            nil
        case .codex:
            "app.showCodexUsage"
        }
    }

    /// Localization key for the Settings toggle, for providers that have one.
    var optInLabelKey: String? {
        switch self {
        case .claude:
            nil
        case .codex:
            "settings.general.showCodexUsage"
        }
    }

    /// Path whose presence implies the user actually runs this harness. Used to
    /// pick a sane default the first time the toggle is read, so Codex users
    /// see their usage without hunting for the switch.
    var installationProbeURL: URL? {
        switch self {
        case .claude:
            nil
        case .codex:
            CodexRolloutDiscovery.defaultRootURL
        }
    }

    /// Providers the user can switch on and off in Settings, in display order.
    static var optional: [UsageProvider] {
        allCases.filter { $0.optInDefaultsKey != nil }
    }
}

/// A provider's current usage windows, ready for display.
struct UsageProviderStatus: Identifiable, Equatable {
    let provider: UsageProvider
    let windows: [UsageWindowSummary]
    let capturedAt: Date?

    var id: UsageProvider { provider }

    var title: String { provider.title }

    var shortTitle: String { provider.shortTitle }

    /// The window closest to its limit — what the collapsed pill reports.
    var peakWindow: UsageWindowSummary? {
        windows.max { lhs, rhs in
            lhs.usedPercentage < rhs.usedPercentage
        }
    }

    var peakWindowLabel: String {
        peakWindow?.label ?? ""
    }

    var peakUsedPercentage: Double {
        peakWindow?.usedPercentage ?? 0
    }

    var peakUsagePercentage: Int {
        peakWindow?.roundedUsedPercentage ?? 0
    }
}

/// Decides which usage provider the opened header shows.
enum UsageProviderSelection {
    static func provider(for tool: AgentTool?) -> UsageProvider? {
        UsageProvider(tool: tool)
    }

    /// Manual pick wins, then the harness in the closed-island spotlight, then
    /// whatever provider has data.
    static func selected(
        available: [UsageProvider],
        activeTool: AgentTool?,
        override: UsageProvider?
    ) -> UsageProvider? {
        if let override, available.contains(override) {
            return override
        }

        if let active = provider(for: activeTool), available.contains(active) {
            return active
        }

        return available.first
    }
}
