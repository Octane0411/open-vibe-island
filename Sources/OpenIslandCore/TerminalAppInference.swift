import Foundation

/// Shared host-terminal classification used by Claude / Codex / Gemini hooks.
///
/// VS Code forks (Cursor, Windsurf, Trae, …) often set `TERM_PROGRAM=vscode`.
/// Classifying them as plain VS Code breaks badge labels and jump targets (#511).
public enum TerminalAppInference: Sendable {
    /// Resolve the VS Code family host for a hook environment.
    /// Prefer Cursor when any Cursor-specific signal is present.
    public static func resolveVSCodeFamilyHost(from environment: [String: String]) -> String {
        if isCursorEnvironment(environment) {
            return "Cursor"
        }
        return "VS Code"
    }

    /// Whether this environment is Cursor rather than stock VS Code.
    ///
    /// Cursor sets `TERM_PROGRAM=vscode` like other VS Code forks. Prefer
    /// explicit Cursor signals; never guess from `TERM_PROGRAM` alone.
    public static func isCursorEnvironment(_ environment: [String: String]) -> Bool {
        if environment["CURSOR_TRACE_ID"] != nil {
            return true
        }

        // Cursor injects several CURSOR_* variables into its integrated terminal.
        if environment.keys.contains(where: { key in
            key.hasPrefix("CURSOR_") && key != "CURSOR_"
        }) {
            return true
        }

        if let bundleID = environment["__CFBundleIdentifier"]?.lowercased() {
            // Official Cursor bundle id (ToDesktop packaging).
            if bundleID == "com.todesktop.230313mzl4w4u92" || bundleID.contains("todesktop") {
                return true
            }
            if bundleID.contains("cursor") {
                return true
            }
        }

        // VS Code family often points askpass / node helpers at the host .app.
        let pathKeys = [
            "VSCODE_GIT_ASKPASS_NODE",
            "VSCODE_GIT_ASKPASS_MAIN",
            "VSCODE_GIT_IPC_HANDLE",
            "VSCODE_NLS_CONFIG",
        ]
        for key in pathKeys {
            if let value = environment[key], value.localizedCaseInsensitiveContains("Cursor.app") {
                return true
            }
        }

        return false
    }
}
