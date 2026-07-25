# Overlay Redesign — Design Materials

Vendored copies of the binding design materials for the Open Island overlay
redesign. These files previously lived only outside the repo; they are versioned
here because they **gate** the implementation tickets — the reviewer for a
Poured 2.0 / Flight Deck 2.0 / Halo ticket checks the diff against the spec in
this folder, not against memory.

Everything here is a **verbatim copy** of the approved source material. Do not
edit these files to match the code; when the code and a spec disagree, either the
code is wrong or the spec needs a deliberate, separately-reviewed amendment.

## Contents

| File | What it is |
| --- | --- |
| `BRIEF.md` | The shared design brief every direction was designed against. Diagnosis of the old UI (§1), physical notch context (§2), **ground-truth data model (§3)**, the A–K scenario matrix every board must cover (§4), mockup format rules (§5), **architecture contract (§6)**, and the round-2 fidelity bar (§7). |
| `SPEC-poured-island.md` | Conformance spec for **Poured Island 2.0 · Liquid Glass**. Reconciles the approved mockup against the already-shipped `PouredTheme`: token deltas, the new typography axis, slot-by-slot map, A–K acceptance criteria, conformance checklist. |
| `SPEC-flight-deck.md` | Conformance spec for **Flight Deck 2.0 · Glass Cockpit**. Same structure, targeting the shipped `FlightDeckTheme` (two-tier MASTER WARNING / MASTER CAUTION nomenclature, phosphor glow, sans/mono split, continuous usage tape, STATUS column). |
| `SPEC-halo.md` | Greenfield build spec for **Halo · Intelligence** — a theme that does not exist yet. Full token sheet, typography, slot-by-slot build plan, contract-compliance check, A–K criteria, registry/rollout note. |
| `01-poured-island.html` | Approved mockup board for Poured Island 2.0. |
| `02-flight-deck.html` | Approved mockup board for Flight Deck 2.0. |
| `06-halo.html` | Approved mockup board for Halo. |

The three mockup boards are self-contained single files: all CSS/JS inline, SVG
inline, system font stacks only, **no external network resources** (no CDNs, no
webfonts, no remote images). Open them straight from disk in a browser. Each is a
scrollable dark design board with the §A–K scenarios as labeled frames, and the
live states genuinely animate.

Rejected round-1 boards (`03-annual`, `04-instrument`, `05-meridian`) and
process-only documents (handoff notes, ticket drafts) are deliberately **not**
vendored — they carry no authority over the implementation.

## Reading the mockups: px @1× = pt

**Mockup CSS px at 1× map 1:1 to SwiftUI pt.** The boards are rendered at 1×
logical sizes (the opened overlay is ~520pt wide), so a `padding:14px` in the
mockup means `14` in Swift, an `11px` type size means `.system(size: 11)`, and a
`2px × 13px` tick is a `2 × 13` pt rect. No scaling factor is ever applied. Hex
colors compare directly against the `Color(red:green:blue:)` literals in
`IslandColorTokens.swift`.

## Authority order

When two documents in this folder conflict, resolve in this order:

1. **`BRIEF.md` §3 (ground truth) and §6 (architecture contract) win over
   everything.** §3 fixes what data the app actually has — a spec or mockup that
   implies a field the app cannot compute is wrong, and no ticket may invent one.
   §6 fixes the theme structure (tokens + the 8 swappable slots) and the
   non-negotiable invariants: attention is loudest, the keyboard map
   (⌘Y / ⌘⇧Y / ⌘N, digits 1–9 + Enter, Esc), the exact row verbs
   (approve, answer, reply, jump, dismiss — there is no kill), the shared
   question-prompt semantics, and the closed-pill's duty to communicate count,
   liveness and attention while fusing around the notch cutout. A per-theme spec
   may restyle these; it may not contradict them.
2. **The per-theme spec wins over its mockup.** Each spec was written after the
   board was approved and deliberately corrects it where the board is not
   implementable or not accessible. Those corrections are intentional, not
   drift — e.g. `SPEC-halo.md` §0 raises the mockup's `--t3` white from **0.42
   to 0.50** because 0.42 on black is 3.9:1 and fails the 4.5:1 body-text floor,
   and lifts every sub-10pt caps role to a 10pt floor. Where a spec explicitly
   flags a mockup value as drift and recommends keeping the shipped token
   (e.g. Poured `--t2 .66` vs shipped `0.6`), the spec's recommendation governs.
3. **The mockup is authoritative only for what the spec does not cover** —
   spacing, rhythm, motion feel, and the overall look you are matching. It is the
   picture; the spec is the contract.

If a conflict is genuine rather than an intentional correction, stop and raise it
rather than picking a side in the implementation.
