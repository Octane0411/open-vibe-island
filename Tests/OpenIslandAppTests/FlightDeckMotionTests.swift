import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-336 (T17): the Flight Deck 2.0 motion identity. `FlightDeckMotion` is the
/// single source of truth for every named period / radius / opacity the 2.0
/// board's motion strip (SPEC-flight-deck §1c / §4K) pins, so this suite pins
/// each value and the Reduce-Motion gating of every ramp — a drift in any of
/// them fails the build the way the mockup's CSS keyframes are the contract.
struct FlightDeckMotionTests {

    // MARK: - Named constants (§1c / §4K)

    /// AC #8: the running "phosphor" breathe is 2.0s, opacity 0.86 → 1.0, glow
    /// radius 5 → 11pt — the mockup `@keyframes phosphor`.
    @Test
    func breatheConstantsMatchTheMockupPhosphorKeyframe() {
        #expect(FlightDeckMotion.Breathe.period == 2.0)
        #expect(FlightDeckMotion.Breathe.opacityMin == 0.86)
        #expect(FlightDeckMotion.Breathe.opacityMax == 1.0)
        #expect(FlightDeckMotion.Breathe.glowRadiusMin == 5)
        #expect(FlightDeckMotion.Breathe.glowRadiusMax == 11)
    }

    /// AC #8 / #3: attention warning 1.0s / caution 1.2s, opacity 1.0 → 0.28 —
    /// the mockup `@keyframes attn`; warning throbs faster than caution.
    @Test
    func attentionConstantsMatchTheMockupAttnKeyframe() {
        #expect(FlightDeckMotion.Attention.warningPeriod == 1.0)
        #expect(FlightDeckMotion.Attention.cautionPeriod == 1.2)
        #expect(FlightDeckMotion.Attention.warningPeriod < FlightDeckMotion.Attention.cautionPeriod)
        #expect(FlightDeckMotion.Attention.opacityMax == 1.0)
        #expect(FlightDeckMotion.Attention.opacityMin == 0.28)
    }

    /// AC #4: lamp snap-on latches instantly (≤ 1 frame, no fade-in) and decays
    /// softly (~120ms) — the mockup `snapon` `steps(1,end)`.
    @Test
    func snapConstantsAreInstantOnSoftDecay() {
        #expect(FlightDeckMotion.Snap.onDuration == 0.0)
        #expect(FlightDeckMotion.Snap.decayDuration == 0.12)
        // On is instantaneous relative to the decay — the asymmetry the AC pins.
        #expect(FlightDeckMotion.Snap.onDuration < FlightDeckMotion.Snap.decayDuration)
    }

    /// AC #5: success settle is a 3.0s one-shot — nominal flash scaled ~1.25 with
    /// a wide halo settling to the calmer advisory dot.
    @Test
    func settleConstantsMatchTheMockupSettleKeyframe() {
        #expect(FlightDeckMotion.Settle.duration == 3.0)
        #expect(FlightDeckMotion.Settle.flashScale == 1.25)
        #expect(FlightDeckMotion.Settle.flashGlowRadius > FlightDeckMotion.Settle.settledGlowRadius)
    }

    /// AC #6: the closed-pill attention bloom is the mockup's negative-spread
    /// shadow approximated as a tight radius (26−14 = 12 / 24−16 = 8) with the
    /// 6pt down-offset and the `.attn-*` border alphas (0.55 / 0.5).
    @Test
    func bloomConstantsApproximateTheMockupNegativeSpread() {
        #expect(FlightDeckMotion.Bloom.permissionRadius == 12)
        #expect(FlightDeckMotion.Bloom.questionRadius == 8)
        #expect(FlightDeckMotion.Bloom.yOffset == 6)
        #expect(FlightDeckMotion.Bloom.permissionGlowOpacity == 0.6)
        #expect(FlightDeckMotion.Bloom.questionGlowOpacity == 0.5)
        #expect(FlightDeckMotion.Bloom.permissionBorderOpacity == 0.55)
        #expect(FlightDeckMotion.Bloom.questionBorderOpacity == 0.5)
        // Permission is the louder alarm: wider halo + stronger border than a question.
        #expect(FlightDeckMotion.Bloom.permissionRadius > FlightDeckMotion.Bloom.questionRadius)
    }

    // MARK: - Ramps: Reduce-Motion gating + range

    /// AC #7: the running breathe ramps between the two pinned endpoints with
    /// motion, and holds the **lit peak** (full opacity + fully-bloomed halo)
    /// under Reduce Motion — a steady lit lamp, never dark.
    @Test
    func breatheRampsWithMotionAndHoldsPeakUnderReduceMotion() {
        // Reduce Motion: pinned to the lit peak, everywhere in the cycle.
        for offset in stride(from: 0.0, through: FlightDeckMotion.Breathe.period, by: 0.25) {
            let now = Date(timeIntervalSinceReferenceDate: offset)
            #expect(FlightDeckMotion.breatheOpacity(now: now, reduceMotion: true) == FlightDeckMotion.Breathe.opacityMax)
            #expect(FlightDeckMotion.breatheGlowRadius(now: now, reduceMotion: true) == FlightDeckMotion.Breathe.glowRadiusMax)
        }

        // With motion: every sample stays inside the pinned opacity / radius band,
        // and the ramp actually varies across the cycle (not a constant).
        var opacities: Set<Double> = []
        for offset in stride(from: 0.0, to: FlightDeckMotion.Breathe.period, by: FlightDeckMotion.Breathe.period / 16) {
            let now = Date(timeIntervalSinceReferenceDate: offset)
            let opacity = FlightDeckMotion.breatheOpacity(now: now, reduceMotion: false)
            let radius = FlightDeckMotion.breatheGlowRadius(now: now, reduceMotion: false)
            #expect(opacity >= FlightDeckMotion.Breathe.opacityMin - 0.0001)
            #expect(opacity <= FlightDeckMotion.Breathe.opacityMax + 0.0001)
            #expect(radius >= FlightDeckMotion.Breathe.glowRadiusMin - 0.0001)
            #expect(radius <= FlightDeckMotion.Breathe.glowRadiusMax + 0.0001)
            opacities.insert((opacity * 1000).rounded())
        }
        #expect(opacities.count > 1)
    }

    /// AC #3 / #7: the attention ramp is brightest at the cycle boundary and
    /// dimmest mid-cycle (mockup `attn`), stays inside its band, and holds the
    /// peak under Reduce Motion. The warning and caution periods share this ramp.
    @Test
    func attentionRampFollowsAttnKeyframeAndHoldsPeakUnderReduceMotion() {
        for period in [FlightDeckMotion.Attention.warningPeriod, FlightDeckMotion.Attention.cautionPeriod] {
            let base = Date(timeIntervalSinceReferenceDate: 0)

            // Reduce Motion → peak (lit), across the whole cycle.
            for offset in stride(from: 0.0, through: period, by: period / 8) {
                let value = FlightDeckMotion.attentionLevel(
                    now: base.addingTimeInterval(offset), period: period, reduceMotion: true
                )
                #expect(value == FlightDeckMotion.Attention.opacityMax)
            }

            // With motion: boundary is the peak, mid-cycle the trough, all in band.
            let boundary = FlightDeckMotion.attentionLevel(now: base, period: period, reduceMotion: false)
            let mid = FlightDeckMotion.attentionLevel(now: base.addingTimeInterval(period / 2), period: period, reduceMotion: false)
            #expect(boundary > mid)
            #expect(abs(boundary - FlightDeckMotion.Attention.opacityMax) < 0.0001)
            #expect(abs(mid - FlightDeckMotion.Attention.opacityMin) < 0.0001)

            // Periodic: identical one full period later.
            let wrapped = FlightDeckMotion.attentionLevel(now: base.addingTimeInterval(period), period: period, reduceMotion: false)
            #expect(abs(wrapped - boundary) < 0.0001)
        }
    }

    // MARK: - Closed-pill bloom resolution (AC #6)

    /// Only the two attention states bloom; every other state stays flat hardware
    /// (`nil`). The permission maps to the warning tint/cadence, the question to
    /// the caution tint/cadence.
    @Test
    func bloomResolvesOnlyForAttentionStates() {
        func activity(_ phase: SessionPhase, outcome: SessionOutcome = .success, fresh: Bool = true) -> IslandClosedPillActivity {
            IslandClosedPillActivity(phase: phase, outcome: outcome, isOutcomeFresh: fresh)
        }

        #expect(
            FlightDeckPillBloom.resolve(activity: activity(.waitingForApproval), mode: .waiting, rightSlot: nil) == .permission
        )
        #expect(
            FlightDeckPillBloom.resolve(activity: activity(.waitingForAnswer), mode: .waiting, rightSlot: nil) == .question
        )
        #expect(
            FlightDeckPillBloom.resolve(activity: activity(.running), mode: .running, rightSlot: nil) == nil
        )
        #expect(
            FlightDeckPillBloom.resolve(activity: activity(.completed, outcome: .success), mode: .idle, rightSlot: nil) == nil
        )
        // No spotlight, idle glyph → no bloom.
        #expect(
            FlightDeckPillBloom.resolve(activity: nil, mode: .idle, rightSlot: nil) == nil
        )

        // The permission is the louder alarm: faster cadence + stronger border.
        #expect(FlightDeckPillBloom.permission.period == FlightDeckMotion.Attention.warningPeriod)
        #expect(FlightDeckPillBloom.question.period == FlightDeckMotion.Attention.cautionPeriod)
        #expect(FlightDeckPillBloom.permission.period < FlightDeckPillBloom.question.period)
        #expect(FlightDeckPillBloom.permission.borderOpacity > FlightDeckPillBloom.question.borderOpacity)
    }
}
