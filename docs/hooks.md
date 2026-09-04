# Hook System

OpenIsland receives lifecycle events from managed hook CLIs and runtime extensions. Codex, Claude-family agents, Gemini CLI, Grok Build, and Kimi CLI invoke `OpenIslandHooks`; Pi and Oh My Pi load a TypeScript extension. Both paths forward typed payloads to the app over its Unix socket. Hook sources that support blocking can receive directives on stdout; Pi-family extensions are fire-and-forget.

## Architecture

```text
Managed hook agent                     Pi / Oh My Pi
  │ stdin: JSON payload                  │ runtime ExtensionAPI events
  ▼                                      ▼
OpenIslandHooks CLI                   open-island.ts
  │                                      │
  └──────────── Unix socket ──────────────┘
                         │
                         ▼
              BridgeServer → AppModel → UI

```
Blocking hook sources receive a `BridgeResponse` through `OpenIslandHooks` stdout. Pi-family extension events do not block the agent.

**Fail-open principle**: if the bridge is unavailable, managed hook processes exit without writing to stdout and Pi-family extensions ignore socket errors, so the agent continues running unchanged.

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

## Pi and Oh My Pi Extensions

**Payload type**: `PiHookPayload`

**Sources**: [`Sources/OpenIslandCore/PiHooks.swift`](../Sources/OpenIslandCore/PiHooks.swift), [`Sources/OpenIslandApp/Resources/open-island-pi.ts`](../Sources/OpenIslandApp/Resources/open-island-pi.ts)

Open Island installs one bundled extension per runtime:

- Pi: `~/.pi/agent/extensions/open-island.ts`
- Oh My Pi: `~/.omp/agent/extensions/open-island.ts`

The setup UI installs, refreshes, reveals, and uninstalls each extension independently. The installer writes only `open-island.ts` plus its Open Island ownership manifest; uninstall leaves other user extensions untouched.

### Event coverage

| Open Island event | Pi event | Oh My Pi event | Behavior |
|---|---|---|---|
| `SessionStart` | `session_start` | `session_start` | Creates the typed Pi/OMP session with model, transcript, working-directory, and terminal metadata |
| `UserPromptSubmit` | `before_agent_start` | `before_agent_start` | Updates the latest user prompt and marks the session running |
| `PreToolUse` | `tool_execution_start` | `tool_execution_start` | Shows the active tool and a clipped input preview |
| `PostToolUse` | `tool_execution_end` | `tool_execution_end` | Clears the active tool and records tool completion |
| `Stop` | `agent_settled` | `session_stop` | Marks the current turn completed and records the latest assistant text |
| `Heartbeat` | 15-second session timer | 15-second session timer | Refreshes only per-session liveness; it does not change turn phase, summary, tool, or message metadata |
| `SessionEnd` | `session_shutdown` | `session_shutdown` | Ends the tracked session immediately; reload shutdowns stop the timer without ending the session |

Jump-back metadata (terminal app, terminal session ID, TTY) is read from the agent process environment at event time; the extension does not forward terminal variables into child shell commands. When a prompt starts it sets `OPEN_ISLAND_ACTIVE=1` in the agent process environment, so commands the agent spawns can tell that Open Island is tracking the session. If the socket is unavailable, connection errors are ignored and agent execution continues. Pi and Oh My Pi liveness is keyed by `session_id`: heartbeat keeps or restores that specific session, a 45-second heartbeat timeout hides it after an abnormal exit, and generic process polling does not keep Pi/OMP sessions alive.

### Current limitations

- Pi and Oh My Pi extension events are fire-and-forget. Open Island does not block, approve, deny, or rewrite tool calls through these integrations.
- Runtime event objects are intentionally decoded defensively because Pi and Oh My Pi expose overlapping lifecycle concepts with some different event names.

---

## Timeout Policy

| Source | Event | Timeout |
|---|---|---|
| Codex | `PermissionRequest` | **1 hour** (awaits human approval) |
| Codex | All other managed events | **45 seconds** |
| Claude Code | `PermissionRequest` | **24 hours** (awaits human approval) |
| Claude Code | All other events | **45 seconds** |
| Gemini CLI | All events | Bridge default |
| Grok Build | All managed events | **45 seconds** |
| Pi / Oh My Pi | Heartbeat liveness | **45 seconds** |

---

## Grok Build Hooks (`--source grok`)

**Payload type**: `GrokHookPayload`
**Source**: [`Sources/OpenIslandCore/GrokHooks.swift`](../Sources/OpenIslandCore/GrokHooks.swift)

Grok Build (Grok CLI / Grok TUI) discovers hooks from `~/.grok/hooks/*.json`. Open Island writes a dedicated managed file at `~/.grok/hooks/open-island.json`.

### Events (managed install)

All of the following are registered in `~/.grok/hooks/open-island.json` by the managed installer:

| Event | Matcher | Current OpenIsland behavior |
|---|---|---|
| `SessionStart` | — | Creates / re-opens the Grok session, title, and jump target |
| `SessionEnd` | — | Marks the hook-managed session ended (`isSessionEnd`) |
| `UserPromptSubmit` | — | Marks the session running and updates summary |
| `Stop` | — | Completion when `reason == "end_turn"`; if `reason` is omitted, treat as turn completion; non-`end_turn` reasons are observe-only |
| `StopFailure` | — | Activity update, phase `.completed` (session not ended) |
| `StopCancelled` | — | Turn completion flagged `isInterrupt` — fires *instead of* `Stop` on a user interrupt (Ctrl+C / Esc), a declined or cancelled permission prompt, `--max-turns`, or a no-progress bail-out; summary is `lastAssistantMessage` when present, else derived from `reason` |
| `Notification` | `*` | Activity update; `notificationType == "idle_prompt"` settles a still-running session as completed (Grok's backstop for turns that reported no Stop-family event) and leaves an already-completed session untouched |
| `PreToolUse` | `*` | Activity update, **fire-and-forget** (no deny directive; fail-open) |
| `PostToolUse` | `*` | Activity update |
| `PostToolUseFailure` | `*` | Activity update, phase `.completed` |
| `SubagentStart` / `SubagentStop` | — | Activity updates |
| `PermissionDenied` | — | Activity update; session stays running. Fires for both a user **Reject** (a `StopCancelled` with `permission_rejected` follows and settles the turn) and a configured **PolicyDeny** rule (the model is told the tool was skipped and keeps working) |
| `PreCompact` / `PostCompact` | — | Activity updates |

Managed status is **healthy only when every event above** is present with an Open Island Grok command. A Vibe Island-only command does **not** count as installed.

### Lifecycle / liveness notes

- Non-`SessionStart` events on an **already ended** session are acknowledged and ignored (no resurrection).
- Process discovery cannot recover Grok session UUIDs. While a `grok` process is alive, Open Island keeps non-ended Grok sessions in the process-alive set (TTY/CWD match when unique; otherwise a conservative “any Grok process” fallback similar to Kimi). Explicit `SessionEnd` still ends the session.

### Wire format notes

- Stdin JSON uses **camelCase** keys (`sessionId`, `hookEventName`, `toolName`, `toolResult`).
- `hookEventName` may arrive as PascalCase (`PreToolUse`), snake_case (`pre_tool_use`) or camelCase (`preToolUse`); all are accepted.
- Envelopes may carry `promptId`; it is decoded as `promptID` but not acted on yet (reserved for ignoring stale-prompt reports).
- `StopCancelled` carries `reason` (`user_interrupt`, `permission_rejected`, `permission_cancelled`, `max_turns`, `no_progress`, `unknown`), `cancelledBy` (`user` / `runtime` / `unknown`) and optional `cancelTrigger` / `reasonDetails` / `lastAssistantMessage`.
- PreToolUse decision format (not used by the managed install yet): `{"decision":"allow"}` / `{"decision":"deny","reason":"..."}`.
- Sessions also land under `~/.grok/sessions/<url-encoded-cwd>/<session-id>/` for offline discovery (not yet scanned by Open Island).

### Install / uninstall

```bash
swift run OpenIslandSetup installGrok
swift run OpenIslandSetup statusGrok
swift run OpenIslandSetup uninstallGrok
```

Or use **Settings → Setup → Grok Build** in the app.

> If commercial Vibe Island is also installed, both may write under `~/.grok/hooks/`. Prefer one controller at a time.

---

## Hermes Agent Hooks (`--source hermes`)

**Payload type**: `HermesHookPayload`
**Source**: [`Sources/OpenIslandCore/HermesHooks.swift`](../Sources/OpenIslandCore/HermesHooks.swift)

Hermes Agent discovers shell hooks from the `hooks:` block in `~/.hermes/config.yaml` and runs each entry via `shlex.split` with `shell=False`, piping a JSON payload to stdin. Open Island appends one entry per managed event; user-authored hooks (for example a `post_tool_call` regression script) are preserved verbatim.

### Events (managed install)

| Event | Current OpenIsland behavior |
|---|---|
| `on_session_start` | Creates or re-opens the Hermes session with model/platform metadata |
| `post_llm_call` | Turn completion: marks the session completed and emits a completion card with the last user message and assistant response |
| `subagent_stop` | Marks the turn completed (subagent role shown in the summary when `child_role` is present) |
| `on_session_end` | Marks the hook-managed session ended (`isSessionEnd`) |
| `pre_tool_call` | Activity update; when `tool_name == "clarify"`, surfaces the question card and sets phase `.waitingForAnswer` (HITL) |
| `pre_approval_request` | Surfaces the approval card and sets phase `.waitingForApproval` (HITL) |

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `hook_event_name` | `hookEventName` | Event type (snake_case) |
| `session_id` | `sessionID` | Session identifier |
| `cwd` | `cwd` | Working directory |
| `tool_name` | `toolName` | Tool name (`pre_tool_call` only; `null` otherwise) |
| `tool_input` | `toolInput` | Tool arguments object (`pre_tool_call` only; `null` otherwise) |
| `extra` | `extra` | Event-specific kwargs (`user_message`, `assistant_response`, `model`, `platform`, `child_role`, `duration_ms`, …) |

`post_llm_call` completion cards read `extra.user_message` / `extra.assistant_response`; unknown `extra` keys are retained and ignored.

### Wire format notes

- Hermes runs hooks with `shlex.split` + `shell=False`, so the managed command is written YAML-single-quoted: `command: '/path/OpenIslandHooks --source hermes'`. The quotes are part of the shell-token split, not a nested shell.
- Hooks are fire-and-forget: the CLI never writes to stdout (any stdout would be parsed as a directive response). Hook failures log to stderr and fail open.
- Because every managed event fires on both CLI and gateway sessions, the bridge timeout is the standard 45 s; there is no blocking/interactive path.

### HITL (human-in-the-loop)

- `pre_tool_call` with `tool_name: "clarify"` decodes `tool_input.questions` (`question`, `header`, `options[].label/description`, `multiSelect`) into the standard question card. The notch shows the question and the session phase becomes `.waitingForAnswer`.
- `pre_approval_request` surfaces the permission card (`toolName` + `toolInput` summary) with phase `.waitingForApproval`.

### Install / uninstall

```bash
swift run OpenIslandSetup installHermes    # write hooks block into ~/.hermes/config.yaml
swift run OpenIslandSetup statusHermes     # report whether managed hooks are present
swift run OpenIslandSetup uninstallHermes  # remove managed entries, preserve user-authored hooks
```

Or use **Settings → Setup → Hermes** in the app.

> After install, Hermes asks for first-use consent per `(event, command)` pair; approve once (or set `hooks_auto_accept: true`, which Open Island does not change). The status hint in the notch disappears once the managed hooks block is detected in `~/.hermes/config.yaml`.

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
| [`Sources/OpenIslandHooks/OpenIslandHooksCLI.swift`](../Sources/OpenIslandHooks/OpenIslandHooksCLI.swift) | Hook CLI entry point — routes to Codex, Claude, Gemini, Grok, … |
| [`Sources/OpenIslandCore/CodexHooks.swift`](../Sources/OpenIslandCore/CodexHooks.swift) | Codex payload model, output encoder, terminal detection |
| [`Sources/OpenIslandCore/ClaudeHooks.swift`](../Sources/OpenIslandCore/ClaudeHooks.swift) | Claude Code payload model, directive types, output encoder |
| [`Sources/OpenIslandCore/GeminiHooks.swift`](../Sources/OpenIslandCore/GeminiHooks.swift) | Gemini CLI payload model, terminal detection, metadata helpers |
| [`Sources/OpenIslandCore/GrokHooks.swift`](../Sources/OpenIslandCore/GrokHooks.swift) | Grok Build payload model, terminal detection, lifecycle summaries |
| [`Sources/OpenIslandCore/GrokHookInstaller.swift`](../Sources/OpenIslandCore/GrokHookInstaller.swift) | Writes `~/.grok/hooks/open-island.json` |
| [`Sources/OpenIslandCore/PiHooks.swift`](../Sources/OpenIslandCore/PiHooks.swift) | Pi/OMP payload model and session metadata helpers |
| [`Sources/OpenIslandCore/PiExtensionInstallationManager.swift`](../Sources/OpenIslandCore/PiExtensionInstallationManager.swift) | Installs and removes the runtime-specific TypeScript extension |
| [`Sources/OpenIslandCore/PiSessionRegistry.swift`](../Sources/OpenIslandCore/PiSessionRegistry.swift) | Persists recent Pi and OMP sessions |
| [`Sources/OpenIslandApp/Resources/open-island-pi.ts`](../Sources/OpenIslandApp/Resources/open-island-pi.ts) | Shared Pi/OMP runtime extension |
| [`Sources/OpenIslandCore/BridgeServer.swift`](../Sources/OpenIslandCore/BridgeServer.swift) | Unix socket server — handles incoming hook payloads |
| [`Sources/OpenIslandCore/BridgeTransport.swift`](../Sources/OpenIslandCore/BridgeTransport.swift) | Protocol codec and envelope types |
