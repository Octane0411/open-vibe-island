import Darwin
import Foundation

/// A terminal-attached Claude Code process that can display a background
/// session: `claude attach <id>` or the `claude agents` view.
///
/// Claude Code background sessions (`claude --bg`, sessions dispatched from
/// `claude agents`) run their engine under the per-user daemon
/// (`claude daemon` → `bg-pty-host`). The engine — and therefore every hook
/// it spawns — has a scrubbed environment and a daemon-owned pty, so the
/// usual `TERM_PROGRAM` / `ITERM_SESSION_ID` / TTY signals point nowhere.
/// The process the user actually looks at is the viewer in a terminal tab.
public struct ClaudeBackgroundSessionViewer: Equatable, Codable, Sendable {
    public var pid: Int32
    public var terminalTTY: String?
    public var workingDirectory: String?
    public var arguments: [String]
    public var environment: [String: String]

    public init(
        pid: Int32,
        terminalTTY: String?,
        workingDirectory: String?,
        arguments: [String],
        environment: [String: String]
    ) {
        self.pid = pid
        self.terminalTTY = terminalTTY
        self.workingDirectory = workingDirectory
        self.arguments = arguments
        self.environment = environment
    }
}

public enum ClaudeBackgroundSessionViewerResolver {
    enum ViewerKind: Equatable {
        /// `claude attach <id>` — shows exactly one session.
        case attach(sessionID: String)
        /// `claude agents [--cwd <path>]` — lists sessions under `scope`,
        /// or every session when `scope` is nil.
        case agents(scope: String?)
    }

    /// Terminal-identifying variables taken from the viewer before terminal
    /// inference. Kept to an explicit list so unrelated viewer state never
    /// leaks into the payload.
    static let terminalEnvironmentKeys: [String] = [
        "TERM_PROGRAM",
        "TERM_PROGRAM_VERSION",
        "TERM_SESSION_ID",
        "ITERM_SESSION_ID",
        "ITERM_PROFILE",
        "LC_TERMINAL",
        "__CFBundleIdentifier",
        "GHOSTTY_RESOURCES_DIR",
        "WARP_IS_LOCAL_SHELL_SESSION",
        "TERMINAL_EMULATOR",
        "TMUX",
        "TMUX_PANE",
        "CMUX_WORKSPACE_ID",
        "CMUX_SURFACE_ID",
        "CMUX_SOCKET_PATH",
        "ZELLIJ",
        "ZELLIJ_PANE_ID",
        "ZELLIJ_SESSION_NAME",
    ]

    /// Whether the hook is running inside a Claude Code background session.
    public static func isBackgroundSession(environment: [String: String]) -> Bool {
        environment["CLAUDE_CODE_SESSION_KIND"] == "bg"
            || environment["CLAUDE_BG_BACKEND"]?.isEmpty == false
    }

    static func viewerKind(arguments: [String]) -> ViewerKind? {
        guard let executable = arguments.first else {
            return nil
        }

        let name = (executable as NSString).lastPathComponent.lowercased()
        guard name == "claude", arguments.count >= 2 else {
            return nil
        }

        switch arguments[1] {
        case "attach":
            guard arguments.count >= 3, !arguments[2].hasPrefix("-") else {
                return nil
            }
            return .attach(sessionID: arguments[2].lowercased())
        case "agents":
            var scope: String?
            var index = 2
            while index < arguments.count {
                let argument = arguments[index]
                if argument == "--cwd", index + 1 < arguments.count {
                    scope = arguments[index + 1]
                    index += 2
                    continue
                }
                if argument.hasPrefix("--cwd=") {
                    scope = String(argument.dropFirst("--cwd=".count))
                }
                index += 1
            }
            return .agents(scope: scope)
        default:
            return nil
        }
    }

    /// Picks the viewer that displays the session, preferring an exact
    /// `claude attach` over the most specific `claude agents --cwd` scope
    /// that contains the session's working directory. Returns nil when no
    /// terminal-attached viewer covers the session.
    public static func selectViewer(
        from candidates: [ClaudeBackgroundSessionViewer],
        sessionID: String,
        sessionName: String?,
        sessionWorkingDirectory: String
    ) -> ClaudeBackgroundSessionViewer? {
        let normalizedSessionID = sessionID.lowercased()
        let normalizedSessionName = sessionName?.lowercased()
        let sessionPath = standardizedPath(sessionWorkingDirectory)

        var bestAgentsViewer: ClaudeBackgroundSessionViewer?
        var bestSpecificity = -1

        for candidate in candidates.sorted(by: { $0.pid < $1.pid }) {
            guard candidate.terminalTTY?.isEmpty == false,
                  let kind = viewerKind(arguments: candidate.arguments) else {
                continue
            }

            switch kind {
            case let .attach(attachedID):
                if attachedID == normalizedSessionName
                    || attachedID == normalizedSessionID
                    || (attachedID.count >= 8 && normalizedSessionID.hasPrefix(attachedID)) {
                    return candidate
                }
            case let .agents(scope):
                let specificity: Int
                if let scope {
                    guard let scopePath = resolvedScopePath(scope, relativeTo: candidate.workingDirectory),
                          sessionPath == scopePath || sessionPath.hasPrefix(scopePath == "/" ? "/" : scopePath + "/") else {
                        continue
                    }
                    specificity = scopePath.count
                } else {
                    specificity = 0
                }

                if specificity > bestSpecificity {
                    bestSpecificity = specificity
                    bestAgentsViewer = candidate
                }
            }
        }

        return bestAgentsViewer
    }

    /// Replaces the hook's terminal-identifying variables with the viewer's.
    /// In a background session those variables are leaked from the tab that
    /// started the daemon, so they are dropped even when no viewer is found.
    public static func terminalEnvironment(
        replacing environment: [String: String],
        with viewer: ClaudeBackgroundSessionViewer?
    ) -> [String: String] {
        var result = environment
        for key in terminalEnvironmentKeys {
            if let value = viewer?.environment[key], !value.isEmpty {
                result[key] = value
            } else {
                result.removeValue(forKey: key)
            }
        }
        return result
    }

    /// The engine PID when the hook runs inside a Claude Code background
    /// session, nil otherwise. Claude Code scrubs the daemon markers from
    /// hook environments, so the engine (`CLAUDE_PID`) is inspected too.
    static func backgroundAgentPID(
        environment: [String: String],
        processEnvironment: (Int32) -> [String: String]? = { processArguments(pid: $0)?.environment }
    ) -> Int32? {
        let enginePID = environment["CLAUDE_PID"].flatMap { Int32($0) }
        if isBackgroundSession(environment: environment) {
            return enginePID ?? getppid()
        }
        guard let enginePID,
              let engineEnvironment = processEnvironment(enginePID),
              isBackgroundSession(environment: engineEnvironment) else {
            return nil
        }
        return enginePID
    }

    /// iTerm2 exports `ITERM_SESSION_ID` as `w0t0p0:<UUID>`; its AppleScript
    /// `id of session` is the bare UUID used by the jump service.
    public static func iTermSessionID(from environmentValue: String?) -> String? {
        guard let environmentValue, !environmentValue.isEmpty else {
            return nil
        }
        let identifier = environmentValue.split(separator: ":", maxSplits: 1).last.map(String.init) ?? environmentValue
        return identifier.isEmpty ? nil : identifier
    }

    static func resolvedScopePath(_ scope: String, relativeTo workingDirectory: String?) -> String? {
        let expanded = (scope as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return standardizedPath(expanded)
        }
        guard let workingDirectory, workingDirectory.hasPrefix("/") else {
            return nil
        }
        return standardizedPath((workingDirectory as NSString).appendingPathComponent(expanded))
    }

    static func standardizedPath(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        if standardized.count > 1, standardized.hasSuffix("/") {
            return String(standardized.dropLast())
        }
        return standardized
    }
}

// MARK: - Live process lookup

extension ClaudeBackgroundSessionViewerResolver {
    /// Lists terminal-attached `claude attach` / `claude agents` processes
    /// owned by the current user, with their exact argv and environment.
    ///
    /// Uses sysctl / libproc directly instead of `ps` + `lsof`: a full
    /// `ps` listing easily exceeds a pipe buffer, and hooks must never block.
    static func liveViewers() -> [ClaudeBackgroundSessionViewer] {
        terminalAttachedProcesses().compactMap { process in
            guard let procArgs = processArguments(pid: process.pid),
                  viewerKind(arguments: procArgs.arguments) != nil else {
                return nil
            }
            return ClaudeBackgroundSessionViewer(
                pid: process.pid,
                terminalTTY: process.terminalTTY,
                workingDirectory: workingDirectory(pid: process.pid),
                arguments: procArgs.arguments,
                environment: procArgs.environment
            )
        }
    }

    /// Current-user processes that have a controlling terminal.
    static func terminalAttachedProcesses() -> [(pid: Int32, terminalTTY: String)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }

        // Leave room for processes spawned between the two calls.
        size += size / 4
        let stride = MemoryLayout<kinfo_proc>.stride
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)
        guard sysctl(&mib, 4, &processes, &size, nil, 0) == 0 else {
            return []
        }

        return processes.prefix(size / stride).compactMap { process in
            let device = process.kp_eproc.e_tdev
            guard device != -1, let name = devname(device, S_IFCHR) else {
                return nil
            }
            return (pid: process.kp_proc.p_pid, terminalTTY: "/dev/" + String(cString: name))
        }
    }

    static func workingDirectory(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let expectedSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, expectedSize) == expectedSize else {
            return nil
        }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return path.hasPrefix("/") ? path : nil
    }

    /// Reads another same-user process's argv and environment via
    /// `KERN_PROCARGS2`.
    static func processArguments(pid: Int32) -> (arguments: [String], environment: [String: String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        return parseProcArgs2(Array(buffer.prefix(size)))
    }

    /// Parses the `KERN_PROCARGS2` layout: `argc` (Int32), the exec path,
    /// NUL padding, `argc` NUL-terminated arguments, then NUL-terminated
    /// `KEY=VALUE` environment strings ending at an empty string.
    static func parseProcArgs2(_ bytes: [UInt8]) -> (arguments: [String], environment: [String: String])? {
        let headerSize = MemoryLayout<Int32>.size
        guard bytes.count > headerSize else {
            return nil
        }

        let argc = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc > 0 else {
            return nil
        }

        var index = headerSize
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }

        func nextString() -> String? {
            guard index < bytes.count else { return nil }
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            let value = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            return value
        }

        var arguments: [String] = []
        while arguments.count < argc, let argument = nextString() {
            arguments.append(argument)
        }
        guard arguments.count == argc else {
            return nil
        }

        var environment: [String: String] = [:]
        while let entry = nextString(), !entry.isEmpty {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<separator])
            guard environment[key] == nil else { continue }
            environment[key] = String(entry[entry.index(after: separator)...])
        }

        return (arguments, environment)
    }
}
