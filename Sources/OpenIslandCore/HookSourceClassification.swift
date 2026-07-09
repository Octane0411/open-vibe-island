import Foundation

/// Classifies a hook `--source` argument into a known payload-protocol case.
///
/// This replaces per-agent if-else chains so that the hook CLI (``OpenIslandHooksCLI``)
/// and any code that inspects source identifiers can share one classification table.
/// Unknown non-empty sources are treated as Claude-format, which is the most common
/// pattern for custom or company-wrapped Claude Code-compatible CLIs.
///
/// - Note: Empty or missing source falls back to ``codex`` for backward compatibility.
public enum HookSourceClassification: Equatable, Sendable {
    /// Codex (Amazon Q Developer) agent protocol.
    case codex
    /// Cursor agent protocol.
    case cursor
    /// Gemini agent protocol.
    case gemini
    /// Claude-format payload, identified by the raw source string.
    case claudeFormat(String)

    /// Whether the classification represents a Claude-format payload.
    ///
    /// Use this for quick checks without pattern matching:
    /// ```swift
    /// if HookSourceClassification.classify(raw).isClaudeFormat { ... }
    /// ```
    public var isClaudeFormat: Bool {
        switch self {
        case .claudeFormat:
            true
        case .codex, .cursor, .gemini:
            false
        }
    }

    /// Classify a raw ``--source`` argument string.
    ///
    /// - Parameter rawSource: The raw `--source` value from the hook CLI invocation,
    ///   or `nil` if the flag was omitted.
    /// - Returns: A ``HookSourceClassification`` matching the known source, or
    ///   ``claudeFormat(_:)`` if the source is unrecognised.
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
