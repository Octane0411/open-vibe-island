import XCTest

@testable import OpenIslandApp

/// AB-327 (draft T09): seed goldens proving the theme-conformance snapshot
/// harness is wired end-to-end and deterministic.
///
/// These are the two pins the ticket calls for — the Classic closed pill in its
/// running state, and the Poured opened session list over the five-fixture
/// baseline set (recorded at both panel widths). Later theme tickets add their
/// own scenarios by calling ``ThemeSnapshotting/assertSnapshot(theme:slot:profile:named:record:file:testName:line:)``.
///
/// XCTest (not swift-testing) on purpose: the fingerprint gate leans on
/// `XCTSkip`, and `swift-snapshot-testing`'s recorder is XCTest-native — both
/// keep the harness robust and CI-green. See the helper's doc and
/// `docs/quality.md`.
@MainActor
final class ThemeSnapshotHarnessTests: XCTestCase {

    /// Classic · closed pill · running · top-bar layout, `×5` right slot.
    func testClassicClosedPillRunning() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: ClassicTheme(),
            slot: .closedPill(mode: .running, rightSlot: .count(5)),
            profile: .topBar,
            named: "classic-closed-pill-running"
        )
    }

    /// Poured · opened session list · five-fixture baseline · notch (540pt).
    func testPouredSessionListBaselineNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: PouredIslandTheme(),
            slot: .sessionList(scenario: .list),
            profile: .notch,
            named: "poured-session-list-baseline-notch"
        )
    }

    /// Poured · opened session list · five-fixture baseline · top-bar (520pt).
    func testPouredSessionListBaselineTopBar() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: PouredIslandTheme(),
            slot: .sessionList(scenario: .list),
            profile: .topBar,
            named: "poured-session-list-baseline-topbar"
        )
    }

    // MARK: - Flight Deck actionable annunciators (AB-334)

    /// Flight Deck · permission command · the red **MASTER WARNING** annunciator
    /// (placard + `PERMISSION REQUIRED` kicker + `HELD` count-up), the
    /// syntax-highlighted command box, and the ⌘Y / ⌘⇧Y / ⌘N ACK switches. The
    /// beacon draws steady-lit here (no `PulseClock` is supplied to the harness).
    /// English only — the harness pins the language (see ``ThemeSnapshotting``).
    func testFlightDeckPermissionMasterWarningNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .permissionCommand),
            profile: .notch,
            named: "flightdeck-permission-master-warning-notch"
        )
    }

    /// Flight Deck · multi-question · the amber **MASTER CAUTION** annunciator
    /// (placard + `QUESTION` kicker + steady amber beacon) wrapping the shared
    /// `StructuredQuestionPromptView` interior. English only.
    func testFlightDeckQuestionMasterCautionNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .questionMulti),
            profile: .notch,
            named: "flightdeck-question-master-caution-notch"
        )
    }

    // MARK: - Flight Deck row register + chips (AB-337 · AC #7)

    /// Flight Deck · duplicate-workspace trio · notch (540pt) **and** top-bar
    /// (520pt). Evidence the `STATUS | SESSION | MODEL | TIME` register survives at
    /// both panel widths with the new folded chips: the two Claude rows carry `⑂`
    /// branch chips (`feat/bridge-auth` / `main`) that double as the T05
    /// disambiguator, one adds `⚙ 3 SUB`, and both narrate a verb-mapped activity
    /// (`Editing …` / `Orchestrating …`), while the Codex row carries no branch
    /// chip (SPEC §6 honesty gate). The name column absorbs truncation; the chips
    /// and fixed lanes hold their columns. The trio carries no actionable HELD
    /// counter, so unlike the `.list` baseline these goldens are time-stable.
    func testFlightDeckDuplicateWorkspaceBranchChipsNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .duplicates),
            profile: .notch,
            named: "flightdeck-duplicates-branch-chips-notch"
        )
    }

    func testFlightDeckDuplicateWorkspaceBranchChipsTopBar() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .duplicates),
            profile: .topBar,
            named: "flightdeck-duplicates-branch-chips-topbar"
        )
    }

    // NOTE (AB-338): the tape gauges' three bands (NOM 34% / CAUT 78% / CRIT 92%)
    // are driven by the `.meters` scenario and were verified by eye against a
    // recorded render, but that scenario is deliberately *not* pinned as a
    // committed golden here: `.meters` reuses the full five-fixture session list,
    // whose live `HELD` count-up and the 5H window's minute-granular `RESET`
    // countdown drift second-to-second — the same temporal instability that keeps
    // the Poured `.list` baselines in the known-drift set. The tape geometry and
    // colour bands are pinned deterministically by `FlightDeckThemeTests`
    // (`tapeGaugePinsThresholdTicksAtSeventyAndNinety`, the cutoff/placard tests).
}
