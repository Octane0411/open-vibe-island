# Warp Precision Jump — Design

Status: Design draft — awaiting user review
Date: 2026-04-10
Follows: `fix-warp-terminal-identification` (merged in PR #254 / v1.0.14) — Warp sessions are now correctly labeled and clicking jump brings Warp to the foreground, but lands on whichever tab Warp last had focused, not necessarily the tab where the agent is running.

## Problem

When multiple Claude Code (and eventually Codex) sessions run concurrently in different Warp tabs, clicking the jump affordance in Agent Deck today only activates the Warp application. The user must then visually scan the tab bar and click the correct tab manually. With 4+ concurrent Claude tabs this is the dominant friction point in the Warp experience. The desired outcome is **one click → Warp activates AND the correct tab becomes focused**, matching the behavior the user has observed in a competitor product.

## Prior art and why the easy answers don't work

Before committing to this design, the following channels were empirically exhausted:

| Channel | Result |
|---|---|
| AppleScript dictionary | Warp does not publish one. `tell application "Warp"` only exposes app-level activation. |
| System Events Accessibility tree | Warp's main terminal window is a Rust-rendered surface. The AX tree for the process contains only a Settings window + 4 traffic-light buttons. Tabs, panes, and terminal content are invisible to AX. |
| CGWindowList | Sees Warp's one OS-level window (tabs are internal). Window title is `<nil>` and remains so even with Screen Recording permission because Warp doesn't set a title on the main window. |
| `oz` CLI | `/Applications/Warp.app/Contents/Resources/bin/oz` is a shell stub for Warp's Cloud Agent orchestration CLI. None of its subcommands (`agent`, `environment`, `run`, etc.) control local window/tab focus. The `focus-tab` schema found in the binary is kitty's CLI autocomplete data embedded for suggestion purposes — not a Warp command. |
| Warp URL scheme (`warp://action/*`) | Closed whitelist. `new_tab` and `new_window` work. Brute-forcing `focus_cli_agent`, `focus_session`, `select_cli_agent`, `cli-agent/focus`, and several variants all returned `[WARN] Received "action" intent with unexpected action: …` in `~/Library/Logs/warp.log`. |
| localhost:9277 | Warp does listen on this TCP port, but HTTP probes on every plausible REST/JSON-RPC/MCP/SSE/WebSocket path returned bare 404 with no body. Not the path. |
| OSC 0/2 tab-title tagging | Would only improve visual disambiguation (2 clicks); the user explicitly declined this as a workaround. |
| OSC 9 / 777 / 1337 "attention" or "focus" sequences | Warp handles OSC 777 as inbound `cli-agent` notifications (plugin → Warp) only. No outbound focus mechanism. |
| `warp://cli-agent` reverse channel | The `claude-code-warp` plugin emits structured JSON events into this URL via OSC 777 escape sequences. It is strictly unidirectional (plugin → Warp) per the plugin README. |
| Warp Launch Configurations with `is_focused` / `active_tab_index` | Per the Warp docs and GitHub Issue #5575 (closed by the Warp team as "already exists"), these fields only take effect when a launch config opens a fresh set of windows/tabs. There is no mechanism to reapply them to refocus an existing Warp window. |
| Accessibility API keystroke cycling with focus-tab readback | We could send `Cmd+Shift+]` from CGEventPost, but since AX/CGWindowList cannot tell us which tab is now focused after cycling, we would have no way to know when to stop. |

The only viable path that remains is to read Warp's **own persisted state** and drive the UI with a keystroke loop whose termination condition is derived from that state.

## The discovery

Warp persists its live UI state in a SQLite database at:

```
~/Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite
```

The database is in WAL mode (`warp.sqlite-wal` and `warp.sqlite-shm` present), so concurrent readers do not block Warp writers. Empirical reads during active Warp use succeeded repeatedly with no contention.

The following fields are load-bearing for this design:

1. **`windows.active_tab_index`** — 0-based position of the focused tab within its window. **Verified live-updated**: a manual Cmd+Shift+] from the user changed the value from `3` to `2` between two SQLite reads.
2. **`app.active_window_id`** — foreign key into `windows` identifying which window is focused. We have only observed single-window setups, but the field is present.
3. **`tabs(id, window_id)`** — tabs ordered by `id ASC` within a window correspond to the visible tab bar order (empirically: `active_tab_index = 2` matched the 3rd tab by `id` order, and the user-reported focused tab's cwd matched).
4. **`pane_nodes(id, tab_id, is_leaf)`** — tree of panes within a tab. Leaf nodes are actual terminals.
5. **`terminal_panes(id, uuid, cwd)`** — per-pane data keyed by `pane_nodes.id`. `uuid` is a stable per-pane identifier (BLOB, unique). `cwd` is the initial cwd of the shell that was launched into the pane (not the live cwd).
6. **`commands(id, session_id, command, pwd)`** — history of shell commands. `session_id` is Warp's internal shell-session timestamp (BIGINTEGER, NOT the Claude agent's session UUID).
7. **`blocks(id, pane_leaf_uuid, block_id, pwd)`** — per-command persistence rows. `block_id` has the format `precmd-<warp_session_id>-<n>`, linking back to `commands.session_id`. `pane_leaf_uuid` is a BLOB matching `terminal_panes.uuid`.

### The join that makes it work

Given a Claude session whose hook ran in `cwd = X`, we can find the Warp `pane_uuid` hosting that session via:

```sql
SELECT hex(b.pane_leaf_uuid) AS pane_uuid
FROM commands c
JOIN blocks b ON b.block_id LIKE 'precmd-' || c.session_id || '-%'
WHERE c.command LIKE 'claude%'
  AND c.pwd = ?              -- the hook's cwd
ORDER BY c.id DESC
LIMIT 1;
```

Empirically verified against three concurrent Claude sessions on the author's machine: the join returned the exact pane uuids matching the tabs where each Claude session was running.

### The focus-check query

Once we have a target pane_uuid and need to know whether the user is currently on that tab:

```sql
SELECT hex(tp.uuid) AS current_focused_uuid
FROM tabs t
JOIN pane_nodes pn ON pn.tab_id = t.id AND pn.is_leaf = 1
JOIN terminal_panes tp ON tp.id = pn.id
WHERE t.window_id = (SELECT active_window_id FROM app)
ORDER BY t.id
LIMIT 1 OFFSET (SELECT active_tab_index FROM windows WHERE id = (SELECT active_window_id FROM app));
```

Compare result to target. If equal → done. Otherwise cycle.

## The algorithm

### Phase 1 — Discovery (fill `AgentSession.jumpTarget.warpPaneUUID`)

Runs once per Claude session, at `SessionStart` hook event or the earliest hook event we receive for a session.

```
if hook.terminalApp == "Warp":
    pane_uuid = WarpSQLiteReader.lookupPaneUUID(forCwd: hook.cwd)
    if pane_uuid != nil:
        payload.jumpTarget.warpPaneUUID = pane_uuid
```

The lookup uses the join query above. If it returns `nil` (pane uuid could not be resolved — e.g. the user started Claude in an unusual way that didn't leave a `commands` row), we store `nil` and fall back to the current "just activate Warp" behavior at jump time.

**Cache policy**: once resolved, the pane_uuid is persisted in the session registry alongside other jump target fields. It does not need to be re-resolved on every hook event. If Warp is restarted, the pane_uuids may still be valid (Warp restores tabs from SQLite and keeps their uuids), but if they're not we lazily re-resolve on the next hook event by overwriting.

### Phase 2 — Jump (when user clicks jump in Agent Deck)

```
target_pane_uuid = session.jumpTarget.warpPaneUUID

if target_pane_uuid is nil:
    # Fallback: no mapping, just activate Warp app
    open -b dev.warp.Warp-Stable
    return "Activated Warp. No precise pane mapping available."

# 1. Activate Warp to bring it to foreground
open -b dev.warp.Warp-Stable

# 2. Read current focused pane uuid
current = WarpSQLiteReader.currentFocusedPaneUUID()
if current == target_pane_uuid:
    return "Focused the matching Warp tab."

# 3. Keystroke cycle loop
max_attempts = WarpSQLiteReader.tabCountInActiveWindow() + 2
for i in 0..<max_attempts:
    CGEventPost(Cmd+Shift+])
    sleep 50ms
    current = WarpSQLiteReader.currentFocusedPaneUUID()
    if current == target_pane_uuid:
        return "Focused the matching Warp tab."

# 4. Gave up — Warp is still activated, user is on some tab, just log and return
return "Activated Warp but could not confirm precision focus (target pane may have closed)."
```

**Why Cmd+Shift+]**: Warp's default "next tab" shortcut. If the user has rebound it, the loop will still terminate because of the max_attempts cap, but will fail to land precisely. Surfacing a settings option to customize the cycle keystroke is a follow-up.

**Why the 50ms sleep between cycles**: empirically, Warp updates `windows.active_tab_index` in SQLite immediately after a tab switch, but the SQLite writer batches transactions. 50ms is conservative; we can tune down if testing shows it's stable at 20-30ms.

### Phase 3 — Permission handling

`CGEventPost` requires macOS Accessibility permission for the parent process (Agent Deck). On first jump attempt, if `AXIsProcessTrustedWithOptions` returns false:

- Show a one-time in-app prompt explaining why the permission is needed ("so Agent Deck can focus the exact Warp tab for your agent session")
- Provide a button that opens `System Settings → Privacy & Security → Accessibility` via `x-apple.systempreferences:`
- If the user denies, Phase 2 silently degrades to "Phase 2 step 1 only" (activate Warp app, no cycling) and the session remembers the denial so we don't prompt every jump

## Code changes

### New files

**`Sources/AgentDeckCore/WarpSQLiteReader.swift`** (~150 lines)

Encapsulates all SQLite access. Uses libsqlite3 via Swift's C interop (no new dependency — libsqlite3 is in the macOS SDK). Offers:

- `lookupPaneUUID(forCwd: String) -> String?` — Phase 1 discovery query
- `currentFocusedPaneUUID() -> String?` — Phase 2 focus check query
- `tabCountInActiveWindow() -> Int` — termination bound for the cycling loop
- Opens the database **read-only** (`SQLITE_OPEN_READONLY`). Never writes.
- Resolves the database path via `FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)` and then into the known Group Container subpath.
- All failures (file missing, schema mismatch, query error) log once and return nil. No throws escape.

**`Sources/AgentDeckApp/AccessibilityPermissionCoordinator.swift`** (~80 lines)

- `isTrusted() -> Bool` wrapping `AXIsProcessTrustedWithOptions(nil as CFDictionary?)`
- `requestTrustAndOpenSettings()` — calls `AXIsProcessTrustedWithOptions` with the `kAXTrustedCheckOptionPrompt` key, then opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` if still denied
- An `@Observable` flag the UI can bind to so the jump button can render a "needs permission" affordance

### Modified files

**`Sources/AgentDeckCore/JumpTarget.swift`** — add one field:
```swift
public var warpPaneUUID: String?
```
Stable field; backward-compatible decoding (nil default).

**`Sources/AgentDeckCore/ClaudeHooks.swift`** — in `withRuntimeContext`, after the existing `terminalApp` inference:
```swift
if payload.terminalApp == "Warp", payload.jumpTarget.warpPaneUUID == nil {
    payload.jumpTarget.warpPaneUUID = WarpSQLiteReader.shared.lookupPaneUUID(forCwd: payload.cwd)
}
```
Guard on `terminalApp == "Warp"` so non-Warp hosts incur zero cost.

**`Sources/AgentDeckCore/CodexHooks.swift`** — same addition, so Codex sessions in Warp get the same precision jump. (Open Code can follow in a separate slice if we want to limit scope.)

**`Sources/AgentDeckApp/TerminalJumpService.swift`** — in the `switch descriptor.bundleIdentifier` at line ~200, add:
```swift
case "dev.warp.Warp-Stable":
    if try jumpToWarpPane(target) {
        return "Focused the matching Warp tab."
    }
```
and implement `jumpToWarpPane(_:)` as a private method that performs the Phase 2 algorithm. It depends on `WarpSQLiteReader` (Core) and a new `KeystrokeInjector` helper.

**`Sources/AgentDeckApp/KeystrokeInjector.swift`** (new, ~40 lines) — thin wrapper around `CGEventCreateKeyboardEvent` / `CGEventPost` with a single public method `sendCmdShiftRightBracket()`. Isolated so it's easy to mock in tests.

### Test changes

- `Tests/AgentDeckCoreTests/WarpSQLiteReaderTests.swift` (new) — creates a temp SQLite database seeded with synthetic `windows`/`tabs`/`pane_nodes`/`terminal_panes`/`commands`/`blocks` rows reproducing the real schema, then asserts `lookupPaneUUID` and `currentFocusedPaneUUID` return the expected values for various scenarios (single window single tab, multiple tabs, non-Warp cwd, nonexistent file, etc.)
- `Tests/AgentDeckAppTests/TerminalJumpServiceTests.swift` — add tests for the Warp branch using an injected `WarpSQLiteReader` protocol stub and a `KeystrokeInjector` spy. Cover: already-at-target (no keystrokes), reaches-target-after-2-cycles, never-reaches-target (falls through cleanly).

## Verification path

### Unit tests
1. `WarpSQLiteReaderTests`: synthetic database, assert lookup correctness across: single tab, multi-tab single window, multi-window (if `app.active_window_id` varies), missing Claude command, schema mismatch (extra columns), missing file.
2. `TerminalJumpServiceTests`: injected stub reader/keystroker, assert the loop terminates on match, terminates on cap, uses the correct keystroke, reads and re-reads between each cycle.

### Manual verification (the real test)
1. In a fresh Warp window, open 4 tabs each with a different Claude Code session in a different cwd.
2. Launch the development `AgentDeckApp` build.
3. Grant Accessibility permission when prompted.
4. Click jump on the 2nd session in the Agent Deck session list while the 4th session is currently focused in Warp.
5. Observe: Warp activates, tab bar flickers through the cycles, comes to rest on the 2nd session's tab. Total elapsed < 500ms.
6. Repeat for several targets in different directions. Repeat with the target already focused (expect zero keystrokes).
7. Revoke Accessibility permission. Click jump. Verify: Warp still activates; no runtime crash; a one-line "degraded" log appears and behavior matches pre-feature state.
8. Close a tab that has a mapped pane_uuid. Click jump on its session. Verify: cycling runs for the full cap, returns the "could not confirm precision focus" result, Warp is still activated.

### Regression
- Full `swift test` must remain green.
- Manual smoke of existing Ghostty and Terminal.app jumps to verify the `TerminalJumpService.jump` dispatcher routes correctly and we didn't break other terminal handlers.

## Known risks and limitations

1. **Dependency on Warp's internal SQLite schema.** Every field this design uses (`windows.active_tab_index`, `tabs` ordering by `id`, `blocks.block_id` format, `commands.session_id` semantics) is an **undocumented implementation detail** of Warp. Warp has no stability contract on it. A Warp update that renames a column, changes the block_id format, or moves the database file will break this feature. Mitigations:
   - Every query runs inside a try/catch that falls back to the pre-feature behavior on any error.
   - A health check at startup reads one row and verifies the columns are present; if not, the feature is disabled for the session and a one-line log written.
   - We track the tested Warp version in the spec and in a README note; when a new Warp ships we re-verify.
2. **Tab reordering by drag-and-drop.** If the user drags a tab to a new position, the `tabs.id` rowid ordering may no longer match the visible tab bar order. We have not tested this. Impact: the cycling loop may settle on the wrong tab or cycle indefinitely until the cap. Mitigation: the cap terminates cleanly. Enhancement (out of scope): detect reorder by storing `tabs.id` for position `active_tab_index` and verifying it matches expectation.
3. **Pane uuid stability after "close tab, reopen same cwd".** The new tab gets a new `pane_uuid`. The stale `warpPaneUUID` stored in the session is now invalid. Next hook event rediscovers and overwrites it. There is a brief window where the wrong uuid is cached — the jump will degrade to the cap-terminated case for that window.
4. **Accessibility permission UX.** First-run users will see a macOS permission prompt. If they deny, they silently get the old degraded behavior. We must communicate this clearly in the jump button affordance and in the README/CHANGELOG.
5. **Cmd+Shift+] rebound.** A user who has remapped this keystroke will have cycling fail to cycle. The loop terminates safely on the cap. Mitigation (out of scope): add a settings field to customize the cycle keystroke, or read Warp's keybinding config from another SQLite field.
6. **Multi-window Warp.** The spec reads `app.active_window_id` and uses it, but all empirical verification was against a single-window setup. Multi-window behavior (do we activate the right window? what if the target pane is in a non-focused window?) needs explicit manual verification before the feature ships. If it doesn't work, the safe fallback is to only precision-jump when target pane is in the active window, and degrade to "activate app" otherwise.
7. **SQLite concurrent access.** WAL mode allows multiple readers without blocking the writer, and empirical testing never saw contention. Still, if a Warp transaction is in flight we may occasionally get `SQLITE_BUSY`. The reader retries with 20ms backoff up to 3 times, then gives up for that attempt.

## Explicitly out of scope

- **Open Code agent support.** This spec covers Claude Code and Codex (both emit `claude%` / `codex%` prefixed commands we can match in the `commands` table). Open Code has a different command name we haven't validated. Add in a separate slice once Claude/Codex are proven.
- **Rebindable cycle keystroke.** V1 hard-codes Cmd+Shift+]. Settings UI for customizing is a follow-up.
- **Auto-rediscovery on Warp restart.** V1 lets the next hook event refresh the mapping. If the user never fires a hook (e.g., Claude is idle), the stale uuid lingers. Active SQLite monitoring / file-watching for Warp state changes is a follow-up.
- **Tab reorder detection.** V1 terminates safely but may land on the wrong tab. Detection via `tabs.id` consistency checks is a follow-up.
- **Replacing the whole design with a native Warp API if one ships.** We will file an upstream issue requesting `warp://action/focus_cli_agent?session_id=...`. If Warp ships it, we replace Phase 2 with a 3-line URL-scheme call and remove the SQLite dependency. The Phase 1 discovery is still useful as a fallback in that world.

## Followups

1. **Upstream feature request to Warp** — draft and file a GitHub issue requesting a `warp://action/focus_cli_agent?session_id=…` URL scheme action. Point out that `CLIAgentSessionsModel` already tracks every session internally, and a public entry point would allow any external integration (not just Agent Deck) to do one-click precision jump without scraping SQLite. Reference the `claude-code-warp` plugin's current one-way integration as the motivating use case.
2. **Open Code agent support** — extend the `commands.command LIKE 'claude%'` filter to also match Open Code's entry binary. Separate slice after V1 ships.
3. **Multi-window precision** — manual test with 2+ Warp windows, add window-activation keystroke (`Cmd+` backtick or Mission Control) if needed.
4. **Settings for cycle keystroke** — expose a text field in Agent Deck settings for the cycle keystroke, default `Cmd+Shift+]`.
5. **SQLite schema version guard** — on every Warp version bump, re-verify the query still works. Automate via a startup self-test that runs the query against its own synthetic database and compares to the live one's schema.
6. **Benchmark and tune the 50ms poll delay** — try 20ms, 30ms on several machines. Lower is better UX (fewer visible tab flickers).
