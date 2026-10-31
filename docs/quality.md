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

The October 31, 2026 baseline locks MarkdownUI 2.4.1, NetworkImage 6.0.1, swift-cmark 0.9.0, and Sparkle 2.10.1. Sparkle's minimum is also 2.10.1, matching the locally tested version. Its [published security advisories](https://github.com/sparkle-project/Sparkle/security/advisories) were reviewed for this baseline; this is not a permanent security guarantee. Local verification used Swift 6.4 and Xcode 27.1 (27A9275). CI now selects Xcode 26.0.1 (minimum Swift 6.2 toolchain) and 26.6 explicitly, and pins checkout/setup-node actions to full revisions. These paths are listed in the [runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md). Workflow execution is still pending on the fork; local verification does not establish the CI results. macOS 14/Intel runtime and GUI checks remain release gates.

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

## Fork validation matrix and limits

| Environment | Evidence | Remaining requirement |
| --- | --- | --- |
| Apple Silicon, macOS 26.6.1, Xcode 27.1 (27A9275), Swift 6.4, Node 25.2.1 | Full isolated Swift tests and JavaScript contract tests run locally | Real agent/terminal and signed desktop checks |
| Xcode 26.0.1 and 26.6 on macOS 26 | Exact toolchains configured in CI; not available together on this machine | Successful fork CI run after pushing the reviewed branch |
| Intel target | Local x86_64 cross-build passed; Mach-O minimum OS is 14.0 | Actual Intel runtime and terminal verification |
| macOS 14 minimum | Declared deployment target | Isolated macOS 14 runtime verification before claiming support |
| iPhone/Watch | Runtime unavailable in this fork | Mobile builds, secure pairing, revocation and remote round trips before re-enabling |
| Terminal replies and SSH setup | Runtime/setup restrictions tested | H09/H16 criteria before re-enabling |

Agent adapters and terminal drivers have fixture coverage, not certification against every installed agent or terminal version. Do not interpret the inherited support tables as a completed fork compatibility matrix. Record the exact agent CLI and terminal versions during release testing; no live agent/terminal version is certified by the automated hardening run.

The harness test step runs both `node --test Tests/PluginTests/*.test.cjs` and the Swift suite. Node 24.22.1 is pinned for CI in `.node-version`; the local Node version is recorded separately above. Both Swift and JavaScript contract suites are required. No test opt-in for live Ghostty/Warp or desktop smoke is enabled by CI.

Packaging uses committed brand assets; normal builds no longer install an unpinned Pillow. Optional regeneration requires Pillow 11.3.0. DMG tooling is pinned to create-dmg 1.2.3, revision `994a036532d3ac1bb1cd5a425a0d5d796ecbed83`; CI checks the revision after fetching. Every bundle records the source commit, lockfile hash, Swift/Xcode versions, and packaging-tool version in `Contents/Resources/build-info.txt`. Hosted runner OS images can still change; CI records the image version. This is not a claim of byte-identical signed archives across machines.

For a local app/ZIP check without Finder automation or app launch, set `OPEN_ISLAND_CREATE_DMG=false` and leave `OPEN_ISLAND_PACKAGE_SMOKE=false`. Explicit desktop smoke requires `OPEN_ISLAND_PACKAGE_SMOKE=true` in a disposable test account. Never grant TCC permissions, start installed hooks, or test real terminal actions as part of the ordinary suite.

Before distribution, record screenshots/results for normal and denied Accessibility/Automation permission, a fresh install, restart with live approvals, terminal switching/cancellation, malformed/expired requests, and upgrade recovery. Use disposable agent projects and test accounts. macOS 14, Intel hardware, mobile devices, signing credentials, and a fork CI run are not supplied by this workspace; their verification remains blocked rather than inferred from local tests. See `docs/release-signing.md`.

The local Apple Silicon release app/ZIP package passed bundle, disabled-update metadata, bundled-license, and strict deep ad-hoc signature checks without launching. DMG creation, Developer ID signing, notarization, and desktop smoke were not run. Both the arm64 release app and x86_64 debug app report a macOS 14.0 minimum in their Mach-O load commands. The Xcode 27 cross-build emits an Intel deprecation warning; no claim of future Intel toolchain support is made.
