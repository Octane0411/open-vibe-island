// Sources/OpenIslandApp/Views/Companion/CompanionStateOverlay.swift
import SwiftUI
import OpenIslandCore

struct CompanionStateOverlay: View {
    let state: CompanionState

    @State private var rotation: Double = 0
    @State private var pulseScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            switch state {
            case .idle:
                glyph("zzz", tint: .white.opacity(0.4))
            case .working:
                glyph("gear", tint: .cyan.opacity(0.85))
                    .rotationEffect(.degrees(rotation))
                    .onAppear { animateRotation() }
            case .waiting:
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulseScale)
                    .onAppear { animatePulse() }
            case .celebrating:
                glyph("sparkles", tint: .yellow)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityLabel(accessibilityText)
    }

    private func glyph(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(tint)
    }

    // Animations follow a reset-before-animate pattern: snap the backing
    // @State to its start value with a transactionless write, then kick off
    // the repeating implicit animation on the next runloop tick. Without the
    // reset, a second onAppear on this view (e.g. when state cycles
    // working → idle → working) finds rotation/pulseScale already at the
    // target value, gets no state delta, and the animation never restarts.
    private func animateRotation() {
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) { rotation = 0 }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    private func animatePulse() {
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) { pulseScale = 1 }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.4
            }
        }
    }

    private var accessibilityText: String {
        let key: String
        switch state {
        case .idle:        key = "island.companion.state.idle"
        case .working:     key = "island.companion.state.working"
        case .waiting:     key = "island.companion.state.waiting"
        case .celebrating: key = "island.companion.state.celebrating"
        }
        return LanguageManager.shared.t(key)
    }
}
