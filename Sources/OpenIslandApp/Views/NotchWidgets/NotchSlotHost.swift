// Sources/OpenIslandApp/Views/NotchWidgets/NotchSlotHost.swift
import SwiftUI
import OpenIslandCore

struct NotchSlotHost: View {
    let kind: NotchWidgetKind
    let availableWidth: CGFloat

    let liveSessionCount: Int
    let spotlightTool: AgentTool?
    let spotlightWorkspaceName: String?
    let spotlightWorkspaceKey: String?
    let projectColorRegistry: ProjectColorRegistry
    let codeburnState: CodeburnState

    var body: some View {
        switch kind {
        case .none:
            Color.clear.frame(width: availableWidth, height: 1)
        case .sessionCount:
            ClosedCountBadge(liveCount: liveSessionCount, tint: .white.opacity(0.85))
        case .projectChip:
            ProjectChipWidget(
                workspaceName: spotlightWorkspaceName,
                workspaceKey: spotlightWorkspaceKey,
                registry: projectColorRegistry,
                availableWidth: availableWidth
            )
        case .agentToolIcon:
            AgentToolIconWidget(tool: spotlightTool)
        case .dollarSpentToday:
            DollarSpentWidget(state: codeburnState)
        }
    }
}
