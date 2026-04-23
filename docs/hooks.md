# Hook System

OpenIsland receives hook events from AI agents (Codex / Claude Code / Gemini CLI) via the `OpenIslandHooks` CLI. The CLI forwards payloads to the app over a Unix socket and, when necessary, writes a directive back to stdout so the agent can act on it (e.g. block a tool call).

## Architecture

```
Agent (Codex / Claude Code / Gemini CLI)
  │  stdin: JSON payload
  ▼
OpenIslandHooks CLI  (--source codex | --source claude | --source gemini)
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

**Entry point**: [`Sources/OpenIslandHooks/main.swift`](../Sources/OpenIslandHooks/main.swift)

---

## Codex Hooks (`--source codex`)

**Payload type**: `CodexHookPayload`  
**Source**: [`Sources/OpenIslandCore/CodexHooks.swift`](../Sources/OpenIslandCore/CodexHooks.swift)

### Events

| `hook_event_name` | When it fires | Notable fields |
|---|---|---|
| `SessionStart` | Session starts or resumes (`source: "resume"` on resume) | `source`, `session_id`, `transcript_path` |
| `PreToolUse` | Before a shell command executes | `tool_name`, `tool_input.command`, `turn_id`, `tool_use_id` |
| `PostToolUse` | After a shell command completes | `tool_name`, `tool_input`, `tool_response`, `turn_id` |
| `UserPromptSubmit` | User submits a new prompt | `prompt`, `turn_id` |
| `Stop` | A turn completes | `last_assistant_message`, `stop_hook_active` |

Current Codex source in `~/work/codex` defines the raw wire payload with `session_id` and `transcript_path`, and those values identify the same rollout thread. `terminal_*` fields are not currently part of the raw Codex schema; `OpenIslandHooks` enriches them at runtime before forwarding the payload to the app.

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `cwd` | `cwd` | Working directory |
| `hook_event_name` | `hookEventName` | Event type |
| `session_id` | `sessionID` | Session UUID; matches the rollout thread identity in current Codex source |
| `model` | `model` | Model name |
| `permission_mode` | `permissionMode` | `default` / `acceptEdits` / `plan` / `dontAsk` / `bypassPermissions` |
| `transcript_path` | `transcriptPath` | JSONL transcript file path |
| `terminal_app` | `terminalApp` | Runtime-enriched terminal name (`Terminal`, `Ghostty`, `iTerm`, …) |
| `terminal_session_id` | `terminalSessionID` | Runtime-enriched terminal session identifier |
| `terminal_tty` | `terminalTTY` | Runtime-enriched TTY device path |
| `terminal_title` | `terminalTitle` | Runtime-enriched tab / window title |
| `turn_id` | `turnID` | Current turn ID |
| `tool_name` | `toolName` | Tool name (e.g. `shell`) |
| `tool_use_id` | `toolUseID` | Tool-use call ID |
| `tool_input` | `toolInput` | Tool input (contains `command`) |
| `tool_response` | `toolResponse` | Tool output (JSON) |
| `prompt` | `prompt` | User prompt text |
| `last_assistant_message` | `lastAssistantMessage` | Last assistant message |
| `stop_hook_active` | `stopHookActive` | Whether the stop hook is active |

### Directive response (PreToolUse only)

The app can block a command by writing this to stdout:

```json
{"decision": "block", "reason": "Blocked by Open Island"}
```

All other events require no stdout response.

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

## Timeout Policy

| Source | Event | Timeout |
|---|---|---|
| Codex | All events | Bridge default |
| Claude Code | `PermissionRequest` | **24 hours** (awaits human approval) |
| Claude Code | All other events | **45 seconds** |
| Gemini CLI | All events | Bridge default |

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
