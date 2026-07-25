import SwiftUI

/// The full set of styling tokens an island theme provides.
///
/// This is the foundation of the theme system: overlay styling that is today
/// hardcoded across `V6Palette`, `IslandDesignPalette`, `NotchShape`,
/// `IslandChromeMetrics` and `IslandPanelView` gets expressed once here, and
/// views read it from the environment via `@Environment(\.islandTokens)`.
///
/// Deliberately split three ways so a theme can override one axis without
/// restating the others. Typography is intentionally absent: themes swap
/// entire slot views, so per-view fonts belong to each theme's own views
/// rather than to a shared token table.
///
/// Not `Codable` — `Color` has no stable `Codable` conformance and
/// `IslandAnimationToken` is a rendering concern, not persisted state. Themes
/// are selected by identifier; the tokens themselves are code, not data.
struct IslandThemeTokens: Equatable, Sendable {
    var colors: IslandColorTokens
    var metrics: IslandMetricsTokens
    var motion: IslandMotionTokens
    var material: IslandMaterialTokens
}

// MARK: - Classic

extension IslandThemeTokens {
    /// The look Open Island ships today: ink/paper island, v6 status tints,
    /// 22pt opened radii, spring open / smooth close, `.hudWindow` vibrancy.
    static let classic = IslandThemeTokens(
        colors: .classic,
        metrics: .classic,
        motion: .classic,
        material: .classic
    )
}

// MARK: - Poured Island

extension IslandThemeTokens {
    /// Poured Island (liquid glass): cool frosted identity, filleted opened
    /// shape, deep soft shadow, lighter vibrancy tint with a specular top edge,
    /// and a softer "poured" open/close spring.
    static let poured = IslandThemeTokens(
        colors: .poured,
        metrics: .poured,
        motion: .poured,
        material: .poured
    )
}

// MARK: - Instrument

extension IslandThemeTokens {
    /// Instrument (precision monospace console): a near-monochrome palette that
    /// spends colour only on status, a squared-off flat panel with no vibrancy or
    /// fillet, and a crisp mechanical open/close spring.
    static let instrument = IslandThemeTokens(
        colors: .instrument,
        metrics: .instrument,
        motion: .instrument,
        material: .instrument
    )
}

// MARK: - Flight Deck

extension IslandThemeTokens {
    /// Flight Deck (avionics annunciator panel): a near-black cockpit ground lit
    /// only by phosphor status colour, a tightly-cut flat panel with no vibrancy
    /// or fillet, and a hard mechanical open/close snap.
    static let flightDeck = IslandThemeTokens(
        colors: .flightDeck,
        metrics: .flightDeck,
        motion: .flightDeck,
        material: .flightDeck
    )
}

// MARK: - Annual

extension IslandThemeTokens {
    /// Annual (editorial Swiss typographic calm): a warm near-black ground and
    /// warm off-white ink spending one orange-red accent only on attention and
    /// critical states, a quiet flat page with no vibrancy or fillet and modestly
    /// rounded corners, and a calm, bounce-free settle.
    static let annual = IslandThemeTokens(
        colors: .annual,
        metrics: .annual,
        motion: .annual,
        material: .annual
    )
}
