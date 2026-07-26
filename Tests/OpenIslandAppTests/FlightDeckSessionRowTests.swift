import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-313 (flightdeck 3/4): the pure display rules behind the annunciator
/// session row — the status-lane state / prominence / pulse mapping, the column-
/// register widths, the row rhythm, the "Unknown" guard, the SSH / app cell, the
/// interrupted/failed glyph, the motion-gated pulse, and the ≥10pt floor.
///
/// The SwiftUI body itself isn't rendered here (there's no headless view host);
/// the row deliberately routes every AC-bearing decision through
/// `FlightDeckSessionRowFormat` / `FlightDeckSessionRowGrid` so the contract is
/// testable without one.
struct FlightDeckSessionRowTests {

    // MARK: - Status lane: state mapping (AC #1)

    @Test
    func lanePriorityMapsEveryStateToItsLane() {
        // Running (green run) — an active turn.
        #expect(
            FlightDeckSessionRowFormat.lanePriority(phase: .running, presence: .running, outcome: .success)
                == .running
        )
        // Done success (blue done) — a fresh clean finish.
        #expect(
            FlightDeckSessionRowFormat.lanePriority(phase: .completed, presence: .active, outcome: .success)
                == .done
        )
        // Failed / interrupted (red alert) — a non-success completion reads as loud
        // as an alarm, never as a quiet done.
        #expect(
            FlightDeckSessionRowFormat.lanePriority(phase: .completed, presence: .active, outcome: .failed)
                == .alert
        )
        #expect(
            FlightDeckSessionRowFormat.lanePriority(phase: .completed, presence: .active, outcome: .interrupted)
                == .alert
        )
        // Attention phases (MASTER CAUTION) also fold into the alert lane.
        #expect(
            FlightDeckSessionRowFormat.lanePriority(phase: .waitingForApproval, presence: .active, outcome: .success)
                == .alert
        )
        // Inactive presence always recedes to the idle (grey) lane, whatever the
        // stored outcome — a stale completed row is grey, not blue/red.
        #expect(
            FlightDeckSessionRowFormat.lanePriority(phase: .completed, presence: .inactive, outcome: .failed)
                == .idle
        )
    }

    // MARK: - Status lane: grayscale brightness redundancy (AC #7)

    @Test
    func alertLaneIsPhysicallyLoudestForGrayscaleRedundancy() {
        // The alert lane must be the widest AND at least as opaque as every other
        // lane, so it stays the loudest mark in a grayscale screenshot where red
        // carries no more luminance than green — redundancy by area/brightness,
        // not by hue alone.
        let alertWidth = FlightDeckSessionRowFormat.laneWidth(.alert)
        let alertOpacity = FlightDeckSessionRowFormat.laneOpacity(.alert)
        for other in FlightDeckSessionRowFormat.LanePriority.allCases where other != .alert {
            #expect(alertWidth > FlightDeckSessionRowFormat.laneWidth(other))
            #expect(alertOpacity >= FlightDeckSessionRowFormat.laneOpacity(other))
        }
        // The prominence ramp is monotonic: every lane is louder than idle.
        let idleWidth = FlightDeckSessionRowFormat.laneWidth(.idle)
        let idleOpacity = FlightDeckSessionRowFormat.laneOpacity(.idle)
        for lane in FlightDeckSessionRowFormat.LanePriority.allCases where lane != .idle {
            #expect(FlightDeckSessionRowFormat.laneWidth(lane) >= idleWidth)
            #expect(FlightDeckSessionRowFormat.laneOpacity(lane) > idleOpacity)
        }
    }

    // MARK: - Status lane: retimed motion mode (AC #1 / #4 / #5)

    @Test
    func laneMotionSplitsRunningBreatheFromAttentionCadence() {
        // A running turn breathes (2.0s phosphor), replacing the old two-step blink.
        #expect(
            FlightDeckSessionRowFormat.laneMotion(phase: .running, presence: .running, outcome: .success)
                == .breathe
        )
        // The attention phases keep their *distinct* EICAS cadences: warning red
        // (permission) throbs faster than caution amber (question).
        #expect(
            FlightDeckSessionRowFormat.laneMotion(phase: .waitingForApproval, presence: .active, outcome: .success)
                == .attention(period: FlightDeckMotion.Attention.warningPeriod)
        )
        #expect(
            FlightDeckSessionRowFormat.laneMotion(phase: .waitingForAnswer, presence: .active, outcome: .success)
                == .attention(period: FlightDeckMotion.Attention.cautionPeriod)
        )
        #expect(FlightDeckMotion.Attention.warningPeriod < FlightDeckMotion.Attention.cautionPeriod)
    }

    @Test
    func laneMotionSettlesOnSuccessAndHoldsSteadyOtherwise() {
        // A fresh completed *success* plays the one-shot settle (nominal flash →
        // advisory dot, A5)…
        #expect(
            FlightDeckSessionRowFormat.laneMotion(phase: .completed, presence: .active, outcome: .success)
                == .settle
        )
        // …while a non-success completion rests steady in its loud alert colour
        // (glyph + width carry the state, not a pulse)…
        #expect(
            FlightDeckSessionRowFormat.laneMotion(phase: .completed, presence: .active, outcome: .failed)
                == .steady
        )
        #expect(
            FlightDeckSessionRowFormat.laneMotion(phase: .completed, presence: .active, outcome: .interrupted)
                == .steady
        )
        // …and an inactive/stale row recedes to a steady dim bar regardless of phase.
        #expect(
            FlightDeckSessionRowFormat.laneMotion(phase: .running, presence: .inactive, outcome: .success)
                == .steady
        )
        #expect(
            FlightDeckSessionRowFormat.laneMotion(phase: .completed, presence: .inactive, outcome: .success)
                == .steady
        )
    }

    // MARK: - Success settle ramp (AC #5)

    @Test
    func settleFlashDecaysThenRests() {
        // At the instant of completion the flash is full (scaled + wide green halo)…
        #expect(FlightDeckMotion.settleFlashAmount(progress: 0) == 1)
        // …decays to nothing by the flash key-time…
        #expect(FlightDeckMotion.settleFlashAmount(progress: FlightDeckMotion.Settle.flashKeyTime) == 0)
        // …and stays at nothing through the settled rest (a done row born settled
        // shows the calm advisory dot, not the flash — deterministic under snapshot).
        #expect(FlightDeckMotion.settleFlashAmount(progress: 1) == 0)
        // Monotonic across the flash window.
        let early = FlightDeckMotion.settleFlashAmount(progress: FlightDeckMotion.Settle.flashKeyTime * 0.25)
        let late = FlightDeckMotion.settleFlashAmount(progress: FlightDeckMotion.Settle.flashKeyTime * 0.75)
        #expect(early > late)
    }

    // MARK: - Steady-lane phosphor (AC #1)

    @Test
    func steadyAlertLaneGlowsButIdleLaneStaysDark() {
        // A loud steady lane (failed/interrupted, resting opacity 1.0) is still a
        // lit lamp — it casts a static halo…
        let alert = FlightDeckSessionRowFormat.laneOpacity(.alert)
        #expect(FlightDeckSessionRowFormat.steadyLaneGlowIntensity(restingOpacity: alert) > 0)
        // …while the recessed idle lane (0.4) is unlit and casts nothing.
        let idle = FlightDeckSessionRowFormat.laneOpacity(.idle)
        #expect(FlightDeckSessionRowFormat.steadyLaneGlowIntensity(restingOpacity: idle) == 0)
    }

    // MARK: - One column grid (AC #2)

    @Test
    func registeredTrailingColumnsHaveFixedNonZeroLanes() {
        // Model, app and time each hold a constant lane so they land on the same
        // x under their captions across every row — the "exact vertical registers"
        // the grid is built on. A zero-width lane would collapse the register.
        for width in FlightDeckSessionRowGrid.registeredColumnWidths {
            #expect(width > 0)
        }
        // The reserved control lanes match the shared trailing-cluster metrics so
        // the caption strip and the row share one trailing geometry.
        #expect(FlightDeckSessionRowGrid.detailToggleColumnWidth == IslandSessionRowMetrics.detailToggleColumnWidth)
        #expect(FlightDeckSessionRowGrid.dismissColumnWidth == IslandSessionRowMetrics.dismissColumnWidth)
    }

    // MARK: - Row rhythm (AC #4)

    @Test
    func rowRhythmIsOneLineDoneTwoLineRunningAndIdle() {
        // done (a fresh completed row: not running, not inactive) → 1 line.
        #expect(FlightDeckSessionRowFormat.showsSubLine(isRunning: false, isIdle: false) == false)
        // running → 2 lines (activity sub-line).
        #expect(FlightDeckSessionRowFormat.showsSubLine(isRunning: true, isIdle: false) == true)
        // idle → 2 lines (prompt sub-line, dimmed).
        #expect(FlightDeckSessionRowFormat.showsSubLine(isRunning: false, isIdle: true) == true)
    }

    // MARK: - Never display "Unknown" (AC #2)

    @Test
    func unknownWorkspaceIsNeverDisplayed() {
        let unknown = JumpTarget.unknownTerminalApp
        // A bare "Unknown" workspace is swapped for the agent's display name.
        #expect(
            FlightDeckSessionRowFormat.displayHeadline(headline: unknown, workspace: unknown, fallback: "Claude Code")
                == "Claude Code"
        )
        // …including when it's the workspace token embedded in a longer headline.
        #expect(
            FlightDeckSessionRowFormat.displayHeadline(
                headline: "\(unknown) · fix the bug",
                workspace: unknown,
                fallback: "Claude Code"
            ) == "Claude Code · fix the bug"
        )
        // A real workspace passes straight through, untouched.
        #expect(
            FlightDeckSessionRowFormat.displayHeadline(
                headline: "open-island · ship it",
                workspace: "open-island",
                fallback: "Claude Code"
            ) == "open-island · ship it"
        )
    }

    // MARK: - APP cell: SSH renders distinctly (AC #2 / #4)

    @Test
    func appColumnRendersSSHForRemoteAndTerminalOtherwise() {
        // A remote session reads SSH in the app lane, whatever its terminal.
        #expect(FlightDeckSessionRowFormat.appColumnText(isRemote: true, terminalBadge: nil) == "SSH")
        #expect(FlightDeckSessionRowFormat.appColumnText(isRemote: true, terminalBadge: "Ghostty") == "SSH")
        // A local session shows its terminal / IDE app.
        #expect(FlightDeckSessionRowFormat.appColumnText(isRemote: false, terminalBadge: "Ghostty") == "Ghostty")
        // No terminal and not remote → nil, so the cell draws its em-dash
        // placeholder rather than a bare "Unknown".
        #expect(FlightDeckSessionRowFormat.appColumnText(isRemote: false, terminalBadge: nil) == nil)
        #expect(FlightDeckSessionRowFormat.appColumnText(isRemote: false, terminalBadge: "   ") == nil)
    }

    // MARK: - Interrupted / failed distinct via glyph (AC #4)

    @Test
    func completionOutcomesMapToDistinctGlyphs() {
        let success = FlightDeckSessionRowFormat.statusGlyphName(phase: .completed, outcome: .success)
        let interrupted = FlightDeckSessionRowFormat.statusGlyphName(phase: .completed, outcome: .interrupted)
        let failed = FlightDeckSessionRowFormat.statusGlyphName(phase: .completed, outcome: .failed)

        // A clean finish reads as a quiet check.
        #expect(success == "checkmark")
        // Interrupted and failed each get a distinct glyph, and neither collides
        // with the success check.
        #expect(interrupted != success)
        #expect(failed != success)
        #expect(interrupted != failed)
    }

    // MARK: - ≥10pt floor (AC #6)

    @Test
    func everyReadableRowSizeHoldsTheTenPointFloor() {
        #expect(!FlightDeckSessionRowFormat.readableTextSizes.isEmpty)
        for size in FlightDeckSessionRowFormat.readableTextSizes {
            #expect(size >= FlightDeckTypography.floor)
        }
    }

    // MARK: - MASTER CAUTION approval surfaces (AB-314)

    /// AC #1 / #2: the ALLOW / always-allow / DENY switches must print the
    /// **real** registered `OverlayPanelController` shortcuts — ⌘Y, ⌘⇧Y, ⌘N —
    /// never the mockup's ⏎/⎋.
    @Test
    func approvalKeyHintGlyphsMatchTheRegisteredShortcuts() {
        #expect(FlightDeckApprovalFormat.Shortcut.allowOnce.glyphString == "⌘Y")
        #expect(FlightDeckApprovalFormat.Shortcut.alwaysAllow.glyphString == "⌘⇧Y")
        #expect(FlightDeckApprovalFormat.Shortcut.deny.glyphString == "⌘N")

        // Every glyph string is built from the ordered glyph run, and the three
        // shortcuts stay distinct so no two switches print the same hint.
        for shortcut in FlightDeckApprovalFormat.Shortcut.allCases {
            #expect(shortcut.glyphString == shortcut.glyphs.joined())
        }
        let hints = FlightDeckApprovalFormat.Shortcut.allCases.map(\.glyphString)
        #expect(Set(hints).count == hints.count)
    }

    /// AC #4: a non-success completion never shares the success row's quiet
    /// check — interrupted and failed each get a distinct, unmistakable glyph.
    @Test
    func completionOutcomeBannerGlyphsAreDistinct() {
        let interrupted = FlightDeckApprovalFormat.completionOutcomeGlyphName(outcome: .interrupted)
        let failed = FlightDeckApprovalFormat.completionOutcomeGlyphName(outcome: .failed)
        #expect(interrupted != failed)
        // Neither collides with the success-row check the row draws.
        #expect(interrupted != FlightDeckSessionRowFormat.statusGlyphName(phase: .completed, outcome: .success))
        #expect(failed != FlightDeckSessionRowFormat.statusGlyphName(phase: .completed, outcome: .success))
    }

    /// AC #1 / #7: the MASTER CAUTION glow pulses only with motion — under Reduce
    /// Motion it is pinned to a steady mid-level so the alarm reads without
    /// animating, and it always stays a legible, in-range opacity.
    @Test
    func cautionGlowIsGatedByReduceMotion() {
        // Under Reduce Motion the glow holds one steady level across the phase.
        let steadyLow = FlightDeckApprovalFormat.glowOpacity(phase: 0.0, reduceMotion: true)
        let steadyHigh = FlightDeckApprovalFormat.glowOpacity(phase: 1.0, reduceMotion: true)
        #expect(steadyLow == steadyHigh)
        #expect(steadyLow > 0 && steadyLow <= 1)

        // With motion it throbs: the trough (phase 0) is dimmer than the crest
        // (phase 0.5), and every value stays a visible, in-range opacity.
        let trough = FlightDeckApprovalFormat.glowOpacity(phase: 0.0, reduceMotion: false)
        let crest = FlightDeckApprovalFormat.glowOpacity(phase: 0.5, reduceMotion: false)
        #expect(crest > trough)
        for step in stride(from: 0.0, through: 1.0, by: 0.1) {
            let value = FlightDeckApprovalFormat.glowOpacity(phase: step, reduceMotion: false)
            #expect(value > 0 && value <= 1)
        }
    }

    /// AC #7: the alarm / completion surfaces hold the same ≥10pt readable floor
    /// as the rest of the theme — no sub-10pt micro-type.
    @Test
    func everyReadableActionableSizeHoldsTheTenPointFloor() {
        #expect(!FlightDeckApprovalFormat.readableTextSizes.isEmpty)
        for size in FlightDeckApprovalFormat.readableTextSizes {
            #expect(size >= FlightDeckTypography.floor)
        }
    }

    // MARK: - Annunciator beacons (AB-334)

    /// AC #4: the red permission beacon throbs faster than the amber question
    /// beacon — 1.0s vs 1.2s — so the two annunciators are told apart by rhythm.
    @Test
    func beaconPeriodsRetimeWarningFasterThanCaution() {
        #expect(FlightDeckApprovalFormat.permissionBeaconPeriod == 1.0)
        #expect(FlightDeckApprovalFormat.questionBeaconPeriod == 1.2)
        #expect(
            FlightDeckApprovalFormat.permissionBeaconPeriod
                < FlightDeckApprovalFormat.questionBeaconPeriod
        )
    }

    /// AC #4: the beacon pulses only with motion, now on the shared `attn` ramp
    /// (AB-336). Under Reduce Motion it is pinned to the lit peak (`opacityMax`, a
    /// lit lamp never dark); with motion it is brightest at the cycle boundary and
    /// dimmest mid-cycle (the mockup `attn` opacity `1.0 → 0.28`), stays in that
    /// band, and returns to its start after one period.
    @Test
    func beaconLevelIsGatedByReduceMotion() {
        let period = FlightDeckApprovalFormat.permissionBeaconPeriod
        let base = Date(timeIntervalSinceReferenceDate: 0)

        // Reduce Motion: one steady lit level (the peak) across the whole cycle.
        for offset in stride(from: 0.0, through: period, by: period / 8) {
            let value = FlightDeckApprovalFormat.beaconLevel(
                now: base.addingTimeInterval(offset), period: period, reduceMotion: true
            )
            #expect(value == FlightDeckMotion.Attention.opacityMax)
        }

        // With motion (`attn` ramp): brightest at the cycle boundary, dimmest half
        // a period in; every level stays inside the [opacityMin, opacityMax] band.
        let boundary = FlightDeckApprovalFormat.beaconLevel(now: base, period: period, reduceMotion: false)
        let mid = FlightDeckApprovalFormat.beaconLevel(
            now: base.addingTimeInterval(period / 2), period: period, reduceMotion: false
        )
        #expect(boundary > mid)
        for offset in stride(from: 0.0, through: period, by: period / 16) {
            let value = FlightDeckApprovalFormat.beaconLevel(
                now: base.addingTimeInterval(offset), period: period, reduceMotion: false
            )
            #expect(value >= FlightDeckMotion.Attention.opacityMin - 0.0001)
            #expect(value <= FlightDeckMotion.Attention.opacityMax + 0.0001)
        }
        // Periodic: the level is identical exactly one period later.
        let full = FlightDeckApprovalFormat.beaconLevel(
            now: base.addingTimeInterval(period), period: period, reduceMotion: false
        )
        #expect(abs(full - boundary) < 0.0001)
    }

    // MARK: - HELD count-up (AB-334)

    /// AC #5: the HELD readout counts up from `updatedAt` in `Nm SSs` form, pads
    /// the seconds, and hides itself (returns nil) when the elapsed approximation
    /// is negative (clock skew) or implausibly large (a stale row, not a live hold).
    @Test
    func heldReadoutFormatsElapsedAndHidesTheImplausible() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)

        // 8 seconds held → "0m 08s" (zero-padded seconds, matching the mockup).
        #expect(
            FlightDeckApprovalFormat.heldReadout(now: now, since: now.addingTimeInterval(-8))
                == "0m 08s"
        )
        // 2m 05s.
        #expect(
            FlightDeckApprovalFormat.heldReadout(now: now, since: now.addingTimeInterval(-125))
                == "2m 05s"
        )
        // Exactly now → "0m 00s" (the boundary is inclusive, not hidden).
        #expect(FlightDeckApprovalFormat.heldReadout(now: now, since: now) == "0m 00s")

        // Negative (future updatedAt / clock skew) → hidden.
        #expect(FlightDeckApprovalFormat.heldReadout(now: now, since: now.addingTimeInterval(5)) == nil)

        // Beyond the 24h ceiling → hidden (a stale row, not a live hold).
        let overCeiling = FlightDeckApprovalFormat.heldReadoutCeiling + 60
        #expect(
            FlightDeckApprovalFormat.heldReadout(now: now, since: now.addingTimeInterval(-overCeiling))
                == nil
        )
        // Just inside the ceiling → still shown.
        #expect(
            FlightDeckApprovalFormat.heldReadout(
                now: now, since: now.addingTimeInterval(-(FlightDeckApprovalFormat.heldReadoutCeiling - 1))
            ) != nil
        )
    }
}
