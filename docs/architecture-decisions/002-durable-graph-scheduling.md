# Durable Graph Scheduling And Executor Ownership

**Status:** Accepted
**Date:** 2026-07-21
**Scope:** Scheduler decisions, runnable selection, claims, leases, retry,
cancellation, timeout declarations, restart recovery, and read-only inspection

## Context

Durable graph history established what happened, but history alone did not decide
what may run next or which executor owns that work. Launching an agent before
these decisions are durable would allow duplicate execution, lost retries,
ambiguous cancellation, and different recovery results after restart.

The scheduling boundary preserves this order:

```text
Definition
-> History
-> Projection
-> Reconciliation
-> Scheduling decision
-> Claim
-> Execution
```

No layer mutates the output of the preceding layer. The scheduler proposes
events. A repository appends them with optimistic concurrency. Replay alone
reconstructs the same scheduling and ownership state.

## Decision

### Pure scheduler

`GraphScheduler.evaluate(_:)` accepts a versioned graph definition, projected
state, reconciled state, scheduler policy, logical evaluation time, available
executor capabilities, claims, leases, and failure categories. It returns a
`GraphSchedulingDecision` containing proposed events, node phases, and reason
codes. It performs no I/O and has no clock, process, model, tmux, marker-file,
SQLite, or Terminal Graph dependency.

The evaluation ID hashes the durable semantic inputs: definition and policy
identity, logical time, capability identities, run/node/attempt state, claim
generations and expiry, retries, cancellations, timeouts, and failure
categories. Input ordering is normalized. Identical input produces identical
events and IDs.

The repository recognizes exact redelivery from the original expected stream
head by replaying that boundary and matching its completed evaluation ID.
Changed input receives a different ID and still requires the current head.

### Scheduling event taxonomy

| Event type | Fact class | Meaning |
|---|---|---|
| `graph.scheduler.evaluation.recorded` | decision | Captures definition, policy, logical time, and available capability identities |
| `graph.scheduler.node.runnable` | decision | Declares a node claimable for that evaluation |
| `graph.scheduler.node.deferred` | decision | Declares a non-claimable phase and reason |
| `graph.executor.claim.requested` | command | Records the ownership request |
| `graph.executor.claim.granted` | declaration | Establishes exclusive ownership |
| `graph.executor.claim.rejected` | declaration | Records a competing valid request that lost |
| `graph.executor.lease.renewed` | declaration | Replaces the claim with its next generation |
| `graph.executor.lease.expired` | declaration | Ends ownership without ending the attempt |
| `graph.executor.claim.released` | declaration | Explicitly relinquishes ownership |
| `graph.scheduler.retry.scheduled` | decision | Records ordinal, delay, eligibility, category, and policy |
| `graph.scheduler.retry.suppressed` | decision | Records why no retry may occur |
| `graph.scheduler.cancellation.requested` | command | Starts the cancellation protocol |
| `graph.scheduler.cancellation.acknowledged` | declaration | Records observation by the current owner |
| `graph.scheduler.timeout.declared` | decision | Records that a named deadline elapsed |
| `graph.scheduler.dependency_failure.propagated` | decision | Records fail-closed transitive blocking |
| `graph.scheduler.cycle.completed` | declaration | Makes an evaluation atomically complete and reusable |

All events use the existing versioned envelope. Unknown future scheduling
events are retained as unknown metadata and do not acquire invented semantics.

### Node phase transition table

| Phase | Entry condition | Claimable | Exit |
|---|---|---:|---|
| `pending` | A required dependency is incomplete, or policy is disabled | no | Dependency or policy changes in a later durable evaluation |
| `blocked` | Definition mismatch or fail-closed dependency failure/cancellation | no | A later definition/run or retry history changes the input |
| `ready` | Dependencies are complete but capability is unavailable, or running ownership expired | no | A matching executor appears or a takeover evaluation is recorded |
| `claimable` | Dependencies complete, policy allows, capability exists, no cancellation/terminal attempt/valid claim/backoff | yes | Claim or any newer scheduling input |
| `claimed` | A valid claim owns a non-running, non-terminal attempt | no | Attempt starts, claim releases, or lease expires |
| `running` | Reconciled attempt is running with a valid claim | no | Terminal declaration, cancellation, release, or expiry |
| `retry_waiting` | A durable retry exists and its recorded eligibility time is later than logical time | no | Logical time reaches the recorded eligibility boundary |
| `cancellation_pending` | A cancellation request exists and the attempt is not terminal | no | Terminal cancellation or another authoritative terminal declaration |
| `terminal` | Run is terminal, attempt completed/cancelled, or retry is exhausted | no | No transition within that attempt/run history |

An incomplete dependency is `pending`; `blocked` is reserved for a condition
that prevents execution under current fail-closed semantics. Both are
non-claimable.

### Reconciliation and scheduling precedence

Node evaluation applies this deterministic precedence:

1. definition identity must match the persisted version and digest;
2. scheduling policy must be enabled;
3. a terminal run is terminal for every node;
4. completed or cancelled attempts are terminal;
5. pending cancellation prevents a claim;
6. dependencies are evaluated to a fixed point; terminal failure or
   cancellation propagates transitively;
7. a running attempt with a valid claim remains running; expired ownership is
   ready for recovery;
8. a valid claim owns only a non-terminal attempt;
9. a recorded retry delay prevents early execution;
10. failed, interrupted, or orphaned attempts apply retry allow/exhaust rules;
11. required capabilities must be available;
12. otherwise the node is claimable because dependencies are satisfied.

An authoritative terminal attempt outranks a lease. A lease never proves that
an attempt is running and never converts expiry into failure, interruption, or
cancellation.

### Reason-code taxonomy

| Category | Stable reason codes |
|---|---|
| Dependency and readiness | `dependencies_satisfied`, `dependency_failed`, `dependency_cancelled`, `dependency_incomplete` |
| Ownership | `existing_active_claim`, `lease_expired`, `claim_granted`, `claim_rejected`, `claim_released`, `lease_renewed` |
| Retry | `retry_allowed`, `retry_exhausted`, `retry_backoff_active`, `retry_not_applicable` |
| Cancellation and timeout | `cancellation_pending`, `cancellation_acknowledged`, `timeout_recorded` |
| Terminal and policy gates | `terminal_attempt_exists`, `run_terminal`, `executor_capability_unavailable`, `graph_definition_mismatch`, `scheduler_policy_denied` |

Every node decision has one typed reason. Consumers never parse prose to decide
whether work is claimable.

### Claims and renewable leases

`GraphExecutorClaim` records schema version, run, node, attempt ordinal, claim
ID, executor ID, capability identity, grant sequence, lease start and expiry,
lease generation, and optional host identity. Claim grant is one append with
attempt creation when needed, request, and grant events.

The event store's expected-head transaction is the exclusion mechanism. There
is no correctness dependency on an in-memory lock. Exactly one competing
writer wins. Exact claim redelivery compares owner, capability identity, host,
lease start, and lease expiry. Contradictory reuse is a structured
`claim_identity_collision`.

Renewal requires the current claim, executor, generation, current stream head,
and an unexpired lease. It writes generation `n + 1`. Stale generations and
expired renewals fail. Takeover records expiry before granting a new claim.
Release is explicit and exact-redelivery idempotent.

### Retry policy

`GraphRetryPolicy` versions maximum attempts, retryable and non-retryable
categories, exponential bounded backoff, optional bounded jitter, timeout
behavior, cancellation behavior, and dependency-failure behavior. Jitter is a
SHA-256-derived function of durable seed, run, node, and next ordinal.

`retryScheduled` records the policy, failed and next ordinals, category,
scheduled time, delay, and eligibility time. A restart during the delay reads
that value; it does not recalculate historical time. Ordinals increase
strictly and are never reused. Exhaustion emits `retrySuppressed` and causes
fail-closed dependency propagation.

### Cancellation protocol

Cancellation is:

```text
request -> owner observation -> acknowledgement -> terminal declaration
```

Before a claim, terminal declaration creates a first cancelled attempt. During
valid ownership, only the matching owner may acknowledge and terminal
declaration requires acknowledgement. After process exit, the request remains
valid because process observation is not terminal workflow state. If the owner
is unavailable and its lease expires, terminal declaration first records lease
expiry, then cancellation. Duplicate requests, acknowledgements, and terminal
declarations are idempotent only when their content matches. Cancellation stays
distinct from failure and interruption.

### Timeout decisions

`GraphTimeoutDecision` supports claim acquisition, lease, attempt execution,
cancellation acknowledgement, and retry delay. Declaration before the deadline
is rejected. Replay reads the recorded declaration and never infers a past
timeout from the current clock. Lease timeout also records explicit lease
expiry but does not end the attempt.

### Repository transactions and restart

`GraphSchedulingRepository` exposes evaluate-and-append, claim, renew, release,
request cancellation, acknowledge cancellation, terminal cancellation, and
timeout declaration. Each operation uses an expected stream head, emits one
atomic append, returns structured conflict reasons, and has exact-redelivery
handling. Domain APIs expose no SQLite type.

Restart recovery opens the same event stream and replays evaluations, claims,
lease generations/status, retries and eligibility, cancellations, and timeout
decisions. Logical time determines whether a currently active lease is still
valid; it does not rewrite history. SQLite contention and restart tests use
separate store instances against one database.

### Read-only inspection and migration

CLI schema version 2 adds scheduling inspection to `graph inspect`, scheduler
reason codes to `graph explain`, scheduling categories to `graph diff`, and the
new events to `graph history`. Inspection includes policy, active claims,
expiry, claim history, retries and eligibility, pending cancellation, timeout
decisions, and scheduling records. Host identity is exposed only as a Boolean.

Schema version 1 remains selectable and omits version 2 fields. JSON/JSONL
envelopes report the selected version. Snapshot decoding defaults a missing
`scheduling` projection to empty. Evaluation payloads decode older records with
no embedded policy. No SQLite schema migration is required because scheduling
uses the existing typed event envelope and snapshot document.

## Compendium fixture result

`compendium-scheduling-graph.json` defines the realistic chain:

```text
architect -> researcher -> graph -> reviewer
```

Each node has distinct capability requirements. Tests prove only architect is
initially claimable; each successor remains non-claimable until its predecessor
completes; renewal preserves ownership; expiry allows takeover; stale renewal
fails; retry uses ordinal two; exhaustion and cancellation block all downstream
nodes; SQLite restart preserves claim and retry state; exact repeated evaluation
adds nothing; and all four completions reconcile the run to successful terminal
state.

## Deferred boundary and next-slice readiness

This decision does not launch a process or model and adds no mutation CLI, UI,
network transport, Terminal Graph MCP call, or provider adapter.

The next slice is ready because scheduler output is deterministic, ownership is
exclusive and restartable, retry/cancellation/timeout state is durable, every
operation is version checked and idempotent, the complete compendium path is a
fixture, schema v1 compatibility is retained, and SQLite contention is proven.

The next task is exactly:

> Implement graph mutation commands and an executor adapter boundary, then use a no-op or deterministic test executor to create, claim, start, complete, retry, and cancel the four-node compendium graph end to end before introducing real tmux, Codex, Qwen, Ollama, or Terminal Graph MCP adapters.

## Requirement audit

All requested scheduling requirements are complete. No requirement is blocked
or partially complete.

### Domain capabilities

| # | Status | Evidence |
|---:|---|---|
| 1 | complete | Scheduler events in `GraphExecutionHistory.swift`; replay test in `GraphSchedulerTests` |
| 2 | complete | Pure phase selection in `GraphScheduling.swift`; compendium progression invariant |
| 3 | complete | `attemptClaim`; in-memory and SQLite competing-claim tests |
| 4 | complete | `renewLease`; renewal and restart tests |
| 5 | complete | Expiry event, timeout, takeover, and stale-owner tests |
| 6 | complete | Exact-redelivery-safe `releaseClaim` and repository test |
| 7 | complete | Versioned `GraphRetryPolicy` and deterministic backoff test |
| 8 | complete | Stable attempt IDs and monotonic ordinal tests |
| 9 | complete | Durable delay and eligibility in retry records and SQLite restart test |
| 10 | complete | Versioned cancellation request record and pre-claim/claimed tests |
| 11 | complete | Owner-validated acknowledgement and stale acknowledgement test |
| 12 | complete | Five timeout kinds and explicit-decision tests |
| 13 | complete | Fixed-point scheduler and reconciler failure propagation tests |
| 14 | complete | Crash-boundary, snapshot, and SQLite reopen tests |
| 15 | complete | Stable input identity and exact original-head redelivery tests |
| 16 | complete | Expected-head exclusion in in-memory and SQLite competing writers |

### Numbered compendium fixture scenarios

| # | Status | Evidence |
|---:|---|---|
| 1 | complete | Initial evaluation makes only architect runnable |
| 2 | complete | Researcher is non-claimable until architect completion |
| 3 | complete | Graph is non-claimable until researcher completion |
| 4 | complete | Reviewer is non-claimable until graph completion |
| 5 | complete | In-memory and SQLite contention each produce one architect owner |
| 6 | complete | Renewal advances generation and preserves the same claim owner |
| 7 | complete | Expiry is recorded before takeover grants a new claim |
| 8 | complete | Prior executor renewal fails after takeover |
| 9 | complete | Retry claim creates ordinal two and never reuses ordinal one |
| 10 | complete | Maximum-attempt exhaustion emits suppression and blocks descendants |
| 11 | complete | Architect cancellation reconciles researcher, graph, and reviewer blocked |
| 12 | complete | SQLite reopen reconstructs identical active claim and retry eligibility |
| 13 | complete | Original-head evaluation redelivery appends zero events |
| 14 | complete | Four completed attempts reconcile every node and run to `completed` |

### Claims, protocols, repository, CLI, and fixture

| Area | Status | Evidence |
|---|---|---|
| Claim field model and one-valid-owner rule | complete | `GraphExecutorClaim`, replay validation, generated collision variants |
| Renewal identity/generation and stale behavior | complete | Repository conflict tests and SQLite takeover invariant |
| Lease is not terminal attempt state | complete | Lease timeout protocol test |
| Retry categories, bounds, jitter, timeout/cancel/dependency behavior | complete | `GraphRetryPolicy` and scheduler tests |
| Cancellation before/while claim, while running, after exit, duplicate, stale, unavailable owner, expiry | complete | `GraphSchedulingProtocolTests` |
| Claim, lease, execution, cancellation, and retry-delay timeout kinds | complete | Timeout category test and durable timeout projection |
| Transactionality, expected head, idempotency, conflicts, no partial writes | complete | `GraphSchedulingRepository.swift`, event-store tests, SQLite invariants |
| Read-only inspect/explain/history/diff with stable output/redaction | complete | CLI schema v1/v2 and byte-identical output tests |
| Four-node fixture scenarios 1-14 | complete | `GraphSchedulingDurabilityInvariantTests` |
| Unknown future event, snapshot replay, stale fixture compatibility | complete | Future/snapshot/stale compatibility invariant |
| Model-generated coverage where practical | complete | Table-driven contradictory claim mutation test |
| No mutation CLI, launcher, MCP, networking, or UI | complete | Core-only adapter-neutral implementation and documented boundary |

## Consequences

- Open Island can now determine and persist who may execute a node without
  executing it.
- Operators can inspect the exact policy, ownership, retry, cancellation, and
  timeout history through a stable read-only interface.
- Executors must treat the claim generation as a fencing value and append
  terminal workflow facts explicitly.
- Dynamic graph mutation, typed handoff validation, resource reservations, and
  real provider launch adapters remain later capabilities.
