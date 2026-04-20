import Foundation
import AgentDeckCore

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
        guard session.phase == .completed else { return false }
        guard let target = session.jumpTarget else { return false }

        // tmux sessions: any terminal can receive send-keys.
        if target.tmuxTarget != nil { return true }

        // Ghostty: native AppleScript input text (1.3.0+).
        let app = target.terminalApp.lowercased()
        if app == "ghostty" { return true }

        return false
    }

    // MARK: - Send

    /// Send `text` followed by Enter to the terminal that owns `session`.
    /// Returns `true` on success.
    @discardableResult
    static func send(_ text: String, to session: AgentSession) -> Bool {
        guard let target = session.jumpTarget else { return false }

        // Prefer tmux when available — it targets a specific pane without
        // needing to activate/focus the terminal window.
        if let tmuxTarget = target.tmuxTarget {
            return sendViaTmux(text, tmuxTarget: tmuxTarget, socketPath: target.tmuxSocketPath)
        }

        let app = target.terminalApp.lowercased()
        if app == "ghostty" {
            return sendViaGhostty(text, target: target)
        }

        return false
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
            NSLog("[AgentDeck] TerminalTextSender: AppleScript compilation failed")
            return false
        }
        let result = appleScript.executeAndReturnError(&error)
        if let error {
            NSLog("[AgentDeck] TerminalTextSender AppleScript error: %@", String(describing: error))
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
