import SwiftUI

struct MusicHoverButton: View {
    var icon: String
    var iconSize: CGFloat = 60
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: iconSize, height: iconSize)
                .overlay {
                    Capsule()
                        .fill(isHovering ? Color.gray.opacity(0.3) : .clear)
                        .frame(width: iconSize * 1.75, height: iconSize * 1.75)
                        .overlay {
                            Image(systemName: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: iconSize, height: iconSize)
                                .contentTransition(.symbolEffect)
                        }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) { isHovering = hovering }
        }
    }
}
