# Poured Island 2.0 · Liquid Glass — Conformance Spec

Implementation-ready spec derived from the **approved** mockup
`mockups/01-poured-island.html` ("Poured Island 2.0 — Liquid Glass"), the shared
`mockups/BRIEF.md`, and the shipped theme in
`Sources/OpenIslandApp/Theme/*` + `Sources/OpenIslandApp/Views/Island/Poured*.swift`.

Conventions:
- **Mockup px at 1× = SwiftUI pt** (brief §5). All px below are pt.
- Verdict column: **unchanged** (mockup == shipped), **changed** (differs, spec
  adopts mockup), **new** (no shipped equivalent — mockup adds it).
- Hex from Swift `Color(red:green:blue:)` literals is rounded to 8-bit
  (`round(component*255)`).
- The mockup was authored to reuse Poured's real tokens, so most rows are
  **unchanged** and this spec is mostly a *fidelity contract*, not a redesign.
  The deltas are called out explicitly.

---

## 0. Executive summary of deltas

The shipped Poured theme already carries this direction's identity. Only these
diverge from the mockup and must be reconciled:

1. **New attention-glow color** `--attn #ffb14d` / `--attn-hot #ff9d5c`, distinct
   from the shipped `statusWarning #d98c26`. The mockup glows the permission hero
   and the closed-pill attention state in the *brighter* amber; the shipped
   `PouredApprovalCard` glows in `statusWarning`. → add color tokens.
2. **New surface body gradient** (`--glass`, 3-stop vertical) + **new secondary
   ink** `--ink-2 #121622`. Shipped surface is a *flat* `surfaceInk` tint over
   vibrancy; the mockup carries elevation by inner luminance (lighter top → darker
   bottom). → add a material/gradient token.
3. **New hard 1px specular edge** `--specular inset 0 1px 0 rgba(255,255,255,.14)`
   layered *in addition to* the shipped 26pt soft sheen (`specularTopEdge`,
   opacity 0.5). → second specular layer.
4. **Typography becomes a token axis** (today hardcoded per slot view; see §2).
   The mockup also **drops monospace chrome**: shipped Poured uses
   `design: .monospaced` for section headers, summary strip, badges, age and
   usage labels; the mockup uses proportional SF Pro + `tabular-nums`, reserving
   mono strictly for code / branch / command. → largest visual change.
5. **Identity ticks replace capsule agent badges.** Shipped row draws a colored
   mono capsule (`agentBadge`); the mockup draws a **2pt × 13pt vertical tick**
   before the workspace name and demotes agent identity to a small dot+label chip
   only where needed (§1.5, "identity stays a whisper").
6. Minor opacity drift to reconcile: mockup `--t2 = .66` vs shipped
   `secondaryTextOpacity 0.6`; mockup `--hair = .09` vs shipped
   `hairlineOpacity 0.08` (both flagged; recommend keep shipped values — the
   mockup's own comment says `.6`, so `.66` is drift).

---

## 1. Token sheet (4 axes)

### 1a. Colors — `IslandColorTokens.poured`

Surface inks & paper:

| Role | Mockup | Shipped Swift (`.poured`) | Verdict |
|---|---|---|---|
| Ink (surface) | `--ink #0b0e16` | `pouredInk = rgb(0x0b,0x0e,0x16)` = #0b0e16 | unchanged |
| Ink-2 (secondary) | `--ink-2 #121622` | — (flat ink only) | **new** |
| Paper | `--paper #f2f5fb` | `pouredPaper = rgb(0xf2,0xf5,0xfb)` = #f2f5fb | unchanged |
| Glass-fillet fill | `--glass-fillet rgba(20,25,36,.92)` = #141924@0.92 | driven by `filletRadius`, filled with `surfaceInk` | **new** (distinct fillet tint) |

Status tints (all shared with Classic; the mockup lifts them verbatim):

| Role | Mockup | Shipped Swift | Verdict |
|---|---|---|---|
| running | `--run #6ea7ff` | `statusRunning = rgb(110,167,255)` = #6ea7ff | unchanged |
| completed | `--done #6fb982` | `statusCompleted = rgb(111,185,130)` = #6fb982 | unchanged |
| waitingForApproval | `--approve #f4a4a4` | `statusWaitingForApproval = rgb(244,164,164)` = #f4a4a4 | unchanged |
| waitingForAnswer | `--answer #ffd58a` | `statusWaitingForAnswer = rgb(255,213,138)` = #ffd58a | unchanged |
| waiting aggregate | `--aggregate #e7a762` | `statusWaitingAggregate = rgb(231,167,98)` = #e7a762 | unchanged |
| warning / interrupted | `--warn #d98c26` | `statusWarning = statusInterrupted = rgb(0.85,0.55,0.15)` = #d98c26 | unchanged |
| failed | `--fail #db5252` | `statusFailed = rgb(0.86,0.32,0.32)` = #db5252 | unchanged |
| idle | (`--t3`, no separate) | `statusIdle = pouredPaper@0.35` | unchanged |
| inactive | — | `statusInactive = pouredPaper@0.38` | unchanged |

Attention glow (the "one loud thing" — the direction's thesis color):

| Role | Mockup | Shipped Swift | Verdict |
|---|---|---|---|
| attention glow | `--attn #ffb14d` | approval card glows in `statusWarning #d98c26` | **new** (brighter than warning) |
| attention hot | `--attn-hot #ff9d5c` | — | **new** |
| attn count badge fill | `--attn #ffb14d`, text `#2a1c05`, glow `rgba(255,177,77,.55)` | `count.attn` n/a — pill count is neutral | **new** |

Agent brand (identity accents only — **verified truthful** against
`AgentSession.brandColorHex`):

| Agent | Mockup | Swift `brandColorHex` | Verdict |
|---|---|---|---|
| claude | `--claude #d97742` | `#d97742` | unchanged |
| codex | `--codex #4aa3df` | `#4aa3df` | unchanged |
| cursor | `--cursor #7a5cff` | `#7a5cff` | unchanged |
| gemini | `--gemini #42e86b` | `#42e86b` | unchanged |
| opencode | `--opencode #ffb547` | `#ffb547` | unchanged |
| kimi | `--kimi #fde047` | `#fde047` | unchanged |

Text ramp / hairline (applied as opacity of `paper`):

| Tier | Mockup | Shipped Swift | Verdict |
|---|---|---|---|
| t1 (primary) | `--t1 paper@.96` | applied ad hoc (title ≈ `paper@0.9–0.96`) | unchanged |
| t2 (secondary) | `--t2 paper@.66` | `secondaryTextOpacity 0.6` | changed (drift — **recommend keep 0.6**; mockup comment itself says `.6`) |
| t3 (tertiary) | `--t3 paper@.5` | `tertiaryTextOpacity 0.5` | unchanged |
| hairline | `--hair paper@.09` | `hairlineOpacity 0.08` (IC 0.24) | changed (drift — **recommend keep 0.08**) |
| IC text boost | — | `increasedContrastTextBoost 0.24` | unchanged |
| hairline IC | — | `hairlineOpacityIncreasedContrast 0.24` (mockup implies .24 fine) | unchanged |

### 1b. Metrics — `IslandMetricsTokens.poured`

| Token | Mockup | Shipped Swift | Verdict |
|---|---|---|---|
| opened top radius | `--r 26px` | `openedTopRadius 26` | unchanged |
| opened bottom radius | `--r 26px` (morph target) | `openedBottomRadius 26` | unchanged |
| notch fillet radius | `--fillet 12px` | `filletRadius 12` | unchanged |
| closed pill height | `38px` (`.pill`) / `40px` (`.pill.big`) | notch height ~38 (24 top-bar), from `OverlayPanelController` | unchanged (env-driven) |
| closed pill radius | `19px` (= height/2) | height/2 (`V6ClosedPillShape`) | unchanged |
| hover scale | `1.03` (`.hover-lift`) | `closedHoverScale 1.03` | unchanged |
| surface shadow | `--shadow 0 18px 34px rgba(0,0,0,.5)` | `surfaceShadow black@0.5, r34, y18` | unchanged |
| opened shadow H inset | (window sizing) | `openedShadowHorizontalInset 28` | unchanged |
| opened shadow bottom inset | (window sizing) | `openedShadowBottomInset 34` | unchanged |
| closed shadow H inset | — | `closedShadowHorizontalInset 16` | unchanged |
| closed shadow bottom inset | — | `closedShadowBottomInset 18` | unchanged |
| panel width | `520px` (`.panel`) / `440px` (`.narrow`) | 540 notch / 520 top-bar (`OverlayPanelController`) | unchanged (env-driven; mockup ≈ top-bar) |
| list max height | `560px` scroll | `maxSessionListHeight 560` | unchanged |
| list side inset | `16px` (mockup panel) | 46 notch / 16 top-bar (`sideInset`) | unchanged (env-driven) |
| identity tick | `2px × 13px`, r1 | — (capsule badge today) | **new** |
| leading status bar | `3px` glow bar | `width 3`, glow shadow r4 | unchanged |

### 1c. Motion — `IslandMotionTokens.poured` + ambient (non-token) timings

**Transition tokens** (open/close/pop) — the mockup's masthead states
"Morph spring · resp .5 · damp .84", matching shipped exactly:

| Token | Mockup | Shipped Swift | Verdict |
|---|---|---|---|
| open (morph) | spring resp .5 / damp .84 | `openAnimation .spring(response:0.5, dampingFraction:0.84, blendDuration:0)` | unchanged |
| close | (implied smooth) | `closeAnimation .smooth(duration:0.34, extraBounce:0)` | unchanged |
| pop (new-event) | (implied) | `popAnimation .spring(response:0.34, dampingFraction:0.55, blendDuration:0)` | unchanged |
| opened unmount delay | — | `openedSurfaceUnmountDelay 0.4` | unchanged |

**Ambient / stateful CSS keyframes** — these are **not** in `IslandMotionTokens`
today; they live as literals in leaf views (`PulseClock`, `easeInOut`
`.repeatForever`). The mockup pins explicit periods the shipped values must match
or the spec should promote to tokens:

| Motion | Mockup keyframe | Shipped equivalent | Verdict |
|---|---|---|---|
| pill breathing ("working") | `lumen` 3s ease-in-out, glow `rgba(110,167,255,.16)` @ r22 | leaf `easeInOut` breathing via `PulseClock`; **no closed-pill breathing shipped** | changed / **new** (pill breathing not implemented) |
| attention pulse (approval) | `attnpulse` 1.9s, glow `rgba(255,177,77,.28→.55)` r18→34 +4px spread | `PouredAmberGlow` (15fps `PulseClock`, two shadows r10→18 / r20→30, `statusWarning`) | changed (color + radii differ; adopt mockup amber & radii) |
| hero pulse (card border) | `heropulse` 2.4s, inset border `rgba(255,177,77,.24→.4)` + outer glow | approval border `amber@0.5` static + `PouredAmberGlow` | changed |
| success settle | `settle` 2.6s ease-out: white flash → green → fade | completion → static check + glow; **no settle animation** | **new** (success settle not implemented) |
| status-dot breathe | `breathe` 2.6s | `PouredPulsingStatusDot` (scale +0.2, glow r5→9) via 15fps clock | unchanged (intent) |
| running glyph bars | `wave` 1.05s (3 bars, staggered .14s) | `UnifiedBars` mode | unchanged (intent) |
| usage-ring danger glow | `easeInOut .8s` breathe | `PouredUsageRing` `glowPulse easeInOut 0.8s` | unchanged |
| agents-grid waiting tile | breathe | `PouredWaitingTile easeInOut 0.7s` | unchanged (period 0.7 vs mockup n/a) |
| pill layout width | `timingCurve(.4,0,.2,1) .45s` | `PouredClosedPill.pillLayoutAnimation timingCurve(0.4,0,0.2,1,0.45)` | unchanged |
| morph filmstrip | top r 0→26, bottom r height/2→26 as frame grows | `NotchShape` morph (brief §2 model) | unchanged |

CSS-cubic → SwiftUI mapping note: the mockup's `morph` demo uses
`cubic-bezier(.2,.7,.2,1)` purely for the *looping filmstrip demo*; the real
morph is the `spring(.5/.84)` token. Do **not** port the demo bezier.

### 1d. Material — `IslandMaterialTokens.poured`

| Token | Mockup | Shipped Swift | Verdict |
|---|---|---|---|
| blur | `backdrop-filter: blur(24px)` | `.hudWindow` (system blur) | unchanged (intent) |
| saturation | `saturate(1.3)` | — (not a token) | **new** (add saturation, or accept `.hudWindow` default) |
| blending | behind-window | `blendingMode .behindWindow` | unchanged |
| appearance | dark | `appearanceName .vibrantDark` | unchanged |
| ink tint opacity | (baked into gradient) | `tintOpacity 0.5` | unchanged |
| body gradient | `--glass` 3-stop: `rgb(26,31,44)@.86` → `rgb(13,17,26)@.94 @62%` → `rgb(9,12,20)@.96` | flat `surfaceInk` tint | **new** (inner-luminance elevation gradient) |
| specular (soft sheen) | (26pt gradient, implicit) | `specularTopEdge{ .white, 0.5, 26pt }` | unchanged |
| specular (hard edge) | `--specular inset 0 1px 0 rgba(255,255,255,.14)` | — | **new** (1pt hard top line) |
| hairline inset | `--hairline-inset inset 0 0 0 .5px rgba(255,255,255,.05)` | — | **new** (0.5pt inner stroke) |

---

## 2. Typography spec (NEW axis)

`IslandThemeTokens` today comments *"Typography is intentionally absent: themes
swap entire slot views."* This spec proposes an **`IslandTypographyTokens`** axis
(or a Poured-local `PouredType` table) so the scale is checkable and consistent.
All roles are **SF Pro** (`.system`, `design: .default`) unless marked **mono**
(`design: .monospaced`). Numerals are **tabular** (`.monospacedDigit()` /
`font-variant-numeric: tabular-nums`) wherever noted.

Font families (both stacks native, per brief §2.6):
- UI: `-apple-system, "SF Pro"` → SwiftUI `.system(design: .default)`
- Mono: `ui-monospace, "SF Mono"` → `.system(design: .monospaced)`

| Role | Size | Weight | Tracking | Line-height | Mono? | Tabular? | Shipped now |
|---|---|---|---|---|---|---|---|
| Headline / workspace title (`.ws`) | 14 | 600 semibold | −0.01em | 1.1 | no | no | 13.2 semibold — **change to 14** |
| Completion header title | 15 | 640 | −0.01em | 1.1 | no | no | 13.2 |
| Prompt / activity line (`.act`) | 12.5 | 500–550 | 0 | 1.45 | no | no | 11.2 / 11 medium — **change to 12.5** |
| Activity verb (`.act .live`) | 12.5 | 550 | 0 | 1.45 | no | no | inline color only |
| Branch disambiguator (`.disamb`) | 11 | 400 | 0 | — | **yes** | no | — (new; mono @ t3) |
| Meta chips (`.chip`) | 10.5 | 500 | 0 | — | no | no | 10.5 mono — **drop mono** |
| Mono chip (`.chip.mono`, e.g. command) | 10 | 500 | 0 | — | **yes** | no | 10.5 mono |
| Age (`.age`) | 11 | 400–500 | 0 | — | no | **yes** | 10.5 mono — **drop mono, keep tabular** |
| Section header (`.grp`) | 10.5 | 650 | 0.09em (≈0.95pt) uppercase | — | no | no | 10.5 **mono** tracking 0.4 — **drop mono, retrack** |
| List overview title | 10.5 | 650 | 0.16em uppercase | — | no | no | 10.5 mono tracking 1.4 |
| Summary strip label | 11 | 400 | 0 | — | no | no | 10.5 mono — **drop mono** |
| Summary strip number (`.n`) | 12 | 700 | 0 | — | no | **yes** | 10.5 mono |
| Agent chip label | 10.5 | 500 | 0 | — | no | no | 10.5 mono capsule — **replace w/ tick + chip** |
| Outcome badge (`.outcome`) | 10.5 | 650 | 0 | — | no | no | 11 bold |
| Jump chip (`.jump`) | 11.5 | 600 | 0 | — | no | no | via button style |
| Display numerals (meter %, `.mpct`) | 20 | 640 | −0.02em | 1.1 | no | **yes** | 11.5 bold mono (ring) |
| Usage ring value (`.uv` / `.mpct` small) | 9.5–11.5 | 700–bold | 0 | — | no | **yes** | 11.5 bold mono ✓ |
| Command mono block (`.cmd`) | 12 | 600 (cmd) / 400 | 0 | 1.6 | **yes** | no | 11.5 semibold mono — **bump to 12** |
| Diff (`.diff`) | 11.5 | 400 | 0 | 1.65 | **yes** | no | shared `PermissionDiffPreview` |
| Keycap (`.kc kbd`) | 10 | 600 | 0 | — | no (UI) | no | via keycap hint views |
| Hero title (`.ht`) | 14 | 640 | −0.01em | — | no | no | 12.5 semibold — **bump to 14** |
| Hero subtitle (`.hs`) | 11 | 400 | 0 | — | no | no | 10.5 medium |
| Question text (`.q-text`) | 14.5 | 560 | −0.01em | 1.4 | no | no | shared question view |
| Option label (`.opt .ol`) | 13 | 600 | 0 | — | no | no | shared |
| Option desc (`.opt .od`) | 11.5 | 400 | 0 | 1.4 | no | no | shared |
| Option number (`.opt .num`) | 11 | 700 | 0 | — | no | **yes** | shared |
| Q chip (`.q-chip`) | 10 | 700 | 0.05em uppercase | — | no | no | shared |
| Subagent type (`.sa-type`) | 12 | 600 | 0 | — | no | no | 11 medium |
| Subagent task (`.sa-task`) | 11 | 400 | 0 | — | no | no | 10.5 |
| Subagent elapsed (`.sa-time`) | 11 | 400 | 0 | — | no | **yes** | 10 medium tabular ✓ |
| Nest header (`.nest-h`) | 10 | 650 | 0.08em uppercase | — | no | no | 10.5 medium |
| Todo (`.todo`) | 12 | 400 | 0 | — | no | no | 10.5 medium |
| Assistant body (`.assistant`) | 12.5 | 400 (strong 640) | 0 | 1.55 | no | no | shared rich text |
| Assistant amh label | 10 | 650 | 0.08em uppercase | — | no | no | — |
| Assistant inline `code` | 11 | 400 | 0 | — | **yes** | no | — |
| Metadata key (`.mk`) | 9.5 | 600 | 0.06em uppercase | — | no | no | — (new metadata grid) |
| Metadata value (`.mv`) | 12.5 | 550 | 0 | — | no | no | — |
| Metadata value mono (`.mv .mono`) | 11.5 | 550 | 0 | — | **yes** | no | — |
| Empty title (`.et`) | 14 | 600 | 0 | — | no | no | 14 medium ✓ |
| Empty subtitle (`.es`) | 12 | 400 | 0 | 1.5 | no | no | 12 ✓ |
| Bootstrap / install hint | 14 / 12 | 500 | 0 | — | no | no | 14 medium / 12 ✓ |

**Numeral rule (tabular-nums where):** age, all timers (`live 1m 42s`, subagent
`0:42`, duration `43m`), summary counts, question progress (`1 of 2`), usage
percentages, reset countdowns (`2h 10m`, `3d 4h`), task counters (`2/5`). Prose
and labels are proportional. The mockup sets `font-variant-numeric: tabular-nums`
on `body` globally + `.tnum`; in SwiftUI apply `.monospacedDigit()` to those
roles (do **not** switch the whole face to mono).

---

## 3. Slot-by-slot implementation map

### 3.1 `closedPill` → `PouredClosedPill`

Mockup (§A, §G‴, §I′): 38–40pt tall, radius = height/2, content in **wings**
either side of the notch dead-zone (`.core` reserves the camera gap). Left wing =
status glyph (3 bars: `wave` running / `breathe` waiting / still idle). Right wing
= `×N` count, mini agents grid (`.agrid` 3-col, 7pt cells, `on`/`idle`/`wait`), or
a compressed chip (`⏲ 2/5`, worst-window `92%` dial). Center label narrates
activity (`Editing AppModel.swift`, `3 working`, `Refactoring · 3 agents`,
`Done · the-automator`, `Interrupted · niche-radar`, `Failed · open-vibe-island`).

Replaces/modifies: `PouredClosedPill` (shipped) — keeps identical outer width math
(`V6ClosedPill.*OuterWidth`) so the morph frame is unchanged. Changes: (a) the
right slot gains **count-attn**, **task-counter**, and **worst-usage-dial**
variants beyond `.count`/`.agents`; (b) center/notch-lane label must carry
**narrated activity + outcome-prefixed** strings; (c) six ambient states
(idle / working / attn-permission / attn-question / just-completed / outcome).

Hardest detail: **the amber attention glow bleeding outside the silhouette
(A3/A4).** Shipped `PouredClosedPill` renders only `surfaceInk` + a clipped
specular; there is no outer glow, and the closed pill sits in a tightly-sized
overlay window (`closedShadowHorizontalInset 16` / `closedShadowBottomInset 18`).
A glow that bleeds `+4px` outside at `r34` needs the closed-pill window insets to
grow to contain it, plus a `.shadow(color: attn, radius:…)` that is *not* clipped
by `V6ClosedPillShape`. Secondary: the running glyph must **travel** into the
header on expand (brief §2), not crossfade.

### 3.2 `openedHeader` → `PouredHeaderControls` + `PouredUsageSummary`

Mockup (§C header, §I): header splits around the notch — usage on left/right
lanes (`.notch-gap 110px` reserved), controls (mute / settings / quit) as 26pt
circular glass buttons on the right. Usage = conic ring (`.uring` 30pt, `--p`
percent, `--rc` threshold color) + label `Claude 5h / resets 2h 10m`.

Replaces/modifies: `PouredHeaderControls` (notch-split shipped) + the conic ring
in `PouredUsageSummary` / `PouredUsageWindowRing` (shipped conic ring 16pt).
Changes: **surface `resetsAt` inline** under each ring (shipped only exposes it in
`.help()` tooltip — see §6), and grow the ring to the mockup's 30pt in the header
lane while the 52pt `.dial` is used in the full §I meter card.

Hardest detail: the **conic ring threshold colors** must stay the shipped
`usageColor` cutoffs (`≥90` red, `70–90` orange, else green) — the mockup's
`pct-fine/warn/crit` map to `--done/--answer/--fail`, a slightly different palette
(`--answer #ffd58a` vs shipped `.orange`). Reconcile: adopt token status colors
for threshold labels, keep `usageColor` for the ring arc, or unify — must be one
rule (currently `PouredUsageWindowRing.usageColor` returns raw `.red/.orange/.green`).

### 3.3 `sessionRow` → `PouredSessionRow` (incl. approval / question / completion bodies)

Mockup (§C, §D, §E, §F, §G, §H). Row = `lead` (status dot/glyph + glow) · `body`
(title-line: **2pt tick** + workspace + `disamb` branch/recency; `act` narrated;
`meta` chips + jump) · `age` (right) · hover-reveal `dismiss`.

- **Approval body (§E hero):** `.amber-hero` — inset amber border + outer glow
  (`heropulse`), mono command with syntax spans (`.t-cmd/.t-sub/.t-flag/.t-str/
  .t-path`), plain-English effect line, `Allow once ⌘Y` (primary amber gradient
  button) + `Deny ⌘N`, scoped `.scopes` always-allow rows (`⌘⇧Y` on first),
  inline `.diff` for Edit/Write, Codex `.codex-note` + single jump-to-approve.
  Replaces `PouredApprovalCard` (shipped). Changes: adopt **`--attn` amber**
  (currently `statusWarning`), add **syntax-highlight spans** in the command
  block, add **keycap hints** (`⌘Y / ⌘⇧Y / ⌘N`).
- **Question body (§F):** `.q-hero` gold-tinted, `.q-chip` header ≤12 chars,
  progress `1 of 2`, numbered `.opt` (tick when selected, square `.num` for
  multi-select), `.opt-other` freeform, `Submit ⌘↵`, digit-select hint `1–3`.
  Shared structure (brief §6) — restyle only.
- **Completion body (§H):** outcome badge (`ok`/`intr`/`fail`), tabular duration,
  result as **rich prose** (`.assistant`), jump primary + reply/transcript/dismiss.
  Replaces `completionOutcomeBanner` etc. (shipped).

Replaces/modifies: `PouredSessionRow` (50KB, shipped covers all states).
Changes: (a) **tick replaces `agentBadge` capsule**; (b) **drop mono** from
section/summary/badge/age fonts; (c) **prompt/activity 11→12.5pt**; (d) approval
amber → `--attn`; (e) **hover-reveal dismiss** (shipped `DismissButton` is always
in the meta HStack — gate on `isHighlighted` from `SessionRowContainer`).

Hardest detail: **status expressed as glow bleeding into the glass**
(`rowIsDrawingGroupSafe = false` already, correctly). The 2pt identity tick +
leading 3pt status glow bar + breathing dot must all read at row scale without the
`.drawingGroup()` flatten. The syntax-highlighted command needs a real tokenizer
(the mockup hand-colors spans; the app must compute them from
`currentCommandPreviewText`).

### 3.4 `sessionList` → `PouredSessionListScaffold` (summary strip + section headers + footer)

Mockup (§C): summary strip shows **only non-zero buckets** (`6 total · 2 waiting ·
2 running · 2 done`), grouped sections with tinted `.gc` dot + uppercase title +
count, footer `Grouped by state · 0 idle`.

Replaces/modifies: `PouredSessionListScaffold` (shipped — already filters
non-zero, already groups, already has header hairline + footer). Changes: **drop
`design: .monospaced`** from `sessionPanelHeader` title, `sessionOverviewMetric`,
and `sessionSectionHeader` (all currently mono); retrack section header to
`0.09em` uppercase SF Pro. Footer today is a bare 10pt hairline spacer — the
mockup gives it text (`Grouped by state` + `All quiet elsewhere · 0 idle`).

Hardest detail: the section-header **frosted wash** (`sectionHeaderWash`, a
top-lit gradient) must survive Reduce Transparency (already handled) *and* read as
"a lip in the glass" against the new body gradient (§1d) — the two gradients must
be tuned together so headers don't muddy.

### 3.5 `notificationCard` → `IslandNotificationCard` (shared chrome, Poured row)

Mockup (§E4): the single `activeActionableSession` pulls the island open; hero
card + `Auto-collapses in 8s · hover pauses` + `Show all 6 sessions →`.

Replaces/modifies: **shared** `IslandNotificationCard` (Poured delegates to it;
its one row is drawn through `PouredSessionRow`'s approval hero). No parallel card.
Changes: none structural — inherits the amber hero + keycaps from §3.3. Verify the
`8s`/`10s` countdown copy and the `Show all N` affordance render on the glass.

Hardest detail: the auto-collapse countdown (`10s` for completions, hover pauses)
is shared behavior (brief §6) — the card must **pause on `onPointerInside`** and
show the honest tabular countdown; the hero glow must not overwhelm the `Show all`
link contrast.

### 3.6 `emptyState` → `PouredEmptyState`

Mockup (§J): breathing monitor glyph (radial `⊹`), `All quiet`, subtitle, and a
`✓ Hooks installed for Claude, Codex, Gemini` reassurance pill.

Replaces/modifies: `PouredEmptyState` (shipped — recessed glass panel, two text
lines). Changes: add the **breathing glyph** (`lumen` 3s) and the **hooks-status
reassurance pill** (`.ecal`). Shipped copy uses `island.noTerminals` +
`startAgent`/`recentSessions` — keep those; add the installed-agents line
(data: which hook installers are present).

Hardest detail: the breathing glyph is the only motion in an otherwise still
frame — must respect Reduce Motion (hold mid-glow, like `PouredWaitingTile`).

### 3.7 `bootstrapPlaceholder` → `PouredBootstrapPlaceholder`

Mockup: not a dedicated frame; treat as the empty-state shell shown while probing
terminals on cold launch. Shipped `PouredBootstrapPlaceholder` (14 medium / 12).
Changes: none required; ensure it uses the new body gradient + specular so it
matches the poured slab. Hardest detail: it must not flash the flat pre-gradient
fill before the material mounts.

### 3.8 `installHint` → `PouredInstallHooksHint`

Mockup: the `.ecal` reassurance pill in §J is the positive inverse; the install
hint is the negative ("hooks not installed, tap to install"). Shipped
`PouredInstallHooksHint` (12 semibold / 12 medium / 10 semibold), `onTap`.
Changes: none structural; align type to §2 (12pt semibold title). Hardest detail:
keep it quiet — it is a hint, not an attention state, so **no amber glow** (color
= state discipline, brief §7).

---

## 4. Scenario acceptance criteria (A–K)

Values quoted are the checkable targets. "glow" = SwiftUI `.shadow(color:radius:)`
unless noted.

### A. Collapsed pill — ambient states
- **A1 idle:** still 3-bar glyph in `t3` (`paper@0.5`), one dim dot `statusIdle`
  (`paper@0.35`); **no glow**, no breathing. Pill min-width ≈ 212pt, height 38pt.
- **A2 working:** breathing `lumen` 3s, glow `statusRunning@0.16` (`#6ea7ff`)
  radius 22pt; running glyph `wave` 1.05s (3 bars staggered 0.14s); label narrates
  `Editing AppModel.swift` (verb `dim`/`t2`, object `t1`), **never** a raw tool id.
- **A2′ many working:** right slot = agents grid, one 7pt cell/session,
  running=`statusRunning` + glow `rgba(110,167,255,.6)` r6, idle=`t3`; label
  `3 working` (count bold 600 + `dim`).
- **A3 attention/permission (loudest):** amber glow **`#ffb14d` bleeds ≥4pt
  outside** the silhouette, `attnpulse` 1.9s r18→34 (+4 spread), opacity .28→.55;
  right slot `count.attn` = amber `#ffb14d` fill, text `#2a1c05`, glow
  `rgba(255,177,77,.55)` r14; left `dot.approve` (`#f4a4a4`) with `.ring`
  (`0 0 0 3px rgba(255,177,77,.22)`); label `Approve swift build?` (command mono).
- **A4 attention/question:** gold glow `statusWaitingForAnswer #ffd58a@0.34` r26;
  breathing `wait` glyph tinted `--answer`; right badge `?` on `#ffd58a` fill,
  text `#2a2205`. **Distinct from A3 by hue AND label/shape** (never color alone).
- **A5 just completed:** `settle` 2.6s — white flash `rgba(255,255,255,.4)` r30 →
  green `statusCompleted #6fb982@0.4` r22 → fade to 0; `dot.done` + checkmark
  (`#6fb982`); label `Done · the-automator`. A moment, not a permanent badge.
- **A6 outcome variants:** interrupted = `statusWarning #d98c26`, `▮` stop glyph,
  label `Interrupted · niche-radar`; failed = `statusFailed #db5252`, `✕` glyph,
  label `Failed · open-vibe-island`. The two are visibly distinct.

### B. Hover peek & morph
- Pointer dwell **0.15s**, pill scales **1.03** (`closedHoverScale`).
- Peek surfaces the single most-actionable session inline (title + mono command)
  and compresses the rest to a `+2 more sessions` chip.
- Morph is **one continuous shape**: top radius 0→26, bottom radius height/2→26 as
  the frame grows; status glyph **travels** into header (no crossfade); spring
  `response 0.5 / damping 0.84`.

### C. Expanded panel — session list
- Header splits around notch; usage rings show **resets countdown inline**
  (`resets 2h 10m` tabular).
- Summary strip shows **only non-zero buckets**; each bucket dot uses its status
  tint; numbers tabular, 12pt/700.
- Sections grouped so **attention floats to top** (`Needs you` first, tinted
  `--attn` dot).
- **Duplicate `the-automator` rows** disambiguated by branch/recency:
  `feat/bridge-auth`, `main · 3 subagents`, `docs/agents-md` in **11pt mono at t3
  (`paper@0.5`)** after the workspace name.
- Every state carries glyph/shape + color (color never alone); rows separated by
  `hairlineOpacity 0.08` white hairline.

### D. Row expanded — detail
- Metadata as a quiet cell grid (`Agent / Model / Permission / Branch / Live /
  Directory`); keys 9.5pt uppercase `t3`, values 12.5pt `t1`, mono for branch/dir.
- Activity narrated; last assistant message rendered as **rich text** (bold, inline
  `code` mono 11pt, bulleted list) — **not** a raw `$ source ~/.nvm…` dump.
- **Jump to terminal is the primary CTA** (blue gradient button); Transcript ghost;
  `Pane attached` chip (green dot) surfaces `attachmentState`.
- Dismiss **hover-reveal only** (opacity 0→1 on row hover).

### E. Permission hero (the most-polished frame)
- Amber hero: inset border `rgba(255,177,77,.28)` + outer glow
  `0 0 42px -6px rgba(255,177,77,.4)`, `heropulse` 2.4s when pulsing.
- Command **syntax-highlighted** (`swift`=`t-cmd #f2f5fb/600`, `build`=`t-sub`);
  plain-English effect line in `rgba(255,214,160,.75)`.
- `Allow once` primary = amber gradient `#ffce8a→#ffb14d`, text `#3a2405`, keycap
  `⌘Y`; `Deny` = `rgba(219,82,82,.14)` text `#f0a8a8`, keycap `⌘N`.
- Scoped always-allow rows: human labels (`Always allow swift build from this
  project`), first carries `⌘⇧Y`; code chips `rgba(255,177,77,.1)` text `#ffd9a8`.
- **E2 diff:** real inline diff (del `rgba(219,82,82,.13)` text `#f0b3b3`, add
  `rgba(111,185,130,.14)` text `#a8e0bb`, gutter line numbers).
- **E3 Codex:** blue-tinted hero (`#4aa3df`), `.codex-note` "approves in-app",
  **single** `Jump to Codex to approve` — **no fake Approve button**.
- **E4 notification card:** `Allow ⌘Y / Always ⌘⇧Y / Deny ⌘N`,
  `Auto-collapses in 8s · hover pauses`, `Show all 6 sessions →`.

### F. Question prompt
- `.q-chip` header ≤12 chars on `#ffd58a`, progress `Question 1 of 2` tabular.
- Options carry **human descriptions** (prose, not enum values); selected option
  has amber tick + `1.5px` inset ring `rgba(255,213,138,.5)` (state not color-only).
- Multi-select: square `.num` with `✓`, `Submit 2 selected` (running count).
- Freeform `Other — type a different approach`; digit hint `1–3`, `Submit ⌘↵`.
- Compact single: Yes/No collapses to one row, same semantics.

### G. Subagents & tasks (nested)
- Expanded: `3 subagents` nested sub-list, each with running dot + type + task +
  **live elapsed tabular** (`0:42`, `1:15`, `0:08`); todo list `Tasks · 2 of 5
  done` with `done`(strikethrough+check `#6fb982`)/`doing`(bars+`now`)/`pending`
  (hollow circle) states.
- Compressed row: rolls up to two chips `3 subagents · ⏲ 2/5 tasks`.
- Pill: `Refactoring · 3 agents` + right slot `⏲ 2/5`.

### H. Completed session
- Outcome badge `Success` (`#6fb982` on `rgba(111,185,130,.14)`), tabular duration
  `43m`, `finished 12m ago`.
- Result as prose (`.assistant`) with `<strong>` + inline `code` — not a dump.
- Jump primary; Reply / Transcript / Dismiss as calm ghost secondaries.

### I. Usage meters
- Full: 52pt conic dials, threshold by **color AND shape/label**: Fine ● `#6fb982`
  (`<70`), Warn ▲ `#ffd58a` (`70–90`), Critical ● `#db5252` (`≥90`); each shows
  `resets in …` tabular countdown. Higher % = more consumed.
- Pill compression: only the **worst** window surfaces — small red dial + `92%`
  (`≥90` crit); fine windows stay silent.

### J. Empty state
- Slow-breathing monitor glyph (`lumen` 3s, static under Reduce Motion),
  `All quiet` (14/600), confident subtitle, `✓ Hooks installed for …` pill so
  silence reads as "nothing to do", not "broken".

### K. Motion spec strip (all live CSS in mockup — must animate in app)
- Pill breathing 3s; expand morph (one shape, radius+frame grow, spring .5/.84);
  attention pulse (amber bleeds out); row entrance (rise+fade spring settle);
  success settle (white→green→quiet). Each must be a real animation, gated under
  Reduce Motion.

---

## 5. Conformance checklist

### 5.1 Fixtures needed (map A–K → deterministic demo sessions)

`AppearancePreviewFixtures.sessions` (in `AppearanceSettingsPane.swift`) today
yields **5** sessions: approval / answer / running / done / idle. The spec needs
these **additional** deterministic fixtures (extend the enum, or add a
`PouredConformanceFixtures`), all `origin: .demo`, fixed `updatedAt` offsets:

| Scenario | Fixture(s) needed | Gap vs shipped |
|---|---|---|
| A1 | idle/monitoring, no sessions active | have `preview-idle` |
| A2/A2′ | 1 running w/ narrated activity; 3 running | have `preview-running` (1) |
| A3 | permission w/ command `swift build` | have `preview-approval` (Codex→needs Claude+cmd) |
| A4 | question waiting | have `preview-answer` |
| A5 | just-completed success (recent) | have `preview-done` |
| A6 | **completed interrupted** + **completed failed** | **missing both** |
| C | duplicate-workspace pair w/ **branches** (`the-automator` ×3) | **missing** |
| D | running w/ assistant message + `attachmentState` | partial |
| E1/E2 | permission w/ **command** and w/ **fileDiffSource** (old/new) | diff **missing** |
| E3 | Codex `requiresTerminalApproval` | **missing** |
| F | **multi-question (2)** + **multiSelect** + **freeform Other** | single-Q only |
| G | Claude w/ `activeSubagents[3]` + `activeTasks[5 mixed]` | **missing** |
| H | completed w/ `completionAssistantMessageText` + duration | partial |
| I | usage providers Claude 5h(34) / 7d(78) / Codex 7d(92) + `resetsAt` | usage fixtures **missing** |
| J | empty (0 sessions) + hooks-installed flags | **missing** |

### 5.2 Token equality tests to add

Following `IslandThemeTokensTests` (pins `.classic`) / `AnnualThemeTests` (pins
accent discipline), add **`PouredThemeTests`**:
- Pin every `.poured` color/metric/motion/material value from §1 (surfaceInk,
  paper, all status tints == classic, secondary 0.6, tertiary 0.5, hairline 0.08,
  radii 26, fillet 12, shadow .5/34/18, hover 1.03, spring .5/.84, tint 0.5,
  specular white/0.5/26).
- Pin **new** tokens: `attentionGlow #ffb14d`, `attentionHot #ff9d5c`, the body
  gradient stops, the hard specular (0.14) and hairline-inset (0.05).
- Pin the **typography table** (§2) once it becomes a token axis — one assertion
  per role (size/weight/mono/tabular) so drift fails the build.
- Assert **status-color parity** with Classic (semantics identical), and
  **usageColor cutoffs** unchanged (`≥90`/`70–90`/else).
- Assert `rowIsDrawingGroupSafe == false`, `usesVibrancy == true`.
- Assert `agentsGridGeometry` still delegates to `V6RightSlotView` statics
  (pinned by `AgentsGridLayoutTests`).

### 5.3 Snapshot-test pins

One deterministic snapshot per scenario frame (fixed `now`, Reduce-Motion **on**
so animations render at settled phase): A1–A6 pills, B peek, C list, D detail,
E1–E4 permission, F/F′/F″ question, G/G′/G″ subagents, H completed, I/I′ meters,
J empty. Also pin: notch vs top-bar layout (panel 540 vs 520), Increase-Contrast
variant of C, Reduce-Transparency variant of E (flat ink under amber wash).

### 5.4 Judged-by-eye (manual sign-off — cannot be asserted)

- Vibrancy / blur believability of the frosted slab against a bright wallpaper.
- The amber glow **actually bleeding outside** the closed-pill silhouette (window
  inset sizing correct, not clipped).
- Specular edge reads as a light-catch, not a border.
- Body gradient reads as **inner luminance / elevation**, not a flat panel.
- Morph feels like one liquid body (no crossfade seam); glyph travel is smooth.
- Success settle timing feels like "a moment", attention pulse feels "loud".

---

## 6. Data / plumbing prerequisites

Everything the mockup shows must be truthfully computable from brief §3. These are
surfaced in the mockup but **not yet exposed by presentation code**:

| Prerequisite | Mockup use | Source field (§3) | Status today |
|---|---|---|---|
| **Resets-in countdown inline** | `resets 2h 10m` under each ring; §I `resets in …` | `UsageWindowPresentation.resetsAt` | Computed in `PouredUsageSummary.remainingDurationString` but only in `.help()` tooltip — **promote to visible readout**. |
| **Branch disambiguation** | Duplicate workspace rows show `feat/bridge-auth`, `main · 3 subagents`, recency | `claudeMetadata` worktree git branch (Claude only) + `updatedAt` | Branch data exists; **no duplicate-name detection + disambiguator string builder** — add a list-level helper (when workspace names collide, append branch for Claude else recency). |
| **Narrated activity lines** | `Editing AppModel.swift`, `Refactoring hook installers`, `Evaluating in the browser` | current tool name + `currentCommandPreviewText` | Row uses `spotlightActivityLineText` — verify it **narrates verb+object** (translate identifier → sentence, kills §1.2) rather than echoing the raw tool id; extend the mapping if not. |
| **Hover-reveal dismiss** | `dismiss` hidden until row hover (opacity 0→1) | `RowActions.dismiss` + `SessionRowContainer` `isHighlighted` | Action exists; shipped `DismissButton` is **always visible** in the meta HStack — gate its opacity on `isHighlighted` (plumbing already flows in). |
| **Pane attachment chip** | `Pane attached` (green) in §D | `SessionAttachmentState .attached/.stale/.detached` | Data exists; **not surfaced** in the Poured row — add a chip. |
| **Closed-pill narrated label** | Pill center shows `Editing AppModel.swift` / `3 working` / `Refactoring · 3 agents` / `Done · X` / `Interrupted · X` | most-salient session's narrated activity + outcome prefix | Pill label string is computed upstream (`V6CenterLabelView` / `UnifiedBars.Mode`); **needs a "most-salient narrated label" builder** feeding the pill. |
| **Pill outcome/attn/task right-slot variants** | `count.attn`, `?` badge, `⏲ 2/5`, worst-usage `92%` dial | outcome, phase, `activeTasks`, worst usage window | `IslandRightSlotContent` today = `.count`/`.agents` only — **add** attn-count, task-counter, usage-dial cases. |
| **Hooks-installed reassurance** | §J `✓ Hooks installed for Claude, Codex, Gemini` | which per-agent hook installers are present | **Add** an installed-agents query surfaced to `PouredEmptyState`. |
| **Syntax-highlighted command** | `.t-cmd/.t-sub/.t-flag/.t-str/.t-path` spans in §E | `currentCommandPreviewText` (plain string) | Shipped renders a single mono string — **add a lightweight shell tokenizer** (command / subcommand / flag / string / path) or ship un-highlighted (acceptable v1). |
| **Keycap hints** | `⌘Y / ⌘⇧Y / ⌘N`, `1–3`, `⌘↵` in §E/§F | keyboard shortcuts registered via `OverlayUICoordinator` (brief §6) | Shortcuts exist; **render the keycap chips** in the Poured approval/question bodies (currently absent). |

Notes on honesty (brief §3): there is **no** per-session token/cost, **no**
tool-invocation counter (the old `×4` was fake), and **no** kill action — the
mockup correctly uses `Dismiss` (hide) and shows subagent/task counts, not
invented precision. Keep it that way.
