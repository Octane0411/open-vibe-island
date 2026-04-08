import SwiftUI

struct IslandCompactButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint == .secondary ? .white.opacity(0.7) : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (tint == .secondary ? Color.white.opacity(0.08) : tint.opacity(0.15)),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct IslandWideButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case warning
        case danger
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(backgroundColor(configuration.isPressed), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary, .warning, .danger:
            return .white
        case .secondary:
            return .white.opacity(0.88)
        }
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        let pressedFactor: Double = isPressed ? 0.78 : 1.0
        switch kind {
        case .primary:
            return Color(red: 0.26, green: 0.45, blue: 0.86).opacity(pressedFactor)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.12 : 0.16)
        case .warning:
            return Color(red: 0.85, green: 0.55, blue: 0.15).opacity(pressedFactor)
        case .danger:
            return Color(red: 0.82, green: 0.22, blue: 0.22).opacity(pressedFactor)
        }
    }
}
