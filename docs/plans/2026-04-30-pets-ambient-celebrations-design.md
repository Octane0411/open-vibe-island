# Pets, Ambient Theme, Celebrations — Design

**Status:** Approved · **Date:** 2026-04-30 · **Owner:** h4ckm1n-dev fork

## Summary

Three coherent personality additions on top of the existing notch-personalization work, all "vibe-coder + beautiful" focused:

1. **Curated pixel-pet companion library** — 8 hand-picked CC0 pets (cat, dog, ducky, dragon, robot, ghost, plant, slime) replacing the existing SF-Symbol overlay. Each pet animates across 4 states (idle / working / waiting / celebrating). Plus a "Random daily" mode that picks one for the day.
2. **Ambient project theme** — a soft gradient (~12% opacity) inside the island, tinted by the active session's project color. Cross-fades when switching projects. Subtle but atmospheric.
3. **Celebration confetti** — when a session completes, 12 project-colored confetti particles burst around the companion, fall + rotate + fade over 2s. Coherent with the ambient theme — a project's color literally celebrates.

## Goals

- Give the island a real personality without sacrificing usefulness.
- Make project context legible at a glance (color of the chrome = which project).
- Add small, repeatable dopamine moments for completed work.
- Reuse what already exists (`CompanionState`, `ProjectColorRegistry`).

## Non-goals

- AI-generated pet sprites or user-uploaded sheets (Phase 3).
- Sound effects (separate feature, deferred).
- Pet evolution / level-up systems.
- Multiple pets simultaneously.

## Locked decisions

| Area | Decision |
|---|---|
| Pet library size | 8 pets, sourced from 2 CC0 packs (Kenney.nl Animal Pack Redux + Pixel Platformer Characters) |
| Ambient placement | Soft background gradient overlay inside the island, 5–20% opacity (default 12%) |
| Celebration particles | 12 project-tinted confetti, fall + fade + rotate over 2s |

## Architecture

### New types in `OpenIslandCore`

```swift
public enum CompanionPet: String, CaseIterable, Codable, Sendable {
    case cat, dog, ducky, dragon, robot, ghost, plant, slime
}

public struct CompanionPetSpec: Codable, Sendable {
    public struct StateSpec: Codable, Sendable {
        public var frames: Int
        public var fps: Double
    }
    public var idle: StateSpec
    public var working: StateSpec
    public var waiting: StateSpec
    public var celebrating: StateSpec
}

public enum CompanionPetManifest {
    public static func parse(_ data: Data) throws -> [CompanionPet: CompanionPetSpec]
}
```

The existing `CompanionState` enum (idle / working / waiting / celebrating) is unchanged.

### New views (`Sources/OpenIslandApp/Views/`)

- `NotchWidgets/AnimatedCompanionPet.swift` — `TimelineView(.animation)`-driven sprite-sheet playback for a `CompanionPet` + `CompanionState`.
- `AmbientThemeOverlay.swift` — `LinearGradient` overlay tinted by the spotlight session's project color, cross-fades on switch.
- `CelebrationParticles.swift` — `Canvas`-based 12-particle confetti, deterministic per-particle physics keyed off elapsed time.

### Resource bundle

`Sources/OpenIslandApp/Resources/Pets.bundle/`:
- 8 sprite sheets (one PNG per pet), 512×256, ~25–30KB each
- `manifest.json` (per-pet frame counts + fps)
- `LICENSE.txt` crediting Kenney.nl

Total bundle ~240KB.

### Settings additions

In `AppearanceSettingsPane.swift`, three new sections between "Project colors" and "Notch widgets":
- **Companion pet** — 4×3 tile grid (8 pets + None + Daily) with live preview.
- **Ambient theme** — toggle + opacity slider (5–20%, default 12%).
- **Celebrations** — single toggle.

### AppModel additions

- `companionPet: CompanionPet?` — UserDefaults `appearance.companionPet`. Special case `"daily"` for random-of-the-day.
- `ambientThemeEnabled: Bool` — UserDefaults `appearance.ambientTheme.enabled`, default `true`.
- `ambientThemeOpacity: Double` — UserDefaults `appearance.ambientTheme.opacity`, default `0.12`.
- `celebrationsEnabled: Bool` — UserDefaults `appearance.celebrations.enabled`, default `true`.

## Data flow

### Pet rendering

```
AppModel.companionPet (UserDefaults)
   │
   └─► IslandPanelView body — gates which view to use:
        ├── nil               → existing CompanionStateOverlay
        ├── .cat / .robot/... → AnimatedCompanionPet(pet:, state:)
        └── "daily"           → AnimatedCompanionPet(pet: dailyPet, state:)
```

`AnimatedCompanionPet` body:
- Loads sprite sheet `Bundle.module.url(forResource: pet.rawValue, withExtension: "png", subdirectory: "Pets.bundle")`. Cached statically.
- Looks up the pet's `CompanionPetSpec` from the parsed manifest.
- `TimelineView(.animation)` ticker drives frame index: `Int((time - stateStartTime) * fps) % frameCount`.
- Renders one cell of the sprite sheet via `Image.cropped(rect:)` + `.frame(width: 16, height: 16)` (scaled to overlay size).

`dailyPet` — hash `Calendar.current.startOfDay(for: Date()).timeIntervalSince1970` → index in `CompanionPet.allCases`. Stable within a calendar day.

### Ambient theme

```
spotlightSession?.jumpTarget?.workingDirectory ?? .workspaceName
   │
   ├─► ProjectColorRegistry.color(for: key) → ProjectColor
   │
   └─► AmbientThemeOverlay(tint: tint, opacity: model.ambientThemeOpacity)
        │
        └─► LinearGradient(colors: [tint.opacity(opacity), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .animation(.easeInOut(duration: 0.4), value: tint)
```

Inserted into `IslandPanelView` body **above** the existing background, **below** all content. Visible in both closed and expanded states for layout consistency.

When `ambientThemeEnabled == false`: returns `EmptyView()`. Zero work.

When no spotlight session: tint = `Color.clear`. No work.

### Celebration particles

```
IslandPanelView.body
  ├── @State var lastCelebrationTimestamp: Date?
  │
  ├── .onChange(of: companionState) { _, new in
  │       guard model.celebrationsEnabled else { return }
  │       guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
  │       if new == .celebrating { lastCelebrationTimestamp = Date() }
  │   }
  │
  └── if let ts = lastCelebrationTimestamp,
         Date().timeIntervalSince(ts) < 2.0 {
         CelebrationParticles(tint: spotlightProjectColor, startedAt: ts, count: 12)
             .allowsHitTesting(false)
             .id(ts)
     }
```

`CelebrationParticles` body — `Canvas` view:
- 12 particles, each with seed `i` ∈ [0, 12).
- Spawn position: anchored near companion, randomized x-offset by seed.
- Initial velocity: small upward + sideways component derived from seed.
- Per-frame physics: `position = origin + v*t + (0, 0.5*g*t²)` with `g = 350pt/s²`.
- Rotation: `seed * 90° + t * 720° per second`.
- Opacity: `1 - elapsed/2.0`.
- Shape: 4×4pt rounded square, fill = tint.
- Self-stops at `elapsed > 2s` (canvas draws fully transparent → SwiftUI removes from tree on next render via the timestamp guard).

Reduced Transparency: ambient gradient drops to 0% opacity; particles still render (they're solid, not blur).

Reduced Motion: particles skipped entirely (the trigger short-circuits).

## Pet library spec

| Pet | Source pack | Idle | Working | Waiting | Celebrating |
|---|---|---|---|---|---|
| cat | Animal Pack Redux | tail flicks (4) | claws batting (6) | head tilts (4) | jumps + spins (8) |
| dog | Animal Pack Redux | breathing (4) | digging (6) | ears perked (4) | tail wags hard (8) |
| ducky | Animal Pack Redux | floats (4) | pecking (6) | head turns (4) | flap wings (8) |
| dragon | Animal Pack Redux | wing flap (4) | breath (6) | head turn (4) | fly + sparkle (8) |
| robot | Pixel Platformer | LED blink (4) | gears (6) | antenna pulse (4) | dance (8) |
| ghost | Pixel Platformer (recolor) | drift (4) | spin (6) | wobble (4) | spiral (8) |
| plant | Pixel Platformer | sway (4) | grow (6) | droop (4) | flowers bloom (8) |
| slime | Pixel Platformer | breathe (4) | bounce (6) | shrink (4) | split + merge (8) |

**fps defaults**: idle=4, working=8, waiting=6, celebrating=12.

**Sprite sheet layout**: 4 rows × 8 cols × 64×64 pixels per cell. Row order: idle, working, waiting, celebrating. Empty cells transparent.

## Settings UX

### Companion pet

```
Companion pet
   ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐
   │None│ │ Cat│ │ Dog│ │Duck│ │Drag│ │Robo│ │Ghst│ │Plnt│
   └────┘ └────┘ └────┘ └────┘ └────┘ └────┘ └────┘ └────┘
          ┌────┐ ┌────┐
          │Slme│ │Daily│
          └────┘ └────┘

   ┌── live preview (4× scale) ──┐
   │ [animated pet idle frame]   │
   └─────────────────────────────┘
```

- 4×3 tile grid; selected tile shows a 2pt accent border.
- Each tile shows a 32×32 idle-frame thumbnail + name label.
- Live preview cycles `idle → working → waiting → celebrating` (2s each, looping).

### Ambient theme

```
Ambient theme
   [✓] Tint island with project color
   Intensity:  Subtle ●━━━━━━━━○━━━━━ Bold     12%
   "Tints the inside of the island in the active session's
   project color, animated when you switch projects."
```

- Toggle bound to `ambientThemeEnabled`.
- Slider 0.05…0.20, bound to `ambientThemeOpacity`.

### Celebrations

```
Celebrations
   [✓] Celebrate when sessions complete
   "Spawns a brief burst of project-colored confetti when a
   session finishes a task."
```

Single toggle bound to `celebrationsEnabled`.

### Localization

New keys in `en.lproj`, `zh-Hans.lproj`, `zh-Hant.lproj`:

```
"settings.companion.title", "settings.companion.preview",
"settings.companion.pet.{none,daily,cat,dog,ducky,dragon,robot,ghost,plant,slime}",
"settings.ambient.{title,toggle,intensity,subtle,bold,help}",
"settings.celebrations.{title,toggle,help}"
```

Chinese files start with English placeholders + `/* TODO: translate */`, consistent with existing pattern in this fork.

## Error handling & edge cases

**Pet assets**
- Missing PNG / corrupt manifest → `AnimatedCompanionPet` falls back to existing `CompanionStateOverlay`. Log once at warn.
- Manifest pet without matching PNG → tile hidden in settings; selection blocked.
- User selected a pet that's later removed → silent fallback to default overlay; settings shows "Unavailable" and lets them re-pick.

**Daily mode**
- Hash uses local-timezone `startOfDay`. Stable within calendar day. Crosses midnight cleanly.

**Animation lifecycle**
- `TimelineView(.animation)` pauses when off-screen.
- Multiple celebrations within 2s: existing `CompanionState.derive` debounce (2s window) prevents stacking. `.id(timestamp)` on the particles view forces a clean restart if it does fire.
- State-change mid-animation: cuts to new state's frame 0 instantly. Honest, no transition flicker on a small overlay.

**Ambient theme**
- `ProjectColorRegistry.color(for:)` always returns a hash-derived color → never nil.
- Rapid spotlight switches collapse into one 0.4s cross-fade.
- Renders in both closed and expanded states for layout consistency.
- Default-appearance mode applies the same gradient (independent of avatar/pet selection).

**Celebrations**
- Pet is "None" → particles spawn from a fixed left-edge anchor.
- No spotlight session → fallback tint `Color.gray.opacity(0.6)`.
- Reduced Motion → trigger short-circuits, no particles.
- Reduced Transparency → ambient gradient drops to 0% opacity.

## Testing

### `Tests/OpenIslandCoreTests/`

- **`CompanionPetTests.swift`**
  - `CompanionPet.allCases.count == 8`.
  - `CompanionPetManifest.parse(...)` over a fixture: valid manifest produces correct map; missing fields default safely; malformed JSON throws.
  - Frame index math: `frameIndex(at: t, fps: 4, frameCount: 4)` correct at boundaries (0, 0.249, 0.25, 1.0, large t for wrap).
  - Daily pet hash stable within a day, changes across days (mocked `Date`).

### `Tests/OpenIslandAppTests/`

- **`AmbientThemeOpacityTests.swift`**
  - Slider clamps to `[0.05, 0.20]`.
  - `effectiveOpacity` is 0 when toggle off, regardless of slider.

- **`CelebrationParticleMathTests.swift`** — pure math, no view rendering
  - Per-particle position is deterministic given seed + elapsed.
  - `opacity(elapsed: 0) ≈ 1`, `opacity(elapsed: 2) ≈ 0`, monotonic between.
  - Particle count parameter accepted (1, 12, 50) without error.

### Manual smoke (PR checklist)

- All 8 pets cycle through 4 states in the live preview.
- "Daily" picks deterministically per day; relaunch confirms persistence.
- Switching workspaces cross-fades the ambient gradient over ~400ms.
- Triggering session completion fires confetti for ~2s.
- Reduced Motion in System Settings → no particles.
- Reduced Transparency → ambient gradient invisible.
- Disabling each toggle in settings cleanly removes the corresponding effect.

### Out of scope

- View snapshot tests (CC0 sprites + animation make this impractical).
- Network-fetched pet packs.
- A11y label localization beyond English (deferred to translation pass).

## Phasing

This design ships as **one feature** (single PR) since the three pieces reinforce each other and share infrastructure. If parallelism is needed:

- **Track A — pet library** (the heaviest sourcing/asset work): `pixel-art-sprite-sourcing` skill, sprite-sheet assembly, manifest, AnimatedCompanionPet view.
- **Track B — ambient + celebrations** (pure SwiftUI on existing data): AmbientThemeOverlay, CelebrationParticles, settings sections.

Tracks A and B can be implemented in parallel by different agents on the same branch. Settings work waits for both.

## Open / deferred

- Sound effects per state — issue #420 community request, separate plan.
- Pet evolution / level-up — out of MVP.
- User-uploaded sprite sheets — Phase 3 feature.
- Voice-to-agent (was option 8 from the brainstorm) — separate plan.
- Quick switcher (was option 5) — separate plan.

## Acknowledgments

- Pixel art adapted from Kenney.nl asset packs (CC0):
  - [Animal Pack Redux](https://kenney.nl/assets/animal-pack-redux)
  - [Pixel Platformer Characters](https://kenney.nl/assets/pixel-platformer)
- `pixel-art-sprite-sourcing` skill for the sourcing workflow.
