import CoreGraphics
import Foundation

/// Motion vocabulary for the Poured 2.0 closed pill's six ambient states
/// (AB-330, `SPEC-poured-island` §1c / §4A · mockup §A keyframes `lumen` /
/// `attnpulse` / `settle`).
///
/// Every period, radius, opacity and spread the six ambient states animate is a
/// named constant here — the single place the numbers live, so `PouredPillMotionTests`
/// can pin them and drift fails the build instead of the eye. The *colours* are
/// deliberately absent: they come from `IslandColorTokens.poured` /
/// `PouredPalette` at the view site (`SPEC-poured-island` §1a keeps status tints
/// on the token layer and the attention glow in `PouredPalette`), so this table
/// stays a pure, `Equatable`-friendly vector of geometry and timing.
///
/// The shipped `PouredPulsingStatusDot` "never acquire the clock under Reduce
/// Motion" precedent governs how these are consumed: with motion, a state
/// breathes/pulses between its `…Min`/`…Max` (or plays its one-shot); under
/// Reduce Motion the view holds the **peak** frame (the loudest, most-visible
/// end — `SPEC` §K "gated under Reduce Motion", ticket "static frames at PEAK
/// attention visibility") and never starts an animation.
enum PouredPillMotion {

    // MARK: A2 · working — `lumen` breathing (glow colour = `statusRunning`)

    enum Working {
        /// `lumen` cycle length — a slow, calm breath.
        static let period: TimeInterval = 3.0
        /// Peak glow radius (mockup `0 0 22px`). Rest is `0` (no glow).
        static let glowRadius: CGFloat = 22
        /// Peak glow opacity (mockup `rgba(110,167,255,.16)`).
        static let glowOpacity: Double = 0.16
    }

    // MARK: A2′ · many working — agents-grid tiles (colours = `statusRunning` / paper)

    enum AgentsGrid {
        /// Running-cell halo (mockup `.agrid i.on { box-shadow:0 0 6px rgba(110,167,255,.6) }`).
        static let runningGlowRadius: CGFloat = 6
        static let runningGlowOpacity: Double = 0.6
        /// Idle-cell fill opacity of `paper` (`SPEC` §A2′ "idle cells paper@0.5").
        static let idleCellOpacity: Double = 0.5
    }

    // MARK: A3 · permission — `attnpulse` (glow colour = `PouredPalette.attention`)

    enum Permission {
        /// `attnpulse` cycle length — faster than `lumen`; this is the loud one.
        static let period: TimeInterval = 1.9
        /// Radius breathes `18 → 34` (mockup `0 0 18px … → 0 0 34px`).
        static let radiusMin: CGFloat = 18
        static let radiusMax: CGFloat = 34
        /// Extra bleed at the peak (mockup `… 34px 4px …` spread). SwiftUI's
        /// `.shadow` has no spread parameter, so the view emulates it with a
        /// second, wider shadow layer keyed off this value.
        static let spreadMax: CGFloat = 4
        /// Opacity breathes `.28 → .55` (mockup `rgba(255,177,77,.28 → .55)`).
        static let opacityMin: Double = 0.28
        static let opacityMax: Double = 0.55
        /// Left status-dot ring (mockup `.ring { box-shadow:0 0 0 3px rgba(255,177,77,.22) }`).
        static let ringWidth: CGFloat = 3
        static let ringOpacity: Double = 0.22
    }

    // MARK: A4 · question — static gold glow + breathing glyph (colour = `statusWaitingForAnswer`)

    enum Question {
        /// Static body glow (mockup A4 `box-shadow: … 0 0 26px rgba(255,213,138,.34)`
        /// — a fixed halo, *not* a keyframe; only the glyph breathes).
        static let glowRadius: CGFloat = 26
        static let glowOpacity: Double = 0.34
        /// The glyph's `breathe` cycle (mockup `.glyph.wait i { animation:breathe 2.6s }`).
        /// The bar wave itself is owned by `UnifiedBars` (`.waiting` mode); this
        /// is the tinted glyph's breathing period the spec pins.
        static let glyphBreathePeriod: TimeInterval = 2.6
    }

    // MARK: A5 · just completed — `settle` one-shot (colours = white → `statusCompleted`)

    enum Settle {
        /// `settle` total duration — a one-shot, ease-out; **never loops**.
        static let duration: TimeInterval = 2.6
        /// Progress point where the cool-white flash has fully become green
        /// (mockup keyframe `22%`).
        static let greenKeyTime: Double = 0.22

        /// Opening cool-white flash (mockup `0%: 0 0 30px 3px rgba(255,255,255,.4)`).
        static let flashRadius: CGFloat = 30
        static let flashSpread: CGFloat = 3
        static let flashOpacity: Double = 0.4

        /// Mid-settle green (mockup `22%: 0 0 22px 2px rgba(111,185,130,.4)`).
        static let greenRadius: CGFloat = 22
        static let greenSpread: CGFloat = 2
        static let greenOpacity: Double = 0.4
        // Tail (`100%`) fades to `0 0 0` — no glow — so no constants needed.
    }

    // MARK: Right-slot chips (A3 count-attn · A4 `?` · G task-counter · I usage dial)

    /// Geometry for the Poured 2.0 closed-pill right-slot variants
    /// (`SPEC-poured-island` §4A A3/A4 · §G · §I). Colours live at the view site
    /// (`PouredPalette` badge inks + status tokens); this table is geometry only,
    /// so it stays a pure vector `PouredPillMotionTests` can pin.
    enum RightSlot {
        /// Capsule padding + corner for the `count.attn` / `?` badges.
        static let badgeHPadding: CGFloat = 5
        static let badgeVPadding: CGFloat = 1.5
        static let badgeCornerRadius: CGFloat = 6

        /// A3 `count.attn` badge glow — `rgba(255,177,77,.55)` r14 (`SPEC` §4A A3
        /// "glow `rgba(255,177,77,.55)` r14"). The badge is the loud one; the `?`
        /// question badge carries the calmer gold fill with no extra badge glow.
        static let attnBadgeGlowRadius: CGFloat = 14
        static let attnBadgeGlowOpacity: Double = 0.55

        /// Task-counter chip (`⏲ 2/5`) — the gap between the timer glyph and the
        /// tabular `done/total` fraction.
        static let taskChipSpacing: CGFloat = 3

        /// Worst-window usage dial (`SPEC` §I "small dial + `92%`"): a compact
        /// conic ring beside the tabular percentage.
        static let usageDialDiameter: CGFloat = 13
        static let usageDialLineWidth: CGFloat = 2.5
        static let usageDialValueSpacing: CGFloat = 3

        /// Usage threshold cutoffs (`SPEC` §I / §3.2 — the shipped `usageColor`
        /// rule): `≥ critical` red, `≥ warn` gold, else green. The pill only ever
        /// receives `≥ critical` per `IslandRightSlotResolver.usageAlertThreshold`,
        /// but the tint is computed from these so an off-threshold fixture is
        /// still coloured truthfully.
        static let usageCriticalThreshold: Int = 90
        static let usageWarnThreshold: Int = 70
    }
}
