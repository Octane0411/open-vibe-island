import SwiftUI
import OpenIslandCore

private struct IslandThemeTokensKey: EnvironmentKey {
    static let defaultValue: IslandThemeTokens = .classic
}

extension EnvironmentValues {
    /// Styling tokens for the island overlay.
    ///
    /// Defaults to `.classic` — the look Open Island ships today — so a view
    /// that reads this without an explicit injection renders unchanged.
    var islandTokens: IslandThemeTokens {
        get { self[IslandThemeTokensKey.self] }
        set { self[IslandThemeTokensKey.self] = newValue }
    }
}

private struct IslandSessionDisambiguatorsKey: EnvironmentKey {
    static let defaultValue: [String: String] = [:]
}

extension EnvironmentValues {
    /// AB-323: session id → duplicate-workspace disambiguator (branch or
    /// recency) for the sessions currently on screen, produced by
    /// `SessionDisambiguation` and injected once by `IslandPanelView`.
    ///
    /// The suffix is list-level state — a row on its own cannot know whether its
    /// workspace name collides — so it travels through the environment rather
    /// than the theme's `sessionRow(...)` signature. A theme that ignores it
    /// renders exactly as before; one that reads it can style the disambiguator
    /// in its own vocabulary instead of the default parenthesised suffix.
    ///
    /// Defaults to empty, i.e. "no collisions", so any view rendered without an
    /// explicit injection shows clean unique-row headlines.
    var islandSessionDisambiguators: [String: String] {
        get { self[IslandSessionDisambiguatorsKey.self] }
        set { self[IslandSessionDisambiguatorsKey.self] = newValue }
    }
}

/// The spotlight session's phase + outcome, threaded to the closed pill so a
/// theme can express ambient states that `UnifiedBars.Mode` alone cannot —
/// `.idle`/`.running`/`.waiting` collapse *running vs. just-completed* and
/// *permission vs. question* into the same glyph mode, and carry no outcome.
///
/// A neutral value (raw `SessionPhase` / `SessionOutcome`, plus whether the
/// completion is still inside its settle window) rather than a Poured-specific
/// enum, so it stays a truthful description of the spotlight and any theme can
/// map it into its own vocabulary. `outcome` is only meaningful when
/// `phase == .completed`; `isOutcomeFresh` is `true` only while a completion is
/// recent enough to still narrate its verdict (mirrors the closed-pill label's
/// settle window, `IslandClosedPillTiming.outcomeLabelWindow`).
struct IslandClosedPillActivity: Equatable, Sendable {
    var phase: SessionPhase
    var outcome: SessionOutcome
    var isOutcomeFresh: Bool

    init(phase: SessionPhase, outcome: SessionOutcome, isOutcomeFresh: Bool) {
        self.phase = phase
        self.outcome = outcome
        self.isOutcomeFresh = isOutcomeFresh
    }
}

private struct IslandClosedPillActivityKey: EnvironmentKey {
    static let defaultValue: IslandClosedPillActivity? = nil
}

extension EnvironmentValues {
    /// AB-330: the spotlight session's phase/outcome behind the closed pill,
    /// injected once by `IslandPanelView` from `AppModel.islandClosedActivity`.
    ///
    /// Like `islandSessionDisambiguators`, this is state the pill's own
    /// arguments (`mode` / `label` / `rightSlot`) cannot carry, so it travels
    /// through the environment rather than the theme's `closedPill(...)`
    /// signature — a theme that ignores it (every theme but Poured today)
    /// renders exactly as before. Defaults to `nil` ("no spotlight"), so a pill
    /// rendered without an explicit injection resolves to its idle ambient
    /// state rather than reading a stale verdict.
    var islandClosedPillActivity: IslandClosedPillActivity? {
        get { self[IslandClosedPillActivityKey.self] }
        set { self[IslandClosedPillActivityKey.self] = newValue }
    }
}

private struct IslandBridgeIsLiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// Whether the app's local bridge socket is up and observing (`AppModel`'s
    /// `isBridgeReady`).
    ///
    /// A theme's opened chrome can wire a status readout to this so it displays
    /// the truth of the bridge connection — a live socket vs a down one — rather
    /// than a static string. Injected once by `IslandPanelView`; Flight Deck's
    /// "BRIDGE LINK" footer is its first consumer (AB-312). Defaults to `false`
    /// so a view that reads it without an explicit injection reads as "down"
    /// rather than falsely "connected".
    var islandBridgeIsLive: Bool {
        get { self[IslandBridgeIsLiveKey.self] }
        set { self[IslandBridgeIsLiveKey.self] = newValue }
    }
}
