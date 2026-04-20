import Foundation
import Testing
import SQLite3
@testable import AgentDeckCore

struct WarpSQLiteReaderTests {
    @Test
    func defaultDatabasePathPointsToWarpGroupContainer() {
        let path = WarpSQLiteReader.defaultDatabasePath()
        #expect(path.hasSuffix("/Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite"))
        // Path should be absolute and start with the user's home dir.
        #expect(path.hasPrefix(NSHomeDirectory()))
    }

    @Test
    func readerAcceptsExplicitPathOverride() {
        let custom = "/tmp/warp-fixture.sqlite"
        let reader = WarpSQLiteReader(databasePath: custom)
        #expect(reader.databasePath == custom)
    }

    @Test
    func lookupPaneUUIDReturnsUppercaseHexForClaudeInKnownCwd() throws {
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .threeTabsTwoClaudes)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        let uuid = reader.lookupPaneUUID(forCwd: "/Users/u/agent-deck")
        #expect(uuid == "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB")
    }

    @Test
    func lookupPaneUUIDReturnsNilForCwdWithoutClaudeCommand() throws {
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .threeTabsTwoClaudes)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        #expect(reader.lookupPaneUUID(forCwd: "/nonexistent") == nil)
    }

    @Test
    func lookupPaneUUIDReturnsNilForMissingDatabaseFile() {
        let reader = WarpSQLiteReader(databasePath: "/nonexistent/path/warp.sqlite")
        #expect(reader.lookupPaneUUID(forCwd: "/any") == nil)
    }

    @Test
    func lookupPaneUUIDFallsBackToCommandHistoryWhenTerminalPanesCwdIsStale() throws {
        // Regression for the compound-command flow: user opens a new Warp
        // tab and pastes `mkdir -p /tmp/compound-test && cd /tmp/compound-test
        // && claude` as one line. Warp's shell integration wrote a
        // precmd-<session>-1 block at the very first prompt render (before
        // the compound command ran), linking the shell session to the pane
        // uuid — but terminal_panes.cwd was never updated past the initial
        // /Users/u because the second prompt never rendered. The primary
        // cwd lookup returns nil; the fallback must inspect the commands
        // history, match the `cd /tmp/compound-test` pattern, follow
        // commands.session_id → blocks.precmd-<session_id>-* →
        // pane_leaf_uuid.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .compoundCommandFlow)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        let uuid = reader.lookupPaneUUID(forCwd: "/tmp/compound-test")
        #expect(uuid == "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD")
    }

    @Test
    func lookupPaneUUIDFallbackAcceptsFirmlinkFlippedInput() throws {
        // Hook payloads arrive with /private/tmp/compound-test because
        // Claude Code captures cwd via getcwd() which resolves the
        // firmlink. The original command was typed as `cd
        // /tmp/compound-test`. The fallback must try both forms so the
        // cross-match succeeds.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .compoundCommandFlow)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        let uuid = reader.lookupPaneUUID(forCwd: "/private/tmp/compound-test")
        #expect(uuid == "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD")
    }

    @Test
    func lookupPaneUUIDByShellPIDReturnsUUIDAtTheSameIndexAsShellInSortedSiblings() throws {
        // Core correlation: Warp spawns one shell child per pane in
        // tab creation order, and writes terminal_panes rows in the
        // same order. The Nth child of Warp's terminal-server (by pid
        // ASC) owns the Nth pane (by tab_id ASC). This is the signal
        // that disambiguates sibling tabs sharing the same cwd — a
        // case neither the primary cwd lookup nor the commands-history
        // fallback can resolve.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .threeTabsTwoClaudes)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        let siblings: [pid_t] = [2001, 2002, 2003]

        // Shell 2001 (index 0 after sort) → first pane in tab order =
        // AAAA (giftcard).
        #expect(reader.lookupPaneUUIDByShellPID(2001, siblings: siblings)
            == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        // Shell 2002 (index 1) → second pane = BBBB (agent-deck).
        #expect(reader.lookupPaneUUIDByShellPID(2002, siblings: siblings)
            == "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB")
        // Shell 2003 (index 2) → third pane = CCCC (/tmp).
        #expect(reader.lookupPaneUUIDByShellPID(2003, siblings: siblings)
            == "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC")
    }

    @Test
    func lookupPaneUUIDByShellPIDReturnsNilWhenShellIsNotInSiblings() throws {
        // Guards against a stale shellPID (e.g. the shell exited and a
        // new one took its pid, or the caller passed a pid that is
        // not a direct child of terminal-server). The correct
        // fallback is nil — never guess.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .threeTabsTwoClaudes)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        #expect(reader.lookupPaneUUIDByShellPID(9999, siblings: [2001, 2002, 2003]) == nil)
    }

    @Test
    func lookupPaneUUIDByShellPIDSortsSiblingsBeforeIndexing() throws {
        // Caller may pass siblings in arbitrary order (e.g. the order
        // pgrep prints them in, which is not guaranteed to be sorted).
        // The pid→index correlation depends on ASCENDING sort, so the
        // method must impose the ordering itself.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .threeTabsTwoClaudes)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        // pgrep output order flipped — still must resolve to the
        // right pane.
        #expect(reader.lookupPaneUUIDByShellPID(2001, siblings: [2003, 2001, 2002])
            == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    }

    @Test
    func lookupPaneUUIDByShellPIDReturnsNilWhenPaneIsInBackgroundWindow() throws {
        // Regression for PR #266 Codex review [P1]:
        // `jumpToWarpPane` only cycles tabs within Warp's frontmost
        // window. If the pid-based lookup returns a pane uuid from a
        // background window, the cycle loop can never match it and
        // the jump times out with "could not confirm precision
        // focus" — a consistent failure for every multi-window user.
        //
        // Fixture has two windows: window 1 is active (tabs 1..2),
        // window 2 is background (tabs 3..4). Shell pid 3003 maps to
        // the index 2 pane globally — which is window 2's first tab.
        // The lookup must return nil for that shell even though the
        // pid ↔ index correlation itself is correct, because the
        // resolved pane is not in the active window.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .twoWindowsFourPanes)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        let siblings: [pid_t] = [3001, 3002, 3003, 3004]

        // Shells for panes in window 1 (active) — accepted.
        #expect(reader.lookupPaneUUIDByShellPID(3001, siblings: siblings)
            == "11111111111111111111111111111111")
        #expect(reader.lookupPaneUUIDByShellPID(3002, siblings: siblings)
            == "22222222222222222222222222222222")
        // Shells for panes in window 2 (background) — rejected.
        #expect(reader.lookupPaneUUIDByShellPID(3003, siblings: siblings) == nil)
        #expect(reader.lookupPaneUUIDByShellPID(3004, siblings: siblings) == nil)
    }

    @Test
    func lookupPaneUUIDByShellPIDFallsBackToSmallestWindowWhenActiveWindowIsNull() throws {
        // On real hardware `app.active_window_id` occasionally reads
        // back NULL while Warp is mid-transition. Blindly rejecting
        // would break every lookup — including the common
        // single-window case where every pane is obviously reachable.
        // The fallback uses `MIN(window_id)` from tabs, which equals
        // the only window when there is only one.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .twoWindowsActiveNull)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        // With active_window_id NULL, MIN(window_id) = 1 (the smaller
        // of the two). Window 1's panes are still accepted; window 2's
        // are still rejected — but now by the fallback, not by the
        // primary query.
        let siblings: [pid_t] = [3001, 3002, 3003, 3004]
        #expect(reader.lookupPaneUUIDByShellPID(3001, siblings: siblings)
            == "11111111111111111111111111111111")
        #expect(reader.lookupPaneUUIDByShellPID(3003, siblings: siblings) == nil)
    }

    @Test
    func currentFocusedPaneUUIDReturnsFocusedLeafOfActiveTabWithSplits() throws {
        // Regression for PR #266 Codex review [P1]:
        // The previous `currentFocusedPaneUUID` query offset into
        // `tabs JOIN pane_nodes` using `windows.active_tab_index`, but
        // `active_tab_index` counts tabs while the join returns one
        // row per LEAF pane. The moment any earlier tab has a split,
        // the join row count no longer matches and the offset returns
        // the wrong leaf.
        //
        // Fixture: window 1 has 3 tabs, tab 1 is split into two leaves.
        // active_tab_index = 1 means "the second tab". The focused
        // leaf of tab 2 must come back — NOT tab 1's second split
        // leaf (which is what the old query returned).
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .threeTabsWithFirstSplit)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        #expect(reader.currentFocusedPaneUUID()
            == "66666666666666666666666666666666")
    }

    @Test
    func currentFocusedPaneUUIDRecoversWhenActiveWindowIDIsNull() throws {
        // Real-world regression: on a live Warp database we observed
        // `app.active_window_id` was NULL mid-session (Warp writes
        // it lazily, and between certain transitions it reads back
        // as NULL). The previous nested-subquery form propagated
        // NULL into the OFFSET expression and SQLite aborted with
        // "datatype mismatch" — every call to
        // currentFocusedPaneUUID() returned nil, which broke the
        // precision-jump cycle loop (initialFocused unknown → loop
        // cannot shortcut via fast-path).
        //
        // The fix is to do the active-window resolution in Swift,
        // falling back to MIN(window_id) when `app.active_window_id`
        // is NULL.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .singleWindowActiveNull)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        // Single window with 2 tabs; active_tab_index=1 (second tab).
        // Fallback sets active window = 1, query drills into tab 2
        // and returns its leaf pane.
        #expect(reader.currentFocusedPaneUUID()
            == "22222222222222222222222222222222")
    }

    @Test
    func currentFocusedPaneUUIDPrefersTheFocusedLeafWithinASplitTab() throws {
        // Within a single split tab, `pane_leaves.is_focused` picks
        // the right leaf. Without this filter, every jump into a
        // split tab would land on whichever leaf has the lowest
        // pane_nodes.id, and the user's live terminal would not be
        // the focused target.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .singleTabSplitLeftFocused)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        // The split tab has two leaves; pane_leaves marks the right
        // leaf (uuid BBBB) as focused. The left leaf (AAAA) must NOT
        // be returned even though its pane_nodes.id is smaller.
        #expect(reader.currentFocusedPaneUUID()
            == "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB")
    }

    @Test
    func lookupPaneUUIDByShellPIDReturnsNilWhenIndexIsOutOfRange() throws {
        // Simulates a transient state where siblings list contains
        // more entries than terminal_panes. Could happen if Warp is
        // mid-spawn on a new tab, or if a helper process is counted
        // as a sibling by accident. Better to return nil than guess.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .threeTabsTwoClaudes)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        // Six siblings, but only 3 panes — shell 2006 (index 5) is
        // out of range.
        #expect(reader.lookupPaneUUIDByShellPID(
            2006,
            siblings: [2001, 2002, 2003, 2004, 2005, 2006]
        ) == nil)
    }

    @Test
    func lookupPaneUUIDFallbackFindsPaneEvenWithoutAnyPrecmdBlocks() throws {
        // Discovered against a real Warp SQLite during local E2E
        // testing: Warp does NOT always write `precmd-<session>-1`
        // for a shell session. Specifically, when the user opens a
        // new tab and immediately pastes a compound command like
        // `mkdir -p /tmp/foo && cd /tmp/foo && claude`, claude grabs
        // the TTY before Warp's shell integration has a chance to
        // record even the first prompt. The commands row exists but
        // the blocks table has ZERO precmd entries for that
        // session_id.
        //
        // This breaks any fallback that depends on a precmd block
        // linking session → pane uuid. We instead correlate via
        // `commands.pwd = terminal_panes.cwd` (both reflect the
        // pane's inherited initial cwd), with the NOT EXISTS filter
        // excluding panes already "owned" by a different session via
        // their own precmd blocks. In this fixture there's a sibling
        // pane with blocks tying it to a different session — the
        // orphan pane (no blocks) is the only valid match.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .compoundCommandInSiblingTabFlow)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        // Scenario: two sibling tabs both with inherited cwd
        // /tmp/sibling. Tab X (uuid AAAA) has precmd blocks tied to
        // its own shell session 10001. Tab Y (uuid CCCC) has NO
        // precmd blocks at all — the compound-command-hijacks-TTY
        // flow. The `cd /tmp/target && claude` command for tab Y's
        // session 10002 lives in commands but is not linked to any
        // pane via blocks. The fallback must correlate
        // commands.pwd with terminal_panes.cwd AND exclude tab X
        // (owned by another session) to land on tab Y.
        let uuid = reader.lookupPaneUUID(forCwd: "/tmp/target")
        #expect(uuid == "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC")
    }

    @Test
    func lookupPaneUUIDFallbackSkipsOrphanBlocksFromClosedTabs() throws {
        // When the user closes a Warp tab, Warp prunes the
        // `terminal_panes` row for that tab but leaves the historical
        // `commands` and `blocks` entries in place — this is visible on
        // the real database, which routinely has ~1000+ blocks against
        // a handful of live terminal_panes rows. The fallback must
        // reject matches whose resolved pane_leaf_uuid is no longer
        // present in terminal_panes, otherwise a stale hit would pass
        // a ghost uuid to the precision jump cycle loop, which would
        // spin its entire cap never seeing that uuid in the focused
        // pane read. Graceful degradation is "activate Warp, no
        // precise target" — not "cycle for a second then give up".
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .compoundCommandFlow)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        // The fixture has an orphan command+block pair pointing at pane
        // uuid FFFF... — no matching terminal_panes row.
        let uuid = reader.lookupPaneUUID(forCwd: "/tmp/closed-tab-cwd")
        #expect(uuid == nil)
    }

    @Test
    func lookupPaneUUIDFallbackDoesNotFalsePositiveOnSubstringCwd() throws {
        // The fallback uses LIKE '%cd <target>%' which is vulnerable to
        // substring collision: a query for `/tmp/foo` must not match a
        // command like `cd /tmp/foo-extended`. Pin the boundary behavior.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .compoundCommandFlow)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        // The fixture has a `cd /tmp/compound-test-extended && claude`
        // command pointed at a different pane uuid. A lookup for the
        // shorter path must NOT match it.
        let uuid = reader.lookupPaneUUID(forCwd: "/tmp/compound")
        #expect(uuid == nil)
    }

    @Test
    func lookupPaneUUIDPrimaryStillWinsWhenTerminalPanesCwdIsPopulated() throws {
        // When terminal_panes.cwd IS populated (normal case where the
        // user ran a non-TUI command between `cd` and `claude`), the
        // primary cwd query should still win and we should not fall
        // through to the slower commands-table fallback. This is pinned
        // by reusing the threeTabsTwoClaudes scenario which has populated
        // terminal_panes.cwd for /Users/u/agent-deck.
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .threeTabsTwoClaudes)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        let uuid = reader.lookupPaneUUID(forCwd: "/Users/u/agent-deck")
        #expect(uuid == "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB")
    }

    @Test
    func currentFocusedPaneUUIDReturnsActiveTabsUUID() throws {
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .threeTabsTwoClaudes)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        // Scenario has active_tab_index = 1 which is tab id 2 (agent-deck).
        let reader = WarpSQLiteReader(databasePath: tmp)
        #expect(reader.currentFocusedPaneUUID() == "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB")
    }

    @Test
    func currentFocusedPaneUUIDReturnsNilForMissingDatabase() {
        let reader = WarpSQLiteReader(databasePath: "/nonexistent.sqlite")
        #expect(reader.currentFocusedPaneUUID() == nil)
    }

    @Test
    func tabCountInActiveWindowReturnsCount() throws {
        let tmp = NSTemporaryDirectory() + "warp-fixture-\(UUID().uuidString).sqlite"
        try WarpSQLiteFixture.write(to: tmp, scenario: .threeTabsTwoClaudes)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let reader = WarpSQLiteReader(databasePath: tmp)
        #expect(reader.tabCountInActiveWindow() == 3)
    }

    @Test
    func tabCountInActiveWindowReturnsZeroForMissingDatabase() {
        let reader = WarpSQLiteReader(databasePath: "/nonexistent.sqlite")
        #expect(reader.tabCountInActiveWindow() == 0)
    }
}

// MARK: - Fixture

/// Builds a minimal synthetic warp.sqlite with the exact schema columns the
/// reader queries. Only the queried subset is present; other tables and
/// constraints are omitted intentionally to keep the fixture short.
enum WarpSQLiteFixture {
    static func write(to path: String, scenario: Scenario) throws {
        // Open (create) the file
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw NSError(domain: "WarpSQLiteFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "open failed"])
        }
        defer { sqlite3_close(db) }

        let schema = """
        CREATE TABLE app (id INTEGER PRIMARY KEY, active_window_id INTEGER);
        CREATE TABLE windows (id INTEGER PRIMARY KEY, active_tab_index INTEGER NOT NULL);
        CREATE TABLE tabs (id INTEGER PRIMARY KEY, window_id INTEGER NOT NULL);
        CREATE TABLE pane_nodes (id INTEGER PRIMARY KEY, tab_id INTEGER NOT NULL, is_leaf BOOLEAN NOT NULL);
        CREATE TABLE terminal_panes (id INTEGER PRIMARY KEY, uuid BLOB NOT NULL, cwd TEXT);
        CREATE TABLE commands (id INTEGER PRIMARY KEY, session_id INTEGER, command TEXT, pwd TEXT);
        CREATE TABLE blocks (id INTEGER PRIMARY KEY, pane_leaf_uuid BLOB, block_id TEXT);
        CREATE TABLE pane_leaves (pane_node_id INTEGER PRIMARY KEY, is_focused BOOLEAN NOT NULL DEFAULT 0);
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "WarpSQLiteFixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "schema failed: \(String(cString: sqlite3_errmsg(db)))"])
        }

        for row in scenario.rows {
            guard sqlite3_exec(db, row, nil, nil, nil) == SQLITE_OK else {
                throw NSError(domain: "WarpSQLiteFixture", code: 3, userInfo: [NSLocalizedDescriptionKey: "insert failed: \(String(cString: sqlite3_errmsg(db)))"])
            }
        }
    }

    struct Scenario {
        var rows: [String]

        /// Models the "compound command" flow where Warp's shell
        /// integration never updates `terminal_panes.cwd` past the
        /// initial shell cwd because the user ran `cd <target> && claude`
        /// as a single pasted line and claude's TUI took over before a
        /// second prompt could render.
        ///
        /// Pane D had one prompt render at shell startup (cwd /Users/u),
        /// wrote precmd-9001-1, then executed the compound command — so
        /// terminal_panes.cwd stays /Users/u but the commands table
        /// records the full text with `cd /tmp/compound-test`.
        ///
        /// Pane E is a separate shell that ran a NEAR-miss command
        /// (`cd /tmp/compound-test-extended`) so we can pin that the
        /// fallback doesn't false-positive on substring collisions.
        static let compoundCommandFlow = Scenario(rows: [
            "INSERT INTO app (id, active_window_id) VALUES (1, 1);",
            "INSERT INTO windows (id, active_tab_index) VALUES (1, 0);",
            "INSERT INTO tabs (id, window_id) VALUES (1, 1), (2, 1);",
            "INSERT INTO pane_nodes (id, tab_id, is_leaf) VALUES (1, 1, 1), (2, 2, 1);",
            "INSERT INTO terminal_panes (id, uuid, cwd) VALUES " +
                "(1, x'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD', '/Users/u')," +
                "(2, x'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE', '/Users/u');",
            "INSERT INTO commands (id, session_id, command, pwd) VALUES " +
                "(300, 9001, 'mkdir -p /tmp/compound-test && cd /tmp/compound-test && claude', '/Users/u')," +
                "(301, 9002, 'mkdir -p /tmp/compound-test-extended && cd /tmp/compound-test-extended && claude', '/Users/u')," +
                // Orphan row: represents a shell session whose tab was
                // closed. commands + blocks linger but terminal_panes is
                // pruned. The fallback must not return FFFF... because
                // no such pane exists anymore.
                "(302, 9003, 'cd /tmp/closed-tab-cwd && claude', '/Users/u');",
            "INSERT INTO blocks (id, pane_leaf_uuid, block_id) VALUES " +
                "(1, x'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD', 'precmd-9001-1')," +
                "(2, x'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE', 'precmd-9002-1')," +
                "(3, x'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', 'precmd-9003-1');",
        ])

        /// Models the "compound command in a sibling tab" flow where
        /// Warp did not write ANY precmd block for the new shell. The
        /// user has two tabs, both with inherited initial cwd
        /// /tmp/sibling:
        ///
        /// - Tab A (pane uuid AAAA): an older shell session 10001
        ///   that ran a `pwd` (or similar non-TUI command) before
        ///   starting claude, so Warp did write precmd-10001-1 and
        ///   precmd-10001-2 blocks tying the pane to session 10001.
        ///   This is the "test-b" equivalent — the already-running
        ///   tab the user is NOT targeting.
        ///
        /// - Tab C (pane uuid CCCC): a newer shell session 10002
        ///   that was opened as a new tab (inheriting cwd from Tab
        ///   A's focus) and IMMEDIATELY pasted a compound command.
        ///   claude took the TTY before Warp's shell integration
        ///   could render a first prompt, so there are ZERO precmd
        ///   blocks for session 10002. This is the "test-c"
        ///   equivalent — the target the user IS trying to jump to.
        ///
        /// The fallback must correlate:
        ///   commands.pwd (/tmp/sibling) → terminal_panes.cwd (/tmp/sibling)
        /// and exclude Tab A via the NOT EXISTS foreign-block check,
        /// leaving Tab C as the only valid match even though Tab C
        /// has zero blocks of its own.
        static let compoundCommandInSiblingTabFlow = Scenario(rows: [
            "INSERT INTO app (id, active_window_id) VALUES (1, 1);",
            "INSERT INTO windows (id, active_tab_index) VALUES (1, 0);",
            "INSERT INTO tabs (id, window_id) VALUES (1, 1), (2, 1);",
            "INSERT INTO pane_nodes (id, tab_id, is_leaf) VALUES (1, 1, 1), (2, 2, 1);",
            // Both panes inherited the same initial cwd because the
            // new tab opened as a sibling to the first.
            "INSERT INTO terminal_panes (id, uuid, cwd) VALUES " +
                "(1, x'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', '/tmp/sibling')," +
                "(2, x'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', '/tmp/sibling');",
            // Both shell sessions ran commands with pwd=/tmp/sibling.
            // Session 10001 has non-compound command history (a plain
            // `pwd` before claude). Session 10002 has ONLY the
            // compound cd+claude.
            "INSERT INTO commands (id, session_id, command, pwd) VALUES " +
                "(400, 10001, 'pwd', '/tmp/sibling')," +
                "(401, 10001, 'claude', '/tmp/sibling')," +
                "(402, 10002, 'mkdir -p /tmp/target && cd /tmp/target && claude', '/tmp/sibling');",
            // Session 10001 has two precmd blocks (one at first
            // prompt, one after `pwd` completed). Session 10002 has
            // no blocks at all — the compound command ran before the
            // first prompt.
            "INSERT INTO blocks (id, pane_leaf_uuid, block_id) VALUES " +
                "(1, x'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'precmd-10001-1')," +
                "(2, x'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'precmd-10001-2');",
        ])

        /// Models a user with two Warp windows open — window 1 is
        /// active (`app.active_window_id = 1`), each window has two
        /// tabs, one leaf pane per tab. The pid-based lookup must
        /// reject panes in window 2 even though the pid index maps to
        /// them correctly, because `jumpToWarpPane` only cycles tabs
        /// in the frontmost window and would otherwise chase an
        /// unreachable uuid.
        static let twoWindowsFourPanes = Scenario(rows: [
            "INSERT INTO app (id, active_window_id) VALUES (1, 1);",
            "INSERT INTO windows (id, active_tab_index) VALUES (1, 0), (2, 0);",
            "INSERT INTO tabs (id, window_id) VALUES " +
                "(1, 1), (2, 1)," +   // window 1 tabs (active)
                "(3, 2), (4, 2);",    // window 2 tabs (background)
            "INSERT INTO pane_nodes (id, tab_id, is_leaf) VALUES " +
                "(1, 1, 1), (2, 2, 1), (3, 3, 1), (4, 4, 1);",
            "INSERT INTO terminal_panes (id, uuid, cwd) VALUES " +
                "(1, x'11111111111111111111111111111111', '/window-1-tab-1')," +
                "(2, x'22222222222222222222222222222222', '/window-1-tab-2')," +
                "(3, x'33333333333333333333333333333333', '/window-2-tab-1')," +
                "(4, x'44444444444444444444444444444444', '/window-2-tab-2');",
        ])

        /// Same topology as `twoWindowsFourPanes` but with
        /// `app.active_window_id = NULL`. Exercises the fallback to
        /// `MIN(window_id)` that keeps single-window lookups working
        /// even when Warp hasn't populated the pointer yet.
        static let twoWindowsActiveNull = Scenario(rows: [
            "INSERT INTO app (id, active_window_id) VALUES (1, NULL);",
            "INSERT INTO windows (id, active_tab_index) VALUES (1, 0), (2, 0);",
            "INSERT INTO tabs (id, window_id) VALUES " +
                "(1, 1), (2, 1)," +
                "(3, 2), (4, 2);",
            "INSERT INTO pane_nodes (id, tab_id, is_leaf) VALUES " +
                "(1, 1, 1), (2, 2, 1), (3, 3, 1), (4, 4, 1);",
            "INSERT INTO terminal_panes (id, uuid, cwd) VALUES " +
                "(1, x'11111111111111111111111111111111', '/window-1-tab-1')," +
                "(2, x'22222222222222222222222222222222', '/window-1-tab-2')," +
                "(3, x'33333333333333333333333333333333', '/window-2-tab-1')," +
                "(4, x'44444444444444444444444444444444', '/window-2-tab-2');",
        ])

        /// Pins `currentFocusedPaneUUID` handling of a split tab
        /// earlier in the tab order. Window 1 has three tabs; tab 1
        /// is split into TWO leaf panes (`pane_nodes` ids 10 and 11,
        /// both `is_leaf = 1`, tab_id = 1), tab 2 and tab 3 each have
        /// a single leaf (ids 20 and 30). `active_tab_index = 1`
        /// means "the second tab" — which is tab_id 2, pane 20.
        ///
        /// The OLD query `LIMIT 1 OFFSET 1` against `tabs JOIN
        /// pane_nodes` would skip past pane 10 and land on pane 11
        /// (tab 1's second split leaf) — wrong. The new CTE-based
        /// query selects tab 2 by offset and then drills into its
        /// leaves.
        static let threeTabsWithFirstSplit = Scenario(rows: [
            "INSERT INTO app (id, active_window_id) VALUES (1, 1);",
            "INSERT INTO windows (id, active_tab_index) VALUES (1, 1);",
            "INSERT INTO tabs (id, window_id) VALUES (1, 1), (2, 1), (3, 1);",
            // Tab 1: SPLIT into two leaves. Tab 2: single leaf. Tab 3: single leaf.
            "INSERT INTO pane_nodes (id, tab_id, is_leaf) VALUES " +
                "(10, 1, 1), (11, 1, 1), (20, 2, 1), (30, 3, 1);",
            "INSERT INTO terminal_panes (id, uuid, cwd) VALUES " +
                "(10, x'44444444444444444444444444444444', '/tab-1-left')," +
                "(11, x'55555555555555555555555555555555', '/tab-1-right')," +
                "(20, x'66666666666666666666666666666666', '/tab-2')," +
                "(30, x'77777777777777777777777777777777', '/tab-3');",
            // pane_leaves — none focused explicitly; the single-leaf
            // tabs (20, 30) have no split so focus is trivially the
            // only leaf.
            "INSERT INTO pane_leaves (pane_node_id, is_focused) VALUES " +
                "(10, 0), (11, 0), (20, 1), (30, 0);",
        ])

        /// Single-window database with `app.active_window_id` NULL,
        /// two tabs, `windows.active_tab_index=1` (second tab). The
        /// fallback to `MIN(window_id)` must pick window 1 and the
        /// query must drill into tab 2's leaf.
        static let singleWindowActiveNull = Scenario(rows: [
            "INSERT INTO app (id, active_window_id) VALUES (1, NULL);",
            "INSERT INTO windows (id, active_tab_index) VALUES (1, 1);",
            "INSERT INTO tabs (id, window_id) VALUES (1, 1), (2, 1);",
            "INSERT INTO pane_nodes (id, tab_id, is_leaf) VALUES (1, 1, 1), (2, 2, 1);",
            "INSERT INTO terminal_panes (id, uuid, cwd) VALUES " +
                "(1, x'11111111111111111111111111111111', '/tab-1')," +
                "(2, x'22222222222222222222222222222222', '/tab-2');",
        ])

        /// Pins the "prefer the focused leaf within a split tab"
        /// behavior. Single tab with two leaves; `pane_leaves` marks
        /// the right leaf (pane_nodes 11 → pane uuid BBBB) as focused.
        /// The lookup must return BBBB, NOT AAAA, even though AAAA has
        /// the smaller pane_nodes.id and would win a naive ordering.
        static let singleTabSplitLeftFocused = Scenario(rows: [
            "INSERT INTO app (id, active_window_id) VALUES (1, 1);",
            "INSERT INTO windows (id, active_tab_index) VALUES (1, 0);",
            "INSERT INTO tabs (id, window_id) VALUES (1, 1);",
            "INSERT INTO pane_nodes (id, tab_id, is_leaf) VALUES (10, 1, 1), (11, 1, 1);",
            "INSERT INTO terminal_panes (id, uuid, cwd) VALUES " +
                "(10, x'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', '/left')," +
                "(11, x'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', '/right');",
            "INSERT INTO pane_leaves (pane_node_id, is_focused) VALUES (10, 0), (11, 1);",
        ])

        /// Three tabs in one window. Tab 1 cwd=giftcard (pane uuid AAAA...),
        /// tab 2 cwd=agent-deck (pane uuid BBBB...), tab 3 cwd=/tmp (pane uuid CCCC...).
        /// Claude was launched in giftcard from Warp shell session 1001 and in agent-deck from 1002.
        static let threeTabsTwoClaudes = Scenario(rows: [
            "INSERT INTO app (id, active_window_id) VALUES (1, 1);",
            "INSERT INTO windows (id, active_tab_index) VALUES (1, 1);", // tab index 1 = second tab (0-based)
            "INSERT INTO tabs (id, window_id) VALUES (1, 1), (2, 1), (3, 1);",
            "INSERT INTO pane_nodes (id, tab_id, is_leaf) VALUES (1, 1, 1), (2, 2, 1), (3, 3, 1);",
            "INSERT INTO terminal_panes (id, uuid, cwd) VALUES " +
                "(1, x'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', '/Users/u/giftcard')," +
                "(2, x'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', '/Users/u/agent-deck')," +
                "(3, x'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', '/tmp');",
            "INSERT INTO commands (id, session_id, command, pwd) VALUES " +
                "(100, 1001, 'cd giftcard', '/Users/u')," +
                "(101, 1001, 'claude --dangerously-skip-permissions', '/Users/u/giftcard')," +
                "(200, 1002, 'claude --dangerously-skip-permissions', '/Users/u/agent-deck');",
            "INSERT INTO blocks (id, pane_leaf_uuid, block_id) VALUES " +
                "(1, x'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'precmd-1001-1')," +
                "(2, x'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'precmd-1001-2')," +
                "(3, x'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', 'precmd-1002-1');",
        ])
    }
}
