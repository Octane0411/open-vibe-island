# Orbit Agent Command Surface Goal

**Status:** Superseded by [Orbit Plan v3](./2026-07-26-orbit-plan-v3.html)
**Date:** 2026-07-26
**Branch:** `feat/orbit-gpl-fork`
**Canonical repository:** `<repository-root>`

> This document is retained as historical context only. Its slash-command,
> router-surface, and skill/plugin/tool discovery scope is not approved for
> implementation. Orbit Plan v3 is the active execution contract.

## Austin Router Directive

Route this as private, local-first macOS product development. Use one bounded implementation pass plus QA. Prefer the smallest capable local route for inspection and deterministic work; escalate reasoning only for architecture, security, or hard debugging. Keep all activity in this Orbit session and repository. Send unrelated Hermes, infrastructure, campaign, or research work to separate sessions or tasks.

## Goal Prompt

Build Orbit’s next-generation agent command surface as a clean-room GPLv3 implementation inspired only by publicly observable product behavior from Vibe Island and similar agent-monitoring products.

Pursue substantially closer behavioral parity in interaction depth, responsiveness, polish, command-driven workflows, agent visibility, automatic integration setup, and notch-first ergonomics. Do not copy proprietary source code, binaries, assets, artwork, branding, sounds, text, or hidden implementation details.

Orbit must remain one native macOS application with one process, one normalized state reducer, one overlay controller, one menu-bar item, one Settings scene, one approval-policy boundary, one hook/setup owner, and one quit path. SwiftUI owns visual animation; AppKit owns synchronous panel geometry.

### 1. Slash-command composer

Typing `/` opens a compact palette anchored to the active composer. Implement:

- fuzzy command search;
- keyboard navigation;
- visible focus;
- Enter execution;
- Escape dismissal;
- cursor-local trigger detection;
- repeated reopening after earlier commands;
- dynamic refresh after commands, skills, plugins, tools, adapters, or sessions change.

Initial commands:

- `/help`
- `/status`
- `/sessions`
- `/agents`
- `/skills`
- `/plugins`
- `/tools`
- `/approve`
- `/deny`
- `/stop`
- `/compact`
- `/handoff`
- `/model`
- `/router`
- `/workspace`
- `/terminal`
- `/settings`

Subcommands must include `/router status`, `/router explain`, and `/router profile`.

### 2. Skills, plugins, and tools

- `/skills` shows name, qualified source, description, capabilities, and safety status.
- `/plugins` shows installed plugins and exposed commands/tools.
- `/tools` groups tools by capability, scope, and approval class.
- Duplicate skill names show every source and require explicit qualification.
- Discovery is read-only and never changes credentials, providers, sessions, hooks, or runtime configuration.
- The command model must support plugin-contributed commands without UI-specific hard-coding.

### 3. Austin Router integration

Show a compact, truthful router status surface containing:

- active profile;
- selected route/model;
- routing tier;
- privacy class;
- complexity class;
- selection reason;
- fallback state;
- verification or health state.

Routine work uses the configured economical/local lane first. Escalation occurs only when task complexity, required tools, policy, or explicit user direction requires it. Never display or record credentials, provider secrets, private endpoints, or raw authorization material.

### 4. Generic coding-agent integration

Represent integrations as versioned capabilities, not product clones. Support current adapters for Codex, Hermes, Claude Code, Gemini, Cursor, Kimi, OpenCode, and compatible generic hook/session sources. Add an extensible path for Pi and other agents without adding a second agent loop or shell.

Show, when available:

- agent type and adapter health;
- workspace and session identity;
- active task and phase;
- current tool/capability;
- pending approval/question;
- jump-back evidence;
- freshness and degraded state.

Automatic integration setup must remain visible, reversible, source-specific, and user-controlled. Installation, repair, or uninstall operations require an explicit user action and immutable receipt.

### 5. Tool use, approvals, and Emergency Stop

Tool calls are capability- and scope-bound. Destructive, external, credentialed, publication, deployment, installation, or permission-changing actions require explicit approval. Approve and deny actions must return through the originating adapter.

Emergency Stop must:

- stop only Orbit-owned mutable work for the active controller generation;
- fail closed on uncertain identity or scope;
- preserve earlier receipts;
- record the stop decision and outcome;
- require a new controller generation before mutation resumes.

### 6. Notch-first interface

- Keep the compact pill as the primary idle surface.
- Preserve transparent space outside the pill.
- Expand into a unified command/workspace panel through one fast reversible morph.
- Match Vibe Island-level perceived quality through timing, hierarchy, continuity, density, and responsiveness, not copied visuals.
- Preserve physical-notch and external-display behavior.
- Support keyboard-only use, VoiceOver, Reduce Motion, Reduce Transparency, Increase Contrast, large text, and visible focus.
- No detached competing panel, duplicated menu item, or second app runtime.

### 7. Immutable receipts

Every command, router decision, tool invocation, approval, denial, setup action, and stop action produces a metadata-only immutable receipt containing:

- command or capability;
- bounded scope;
- actor/adapter identity;
- timestamp;
- policy decision;
- outcome and evidence reference.

Redact prompts, credentials, tokens, personal data, provider secrets, and sensitive source content. Fail closed when identity, scope, approval, or adapter health is uncertain.

## Required Workflow

1. Inspect the current Orbit architecture and worktree.
2. Capture only public behavior references and existing clean-room notes.
3. Write a short ADR defining command/catalog, router projection, adapter capability, and receipt boundaries.
4. Use strict TDD: failing behavior tests before implementation.
5. Implement one bounded vertical slice before broadening the catalog.
6. Run focused verification, then the complete Swift suite.
7. Run docs, localization, accessibility-artifact, security, and performance checks.
8. Run every deterministic runtime scenario.
9. End with a gate-by-gate ship/no-ship report.

## First Vertical Slice

Implement the smallest complete path:

1. `/` opens and filters a cursor-local command catalog.
2. `/status`, `/skills`, `/plugins`, `/tools`, and `/router status` return read-only model projections.
3. One generic adapter-contributed command appears dynamically.
4. Executing a read-only command creates a redacted immutable receipt.
5. Close and reopen `/`; verify a changed catalog is refreshed.
6. Exercise keyboard navigation, Escape, VoiceOver labels, Reduce Motion, and Reduce Transparency.

No mutation-capable command is enabled in this first slice.

## Success Criteria

- [ ] ADR committed before production implementation.
- [ ] Slash catalog supports all listed command identities and plugin contributions.
- [ ] Repeated `/`, multiple slash tokens, cursor movement, post-command `/`, and catalog refresh tests pass.
- [ ] Duplicate skill names require qualification and show sources.
- [ ] Austin Router surface displays truthful non-secret route state.
- [ ] Generic adapter capability discovery covers current Orbit agent sources and an extensible Pi-compatible path.
- [ ] Read-only command execution produces immutable redacted receipts.
- [ ] Approval, denial, and Emergency Stop contracts have tests before they are enabled.
- [ ] Keyboard, VoiceOver, Reduce Motion, Reduce Transparency, and contrast gates pass.
- [ ] Focused tests and the full Swift suite pass.
- [ ] Docs, localization, security, performance, and deterministic runtime scenarios pass.
- [ ] Verification artifacts are written to a dated local directory.
- [ ] Final report explicitly marks every gate passed, failed, skipped, or blocked.

## Approval Boundaries

Do not publish, push, merge, sign, notarize, deploy, contact external services, install hooks, change permissions, change credentials, change providers, or alter production integrations without a separate explicit approval.

## Stop Conditions

Stop with a concrete blocker instead of retrying indefinitely when:

- a clean-room boundary cannot be established;
- the active worktree becomes dirty from unrelated changes;
- an action needs credentials, permissions, external publication, or destructive authority;
- two consecutive attempts fail through the same mechanism;
- deterministic verification contradicts the implementation plan.

## Deliverables

- ADR/design note;
- tested command and catalog model;
- slash palette and Austin Router status surface;
- generic agent/plugin/tool capability model;
- immutable receipt integration;
- regression tests;
- accessibility and runtime artifacts;
- concise PR-ready summary and ship/no-ship report.

## Current Checkpoint

This goal document is the active objective for the current Orbit Development session. The Hermes slash-lookup PR and every non-Orbit infrastructure idea belong to separate sessions and must not interrupt this execution plan.
