import Foundation

/// Terminal detection and identification — infers which terminal app
/// a hook process is running in, resolves TTY, and queries focused
/// terminal panes via AppleScript. Shared across agent hook payloads.
public enum TerminalDetectionService {

    // MARK: - App detection from environment

    /// Infer the terminal app from environment variables set by the shell.
    public static func inferTerminalApp(from environment: [String: String]) -> String? {
        if environment["ITERM_SESSION_ID"] != nil || environment["LC_TERMINAL"] == "iTerm2" {
            return "iTerm"
        }

        if environment["CMUX_WORKSPACE_ID"] != nil || environment["CMUX_SOCKET_PATH"] != nil {
            return "cmux"
        }

        if environment["GHOSTTY_RESOURCES_DIR"] != nil {
            return "Ghostty"
        }

        let termProgram = environment["TERM_PROGRAM"]?.lowercased()
        switch termProgram {
        case .some("apple_terminal"):
            return "Terminal"
        case .some("iterm.app"), .some("iterm2"):
            return "iTerm"
        case let value? where value.contains("ghostty"):
            // cmux also sets TERM_PROGRAM=ghostty; already handled above via
            // CMUX_WORKSPACE_ID / CMUX_SOCKET_PATH, so reaching here means
            // genuine Ghostty.
            return "Ghostty"
        case .some("kaku"):
            return "Kaku"
        case .some("wezterm"):
            return "WezTerm"
        default:
            return nil
        }
    }

    // MARK: - App classification

    public static func isGhostty(_ terminalApp: String?) -> Bool {
        guard let app = terminalApp?.lowercased() else { return false }
        return app.contains("ghostty")
    }

    public static func isCmux(_ terminalApp: String?) -> Bool {
        terminalApp?.lowercased() == "cmux"
    }

    /// Whether the focused-terminal AppleScript locator should be used
    /// for this terminal app. Ghostty, cmux, Kaku, and WezTerm are excluded
    /// because they either lack AppleScript support or return unreliable results.
    public static func shouldUseFocusedTerminalLocator(for terminalApp: String) -> Bool {
        let lower = terminalApp.lowercased()
        return !lower.contains("ghostty") && lower != "cmux"
            && lower != "kaku" && lower != "wezterm"
    }

    // MARK: - TTY resolution

    /// Get the TTY of the current process, falling back to parent process TTY.
    public static func currentTTY() -> String? {
        if let tty = ShellProcess.output(executablePath: "/usr/bin/tty", arguments: []),
           !tty.contains("not a tty") {
            return tty
        }

        return parentProcessTTY()
    }

    private static func parentProcessTTY() -> String? {
        let ppid = getppid()
        guard let raw = ShellProcess.output(executablePath: "/bin/ps", arguments: ["-p", "\(ppid)", "-o", "tty="]) else {
            return nil
        }

        let tty = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tty.isEmpty, tty != "??", tty != "-" else {
            return nil
        }

        return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    // MARK: - Focused terminal locator (AppleScript)

    /// Query the focused terminal pane via AppleScript. Returns the session ID,
    /// TTY, and title of the currently focused pane in the given terminal app.
    public static func terminalLocator(for terminalApp: String) -> (sessionID: String?, tty: String?, title: String?) {
        let normalized = terminalApp.lowercased()

        if normalized.contains("iterm") {
            let values = osascriptValues(script: """
            tell application "iTerm"
                if not (it is running) then return ""
                tell current session of current window
                    return (id as text) & (ASCII character 31) & (tty as text) & (ASCII character 31) & (name as text)
                end tell
            end tell
            """)
            return (
                sessionID: values[safe: 0],
                tty: values[safe: 1],
                title: values[safe: 2]
            )
        }

        if normalized == "cmux" {
            return (sessionID: nil, tty: nil, title: nil)
        }

        if normalized.contains("ghostty") {
            let values = osascriptValues(script: """
            tell application "Ghostty"
                if not (it is running) then return ""
                tell focused terminal of selected tab of front window
                    return (id as text) & (ASCII character 31) & (working directory as text) & (ASCII character 31) & (name as text)
                end tell
            end tell
            """)
            return (
                sessionID: values[safe: 0],
                tty: nil,
                title: values[safe: 2]
            )
        }

        if normalized.contains("terminal") {
            let values = osascriptValues(script: """
            tell application "Terminal"
                if not (it is running) then return ""
                tell selected tab of front window
                    return (tty as text) & (ASCII character 31) & (custom title as text)
                end tell
            end tell
            """)
            return (
                sessionID: nil,
                tty: values[safe: 0],
                title: values[safe: 1]
            )
        }

        return (nil, nil, nil)
    }

    // MARK: - Helpers

    private static func osascriptValues(script: String) -> [String] {
        guard let raw = ShellProcess.output(executablePath: "/usr/bin/osascript", arguments: ["-e", script]) else {
            return []
        }

        let separator = String(UnicodeScalar(31)!)
        return raw
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
