# Local Process Execution And Native Graph Workspace

**Status:** Accepted
**Date:** 2026-07-22
**Scope:** Supervised direct processes, durable process evidence, graph documents,
and the native Definition/Run/History workspace

## Context

The graph ledger, reconciliation, scheduler, claims, mutation commands, executor
protocol, and deterministic executor were complete. The next step had to prove
those contracts against operating-system processes without making tmux, a model
provider, marker files, or the UI a second execution authority.

## Decision

### Direct processes precede tmux and model providers

`SupervisedLocalProcessExecutor` is the first production adapter. It launches an
absolute executable with an argument vector through `Foundation.Process`; it
does not invoke a shell. Direct launch exposes the child PID, process group,
executable, streams, exit reason, and cancellation behavior without terminal
multiplexer state. Tmux and Codex, Qwen, Ollama, or OpenClaw adapters may later
use their own supervision mechanisms, but must translate them through the same
seven executor operations and typed observations.

The native app and production CLI compose the same local adapter. The
deterministic adapter remains available for isolated domain tests.

### Durable identity and PID reuse

A launch record binds the process PID to its operating-system birth identity,
executable identity, invocation digest, workspace identity, run, node, attempt,
claim, lease generation, executor instance, process group, and launch-record ID.
Recovery classifies that complete identity as matching-running,
matching-exited, identity-mismatch, or indeterminate. A PID match alone never
authorizes observation, output, cancellation, or cleanup.

Claim generation remains the graph fencing token. A recovered process can be
alive while its executor command is stale; stale commands cannot publish.

### Launch and recovery boundaries

| Boundary | Durable adapter state | Recovery |
|---|---|---|
| before spawn | prepared launch record, no PID | launch once through `recover` |
| spawn accepted | PID, birth and process-group identity | attach only on complete identity match |
| child exited before observation | durable identity and exit evidence | report terminal result without relaunch |
| identity mismatch | durable expected identity | report `identity_mismatch`; do not signal |
| indeterminate evidence | durable expected identity | report conservative interruption/orphan evidence |

Launch IDs include the fenced attempt identity, so retries create distinct
records and duplicate starts return the original process.

### Cancellation and timeout

The child becomes its own process-group leader where the host permits it.
Cancellation records intent before sending `SIGTERM` to the matching group. If
the durable acknowledgement deadline passes, the adapter records escalation
and sends `SIGKILL`. It never signals an identity mismatch or an unrelated PID.
Cleanup is idempotent. Execution timeout remains an orchestration decision; its
`interrupted` observation is not overwritten by result collection before the
adapter cleans up the process.

### Logs and artifacts

Stdout and stderr are appended as sequenced records under the launch runtime
root. Each stream has a byte limit, truncation evidence, UTF-8 fallback, and
configured value redaction. Graph events receive an execution-log reference,
not log bodies. The workspace log viewer reads that bounded store and supports
follow and channel inspection.

Only declared output paths contained by the workspace and writable roots are
collected. Artifacts are size checked, SHA-256 addressed, and recorded with
media type, logical role, sensitivity, attempt, and claim provenance.
Undeclared files are ignored. Environment is empty by default and only named,
allowlisted keys can be inherited or assigned.

### Versioned definition documents

`.openisland-graph.json` documents contain graph and definition IDs, metadata,
nodes, explicit typed dependency edges, immutable executor specifications,
policy, repository context, and separate layout metadata. Deterministic JSON
round trips retain compatible unknown top-level fields. Validation rejects
cycles, duplicate or unknown edges, self-dependencies, unsafe process
specifications, and invalid layouts.

The semantic definition digest excludes layout. Creating a run stores an
immutable executable snapshot and digest; later document edits cannot alter
that run. Active claims, current projection, secrets, artifact bodies, and
unrestricted environment dumps do not belong in graph documents.

### Native workspace and command boundary

The workspace has explicit Definition, Run, and History modes. Its service is
composed from `GraphMutating`, `GraphOrchestrating`, and
`GraphTemporalInspecting`; SwiftUI receives typed command results and read
models. Views cannot append events, edit SQLite, fabricate completion, bypass
claims, or mutate an existing run definition.

The Definition canvas owns only document and layout edits. Run mode projects
authoritative execution, claims, attempts, blockers, artifacts, logs, and typed
command availability. History mode reuses temporal history and causal
explanation APIs. Committed revision streams, process-exit streams, and durable
retry deadlines drive refresh; polling is not history.

`Graph Workspace` is a singleton app window opened from the island button,
Command-Shift-G, File commands, or Window menu. The last document, run, mode,
selection, and viewport are restored when applicable.

## Consequences

- The local adapter proves process behavior without granting a terminal or
  provider authority over graph state.
- The same SQLite history is inspectable from the app and CLI.
- Provider adapters must preserve identity, fencing, logs, artifacts,
  cancellation, timeout, and recovery semantics.
- Terminal Graph compatibility remains a stable CLI/JSONL/workspace-plan
  boundary. Future MCP synchronization must call public mutation and temporal
  services and must not write the store or visual state directly.
- Tmux supervision, remote execution, mixed-provider graphs, collaborative
  editing, and Liquid Glass redesign remain separate decisions.

