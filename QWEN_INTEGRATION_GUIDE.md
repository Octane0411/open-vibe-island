# Qwen Code Integration & State Machine Guide

This document outlines the architectural decisions, challenges solved, and implementation details for deeply integrating Qwen Code (`qwen-cli`) into the Open Island ecosystem.

## 1. The Dual-Track State Machine Challenge

Open Island tracks CLI agents using two distinct and parallel systems:
1. **Process Discovery (Polling)**: A background task (`sessionAttachmentMonitorTask`) uses `lsof` and `ps` to scan the OS every ~2 seconds to find running agent processes and their working directories.
2. **Hook Events (Push)**: The CLI tool actively sends Unix socket events (`sessionstart`, `userpromptsubmit`, `sessionend`, etc.) directly to the Open Island `BridgeServer`.

### The Flaky Polling Problem (The "Flashing Card" Bug)
CLI tools like `qwen-cli` are frequently invoked via Node.js package managers (`npx`, `bun`, `npm`, `yarn`, `pnpm`). These wrappers create deeply nested process trees. Process polling can easily miss the actual agent process for a few seconds during high CPU load or complex package manager resolutions.

*   **Previous Behavior**: If the poller missed a process twice (about 4 seconds), the State Machine forcefully marked the session as `isSessionEnded = true` and `phase = .completed`. This caused the UI card to unexpectedly disappear ("flash" out of existence) right in the middle of a task, only to reappear when the actual `sessionend` hook finally arrived.
*   **The Solution (Hook Fallback)**: Hook-managed sessions primarily rely on hook lifecycle signals (`SessionStart` / `SessionEnd`). However, if the terminal crashes or the bridge becomes unavailable, the `sessionend` hook may never arrive, leaving the session permanently stuck as visible. As a fallback, we check process liveness: when the agent process is confirmed dead by two consecutive polls, we forcefully mark the session ended (`isSessionEnded = true`, `phase = .completed`) so it can be cleaned up and smoothly animate out.

## 2. Process Identification Details

To successfully map a Qwen terminal window to its UI card, `ActiveAgentProcessDiscovery.swift` handles several edge cases:

*   **Package Manager Penetration**: The `isAgentProcess` matcher accepts commands starting with `node`, `npx`, `bun`, `npm`, `pnpm`, or `yarn`, as long as the relevant agent executable name (for example `qwen` or `qwen-cli`) appears later in the argument list.
*   **Transcript Segregation**: Claude Code and Qwen Code use different local storage paths. The discovery engine's `bestClaudeTranscriptPath` selects the appropriate project root based on `isQwen` (for example `/.claude/projects/` vs `/.qwen/projects/`) rather than merging searches across both trees, which avoids cross-contamination.

## 3. UI Lifecycle & The "Zombie Session" Prevention

Achieving the exact 5-second graceful exit animation after a task finishes required solving a deeply hidden race condition known as the "Zombie Synthetic Session" bug.

### The Zombie Bug Anatomy:
1. `qwen-cli` finishes its task and sends the `sessionend` hook.
2. The UI correctly displays the completed green card for 5.0 seconds (managed by `islandPresence`).
3. After 5 seconds, the card smoothly animates out of the Notch and the list. `isVisibleInIsland` evaluates to `false`.
4. `SessionState.removeInvisibleSessions()` executes garbage collection and purges the session from memory to save RAM.
5. **The Race Condition**: The user's terminal window is still open (`isProcessAlive == true`).
6. The background Process Poller runs its 2-second scan, sees the Qwen terminal process, but finds *no matching session in memory* (because we just deleted it).
7. The Poller mistakenly assumes this is an untracked agent and instantly generates a new "Synthetic Session"—a fake `Running` card (blue dot) with no chat history that cannot be dismissed until the user completely quits the terminal app.

### The Tombstone Solution:
We changed the garbage collection filter in `SessionState.removeInvisibleSessions()`. 

*   **Old Filter**: `session.isVisibleInIsland`
*   **New Filter**: `session.isVisibleInIsland || session.isProcessAlive`

**Result**: Once a task finishes, it disappears from the user's view (Notch/List), but its data structure acts as a "tombstone" in the memory pool for as long as the terminal remains open. When the Process Poller scans the terminal, it matches the tombstone, realizes the session is already completed, and safely ignores it. Synthetic zombies are completely eradicated.

## 4. Metadata Synchronization & Context Preservation

Qwen's metadata is synchronized via `BridgeServer.swift` -> `synchronizeQwenMetadata()`. 

To ensure the UI collapsed card always displays the initial user request (e.g., `You: Create a python script`) instead of remaining blank after completion:
*   The bridge intercepts the `sessionstart` hook event in addition to `userpromptsubmit`.
*   It populates `initialUserPrompt` and `lastUserPrompt` with the provided prompt or title data immediately upon session creation.
*   This data flows seamlessly through `AgentSession+Presentation.swift` directly into the Spotlight UI components, ensuring the context is preserved even after the agent finishes execution.
