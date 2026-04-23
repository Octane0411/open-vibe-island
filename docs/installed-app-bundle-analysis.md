# Installed App Bundle Analysis

Reviewed on 2026-04-02 against the locally installed app:

- bundle: `/Applications/Vibe Island.app`
- version: `1.0.15`
- bundle id: `app.vibeisland.macos`
- analysis branch: `docs/analyze-installed-app-bundle`
- analysis worktree: `<analysis-worktree>`

## Scope

This note is about the installed macOS app bundle and its local runtime footprint on this machine, not the open-source repository implementation.

The goal was to answer:

1. what communication paths the installed app really uses
2. what helper / plugin / extension surfaces it installs
3. whether "ordinary hooks only" can explain the observed feature set

Focused follow-up:

- [App -> Ghostty -> Codex Chain](./app-ghostty-codex-chain.md)

## Executive Summary

No. The installed app is not "just a hook script."

It is a multi-surface local integration product built from these layers:

- a resident menu bar app with a local Unix socket server at `/tmp/vibe-island.sock`
- a bundled helper binary at `Contents/Helpers/vibe-island-bridge`
- auto-installed CLI hook wiring for Claude, Codex, Gemini, and Cursor
- a Claude statusline bridge that writes quota payloads into `/tmp/vibe-island-rl.json`
- IDE extensions for Cursor and VS Code to focus the correct integrated terminal by PID
- Apple Events / AppleScript automation for Terminal and iTerm2
- additional richer integrations beyond plain hooks, especially for Codex and OpenCode
- local session persistence under `~/Library/Application Support/vibe-island/session-terminals.json`

## Bundle Anatomy

Observed inside `/Applications/Vibe Island.app/Contents`:

- main executable: `MacOS/vibe-island`
- helper executable: `Helpers/vibe-island-bridge`
- frameworks: `Sparkle.framework`, `Sentry.framework`
- Sparkle XPC services:
  - `Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc`
  - `Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc`
- resources:
  - custom font `DepartureMono-Regular.otf`
  - onboarding sound
  - `extension-icon.png`

There are no custom macOS app extensions or login items embedded in the bundle besides Sparkle's updater services.

## Confirmed Local Communication Channels

### 1. Unix Socket Ingest

Runtime inspection shows the app itself listening on:

- `/tmp/vibe-island.sock`

Observed with `lsof`:

- process `/Applications/Vibe Island.app/Contents/MacOS/vibe-island`
- open Unix domain socket fd on `/tmp/vibe-island.sock`

This is the main local bridge endpoint.

## 2. Bundled Helper Bridge

The app ships a real helper binary:

- `/Applications/Vibe Island.app/Contents/Helpers/vibe-island-bridge`

The user-facing launcher installed under the home directory is only a wrapper:

- `~/.vibe-island/bin/vibe-island-bridge`

That wrapper:

- looks for the app in `/Applications` and `$HOME/Applications`
- falls back to Spotlight `mdfind` lookup by bundle identifier
- caches the resolved app path in `~/.vibe-island/bin/.bridge-cache`
- then `exec`s the bundled helper inside the app bundle

So the durable integration point is the installed app, not a standalone script copied out of the repo.

### 3. CLI Hooks Across Multiple Tools

The app has modified local CLI config files on this machine:

- `~/.claude/settings.json`
- `~/.codex/hooks.json`
- `~/.gemini/settings.json`
- `~/.cursor/hooks.json`

All of them point to:

- `~/.vibe-island/bin/vibe-island-bridge --source <tool>`

Current observed coverage:

- Claude:
  - `Notification`
  - `PermissionRequest`
  - `PostToolUse`
  - `PreCompact`
  - `PreToolUse`
  - `SessionEnd`
  - `SessionStart`
  - `Stop`
  - `SubagentStart`
  - `SubagentStop`
  - `UserPromptSubmit`
- Codex:
  - `SessionStart`
  - `UserPromptSubmit`
  - `Stop`
- Gemini:
  - `BeforeAgent`
  - `AfterAgent`
  - `BeforeTool`
  - `AfterTool`
  - `SessionStart`
  - `SessionEnd`
- Cursor:
  - `beforeSubmitPrompt`
  - `beforeShellExecution`
  - `afterShellExecution`
  - `beforeMCPExecution`
  - `afterMCPExecution`
  - other response / file / stop hooks

This proves the product is already multi-tool and not Codex-only.

### 4. Claude Statusline Side Channel

Claude is configured with:

- `statusLine.command = $HOME/.vibe-island/bin/vibe-island-statusline`

That script reads Claude JSON from stdin and writes:

- `.rate_limits` payload into `/tmp/vibe-island-rl.json`

So Claude quota / usage display is not coming from ordinary event hooks alone. There is a second path via statusline output.

### 5. IDE Terminal Focus Extensions

Installed extensions found in both:

- `~/.cursor/extensions/vibe-island.terminal-focus-1.0.0`
- `~/.vscode/extensions/vibe-island.terminal-focus-1.0.0`

The extension registers `vscode.window.registerUriHandler(...)` and:

- parses `pid` query parameters from the incoming URI
- scans `vscode.window.terminals`
- compares each terminal's `processId`
- focuses the matching terminal tab

This is an important answer to the "how can it jump so precisely?" question:

- ordinary shell hooks cannot focus the correct integrated terminal tab inside Cursor / VS Code
- Vibe Island solves that by installing an IDE extension and using a URI handler as a second communication channel

### 6. Apple Events for Terminal / iTerm2

The app bundle declares:

- `NSAppleEventsUsageDescription`

and the signed entitlements include:

- `com.apple.security.automation.apple-events = true`

The main binary also contains AppleScript snippets for:

- `tell application "iTerm2" ...`
- `tell application "Terminal" ...`

and strings related to TTY and pane matching.

That means native terminal jump is handled with Apple Events / AppleScript automation, not just shell-side hooks.

### 7. Local Session Persistence

The app stores session state here:

- `~/Library/Application Support/vibe-island/session-terminals.json`

Observed fields include:

- `cwd`
- `tty`
- `currentTool`
- `status`
- `source`
- `firstUserMessage`
- `lastUserMessage`
- `lastAssistantMessage`
- `lastAssistantMessageFull`
- `codexRolloutPath`
- `codexOrigin`
- `codexOriginator`
- `codexThreadSource`

This is a strong signal that the app keeps its own indexed session model for jump-back and summaries.

Hooks alone do not give you a durable multi-session index like this unless the app is persisting and reconciling state.

## Confirmed Extra Plugin / Integration Surfaces

### OpenCode Plugin

Found on disk:

- `~/.config/opencode/plugins/vibe-island.js`

This plugin is much richer than a plain hook bridge:

- connects directly to `/tmp/vibe-island.sock`
- supports fire-and-forget and wait-for-response socket modes
- injects terminal environment details into the tool runtime
- derives TTY by walking the process tree
- writes Ghostty OSC 2 tab titles
- maps OpenCode events into Vibe Island hook-shaped payloads
- handles question replies via:
  - `http://localhost:${serverPort}/question/{id}/reply`
- handles permission replies via:
  - `http://localhost:${serverPort}/permission/{id}/reply`

So for OpenCode, Vibe Island is not merely listening. It actively participates in in-process approval and question response flow.

### Codex Advanced Integration

This is the biggest finding.

The local `~/.codex/hooks.json` only wires:

- `SessionStart`
- `UserPromptSubmit`
- `Stop`

That alone is not enough to explain approval handling, richer session monitoring, or desktop-grade interaction.

But the installed main binary contains these symbols / strings:

- `VibeIsland.CodexAppServerClient`
- `VibeIsland.CodexAppServerManager`
- `VibeIsland.CodexDesktopApprovalWatcher`
- `VibeIsland.CodexSessionWatcher`
- `enableCodexAppServer`
- `webSocketTask`
- `ws://127.0.0.1:0`
- `http://127.0.0.1:`
- `thread/status/changed`
- `waitingOnApproval`
- `/Applications/Codex.app/Contents/Resources/codex`
- `timed out waiting for port from codex app-server stderr`
- `codex app-server process exited before becoming ready`
- `.codex/session_index.jsonl`
- `/.codex/sessions`
- `codex-desktop-approval`

Also observed locally:

- `~/.codex/config.toml` has `[features] codex_hooks = true`
- `~/.codex/.tmp/app-server-remote-plugin-sync-v1` exists

Inference:

- Codex support in the installed app uses more than `hooks.json`
- there is very likely a second local Codex app-server / WebSocket path for richer events and approval watching
- the app also watches Codex session files under `~/.codex`

This matches the intuition that "ordinary hooks" are insufficient for the full behavior.

## External Network / Service Surfaces

Confirmed from `Info.plist`, embedded frameworks, and binary strings:

- Sparkle update feed:
  - `https://edwluo.github.io/vibe-island-updates/appcast.xml`
- release notes:
  - `https://dl.vibeisland.app/release-notes/`
- Sentry ingestion:
  - `https://375861f9d4f0bfd47ed9f9b44b1872fd@o4510782780014592.ingest.us.sentry.io/4510782787289088`
- PostHog analytics:
  - `https://us.i.posthog.com/capture/`
- Anthropic OAuth usage:
  - `https://api.anthropic.com/api/oauth/usage`
- sound pack registry:
  - `https://PeonPing.github.io/registry/index.json`
- LemonSqueezy licensing / checkout strings are also present

So the installed app communicates both locally and externally.

## Plugin / Helper Inventory

Confirmed present:

- bundled helper binary:
  - `Contents/Helpers/vibe-island-bridge`
- home-level bridge launcher:
  - `~/.vibe-island/bin/vibe-island-bridge`
- Claude statusline helper:
  - `~/.vibe-island/bin/vibe-island-statusline`
- Cursor extension:
  - `~/.cursor/extensions/vibe-island.terminal-focus-1.0.0`
- VS Code extension:
  - `~/.vscode/extensions/vibe-island.terminal-focus-1.0.0`
- OpenCode plugin:
  - `~/.config/opencode/plugins/vibe-island.js`
- Sparkle updater XPC services:
  - `Downloader.xpc`
  - `Installer.xpc`

Not observed:

- custom login item in `~/Library/LaunchAgents`
- custom app extension bundles inside the Vibe Island app itself

## Hook Management Evidence

The main binary contains strings indicating hook lifecycle management:

- `hooks.json.backup`
- `settings.json.backup`
- `hookRepairTimestamps`
- `hookRepairMaxPerHour`
- `com.vibe-island.repairHooks`
- `com.vibe-island.repairHooksCompleted`
- `Hooks are configured automatically when a CLI tool is detected.`

So hook install / repair is a managed subsystem, not a one-time manual write.

## Why Plain Hooks Are Not Enough

The installed app's feature set depends on multiple capabilities that plain hooks do not provide by themselves:

- persistent local socket server
- synchronous approval reply path
- IDE tab focusing through installed extensions
- Apple Events automation for native terminals
- local session persistence and reconciliation
- statusline-based quota ingestion
- OpenCode in-process reply loop over localhost HTTP
- likely Codex desktop app-server / WebSocket integration

Hooks are only one ingress layer.

## Most Important Architectural Takeaway

If we want Vibe Island OSS to approach the behavior of the installed app, the right mental model is:

1. hooks for basic event ingress
2. a resident local bridge/server
3. per-tool adapters beyond hooks where needed
4. IDE extensions for precise terminal tab focus
5. native terminal automation via Apple Events
6. local session index / persistence for jump-back and context

Trying to reproduce the installed product with hooks alone would leave out the core jump and approval experience.

## Repro Commands

The main commands used for this analysis:

```bash
find '/Applications/Vibe Island.app/Contents' -maxdepth 3 -print | sort
plutil -p '/Applications/Vibe Island.app/Contents/Info.plist'
codesign -d --entitlements :- '/Applications/Vibe Island.app'
otool -L '/Applications/Vibe Island.app/Contents/MacOS/vibe-island'
strings -a '/Applications/Vibe Island.app/Contents/MacOS/vibe-island'
lsof -nP -U | rg '/tmp/vibe-island.sock|vibe-island'
sed -n '1,260p' ~/.claude/settings.json
sed -n '1,260p' ~/.codex/hooks.json
sed -n '1,260p' ~/.cursor/hooks.json
sed -n '1,260p' ~/.gemini/settings.json
sed -n '1,260p' ~/.config/opencode/plugins/vibe-island.js
sed -n '1,260p' ~/.cursor/extensions/vibe-island.terminal-focus-1.0.0/extension.js
sed -n '1,220p' ~/Library/Application\ Support/vibe-island/session-terminals.json
```

## Confidence Notes

Confirmed directly:

- bundle contents
- entitlements
- socket presence
- local hook config
- installed extension/plugin files
- session persistence file
- external endpoint strings

Inference with strong evidence but not directly exercised in this pass:

- the full Codex desktop app-server / WebSocket flow
- the exact runtime conditions that activate `CodexDesktopApprovalWatcher`
- the exact URI scheme used by the IDE terminal-focus extension
