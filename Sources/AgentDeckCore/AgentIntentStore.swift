import Foundation

/// Persists the user's per-agent hook install intent across launches.
///
/// Backed by `UserDefaults`. Tests inject a throwaway suite so production
/// preferences aren't touched. `AgentIntentStore` is the single source of
/// truth for whether the startup flow should auto-install, skip, or prompt.
public final class AgentIntentStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Per-agent intent

    public func intent(for agent: AgentIdentifier) -> AgentHookIntent {
        guard
            let raw = defaults.string(forKey: Self.intentKey(for: agent)),
            let intent = AgentHookIntent(rawValue: raw)
        else {
            return .untouched
        }
        return intent
    }

    public func setIntent(_ intent: AgentHookIntent, for agent: AgentIdentifier) {
        defaults.set(intent.rawValue, forKey: Self.intentKey(for: agent))
    }

    /// Returns every agent whose recorded intent is `.installed`.
    public func installedAgents() -> [AgentIdentifier] {
        AgentIdentifier.allCases.filter { intent(for: $0) == .installed }
    }

    // MARK: - First-launch tracking

    /// True once the user has completed (or explicitly skipped) onboarding, or
    /// has been migrated as a legacy user with existing hooks.
    public var firstLaunchCompleted: Bool {
        get { defaults.bool(forKey: Self.firstLaunchCompletedKey) }
        set { defaults.set(newValue, forKey: Self.firstLaunchCompletedKey) }
    }

    // MARK: - Legacy migration

    /// Reconciles intent state with what is actually on disk the first time a
    /// post-onboarding build launches.
    ///
    /// - For every agent whose hook is currently present, records `.installed`.
    /// - For every agent whose hook is absent, records `.untouched`.
    /// - If any agent was detected as installed, assumes this is a legacy user
    ///   and flips `firstLaunchCompleted` to `true` so onboarding does not
    ///   appear on upgrade.
    ///
    /// Idempotent: guarded by ``migrationVersion`` so subsequent launches are
    /// no-ops until the version bumps.
    ///
    /// - Parameter detectInstalled: caller-supplied closure that reports
    ///   whether a given agent's managed hooks are currently present. Should
    ///   only be called after all hook status reads have completed.
    /// - Returns: `true` if migration ran and at least one agent was found to
    ///   be installed. Callers may use this to trigger additional legacy
    ///   bookkeeping.
    @discardableResult
    public func migrateFromLegacyStateIfNeeded(
        detectInstalled: (AgentIdentifier) -> Bool
    ) -> Bool {
        guard migrationVersion < Self.currentMigrationVersion else {
            return false
        }

        var anyInstalled = false
        for agent in AgentIdentifier.allCases {
            let installed = detectInstalled(agent)
            setIntent(installed ? .installed : .untouched, for: agent)
            if installed { anyInstalled = true }
        }

        if anyInstalled {
            firstLaunchCompleted = true
        }

        defaults.set(Self.currentMigrationVersion, forKey: Self.migrationVersionKey)
        return anyInstalled
    }

    public var migrationVersion: Int {
        defaults.integer(forKey: Self.migrationVersionKey)
    }

    // MARK: - Keys

    private static func intentKey(for agent: AgentIdentifier) -> String {
        "agentIntent.\(agent.rawValue)"
    }

    private static let firstLaunchCompletedKey = "firstLaunchCompleted"
    private static let migrationVersionKey = "agentIntentMigrationVersion"
    private static let currentMigrationVersion = 1
}
