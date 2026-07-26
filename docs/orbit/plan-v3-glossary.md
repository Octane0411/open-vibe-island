# Orbit Plan v3 Glossary

## Orbit

The GPLv3 macOS product built from the Open Island implementation base. Orbit is the single runtime, notch/menu-bar owner, state owner, settings owner, and user-facing activity surface.

## Active agent

The session selected by attention arbitration as the most important session to show now.

## Attention arbitration

The deterministic policy that selects one primary surface: approval/question, then error, active work, unread completion, and idle.

## Compact pill

The collapsed notch or top-center surface. It communicates the active agent state first and may show one quiet usage or context-pressure signal.

## Expanded surface

The progressive-detail surface opened by click, hover/focus policy, or an allowed attention event. It shows one primary session plus secondary usage and context evidence.

## Provider usage snapshot

A normalized, timestamped observation of provider consumption, remaining allowance, reset timing, and source quality. Fields may be unavailable when a provider does not expose them.

## Usage pressure

A derived, bounded signal such as normal, elevated, or critical. It is never inferred from missing data.

## Context budget

The target and reserved token capacity used to assess whether metadata-described context fits, requires compaction, or requires redaction.

## Context savings evidence

A report of estimated input, retained, and omitted tokens linked to a compaction or omission event. It does not claim monetary savings without authoritative usage and pricing data.

## Savings confidence

The quality of a savings estimate: measured, estimated, or unavailable. The UI must not visually blur these categories.

## Truth state

The provenance quality attached to a value:

- **live** — observed from the current authoritative source;
- **inferred** — derived from bounded local evidence;
- **stale** — previously observed but beyond its freshness window;
- **unavailable** — not exposed, inaccessible, or invalid.

## Receipt

An immutable bounded local record of an action. It stores metadata and outcome, never raw prompts, commands, transcripts, file contents, or secrets.

## Provenance

The adapter, session, source timestamp, and confidence that explain where a displayed state or metric came from.

## Degraded state

An honest UI state used when Orbit cannot verify a session, usage source, terminal target, or savings estimate. Agents continue running.

## Fail open

Orbit failure or loss of observability must not stop or alter the originating coding agent.

## One-panel ownership

The invariant that one Orbit process and one AppModel own the overlay panel and its state. No reference integration may create a second notch owner.

## Clean-room parity

Independent implementation of publicly observable interaction goals without copying proprietary code, assets, branding, binaries, or undocumented internals.

## Vibe Island quality target

The desired level of physical-notch fit, morph continuity, information hierarchy, motion restraint, settings depth, and perceived polish. It is not a license to copy protected implementation.

## Usage adapter

A read-only normalizer that converts a supported provider's available usage fields into Orbit's provider-neutral snapshot without owning credentials.

## Context adapter

A metadata-only source that reports token estimates, compaction events, and provenance without exposing conversation content.

## Unread completion

A verified result that remains visible after collapse until the user has reviewed or dismissed it.

## Calm mode

An optional presentation policy that suppresses low-priority automatic expansion during full-screen, presentation, or focus-sensitive work. It never hides approvals or errors silently.

## Approval request

A correlated, time-bounded request from an originating agent adapter for a specific capability, target, scope, and reason. It remains owned by its source even when Orbit presents it.

## Approval decision

An immutable allow, deny, timeout, or cancellation outcome associated with exactly one request and one decision ID.

## Denial

An explicit refusal returned to the originating adapter. Timeout, stale state, and adapter failure are represented separately but never converted to allow.

## Capability

The action class requested by the agent, such as writing a file, running a command, accessing a network resource, or changing a setting.

## Scope

The least-privilege boundary of a decision: one request, one session, or a bounded time period when the source explicitly supports it.

## Correlation ID

The source-stable identifier used to match one displayed request, one decision, and one adapter acknowledgement. It prevents stale or duplicate UI actions from resolving the wrong request.

## Origin adapter

The provider-specific bridge that received the request and must translate Orbit's decision back into the source agent's supported semantics.

## Enforcement authority

The originating agent or adapter that actually permits or blocks the requested operation. Orbit presents and brokers decisions but does not silently replace this authority.

## Approval inbox

The ordered set of unresolved cross-agent requests. One request may be primary while all others remain independently visible and resolvable.

## Timeout policy

The rule that an expired or unreachable request becomes expired or denied according to source semantics, never allowed.
