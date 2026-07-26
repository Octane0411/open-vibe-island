# Orbit Plan v3 Design Critique

**Stage:** Product refinement before implementation
**Evidence:** deterministic runtime captures for closed, session list, approval, question, completion, and long completion states

## Overall impression

Orbit has a credible native notch shell, continuous compact-to-expanded geometry, working agent/session projections, and safe action plumbing. The largest opportunity is not adding more features. It is establishing a decisive hierarchy: one active agent and one next action, with usage and savings serving as evidence rather than competing dashboards.

## First impression

### What works

- The compact pill aligns convincingly with the physical notch.
- Transparent space outside the pill preserves the macOS desktop.
- The ink/fog shell and restrained starfield establish a distinct Orbit identity.
- Approval, question, and completion scenarios already exist as deterministic fixtures.

### What needs work

- Setup notices can out-rank active work visually.
- Agent, project, terminal, state, and metadata badges have similar weight.
- Colored dots carry too much semantic responsibility.
- Usage indicators occupy header space without a consistent truth/freshness grammar.

## Usability findings

| Finding | Severity | Recommendation |
|---|---:|---|
| Active work is not always the first readable object | Critical | Pin one primary session at the top and demote setup/idle information. |
| Approval actions lack enough requester and scope context | Critical | Show agent, reason, target, effects, and `Allow once` wording before approval. |
| Simultaneous requests can compete for one notification surface | Critical | Use an ordered approval inbox; preserve every request and show a pending count without replacing the primary card. |
| A captured click can be mistaken for enforced permission | Critical | Show delivery and adapter acknowledgement separately; failures and expiry must remain visible. |
| Completion cards lack evidence and persistence | Major | Show verified outcome, artifact/evidence count, jump-back, and unread state. |
| Usage can imply precision without freshness | Major | Attach truth state and updated time; use unavailable instead of zero. |
| Idle sessions create vertical sprawl | Major | Collapse inactive sessions behind progressive disclosure. |
| Power control sits near routine controls | Major | Separate destructive controls and preserve confirmation. |
| State relies on color and animated dots | Major | Add explicit verbs and state-specific symbols. |
| Decorative effects can compete with text | Minor | Reduce effects behind content and honor Reduce Transparency. |

## Recommended information hierarchy

### Compact pill

1. Agent identity or recognizable source glyph
2. Explicit state verb: Working, Waiting, Needs approval, Complete, Error
3. Short task label when geometry permits
4. One secondary pressure signal: usage **or** context, whichever is more urgent and trustworthy

### Expanded surface

1. Primary session and current task
2. Required action or verified result
3. Provenance and truth state
4. Usage strip: remaining/reset/source freshness
5. Context strip: input/retained/omitted/confidence
6. Other sessions behind disclosure
7. Settings and destructive controls outside the primary reading path

## Motion critique

- Preserve the existing top-anchored matched-geometry morph.
- Target 160–240 ms for ordinary state changes and 280–420 ms for open/close springs.
- Make transitions interruptible. New approval state must replace an opening animation safely.
- Do not auto-collapse while the pointer or keyboard focus is inside the surface.
- Under Reduce Motion, use opacity and minimal geometry interpolation.
- A completion should settle into a compact unread result before returning to idle.

## Accessibility requirements

- All actions keyboard reachable with logical focus order.
- Escape closes non-blocking expanded states, but never discards an unresolved approval.
- Visible focus ring with at least 3:1 non-text contrast.
- Text contrast at least 4.5:1; large text at least 3:1.
- Buttons target at least 44×44 points where geometry permits; compact controls need equivalent accessible hit regions.
- VoiceOver announces agent, task, state, truth label, usage freshness, and action scope.
- No information conveyed by color alone.
- Reduce Motion and Reduce Transparency produce purpose-built visual states.

## Priority recommendations

1. **Build the active-agent-first state model before polishing individual cards.** It determines every layout and transition.
2. **Normalize usage and context evidence behind explicit truth states.** Never let unavailable data masquerade as zero.
3. **Redesign approval and completion as the two trust-critical cards.** They define whether Orbit feels safe and useful.
4. **Add progressive disclosure for secondary sessions and metrics.** Keep the notch calm.
5. **Make accessibility and reduced-effects fixtures first-class deterministic scenarios.** Do not defer them to final polish.

## Unified approval inbox critique

- Preserve the originating agent identity and project at the top of every request.
- Put capability, redacted target, reason, consequence, scope, and expiry before actions.
- Make `Allow once` the primary positive action; never imply a broader grant than the source supports.
- Keep Deny equally reachable by keyboard and VoiceOver without relying on red/green color.
- When multiple requests exist, show one focused card plus queue position and pending count; never overwrite an unresolved request.
- Disable stale buttons by immutable request identity, not by visual position.
- After action, show Captured, Acknowledged, Rejected, or Expired. Do not call a decision complete before the adapter responds.
- Timeout, source disconnect, and unsupported native response must explain the safe outcome and offer jump-back when available.

## Ship criterion

A new user should identify within two seconds:

- which agent is active;
- what it is doing;
- whether action is required;
- how much provider/context headroom is known;
- whether each displayed metric is live, inferred, stale, or unavailable.
