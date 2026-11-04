# Open Island DSH host plugin

Dependency-free ESM host plugin for DSH 0.2.1-rc.3 and compatible 0.2 releases. No build step, browser plugin, subprocess hook, or live user configuration change is required to prepare the package.

## Install explicitly

Prefer Settings > Setup > DSH (Web profile) in Open Island. It installs a managed local bundle and preserves unrelated profile settings. Restart DSH afterward.

For other profiles, use the Open Island setup CLI documented in the [hook guide](../../../../docs/hooks.md#deepseek-harness-dsh-plugin), or install this package directly from the repository as an alternative. Use one installation method per profile to avoid duplicate observers:

```sh
dsh plugin --profile web add "file:$PWD/Sources/OpenIslandApp/Resources/open-island-dsh"
```

Use the actual profile name for other hosts. Restart that profile if it does not support host plugin reload. This command changes the selected DSH profile only when a person runs it.

The app installer reconstructs a persistent managed package from the bundled JavaScript and generated Cordis metadata. It registers the bundle in the existing profile manifest without running `dsh plugin` or rewriting user YAML. Its managed package name is `open-island-dsh`. SwiftPM may flatten the source resources, so installation does not depend on the original package directory surviving in the app bundle.

Remove a managed installation through Open Island Settings. Remove a direct package installation with:

```sh
dsh plugin --profile web remove dsh-plugin-open-island
```

## Public host APIs

The Cordis entry exports `name`, `inject = ['sessions']`, and `apply(ctx, config)`. It uses `ctx.on`, `ctx.effect`, `ctx.sessions.list()`, and `ctx.sessions.get(id)`. Session metadata uses `session.id`, `session.header.cwd`, and the incremental `session.requestHeader()` fold.

It subscribes to `session/created`, `session/event`, and `session/disposed`. Initial enumeration includes only loaded live Session objects. Detached persisted sessions and the host process itself never produce heartbeats. Each live Session object owns its heartbeat timer, tool-call correlation, model metadata, and latest assistant text. A disposed object cannot be revived by another session reusing its id. Plugin unload ends all observed sessions and clears every timer.

| DSH event | Open Island lifecycle |
| --- | --- |
| Session creation or existing live session at plugin load | `SessionStart` |
| `user/message` with `source.kind = 'user'` | `UserPromptSubmit` |
| `tool/call` | `PreToolUse` |
| `tool/result` | `PostToolUse` |
| `turn/end`, including cancellation and failure | `Stop` |
| Timer while exact Session object remains in the store | `Heartbeat` |
| Session disposal or plugin unload | `SessionEnd` |

Injected context is not a user prompt. Assistant reasoning, attachments, and tool outputs are not forwarded. Text previews and raw tool argument strings are capped at 4096 characters. The session id is the native DSH id, without an extra prefix. No guessed terminal or process identity is attached to Web sessions.

## Bridge transport

Each observation is one newline-terminated JSON command:

```json
{"type":"command","command":{"type":"processDshHook","dshHook":{"hook_event_name":"PreToolUse","session_id":"session-id","cwd":"/workspace","model":"deepseek/model-id","tool_name":"bash","tool_input":"{\"command\":\"pwd\"}"}}}
```

The snake_case payload follows the Pi lifecycle contract without its `agent` field. Optional fields are `prompt`, `tool_name`, `tool_input`, `last_assistant_message`, and `model`. `Stop` describes turn completion, not session disposal.

Socket selection matches `BridgeSocketLocation.currentURL`: `OPEN_ISLAND_SOCKET_PATH`, then `VIBE_ISLAND_SOCKET_PATH`, then the per-user `Library/Application Support/OpenIsland/bridge.sock`. There is no automatic fallback to the old temporary socket.

The sender preserves observation order with a bounded FIFO of 64 pending frames. Connections have a 500 ms absolute deadline and do not await acknowledgements. Socket errors, missing apps, malformed local transport configuration, and backlog overflow drop observations. They never block agent callbacks, alter results, retry stale events, or change permission policy. Later observations reconnect, so a subsequent heartbeat can recover after Open Island starts. Plugin disposal drains best-effort for at most 500 ms.

Optional Cordis row settings are `socketPath` and `heartbeatIntervalMs`. `OPEN_ISLAND_HEARTBEAT_INTERVAL_MS` also configures the timer, defaulting to 15000 ms. Invalid, fractional, non-positive, or oversized intervals use the default. Timers and sockets are unreferenced so they do not keep the host process alive.

## Safety and limitations

This first version is observe-only. DSH exposes committed `approval/asked` and `approval/decided` audit events. Its `approval/request` and `user-questions/ask` APIs are answerer waterfalls, not passive notification feeds. The plugin does not register either waterfall, answer questions, grant approvals, switch policies, or accept app commands.

Session end delivery is best-effort during abrupt process exit. A session that remains loaded in a Web host is live even when its browser tab is disconnected. Unloading this plugin emits `SessionEnd` for its observation lifetime even if DSH itself continues running. Reload emits a new start. Historical prompts and in-flight tool calls are not replayed on plugin attachment. Transcript paths and exact terminal jump metadata are not available through the session APIs used here and are omitted. Delivery is not acknowledged or persisted.

## Tests

From the repository root:

```sh
node --test Tests/DshPluginTests/*.test.mjs
```

Normalization and real Unix socket tests require only Node. To also run the real Cordis and SessionStore lifecycle tests, use an installed DSH package as the dependency anchor:

```sh
DSH_PACKAGE_ROOT="$(npm root -g)/@deepseek-ai/dsh" node --test Tests/DshPluginTests/*.test.mjs
```

The integration tests use real published DSH classes, create multiple live sessions and detached history, and verify timer cleanup on session disposal, id reuse, and plugin unload. A child process also verifies that loaded sessions and an unavailable bridge cannot keep the host alive. Without the dependency anchor or locally resolvable DSH packages, these two API integration tests are explicitly skipped.
