import SwiftUI

/// Poured Island 2.0's attention-glow palette (AB-329, `SPEC-poured-island`
/// §0 / §1a).
///
/// The "one loud thing" — the direction's thesis colour. A brighter amber than
/// the shipped `statusWarning` (`#d98c26`), reserved for the permission-hero
/// glow and the closed-pill attention state so the loudest, act-now moments
/// read hotter than the calmer caution/interrupted amber.
///
/// Deliberately theme-local (an `enum` beside the other `Poured*` views) rather
/// than a slot on `IslandColorTokens`: it is a Poured-only accent and must stay
/// **distinct** from the status token layer. `statusWarning` / `statusInterrupted`
/// keep their existing caution / interrupted role untouched — nothing here
/// changes a status colour.
enum PouredPalette {
    /// Attention glow — `#ffb14d`. The brighter amber the permission hero and the
    /// closed-pill attention state bloom in.
    static let attention = Color(red: 0xFF / 255.0, green: 0xB1 / 255.0, blue: 0x4D / 255.0)

    /// Attention hot — `#ff9d5c`. The warmer end of the attention pulse, hotter
    /// than `attention` for the peak of the amber breathing cycle.
    static let attentionHot = Color(red: 0xFF / 255.0, green: 0x9D / 255.0, blue: 0x5C / 255.0)
}
