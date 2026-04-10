# AGENTS

This file defines the working agreement for the coding agent in this repository.

## Goal

Keep all work incremental, reviewable, and reversible. Every meaningful round of changes must end with a Git commit so commits become the control surface for progress, rollback, and review.

## Required Workflow

1. Start each round by checking the current repository state with `git status -sb`.
2. Read the relevant files before editing. Do not guess repository structure or behavior.
3. Keep each round focused on a single coherent change.
4. After making changes, run the most relevant verification available for that round.
5. Summarize what changed, including any verification gaps.
6. Commit the round before stopping.

## Commit Policy

- Every round that modifies files must end with a commit.
- Do not batch unrelated changes into one commit.
- Use clear conventional-style commit messages such as `feat:`, `fix:`, `refactor:`, `docs:`, or `chore:`.
- Do not amend existing commits unless explicitly requested.
- Do not create branches unless explicitly requested.
- When the user explicitly requests parallel work or multiple worktrees, create a dedicated branch for each worktree and keep `main` as the integration branch.

## Safety Rules

- Never revert or overwrite user changes unless explicitly requested.
- If unexpected changes appear, inspect them and work around them when possible.
- If a conflict makes the task ambiguous or risky, stop and ask before proceeding.
- Never use destructive Git commands such as `git reset --hard` without explicit approval.

## Engineering Rules

- Prefer small end-to-end slices over large speculative scaffolding.
- Preserve a clean working tree after each round.
- Add documentation when making architectural or workflow decisions.
- Prefer native macOS and Swift-friendly project structure for this repository.

## Parallel Worktree Rules

- Treat `/Users/wangruobing/Personal/open-island` on `main` as the shared integration worktree.
- Do not do day-to-day feature development directly on the shared `main` worktree when parallel work is active.
- Create one worktree per branch and one branch per worktree. Never attach two worktrees to the same branch.
- Create new worktrees from `origin/main`, not from a locally drifted feature branch.
- Use sibling worktree paths named like `/Users/wangruobing/Personal/open-island-<topic>`.
- Use branch names that match the workstream, such as `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, or `investigate/<topic>`.
- Keep each worktree focused on one coherent slice with a narrow file ownership area when possible.
- Rebase or merge the latest `origin/main` into the feature branch before integrating it back.
- Integrate completed work from the shared `main` worktree after verification, preferably with fast-forward history when practical.
- Remove merged worktrees and delete merged branches after the integration round is complete.
- If multiple agents are working in parallel, assign each agent its own worktree instead of sharing one checkout.

See [docs/worktree-workflow.md](/Users/wangruobing/Personal/open-island/docs/worktree-workflow.md) for the concrete commands and lifecycle.

## Reproduction Scope

- Supported agents: `Claude Code`, `Codex`, `OpenCode`, `Cursor`, `Qoder`, `Qwen Code`, `Factory`, `CodeBuddy`.
- Supported terminals: `Terminal.app`, `Ghostty`, `iTerm2`, `WezTerm`, `cmux`, `Kaku`, `Zellij`; `tmux` (multiplexer).
- IDE workspace jump: `VS Code`, `Cursor`, `Windsurf`, `Trae`, `JetBrains IDEs`.
- Treat these surfaces as the supported product boundary. See `docs/product.md` for the canonical list.
- Do not broaden the scope to other tools, runtimes, platforms, or environments unless the user explicitly asks to expand it.

## App Targets And Naming

- Treat the repository executable product `OpenIslandApp` as the canonical OSS app runtime.
- Treat `swift run OpenIslandApp` and the Xcode app target as the source-of-truth way to run the current branch's app code.
- Treat `~/Applications/Open Island Dev.app` as a local development bundle wrapper around the repo-built `OpenIslandApp`, not as a separate product line.
- Use `Open Island Dev.app` for manual OSS app verification when bundle semantics, LaunchServices, or installed-hook behavior matter.
- When the user asks to launch or restart `Open Island Dev.app`, refresh the bundle from the current repo first with `zsh scripts/launch-dev-app.sh` instead of only running `open -na`. Opening the bundle alone can relaunch a stale binary.
- Use `scripts/harness.sh smoke` or `scripts/smoke-dev-app.sh` only for deterministic harness runs; those commands intentionally launch the repo executable directly rather than the installed dev bundle.
- Treat any in-app label such as `Open Island OSS` as UI copy only, not as evidence of a third app target.
- Treat `/Applications/Vibe Island.app` and `https://vibeisland.app/` as closed-source reference baselines only. They are behavior benchmarks, not the development runtime for this repository.
- Unless the user explicitly asks otherwise, build, debug, and verify OSS changes against `OpenIslandApp`, then compare behavior against the reference app separately when needed.

## Reference Baselines

- Official product reference: `https://vibeisland.app/`
- Treat the official site as the primary behavior benchmark for notch placement, compact-vs-expanded island behavior, and external-display fallback behavior.
- Current official-product constraint to preserve: on Macs with a built-in notch, the island should sit in the notch area; on external displays or non-notch Macs, it should fall back to a compact top-center bar.
- Community implementation reference: `https://github.com/farouqaldori/claude-island`
- Useful ideas to learn from `claude-island`:
  - persist explicit screen selection, while keeping an automatic built-in-display fallback
  - derive notch geometry from `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`
  - separate compact closed state from expanded actionable state instead of treating the island as one always-expanded panel
  - keep hook installation and Unix-socket request/response loops explicit and local-first
  - enrich live session state from transcript or history parsing when hooks alone are too shallow
- Do not treat `claude-island` as a product spec. It is a reference implementation, not the source of truth for Open Island.
- Unless the user explicitly asks, do not import or prioritize these `claude-island` choices into this repository:
  - Mixpanel or other analytics
  - `yabai` or window-manager-specific scope expansion
  - Claude-only assumptions that weaken the shared agent model
  - raising the repository support boundary beyond the surfaces already listed above

## Verification

- Run targeted checks that match the change.
- If no automated verification exists yet, state that explicitly in the final summary and still commit the change.

## Default Expectation

Unless the user says otherwise, the agent should finish each completed round in this order:

1. implement
2. verify
3. summarize
4. commit
