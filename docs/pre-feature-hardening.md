# Open Island Hardening Before New Features

Continue development of the existing native macOS application, but complete the core safety and reliability work below before adding features. Preserve the session reducer, existing regression fixtures, and agent and terminal compatibility code. Address defects through small changes with regression tests; a full rewrite is not a prerequisite.

This plan covers incorrect approvals, configuration damage, unreliable communication, session races, privacy behavior, test isolation, and release safeguards. Optional remote approvals and terminal replies require additional protection before they can be enabled safely.

## Baseline and evidence

- Review date: October 31, 2026.
- Source baseline: upstream commit [`01aa0924fd96bf319a64e75646765c55cae4e2c5`](https://github.com/Octane0411/open-vibe-island/tree/01aa0924fd96bf319a64e75646765c55cae4e2c5), also the fork's starting commit.
- H01 and H15 are implemented and locally verified on the hardening branch. All other findings remain open unless the implementation record below says otherwise.
- Source references point to the reviewed commit so their line numbers remain stable as the fork changes.

The baseline package built on Apple Silicon with macOS 26.6.1 and Swift 6.4. Documentation and localization checks passed, as did 78 selected tests across 14 suites. The selected suites covered payloads, transcript processing, registries, subprocess behavior, and related model logic. They do not establish full application, GUI, remote-device, Intel, or macOS 14 compatibility.

Evidence labels distinguish three levels:

- **Reproduced:** an isolated probe exercised the implementation and observed the defect. Configuration probes used temporary directories; transport probes used mocked messages or a local socket pair.
- **Source traced:** the defect follows from the inspected control flow, but its complete user-facing scenario still needs an automated regression test.
- **Engineering gap:** a missing protection or verification step, with a concrete acceptance criterion. This is not a claim that exploitation has been demonstrated.

The full test suite was not run on the developer's live environment because H01 identifies tests that can touch production state. No signed release artifact was independently audited. Dependency versions resolved during the review do not establish versions embedded in previously published downloads.

## Implementation record

### H01 — implemented, locally verified

Resolving commit: `6ebc913` (`fix: isolate automated tests from user state (H01)`).

The bridge compatibility listener is now an explicit production option. App tests use unique preferences and temporary registry storage, a headless panel controller, and injected terminal actions. The live Warp check requires explicit opt-in; the payload inference test supplies a terminal locator instead of querying iTerm. Pending registry writes are cancelled when their coordinator is released.

Verification on October 31, 2026: Swift 6.4, macOS 26.6.1, Apple Silicon. The full Swift Testing run reported 355 core tests in 37 suites and 177 app tests in 24 suites passing. The Warp check was skipped and Ghostty integration check cancelled by its opt-in guard. Production registry bytes/metadata and socket identities were unchanged across the completed run. New tests cover independent preferences, all five injected registry paths, and an existing compatibility listener alongside two test servers. Documentation and whitespace checks passed. See [test isolation guidance](./quality.md#test-isolation).

An initial run was stopped after discovering an unisolated iTerm AppleScript query; that test now injects its locator and the completed rerun has no live terminal interaction. GUI, permission-dialog, and other platform checks remain outside this verification.

### H13 — dependency locking implemented; remaining work open

Resolving commit for dependency locking: `d4f4c7a` (`build: lock tested dependency versions (H13)`).

`Package.resolved` records the four locally tested dependency versions. Test, harness-build, and packaging entry points require those resolutions. Sparkle's minimum is raised to the already-tested 2.10.1 so a future resolution cannot fall back to the old 2.9.0 floor. [Upstream advisories](https://github.com/sparkle-project/Sparkle/security/advisories) were rechecked on October 31, 2026; their listed patched versions are at or below 2.9.6.

Verification: the locked package build and test wrapper passed locally; shell syntax, documentation, and localization checks passed. Packaging was checked for syntax only, not signed or distributed.

This is only the dependency-locking portion of H13. The toolchain/platform matrix, action and packaging-tool pinning, signed packaging, GUI checks, and mobile validation remain open.

### H15 — implemented, locally verified

A controllable dismissal delay reproduced the old behavior: selecting B before A's delay finished executed B and then A. The regression now passes with only B executed. Cancellation errors leave before dispatch, and a serial executor checks cancellation again before invoking the platform runner. A second regression verifies that a running A completes before B starts and cannot overwrite B's final status.

An OS action that has already started is not forcibly interrupted or undone; later actions wait for it. This defines ordering without claiming that every existing terminal driver is preemptible. Both cancellation/ordering tests passed with fake platform runners; no real terminal was activated.

## Completion gates

| Gate | Required outcome |
| --- | --- |
| Core | Complete before new feature implementation. A passing regression test and reviewed implementation close each item. |
| Conditional | Complete before the affected optional capability is enabled or advertised as supported. Deferral requires an enforced runtime restriction and clear product documentation; a default-off preference alone is insufficient. |
| Release | Complete before distributing a fork build or activating its update channel. |

P1 means incorrect authorization, unintended input, configuration damage, or a significant trust-boundary failure is possible. P2 covers reliability, privacy, and verification defects that still need scheduled remediation. These are engineering priorities, not CVSS scores.

| ID | Work item | Priority | Gate |
| --- | --- | --- | --- |
| H01 | Isolate automated tests from the developer environment | P1 | Core |
| H02 | Bind approvals and answers to exact requests | P1 | Core |
| H03 | Acknowledge decisions before clearing the interface | P2 | Core |
| H04 | Preserve agent configuration during installation | P1 | Core |
| H05 | Repair the OpenCode protocol contract | P1 | Core |
| H06 | Bound bridge reads, writes, and connections | P2 | Core |
| H07 | Enforce local bridge identity and command permissions | P1 | Core |
| H08 | Preserve live state during startup discovery | P2 | Core |
| H09 | Verify the destination before submitting terminal replies | P1 | Conditional |
| H10 | Secure remote pairing and approvals | P1 | Conditional |
| H11 | Fix remote endpoint lifecycle and request processing | P2 | Conditional |
| H12 | Restrict diagnostics and remote Markdown content | P2 | Core |
| H13 | Make builds and compatibility checks reproducible | P2 | Core and Release |
| H14 | Give the fork a safe release and update configuration | P1 | Release |
| H15 | Stop cancelled terminal jumps before side effects | P2 | Core |
| H16 | Preserve and correctly merge SSH hook configuration | P2 | Conditional |

## Core fixes

### H01 Isolate automated tests

**Evidence: Source traced.** A bridge started with a custom test socket also attempts to bind the production legacy socket. Some application tests schedule persistence through stores with production default paths. A keystroke test invokes the real Warp controller, which activates the app and clicks its tab menu. Test execution can therefore interfere with a running app, overwrite session registries, or change desktop focus.

Sources: [BridgeServer.swift:114–127](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeServer.swift#L114-L127), [SessionDiscoveryCoordinator.swift:44–57](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/SessionDiscoveryCoordinator.swift#L44-L57), [AppModel.swift:1582–1586](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/AppModel.swift#L1582-L1586), [KeystrokeInjectorTests.swift:5–12](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Tests/OpenIslandAppTests/KeystrokeInjectorTests.swift#L5-L12).

Inject storage locations, preferences, socket locations, clocks, and platform command runners. Make the legacy socket an explicit production option. Put real desktop interactions in a separately invoked integration suite.

**Acceptance criteria**

- The ordinary suite uses temporary stores and sockets, with no production registry writes, integration installs, terminal activation, or permission prompts.
- Two suites can run concurrently without sharing sockets or persistent state.
- A sentinel production socket and sentinel registry files remain unchanged during test execution.
- Real OS integration tests require explicit invocation and an isolated test environment.

### H02 Bind decisions to exact requests

**Evidence: Source traced.** Approval commands identify only the session. Pending Claude and OpenCode interactions are also keyed by session, so request B can replace request A. A delayed decision for A can then resolve B. The Watch relay receives a request ID but forwards only the session ID and decision.

Sources: [BridgeTransport.swift:82–86](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeTransport.swift#L82-L86), [BridgeServer.swift:758–787](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeServer.swift#L758-L787), [OpenCode pending request storage](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeServer.swift#L1144-L1167), [WatchNotificationRelay.swift:157–175](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/WatchNotificationRelay.swift#L157-L175).

Carry an immutable request ID, session identity, and decision through the UI, protocol, remote relay, and pending-request store. Define expiration, cancellation, and concurrent-request behavior. Version the protocol change and define compatibility with installed older helpers.

**Acceptance criteria**

- With A and B pending in one session, approving A never approves B; neither waiter is silently overwritten.
- Stale, expired, cancelled, duplicate, unknown, and wrong-session responses have explicit outcomes.
- Desktop and remote clients use the same request identity rules.
- Unsupported protocol versions cannot silently convert a decision into an approval.

### H03 Confirm decision delivery

**Evidence: Source traced.** The UI clears approvals and questions before sending. A send failure only changes status text. The local client treats a successful socket write as completion and does not await a matching application response.

Sources: [AppModel.swift:1428–1444](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/AppModel.swift#L1428-L1444), [answer and error handling](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/AppModel.swift#L1484-L1530), [LocalBridgeClient.swift:72–98](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/LocalBridgeClient.swift#L72-L98).

Introduce pending, sending, acknowledged, failed, and expired states. An acknowledgment must describe acceptance of the exact request, not merely successful byte delivery. Retry using the same decision identity and deduplicate on the receiving side.

**Acceptance criteria**

- Disconnecting before or during delivery does not leave a false success state or silently discard a still-actionable request.
- Server rejection and timeout produce an actionable error.
- Retrying after an uncertain acknowledgment cannot apply the decision twice or resolve another request.

### H04 Preserve configuration during installation

**Evidence: Reproduced.** The Codex editor fails to recognize a valid commented table header and appends another table. For example:

```toml
[features] # optional settings
hooks = false
```

Installation adds a second `[features]` table. An independent TOML parser rejected the generated result. Separately, OpenCode installation treats malformed JSON as an empty dictionary and replaces the active configuration with a plugin-only object. A backup is written, but the invalid input is not reported as an installation failure.

Sources: [CodexHookInstaller.swift:201–220](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/CodexHookInstaller.swift#L201-L220), [table recognition](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/CodexHookInstaller.swift#L415-L424), [Codex configuration write](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/CodexHookInstallationManager.swift#L88-L122), [OpenCodePluginInstallationManager.swift:153–180](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/OpenCodePluginInstallationManager.swift#L153-L180).

Use syntax-aware editing and distinguish a missing file from an unreadable or invalid file. Validate all proposed outputs before replacing any active configuration. Preserve unrelated settings, detect concurrent edits, and make partial installation recoverable. Audit the other installers for the same patterns rather than assuming these two are the only affected adapters.

**Acceptance criteria**

- Commented headers, quoted keys, unrelated tables, and existing user hooks survive install and uninstall.
- Invalid or unreadable input fails without modifying configuration or installed helper/plugin files.
- Repeated installation is idempotent; uninstall removes only managed entries.
- A concurrent edit is detected rather than overwritten.
- Simulated write failure leaves a consistent previous state or a documented, tested recovery path.

### H05 Repair the OpenCode protocol contract

**Evidence: Reproduced transport defects; source-traced answer loss.** The JavaScript client assumes the second received line is a response. The server broadcasts events to every client, including request producers. The client also parses an incomplete second line and closes the connection. Isolated execution of the actual function returned an event for `hello + event + response`, and returned `null` for a partial response.

Structured answers have a separate defect: the server flattens multiple answers into display text, then the plugin sends that text as a single answer array. Question order and multiple selections are lost.

Sources: [open-island-opencode.js:36–61](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/Resources/open-island-opencode.js#L36-L61), [BridgeServer.swift:3324–3331](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeServer.swift#L3324-L3331), [answer flattening](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeServer.swift#L2413-L2439), [answer submission](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/Resources/open-island-opencode.js#L347-L360).

Parse complete frames with streaming UTF-8 decoding, inspect envelope types, and wait for the correlated response. Deliver observer events only to authorized subscribers. Preserve typed answers in source question order. Validate the plugin against explicitly supported OpenCode versions; the source defects above are separate from upstream API compatibility.

**Acceptance criteria**

- A real Swift bridge and JavaScript client complete permission and question round trips using isolated sockets.
- Fragmentation at every byte boundary, including multibyte characters, and interleaved events do not lose a response.
- Two questions and multiple selected answers round-trip without flattening or reordering.
- Disconnect and timeout leave the underlying agent in its documented fallback state.

### H06 Bound bridge resource use

**Evidence: Reproduced writer blocking; source-traced limits gap.** `writeAll` retries `EAGAIN` indefinitely. The server calls it on a shared serial queue, so a non-reading client can stall unrelated sessions. A socket-pair probe remained blocked beyond 300 ms and stopped when the peer closed. Source inspection establishes the missing deadline; the probe was not a full application denial-of-service test. Incoming frame buffers and connection counts also need explicit bounds.

Sources: [BridgeTransport.swift:454–474](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeTransport.swift#L454-L474), [BridgeServer.swift:267–297](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeServer.swift#L267-L297), [shared write path](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeServer.swift#L3311-L3331).

Use asynchronous writes with bounded per-client queues and deadlines. Set documented limits for frames, connections, pending work, and idle clients. Choose limits from representative valid payload fixtures, including large transcripts.

**Acceptance criteria**

- A stalled client cannot prevent a second client from completing a request within the documented deadline.
- Oversized or unterminated frames and excess clients are rejected with bounded memory use.
- Disconnect, timeout, and shutdown cancel work and release descriptors and pending requests.

### H07 Enforce local bridge trust boundaries

**Evidence: Engineering gap confirmed in source.** Socket creation does not explicitly enforce private permissions or peer credentials. Command handling does not establish distinct authority for a hook producer, observer, and decision controller. A process able to connect can submit decision commands. The legacy path also needs safe ownership and stale-socket handling.

Sources: [BridgeServer.swift:124–169](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeServer.swift#L124-L169), [accepted clients](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeServer.swift#L215-L264), [command dispatch](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/BridgeServer.swift#L315-L353).

Define and enforce the supported trust boundary. Use a private directory, explicit socket permissions, peer UID checks, and an ownership check before removing a stale socket. Keep UI decision control in process where practical, or grant it separate authenticated authority. A client-supplied role string alone is not authentication.

**Acceptance criteria**

- An unauthorized peer cannot subscribe to events or resolve requests.
- A hook producer cannot gain controller authority merely by changing a message field.
- Starting another instance cannot silently replace a live listener or remove an unrelated path.
- Document same-user limitations: this is not a general sandbox against arbitrary code already running as the account owner. The default Unix socket is not a remote network endpoint.

### H08 Preserve live state during startup

**Evidence: Source traced.** Startup discovery runs asynchronously while the bridge begins receiving events. Applying a nonempty cached Codex list later replaces the entire current state, discarding live sessions or approvals received during discovery.

Sources: [AppModel.swift:1131–1137](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/AppModel.swift#L1131-L1137), [bridge startup](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/AppModel.swift#L1173-L1175), [SessionDiscoveryCoordinator.swift:156–159](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/SessionDiscoveryCoordinator.swift#L156-L159).

Seed state before accepting events or merge discovery results beneath newer live state. Define precedence using event/source identity and ordering; avoid relying solely on wall-clock timestamps.

**Acceptance criteria**

- Delay discovery, deliver a new session and approval, then complete discovery: both remain present and actionable.
- Cached records cannot restore an older phase over a newer live phase or resurrect an ended session.
- The authoritative store and bridge view remain consistent after startup and reconnect.

### H12 Restrict sensitive diagnostics and remote content

**Evidence: Source traced.** The OpenCode plugin logs portions of every event's properties to a predictable `/tmp` file without opt-in, explicit private permissions, redaction, or rotation. Completion Markdown uses the resolved MarkdownUI dependency's default network image provider, so rendering agent output can request remote images. This network behavior was traced through the dependency, not exercised with a live tracking endpoint. The privacy policy describes substantially less storage and external communication than the application supports.

Sources: [debug log destination](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/Resources/open-island-opencode.js#L8-L10), [logged event properties](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/Resources/open-island-opencode.js#L318-L323), [completion Markdown](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/Views/IslandPanelView.swift#L1776-L1784), [privacy policy](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/PRIVACY_POLICY.md#L9-L22).

Disable payload diagnostics by default. Use private bounded storage and redact sensitive values when diagnostics are enabled. Block remote image loading unless the user chooses it. Document caches, retention, diagnostics, remote devices, and update traffic accurately.

**Acceptance criteria**

- Sensitive fixture prompts and tool inputs do not appear in default diagnostics.
- Rendering Markdown containing remote images performs no network request by default, including inline images.
- Tests verify diagnostic permissions, size/retention limits, and redaction.
- Privacy documentation describes the implemented behavior and available deletion controls.

### H15 Respect cancelled terminal jumps

**Evidence: Source traced.** Cancelling the previous jump task does not prevent its action. Cancellation during the delay is swallowed, detached work starts anyway, and the cancellation check occurs after the window operation.

Source: [AppModel.swift:1390–1412](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/AppModel.swift#L1390-L1412).

Check cancellation before side effects and serialize platform actions. Use bounded, cancellable subprocess operations where possible.

**Acceptance criteria**

- With a controllable clock and fake runner, selecting A then B during the dismissal delay invokes only B.
- Work already dispatched has defined cancellation behavior and cannot apply a later stale focus change after B completes.

## Optional capability fixes

### H09 Verify terminal reply destinations

**Evidence: Source traced.** The reply path falls back from a missing Ghostty session ID to the first directory/title match, then sends text and Enter. It does not revalidate that the intended agent still owns the terminal. A stale session can therefore send input to another pane or to a shell. The feature defaults off, but saved preferences can enable it.

Source: [TerminalTextSender.swift:82–147](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/TerminalTextSender.swift#L82-L147).

Require a current exact terminal identity and validate the recipient immediately before submission. Refuse stale or ambiguous targets. Prefer an agent input API when available. Process checks and text injection are not inherently atomic, so document and address the remaining race rather than treating a PID lookup as a complete guarantee.

**Acceptance criteria**

- Closing the original pane, duplicating its directory/title, or returning to a shell never causes fallback text submission.
- A changed recipient between validation and submission is handled safely to the extent supported by the terminal API; unsupported cases disable submission.
- Test tmux as well as Ghostty, including reused pane identities and terminated agents.

### H10 Secure remote approval access

**Evidence: Source traced.** The optional phone/Watch endpoint advertises a plaintext TCP service and pairs using a four-digit code, without attempt throttling or explicit Mac confirmation. Bearer tokens authorize decisions. An attacker able to intercept traffic can obtain a token; a reachable client can repeatedly guess pairing codes. Remote support defaults off.

Sources: [WatchHTTPEndpoint.swift:113–124](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/WatchHTTPEndpoint.swift#L113-L124), [listener](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/WatchHTTPEndpoint.swift#L206-L240), [pairing](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/WatchHTTPEndpoint.swift#L305-L329), [decision endpoint](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/WatchHTTPEndpoint.swift#L403-L416).

Use authenticated encryption with a verified peer identity, explicit pairing confirmation, bounded pairing attempts, and device-specific credentials. Store secrets in platform credential storage. Separate notification access from approval authority and define expiry and revocation behavior.

**Acceptance criteria**

- An unpaired or revoked device cannot read events or submit decisions.
- Pairing resists repeated guesses and active peer impersonation, not just passive observation.
- Approval requests use H02's exact identity and H03's acknowledgment semantics.
- Enabling the feature clearly communicates its reach and capabilities; disabling it closes all listeners and connections.

### H11 Correct remote endpoint behavior

**Evidence: Source traced.** Revoking tokens leaves existing event streams connected. `/status` calls a `MainActor.assumeIsolated` closure from the networking queue, which can fail the actor isolation assertion. Request parsing assumes a single TCP receive contains a complete HTTP request.

Sources: [token revocation and event delivery](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/WatchHTTPEndpoint.swift#L179-L200), [HTTP receive](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/WatchHTTPEndpoint.swift#L254-L271), [status callback](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandCore/WatchHTTPEndpoint.swift#L419-L428), [actor assumption](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Sources/OpenIslandApp/AppModel.swift#L536-L541).

Associate streams with device credentials and cancel them on revocation. Read session counts through an explicit synchronized snapshot or actor hop. Use bounded incremental HTTP parsing with complete body handling, or a maintained server implementation appropriate to the product.

**Acceptance criteria**

- A revoked open stream receives no subsequent events.
- Authenticated `/status` calls from the real endpoint succeed without an isolation assertion.
- Fragmented headers/bodies, malformed lengths, oversized requests, and slow clients are handled predictably with deadlines.
- Stop/start cycles cannot leave orphan connections or restart a listener after the user disables it.

### H16 Correct SSH hook merging

**Evidence: Source traced.** The SSH setup script deduplicates `command` on hook groups even though commands are nested inside `hooks`. Existing and new groups can both appear to have a missing command, causing the new integration to be skipped.

Source: [remote-setup.sh:78–92](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/scripts/remote-setup.sh#L78-L92).

Merge using the actual nested schema and preserve unrelated hooks. Apply the configuration integrity rules from H04. The legacy socket path is intentionally supported by the bridge and is not itself a confirmed SSH defect.

**Acceptance criteria**

- A fixture with existing user hooks receives the Open Island entries without losing those hooks.
- A second installation creates no duplicate entries.
- Invalid input is preserved and reported; removal affects only managed entries.

## Build and distribution fixes

### H13 Reproduce builds and verify supported environments

**Evidence: Engineering gap.** The manifest uses dependency version ranges and `.gitignore` excludes `Package.resolved`. CI uses a single macOS runner family and omits GUI smoke tests. Passing on Swift 6.4 does not verify the declared Swift 6.2 minimum, macOS 14 runtime, Intel hardware, or mobile targets.

Sources: [Package.swift](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/Package.swift), [ignored lockfile](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/.gitignore#L13-L17), [CI workflow](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/.github/workflows/ci.yml#L15-L39), [documented harness gaps](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/docs/quality.md).

The review resolved MarkdownUI 2.4.1, Sparkle 2.10.1, NetworkImage 6.0.1, and swift-cmark 0.9.0. Record these as historical evidence, not an indefinite approval of those versions. Sparkle's lower permitted versions include releases affected by [GHSA-3x7w-j75x-ppq5](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-3x7w-j75x-ppq5), fixed in 2.9.6. Recheck current advisories when selecting the fork's lockfile.

**Acceptance criteria**

- Commit `Package.resolved`; clean CI builds use the recorded resolutions and a declared toolchain.
- Pin workflow actions to reviewed revisions and record packaging tool versions.
- Run the full isolated suite after H01, including JavaScript/Swift contract tests from H05.
- Add GUI and permission-denied checks in a suitable environment. Record the tested OS, architecture, terminal, and agent versions; narrow support claims where coverage is unavailable.
- Validate mobile builds and remote round trips before enabling phone/Watch support.

### H14 Protect the fork release channel

**Evidence: Source traced and engineering gap.** Packaging defaults to the upstream Sparkle feed and public key. A fork build must not unintentionally offer upstream replacements. The release workflow also merges update metadata before creating a draft release, so it can advertise assets before they are publicly available. This is a workflow defect, not a claim that the current published appcast is broken.

Sources: [package-app.sh:127–130](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/scripts/package-app.sh#L127-L130), [release.yml:181–224](https://github.com/Octane0411/open-vibe-island/blob/01aa0924fd96bf319a64e75646765c55cae4e2c5/.github/workflows/release.yml#L181-L224).

Choose the fork's bundle identity, signing identity, update feed, and update signing key. Keep updates disabled until that configuration exists. Inventory shared cache, helper, socket, and configuration ownership before claiming the fork can coexist with upstream. Preserve required license notices and define the fork's distribution approach before release.

**Acceptance criteria**

- A packaged fork build has the intended identity and never contacts the upstream update feed by accident.
- Release validation covers the exact source commit, dependency resolutions, signatures, bundle resources, and notarization result.
- Create and verify assets first; publish them and confirm anonymous download access before promoting the appcast or package-manager metadata.
- Failed or draft releases do not become offered updates.
- An upgrade test verifies signature acceptance, application replacement, helper compatibility, and recovery from an interrupted update.

## Implementation sequence

1. **Make verification safe:** H01, then the dependency-locking portion of H13. Establish one repeatable baseline command and record existing failures without suppressing them.
2. **Protect decisions and configuration:** H02, H03, H04, and H05. Add failing regression tests before changing these behaviors. Keep protocol migration and existing helper compatibility explicit.
3. **Stabilize the local runtime:** H06, H07, H08, H12, and H15. Verify resource bounds, state ordering, and permission-denied behavior.
4. **Decide optional capability readiness:** complete H09–H11 and H16, or enforce their disabled/unsupported status while recording the deferral. Update existing preferences safely so a previously enabled capability cannot bypass the restriction.
5. **Complete distribution checks:** finish H13 and H14 before shipping a fork build. Run the selected platform and compatibility matrix against the release candidate.

Each implementation change should reference its finding ID, include a regression test or concrete manual verification procedure, and record the resolving commit or PR. Update the register status when the acceptance criteria are satisfied. Keep separate PRs focused on one coherent change; do not combine a broad interface rewrite with a safety fix.

## Architecture direction

Use these fixes to establish one serialized owner of session and pending-request state. Discovery and agent adapters should emit typed events; the UI should send request-scoped decisions; transport and terminal operations should execute bounded effects through testable interfaces.

Preserve `SessionState.apply` and useful regression fixtures. Extract agent adapters and terminal drivers as the affected areas change. Large files are evidence of concentrated responsibility, but splitting every large file is not an exit criterion for this milestone.

Hooks intentionally fail open when the application is unavailable. Preserve the underlying agent's own permission behavior and document this boundary. Open Island must not be presented as a mandatory security enforcement layer.

## Exit criteria before new features

- [ ] Every Core item is resolved with its acceptance criteria verified.
- [ ] Conditional capabilities are either verified or explicitly restricted in code and documentation, including previously saved enablement preferences.
- [x] The full ordinary test suite runs without modifying real user state or controlling desktop applications on the locally verified environment.
- [ ] Request identity, delivery acknowledgment, installer preservation, fragmented messages, startup ordering, and stalled clients have regression coverage.
- [ ] Supported agent and terminal versions are recorded, with known limitations visible.
- [ ] Remaining Release items have named follow-up work and block distribution until complete.
- [ ] The resolving changes and verification results are linked from this plan; passing the original 78-test subset alone does not close the milestone.
