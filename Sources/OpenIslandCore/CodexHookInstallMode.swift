import Foundation

/// Controls how aggressively Open Island integrates with Codex CLI.
///
/// - `notifyOnly` (default): mirrors the historical footprint — `SessionStart`,
///   `UserPromptSubmit`, `Stop`. Surfaces activity without intercepting tool
///   execution.
/// - `fullControl`: additionally registers `PreToolUse` (blocking approval) and
///   `PostToolUse` (fire-and-forget notification) so the user can approve or
///   deny each shell command before Codex runs it. This raises per-turn
///   notification volume and requires the app to be running to answer
///   approvals within the 1h PreToolUse hook timeout.
public enum CodexHookInstallMode: String, Codable, Sendable, CaseIterable {
    case notifyOnly
    case fullControl

    public static let `default`: CodexHookInstallMode = .notifyOnly
}
