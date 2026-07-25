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

`scripts/smoke-dev-app.sh` sets harness environment variables before launching `OpenIslandApp`.

The smoke path is intentionally aimed at the repository executable, not `~/Applications/Open Island Dev.app`. The dev bundle remains useful for manual end-to-end OSS verification, but harness automation should target the current branch's `OpenIslandApp` binary so the verification result matches the checked-out code exactly.

- `OPEN_ISLAND_HARNESS_SCENARIO` selects a case from `IslandDebugScenario`
- `OPEN_ISLAND_HARNESS_PRESENT_OVERLAY` mirrors the scenario onto the real island overlay
- `OPEN_ISLAND_HARNESS_START_BRIDGE` skips live socket setup when disabled
- `OPEN_ISLAND_HARNESS_BOOT_ANIMATION` disables the normal boot animation for deterministic runs
- `OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS` controls when artifact capture runs after launch
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

## Theme Snapshot Harness

Deterministic per-scenario golden pins for the themed overlay live in
`Tests/OpenIslandAppTests`. The helper `ThemeSnapshotting`
(`Tests/OpenIslandAppTests/Support/ThemeSnapshotting.swift`) renders any
`IslandTheme` slot — the closed pill or the opened session list — to a
fixed-size dark bitmap and pins it against a committed golden under
`__Snapshots__/`, using the test-target-only
`pointfreeco/swift-snapshot-testing` dependency (AB-327). Later theme tickets
add scenarios by calling
`ThemeSnapshotting.assertSnapshot(theme:slot:profile:named:record:…)`; the
`__Snapshots__` layout follows swift-snapshot-testing convention
(`__Snapshots__/<TestFile>/<testMethod>.<name>.png`).

### What each golden pins

- **Fixed widths.** 540pt (notch profile) and 520pt (top-bar profile),
  rasterized at an explicit **2×** into a bitmap the harness owns — never the
  host screen's backing scale.
- **Dark only.** The hosting view is forced to `NSAppearance(named: .darkAqua)`;
  the overlay ships no light variant, so there are no light-mode goldens.
- **Flat fill.** The opened surface is drawn on its reduce-transparency
  `surfaceInk` fill, so no `NSVisualEffectView` vibrancy leaks in — off-window
  vibrancy is neither deterministic nor window-server-independent.
- **Frozen fixtures.** Sessions come from `AppearancePreviewFixtures` (AB-326),
  which is fully `now`-injected, and no motion enters the bitmap (the capture
  reads the model layer, not the animating presentation layer; no `PulseClock`
  is supplied).

### Recording / updating goldens

Goldens re-record **only in the PR that intentionally changes pixels.** To
(re)record:

```bash
OPEN_ISLAND_RECORD_SNAPSHOTS=1 swift test --filter ThemeSnapshotHarnessTests
```

Record mode writes the PNGs and reports a deliberate failure telling you to
re-run; a plain `swift test --filter ThemeSnapshotHarnessTests` then asserts
against them. Commit the regenerated `__Snapshots__/*.png` alongside the code
change that moved the pixels, and call the re-record out in the PR body. Never
re-record just to make a red check pass — a diff means either an intended
visual change (record it and eyeball the image), or a regression (fix the
code). Recording also refreshes `environment-fingerprint.txt` (below).

### Determinism

The same slot renders **byte-for-byte identically** run to run. The fixtures
are `now`-injected, and the one wall-clock read that survives into pixels — the
rows' relative-age badges (`spotlightAgeBadge`, and each row's
`TimelineView(.periodic(from: .now …))`) — is bucketed coarsely (`<1m` / `1m` /
`2m` / `25m`). The fixtures' offsets are chosen to sit mid-bucket (never within
~30s of a `60s` boundary), so the rendered *string* never drifts even though the
raw `Date` does. Verified by re-recording seconds later and diffing the PNG
hashes (identical).

### Environment fingerprint (keeps CI green)

A golden recorded on one macOS build is **not** guaranteed byte-identical on
another (font smoothing, Core Text, GPU). Each `__Snapshots__/<TestFile>/`
directory therefore carries an `environment-fingerprint.txt` recording the
macOS build, CPU arch, and render scale. When the runtime fingerprint doesn't
match the recorded one, the pixel comparison is **skipped** (`XCTSkip`), not
failed:

- The view is still **rendered** on every runner, so a crash or a build-level
  regression in a slot fails loudly everywhere.
- Only the byte-exact pixel pin is relaxed across the environment boundary —
  strict pins are preserved on a matching machine.

CI runs on the pinned `macos-26` image (`.github/workflows/ci.yml`). The
committed goldens were recorded on a different local build, so the snapshot
tests **skip the pixel comparison on CI by design** while still exercising the
render path. Re-record on the environment whose pixels you intend to pin, and
review golden diffs there.

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
