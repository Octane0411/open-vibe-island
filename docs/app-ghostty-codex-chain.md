# App -> Ghostty -> Codex Chain

Reviewed on 2026-04-02 against the locally installed app bundle:

- app: `/Applications/Vibe Island.app`
- app version: `1.0.15`
- focus: how the installed app tracks and enriches Codex sessions running inside Ghostty

## Bottom Line

This chain is not implemented by plain Codex hooks alone.

The installed app appears to combine at least four local channels:

1. Codex hook ingress into `vibe-island-bridge`
2. terminal identity capture from Ghostty-provided env plus the session TTY
3. Codex rollout / session-file watching under `~/.codex/sessions`
4. Ghostty-specific title / cache / likely Accessibility-based recovery on the app side

Current best answer on the specific "sessions files vs app-server" question:

- the app is definitely using local Codex session files
- the app binary also contains Codex app-server support code paths
- but during this analysis pass we did not observe an active Codex app-server process or localhost WebSocket connection attributable to Vibe Island

So on this machine, the evidence currently favors:

- `~/.codex/sessions/.../rollout-*.jsonl` as the primary rich-state source
- app-server support as possible / optional / dormant, not proven active

High-confidence model:

```text
Ghostty tab
  -> launches shell with TERM_PROGRAM=ghostty / TERM=xterm-ghostty
  -> runs Codex CLI on a concrete tty like /dev/ttys025
  -> Codex hook calls ~/.vibe-island/bin/vibe-island-bridge --source codex
  -> bridge sends terminal + Codex metadata to /tmp/vibe-island.sock
  -> app stores session metadata in session-terminals.json
  -> app watches ~/.codex/sessions/*.jsonl for richer state deltas
  -> app updates Ghostty-facing title/cache state and uses that to recover the right tab later
```

## What Is Confirmed

### 1. Codex really runs inside Ghostty-owned TTYs

Observed Codex processes:

- `node .../bin/codex`
- vendored `codex` binary under `@openai/codex-darwin-arm64/.../codex`

Observed TTYs:

- `ttys000`
- `ttys025`
- `ttys033`

Observed inherited environment on live Codex processes:

- `TERM_PROGRAM=ghostty`
- `TERM=xterm-ghostty`
- `__CFBundleIdentifier=com.mitchellh.ghostty`
- `GHOSTTY_SHELL_FEATURES=cursor:blink,path,title`
- `PWD=<repo-root>`

That gives Vibe Island a reliable `(tool=session, tty, cwd, termProgram)` identity seed, but not a stable Ghostty tab id.

### 2. The installed app persists Codex sessions as Ghostty sessions

`~/Library/Application Support/vibe-island/session-terminals.json` currently contains multiple records like:

- `source: codex`
- `bundleIdentifier: com.mitchellh.ghostty`
- `termProgram: ghostty`
- `tty: /dev/ttys025`
- `cwd: <repo-root>`
- `codexOrigin: cli`
- `codexOriginator: codex-tui`
- `codexThreadSource: cli`
- `codexNotifyThreadId: <same session id>`
- `codexRolloutPath: ~/.codex/sessions/.../rollout-...jsonl`

This is the strongest runtime proof that the app is explicitly modeling "Codex inside Ghostty", not just "some hook fired."

### 3. The bridge helper expects both terminal metadata and Codex-specific metadata

Strings from `/Applications/Vibe Island.app/Contents/Helpers/vibe-island-bridge` show the helper knows about:

- terminal env:
  - `TERM_PROGRAM`
  - `TERM_SESSION_ID`
  - `TMUX`
  - `TMUX_PANE`
  - `KITTY_WINDOW_ID`
  - `ITERM_SESSION_ID`
  - `/dev/tty`
- Codex payload keys:
  - `codex_event_type`
  - `codex_transcript_path`
  - `codex_permission_mode`
  - `codex_session_start_source`
  - `codex_last_assistant_message`
  - `hook-session-start`
  - `hook-user-prompt-submit`
- Ghostty-specific title path:
  - `/tmp/vibe-island-osc2-title-`

That means the bridge is not just relaying a generic "hook happened" signal. It is normalizing terminal identity and Codex session fields into a local event payload.

### 4. Codex hooks are only one ingress layer

The installed-app bridge entries currently visible in `~/.codex/hooks.json` are:

- `SessionStart`
- `UserPromptSubmit`
- `Stop`

On this machine there are also extra local development hooks from the open-source repo build, but those are separate from the installed closed-source app bundle.

Even if we ignore the extra local dev hooks, the installed app bridge still only gets three Codex hook events, which is not enough by itself to explain:

- per-session last assistant message
- long-lived running / approval / idle states
- durable jump-back into the correct Ghostty tab

### 5. The app side has dedicated Codex watchers beyond hook ingress

Strings from `/Applications/Vibe Island.app/Contents/MacOS/vibe-island` show dedicated Codex integration components:

- `CodexSessionWatcher`
- `CodexSessionIndexStore`
- `CodexDesktopApprovalWatcher`
- `pendingCodexDeltas`
- `refreshingCodexTitleSessionIds`
- `waitingOnApproval`
- `thread/status/changed`
- `http://127.0.0.1:`
- `ws://127.0.0.1:0`
- `/.codex/sessions`
- `.codex/session_index.jsonl`

This strongly suggests a two-layer Codex design:

1. hooks for immediate session ingress
2. local file watching and possibly app-server / WebSocket monitoring for richer state

### 6. Codex rollout files exist and match what the app stores

The rollout paths referenced in `session-terminals.json` exist on disk under:

- `~/.codex/sessions/2026/04/02/rollout-<timestamp>-<session-id>.jsonl`

Sample contents confirm these are real Codex session streams, starting with:

- `session_meta`
- `event_msg.task_started`
- `response_item.message`

The `session_meta.payload.id` matches the `codexNotifyThreadId` stored by Vibe Island.

So the app does not have to infer session history from hooks only. It can reopen the rollout file for the same session and mine richer state directly.

### 7. Runtime evidence favors rollout-file watching over app-server

This pass added a more direct runtime comparison.

Observed facts:

- `~/Library/Logs/VibeIsland/bridge.log` only shows Codex hook ingress at:
  - `SessionStart`
  - `UserPromptSubmit`
  - `Stop`
- the current live Codex session `019d4c40-5853-7830-a34b-54b1d87ad646` now appears in `session-terminals.json`
- that record includes:
  - `status: processing`
  - `currentTool: Bash`
  - `codexRolloutPath: ~/.codex/sessions/.../rollout-2026-04-02T11-32-58-019d4c40-5853-7830-a34b-54b1d87ad646.jsonl`
  - `lastAssistantMessage` equal to a recent commentary message from this analysis session
- the matching rollout file contains the same recent:
  - `agent_message`
  - `response_item.message`
  - `function_call`
  - `exec_command_end`

That matters because the bridge log does not contain those richer events, but the rollout file does.

So the simplest explanation for the app's current live state is:

- bridge hooks bootstrap the session
- then the app reads the rollout JSONL stream for ongoing state

We also checked for active app-server evidence and did not see it:

- `vibe-island` has no child process resembling `codex app-server`
- `ps` showed no running Codex process with `app-server` arguments
- `lsof -a -p <vibe-island-pid> -iTCP -iUDP` only showed the app's proxy connection to `127.0.0.1:7897`, not a Codex localhost port
- `~/.codex/config.toml` enables `codex_hooks = true` but does not enable any app-server-specific setting
- `~/.codex/session_index.jsonl` is stale on this machine and only contains two old March sessions, so it cannot explain the app's live April session tracking

The Codex CLI definitely supports an `app-server` subcommand, and the Vibe Island binary contains strings such as:

- `enableCodexAppServer`
- `spawnAppServer(binaryPath:manager:)`
- `ws://127.0.0.1:0`
- `http://127.0.0.1:`
- `thread/status/changed`

But that is still weaker than the runtime evidence above.

Current conclusion:

- local rollout-file watching is confirmed in practice
- active app-server usage is not confirmed in practice
- app-server code likely exists as a fallback, optional integration, or future-facing path

## Ghostty-Specific Interpretation

### What Ghostty gives for free

Ghostty provides enough shell environment for the app to know:

- this session came from Ghostty
- which tty the process is attached to
- which working directory the shell is in

That is enough to index the session, but not enough to deterministically focus a specific Ghostty tab later.

### What Ghostty does not seem to give for free

From the live Codex environments we inspected, there is no obvious stable Ghostty window/tab identifier comparable to:

- VS Code terminal `processId`
- iTerm2 session ids
- Terminal AppleScript tab references

That gap explains why the app binary contains Ghostty-specific title machinery:

- `GhosttyTabCacheEntry`
- `TerminalTitleManager`
- `/tmp/vibe-island-osc2-title-`
- `/tmp/vibe-island-ghostty-title-`
- `ghosttyPid`
- `hasConfiguredGhosttyEnv`

The most likely design is:

1. use tty + Codex session id as the durable logical identity
2. push a recognizable title into the Ghostty tab via OSC 2 when possible
3. cache that title locally
4. later recover the right Ghostty UI target via title matching and/or Accessibility tree inspection

This is consistent with the app having AX-related strings and permission prompts, while the Info.plist Apple Events description only mentions Terminal and iTerm2.

## Why Plain Hooks Are Not Enough

Plain hooks can explain:

- session start
- prompt submit
- stop
- maybe a few copied fields from stdin / env

Plain hooks do not explain the full observed behavior:

- persistent session index in `session-terminals.json`
- last assistant message and rollout linkage
- `waitingOnApproval` handling
- `thread/status/changed` WebSocket hints
- Ghostty tab recovery without an AppleScript API

So the practical answer is:

- Codex hooks are the ingestion edge
- not the whole implementation

## Most Likely End-to-End Path

### Stage A. Terminal identity capture

Ghostty launches the shell and Codex inherits:

- `TERM_PROGRAM=ghostty`
- `TERM=xterm-ghostty`
- bundle id environment
- current working directory
- controlling tty

### Stage B. Hook-to-bridge handoff

Codex fires hook events and invokes:

- `~/.vibe-island/bin/vibe-island-bridge --source codex`

The wrapper then forwards into:

- `/Applications/Vibe Island.app/Contents/Helpers/vibe-island-bridge`

The helper reads stdin JSON plus terminal env, then sends a normalized payload into:

- `/tmp/vibe-island.sock`

### Stage C. App-side session model

The main app receives the event and updates its session store with:

- Ghostty bundle identity
- tty
- cwd
- Codex session id
- rollout path
- last seen messages / status

persisted to:

- `~/Library/Application Support/vibe-island/session-terminals.json`

### Stage D. Richer Codex state tracking

The app separately watches:

- `~/.codex/sessions`
- possibly `.codex/session_index.jsonl` for auxiliary indexing
- possibly a local Codex app-server / WebSocket endpoint when available

This is how it can keep up with:

- incremental assistant output
- approval-related state
- thread status transitions

### Stage E. Ghostty return path

For Ghostty, the app likely cannot rely on AppleScript.

Instead it appears to maintain Ghostty-specific title/cache state and then use:

- tty
- Ghostty process context
- cached tab titles
- possibly Accessibility inspection

to recover the correct tab or at least the correct terminal surface.

## Confidence Levels

### High confidence

- Codex in Ghostty is identified by tty plus Ghostty env
- bridge helper is a real structured ingress layer
- app persists Codex/Ghostty sessions locally
- app watches Codex session files beyond hook ingress
- current live tracking is explainable directly from rollout JSONL files
- Ghostty path uses title/cache machinery not plain AppleScript

### Medium confidence

- `ws://127.0.0.1:<port>` and `http://127.0.0.1:<port>` belong to a Codex local app-server path used for approval and thread status
- Ghostty jump-back uses Accessibility plus cached titles, not just title writes alone

### Not yet proven

- that Vibe Island is actively using Codex app-server on this machine
- the exact function that turns a clicked island item into a concrete Ghostty tab focus action
- whether Ghostty recovery is title-only, AX-only, or hybrid
- when the Codex app-server path is enabled versus falling back to file polling

## Best Next Dynamic Checks

To fully close this chain, the next dynamic pass should focus on:

1. Trigger a fresh Codex prompt in Ghostty and diff `session-terminals.json` before/after.
2. Watch whether `/tmp/vibe-island-osc2-title-*` or `/tmp/vibe-island-ghostty-title-*` appears during active Codex turns.
3. Observe whether the app opens a localhost port or WebSocket connection when Codex enters approval or running-tool states.
4. Capture the Ghostty focus/jump path at click time to see whether it goes through AX, title matching, or another local IPC route.
