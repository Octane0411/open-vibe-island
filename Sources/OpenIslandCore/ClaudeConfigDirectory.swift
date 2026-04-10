import Foundation

/// Resolves the Claude Code configuration directory.
///
/// Checks the `CLAUDE_CONFIG_DIR` environment variable first, falling back to `~/.claude`.
/// This allows users who run Claude Code with a custom config directory to have their
/// hooks and settings managed correctly.
public enum ClaudeConfigDirectory {
    public static func resolved(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let customPath = environment["CLAUDE_CONFIG_DIR"], !customPath.isEmpty {
            return URL(fileURLWithPath: (customPath as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }
}
