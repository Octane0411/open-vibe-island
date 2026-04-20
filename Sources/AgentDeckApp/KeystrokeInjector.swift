import Foundation

/// Invoked once per retry iteration in the Warp precision jump cycling
/// loop. The protocol name is historical — earlier implementations posted
/// a synthetic Cmd+Shift+] keystroke, which is Warp's bound shortcut for
/// "Switch to Next Tab". The current production implementation takes a
/// more reliable path (see DefaultKeystrokeInjector below) but the
/// protocol contract is the same: "advance Warp by one tab".
public protocol KeystrokeInjector {
    func sendCmdShiftRightBracket()
}

/// Production implementation that advances Warp to its next tab by
/// clicking the `Tab ▸ Switch to Next Tab` menu item via the macOS
/// Accessibility API, not by synthesizing a Cmd+Shift+] key event.
///
/// Why not synthesize the keystroke? Two earlier attempts failed, both
/// because synthetic key events and physical key events are not
/// interchangeable on macOS:
///
/// 1. `CGEventPost(.cghidEventTap, ...)` silently produced NSBeep
///    without cycling tabs. Accessibility/HID filtering drops untrusted
///    synthetic events before they reach any app's keyEquivalent lookup.
/// 2. `tell application "System Events" to keystroke "]" using
///    {command down, shift down}` cycled exactly one tab on the very
///    first invocation after each fresh Accessibility grant, then
///    beeped on every subsequent call. The Apple Event boundary plus
///    the asynchronous WindowServer "frontmost app ↔ key window"
///    handoff creates a state where System Events' synthetic event
///    reaches Warp's process queue but does not walk the normal
///    NSWindow → responder chain → menu key-equivalent path, so the
///    `Next Tab` action never fires.
///
/// Clicking the menu item via AX side-steps all of that. The action
/// bound to the menu item runs directly, regardless of which Warp
/// window is key, which view is first responder, whether a TUI app
/// (claude) is running inside the focused pane, or whether modifier-key
/// state from a previous synthetic event is still "stuck". It is the
/// same dispatch path that fires when a user physically clicks the menu
/// with their mouse.
///
/// Menu path validated empirically against Warp Stable (April 2026):
///   menu bar → menu bar item "Tab" → menu "Tab" → menu item "Switch to Next Tab"
///
/// If a future Warp release renames the menu item or moves it to a
/// different submenu, this call will throw an AppleScript error which
/// is logged via NSLog; the bounded retry loop in
/// `TerminalJumpService.jumpToWarpPane` then caps out and falls back to
/// the "Activated Warp but could not confirm precision focus" message.
///
/// Permission: The Accessibility permission the user grants to the
/// Agent Deck host app authorizes `click menu item` on other
/// processes. Automation permission for `System Events` is also
/// required on the first call; macOS presents its standard consent
/// prompt.
public struct DefaultKeystrokeInjector: KeystrokeInjector {
    public init() {}

    public func sendCmdShiftRightBracket() {
        let source = #"""
        tell application id "dev.warp.Warp-Stable" to activate
        delay 0.08
        tell application "System Events"
            tell process "Warp"
                click menu item "Switch to Next Tab" of menu "Tab" of menu bar item "Tab" of menu bar 1
            end tell
        end tell
        """#
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            NSLog("[AgentDeck] Warp tab advance: NSAppleScript compilation returned nil")
            return
        }
        script.executeAndReturnError(&error)
        if let error {
            NSLog("[AgentDeck] Warp tab advance failed: %@", String(describing: error))
        }
    }
}
