# Flight Deck 2.0 · Glass Cockpit — Implementation Conformance Spec

Source mockup: `02-flight-deck.html` ("Flight Deck 2.0 — Glass Cockpit").
Target theme: `FlightDeckTheme` (already shipped through AB-311…314). This spec
finalizes the **approved** mockup into checkable deltas against the current Swift
implementation.

Conventions: **mockup px @1x = SwiftUI pt.** Hex is compared against the exact
`Color(red:green:blue:)` literals in `IslandColorTokens.swift`. Verdicts:
`unchanged` (mockup == shipped), `changed` (mockup differs from a shipped token),
`new` (no shipped token/treatment exists).

> **Headline finding — read first.** The mockup's *color* mapping already matches
> the shipped `flightDeck` tokens almost verbatim (ground/nominal/advisory/
> caution/warning are byte-identical hexes). The real deltas are: (1) the
> **two-tier alarm nomenclature** (permission = red **MASTER WARNING**, question =
> amber **MASTER CAUTION**) — a *label + structure* change, NOT a token
> remapping; (2) **phosphor glow** re-introduced on every lit lamp (shipped Flight
> Deck is deliberately glow-free flat hardware); (3) a **sans-narration / mono-value
> type split** (shipped renders everything mono); (4) the usage gauge changes from
> **12-tick segmented** to **continuous tape + 70/90 threshold ticks + inline
> RESETS-IN**; (5) a **STATUS text-code column** and **engine-cluster subagent
> display** that do not exist in the shipped row.

---

## 1. Token sheet — mockup CSS → current Swift → verdict

### 1a. Colors (`IslandColorTokens.flightDeck`)

| Role | Mockup CSS | Shipped Swift literal | Hex | Verdict |
|---|---|---|---|---|
| Cockpit ground / `surfaceInk` | `--ground #08090a` | `flightDeckInk = rgb(0x08,0x09,0x0a)` | `#08090A` | **unchanged** (exact) |
| Nominal (running) | `--nominal #4ac99e` | `flightDeckNominal = rgb(74,201,158)` | `#4AC99E` | **unchanged** (exact) |
| Advisory (completed·success) | `--advisory #6392c4` | `flightDeckComplete = rgb(99,146,196)` | `#6392C4` | **unchanged** (exact) |
| Caution (question / interrupted) | `--caution #e6aa42` | `flightDeckCaution = rgb(230,170,66)` | `#E6AA42` | **unchanged** (exact) |
| Warning (permission / failed) | `--warning #e04a42` | `flightDeckWarning = rgb(224,74,66)` | `#E04A42` | **unchanged** (exact) |
| Legend ink / `paper` | `--paper #d8e1e6` | `flightDeckPaper = rgb(0xd4,0xda,0xd6)` | shipped `#D4DAD6` | **changed** — mockup is cooler/lighter (`#D8E1E6`, rgb 216,225,230). Small but real; either adopt `#D8E1E6` or keep `#D4DAD6` and document. Contrast on ink stays ≥ 4.5:1 either way. |
| Opened panel body | `--surface #0e1113` | *(none — panel = `surfaceInk`)* | — | **new** — mockup panel body (`#0E1113`) is a distinct tone *lighter* than ground; shipped panel = `surfaceInk` (`#08090A`). Add a `surfacePanel` token or lift panel fill. |
| Tiles / sub-panels | `--surface-2 #101519` | *(derived: `paper.opacity(0.012–0.035)` washes)* | — | **new** — mockup uses an explicit near-black tile tone; shipped derives tiles from paper washes over ink. |
| Raised / hovered | `--surface-hi #161c22` | `paper.opacity(0.05)` hover wash | — | **changed** — hover is currently a paper wash, not a distinct surface tone. |
| Recessed wells (code / tape track) | `--well #060708` | `paper.opacity(0.04–0.05)` over ink | — | **new** — mockup wells are *darker* than ground; shipped has no recessed well tone (uses light washes, which read raised, not recessed). |
| Hairline tier 1 | `--hair rgba(154,176,188,0.14)` | `hairlineOpacity = 0.13` × `paper` | — | **changed** — mockup base is cool blue-grey `#9AB0BC`, not `paper`; opacity 0.14 ≈ 0.13. |
| Hairline tier 2 | `--hair2 rgba(154,176,188,0.26)` | `hairlineOpacity*2 = 0.26` (inline, lamp housing) | — | **changed** — value matches (0.26) but exists only as an inline `*2`, not a token. |
| Hairline tier 3 | `--hair3 rgba(154,176,188,0.40)` | *(none)* | — | **new** — a 3rd hairline tier (0.40) for strong bezels/ticks; no shipped equivalent. |
| Dim text (`--dim #8a97a0`) | `#8a97a0` | `paper.opacity(secondaryTextOpacity=0.6)` | — | **changed** — mockup uses an explicit cooler grey; shipped derives from paper @ 0.6. |
| Faint text (`--faint #5b656c`) | `#5b656c` | `paper.opacity(tertiaryTextOpacity=0.5)` | — | **changed** — same story @ 0.5. |
| Idle lamp | `--well` + `--hair2` border | `statusIdle = paper.opacity(0.30)` / `statusInactive = 0.26` | — | **unchanged** (concept) |
| Secondary/Tertiary text opacity | — | `0.6 / 0.5` | — | **unchanged** |
| Hairline opacity (default / IC) | — | `0.13 / 0.32` | — | **unchanged** |

**Two-tier alarm — the semantic mapping (critical).** The shipped tokens already
encode the mockup's two tiers correctly:

```
statusWaitingForApproval == statusFailed  == flightDeckWarning  (#E04A42 red)   → WARNING tier
statusWaitingForAnswer   == statusInterrupted == statusWarning == flightDeckCaution (#E6AA42 amber) → CAUTION tier
statusRunning   = flightDeckNominal  (#4AC99E)   statusCompleted = flightDeckComplete (#6392C4)
```

This is **exactly** the mockup: permission → red, question → amber, failed →
red, interrupted → amber. **No `IslandColorTokens` tint-role remapping is
required for the color axis.** `FlightDeckThemeTests.statusPaletteIsTheFour...`
(lines 52–77) already pins these equalities and must stay green.

What *is* wrong today is **nomenclature, not color**: the shipped
`FlightDeckApprovalCard` paints the (red) permission block but labels it
`island.flightDeck.approval.masterCaution` = **"Master Caution"** — an
avionics category error (red must be WARNING; amber is CAUTION). And the
**question** phase currently renders the bare `StructuredQuestionPromptView`
with *no annunciator header at all*. The remapping to implement is therefore:

| Phase | Color token (unchanged) | Shipped placard | Required placard |
|---|---|---|---|
| `waitingForApproval` (permission) | `statusWaitingForApproval` = warning **red** | `masterCaution` "Master Caution" | **`masterWarning` "Master Warning"** (new string; red beacon) |
| `waitingForAnswer` (question) | `statusWaitingForAnswer` = caution **amber** | *(none)* | **`masterCaution` "Master Caution"** amber annunciator header **added above the question prompt** |

Net string change: add `island.flightDeck.approval.masterWarning`; repoint the
permission card to it; reuse the existing `masterCaution` string for the *new*
question annunciator. (All three locale files: en / zh-Hans / zh-Hant.)

### 1b. Metrics (`IslandMetricsTokens.flightDeck`)

| Token | Mockup | Shipped | Verdict |
|---|---|---|---|
| `openedTopRadius` / `openedBottomRadius` | panel is a sharp rect (radius 0); chamfer lives on children via `--ch` | `6 / 6` | **unchanged** — keep 6 so the pill→panel morph has a radius to animate; children carry the chamfer (matches mockup's `.oct`). |
| Chamfer default (`--ch`) | `6px` | `FlightDeckChamferedRectangle` card `6`, box `5`, button `5`, placard `3`, keycap `2.5` | **unchanged** — mockup per-element chamfers (`6/5/4/3/2`) map onto shipped `6/5/3/2.5`. |
| `surfaceShadow` | panel relies on desk gradient (no hero drop shadow) | `black · 0.42 · r14 · y7` | **unchanged** (crisp shallow shadow is on-idiom). |
| Attention pill bloom | `.attn-perm 0 6px 26px -14px rgba(224,74,66,.6)`; `.attn-caut 0 6px 24px -16px rgba(230,170,66,.5)` | *(none — flat pill)* | **new** — per-state **colored** drop-glow on the closed pill's attention states. `IslandShadowToken` models one black shadow only; needs a status-tinted shadow variant. |
| `closedHoverScale` | "~1.03" | `1.028` | **unchanged** |
| Shadow insets | — | `18 / 22 / 12 / 14` | **unchanged** |
| `filletRadius` | 0 (no poured fillet) | `0` | **unchanged** |

Physical dims (from `OverlayPanelController`, **not** theme tokens — brief §2):
pill height ≈ 38pt (24pt top-bar); panel width 540pt notch / 520pt top-bar; list
side inset 46pt notch / 16pt. Mockup's board px (520/560/600, 200px notch lane)
are illustrative and consistent with these.

### 1c. Motion (`IslandMotionTokens.flightDeck`)

| Token | Mockup | Shipped | Verdict |
|---|---|---|---|
| `openAnimation` (relay-snap) | "response **.32** / damping **.92**" | `.spring(response: 0.32, dampingFraction: 0.92)` | **unchanged** (exact — this is the named identity). |
| `closeAnimation` | pill transitions `.32s`; morph not numerically specified | `.smooth(duration: 0.24)` | **unchanged** |
| `popAnimation` | beacon flash / attention pop | `.spring(response: 0.22, dampingFraction: 0.6)` | **unchanged** |
| `openedSurfaceUnmountDelay` | — | `0.28` | **unchanged** |
| Lamp **snap-on 120ms** + soft decay | §K: "Lamp snap-on 120ms on · soft decay"; `snapon` uses `steps(1,end)` (instant on) | pulsing lane = 15fps `pulseClock` two-step (`>0.5 ? 1 : 0.45`); waiting lamp `easeInOut 0.6s` autoreverse; bridge lamp `easeInOut 0.9s` | **changed** — no explicit 120ms-on / asymmetric-decay curve today. Needs a view-level snap-on/decay constant (not a token). |
| Running **breathe 2s** phosphor | `@keyframes phosphor 2s` (opacity 0.86→1 + glow 5px→11px) | closed-pill running lamp is **flat, steady, no glow**; list lane is a two-step blink off the shared clock | **changed** — running should breathe at 2s **with glow bloom**, not blink/stay-flat. |
| Attention pulse | `attn 1s` (perm) / `1.2s` (caut), opacity 1→0.28 | caution glow = triangle breathe off shared clock; waiting lamp 0.6s ease | **changed** — retime to 1s (warning) / 1.2s (caution). |
| Success settle | `settle 3s`: nominal flash+scale → advisory dim | shipped completion pop exists at panel level; no per-row nominal→advisory settle | **new** — A5 "brief blue advisory flash then calm dot". |
| Reduce Motion | `animation-duration:.001ms` | every animated leaf gates on `accessibilityReduceMotion` and paints a steady state | **unchanged** (already conformant). |

### 1d. Material (`IslandMaterialTokens.flightDeck`)

| Token | Mockup | Shipped | Verdict |
|---|---|---|---|
| `material` / `blendingMode` / `appearanceName` | opaque flat panel | `.hudWindow / .behindWindow / .vibrantDark` (fallback only) | **unchanged** |
| `usesVibrancy` | opaque | `false` | **unchanged** |
| `tintOpacity` | opaque | `1.0` | **unchanged** |
| `specularTopEdge` | none (flat) | `nil` | **unchanged** |
| **Phosphor glow / self-lit lamps** | every lit lamp/beacon: `box-shadow: 0 0 5–14px <status>` bleeding outside the silhouette | shipped lamps are **flat, no glow** ("full cyan-green nominal — flat, no glow"); only `FlightDeckCautionGlow` (blurred halo behind the alarm block) exists | **new** — the single biggest visual delta. §7 fidelity bar mandates "glow that bleeds outside the silhouette." Extend the existing `FlightDeckCautionGlow` blur-halo technique to every lit lamp (pill grid, list lane, annunciator tiles, engine lamps, footer link, empty-state grid). |

---

## 2. Typography spec (NEW axis — currently hardcoded per view)

The token layer intentionally carries no typography; `FlightDeckTypography`
(in `FlightDeckTheme.swift`) is a **mono-only** table and every slot view
hardcodes literal sizes. The mockup demands a **two-font system** the shipped
theme does not honor:

- **Sans narration** = `-apple-system / SF Pro Text` — session/workspace names,
  live activity narration prose, option labels, assistant-message rich text.
- **Mono tabular values** = `SF Mono` (`design: .monospaced`, `tabular-nums`) —
  all timers, counts, percentages, status codes, key hints, command/diff, brand
  wordmark, placards.

> **Shipped gap:** `FlightDeckRowContent.scaledFont` renders `displayHeadline`
> (the session name) with `design: .monospaced`. The mockup's `.row .ws` uses
> `var(--sans)`. Introduce a `sansScaled(...)` helper and route the
> headline + narration prose through it; keep values on the mono helper.

### Full scale (mockup value → role → floor compliance)

| Role | Mockup | Font | Weight / tracking | Floor |
|---|---|---|---|---|
| Session/workspace name (`.ws`) | 13.5px | **sans** | 640 / −0.01em | ✅ |
| Live narration (`.narr`, `.narr2`) | 12px | **sans** | 400–600 | ✅ |
| Assistant rich text (`.assist`) | 13px/1.55 | **sans** | 400 | ✅ |
| Option label (`.qopt .ol`) | 13px | **sans** | 600 | ✅ |
| Option description (`.od`) | 11.5px | **sans** | 400 | ✅ |
| Duration readout (`.dur`) | 12px | **mono** tabular | 600 | ✅ |
| Model/meta (`.meta`) | 10.5px | **mono** | 400 | ✅ |
| Age (`.age`) | 10px | **mono** | 400 | ✅ (at floor) |
| Gauge value (`.gval`) | 12px | **mono** tabular | 700 | ✅ |
| Command / diff (`.cmd`, `.diff`) | 13 / 12px | **mono** | 600 / 400 | ✅ |
| Brand wordmark (`.brand .wm`) | 11px | **mono** | / 0.18em | ✅ |
| MASTER placard (`.master .big`) | 12px | **mono** | 800 / 0.12em | ✅ |
| ACK switch label (`.ack .lab`) | 12px | **mono** | 800 / 0.10em | ✅ |
| Button (`.btn`) | 11px | **mono** | 600 / 0.04em | ✅ |
| Caps micro-label (`.caps`) | 10px | **sans** | 600 / 0.14em UPPER | ✅ (at floor) |
| **Status code (`.code`)** | **9.5px** | mono | 700 / 0.08em | ❌ → **lift to 10** |
| **Column caption (`.colcap`)** | **9px** | sans | 600 / 0.14em UPPER | ❌ → **lift to 10** |
| **Gauge label (`.glabel`)** | **9.5px** | sans | 600 / 0.13em UPPER | ❌ → **lift to 10** |
| **Metacell/summary/donestat key** | **9px** | sans | 600 / 0.12–0.13em UPPER | ❌ → **lift to 10** |
| **Unit tag (`.gval u` "%")** | **9px** | mono | / 0.1em | ❌ → **lift to 10** |
| **Key hint (`.kk` `⌘Y`)** | **9px** | mono | | ❌ → **lift to 10** (shipped `keyHint` is already 10) |
| Overflow `+N` (grid) | fitted | mono | 800 | **exempt** (fitted micro-indicator, sized to lamp — same exemption shipped uses) |

**≥10pt floor compliance:** the mockup routinely drops to 9–9.5px on micro-labels;
the shipped theme pins `FlightDeckTypography.floor = 10` and asserts it in
`FlightDeckThemeTests.everyReadableTypographyRoleHoldsTheTenPointFloor`. **Every
sub-10 caps role above must be lifted to 10pt** — density comes from tracking +
rules, never sub-10 type. Only the fitted `+N` roll-up is exempt.

**Letterspaced-caps unit labels:** uppercase + `.tracking()` on Latin only; both
neutralize to un-cased/0-tracking for CJK via `FlightDeckText.caps/tracking`
(already implemented). Unit tags ("%", "5H", "7D") stay Latin placards in every
locale (same rule EICAS legends and `FlightDeckUsagePlacard` follow).

**Numeral rules:** `tabular-nums` on every timer/counter/meter/percentage — met
for free by `design: .monospaced` on all mono roles.

---

## 3. Slot-by-slot implementation map (8 `IslandTheme` slots)

### Slot 1 — `closedPill` → `FlightDeckClosedPill`
- **Mockup:** pill fused around the 200px notch lane, content in wings.
  Left wing = 3-bar liveness (`.bars idle/run/wait/warn`) + optional sans
  narration; right wing = `×N` count **or** mini annunciator grid (`.mgrid`
  7×7px lamps) **or** attention segment (`.seg warn/caution` with ACK/ANSWER
  ×N) **or** usage mini-tape (`7D 76%`). Per-state ambient variants A1–A6
  (idle/working/perm/question/settle/interrupted-failed) each read across the
  room; attention pill carries a **colored bloom** border+shadow.
- **Replaces/modifies:** `FlightDeckClosedPill` + `FlightDeckRightSlotView` +
  `FlightDeckAnnunciatorLight`. Keeps `V6ClosedPill` width math (morph frame
  stays identical).
- **Hardest detail:** (a) **phosphor glow on the running lamp + 2s breathe** —
  shipped lamps are flat; (b) the **attention `.seg` (ACK×1 / ANSWER×1)** and the
  **usage mini-tape** are two *new* right-slot content kinds — `IslandRightSlotContent`
  only has `.count` / `.agents`; adding attention-segment and usage need new
  cases + plumbing (see §6); (c) colored attention bloom needs a status-tinted
  shadow (see §1b).

### Slot 2 — `openedHeader` → `FlightDeckHeaderControls` + `FlightDeckUsageSummary`
- **Mockup:** notch-split lanes; brand mark + wordmark; usage as **linear tape
  gauges** with 70/90 threshold ticks + `RESETS-IN` countdown; mute/settings/quit
  as squared panel switches.
- **Replaces/modifies:** header layout **unchanged**. `FlightDeckUsageSummary` /
  `FlightDeckUsageWindowGauge` / `FlightDeckTickGauge` are **restyled**:
  12-tick-segmented → **continuous tape + 2 ticks + inline resets-in**.
- **Hardest detail:** surfacing **`resetsAt` inline** (today only in `.help()`
  tooltip) while keeping the notch-split width math; the tape must draw the 70%
  hairline tick + 90% red `crit` tick at fixed x regardless of fill %.

### Slot 3 — `sessionRow` → `FlightDeckSessionRow` (+ approval / question / completion bodies)
- **Mockup (non-actionable):** grid `Status | Session | Model | Time`. **Status =
  a lamp + a text code** (RUN/DONE/CAUT/WARN/INTR/FAIL/IDLE). Session = name
  (sans) + branch chip + optional SSH / `⚙ N SUB` chip + narration sub-line.
  Actionable rows dominate: `act-perm` red inset bar + gradient wash;
  `act-caut` amber. Hover-reveal dismiss (`✕`).
- **Replaces/modifies:** `FlightDeckRowContent`. Two structural changes vs shipped:
  (1) **add a STATUS text-code column** (shipped conveys status only through the
  colored lane, no text code); (2) the shipped grid is `Session|Model|App|Time` —
  the mockup folds APP (SSH) into a chip and puts a **status code** first.
- **Actionable — permission** → `FlightDeckApprovalCard`: **MASTER WARNING** (see
  §1a two-tier). Red beacon + placard + `PERMISSION REQUIRED` kicker; command in
  a chamfered mono box; affected-path line; inline diff; ALLOW(inverted)/DENY
  (outlined) switches with **real ⌘Y / ⌘⇧Y / ⌘N** hints; scoped always-allow
  from `suggestedUpdates`; **held Ns** counter; Codex → jump-to-approve bar.
- **Actionable — question** → add **MASTER CAUTION** amber annunciator header
  above `StructuredQuestionPromptView` (currently header-less); numbered digits
  1–9, multi-select, freeform Other, Enter submits.
- **Actionable — completion** → chamfered mono card; outcome banner for
  interrupted/failed; reply input where supported.
- **Hardest detail:** the permission card is the hero — a *pulsing red glow*
  (`FlightDeckCautionGlow` retinted to warning), the two-tier rename, and keeping
  the **⌘Y/⌘⇧Y/⌘N** glyphs in lock-step with the global handler (never the
  mockup's ⏎/⎋). Plus the new STATUS-code column re-aligning every register.

### Slot 4 — `sessionList` → `FlightDeckSessionListScaffold`
- **Mockup:** annunciator **summary strip** (`ATTN/RUN/DONE/IDLE`, lit when
  non-zero, dark at zero) → **column captions** (`STATUS SESSION MODEL TIME`) →
  section headers (tinted lamp + caps title + count) → rows → **BRIDGE LINK
  footer** (green blinking lamp + `LINK`/`NO LINK` + session count).
- **Replaces/modifies:** `FlightDeckSessionListScaffold` — mostly present.
  Column captions must gain a **STATUS** caption (mockup 74px) to sit over the new
  status-code column; footer must **drop `socket path` and `EVT/MIN`** (no data
  source — §6).
- **Hardest detail:** the caption strip already registers MODEL/APP/TIME lanes to
  the row grid; re-registering to `STATUS|SESSION|MODEL|TIME` while the row's
  fixed lanes shift.

### Slot 5 — `notificationCard` → `IslandNotificationCard` (inherits row treatment)
- **Mockup:** the single actionable item as a card (`.alarm`) — `minihead`
  (brand + "Show all N ›") + annunciator + phase interior. Auto-collapse 10s
  (completions), hover pauses countdown.
- **Replaces/modifies:** unchanged wiring; inherits `FlightDeckSessionRow` via the
  factory. The MASTER WARNING/CAUTION annunciator is the card's hero.
- **Hardest detail:** the `minihead` notch-split + "Show all N" affordance already
  exist in the shared card; ensure the two-tier annunciator renders identically in
  `.notification` and `.list` presentations.

### Slot 6 — `emptyState` → `FlightDeckEmptyState`
- **Mockup §J:** lamp grid (1 lit, breathing) + heading **"ALL SYSTEMS NOMINAL"**
  + monitoring copy + `BRIDGE LINK · MONITORING · 0 SESSIONS` sysline + footer.
- **Replaces/modifies:** `FlightDeckEmptyState` — shipped heading is **"NO SIGNAL"**
  (dim). Mockup is confident/positive (green lit lamp).
- **Hardest detail:** tone flip (NO SIGNAL → ALL SYSTEMS NOMINAL) + a breathing
  lit lamp in the empty grid (needs the same glow treatment).

### Slot 7 — `bootstrapPlaceholder` → `FlightDeckBootstrapPlaceholder`
- **Mockup:** not a distinct frame; reuse the empty-state "power on, monitoring"
  idiom (squared hairline panel, `STANDBY`/probing caption).
- **Replaces/modifies:** unchanged shell; align caption + glow with the empty state.

### Slot 8 — `installHint` → `FlightDeckInstallHooksHint`
- **Mockup:** not a distinct frame; a squared hairline panel with a `SETUP`
  caption (string exists: `island.flightDeck.hint.setup`).
- **Replaces/modifies:** unchanged shell; verify chamfer/hairline idiom + tap CTA.

---

## 4. Scenario acceptance criteria (A–K)

### A — Collapsed pill, ambient states
- A1 idle: bars `.idle` at ~4px, opacity 0.5; right wing caps **"STANDBY"**; no
  status color; near-invisible.
- A2 working: bars `.run` wave at **1.4s** (`#4AC99E` + 5px glow); sans narration
  "**Editing** AppModel.swift" (verb `#4AC99E`); right = mini grid, running lamps
  breathe at **2s** with glow, idle lamps dark.
- A3 permission (WARNING): pill `attn-perm` = **red** border `rgba(224,74,66,.55)`
  + bloom `0 6px 26px -14px rgba(224,74,66,.6)`; bars `.warn` red; `.seg warn`
  ⚠ ACK ×1 at `attn 1s`.
- A4 question (CAUTION): pill `attn-caut` = **amber** border; bars `.wait` amber;
  `.seg caution` `?` ANSWER ×1 at `cautbg 1.2s`.
- A5 completion settle: `settle 3s` — nominal `#4AC99E` flash+scale(1.25) →
  advisory `#6392C4` calm dot; narration "Done · AGENTS.md" (`#6392C4`).
- A6 outcome variants: interrupted = amber `⊘` (`#E6AA42`); failed = red `✕`
  (`#E04A42`); **never green for both**; each pairs glyph + color (not color alone).

### B — Hover peek
- Dwell **0.15s** → shape begins to open; pill scales **~1.028**.
- Peek tray drops per-session micro-rows, **actionable item on top** (perm before
  running before question); `Click to open · Esc to dismiss` caption.
- Expand is **one shape**: top radius 0→6, glyph **travels** into header (no
  crossfade); motion = relay-snap (response .32 / damping .92).

### C — Expanded list
- Header notch-split: left `CLAUDE · 5H 17%` green tape + `RESET 2H 10M`; right
  `CLAUDE · 7D 76%` amber tape + `RESET 4D 06H`; mute/settings/quit switches.
- Summary strip: `ATTN 2` (red lit) · `RUN 2` (green lit) · `DONE 3` (blue lit) ·
  `IDLE 0` (dark).
- Column captions `STATUS SESSION MODEL TIME`.
- Rows top-to-bottom by attention: `WARN` perm (red inset) → `CAUT` question
  (amber inset) → `RUN` → `RUN ⚙3 SUB` → `DONE` → `INTR` (amber).
- Duplicate `the-automator` disambiguated by **branch chip** (`feat/auth-bridge`
  vs `main`).
- Footer: green **blinking** link lamp + `BRIDGE LINK LINK` + `N SESSIONS`
  (**no** socket path, **no** EVT/MIN — §6).

### D — Row detail
- Metagrid: Agent / Model / **Mode** (`acceptEdits`) / **Branch** / Uptime
  (tabular, live) / Terminal + **`ATTACHED`** badge.
- "NOW" narration: verb `#4AC99E` + file paper; "Last message" as **clean rich
  text** (not raw dump); inline `code` in `#4AC99E`.
- Primary CTA = **Jump to terminal**; Transcript link; **Dismiss hover-reveal**.

### E — Permission (hero, MASTER WARNING)
- Red beacon (chamfer 3) pulsing at **1s**; placard **"MASTER WARNING"** (red);
  `PERMISSION REQUIRED` kicker; `HELD 0m 08s` counter counting up.
- E1 command: `$ swift build -c release --product OpenIslandHooks` syntax-lit in a
  chamfered mono box; narration; scoped `⌘⇧Y` always-allow options.
- E2 diff: `−1 +2`; del row red gutter/bg, add row green gutter/bg (phosphor
  `#4AC99E`/`#E04A42`).
- ACK switches: **ALLOW ONCE ⌘Y** (inverted paper), **ALLOW ALWAYS ⌘⇧Y** (ghost),
  **DENY ⌘N** (outlined). Glyphs match the real global handler, never ⏎/⎋.
- E3 Codex: no ACK switches; `↗ Approve in Codex` bar + `Jump to Codex.app`
  (`requiresTerminalApproval == true`).

### F — Question (MASTER CAUTION)
- Amber beacon pulsing at **1.2s**; placard **"MASTER CAUTION"** (amber) — this
  header is **new** (shipped question has none).
- F1: `AUTH Q 1/2 · SINGLE` (digits 1–3) with per-option descriptions; `SCOPE
  Q 2/2 · MULTI` (digits 4–6, amber-filled checks) + `Other` (digit 7) freeform;
  hint "Digits **1–9** select · Enter submits · Esc closes"; Submit `⏎`.
- F2 compact single: one question, `1/2` hint, tight footprint.
- Digits/Enter driven by `OverlayUICoordinator` (not restyled semantics).

### G — Subagents + tasks (engine cluster)
- 3 engines, each: type placard (`EXPLORE`/`GENERAL`/`PLAN`, `#4AC99E`) + breathing
  lamp + task line + **per-subagent elapsed** (`3m 04s` tabular from `startedAt`) +
  arc fill %.
- Todo list `4 / 6 DONE`: done=blue check + strikethrough; doing=green breathing
  box; pending=dim.
- Compression: whole cluster → **one pulsing lamp** + wing "3 subagents · 4/6".

### H — Completed (advisory blue)
- `SUCCESS` badge (blue check); result as **prose** (not dump); donestats Outcome
  `✓ Success` / Duration `43m 12s` / Files `3 changed` / Agent; follow-ups
  **Jump / Transcript / Reply / Dismiss**.
- Interrupted/failed variants carry the outcome banner + amber/red status.

### I — Usage meters (tape gauges)
- NOM: `< 70%` green fill; ticks at 70 (hairline) + 90 (red crit); `Resets in 2h 10m`.
- CAUT: `70–90%` amber; value amber.
- CRIT: `≥ 90%` red, fill past the 90 tick, gauge **blinks**; `Resets in`.
- Pill compression: worst window → wing mini-tape + `7D 76%` (amber).

### J — Empty
- Lamp grid: 1 lit (breathing `2.6s`) + 3 dark; heading **"ALL SYSTEMS NOMINAL"**;
  monitoring copy; `BRIDGE LINK · MONITORING · 0 SESSIONS`; footer `IDLE`.

### K — Motion strip (live CSS → Swift constants)
- Phosphor pulse (running · 2s), Expand morph (one shape · radius latch), Attention
  pulse (master alarm · 1s), Row entrance (relay-snap in), Success settle (flash →
  advisory), **Lamp snap-on (120ms on · soft decay)**. Each demo maps to a named
  Swift animation constant; `prefers-reduced-motion` → steady.

---

## 5. Conformance checklist

### Fixtures (extend `AppearancePreviewFixtures.sessions`, `AppearanceSettingsPane.swift:1155`)
Current fixtures cover only A2/A3/A4/A5-ish + C-partial (5 sessions:
approval-codex, answer-claude, running-cursor, done-gemini, idle-codex). They
**lack** everything the mockup adds. Map A–K to deterministic fixtures:

| Frame | Fixture need (fields to set) |
|---|---|
| A1 / J | empty (0 sessions) |
| A2 / C-run | running + `currentTool`/`currentCommandPreview` → "Editing AppModel.swift" |
| A3 / C-perm / E1 | `waitingForApproval` + `permissionRequest.commandPreview` (`swift build …`) + `suggestedUpdates` |
| E2 | `permissionRequest.fileDiffSource` (old/new) on an Edit |
| E3 | `waitingForApproval` + `tool: .codex` + `requiresTerminalApproval = true` |
| A4 / F1 | `waitingForAnswer` + multi-`QuestionPromptItem` (single + `multiSelect` + option descriptions + Other) |
| F2 | single-question prompt (`tool: .opencode`) |
| A5 / H | `completed` + `outcome: .success` + assistant message (markdown) + `reply` action |
| A6 / C-intr | `completed` + `outcome: .interrupted` **(new — no fixture has non-success outcome)** |
| A6 | `completed` + `outcome: .failed` |
| C-dupe | two `the-automator` sessions w/ different `worktreeGitBranch` **(claude only)** |
| D | running + `attachmentState: .attached` + `permissionMode: .acceptEdits` + `isRemote` (SSH) |
| G | claude running + `activeSubagents[3]` (agentType/task/startedAt) + `activeTasks[6]` (4 done/1 inProgress/1 pending) **(new)** |
| I | `UsageProviderPresentation` windows with **non-nil `resetsAt`** at 17/76/93% **(current preview usage has `resetsAt: nil`)** |

### Token equality tests (must stay green / update)
- `FlightDeckThemeTests.statusPaletteIsTheFour...` — **unchanged** (two-tier color
  mapping already correct).
- `everyReadableTypographyRoleHoldsTheTenPointFloor` — extend `readableRoleSizes`
  with any new sans roles; all ≥ 10 (lift the 9–9.5px caps).
- `chamferedChromeMorphsWithoutAPouredFillet` — unchanged (radii 6, fillet 0).
- `flightDeckIsAFlatPanelWithoutVibrancy` — unchanged.
- `FlightDeckUsageWindowGauge.usageColor` band tests (90/70) — unchanged when the
  gauge geometry flips to tape (keep the same thresholds).
- New: assert `masterWarning` string is wired to `statusWaitingForApproval` (red)
  and `masterCaution` to `statusWaitingForAnswer` (amber).
- New: assert `FlightDeckApprovalFormat.Shortcut.glyphString` == `⌘Y / ⌘⇧Y / ⌘N`
  (already pinned — keep).

### Snapshot pins (Settings previews, AB-305)
Pin one snapshot per frame A–K at the editing profile, both notch + top-bar,
default + Increase Contrast + Reduce Motion, en + zh-Hans. Hero pins:
permission (MASTER WARNING red), question (MASTER CAUTION amber), engine cluster,
tape gauges (NOM/CAUT/CRIT), empty (ALL SYSTEMS NOMINAL).

### Judged-by-eye (manual sign-off)
- Phosphor glow bleeds **outside** each lit lamp silhouette (pill, lane, tiles,
  engines, footer, empty grid) without smearing text.
- Running breathes at 2s (not blink); lamp snap-on reads as instant-on / soft-decay.
- Permission frame "feels like an EVENT" (pulsing red glass), not a restyled form.
- Sans headline vs mono values is visibly distinct; no mid-word truncation;
  duplicate names disambiguated by branch.
- Attention pill readable "across the room"; exactly **one loud thing** at a time.
- Colored attention bloom on the closed pill matches per-state tint.

---

## 6. Data / plumbing prerequisites (source field per brief §3)

| Shown in mockup | Status today | Source field (§3) | Action |
|---|---|---|---|
| **RESETS-IN** countdown on gauges | computed but only in `.help()` tooltip | `UsageWindowPresentation.resetsAt` | surface inline; preview fixtures set `resetsAt` non-nil |
| **Attachment** readout (`ATTACHED`/stale/detached) | captured, not rendered | `AgentSession.attachmentState` | render as metagrid badge (D) |
| **Narrated activity** ("Editing AppModel.swift") | shipped shows `$ <preview>` | current tool name + `currentCommandPreviewText` / `spotlightActivityLineText` | needs a **verb map** (Edit→"Editing", Task→"Orchestrating"); confirm whether narration exists or just echoes the tool — likely a **new translation layer** |
| **Branch** chip + disambiguation | not surfaced in FlightDeck row | `worktreeGitBranch` (**claude only**) | render chip; ⚠ mockup shows a **codex** row w/ `feat/auth-bridge` — codex has no branch per §3, so that specific content is not truthful; gate the chip on availability |
| **Permission mode** chip (`acceptEdits`) | not surfaced | `permissionMode` (**claude only**) | render chip/metagrid (C/D); gate on claude |
| **Subagents engine cluster** + per-subagent elapsed | **not rendered at all** | `activeSubagents[]` (agentType/task/`startedAt`) | new surface (G); elapsed = now − startedAt |
| **Todo list** (4/6) | not rendered | `activeTasks[]` (pending/inProgress/completed) | new surface (G) |
| **`⚙ N SUB` / compression** in pill+row | not rendered | count of `activeSubagents` | roll-up wing + row chip |
| **HELD Ns** on the alarm | not shown | *(no explicit "request arrived at" field)* | ⚠ needs a held-since timestamp; approximate from `session.updatedAt` or add one |
| **SSH** badge | shipped shows APP=`SSH` | `isRemote` | reuse; render as chip |
| Diff / scoped always-allow / Codex jump | shipped ✅ | `fileDiffSource`, `suggestedUpdates`, `requiresTerminalApproval` | keep |
| Usage compressed into pill (mini-tape) | **not routed to pill** | `usedPercentage` (worst window) | new `IslandRightSlotContent` case (usage) |
| Attention `.seg` (ACK×1 / ANSWER×1) in pill | **not a right-slot kind** | waiting count by phase | new `IslandRightSlotContent` case (attention segment) |
| **Footer `socket path` + `EVT/MIN`** | shipped footer = link + count only | **no source field** (EVT/MIN, socket path) | ⚠ **do not render** — invented precision (the "×4" trap, brief §1.2/§3). Keep shipped's honest link + session count. |

---

## Appendix — key files

- Tokens: `Sources/OpenIslandApp/Theme/IslandColorTokens.swift` (`.flightDeck`
  L282–316), `IslandMetricsTokens.swift` (L90–116), `IslandMotionTokens.swift`
  (L100–113), `IslandMaterialTokens.swift` (L107–122), `IslandThemeTokens.swift`.
- Slots: `Views/Island/FlightDeckClosedPill.swift`, `FlightDeckHeaderControls.swift`,
  `FlightDeckUsageSummary.swift`, `FlightDeckSessionRow.swift` (incl.
  `FlightDeckApprovalCard` L1410, `FlightDeckCautionGlow` L1625,
  `FlightDeckApprovalButton` L1671, `FlightDeckChamferedRectangle` L929),
  `FlightDeckSessionListScaffold.swift` (BRIDGE LINK footer L376),
  `FlightDeckEmptyState.swift`, `FlightDeckBootstrapPlaceholder.swift`,
  `FlightDeckInstallHooksHint.swift`.
- Typography: `FlightDeckTypography` / `FlightDeckText` in `FlightDeckTheme.swift`.
- Fixtures: `Views/AppearanceSettingsPane.swift` `AppearancePreviewFixtures` (L1155).
- Strings: `Resources/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings`
  (`island.flightDeck.*` L251–272; add `approval.masterWarning`).
- Tests: `Tests/OpenIslandAppTests/FlightDeckThemeTests.swift`,
  `FlightDeckSessionRowTests.swift`.
