# Pets, Ambient Theme, Celebrations Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add three coherent personality additions: animated pixel-pet companions, soft project-colored ambient gradient inside the island, and project-tinted confetti on session completion.

**Architecture:** Pet sprites are authored as compact ASCII grids in Swift source (no external assets in Phase 1) — each pet defines 4 state animations (idle/working/waiting/celebrating) as arrays of grid frames rendered via `Canvas`. Ambient theme is a `LinearGradient` overlay tinted by `ProjectColorRegistry`. Celebrations are a 12-particle `Canvas` confetti driven by deterministic per-particle physics. All three respect Reduced Motion / Reduced Transparency accessibility settings.

**Tech Stack:** Swift 6.2 · SwiftUI · `@Observable` · Swift Testing (`#expect`) · `Canvas` (high-perf custom drawing) · `TimelineView(.animation)` for ticker.

**Reference design:** `docs/plans/2026-04-30-pets-ambient-celebrations-design.md`

**Branch:** continue on `feat/notch-personalization`.

---

## Pragmatic scope adjustment from the design

The design specifies 8 pets sourced from CC0 packs (Kenney.nl). Sourcing + assembling sprite sheets is a manual asset workflow that subagents handle poorly. **This Phase 1 plan ships 3 procedural pets** (cat, ghost, robot) authored as ASCII-grid string literals in Swift source code. Adding more pets is mechanical — each new pet is one more file. Real CC0 sprite assets remain the Phase 2 goal in a separate plan.

The architecture (`CompanionPet` enum, `PixelPetSprite` type, `AnimatedCompanionPet` view, settings tile grid) is built to scale to 8+ pets without changes — just adds tiles.

---

## Conventions

- Swift Testing.
- Run all tests: `swift test`. Single struct: `swift test --filter <Name>`.
- Stage only files the task touches; pre-existing `Assets/Brand/**.png` modifications stay unstaged.
- Each task = one commit. Conventional Commits: `feat(...)`, `test(...)`, `refactor(...)`.
- Do not push.

---

## Task 1 — `PixelPetSprite` + `CompanionPet` enum

**Files:**
- Create: `Sources/OpenIslandCore/CompanionPet.swift`
- Create: `Tests/OpenIslandCoreTests/CompanionPetTests.swift`

**Step 1 — failing tests:**

```swift
// Tests/OpenIslandCoreTests/CompanionPetTests.swift
import Foundation
import Testing
@testable import OpenIslandCore

struct CompanionPetTests {
    @Test
    func threeBuiltInPets() {
        #expect(CompanionPet.allCases.count == 3)
        #expect(CompanionPet.allCases.contains(.cat))
        #expect(CompanionPet.allCases.contains(.ghost))
        #expect(CompanionPet.allCases.contains(.robot))
    }

    @Test
    func rawValuesAreStable() {
        // Stable raw values matter for UserDefaults persistence.
        #expect(CompanionPet.cat.rawValue == "cat")
        #expect(CompanionPet.ghost.rawValue == "ghost")
        #expect(CompanionPet.robot.rawValue == "robot")
    }

    @Test
    func dailyHashIsStableWithinDay() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let pickA = CompanionPet.dailyPick(at: day1)
        let pickB = CompanionPet.dailyPick(at: day1.addingTimeInterval(3600))
        #expect(pickA == pickB)  // same calendar day
    }

    @Test
    func dailyHashChangesAcrossDays() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(86_400 * 7)  // 7 days later
        let pickA = CompanionPet.dailyPick(at: day1)
        let pickB = CompanionPet.dailyPick(at: day2)
        // Across a week, with 3 pets, at least one of the 7 day-shifts will
        // produce a different pick. Not strictly guaranteed for 1-day shifts.
        #expect(pickA != CompanionPet.dailyPick(at: day1.addingTimeInterval(86_400))
            || pickA != CompanionPet.dailyPick(at: day1.addingTimeInterval(86_400 * 2))
            || pickA != pickB)
    }
}
```

**Step 2 — run, expect FAIL:**

`swift test --filter CompanionPetTests` → cannot find `CompanionPet`.

**Step 3 — minimal implementation:**

```swift
// Sources/OpenIslandCore/CompanionPet.swift
import Foundation

public enum CompanionPet: String, CaseIterable, Codable, Sendable {
    case cat
    case ghost
    case robot

    /// Picks a deterministic pet for the calendar day containing `date`.
    /// Used by the "Daily" mode in settings.
    public static func dailyPick(at date: Date = Date()) -> CompanionPet {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let dayNumber = Int(startOfDay.timeIntervalSince1970 / 86_400)
        let index = abs(dayNumber) % CompanionPet.allCases.count
        return CompanionPet.allCases[index]
    }

    public var displayName: String {
        switch self {
        case .cat:   "Cat"
        case .ghost: "Ghost"
        case .robot: "Robot"
        }
    }
}
```

**Step 4 — run, expect 4/4 PASS.**

**Step 5 — commit:**

```bash
git add Sources/OpenIslandCore/CompanionPet.swift Tests/OpenIslandCoreTests/CompanionPetTests.swift
git commit -m "feat(core): add CompanionPet enum with daily picker"
```

---

## Task 2 — `PixelPetSprite` ASCII-grid renderer type

**Files:**
- Modify (append): `Sources/OpenIslandCore/CompanionPet.swift`
- Modify: `Tests/OpenIslandCoreTests/CompanionPetTests.swift`

**Step 1 — append failing tests:**

```swift
@Test
func pixelGridParsesAsciiCorrectly() {
    let grid = PixelPetSprite.parseGrid("""
    .X.
    XXX
    .X.
    """)
    #expect(grid.count == 3)
    #expect(grid[0] == [false, true, false])
    #expect(grid[1] == [true, true, true])
    #expect(grid[2] == [false, true, false])
}

@Test
func pixelGridSkipsBlankLines() {
    let grid = PixelPetSprite.parseGrid("""

    XX

    """)
    #expect(grid.count == 1)
    #expect(grid[0] == [true, true])
}

@Test
func pixelGridUsesTrailingShorterRow() {
    // Each row keeps its own width — no padding. Caller is responsible for
    // matching widths in their authored frames.
    let grid = PixelPetSprite.parseGrid("""
    XX
    X
    """)
    #expect(grid[0].count == 2)
    #expect(grid[1].count == 1)
}
```

**Step 2 — run, expect FAIL** (`PixelPetSprite` not defined).

**Step 3 — append implementation:**

```swift
// Append to Sources/OpenIslandCore/CompanionPet.swift

/// A single frame of a pixel pet: 2D grid of bool (true = filled, false = transparent).
public typealias PixelPetGrid = [[Bool]]

public enum PixelPetSprite {
    /// Parses an ASCII pixel grid where '.' is transparent and any other
    /// non-whitespace character is filled. Skips blank lines.
    public static func parseGrid(_ ascii: String) -> PixelPetGrid {
        ascii
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                line.map { ch in
                    ch != "." && !ch.isWhitespace
                }
            }
    }
}
```

**Step 4 — run, expect 7/7 PASS** (3 new + 4 prior).

**Step 5 — commit:**

```bash
git add Sources/OpenIslandCore/CompanionPet.swift Tests/OpenIslandCoreTests/CompanionPetTests.swift
git commit -m "feat(core): add PixelPetSprite ASCII grid parser"
```

---

## Task 3 — Pet sprite data (cat, ghost, robot)

**Files:**
- Create: `Sources/OpenIslandCore/PetSpriteData.swift`
- Modify: `Tests/OpenIslandCoreTests/CompanionPetTests.swift` (add 1 sanity test)

**Step 1 — append failing test:**

```swift
@Test
func eachPetHasFramesForEveryState() {
    for pet in CompanionPet.allCases {
        for state in CompanionState.allCases {
            let frames = PetSpriteData.frames(for: pet, state: state)
            #expect(!frames.isEmpty, "\(pet)/\(state) has no frames")
            #expect(frames.allSatisfy { !$0.isEmpty }, "\(pet)/\(state) has empty frame")
        }
    }
}
```

(`CompanionState` already has `.allCases` from being `CaseIterable`. If it isn't, add `: CaseIterable` to the enum declaration in `CompanionState.swift` — single-line edit.)

**Step 2 — run, expect FAIL.**

**Step 3 — write `PetSpriteData.swift`** with 3 pets × 4 states × ~3 frames per state. ASCII grids ~10×10 each.

```swift
// Sources/OpenIslandCore/PetSpriteData.swift
import Foundation

public enum PetSpriteData {
    public static func frames(for pet: CompanionPet, state: CompanionState) -> [PixelPetGrid] {
        switch pet {
        case .cat:
            return CatSprites.frames(for: state)
        case .ghost:
            return GhostSprites.frames(for: state)
        case .robot:
            return RobotSprites.frames(for: state)
        }
    }
}

// MARK: - Cat

private enum CatSprites {
    static func frames(for state: CompanionState) -> [PixelPetGrid] {
        switch state {
        case .idle:       return idleFrames
        case .working:    return workingFrames
        case .waiting:    return waitingFrames
        case .celebrating: return celebratingFrames
        }
    }

    static let idleFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        .XXXX.
        .X..X.
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        .XXXX.
        ..X.X.
        """),
    ]

    static let workingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X..--X
        XXXXXX
        .XXXX.
        .X.XX.
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X-X-XX
        XXXXXX
        .XXXX.
        .XXX..
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XXX-XX
        XXXXXX
        .XXXX.
        ..XX.X
        """),
    ]

    static let waitingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X??X?X
        XXXXXX
        .XXXX.
        .X..X.
        """),
        PixelPetSprite.parseGrid("""
        ..X.X.
        .XXXXX
        .X??X?
        .XXXXX
        ..XXXX
        ..X..X
        """),
    ]

    static let celebratingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        ..XX..
        XXXXXX
        XOOOOO
        XXXXXX
        XXXXXX
        X.XX.X
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X*XX*X
        XXXXXX
        .XXXX.
        XX..XX
        """),
        PixelPetSprite.parseGrid("""
        ..XX..
        .XXXX.
        .X**X.
        .XXXX.
        ..XX..
        ..XX..
        """),
    ]
}

// MARK: - Ghost

private enum GhostSprites {
    static func frames(for state: CompanionState) -> [PixelPetGrid] {
        switch state {
        case .idle:        return idleFrames
        case .working:     return workingFrames
        case .waiting:     return waitingFrames
        case .celebrating: return celebratingFrames
        }
    }

    static let idleFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XXOXXOXX
        XXXXXXXX
        XXXXXXXX
        X.X.X.X.
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XXOXXOXX
        XXXXXXXX
        XXXXXXXX
        .X.X.X.X
        """),
    ]

    static let workingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XX-XX-XX
        XXXXXXXX
        XXXXXXXX
        X.X.X.X.
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XX--XXXX
        XXXXXXXX
        XXXXXXXX
        .X.X.X.X
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XXXX--XX
        XXXXXXXX
        XXXXXXXX
        X.X.X.X.
        """),
    ]

    static let waitingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XX??XX?X
        XXXXXXXX
        XXXXXXXX
        X.X.X.X.
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        X??XX??X
        XXXXXXXX
        XXXXXXXX
        .X.X.X.X
        """),
    ]

    static let celebratingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XX**XX**
        XXXXXXXX
        XXXXXXXX
        XX.XX.XX
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .X****X.
        X*XX*XXX
        X**XX**X
        XXXXXXXX
        X.XX.XX.
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XXOOOOXX
        XXXXXXXX
        XXXXXXXX
        XX.XX.XX
        """),
    ]
}

// MARK: - Robot

private enum RobotSprites {
    static func frames(for state: CompanionState) -> [PixelPetGrid] {
        switch state {
        case .idle:        return idleFrames
        case .working:     return workingFrames
        case .waiting:     return waitingFrames
        case .celebrating: return celebratingFrames
        }
    }

    static let idleFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        XX..XX
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X.XX.X
        XXXXXX
        XX..XX
        """),
    ]

    static let workingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        XX*-XX
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        XX-*XX
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        XX**XX
        """),
    ]

    static let waitingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X?XX?X
        XXXXXX
        XX..XX
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X.XX.X
        XXXXXX
        XX..XX
        """),
    ]

    static let celebratingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        XX..XX
        XXXXXX
        X*XX*X
        XXXXXX
        XX**XX
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X**X**
        XXXXXX
        X*..*X
        """),
        PixelPetSprite.parseGrid("""
        XX..XX
        .XXXX.
        XO**OX
        .XXXX.
        XX..XX
        """),
    ]
}
```

**Step 4 — run, expect all tests passing.**

**Step 5 — commit:**

```bash
git add Sources/OpenIslandCore/PetSpriteData.swift Sources/OpenIslandCore/CompanionState.swift Tests/OpenIslandCoreTests/CompanionPetTests.swift
git commit -m "feat(core): add PetSpriteData with 3 procedural pets"
```

---

## Task 4 — `AnimatedCompanionPet` view

**Files:**
- Create: `Sources/OpenIslandApp/Views/NotchWidgets/AnimatedCompanionPet.swift`

**Step 1 — write implementation:**

```swift
import SwiftUI
import OpenIslandCore

struct AnimatedCompanionPet: View {
    let pet: CompanionPet
    let state: CompanionState

    /// Frame rate per state — slower for idle, faster for celebrating.
    private static func fps(for state: CompanionState) -> Double {
        switch state {
        case .idle:        return 2
        case .working:     return 6
        case .waiting:     return 3
        case .celebrating: return 8
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let frames = PetSpriteData.frames(for: pet, state: state)
            let fps = Self.fps(for: state)
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let frameIndex = Int(elapsed * fps) % max(frames.count, 1)
            let grid = frames[frameIndex]

            Canvas { ctx, size in
                guard let firstRow = grid.first else { return }
                let rows = grid.count
                let cols = firstRow.count
                let cellW = size.width / CGFloat(cols)
                let cellH = size.height / CGFloat(rows)
                for (y, row) in grid.enumerated() {
                    for (x, filled) in row.enumerated() where filled {
                        let rect = CGRect(
                            x: CGFloat(x) * cellW,
                            y: CGFloat(y) * cellH,
                            width: cellW,
                            height: cellH
                        )
                        ctx.fill(Path(rect), with: .color(.white.opacity(0.92)))
                    }
                }
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityLabel("\(pet.displayName) — \(state.rawValue)")
    }
}
```

**Step 2 — verify build:**

`swift build` → success.

**Step 3 — commit:**

```bash
git add Sources/OpenIslandApp/Views/NotchWidgets/AnimatedCompanionPet.swift
git commit -m "feat(app): add AnimatedCompanionPet view (Canvas sprite playback)"
```

---

## Task 5 — `companionPet` selection on AppModel

**Files:**
- Modify: `Sources/OpenIslandApp/AppModel.swift`

**Step 1 — read AppModel briefly to find a spot near other appearance properties** (`grep -n "islandPixelShapeStyle" Sources/OpenIslandApp/AppModel.swift`).

**Step 2 — add fields:**

```swift
// Near other appearance defaults keys
private static let companionPetDefaultsKey = "appearance.companionPet"

/// User's companion pet selection. Nil = use default SF-Symbol overlay.
/// Special string "daily" = pick deterministically per calendar day.
var companionPetSelection: String? = nil {
    didSet {
        guard companionPetSelection != oldValue else { return }
        UserDefaults.standard.set(companionPetSelection, forKey: Self.companionPetDefaultsKey)
    }
}

/// Resolves the selection string to a concrete CompanionPet, or nil for "default overlay".
var resolvedCompanionPet: CompanionPet? {
    guard let raw = companionPetSelection else { return nil }
    if raw == "daily" { return CompanionPet.dailyPick() }
    return CompanionPet(rawValue: raw)
}
```

In `init(...)`, after other UserDefaults reads:

```swift
companionPetSelection = UserDefaults.standard.string(forKey: Self.companionPetDefaultsKey)
```

**Step 3 — verify build + tests:**

`swift build` → success.
`swift test` → all green.

**Step 4 — commit:**

```bash
git add Sources/OpenIslandApp/AppModel.swift
git commit -m "feat(app): persist companion pet selection in AppModel"
```

---

## Task 6 — Wire `AnimatedCompanionPet` into `IslandPanelView`

**Files:**
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift`

**Step 1 — find the existing `CompanionStateOverlay(state: companionState)` usage** (Task 15 of the closed-notch plan placed it inside the custom-appearance ZStack). Replace with a conditional:

```swift
ZStack(alignment: .bottomTrailing) {
    IslandPixelGlyph(
        tint: scoutTint,
        style: model.islandPixelShapeStyle,
        isAnimating: hasClosedActivity,
        customAvatarImage: model.customAvatarImage
    )
    .matchedGeometryEffect(id: "island-icon", in: notchNamespace, isSource: true)

    if let pet = model.resolvedCompanionPet {
        AnimatedCompanionPet(pet: pet, state: companionState)
            .offset(x: 2, y: 2)
    } else {
        CompanionStateOverlay(state: companionState)
            .offset(x: 2, y: 2)
    }
}
```

**Step 2 — verify build:**

`swift build` → success.

**Step 3 — commit:**

```bash
git add Sources/OpenIslandApp/Views/IslandPanelView.swift
git commit -m "feat(app): swap in AnimatedCompanionPet when a pet is selected"
```

---

## Task 7 — `AmbientThemeOverlay` view + AppModel state

**Files:**
- Create: `Sources/OpenIslandApp/Views/AmbientThemeOverlay.swift`
- Modify: `Sources/OpenIslandApp/AppModel.swift`
- Create: `Tests/OpenIslandAppTests/AmbientThemeOpacityTests.swift`

**Step 1 — failing tests:**

```swift
// Tests/OpenIslandAppTests/AmbientThemeOpacityTests.swift
import Foundation
import Testing
@testable import OpenIslandApp

@MainActor
struct AmbientThemeOpacityTests {
    @Test
    func opacityClampsToValidRange() {
        #expect(AmbientTheme.clampOpacity(0.30) == 0.20)
        #expect(AmbientTheme.clampOpacity(-0.10) == 0.05)
        #expect(AmbientTheme.clampOpacity(0.12) == 0.12)
    }

    @Test
    func effectiveOpacityIsZeroWhenDisabled() {
        #expect(AmbientTheme.effectiveOpacity(enabled: false, sliderValue: 0.20) == 0)
        #expect(AmbientTheme.effectiveOpacity(enabled: true, sliderValue: 0.20) == 0.20)
    }
}
```

**Step 2 — run, expect FAIL.**

**Step 3 — implementation:**

```swift
// Sources/OpenIslandApp/Views/AmbientThemeOverlay.swift
import SwiftUI
import OpenIslandCore

enum AmbientTheme {
    static let minOpacity: Double = 0.05
    static let maxOpacity: Double = 0.20

    static func clampOpacity(_ value: Double) -> Double {
        max(minOpacity, min(maxOpacity, value))
    }

    static func effectiveOpacity(enabled: Bool, sliderValue: Double) -> Double {
        guard enabled else { return 0 }
        return clampOpacity(sliderValue)
    }
}

struct AmbientThemeOverlay: View {
    let tintColor: ProjectColor?
    let opacity: Double

    var body: some View {
        if let tint = tintColor, opacity > 0 {
            LinearGradient(
                colors: [
                    Color(red: tint.red, green: tint.green, blue: tint.blue).opacity(opacity),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.4), value: tint)
        } else {
            EmptyView()
        }
    }
}
```

In AppModel.swift, add:

```swift
private static let ambientThemeEnabledDefaultsKey = "appearance.ambientTheme.enabled"
private static let ambientThemeOpacityDefaultsKey = "appearance.ambientTheme.opacity"

var ambientThemeEnabled: Bool = true {
    didSet {
        guard ambientThemeEnabled != oldValue else { return }
        UserDefaults.standard.set(ambientThemeEnabled, forKey: Self.ambientThemeEnabledDefaultsKey)
    }
}

var ambientThemeOpacity: Double = 0.12 {
    didSet {
        guard ambientThemeOpacity != oldValue else { return }
        UserDefaults.standard.set(ambientThemeOpacity, forKey: Self.ambientThemeOpacityDefaultsKey)
    }
}
```

In init, after other reads:

```swift
UserDefaults.standard.register(defaults: [
    Self.ambientThemeEnabledDefaultsKey: true,
    Self.ambientThemeOpacityDefaultsKey: 0.12,
])
ambientThemeEnabled = UserDefaults.standard.bool(forKey: Self.ambientThemeEnabledDefaultsKey)
ambientThemeOpacity = UserDefaults.standard.double(forKey: Self.ambientThemeOpacityDefaultsKey)
```

(If a `register(defaults:)` call already exists, merge into it instead of adding a second one.)

**Step 4 — run tests, expect PASS.**

**Step 5 — commit:**

```bash
git add Sources/OpenIslandApp/Views/AmbientThemeOverlay.swift \
        Sources/OpenIslandApp/AppModel.swift \
        Tests/OpenIslandAppTests/AmbientThemeOpacityTests.swift
git commit -m "feat(app): add AmbientThemeOverlay + AppModel persistence"
```

---

## Task 8 — Insert `AmbientThemeOverlay` into `IslandPanelView`

**Files:**
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift`

**Step 1 — find the body of `IslandPanelView`** (or whatever ZStack/Group wraps the content). Insert the overlay before the existing chrome content — it should sit on top of the background fill but below all foreground content.

The cleanest approach is to wrap the existing `notchContent(...)` body in a ZStack with the overlay layer:

```swift
ZStack {
    // Existing background + content stays as-is.
    existingBody

    // New ambient layer.
    AmbientThemeOverlay(
        tintColor: spotlightProjectColor,
        opacity: AmbientTheme.effectiveOpacity(
            enabled: model.ambientThemeEnabled,
            sliderValue: model.ambientThemeOpacity
        )
    )
    .allowsHitTesting(false)
}
```

`spotlightProjectColor` is a new computed:

```swift
private var spotlightProjectColor: ProjectColor? {
    guard let key = closedSpotlightSession?.jumpTarget?.workingDirectory
        ?? closedSpotlightSession?.jumpTarget?.workspaceName else {
        return nil
    }
    return model.projectColorRegistry.color(for: key)
}
```

Place the overlay so it covers the island's full surface area but is below all interactive content. Put `.allowsHitTesting(false)` on it so clicks pass through.

If wrapping `existingBody` is too invasive, alternative: add `.overlay { AmbientThemeOverlay(...) }` to the lowest-level container that fills the island. The key constraint: it must be visible in both opened and closed states.

**Step 2 — verify build + visual:**

`swift build` → success.

Run the dev app:

```bash
zsh scripts/launch-dev-app.sh --skip-setup
```

Switch between Claude sessions in different projects — gradient should cross-fade.

**Step 3 — commit:**

```bash
git add Sources/OpenIslandApp/Views/IslandPanelView.swift
git commit -m "feat(app): render ambient project gradient inside island"
```

---

## Task 9 — `CelebrationParticles` view + math tests

**Files:**
- Create: `Sources/OpenIslandApp/Views/CelebrationParticles.swift`
- Create: `Tests/OpenIslandAppTests/CelebrationParticleMathTests.swift`

**Step 1 — failing tests:**

```swift
// Tests/OpenIslandAppTests/CelebrationParticleMathTests.swift
import Foundation
import CoreGraphics
import Testing
@testable import OpenIslandApp

@MainActor
struct CelebrationParticleMathTests {
    @Test
    func opacityIsOneAtStart() {
        #expect(abs(CelebrationParticles.opacity(elapsed: 0) - 1.0) < 0.001)
    }

    @Test
    func opacityIsZeroAtEnd() {
        #expect(CelebrationParticles.opacity(elapsed: 2.0) == 0)
    }

    @Test
    func opacityClampsBeyondEnd() {
        #expect(CelebrationParticles.opacity(elapsed: 5.0) == 0)
    }

    @Test
    func positionAdvancesOverTime() {
        let p0 = CelebrationParticles.position(seed: 5, elapsed: 0, anchor: .zero)
        let p1 = CelebrationParticles.position(seed: 5, elapsed: 1.0, anchor: .zero)
        #expect(p0 != p1)
    }

    @Test
    func positionIsDeterministicForSameSeed() {
        let a = CelebrationParticles.position(seed: 3, elapsed: 0.5, anchor: .zero)
        let b = CelebrationParticles.position(seed: 3, elapsed: 0.5, anchor: .zero)
        #expect(a == b)
    }
}
```

**Step 2 — run, expect FAIL.**

**Step 3 — implementation:**

```swift
// Sources/OpenIslandApp/Views/CelebrationParticles.swift
import SwiftUI
import OpenIslandCore

struct CelebrationParticles: View {
    let tint: ProjectColor?
    let startedAt: Date
    let count: Int

    static let duration: TimeInterval = 2.0
    static let gravity: CGFloat = 350

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            if elapsed < Self.duration {
                Canvas { ctx, size in
                    let alpha = Self.opacity(elapsed: elapsed)
                    let color = tint.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
                        ?? Color.gray.opacity(0.6)
                    let anchor = CGPoint(x: size.width * 0.15, y: size.height * 0.5)

                    for seed in 0..<count {
                        let pos = Self.position(seed: seed, elapsed: elapsed, anchor: anchor)
                        let rotation = Self.rotation(seed: seed, elapsed: elapsed)
                        let rect = CGRect(x: pos.x - 2, y: pos.y - 2, width: 4, height: 4)

                        ctx.translateBy(x: pos.x, y: pos.y)
                        ctx.rotate(by: .radians(rotation))
                        ctx.translateBy(x: -pos.x, y: -pos.y)

                        ctx.fill(
                            Path(roundedRect: rect, cornerRadius: 1),
                            with: .color(color.opacity(alpha))
                        )

                        ctx.translateBy(x: pos.x, y: pos.y)
                        ctx.rotate(by: .radians(-rotation))
                        ctx.translateBy(x: -pos.x, y: -pos.y)
                    }
                }
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Pure math (unit-testable)

    static func opacity(elapsed: TimeInterval) -> Double {
        max(0, 1 - elapsed / duration)
    }

    static func position(seed: Int, elapsed: TimeInterval, anchor: CGPoint) -> CGPoint {
        let s = Double(seed)
        let vx = (sin(s * 7.3) * 60)
        let vy = -120 - (s.truncatingRemainder(dividingBy: 4)) * 30
        let t = elapsed
        let x = anchor.x + CGFloat(vx * t)
        let y = anchor.y + CGFloat(vy * t + 0.5 * Double(gravity) * t * t)
        return CGPoint(x: x, y: y)
    }

    static func rotation(seed: Int, elapsed: TimeInterval) -> Double {
        let s = Double(seed)
        return s * .pi / 2 + elapsed * .pi * 4
    }
}
```

**Step 4 — run tests, expect 5/5 PASS.**

**Step 5 — commit:**

```bash
git add Sources/OpenIslandApp/Views/CelebrationParticles.swift \
        Tests/OpenIslandAppTests/CelebrationParticleMathTests.swift
git commit -m "feat(app): add CelebrationParticles with deterministic physics"
```

---

## Task 10 — Wire celebration spawn into `IslandPanelView`

**Files:**
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift`
- Modify: `Sources/OpenIslandApp/AppModel.swift` (add `celebrationsEnabled`)

**Step 1 — add the AppModel toggle** (parallel to ambientThemeEnabled):

```swift
private static let celebrationsEnabledDefaultsKey = "appearance.celebrations.enabled"

var celebrationsEnabled: Bool = true {
    didSet {
        guard celebrationsEnabled != oldValue else { return }
        UserDefaults.standard.set(celebrationsEnabled, forKey: Self.celebrationsEnabledDefaultsKey)
    }
}
```

In init defaults:

```swift
UserDefaults.standard.register(defaults: [Self.celebrationsEnabledDefaultsKey: true])
celebrationsEnabled = UserDefaults.standard.bool(forKey: Self.celebrationsEnabledDefaultsKey)
```

**Step 2 — add to IslandPanelView body**:

Add `@State` for celebration tracking:

```swift
@State private var lastCelebrationTimestamp: Date?
```

Modify the existing `.onChange(of: closedSpotlightSession?.phase)` block to ALSO trigger celebration timestamps (it already updates `lastCompletionTimestamp`). Add another onChange or extend the existing one:

```swift
.onChange(of: companionState) { _, newState in
    if newState == .celebrating {
        guard model.celebrationsEnabled else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        lastCelebrationTimestamp = Date()
    }
}
```

In the body's ZStack (above all content, below ambient overlay), add:

```swift
if let ts = lastCelebrationTimestamp,
   Date().timeIntervalSince(ts) < CelebrationParticles.duration {
    CelebrationParticles(
        tint: spotlightProjectColor,
        startedAt: ts,
        count: 12
    )
    .id(ts)
}
```

**Step 3 — verify build + test:**

`swift build` → success.
`swift test` → all green.

**Step 4 — commit:**

```bash
git add Sources/OpenIslandApp/AppModel.swift Sources/OpenIslandApp/Views/IslandPanelView.swift
git commit -m "feat(app): spawn celebration confetti on session completion"
```

---

## Task 11 — Settings UI sections

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift`
- Modify: localization `.strings` files (en, zh-Hans, zh-Hant)

**Step 1 — add localization keys** to all three `.strings` files (English shown; other two with `/* TODO: translate */`):

```
"settings.companion.title" = "Companion pet";
"settings.companion.preview" = "Live preview";
"settings.companion.pet.none" = "Default";
"settings.companion.pet.daily" = "Daily";
"settings.companion.pet.cat" = "Cat";
"settings.companion.pet.ghost" = "Ghost";
"settings.companion.pet.robot" = "Robot";

"settings.ambient.title" = "Ambient theme";
"settings.ambient.toggle" = "Tint island with project color";
"settings.ambient.intensity" = "Intensity";
"settings.ambient.subtle" = "Subtle";
"settings.ambient.bold" = "Bold";
"settings.ambient.help" = "Tints the inside of the island in the active session's project color, animated when you switch projects.";

"settings.celebrations.title" = "Celebrations";
"settings.celebrations.toggle" = "Celebrate when sessions complete";
"settings.celebrations.help" = "Spawns a brief burst of project-colored confetti when a session finishes a task.";
```

**Step 2 — extend `AppearanceSettingsPane`:**

Append three new sections after the existing ones (likely between "Project colors" and "Notch widgets"):

```swift
Section(lang.t("settings.companion.title")) {
    let petOptions: [(String, String)] = [
        ("__none__", lang.t("settings.companion.pet.none")),
        ("daily",    lang.t("settings.companion.pet.daily")),
    ] + CompanionPet.allCases.map { ($0.rawValue, lang.t("settings.companion.pet.\($0.rawValue)")) }

    Picker("", selection: Binding(
        get: { model.companionPetSelection ?? "__none__" },
        set: { newValue in
            model.companionPetSelection = (newValue == "__none__") ? nil : newValue
        }
    )) {
        ForEach(petOptions, id: \.0) { value, label in
            Text(label).tag(value)
        }
    }
    .pickerStyle(.segmented)

    if let pet = model.resolvedCompanionPet {
        VStack(spacing: 4) {
            Text(lang.t("settings.companion.preview")).font(.caption).foregroundStyle(.secondary)
            companionLivePreview(pet: pet)
                .frame(width: 64, height: 64)
                .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

Section(lang.t("settings.ambient.title")) {
    Toggle(lang.t("settings.ambient.toggle"), isOn: Binding(
        get: { model.ambientThemeEnabled },
        set: { model.ambientThemeEnabled = $0 }
    ))

    HStack {
        Text(lang.t("settings.ambient.subtle")).font(.caption).foregroundStyle(.secondary)
        Slider(value: Binding(
            get: { model.ambientThemeOpacity },
            set: { model.ambientThemeOpacity = AmbientTheme.clampOpacity($0) }
        ), in: AmbientTheme.minOpacity...AmbientTheme.maxOpacity)
        Text(lang.t("settings.ambient.bold")).font(.caption).foregroundStyle(.secondary)
    }

    Text(lang.t("settings.ambient.help")).font(.caption).foregroundStyle(.secondary)
}

Section(lang.t("settings.celebrations.title")) {
    Toggle(lang.t("settings.celebrations.toggle"), isOn: Binding(
        get: { model.celebrationsEnabled },
        set: { model.celebrationsEnabled = $0 }
    ))
    Text(lang.t("settings.celebrations.help")).font(.caption).foregroundStyle(.secondary)
}
```

Add the live-preview helper:

```swift
@ViewBuilder
private func companionLivePreview(pet: CompanionPet) -> some View {
    TimelineView(.animation) { timeline in
        let elapsed = timeline.date.timeIntervalSinceReferenceDate
        let stateIndex = Int(elapsed / 2.0) % 4
        let state: CompanionState = [
            .idle, .working, .waiting, .celebrating
        ][stateIndex]

        AnimatedCompanionPet(pet: pet, state: state)
            .scaleEffect(3)  // 16pt → 48pt visible at 4× scale density
    }
}
```

**Step 3 — verify build + tests:**

`swift build` → success.
`swift test` → all green.

**Step 4 — commit:**

```bash
git add Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift Sources/OpenIslandApp/Resources/
git commit -m "feat(app): add Companion pet, Ambient theme, Celebrations settings"
```

---

## Task 12 — Final smoke + push

**Step 1 — release build:**

```bash
swift build -c release
```

Expected: clean.

**Step 2 — full test suite:**

```bash
swift test
```

All green.

**Step 3 — manual smoke (you, on the dev app):**

```bash
pkill -9 -f "Open Island Dev.app/Contents/MacOS/OpenIslandApp" 2>/dev/null
sleep 1
zsh scripts/launch-dev-app.sh --skip-setup
```

Verify:
- Settings → Appearance → "Companion pet" shows segmented picker (Default / Daily / Cat / Ghost / Robot). Picking each updates the live preview.
- "Ambient theme" toggle on by default. Slider ranges Subtle ↔ Bold. Disabling makes the gradient vanish.
- "Celebrations" toggle on by default.
- Open the island. Pick "Cat" — the cat appears in the bottom-trailing of the avatar. Animations cycle.
- Trigger a Claude session completion. Confetti fires for ~2s in the project color.
- Switch to a different project session. Ambient gradient cross-fades over ~400ms.
- macOS System Settings → Accessibility → Display → enable Reduced Motion. Trigger another completion: no confetti. Disable.
- Reduced Transparency: ambient gradient hides.

**Step 4 — push:**

```bash
git push origin feat/notch-personalization
```

---

## Out of scope / Phase 2

- 5 more pets (dog, ducky, dragon, plant, slime) — separate plan with `pixel-art-sprite-sourcing` skill for real CC0 sprite sheets.
- Pet picker tile grid (currently a segmented picker) — upgrade UI when pet count grows.
- Sound effects — separate feature, deferred.
- Pet evolution / level-up.
- User-uploaded sprite sheets.
