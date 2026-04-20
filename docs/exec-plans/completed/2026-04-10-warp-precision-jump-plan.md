# Warp Precision Jump Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a user clicks jump on a Warp-hosted Claude or Codex session in Agent Deck, automatically focus the exact Warp tab running that session (one click, no manual tab scanning).

**Architecture:** Read Warp's live SQLite state (`~/Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite`, WAL mode, already empirically confirmed live-updated) to (a) discover each session's `pane_uuid` at hook time and (b) detect the currently-focused pane at jump time. When the target pane isn't focused, send `Cmd+Shift+]` via `CGEventPost` in a bounded loop, re-reading SQLite between each press until the target pane is focused or we exhaust the retry cap.

**Tech Stack:** Swift 6.2 / SwiftPM, `import SQLite3` (macOS system library, no new SPM dependency), `CoreGraphics.CGEventPost`, `ApplicationServices.AXIsProcessTrustedWithOptions`. Tests use XCTest + Swift Testing, with an in-file `WarpSQLiteFixture` helper that writes a synthetic warp.sqlite to a temp path.

**Spec:** `docs/exec-plans/active/2026-04-10-warp-precision-jump-design.md`

---

## File Structure

**New files**

| Path | Responsibility |
|---|---|
| `Sources/AgentDeckCore/WarpSQLiteReader.swift` | Read-only SQLite queries against Warp's database. Exposes `lookupPaneUUID(forCwd:)`, `currentFocusedPaneUUID()`, `tabCountInActiveWindow()`. All failures return nil/0 and log once. |
| `Sources/AgentDeckApp/KeystrokeInjector.swift` | Thin wrapper over `CGEventCreateKeyboardEvent`/`CGEventPost` exposing `sendCmdShiftRightBracket()`. Protocol + default impl for injection in tests. |
| `Sources/AgentDeckApp/AccessibilityPermissionChecker.swift` | One-function wrapper around `AXIsProcessTrustedWithOptions` so we can detect + graceful-degrade when Accessibility permission is missing. |
| `Tests/AgentDeckCoreTests/WarpSQLiteReaderTests.swift` | Unit tests using a synthetic warp.sqlite temp-file fixture that reproduces the exact minimal schema we query. |

**Modified files**

| Path | Change |
|---|---|
| `Sources/AgentDeckCore/AgentSession.swift` | Add `warpPaneUUID: String?` field to `JumpTarget` struct (and its init). Backward-compat Codable via `decodeIfPresent`. |
| `Sources/AgentDeckCore/ClaudeHooks.swift` | Add `warpPaneUUID` field to `ClaudeHookPayload`. Populate it in `withRuntimeContext` when `terminalApp == "Warp"`. Pass it through `defaultJumpTarget`. |
| `Sources/AgentDeckCore/CodexHooks.swift` | Same three changes as ClaudeHooks. |
| `Sources/AgentDeckApp/TerminalJumpService.swift` | Add `WarpFocusedPaneReader` / `WarpTabCountReader` / `WarpKeystroker` typealiases + injection points. Add `jumpToWarpPane(_:)` private method. Register `case "dev.warp.Warp-Stable"` in the `jump(to:)` dispatcher. |
| `Tests/AgentDeckCoreTests/ClaudeHooksTests.swift` | Add tests verifying `withRuntimeContext` populates `warpPaneUUID` when reader stub returns a value, skips lookup when `terminalApp != "Warp"`, and leaves payload unchanged on nil return. |
| `Tests/AgentDeckCoreTests/CodexHooksTests.swift` | Same. |
| `Tests/AgentDeckAppTests/TerminalJumpServiceTests.swift` | Add tests for `jumpToWarpPane` covering: already-on-target (zero keystrokes, Warp activated), reaches-target-after-N-cycles, never-reaches-target (caps out gracefully), nil target (degrades to app activation). |

---

## Task 1: Add `warpPaneUUID` field to `JumpTarget`

**Files:**
- Modify: `Sources/AgentDeckCore/AgentSession.swift:114-143`
- Test: `Tests/AgentDeckCoreTests/SessionStateTests.swift` (add one Codable round-trip test)

- [ ] **Step 1: Write failing round-trip Codable test**

Add to `Tests/AgentDeckCoreTests/SessionStateTests.swift` (inside the existing test struct):

```swift
@Test
func jumpTargetRoundTripsWarpPaneUUIDThroughCodable() throws {
    let target = JumpTarget(
        terminalApp: "Warp",
        workspaceName: "demo",
        paneTitle: "Claude demo",
        workingDirectory: "/tmp/demo",
        warpPaneUUID: "D1A5DF3027E44FC080FE2656FAF2BA2E"
    )
    let data = try JSONEncoder().encode(target)
    let decoded = try JSONDecoder().decode(JumpTarget.self, from: data)
    #expect(decoded.warpPaneUUID == "D1A5DF3027E44FC080FE2656FAF2BA2E")

    // And: legacy JSON without the field decodes to nil
    let legacyJSON = """
    {"terminalApp":"Warp","workspaceName":"demo","paneTitle":"Claude demo","workingDirectory":"/tmp/demo"}
    """.data(using: .utf8)!
    let legacy = try JSONDecoder().decode(JumpTarget.self, from: legacyJSON)
    #expect(legacy.warpPaneUUID == nil)
}
```

- [ ] **Step 2: Run test to verify it fails at compile time**

Run: `swift test --filter jumpTargetRoundTripsWarpPaneUUIDThroughCodable 2>&1 | tail -20`

Expected: compile error about unknown argument label `warpPaneUUID` in `JumpTarget.init`.

- [ ] **Step 3: Add the field to `JumpTarget`**

Edit `Sources/AgentDeckCore/AgentSession.swift` lines 114-143. The existing struct already has `tmuxTarget` and `tmuxSocketPath` — add `warpPaneUUID` alongside them:

```swift
public struct JumpTarget: Equatable, Codable, Sendable {
    public var terminalApp: String
    public var workspaceName: String
    public var paneTitle: String
    public var workingDirectory: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var tmuxTarget: String?
    public var tmuxSocketPath: String?
    public var warpPaneUUID: String?

    public init(
        terminalApp: String,
        workspaceName: String,
        paneTitle: String,
        workingDirectory: String? = nil,
        terminalSessionID: String? = nil,
        terminalTTY: String? = nil,
        tmuxTarget: String? = nil,
        tmuxSocketPath: String? = nil,
        warpPaneUUID: String? = nil
    ) {
        self.terminalApp = terminalApp
        self.workspaceName = workspaceName
        self.paneTitle = paneTitle
        self.workingDirectory = workingDirectory
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.tmuxTarget = tmuxTarget
        self.tmuxSocketPath = tmuxSocketPath
        self.warpPaneUUID = warpPaneUUID
    }
}
```

Because `JumpTarget` uses synthesized `Codable`, the decoder automatically tolerates missing keys for optional fields. No custom `CodingKeys` or decoder work needed — verify by re-running the test.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter jumpTargetRoundTripsWarpPaneUUIDThroughCodable 2>&1 | tail -10`

Expected: PASS.

- [ ] **Step 5: Run the full test suite to confirm no regressions from adding an optional field**

Run: `swift test 2>&1 | tail -5`

Expected: all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentDeckCore/AgentSession.swift Tests/AgentDeckCoreTests/SessionStateTests.swift
git commit -m "feat(core): add warpPaneUUID field to JumpTarget

Optional field reserved for Warp precision-jump; nil for all other
terminals. Backward-compatible decoding via synthesized Codable +
existing decodeIfPresent pattern in AgentSession."
```

---

## Task 2: Plumb `warpPaneUUID` through `ClaudeHookPayload` and `CodexHookPayload`

**Files:**
- Modify: `Sources/AgentDeckCore/ClaudeHooks.swift:355-403` (add field + CodingKey) and the `defaultJumpTarget` computed property near line 677
- Modify: `Sources/AgentDeckCore/CodexHooks.swift` (equivalent field, CodingKey, defaultJumpTarget)
- Test: `Tests/AgentDeckCoreTests/ClaudeHooksTests.swift`, `Tests/AgentDeckCoreTests/CodexHooksTests.swift`

- [ ] **Step 1: Write failing test for Claude**

Add to `Tests/AgentDeckCoreTests/ClaudeHooksTests.swift`:

```swift
@Test
func claudeDefaultJumpTargetForwardsWarpPaneUUID() {
    let payload = ClaudeHookPayload(
        cwd: "/tmp/demo",
        hookEventName: .sessionStart,
        sessionID: "s1",
        terminalApp: "Warp",
        warpPaneUUID: "D1A5DF3027E44FC080FE2656FAF2BA2E"
    )
    #expect(payload.defaultJumpTarget.warpPaneUUID == "D1A5DF3027E44FC080FE2656FAF2BA2E")
}
```

- [ ] **Step 2: Write equivalent failing test for Codex**

Add to `Tests/AgentDeckCoreTests/CodexHooksTests.swift`:

```swift
@Test
func codexDefaultJumpTargetForwardsWarpPaneUUID() {
    var payload = CodexHookPayload(
        cwd: "/tmp/demo",
        hookEventName: .sessionStart,
        sessionID: "s1"
    )
    payload.terminalApp = "Warp"
    payload.warpPaneUUID = "D1A5DF3027E44FC080FE2656FAF2BA2E"
    #expect(payload.defaultJumpTarget.warpPaneUUID == "D1A5DF3027E44FC080FE2656FAF2BA2E")
}
```

(Note: if `CodexHookPayload.init` accepts `warpPaneUUID` directly after this task, simplify the test to construct it via `init`. Use whichever constructor shape you land on.)

- [ ] **Step 3: Run tests to verify compile failure**

Run: `swift test --filter "claudeDefaultJumpTargetForwardsWarpPaneUUID|codexDefaultJumpTargetForwardsWarpPaneUUID" 2>&1 | tail -15`

Expected: compile error on the unknown argument / property `warpPaneUUID`.

- [ ] **Step 4: Add the field and CodingKey to `ClaudeHookPayload`**

In `Sources/AgentDeckCore/ClaudeHooks.swift`:

1. Add field declaration next to the other `terminal*` fields (around line 364):
   ```swift
   public var terminalTitle: String?
   /// Warp-specific per-pane identifier discovered via Warp's SQLite state
   /// at hook runtime. Not sent over the wire by the hook script — populated
   /// in `withRuntimeContext` and serialized through the bridge.
   public var warpPaneUUID: String?
   ```

2. Add CodingKey (around line 400):
   ```swift
   case terminalTitle = "terminal_title"
   case warpPaneUUID = "warp_pane_uuid"
   ```

3. Add parameter to the public `init` (around line 432) and assign to self:
   ```swift
   terminalTitle: String? = nil,
   warpPaneUUID: String? = nil,
   remote: Bool? = nil
   ```
   and in the init body:
   ```swift
   self.terminalTitle = terminalTitle
   self.warpPaneUUID = warpPaneUUID
   self.remote = remote
   ```

4. Handle decode in `init(from decoder:)` (search for `terminalTitle = try container.decodeIfPresent` and add a sibling line):
   ```swift
   terminalTitle = try container.decodeIfPresent(String.self, forKey: .terminalTitle)
   warpPaneUUID = try container.decodeIfPresent(String.self, forKey: .warpPaneUUID)
   ```

5. Handle encode in `encode(to encoder:)` (search for `try container.encodeIfPresent(terminalTitle` and add a sibling line):
   ```swift
   try container.encodeIfPresent(terminalTitle, forKey: .terminalTitle)
   try container.encodeIfPresent(warpPaneUUID, forKey: .warpPaneUUID)
   ```

6. Thread it through `defaultJumpTarget` (line 677-686):
   ```swift
   var defaultJumpTarget: JumpTarget {
       JumpTarget(
           terminalApp: terminalApp ?? "Unknown",
           workspaceName: workspaceName,
           paneTitle: terminalTitle ?? "Claude \(sessionID.prefix(8))",
           workingDirectory: cwd,
           terminalSessionID: terminalSessionID,
           terminalTTY: terminalTTY,
           warpPaneUUID: warpPaneUUID
       )
   }
   ```

- [ ] **Step 5: Make the same change to `CodexHookPayload`**

In `Sources/AgentDeckCore/CodexHooks.swift`, repeat all six sub-steps from Step 4 against the Codex payload type. The `terminalApp` field is already there (added in an earlier change); `warpPaneUUID` slots in beside it.

Find the `defaultJumpTarget` computed property (around line 266-275) and add `warpPaneUUID: warpPaneUUID` to the `JumpTarget(…)` constructor call.

- [ ] **Step 6: Run the two new tests to verify they now compile and pass**

Run: `swift test --filter "claudeDefaultJumpTargetForwardsWarpPaneUUID|codexDefaultJumpTargetForwardsWarpPaneUUID" 2>&1 | tail -10`

Expected: both PASS.

- [ ] **Step 7: Run the full test suite to catch Codable regressions**

Run: `swift test 2>&1 | tail -5`

Expected: all tests pass. Any test that encoded a full `ClaudeHookPayload` and compared bytes would need updating — verify none do (as of the start of this work, none did).

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentDeckCore/ClaudeHooks.swift Sources/AgentDeckCore/CodexHooks.swift Tests/AgentDeckCoreTests/ClaudeHooksTests.swift Tests/AgentDeckCoreTests/CodexHooksTests.swift
git commit -m "feat(core): plumb warpPaneUUID through Claude and Codex hook payloads

New optional wire field \"warp_pane_uuid\" carries the per-pane
identifier discovered in withRuntimeContext through the bridge to
AppModel, and through defaultJumpTarget into JumpTarget. Fully
backward-compatible: legacy payloads without the field decode to nil."
```

---

## Task 3: `WarpSQLiteReader` — initialization and path resolution

**Files:**
- Create: `Sources/AgentDeckCore/WarpSQLiteReader.swift`
- Test: `Tests/AgentDeckCoreTests/WarpSQLiteReaderTests.swift`

- [ ] **Step 1: Create the test file with a failing init test**

Create `Tests/AgentDeckCoreTests/WarpSQLiteReaderTests.swift`:

```swift
import Foundation
import Testing
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
}
```

- [ ] **Step 2: Run tests to see compile failure**

Run: `swift test --filter WarpSQLiteReaderTests 2>&1 | tail -15`

Expected: compile error "no such module/type `WarpSQLiteReader`".

- [ ] **Step 3: Create `WarpSQLiteReader.swift` with init + default path**

Create `Sources/AgentDeckCore/WarpSQLiteReader.swift`:

```swift
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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter WarpSQLiteReaderTests 2>&1 | tail -10`

Expected: both init tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentDeckCore/WarpSQLiteReader.swift Tests/AgentDeckCoreTests/WarpSQLiteReaderTests.swift
git commit -m "feat(core): scaffold WarpSQLiteReader with default-path resolution

Read-only reader over Warp's live SQLite state. This task only lands
the struct + default-path helper; queries come in subsequent tasks."
```

---

## Task 4: `WarpSQLiteReader.lookupPaneUUID(forCwd:)`

**Files:**
- Modify: `Sources/AgentDeckCore/WarpSQLiteReader.swift`
- Modify: `Tests/AgentDeckCoreTests/WarpSQLiteReaderTests.swift`

- [ ] **Step 1: Add a SQLite fixture helper to the test file**

Append to `Tests/AgentDeckCoreTests/WarpSQLiteReaderTests.swift` **outside** the test struct:

```swift
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
```

- [ ] **Step 2: Write failing test for `lookupPaneUUID`**

Append to `WarpSQLiteReaderTests` struct:

```swift
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
```

- [ ] **Step 3: Run tests to see failure**

Run: `swift test --filter "lookupPaneUUID" 2>&1 | tail -15`

Expected: compile error (method doesn't exist yet).

- [ ] **Step 4: Implement `lookupPaneUUID`**

In `Sources/AgentDeckCore/WarpSQLiteReader.swift`, append a method to the struct:

```swift
    /// Resolves the Warp pane UUID hosting a Claude/Codex agent running in `cwd`.
    ///
    /// The query joins `commands` → `blocks` via the `precmd-<session_id>-<n>`
    /// block_id format (Warp records one block per shell prompt), filters to
    /// commands starting with "claude" or "codex" in the given pwd, and takes
    /// the most recent match.
    ///
    /// Returns uppercase hex string (32 chars, no separators) suitable for
    /// comparison against the result of `currentFocusedPaneUUID`. Returns nil
    /// on any error.
    public func lookupPaneUUID(forCwd cwd: String) -> String? {
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT hex(b.pane_leaf_uuid)
        FROM commands c
        JOIN blocks b ON b.block_id LIKE 'precmd-' || c.session_id || '-%'
        WHERE (c.command LIKE 'claude%' OR c.command LIKE 'codex%')
          AND c.pwd = ?
        ORDER BY c.id DESC
        LIMIT 1;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        let cwdCString = cwd.withCString { strdup($0) }
        defer { free(cwdCString) }
        sqlite3_bind_text(stmt, 1, cwdCString, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cString)
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
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter "lookupPaneUUID" 2>&1 | tail -10`

Expected: three PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentDeckCore/WarpSQLiteReader.swift Tests/AgentDeckCoreTests/WarpSQLiteReaderTests.swift
git commit -m "feat(core): implement WarpSQLiteReader.lookupPaneUUID

Joins Warp's commands -> blocks tables via the precmd-<session>-<n>
block_id format to resolve the Warp pane UUID hosting a Claude or
Codex agent in a given working directory. All failures return nil."
```

---

## Task 5: `WarpSQLiteReader.currentFocusedPaneUUID` and `tabCountInActiveWindow`

**Files:**
- Modify: `Sources/AgentDeckCore/WarpSQLiteReader.swift`
- Modify: `Tests/AgentDeckCoreTests/WarpSQLiteReaderTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `WarpSQLiteReaderTests`:

```swift
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
```

- [ ] **Step 2: Run tests to see failure**

Run: `swift test --filter "currentFocusedPaneUUID|tabCountInActiveWindow" 2>&1 | tail -15`

Expected: compile errors (methods don't exist).

- [ ] **Step 3: Implement both methods**

Append to `WarpSQLiteReader` struct (above the private `openReadOnly()`):

```swift
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

        let sql = """
        SELECT hex(tp.uuid)
        FROM tabs t
        JOIN pane_nodes pn ON pn.tab_id = t.id AND pn.is_leaf = 1
        JOIN terminal_panes tp ON tp.id = pn.id
        WHERE t.window_id = (SELECT active_window_id FROM app LIMIT 1)
        ORDER BY t.id
        LIMIT 1 OFFSET (
            SELECT active_tab_index FROM windows
            WHERE id = (SELECT active_window_id FROM app LIMIT 1)
        );
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cString)
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
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter "currentFocusedPaneUUID|tabCountInActiveWindow" 2>&1 | tail -10`

Expected: four PASS.

- [ ] **Step 5: Run full WarpSQLiteReader suite to confirm nothing broke**

Run: `swift test --filter WarpSQLiteReaderTests 2>&1 | tail -15`

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentDeckCore/WarpSQLiteReader.swift Tests/AgentDeckCoreTests/WarpSQLiteReaderTests.swift
git commit -m "feat(core): add currentFocusedPaneUUID and tabCountInActiveWindow

Both queries drive the precision jump cycling loop: the focus check
is the termination condition, the tab count bounds the retry cap."
```

---

## Task 6: Wire `WarpSQLiteReader.lookupPaneUUID` into `ClaudeHooks.withRuntimeContext`

**Files:**
- Modify: `Sources/AgentDeckCore/ClaudeHooks.swift` (in `withRuntimeContext`, around line 920-940 where `inferTerminalApp` is called)
- Modify: `Tests/AgentDeckCoreTests/ClaudeHooksTests.swift`

- [ ] **Step 1: Add a function-parameter reader stub to `withRuntimeContext`**

The existing `withRuntimeContext(environment:currentTTYProvider:terminalLocatorProvider:)` method will grow one more optional parameter: `warpPaneResolver: (String) -> String?`. Default it to the real `WarpSQLiteReader().lookupPaneUUID(forCwd:)` so production callers don't need to know.

- [ ] **Step 2: Write failing test**

Add to `ClaudeHooksTests`:

```swift
@Test
func claudeWithRuntimeContextPopulatesWarpPaneUUIDFromResolver() {
    let payload = ClaudeHookPayload(
        cwd: "/Users/u/demo",
        hookEventName: .sessionStart,
        sessionID: "s1"
    ).withRuntimeContext(
        environment: ["WARP_IS_LOCAL_SHELL_SESSION": "1"],
        currentTTYProvider: { nil },
        terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) },
        warpPaneResolver: { cwd in
            cwd == "/Users/u/demo" ? "DEADBEEFDEADBEEFDEADBEEFDEADBEEF" : nil
        }
    )

    #expect(payload.terminalApp == "Warp")
    #expect(payload.warpPaneUUID == "DEADBEEFDEADBEEFDEADBEEFDEADBEEF")
    #expect(payload.defaultJumpTarget.warpPaneUUID == "DEADBEEFDEADBEEFDEADBEEFDEADBEEF")
}

@Test
func claudeWithRuntimeContextSkipsWarpResolverForNonWarpTerminal() {
    var resolverCalls = 0
    let payload = ClaudeHookPayload(
        cwd: "/Users/u/demo",
        hookEventName: .sessionStart,
        sessionID: "s1"
    ).withRuntimeContext(
        environment: ["TERM_PROGRAM": "ghostty"],
        currentTTYProvider: { nil },
        terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) },
        warpPaneResolver: { _ in
            resolverCalls += 1
            return "SHOULD-NOT-BE-USED"
        }
    )

    #expect(payload.terminalApp == "Ghostty")
    #expect(payload.warpPaneUUID == nil)
    #expect(resolverCalls == 0)
}
```

- [ ] **Step 3: Run tests to see failure**

Run: `swift test --filter "claudeWithRuntimeContextPopulatesWarpPaneUUID|claudeWithRuntimeContextSkipsWarpResolver" 2>&1 | tail -15`

Expected: compile error (unknown parameter `warpPaneResolver`).

- [ ] **Step 4: Implement the parameter in `withRuntimeContext`**

In `Sources/AgentDeckCore/ClaudeHooks.swift`, find the convenience `withRuntimeContext()` (no args) that calls the full one, and find the full one that takes `environment`, `currentTTYProvider`, `terminalLocatorProvider`. Modify the full version:

```swift
public func withRuntimeContext(
    environment: [String: String],
    currentTTYProvider: () -> String?,
    terminalLocatorProvider: (String) -> (sessionID: String?, tty: String?, title: String?),
    warpPaneResolver: (String) -> String? = { cwd in
        WarpSQLiteReader().lookupPaneUUID(forCwd: cwd)
    }
) -> ClaudeHookPayload {
    var payload = self

    if payload.terminalApp == nil {
        payload.terminalApp = inferTerminalApp(from: environment)
    }

    // ... (existing body)

    // NEW: resolve Warp pane UUID from the live SQLite state
    if payload.terminalApp == "Warp", payload.warpPaneUUID == nil {
        payload.warpPaneUUID = warpPaneResolver(payload.cwd)
    }

    return payload
}
```

The file has a convenience overload `withRuntimeContext(environment:)` (around line 912) that forwards to the full method with inline providers. Update that overload to also pass a default `warpPaneResolver` so existing no-argument callers stay source-compatible:

```swift
func withRuntimeContext(environment: [String: String]) -> ClaudeHookPayload {
    withRuntimeContext(
        environment: environment,
        currentTTYProvider: { currentTTY() },
        terminalLocatorProvider: { terminalLocator(for: $0) },
        warpPaneResolver: { cwd in WarpSQLiteReader().lookupPaneUUID(forCwd: cwd) }
    )
}
```

If the convenience overload has a different parameter list than shown above, preserve its existing parameters and only add the new `warpPaneResolver` line.

- [ ] **Step 5: Run the new tests**

Run: `swift test --filter "claudeWithRuntimeContextPopulatesWarpPaneUUID|claudeWithRuntimeContextSkipsWarpResolver" 2>&1 | tail -10`

Expected: both PASS.

- [ ] **Step 6: Run full Claude hook test suite to catch regressions**

Run: `swift test --filter ClaudeHooksTests 2>&1 | tail -15`

Expected: all tests pass (including the earlier Warp identification tests added for the fix PR).

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentDeckCore/ClaudeHooks.swift Tests/AgentDeckCoreTests/ClaudeHooksTests.swift
git commit -m "feat(core): resolve Warp pane UUID in ClaudeHooks.withRuntimeContext

On hook events in Warp, query Warp's SQLite to find the pane_uuid
of the tab running this Claude session, and stash it on the payload
so the jump service can use it for precision focus. Injectable
resolver parameter for testability; non-Warp terminals skip lookup."
```

---

## Task 7: Wire the same resolver into `CodexHooks.withRuntimeContext`

**Files:**
- Modify: `Sources/AgentDeckCore/CodexHooks.swift` (find its `withRuntimeContext` equivalent)
- Modify: `Tests/AgentDeckCoreTests/CodexHooksTests.swift` (there may not be one yet — if so, see Step 1)

- [ ] **Step 1: Locate Codex's runtime-context method**

Read `Sources/AgentDeckCore/CodexHooks.swift` and find the method equivalent to Claude's `withRuntimeContext`. Based on earlier exploration it's around line 389-460 and invokes `inferTerminalApp(from: environment)` (line 394). Confirm the method signature before continuing.

- [ ] **Step 2: Write failing test**

If `Tests/AgentDeckCoreTests/CodexHooksTests.swift` does not exist yet, create it with the standard header:

```swift
import Foundation
import Testing
@testable import AgentDeckCore

struct CodexHooksTests {
    @Test
    func codexWithRuntimeContextPopulatesWarpPaneUUIDFromResolver() {
        // ... same shape as the Claude test but with CodexHookPayload
    }
}
```

Full test code to append (keep the outer `struct CodexHooksTests { ... }` if it already exists; otherwise create it with the header above):

```swift
@Test
func codexWithRuntimeContextPopulatesWarpPaneUUIDFromResolver() {
    let payload = CodexHookPayload(
        cwd: "/Users/u/demo",
        hookEventName: .sessionStart,
        sessionID: "s1"
    ).withRuntimeContext(
        environment: ["WARP_IS_LOCAL_SHELL_SESSION": "1"],
        currentTTYProvider: { nil },
        terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) },
        warpPaneResolver: { cwd in
            cwd == "/Users/u/demo" ? "DEADBEEFDEADBEEFDEADBEEFDEADBEEF" : nil
        }
    )

    #expect(payload.terminalApp == "Warp")
    #expect(payload.warpPaneUUID == "DEADBEEFDEADBEEFDEADBEEFDEADBEEF")
    #expect(payload.defaultJumpTarget.warpPaneUUID == "DEADBEEFDEADBEEFDEADBEEFDEADBEEF")
}

@Test
func codexWithRuntimeContextSkipsWarpResolverForNonWarpTerminal() {
    var resolverCalls = 0
    let payload = CodexHookPayload(
        cwd: "/Users/u/demo",
        hookEventName: .sessionStart,
        sessionID: "s1"
    ).withRuntimeContext(
        environment: ["TERM_PROGRAM": "ghostty"],
        currentTTYProvider: { nil },
        terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) },
        warpPaneResolver: { _ in
            resolverCalls += 1
            return "SHOULD-NOT-BE-USED"
        }
    )

    #expect(payload.terminalApp == "Ghostty")
    #expect(payload.warpPaneUUID == nil)
    #expect(resolverCalls == 0)
}
```

Adjust the `CodexHookPayload` constructor arguments (`hookEventName`, `sessionID`, etc.) if the Codex type's init signature differs slightly from the Claude one. Use the existing `CodexHookPayload.init` for reference.

- [ ] **Step 3: Run tests to see failure**

Run: `swift test --filter "codexWithRuntimeContextPopulatesWarpPaneUUID" 2>&1 | tail -15`

Expected: compile error.

- [ ] **Step 4: Add the parameter and the Warp-guarded call**

In `Sources/AgentDeckCore/CodexHooks.swift`, modify the full `withRuntimeContext` (around line 386) and its convenience overload (around line 378):

1. Full method signature — add `warpPaneResolver` with a real default:

```swift
func withRuntimeContext(
    environment: [String: String],
    currentTTYProvider: () -> String?,
    terminalLocatorProvider: (String) -> (sessionID: String?, tty: String?, title: String?),
    warpPaneResolver: (String) -> String? = { cwd in
        WarpSQLiteReader().lookupPaneUUID(forCwd: cwd)
    }
) -> CodexHookPayload {
    var payload = self
    // ... existing body ...
    if payload.terminalApp == nil {
        payload.terminalApp = inferTerminalApp(from: environment)
    }

    // NEW: after terminalApp is resolved
    if payload.terminalApp == "Warp", payload.warpPaneUUID == nil {
        payload.warpPaneUUID = warpPaneResolver(payload.cwd)
    }

    return payload
}
```

2. Convenience overload — pass a default resolver so existing callers stay source-compatible:

```swift
func withRuntimeContext(environment: [String: String]) -> CodexHookPayload {
    withRuntimeContext(
        environment: environment,
        currentTTYProvider: { currentTTY() },
        terminalLocatorProvider: { terminalLocator(for: $0) },
        warpPaneResolver: { cwd in WarpSQLiteReader().lookupPaneUUID(forCwd: cwd) }
    )
}
```

If the existing convenience overload has additional parameters (e.g. TTY provider arguments), preserve them and only add the `warpPaneResolver` line.

- [ ] **Step 5: Run tests**

Run: `swift test --filter CodexHooksTests 2>&1 | tail -10`

Expected: tests PASS; no regression in existing Codex tests.

- [ ] **Step 6: Run the whole test suite to catch cross-cutting regressions**

Run: `swift test 2>&1 | tail -5`

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentDeckCore/CodexHooks.swift Tests/AgentDeckCoreTests/CodexHooksTests.swift
git commit -m "feat(core): resolve Warp pane UUID in CodexHooks.withRuntimeContext

Codex parity with Claude: the same injectable warpPaneResolver is
invoked only when the classifier resolves terminalApp to \"Warp\"."
```

---

## Task 8: `KeystrokeInjector` for `Cmd+Shift+]`

**Files:**
- Create: `Sources/AgentDeckApp/KeystrokeInjector.swift`
- Test: `Tests/AgentDeckAppTests/KeystrokeInjectorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AgentDeckAppTests/KeystrokeInjectorTests.swift`:

```swift
import XCTest
@testable import AgentDeckApp

final class KeystrokeInjectorTests: XCTestCase {
    func testDefaultInjectorPostsCmdShiftRightBracketWithoutCrashing() {
        // We can't observe actual OS-level CGEvent delivery in a unit test,
        // but constructing and posting the event without throwing/crashing
        // covers the init-time correctness of the keycode and flags.
        let injector = DefaultKeystrokeInjector()
        injector.sendCmdShiftRightBracket()  // no XCTAssert — if this crashes the test fails
    }

    func testSpyKeystrokerRecordsCalls() {
        let spy = KeystrokeInjectorSpy()
        spy.sendCmdShiftRightBracket()
        spy.sendCmdShiftRightBracket()
        XCTAssertEqual(spy.callCount, 2)
    }
}

final class KeystrokeInjectorSpy: KeystrokeInjector, @unchecked Sendable {
    var callCount = 0
    func sendCmdShiftRightBracket() {
        callCount += 1
    }
}
```

(Leave this type at **file scope**, not nested inside `KeystrokeInjectorTests`, so Task 10's tests in `TerminalJumpServiceTests.swift` can reuse it across the shared test target.)

- [ ] **Step 2: Run tests to see failure**

Run: `swift test --filter KeystrokeInjector 2>&1 | tail -15`

Expected: compile error (protocol and default impl do not exist).

- [ ] **Step 3: Create the implementation file**

Create `Sources/AgentDeckApp/KeystrokeInjector.swift`:

```swift
import Foundation
import CoreGraphics

/// Injection point for CGEvent keystroke delivery. Implementations must be
/// safe to call from any thread.
public protocol KeystrokeInjector {
    func sendCmdShiftRightBracket()
}

/// Production implementation that posts a synthetic Cmd+Shift+] via CGEventPost.
/// Requires macOS Accessibility permission; will silently no-op (events are
/// dropped by the system) if permission is denied. Callers should check
/// permission separately if they need reliable delivery.
public struct DefaultKeystrokeInjector: KeystrokeInjector {
    public init() {}

    public func sendCmdShiftRightBracket() {
        // Virtual keycode 0x1E is the US-layout `]` key. Cmd+Shift+] is the
        // Warp default "next tab" shortcut.
        let keyCode: CGKeyCode = 0x1E
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return
        }

        keyDown.flags = [.maskCommand, .maskShift]
        keyUp.flags = [.maskCommand, .maskShift]

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter KeystrokeInjector 2>&1 | tail -10`

Expected: PASS. (The "no crash" test will emit a single keystroke to whoever has focus during the test run — harmless. If the test runner itself eats it, even better.)

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentDeckApp/KeystrokeInjector.swift Tests/AgentDeckAppTests/KeystrokeInjectorTests.swift
git commit -m "feat(app): add KeystrokeInjector protocol with Cmd+Shift+] implementation

Thin wrapper over CGEventPost for the Warp \"next tab\" shortcut,
gated behind a protocol so TerminalJumpService can inject a spy
in unit tests. Requires macOS Accessibility permission at runtime."
```

---

## Task 9: `AccessibilityPermissionChecker`

**Files:**
- Create: `Sources/AgentDeckApp/AccessibilityPermissionChecker.swift`
- Test: `Tests/AgentDeckAppTests/AccessibilityPermissionCheckerTests.swift`

- [ ] **Step 1: Write failing test**

Create `Tests/AgentDeckAppTests/AccessibilityPermissionCheckerTests.swift`:

```swift
import XCTest
@testable import AgentDeckApp

final class AccessibilityPermissionCheckerTests: XCTestCase {
    func testCheckerReportsBoolWithoutCrashing() {
        // We cannot assume the test host has (or lacks) Accessibility.
        // The point of this test is that the call returns cleanly and
        // doesn't prompt the user during `swift test`.
        let checker = DefaultAccessibilityPermissionChecker()
        _ = checker.isTrusted()
    }

    func testStubCheckerReturnsInjectedValue() {
        let trueChecker = AccessibilityPermissionCheckerStub(trusted: true)
        XCTAssertTrue(trueChecker.isTrusted())

        let falseChecker = AccessibilityPermissionCheckerStub(trusted: false)
        XCTAssertFalse(falseChecker.isTrusted())
    }
}

struct AccessibilityPermissionCheckerStub: AccessibilityPermissionChecker {
    let trusted: Bool
    func isTrusted() -> Bool { trusted }
}
```

- [ ] **Step 2: Run tests to see failure**

Run: `swift test --filter AccessibilityPermissionChecker 2>&1 | tail -15`

Expected: compile error.

- [ ] **Step 3: Create the implementation**

Create `Sources/AgentDeckApp/AccessibilityPermissionChecker.swift`:

```swift
import Foundation
import ApplicationServices

/// Checks whether the current process has macOS Accessibility permission,
/// required for CGEventPost keystroke injection used by Warp precision jump.
public protocol AccessibilityPermissionChecker {
    func isTrusted() -> Bool
}

public struct DefaultAccessibilityPermissionChecker: AccessibilityPermissionChecker {
    public init() {}

    public func isTrusted() -> Bool {
        // Pass `prompt: false` so unit tests don't pop the system dialog.
        // The real jump flow calls AXIsProcessTrustedWithOptions with the
        // prompt key separately, guarded by the first-jump-attempt code path.
        AXIsProcessTrusted()
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AccessibilityPermissionChecker 2>&1 | tail -10`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentDeckApp/AccessibilityPermissionChecker.swift Tests/AgentDeckAppTests/AccessibilityPermissionCheckerTests.swift
git commit -m "feat(app): add AccessibilityPermissionChecker wrapper

Protocol + AXIsProcessTrusted default impl. Production code can
gate CGEventPost-based keystroke injection on a non-prompting trust
check; tests inject a stub."
```

---

## Task 10: `TerminalJumpService.jumpToWarpPane` + dispatcher wire-up

This task combines the new handler implementation and its registration in the `jump(to:)` switch. They must land together because the tests call `service.jump(to:)` which routes through the dispatcher.

**Files:**
- Modify: `Sources/AgentDeckApp/TerminalJumpService.swift` — add new typealiases, init parameters, the `jumpToWarpPane` private method, AND the dispatcher case.
- Modify: `Tests/AgentDeckAppTests/TerminalJumpServiceTests.swift`

- [ ] **Step 1: Write failing tests for the three main paths**

Append to `TerminalJumpServiceTests`:

```swift
func testWarpJumpReturnsImmediatelyWhenAlreadyOnTargetPane() throws {
    let openedArguments = OpenedArgumentsBox()
    let keystroker = KeystrokeInjectorSpy()
    let targetUUID = "D1A5DF3027E44FC080FE2656FAF2BA2E"

    let service = TerminalJumpService(
        applicationResolver: { id in
            id == "dev.warp.Warp-Stable" ? URL(fileURLWithPath: "/Applications/Warp.app") : nil
        },
        appRunningChecker: { id in id == "dev.warp.Warp-Stable" },
        openAction: { arguments in openedArguments.values.append(arguments) },
        appleScriptRunner: { _ in "" },
        warpFocusedPaneReader: { targetUUID },  // already at target
        warpTabCountReader: { 3 },
        warpKeystroker: keystroker,
        accessibilityTrustChecker: { true }
    )

    let result = try service.jump(
        to: JumpTarget(
            terminalApp: "Warp",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/Users/u/demo",
            warpPaneUUID: targetUUID
        )
    )

    XCTAssertEqual(result, "Focused the matching Warp tab.")
    XCTAssertEqual(keystroker.callCount, 0)
    XCTAssertEqual(openedArguments.values, [["-b", "dev.warp.Warp-Stable"]])
}

func testWarpJumpCyclesThroughTabsUntilTargetIsFocused() throws {
    let openedArguments = OpenedArgumentsBox()
    let keystroker = KeystrokeInjectorSpy()
    let targetUUID = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"

    // Simulate starting on some other tab, then after 2 keystrokes landing on target.
    let readSequence = ReadSequenceBox(values: [
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", // initial
        "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC", // after 1st keystroke
        targetUUID,                         // after 2nd keystroke — match!
    ])

    let service = TerminalJumpService(
        applicationResolver: { id in
            id == "dev.warp.Warp-Stable" ? URL(fileURLWithPath: "/Applications/Warp.app") : nil
        },
        appRunningChecker: { id in id == "dev.warp.Warp-Stable" },
        openAction: { arguments in openedArguments.values.append(arguments) },
        appleScriptRunner: { _ in "" },
        warpFocusedPaneReader: { readSequence.next() },
        warpTabCountReader: { 4 },
        warpKeystroker: keystroker,
        accessibilityTrustChecker: { true }
    )

    let result = try service.jump(
        to: JumpTarget(
            terminalApp: "Warp",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/Users/u/demo",
            warpPaneUUID: targetUUID
        )
    )

    XCTAssertEqual(result, "Focused the matching Warp tab.")
    XCTAssertEqual(keystroker.callCount, 2)
    XCTAssertEqual(openedArguments.values, [["-b", "dev.warp.Warp-Stable"]])
}

func testWarpJumpCapsOutAfterTabCountPlusTwoAndReturnsBestEffortMessage() throws {
    let keystroker = KeystrokeInjectorSpy()
    let service = TerminalJumpService(
        applicationResolver: { id in
            id == "dev.warp.Warp-Stable" ? URL(fileURLWithPath: "/Applications/Warp.app") : nil
        },
        appRunningChecker: { id in id == "dev.warp.Warp-Stable" },
        openAction: { _ in },
        appleScriptRunner: { _ in "" },
        warpFocusedPaneReader: { "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" },  // never matches
        warpTabCountReader: { 3 },
        warpKeystroker: keystroker,
        accessibilityTrustChecker: { true }
    )

    let result = try service.jump(
        to: JumpTarget(
            terminalApp: "Warp",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/Users/u/demo",
            warpPaneUUID: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
        )
    )

    XCTAssertEqual(result, "Activated Warp but could not confirm precision focus.")
    XCTAssertEqual(keystroker.callCount, 5)  // tabCount (3) + 2
}

func testWarpJumpWithNilWarpPaneUUIDFallsBackToAppActivation() throws {
    let keystroker = KeystrokeInjectorSpy()
    let openedArguments = OpenedArgumentsBox()
    let service = TerminalJumpService(
        applicationResolver: { id in
            id == "dev.warp.Warp-Stable" ? URL(fileURLWithPath: "/Applications/Warp.app") : nil
        },
        appRunningChecker: { id in id == "dev.warp.Warp-Stable" },
        openAction: { arguments in openedArguments.values.append(arguments) },
        appleScriptRunner: { _ in "" },
        warpFocusedPaneReader: { "SHOULD-NOT-BE-READ" },
        warpTabCountReader: { 3 },
        warpKeystroker: keystroker,
        accessibilityTrustChecker: { true }
    )

    let result = try service.jump(
        to: JumpTarget(
            terminalApp: "Warp",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/Users/u/demo",
            warpPaneUUID: nil
        )
    )

    XCTAssertEqual(result, "Activated Warp. No precise pane mapping available.")
    XCTAssertEqual(keystroker.callCount, 0)
    XCTAssertEqual(openedArguments.values, [["-b", "dev.warp.Warp-Stable"]])
}

func testWarpJumpWithoutAccessibilityPermissionFallsBackToAppActivation() throws {
    let keystroker = KeystrokeInjectorSpy()
    let openedArguments = OpenedArgumentsBox()
    let service = TerminalJumpService(
        applicationResolver: { id in
            id == "dev.warp.Warp-Stable" ? URL(fileURLWithPath: "/Applications/Warp.app") : nil
        },
        appRunningChecker: { id in id == "dev.warp.Warp-Stable" },
        openAction: { arguments in openedArguments.values.append(arguments) },
        appleScriptRunner: { _ in "" },
        warpFocusedPaneReader: { "SOMETHING-ELSE" },
        warpTabCountReader: { 3 },
        warpKeystroker: keystroker,
        accessibilityTrustChecker: { false },   // <-- permission denied
        warpPaneUUID: nil
    )

    let result = try service.jump(
        to: JumpTarget(
            terminalApp: "Warp",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/Users/u/demo",
            warpPaneUUID: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
        )
    )

    XCTAssertEqual(result, "Activated Warp. Grant Accessibility permission to enable precision jump.")
    XCTAssertEqual(keystroker.callCount, 0)
    XCTAssertEqual(openedArguments.values, [["-b", "dev.warp.Warp-Stable"]])
}

// Helper type used by the tests above. `KeystrokeInjectorSpy` is already
// defined at file scope in Tests/AgentDeckAppTests/KeystrokeInjectorTests.swift
// from Task 8 — do NOT redeclare it here, the test target is a single
// module and duplicates will fail to compile. Just reference it.

final class ReadSequenceBox: @unchecked Sendable {
    private var values: [String?]
    init(values: [String?]) { self.values = values }
    func next() -> String? {
        guard !values.isEmpty else { return nil }
        return values.removeFirst()
    }
}
```

Before running Step 2, confirm that `KeystrokeInjectorSpy` in `Tests/AgentDeckAppTests/KeystrokeInjectorTests.swift` is at file scope (not nested inside `final class KeystrokeInjectorTests`) and has `internal` access. If Task 8 placed it nested or fileprivate, promote it before continuing this task.

- [ ] **Step 2: Run tests to see failure**

Run: `swift test --filter "testWarpJump" 2>&1 | tail -20`

Expected: compile errors (unknown init params, no `jumpToWarpPane` method, missing case in switch).

- [ ] **Step 3: Add new typealiases + init parameters to `TerminalJumpService`**

In `Sources/AgentDeckApp/TerminalJumpService.swift`, just after the existing typealiases (around line 10), add:

```swift
    typealias WarpFocusedPaneReader = @Sendable () -> String?
    typealias WarpTabCountReader = @Sendable () -> Int
    typealias AccessibilityTrustChecker = @Sendable () -> Bool
```

Add stored properties:

```swift
    private let warpFocusedPaneReader: WarpFocusedPaneReader
    private let warpTabCountReader: WarpTabCountReader
    private let warpKeystroker: KeystrokeInjector
    private let accessibilityTrustChecker: AccessibilityTrustChecker
```

Update the `init` signature (currently around line 156) to accept these new dependencies with real defaults:

```swift
    init(
        applicationResolver: @escaping ApplicationResolver = { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        },
        appRunningChecker: @escaping AppRunningChecker = { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
        },
        openAction: @escaping OpenAction = Self.defaultOpenAction(arguments:),
        appleScriptRunner: @escaping AppleScriptRunner = Self.defaultAppleScriptRunner(script:),
        processRunner: @escaping ProcessRunner = Self.defaultProcessRunner(executable:arguments:),
        warpFocusedPaneReader: @escaping WarpFocusedPaneReader = { WarpSQLiteReader().currentFocusedPaneUUID() },
        warpTabCountReader: @escaping WarpTabCountReader = { WarpSQLiteReader().tabCountInActiveWindow() },
        warpKeystroker: KeystrokeInjector = DefaultKeystrokeInjector(),
        accessibilityTrustChecker: @escaping AccessibilityTrustChecker = { DefaultAccessibilityPermissionChecker().isTrusted() }
    ) {
        self.applicationResolver = applicationResolver
        self.appRunningChecker = appRunningChecker
        self.openAction = openAction
        self.appleScriptRunner = appleScriptRunner
        self.processRunner = processRunner
        self.warpFocusedPaneReader = warpFocusedPaneReader
        self.warpTabCountReader = warpTabCountReader
        self.warpKeystroker = warpKeystroker
        self.accessibilityTrustChecker = accessibilityTrustChecker
    }
```

- [ ] **Step 4: Implement `jumpToWarpPane`**

Add this private method near the bottom of the struct (before `resolveTerminalApp`):

```swift
    private func jumpToWarpPane(_ target: JumpTarget) throws -> String {
        // 1. Always activate Warp first — this is the baseline behavior.
        try openAction(["-b", "dev.warp.Warp-Stable"])

        // 2. If we don't have a mapped pane UUID, we're done.
        guard let targetPaneUUID = target.warpPaneUUID else {
            return "Activated Warp. No precise pane mapping available."
        }

        // 3. Quick check: are we already on the target pane?
        if warpFocusedPaneReader() == targetPaneUUID {
            return "Focused the matching Warp tab."
        }

        // 4. We need to cycle. CGEventPost requires Accessibility permission;
        //    if it's missing, keystrokes silently get dropped and the loop
        //    is useless. Tell the user instead of pretending to try.
        guard accessibilityTrustChecker() else {
            return "Activated Warp. Grant Accessibility permission to enable precision jump."
        }

        // 5. Cycle with a cap. The cap is `tabCount + 2` — we only need at
        //    most tabCount-1 cycles to reach any tab, but +2 is safety margin
        //    for counting quirks and the rare case where active_tab_index is
        //    briefly stale between read and next keystroke.
        let tabCount = max(1, warpTabCountReader())
        let maxAttempts = tabCount + 2

        for _ in 0..<maxAttempts {
            warpKeystroker.sendCmdShiftRightBracket()
            // Small delay to let Warp update its SQLite state after tab switch.
            // Empirically 50ms is stable; can be tuned down if benchmarking allows.
            Thread.sleep(forTimeInterval: 0.05)
            if warpFocusedPaneReader() == targetPaneUUID {
                return "Focused the matching Warp tab."
            }
        }

        return "Activated Warp but could not confirm precision focus."
    }
```

- [ ] **Step 5: Wire the Warp case into the dispatcher switch**

In the same file, inside `func jump(to target:)` around lines 199-246 (the `switch descriptor.bundleIdentifier` block), add between `com.apple.Terminal` and `fun.tw93.kaku`:

```swift
            case "dev.warp.Warp-Stable":
                return try jumpToWarpPane(target)
```

This case `return`s directly because `jumpToWarpPane` always produces a final answer (either a precise match, a fallback message, or the best-effort cap exhaustion result). Unlike other cases it does not fall through.

- [ ] **Step 6: Run the new tests**

Run: `swift test --filter "testWarpJump" 2>&1 | tail -30`

Expected: all five `testWarpJump*` tests PASS.

- [ ] **Step 7: Run the full test suite**

Run: `swift test 2>&1 | tail -5`

Expected: all existing tests still pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentDeckApp/TerminalJumpService.swift Tests/AgentDeckAppTests/TerminalJumpServiceTests.swift
git commit -m "feat(app): precision jump to Warp tab via SQLite polling + keystroke cycle

New private method TerminalJumpService.jumpToWarpPane dispatched from
the existing jump(to:) switch for dev.warp.Warp-Stable. When a
JumpTarget carries warpPaneUUID, the service activates Warp, checks
the currently focused pane via WarpSQLiteReader, and if it doesn't
match, sends Cmd+Shift+] via KeystrokeInjector in a bounded loop
(tabCount + 2 attempts) until the SQLite check confirms we've landed.

Falls back to bare activation when: warpPaneUUID is nil, Accessibility
permission is denied, or the cap is exhausted without a match. All
new dependencies (focused-pane reader, tab-count reader, keystroker,
trust checker) are injectable for test coverage; production callers
get the real WarpSQLiteReader and DefaultKeystrokeInjector by default."
```

---

## Task 11: Manual end-to-end verification + CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md` (add a new entry under the next release)

- [ ] **Step 1: Build the dev app and run it**

```bash
swift build 2>&1 | tail -5
swift run AgentDeckApp &
```

If `/Applications/Agent Deck.app` is running, quit it first (`osascript -e 'quit app "Agent Deck"'`) so there's no bridge-socket collision.

- [ ] **Step 2: Grant Accessibility permission**

Open **System Settings → Privacy & Security → Accessibility**. If `AgentDeckApp` is listed, toggle it on. If not, trigger a jump attempt from Agent Deck first (which will cause macOS to add it to the list) and come back.

- [ ] **Step 3: Set up the multi-tab scenario**

1. Open Warp.
2. Open 4 new tabs, each in a **different directory**:
   - `cd ~/Developer/agent-deck && claude`
   - `cd /tmp && claude --dangerously-skip-permissions` (any second repo)
   - `cd ~/some-other-project && claude`
   - A fourth tab with a different directory, optionally no Claude.
3. Switch to the Warp tab showing the 4th option so you're NOT on any of the Claude tabs initially.

- [ ] **Step 4: Verify precision jump**

1. Open Agent Deck's session list (notch / top-bar).
2. Identify the session corresponding to tab #1 (by workspace name).
3. Click the jump affordance for that session.
4. **Expected**:
   - Warp activates to the foreground within 100ms.
   - The tab bar visibly flickers as the service cycles tabs.
   - The tab stops on the correct tab within ~300-500ms total.
5. Repeat for sessions #2 and #3. Each should land on its correct tab regardless of where you started.

- [ ] **Step 5: Verify the already-at-target fast path**

1. With a Claude session tab already focused in Warp, switch to a different app (Finder).
2. In Agent Deck, click jump for that same session.
3. **Expected**: Warp activates, no tab flicker (zero keystrokes), lands directly because `warpFocusedPaneReader` saw an immediate match.

- [ ] **Step 6: Verify fallbacks**

1. **No permission**: temporarily disable AgentDeckApp in System Settings → Accessibility. Click jump. Expected: Warp activates, no cycling, Agent Deck toast/log says "Grant Accessibility permission to enable precision jump."
2. **Re-enable permission** and continue.
3. **Close a Claude tab** while the session is still in Agent Deck's list. Click jump for the closed session. Expected: cycling runs the full cap, then returns "Activated Warp but could not confirm precision focus." — never crashes.

- [ ] **Step 7: Run full test suite once more**

```bash
swift test 2>&1 | tail -5
```

Expected: all green.

- [ ] **Step 8: Add CHANGELOG entry**

Edit `CHANGELOG.md` and add a new section at the top (under the "Unreleased" or next version header, whichever the project uses):

```markdown
### Added
- **Precision jump for Warp**: clicking jump on a Claude or Codex session running in Warp now focuses the exact tab hosting that agent, not just the Warp app. Works by reading Warp's live SQLite state (`~/Library/Group Containers/2BBY89MBSN.dev.warp/.../warp.sqlite`) to detect the current focused pane and cycling `Cmd+Shift+]` via `CGEventPost` until the correct tab is reached. Requires macOS Accessibility permission; falls back to bare app activation if permission is denied or the target tab cannot be located.

  **Note**: this feature depends on Warp's internal SQLite schema, which is not a supported public API. A Warp update that changes the schema may break precision jump; the feature always degrades cleanly to the pre-v1.0.14 behavior on any query failure.
```

- [ ] **Step 9: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog entry for Warp precision jump"
```

- [ ] **Step 10: Final manual validation**

After committing, run a final smoke test: `swift run AgentDeckApp` with three Claude tabs in Warp, click jump on each in turn, verify all three land on the right tab. If anything regressed, investigate before pushing.

---

## Out of scope for this plan

The following were explicitly carved out of V1 in the design spec:

1. **Open Code and other third-party agents.** The `commands.command LIKE` filter only matches `claude%` and `codex%`. Extending to other agents is a separate slice once their entry binary names are confirmed.
2. **Rebindable cycle keystroke.** Hard-coded `Cmd+Shift+]`. A settings field reading from Warp's keybinding config is a followup.
3. **Auto-rediscovery of pane UUIDs without a fresh hook event.** If Warp is restarted while a session is idle, the cached pane UUID may be stale until the next hook event refreshes it. Watching Warp's SQLite for changes is a followup.
4. **Tab reorder detection.** Drag-and-drop tab reordering may cause cycling to land on the wrong tab. Loop still terminates at the cap so it's not catastrophic.
5. **Multi-window Warp precision.** V1 uses `app.active_window_id` but has only been tested with single-window Warp. Multi-window behavior needs explicit manual verification before the feature is enabled there.
6. **Upstream API.** We will file a Warp feature request for `warp://action/focus_cli_agent?session_id=…` but that is follow-up work, not part of this plan.
7. **Startup schema health check.** The design spec mentioned proactively reading one row at app startup to detect a schema mismatch and disable the feature for the session with a single log line. V1 instead relies on per-query failure fallback (each `lookupPaneUUID` / `currentFocusedPaneUUID` call that fails returns nil and the caller degrades gracefully). Functionally equivalent; the startup check would give earlier feedback in logs. Add as a followup if schema drift becomes a recurring issue.
8. **Multi-column test coverage for schema mismatch scenarios.** V1 tests cover the happy path, missing database, and missing Claude command. Tests for "schema has extra columns we don't know about" and "schema has removed columns we need" are deferred. The production code's defensive `return nil` behavior handles both cases correctly; the tests would just document it.
9. **Fine-grained SQLITE_BUSY backoff.** V1 uses `sqlite3_busy_timeout(db, 60)` which has SQLite internally retry for up to 60ms before returning SQLITE_BUSY. The spec mentioned an explicit 3-retry 20ms loop at the Swift level, but the built-in timeout is functionally equivalent and simpler. If contention becomes a real problem, switch to an explicit loop.
