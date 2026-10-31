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

## Dependency baseline

Commit `Package.resolved` with dependency changes. The test wrapper, harness build, and packaging script use `--force-resolved-versions` so they fail when resolution needs to change instead of silently selecting new versions. For direct commands, use `swift build --force-resolved-versions` and `swift test --force-resolved-versions`.

To update dependencies deliberately, review upstream releases and security advisories, run `swift package update`, inspect the lockfile diff, and rerun the isolated suite and relevant packaging checks before committing. Do not remove the lockfile to fix a CI failure.

The October 31, 2026 baseline locks MarkdownUI 2.4.1, NetworkImage 6.0.1, swift-cmark 0.9.0, and Sparkle 2.10.1. Sparkle's minimum is also 2.10.1, matching the locally tested version. Its [published security advisories](https://github.com/sparkle-project/Sparkle/security/advisories) were reviewed for this baseline; this is not a permanent security guarantee. Local verification used Swift 6.4 and Xcode 27.1 (27A9275). CI toolchain pinning, action revision pinning, packaging-tool versions, macOS 14/Intel runtime checks, and GUI checks remain tracked under H13.

## Test isolation

Ordinary `swift test` runs use unique temporary sockets and installer directories. Application model tests use `AppModelTestEnvironment`: a fresh preferences suite, temporary session registry directory, headless overlay panel, and injected terminal/foreground actions. Reuse that environment when a test needs to reload a model. Do not construct a production `AppModel()` in a unit test or clear `UserDefaults.standard`.

`BridgeServer` binds only its primary socket unless `legacySocketURL` is explicitly supplied. The app supplies its legacy compatibility address; tests must use unique addresses for both listeners. Never point a test server at a production socket.

Live desktop tests are opt-in and should run only in an isolated macOS test account with disposable terminal sessions:

```sh
OPEN_ISLAND_RUN_GHOSTTY_JUMP_INTEGRATION=1 swift test --filter ghosttyJumpIntegrationMatchesFocusedTerminalForLiveSurfaces
OPEN_ISLAND_RUN_WARP_TAB_INTEGRATION=1 swift test --filter liveWarpTabAdvanceSmokeTest
```

These checks can activate applications, switch tabs, and request Automation or Accessibility permission. Keep both variables unset for ordinary tests and CI. The Warp check is a manual smoke check; its lack of a crash does not prove the intended tab received focus.

When using a custom Swift build directory, set `OPEN_ISLAND_HOOKS_BINARY` to the `OpenIslandHooks` executable from that build before running the Hermes end-to-end tests.

## Smoke Mode

`scripts/smoke-dev-app.sh` sets harness environment variables before launching `OpenIslandApp`.

The smoke path is intentionally aimed at the repository executable, not `~/Applications/Open Island Dev.app`. The dev bundle remains useful for manual end-to-end OSS verification, but harness automation should target the current branch's `OpenIslandApp` binary so the verification result matches the checked-out code exactly.

- `OPEN_ISLAND_HARNESS_SCENARIO` selects a case from `IslandDebugScenario`
- `OPEN_ISLAND_HARNESS_PRESENT_OVERLAY` mirrors the scenario onto the real island overlay
- `OPEN_ISLAND_HARNESS_START_BRIDGE` skips live socket setup when disabled
- `OPEN_ISLAND_HARNESS_BOOT_ANIMATION` disables the normal boot animation for deterministic runs
- `OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS` controls when artifact capture runs after launch
- `OPEN_ISLAND_HARNESS_INTERACTIVE=1` enables pointer interaction for manual harness runs
- `OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS` terminates the app automatically after the selected duration
- `OPEN_ISLAND_HARNESS_ARTIFACT_DIR` selects the output directory for `report.json`, `timeline.json`, `runtime.log`, PNG captures, and `.ax.json` accessibility snapshots

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
