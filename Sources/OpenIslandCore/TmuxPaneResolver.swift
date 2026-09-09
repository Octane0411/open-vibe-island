import Foundation

public extension ProcessInfo {
    /// Parent PID of the given process, via `ps`. Returns nil when the lookup
    /// fails or the process has exited.
    func parentPID(of pid: Int) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "ppid="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty else {
            return nil
        }

        return Int(output)
    }
}

/// Resolves a TTY to its tmux pane (`session:window.pane`) and the host
/// terminal app that owns the tmux client, via the tmux CLI.
///
/// Used by the Hermes hook runtime context: inside tmux the inherited
/// `TERM_PROGRAM` / `ITERM_SESSION_ID` describe whatever launched the tmux
/// client, so the host terminal must be derived from the tmux client's
/// process chain instead of the environment.
public protocol TmuxPaneResolverProtocol: Sendable {
    func pane(forTTY tty: String) -> TmuxPaneResolver.Pane?
    func hostTerminalApp() -> String?
    var socketPath: String? { get }
}

public struct TmuxPaneResolver: TmuxPaneResolverProtocol {
    public struct Pane: Equatable, Sendable {
        public var target: String
        public init(target: String) {
            self.target = target
        }
    }

    let tmuxPath: String
    public let socketPath: String?

    private let hostTerminalMarkers: [(marker: String, app: String)] = [
        ("iterm.app/contents/macos/iterm2", "iTerm"),
        ("iterm.app/contents/macos/iterm", "iTerm"),
        ("visual studio code.app", "VS Code"),
        ("vs code insiders.app", "VS Code Insiders"),
        ("cursor.app", "Cursor"),
        ("windsurf.app", "Windsurf"),
        ("trae.app", "Trae"),
        ("ghostty.app", "Ghostty"),
        ("warp.app", "Warp"),
        ("kaku.app", "Kaku"),
        ("wezterm.app", "WezTerm"),
        ("terminal.app", "Terminal"),
    ]

    public init?(tmuxPath: String? = nil, socketPath: String? = nil) {
        if let tmuxPath {
            self.tmuxPath = tmuxPath
            self.socketPath = socketPath
            return
        }

        guard let resolved = Self.resolveTmuxPath() else {
            return nil
        }
        self.tmuxPath = resolved
        self.socketPath = nil
    }

    static func resolveTmuxPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        return nil
    }

    /// Pane whose `pane_tty` matches the given agent TTY.
    public func pane(forTTY tty: String) -> Pane? {
        let paneTTY = tty.hasPrefix("/dev/") ? String(tty.dropFirst("/dev/".count)) : tty
        guard let output = run(["list-panes", "-a", "-F", "#{pane_tty}\t#{session_name}:#{window_index}.#{pane_index}"]) else {
            return nil
        }

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let listedTTY = parts[0].trimmingCharacters(in: .whitespaces)
            let listedBare = listedTTY.hasPrefix("/dev/") ? String(listedTTY.dropFirst("/dev/".count)) : listedTTY
            if listedBare == paneTTY || listedTTY == tty {
                return Pane(target: parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    /// Display name of the host terminal owning the tmux client, derived by
    /// walking the client process chain for a recognized terminal bundle.
    public func hostTerminalApp() -> String? {
        guard let clientTTY = run(["list-clients", "-F", "#{client_tty}"])?
            .split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else {
            return nil
        }

        var pid: Int? = pidForTTY(clientTTY)
        var visited: Set<Int> = []
        while let current = pid, visited.insert(current).inserted, current > 1 {
            if let host = hostAppForPID(current) {
                return host
            }
            pid = parentPID(current)
        }
        return nil
    }

    private func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        var args = arguments
        if let socketPath, !socketPath.isEmpty {
            args = ["-S", socketPath] + args
        }
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
            return nil
        }
        return output
    }

    private func pidForTTY(_ tty: String) -> Int? {
        let bare = tty.hasPrefix("/dev/") ? String(tty.dropFirst("/dev/".count)) : tty
        guard let output = runProcess("/bin/ps", ["-t", bare, "-o", "pid="]) else {
            return nil
        }
        return output.split(whereSeparator: \.isWhitespace).first.flatMap { Int($0) }
    }

    private func parentPID(_ pid: Int) -> Int? {
        guard let output = runProcess("/bin/ps", ["-p", "\(pid)", "-o", "ppid="]) else {
            return nil
        }
        return output.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : Int(output.trimmingCharacters(in: .whitespaces))
    }

    private func hostAppForPID(_ pid: Int) -> String? {
        guard let output = runProcess("/bin/ps", ["-p", "\(pid)", "-o", "command="]) else {
            return nil
        }
        let lowered = output.lowercased()
        for (marker, app) in hostTerminalMarkers where lowered.contains(marker) {
            return app
        }
        return nil
    }

    private func runProcess(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
            return nil
        }
        return output
    }
}
