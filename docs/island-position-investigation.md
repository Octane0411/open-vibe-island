# Island Position Investigation

Reviewed on 2026-04-02 in worktree `../agent-deck-island-investigate` on branch `investigate/island-position`.

## Question

Why does the current open-source island feel "off" compared with the official Agent Deck behavior on a MacBook with a built-in notch?

## Short Answer

The current overlay is not actually modeled as a notch surface.

It is a single large `NSPanel` that:

- chooses `NSScreen.main` instead of preferring the built-in notched display
- positions itself from `visibleFrame` instead of the full screen frame and safe-area geometry
- always renders the expanded detail panel instead of a compact notch state with a fallback top bar on non-notch displays

That combination makes it behave like a generic top-center floating window, not a notch-native island.

## Evidence

### 1. The code picks the wrong screen

Current positioning logic in `Sources/AgentDeckApp/OverlayPanelController.swift`:

```swift
let screen = NSScreen.main ?? NSScreen.screens.first
```

That means the overlay follows the screen of the key window, not the screen that actually has the built-in notch.

On the current machine, a quick AppKit probe returned:

```text
screen 0: DELL P2723QE
  frame={{0, 0}, {1920, 1080}}
  visibleFrame={{0, 85}, {1920, 964}}
  safeAreaInsets=top:0.0 left:0.0 bottom:0.0 right:0.0

screen 1: Built-in Retina Display
  frame={{1920, 78}, {1312, 848}}
  visibleFrame={{1920, 78}, {1312, 824}}
  safeAreaInsets=top:24.0 left:0.0 bottom:0.0 right:0.0
  auxiliaryTopLeftArea={{1920, 902}, {586, 24}}
  auxiliaryTopRightArea={{2646, 902}, {586, 24}}
```

So this machine clearly has both:

- an external display with no notch
- a built-in display with notch-specific safe-area geometry

If the control-center window is key on the external display, the current overlay logic will happily anchor the island there.

### 2. The code positions relative to `visibleFrame`, not the notch

Current positioning logic:

```swift
let visibleFrame = screen.visibleFrame
let frame = NSRect(
    x: visibleFrame.midX - (size.width / 2),
    y: visibleFrame.maxY - size.height - 18,
    width: size.width,
    height: size.height
)
```

For the built-in display on this machine:

- `screen.frame.maxY = 926`
- `screen.visibleFrame.maxY = 902`
- top safe-area inset = `24`

With the current overlay size `520x256`, the computed top edge becomes:

```text
panelTop = visibleFrame.maxY - 18 = 884
distanceFromPhysicalTop = 926 - 884 = 42
```

So the panel starts `42pt` below the physical top of the built-in display. It can never visually merge with the notch area because it is already pushed below the menu-bar/safe-area boundary before any content is drawn.

### 3. The current surface is the wrong shape

The current panel is created as a single expanded surface:

```swift
contentRect: NSRect(x: 0, y: 0, width: 520, height: 256)
```

The official product behavior is different:

- Commercial reference behavior says: on Macs with a built-in notch, the panel "sits in the notch area"
- the same FAQ says external or non-notch displays should use "a compact floating bar at the top center of the screen"
- the website demo uses a compact notch state first, then expands into richer approval / question / jump states

The repository product docs already align with that direction:

- `docs/product.md` says the app should render "live session state in a notch or floating top bar"
- `docs/product.md` lists an "External-display fallback bar for machines without a notch"
- `docs/notchi-integration.md` calls out "compact notch view" plus expanded detail

The current AppKit implementation does not make that distinction. It always shows the large detail panel.

## Root Cause

This is not one bug. It is three layers of mismatch:

1. screen selection bug
2. coordinate-system bug
3. UI-surface modeling gap

That is why the current island feels fundamentally different from the official app instead of just slightly misplaced.

## Recommended Fix Order

### 1. Prefer the built-in notched display when present

Selection should prefer a screen with notch-related geometry such as:

- `safeAreaInsets.top > 0`
- non-empty `auxiliaryTopLeftArea`
- non-empty `auxiliaryTopRightArea`

Only fall back to `NSScreen.main` or the first screen when no notched display is available.

### 2. Separate notch mode from fallback top-bar mode

The overlay should have two placement modes:

- notch mode: anchored from `screen.frame` and safe-area geometry on the built-in display
- fallback mode: anchored from `visibleFrame` at the top center on non-notch displays

Using a single `visibleFrame` formula for both cases is the core placement mistake.

### 3. Add a compact idle surface

The built-in notch path should default to a compact island-sized surface and only expand for richer states. The current always-expanded `520x256` panel is too large to read as an ambient notch presence.

## What To Change Next

The next implementation round should focus on one coherent slice:

1. add a dedicated overlay screen-selection policy
2. add notch-aware placement math using `NSScreen.safeAreaInsets`
3. split compact and expanded overlay sizes so the default state can live at the notch without feeling like a floating modal

Until those three pieces land together, small coordinate tweaks alone will not make the island feel correct.
