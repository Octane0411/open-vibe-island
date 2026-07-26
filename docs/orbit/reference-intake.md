# Orbit Reference Intake Ledger

Status: verified intake, recorded 2026-07-25.
Scope: documentation only. This ledger records external sources reviewed for the Orbit GPLv3 fork, the license boundary for each source, and what may flow into this repository. It does not vendor, fetch, sign, publish, or modify any code or dependency.

## Repository Position

- This worktree is the Orbit GPLv3 fork. The `LICENSE` file at the repository root is GNU GPL version 3, and the fork's implementation base is the existing GPL Open Island upstream.
- `/Applications/Vibe Island copy.app` is a proprietary, closed-source application. It is a behavior-only reference: its observable behavior may inform requirements, but no code, assets, or UI elements may be copied from it.

## Verification Note

The license identifications, copyright holders, and candidate areas below were verified by the requesting operator before intake. Per the task boundary for this ledger, no network fetches, dependency downloads, or license re-verification passes were performed while recording this file. Re-confirm license text upstream before any actual code adoption.

## Source Ledger

### 1. CodeIsland (MIT)

- URL: https://github.com/wxtsky/CodeIsland
- License: MIT, Copyright 2026 wxtsky.
- GPLv3 compatibility: compatible, provided the copyright notice and the MIT permission notice are preserved alongside any reused code.
- Candidate study/reuse areas: native notch host geometry, hover/collapse behavior, multi-display fallback, permission UI, terminal jump, settings, configurable shortcuts.
- Do not copy: logos, mascots, sounds, or trademarks.

### 2. headroom-desktop (MIT)

- URL: https://github.com/gglucass/headroom-desktop
- License: MIT, Copyright 2026 Garm Tech BV.
- GPLv3 compatibility: compatible, provided the copyright notice and the MIT permission notice are preserved alongside any reused code.
- Candidate areas: menu-bar desktop health/status patterns, dependency pin/checksum verification, local proxy health, savings analytics.
- Do not copy: commercial branding or subscription/auth flows.

### 3. headroom (Apache-2.0)

- URL: https://github.com/headroomlabs-ai/headroom
- License: Apache-2.0, Copyright 2025 Headroom Contributors.
- GPLv3 compatibility: compatible, provided the Apache license text and any upstream NOTICE content are retained and every modified file carries a prominent notice stating that it was changed.
- Integration stance: prefer the documented local API / MCP / proxy integration surface over vendoring the backend into this repository.

### 4. AgentPeek (commercial, closed source)

- URL: https://agentpeek.app
- License: none found; commercial closed-source product.
- Use boundary: behavioral and requirements reference only. No code, assets, or UI copy of any kind.
- Public features that may inform requirements: multi-agent board, transcripts / tool calls / diffs / cost / tokens, permission prompts, usage windows, widgets, local servers, skills / plugins / config / log routes, saved commands, terminal workspaces, pop-out chat, menu-bar fallback.

## Prioritized Adopt / Integrate / Study-only Table

| Priority | Source | Disposition | Scope |
| --- | --- | --- | --- |
| P1 | Open Island upstream (GPL) | Implementation base | Existing GPL codebase this fork builds on; not an external intake. |
| P1 | CodeIsland (MIT) | Adopt | Native notch host geometry, hover/collapse behavior, multi-display fallback, permission UI, terminal jump, settings, configurable shortcuts — reuse permitted with MIT copyright and permission notices preserved. |
| P2 | headroom-desktop (MIT) | Adopt | Menu-bar desktop health/status patterns, dependency pin/checksum verification, local proxy health, savings analytics — reuse permitted with MIT copyright and permission notices preserved. |
| P3 | headroom (Apache-2.0) | Integrate | Documented local API / MCP / proxy integration only; do not vendor the backend. Apache license/NOTICE retention and prominent modification notices apply to any adopted files. |
| Reference | AgentPeek (closed source) | Study-only | Requirements and behavior notes from public features; clean-room reimplementation only, no code/assets/UI. |
| Reference | Vibe Island copy.app (proprietary) | Study-only | Behavior observation only; no code/assets/UI. |

## Attribution Checklist

Before merging any change that incorporates material from a ledger source, confirm every applicable item:

- [ ] CodeIsland-derived code carries "Copyright 2026 wxtsky" and the full MIT permission notice in the file header or an adjacent notice file.
- [ ] headroom-desktop-derived code carries "Copyright 2026 Garm Tech BV" and the full MIT permission notice in the file header or an adjacent notice file.
- [ ] headroom-derived code retains the Apache-2.0 license text and any upstream NOTICE content, and each modified file carries a prominent notice stating that it was changed.
- [ ] The combined work remains licensed under GPLv3, and any incorporated permissively licensed files are identified as such in their file headers.
- [ ] No logos, mascots, sounds, or trademarks from CodeIsland are present in the change.
- [ ] No commercial branding, subscription flow, or auth flow from headroom-desktop is present in the change.
- [ ] headroom is integrated through its documented local API / MCP / proxy surface, and its backend has not been vendored into this repository.
- [ ] Anything informed by AgentPeek or `/Applications/Vibe Island copy.app` is a clean-room reimplementation from observed behavior, with no copied code, assets, or UI elements.
- [ ] The adopting commit message names the upstream source project and its license.

## Standing Boundaries

- This ledger authorizes study of every listed source and, where a permissive license allows, reuse of code under the stated notice conditions. It does not authorize copying branding, artwork, audio, trademarks, proprietary binaries, or closed-source code from any source.
- New external sources must be appended to this ledger with license evidence before any adoption work begins.
