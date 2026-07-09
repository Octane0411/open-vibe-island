import Foundation

public enum HookSourceClassification: Equatable, Sendable {
    case codex
    case cursor
    case gemini
    case claudeFormat(String)

    public var isClaudeFormat: Bool {
        switch self {
        case .claudeFormat(_):
            true
        case .codex, .cursor, .gemini:
            false
        }
    }

    public static func classify(_ rawSource: String?) -> HookSourceClassification {
        guard let rawSource, !rawSource.isEmpty else {
            return .codex
        }

        switch rawSource {
        case "codex":
            return .codex
        case "cursor":
            return .cursor
        case "gemini":
            return .gemini
        default:
            return .claudeFormat(rawSource)
        }
    }
}
