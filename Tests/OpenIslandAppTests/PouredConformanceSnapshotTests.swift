import XCTest

@testable import OpenIslandApp

/// AB-333 (draft T15): the Poured 2.0 A–K conformance snapshot pins.
///
/// Each `AppearancePreviewScenario` that maps to a §4 scenario is pinned through
/// the shared `ThemeSnapshotting` harness (AB-327) at both panel widths (notch
/// 540pt / top-bar 520pt), plus the two §5.3 accessibility variants (Increase
/// Contrast of C, Reduce Transparency of E) and the closed-pill ambient frames
/// the harness can render without threading a `PouredPillAmbientState` (A1 idle /
/// A2 working — the amber/gold/outcome pill glows A3–A6 are driven upstream of
/// the `closedPill` slot and are verified at code level in `CONFORMANCE-AB-333.md`).
///
/// Goldens are byte-exact and gated on the environment fingerprint, so a
/// differently-rendering CI runner skips the pixel compare rather than failing
/// (see `ThemeSnapshotting`). Re-record with `OPEN_ISLAND_RECORD_SNAPSHOTS=1`.
@MainActor
final class PouredConformanceSnapshotTests: XCTestCase {

    private func theme() -> PouredIslandTheme { PouredIslandTheme() }

    // MARK: - Scenario list frames (C · D · E1–E3 · F · G · H · A6 · I · J)

    /// Pins one scenario at both panel widths under `named`-`notch` / `-topbar`.
    private func assertBothProfiles(
        _ scenario: AppearancePreviewScenario,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) throws {
        for profile in [ThemeSnapshotting.Profile.notch, .topBar] {
            let suffix = profile == .notch ? "notch" : "topbar"
            try ThemeSnapshotting.assertSnapshot(
                theme: theme(),
                slot: .sessionList(scenario: scenario),
                profile: profile,
                named: "\(name)-\(suffix)",
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    /// D · G — the expanded running row: metadata grid + subagent/task nests.
    func testExpandedDetailAndSubagents() throws {
        try assertBothProfiles(.subagents, named: "poured-D-G-subagents")
    }

    /// E1 — permission hero over a shell command (`$ swift build …`, syntax spans,
    /// scoped allow rows, keycaps).
    func testPermissionCommandHero() throws {
        try assertBothProfiles(.permissionCommand, named: "poured-E1-permission-command")
    }

    /// E2 — permission hero with the inline Edit diff.
    func testPermissionDiffHero() throws {
        try assertBothProfiles(.permissionDiff, named: "poured-E2-permission-diff")
    }

    /// E3 — Codex terminal-approval hero (blue-tinted, single jump CTA).
    func testCodexApprovalHero() throws {
        try assertBothProfiles(.codexApproval, named: "poured-E3-codex-approval")
    }

    /// F — the question hero: gold `.q-hero` wash, header chip, selection ring.
    func testQuestionHero() throws {
        try assertBothProfiles(.questionMulti, named: "poured-F-question")
    }

    /// H — the completion body: Success badge + tabular duration + rich prose +
    /// action rail.
    func testCompletionSuccess() throws {
        try assertBothProfiles(.completedSuccess, named: "poured-H-completed-success")
    }

    /// A6 — the completed outcome variants (interrupted expanded, failed collapsed).
    func testCompletedOutcomeVariants() throws {
        try assertBothProfiles(.completedVariants, named: "poured-A6-completed-variants")
    }

    /// I — the usage meters (header rings + full §I meter card).
    func testUsageMeters() throws {
        try assertBothProfiles(.meters, named: "poured-I-usage-meters")
    }

    /// J — the empty state (breathing glyph, hooks-installed reassurance pill).
    func testEmptyState() throws {
        try assertBothProfiles(.empty, named: "poured-J-empty")
    }

    // Accessibility conformance (Increase Contrast of C, Reduce Transparency of
    // E/F, Reduce Motion on pulsing surfaces) is verified at **code level** in
    // `CONFORMANCE-AB-333.md`: the environment keys the rows read
    // (`\.colorSchemeContrast`, `\.accessibilityReduceTransparency`,
    // `\.accessibilityReduceMotion`) are read-only in this SDK, so the harness
    // can't inject them to pin a variant golden. The branches themselves are the
    // pinned evidence (file:line in the checklist).

    // MARK: - Closed-pill ambient frames the harness supports (A1 · A2)

    /// A1 — idle pill (still 3-bar glyph, no glow).
    func testClosedPillIdle() throws {
        for profile in [ThemeSnapshotting.Profile.notch, .topBar] {
            let suffix = profile == .notch ? "notch" : "topbar"
            try ThemeSnapshotting.assertSnapshot(
                theme: theme(),
                slot: .closedPill(mode: .idle, rightSlot: nil),
                profile: profile,
                named: "poured-A1-idle-pill-\(suffix)"
            )
        }
    }

    /// A2 — working pill (running wave glyph, `×3` count).
    func testClosedPillWorking() throws {
        for profile in [ThemeSnapshotting.Profile.notch, .topBar] {
            let suffix = profile == .notch ? "notch" : "topbar"
            try ThemeSnapshotting.assertSnapshot(
                theme: theme(),
                slot: .closedPill(mode: .running, rightSlot: .count(3)),
                profile: profile,
                named: "poured-A2-working-pill-\(suffix)"
            )
        }
    }
}
