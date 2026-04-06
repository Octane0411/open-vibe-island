import AppKit
import Foundation
import OpenIslandCore

struct TerminalJumpService {
    enum HostApprovalResponse {
        case accept
        case acceptAndDontAsk
        case reject

        var usesGhosttyEscAction: Bool {
            if case .reject = self {
                return true
            }
            return false
        }

        var ghosttyKey: String {
            switch self {
            case .accept:
                return "a"
            case .acceptAndDontAsk:
                return "p"
            case .reject:
                return "esc"
            }
        }

        var terminalInput: String? {
            switch self {
            case .accept:
                return "a"
            case .acceptAndDontAsk:
                return "p"
            case .reject:
                return "n"
            }
        }

        var statusLabel: String {
            switch self {
            case .accept:
                return "accepted"
            case .acceptAndDontAsk:
                return "accepted with don't-ask preference"
            case .reject:
                return "rejected"
            }
        }
    }

    typealias ApplicationResolver = @Sendable (String) -> URL?
    typealias AppRunningChecker = @Sendable (String) -> Bool
    typealias OpenAction = @Sendable ([String]) throws -> Void
    typealias AppleScriptRunner = @Sendable (String) throws -> String

    private struct TerminalAppDescriptor {
        let displayName: String
        let bundleIdentifier: String
        let aliases: [String]
    }

    private static let knownApps: [TerminalAppDescriptor] = [
        TerminalAppDescriptor(
            displayName: "iTerm",
            bundleIdentifier: "com.googlecode.iterm2",
            aliases: ["iterm", "iterm2", "iterm.app"]
        ),
        TerminalAppDescriptor(
            displayName: "cmux",
            bundleIdentifier: "com.cmuxterm.app",
            aliases: ["cmux"]
        ),
        TerminalAppDescriptor(
            displayName: "Ghostty",
            bundleIdentifier: "com.mitchellh.ghostty",
            aliases: ["ghostty"]
        ),
        TerminalAppDescriptor(
            displayName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            aliases: ["terminal", "apple_terminal"]
        ),
        TerminalAppDescriptor(
            displayName: "Warp",
            bundleIdentifier: "dev.warp.Warp-Stable",
            aliases: ["warp", "warpterminal"]
        ),
        TerminalAppDescriptor(
            displayName: "WezTerm",
            bundleIdentifier: "com.github.wez.wezterm",
            aliases: ["wezterm"]
        ),
    ]

    private static let ghosttyFocusSettleDelay = 0.08
    private static let ghosttyWindowActivationDelay = 0.04
    private static let ghosttyFocusAttempts = 3

    private let applicationResolver: ApplicationResolver
    private let appRunningChecker: AppRunningChecker
    private let openAction: OpenAction
    private let appleScriptRunner: AppleScriptRunner

    init(
        applicationResolver: @escaping ApplicationResolver = { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        },
        appRunningChecker: @escaping AppRunningChecker = { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
        },
        openAction: @escaping OpenAction = Self.defaultOpenAction(arguments:),
        appleScriptRunner: @escaping AppleScriptRunner = Self.defaultAppleScriptRunner(script:)
    ) {
        self.applicationResolver = applicationResolver
        self.appRunningChecker = appRunningChecker
        self.openAction = openAction
        self.appleScriptRunner = appleScriptRunner
    }

    func jump(to target: JumpTarget) throws -> String {
        let descriptor = resolveTerminalApp(preferredName: target.terminalApp)
        let hasWorkingDirectory = target.workingDirectory.map { FileManager.default.fileExists(atPath: $0) } ?? false
        let hasPreciseLocator = [target.terminalSessionID, target.terminalTTY].contains {
            guard let value = $0?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !value.isEmpty
        }
        let appIsRunning = descriptor.map { appRunningChecker($0.bundleIdentifier) } ?? false

        if let descriptor {
            switch descriptor.bundleIdentifier {
            case "com.googlecode.iterm2":
                if try jumpToITermSession(target) {
                    return "Focused the matching iTerm session."
                }
            case "com.cmuxterm.app":
                if jumpToCmuxTerminal(target) {
                    return "Focused the matching cmux terminal."
                }
            case "com.mitchellh.ghostty":
                if try jumpToGhosttyTerminal(target) {
                    return "Focused the matching Ghostty terminal."
                }
            case "com.apple.Terminal":
                if try jumpToTerminalTab(target) {
                    return "Focused the matching Terminal tab."
                }
            default:
                break
            }
        }

        if let descriptor, hasPreciseLocator, appIsRunning {
            try openAction(["-b", descriptor.bundleIdentifier])
            return "Activated \(descriptor.displayName). Exact pane targeting could not find the live terminal."
        }

        if let descriptor, hasWorkingDirectory, let workingDirectory = target.workingDirectory {
            try openAction(["-b", descriptor.bundleIdentifier, workingDirectory])
            return "Opened \(target.workspaceName) in \(descriptor.displayName). Exact pane targeting is still best-effort."
        }

        if let descriptor {
            try openAction(["-b", descriptor.bundleIdentifier])
            return "Activated \(descriptor.displayName). Exact pane targeting is still best-effort."
        }

        if hasWorkingDirectory, let workingDirectory = target.workingDirectory {
            try openAction([workingDirectory])
            return "Opened \(target.workspaceName) in Finder because no supported terminal app could be resolved."
        }

        throw TerminalJumpError.unsupportedTerminal(target.terminalApp)
    }

    func submitHostApproval(on target: JumpTarget, response: HostApprovalResponse) throws -> String {
        guard try sendHostApprovalWithoutActivation(to: target, response: response) else {
            throw TerminalJumpError.appleScriptFailed("Unable to submit host approval input without changing focus.")
        }
        return "Submitted \(response.statusLabel) input in \(target.terminalApp)."
    }

    private func sendHostApprovalWithoutActivation(
        to target: JumpTarget,
        response: HostApprovalResponse
    ) throws -> Bool {
        guard let descriptor = resolveTerminalApp(preferredName: target.terminalApp) else {
            return false
        }

        switch descriptor.bundleIdentifier {
        case "com.mitchellh.ghostty":
            return try sendHostApprovalToGhosttyTerminal(target, response: response)
        case "com.apple.Terminal":
            return try sendHostApprovalToTerminalTab(target, response: response)
        case "com.googlecode.iterm2":
            return try sendHostApprovalToITermSession(target, response: response)
        default:
            return false
        }
    }

    private func sendHostApprovalToGhosttyTerminal(
        _ target: JumpTarget,
        response: HostApprovalResponse
    ) throws -> Bool {
        let terminalSessionID = escapeAppleScript(target.terminalSessionID)
        let workingDirectory = escapeAppleScript(target.workingDirectory)
        let paneTitle = escapeAppleScript(target.paneTitle)
        let decisionKey = response.ghosttyKey
        let useEscAction = response.usesGhosttyEscAction

        let script = """
        tell application "Ghostty"
            if not (it is running) then return ""

            set targetTerminal to missing value

            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aTerminal in terminals of aTab
                        if "\(terminalSessionID)" is not "" and (id of aTerminal as text) is "\(terminalSessionID)" then
                            set targetTerminal to aTerminal
                            exit repeat
                        end if
                    end repeat

                    if targetTerminal is not missing value then
                        exit repeat
                    end if
                end repeat

                if targetTerminal is not missing value then
                    exit repeat
                end if
            end repeat

            if targetTerminal is missing value and "\(workingDirectory)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (working directory of aTerminal as text) is "\(workingDirectory)" then
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat

                        if targetTerminal is not missing value then
                            exit repeat
                        end if
                    end repeat

                    if targetTerminal is not missing value then
                        exit repeat
                    end if
                end repeat
            end if

            if targetTerminal is missing value and "\(paneTitle)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (name of aTerminal as text) contains "\(paneTitle)" then
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat

                        if targetTerminal is not missing value then
                            exit repeat
                        end if
                    end repeat

                    if targetTerminal is not missing value then
                        exit repeat
                    end if
                end repeat
            end if

            if targetTerminal is missing value then
                try
                    set targetTerminal to focused terminal of selected tab of front window
                end try
            end if

            if targetTerminal is missing value then return ""

            if \(useEscAction ? "true" : "false") then
                try
                    perform action "esc" on targetTerminal
                on error
                    try
                        send key "escape" to targetTerminal
                    on error
                        send key "n" to targetTerminal
                    end try
                end try
            else
                send key "\(decisionKey)" to targetTerminal
            end if
            return "submitted"
        end tell
        return ""
        """

        return try runAppleScript(script) == "submitted"
    }

    private func sendHostApprovalToTerminalTab(
        _ target: JumpTarget,
        response: HostApprovalResponse
    ) throws -> Bool {
        guard let decisionToken = response.terminalInput else {
            return false
        }
        let terminalTTY = escapeAppleScript(target.terminalTTY)
        let paneTitle = escapeAppleScript(target.paneTitle)

        let script = """
        tell application "Terminal"
            if not (it is running) then return ""
            set targetTab to missing value
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    if "\(terminalTTY)" is not "" and (tty of aTab as text) is "\(terminalTTY)" then
                        set targetTab to aTab
                        exit repeat
                    end if
                    if "\(paneTitle)" is not "" and (custom title of aTab as text) contains "\(paneTitle)" then
                        set targetTab to aTab
                        exit repeat
                    end if
                end repeat
                if targetTab is not missing value then exit repeat
            end repeat

            if targetTab is missing value then
                try
                    set targetTab to selected tab of front window
                end try
            end if

            if targetTab is missing value then return ""

            do script "\(decisionToken)" in targetTab
            return "submitted"
        end tell
        return ""
        """

        return try runAppleScript(script) == "submitted"
    }

    private func sendHostApprovalToITermSession(
        _ target: JumpTarget,
        response: HostApprovalResponse
    ) throws -> Bool {
        guard let decisionToken = response.terminalInput else {
            return false
        }
        let script = """
        tell application "iTerm"
            if not (it is running) then return ""
            set targetSession to missing value
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if "\(escapeAppleScript(target.terminalSessionID))" is not "" and (id of aSession as text) is "\(escapeAppleScript(target.terminalSessionID))" then
                            set targetSession to aSession
                            exit repeat
                        end if
                        if "\(escapeAppleScript(target.terminalTTY))" is not "" and (tty of aSession as text) is "\(escapeAppleScript(target.terminalTTY))" then
                            set targetSession to aSession
                            exit repeat
                        end if
                    end repeat
                    if targetSession is not missing value then exit repeat
                end repeat
                if targetSession is not missing value then exit repeat
            end repeat

            if targetSession is missing value then
                try
                    set targetSession to current session of current window
                end try
            end if

            if targetSession is missing value then return ""

            tell targetSession to write text "\(decisionToken)"
            return "submitted"
        end tell
        return ""
        """

        return try runAppleScript(script) == "submitted"
    }

    private func jumpToITermSession(_ target: JumpTarget) throws -> Bool {
        let script = """
        tell application "iTerm"
            if not (it is running) then return ""
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if "\(escapeAppleScript(target.terminalSessionID))" is not "" and (id of aSession as text) is "\(escapeAppleScript(target.terminalSessionID))" then
                            select aSession
                            return "matched"
                        end if
                        if "\(escapeAppleScript(target.terminalTTY))" is not "" and (tty of aSession as text) is "\(escapeAppleScript(target.terminalTTY))" then
                            select aSession
                            return "matched"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return ""
        """

        return try runAppleScript(script) == "matched"
    }

    private func jumpToCmuxTerminal(_ target: JumpTarget) -> Bool {
        // Try the cmux Unix socket API to focus a specific surface.
        guard let surfaceID = target.terminalSessionID,
              !surfaceID.isEmpty else {
            // No surface ID — fall back to generic app activation.
            return false
        }

        guard let socketPath = Self.resolveCmuxSocketPath() else {
            return false
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        precondition(pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path))
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

        // Send JSON-RPC surface.focus request.
        let request = #"{"jsonrpc":"2.0","method":"surface.focus","params":{"surface_id":"\#(surfaceID)"},"id":1}"# + "\n"
        let sent = request.withCString { ptr in
            Darwin.send(fd, ptr, strlen(ptr), 0)
        }
        guard sent > 0 else { return false }

        // Best-effort: activate the cmux app window.
        try? openAction(["-b", "com.cmuxterm.app"])

        return true
    }

    private static func resolveCmuxSocketPath() -> String? {
        let fm = FileManager.default

        // 1. cmux writes the active socket path here on startup.
        if let redirected = try? String(contentsOfFile: "/tmp/cmux-last-socket-path", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !redirected.isEmpty,
           fm.fileExists(atPath: redirected) {
            return redirected
        }

        // 2. Standard Application Support location.
        let appSupportPath = NSHomeDirectory() + "/Library/Application Support/cmux/cmux.sock"
        if fm.fileExists(atPath: appSupportPath) {
            return appSupportPath
        }

        // 3. Legacy fallback.
        let legacyPath = "/tmp/cmux.sock"
        if fm.fileExists(atPath: legacyPath) {
            return legacyPath
        }

        return nil
    }

    private func jumpToGhosttyTerminal(_ target: JumpTarget) throws -> Bool {
        try runAppleScript(ghosttyJumpScript(for: target)) == "matched"
    }

    func ghosttyJumpScript(for target: JumpTarget) -> String {
        let terminalSessionID = escapeAppleScript(target.terminalSessionID)
        let workingDirectory = escapeAppleScript(target.workingDirectory)
        let paneTitle = escapeAppleScript(target.paneTitle)

        return """
        tell application "Ghostty"
            if not (it is running) then return ""
            activate

            set targetWindow to missing value
            set targetTab to missing value
            set targetTerminal to missing value

            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aTerminal in terminals of aTab
                        if "\(terminalSessionID)" is not "" and (id of aTerminal as text) is "\(terminalSessionID)" then
                            set targetWindow to aWindow
                            set targetTab to aTab
                            set targetTerminal to aTerminal
                            exit repeat
                        end if
                    end repeat

                    if targetTerminal is not missing value then
                        exit repeat
                    end if
                end repeat

                if targetTerminal is not missing value then
                    exit repeat
                end if
            end repeat

            if targetTerminal is missing value and "\(workingDirectory)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (working directory of aTerminal as text) is "\(workingDirectory)" then
                                set targetWindow to aWindow
                                set targetTab to aTab
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat

                        if targetTerminal is not missing value then
                            exit repeat
                        end if
                    end repeat

                    if targetTerminal is not missing value then
                        exit repeat
                    end if
                end repeat
            end if

            if targetTerminal is missing value and "\(paneTitle)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (name of aTerminal as text) contains "\(paneTitle)" then
                                set targetWindow to aWindow
                                set targetTab to aTab
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat

                        if targetTerminal is not missing value then
                            exit repeat
                        end if
                    end repeat

                    if targetTerminal is not missing value then
                        exit repeat
                    end if
                end repeat
            end if

            if targetTerminal is missing value then return ""

            if "\(terminalSessionID)" is "" then
                if targetWindow is not missing value then
                    activate window targetWindow
                    delay \(Self.ghosttyWindowActivationDelay)
                end if

                if targetTab is not missing value then
                    select tab targetTab
                    delay \(Self.ghosttyWindowActivationDelay)
                end if

                focus targetTerminal
                delay \(Self.ghosttyFocusSettleDelay)
                return "matched"
            end if

            repeat \(Self.ghosttyFocusAttempts) times
                if targetWindow is not missing value then
                    activate window targetWindow
                    delay \(Self.ghosttyWindowActivationDelay)
                end if

                if targetTab is not missing value then
                    select tab targetTab
                    delay \(Self.ghosttyWindowActivationDelay)
                end if

                focus targetTerminal
                -- Ghostty updates the focused split asynchronously after focus returns.
                delay \(Self.ghosttyFocusSettleDelay)

                try
                    if (id of focused terminal of selected tab of front window as text) is "\(terminalSessionID)" then
                        return "matched"
                    end if
                end try
            end repeat
        end tell
        return ""
        """
    }

    private func jumpToTerminalTab(_ target: JumpTarget) throws -> Bool {
        let script = """
        tell application "Terminal"
            if not (it is running) then return ""
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    if "\(escapeAppleScript(target.terminalTTY))" is not "" and (tty of aTab as text) is "\(escapeAppleScript(target.terminalTTY))" then
                        set selected of aTab to true
                        set frontmost of aWindow to true
                        return "matched"
                    end if
                    if "\(escapeAppleScript(target.paneTitle))" is not "" and (custom title of aTab as text) contains "\(escapeAppleScript(target.paneTitle))" then
                        set selected of aTab to true
                        set frontmost of aWindow to true
                        return "matched"
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """

        return try runAppleScript(script) == "matched"
    }

    private func resolveTerminalApp(preferredName: String) -> TerminalAppDescriptor? {
        let normalized = preferredName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let exact = Self.knownApps.first(where: { descriptor in
            descriptor.displayName.lowercased() == normalized || descriptor.aliases.contains(normalized)
        }) {
            return exact
        }

        return Self.knownApps.first(where: { isInstalled(bundleIdentifier: $0.bundleIdentifier) })
    }

    private func isInstalled(bundleIdentifier: String) -> Bool {
        applicationResolver(bundleIdentifier) != nil
    }

    private func runAppleScript(_ script: String) throws -> String {
        try appleScriptRunner(script)
    }

    private static func defaultOpenAction(arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = arguments

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw TerminalJumpError.openFailed(arguments)
        }
    }

    private static func defaultAppleScriptRunner(script: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        try task.run()
        task.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard task.terminationStatus == 0 else {
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw TerminalJumpError.appleScriptFailed(stderr.isEmpty ? script : stderr)
        }

        return output
    }

    private func escapeAppleScript(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum TerminalJumpError: Error, LocalizedError {
    case unsupportedTerminal(String)
    case openFailed([String])
    case appleScriptFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedTerminal(terminal):
            "Could not resolve a supported terminal app for \(terminal)."
        case let .openFailed(arguments):
            "Failed to launch terminal with arguments: \(arguments.joined(separator: " "))"
        case let .appleScriptFailed(message):
            "Terminal automation failed: \(message)"
        }
    }
}
