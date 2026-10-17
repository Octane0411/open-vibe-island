# Terminal Graph Integration

## Boundary

Open Island remains the authoritative execution system. Terminal Graph is an
optional visualization, terminal, spatial interaction, worktree, and future MCP
surface. It may render or route read-only Open Island data, but it does not own
canonical graph IDs, execution history, reconciliation, or scheduler decisions.

Open Island Core does not import Terminal Graph internals, require `tg`, write
Terminal Graph state, install hooks, or call its MCP server. Compatibility uses
stable CLI, JSON, JSONL, environment, workspace-plan, and adapter contracts.
Ordinary CLI operation is identical when Terminal Graph is absent.

## Terminal Pipelines

The structured modes are non-TTY dependent, line buffered, ANSI-free, and keep
diagnostics on stderr. Recommended Terminal Graph pipelines include:

```sh
openisland graph history RUN_ID --output jsonl | tg run jq .
openisland graph history RUN_ID --output jsonl | tg send
tg run --out openisland graph list --output jsonl
tg recv | jq 'select(.recordType == "event")'
```

For lifecycle-aware nodes, request a final completion record:

```sh
openisland graph history RUN_ID \
  --output jsonl \
  --emit-completion-record |
  tg send
```

Each JSONL object is written as one bounded line. Open Island stops cleanly when
a downstream reader closes, ignores SIGPIPE crash behavior, and returns 130 for
SIGINT. A completion record is emitted only when requested and only after all
result records. It carries the command, category, exit code, result count, event
count, last sequence, and optional execution context.

CI does not require `tg`. The compatibility suite exercises the same contracts
with real Unix pipes, an early-closing `head` reader, process signals, fixture
environments, and the neutral models.

## Typed Port Mapping

Open Island describes logical ports, not Terminal Graph paths or private port
objects.

| Kind | Open Island semantic types | Recommended use |
|---|---|---|
| stream | `stream.event_history`, `stream.log_records`, `stream.jsonl_records` | Event history, logs, and generic JSONL flow |
| signal | `signal.refresh`, `signal.select`, `signal.open`, `signal.focus`, `signal.completion` | Stateless operator or lifecycle notifications |
| state | `state.current_run_summary`, `state.selected_run`, `state.selected_checkpoint`, `state.workspace_context` | Replaceable current selection or context |

The neutral port contract includes a stable ID, kind, direction, semantic type,
and label. A Terminal Graph adapter may map these to its public port API. That
mapping must remain outside Open Island Core.

## Environment Discovery

Any `TG_*` value marks Terminal Graph as detected. Version 1 recognizes:

```text
TG_NODE_ID
TG_WORKSPACE_ID
TG_PROJECT_ID
TG_GROUP_ID
TG_EXTERNAL_CONTEXT_ID
TG_PROJECT_ROOT
TG_WORKTREE_ROOT
TG_MCP_URL
TG_PORT_IN
TG_PORT_OUT
```

Unknown `TG_*` names are preserved as bounded integration context when safe, so
new public values do not require immediate core changes. Secret-like names,
credential-bearing values, unknown absolute paths, empty or oversized values,
and arbitrary multiline content are redacted. MCP URLs lose credentials,
queries, and fragments.

Discovery can add optional context to structured output and telemetry records
only a detection boolean. Command correctness never depends on an environment
value, FIFO, endpoint, or unrestricted path.

## Worktrees And Multi-Project Workspaces

Repository context is optional and read-only. The Git resolver distinguishes:

- canonical project root, based on the common Git directory when available;
- current worktree root;
- stable redacted repository identity;
- current branch, commit, and dirty-state indicator;
- external workspace and source-project association.

It does not assume the branch is `main`, resolve away symlink intent, modify a
worktree, create or delete a branch, or persist arbitrary paths. Paths are
exposed only when Terminal Graph explicitly supplied a project or worktree
root; otherwise path fields state that they were redacted.

`GraphWorkspaceContext` represents zero, one, or many repositories and includes
an optional selected repository identity. Repositories sort by stable identity,
so a Terminal Graph multi-project workspace can correlate several worktrees
without changing graph identity.

## Neutral Workspace Plan

Generate a versioned plan without writing Terminal Graph files:

```sh
openisland graph export RUN_ID \
  --format terminal-workspace-plan \
  --output json
```

`GraphTerminalWorkspacePlan` version 1 contains:

| Field | Meaning |
|---|---|
| `schemaVersion` | Neutral plan schema, currently 1 |
| `planID` | Stable content-derived plan identity |
| `graphRunID` | Canonical Open Island run ID |
| `graphDefinitionVersion`, `graphDefinitionDigest` | Immutable definition correlation |
| `authority` | Always `openisland` |
| `workspaceContext` | Optional redaction-aware multi-project context |
| `terminals` | Suggested terminal nodes sorted by stable ID |
| `connections` | Suggested typed connection intents sorted by stable ID |

Each suggested terminal has a stable external mapping key, label, command as an
argument array, optional startup command, repository and worktree association,
logical group, run and node association, ports, layout hint, and sensitivity
classification. Suggested connections identify source and target mapping keys,
dependency/provenance/selection/completion intent, semantic types, and label.

Mapping keys are derived from canonical Open Island run and entity IDs. External
canvas IDs are correlations only and can be replaced without changing history.
Commands do not contain shell interpolation or hard-coded Terminal Graph paths.

## Future MCP Adapter

`GraphVisualizationSynchronizationAdapter` is the read-only future-facing
boundary. Its request consumes a graph inspection, neutral workspace plan, and
existing external mappings. Its result returns sorted canonical-to-external
mappings and diagnostics.

A future Terminal Graph MCP adapter may:

1. read `graph inspect`, history, explanation, and workspace-plan output;
2. create or update public node, connection, group, and workspace resources;
3. preserve stable external mapping keys for idempotent synchronization;
4. return external IDs only as correlation metadata;
5. repeat synchronization without duplicating entities;
6. refresh the visualization without appending or rewriting Open Island history.

It must not infer scheduler authorization from canvas state, make an external
node ID canonical, or mutate graph execution in response to visualization
drift. No MCP operation is performed by this release.

## Hooks And Completion

Future Terminal Graph hooks may trigger read-only refresh, select, open, focus,
or completion signals. They should consume the documented exit codes and the
optional versioned completion record. Hook scripts must be explicitly installed
by an operator or a future isolated adapter; Open Island does not install them.

Terminal lifecycle events are observations, not business completion. A shell
exit, including exit code zero, cannot by itself declare an Open Island attempt
completed. Adapters must translate process observations into canonical evidence,
while authoritative terminal outcomes remain explicit execution events.

