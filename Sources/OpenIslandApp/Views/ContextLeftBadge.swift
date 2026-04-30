import SwiftUI
import OpenIslandCore

struct ContextLeftBadge: View {
    let usage: ContextUsage

    static let barWidth: CGFloat = 18
    static let barHeight: CGFloat = 4

    enum FillColor: Equatable {
        case green, yellow, orange, red
    }

    var body: some View {
        if usage.percentLeft < 1 {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.04), in: Capsule())
                .accessibilityLabel("\(Int(usage.percentLeft.rounded()))% context left")
                .allowsHitTesting(false)
        } else {
            HStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: Self.barWidth, height: Self.barHeight)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(swiftUIColor(for: fillColor))
                        .frame(width: fillWidth, height: Self.barHeight)
                }
                Text("\(Int(usage.percentLeft.rounded()))%")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.04), in: Capsule())
            .accessibilityLabel("\(Int(usage.percentLeft.rounded()))% context left")
            .allowsHitTesting(false)
        }
    }

    var fillWidth: CGFloat {
        let used = max(0, min(100, usage.percentUsed))
        let raw = Self.barWidth * CGFloat(used / 100)
        return used > 0 ? max(2, raw) : 0
    }

    var fillColor: FillColor {
        let left = usage.percentLeft
        if left > 50 { return .green }
        if left > 20 { return .yellow }
        if left > 10 { return .orange }
        return .red
    }

    private func swiftUIColor(for fill: FillColor) -> Color {
        switch fill {
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        }
    }
}
