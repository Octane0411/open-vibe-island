import Foundation
import OpenIslandCore

struct ActiveAgentProcessDiscovery {
    private static let processCommandTimeout: TimeInterval = 0.5
    private static let lsofCommandTimeout: TimeInterval = 0.2

    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    struct ProcessSnapshot: Equatable, Sendable {
        var tool: AgentTool
        var sessionID: String?
        var workingDirectory: String?
        var terminalTTY: String?
        var terminalApp: String?
        var transcriptPath: String?

        init(
            tool: AgentTool,
            sessionID: String?,
            workingDirectory: String?,
            terminalTTY: String?,
            terminalApp: String? = nil,
            transcriptPath: String? = nil
        ) {
            self.tool = tool
            self.sessionID = sessionID
            self.workingDirectory = workingDirectory
            self.terminalTTY = terminalTTY
            self.terminalApp = terminalApp
            self.transcriptPath = transcriptPath
        }
    }

    private struct RunningProcess {
        var pid: String
        var parentPID: String
        var terminalTTY: String?
        var command: String
    }

    typealias CommandRunner = @Sendable (_ executablePath: String, _ arguments: [String]) -> String?

    private let commandRunner: CommandRunner

    init(commandRunner: @escaping CommandRunner = Self.commandOutput) {
        self.commandRunner = commandRunner
    }

    func discover() -> [ProcessSnapshot] {
        let processes = runningProcesses()
        guard !processes.isEmpty else {
            return []
        }

        let processesByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })

        var snapshots: [ProcessSnapshot] = []
        var claimedKeys: Set<String> = []

        for process in processes {
            // Codex can run as a native app (no TTY), so check it before the
            // TTY filter. CLI-based agents still require a terminal.
            if isCodexProcess(command: process.command) || isCodexNativeAppProcess(command: process.command) {
                guard let snapshot = codexSnapshot(for: process, processesByPID: processesByPID) else {
                    continue
                }

                let claimKey = "codex:\(snapshot.sessionID ?? process.pid)"
                guard claimedKeys.insert(claimKey).inserted else {
                    continue
                }

                snapshots.append(snapshot)
                continue
            }

            guard process.terminalTTY != nil else {
                continue
            }

            if isClaudeProcess(command: process.command) {
                guard let snapshot = claudeSnapshot(for: process, processesByPID: processesByPID) else {
                    continue
                }

                let claimKey = "claude:\(snapshot.sessionID ?? snapshot.terminalTTY ?? snapshot.workingDirectory ?? process.pid)"
                guard claimedKeys.insert(claimKey).inserted else {
                    continue
                }

                snapshots.append(snapshot)
                continue
            }

            if isOpenCodeProcess(command: process.command) {
                let claimKey = "opencode:\(process.pid)"
                guard claimedKeys.insert(claimKey).inserted else {
                    continue
                }

                snapshots.append(ProcessSnapshot(
                    tool: .openCode,
                    sessionID: nil,
                    workingDirectory: nil,
                    terminalTTY: process.terminalTTY
                ))
            }
        }

        return snapshots
    }

    private func runningProcesses() -> [RunningProcess] {
        guard let output = commandRunner("/bin/ps", ["-Ao", "pid=,ppid=,tty=,command="]) else {
            return []
        }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> RunningProcess? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }

                let components = trimmed.split(maxSplits: 3, whereSeparator: \.isWhitespace)
                guard components.count == 4 else {
                    return nil
                }

                let pid = String(components[0])
                let parentPID = String(components[1])
                let tty = normalizedTTY(String(components[2]))
                let command = String(components[3]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty else {
                    return nil
                }

                return RunningProcess(pid: pid, parentPID: parentPID, terminalTTY: tty, command: command)
            }
    }

    private func codexSnapshot(
        for process: RunningProcess,
        processesByPID: [String: RunningProcess]
    ) -> ProcessSnapshot? {
        guard let lsofOutput = lsofOutput(pid: process.pid),
              let transcriptPath = matchingPath(in: lsofOutput, containing: "/.codex/sessions/", suffix: ".jsonl"),
              let sessionID = firstUUID(in: transcriptPath) else {
            return nil
        }

        return ProcessSnapshot(
            tool: .codex,
            sessionID: sessionID,
            workingDirectory: workingDirectory(from: lsofOutput),
            terminalTTY: process.terminalTTY,
            terminalApp: terminalApp(for: process, processesByPID: processesByPID)
        )
    }

    private func isClaudeSubagentWorktree(_ path: String) -> Bool {
        path.contains("/.claude/worktrees/agent-")
    }

    private func claudeSnapshot(
        for process: RunningProcess,
        processesByPID: [String: RunningProcess]
    ) -> ProcessSnapshot? {
        let lsofOutput = lsofOutput(pid: process.pid)
        let workingDirectory = lsofOutput.flatMap(workingDirectory(from:))

        // Subagent processes run in .claude/worktrees/agent-*/ directories.
        // They are tracked as metadata on the parent session, not as separate sessions.
        if let cwd = workingDirectory, isClaudeSubagentWorktree(cwd) {
            return nil
        }

        let transcriptPath = lsofOutput.flatMap {
            bestClaudeTranscriptPath(in: $0, workingDirectory: workingDirectory)
        }
        let sessionID = transcriptPath.flatMap(firstUUID(in:))
            ?? claudeSessionID(from: process.command)

        guard workingDirectory != nil || sessionID != nil else {
            return nil
        }

        return ProcessSnapshot(
            tool: .claudeCode,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            terminalTTY: process.terminalTTY,
            terminalApp: terminalApp(for: process, processesByPID: processesByPID),
            transcriptPath: transcriptPath
        )
    }

    private func bestClaudeTranscriptPath(in lsofOutput: String, workingDirectory: String?) -> String? {
        let paths = allMatchingPaths(in: lsofOutput, containing: "/.claude/projects/", suffix: ".jsonl")
        guard !paths.isEmpty else {
            return nil
        }

        if paths.count == 1 {
            return paths[0]
        }

        if let cwd = workingDirectory {
            let encodedCWD = cwd.replacingOccurrences(of: "/", with: "-")
            if let preferred = paths.first(where: { $0.contains(encodedCWD) }) {
                return preferred
            }
        }

        return paths.first
    }

    private func allMatchingPaths(in lsofOutput: String, containing fragment: String, suffix: String) -> [String] {
        var results: [String] = []
        for line in lsofOutput.split(whereSeparator: \.isNewline) {
            guard line.first == "n" else {
                continue
            }

            let value = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.contains(fragment), value.hasSuffix(suffix) else {
                continue
            }

            results.append(value)
        }

        return results
    }

    private func terminalApp(
        for process: RunningProcess,
        processesByPID: [String: RunningProcess]
    ) -> String? {
        var currentParentPID = process.parentPID
        var visited: Set<String> = []

        while !currentParentPID.isEmpty,
              currentParentPID != "0",
              currentParentPID != "1",
              visited.insert(currentParentPID).inserted,
              let parent = processesByPID[currentParentPID] {
            if let terminalApp = recognizedTerminalApp(for: parent.command) {
                return terminalApp
            }

            currentParentPID = parent.parentPID
        }

        return nil
    }

    private func recognizedTerminalApp(for command: String) -> String? {
        let lowered = command.lowercased()

        if lowered.contains("/cmux.app/contents/macos/cmux") {
            return "cmux"
        }

        if lowered.contains("/ghostty.app/contents/macos/ghostty") || lowered.hasSuffix("/ghostty") {
            return "Ghostty"
        }

        if lowered.contains("/terminal.app/contents/macos/terminal") {
            return "Terminal"
        }

        if lowered.contains("/iterm.app/contents/macos/iterm2") {
            return "iTerm"
        }

        if lowered.contains("/kaku.app/contents/macos/kaku-gui") || lowered.hasSuffix("/kaku-gui") {
            return "Kaku"
        }

        if lowered.contains("/wezterm.app/contents/macos/wezterm-gui") || lowered.hasSuffix("/wezterm-gui") {
            return "WezTerm"
        }

        if lowered.contains("/warp.app/") || lowered.hasSuffix("/warp") {
            return "Warp"
        }

        if lowered.hasSuffix("/zellij") {
            return "Zellij"
        }

        // VS Code family
        if lowered.contains("/visual studio code.app/") || lowered.contains("/code helper") {
            return "VS Code"
        }
        if lowered.contains("/visual studio code - insiders.app/") {
            return "VS Code Insiders"
        }
        if lowered.contains("/cursor.app/") {
            return "Cursor"
        }
        if lowered.contains("/windsurf.app/") {
            return "Windsurf"
        }
        if lowered.contains("/trae.app/") {
            return "Trae"
        }

        // JetBrains IDEs
        if lowered.contains("/intellij idea.app/") || lowered.contains("/idea.app/") {
            return "IntelliJ IDEA"
        }
        if lowered.contains("/webstorm.app/") {
            return "WebStorm"
        }
        if lowered.contains("/pycharm.app/") {
            return "PyCharm"
        }
        if lowered.contains("/goland.app/") {
            return "GoLand"
        }
        if lowered.contains("/clion.app/") {
            return "CLion"
        }
        if lowered.contains("/rubymine.app/") {
            return "RubyMine"
        }
        if lowered.contains("/phpstorm.app/") {
            return "PhpStorm"
        }
        if lowered.contains("/rider.app/") {
            return "Rider"
        }
        if lowered.contains("/rustrover.app/") {
            return "RustRover"
        }

        return nil
    }

    private func lsofOutput(pid: String) -> String? {
        commandRunner("/usr/sbin/lsof", ["-a", "-p", pid, "-Fn"])
    }

    private func workingDirectory(from lsofOutput: String) -> String? {
        let lines = lsofOutput.split(whereSeparator: \.isNewline).map(String.init)
        for index in lines.indices {
            guard lines[index] == "fcwd",
                  lines.indices.contains(index + 1) else {
                continue
            }

            let nextLine = lines[index + 1]
            guard nextLine.first == "n" else {
                continue
            }

            let value = String(nextLine.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("/") {
                return value
            }
        }

        return nil
    }

    private func matchingPath(in lsofOutput: String, containing fragment: String, suffix: String) -> String? {
        for line in lsofOutput.split(whereSeparator: \.isNewline) {
            guard line.first == "n" else {
                continue
            }

            let value = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.contains(fragment), value.hasSuffix(suffix) else {
                continue
            }

            return value
        }

        return nil
    }

    private func firstUUID(in text: String) -> String? {
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }

        return String(text[matchRange]).lowercased()
    }

    private func claudeSessionID(from command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else {
            return nil
        }

        for index in tokens.indices {
            let token = tokens[index]

            if token == "--resume" || token == "-r" || token == "--session-id" {
                let nextIndex = tokens.index(after: index)
                guard tokens.indices.contains(nextIndex) else {
                    continue
                }

                if let sessionID = firstUUID(in: tokens[nextIndex]) {
                    return sessionID
                }
            }

            if token.hasPrefix("--resume=") || token.hasPrefix("--session-id=") {
                let value = String(token.split(separator: "=", maxSplits: 1).last ?? "")
                if let sessionID = firstUUID(in: value) {
                    return sessionID
                }
            }
        }

        return nil
    }

    private func normalizedTTY(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "??" else {
            return nil
        }

        if trimmed.hasPrefix("/dev/") {
            return trimmed
        }

        return "/dev/\(trimmed)"
    }

    private func isCodexProcess(command: String) -> Bool {
        let lowered = command.lowercased()
        guard let firstToken = lowered.split(separator: " ").first.map(String.init) else {
            return false
        }

        return firstToken == "codex"
            || firstToken.hasSuffix("/codex")
            || lowered.contains("/codex/codex")
    }

    /// Detect Codex running as a native macOS app bundle.
    private func isCodexNativeAppProcess(command: String) -> Bool {
        let lowered = command.lowercased()
        return lowered.contains("/codex.app/contents/")
    }

    private func isOpenCodeProcess(command: String) -> Bool {
        let lowered = command.lowercased()
        return lowered.contains("/opencode-ai/") || lowered.contains("/opencode")
            || lowered.contains("/.opencode")
    }

    private func isClaudeProcess(command: String) -> Bool {
        let lowered = command.lowercased()
        if lowered.contains("/.local/bin/claude") {
            return true
        }

        guard let firstToken = lowered.split(separator: " ").first else {
            return false
        }

        return firstToken == "claude"
    }

    private static func commandOutput(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        let completionGroup = DispatchGroup()
        completionGroup.enter()
        process.terminationHandler = { _ in
            completionGroup.leave()
        }
        let outputGroup = DispatchGroup()
        outputGroup.enter()
        let outputBox = OutputBox()
        DispatchQueue.global(qos: .utility).async {
            outputBox.data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputGroup.leave()
        }
        let timeout: TimeInterval = executablePath.hasSuffix("/lsof")
            ? Self.lsofCommandTimeout
            : Self.processCommandTimeout

        do {
            try process.run()
        } catch {
            return nil
        }

        let waitResult = completionGroup.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            process.terminate()
            _ = completionGroup.wait(timeout: .now() + 0.1)
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        _ = outputGroup.wait(timeout: .now() + 0.1)
        guard let output = String(data: outputBox.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        return output
    }
}
