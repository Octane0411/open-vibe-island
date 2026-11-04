# Open Island DSH companion

Dependency-free host and browser companion for DSH 0.2.1-rc.3 and compatible 0.2 releases. It observes live sessions and relays one narrow action: select a conversation in the installed DSH Web PWA and focus its composer. No build step, subprocess hook, or live user configuration change is required to prepare the package.

## Install explicitly

Prefer Settings > Setup > DSH (Web profile) in Open Island. It installs a managed local bundle with both JavaScript files and preserves unrelated profile settings. Restart the DSH host and reload the installed PWA afterward. A host restart alone does not invalidate the browser client-module cache.

For other profiles, use the Open Island setup CLI documented in the [hook guide](../../../../docs/hooks.md#deepseek-harness-dsh-plugin), or install this package directly from the repository as an alternative. Use one installation method per profile to avoid duplicate observers:

```sh
dsh plugin --profile web add "file:$PWD/Sources/OpenIslandApp/Resources/open-island-dsh"
```

Use the actual profile name for other hosts. Restart that profile if it does not support host plugin reload. This command changes the selected DSH profile only when a person runs it.

The app installer reconstructs a persistent managed package from the bundled JavaScript and generated Cordis metadata. It registers the bundle in the existing profile manifest without running `dsh plugin` or rewriting user YAML. Its managed package name is `open-island-dsh`. SwiftPM may flatten the source resources, so installation does not depend on the original package directory surviving in the app bundle.

Remove a managed installation through Open Island Settings. Remove a direct package installation with:

```sh
dsh plugin --profile web remove open-island-dsh
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

DSH exposes committed `approval/asked` and `approval/decided` audit events. Its `approval/request` and `user-questions/ask` APIs are answerer waterfalls, not passive notification feeds. The companion does not register either waterfall, answer questions, grant approvals, switch policies, control tools, or execute arbitrary UI scripts. The only native command accepted is conversation focus.

Session end delivery is best-effort during abrupt process exit. A session that remains loaded in a Web host is live even when its browser tab is disconnected. Unloading this plugin emits `SessionEnd` for its observation lifetime even if DSH itself continues running. Reload emits a new start. Historical prompts and in-flight tool calls are not replayed on plugin attachment. Transcript paths and exact terminal jump metadata are not available through the session APIs used here and are omitted. Delivery is not acknowledged or persisted.

## Conversation focus protocol

The package and Cordis patch identity are `open-island-dsh`. The package exports `./client`, whose file registers a lazy `window.__ModuleLoader__.load` factory with that same ID, not raw ESM. Its web injection metadata lists these package IDs:

- `@deepseek-ai/dsh-client-connection`
- `@deepseek-ai/dsh-api-session-controller`
- `@deepseek-ai/dsh-client-ui-workspace`
- `@deepseek-ai/dsh-client-ui-conversation`

The client requires services `connection`, `sessions`, `uiWorkspace`, and `conversation`. Host `connection` and `webApp` are optional, so sessions-only CLI profiles retain lifecycle observation without a focus listener.

Web hosts publish optional lifecycle fields only after the endpoint is ready:

- `web_origin`: credential-free loopback HTTP origin with a trailing slash
- `web_focus_socket`: `/tmp/oi-dsh-focus-<random>/focus.sock`

The parent directory is owned by the host user with mode `0700`. Its socket has the same owner and mode `0600`. Both are checked before publication. macOS may resolve `/tmp` to `/private/tmp`. Native first activates the matching installed PWA, then connects to this exact socket and writes one UTF-8 NDJSON line:

```json
{"session_id":"target-session-id"}
```

Read one response line, either `{"ok":true}` or `{"ok":false,"error":"safe-code"}`. Error codes are `invalid-request`, `not-found`, `no-client`, `timeout`, `busy`, `disposed`, `superseded`, and `focus-failed`. Input is capped at 8 KiB, with at most 16 local connections and 16 registered clients. Requests finish within 5.8 seconds from connection acceptance. New valid requests replace older focus work instead of queuing stale clicks. Unknown and disposed host sessions cannot be opened.

The listener is unreferenced so it cannot keep a CLI process alive. Disposal closes connections and polls. Node removes its bound socket on close, then the companion removes only its verified own empty directory. It never scans for sockets or recursively removes directories. The private random parent prevents replacement by other users. Processes running as the same user remain inside the local trust boundary, including Node's automatic unlink behavior.

### Browser routing

The relay uses existing authenticated Connection RPC at `/open-island-dsh`, with endpoints `poll`, `ack`, and `leave`. It does not create another HTTP server. The host accepts only the existing browser owner Peer, not authenticated API principals. Acknowledgements must match the current random request ID and selected client ID.

Only standalone, fullscreen, or minimal-ui display modes register. Fullscreen is necessary because DSH's shipped manifest requests it. Mini windows, mini previews, and standard browser display mode are excluded. Browser display-mode APIs cannot attest installed application identity, so native installed-app matching and activation remain necessary.

Clients report focus epochs through one-second polls. The host selects the most recently focused eligible client, never broadcasts to all tabs, and expires registrations after 3.5 seconds without a poll. A cold client can register while a request waits. Once delivered, a request is not redirected to a different client.

The client calls public `uiWorkspace.openSession(id)`, borrows `sessions.scope(id)`, and calls `conversation.input.for(scope).focus()`. It yields to rendering and retries for a mounted editor. Success requires the target to retain its public `mainView` reference, a focused document, and the composer to hold keyboard focus. Newer selections invalidate older asynchronous focus work. Drafts are never modified.

## Tests

From the repository root:

```sh
node --test Tests/DshPluginTests/*.test.mjs
```

Normalization and real Unix socket tests require only Node. To also run the real Cordis and SessionStore lifecycle tests, use an installed DSH package as the dependency anchor:

```sh
DSH_PACKAGE_ROOT="$(npm root -g)/@deepseek-ai/dsh" node --test Tests/DshPluginTests/*.test.mjs
```

The integration tests use real published Cordis and SessionStore classes, create live sessions and detached history, and verify cleanup on disposal, id reuse, optional web activation, and plugin unload. Real Unix sockets exercise NDJSON validation, cold registration, latest-request selection, stale acknowledgements, timeouts, and private endpoint permissions. Browser tests execute the actual closure factory with public-service doubles and delayed composer mounts. A child process verifies that loaded sessions and an unavailable bridge cannot keep the host alive. Tests requiring installed APIs are explicitly skipped without the dependency anchor or locally resolvable DSH packages.

Installed Chrome PWA activation and actual React editor rendering still require a manual end-to-end check after installation and restart.
