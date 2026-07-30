# Durable Graph History And Replay

**Status:** Accepted
**Date:** 2026-07-20
**Scope:** Native graph execution history, replay, snapshots, reconciliation, local persistence, artifacts, and telemetry vocabulary

**Follow-on:** [ADR 002](./002-durable-graph-scheduling.md) now adds scheduling,
claims, leases, retry, cancellation, and timeout decisions on this history
boundary. Statements below that scheduling is absent describe this ADR's
original scope, not the current repository capability.

## Context

Open Island needs durable graph execution before it can safely add model launchers,
scheduling, mutation commands, time travel, or distributed executors. The prior runtime
could describe a DAG and execute an in-memory simulation, but it could not prove what
happened after restart, distinguish a workflow from an operating-system process, reject
concurrent writers, or reconstruct state at a historical stream boundary.

The design separates five concerns:

1. **Definition** describes intended graph work.
2. **History** records immutable commands, observations, declarations, and metadata.
3. **Projection** deterministically folds history into persisted logical state.
4. **Reconciliation** compares projected state with current external process evidence.
5. **Decision** determines what should execute next and remains out of scope.

A snapshot is not history. A process is not a workflow. A reconciled state is not written
back as though it were an external fact. A UI is not a scheduler.

## Decision

### Event-sourced authority

`GraphExecutionEventEnvelope` is the durable unit of history. Every envelope carries:

- envelope and payload schema versions
- globally stable event ID
- run, optional node, and optional attempt identity
- monotonically increasing run-stream sequence
- separate occurrence and recording timestamps
- event type and typed payload
- producer identity
- correlation and causation IDs
- extensible trace context
- optional integrity metadata

The stream sequence is authoritative ordering. Timestamps are descriptive and are never the
sole ordering mechanism.

Known payload types are strongly typed. Unknown event types remain
`GraphExecutionEventPayload.unknown` with a JSON value body. Replay advances the stream
version, retains the envelope, emits a warning diagnostic, and does not invent semantics.
A newer envelope schema is rejected because its structural invariants cannot be assumed.

### Event taxonomy

The initial taxonomy distinguishes metadata, commands, observations, and authoritative
declarations:

| Class | Events |
|---|---|
| Metadata | run created, node registered, attempt created, artifact recorded |
| Command | attempt starting, human interrupt requested |
| Observation | process identity observed, heartbeat observed, process exit observed |
| Declaration | attempt completed, failed, interrupted, orphaned, or cancelled; human interrupt resolved; run terminal state recorded |

Process exit is only an observation. Without an explicit terminal attempt declaration,
reconciliation classifies the attempt as interrupted rather than completed, including when
the process exit code is zero.

### Ordering, duplicates, and concurrency

Each run starts at stream version zero. A successful append requires:

1. every envelope names the target run;
2. every new event ID is globally unique;
3. an existing event ID has byte-equivalent semantic content;
4. the caller's expected version equals the persisted stream head;
5. new sequences are contiguous from `head + 1`.

An exact redelivery is idempotent, including a retry made with the pre-append expected
version. Event-ID reuse with different content, contradictory stream sequences, and gaps are
errors. No update, replacement, or deletion API exists.

SQLite uses `BEGIN IMMEDIATE` to serialize writers. The expected-version check and all event
inserts occur in one transaction. Two writers starting from the same version therefore
produce one commit and one explicit version conflict. WAL mode supports concurrent readers,
and deterministic queries order by `(run_id, stream_sequence, event_id)`.

### Replay projection

`GraphExecutionProjector` is side-effect-free. It does not read clocks, generate identifiers,
access files, query processes, open storage, or perform network operations.

Replay:

1. validates an optional initial projection boundary;
2. orders input by stream sequence and event ID;
3. removes only exact duplicate delivery;
4. rejects ID collisions, sequence conflicts, and gaps;
5. validates envelope and payload compatibility;
6. applies each typed event;
7. advances stream version only after successful application;
8. retains unknown events and diagnostics;
9. normalizes collection ordering for stable equality and encoding.

Attempt ordinals must be exactly monotonic per logical node. An attempt cannot change
process identity unless a future explicit migration event defines that behavior. Terminal
attempts and terminal runs cannot regress. A committed successful sibling attempt and its
artifacts remain materialized when another sibling fails.

### Snapshots and checkpoints

`GraphExecutionSnapshot` contains:

- snapshot schema and run ID
- stream version covered by the snapshot
- graph-definition version and digest
- complete projected state
- creation time and producer
- optional integrity metadata
- checkpoint namespace and named checkpoint references

A snapshot is a replay cache. The repository bypasses incompatible, corrupt, internally
inconsistent, or ahead-of-stream snapshots. A stale compatible snapshot is accepted only as
an initial projection, followed by replay of every subsequent event. Snapshot creation
frequency is controlled by `GraphExecutionSnapshotPolicy`; the default never writes one.

Checkpoint-ready fields preserve:

- named stream boundaries
- parent run and parent checkpoint for future forks
- explicit subgraph checkpoint namespace
- completed sibling writes
- durable human interrupt request and resolution facts

This task does not expose time travel or forks to users. Future replay APIs can select a
stream boundary without changing the event or snapshot schemas.

### Reconciliation and evidence isolation

`DefaultGraphExecutionRepository.load` follows this order:

1. load and validate the latest snapshot;
2. read subsequent events, or the complete stream when bypassing a snapshot;
3. replay deterministically;
4. request external evidence through `ProcessEvidenceSource`;
5. invoke `GraphExecutionReconciler`;
6. return persisted projection, reconciled state, snapshot disposition, evidence outcome,
   replay diagnostics, and repository diagnostics.

Evidence outcomes are explicit: available, unavailable, stale, permission denied, adapter
failed, or identity mismatch. Evidence failures never append history and never masquerade
as workflow terminal events. Identity-mismatched evidence is not passed to reconciliation.
Unavailable evidence conservatively turns unsupported running claims into interrupted or
orphaned projections while preserving the persisted history unchanged.

### Local persistence

`SQLiteGraphExecutionStore` is the production local event and snapshot store. Its default
location is:

```text
~/Library/Application Support/OpenIsland/graph-execution.sqlite
```

Database schema version 1 contains:

```text
graph_schema_migrations
  version PRIMARY KEY
  applied_at

graph_execution_streams
  run_id PRIMARY KEY
  current_version

graph_execution_events
  event_id PRIMARY KEY
  run_id
  stream_sequence
  envelope_schema_version
  event_type
  payload_version
  occurred_at
  recorded_at
  event_json
  UNIQUE(run_id, stream_sequence)
  INDEX(run_id, stream_sequence)

graph_execution_snapshots
  run_id
  stream_version
  snapshot_schema_version
  graph_definition_version
  graph_definition_digest
  created_at
  snapshot_json
  PRIMARY KEY(run_id, stream_version)
  INDEX(run_id, stream_version DESC)
```

Migrations run transactionally and are recorded in both `graph_schema_migrations` and
SQLite `user_version`. Indexed columns are cross-checked against decoded envelopes and
snapshots so malformed or tampered JSON produces a corruption error.

### Artifact lineage

`GraphArtifactReference` stores metadata, not artifact contents:

- schema version and artifact ID
- content digest
- media type and logical role
- producing run, node, and attempt
- creation timestamp
- abstract storage scheme and opaque locator
- sensitivity/redaction classification

The projector rejects artifact provenance that disagrees with its event envelope and rejects
artifact-ID reuse with different metadata. This provides the future handoff, lineage,
selective-backfill, integrity, and redaction boundary without embedding large outputs in
events.

### Observability and privacy

The internal vocabulary uses OpenTelemetry-compatible operation and attribute naming without
adding an SDK:

Operations:

- `openisland.graph.repository.load`
- `openisland.graph.event.append`
- `openisland.graph.event.replay`
- `openisland.graph.snapshot.load`
- `openisland.graph.reconciliation`
- `openisland.graph.process_evidence.query`

Stable attributes:

- `openisland.graph.run.id`
- `openisland.graph.node.id`
- `openisland.graph.attempt.id`
- `openisland.graph.executor.id`
- `openisland.graph.event.type`
- `openisland.graph.stream.version`
- `openisland.graph.replay.count`
- `openisland.graph.reconciliation.result`
- `error.type`

These are trace/log attributes, not unbounded metric dimensions. Prompts, secrets, file
contents, artifact contents, and unrestricted command arguments are prohibited. Telemetry is
local and no export dependency is installed.

### Schema evolution

- Database changes use ordered transactional migrations and increment `user_version`.
- Envelope structural changes increment the envelope schema.
- Payload changes increment the payload version independently.
- Additive optional payload fields may remain compatible within a payload version only when
  old decoders preserve the same meaning.
- Unknown event types within the current envelope schema are retained but not interpreted.
- Incompatible known payloads and future envelope schemas fail replay explicitly.
- Snapshot schema changes do not rewrite history; incompatible snapshots are bypassed.
- Graph-definition versions and digests are immutable per run.
- Process-identity migration requires a future explicit event type.

### Retention and compaction

No retention or deletion API is implemented. This is intentional: compaction policy cannot
silently turn snapshots into authority. A future archival design must preserve immutable
event identity, stream sequence, integrity metadata, checkpoint references, and a verifiable
archive boundary before local history can be removed. Snapshot cadence is injectable now so
performance policy can evolve without changing replay semantics.

## Framework Interoperability

- **Temporal-style durable execution:** this foundation supplies immutable history,
  optimistic concurrency, replay, and version boundaries. ADR 002 adds local scheduler and
  timeout decisions; task queues, workflow workers, and distributed transport remain absent.
- **LangGraph-style checkpoints and time travel:** snapshots, named stream boundaries,
  parent checkpoint references, subgraph namespaces, human interrupts, and replay from a
  projection boundary provide the required data model. User-facing state mutation and fork
  APIs remain deferred.
- **Dagster-style lineage and backfills:** content-addressed artifacts and explicit producer
  provenance provide the asset boundary. Partitions, selective backfills, and materialization
  policies are future scheduling features.
- **OpenTelemetry-style observability:** operation and attribute names align with traces,
  spans, links, logs, and resources without binding core code to an exporter or SDK.

Open Island does not copy or depend on these frameworks. Interoperability must occur through
versioned events, artifacts, checkpoints, telemetry context, or adapter protocols.

## Consequences

Benefits:

- restart-safe and deterministic logical history
- explicit corruption and concurrent-writer failure
- conservative degradation when process evidence is missing
- future-safe boundaries for checkpoints, forks, nested graphs, human interrupts, lineage,
  and telemetry
- a local production store with no cloud dependency

Costs and consciously deferred work:

- event history grows without a retention/archival implementation
- integrity metadata is stored but cryptographic verification policy is not yet selected
- dynamic graphs, provider executors, resource reservation, and distributed networking are
  not implemented; ADR 002 supplies scheduling, claiming, lease-generation fencing, and
  explicit timeout decisions
- no execution mutation commands or user-facing temporal debugger exist yet

## Requirement Audit

| # | Status | Implementation and test evidence |
|---|---|---|
| 1. Persistence protocols | complete | `GraphExecutionEventStore`, `GraphExecutionSnapshotStore`, `ProcessEvidenceSource`, and `GraphExecutionRepository`; event-store and repository test suites |
| 2. Canonical event envelope | complete | `GraphExecutionEventEnvelope`, producer, correlation/causation, telemetry, integrity, separate timestamps, typed payloads; envelope round-trip and ordering tests |
| 3. Event taxonomy | complete | `GraphExecutionEventType`, typed payload structs, and `GraphExecutionEventFactClass`; normal replay, process, artifact, and interrupt tests |
| 4. Replay projector | complete | `GraphExecutionProjector` and replay diagnostics/errors; duplicate, collision, gap, ordinal, identity, terminal-regression, unknown-event, generated determinism tests |
| 5. Snapshot boundary | complete | versioned snapshots, protocol, in-memory and SQLite stores, injectable policy; stale, incompatible, corrupt, ahead, restart, and result-equivalence tests |
| 6. Checkpoint-ready model | complete | checkpoint references, parent run/checkpoint, namespace, named boundaries, durable interrupts, independent sibling writes; checkpoint/interrupt and sibling-failure tests |
| 7. Local persistence | complete | SQLite WAL store, transactions, unique constraints, indexes, migrations, deterministic reads, default macOS path; migration, restart, corruption, and concurrent-writer tests |
| 8. Evidence failure isolation | complete | six explicit evidence outcomes and repository diagnostics; unavailable, stale, failure, mismatch, heartbeat, and exit tests |
| 9. Artifact provenance | complete | content-addressed metadata reference and storage abstraction; provenance rejection and SQLite/replay round-trip tests |
| 10. Observability preparation | complete | operation, phase, sink, record, and stable attribute vocabulary; repository emits load/replay/snapshot/evidence/reconciliation records without sensitive payloads |
| 11. Required tests | complete | all listed cases are covered across `GraphExecutionEventStoreTests`, `GraphExecutionReplayTests`, `GraphExecutionRepositoryTests`, `SQLiteGraphExecutionStoreTests`, and `GraphExecutionDurabilityInvariantTests` |
| 12. Property/model validation | complete | generated 1-20 attempt streams, duplicate/reverse replay equivalence, monotonic stream versions and ordinals, snapshot-boundary equivalence, fixed-point reconciliation, and no-manufactured-event reload tests |

Architectural principles 1-10 are complete in this ADR's implemented boundaries: definition remains
separate, history is immutable, projection and reconciliation are pure, scheduling was kept
outside this history layer and is now defined separately by ADR 002,
attempt/process identity is distinct, artifacts are durable references, core has no
provider/terminal/UI coupling, storage is accessed through protocols with SQLite confined to
the local adapter, and every persisted public format is schema-versioned.
