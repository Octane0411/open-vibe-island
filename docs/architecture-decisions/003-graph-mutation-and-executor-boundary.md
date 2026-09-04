# Graph Mutation And Executor Boundary

**Status:** Accepted
**Date:** 2026-07-22
**Scope:** Mutation commands, fenced executor operations, bounded orchestration,
artifact handoffs, crash recovery, and deterministic compendium execution

## Context

Durable history, replay, reconciliation, scheduling decisions, claims, leases,
retry, cancellation, and timeout policy existed before graph execution. The next
boundary had to execute work without allowing a CLI process or provider adapter
to become a second source of truth.

The required authority chain is:

```text
Definition
-> History
-> Projection
-> Reconciliation
-> Scheduling decision
-> Claim
-> Executor command
-> Executor observation
-> Durable terminal declaration
```

Real Codex, Qwen, Ollama, tmux, and Terminal Graph MCP adapters remain out of
scope. This decision establishes the contract they must implement.

## Decision

### Mutation command semantics

`GraphMutationService` owns `create`, `start`, `cancel`, and `retry` requests.
Every accepted mutation is represented by versioned append-only events and
supports expected-head concurrency. Client idempotency keys make exact
redelivery safe and reject conflicting reuse.

- `create` persists the validated executable definition and content digest but
  does not start it.
- `start` persists scheduling intent but cannot claim or execute a node.
- `cancel` persists run- or node-scoped intent. It cannot fabricate adapter
  acknowledgement or terminal cancellation.
- `retry` persists operator intent only when policy permits. The scheduler still
  owns retry delay and the next attempt ordinal.
- `step` and `run` call the orchestration service; they do not append internal
  lifecycle events directly.

Dry-run is side-effect-free. Structured stdout uses the existing versioned JSON
and JSONL envelopes; diagnostics remain on stderr.

### Executor adapter boundary

`GraphExecutorAdapter` is provider-neutral and has seven typed operations:

| Operation | Purpose |
|---|---|
| `prepare` | Validate capability and create adapter-local prerequisites |
| `start` | Start or attach to the claimed execution identity |
| `observe` | Return current execution evidence |
| `requestCancellation` | Deliver durable cancellation intent to the owner |
| `collectResult` | Return terminal status and content-addressed references |
| `cleanup` | Release adapter-local resources without changing graph truth |
| `recover` | Conservatively reattach after a persisted start intent or restart |

Every request carries run, node, attempt ID and ordinal, claim ID, lease
generation, executor ID, capability requirements, immutable execution
specification, workspace context, environment-name allowlist, input artifact
references, cancellation state, timeout policy, correlation metadata, prior
observation count, and logical time.

Responses use the closed `GraphExecutorResponseStatus` vocabulary:
`accepted`, `started`, `still_running`, `succeeded`, `failed`, `cancelled`,
`interrupted`, `unavailable`, `rejected`, `identity_mismatch`, `stale_claim`, and
`transient_adapter_failure`. Free-form strings cannot drive transitions.

### Intent versus observation

Intent and evidence remain distinct:

1. claim grant establishes exclusive ownership;
2. `attemptStarting` persists start intent and the full fenced identity;
3. adapter work happens outside the event-store transaction;
4. `executorObservationRecorded` persists the typed result;
5. artifact-reference events are appended with that observation;
6. a repository validates the observation before a terminal declaration;
7. terminal declaration and claim release are appended together.

An adapter return value alone never completes an attempt. Cleanup acceptance is
also not completion evidence.

### Fencing and stale executors

Every repository mutation validates all of:

- run ID;
- node ID;
- attempt ID and monotonic ordinal;
- claim ID and active status;
- executor ID;
- current lease generation;
- unexpired logical lease time.

Lease generation is the fencing token. Renewal increments it. An operation
using an old token cannot start, observe, publish artifacts, acknowledge
cancellation, declare terminal state, or clean up as current owner. Stable
reason codes distinguish run, node, attempt, ordinal, claim, executor,
generation, expiry, inactive-claim, provenance, and version failures.

### Orchestration-cycle transactions

`DefaultGraphOrchestrationService.step` performs one bounded cycle:

1. load and replay the complete run;
2. validate expected head and executable definition;
3. reconcile state and append one deterministic scheduler evaluation;
4. acquire the first eligible claim in stable node order;
5. renew an active lease when no more than half its policy duration remains;
6. persist start intent before invoking external work;
7. call one adapter path outside database transactions;
8. append the observation at the current expected head;
9. collect reference-only results and request cleanup when terminal;
10. append terminal declaration and claim release when justified;
11. aggregate a terminal run only from durable node outcomes;
12. return a versioned cycle report.

`run` repeats this bounded operation until the run is terminal, cancellation
needs external acknowledgement, no progress is possible, the adapter is
unavailable, the process is interrupted, or the cycle limit is reached.
Reinvocation resumes from history.

No transaction is held across an adapter call. Any optimistic conflict is
visible and retryable by rereading history.

### Attempt lifecycle

The projected lifecycle is explicit:

| Current | Input | Next |
|---|---|---|
| `created` | valid claim grant | `claimed` |
| `claimed` | durable start intent | `startRequested` |
| `startRequested` | `started` observation or recovery | `started` |
| `started` | running observation | `running` |
| `running` | cancellation request | `cancellationRequested` |
| active phase | validated terminal observation and declaration | `terminal` |
| `terminal` | atomic release declaration | `claimReleased` |

Exact duplicate events are idempotent. Terminal-to-running regression,
different-identity duplicate start, completion without durable start, stale
generation results, wrong-attempt artifacts, non-owner cancellation
acknowledgement, and terminal ordinal reuse are rejected.

### Crash boundaries

| Boundary | Durable evidence | Recovery behavior |
|---|---|---|
| before claim append | scheduler decision only | another cycle may claim |
| after claim append | active claim and created attempt | same owner continues while lease is valid |
| after start-intent append, before adapter acceptance | `startRequested` | call `recover`, never blind-start |
| after adapter acceptance, before process certainty | accepted observation | call `recover` conservatively |
| after terminal observation, before declaration | terminal observation | validate, collect/cleanup as required, then declare once |
| after terminal declaration | terminal attempt and released claim | replay returns terminal; no adapter call |

The deterministic executor injects both start crash boundaries without sleeps or
randomness. SQLite reopen tests prove process restart resumes the same stream.

### Artifact input and output resolution

Executor outputs are content-addressed `GraphArtifactReference` records. Event
history never stores bodies. Each reference validates digest, media type, role,
sensitivity, producer run/node/attempt/ordinal/claim, and non-inline storage
locator.

`GraphArtifactInputResolver` computes all ancestors from the immutable DAG,
filters by the consumer's declared input roles, validates completed-attempt and
claim provenance, and returns stable ID order. Adapters receive references only.

Supported roles are node output, execution log, structured result, and
diagnostic artifact.

### Deterministic compendium execution

The committed fixture executes:

```text
architect -> researcher -> graph -> reviewer
```

Architect emits a section-plan reference. Researcher consumes it and emits
researched sections. Graph consumes researcher output and emits a relationship
graph. Reviewer resolves all matching upstream artifacts and emits a review
verdict. The fixture contains no regulatory claims or model prompts.

The executor script supports immediate success, logical running polls,
retryable and non-retryable failure, indefinite running for timeout tests,
cancellation acknowledge/ignore, both crash boundaries, artifact emission,
duplicate observations, and stale-generation observations.

## Consequences

- Real adapters can be added without changing history, scheduling, CLI, or
  terminal declaration semantics.
- Adapter-local process state is recoverable evidence, not graph authority.
- Execution is deliberately single-cycle and bounded; throughput optimization
  comes after correctness and observability.
- Dynamic graph mutation, remote leases, distributed transport, and production
  model execution remain separate future decisions.

## Readiness Criteria For A Real Adapter

A local adapter is ready only when it:

1. persists durable process identity and can reject PID/session reuse;
2. captures bounded logs and content-addressed artifacts without event bodies;
3. implements all seven operations and typed statuses;
4. accepts renewed lease generations and rejects stale commands;
5. recovers both start crash windows without duplicate launch;
6. honors cancellation and execution deadlines using logical durable decisions;
7. passes the deterministic repository, SQLite restart, pipe, replay, diff, and
   full application regression suites;
8. exposes no prompts, secrets, unrestricted environment, or artifact contents
   through graph events or structured CLI output.

The first real adapter should be a supervised direct-process or tmux adapter.
Only one compendium node should use it initially; provider-specific Codex, Qwen,
Ollama, and Terminal Graph MCP adapters follow after that boundary is proven.

## Numbered Requirement Audit

All numbered requirements are complete. No numbered item is partially complete
or blocked.

### Primary objective

| # | Status | Evidence |
|---:|---|---|
| 1 | complete | `GraphMutationService.create`; `GraphMutationServiceTests.testCreateIsInactiveDurableAndIdempotent` |
| 2 | complete | `GraphMutationService.start`; `testStartMakesArchitectSchedulableAndIsIdempotent` |
| 3 | complete | `GraphOrchestrationService.step`; `testStepIsBoundedAndDryRunHasNoWritesOrInvocations` |
| 4 | complete | `GraphExecutorRepository.recordStartRequest`; `testFencedStartObservationArtifactAndTerminalDeclaration` |
| 5 | complete | Typed observation and terminal declaration; `testCompendiumRunsAllFourNodesAndPropagatesArtifacts` |
| 6 | complete | Recorded retry eligibility and new ordinal; `testRetryDelaySurvivesServiceRestart` |
| 7 | complete | Cancellation request/acknowledgement; `testCancellationAcknowledgementAndTimeoutAreDurable` |
| 8 | complete | Pure scheduler dependency propagation; compendium and non-retryable failure tests |
| 9 | complete | Durable run terminal aggregation; successful and failed compendium tests |
| 10 | complete | Recover operation and SQLite reopen; both crash tests and SQLite restart test |

### Orchestration service responsibilities

| # | Status | Evidence |
|---:|---|---|
| 1 | complete | `DefaultGraphOrchestrationService.load` reads the authoritative stream |
| 2 | complete | Projector replay plus `GraphExecutionProjectionReconciler` in dry-run and scheduler paths |
| 3 | complete | `DefaultGraphSchedulingRepository.evaluateAndAppend` |
| 4 | complete | Expected-head scheduler transaction and SQLite competing-writer tests |
| 5 | complete | Stable runnable selection and `attemptClaim`; bounded-step test |
| 6 | complete | `executionContext` plus repository `currentOwnership` exact fencing |
| 7 | complete | Seven typed `invoke*` adapter methods outside store operations |
| 8 | complete | `persistObservation` with current expected version |
| 9 | complete | `finishTerminalObservation` validates observation before declaration |
| 10 | complete | Half-life renewal and atomic terminal release; lease renewal test |
| 11 | complete | Repeated scheduler cycles perform fixed-point dependency propagation |
| 12 | complete | Versioned `GraphOrchestrationCycleReport` in text, JSON, and JSONL tests |

### End-to-end scenarios

| # | Status | Evidence |
|---:|---|---|
| 1 | complete | `testCreateIsInactiveDurableAndIdempotent` |
| 2 | complete | `testCreateIsInactiveDurableAndIdempotent` exact redelivery |
| 3 | complete | `testCreateRejectsConflictingIdempotencyReuse` |
| 4 | complete | `testStartMakesArchitectSchedulableAndIsIdempotent` |
| 5 | complete | `testCrashAfterAdapterAcceptanceRecoversConservatively` asserts one architect start |
| 6 | complete | `testCompendiumRunsAllFourNodesAndPropagatesArtifacts` |
| 7 | complete | Compendium test plus `GraphArtifactInputResolver` producer assertions |
| 8 | complete | Compendium test resolves researcher output into graph execution |
| 9 | complete | Compendium test resolves all architect, researcher, and graph inputs for reviewer |
| 10 | complete | Compendium test asserts four completed attempts and completed run |
| 11 | complete | `testRetryDelaySurvivesServiceRestart` asserts ordinals 1 and 2 |
| 12 | complete | Same test reconstructs recorded eligibility in a new service |
| 13 | complete | `testNonRetryableFailureBlocksDownstreamAndFailsRun` |
| 14 | complete | `testCancellationBeforeClaimDoesNotInvokeExecutor` |
| 15 | complete | Cancellation durability test asserts adapter cancellation operation |
| 16 | complete | Same test asserts acknowledged and terminal-cancelled state |
| 17 | complete | Same test asserts cancellation timeout and interruption |
| 18 | complete | `testStaleClaimCannotPublishAfterLeaseTakeover` and stale orchestration test |
| 19 | complete | `GraphExecutorRepositoryTests.testDuplicateObservationIsIdempotent` |
| 20 | complete | `testCrashAfterStartRequestRecoversWithoutDuplicateStart` |
| 21 | complete | `testCrashAfterAdapterAcceptanceRecoversConservatively` |
| 22 | complete | `testSQLiteProcessRestartResumesSameGraphWithoutDuplicateStart` |
| 23 | complete | `testRepeatedRunDoesNotDuplicateTerminalWork` |
| 24 | complete | `testStepIsBoundedAndDryRunHasNoWritesOrInvocations` |
| 25 | complete | `testRunJSONLPreservesTerminalGraphCompatibleRecords` plus real pipe test |
| 26 | complete | CLI compendium test asserts four nodes and five artifact export records |
| 27 | complete | `testSuccessfulExecutionReplaysByteIdenticallyAndDiffExplainsRun` |
| 28 | complete | Same test asserts run, every node, artifacts, and event-range changes |
