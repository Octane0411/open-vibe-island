import Darwin
import Foundation
import OpenIslandCore

/// Sends reply text to a terminal where an agent session is running.
///
/// Currently supported:
/// - **tmux**: `tmux send-keys -l "text" Enter`
/// - **Ghostty**: AppleScript `input text` (requires Automation permission)
/// - **iTerm2**: AppleScript `write text`
/// - **Terminal.app**: System Events keystroke (after activate)
///
/// The static ``canReply(to:)`` method gates the UI — the reply input field
/// is only shown when the session's phase wants user input AND the host
/// terminal supports text injection.
struct TerminalTextSender {

    static let supportedNonTmuxTerminalApps: Set<String> = [
        "ghostty",
        "iterm2",
        "iterm",
        "terminal",
        "cmux",
    ]

    static let phasesAcceptingReply: Set<SessionPhase> = [
        .completed,
        .waitingForAnswer,
        .waitingForApproval,
    ]

    // MARK: - Capability check

    static func canReply(to session: AgentSession, enabled: Bool) -> Bool {
        guard enabled else { return false }
        guard phasesAcceptingReply.contains(session.phase) else { return false }
        guard let target = session.jumpTarget else { return false }

        // tmux sessions: any terminal can receive send-keys.
        if target.tmuxTarget != nil { return true }

        let app = target.terminalApp.lowercased()
        return supportedNonTmuxTerminalApps.contains(app)
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

        switch target.terminalApp.lowercased() {
        case "ghostty":
            return sendViaGhostty(text, target: target)
        case "iterm2", "iterm":
            return sendViaITerm2(text, target: target)
        case "terminal":
            return sendViaTerminalApp(text, target: target)
        case "cmux":
            return sendViaCmux(text, target: target)
        default:
            return false
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

    // MARK: - cmux

    /// cmux native (no tmux backend): cmux's RPC exposes `surface.focus` and
    /// `surface.list` but no text-write method, so we focus the target tab
    /// via the socket then drive a System Events keystroke. Use `set
    /// frontmost of process "cmux"` instead of plain `activate` because the
    /// notch panel may still hold the key window after the user submits;
    /// `set frontmost` forces window focus to cmux regardless of who held
    /// it last.
    private static func sendViaCmux(_ text: String, target: JumpTarget) -> Bool {
        if let surfaceID = target.terminalSessionID, !surfaceID.isEmpty {
            _ = sendCmuxSurfaceFocus(surfaceID: surfaceID)
        }

        let escapedText = escapeAppleScript(text)
        let script = """
        tell application "System Events"
            if not (exists process "cmux") then return "error"
            set frontmost of process "cmux" to true
            delay 0.25
            keystroke "\(escapedText)"
            key code 36
        end tell
        return "ok"
        """
        return runAppleScript(script)
    }

    private static func sendCmuxSurfaceFocus(surfaceID: String) -> Bool {
        let candidates = [
            (try? String(contentsOfFile: "/tmp/cmux-last-socket-path", encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            NSHomeDirectory() + "/Library/Application Support/cmux/cmux.sock",
            "/tmp/cmux.sock",
        ].compactMap { $0 }.filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }

        guard let socketPath = candidates.first else { return false }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { sunPath in
            for (i, byte) in pathBytes.enumerated() {
                sunPath[i] = UInt8(bitPattern: byte)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return false }

        let request = #"{"jsonrpc":"2.0","method":"surface.focus","params":{"surface_id":"\#(surfaceID)"},"id":1}"# + "\n"
        let sent = request.withCString { ptr in
            Darwin.send(fd, ptr, strlen(ptr), 0)
        }
        return sent > 0
    }

    // MARK: - iTerm2

    private static func sendViaITerm2(_ text: String, target: JumpTarget) -> Bool {
        let escapedText = escapeAppleScript(text)
        let script = """
        tell application "iTerm2"
            if not (it is running) then return "error"
            activate
            tell current session of current window
                write text "\(escapedText)"
            end tell
            return "ok"
        end tell
        """
        return runAppleScript(script)
    }

    // MARK: - Terminal.app

    private static func sendViaTerminalApp(_ text: String, target: JumpTarget) -> Bool {
        // Terminal.app's native AppleScript only exposes `do script` (which
        // runs the text as a command in a new tab if no target is given).
        // Activate the app first, then drive a keystroke through System
        // Events to inject the text into the front window's selected tab.
        let escapedText = escapeAppleScript(text)
        let script = """
        tell application "Terminal"
            if not (it is running) then return "error"
            activate
        end tell
        delay 0.05
        tell application "System Events"
            keystroke "\(escapedText)"
            key code 36
        end tell
        return "ok"
        """
        return runAppleScript(script)
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
