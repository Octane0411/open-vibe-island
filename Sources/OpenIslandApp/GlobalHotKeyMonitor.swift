import Carbon
import AppKit

/// Module-level callback storage for the C-convention Carbon event handler.
@MainActor private var _hotKeyCallback: (() -> Void)?

/// Registers a system-wide hotkey using Carbon `RegisterEventHotKey`.
/// Fires globally regardless of which app has focus and does NOT require
/// Accessibility permissions.
@MainActor
final class GlobalHotKeyMonitor {
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandlerRef: EventHandlerRef?
    let modifiers: NSEvent.ModifierFlags
    let keyCode: UInt16

    init(modifiers: NSEvent.ModifierFlags, keyCode: UInt16, callback: @escaping () -> Void) {
        self.modifiers = modifiers.intersection(kRealModifiers)
        self.keyCode = keyCode
        _hotKeyCallback = callback
        setupMonitor()
    }

    private func setupMonitor() {
        let carbonMods = nsModifiersToCarbon(modifiers)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F50494C), id: UInt32(1)) // 'OPIL'
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async { _hotKeyCallback?() }
                return noErr
            },
            1, &eventType, nil, &eventHandlerRef
        )
        RegisterEventHotKey(
            UInt32(keyCode), carbonMods, hotKeyID,
            GetApplicationEventTarget(), OptionBits(0), &hotKeyRef
        )
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
    }
}

private func nsModifiersToCarbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var carbon: UInt32 = 0
    if flags.contains(.command) { carbon |= UInt32(cmdKey) }
    if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
    if flags.contains(.option)  { carbon |= UInt32(optionKey) }
    if flags.contains(.control) { carbon |= UInt32(controlKey) }
    return carbon
}
