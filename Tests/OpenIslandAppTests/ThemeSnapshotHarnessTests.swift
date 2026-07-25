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
}
