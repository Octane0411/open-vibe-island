import Foundation
import SQLite3

/// Read-only access to Warp's live SQLite state for precision jump targeting.
///
/// This depends on Warp's internal schema and is not a supported Warp API.
/// All query failures degrade silently: callers receive nil/0 and should
/// fall back to whatever non-Warp behavior they had.
public struct WarpSQLiteReader: Sendable {
    public let databasePath: String

    public init(databasePath: String = WarpSQLiteReader.defaultDatabasePath()) {
        self.databasePath = databasePath
    }

    /// Returns the standard on-disk location of Warp's SQLite database for the
    /// stable release channel. Warp stores state inside its Group Container,
    /// not the per-app Application Support, because Warp is sandboxed.
    public static func defaultDatabasePath() -> String {
        NSHomeDirectory()
            + "/Library/Group Containers/2BBY89MBSN.dev.warp"
            + "/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite"
    }

    /// Resolves the Warp pane UUID hosting a Claude/Codex agent running in
    /// `cwd`. Returns uppercase hex string (32 chars, no separators), or nil
    /// on any error / when no pane can be located.
    ///
    /// Tries two lookup strategies in order:
    ///
    /// **Primary — `terminal_panes.cwd` direct match.** Queries Warp's
    /// per-pane cwd column. Fast and precise when Warp's shell integration
    /// had a chance to update the column, which happens whenever the shell
    /// renders a prompt with a cwd different from the pane's initial
    /// launch cwd. Both firmlink forms of the input cwd are tried because
    /// Claude Code captures cwd via `getcwd()` (resolved:
    /// `/private/tmp/foo`) while Warp usually stores the unresolved form
    /// the shell sent over OSC (`/tmp/foo`).
    ///
    /// **Fallback — `commands → blocks` cross-reference.** If the primary
    /// miss, inspect the command history for a row whose text contains
    /// `cd <target>` (both firmlink forms, bounded so `/tmp/foo` doesn't
    /// false-positive-match `/tmp/foo-extended`), take that row's
    /// `session_id`, and join to a `precmd-<session_id>-*` block to get
    /// the pane uuid. Covers the common "compound command" flow where a
    /// user pastes `mkdir -p /tmp/foo && cd /tmp/foo && claude` as a
    /// single line: Warp renders the first prompt (writing
    /// `precmd-<session>-1` and linking the shell session to the pane
    /// uuid), then claude's TUI takes over before a second prompt can
    /// fire, so terminal_panes.cwd never updates past the initial
    /// `/Users/u`. The commands table still has the full pasted text, so
    /// matching on `cd /tmp/foo` recovers the mapping.
    ///
    /// Known limitations:
    /// - Substring collision within the fallback is mitigated by
    ///   bounding the match on a shell separator (space / `;` / `&` /
    ///   `|`) or end-of-command. Exotic separators (newline-only,
    ///   trailing-slash path normalization) are not handled.
    /// - If two Warp tabs share the same cwd in either table, the most
    ///   recently created row (`id DESC`) wins. Disambiguating
    ///   same-cwd panes from SQLite alone is not possible because Warp
    ///   does not expose a per-pane PID or TTY.
    /// - Paths containing SQLite GLOB meta-characters (`*`, `?`, `[`,
    ///   `]`) will fall through the fallback silently. These are
    ///   vanishingly rare in practice; the primary lookup still handles
    ///   them correctly.
    public func lookupPaneUUID(forCwd cwd: String) -> String? {
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }

        if let uuid = lookupViaTerminalPanesCwd(db: db, cwd: cwd) {
            return uuid
        }
        if let uuid = lookupViaCommandsHistory(db: db, cwd: cwd) {
            return uuid
        }
        return nil
    }

    private func lookupViaTerminalPanesCwd(db: OpaquePointer, cwd: String) -> String? {
        let candidates = Self.cwdLookupCandidates(for: cwd)

        let sql = """
        SELECT hex(uuid)
        FROM terminal_panes
        WHERE cwd IN (\(Array(repeating: "?", count: candidates.count).joined(separator: ", ")))
        ORDER BY id DESC
        LIMIT 1;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        var heldCStrings: [UnsafeMutablePointer<CChar>?] = []
        defer { heldCStrings.forEach { free($0) } }

        for (index, candidate) in candidates.enumerated() {
            let cString = candidate.withCString { strdup($0) }
            heldCStrings.append(cString)
            sqlite3_bind_text(stmt, Int32(index + 1), cString, -1, nil)
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cString)
    }

    private func lookupViaCommandsHistory(db: OpaquePointer, cwd: String) -> String? {
        let candidates = Self.cwdLookupCandidates(for: cwd)

        // Skip the fallback if any candidate contains SQLite GLOB meta
        // characters — escaping them safely is more effort than this
        // fallback is worth for paths that are effectively never used.
        if candidates.contains(where: { path in path.contains(where: { "*?[".contains($0) }) }) {
            return nil
        }

        // Two GLOB patterns per candidate:
        //   1. `*cd <path>[ ;&|]*` — `cd <path>` followed by a shell
        //      separator (standard case, e.g. `cd /tmp/foo && claude`).
        //   2. `*cd <path>`       — `cd <path>` at the very end of the
        //      command string.
        // The `[ ;&|]` character class is what prevents substring
        // collision: a lookup for `/tmp/foo` will not match a command
        // containing `cd /tmp/foo-extended` because the character after
        // `foo` is `-`, not one of the separators.
        var globPatterns: [String] = []
        for candidate in candidates {
            globPatterns.append("*cd \(candidate)[ ;&|]*")
            globPatterns.append("*cd \(candidate)")
        }

        let whereClause = Array(repeating: "c.command GLOB ?", count: globPatterns.count)
            .joined(separator: " OR ")

        // The join chain matches a Warp pane via command-history
        // correlation, structured to handle the case where the shell
        // never rendered a prompt before claude took over the TTY and
        // so Warp never wrote ANY `precmd-<session>-*` block for the
        // shell. Block-based linking alone fails in that case. The
        // trick is to correlate via `commands.pwd` (the shell's cwd at
        // command execution time, which for a compound command in a
        // freshly opened tab equals the pane's inherited initial cwd)
        // to `terminal_panes.cwd` (which stays at the inherited value
        // when the shell never OSC'd a new cwd).
        //
        // Three ordering signals disambiguate when multiple panes
        // share the same initial cwd (common: Warp opens new tabs
        // inheriting cwd from the previously-focused tab, so two sibling
        // tabs both started at /tmp/foo will both show cwd='/tmp/foo'
        // in terminal_panes):
        //
        // 1. `has_matching_block DESC` — prefer a pane that is
        //    already linked via a precmd block to the command's own
        //    shell session. When a block exists, the pane assignment
        //    is definitive and we should always take it.
        //
        // 2. `NOT EXISTS (... foreign block ...)` in WHERE — exclude
        //    panes that are already "owned" by a different shell
        //    session via a precmd block. Without this filter, a query
        //    for test-c would return the test-b pane (because they
        //    share the same stale cwd in terminal_panes, and test-b's
        //    pane is higher-id). test-b is visibly wrong — it has a
        //    block linked to test-b's session_id, not test-c's.
        //
        // 3. `c.id DESC, tp.id DESC` — most recent command, most
        //    recent pane wins. This is the tiebreaker when neither
        //    the positive block-link nor the negative foreign-block
        //    exclusion disambiguates.
        //
        // The outer JOIN on `terminal_panes` is also load-bearing:
        // Warp prunes terminal_panes rows when the user closes a tab
        // but leaves `commands` and `blocks` history in place. On a
        // real database the ratio is routinely ~1000 orphan blocks
        // per live pane. Joining against terminal_panes keeps the
        // result constrained to currently-live panes so a miss
        // degrades cleanly to "no precise pane mapping available"
        // rather than chasing ghost uuids.
        let sql = """
        SELECT hex(tp.uuid)
        FROM commands c
        JOIN terminal_panes tp ON tp.cwd = c.pwd
        LEFT JOIN blocks b_match
            ON b_match.pane_leaf_uuid = tp.uuid
            AND b_match.block_id GLOB 'precmd-' || c.session_id || '-*'
        WHERE (\(whereClause))
          AND NOT EXISTS (
              SELECT 1 FROM blocks b_foreign
              WHERE b_foreign.pane_leaf_uuid = tp.uuid
                AND b_foreign.block_id GLOB 'precmd-*-*'
                AND b_foreign.block_id NOT GLOB 'precmd-' || c.session_id || '-*'
          )
        ORDER BY (b_match.id IS NOT NULL) DESC,
                 c.id DESC,
                 tp.id DESC
        LIMIT 1;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        var heldCStrings: [UnsafeMutablePointer<CChar>?] = []
        defer { heldCStrings.forEach { free($0) } }

        for (index, pattern) in globPatterns.enumerated() {
            let cString = pattern.withCString { strdup($0) }
            heldCStrings.append(cString)
            sqlite3_bind_text(stmt, Int32(index + 1), cString, -1, nil)
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cString)
    }

    /// Generates the set of equivalent cwd strings to query Warp's SQLite
    /// against. macOS firmlinks `/tmp` → `/private/tmp` (and `/var` →
    /// `/private/var`), so a single conceptual directory has two valid
    /// string forms. Always returns the input as-is plus, when applicable,
    /// the firmlink-flipped sibling.
    static func cwdLookupCandidates(for cwd: String) -> [String] {
        var result: [String] = [cwd]
        if cwd.hasPrefix("/private/tmp/") || cwd == "/private/tmp" {
            result.append(String(cwd.dropFirst("/private".count)))
        } else if cwd.hasPrefix("/tmp/") || cwd == "/tmp" {
            result.append("/private" + cwd)
        } else if cwd.hasPrefix("/private/var/") || cwd == "/private/var" {
            result.append(String(cwd.dropFirst("/private".count)))
        } else if cwd.hasPrefix("/var/") || cwd == "/var" {
            result.append("/private" + cwd)
        }
        return result
    }

    /// Resolves the Warp pane UUID for a shell process by its position in
    /// Warp's `terminal-server` child list.
    ///
    /// Warp spawns one shell process per pane as a direct child of its
    /// `terminal-server` helper. Because both the shell children and the
    /// `terminal_panes` rows are created in the same order (one pair per
    /// "open new tab" action), the shell's index among terminal-server's
    /// children equals the pane's index in `terminal_panes` joined to
    /// tabs ordered by `tab_id ASC`. That correlation is enough to pick
    /// the right pane even when two panes share the same `cwd` — which
    /// is exactly where the cwd-based lookups fail.
    ///
    /// This method is deliberately *pure*: it accepts the siblings list
    /// rather than enumerating it itself so tests can pin the index
    /// logic without spawning subprocesses. The production wrapper
    /// `lookupPaneUUIDByShellPID(_:terminalServerPID:)` handles the
    /// enumeration via `pgrep`.
    ///
    /// Returns nil when `shellPID` is not in `siblings`, when the index
    /// is out of range relative to the tab list, when the resolved
    /// pane lives in a background Warp window (unreachable by the
    /// cycle loop in `jumpToWarpPane`), or on any SQLite error.
    public func lookupPaneUUIDByShellPID(
        _ shellPID: pid_t,
        siblings: [pid_t]
    ) -> String? {
        let sorted = siblings.sorted()
        guard let index = sorted.firstIndex(of: shellPID) else {
            return nil
        }

        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }

        // Enumerate every live leaf pane ACROSS ALL WINDOWS in tab_id
        // order. Filtering by window in SQL would break the index
        // arithmetic — pid correlation is built on the global creation
        // sequence of shell children, and the shell ordering matches
        // the global tab_id ordering, not a per-window ordering.
        // Instead we pull the row's `window_id` alongside the uuid and
        // reject it in Swift when the pane lives in a background
        // window, because `jumpToWarpPane` only cycles tabs in the
        // frontmost window — a pane uuid from any other window can
        // never match `currentFocusedPaneUUID()` and the cycle loop
        // would spin its entire cap before timing out.
        let sql = """
        SELECT hex(tp.uuid), t.window_id
        FROM tabs t
        JOIN pane_nodes pn ON pn.tab_id = t.id AND pn.is_leaf = 1
        JOIN terminal_panes tp ON tp.id = pn.id
        ORDER BY t.id ASC
        LIMIT 1 OFFSET ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(index))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
        let uuid = String(cString: cString)
        let paneWindowID = sqlite3_column_int64(stmt, 1)

        // Reject panes in non-active windows. When the active window
        // cannot be determined at all (Warp leaves `app.active_window_id`
        // NULL transiently and the tabs table is empty for some reason),
        // we accept any window as a best-effort — declining would
        // break the single-window case where the row is obviously
        // reachable.
        if let activeWindowID = fetchActiveWindowID(db: db), activeWindowID != paneWindowID {
            return nil
        }
        return uuid
    }

    /// Reads Warp's current "active window" pointer.
    ///
    /// Primary source: `app.active_window_id`. Warp sometimes leaves
    /// this NULL during transient states; in that case we fall back to
    /// `MIN(window_id)` from tabs, which equals the only window for
    /// the overwhelmingly common single-window case. Returns nil only
    /// when both the primary and fallback queries give nothing
    /// actionable — at which point callers should skip the
    /// active-window filter rather than reject all panes.
    private func fetchActiveWindowID(db: OpaquePointer) -> Int64? {
        if let value = fetchSingleInt64(db: db, sql: "SELECT active_window_id FROM app LIMIT 1") {
            return value
        }
        return fetchSingleInt64(db: db, sql: "SELECT MIN(window_id) FROM tabs")
    }

    /// Executes a SQL query that is expected to return a single integer
    /// column and row. Returns nil when the query yields no rows or
    /// the column is NULL — the caller decides how to interpret the
    /// absence.
    private func fetchSingleInt64(db: OpaquePointer, sql: String) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    /// Production-facing overload that enumerates terminal-server's
    /// children via `pgrep -P <terminalServerPID>` and then delegates
    /// to the pure `lookupPaneUUIDByShellPID(_:siblings:)`.
    ///
    /// Separated from the pure variant so tests can pin the pid→index
    /// correlation logic without spawning subprocesses.
    public func lookupPaneUUIDByShellPID(
        _ shellPID: pid_t,
        terminalServerPID: pid_t
    ) -> String? {
        guard let siblings = Self.enumerateChildPIDs(of: terminalServerPID) else {
            return nil
        }
        return lookupPaneUUIDByShellPID(shellPID, siblings: siblings)
    }

    /// Spawns `/usr/bin/pgrep -P <pid>` to enumerate direct children of
    /// the given pid. Returns nil on any error. Returns an empty array
    /// when pgrep exits with code 1 (no children found) — a valid
    /// result, not an error.
    static func enumerateChildPIDs(of pid: pid_t) -> [pid_t]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-P", "\(pid)"]
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        // pgrep: 0 = matches found, 1 = no matches (not an error),
        // 2+    = genuine error.
        guard task.terminationStatus == 0 || task.terminationStatus == 1 else {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output
            .split(separator: "\n")
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Resolves the pane UUID of the currently focused pane in the currently
    /// active Warp window. This is what drives the polling loop during a
    /// precision jump.
    ///
    /// Returns uppercase hex string suitable for direct comparison to the
    /// output of `lookupPaneUUID`. Returns nil on any error or if there is
    /// no active window.
    public func currentFocusedPaneUUID() -> String? {
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }

        // Resolution happens in three explicit SQL steps rather than a
        // single nested query. The motivation is that on real hardware
        // `app.active_window_id` is frequently NULL during transient
        // Warp states, and the old nested form `LIMIT 1 OFFSET (SELECT
        // ... WHERE id = (SELECT active_window_id ...))` propagates
        // that NULL into the OFFSET expression, which raises
        // "datatype mismatch" and aborts the whole query. Doing the
        // lookups in separate statements lets us fall back (via
        // `fetchActiveWindowID`) to `MIN(window_id)` when the primary
        // pointer is missing, which keeps the common single-window
        // case working.
        guard let activeWindowID = fetchActiveWindowID(db: db) else {
            return nil
        }
        let activeTabIndex = fetchActiveTabIndex(db: db, windowID: activeWindowID) ?? 0
        guard let activeTabID = fetchTabIDAtOffset(
            db: db,
            windowID: activeWindowID,
            offset: activeTabIndex
        ) else {
            return nil
        }

        // Fetch the active tab's focused leaf. `pane_leaves.is_focused`
        // is a best-effort preference — empirical observation on real
        // Warp databases shows it is often `1` for every leaf
        // (unconditionally set on creation, never cleared), so the
        // ordering effectively decays into the `pn.id ASC` tiebreaker
        // for split tabs. That is an acceptable graceful degradation:
        // single-leaf tabs still return the correct uuid, and split
        // tabs return a deterministic-but-possibly-not-focused leaf
        // that users can adjust manually. The important correctness
        // property is that we no longer offset into the `tabs JOIN
        // pane_nodes` row set by `active_tab_index`, so prior-split
        // tabs can no longer shift subsequent tabs' results.
        let sql = """
        SELECT hex(tp.uuid)
        FROM pane_nodes pn
        LEFT JOIN pane_leaves pl ON pl.pane_node_id = pn.id
        JOIN terminal_panes tp ON tp.id = pn.id
        WHERE pn.tab_id = ?
          AND pn.is_leaf = 1
        ORDER BY COALESCE(pl.is_focused, 0) DESC, pn.id ASC
        LIMIT 1;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, activeTabID)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cString)
    }

    /// Reads `windows.active_tab_index` for the given window, or nil
    /// when the row is missing or the column is NULL.
    private func fetchActiveTabIndex(db: OpaquePointer, windowID: Int64) -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT active_tab_index FROM windows WHERE id = ?",
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, windowID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// Selects the tab_id at `offset` within the given window's tab
    /// list, ordered by `tabs.id ASC` (matches Warp's left-to-right
    /// tab strip layout).
    private func fetchTabIDAtOffset(
        db: OpaquePointer,
        windowID: Int64,
        offset: Int
    ) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT id FROM tabs WHERE window_id = ? ORDER BY id ASC LIMIT 1 OFFSET ?",
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, windowID)
        sqlite3_bind_int64(stmt, 2, Int64(offset))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    /// Returns the number of tabs in the currently active Warp window.
    /// Used as the upper bound for the keystroke cycle retry loop during
    /// precision jump. Returns 0 on any error.
    public func tabCountInActiveWindow() -> Int {
        guard let db = openReadOnly() else { return 0 }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT COUNT(*) FROM tabs
        WHERE window_id = (SELECT active_window_id FROM app LIMIT 1);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    // MARK: - Internal

    private func openReadOnly() -> OpaquePointer? {
        var db: OpaquePointer?
        let flags: Int32 = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databasePath, &db, flags, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        // Set a short busy timeout so we don't hang if Warp is mid-transaction.
        sqlite3_busy_timeout(db, 60) // ms
        return db
    }
}
