import SwiftUI
import OpenIslandCore

struct AgentToolIconWidget: View {
    let tool: AgentTool?

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 16, height: 16)
    }

    /// Map agent tool to SF Symbol. Phase 1 uses generic glyphs; Phase 2 can
    /// swap in branded asset images per agent.
    private var symbolName: String {
        guard let tool else { return "circle.dashed" }
        switch tool {
        case .claudeCode: return "sparkles"
        case .codex:      return "chevron.left.forwardslash.chevron.right"
        case .cursor:     return "cursorarrow.rays"
        case .geminiCLI:  return "diamond"
        case .openCode:   return "curlybraces"
        case .qoder:      return "wand.and.stars"
        case .qwenCode:   return "circle.hexagongrid"
        case .factory:    return "hammer"
        case .codebuddy:  return "person.2"
        case .kimiCLI:    return "moon.stars"
        }
    }

    private var tint: Color {
        guard tool != nil else { return .white.opacity(0.4) }
        return .white.opacity(0.85)
    }
}
