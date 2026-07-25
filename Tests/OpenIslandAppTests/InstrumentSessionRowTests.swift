import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-309 (instrument 3/4): the pure display rules behind the tabular session
/// row — the column-register widths, the row rhythm, the "Unknown" guard, the
/// interrupted/failed glyph, the motion-gated blink, and the ≥10pt floor.
///
/// The SwiftUI body itself isn't rendered here (there's no headless view host);
/// the row deliberately routes every AC-bearing decision through
/// `InstrumentSessionRowFormat` / `InstrumentSessionRowGrid` so the contract is
/// testable without one.
struct InstrumentSessionRowTests {

    // MARK: - One column grid (AC #1)

    @Test
    func registeredTrailingColumnsHaveFixedNonZeroLanes() {
        // Model, host and age each hold a constant lane so they land on the same
        // x across every row — the "exact vertical registers" the grid is built
        // on. A zero-width lane would collapse the register.
        for width in InstrumentSessionRowGrid.registeredColumnWidths {
            #expect(width > 0)
        }
        // The age lane matches the shared trailing-cluster metric so it lines up
        // with the other themes' rows interleaved in one list.
        #expect(InstrumentSessionRowGrid.ageColumnWidth == IslandSessionRowMetrics.ageColumnWidth)
        // The agent tick is a hairline 3px mark, not a filled pill.
        #expect(InstrumentSessionRowGrid.agentTickWidth == 3)
    }

    // MARK: - Row rhythm (AC #3)

    @Test
    func rowRhythmIsOneLineDoneTwoLineRunningAndIdle() {
        // done (a fresh completed row: not running, not inactive) → 1 line.
        #expect(InstrumentSessionRowFormat.showsSubLine(isRunning: false, isIdle: false) == false)
        // running → 2 lines (activity sub-line).
        #expect(InstrumentSessionRowFormat.showsSubLine(isRunning: true, isIdle: false) == true)
        // idle → 2 lines (prompt sub-line, dimmed).
        #expect(InstrumentSessionRowFormat.showsSubLine(isRunning: false, isIdle: true) == true)
    }

    // MARK: - Never display "Unknown" (AC #2)

    @Test
    func unknownWorkspaceIsNeverDisplayed() {
        let unknown = JumpTarget.unknownTerminalApp
        // A bare "Unknown" workspace is swapped for the agent's display name.
        #expect(
            InstrumentSessionRowFormat.displayHeadline(headline: unknown, workspace: unknown, fallback: "Claude Code")
                == "Claude Code"
        )
        // …including when it's the workspace token embedded in a longer headline.
        #expect(
            InstrumentSessionRowFormat.displayHeadline(
                headline: "\(unknown) · fix the bug",
                workspace: unknown,
                fallback: "Claude Code"
            ) == "Claude Code · fix the bug"
        )
        // A real workspace passes straight through, untouched.
        #expect(
            InstrumentSessionRowFormat.displayHeadline(
                headline: "open-island · ship it",
                workspace: "open-island",
                fallback: "Claude Code"
            ) == "open-island · ship it"
        )
    }

    // MARK: - Interrupted / failed distinct via glyph (AC #4)

    @Test
    func completionOutcomesMapToDistinctGlyphs() {
        let success = InstrumentSessionRowFormat.statusGlyphName(phase: .completed, outcome: .success)
        let interrupted = InstrumentSessionRowFormat.statusGlyphName(phase: .completed, outcome: .interrupted)
        let failed = InstrumentSessionRowFormat.statusGlyphName(phase: .completed, outcome: .failed)

        // A clean finish reads as a quiet check.
        #expect(success == "checkmark")
        // Interrupted and failed each get a distinct glyph, and neither collides
        // with the success check.
        #expect(interrupted != success)
        #expect(failed != success)
        #expect(interrupted != failed)
    }

    // MARK: - Motion-gated running blink (AC #4)

    @Test
    func runningBlinkIsGatedByReduceMotion() {
        // Under Reduce Motion the tick is pinned fully lit — no animation.
        #expect(InstrumentSessionRowFormat.blinkOpacity(phase: 0.0, reduceMotion: true) == 1)
        #expect(InstrumentSessionRowFormat.blinkOpacity(phase: 1.0, reduceMotion: true) == 1)
        // With motion, it steps crisply between lit and dim across the phase.
        #expect(InstrumentSessionRowFormat.blinkOpacity(phase: 0.9, reduceMotion: false) == 1)
        #expect(InstrumentSessionRowFormat.blinkOpacity(phase: 0.1, reduceMotion: false) < 1)
    }

    // MARK: - ≥10pt floor (AC #7)

    @Test
    func everyReadableRowSizeHoldsTheTenPointFloor() {
        #expect(!InstrumentSessionRowFormat.readableTextSizes.isEmpty)
        for size in InstrumentSessionRowFormat.readableTextSizes {
            #expect(size >= InstrumentTypography.floor)
        }
    }

    // MARK: - Actionable approval surfaces (AB-310)

    /// AC #1 / #2: the ALLOW / always-allow / DENY buttons must print the
    /// **real** registered `OverlayPanelController` shortcuts — ⌘Y, ⌘⇧Y, ⌘N —
    /// never the mockup's ⏎/⎋.
    @Test
    func approvalKeyHintGlyphsMatchTheRegisteredShortcuts() {
        #expect(InstrumentApprovalFormat.Shortcut.allowOnce.glyphString == "⌘Y")
        #expect(InstrumentApprovalFormat.Shortcut.alwaysAllow.glyphString == "⌘⇧Y")
        #expect(InstrumentApprovalFormat.Shortcut.deny.glyphString == "⌘N")

        // Every glyph string is built from the ordered glyph run, and the three
        // shortcuts stay distinct so no two buttons print the same hint.
        for shortcut in InstrumentApprovalFormat.Shortcut.allCases {
            #expect(shortcut.glyphString == shortcut.glyphs.joined())
        }
        let hints = InstrumentApprovalFormat.Shortcut.allCases.map(\.glyphString)
        #expect(Set(hints).count == hints.count)
    }

    /// AC #4: a non-success completion never shares the success row's quiet
    /// check — interrupted and failed each get a distinct, unmistakable glyph.
    @Test
    func completionOutcomeBannerGlyphsAreDistinct() {
        let interrupted = InstrumentApprovalFormat.completionOutcomeGlyphName(outcome: .interrupted)
        let failed = InstrumentApprovalFormat.completionOutcomeGlyphName(outcome: .failed)
        #expect(interrupted != failed)
        // Neither collides with the success-row check the tabular grid draws.
        #expect(interrupted != InstrumentSessionRowFormat.statusGlyphName(phase: .completed, outcome: .success))
        #expect(failed != InstrumentSessionRowFormat.statusGlyphName(phase: .completed, outcome: .success))
    }

    /// AC #7: the alarm / completion surfaces hold the same ≥10pt readable floor
    /// as the rest of the theme — no 8.5px micro-type.
    @Test
    func everyReadableActionableSizeHoldsTheTenPointFloor() {
        #expect(!InstrumentApprovalFormat.readableTextSizes.isEmpty)
        for size in InstrumentApprovalFormat.readableTextSizes {
            #expect(size >= InstrumentTypography.floor)
        }
    }
}
