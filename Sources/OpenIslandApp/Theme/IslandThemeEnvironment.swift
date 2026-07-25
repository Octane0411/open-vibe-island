import SwiftUI

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
