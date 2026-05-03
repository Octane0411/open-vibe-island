import SwiftUI
import OpenIslandCore

enum BadgeColors {
    /// Distinct per-agent tint for the agent badge text. Picked to match the
    /// agent's brand association where one is obvious; otherwise a stable
    /// hash-friendly hue from the standard SwiftUI palette.
    static func agent(_ tool: AgentTool) -> Color {
        switch tool {
        case .claudeCode: return Color.orange
        case .codex:      return Color.green
        case .cursor:     return Color.cyan
        case .geminiCLI:  return Color.purple
        case .openCode:   return Color.teal
        case .qoder:      return Color.pink
        case .qwenCode:   return Color.red
        case .factory:    return Color.yellow
        case .codebuddy:  return Color(red: 0.95, green: 0.55, blue: 0.85)  // hot pink
        case .kimiCLI:    return Color(red: 0.55, green: 0.95, blue: 0.65)  // mint
        }
    }

    /// Distinct per-terminal tint. Substring match on the terminal app/badge
    /// name — falls back to neutral gray for unknowns.
    static func terminal(_ name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("cmux") || lower.contains("tmux")     { return Color.green }
        if lower.contains("ghostty")                            { return Color.purple }
        if lower.contains("iterm")                              { return Color(red: 0.4, green: 0.7, blue: 1.0) }
        if lower.contains("terminal")                           { return Color.white.opacity(0.85) }
        if lower.contains("warp")                               { return Color.orange }
        if lower.contains("wezterm")                            { return Color.red }
        if lower.contains("zellij")                             { return Color.yellow }
        if lower.contains("kaku")                               { return Color.pink }
        if lower.contains("vs code") || lower.contains("vscode") { return Color.blue }
        if lower.contains("cursor")                             { return Color.cyan }
        if lower.contains("windsurf")                           { return Color.teal }
        return Color.white.opacity(0.7)
    }
}
