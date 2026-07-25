import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-317 (annual 3/4): the pure display rules behind the editorial dot-grammar
/// session row — the status-mark state mapping, the one-accent discipline, the
/// pulse gating, the meta-line construction, the "Unknown" guard, the SSH cell,
/// the interrupted / failed glyph, the ≥24pt control hit targets, and the ≥10pt
/// type floor.
///
/// The SwiftUI body itself isn't rendered here (there's no headless view host);
/// the row deliberately routes every AC-bearing decision through
/// `AnnualSessionRowFormat` / `AnnualSessionRowGrid` so the contract is testable
/// without one. The pixel screenshot, Accessibility-Inspector and live-scroll ACs
/// are flagged manual in the PR.
struct AnnualSessionRowTests {

    // MARK: - Dot grammar: state mapping (AC #2 · #4)

    @Test
    func statusMarkMapsEveryStateToItsDotGrammar() {
        // A running turn → the filled (pulsing) dot.
        #expect(
            AnnualSessionRowFormat.statusMark(phase: .running, presence: .running, outcome: .success)
                == .running
        )
        // A fresh clean finish → the hollow ring.
        #expect(
            AnnualSessionRowFormat.statusMark(phase: .completed, presence: .active, outcome: .success)
                == .done
        )
        // A non-success completion → its own distinct glyph mark, never the ring.
        #expect(
            AnnualSessionRowFormat.statusMark(phase: .completed, presence: .active, outcome: .interrupted)
                == .interrupted
        )
        #expect(
            AnnualSessionRowFormat.statusMark(phase: .completed, presence: .active, outcome: .failed)
                == .failed
        )
        // The attention phases → the one accent, pulsing.
        #expect(
            AnnualSessionRowFormat.statusMark(phase: .waitingForApproval, presence: .active, outcome: .success)
                == .attention
        )
        #expect(
            AnnualSessionRowFormat.statusMark(phase: .waitingForAnswer, presence: .active, outcome: .success)
                == .attention
        )
        // Inactive presence always recedes to the dim idle dot, whatever the
        // stored outcome — a stale completed (even failed) row is dim, not a glyph.
        #expect(
            AnnualSessionRowFormat.statusMark(phase: .completed, presence: .inactive, outcome: .failed)
                == .idle
        )
    }

    // MARK: - One-accent discipline (AC #8)

    /// The core row invariant behind "a mixed list with no attention session shows
    /// zero accent pixels": **only** a genuine attention mark spends the accent.
    /// Every calm mark — running, done, idle — and both non-success completions
    /// stay warm grey, because a completed row does not require attention.
    @Test
    func onlyAttentionMarksSpendTheAccent() {
        #expect(AnnualSessionRowFormat.spendsAccent(.attention) == true)
        for mark in AnnualSessionRowFormat.StatusMark.allCases where mark != .attention {
            #expect(AnnualSessionRowFormat.spendsAccent(mark) == false)
        }
        // Called out explicitly: interrupted and failed are distinct via glyph +
        // wording, but they never light the accent in a row.
        #expect(AnnualSessionRowFormat.spendsAccent(.interrupted) == false)
        #expect(AnnualSessionRowFormat.spendsAccent(.failed) == false)
    }

    // MARK: - Which marks pulse (AC #2)

    @Test
    func onlyLiveMarksPulse() {
        // A running turn and an attention phase pulse (the subtle breathe)…
        #expect(AnnualSessionRowFormat.pulses(phase: .running, presence: .running) == true)
        #expect(AnnualSessionRowFormat.pulses(phase: .waitingForApproval, presence: .active) == true)
        #expect(AnnualSessionRowFormat.pulses(phase: .waitingForAnswer, presence: .active) == true)
        // …while every settled outcome holds steady.
        #expect(AnnualSessionRowFormat.pulses(phase: .completed, presence: .active) == false)
        #expect(AnnualSessionRowFormat.pulses(phase: .completed, presence: .inactive) == false)
    }

    // MARK: - Motion-gated pulse (AC #2)

    @Test
    func dotPulseIsGatedByReduceMotionAndStaysInRange() {
        // Under Reduce Motion the dot is pinned fully lit — no animation.
        #expect(AnnualSessionRowFormat.pulseOpacity(phase: 0.0, reduceMotion: true) == 1)
        #expect(AnnualSessionRowFormat.pulseOpacity(phase: 0.5, reduceMotion: true) == 1)
        // With motion it breathes: the crest (phase 0.5) is brighter than the
        // trough (phase 0), and every value stays a legible, in-range opacity.
        let trough = AnnualSessionRowFormat.pulseOpacity(phase: 0.0, reduceMotion: false)
        let crest = AnnualSessionRowFormat.pulseOpacity(phase: 0.5, reduceMotion: false)
        #expect(crest > trough)
        for step in stride(from: 0.0, through: 1.0, by: 0.1) {
            let value = AnnualSessionRowFormat.pulseOpacity(phase: step, reduceMotion: false)
            #expect(value > 0 && value <= 1)
        }
    }

    // MARK: - Row rhythm

    @Test
    func rowRhythmIsOneLineDoneTwoLineRunningAndIdle() {
        // done (a fresh completed row) → 1 line (headline + meta).
        #expect(AnnualSessionRowFormat.showsSubLine(isRunning: false, isIdle: false) == false)
        // running → an activity sub-line.
        #expect(AnnualSessionRowFormat.showsSubLine(isRunning: true, isIdle: false) == true)
        // idle → a prompt sub-line, receded.
        #expect(AnnualSessionRowFormat.showsSubLine(isRunning: false, isIdle: true) == true)
    }

    // MARK: - Never display "Unknown" (AC #1)

    @Test
    func unknownWorkspaceIsNeverDisplayed() {
        let unknown = JumpTarget.unknownTerminalApp
        #expect(
            AnnualSessionRowFormat.displayHeadline(headline: unknown, workspace: unknown, fallback: "Claude Code")
                == "Claude Code"
        )
        #expect(
            AnnualSessionRowFormat.displayHeadline(
                headline: "\(unknown) · fix the bug",
                workspace: unknown,
                fallback: "Claude Code"
            ) == "Claude Code · fix the bug"
        )
        // A real workspace passes straight through.
        #expect(
            AnnualSessionRowFormat.displayHeadline(
                headline: "open-island · ship it",
                workspace: "open-island",
                fallback: "Claude Code"
            ) == "open-island · ship it"
        )
    }

    // MARK: - Meta line: lowercase, vendor-free, SSH within the line (AC #1 · #4)

    @Test
    func metaLineIsLowercaseAndCarriesSSHWithinTheLine() {
        // The canonical shape: agent · model · app, all lowercase.
        #expect(
            AnnualSessionRowFormat.metaLine(agent: "claude", model: "Fable 5", isRemote: false, terminal: "Ghostty")
                == "claude · fable 5 · ghostty"
        )
        // A remote session reads `ssh` in the app position, whatever the terminal —
        // the SSH state renders within the meta line, not as a separate cell.
        #expect(
            AnnualSessionRowFormat.metaLine(agent: "claude", model: "Sonnet 4.5", isRemote: true, terminal: "Ghostty")
                == "claude · sonnet 4.5 · ssh"
        )
        // An absent model is dropped rather than printing a placeholder.
        #expect(
            AnnualSessionRowFormat.metaLine(agent: "codex", model: nil, isRemote: false, terminal: "Terminal")
                == "codex · terminal"
        )
        // No terminal and not remote → the app piece is dropped (never "Unknown").
        #expect(
            AnnualSessionRowFormat.metaLine(agent: "gemini", model: "Gemini 2.5", isRemote: false, terminal: nil)
                == "gemini · gemini 2.5"
        )
        // A whitespace-only model / terminal is treated as absent.
        #expect(
            AnnualSessionRowFormat.metaLine(agent: "kimi", model: "   ", isRemote: false, terminal: "  ")
                == "kimi"
        )
    }

    // MARK: - Interrupted / failed distinct via glyph (AC #2)

    @Test
    func completionOutcomesMapToDistinctGlyphs() {
        let success = AnnualSessionRowFormat.statusGlyphName(phase: .completed, outcome: .success)
        let interrupted = AnnualSessionRowFormat.statusGlyphName(phase: .completed, outcome: .interrupted)
        let failed = AnnualSessionRowFormat.statusGlyphName(phase: .completed, outcome: .failed)

        #expect(success == "checkmark")
        // Interrupted and failed each get a distinct glyph, and neither collides
        // with the success check.
        #expect(interrupted != success)
        #expect(failed != success)
        #expect(interrupted != failed)
    }

    // MARK: - Control hit targets ≥ 24×24 (AC #5)

    @Test
    func everyInteractiveControlHoldsTheTwentyFourPointHitFloor() {
        #expect(!AnnualSessionRowGrid.controlHitTargets.isEmpty)
        for target in AnnualSessionRowGrid.controlHitTargets {
            #expect(target >= AnnualSessionRowGrid.minHitTarget)
        }
        // The dismiss lane is deliberately wider than the shared 16pt classic
        // dismiss so its hit target clears the floor even though the ✕ glyph is
        // small.
        #expect(AnnualSessionRowGrid.dismissHitWidth >= AnnualSessionRowGrid.minHitTarget)
        #expect(AnnualSessionRowGrid.chevronHitWidth >= AnnualSessionRowGrid.minHitTarget)
    }

    // MARK: - Single time lane (AC #1)

    @Test
    func timeColumnIsOneFixedNonZeroLane() {
        // The time is right-aligned in a single fixed lane so it lands on the same
        // x across every row.
        #expect(AnnualSessionRowGrid.timeColumnWidth > 0)
        #expect(AnnualSessionRowGrid.timeColumnWidth == IslandSessionRowMetrics.ageColumnWidth)
    }

    // MARK: - ≥10pt floor (AC #7)

    @Test
    func everyReadableRowSizeHoldsTheTenPointFloor() {
        #expect(!AnnualSessionRowFormat.readableTextSizes.isEmpty)
        for size in AnnualSessionRowFormat.readableTextSizes {
            #expect(size >= AnnualTypography.floor)
        }
    }

    // MARK: - Row jump string localizes (AC #1 · #7)

    @Test
    func rowJumpStringLocalizesInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            let resolved = manager.t("island.annual.row.jump")
            #expect(resolved != "island.annual.row.jump", "row.jump is unlocalized in \(language)")
            #expect(!resolved.isEmpty)
        }
    }

    // MARK: - Typographic alarm: key-hint glyphs (AB-318 · AC #1 · #2)

    /// The `allow` / always-allow / `deny` buttons must print the **real** registered
    /// `OverlayPanelController` shortcuts — ⌘Y, ⌘⇧Y, ⌘N — so the on-screen hint never
    /// drifts from the keys that actually fire.
    @Test
    func approvalKeyHintGlyphsMatchTheRegisteredShortcuts() {
        #expect(AnnualApprovalFormat.Shortcut.allowOnce.glyphString == "⌘Y")
        #expect(AnnualApprovalFormat.Shortcut.alwaysAllow.glyphString == "⌘⇧Y")
        #expect(AnnualApprovalFormat.Shortcut.deny.glyphString == "⌘N")

        // Every glyph string is built from the ordered glyph run, and the three
        // shortcuts stay distinct so no two buttons print the same hint.
        for shortcut in AnnualApprovalFormat.Shortcut.allCases {
            #expect(shortcut.glyphString == shortcut.glyphs.joined())
        }
        let hints = AnnualApprovalFormat.Shortcut.allCases.map(\.glyphString)
        #expect(Set(hints).count == hints.count)
    }

    // MARK: - Approval / question are the accent-bearing phases (AB-318 · AC #6)

    /// The single accent is spent only on the alarm and the pending question. Both
    /// attention phases resolve to the `.attention` mark, which is the one mark that
    /// spends the accent — every completion / running actionable header stays grey.
    @Test
    func onlyAttentionPhasesLightTheAlarmAccent() {
        for phase in [SessionPhase.waitingForApproval, .waitingForAnswer] {
            let mark = AnnualSessionRowFormat.statusMark(phase: phase, presence: .active, outcome: .success)
            #expect(mark == .attention)
            #expect(AnnualSessionRowFormat.spendsAccent(mark) == true)
        }
        // A completed actionable header (success / interrupted / failed) never spends
        // the accent, so a completion card can't compete with the permission row.
        for outcome in [SessionOutcome.success, .interrupted, .failed] {
            let mark = AnnualSessionRowFormat.statusMark(phase: .completed, presence: .active, outcome: outcome)
            #expect(AnnualSessionRowFormat.spendsAccent(mark) == false)
        }
    }

    // MARK: - Completion outcome glyphs are distinct + accent-free (AB-318 · AC #4)

    @Test
    func completionOutcomeGlyphsAreDistinct() {
        let interrupted = AnnualApprovalFormat.completionOutcomeGlyphName(outcome: .interrupted)
        let failed = AnnualApprovalFormat.completionOutcomeGlyphName(outcome: .failed)
        #expect(interrupted != failed)
        // Neither collides with the success-row check the header draws.
        #expect(interrupted != AnnualSessionRowFormat.statusGlyphName(phase: .completed, outcome: .success))
        #expect(failed != AnnualSessionRowFormat.statusGlyphName(phase: .completed, outcome: .success))
    }

    // MARK: - ≥10pt floor on the alarm / completion surfaces (AB-318 · AC #7)

    @Test
    func everyReadableActionableSizeHoldsTheTenPointFloor() {
        #expect(!AnnualApprovalFormat.readableTextSizes.isEmpty)
        for size in AnnualApprovalFormat.readableTextSizes {
            #expect(size >= AnnualTypography.floor)
        }
    }

    // MARK: - Approval strings localize in every language (AB-318 · AC #7)

    @Test
    func approvalStringsLocalizeInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let keys = [
            "island.annual.approval.permissionRequired",
            "island.annual.approval.allow",
            "island.annual.approval.deny",
        ]
        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            for key in keys {
                let resolved = manager.t(key)
                #expect(resolved != key, "\(key) is unlocalized in \(language)")
                #expect(!resolved.isEmpty)
            }
        }
    }
}
