import Foundation
import OpenIslandCore

/// Sends reply text to a terminal where an agent session is running.
///
/// Currently supported:
/// - **tmux**: `tmux send-keys -l "text" Enter`
/// - **Ghostty**: AppleScript `input text` (requires Automation permission)
///
/// The static ``canReply(to:)`` method gates the UI — the reply input field
/// is only shown when the session's terminal supports text injection.
struct TerminalTextSender {

    // MARK: - Capability check

    static func canReply(to session: AgentSession, enabled: Bool) -> Bool {
        guard enabled else { return false }
        guard let target = session.jumpTarget else { return false }

        // tmux sessions: any terminal can receive send-keys.
        if target.tmuxTarget != nil { return true }

        // Ghostty: native AppleScript input text (1.3.0+).
        let app = target.terminalApp.lowercased()
        if app == "ghostty" { return true }

        return false
    }

    /// Whether chat messages can be sent to this session's terminal.
    /// Same as canReply but without the feature flag requirement.
    /// Also checks if tmux is available even without jumpTarget.
    static func canChat(to session: AgentSession) -> Bool {
        // If we have a jumpTarget with tmux or Ghostty, we can chat
        if let target = session.jumpTarget {
            if target.tmuxTarget != nil { return true }
            if target.terminalApp.lowercased() == "ghostty" { return true }
        }

        // Fallback: check if tmux is available (for sessions without jumpTarget)
        if resolveTmuxPath() != nil { return true }

        return false
    }

    // MARK: - Send

    /// Send `text` followed by Enter to the terminal that owns `session`.
    /// Returns `true` on success.
    @discardableResult
    static func send(_ text: String, to session: AgentSession) -> Bool {
        // Try jumpTarget first
        if let target = session.jumpTarget {
            // Prefer tmux when available — it targets a specific pane without
            // needing to activate/focus the terminal window.
            if let tmuxTarget = target.tmuxTarget {
                return sendViaTmux(text, tmuxTarget: tmuxTarget, socketPath: target.tmuxSocketPath)
            }

            let app = target.terminalApp.lowercased()
            if app == "ghostty" {
                return sendViaGhostty(text, target: target)
            }
        }

        // Fallback: try to find tmux target via working directory
        if let tmuxPath = resolveTmuxPath(),
           let cwd = workingDirectory(for: session) {
            if let tmuxTarget = findTmuxTarget(tmuxPath: tmuxPath, workingDirectory: cwd) {
                return sendViaTmux(text, tmuxTarget: tmuxTarget, socketPath: nil)
            }
        }

        return false
    }

    /// Derives the working directory from the session's transcript path.
    private static func workingDirectory(for session: AgentSession) -> String? {
        guard let transcriptPath = session.trackingTranscriptPath else { return nil }
        // Path format: ~/.claude/projects/<workspace>/<session_id>.jsonl
        let path = transcriptPath
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "")
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        // Find "projects" and take the next component as workspace
        if let projectsIndex = components.firstIndex(of: "projects"),
           projectsIndex + 1 < components.count {
            let workspace = components[projectsIndex + 1]
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("projects")
                .appendingPathComponent(workspace)
                .path
        }
        return nil
    }

    /// Finds a tmux target pane matching the given working directory.
    private static func findTmuxTarget(tmuxPath: String, workingDirectory: String) -> String? {
        let result = runProcessWithOutput(tmuxPath, arguments: [
            "list-panes", "-a", "-F",
            "#{session_name}:#{window_index}.#{pane_index} #{pane_current_path}"
        ])

        guard result.exitCode == 0 else { return nil }

        let lines = result.output.components(separatedBy: "\n")
        for line in lines {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " ")
            guard parts.count >= 2 else { continue }
            let target = parts[0]
            let panePath = parts[1...].joined(separator: " ")

            if panePath == workingDirectory {
                return target
            }
        }
        return nil
    }

    private static func runProcessWithOutput(_ path: String, arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (-1, "")
        }
    }

    // MARK: - tmux

    private static func sendViaTmux(_ text: String, tmuxTarget: String, socketPath: String?) -> Bool {
        guard let tmuxPath = resolveTmuxPath() else { return false }

        var baseArgs: [String] = []
        if let socketPath, !socketPath.isEmpty {
            baseArgs = ["-S", socketPath]
        }

        // Send the literal text (no Enter yet).
        let textResult = runProcess(tmuxPath, arguments: baseArgs + ["send-keys", "-t", tmuxTarget, "-l", text])
        guard textResult else { return false }

        // Send Enter as a separate command.
        return runProcess(tmuxPath, arguments: baseArgs + ["send-keys", "-t", tmuxTarget, "Enter"])
    }

    // MARK: - Ghostty

    private static func sendViaGhostty(_ text: String, target: JumpTarget) -> Bool {
        // Build an AppleScript that:
        //   1. Finds the correct terminal (by session id, working directory, or name)
        //   2. Focuses it
        //   3. Sends the reply text + newline via `input text`
        let script = ghosttySendScript(text: text, target: target)
        return runAppleScript(script)
    }

    private static func ghosttySendScript(text: String, target: JumpTarget) -> String {
        let terminalSessionID = escapeAppleScript(target.terminalSessionID)
        let workingDirectory = escapeAppleScript(target.workingDirectory)
        let paneTitle = escapeAppleScript(target.paneTitle)
        let escapedText = escapeAppleScript(text)

        return """
        tell application "Ghostty"
            if not (it is running) then return "error"

            set targetTerminal to missing value

            -- Match by terminal session ID (most precise)
            if "\(terminalSessionID)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (id of aTerminal as text) is "\(terminalSessionID)" then
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if

            -- Fallback: match by working directory
            if targetTerminal is missing value and "\(workingDirectory)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (working directory of aTerminal as text) is "\(workingDirectory)" then
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if

            -- Fallback: match by pane title
            if targetTerminal is missing value and "\(paneTitle)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (name of aTerminal as text) contains "\(paneTitle)" then
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if

            if targetTerminal is missing value then return "error"

            -- Send the text, then press Enter as a separate key event.
            -- `input text` sends characters; `send key` simulates a key press.
            input text "\(escapedText)" to targetTerminal
            send key "enter" to targetTerminal
            return "ok"
        end tell
        """
    }

    // MARK: - Helpers

    private static func escapeAppleScript(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ script: String) -> Bool {
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            NSLog("[OpenIsland] TerminalTextSender: AppleScript compilation failed")
            return false
        }
        let result = appleScript.executeAndReturnError(&error)
        if let error {
            NSLog("[OpenIsland] TerminalTextSender AppleScript error: %@", String(describing: error))
            return false
        }
        return result.stringValue == "ok"
    }

    private static func resolveTmuxPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback: `which tmux`
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["tmux"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let output, FileManager.default.isExecutableFile(atPath: output) {
                return output
            }
        } catch {}
        return nil
    }

    @discardableResult
    private static func runProcess(_ path: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
