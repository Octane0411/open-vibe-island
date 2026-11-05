import AppKit
import Carbon.HIToolbox

/// Register only the explicit toggle globally. Action keys are scoped to the
/// focused island panel, so typing in a terminal or Settings stays untouched.
@MainActor
final class IslandShortcutController {
    private weak var model: AppModel?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var localMonitor: Any?

    init(model: AppModel) { self.model = model }

    func configure() {
        stop()
        guard let model, model.keyboardShortcutsEnabled else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == 0x4f49534c, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let controller = Unmanaged<IslandShortcutController>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in controller.model?.toggleOverlay() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { model.keyboardShortcutError = status; return }
        let modifiers = model.islandToggleShortcut == .commandShiftI ? UInt32(cmdKey | shiftKey) : UInt32(controlKey | optionKey)
        let registerStatus = RegisterEventHotKey(UInt32(kVK_ANSI_I), modifiers,
            EventHotKeyID(signature: 0x4f49534c, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        model.keyboardShortcutError = registerStatus == noErr ? nil : registerStatus
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleLocal(event) == true ? nil : event
            }
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        hotKey = nil
        handler = nil
        localMonitor = nil
        model?.keyboardShortcutError = nil
    }

    private func handleLocal(_ event: NSEvent) -> Bool {
        guard let model, model.notchStatus == .opened,
              model.overlay.overlayPanelController.isKeyPanel else { return false }
        // Leave field editing, Markdown selection and multiline answers alone.
        if NSApp.keyWindow?.firstResponder is NSTextView { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) { model.notchClose(); return true }
        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Return) {
            if let session = model.focusedSession { model.jumpToSession(session) }
            return true
        }
        guard modifiers == .command else { return false }
        switch event.keyCode {
        case UInt16(kVK_DownArrow): model.moveIslandSelection(by: 1)
        case UInt16(kVK_UpArrow): model.moveIslandSelection(by: -1)
        case UInt16(kVK_ANSI_Y), UInt16(kVK_ANSI_N):
            guard let session = model.activeIslandCardSession ?? model.focusedSession,
                  session.phase == .waitingForApproval, session.permissionRequest != nil else { return false }
            model.approvePermission(for: session.id, approved: event.keyCode == UInt16(kVK_ANSI_Y))
        default: return false
        }
        return true
    }
}
