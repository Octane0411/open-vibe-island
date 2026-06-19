# Hide In Fullscreen Setting Design

## Context

Open Island currently creates its overlay panel with `.fullScreenAuxiliary` and `.canJoinAllSpaces`, so the island remains visible in fullscreen application Spaces. This is useful for users who want the island everywhere, but it can interfere with fullscreen workflows such as browser interactions.

The app already ships localized strings for `settings.general.hideFullscreen` in English, Simplified Chinese, and Traditional Chinese. The setting is not wired into the model, settings UI, or panel behavior yet.

## Goal

Add a General settings option named `Hide in fullscreen` / `全屏时隐藏` that lets users opt out of showing the island over fullscreen apps.

The setting defaults to off. Existing users and new installs keep the current behavior unless they explicitly enable the option.

## User Behavior

When the option is off, Open Island behaves as it does today: the panel can join all Spaces and can appear over fullscreen apps.

When the option is on, Open Island keeps its normal non-fullscreen top-of-screen behavior but does not join fullscreen application Spaces. The change should apply immediately to the existing panel after the toggle changes, without requiring an app restart.

## Architecture

`AppModel` owns the persisted preference, matching the existing General settings pattern:

- Add a `UserDefaults` key such as `app.hideFullscreen`.
- Register the default value as `false`.
- Expose an observable `hideFullscreen` Boolean.
- Persist changes after initialization.
- Notify the overlay coordinator when the value changes.

`SettingsView` adds a Toggle in General > Behavior using the existing localized key `settings.general.hideFullscreen`.

`OverlayUICoordinator` forwards the preference to `OverlayPanelController`, keeping panel-specific AppKit behavior out of SwiftUI view code.

`OverlayPanelController` centralizes collection behavior construction. It keeps `.canJoinAllSpaces`, `.ignoresCycle`, and `.stationary` in both modes, and includes `.fullScreenAuxiliary` only when `hideFullscreen` is false.

## Data Flow

1. App starts and `AppModel` loads `hideFullscreen` from `UserDefaults`, defaulting to `false`.
2. AppModel configures the overlay coordinator with the current value.
3. When the panel is created, the panel controller applies collection behavior based on the value.
4. When the user changes the Toggle, AppModel persists the new value and asks the overlay controller to reapply collection behavior to any existing panel.

## Edge Cases

If the panel has not been created yet, the preference is stored and applied on creation.

If the user changes the setting while currently in a fullscreen Space, AppKit is responsible for moving or removing the auxiliary panel according to the updated collection behavior. The app does not try to manually detect fullscreen windows.

The feature does not change notification filtering. Existing `suppressFrontmostNotifications` behavior remains separate.

## Testing

Add focused tests for:

- The collection behavior helper includes `.fullScreenAuxiliary` when `hideFullscreen` is false.
- The helper excludes `.fullScreenAuxiliary` when `hideFullscreen` is true.
- `AppModel` default initialization keeps `hideFullscreen` false.

Manual verification should launch the dev app, enable the setting, enter a fullscreen browser window, and confirm the island no longer appears there while still appearing on the normal desktop Space.

## Verification Note

Initial baseline `swift test` in this worktree could not complete because the active developer directory is Command Line Tools, and the test build failed to import Swift's `Testing` module. This is an environment/toolchain issue to resolve before final automated verification.
