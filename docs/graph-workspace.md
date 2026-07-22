# Graph Workspace

The native Graph Workspace edits versioned graph definitions and operates
durable runs through the same domain services as `openisland graph`.

## Open The Workspace

- Select **Graph Workspace** in the island toolbar.
- Press Command-Shift-G.
- Choose **Window -> Graph Workspace**.

Repeated activation focuses the existing window. The workspace restores the
last document, run, mode, selection, and viewport when those records still
exist. Use **File -> New Graph** for an empty document or **File -> Open Graph
Definition** to load JSON. **Open Compendium Example** loads the bundled
architect-to-reviewer process graph.

## Define A Graph

Use **Definition** mode to add or remove nodes, edit stable node properties,
assign required capabilities and process specifications, and configure retry
and timeout policy. Drag from a typed dependency output to an input to connect
nodes. Select an edge or node and use Delete to remove it. The canvas supports
selection, multi-selection, drag positioning, pan, zoom, fit, automatic layout,
keyboard navigation, context menus, and accessibility descriptions.

Node positions are document layout metadata, not runtime state. Renaming a node
does not change its stable ID. Validate before saving or creating a run; cycles,
self-edges, duplicate edges, unknown nodes, and unsafe process paths are
rejected. Save and export graph definitions as deterministic
`.openisland-graph.json` files.

## Run A Graph

Creating a run records an immutable definition snapshot and digest. Switch to
**Run**, then use **Start**, **Step**, or **Run**. Run advances scheduler and
executor work until terminal state or an operator boundary. **Pause** stops only
the local loop; it does not invent a durable paused state.

Node inspection shows attempts, claims, lease generation, executor, blockers,
retry eligibility, cancellation, timestamps, artifacts, and causal summary.
**Open Logs** displays bounded stdout and stderr captured for the selected local
process. **Export** writes the current authoritative run inspection.

Cancel the selected node or entire run with the corresponding command. The
request is durable before the supervised process group receives termination.
Retry is enabled only when the typed policy decision permits it; the scheduler
owns the next attempt ordinal and recorded eligibility time.

## Inspect History

Use **History** or **Inspect History** for events, scheduler decisions, claims,
lease generations, retries, timeouts, artifacts, ignored evidence, checkpoints,
and causal explanation. These views replay durable history and do not mutate
the run. Equivalent terminal inspection is available through
`openisland graph inspect`, `history`, `explain`, `replay`, `diff`, and `export`.

Definition import and export are separate from run export. Importing a changed
document never mutates a run already created from an earlier version.

