import SwiftUI

/// Flight Deck's one phosphor-glow primitive (AB-336).
///
/// The shipped Flight Deck is deliberately glow-free flat hardware; the only
/// glow that ever existed was `FlightDeckCautionGlow` — a blurred chamfered halo
/// behind the MASTER WARNING block (AB-314). The 2.0 board (BRIEF §7 "glow that
/// bleeds outside the silhouette", SPEC-flight-deck §1d) makes *every* lit lamp
/// self-lit phosphor, so that one-off halo is generalized here into a single
/// reusable primitive: a shape filled with the lit tint, blurred to `radius`,
/// held at `intensity`, and bled `bleed` points past its own silhouette via
/// negative padding so the light spills outside the lamp the way a real
/// phosphor lamp does.
///
/// **This is the ONE glow technique every lit Flight Deck lamp uses** — no
/// per-site blur copies. Part 1 wires it behind the closed-pill running /
/// waiting lamps and the mini annunciator grid, and re-expresses the caution
/// glow through it. Part 2 (T18/T19) applies the same primitive to the row
/// status lanes, summary-strip annunciator tiles, the footer link lamp and the
/// empty-state lamp; T20's engine-cluster lamps reuse it too. Because it takes a
/// generic `Shape`, a square lamp (`RoundedRectangle`), a chamfered placard
/// (`FlightDeckChamferedRectangle`) and a bar all light identically.
///
/// It is a passive halo (no clock of its own): callers that breathe the light
/// animate `radius` / `intensity` from their own motion source and hand the
/// current frame's values in, so a single site owns the cadence and the glow
/// stays a pure function of them. Always accessibility-hidden — a lit lamp's
/// meaning is carried by its status colour and label, never the halo.
struct FlightDeckPhosphorGlow<S: Shape>: View {
    /// The lit shape whose silhouette the halo traces (the same shape the lamp
    /// fills, so the glow sits exactly under it).
    let shape: S
    /// The phosphor tint — always a semantic status colour, never an agent brand.
    let tint: Color
    /// Blur radius of the halo; the larger it is the further the light bleeds.
    let radius: CGFloat
    /// Halo opacity (`0…1`) — how brightly the lamp is lit this frame.
    let intensity: Double
    /// How far the halo is pushed past the lamp silhouette before blurring, so
    /// the light spills *outside* the lamp. Matches the AB-314 caution halo's
    /// `padding(-2)`.
    var bleed: CGFloat = 2

    var body: some View {
        shape
            .fill(tint)
            .blur(radius: radius)
            .opacity(intensity)
            .padding(-bleed)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Seats a `FlightDeckPhosphorGlow` behind this lamp, tracing `shape`. A thin
    /// convenience over `.background(FlightDeckPhosphorGlow(...))` so a lit lamp
    /// reads as `lamp.phosphorGlow(...)` at the call site.
    func phosphorGlow<S: Shape>(
        shape: S,
        tint: Color,
        radius: CGFloat,
        intensity: Double,
        bleed: CGFloat = 2
    ) -> some View {
        background(
            FlightDeckPhosphorGlow(
                shape: shape,
                tint: tint,
                radius: radius,
                intensity: intensity,
                bleed: bleed
            )
        )
    }
}

// MARK: - Motion identity

/// The Flight Deck 2.0 motion identity, in one place (AB-336 · SPEC-flight-deck
/// §1c / §4K "motion strip").
///
/// The shipped theme scattered its cadences across leaf views — the closed-pill
/// running lamp was flat, the list lane blinked two-step off the shared 15fps
/// clock, the caution glow throbbed a triangle, the AB-334 beacons carried their
/// own 1.0s / 1.2s periods. This enum is the single source of truth for every
/// named period, radius and opacity the 2.0 board pins, so the mockup's motion
/// strip and the Swift constants can never drift; `FlightDeckMotionTests` pins
/// each value. Every ramp is a **pure function of wall-clock `now`** (the AB-334
/// `beaconLevel` pattern) so an independently-timed lamp needs no per-lamp clock,
/// and every ramp is **gated on Reduce Motion** to a steady lit frame — a glow
/// never animates, and never even acquires a clock, when motion is off.
enum FlightDeckMotion {

    /// Running "phosphor" breathe (`@keyframes phosphor 2s`): the lit nominal
    /// lamp swells opacity `0.86 → 1.0` and its halo `5 → 11pt` once per 2.0s,
    /// ease-in-out. Replaces the shipped flat running fill / two-step blink.
    enum Breathe {
        static let period: Double = 2.0
        static let opacityMin: Double = 0.86
        static let opacityMax: Double = 1.0
        static let glowRadiusMin: CGFloat = 5
        static let glowRadiusMax: CGFloat = 11
    }

    /// Master-alarm attention pulse (`@keyframes attn`): opacity ramps
    /// `1.0 → 0.28` and back, warning-red on a faster 1.0s cadence and
    /// caution-amber on a calmer 1.2s so the two annunciators are told apart by
    /// rhythm as well as hue. Drives the AB-334 beacons and the closed-pill
    /// attention bloom.
    enum Attention {
        static let warningPeriod: Double = 1.0
        static let cautionPeriod: Double = 1.2
        /// Fully lit (the peak / loudest frame Reduce Motion pins to).
        static let opacityMax: Double = 1.0
        /// The dim trough of the pulse.
        static let opacityMin: Double = 0.28
    }

    /// Lamp snap-on (§4K "Lamp snap-on 120ms on · soft decay"; the mockup's
    /// `snapon` uses `steps(1,end)` — an instant on). A lamp latches to lit in
    /// `onDuration` (≤ 1 frame, no fade-in) and, when it unlits, decays over
    /// `decayDuration` (~120ms) so it reads as instrument hardware, not a fade.
    enum Snap {
        /// Instant on — a relay throws, it does not ramp (≤ 1 frame).
        static let onDuration: Double = 0.0
        /// Soft decay when a lit lamp goes dark (~120ms).
        static let decayDuration: Double = 0.12
    }

    /// Success settle (`@keyframes settle 3s`, one-shot · A5): a completed lamp
    /// flashes nominal `#4AC99E` scaled `1.25` with a wide halo, then settles to
    /// advisory `#6392C4` and a calm dot over 3.0s and never loops. The flash /
    /// settled *colours* are the shared `statusRunning` / `statusCompleted`
    /// tokens (identical hexes), resolved at the call site.
    enum Settle {
        static let duration: Double = 3.0
        static let flashScale: CGFloat = 1.25
        static let flashGlowRadius: CGFloat = 18
        static let settledGlowRadius: CGFloat = 5
        /// The fraction of the one-shot the nominal flash occupies before the
        /// lamp has fully crossed to the calm advisory dot: the scale, the wide
        /// halo and the green→blue crossfade all decay to their settled values by
        /// this key-time, then the remaining travel is the lamp resting. Small, so
        /// the flash reads as a quick bloom, not a slow fade.
        static let flashKeyTime: Double = 0.2
    }

    /// The closed-pill attention **bloom** — a per-state colored drop-glow that
    /// bleeds outside the pill silhouette (mockup `.attn-perm` / `.attn-caut`).
    ///
    /// The mockup's shadows carry a negative spread
    /// (`0 6px 26px −14px` / `0 6px 24px −16px`) that SwiftUI's `.shadow` — which
    /// has no spread parameter — can only approximate: a negative spread means a
    /// *tight* halo, so the effective radius is `radius + spread`
    /// (`26 − 14 = 12`, `24 − 16 = 8`) carried with the mockup's `6pt`
    /// down-offset. The border opacities are the mockup's `.attn-*` border rgba
    /// alphas.
    enum Bloom {
        static let permissionRadius: CGFloat = 12   // 26 − 14
        static let questionRadius: CGFloat = 8      // 24 − 16
        static let yOffset: CGFloat = 6
        static let permissionGlowOpacity: Double = 0.6
        static let questionGlowOpacity: Double = 0.5
        static let permissionBorderOpacity: Double = 0.55
        static let questionBorderOpacity: Double = 0.5
    }

    /// Row entrance — **relay-snap in** (§4K motion strip · mockup `enter`). A
    /// freshly-inserted list row slides in from a small horizontal offset and
    /// fades once into its settled frame, driven by the theme's named relay-snap
    /// open spring (response `0.32` / damping `0.92`) so a row arriving reads with
    /// the same decisive no-overshoot latch as the panel's open morph. One-shot;
    /// under Reduce Motion the row is born settled — no offset, no fade, no clock
    /// (§4K "gated under Reduce Motion").
    enum Entrance {
        /// Starting horizontal offset (mockup `enter` translateX), eased to `0`.
        static let slideOffset: CGFloat = 12
        /// Starting opacity, eased to `1`.
        static let initialOpacity: Double = 0
        /// The relay-snap open spring — the FD identity (`IslandMotionTokens
        /// .flightDeck.openAnimation`), named here so the entrance can't drift off it.
        static let springResponse: TimeInterval = 0.32
        static let springDamping: Double = 0.92
    }

    // MARK: Ramps (pure, wall-clock, Reduce-Motion gated)

    /// A normalized ease-in-out triangle for `now` at `period`: `0 → 1 → 0` over
    /// one period, smoothstepped so the turn at the peak/trough eases rather than
    /// kinking. The shared shape behind every breathe/pulse ramp below.
    static func easedTriangle(now: Date, period: Double) -> Double {
        guard period > 0 else { return 0 }
        let position = now.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period      // −1 … 1
        let phase = position < 0 ? position + 1 : position          // 0 … 1
        let triangle = phase < 0.5 ? phase * 2 : (1 - phase) * 2     // 0 → 1 → 0
        return triangle * triangle * (3 - 2 * triangle)             // smoothstep
    }

    /// Running-lamp breathe opacity at `now` (`Breathe`). Reduce Motion pins it
    /// to `opacityMax` — a steady lit lamp, never dark.
    static func breatheOpacity(now: Date, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return Breathe.opacityMax }
        let t = easedTriangle(now: now, period: Breathe.period)
        return Breathe.opacityMin + t * (Breathe.opacityMax - Breathe.opacityMin)
    }

    /// Running-lamp halo radius at `now` (`Breathe`). Reduce Motion pins it to
    /// `glowRadiusMax` — the fully-bloomed halo held steady.
    static func breatheGlowRadius(now: Date, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return Breathe.glowRadiusMax }
        let t = CGFloat(easedTriangle(now: now, period: Breathe.period))
        return Breathe.glowRadiusMin + t * (Breathe.glowRadiusMax - Breathe.glowRadiusMin)
    }

    /// Attention-pulse level at `now` for a lamp/surface on `period` (`Attention`).
    /// Brightest (`opacityMax`) at the cycle boundaries, dimmest (`opacityMin`)
    /// mid-cycle — the mockup `attn` ramp. Reduce Motion holds it at the peak
    /// (`opacityMax`) so the alarm is pinned fully lit, never dark (§K).
    static func attentionLevel(now: Date, period: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion, period > 0 else { return Attention.opacityMax }
        let t = easedTriangle(now: now, period: period)
        return Attention.opacityMax - t * (Attention.opacityMax - Attention.opacityMin)
    }

    /// The success-settle "flash amount" for a one-shot at `progress` (`0 → 1`
    /// over `Settle.duration`): `1` at the instant of completion (full nominal
    /// flash — scaled, wide green halo) decaying to `0` by `Settle.flashKeyTime`,
    /// then held at `0` while the lamp rests as the calm advisory dot. Every
    /// settle-frame value (scale, halo radius, green→blue crossfade) is a pure
    /// function of this, so the flash and the settled rest share one clock and a
    /// snapshot at `progress = 1` is deterministic.
    static func settleFlashAmount(progress: Double) -> Double {
        let key = Settle.flashKeyTime
        guard key > 0 else { return progress <= 0 ? 1 : 0 }
        return max(0, min(1, 1 - progress / key))
    }
}
