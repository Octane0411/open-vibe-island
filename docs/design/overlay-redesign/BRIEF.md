# Open Island — Overlay Redesign Brief (shared, read fully before designing)

Open Island is a native macOS notch/menu-bar overlay that monitors local AI coding-agent
sessions (Claude Code, Codex, Gemini, Cursor, OpenCode, Kimi + Claude forks), surfaces
permission/question events, and jumps back to the exact terminal pane. Local-first, no server.
Target quality bar: Apple Dynamic Island / Linear / Arc / Raycast — *premium native macOS*.

Your deliverable: ONE self-contained HTML file (no external resources, no CDNs) that is a
high-fidelity design board for a complete overlay redesign in your assigned art direction.
It must cover EVERY scenario in §4. It will be judged on taste, hierarchy, typography,
motion, and truthfulness to the real data model (§3).

---

## 1. Diagnosis of the current UI (what you must fix)

1. **No attention hierarchy.** "Does anything need me right now?" is not answerable at a
   glance. Running/done/idle are near-identical dots; a pending permission looks no louder
   than a finished session.
2. **Raw machine data, untranslated.** "Mcp Playwright Browser Evaluate ×4" (title-cased
   tool identifier), raw `$ source ~/.nvm/nvm…`, `$ http://127.0.0.1:4747/`. The UI renders
   internal state instead of narrating it ("Evaluating in the browser · 4th call").
3. **Pill soup + placeholder noise.** `claude` / `BYPASS` / `Opus 4.8` / `codex` as
   equal-weight pills; "Transcript" label rows and `—` dash columns spend prime space on
   zero information.
4. **Typography has no system.** One size/weight nearly everywhere, monospace for prose,
   mid-word truncation ("clau…", "You are gener..."), three identical "the-automator" rows
   with no disambiguation, no tabular numerals.
5. **No motion identity.** The metaphor is the Dynamic Island, yet nothing morphs, breathes,
   or transitions.
6. **Cryptic meters.** "Cl 5h ▮▮▮ 17% OK" — abbreviation soup, EQ-style segment bars, green
   used for both "usage" and "success".
7. **Destructive actions always exposed.** ✕ on every row at equal prominence with expand.
8. **Space spent, not invested.** Chrome oversized; the valuable content (what the agent did,
   what it wants) truncated or buried.

Design principles to enforce: one loud thing at a time (attention states dominate);
translate identifiers into human sentences; progressive disclosure (quiet by default, loud
when needed); color = state only, never decoration; a real type scale with tabular numerals
for all timers/meters; middle-truncate paths, disambiguate duplicate session names (branch /
worktree / recency); hover-reveal destructive actions; motion with purpose (fast springs for
morphs ~250–350ms, slow ambient breathing 2–4s for "working", no gratuitous animation).

## 2. Physical context (must be respected)

- The overlay hangs from the TOP CENTER of a MacBook display, below/around the notch, above
  all windows. Dark environment. Rendered on retina.
- REAL dimensions (from OverlayPanelController.swift — design to these): collapsed pill
  height = notch height (~38pt; 24pt in top-bar mode on external displays); pill width =
  notch width (~190pt) + ~88pt of lateral wings, up to +200pt more when a text label shows.
  Expanded panel width = 540pt (notch mode) / 520pt (top-bar). Panel height is measured from
  content; the session list scrolls beyond 560pt. List side insets 46pt (notch) / 16pt.
  Corner radii today range 6pt (Flight Deck) to 26pt + 12pt notch fillet (Poured).
- The expand/collapse is ONE continuously-morphing shape: top corner radius animates 0→R,
  bottom radius pillHeight/2→R while the frame grows; the status glyph travels from the pill
  into the header (it does not crossfade). Hover scales the pill ~1.03 and opens after 0.15s
  dwell. Your motion frames should honor this morph model.
- Simulate this context in the mockup: a dark macOS desktop strip with a menu bar + notch at
  top of each frame (simple, dark, credible; the overlay is the star).
- Fonts: use the native stack only — `-apple-system, BlinkMacSystemFont, "SF Pro"` for UI,
  `ui-monospace, "SF Mono"` for code, optionally `"New York", ui-serif` if your direction
  calls for a serif. `font-variant-numeric: tabular-nums` on every timer/counter/meter.

## 3. Ground truth — data the app REALLY has (never invent fields)

Per session: agent kind (claude/codex/gemini/opencode/cursor/kimi/… with brand color);
session title → workspace name; phase ∈ {running, waitingForApproval, waitingForAnswer,
completed}; outcome when completed ∈ {success, interrupted, failed}; summary one-liner;
firstSeenAt (→ live running duration), updatedAt (→ age like "5m"); current tool name +
current command preview; last/initial user prompt; last assistant message (Gemini even has
full markdown body); transcript path (claude/codex/gemini); model name (claude/opencode/
cursor only); permission mode (claude only: default/plan/acceptEdits/bypassPermissions/
dontAsk/auto); worktree git branch (claude only); working directory (captured, never shown —
you MAY show it); SSH badge (isRemote); terminal app + workspace for jump.

Permission request: title, human summary, affected path, full command preview, file diff
(old/new text for Edit/Write — you can render a real inline diff), primary/secondary action
labels, and **suggestedUpdates**: scoped "always allow" options with human labels like
"Yes, allow running `swift build` from this project" (Claude family). Approve/Deny from the
overlay is a REAL round-trip — the hook blocks until the user decides. Codex.app is the
exception: approval must happen in-app → show a "jump to approve" treatment for it.

Question prompt: 1..N questions, each with header (chip label ≤12 chars), question text,
options each having label + description, multiSelect flag, freeform "Other". Answering from
the overlay is REAL (Claude, OpenCode).

Subagents (Claude only): activeSubagents[] with agentType, task description, startedAt
(→ live elapsed per subagent); activeTasks[] = todo list with status pending/inProgress/
completed. These live INSIDE a session (nested), they are not separate sessions.

Usage meters: Claude 5h + 7d windows, Codex dynamic windows (e.g. 7d) — usedPercentage
(0–100, higher = more consumed), resetsAt (→ "resets in 2h 10m" — currently hidden, SHOW IT),
Codex planType. Thresholds: <70 fine, 70–90 warn, ≥90 critical.

There is NO per-session token/cost data, NO tool-invocation counter (the ×4 in the old UI
was fake precision), NO kill-process action (Dismiss only hides a row). Don't design those
as if real; "dismiss" is the honest verb.

States that are real but currently invisible (opportunities): attachment (terminal pane
attached/stale/detached), interrupted-vs-failed-vs-success completion, permission modes
beyond BYPASS, resets-at countdowns, branch names, working directory, Claude todo list.

## 4. Scenario matrix — EVERY mockup must include ALL of these as labeled frames

A. **Collapsed pill — ambient states** (this is where the product lives 95% of the time):
   A1 idle/monitoring (calm, nearly invisible); A2 one/many sessions working (ambient "alive"
   motion — breathing, shimmer, orbit — visible from across the room but not distracting;
   show how current activity is narrated, e.g. "Editing AppModel.swift"); A3 attention —
   permission needed (the loudest ambient state, amber/hot accent, e.g. count badge);
   A4 attention — question waiting; A5 a session just completed (brief success moment that
   then settles); A6 completion outcome variants (interrupted/failed).
B. **Hover peek** — pointer over the collapsed pill, pre-click: the morph begins; show an
   intermediate "peek" state (e.g. slightly grown pill with per-session micro-rows or the
   single actionable item surfaced).
C. **Expanded panel — session list** with a realistic mix: 1 running w/ live activity line,
   1 waiting-for-permission, 1 waiting-for-question, 1 completed success, 1 completed
   interrupted, 1 running with active subagents. Include header (brand/status + usage meters
   + mute/settings/quit), summary strip, and footer. Show duplicate workspace names properly
   disambiguated (branch or recency).
D. **Row expanded — session detail**: metadata done tastefully (agent, model, permission
   mode, branch, duration), narrated current/last activity, last assistant message rendered
   as clean rich text (not a raw dump), transcript affordance, jump-to-terminal as the
   primary CTA, dismiss as hover-reveal.
E. **Permission request — full treatment**: command with syntax highlighting OR file-edit
   with inline diff; Approve/Deny; the scoped "always allow…" options; the Codex.app
   variant (jump-to-approve). This must be the most polished frame — it's the core value.
F. **Question prompt — full treatment**: multi-question example with option descriptions,
   multi-select, freeform "Other"; show single-question compact variant too.
G. **Subagents + tasks**: a Claude session running 3 subagents (with per-subagent elapsed +
   task description) and a todo list with mixed statuses; how this compresses into the row
   and the collapsed pill.
H. **Completed session** — result summary rendered beautifully, duration, outcome badge,
   follow-up affordances (jump, transcript, dismiss).
I. **Usage meters — redesigned**: Claude 5h/7d + Codex window with resets-in countdown,
   threshold states (fine/warn/critical), and how they compress into the collapsed pill.
J. **Empty state** — no sessions; quiet confidence, not a hole.
K. **Motion spec strip**: a row of small labeled demos of your motion language implemented
   in CSS — pill breathing, expand morph, attention pulse, row entrance, success settle.
   Real CSS animations, not descriptions.

## 5. Mockup format requirements

- ONE self-contained `.html` file. Inline all CSS/JS. No external fonts/images/libraries.
  System font stack only. SVG inline where needed.
- Structure it as a scrollable dark design board: a short header (direction name + one-line
  thesis), then sections §A–§K in order, each frame labeled with scenario ID + name +
  a one-line rationale caption. Frames rendered at 1x logical pt sizes (the overlay ~520pt
  wide) centered on dark desktop context strips.
- Live states MUST actually animate (CSS keyframes): breathing/working, attention pulse,
  shimmer, morph demo. Hover states must actually work with :hover where sensible
  (row hover, destructive-reveal, hover-peek frame).
- Use realistic content drawn from the real workflow: workspaces `open-vibe-island`,
  `the-automator`, `niche-radar`; agents claude (Opus 4.8, Sonnet 5, Fable 5), codex,
  gemini, cursor; a `swift build` permission; an `rtk grep -rn "fetch(" packages/ui/src`
  command; an AskUserQuestion like "Which auth method should the bridge use?" with options;
  a completed result about editing AGENTS.md/CLAUDE.md. Timers like 1m 42s, 43m, 2h 10m.
- Every text string you show must be something the app could truthfully compute from §3.
- Accessibility sanity: contrast ≥ 4.5:1 for body text, state never conveyed by color alone
  (pair with icon/shape/label).
- Aim for ~800–1400 lines of careful HTML/CSS. Craft > quantity. No lorem ipsum.

## 6. Architecture contract (design within it — it makes your mockup implementable)

The app has a real theme system: a theme = design tokens (colors / metrics / motion /
material) + 8 swappable slot views: closedPill, openedHeader, sessionRow (incl. permission +
completion bodies), sessionList (summary strip + section headers + footer), notificationCard,
emptyState, bootstrapPlaceholder, installHint. Your mockup should be expressible as those
slots + tokens. Non-negotiable contract invariants shared by every theme:

- **Attention is loudest** — a waitingForApproval/waitingForAnswer session always dominates
  every surface it appears on; there is exactly one "activeActionableSession" that can pull
  the island open as a notification card (auto-collapses after 10s for completions; hover
  pauses the countdown; a "Show all N sessions" affordance sits below it).
- **Keyboard**: permission card ⌘Y = Allow once, ⌘⇧Y = first "always allow" option,
  ⌘N = Deny; question card digits 1–9 select options, Enter submits; Esc closes the island.
  SHOW these as subtle keycap hints in your permission/question frames — it signals quality.
- **Row verbs** are exactly: approve, answer, reply (completed sessions, narrow support),
  jump (row tap = jump to terminal — the primary action), dismiss (hide, hover-reveal).
  There is no kill.
- The question prompt structure is shared across themes (you restyle it, you don't
  restructure its semantics: numbered options, multi-select, freeform, submit).
- Sessions can be grouped (by state / agent / project) with tinted section headers, and the
  summary strip shows only non-zero buckets: total / waiting / running / done / idle.
- Closed-pill anatomy today: left glyph (3 animated bars: wave=running, breathe=waiting,
  still=idle), optional center label, right slot = either "×N" count or a mini agents grid
  (one cell per session: bright=running, dim=idle, breathing=waiting). You may reinvent the
  vocabulary, but the pill must communicate: count, liveness, and attention — while fused
  around the physical notch cutout (content sits in the wings, not behind the notch).
- Header in notch mode splits around the notch: usage meters occupy left/right lanes beside
  the cutout; mute / settings / quit are small circular controls on the right.

## 7. Fidelity bar (added after round-1 review — binding)

Round-1 verdict: "Poured Island 2.0 · Liquid Glass" and "Flight Deck 2.0 · Glass Cockpit"
were APPROVED. The other two boards were REJECTED as "average in UX and fidelity, low
attention to detail." What made the winners win — you must match or beat ALL of this:

- A continuous PHYSICAL metaphor rendered with layered light: multi-stop gradients, specular
  edges, inner luminance, glow that bleeds outside the silhouette, believable multi-layer
  shadow stacks. Never a single flat fill with a border.
- A hero permission frame that feels like an EVENT (amber light inside glass; MASTER
  WARNING annunciator) — not a restyled form.
- A real, named motion identity — parameterized, demonstrated live in §K, and applied to
  every stateful element across the whole board, not just the demo strip.
- Obsessive micro-detail everywhere: keycap hints, hover reveals, focus treatments, aligned
  baselines and optical corrections, per-state ambient pill variants that read from across
  the room, believable content in every frame.
- Semantic color discipline under pressure: the richer the material, the stricter the rule
  that color = state. Identity stays a whisper (small monogram/tick, never a colored pill).

Anti-goals (why the rejected boards lost): flat single-layer cards; frames that all look
the same; sparse rows with leftover space; generic type hierarchy; static non-hero frames;
detail invested only in one frame while the rest sit at wireframe quality.
