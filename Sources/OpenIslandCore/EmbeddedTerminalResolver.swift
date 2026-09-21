import Foundation
import Darwin

/// Walks the calling process's ancestor chain to detect when an agent is
/// running inside an embedded terminal hosted by a known IDE or editor app
/// (VS Code family, JetBrains, Obsidian).
///
/// This complements `inferTerminalApp(from:)` in the hook payload pipeline.
/// Env-var inference is authoritative when `TERM_PROGRAM` (or the JetBrains
/// `TERMINAL_EMULATOR` signal) is set, but plugins like Obsidian's terminal
/// or any agent launched without inheriting those vars leave inference with
/// nothing to go on. The process tree always knows.
///
/// The walk starts at `getppid()` (the agent process) and climbs upward via
/// `ps -o ppid=` until it finds a process whose `ps -o command=` line points
/// at a known IDE `.app` bundle path, or until the depth cap is hit.
public enum EmbeddedTerminalResolver {

    /// A single embedded host the resolver can recognize.
    public enum EmbeddedHost: Sendable, Equatable, Codable {
        case vscodeFamily(bundleID: String, displayName: String)
        case jetbrains(bundleID: String, displayName: String)
        case obsidian

        public var bundleID: String {
            switch self {
            case let .vscodeFamily(bundleID, _), let .jetbrains(bundleID, _):
                return bundleID
            case .obsidian:
                return "md.obsidian"
            }
        }

        public var displayName: String {
            switch self {
            case let .vscodeFamily(_, displayName), let .jetbrains(_, displayName):
                return displayName
            case .obsidian:
                return "Obsidian"
            }
        }
    }

    /// Identifies the embedded host found above the calling process.
    public struct HostContext: Sendable, Equatable, Codable {
        public let host: EmbeddedHost
        /// PID of the first ancestor whose command matches a known host
        /// `.app` bundle path. For helper-heavy hosts like VS Code this
        /// can be a helper inside the bundle (e.g. `Code Helper (Plugin)`)
        /// rather than the outer app's PID — the bundle path alone is
        /// enough for current callers, which dispatch by bundle ID. A
        /// future phase that needs the outer-app PID should walk further
        /// up while the classification stays the same.
        public let hostPID: pid_t
        /// PID of the direct child of `hostPID`. For most IDEs this is
        /// the shell that owns the embedded terminal pane — useful later
        /// for per-pane focus precision.
        public let shellPID: pid_t

        public init(host: EmbeddedHost, hostPID: pid_t, shellPID: pid_t) {
            self.host = host
            self.hostPID = hostPID
            self.shellPID = shellPID
        }
    }

    /// Resolves the embedded host of the calling process. Returns nil when
    /// the process is not a descendant of any recognized IDE.
    public static func resolveCurrentHostContext() -> HostContext? {
        resolveCurrentHostContext(
            parentPIDProvider: defaultParentPIDProvider,
            commandProvider: defaultCommandProvider
        )
    }

    /// Test-friendly overload that accepts injected providers.
    public static func resolveCurrentHostContext(
        parentPIDProvider: (pid_t) -> pid_t?,
        commandProvider: (pid_t) -> String?
    ) -> HostContext? {
        resolveHostContext(
            startingFrom: getppid(),
            parentPIDProvider: parentPIDProvider,
            commandProvider: commandProvider
        )
    }

    /// Internal walker. Climbs the parent chain from `initial` looking for a
    /// known IDE ancestor. The depth cap (24) is generous enough to cover
    /// VS Code's helper-process tree (Code Helper (Plugin) → Code Helper →
    /// Electron → outer app) plus several levels of shell/agent nesting,
    /// while bounding the walk so a broken `ps` chain cannot loop forever.
    static func resolveHostContext(
        startingFrom initial: pid_t,
        parentPIDProvider: (pid_t) -> pid_t?,
        commandProvider: (pid_t) -> String?
    ) -> HostContext? {
        var current = initial
        for _ in 0..<24 {
            guard current > 1 else { return nil }
            guard let parent = parentPIDProvider(current), parent > 1 else {
                return nil
            }
            if let parentCommand = commandProvider(parent),
               let host = classify(command: parentCommand) {
                return HostContext(host: host, hostPID: parent, shellPID: current)
            }
            current = parent
        }
        return nil
    }

    /// Maps a `ps -o command=` line for a process to a known embedded host.
    /// Match by `.app` path because VS Code forks (Cursor, Windsurf, Trae)
    /// share Electron's `Code Helper` binary names — the bundle path is the
    /// only reliable discriminator on macOS.
    static func classify(command: String) -> EmbeddedHost? {
        let lower = command.lowercased()

        // VS Code family. Order matters: Insiders before generic VS Code,
        // since Insiders contains "code.app" in some helper paths too.
        if lower.contains("/visual studio code - insiders.app/") ||
           lower.contains("/code - insiders.app/") {
            return .vscodeFamily(
                bundleID: "com.microsoft.VSCodeInsiders",
                displayName: "VS Code Insiders"
            )
        }
        if lower.contains("/visual studio code.app/") || lower.contains("/code.app/") {
            return .vscodeFamily(bundleID: "com.microsoft.VSCode", displayName: "VS Code")
        }
        if lower.contains("/cursor.app/") {
            return .vscodeFamily(
                bundleID: "com.todesktop.230313mzl4w4u92",
                displayName: "Cursor"
            )
        }
        if lower.contains("/windsurf.app/") {
            return .vscodeFamily(bundleID: "com.exafunction.windsurf", displayName: "Windsurf")
        }
        if lower.contains("/trae cn.app/") {
            return .vscodeFamily(bundleID: "cn.trae.app", displayName: "Trae")
        }
        if lower.contains("/trae.app/") {
            return .vscodeFamily(bundleID: "com.trae.app", displayName: "Trae")
        }

        // JetBrains family. Each IDE ships its own `.app`; the binary name
        // inside Contents/MacOS matches the lowercased product name.
        for entry in jetbrainsAppPathFragments {
            if lower.contains(entry.fragment) {
                return .jetbrains(bundleID: entry.bundleID, displayName: entry.displayName)
            }
        }

        if lower.contains("/obsidian.app/") {
            return .obsidian
        }

        return nil
    }

    private struct JetBrainsEntry {
        let fragment: String
        let bundleID: String
        let displayName: String
    }

    /// Lowercased `.app/` path fragments that uniquely identify each
    /// JetBrains IDE bundle. Kept in a single table so adding a new IDE is
    /// one line. Must stay in sync with the descriptors in
    /// `TerminalJumpService.knownApps`.
    private static let jetbrainsAppPathFragments: [JetBrainsEntry] = [
        JetBrainsEntry(fragment: "/intellij idea", bundleID: "com.jetbrains.intellij", displayName: "IntelliJ IDEA"),
        JetBrainsEntry(fragment: "/webstorm.app/", bundleID: "com.jetbrains.WebStorm", displayName: "WebStorm"),
        JetBrainsEntry(fragment: "/pycharm.app/", bundleID: "com.jetbrains.pycharm", displayName: "PyCharm"),
        JetBrainsEntry(fragment: "/pycharm ce.app/", bundleID: "com.jetbrains.pycharm", displayName: "PyCharm"),
        JetBrainsEntry(fragment: "/goland.app/", bundleID: "com.jetbrains.goland", displayName: "GoLand"),
        JetBrainsEntry(fragment: "/clion.app/", bundleID: "com.jetbrains.CLion", displayName: "CLion"),
        JetBrainsEntry(fragment: "/rubymine.app/", bundleID: "com.jetbrains.rubymine", displayName: "RubyMine"),
        JetBrainsEntry(fragment: "/phpstorm.app/", bundleID: "com.jetbrains.PhpStorm", displayName: "PhpStorm"),
        JetBrainsEntry(fragment: "/rider.app/", bundleID: "com.jetbrains.rider", displayName: "Rider"),
        JetBrainsEntry(fragment: "/rustrover.app/", bundleID: "com.jetbrains.rustrover", displayName: "RustRover"),
    ]

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
