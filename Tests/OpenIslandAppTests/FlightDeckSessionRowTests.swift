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

    // MARK: - Status lane: which lanes pulse (AC #1)

    @Test
    func onlyLiveLanesPulse() {
        // A running turn and an attention phase pulse (the live/EICAS blink)…
        #expect(FlightDeckSessionRowFormat.lanePulses(phase: .running, presence: .running) == true)
        #expect(FlightDeckSessionRowFormat.lanePulses(phase: .waitingForApproval, presence: .active) == true)
        #expect(FlightDeckSessionRowFormat.lanePulses(phase: .waitingForAnswer, presence: .active) == true)
        // …while every settled outcome holds steady.
        #expect(FlightDeckSessionRowFormat.lanePulses(phase: .completed, presence: .active) == false)
        #expect(FlightDeckSessionRowFormat.lanePulses(phase: .completed, presence: .inactive) == false)
    }

    // MARK: - Motion-gated pulse (AC #1)

    @Test
    func lanePulseIsGatedByReduceMotion() {
        // Under Reduce Motion the lane is pinned fully lit — no animation.
        #expect(FlightDeckSessionRowFormat.pulseOpacity(phase: 0.0, reduceMotion: true) == 1)
        #expect(FlightDeckSessionRowFormat.pulseOpacity(phase: 1.0, reduceMotion: true) == 1)
        // With motion, it steps crisply between lit and dim across the phase.
        #expect(FlightDeckSessionRowFormat.pulseOpacity(phase: 0.9, reduceMotion: false) == 1)
        #expect(FlightDeckSessionRowFormat.pulseOpacity(phase: 0.1, reduceMotion: false) < 1)
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
}
