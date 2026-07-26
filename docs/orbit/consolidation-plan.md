# Orbit Consolidation Architecture

**Status:** Accepted implementation direction
**Date:** 2026-07-25
**Canonical implementation:** this GPLv3 fork at `feat/orbit-gpl-fork`

## Goal

Ship one native macOS application, `Orbit.app`, that provides the useful agent-monitoring, approval, navigation, context-savings, and developer-tool capabilities identified across the approved source ledger. Orbit must own one process, one notch or top-bar panel, one menu-bar item, one settings scene, and one normalized state model.

The former first-party prototype at `hermex-vibe-orchestrator` is archive/reference-only. It must not run alongside the GPL fork or remain a competing menu-bar, overlay, router, receipt, or settings owner.

## Source Composition

| Source | Role in Orbit |
|---|---|
| Open Island GPLv3 | Application, transport, session-state, settings, and notch implementation base |
| CodeIsland MIT | Selectively adopted notch, multi-display, permission, jump, settings, and shortcut components with attribution |
| headroom-desktop MIT | Selectively adopted health, checksum, proxy-status, and savings-presentation patterns with attribution |
| Headroom Apache-2.0 | External local service behind a narrow API, MCP, or proxy bridge; backend is not vendored |
| AgentPeek | Public feature and behavior requirements only |
| Vibe Island proprietary app | Recorded behavior and motion reference only |
| Former Orbit prototype | Source of Orbit-specific domain requirements and test fixtures only; no second runtime |

All adoption is governed by `docs/orbit/reference-intake.md`.

## Single-App Invariants

1. Exactly one `Orbit.app` process owns user-visible state.
2. Exactly one `NSPanel` controller owns the notch or top-bar overlay.
3. Exactly one menu-bar item opens Orbit controls.
4. Exactly one SwiftUI `Settings` scene owns persistent preferences.
5. Exactly one `SessionState` reducer owns normalized session state.
6. An originating adapter alone executes an action and returns evidence.
7. Orbit never becomes a shell, model router, agent loop, hook-policy authority, app-server master, or Headroom backend.
8. External helpers are bounded adapters or setup tools, never competing UI processes.

## Runtime Shape

```text
Agent hooks/plugins/transcripts/processes
                 |
          Adapter registry
                 |
       Versioned AgentEvent envelope
                 |
     SessionState reducer + receipt ledger
          |                    |
  Orbit notch/settings     Audit export
          |
User action -> originating adapter -> scope-matched Action Receipt

Headroom local service -> HeadroomBridge -> savings/health projection only
```

### Application shell

`OrbitApp` owns:

- accessory activation policy;
- one menu-bar item;
- one transparent top-edge panel;
- one Activity window;
- one Settings scene;
- one application-wide `AppModel`.

The panel must bypass normal menu-bar frame constraints, remain physically anchored to a notched display, and use a top-center fallback on external or notchless displays. AppKit owns placement and window behavior. SwiftUI owns shape, content, and a single motion system.

### Surface routing

- `closed`: compact status and attention indicator;
- `sessionList`: manual hover or click browsing;
- `approvalCard`: scoped approval prompt;
- `questionCard`: reply or choice prompt;
- `completionCard`: bounded completion receipt;
- `errorCard`: disconnected, degraded, or failed state;
- `emergencyStop`: irreversible for the current controller generation.

Temporary cards collapse on resolution, timeout, or pointer exit with configurable grace. Reduced Motion replaces springs and staged movement with immediate geometry and opacity changes.

## Integration Registry

Each integration declares:

- stable adapter ID and agent type;
- observation capabilities;
- supported action capabilities;
- transport and schema version;
- session and jump-target identity strategy;
- health and freshness state;
- setup, repair, and uninstall operations;
- fail-open or fail-closed behavior.

Adapters normalize into `AgentEvent`. UI code never dispatches directly to a shell command, provider, hook file, or app server.

## Actions, Evidence, and Safety

Visible actions include capability and availability labels. A live action requires:

1. visible action scope and `approveHere` evidence;
2. current session, adapter, request, and target identity;
3. dispatch through the originating adapter;
4. immutable scope-matched Action Receipt;
5. audit event with secret-safe metadata.

Without matching evidence, Orbit displays `not sent` or `inspection only`. Emergency Stop blocks mutation for the current generation, preserves prior receipt history, and requires a new generation to resume.

## Headroom Bridge

`HeadroomBridge` is read-only by default and connects to the documented local API, MCP, or proxy surface. It may project:

- service health and version;
- route or proxy reachability;
- tokens saved and compression ratio;
- retrieval availability;
- per-session savings when stable identity is available.

Orbit does not copy the Headroom backend, own provider credentials, alter model routing, or silently start public listeners. Configuration changes remain a separate human gate.

## Product Surfaces

### Notch and menu bar

- compact default state;
- hover, click, and attention expansion;
- one continuous shape attached to the physical notch;
- no second menu-bar icon or detached panel;
- smooth open and restrained non-bouncy close;
- external-display fallback.

### Activity

- session list and status grouping;
- transcript, tool call, diff, cost, token, and usage views when provided;
- permission and question history;
- exact jump-back evidence;
- multi-agent board;
- pop-out session detail or chat only when the adapter supports safe attachment.

### Developer tools

- detected local servers;
- agent folders and routes to skills, plugins, config, and logs;
- saved commands and terminal workspace views;
- all executable actions remain explicitly scoped and approval-gated.

### Settings

- integrations and setup health;
- display placement;
- hover delay and collapse grace;
- spring response and damping;
- auto-expand and smart suppression;
- panel size, typography, and information density;
- sound and quiet mode;
- shortcuts;
- privacy, audit, and receipt retention;
- Headroom connection;
- third-party notices and GPL source/license access;
- reset defaults.

## Budgets

- steady expanded CPU below 2%; idle rendering demand-driven;
- RSS below 128 MiB for the base app target;
- no continuous display-link loop while idle;
- 44-point primary targets;
- complete keyboard access, Escape collapse, and visible focus;
- VoiceOver names, roles, values, status, and truthful availability;
- Reduce Motion, Increase Contrast, Reduce Transparency, and large-text support.

## Migration Phases

1. **Baseline:** resolve or explicitly quarantine existing upstream test failures.
2. **Provenance:** add Orbit modification notice, third-party notices, and source-access UI.
3. **Identity:** rename package, executable, bundle, settings keys, and public copy to Orbit while preserving history.
4. **Presentation:** make the GPL fork the only notch/menu-bar owner and validate Vibe Island-quality motion.
5. **Orbit domain:** migrate approval evidence, immutable receipts, emergency stop, audit, and context-savings contracts from the former prototype as tests first.
6. **Permissive adoption:** import only approved CodeIsland and headroom-desktop components with file-level notices and focused tests.
7. **Headroom integration:** add the bounded read-only bridge and health/savings surfaces.
8. **Capability expansion:** board, transcripts, usage, servers, routes, actions, views, and pop-out details.
9. **Release gate:** full automated suite, runtime dogfood, accessibility/security/design review, performance sample, license audit, and physical-notch evidence.

Each phase is a reviewable local commit. No remote push or release follows automatically.

## Verification Gates

- focused red-green tests for every behavior change;
- complete Swift test suite using the full Xcode toolchain;
- adapter identity and fail-open/fail-closed tests;
- receipt scope and emergency-stop lifecycle tests;
- menu-bar/notch geometry and multi-display tests;
- keyboard, VoiceOver, Reduce Motion, and contrast review;
- dependency, secret, and license scans;
- runtime CPU/RSS sampling;
- collapsed, expanded, approval, completion, error, and settings evidence;
- clean working tree and exact artifact hashes.

## Attribution Gates

Before adopting external code:

1. verify the exact upstream commit and license;
2. preserve required copyright, license, and NOTICE text;
3. mark modified Apache-2.0 files;
4. identify adopted files and origin in the commit and third-party notice;
5. exclude trademarks, artwork, mascots, sounds, and commercial flows;
6. verify the combined distribution remains GPLv3 compliant.

## Explicit Exclusions

- multiple Orbit/Open Island/Vibe Island processes or menu-bar owners;
- proprietary Vibe Island or AgentPeek code, assets, sounds, or branding;
- wholesale vendoring of Headroom;
- silent hook installation, provider routing, credential changes, or public listeners;
- a second agent loop, shell, router, approval-policy owner, or app-server master;
- signing, notarization, publication, deployment, or device transport without a separate human gate.
