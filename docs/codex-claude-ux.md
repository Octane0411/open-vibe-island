# Codex and Claude workflow comparison

Reference: the installed Vibe Island 1.0.55, its English interface labels and
current local display preferences, plus the public [product preview](https://vibeisland.app/)
and [release notes](https://vibeisland.app/changelog/). Scope is local Codex and
Claude workflows. Remote sessions, mobile alerts and additional integrations
are outside this comparison.

## Behavior and display

| Workflow | Open Island behavior in this change |
| --- | --- |
| Recent active conversations | Shared Codex daemon supplies actual root thread IDs and phases. Active roots and five minutes of completions appear; process presence alone creates no conversation. |
| Nested child agents | Structured `source.subAgent.thread_spawn` and modern `parentThreadId` retain parent, nickname and role. Descendants appear under their root with independent states. Cycles, orphans, ephemeral children and stale completions are excluded. |
| Parent lifecycle | A running child keeps its parent visible without changing a completed parent's phase or playing a new completion alert. Children do not increase the root conversation count. |
| Claude children | Existing SubagentStart/Stop metadata uses the same nested presentation as Codex. Existing task lists remain available. |
| Hide child details | General → Show subagents hides ordinary child rows and keeps the running count. Children waiting for approval or input remain visible. |
| Model and reasoning | Display has independent switches. Codex reads configured model/effort from the daemon and turn context; Claude uses the model supplied by its integration. Unavailable values are omitted. These are configuration labels, not execution telemetry. |
| Clean / Detailed | Display controls the closed island's conversation label on displays without a notch. Clean reduces menu-bar space; Detailed retains the title. Both preserve the physical cutout on notch displays. |
| Completion / question reveal | Independent General switches control automatic expansion. Approvals remain actionable; existing frontmost-session suppression, sounds, mute and keep-open behavior are preserved. |
| Outside click | General controls dismissal of automatic reveals. Manually opened panels retain normal outside-click dismissal. |
| Keyboard | A configurable global toggle opens/focuses the island. Command-Up/Down selects a conversation; Return jumps; Escape closes; Command-Y/N acts only on an actual visible or selected approval. Text fields retain editing behavior. |
| Missing terminal locator | A unique observed Codex host app for the same workspace supplies an app-only jump. No TTY or tab is guessed; conflicting or unknown hosts remain unresolved. |
| Usage, Markdown and navigation | Existing Claude/Codex quota displays, Markdown completion/plan content, questions and terminal jump integrations remain in use. |

The shared daemon connection is observational: initialize, list and read. It
never resumes a thread, creates a turn, claims the writer lock, or sends approval
responses to another client. Action buttons require a real request delivered by
an existing supported hook/desktop integration; an active-state flag alone does
not manufacture controls. See [hooks](hooks.md) for per-runtime capabilities and
Codex's own hook trust review.

## Verification

Tests cover structured and modern parent metadata, descendant grouping, cycles
and orphans, independent child phases, cache compatibility, metadata refreshes,
completion expiry and reveal suppression. The `subagents` native harness scenario
renders mixed Codex child states and Claude children. Its JSON artifact includes
the child rows so native screenshots can be checked against the underlying state.

This is functional alignment with the selected workflows, not a claim that every
commercial settings page or animation is identical. External inspection of the
installed reference window requires macOS Accessibility and Screen Recording;
those permissions were unavailable during the comparison. Native Open Island
captures use the app's own harness.

## Portable custom build

The package requires macOS 14 or later. Build both Apple Silicon and Intel slices:

```sh
OPEN_ISLAND_UNIVERSAL=true OPEN_ISLAND_CUSTOM_BUILD=true \
OPEN_ISLAND_VERSION=1.3.2 OPEN_ISLAND_BUILD_NUMBER=86 \
OPEN_ISLAND_BUNDLE_ID=app.openisland.OpenIsland \
zsh scripts/package-app.sh
```

The custom-build marker disables upstream Sparkle update checks so an official
release cannot silently replace these changes. Normal packages retain their
existing updater. ZIP/DMG bundles include the executable, hook/setup helpers,
SwiftPM resources and Sparkle framework; another Mac needs no repository or Swift
installation. Developer ID signing and notarization still require their existing
packaging credentials. An unnotarized custom build may need macOS's Open Anyway
approval on the destination Mac.
