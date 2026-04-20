# Worktree Workflow

This repository should use Git worktrees as the default shape for parallel development.

## Goals

- keep `main` stable enough to integrate and verify
- give each agent or human one isolated checkout
- reduce accidental interference across unrelated slices
- keep merge and rollback boundaries obvious

## Roles

### 1. Integration worktree

- Path: `/Users/wangruobing/Personal/agent-deck`
- Branch: `main`
- Purpose: fetch, integrate, verify, and push

Rules:

- Do not start new feature work here when parallel work is active.
- Only use this worktree to inspect the overall state, run final integration checks, resolve conflicts, and push `main`.

### 2. Topic worktrees

- Path pattern: `/Users/wangruobing/Personal/agent-deck-<topic>`
- Branch pattern: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `investigate/<topic>`
- Purpose: isolated implementation for one slice

Rules:

- One worktree owns one branch.
- One branch should represent one coherent slice.
- If two agents are working in parallel, they must use different worktrees and different branches.
- If two slices would touch many of the same files, do not run them in parallel unless one slice clearly owns the shared files.

## Standard Lifecycle

### Create a new topic worktree

From the integration worktree:

```bash
git fetch origin
git worktree add /Users/wangruobing/Personal/agent-deck-<topic> -b <branch-name> origin/main
```

Example:

```bash
git fetch origin
git worktree add /Users/wangruobing/Personal/agent-deck-island-polish -b feat/island-polish origin/main
```

## Work inside the topic worktree

Inside the topic worktree:

```bash
git status -sb
```

Then follow the normal repository workflow:

1. read the relevant files
2. make one coherent change
3. verify the change
4. commit before stopping

If the branch needs new `main` changes during development:

```bash
git fetch origin
git rebase origin/main
```

If rebase is risky for that slice, merge `origin/main` into the topic branch explicitly instead.

## Integrate back into `main`

First make sure the topic worktree is committed and verified.

Then return to the integration worktree:

```bash
git switch main
git fetch origin
git pull --ff-only origin main
```

Preferred path for clean history:

1. rebase the topic branch onto the latest `origin/main`
2. merge it into local `main` with fast-forward when possible

Example:

```bash
git switch feat/island-polish
git fetch origin
git rebase origin/main

git switch main
git merge --ff-only feat/island-polish
```

If only part of a topic branch is ready, use `git cherry-pick` from the integration worktree instead of merging the whole branch.

## Push policy

- Push topic branches when you want backup, review, or collaboration.
- Push `main` only after the integration worktree has absorbed the intended branch set and passed the relevant verification.

## Cleanup

After the topic branch is merged:

```bash
git worktree remove /Users/wangruobing/Personal/agent-deck-<topic>
git branch -d <branch-name>
```

If the branch was pushed upstream:

```bash
git push origin --delete <branch-name>
```

## Recommended Conventions

- Keep topic names short and concrete: `codex-hooks-noise`, `island-geometry`, `claude-usage`.
- Prefer sibling directories under `/Users/wangruobing/Personal/` so all worktrees stay easy to discover.
- Do not leave long-lived unmerged worktrees drifting far away from `origin/main`.
- If a worktree becomes exploratory rather than shippable, rename the branch into `investigate/<topic>` or close it.
- When assigning work to multiple agents, split by file ownership or subsystem, not by vague goal.

## Suggested Parallel Layout

Good parallel split:

- `feat/island-visual-polish`: `Sources/AgentDeckApp/Views/*`
- `fix/codex-hook-installer`: `Sources/AgentDeckCore/CodexHookInstaller.swift`
- `investigate/jump-accuracy`: terminal jump diagnostics and docs

Bad parallel split:

- two agents both editing `AppModel.swift`
- one branch mixing hook installer work, island UI changes, and docs cleanup
- direct feature edits on the shared `main` worktree while another topic branch is still integrating
