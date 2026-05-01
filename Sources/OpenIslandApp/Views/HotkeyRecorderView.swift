import AppKit
import SwiftUI

// MARK: - Hotkey recorder button (SwiftUI)

struct HotkeyRecorderButton: View {
    @Binding var recordedKey: KeyCombo
    @State private var isRecording = false

    var body: some View {
        HotkeyRecorderNSView(
            isRecording: $isRecording,
            onKeyRecorded: { combo in
                recordedKey = combo
                isRecording = false
            }
        )
        .overlay(
            Text(isRecording ? "Press keys now…" : recordedKey.displayString)
                .foregroundColor(isRecording ? .accentColor : .primary)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
        )
        .frame(height: 28)
    }
}

// MARK: - NSViewRepresentable bridge

private struct HotkeyRecorderNSView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onKeyRecorded: (KeyCombo) -> Void

    func makeNSView(context: Context) -> HotkeyCapturingView {
        let view = HotkeyCapturingView()
        view.onRecordingStarted = {
            DispatchQueue.main.async { isRecording = true }
        }
        view.onKeyRecorded = { combo in
            DispatchQueue.main.async {
                isRecording = false
                onKeyRecorded(combo)
            }
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyCapturingView, context: Context) {
        if !isRecording && nsView.isRecording {
            nsView.cancelRecording()
        }
    }
}

// MARK: - NSView that captures a key combo on click

@MainActor
final class HotkeyCapturingView: NSView {
    var onKeyRecorded: ((KeyCombo) -> Void)?
    var onRecordingStarted: (() -> Void)?
    var isRecording: Bool = false {
        didSet { needsDisplay = true }
    }

    private nonisolated(unsafe) var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    func cancelRecording() {
        isRecording = false
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else { return }
        isRecording = true
        onRecordingStarted?()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.isRecording else { return e }
            let mods = e.modifierFlags.intersection(kRealModifiers)
            guard !mods.isEmpty else { return e }
            let combo = KeyCombo(keyCode: e.keyCode, modifiers: mods)
            self.isRecording = false
            if let m = self.localMonitor { NSEvent.removeMonitor(m); self.localMonitor = nil }
            self.onKeyRecorded?(combo)
            return nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.15)
            : NSColor.controlBackgroundColor
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 4, yRadius: 4
        ).stroke()
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}
