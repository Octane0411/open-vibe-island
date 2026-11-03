# Graph Workspace

The native Graph Workspace authors versioned graph definitions and operates
durable runs through the same domain services as `openisland graph`. Definition
editing never appends run events, and run commands never rewrite a definition.

## Open Or Create A Graph

Open **Graph Workspace** from the island, the Window menu, or Command-Shift-G.
The window is a singleton and restores the last available document, run, mode,
selection, and viewport.

Use **New Graph** to choose Blank Graph, Linear Pipeline, Fan-Out/Fan-In,
Review Loop, Compendium Fill, or Local Process Example. The creation sheet sets
the name, stable graph ID, definition version, description, default executor,
retry and timeout defaults, and optional workspace. It creates an editable
in-memory document, not a durable run.

An empty workspace offers new, open, recent, and example actions. **Open Graph**
loads deterministic `.openisland-graph.json` documents.

## Add And Configure Nodes

Add nodes from the Edit menu, canvas menu, or keyboard command. The palette
contains Local Process, Deterministic Test, Generic Agent, Input Reference,
Output Reference, and Annotation. Only the first two are runnable. Reference
and annotation nodes cannot accidentally enter executable dependencies.

Selecting a node opens its inspector:

- **Identity:** stable ID, name, description, type, and tags.
- **Execution:** executable picker, discrete ordered arguments, workspace and
  relative working directory, environment inheritance and allowlist, stdin,
  output declarations, and reveal action.
- **Capabilities:** required and preferred capabilities, executor kind, and
  platform constraints.
- **Inputs/Outputs:** typed ports, stable bindings, media types, runtime roles,
  paths, required state, size limits, sensitivity, and visibility.
- **Retry/Timeout:** graph-default inheritance or a complete node override.
- **Validation:** node-local errors and warnings with corrective guidance.

Local-process arguments are vectors, never shell strings. `${workspace}`
resolves the workspace, `${input:node_output}` resolves an upstream artifact,
and `${artifact:structured_result}` resolves an output declared by the current
node. Validation rejects unavailable roles before run creation.

## Connect Nodes

Drag a dependency handle or typed output to a valid input, use the input
binding's **Connect Upstream Output** menu, use **Add Dependency**, or use the
keyboard dependency workflow. The same connection evaluator rejects self
edges, cycles, duplicates, visual-node dependencies, incompatible port types,
and incompatible media types before commit.

Artifact bindings retain source node, source output, target input, role, and
port identities. Selecting an edge opens its source, destination, type,
required state, typed ports, and delete action. Escape cancels an in-progress
connection.

Graph inputs support text, JSON, files, directories, artifact references,
numbers, and Booleans. Sensitive values are runtime references, not persisted
secrets. Graph outputs point to declared node outputs.

## Validate And Save

**Validate** opens a persistent diagnostic panel. Selecting a diagnostic
selects its graph, node, or edge target. Validation runs after structural and
execution edits and is a hard gate for **Create Run**. It covers identity,
topology, execution specifications, local-process tokens and paths, typed
ports, required bindings, artifact roles, policies, capabilities, reachability,
terminal outputs, sensitive literals, and immutable-version rules.

**Save** uses deterministic JSON and atomic replacement. **Document** provides
Save As, Revert, and Close. Recent documents, dirty state, last saved digest,
external modification, schema version, and last successful validation are
tracked. An externally changed file is never silently overwritten. Closing a
dirty document offers Save, Don't Save, and Cancel.

Layout-only edits do not change the semantic digest. Once a definition owns a
run, semantic edits produce a visible Draft. Use **Create New Definition
Version** before creating another run. Existing runs retain their immutable
definition snapshot and digest.

Undo and Redo cover node, edge, inspector, artifact, policy, layout, and
automatic-layout edits. A drag coalesces into one action. Undo never emits run
mutations. **Auto Layout**, **Fit**, and **Reset** provide deterministic canvas
control without changing node identity.

## Create And Operate A Run

**Create Run** shows graph identity, version, digest, validation state,
compatible backend, workspace, unresolved graph inputs, policy warnings, and
estimated node count. Supervised Local Process and Deterministic Test are
available when compatible. Codex, Qwen, Ollama, and OpenClaw remain visible but
disabled until adapters are configured.

After creation, use **Start** to record run start, then **Step** or **Run**.
Run mode projects authoritative nodes, attempts, claims, blockers, artifacts,
and terminal state. Select a node and choose **Open Logs** for bounded stdout or
stderr. **Inspect History** shows events, scheduler decisions, leases, retries,
timeouts, checkpoints, and causal explanation. Retry and cancellation controls
are enabled only when typed runtime policy permits them.

The app and CLI inspect the same SQLite event history. Importing or editing a
definition cannot mutate an existing run.

## Keyboard And Accessibility

Standard Save, Undo, Redo, Delete, and cancel shortcuts work while the graph
window is focused. Commands also cover node creation, dependency creation,
validation, and run creation. Critical controls have text labels or tooltips;
nodes, edges, validation changes, modes, selections, sheet actions, and save
state expose meaningful accessibility descriptions.
