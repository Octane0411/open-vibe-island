import SwiftUI

// MARK: - Open Island icon (left side of closed notch)

struct OpenIslandIcon: View {
    let size: CGFloat
    var isAnimating: Bool = false
    var tint: Color = .mint

    var body: some View {
        OpenIslandBrandMark(
            size: size,
            tint: tint,
            isAnimating: isAnimating,
            style: .duotone
        )
    }
}

// MARK: - Attention indicator (permission/question dot)

struct AttentionIndicator: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: size * 0.75, weight: .bold))
            .foregroundStyle(color)
    }
}

// MARK: - Closed count badge (right side of closed notch)

struct ClosedCountBadge: View {
    let liveCount: Int
    let tint: Color

    var body: some View {
        Text("\(liveCount)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(red: 0.14, green: 0.14, blue: 0.15), in: Capsule())
    }
}
