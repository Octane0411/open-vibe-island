import Foundation

/// The ordered set of island themes the app knows about, and lookup by id.
///
/// The order here is the order the Settings picker offers them; the first entry
/// is the default a fresh install (or an unknown / missing stored id) falls back
/// to. Registering a new theme is a one-line append here plus its `IslandTheme`
/// conformance — nothing else in the overlay needs to change (AB-299).
@MainActor
enum ThemeRegistry {

    /// Every theme, in picker order. Poured Island is first, so it's the
    /// default — the final Poured slice (AB-304, poured 5/5) flipped the default
    /// to it, making it the product's face. Classic stays registered and
    /// selectable (second in the picker) for anyone who prefers the original
    /// ink-and-paper look.
    static let all: [any IslandTheme] = [
        PouredIslandTheme(),
        ClassicTheme(),
        InstrumentTheme(),
    ]

    /// The default theme a fresh install and every unrecoverable lookup use.
    static var `default`: any IslandTheme { all[0] }

    /// The theme with `id`, or the default when `id` is nil / unknown. This is
    /// the single fallback point: a missing or garbage persisted id resolves to
    /// `default` rather than crashing or rendering blank.
    static func theme(id: String?) -> any IslandTheme {
        guard let id, let match = all.first(where: { $0.id == id }) else {
            return `default`
        }
        return match
    }
}
