# Halo · Intelligence — Greenfield Build Spec

Implementation-ready spec derived from the **approved** mockup
`mockups/06-halo.html` ("Halo — Intelligence"), the shared `mockups/BRIEF.md`,
and the repo theme system in `Sources/OpenIslandApp/Theme/*` +
`Sources/OpenIslandApp/Views/Island/*`.

**This is a from-scratch build**, unlike the two sibling specs. There is no
shipped Halo implementation to diff against, so every row below is
`mockup value → proposed token/value → note`, not `unchanged/changed/new`.
Where the two sibling themes (`FlightDeckTheme`, `AnnualTheme`) already prove a
non-vibrancy, flat-panel structure, this spec cribs that structure verbatim and
notes it. Where Poured proves the glow/specular idiom, this spec cribs its
`.shadow`-bleed technique.

Conventions:
- **Mockup px @1× = SwiftUI pt** (brief §5). All px below are pt.
- Hex → SwiftUI is `Color(red: r/255, green: g/255, blue: b/255)`; opacities are
  `.opacity(x)` of white on the pure-black ground.
- The mockup's `--desk` / `.masthead` / `.sec-*` styles are **board chrome** (the
  presentation page), never the overlay — they are excluded from the token sheet.
  Only `.isle`, `.pill`, `.panel`, `.row`, `.hero`, `.opt`, `.meter`, `.empty`,
  and the `§K` motion primitives map to slots/tokens.

---

## 0. Executive summary

Halo is the darkest and most motion-defined theme in the set. Its identity is a
**pure-black (#000000) OLED void** whose **only** chrome is a **1.5pt living
prismatic edge-light** traced around the morphing silhouette. There are no fills,
no cards, no vibrancy — content floats in the black and structure comes entirely
from typography + hairlines. The edge **is** the state channel:

- 95% of the time it is a bare 8%-white hairline (idle).
- Working → a cyan→violet segment **orbits** the perimeter (6s linear).
- Permission → the light **condenses**, warms **amber→magenta**, pulses, and
  **blooms outside** the silhouette (the loudest ambient state).
- Question → a softer **amber (qgold)** edge, gentler pulse.
- Success → a brief **green bloom** that dissolves back to hairline.
- Failure → a **static dim red** segment that does **not** pulse.

Five build headlines:

1. **New pure-black surface token** `surfaceInk = #000000` — darker than every
   shipped ink (`flightDeckInk #08090A` was the previous floor). `usesVibrancy =
   false`, `tintOpacity = 1.0`, `specularTopEdge = nil` — the animated edge
   *replaces* the specular concept entirely.
2. **New edge-light accent table.** The shared `IslandColorTokens` models only
   semantic status slots; Halo needs partner hues (violet, magenta) for the two
   gradient states plus three usage thresholds — these live in a Halo-local
   `HaloEdge` palette (mirroring how `FlightDeckTypography` / `AnnualHairline`
   keep theme-local constants outside the token struct).
3. **The single hardest problem** is the orbiting/morphing perimeter edge-light —
   a masked `AngularGradient` ring on the shared `OpenedIslandSurfaceShape` /
   `V6ClosedPillShape`, with the orbit driven by an independent linear-repeat
   angle so it never collides with the morph's `animatableData` radii (§3a).
4. **Contrast + floor corrections:** mockup `--t3` (white @ 0.42) yields 3.9:1 on
   black (< 4.5:1) → corrected to **0.50** (5.3:1); every sub-10pt caps role is
   lifted to a **10pt floor** (§2), matching the sibling themes' floor discipline.
5. **Larger window insets:** the attention bloom bleeds ~46pt outside the closed
   pill and the permission card's outer glow reaches 48pt — the shadow-inset
   tokens must grow well past every shipped theme (§1b) so `OverlayPanelController`
   never clips the loudest light.

---

## 1. Token sheet (4 axes)

### 1a. Colors — `IslandColorTokens.halo`

**Surface & text ramp** (paper is pure white; the ramp is white @ opacity):

| Role | Mockup | Proposed Swift (`.halo`) | Note |
|---|---|---|---|
| `surfaceInk` (void) | `.isle{background:#000}` | `Color(red:0,green:0,blue:0)` = **#000000** | New floor; darker than `flightDeckInk`. Opaque OLED void. |
| `paper` | text ramp is white | `Color.white` (#FFFFFF) | The ramp applies opacity to this. |
| `surfaceText` | white | `.white` | Matches peers. |
| t1 primary | `--t1 white@.95` | applied ad hoc `paper@0.95` | Headlines/values. 19:1 on black. |
| `secondaryTextOpacity` (t2) | `--t2 white@.63` | **0.63** | 7.4:1 ✅ (repo peers use 0.60 — 0.63 is within tolerance; adopt mockup). |
| `tertiaryTextOpacity` (t3) | `--t3 white@.42` | **0.50** ⚠️ **corrected** | Mockup .42 = **3.9:1 < 4.5:1** on black. Lift to 0.50 (5.3:1). Applies to age/disamb/meta text. |
| `hairlineOpacity` (idle edge / dividers) | `--hair white@.08` | **0.08** | The bare idle edge and row/section dividers. |
| `hairlineOpacityIncreasedContrast` | (implied) | **0.24** | Repo standard; also brightens the idle silhouette edge. |
| `increasedContrastTextBoost` | — | **0.24** | Repo standard. |

Halo-local washes (below the token model — a small `HaloEdge`/`HaloWash` table):
`--hair2 white@.05` (code-block inset stroke), `--lift white@.028` (mono-block
whisper fill).

**Status tints** — each status maps to its *primary* edge hue:

| Role | Mockup hue | Proposed Swift | rgb |
|---|---|---|---|
| `statusRunning` | `--cyan #33dcff` | `rgb(51,220,255)` | working (orbit primary) |
| `statusCompleted` | `--green #5fe39a` | `rgb(95,227,154)` | success bloom |
| `statusWaitingForApproval` | `--amber #ffb14d` | `rgb(255,177,77)` | permission (hottest) |
| `statusWaitingForAnswer` | `--qgold #ffcf7a` | `rgb(255,207,122)` | question (softer) |
| `statusWaitingAggregate` | `--amber #ffb14d` | `rgb(255,177,77)` | roll-up uses attention amber |
| `statusWarning` | `--warn #e6aa42` | `rgb(230,170,66)` | bypass/interrupted amber (= `flightDeckCaution`) |
| `statusInterrupted` | `--warn #e6aa42` | `rgb(230,170,66)` | same amber as warning |
| `statusFailed` | `--red #e0596c` | `rgb(224,89,108)` | static dim red |
| `statusIdle` | `--t3` (dot) | `paper.opacity(0.42)` | a *dot*, not text — .42 fine for a mark |
| `statusInactive` | (dimmer) | `paper.opacity(0.28)` | process gone |

**Halo-local edge accents** (NOT expressible as status slots — the gradient
*partner* stops and usage thresholds; put in `enum HaloEdge`):

| Name | Mockup | Swift |
|---|---|---|
| `violet` (working stop 2) | `--violet #7c5cff` | `rgb(124,92,255)` |
| `magenta` (permission stop 2) | `--magenta #ff5ea8` | `rgb(255,94,168)` |
| `usageFine` | `--fine #5fe39a` | `rgb(95,227,154)` (= green) |
| `usageWarn` | `--wrn #ffcf7a` | `rgb(255,207,122)` (= qgold) |
| `usageCrit` | `--crit #ff6b6b` | `rgb(255,107,107)` |

> **Discipline note (brief §7):** the richer the material, the stricter that
> color = state. Agent identity in Halo is an **achromatic** monogram
> (`.mono-tag` white@.07 fill, white@.63 text) — the edge-light is **never**
> brand-colored. `AgentSession.brandColorHex` is deliberately unused on the edge;
> it may only tint the tiny monogram chip if at all (mockup keeps it grey).

**Edge-light gradient stops per state** (the load-bearing spec — masked
`AngularGradient` stops, angle in degrees measured from the gradient's `from`):

| State | Stops (mockup conic) | Bloom shadow (colored `.shadow`) |
|---|---|---|
| idle | flat `white@.08` (no gradient) | none |
| working | `white@.05 · 0–176°`, `cyan @232°`, `violet @300°`, `white@.05 · 348–360°`; **orbit `from` 0→360° / 6s** | `0 0 26 -10 rgba(96,150,255,.45)` (steady) |
| permission | `amber@.04 @0°`, `amber @40°`, `magenta @84°`, `amber @128°`, `amber@.04 · 190–360°`; **pulse opacity .55↔1 / 1.9s** | `bloompulse` r20→46, `rgba(255,120,90,.5→.85)` / 1.9s |
| question | `qgold@.04 @0°`, `qgold @46–122°`, `qgold@.04 · 190–360°`; **pulse / 2.6s** | `0 0 22 -10 rgba(255,207,122,.4)` (steady) |
| success | `green→cyan→green`; **`okedge` opacity 1→.12 / 3s ease-out** (dissolve to hairline) | `okbloom` r40→0 `rgba(95,227,154,.7→0)` / 3s ease-out |
| failure | `white@.05 · 0–20°`, `red @60–120°`, `white@.05 · 160–360°`; **STATIC — no animation** | none (failure never glows) |

### 1b. Metrics — `IslandMetricsTokens.halo`

| Token | Mockup | Proposed | Note |
|---|---|---|---|
| `openedTopRadius` | `--r 20` | **20** | Morph target (top 0→20). |
| `openedBottomRadius` | `--r 20` | **20** | Morph target (bottom height/2→20). |
| `filletRadius` | plain concave (fused pill) | **0** | Non-vibrancy path — same as Flight Deck/Annual/Instrument. |
| `closedHoverScale` | `.hoverlift scale(1.03)` | **1.03** | Same as Poured. |
| `surfaceShadow` | (void seated on dark desk) | `IslandShadowToken(.black, 0.6, r30, y12)` | Deep so the OLED cutout reads seated; the *state* glows are separate colored shadows. |
| `openedShadowHorizontalInset` | card outer glow 48pt | **40** ⚠️ | Larger than any shipped theme (Poured 28). |
| `openedShadowBottomInset` | card outer glow 48pt | **48** ⚠️ | Must contain permission card `0 0 48 -8`. |
| `closedShadowHorizontalInset` | attn bloom ~46pt outside pill | **40** ⚠️ | Poured is 16 — Halo's bloom is far larger. |
| `closedShadowBottomInset` | attn bloom ~46pt | **44** ⚠️ | Sized to the loudest `bloompulse`. |

Halo-local metrics (below the token model — `enum HaloMetrics`):
- `edge = 1.5` (prismatic edge thickness) — **1.5pt** is the theme's signature.
- `pillRadius = height/2` (= 19 at 38pt) — standard `V6ClosedPillShape`.
- `railWidth = 2`, `railInsetY = 8` (actionable-row edge-lit rail).
- `dot = 8`, `dotBloom = -3 inset, blur 2, opacity .55`.
- `heroRadius = 16`, `heroRingWidth = 1.5`.
- `gridCell = 6`, `gridGap = 3.5`, `gridRadius = 3` (circles — see §4 grid).

> ⚠️ **Biggest metrics finding.** The attention bloom (`bloompulse`
> `0 0 46 -4`) and the hero card outer glow (`0 0 48 -8`) both bleed **outside**
> their silhouettes — the theme's whole point. `OverlayPanelController` sizes the
> overlay window from the shadow-inset tokens, so those tokens must be sized to
> the *worst-case* bloom (attention), not to the idle pill. If they stay at
> Poured/Flight-Deck values the loudest light is clipped at the window edge and
> the "visible across the room" claim fails. This is the same class of issue the
> Poured spec flagged (§3.1 there), amplified.

### 1c. Motion — `IslandMotionTokens.halo` + ambient table

**Transition tokens** (open/close/pop). The mockup gives no explicit spring
numbers for Halo (unlike Poured/Flight Deck), and the identity is a fluid "light
travels" morph — smooth, no bounce, the notch *growing*. Proposed:

| Token | Proposed | Rationale |
|---|---|---|
| `openAnimation` | `.spring(response: 0.46, dampingFraction: 0.86, blendDuration: 0)` | Fluid settle, no overshoot (between Poured .5/.84 and Annual .44/.86). |
| `closeAnimation` | `.smooth(duration: 0.32, extraBounce: 0)` | Clean collapse back to the notch. |
| `popAnimation` | `.spring(response: 0.34, dampingFraction: 0.66, blendDuration: 0)` | A soft "condense" on a new event — light gathering, not a mechanical snap. |
| `openedSurfaceUnmountDelay` | `0.36` | Tracks the close. |

**Ambient / stateful timings** — NOT in `IslandMotionTokens` (which models only
open/close/pop/unmount, as in every shipped theme). These live as Halo view-level
constants (`enum HaloMotion`) exactly as Poured/Flight-Deck keep their leaf
periods. The mockup pins them:

| Motion | Mockup keyframe | SwiftUI realization |
|---|---|---|
| working orbit | `orbit 6s linear infinite` (`--a` 0→360°) | `withAnimation(.linear(duration:6).repeatForever(autoreverses:false))` on a `phase` state → `AngularGradient.angle` (§3a). Monotonic — **not** a `PulseClock` sin. |
| permission edge pulse | `edgepulse 1.9s ease-in-out` (.55↔1) | `PulseClock.phase` (its built-in period ≈ 1.96s ≈ 1.9s — essentially free). |
| permission outer bloom | `bloompulse 1.9s` (r20→46) | same clock → colored `.shadow(radius:)` (Poured `PouredAmberGlow` technique). |
| question edge pulse | `edgepulse 2.6s ease-in-out` | dedicated `easeInOut(2.6).repeatForever(autoreverses:true)`. |
| success bloom | `okedge`/`okbloom 3s ease-out` (bloom→dissolve) | one-shot `.easeOut(3.0)` on appear; settles to hairline. |
| row entrance sweep | `rowsweep` (demo loops 3.4s) | **single pass ~0.7s** `easeOut` on row insert (the demo's loop is illustration only — do **not** port the loop). |
| hero card ring pulse | `edgepulse 2.2s` on `.hero::before` | `easeInOut(2.2).repeatForever(autoreverses:true)`. |
| running glyph wave | `wave 1.05s` (3 bars, delay .13/.26s) | shared liveness-glyph leaf (reuse `UnifiedBars`-style staggered wave). |
| waiting glyph breathe | `breathe 2.4s` | shared glyph leaf, breathe mode. |
| agents-grid waiting dot | `breathe-dot 2s` (.4↔1) | grid tile leaf. |

### 1d. Material — `IslandMaterialTokens.halo`

| Token | Mockup | Proposed | Note |
|---|---|---|---|
| `material` | opaque void | `.hudWindow` | Fallback only — never instantiated (vibrancy off). |
| `blendingMode` | — | `.behindWindow` | Fallback. |
| `appearanceName` | dark | `.vibrantDark` | Fallback. |
| `tintOpacity` | `#000` fully opaque | **1.0** | Fully opaque ink — the void. |
| `specularTopEdge` | none (edge-light replaces it) | **nil** | **The animated 1.5pt perimeter edge is the light channel; it is a per-slot view stroke, not a static top sheen.** An `IslandSpecularEdge` cannot express an orbiting/masked ring, so the material token carries none. |

**Capability flags:**
- `usesVibrancy = false` — the void is opaque `#000`, so `OpenedSurfaceBackground`
  takes the opaque `surfaceInk` path and never builds a vibrancy view. **Reduce
  Transparency is a no-op** (already opaque) — same as Flight Deck/Annual/Instrument.
- `rowIsDrawingGroupSafe = false` — see §3c. Rows are near-chromeless, but the
  actionable-row **rail carries a glow** (`box-shadow`) and the **status dot a
  `::after` bloom** (blur); `.drawingGroup()` would flatten/clip both to row
  bounds. The animated *panel* edge is on the surface shape, not the row, so it
  does not enter this decision — the row's own luminous bleed settles it at
  `false` (matching Poured's reasoning).

---

## 2. Typography spec

The mockup relies on typography + hairlines for **all** structure (there are no
fills), so this is load-bearing. All roles are **SF Pro** (`.system(design:
.default)`) unless marked **mono** (`.system(design: .monospaced)`). A Halo-local
`enum HaloTypography` holds the scale (like `FlightDeckTypography` /
`AnnualTypography`) with `floor = 10` pinned by `HaloThemeTests`.

Fonts (native only, brief §2.6): UI `-apple-system, "SF Pro"` → `.default`; mono
`ui-monospace, "SF Mono"` → `.monospaced`.

**White-to-gray ramp** (opacity of white on `#000`): **t1 0.95** (primary /
values / selected labels) · **t2 0.63** (secondary body) · **t3 0.50**
(*corrected* from .42 — tertiary meta/age/disamb). Idle-edge hairline and dividers
are a separate 0.08 white (not text).

| Role (mockup class) | Mockup | Font | Weight / tracking | Tabular? | Floor |
|---|---|---|---|---|---|
| Pill label (`.lab`) | 12.5 | sans | 400 / −0.01em | no | ✅ |
| Pill mono value (`.lab .mn`) | 11 | **mono** | 400 | no | ✅ |
| Workspace title (`.ws`) | 14 | sans | 600 / −0.01em | no | ✅ |
| Branch disamb (`.disamb`) | 10.5 | **mono** | 400 @ t3 | no | ✅ |
| Activity line (`.act`) | 12.5 | sans | 400–500 | no | ✅ |
| Activity verb (`.act .live`) | 12.5 | sans | 500, cyan | no | ✅ |
| Meta chips (`.chip`) | 10.5 | sans | 500 | no | ✅ |
| Mono chip (`.chip.mn`) | 10 | **mono** | 500 | no | ✅ |
| Age (`.age`) | 11 | sans | 400 @ t3 | **yes** | ✅ |
| Section header (`.grp`) | **10** | sans | 700 / 0.10em UPPER | no | ✅ (at floor) |
| Summary strip label (`.summary`) | 11 | sans | 400 | no | ✅ |
| Summary number (`.b .n`) | 12 | sans | 700 | **yes** | ✅ |
| Outcome badge (`.outc`) | 10.5 | sans | 700 | no | ✅ |
| Jump chip (`.jump`) | 11.5 | sans | 600 | no | ✅ |
| Hero title (`.ht`) | 14 | sans | 650 / −0.01em | no | ✅ |
| Hero subtitle (`.hs`) | 11 | sans | 400 | no | ✅ |
| Command block (`.cmd`) | 12 | **mono** | 600 cmd / 400 | no | ✅ |
| Diff (`.diff`) | 11.5 | **mono** | 400 | no | ✅ |
| Keycap (`.kc kbd`) | 10 | sans | 600 | no | ✅ (at floor) |
| Question text (`.qtext`) | 14.5 | sans | 560 / −0.01em | no | ✅ |
| Option label (`.opt .ol`) | 13 | sans | 600 | no | ✅ |
| Option desc (`.opt .od`) | 11.5 | sans | 400 | no | ✅ |
| Option number (`.opt .num`) | 11 | **mono** | 700 | **yes** | ✅ |
| Q chip (`.q-tag`) | 10 | sans | 700 / 0.05em UPPER | no | ✅ (at floor) |
| Subagent type (`.sty`) | 12 | sans | 600 | no | ✅ |
| Subagent task (`.stk`) | 11 | sans | 400 | no | ✅ |
| Subagent elapsed (`.sti`) | 11 | sans | 400 | **yes** | ✅ |
| Nest header (`.nest-h`) | 10 | sans | 700 / 0.09em UPPER | no | ✅ (at floor) |
| Todo (`.todo`) | 12 | sans | 400 | no | ✅ |
| Assistant body (`.assistant`) | 12.5 | sans | 400 (strong 640) | no | ✅ |
| Assistant inline `code` | 11 | **mono** | 400 | no | ✅ |
| Metadata value (`.mv`) | 12.5 | sans | 560 | no | ✅ |
| Meter value (`.mp`) | 22 | sans | 660 / −0.02em | **yes** | ✅ |
| Empty title (`.et`) | 14 | sans | 600 | no | ✅ |
| Empty subtitle (`.es`) | 12 | sans | 400 | no | ✅ |

**Sub-10pt roles lifted to the 10pt floor** (mockup value → corrected):
- Usage kicker `.fk` **9 → 10**; usage value `.fv` 11 ✅.
- Metadata key `.mk` **9 → 10**; grid key `.mcell .mk` **9 → 10**.
- Threshold pill `.thl` **9.5 → 10**.
- Agent monogram `.mono-tag` **9.5 → 10** (it carries readable characters like
  "S5"/"OC", so it is a *readable* role, not a fitted micro-indicator — lift it,
  unlike the grid's fitted `+N` which stays exempt).
- Multi-select hint kbd (inline `1`–`3`) **10** ✅.

**Numeral rule:** `.monospacedDigit()` on age, all timers (`1m 42s`, subagent
`0m 46s`, duration `14m 08s`), summary counts, question progress (`1 of 2`),
usage percentages + reset countdowns (`2h 10m`, `3d 4h`, `19h`), task counters
(`2 of 5`). Prose and labels stay proportional. Do **not** switch the whole face
to mono — mono is reserved for command/diff/branch/inline-code/pill-value.

---

## 3. Slot-by-slot build plan

Each slot below: what the mockup specifies, the closest existing component to
crib from, and the hardest detail. Sections **3a–3c** carry the special-depth
engineering the task calls out.

### Slot 1 — `closedPill` → `HaloClosedPill`
- **Mockup (§A, §G′, §I′):** 38pt tall, radius = height/2, content in **wings**
  either side of the notch dead-zone (`.core` reserves the camera gap). Left wing
  = liveness glyph (`.gly` filament bars: `wave` run / `breathe` wait / still
  idle) + optional label. Right wing = `×N` count, mini agents-grid (`.agrid`
  circles), a hot attention count (`.cnt.hot` amber→magenta / `.cnt.q` qgold), a
  completion checkmark, or a usage filament. Center label narrates activity
  (`Editing AppModel.swift`, `3 working`, `Approve swift build?`, `Answer
  needed`, `Done · the-automator`, `Interrupted · …`, `Failed · …`). Six ambient
  states A1–A6.
- **Crib from:** `AnnualClosedPill` (same wings/notch-lane structure, flat panel,
  `IslandRightSlotContent` fork) for layout; `PouredClosedPill` for the glow-shadow
  idiom; keep `V6ClosedPill` width math so the morph frame is unchanged.
- **Hardest detail:** the **orbiting/pulsing/blooming edge-light on
  `V6ClosedPillShape`** (§3a) and the attention **bloom that bleeds outside** the
  pill (needs the grown `closedShadowInset` tokens, §1b). The running glyph must
  **travel** into the header on expand (brief §2), not crossfade.

### Slot 2 — `openedHeader` → `HaloHeaderControls` + `HaloUsageSummary`
- **Mockup (§C header, §I):** header splits around the notch (`.ngap 96pt`
  reserved); usage as a thin **light-filament arc** (`.fil` 30pt svg ring, color
  = threshold) + `Claude 5h · 34% · 2h 10m` with **resets-in inline**;
  mute/settings/quit as 26pt circular controls (`.ctl` white@.06) on the right.
- **Crib from:** `AnnualHeaderControls` / `AnnualUsageSummary` (notch-split lane
  layout, resets-in readout) or Poured's conic ring for the arc geometry.
- **Hardest detail:** surfacing **`resetsAt` inline** (today only in `.help()`
  tooltip — §6) while honoring the notch-split width math; the filament arc glows
  (`drop-shadow`) so it inherits the row's `drawingGroup = false`.

### Slot 3 — `sessionRow` → `HaloSessionRow` (+ approval / question / completion bodies)
- **Mockup (§C/§D/§E/§F/§G/§H):** row = `lead` (status dot + monogram) · `body`
  (title line: workspace + `disamb` branch/recency; `act` narrated; `meta` chips +
  jump) · `age` (right) · hover-reveal `dismiss`. A **2pt edge-lit rail** appears
  **only** on the active/actionable row (`.rail` run cyan→violet / perm
  amber→magenta / ques qgold, each with a glow). Row entrance = a faint light
  **sweep**. Bodies:
  - **Approval (§E hero):** `.hero` — void body, **inset amber ring** + outer glow
    + pulsing `::before` ring (the "condensed light"); annunciator; syntax-lit
    command (`.cmd` spans: cmd `#f4f6fb`/600, sub cyan, flag `#8fb6ff`, str green,
    path white@.5, prompt amber@.65); inline diff (`.diff` del `rgba(224,89,108,.11)`
    / add `rgba(95,227,154,.11)`); `Allow once ⌘Y` (amber gradient `#ffce8a→#ffab54`,
    text `#3a2205`) + `Deny ⌘N`; scoped `.scopes` always-allow (`⌘⇧Y` on first);
    Codex `.codex-note` (blue) + single `Jump to Codex ⌘J`.
  - **Question (§F):** `.hero.q` gold ring; `.q-tag` ≤12 chars; progress `1 of 2`;
    numbered `.opt` (ring + tick when selected, square `.num` for multi-select);
    `.opt-other` freeform; `Next/Submit ↵`; digit hint `1`–`3`.
  - **Completion (§H):** outcome badge (`.outc` ok/intr/fail), tabular duration,
    result as `.assistant` rich text, `Jump` primary + Reply/Transcript/Dismiss.
- **Crib from:** `AnnualSessionRow` (74KB — the fullest non-vibrancy row covering
  every state incl. actionable bodies) for structure; `PouredSessionRow`'s
  `PouredAmberGlow` modifier for the hero ring/bloom.
- **Hardest detail:** the **permission hero ring** — a masked `AngularGradient`
  ring on the card's `RoundedRectangle` (heroRadius 16) + pulsing outer glow, and
  the **glow-travel handoff** from the perimeter edge into that ring (§3b). Plus a
  **shell tokenizer** for the syntax-lit command (command/sub/flag/string/path) or
  ship un-highlighted v1 (§6).

### Slot 4 — `sessionList` → `HaloSessionListScaffold`
- **Mockup (§C):** hairline-bounded **summary strip** showing only non-zero
  buckets (`6 total · 2 waiting · 2 running · 2 done`, each with a status dot);
  grouped **section headers** (`.grp` uppercase + tinted dot + count, "Needs you"
  first so attention floats to top); footer (`6 sessions · 2 need you` +
  `Group by project`). Rows separated by 8%-white hairlines.
- **Crib from:** `AnnualSessionListScaffold` (non-zero-bucket filter, four grouping
  modes, hairline rules, quiet footer) — nearly 1:1.
- **Hardest detail:** the section-header tinted dot must read against the pure-black
  void without any fill; keep the "attention floats to top" ordering (shared
  presentation rule — not restyled).

### Slot 5 — `notificationCard` → `IslandNotificationCard` (shared, Halo row)
- **Mockup (§E, §F3):** the single `activeActionableSession` pulls the island open;
  the void body + condensed ring hero; `Show all N` affordance; 10s auto-collapse
  (completions), hover pauses.
- **Crib from:** **shared** `IslandNotificationCard` — Halo's factory delegates to
  it (exactly like Annual/Poured), and its one row routes through
  `sessionRow(isActionable: true)`, so it inherits the amber-ring hero **with no
  parallel card**.
- **Hardest detail:** confirm the shared card imposes **no background** that fights
  the pure-black void (it must render on `#000`), and that the two-tier
  amber/qgold ring renders identically in `.notification` and `.list`.

### Slot 6 — `emptyState` → `HaloEmptyState`
- **Mockup (§J):** monitor glyph (34pt clock, t3), **"All quiet"** (14/600),
  confident subtitle, and a `● Monitoring · 4 workspaces` pill (idle dot + hairline
  ring). Mirrors the A1 idle pill — edge off.
- **Crib from:** `AnnualEmptyState` (purely typographic, no boxes) or
  `PouredEmptyState` (adds a reassurance pill).
- **Hardest detail:** the glyph is the only motion in an otherwise still frame —
  it must be static (no breathing) since Halo's rest state is "edge off, calm";
  keep it a plain dim glyph.

### Slot 7 — `bootstrapPlaceholder` → `HaloBootstrapPlaceholder`
- **Mockup:** no dedicated frame — reuse the empty-state void shell shown while
  probing terminals on cold launch.
- **Crib from:** `AnnualBootstrapPlaceholder` / `FlightDeckBootstrapPlaceholder`.
- **Hardest detail:** must not flash a non-black fill before the void mounts (it is
  already opaque `#000`, so this is trivial vs Poured's gradient-flash risk).

### Slot 8 — `installHint` → `HaloInstallHooksHint`
- **Mockup:** no dedicated frame — a quiet hairline-bounded line with a `SETUP`/tap
  CTA (the positive inverse of §J's monitoring pill).
- **Crib from:** `AnnualInstallHooksHint` / `PouredInstallHooksHint`.
- **Hardest detail:** keep it **quiet** — a hint is not an attention state, so
  **no edge-light / no glow** (color = state discipline, brief §7).

---

### 3a. The animated perimeter edge-light (the hardest engineering problem)

**Goal:** a 1.5pt prismatic ring hugging the *morphing* silhouette
(`OpenedIslandSurfaceShape` when open, `V6ClosedPillShape` when collapsed) that
(i) orbits for working, (ii) pulses for attention, (iii) blooms for success,
(iv) sits static for failure/idle — and never breaks during the morph.

**Recommended realization — masked `AngularGradient` ring (direct analog of the
mockup's `conic-gradient` + `mask-composite: exclude`):**

```
// Fill the whole rect with the state's angular gradient, then reveal only the
// 1.5pt border by masking with the SAME morphing shape's stroke.
AngularGradient(gradient: state.stops, center: .center, angle: .degrees(orbit))
    .mask(
        shape(topRadius: r.top, bottomRadius: r.bottom)   // the SAME shape
            .stroke(lineWidth: HaloMetrics.edge)          // 1.5pt ring
    )
```

- **Morph composition.** The mask uses the *same* `OpenedIslandSurfaceShape`
  instance whose `animatableData` (top/bottom corner radii) the open/close
  transition already drives. So as the silhouette morphs, the ring morphs in
  lockstep — one liquid black body, never a crossfade (brief §2, "the status glyph
  travels"). The pill uses `V6ClosedPillShape(cornerRadius:)` under the same wrap.
- **Orbit vs morph independence — the key insight.** The orbit is an
  **independent** animation on the gradient's `angle` (a `phase` state animated
  `withAnimation(.linear(duration: 6).repeatForever(autoreverses: false))` from 0
  to 360°). It never touches `animatableData`, so the two animations compose
  without conflict: the shape's radii interpolate on their spring while the
  gradient angle rotates linearly. (Contrast with `PulseClock`, whose `sin`-based
  `phase` is monotone-wrong for a linear orbit — reuse `PulseClock` only for the
  *pulse* states, whose ≈1.96s period already matches the 1.9s permission pulse.)
- **Why not Canvas/TimelineView.** A `Canvas` + `TimelineView(.animation)` could
  redraw the stroked path per frame, but it re-evaluates the view body every
  frame and cannot ride the shape's own `animatableData` interpolation, forcing
  you to recompute the morph radii by hand. The masked-gradient approach lets
  SwiftUI's animation system interpolate both the radii (spring) and the angle
  (linear) on the render server — cheaper and morph-correct. Reserve
  Canvas/TimelineView as a fallback only if the mask stroke shows AA seams at the
  concave notch fillet.
- **Perf cost.** One gradient fill + one shape-stroke mask, animated by the
  system (no per-frame Swift re-eval when driven by `withAnimation`). Cheap enough
  for the single always-on panel/pill edge. It runs on exactly **one** surface at a
  time (the open panel *or* the closed pill), plus the hero card ring — not per
  row — so the cost is O(1), independent of session count.
- **`rowIsDrawingGroupSafe` given "rows are chromeless while the panel edge
  animates":** the edge animates on the **surface**, not the row, so it does not
  bear on the row's drawingGroup decision at all. The rows still carry a rail glow
  + dot bloom that `.drawingGroup()` would flatten → keep **`false`** (the panel
  edge is a red herring for this flag; the row's own glow decides it).

### 3b. The "glow travels from pill into the card ring" attention sequence

The mockup's §E filmstrip is three frames: (1) light **fires** at the pill edge →
(2) **travels** down the growing silhouette → (3) **condenses** into the card
ring. Because pill→panel is **one continuously morphing shape**, the perimeter
edge-light (§3a) is already on that shape throughout — so the "travel" is
*emergent* from the morph, not a separate animation:

1. On a permission event, the pill edge switches from idle-hairline (or cyan
   orbit) to the **amber→magenta** attention gradient + `bloompulse` outer glow,
   and the pill performs `popAnimation` (the "condense").
2. The open transition runs; the same masked ring stretches down the growing
   silhouette (the bloom shadow travels with it — visible as the `-16px 0 30px`
   directional glow in the mockup's `travel.f2`).
3. The notification card mounts with its **own** amber ring (`.hero::before`, a
   masked `AngularGradient` on the 16pt-radius card) pulsing at 2.2s.
4. **Emphasis handoff (the polish):** as the card ring fades up, dim the perimeter
   edge's opacity slightly (a luminous cross-fade) so the light reads as
   *condensing* from the whole silhouette into the card boundary — timed to the
   `openAnimation` spring. Both ends stay amber (still attention), so nothing goes
   dark mid-handoff.

Implementation: drive the perimeter attention state and the card ring off the same
`activeActionableSession` phase; the handoff is a linear opacity relationship over
the open transition duration. No new shape math — both are the §3a masked ring at
different radii.

### 3c. Reduce Motion fallback (critical — the state channel is animated light)

Because Halo conveys state through *moving* light, Reduce Motion must degrade the
edge to a **static state-colored 1.5pt hairline** — never drop the hue, or state
becomes illegible. Per-state fallback:

| State | Live | Reduce Motion (static) |
|---|---|---|
| idle | 8%-white hairline | unchanged (already static) |
| working | orbiting cyan→violet | **static** cyan→violet ring at full 1.5pt, no rotation; keep the steady working glow. |
| permission | pulsing amber→magenta + bloom | **static** amber→magenta ring at **peak** opacity + bloom held at its **peak** radius (attention must stay loudest statically). |
| question | pulsing qgold | **static** qgold ring, steady. |
| success | green bloom → dissolve | render the **settled** state (green dot + check), no bloom animation. |
| failure | static red | unchanged (already static). |
| row entrance sweep | ~0.7s light sweep | **no sweep** — row appears. |
| running / waiting glyph | wave / breathe | freezes to a steady state (shared glyph leaf gates on `reduceMotion`, like `PouredPulsingStatusDot` — never even acquires the clock). |

Mechanism: mirror `PouredPulsingStatusDot` / `PouredAmberGlow` — read
`@Environment(\.accessibilityReduceMotion)`; when true, never acquire the orbit
animation or `PulseClock`, and paint the frozen state. The non-animated pairings
(dot / glyph / label / rail / badge — §4 "never color alone") carry state fully
without motion, so Reduce Motion loses zero information.

---

## 4. Contract compliance check

**Attention is loudest.** A `waitingForApproval`/`waitingForAnswer` session
dominates every surface: on the pill it condenses the edge to amber/qgold, pulses,
and blooms outside the silhouette (A3/A4); in the list it sorts into the "Needs
you" section at the top with a 2pt edge-lit rail; exactly one
`activeActionableSession` pulls the island open as the shared
`IslandNotificationCard` (10s auto-collapse for completions, hover pauses, "Show
all N" below). Permission (amber, hottest) outranks question (qgold, softer) by
**hue and shape** — permission blooms, question only pulses.

**Keyboard hints.** Render subtle keycap chips (`.kc kbd`: black@.3 fill, inset
white@.16 ring, white@.78 text):
- Permission: `Allow once ⌘Y`, first always-allow `⌘⇧Y`, `Deny ⌘N`.
- Question: digits `1`–`9` select, `Enter` (↵) submits; `Esc` closes.
- Codex jump: `⌘J` (the real jump shortcut).
Semantics are owned by `OverlayUICoordinator` (shared) — Halo restyles the chips
only. ⚠️ Ensure glyphs track the **real global handler**; do not drift to the
mockup's decorative `↵`/`⎋` on the wrong action (the Flight-Deck spec's caution).

**Shared `StructuredQuestionPromptView`.** Restyle only (qgold tint, ring+tick
selection, void bg, square marker for multi-select, `.opt-other` last). Do **not**
restructure the numbered-options / multi-select / freeform / submit semantics
(brief §6).

**Shared `IslandNotificationCard`.** Halo delegates to it (no fork). Restyling is
limited to what the routed `sessionRow(isActionable:)` body draws (the void + ring
hero); the "Show all N", auto-collapse timing, and hover-pause are inherited
untouched.

**Accessibility gates.**
- **Reduce Motion** → §3c static state-colored hairline. Attention stays loudest
  statically. The single most important gate for this theme.
- **Reduce Transparency** → **no-op** (the void is already opaque `#000`;
  `usesVibrancy = false`). The colored *glow* shadows are the state channel, not a
  material, so they persist (do **not** strip them here).
- **Increase Contrast** → text opacities +0.24 (t1→1.0, t2→0.87, t3→0.74);
  hairline → 0.24; **brighten the idle-edge hairline** (0.08 → 0.24) so the void's
  silhouette boundary is discernible when the edge is off; the bright edge hues
  already clear contrast on black.
- **Dynamic Type** → shared text scaling applies (all roles ≥ 10pt floor, so
  scaling never crosses a sub-legible size).

**Agents-grid geometry.** The mockup's right-wing grid (`.agrid`) is **circles**:
3-col, 6pt cells, 3.5pt gap, `border-radius:50%`, with a per-cell bloom
(`on` = cyan + glow, `wt` = amber breathing 2s, idle = t3). Proposal: reuse
Classic's `balancedRows` matrix (so pill width math + morph frame are unchanged —
same move `AnnualTheme` made) but override `cellGeometry` to `(cell: 6, gap: 3.5,
radius: 3)` so each cell renders as a **bloomed light circle** (radius = cell/2).
Pinned by `HaloThemeTests` (Classic's `AgentsGridLayoutTests` untouched).

```
var agentsGridGeometry: IslandAgentsGridGeometry {
    IslandAgentsGridGeometry(
        balancedRows: { V6RightSlotView.balancedRows($0) },
        cellGeometry: { _ in (cell: 6, gap: 3.5, radius: 3) }  // circles, bloomed
    )
}
```

**"Never color alone" pairings** (every state carries ≥2 non-color channels):

| State | Hue | + shape/glyph | + motion | + label |
|---|---|---|---|---|
| running | cyan/violet | wave glyph bars | orbit 6s | "Editing AppModel.swift" |
| permission | amber/magenta | filled dot + hot count badge | pulse + bloom | "Approve swift build?" |
| question | qgold | breathing glyph + "?" badge | gentle pulse | "Answer needed" |
| success | green | filled dot + ✓ check | bloom→settle | "Done · the-automator" |
| interrupted | warn amber | dot + ▢ stop square | none (no glow) | "Interrupted · niche-radar" |
| failure | red | dot + ✕ cross | **static** (no pulse) | "Failed · open-vibe-island" |
| idle | none | dim dot + still glyph | none | (no label) |

---

## 5. Scenario acceptance criteria (A–K)

Values are the checkable targets (mockup px = pt; "glow" = colored `.shadow`).

### A. Collapsed pill — ambient states
- **A1 idle:** edge = **8%-white hairline** (off); one **dim dot** (`statusIdle`
  white@.42); still 3-bar glyph @ t3; **no glow**. Pill min-width ≈ 214pt, height
  38pt. The calmest frame in the set.
- **A2 working:** cyan→violet segment **orbits** the silhouette (`from` 0→360° /
  **6s linear**); glow `rgba(96,150,255,.45)` r26; `wave` glyph 1.05s (bars
  staggered .13/.26s); label narrates **"Editing AppModel.swift"** (verb dim/t2,
  file mono/t1) — **never** a raw tool id.
- **A2′ many working:** right wing = **agents grid of bloomed circles** (6pt, on =
  cyan + glow `rgba(80,180,255,.7)` r5, idle = t3); left label `**3** working`.
- **A3 permission (loudest):** edge condenses **amber→magenta**, **pulses**
  (`edgepulse` 1.9s .55↔1), bloom **bleeds outside** (`bloompulse` r20→46,
  `rgba(255,120,90,.5→.85)`); right slot `.cnt.hot` = amber→magenta gradient, text
  `#241203`, glow `rgba(255,150,90,.6)` r16; label `Approve swift build?`
  (`build` mono). Readable across the room.
- **A4 question:** edge = **qgold**, gentler `edgepulse` **2.6s**; breathing glyph
  tinted qgold; right badge `.cnt.q` = qgold, text `#241a03`; label `Answer
  needed`. **Distinct from A3 by hue AND shape/label** (question pulses, doesn't
  bloom).
- **A5 just completed:** brief **green bloom** (`okbloom` r40→0 / 3s ease-out) that
  **dissolves back to hairline** (`okedge` opacity 1→.12); `dot.done` + ✓; label
  `Done · the-automator`. A moment, not a permanent badge.
- **A6 outcome variants:** interrupted = warn amber, **▢ stop** glyph, **no glow**,
  label `Interrupted · niche-radar`; failed = **static dim red** edge segment
  (does **not** pulse), **✕** glyph, label `Failed · open-vibe-island`. Visibly
  distinct (§3 truthful outcomes).

### B. Hover peek & morph
- Pointer dwell **0.15s**, pill scales **1.03** (`closedHoverScale`).
- Peek surfaces the single most-actionable session inline (`the-automator wants to
  run a command` + mono `swift build`) and compresses the rest to `+2 more
  sessions`; the amber ring has already begun condensing before the click.
- Morph is **one continuous shape**: top radius **0→20**, bottom radius
  **height/2→20** as the frame grows; the orbiting edge-light **never breaks**
  (§3a); glyph travels into the header (no crossfade); `openAnimation`
  `response 0.46 / damping 0.86`.

### C. Expanded panel — session list
- Header splits around the notch; usage filaments show **resets-in inline**
  (`Claude 5h · 34% · 2h 10m` tabular, `Claude 7d · 78% · 3d`).
- Summary strip shows **only non-zero buckets** (`6 total · 2 waiting · 2 running ·
  2 done`), each dot in its status tint; numbers 12pt/700 tabular.
- Sections grouped so **attention floats to top** ("Needs you" first, amber dot).
- **Duplicate `the-automator`** disambiguated by branch: `feat/bridge-auth`,
  `main`, in **10.5pt mono @ t3** after the workspace name.
- A **2pt edge-lit rail** marks only the two actionable rows (perm amber→magenta,
  ques qgold); running rows get a cyan→violet rail; done/idle rows have **no** rail.
- Rows separated by 8%-white hairlines; hover bg white@.026; every state pairs
  glyph/shape + hue.

### D. Row expanded — detail
- Metadata as a quiet cell grid (`Agent / Model / Permission / Branch / Duration /
  Terminal`); keys 10pt uppercase t3, values 12.5pt t1, mono for branch/dir.
- Activity **narrated** (`Editing AppModel.swift` · compiling OpenIslandCore); last
  assistant message rendered as **rich text** (`.assistant`, bold + inline `code`
  mono 11pt) — not a raw `$ source …` dump.
- **Jump to Ghostty is the primary CTA** (blue-lit chip); Transcript ghost;
  working directory shown mono/dimmed (`~/Developer/open-vibe-island`).
- Dismiss **hover-reveal** (opacity 0→1, scale .82→1 on row hover).

### E. Permission hero (the most-polished frame)
- **Void body** (`#000`) with **inset amber ring** `rgba(255,160,80,.55)` 1.5pt +
  outer glow `0 0 48 -8 rgba(255,140,80,.5)` + pulsing `::before` ring
  (`edgepulse` 2.2s). The light **travels** from the pill edge into this ring
  (§3b).
- **E1 command:** syntax-lit `$ rtk grep -rn "fetch(" packages/ui/src` (cmd
  `#f4f6fb`/600, sub cyan, flag `#8fb6ff`, string green, path white@.5, prompt
  amber@.65); `Allow once` = amber gradient `#ffce8a→#ffab54` text `#3a2205`
  keycap `⌘Y`; `Deny` = `rgba(224,89,108,.13)` text `#f0a6b0` keycap `⌘N`; scoped
  `.scopes` always-allow rows, first carries `⌘⇧Y`, code chips `rgba(255,160,80,.1)`
  text `#ffd6a4`.
- **E2 diff:** real inline diff (del `rgba(224,89,108,.11)` text `#f2b0ba`, add
  `rgba(95,227,154,.11)` text `#a7ecc6`, gutter line numbers) — not a description.
  Same ring + keycaps as E1.
- **E3 Codex:** ring stays **amber** (still attention), but **no fake Approve
  button** — a cool-blue `.codex-note` (`rgba(80,170,255,.09)` + `rgba(80,170,255,.24)`
  ring) and a single blue `Jump to Codex ⌘J` (`#7ec9ff→#4aa3df`, text `#04233a`).
- **E4 notification card:** `Allow ⌘Y / Always ⌘⇧Y / Deny ⌘N`, auto-collapse copy,
  `Show all 6 sessions →`.

### F. Question prompt
- `.hero.q` gold ring; `.q-tag` header ≤12 chars (`Auth`, `Platforms`) on qgold,
  text `#2a2003`; progress `1 of 2` tabular.
- Options carry **human descriptions**; selected = qgold **ring + tick** (`.opt.sel`
  inset `1.5px rgba(255,207,122,.55)`) — state by **shape**, not color alone.
- Multi-select: **square** `.num` (radius 4) with `✓`, `2 selected · toggle with
  digits`; single-select rounded `.num`.
- Freeform `Other…` is always the **last** row; digit hint `1`–`3`; `Next/Submit ↵`.
- Compact single (F3): a yes/no collapses to two tight rows — the notification-card
  variant.

### G. Subagents & tasks (nested)
- Expanded: `3 subagents` nested list, each with a running glyph + type + task +
  **live elapsed tabular** (`1m 18s`, `0m 46s`, `0m 12s`); todo list with
  done (✓ + strikethrough, green) / doing (◷ clock, cyan, `in progress`) / pending
  (hollow ring) by **icon**, not color alone; `2 of 5` done.
- Compressed to the pill (G′): rolls up to a single **`3`** count + a nodes glyph
  (cyan); the orbiting working-light already says "alive". No nested clutter.

### H. Completed session
- Outcome badge `Success` (green ✓ on `rgba(95,227,154,.12)`); result as
  `.assistant` prose (`<strong>` + inline `code`) — not a dump; metadata grid
  (Outcome / Duration `14m 08s` / Model `Opus 4.8` / Finished `2m ago`, tabular).
- Follow-ups: **Jump** primary + Reply (only where the agent supports it) +
  Transcript + **Dismiss** (the honest verb — hides the row, there is no kill).
- The edge has already bloomed green and settled to hairline.

### I. Usage meters
- Full (`.meterc`): thin **light-filament** dials (52pt), filament color =
  threshold — Fine `#5fe39a` (`<70`) + `FINE` word, Warn `#ffcf7a` (`70–90`) +
  `WARN`, Critical `#ff6b6b` (`≥90`) + `CRITICAL`; each shows **resets-in**
  (`resets in 2h 10m` / `3d 4h` / `19h`) tabular. Higher % = more consumed.
- Pill compression (I′): only the **worst** window surfaces — a small crit filament
  + `Codex 94%` (crit red) + `19h`. Fine windows stay silent (usage earns pill
  space only when critical).

### J. Empty state
- Monitor glyph (34pt, t3, **static**); `All quiet` (14/600); confident subtitle;
  `● Monitoring · 4 workspaces` pill (idle dot + hairline ring). Mirrors the A1
  idle pill — edge off. The void "earns its keep by disappearing until it has
  something true to say."

### K. Motion spec strip (all must animate; gated under Reduce Motion)
- Working orbit (6s linear), expand morph (one shape, radius latch + spring
  .46/.86), attention condense (amber→magenta pulse + bloom, 1.9s), success bloom
  (green blooms then dissolves, 3s), row entrance (single light sweep ~0.7s),
  failure (static red, **does not** pulse), idle hairline (edge off), liveness
  glyph (wave/breathe/still). Each maps to a named `HaloMotion` constant; Reduce
  Motion → steady state (§3c).

---

## 6. Conformance checklist + prerequisites

### 6.1 Fixtures needed (map A–K → deterministic demo sessions)

`AppearancePreviewFixtures.sessions` (in `AppearanceSettingsPane.swift`, ~L1155)
ships **5** sessions (approval / answer / running / done / idle). Halo needs the
**same additional** fixtures the sibling specs require — reuse them verbatim where
identical, all `origin: .demo`, fixed `updatedAt` offsets:

| Scenario | Fixture | Shared with siblings? |
|---|---|---|
| A6 | `completed` + `outcome: .interrupted` **and** `.failed` | **shared** (both siblings flag it missing) |
| C | duplicate-workspace pair with **branches** (`the-automator` ×2+) | **shared** |
| D | running + `attachmentState: .attached` + `permissionMode: .acceptEdits` + assistant message | **shared** |
| E1/E2 | permission with **command** (`swift build`/`rtk grep`) and with **fileDiffSource** (old/new Edit) | **shared** |
| E3 | Codex `requiresTerminalApproval == true` | **shared** |
| F | **multi-question (2)** + `multiSelect` + freeform Other + descriptions | **shared** |
| G | Claude `activeSubagents[3]` (agentType/task/startedAt) + `activeTasks[5 mixed]` | **shared** |
| I | usage providers Claude 5h(34)/7d(78) + Codex 7d(94) with **non-nil `resetsAt`** | **shared** |
| J | empty (0 sessions) + hooks-installed flags | **shared** |
| **A5** | **just-completed success within the bloom window** (recent `updatedAt`) so the green bloom→settle renders | **Halo-specific** (bloom is time-sensitive) |
| **A2** | running with narrated activity (`Editing AppModel.swift`) for the orbit + narration | shared, but Halo also needs it at **orbit phase 0** for snapshots |

### 6.2 Token-equality tests to add (`HaloThemeTests`)

Following `AnnualThemeTests` / `FlightDeckThemeTests`, pin every `.halo` value from
§1:
- `surfaceInk == #000000` (assert pure black — the theme's defining value);
  `paper == .white`.
- Status tints: running cyan `#33dcff`, completed green `#5fe39a`, approval amber
  `#ffb14d`, answer qgold `#ffcf7a`, warning/interrupted `#e6aa42`, failed
  `#e0596c`.
- Text ramp: `secondaryTextOpacity == 0.63`, **`tertiaryTextOpacity == 0.50`**
  (the corrected value — pin it so no one restores the failing .42), `hairlineOpacity
  == 0.08`, IC boost 0.24.
- Metrics: opened radii 20/20, fillet 0, hover 1.03, **grown insets 40/48/40/44**
  (pin so window sizing never regresses and clips the bloom).
- Motion: open `.spring(0.46, 0.86)`, close `.smooth(0.32)`, pop `.spring(0.34,
  0.66)`, unmount 0.36.
- Material: `usesVibrancy == false`, `rowIsDrawingGroupSafe == false`,
  `tintOpacity == 1.0`, `specularTopEdge == nil`.
- Halo-local `HaloEdge` accents (violet `#7c5cff`, magenta `#ff5ea8`, usage
  fine/warn/crit) and `HaloMetrics.edge == 1.5`.
- **Type floor:** every readable role ≥ **10** (assert the vector, incl. the
  lifted `.fk`/`.mk`/`.thl`/`.mono-tag`); the fitted grid `+N` exempt.
- **"Never color alone" discipline:** assert each state resolves a shape/glyph
  channel independent of hue (mirroring `AnnualThemeTests`' accent-discipline test).
- Agents-grid geometry: assert `cellGeometry` returns `(6, 3.5, 3)` (circle
  radius) and `balancedRows` delegates to `V6RightSlotView` (pins the deviation
  the way Annual pins its `radius: 0`).

### 6.3 Snapshot pins (time-frozen — Halo-specific requirement)

One deterministic snapshot per frame A1–K, both notch (540) + top-bar (520)
profiles, default + Increase Contrast + Reduce Motion, en + zh-Hans.

⚠️ **The animated edge-light needs a frozen phase.** Expose a
**pause/phase parameter** — an environment key `\.haloEdgePhase` (or an injectable
`HaloClock`) carrying `(orbitAngle: Double, pulse: Double)`, defaulting to the live
clock and **overridable to a fixed value** in snapshot tests. Render snapshots at
**orbitAngle 0 / pulse 0** with **Reduce Motion ON** so the orbit, pulse, bloom and
sweep all render at a settled, deterministic phase. Without this, edge-light
snapshots are non-reproducible. Hero pins: permission ring (E1, amber), diff (E2),
Codex (E3, blue), question (F1/F2, qgold), success bloom-settled (A5), attention
pill (A3, amber bloom), failure static (A6, red).

### 6.4 Judged-by-eye (manual sign-off — cannot be asserted)

- The orbit reads as **smooth traveling light** (no stepping) around the concave
  notch fillet.
- The attention bloom **actually bleeds outside** the pill/panel silhouette
  (grown window insets correct, not clipped).
- The pure-black void reads as an **OLED cutout fused with the physical notch**
  (they share `#000`).
- The morph is **one liquid body** — the ring never breaks or crossfades; the
  glyph travels smoothly.
- The **glow travels** from the pill edge into the card ring (§3b handoff reads as
  condensing, not two separate lights).
- Attention is loud "across the room"; exactly **one** loud thing at a time.
- Failure is visibly **static** (no pulse) vs the pulsing attention states.

### 6.5 Data / plumbing prerequisites (source field per brief §3)

| Prerequisite | Mockup use | Source (§3) | Shared vs Halo |
|---|---|---|---|
| **Resets-in inline** | `resets in 2h 10m` under each filament | `UsageWindowPresentation.resetsAt` | **shared** — computed but only in `.help()` tooltip; promote to a visible readout. |
| **Branch disambiguation** | duplicate `the-automator` rows show `feat/bridge-auth` / `main` | `worktreeGitBranch` (claude only) + `updatedAt` recency | **shared** — needs a list-level duplicate-name detector + disambiguator builder (branch for Claude, else recency). ⚠️ Gate the branch chip on availability — codex/others have no branch (§3). |
| **Hover-reveal dismiss** | `.dismiss` hidden until row hover | `RowActions.dismiss` + `SessionRowContainer.isHighlighted` | **shared** — action exists; gate opacity on `isHighlighted`. |
| **Narrated activity** | `Editing AppModel.swift`, `Orchestrating 3 subagents` | current tool + `currentCommandPreviewText` / `spotlightActivityLineText` | **shared** — needs a verb map (Edit→"Editing", Task→"Orchestrating") translating identifier → sentence (kills §1.2). |
| **Syntax-highlighted command** | `.cmd` spans (cmd/sub/flag/str/path) | `currentCommandPreviewText` (plain) | **shared** — add a lightweight shell tokenizer, or ship un-highlighted v1 (acceptable). |
| **Keycap hints** | `⌘Y / ⌘⇧Y / ⌘N`, `1–3`, `↵`, `⌘J` | shortcuts via `OverlayUICoordinator` | **shared** — render the keycap chips (semantics already registered). |
| **Pane attachment** | `Ghostty · attached` in §D | `SessionAttachmentState` | **shared** — data exists; surface as a metadata value. |
| **Orbit-phase injection for snapshots** | frozen edge-light in tests | (rendering concern) | **Halo-specific** — the `\.haloEdgePhase` parameter (§6.3). |
| **Grown overlay-window insets** | bloom bleeding outside the pill/panel | (rendering concern) | **Halo-specific** — the enlarged shadow-inset tokens must flow into `OverlayPanelController` window sizing (§1b). |
| **Pure-black opaque surface path** | `#000` void | `OpenedSurfaceBackground` opaque path | **Halo-specific** — reuses the `usesVibrancy == false` path, but with a *pure-black* `surfaceInk` (darker than any peer). |

**Honesty (brief §3):** no per-session token/cost, no tool-invocation counter (the
old `×4` was fake), no kill action — the mockup correctly uses **Dismiss** (hide)
and shows subagent/task counts, not invented precision. Keep it that way.

---

## 7. Registry & rollout note

**Identity strings** (append to all three `Localizable.strings`, matching the
bilingual convention at L192–199):

| Key | en | zh-Hans |
|---|---|---|
| `theme.halo.name` | `Halo` | `光环` |
| `theme.halo.descriptor` | `Prismatic edge-light on a true-black void.` | `纯黑虚空中流动的棱彩光边。` |

- `id = "halo"` — data, never localized (the `IslandTheme.id`).
- (Add zh-Hant too: name `光環`, descriptor `純黑虛空中流動的稜彩光邊。`)

**Registry position.** Append `HaloTheme()` to `ThemeRegistry.all` **after**
`AnnualTheme()`, **non-default** — Poured Island stays `all[0]` (the product's
face). Adding a theme is a one-line append + the `IslandTheme` conformance +
strings (architecture.md §"Adding a theme"); nothing in `IslandPanelView` changes.

```
static let all: [any IslandTheme] = [
    PouredIslandTheme(),   // default
    ClassicTheme(),
    InstrumentTheme(),
    FlightDeckTheme(),
    AnnualTheme(),
    HaloTheme(),           // ← appended, non-default
]
```

**Shipped Annual + Instrument themes.** Out of scope to remove. The registry would
then carry **six** themes (Poured, Classic, Instrument, Flight Deck, Annual, Halo).
Whether to retire Annual and/or Instrument to keep the picker tight is a **product
/ user decision** — flag it, do not act on it here. (The theme-plan memo scoped
"4 themes, Poured default"; Flight Deck + Annual + Halo already exceed that, so the
final shipped set is a curation call for the user.)
