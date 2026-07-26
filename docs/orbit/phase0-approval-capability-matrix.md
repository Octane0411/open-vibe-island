# Orbit Phase 0: Cross-Agent Approval Capability Audit

**Status:** Phase 0 audit complete; request-ID implementation and contract tests pending
**Date:** 2026-07-26
**Scope:** Existing Orbit/Open Island bridge and hook paths only. This audit does not add a second approval system or claim T3 Code compatibility.

## Executive finding

Orbit already has provider-specific approval and question handling. The safe implementation path is to strengthen those existing bridge paths, not create a parallel inbox or make Orbit the enforcement authority.

The critical defect is request addressing:

- `BridgeServer` stores pending interactions in the session-keyed maps `pendingApprovals`, `pendingClaudeInteractions`, `pendingOpenCodeInteractions`, and `pendingCursorInteractions`.
- `BridgeCommand.resolvePermission` carries only `sessionID` and `PermissionResolution`.
- Client disconnect cleanup also removes pending work by session ID.
- Incoming payloads can expose stronger request identity, including Codex/Claude tool-use IDs and Claude's `permissionCorrelationKey`, but that identity is not propagated through the response command.

Therefore, two outstanding requests from one session can overwrite one another or be resolved ambiguously. Session identity is suitable for grouping and display, not decision correlation.

## Capability classifications

| Classification | Meaning |
|---|---|
| **User-brokered** | Orbit can hold the originating request, show a decision, and return a provider directive. |
| **Adapter path present; verification required** | The source shares a directive-capable decoder/encoder, but deterministic per-agent enforcement evidence is not yet recorded. |
| **Auto-directed** | A blocking directive transport exists, but current Orbit behavior does not ask the user. |
| **Fire-and-forget** | Orbit ingests state but does not return an approval decision. |
| **Unverified optional** | No compatibility claim or product dependency is permitted. |

## Agent capability matrix

| Agent | Entry point and event format | Current blocking/decision behavior | Correlation today | Timeout and disconnect behavior | Verification status | Required next action |
|---|---|---|---|---|---|---|
| **Codex CLI** | `OpenIslandHooks --source codex`; `CodexHookPayload`; managed `PermissionRequest` | **User-brokered.** Returns `CodexHookDirective` allow/deny. Managed file-edit coverage is not guaranteed because internal apply-patch paths may not emit `PreToolUse`. | Payload may include `turnID` and `toolUseID`; pending map and response command use `sessionID`. | Permission hook waits 1 hour. Bridge/client loss fails open and removes pending state; no allow may be inferred. | Existing focused hook/session tests; simultaneous same-session request fixture missing. | Propagate opaque request ID through ingress, UI event, resolve command, and adapter delivery. |
| **Claude Code** | `OpenIslandHooks --source claude`; `ClaudeHookPayload`; `PreToolUse` and `PermissionRequest` | **User-brokered.** Returns `ClaudeHookDirective` allow/deny/ask or updated input where supported. | Payload has `toolUseID` and `permissionCorrelationKey`; pending map and response command use `sessionID`. | Permission request waits 24 hours; other hooks 45 seconds. Disconnect removes pending state. | Existing directive tests; simultaneous same-session fixture missing. | Preserve provider correlation while adding Orbit request ID; separately test PreToolUse and PermissionRequest semantics. |
| **OpenCode** | JS/plugin bridge; `OpenCodeHookPayload`; permission and question events | **User-brokered.** Returns `OpenCodeHookDirective` allow/deny/answer. | Pending interaction and resolution use `sessionID`. | Pending plugin disconnect removes interaction. Current timeout behavior must be captured in a deterministic fixture. | Existing permission/question tests; request-addressing fixture missing. | Add request-ID addressing without merging permission and question semantics. |
| **Cursor** | `OpenIslandHooks --source cursor`; `CursorHookPayload`; blocking shell/MCP hooks | **Auto-directed today.** Transport can return `CursorHookDirective`, but current `beforeShellExecution` and `beforeMCPExecution` handlers return `.allow` immediately rather than showing Orbit approval UI. | Pending Cursor type exists and resolver uses `sessionID`; current auto-allow path does not establish user-brokered coverage. | Blocking CLI timeout is 24 hours; disconnect cleanup exists for pending interactions. | Directive codec/path exists; user-brokered fixture absent. | Do not label supported approval until an explicit product decision and deterministic allow/deny fixture exist. |
| **Gemini CLI** | `OpenIslandHooks --source gemini`; `GeminiHookPayload` | **Fire-and-forget.** Session/activity ingestion only; no Gemini-specific decision directive is returned. | Session identity only; no approval request contract. | Bridge default/45-second CLI send; failure is ignored/fail-open. | Documented lifecycle coverage. | Keep UI truth explicit: display-only/unavailable for response until Gemini exposes and Orbit implements a blocking contract. |
| **Qoder** | Claude-format path via `--source qoder`; source is retained in `hookSource` and resolves to `.qoder` | **Adapter path present; verification required.** Shared Claude directive encoder is capable, but per-agent enforcement is not proven by the shared decoder alone. | Same session-keyed Claude interaction path. | Claude-format permission timeout is 24 hours; disconnect removes pending state. | Source dispatch exists; deterministic live/fixture proof missing. | Add source-specific payload/directive fixture before claiming enforceable approval. |
| **Qwen Code** | Claude-format path via `--source qwen`; resolves to `.qwenCode` | **Adapter path present; verification required.** | Same session-keyed Claude interaction path. | Same shared Claude timeout/disconnect behavior. | Source dispatch exists; deterministic live/fixture proof missing. | Add source-specific payload/directive fixture. |
| **Factory / Droid** | Claude-format path via `--source factory` or `--source droid`; resolves to `.factory` | **Adapter path present; verification required.** | Same session-keyed Claude interaction path. | Same shared Claude timeout/disconnect behavior. | Source dispatch exists; deterministic live/fixture proof missing. | Add source-specific payload/directive fixture and verify current vendor event names. |
| **CodeBuddy** | Claude-format path via `--source codebuddy`; resolves to `.codebuddy` | **Adapter path present; verification required.** | Same session-keyed Claude interaction path. | Same shared Claude timeout/disconnect behavior. | Source dispatch exists; deterministic live/fixture proof missing. | Add source-specific payload/directive fixture. |
| **Kimi CLI** | Claude-format runtime via `--source kimi`; dedicated TOML installer currently installs lifecycle, `PreToolUse`, and `PostToolUse` hooks | **Adapter path present; verification required.** The managed installer does not currently install `PermissionRequest`, so shared decoding does not prove first-class approval coverage. | Same session-keyed Claude interaction path when an interactive event is received. | Managed installer uses 45 seconds; CLI uses 24 hours only for a received `PermissionRequest`. Disconnect removes pending state. | Byte-compatible path documented; first-class permission fixture/config coverage missing. | Verify Kimi's supported event/directive contract before changing installer events or claiming approval support. |
| **T3 Code** | No verified public hook, extension API, IPC protocol, CLI callback, or licensed add-on surface recorded | **Unverified optional investigation.** | None. | Unknown. | No compatibility evidence. | Keep Orbit independent. Investigate only from public documentation/source and record license/protocol evidence before recommending an adapter. |

## Existing source boundary

The implementation must preserve these responsibilities:

- **Origin adapter:** owns provider payloads, provider-specific scope semantics, directive encoding, delivery, and enforcement.
- **Orbit bridge:** correlates a request, projects safe metadata, captures one user decision, routes it back to the originating adapter, and records delivery state.
- **Orbit UI:** presents provider, capability, redacted resource, scope, consequence, expiry, and truth state; it does not imply unsupported scope or successful enforcement.
- **Session state:** groups requests for presentation but does not identify a decision target.

## Minimum safe request-ID seam

The next implementation slice should modify the existing bridge rather than add a new inbox:

1. Generate an opaque `ApprovalRequestID` at ingress.
2. Retain an `ApprovalCorrelation` containing request ID, adapter/source, session ID, and provider correlation/tool-use ID when available.
3. Key pending interactions by request ID. Maintain a secondary session index only for grouping and cleanup.
4. Change permission resolution to address `requestID`, retaining `sessionID` only as display/context metadata.
5. Permit exactly one terminal user decision per request.
6. Treat an identical repeated decision as idempotent and reject a conflicting second decision.
7. Track user decision, adapter delivery, and provider acknowledgement as separate states.
8. Treat expiry, cancellation, stale correlation, disconnect, adapter rejection, or delivery failure as non-allowing terminal outcomes.
9. Store bounded/redacted resource metadata in Orbit records; retain raw provider payload ownership at the adapter boundary.
10. Keep current fail-open hook behavior explicit. A missing Orbit bridge must never be misrepresented as an Orbit approval or denial.

## Required contract fixtures

Tests for the request-ID slice must exercise the existing bridge seam:

- two simultaneous requests from one session remain independently addressable;
- provider tool-use/correlation identity survives ingress and response routing;
- one request cannot resolve another request in the same session;
- repeated identical decisions are idempotent;
- conflicting second decisions are rejected;
- expiry, stale correlation, cancellation, disconnect, and delivery failure never become allow;
- decision capture, directive delivery, and acknowledgement remain distinct;
- projected request/receipt metadata excludes raw prompts, commands, credentials, and provider payloads;
- each Claude-format source has a deterministic payload/directive fixture before being labeled enforceable;
- Cursor remains auto-directed and Gemini remains fire-and-forget until source-specific behavior changes.

## Verification status and blocker

The audit is source-backed and can be checked with repository documentation and diff validators. Swift contract tests are **not complete**.

On 2026-07-26, `swift test --filter OrbitApprovalContractTests` failed before package compilation because the selected Command Line Tools installation could not link the SwiftPM `PackageDescription` manifest library. No alternate Xcode or Swift toolchain was found in the inspected standard locations. This audit does not modify `Package.swift`, install developer tools, or claim that tests passed.

The discarded test draft referenced a future `OrbitApprovalInbox` parallel model and was intentionally not committed. New RED tests must target request-ID propagation through the existing `BridgeTransport` and `BridgeServer` seam.

## Phase 0 exit decision

- **Audit:** complete with this document.
- **Contract implementation/tests:** pending as the next coherent slice.
- **T3 Code:** optional investigation only; no integration recommendation yet.
- **Production/UI behavior:** unchanged by this audit.