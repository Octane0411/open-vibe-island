# Graph Control And Temporal Inspection CLI

## Authority And Scope

Open Island graph history is the authoritative execution record. Mutation
commands append versioned requests, decisions, observations, and declarations;
inspection commands project that history without changing it. An adapter return
value is never treated as execution success until its observation and matching
terminal declaration are durable.

History, projection, reconciliation, and decisions remain separate:

1. immutable events record what was declared or observed;
2. deterministic replay projects persisted logical state;
3. reconciliation compares that projection with optional process evidence;
4. the pure scheduler proposes version-checked execution decisions;
5. claims establish exclusive ownership before an executor acts;
6. fenced executor commands produce typed observations;
7. durable terminal declarations establish attempt and run outcomes.

The stream sequence is authoritative ordering. Timestamps are descriptive and
use ISO 8601 UTC encoding.

## Command Reference

```text
openisland graph create DEFINITION --run-id RUN_ID --idempotency-key KEY [options]
openisland graph start RUN_ID --idempotency-key KEY [options]
openisland graph step RUN_ID [options]
openisland graph run RUN_ID [--cycle-limit N] [options]
openisland graph cancel RUN_ID [--node NODE_ID] --idempotency-key KEY [options]
openisland graph retry RUN_ID NODE_ID --idempotency-key KEY [options]
openisland graph list [options]
openisland graph inspect RUN_ID [options]
openisland graph history RUN_ID [options]
openisland graph explain RUN_ID [NODE_ID] [options]
openisland graph checkpoint list RUN_ID [options]
openisland graph replay RUN_ID --dry-run [options]
openisland graph diff LEFT_REF RIGHT_REF [options]
openisland graph export RUN_ID --format FORMAT [options]
```

Examples:

```sh
openisland graph create Tests/OpenIslandCoreTests/Fixtures/compendium-execution.json --run-id compendium-001 --idempotency-key create-001 --output json
openisland graph start compendium-001 --idempotency-key start-001 --output json
openisland graph step compendium-001 --expected-version 9 --output json
openisland graph run compendium-001 --cycle-limit 100 --output jsonl --emit-completion-record
openisland graph cancel compendium-001 --node researcher --idempotency-key cancel-researcher --output json
openisland graph retry compendium-001 researcher --idempotency-key retry-researcher --output json
openisland graph inspect compendium-001 --include-artifacts --output json
openisland graph history compendium-001 --output jsonl
openisland graph explain compendium-001 reviewer --output json
openisland graph export compendium-001 --format mermaid
```

Temporal references use these forms:

| Form | Meaning |
|---|---|
| `RUN_ID` | Current stream head |
| `RUN_ID@SEQUENCE` | Inclusive stream sequence |
| `RUN_ID#CHECKPOINT` | Named checkpoint boundary |

`graph replay` also accepts either `--to-sequence SEQUENCE` or
`--checkpoint CHECKPOINT`. These options are mutually exclusive. `--dry-run` is
required.

`graph export` formats are `json`, `jsonl`, `mermaid`, and
`terminal-workspace-plan`. JSON and JSONL preserve the normal structured
envelopes. Mermaid is a deterministic text graph. The terminal workspace plan
is the neutral integration model documented in
[terminal-graph-integration.md](./terminal-graph-integration.md).

## Mutation And Execution Semantics

| Command | Durable effect |
|---|---|
| `create` | Validates and records a versioned executable definition and digest. The run remains inactive. Same-key redelivery is idempotent; conflicting reuse fails. |
| `start` | Records scheduling intent. It never bypasses scheduler decisions, claims, or leases. |
| `step` | Performs one bounded replay, reconciliation, scheduling, claim, and executor-operation cycle. |
| `run` | Repeats bounded cycles until terminal, stalled, waiting for cancellation, adapter unavailable, interrupted, or at the cycle limit. Reinvocation resumes history. |
| `cancel` | Records run- or node-scoped cancellation intent. The adapter owner must acknowledge a running cancellation before terminal cancellation is declared. |
| `retry` | Records an operator retry request only when policy permits. Attempt ordinals remain monotonic and recorded backoff is not bypassed. |

`--dry-run` performs no writes and invokes no adapter. For `step` and `run`, it
reports proposed scheduler decisions, the claim candidate, the executor
operation, expected event types, and policy denials. `--expected-version`
enforces the caller's observed stream head. Mutation idempotency keys are
required for `create`, `start`, `cancel`, and `retry`; orchestration cycles are
made idempotent by deterministic decision, claim, command, and observation IDs.

The built-in CLI currently configures only the in-process deterministic
executor. Its purpose is local validation of the control protocol, not real
model work. Codex, Qwen, Ollama, tmux, and Terminal Graph MCP execution are not
connected.

## Options And Filters

All applicable commands support:

```text
--output text|json|jsonl
--schema-version 1|2
--no-color
--quiet
--include-diagnostics
--include-artifacts
--emit-completion-record
--idempotency-key KEY
--expected-version VERSION
--dry-run
--logical-time UTC_DATE
```

Mutation-specific options also include `--run-id` for `create`, `--requested-by`
and `--reason` for operator provenance, and `--cycle-limit` for `run` (1 through
10,000).

`--emit-completion-record` is valid only with `--output jsonl`. `--quiet`
executes and emits telemetry but suppresses successful stdout. Errors still go
to stderr.

Inspection filters are applied where their subject exists:

| Option | Behavior |
|---|---|
| `--node NODE_ID` | Select a node or events associated with it |
| `--attempt ATTEMPT_ID` | Select an attempt or its events |
| `--state STATE` | Select reconciled run, node, or attempt state |
| `--event-type TYPE` | Select history event type; repeatable |
| `--since UTC_DATE` | Include history events at or after the date |
| `--until UTC_DATE` | Include history events at or before the date |
| `--after-sequence N` | Start event scanning after sequence `N` |
| `--limit N` | Bound results; valid range is 1 through 1,000,000 |

Replay evidence modes are:

| Option | Behavior |
|---|---|
| `--without-live-evidence` | Reconcile without querying external evidence |
| `--require-live-evidence` | Fail with exit 7 unless evidence is available |

The modes are mutually exclusive. Historical boundaries never query live
evidence because present evidence cannot establish historical process state.

## Output Schema Versions

Version 2 is the default. Version 1 remains selectable for existing consumers.
The document/record envelopes, exit codes, redaction rules, ordering, and
JSONL streaming behavior are unchanged.

### Version 1

Text output is concise operator output. It is not a parsing contract.

JSON is one complete document:

```json
{
  "schemaVersion": 1,
  "command": "graph.history",
  "resultCount": 2,
  "eventCount": 2,
  "result": [],
  "diagnostics": [],
  "context": {}
}
```

`diagnostics` and `context` are optional. Diagnostics appear in the document
only when deliberately requested or required by that result. Otherwise,
diagnostics are written to stderr.

JSONL emits one self-contained record per line:

```json
{"schemaVersion":1,"command":"graph.history","recordType":"event","ordinal":0,"payload":{},"context":{}}
```

The record types are:

| Command | JSONL `recordType` |
|---|---|
| `create`, `start`, `cancel`, `retry` | `mutation` |
| `step`, `run` | `orchestration_cycle` |
| `list` | `run` |
| `inspect` | `inspection` |
| `history` | `event` |
| `explain` | `explanation` |
| `checkpoint list` | `checkpoint` |
| `replay` | `replay` |
| `diff` | `change` |
| `export` | `graph_entity`, `mermaid`, or `terminal_workspace_plan` |

When explicitly requested, the final JSONL record is:

```json
{
  "schemaVersion": 1,
  "recordType": "completion",
  "command": "graph.history",
  "status": "success",
  "exitCode": 0,
  "resultCount": 2,
  "eventCount": 2,
  "lastSequence": 12,
  "context": {}
}
```

Structured stdout never contains banners, progress output, terminal cursor
control, ANSI escapes, or incidental diagnostics. JSON encoding sorts keys.
Collections use explicit stable ordering:

- run summaries: newest `updatedAt` first, then `runID`;
- events: stream sequence, then event ID;
- nodes, artifacts, external mappings, and workspace-plan entities: stable ID;
- attempts: node ID, ordinal, then attempt ID;
- checkpoints: stream version, then checkpoint ID;
- diff changes: category, entity ID, field, then values.

IDs are read from durable history or derived from stable content and do not
change across repeated reads.

### Version 2 scheduling fields

Version 2 adds an optional `scheduling` object to `graph inspect` with:

- the latest evaluation and complete versioned scheduler policy;
- active claims with executor and capability identity, attempt ordinal, grant
  sequence, lease start/expiry, generation, status, and host-presence Boolean;
- deterministic claim history;
- durable retries, policy, delay, and eligibility time;
- pending cancellation and complete cancellation history;
- explicit timeout decisions;
- stable scheduler reason codes and ordered scheduling records.

`graph explain` adds `schedulerReasons`. `graph diff` adds `scheduler`,
`claim`, `retry`, `cancellation`, and `timeout` change categories. `graph
history` exposes the versioned scheduling event taxonomy without changing its
record envelope. Schema version 1 omits these additions.

Node and attempt filters also filter scheduling entities. Host IDs are not
returned by scheduling inspection; only `hostIdentityPresent` is exposed.

## Exit Codes

| Code | Category | Meaning |
|---:|---|---|
| 0 | `success` | Complete successful read |
| 2 | `invalid_arguments` | Invalid command, option, reference, or arguments |
| 3 | `not_found` | Run or checkpoint does not exist |
| 4 | `incompatible_schema` | Requested or persisted schema is unsupported |
| 5 | `corrupt_history` | Corrupt history, invalid boundary, or replay failure |
| 6 | `persistence_failure` | Read-store or database failure |
| 7 | `evidence_unavailable` | Live evidence was explicitly required but unavailable |
| 8 | `partial_result` | Reserved for a structured partial result with diagnostics |
| 9 | `optimistic_conflict` | Expected stream version or idempotency identity conflicts |
| 10 | `policy_denied` | Retry or another requested mutation is not allowed by policy |
| 11 | `stale_executor` | Claim, executor, attempt, or lease generation failed fencing |
| 12 | `adapter_unavailable` | The configured executor adapter cannot perform the operation |
| 13 | `execution_terminal_failure` | The run terminated failed, interrupted, orphaned, or blocked |
| 14 | `cancellation` | The run terminated cancelled |
| 130 | `interrupted` | SIGINT termination |

A downstream broken pipe is treated as normal pipeline completion. Other write
errors remain failures. SIGPIPE is handled without emitting a crash report, and
SIGINT exits 130.

## Replay And Diff

`graph replay --dry-run` loads an eligible snapshot only as a replay cache,
validates it, and replays through the selected boundary. The result reports:

- requested and resolved boundary;
- stream head;
- snapshot use, staleness, or bypass;
- replayed event count and unknown-event diagnostics;
- persisted projected run, node, and attempt states;
- separately reconciled run, node, and attempt states;
- process-evidence outcome and repository diagnostics.

Replay never appends events or writes snapshots. Repeated calls with the same
history, boundary, and evidence mode produce identical structured results.

`graph diff` compares two run heads, checkpoints, or sequence boundaries. It
reports graph-definition, run, node, attempt, event-set, artifact, evidence,
reconciliation, causal-reason, scheduler, claim, retry, cancellation, and
timeout changes. Timestamps alone are not semantic changes. Change records are
deterministically sorted.

## Causal Explanations

`graph explain` returns concise prose and a structured explanation graph. The
graph contains stable entities, reason nodes, typed edges, a shortest causal
chain, blocking dependency IDs, supporting and ignored event IDs, readiness
requirements, and version 2 scheduler reason codes.

Version 1 reason codes are:

| Category | Reason codes |
|---|---|
| Persisted declarations | `run_terminal_declaration`, `run_derived_from_node`, `attempt_terminal_declaration`, `persisted_state` |
| Process evidence | `matching_process_exit`, `valid_heartbeat`, `missing_process_identity`, `missing_executor_evidence` |
| Evidence degradation | `evidence_unavailable`, `evidence_stale`, `evidence_permission_denied`, `evidence_adapter_failed`, `evidence_identity_mismatch` |
| Dependency state | `dependency_failed`, `dependency_interrupted`, `dependency_orphaned`, `dependency_blocked`, `dependency_cancelled`, `dependency_pending`, `dependency_running`, `dependency_missing`, `dependencies_completed` |
| Other | `no_execution_attempt`, `unknown_event_ignored` |

Reason edges use `caused`, `blocked`, `observed`, `derived`, or `ignored`. This
lets consumers answer why a node is pending or blocked, which dependency caused
it, why an attempt is interrupted or orphaned, which evidence or event supports
the state, what was ignored, the shortest causal chain, and what must become
true for readiness without parsing prose.

## Redaction

Structured output does not expose prompt bodies, secrets, complete environment
dumps, unrestricted command arguments, artifact bodies, sensitive storage
locators, URL credentials, or private file contents.

Artifact inspection always withholds the storage locator and returns explicit
redaction metadata. Artifact IDs, content digests, media types, logical roles,
producer identity, and sensitivity classification remain available for
lineage. Repository paths are withheld unless Terminal Graph explicitly
provides a project or worktree root. Endpoint credentials, query strings, and
fragments are removed. Unknown secret-like, path-like, oversized, multiline, or
credential-bearing `TG_*` values are redacted or bounded.

There is no option to reveal secrets.

## CLI Telemetry

Each command emits a bounded, local OSLog record. Telemetry failure cannot
change command success. Version 1 fields are:

- command name and output mode;
- monotonic duration and exit category;
- result and event counts;
- replay boundary and snapshot disposition;
- reconciliation outcome;
- Terminal Graph detected as a boolean;
- piped output as a boolean.

Telemetry excludes raw arguments, environment values, prompts, file or artifact
contents, secrets, and unrestricted paths. No remote exporter is installed.

## Numbered Requirement Audit

This audit covers every explicitly numbered requirement in the temporal CLI
implementation request. All entries are complete.

### Stable output requirements

| # | Status | Evidence |
|---:|---|---|
| 1 | complete | Concise renderers in `GraphCLI.swift`; every-command text coverage in `GraphCLIStreamingInvariantTests.testEveryCommandSupportsTextJSONAndJSONL` |
| 2 | complete | `GraphCLIOutputDocument` and deterministic JSON test in `GraphCLITests.testJSONOutputIsVersionedDeterministicAndANSIFree` |
| 3 | complete | `GraphCLIJSONLRecord`, paged history emission, and `GraphCLITests.testHistoryJSONLStreamsWithoutSkippingPageBoundary` |
| 4 | complete | Structured sink isolation and ANSI assertions in `GraphCLITests.testJSONOutputIsVersionedDeterministicAndANSIFree` |
| 5 | complete | Separate stdout/stderr sinks and `GraphCLITests.testInvalidArgumentsUseStderrAndLeaveStdoutEmpty` |
| 6 | complete | Sorted-key encoder and deterministic collection builders; repeated-output diff test |
| 7 | complete | Explicit ordering in inspector and models; event pagination and multi-project ordering tests |
| 8 | complete | Shared ISO 8601 UTC encoder and structured-output tests |
| 9 | complete | Durable IDs and stable mapping-key builders; repeated invocation and workspace-plan tests |
| 10 | complete | `GraphCLIExitCode`, this exit table, and `GraphCLIStreamingInvariantTests.testExitCodeContractIsStable` |

### Terminal Graph compatibility requirements

| # | Status | Evidence |
|---:|---|---|
| 1 | complete | Paged one-line writes, signal handlers, file-descriptor sink, real Unix pipe, broken-pipe, SIGINT, and 5,000-event bounded-write tests |
| 2 | complete | `GraphIntegrationPortKind`, `GraphIntegrationSemanticType`, neutral ports, and the typed-port mapping in the integration guide |
| 3 | complete | `TerminalGraphEnvironmentDiscovery` plus absent, representative, malformed, bounded, and secret-redaction tests |
| 4 | complete | `GitGraphRepositoryContextResolver`, `GraphWorkspaceContext`, worktree/path-redaction test, and deterministic multi-project test |
| 5 | complete | `GraphTerminalWorkspacePlan`, deterministic builder/export tests, and the neutral schema documentation |
| 6 | complete | `GraphVisualizationSynchronizationAdapter`, stable external mapping keys, sorted synchronization test, and future MCP boundary documentation |
| 7 | complete | Stable exit categories, opt-in `GraphCLICompletionRecord`, signal tests, and hook/completion documentation |

### Documentation requirements

| # | Status | Evidence |
|---:|---|---|
| 1 | complete | Command Reference in this document |
| 2 | complete | Output Schema Version 1 in this document |
| 3 | complete | Exit Codes in this document |
| 4 | complete | Authority And Scope plus Replay And Diff in this document |
| 5 | complete | Causal Explanations in this document |
| 6 | complete | Redaction in this document |
| 7 | complete | [terminal-graph-integration.md](./terminal-graph-integration.md) |
| 8 | complete | Terminal Pipelines examples for `tg run`, `tg send`, and `tg recv` |
| 9 | complete | Worktrees And Multi-Project Workspaces |
| 10 | complete | Future MCP Adapter |
| 11 | complete | Neutral Workspace Plan |
| 12 | complete | Boundary explicitly preserves Open Island execution authority and makes Terminal Graph an optional interaction surface |
