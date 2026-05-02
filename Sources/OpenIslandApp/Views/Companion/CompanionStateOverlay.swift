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

    private func animateRotation() {
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }

    private func animatePulse() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.4
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
