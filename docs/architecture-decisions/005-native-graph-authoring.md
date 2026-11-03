# Native Graph Authoring And Run-Creation Boundary

**Status:** Accepted
**Date:** 2026-07-22
**Scope:** Graph authoring state, document lifecycle, typed wiring, validation,
undo, templates, and durable run creation

## Context

The durable graph runtime and first production executor were complete, but the
native workspace could not construct an executable graph without fixture JSON
or command-line assembly. Provider adapters would have hidden that gap behind
provider-specific forms and made the editor, adapter, or UI a competing source
of execution truth.

## Decision

### Authoring state is a document, not a run

`GraphDefinitionDocument` is the canonical editable value. The view model owns
selection, viewport, undo history, file state, diagnostics, run-creation draft,
and definition/run association. SwiftUI bindings always call mutations against
the current document rather than retaining stale node copies.

Creating or editing a document emits no graph execution event. **Create Run**
materializes an immutable `GraphExecutableDefinition` only after validation,
input resolution, workspace checks, and backend compatibility succeed. All
later Start, Step, Run, Retry, Cancel, and inspection behavior goes through the
existing mutation, orchestration, and temporal service boundaries.

### Lifecycle and version semantics

| State | Allowed behavior | Run relationship |
| --- | --- | --- |
| unsaved editable | author, validate, save, close | no run exists |
| saved editable | atomic save, Save As, revert, reopen | no semantic lock |
| saved with runs | layout edits remain ordinary; semantic edits become Draft | prior snapshots stay immutable |
| Draft | edit and save; Create Run is blocked | create a new definition version first |
| new definition version | editable with incremented version and no associated runs | may create a new immutable run |

File state includes URL, dirty digest, last saved digest, external-change
evidence, schema version, validation time, and recent-document order. Writes
are deterministic and atomic with optimistic external-modification checking.

### Typed ports and artifacts

Every node input and output has a stable ID and a port type. Artifact edges bind
stable source node/output and target node/input identities. A shared pure
connection evaluator serves drag, inspector, menu, and keyboard paths and
rejects invalid topology or types before mutation. Runtime input roles are
derived from accepted artifact bindings.

Local-process `${input:role}` tokens address upstream artifacts;
`${artifact:role}` tokens address outputs declared by the current node. Static
validation mirrors the executor resolver so an unavailable token is an
authoring error rather than a pre-launch runtime failure.

### Validation architecture

`GraphDefinitionValidator` is side-effect-free and returns typed diagnostics
with severity, stable code, target, message, and suggested action. It runs
incrementally after edits, on demand, and as a hard run-creation gate. The
taxonomy covers empty/name/ID errors, topology, references, execution and
argument tokens, local paths, artifact containment, typed ports, required
inputs, provider multiplicity, role collisions, retry/timeout policy,
executor/capability support, terminal outputs, reachability, sensitive
literals, and immutable-definition mutation.

The validation panel and node inspector project the same diagnostic values.
Navigation selects the affected element; neither surface changes runtime state.

### Undo, layout, and templates

Authoring commands snapshot document plus selection before mutation. Undo/redo
restores both and never sends execution mutations. Node drag coalesces into one
entry. Layout metadata is excluded from semantic digests; automatic layout is
deterministic and undoable.

Templates use the ordinary graph-document factory. Blank, Linear,
Fan-Out/Fan-In, Review Loop, Compendium Fill, and Local Process Example produce
editable, serializable documents. Local templates use only the packaged helper
executable; no committed graph JSON is decoded as their definition.

### Provider-adapter readiness gate

A provider adapter may be added only behind `GraphExecutorAdapter`. Its first
node must expose credentials by reference, model selection, prompt template,
structured output declaration, cancellation, logs, artifacts, and recovery
through the same completed authoring and run-creation surfaces. It cannot own
topology, persist secrets in documents, mutate projections, or bypass claims
and lease fencing.

## Requirement Audit

| Requirement group | Status | Evidence |
| --- | --- | --- |
| Baseline usability audit | complete | Active execution plan preserves the pre-change capability audit and resolution. |
| New/Open/Save/Save As/Validate/Create Run and guided empty state | complete | `GraphWorkspaceView`, `GraphWorkspaceViewModel`, `GraphWorkspaceTests`. |
| Creation sheet, defaults, blank in-memory document | complete | `GraphWorkspaceAuthoringState`, `GraphWorkspaceTemplateFactory`, template tests. |
| Toolbar, canvas, and keyboard node creation with stable identity | complete | `GraphWorkspaceView`, node-authoring and keyboard tests. |
| Executable, reference, generic, and annotation node palette | complete | `GraphDefinitionNodeType`, `testNodePaletteCreatesExplicitExecutableAndReferenceTypes`. |
| Full identity, execution, capability, input, output, retry, timeout, and validation inspector | complete | `GraphNodeInspector`, `testCompleteLocalProcessNodeAuthoringPreservesIdentityAndUndo`. |
| Drag, inspector, dependency, keyboard, edge inspection, rejection, and deletion | complete | `GraphConnectionEvaluator`, canvas/view-model connection tests. |
| Typed dependency, artifact, stream, and signal ports | complete | Typed edge model, connection evaluator, validator tests. |
| Graph inputs, graph outputs, unresolved-input run gate, secret references | complete | View-model graph I/O test and Create Run sheet. |
| First-class typed validator and navigable incremental panel | complete | `GraphDefinitionValidator`, validator tests, workspace validation test. |
| New/Open/Save/Save As/Revert/Close/Recent, dirty/conflict/atomic behavior | complete | `GraphWorkspaceService`, lifecycle and external-modification tests. |
| Draft versus immutable definition versions | complete | Graph inspector version action and versioning test. |
| Canvas/inspector selection synchronization | complete | Selection, edge, validation-navigation, and undo tests. |
| Document Undo/Redo and coalesced drag | complete | Authoring state and workspace/canvas tests. |
| Deterministic Auto Layout/Fit/Reset | complete | Canvas controls and template/layout tests. |
| Six editable built-in templates | complete | `GraphWorkspaceTemplateFactory`, `GraphWorkspaceTemplateTests`. |
| Guided backend/input/workspace Create Run flow | complete | Create Run sheet, compatibility gate, workspace tests. |
| UI-service-built generate/transform/verify execution | complete | `UIAuthoredGraphEndToEndTests`; save/reopen/restart/log/artifact/CLI parity assertions. |
| UI-service-built architect/researcher/graph/reviewer execution | complete | `UIAuthoredGraphEndToEndTests`; no graph fixture input. |
| Usability labels, guidance, keyboard, accessibility | complete | View labels/hints, entry-point test, packaged accessibility-tree acceptance. |
| Full automated and packaged manual acceptance | complete | Test suite plus the active plan's 2026-07-22 acceptance record. |
| Provider/tmux/Terminal Graph mutation/visual redesign exclusions | complete | No such adapter or redesign added; existing boundaries unchanged. |

## Consequences

- A graph can be authored, saved, reopened, versioned, run, and inspected from
  the packaged app without JSON or CLI construction.
- Definition documents and runtime history remain separate authorities.
- Provider-specific work can now be evaluated one adapter and one node at a
  time without weakening graph semantics.
- Collaborative editing, active-run topology mutation, tmux, remote execution,
  provider adapters, and broad visual redesign remain out of scope.
