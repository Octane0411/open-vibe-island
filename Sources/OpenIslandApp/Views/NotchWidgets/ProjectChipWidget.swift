import SwiftUI
import OpenIslandCore

struct ProjectChipWidget: View {
    let workspaceName: String?
    let workspaceKey: String?
    let registry: ProjectColorRegistry
    let availableWidth: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(swiftUIColor)
                .frame(width: 8, height: 8)

            if let name = workspaceName, availableWidth >= compactThreshold {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: availableWidth, alignment: .trailing)
    }

    private var compactThreshold: CGFloat { 60 }

    private var swiftUIColor: Color {
        guard let key = workspaceKey else {
            return Color.gray.opacity(0.6)
        }
        let c = registry.color(for: key)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}
