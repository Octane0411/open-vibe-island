# Hook System

OpenIsland receives hook events from AI agents (Codex / Claude Code / Gemini CLI) via the `OpenIslandHooks` CLI, and from Pi via the official Pi Extension API. The hook CLI or extension forwards payloads to the app over a Unix socket and, when necessary, writes a directive back so the agent can act on it (e.g. block a tool call).

## Architecture

```
Agent (Codex / Claude Code / Gemini CLI)
  │  stdin: JSON payload
  ▼
OpenIslandHooks CLI  (--source codex | --source claude | --source gemini)
  │  Unix socket
  ▼
BridgeServer → AppModel → UI

Pi
  │  TypeScript Extension API events
  ▼
open-island-pi.ts extension
  │  Unix socket
  ▼
BridgeServer → AppModel → UI
  │  BridgeResponse
  ▼
OpenIslandHooks CLI
  │  stdout: JSON directive (only when a response is needed)
  ▼
Agent
```

**Fail-open principle**: if the bridge is unavailable the hook process exits silently without writing to stdout, so the agent continues running unaffected.

## Skip Hooks For Delegated Control

Set `OPEN_ISLAND_SKIP_HOOKS=1` on a child agent process when another local controller intentionally owns permission handling for that run. The hook CLI exits immediately without reading or forwarding the payload, so the agent continues without Open Island UI intervention.

`VIBE_ISLAND_SKIP=1` is also recognized as a legacy compatibility alias.

This is meant for per-process launches. Do not set it globally unless you want Open Island hooks disabled for every agent started from that environment.

**Entry point**: [`Sources/OpenIslandHooks/main.swift`](../Sources/OpenIslandHooks/main.swift)

---

## Codex Hooks (`--source codex`)

**Payload type**: `CodexHookPayload`  
**Source**: [`Sources/OpenIslandCore/CodexHooks.swift`](../Sources/OpenIslandCore/CodexHooks.swift)

### Events

| `hook_event_name` | When it fires | Notable fields |
|---|---|---|
| `SessionStart` | Session starts or resumes (`source: "resume"` on resume) | `prompt`, `source` |
| `PreToolUse` | Before a shell command executes | `tool_name`, `tool_input.command`, `turn_id`, `tool_use_id` |
| `PermissionRequest` | Codex requests permission for a tool/action | `tool_name`, `tool_input`, `turn_id` |
| `PostToolUse` | After a shell command completes | `tool_name`, `tool_input`, `tool_response`, `turn_id` |
| `UserPromptSubmit` | User submits a new prompt | `prompt` |
| `Stop` | A turn completes | `last_assistant_message`, `stop_hook_active` |

### Default managed installation

The managed Codex hook installer (`CodexHookInstaller`) installs `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, and `Stop` by default. This keeps the lifecycle hooks low-noise while still allowing OpenIsland to broker Codex's first-class approval requests. Per-command `PreToolUse` / `PostToolUse` hooks remain opt-in because they can add terminal log noise.

The installer chooses the Codex hook feature flag that the local Codex CLI advertises. Newer Codex builds use `[features].hooks = true`; older builds use the legacy `[features].codex_hooks = true`. Status checks recognize both keys, and managed installs migrate between them when the local Codex version changes.

After hooks are installed or changed, Codex may require a manual trust review before running them. Open `/hooks` inside Codex CLI and approve the expected Open Island hook entries. This approval gate belongs to Codex and is not bypassed by Open Island.

The `CodexHookPayload` model and `BridgeServer` can parse richer events (`PreToolUse`, `PostToolUse`) when they are present in the hook payload, and will surface them in the UI if received. However, these per-tool lifecycle events are **not** installed by the managed installer and must be configured manually if desired.

> **Note on file-edit coverage**: Codex file edits may use internal apply-patch paths that do not emit `PreToolUse` events. File-edit approval should not be treated as guaranteed `PreToolUse` coverage; the current reliable coverage is command/shell-level events, depending on Codex hook configuration.

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `cwd` | `cwd` | Working directory |
| `hook_event_name` | `hookEventName` | Event type |
| `session_id` | `sessionID` | Session UUID |
| `model` | `model` | Model name |
| `permission_mode` | `permissionMode` | `default` / `acceptEdits` / `plan` / `dontAsk` / `bypassPermissions` |
| `transcript_path` | `transcriptPath` | JSONL transcript file path |
| `terminal_app` | `terminalApp` | Terminal name (`Terminal`, `Ghostty`, `iTerm`, …) |
| `terminal_session_id` | `terminalSessionID` | Terminal session identifier |
| `terminal_tty` | `terminalTTY` | TTY device path |
| `terminal_title` | `terminalTitle` | Tab / window title |
| `turn_id` | `turnID` | Current turn ID |
| `tool_name` | `toolName` | Tool name (e.g. `shell`) |
| `tool_use_id` | `toolUseID` | Tool-use call ID |
| `tool_input` | `toolInput` | Tool input (commonly includes `command` and/or `description`) |
| `tool_response` | `toolResponse` | Tool output (JSON) |
| `prompt` | `prompt` | User prompt text |
| `last_assistant_message` | `lastAssistantMessage` | Last assistant message |
| `stop_hook_active` | `stopHookActive` | Whether the stop hook is active |

### Directive responses

#### `PreToolUse`

The app can block a command by writing this to stdout:

```json
{"decision": "block", "reason": "Blocked by Open Island"}
```

#### `PermissionRequest`

The managed `PermissionRequest` hook has a 1-hour timeout so the user can approve or deny from the UI.

Allow:

```json
{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow"
    }
  }
}
```

Deny:

```json
{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "User denied the permission request"
    }
  }
}
```

All other Codex events require no stdout response.

---

## Claude Code Hooks (`--source claude`)

**Payload type**: `ClaudeHookPayload`  
**Source**: [`Sources/OpenIslandCore/ClaudeHooks.swift`](../Sources/OpenIslandCore/ClaudeHooks.swift)

### Events

| `hook_event_name` | When it fires | Directive response |
|---|---|---|
| `SessionStart` | Session starts (`startup` / `resume` / `clear` / `compact`) | None |
| `SessionEnd` | Session ends | None |
| `UserPromptSubmit` | User submits a prompt | None |
| `PreToolUse` | Before a tool call | **Yes** — allow / deny / modify input |
| `PostToolUse` | After a successful tool call | None |
| `PostToolUseFailure` | After a failed tool call | None |
| `PermissionRequest` | Agent requests user approval | **Yes** — allow or deny (24 h timeout) |
| `PermissionDenied` | A permission was denied | None |
| `Notification` | Agent emits a notification | None |
| `Stop` | Turn ends normally | None |
| `StopFailure` | Turn ends with an error | None |
| `SubagentStart` | A sub-agent starts | None |
| `SubagentStop` | A sub-agent stops | None |
| `PreCompact` | Before context compaction | None |

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `cwd` | `cwd` | Working directory |
| `hook_event_name` | `hookEventName` | Event type |
| `session_id` | `sessionID` | Session UUID |
| `transcript_path` | `transcriptPath` | JSONL transcript file path |
| `permission_mode` | `permissionMode` | Permission mode |
| `model` | `model` | Model name |
| `agent_id` | `agentID` | Sub-agent ID (SubagentStart/Stop) |
| `agent_type` | `agentType` | Sub-agent type |
| `source` | `source` | Start source (`startup` / `resume` / `clear` / `compact`) |
| `tool_name` | `toolName` | Tool name |
| `tool_input` | `toolInput` | Tool input parameters (JSON) |
| `tool_use_id` | `toolUseID` | Tool-use call ID |
| `tool_response` | `toolResponse` | Tool output (JSON) |
| `permission_suggestions` | `permissionSuggestions` | Suggested permission changes (PermissionRequest) |
| `prompt` | `prompt` | User prompt text |
| `message` | `message` | Notification message body |
| `title` | `title` | Notification title |
| `notification_type` | `notificationType` | Notification type |
| `stop_hook_active` | `stopHookActive` | Whether the stop hook is active |
| `last_assistant_message` | `lastAssistantMessage` | Last assistant message |
| `error` | `error` | Error message (Failure events) |
| `error_details` | `errorDetails` | Extended error details |
| `is_interrupt` | `isInterrupt` | Whether the event is an interrupt |
| `agent_transcript_path` | `agentTranscriptPath` | Sub-agent transcript path |
| `terminal_app` | `terminalApp` | Terminal name |
| `terminal_session_id` | `terminalSessionID` | Terminal session identifier |
| `terminal_tty` | `terminalTTY` | TTY device path |
| `terminal_title` | `terminalTitle` | Tab / window title |

### PreToolUse directive response

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow" | "deny" | "ask",
    "permissionDecisionReason": "reason shown to the agent",
    "updatedInput": { ... },
    "additionalContext": "extra context injected into the turn"
  }
}
```

| Field | Description |
|---|---|
| `permissionDecision` | `allow` — proceed; `deny` — block; `ask` — let the agent ask the user |
| `permissionDecisionReason` | Human-readable reason forwarded to the agent |
| `updatedInput` | Replace the tool's input parameters (optional) |
| `additionalContext` | Inject additional context into the turn (optional) |

### PermissionRequest directive response

The `PermissionRequest` event has a **24-hour timeout** to allow the user to review and approve in the UI.

Allow:

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedInput": { ... },
      "updatedPermissions": [ ... ]
    }
  }
}
```

Deny:

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "User denied the permission request",
      "interrupt": false
    }
  }
}
```

Setting `interrupt: true` terminates the current agent turn immediately.

---

## Gemini CLI Hooks (`--source gemini`)

**Payload type**: `GeminiHookPayload`  
**Source**: [`Sources/OpenIslandCore/GeminiHooks.swift`](../Sources/OpenIslandCore/GeminiHooks.swift)

### Events

| `hook_event_name` | When it fires | Current OpenIsland behavior |
|---|---|---|
| `SessionStart` | Session starts or resumes | Creates or restores the Gemini session, title, jump target, and transcript metadata |
| `BeforeAgent` | Gemini starts handling a prompt / turn | Marks the session running, updates prompt text, refreshes terminal metadata |
| `AfterAgent` | Gemini finishes a turn | Marks the turn completed and emits a completion card |
| `SessionEnd` | Gemini reports the session ended | Marks the hook-managed session ended and removes it from active visibility |
| `Notification` | Gemini emits a notification message | Updates the session summary / activity text without blocking the agent |

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `cwd` | `cwd` | Working directory |
| `hook_event_name` | `hookEventName` | Event type |
| `session_id` | `sessionID` | Session identifier |
| `transcript_path` | `transcriptPath` | Gemini transcript file path |
| `timestamp` | `timestamp` | Hook timestamp |
| `prompt` | `prompt` | User prompt text |
| `prompt_response` | `promptResponse` | Gemini response text |
| `source` | `source` | Session start source |
| `reason` | `reason` | Session-end reason |
| `notification_type` | `notificationType` | Notification category |
| `message` | `message` | Notification message |
| `details` | `details` | Structured notification payload |
| `stop_hook_active` | `stopHookActive` | Whether Gemini stop hook support is active |
| `terminal_app` | `terminalApp` | Terminal name |
| `terminal_session_id` | `terminalSessionID` | Terminal session identifier |
| `terminal_tty` | `terminalTTY` | TTY device path |
| `terminal_title` | `terminalTitle` | Tab / window title |

### Current feature coverage

- Session lifecycle ingestion for Gemini CLI via `OpenIslandHooks --source gemini`
- Session list and island visibility updates from Gemini hook events
- Prompt / response metadata capture for completion cards and session details
- Terminal jump metadata enrichment for Terminal.app, iTerm2, Ghostty, and other supported terminals
- Process-assisted liveness matching so active Gemini CLI sessions can stay visible even when hook traffic is sparse

### Current limitations

- Gemini hooks are currently treated as fire-and-forget. OpenIsland does not send Gemini-specific approval or modification directives back to stdout.
- Gemini hook payloads sometimes include a duplicated copy of the final response body, often with whitespace-only differences. OpenIsland applies a best-effort compatibility pass before rendering completion content, but the result is not guaranteed to be perfect for every response shape.
- Gemini support is currently limited to the hook events and UI/session behaviors listed above. It does not yet match the richer permission / interaction flows available for Claude Code or OpenCode.

---

## Pi Extension

**Payload type**: `PiHookPayload`  
**Source**: [`Sources/OpenIslandCore/PiHooks.swift`](../Sources/OpenIslandCore/PiHooks.swift) and [`Sources/OpenIslandApp/Resources/open-island-pi.ts`](../Sources/OpenIslandApp/Resources/open-island-pi.ts)

Pi has no native Open Island hook or approval system. Open Island support is implemented through Pi's official TypeScript Extension API and does not patch Pi internals.

### Events

| Pi extension event | Open Island event | Behavior |
|---|---|---|
| `session_start` | `SessionStart` | Creates or restores a Pi session row |
| timer while Pi is alive | `Heartbeat` | Recreates the row after Open Island restarts without guessing from process lists |
| `input` | `UserPromptSubmit` | Marks the session running with prompt preview |
| `agent_start` | `AgentStart` | Marks the session running |
| `tool_call` | `PreToolUse` | For `bash`, `edit`, and `write`, blocks until Open Island returns allow/deny |
| `tool_result` | `PostToolUse` | Updates activity after tool completion |
| `agent_end` | `Stop` | Marks the turn completed |
| `session_shutdown` | `SessionEnd` | Marks the Pi session ended |

### Install

Copy the bundled extension to Pi's global extension directory and reload Pi:

```bash
mkdir -p ~/.pi/agent/extensions
cp Sources/OpenIslandApp/Resources/open-island-pi.ts ~/.pi/agent/extensions/open-island.ts
# inside Pi: /reload
```

The extension talks directly to `OPEN_ISLAND_SOCKET_PATH` when set, otherwise to Open Island's stable per-user socket at `~/Library/Application Support/OpenIsland/bridge.sock`.

### Directive response

For blocking `PreToolUse` events, BridgeServer returns a normal bridge response envelope. The Pi extension reads `response.response.type === "piHookDirective"` and then applies `response.response.directive`:

```json
{"type":"response","response":{"type":"piHookDirective","directive":{"type":"allow"}}}
```

or:

```json
{"type":"response","response":{"type":"piHookDirective","directive":{"type":"deny","reason":"Denied by Open Island"}}}
```

The extension maps a deny directive to Pi's blocking extension return value:

```ts
return { block: true, reason: "Denied by Open Island" }
```

---

## Timeout Policy

| Source | Event | Timeout |
|---|---|---|
| Codex | `PermissionRequest` | **1 hour** (awaits human approval) |
| Codex | All other managed events | **45 seconds** |
| Claude Code | `PermissionRequest` | **24 hours** (awaits human approval) |
| Claude Code | All other events | **45 seconds** |
| Gemini CLI | All events | Bridge default |
| Pi Extension | `PreToolUse` for blocking approval tools | **24 hours** (awaits human approval) |
| Pi Extension | All other events | Bridge default |

---

## Terminal Auto-detection

The hook process infers the terminal type from environment variables at runtime:

| Environment variable | Inferred terminal |
|---|---|
| `ITERM_SESSION_ID` or `LC_TERMINAL=iTerm2` | `iTerm` |
| `CMUX_WORKSPACE_ID` or `CMUX_SOCKET_PATH` | `cmux` |
| `GHOSTTY_RESOURCES_DIR` | `Ghostty` |
| `WARP_IS_LOCAL_SHELL_SESSION` | `Warp` |
| `TERM_PROGRAM=Apple_Terminal` | `Terminal` |
| `TERM_PROGRAM=WezTerm` | `WezTerm` |

For iTerm, Terminal, and Ghostty the process additionally runs an AppleScript query to obtain the session ID, TTY, and window title — used to power the "jump back to terminal" feature. The `cmux` terminal uses `CMUX_SURFACE_ID` instead of AppleScript.

---

## Related source files

| File | Responsibility |
|---|---|
| [`Sources/OpenIslandHooks/main.swift`](../Sources/OpenIslandHooks/main.swift) | Hook CLI entry point — routes to Codex, Claude, or Gemini path |
| [`Sources/OpenIslandCore/CodexHooks.swift`](../Sources/OpenIslandCore/CodexHooks.swift) | Codex payload model, output encoder, terminal detection |
| [`Sources/OpenIslandCore/ClaudeHooks.swift`](../Sources/OpenIslandCore/ClaudeHooks.swift) | Claude Code payload model, directive types, output encoder |
| [`Sources/OpenIslandCore/GeminiHooks.swift`](../Sources/OpenIslandCore/GeminiHooks.swift) | Gemini CLI payload model, terminal detection, metadata helpers |
| [`Sources/OpenIslandCore/BridgeServer.swift`](../Sources/OpenIslandCore/BridgeServer.swift) | Unix socket server — handles incoming hook payloads |
| [`Sources/OpenIslandCore/BridgeTransport.swift`](../Sources/OpenIslandCore/BridgeTransport.swift) | Protocol codec and envelope types |
