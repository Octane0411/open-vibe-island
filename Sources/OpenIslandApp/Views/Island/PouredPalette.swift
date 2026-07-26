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

    /// Ink drawn *on* the amber `count.attn` permission badge — `#2a1c05`
    /// (`SPEC-poured-island` §4A A3 "text `#2a1c05`"). A near-black warm brown so
    /// the count reads against the bright `attention` fill; theme-local for the
    /// same reason as `attention` — it is a Poured accent, not a status token.
    static let attentionBadgeInk = Color(red: 0x2A / 255.0, green: 0x1C / 255.0, blue: 0x05 / 255.0)

    /// Ink drawn *on* the gold `?` question badge — `#2a2205`
    /// (`SPEC-poured-island` §4A A4 "text `#2a2205`"). The question twin of
    /// `attentionBadgeInk`, over the `statusWaitingForAnswer` gold fill.
    static let questionBadgeInk = Color(red: 0x2A / 255.0, green: 0x22 / 255.0, blue: 0x05 / 255.0)
}
