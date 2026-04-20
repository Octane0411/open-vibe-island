import Foundation
import Darwin

/// Walks the calling process's ancestor chain to locate the Warp pane that
/// hosts it, without depending on Warp's SQLite cwd column.
///
/// The core observation is that Warp spawns one shell subprocess per pane
/// as a direct child of its `terminal-server` process. From any descendant
/// of such a shell (like the hook CLI running inside a `claude` process),
/// walking `getppid` upward will eventually hit a process whose parent is
/// the terminal-server. That process's pid uniquely identifies the pane,
/// even when two sibling panes share the same working directory.
///
/// This is what makes it possible to disambiguate sibling tabs that have
/// identical `terminal_panes.cwd` — a case Warp's SQLite cannot resolve on
/// its own because it stores no per-pane PID or TTY.
public enum WarpProcessResolver {

    /// Identifies a specific Warp pane via its hosting shell process chain.
    public struct PaneContext: Sendable, Equatable {
        /// PID of the shell that is the direct child of
        /// `terminalServerPID`. This is unique per Warp pane within a
        /// running Warp instance.
        public let shellPID: pid_t
        /// PID of the `stable terminal-server` helper process. Stable
        /// for as long as Warp is running.
        public let terminalServerPID: pid_t

        public init(shellPID: pid_t, terminalServerPID: pid_t) {
            self.shellPID = shellPID
            self.terminalServerPID = terminalServerPID
        }
    }

    /// Resolves the pane context of the calling process (typically the
    /// AgentDeckHooks CLI running inside a Claude/Codex child of a Warp
    /// shell). Returns nil when the process is not a descendant of a Warp
    /// terminal-server (e.g. running under Ghostty or Terminal.app).
    public static func resolveCurrentPaneContext() -> PaneContext? {
        resolveCurrentPaneContext(
            parentPIDProvider: defaultParentPIDProvider,
            commandProvider: defaultCommandProvider
        )
    }

    /// Test-friendly overload that accepts injected providers. Production
    /// callers should use the zero-argument variant.
    public static func resolveCurrentPaneContext(
        parentPIDProvider: (pid_t) -> pid_t?,
        commandProvider: (pid_t) -> String?
    ) -> PaneContext? {
        resolvePaneContext(
            startingFrom: getppid(),
            parentPIDProvider: parentPIDProvider,
            commandProvider: commandProvider
        )
    }

    /// Internal walker. Starts at `startingFrom` and climbs the parent
    /// chain until a process whose parent is a Warp terminal-server is
    /// found, or until the depth cap is hit.
    ///
    /// The depth cap (16) is generous enough to cover realistic nesting
    /// (hook CLI → claude → zsh → optional wrapper → Warp shell) while
    /// bounding the walk so a broken ps chain cannot loop forever.
    static func resolvePaneContext(
        startingFrom initial: pid_t,
        parentPIDProvider: (pid_t) -> pid_t?,
        commandProvider: (pid_t) -> String?
    ) -> PaneContext? {
        var current = initial
        for _ in 0..<16 {
            guard current > 1 else { return nil }
            guard let parent = parentPIDProvider(current), parent > 1 else {
                return nil
            }
            if let parentCommand = commandProvider(parent),
               isWarpTerminalServer(command: parentCommand) {
                return PaneContext(shellPID: current, terminalServerPID: parent)
            }
            current = parent
        }
        return nil
    }

    /// True when `command` looks like Warp's `terminal-server` helper
    /// invocation. Matches both Warp Stable and Warp Preview because both
    /// ship the binary under `/Warp.app/` and pass the `terminal-server`
    /// subcommand on the argv line.
    static func isWarpTerminalServer(command: String) -> Bool {
        let lower = command.lowercased()
        return lower.contains("/warp.app/") && lower.contains("terminal-server")
    }

    // MARK: - Default providers (production)

    static let defaultParentPIDProvider: @Sendable (pid_t) -> pid_t? = { pid in
        guard let output = runSubprocess(
            executable: "/bin/ps",
            arguments: ["-o", "ppid=", "-p", "\(pid)"]
        ) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return pid_t(trimmed)
    }

    static let defaultCommandProvider: @Sendable (pid_t) -> String? = { pid in
        guard let output = runSubprocess(
            executable: "/bin/ps",
            arguments: ["-o", "command=", "-p", "\(pid)"]
        ) else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runSubprocess(executable: String, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
