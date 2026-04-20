# Quality And Harness

## Purpose

The repository harness exists to make a round of work mechanically checkable. The current baseline is intentionally small: document structure, package tests, package build, and an opt-in local app smoke path.

## Commands

- `scripts/harness.sh` runs the baseline checks. With no arguments it runs `docs`, `test`, and `build`.
- `scripts/harness.sh ci` is the non-GUI path used by CI.
- `scripts/harness.sh smoke` launches the macOS app in harness mode, loads a deterministic debug scenario, captures local artifacts, and auto-exits after a short timeout.
- `scripts/harness.sh smoke-all` runs the full debug-scenario suite and validates each artifact set.
- `scripts/check-docs.sh` enforces the minimum doc map and required links.

## Current Guarantees

- Core docs remain present and indexed from [docs/index.md](./index.md).
- Markdown files under `docs/` keep a visible top-level heading.
- `swift test` stays green for the package targets.
- `swift build` stays green for the package products.
- The app can be launched locally in a deterministic harness mode without requiring live hook traffic.
- The smoke path produces a machine-readable report plus PNG, accessibility, and runtime-observability evidence for the rendered window surface.

## Smoke Mode

`scripts/smoke-dev-app.sh` sets harness environment variables before launching `AgentDeckApp`.

The smoke path is intentionally aimed at the repository executable, not `~/Applications/Agent Deck Dev.app`. The dev bundle remains useful for manual end-to-end OSS verification, but harness automation should target the current branch's `AgentDeckApp` binary so the verification result matches the checked-out code exactly.

- `AGENT_DECK_HARNESS_SCENARIO` selects a case from `IslandDebugScenario`
- `AGENT_DECK_HARNESS_PRESENT_OVERLAY` mirrors the scenario onto the real island overlay
- `AGENT_DECK_HARNESS_SHOW_CONTROL_CENTER` controls whether the debug window is frontmost
- `AGENT_DECK_HARNESS_START_BRIDGE` skips live socket setup when disabled
- `AGENT_DECK_HARNESS_BOOT_ANIMATION` disables the normal boot animation for deterministic runs
- `AGENT_DECK_HARNESS_CAPTURE_DELAY_SECONDS` controls when artifact capture runs after launch
- `AGENT_DECK_HARNESS_AUTO_EXIT_SECONDS` terminates the app automatically after the selected duration
- `AGENT_DECK_HARNESS_ARTIFACT_DIR` selects the output directory for `report.json`, `timeline.json`, `runtime.log`, PNG captures, and `.ax.json` accessibility snapshots

The default smoke path writes artifacts under `output/harness/`.

Each smoke artifact directory now includes a minimal observability slice:

- `report.json` for the scenario summary and runtime artifact index
- `timeline.json` for ordered launch milestones and harness log events
- `runtime.log` for a grep-friendly textual event stream
- `*.png` and `*.ax.json` for visual and semantic UI evidence

The validator also checks that launch reaches a complete bootstrap milestone, that overlay presentation is observed for overlay runs, and that bootstrap and capture timings stay inside a conservative local threshold.

For the deterministic scenario suite, the harness now performs these semantic checks against the accessibility snapshot:

- `closed`: compact geometry remains in the closed-notch range
- `sessionList`: expanded geometry is present and the list exposes multiple actionable rows
- `approvalCard`: overlay stays open and the accessibility tree contains `Deny` plus an allow-style button label
- `questionCard`: overlay stays open and the three answer choices appear as buttons
- `completionCard`: overlay stays open and exposes the `Done` completion copy
- `longCompletionCard`: overlay stays open and exposes the long completion response text instead of collapsing away

## Evidence Expectations

Every meaningful round should leave behind:

- passing `scripts/harness.sh ci`
- any additional targeted verification for the changed subsystem
- a short summary of remaining gaps, especially when a GUI-only path was not exercised

## Current Gaps

- CI does not run the GUI smoke step yet because the current baseline avoids depending on a window-server-backed runner path.
- The harness captures milestone timings and log summaries, but it does not yet provide a queryable log/metrics/trace stack.
- The current accessibility assertions are still scenario-specific rather than full golden snapshots.
- We do not yet have execution-plan lifecycle automation beyond the directory conventions defined in [docs/exec-plans/README.md](./exec-plans/README.md).
