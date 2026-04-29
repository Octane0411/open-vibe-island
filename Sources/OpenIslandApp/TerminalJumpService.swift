import AppKit
import Foundation
import OpenIslandCore

struct TerminalJumpService {
    typealias ApplicationResolver = @Sendable (String) -> URL?
    typealias AppRunningChecker = @Sendable (String) -> Bool
    typealias OpenAction = @Sendable ([String]) throws -> Void
    typealias AppleScriptRunner = @Sendable (String) throws -> String
    typealias ProcessRunner = @Sendable (String, [String]) -> Bool
    typealias WarpFocusedPaneReader = @Sendable () -> String?
    typealias WarpTabCountReader = @Sendable () -> Int
    /// Returns true when Warp is the system's frontmost app and ready to
    /// receive the next tab-advance command. Production asks
    /// `NSWorkspace.shared.frontmostApplication`; tests inject `{ true }`
    /// to skip the polling loop entirely.
    typealias WarpFrontmostChecker = @Sendable () -> Bool

    private struct TerminalAppDescriptor {
        let displayName: String
        let bundleIdentifier: String
        let aliases: [String]
        let alternateBundleIdentifiers: [String]
        let preferredBundleIdentifiersByAlias: [String: String]

        init(
            displayName: String,
            bundleIdentifier: String,
            aliases: [String],
            alternateBundleIdentifiers: [String] = [],
            preferredBundleIdentifiersByAlias: [String: String] = [:]
        ) {
            self.displayName = displayName
            self.bundleIdentifier = bundleIdentifier
            self.aliases = aliases
            self.alternateBundleIdentifiers = alternateBundleIdentifiers
            self.preferredBundleIdentifiersByAlias = preferredBundleIdentifiersByAlias
        }

        var allBundleIdentifiers: [String] {
            [bundleIdentifier] + alternateBundleIdentifiers
        }
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
        TerminalAppDescriptor(
            displayName: "Codex.app",
            bundleIdentifier: "com.openai.codex",
            aliases: ["codex.app"]
        ),
        TerminalAppDescriptor(
            displayName: "Kaku",
            bundleIdentifier: "fun.tw93.kaku",
            aliases: ["kaku"]
        ),
        TerminalAppDescriptor(
            displayName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            aliases: ["cursor"]
        ),
        TerminalAppDescriptor(
            displayName: "VS Code",
            bundleIdentifier: "com.microsoft.VSCode",
            aliases: ["vscode", "code", "visual studio code"]
        ),
        TerminalAppDescriptor(
            displayName: "VS Code Insiders",
            bundleIdentifier: "com.microsoft.VSCodeInsiders",
            aliases: ["vscode-insiders", "code-insiders"]
        ),
        TerminalAppDescriptor(
            displayName: "Windsurf",
            bundleIdentifier: "com.exafunction.windsurf",
            aliases: ["windsurf"]
        ),
        TerminalAppDescriptor(
            displayName: "Trae",
            bundleIdentifier: "com.trae.app",
            aliases: ["trae", "trae cn", "trae-cn", "traecn"],
            alternateBundleIdentifiers: ["cn.trae.app"],
            preferredBundleIdentifiersByAlias: [
                "trae": "com.trae.app",
                "trae cn": "cn.trae.app",
                "trae-cn": "cn.trae.app",
                "traecn": "cn.trae.app",
            ]
        ),
        TerminalAppDescriptor(
            displayName: "IntelliJ IDEA",
            bundleIdentifier: "com.jetbrains.intellij",
            aliases: ["intellij", "idea"]
        ),
        TerminalAppDescriptor(
            displayName: "WebStorm",
            bundleIdentifier: "com.jetbrains.WebStorm",
            aliases: ["webstorm"]
        ),
        TerminalAppDescriptor(
            displayName: "PyCharm",
            bundleIdentifier: "com.jetbrains.pycharm",
            aliases: ["pycharm"]
        ),
        TerminalAppDescriptor(
            displayName: "GoLand",
            bundleIdentifier: "com.jetbrains.goland",
            aliases: ["goland"]
        ),
        TerminalAppDescriptor(
            displayName: "CLion",
            bundleIdentifier: "com.jetbrains.CLion",
            aliases: ["clion"]
        ),
        TerminalAppDescriptor(
            displayName: "RubyMine",
            bundleIdentifier: "com.jetbrains.rubymine",
            aliases: ["rubymine"]
        ),
        TerminalAppDescriptor(
            displayName: "PhpStorm",
            bundleIdentifier: "com.jetbrains.PhpStorm",
            aliases: ["phpstorm"]
        ),
        TerminalAppDescriptor(
            displayName: "Rider",
            bundleIdentifier: "com.jetbrains.rider",
            aliases: ["rider"]
        ),
        TerminalAppDescriptor(
            displayName: "RustRover",
            bundleIdentifier: "com.jetbrains.rustrover",
            aliases: ["rustrover"]
        ),
    ]

    /// Returns all known bundle identifiers for a terminal/IDE app given its
    /// display name (as stored in `JumpTarget.terminalApp`).  Used by
    /// `ForegroundTerminalSessionProbe` to suppress notifications when the
    /// agent's parent app is already frontmost.
    static func bundleIdentifiers(forTerminalAppName name: String) -> [String] {
        let lowered = name.lowercased()
        for app in knownApps where app.displayName.lowercased() == lowered
            || app.aliases.contains(lowered) {
            return app.allBundleIdentifiers
        }
        return []
    }

    /// Bundle identifiers of JetBrains IDEs.
    private static let jetbrainsBundleIDs: Set<String> = Set(
        knownApps
            .filter { $0.bundleIdentifier.hasPrefix("com.jetbrains.") }
            .map(\.bundleIdentifier)
    )

    /// Bundle identifiers of VS Code family editors (VS Code, Insiders, Cursor, Windsurf, Trae).
    private static let vscodeFamilyBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf",
        "com.trae.app",
        "cn.trae.app",
    ]

    /// Bundle identifiers of terminal emulators that commonly host Zellij,
    /// derived from `knownApps` so it stays in sync automatically.
    private static let zellijParentTerminals = knownApps.map(\.bundleIdentifier)

    private static let ghosttyFocusSettleDelay = 0.08
    private static let ghosttyWindowActivationDelay = 0.04
    private static let ghosttyFocusAttempts = 3

    /// Maximum time to wait for Warp to become the system frontmost app after
    /// an activation request. macOS app activation is async at the WindowServer
    /// level. Without waiting for `frontmostApplication` to actually be Warp,
    /// the first few Cmd+Shift+] keystrokes can land on whatever app was
    /// focused before activation, producing system beeps and never cycling
    /// Warp tabs. The poll loop exits as soon as Warp becomes frontmost (often
    /// 50-200ms on Apple Silicon); this constant is the cap. 1.5s tolerates
    /// machines under load where activation takes longer.
    private static let warpFrontmostMaxWait = 1.5
    /// Poll interval inside the frontmost-wait loop. Smaller = lower latency
    /// once Warp arrives but more SyscallChurn.
    private static let warpFrontmostPollInterval = 0.025
    /// How long to wait after each Cmd+Shift+] keystroke before re-reading
    /// `windows.active_tab_index` from Warp's SQLite. Warp persists the new
    /// active tab index a few tens of milliseconds after processing the
    /// keystroke; reading too soon can return stale state and cause the
    /// cycling loop to terminate at the wrong tab.
    private static let warpTabCycleSettleDelay = 0.1

    private let applicationResolver: ApplicationResolver
    private let appRunningChecker: AppRunningChecker
    private let openAction: OpenAction
    private let appleScriptRunner: AppleScriptRunner
    private let processRunner: ProcessRunner
    private let warpFocusedPaneReader: WarpFocusedPaneReader
    private let warpTabCountReader: WarpTabCountReader
    private let warpKeystroker: KeystrokeInjector
    private let warpFrontmostChecker: WarpFrontmostChecker

    init(
        applicationResolver: @escaping ApplicationResolver = { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        },
        appRunningChecker: @escaping AppRunningChecker = { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
        },
        openAction: @escaping OpenAction = Self.defaultOpenAction(arguments:),
        appleScriptRunner: @escaping AppleScriptRunner = Self.defaultAppleScriptRunner(script:),
        processRunner: @escaping ProcessRunner = Self.defaultProcessRunner(executable:arguments:),
        warpFocusedPaneReader: @escaping WarpFocusedPaneReader = { WarpSQLiteReader().currentFocusedPaneUUID() },
        warpTabCountReader: @escaping WarpTabCountReader = { WarpSQLiteReader().tabCountInActiveWindow() },
        warpKeystroker: KeystrokeInjector = DefaultKeystrokeInjector(),
        warpFrontmostChecker: @escaping WarpFrontmostChecker = {
            // Use NSWorkspace.frontmostApplication (live workspace state)
            // rather than NSRunningApplication.isActive (a cached property
            // updated via KVO that can lag the real frontmost transition).
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                == "dev.warp.Warp-Stable"
        }
    ) {
        self.applicationResolver = applicationResolver
        self.appRunningChecker = appRunningChecker
        self.openAction = openAction
        self.appleScriptRunner = appleScriptRunner
        self.processRunner = processRunner
        self.warpFocusedPaneReader = warpFocusedPaneReader
        self.warpTabCountReader = warpTabCountReader
        self.warpKeystroker = warpKeystroker
        self.warpFrontmostChecker = warpFrontmostChecker
    }

    func jump(to target: JumpTarget) throws -> String {
        // tmux sessions: switch pane first, then use the terminal-specific
        // jump to focus the correct window/tab (not just activate the app).
        if let tmuxTarget = target.tmuxTarget, !tmuxTarget.isEmpty {
            let paneSelected = jumpToTmuxPane(target)

            let descriptor = resolveTerminalApp(preferredName: target.terminalApp)

            // Use the full terminal-specific jump (AppleScript for Ghostty/iTerm,
            // CLI for WezTerm, etc.) to focus the correct window/tab.
            if let descriptor {
                switch descriptor.bundleIdentifier {
                case "com.mitchellh.ghostty":
                    if try jumpToGhosttyTerminal(target) {
                        return "Focused the matching tmux pane in Ghostty."
                    }
                case "com.googlecode.iterm2":
                    if try jumpToITermSession(target) {
                        return "Focused the matching tmux pane in iTerm."
                    }
                case "com.apple.Terminal":
                    if try jumpToTerminalTab(target) {
                        return "Focused the matching tmux pane in Terminal."
                    }
                default:
                    break
                }

                // Fallback: at least activate the app
                try openAction(["-b", descriptor.bundleIdentifier])
                return paneSelected
                    ? "Focused the matching tmux pane and activated \(descriptor.displayName)."
                    : "Activated \(descriptor.displayName). tmux pane targeting failed."
            }

            if paneSelected {
                return "Focused the matching tmux pane."
            }
        }

        let normalizedPreferredName = normalizeTerminalAppName(target.terminalApp)
        let descriptor = resolveTerminalApp(preferredName: target.terminalApp)
        let hasWorkingDirectory = target.workingDirectory.map { FileManager.default.fileExists(atPath: $0) } ?? false
        let hasPreciseLocator = [target.terminalSessionID, target.terminalTTY].contains {
            guard let value = $0?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !value.isEmpty
        }
        let preferredBundleIdentifier: String?
        if let descriptor {
            preferredBundleIdentifier = preferredBundleIdentifierForAlias(
                for: descriptor,
                normalizedPreferredName: normalizedPreferredName
            )
        } else {
            preferredBundleIdentifier = nil
        }

        let resolvedBundleIdentifier: String?
        if let descriptor {
            resolvedBundleIdentifier = resolveBundleIdentifier(
                for: descriptor,
                preferredBundleIdentifier: preferredBundleIdentifier
            )
        } else {
            resolvedBundleIdentifier = nil
        }
        let appIsRunning = resolvedBundleIdentifier.map(appRunningChecker) ?? false

        // Zellij is a terminal multiplexer, not a macOS .app. Handle it
        // before the descriptor-based dispatch since it won't have one.
        if target.terminalApp.lowercased() == "zellij" {
            if jumpToZellijPane(target) {
                return "Focused the matching Zellij pane."
            }
            // Fallback: activate whichever parent terminal is running.
            if let parentBundleID = Self.zellijParentTerminals.first(where: { appRunningChecker($0) }) {
                try openAction(["-b", parentBundleID])
                return "Activated parent terminal. Zellij pane targeting could not find the pane."
            }
            throw TerminalJumpError.unsupportedTerminal("Zellij (no parent terminal found)")
        }

        if let descriptor {
            switch resolvedBundleIdentifier ?? descriptor.bundleIdentifier {
            case "com.openai.codex":
                // If we have a thread ID, use the codex:// URL scheme to
                // open the specific conversation directly.  Otherwise just
                // activate the app.
                if let threadID = target.codexThreadID, !threadID.isEmpty {
                    try openAction(["codex://threads/\(threadID)"])
                    return "Focused the Codex.app conversation."
                }
                try openAction(["-b", "com.openai.codex"])
                return "Activated Codex.app."
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
            case "dev.warp.Warp-Stable":
                return try jumpToWarpPane(target)
            case "fun.tw93.kaku", "com.github.wez.wezterm":
                if let cliPath = weztermFamilyCLIPath(for: descriptor.bundleIdentifier),
                   jumpToWeztermFamilyTerminal(target, cliPath: cliPath, bundleIdentifier: descriptor.bundleIdentifier) {
                    return "Focused the matching \(descriptor.displayName) pane."
                }
            case let id where Self.vscodeFamilyBundleIDs.contains(id):
                if let workingDirectory = target.workingDirectory {
                    let opened = jumpToVSCodeFamilyWorkspace(workingDirectory, bundleIdentifier: id)
                    if opened {
                        return "Focused the matching \(descriptor.displayName) workspace."
                    }
                }
                if appIsRunning {
                    try openAction(["-b", id])
                    return "Activated \(descriptor.displayName)."
                }
            case let id where Self.jetbrainsBundleIDs.contains(id):
                if let workingDirectory = target.workingDirectory {
                    let opened = jumpToJetBrainsProject(workingDirectory, bundleIdentifier: id)
                    if opened {
                        return "Focused the matching \(descriptor.displayName) project."
                    }
                }
                if appIsRunning {
                    try openAction(["-b", id])
                    return "Activated \(descriptor.displayName)."
                }
            default:
                break
            }
        }

        if let descriptor, hasPreciseLocator, appIsRunning {
            try openAction(["-b", resolvedBundleIdentifier ?? descriptor.bundleIdentifier])
            return "Activated \(descriptor.displayName). Exact pane targeting could not find the live terminal."
        }

        if let descriptor, hasWorkingDirectory, let workingDirectory = target.workingDirectory {
            try openAction(["-b", resolvedBundleIdentifier ?? descriptor.bundleIdentifier, workingDirectory])
            return "Opened \(target.workspaceName) in \(descriptor.displayName). Exact pane targeting is still best-effort."
        }

        if let descriptor {
            try openAction(["-b", resolvedBundleIdentifier ?? descriptor.bundleIdentifier])
            return "Activated \(descriptor.displayName). Exact pane targeting is still best-effort."
        }

        if hasWorkingDirectory, let workingDirectory = target.workingDirectory {
            try openAction([workingDirectory])
            return "Opened \(target.workspaceName) in Finder because no supported terminal app could be resolved."
        }

        throw TerminalJumpError.unsupportedTerminal(target.terminalApp)
    }

    private func jumpToITermSession(_ target: JumpTarget) throws -> Bool {
        let script = """
        tell application "iTerm"
            if not (it is running) then return ""
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        set matched to false
                        if "\(escapeAppleScript(target.terminalSessionID))" is not "" and (id of aSession as text) is "\(escapeAppleScript(target.terminalSessionID))" then
                            set matched to true
                        end if
                        if not matched and "\(escapeAppleScript(target.terminalTTY))" is not "" and (tty of aSession as text) is "\(escapeAppleScript(target.terminalTTY))" then
                            set matched to true
                        end if
                        if matched then
                            select aWindow
                            tell aWindow to select aTab
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

    // MARK: - VS Code family (VS Code, Insiders, Cursor, Windsurf, Trae)

    /// Maps bundle identifiers to the CLI command used to open a workspace.
    private static let vscodeFamilyCLI: [String: String] = [
        "com.microsoft.VSCode": "code",
        "com.microsoft.VSCodeInsiders": "code-insiders",
        "com.todesktop.230313mzl4w4u92": "cursor",
        "com.exafunction.windsurf": "windsurf",
        "com.trae.app": "trae",
        "cn.trae.app": "trae",
    ]

    private func jumpToVSCodeFamilyWorkspace(_ workspacePath: String, bundleIdentifier: String) -> Bool {
        guard let cli = Self.vscodeFamilyCLI[bundleIdentifier] else {
            return false
        }
        return processRunner(cli, ["-r", workspacePath])
    }

    // MARK: - JetBrains IDE family

    /// Maps bundle identifiers to the CLI launcher script name (typically in
    /// `/usr/local/bin/` or `~/Library/Application Support/JetBrains/Toolbox/scripts/`).
    private static let jetbrainsCLI: [String: String] = [
        "com.jetbrains.intellij": "idea",
        "com.jetbrains.WebStorm": "webstorm",
        "com.jetbrains.pycharm": "pycharm",
        "com.jetbrains.goland": "goland",
        "com.jetbrains.CLion": "clion",
        "com.jetbrains.rubymine": "rubymine",
        "com.jetbrains.PhpStorm": "phpstorm",
        "com.jetbrains.rider": "rider",
        "com.jetbrains.rustrover": "rustrover",
    ]

    private func jumpToJetBrainsProject(_ projectPath: String, bundleIdentifier: String) -> Bool {
        guard let cli = Self.jetbrainsCLI[bundleIdentifier] else {
            return false
        }
        return processRunner(cli, [projectPath])
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

    // MARK: - Tmux CLI-based jump

    private func jumpToTmuxPane(_ target: JumpTarget) -> Bool {
        guard let tmuxTarget = target.tmuxTarget, !tmuxTarget.isEmpty else {
            return false
        }

        guard let tmuxPath = resolveTmuxPath() else {
            return false
        }

        // tmuxTarget is "session:window.pane" (e.g. "oss-contributions:3.0")
        // When running from a macOS GUI app (outside tmux), there is no
        // "current client" — $TMUX is not set. We must explicitly find the
        // client TTY and pass it via -c to switch-client.

        func socketArgs() -> [String] {
            if let socketPath = target.tmuxSocketPath, !socketPath.isEmpty {
                return ["-S", socketPath]
            }
            return []
        }

        // Extract "session:window" and "session" from "session:window.pane"
        let sessionWindow: String
        if let dotIndex = tmuxTarget.lastIndex(of: ".") {
            sessionWindow = String(tmuxTarget[tmuxTarget.startIndex..<dotIndex])
        } else {
            sessionWindow = tmuxTarget
        }

        let sessionName: String
        if let colonIndex = tmuxTarget.firstIndex(of: ":") {
            sessionName = String(tmuxTarget[tmuxTarget.startIndex..<colonIndex])
        } else {
            sessionName = tmuxTarget
        }

        // Find the client TTY so we can explicitly target it with switch-client.
        let clientTTY = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs(),
                                       args: ["list-clients", "-F", "#{client_tty}"])?
            .components(separatedBy: "\n").first { !$0.isEmpty }

        // Step 1: switch-client — point the client at the target session.
        if let clientTTY = clientTTY {
            _ = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs(),
                               args: ["switch-client", "-c", clientTTY, "-t", sessionName])
        }

        // Step 2: select-window — switch to the correct window.
        _ = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs(),
                           args: ["select-window", "-t", sessionWindow])

        // Step 3: select-pane — focus the exact pane.
        let spResult = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs(),
                                      args: ["select-pane", "-t", tmuxTarget])

        return spResult != nil
    }

    /// Run a tmux command and return its stdout (nil on failure).
    /// Uses the same direct-exec pattern as ActiveAgentProcessDiscovery.commandOutput.
    private func runTmuxCommand(tmuxPath: String, socketArgs: [String], args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = socketArgs + args

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return nil
        }
    }

    private func resolveTmuxPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]

        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        // Fallback to 'which'
        let whichTask = Process()
        whichTask.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichTask.arguments = ["tmux"]
        let pipe = Pipe()
        whichTask.standardOutput = pipe
        whichTask.standardError = FileHandle.nullDevice
        guard (try? whichTask.run()) != nil else { return nil }
        whichTask.waitUntilExit()
        guard whichTask.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    // MARK: - Zellij CLI-based jump

    /// Parses the encoded `terminalSessionID` (format: `paneId:sessionName`)
    /// and uses `zellij action` to switch to the tab containing that pane.
    private func jumpToZellijPane(_ target: JumpTarget) -> Bool {
        guard let encoded = target.terminalSessionID, !encoded.isEmpty else {
            return false
        }

        let parts = encoded.split(separator: ":", maxSplits: 1)
        let paneIDString = String(parts[0])
        let sessionName = parts.count > 1 ? String(parts[1]) : nil

        guard let paneID = Int(paneIDString) else {
            return false
        }

        guard let zellijPath = resolveZellijPath() else {
            return false
        }

        // Query all panes to find which tab contains our target pane.
        guard let tabPosition = zellijTabPosition(
            zellijPath: zellijPath,
            sessionName: sessionName,
            paneID: paneID
        ) else {
            return false
        }

        // Switch to the tab (1-indexed).
        let goToTab = Process()
        goToTab.executableURL = URL(fileURLWithPath: zellijPath)
        if let sessionName, !sessionName.isEmpty {
            goToTab.arguments = ["--session", sessionName, "action", "go-to-tab", "\(tabPosition + 1)"]
        } else {
            goToTab.arguments = ["action", "go-to-tab", "\(tabPosition + 1)"]
        }
        goToTab.standardOutput = FileHandle.nullDevice
        goToTab.standardError = FileHandle.nullDevice
        guard (try? goToTab.run()) != nil else { return false }
        goToTab.waitUntilExit()

        // Activate the parent terminal app window.
        if let parentBundleID = Self.zellijParentTerminals.first(where: { appRunningChecker($0) }) {
            try? openAction(["-b", parentBundleID])
        }

        return goToTab.terminationStatus == 0
    }

    private func resolveZellijPath() -> String? {
        let candidates = [
            NSHomeDirectory() + "/.local/bin/zellij",
            "/usr/local/bin/zellij",
            "/opt/homebrew/bin/zellij",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        // Fallback: which.
        let whichTask = Process()
        whichTask.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichTask.arguments = ["zellij"]
        let pipe = Pipe()
        whichTask.standardOutput = pipe
        whichTask.standardError = FileHandle.nullDevice
        guard (try? whichTask.run()) != nil else { return nil }
        whichTask.waitUntilExit()
        guard whichTask.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    private struct ZellijPaneInfo: Decodable {
        let id: Int
        let tabPosition: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case tabPosition = "tab_position"
        }
    }

    /// Queries Zellij for pane info and returns the tab position of the given pane.
    private func zellijTabPosition(
        zellijPath: String,
        sessionName: String?,
        paneID: Int
    ) -> Int? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: zellijPath)
        var args: [String] = []
        if let sessionName, !sessionName.isEmpty {
            args += ["--session", sessionName]
        }
        args += ["action", "list-panes", "--json", "--tab"]
        task.arguments = args

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let panes = try? JSONDecoder().decode([ZellijPaneInfo].self, from: data) else {
            return nil
        }

        return panes.first(where: { $0.id == paneID })?.tabPosition
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

    // MARK: - WezTerm-family (Kaku / WezTerm) CLI-based jump

    private func weztermFamilyCLIPath(for bundleIdentifier: String) -> String? {
        let cliName: String
        let appName: String
        switch bundleIdentifier {
        case "fun.tw93.kaku":
            cliName = "kaku"
            appName = "Kaku"
        case "com.github.wez.wezterm":
            cliName = "wezterm"
            appName = "WezTerm"
        default: return nil
        }

        // Try well-known .app bundle paths first (most reliable).
        let bundleCandidates = [
            "/Applications/\(appName).app/Contents/MacOS/\(cliName)",
            NSHomeDirectory() + "/Applications/\(appName).app/Contents/MacOS/\(cliName)",
        ]
        if let found = bundleCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        // Fallback: try PATH via /usr/bin/which.
        let whichTask = Process()
        whichTask.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichTask.arguments = [cliName]
        let pipe = Pipe()
        whichTask.standardOutput = pipe
        whichTask.standardError = FileHandle.nullDevice
        if let _ = try? whichTask.run() {
            whichTask.waitUntilExit()
            if whichTask.terminationStatus == 0 {
                let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty { return path }
            }
        }

        return nil
    }

    /// Strip `file://` scheme and percent-encoding from a WezTerm/Kaku cwd URL.
    private static func weztermFamilyNormalizeCWD(_ cwd: String) -> String {
        if cwd.hasPrefix("file://"), let url = URL(string: cwd) {
            return url.path
        }
        return cwd
    }

    private func jumpToWeztermFamilyTerminal(
        _ target: JumpTarget,
        cliPath: String,
        bundleIdentifier: String
    ) -> Bool {
        guard let panes = weztermFamilyListPanes(cliPath: cliPath) else {
            return false
        }

        // Match by pane_id (stored in terminalSessionID).
        if let sessionID = target.terminalSessionID,
           let paneID = Int(sessionID),
           panes.contains(where: { $0.paneID == paneID }) {
            if weztermFamilyActivatePane(cliPath: cliPath, paneID: paneID) {
                try? openAction(["-b", bundleIdentifier])
                return true
            }
        }

        // Match by TTY.
        if let targetTTY = target.terminalTTY,
           !targetTTY.isEmpty,
           let matched = panes.first(where: { $0.ttyName == targetTTY }) {
            if weztermFamilyActivatePane(cliPath: cliPath, paneID: matched.paneID) {
                try? openAction(["-b", bundleIdentifier])
                return true
            }
        }

        // Match by working directory.
        if let targetCWD = target.workingDirectory {
            let normalizedTarget = URL(fileURLWithPath: targetCWD).standardizedFileURL.path
            if let matched = panes.first(where: {
                let paneCWD = Self.weztermFamilyNormalizeCWD($0.cwd)
                return URL(fileURLWithPath: paneCWD).standardizedFileURL.path == normalizedTarget
            }) {
                if weztermFamilyActivatePane(cliPath: cliPath, paneID: matched.paneID) {
                    try? openAction(["-b", bundleIdentifier])
                    return true
                }
            }
        }

        // Match by title.
        if !target.paneTitle.isEmpty {
            if let matched = panes.first(where: { $0.title.contains(target.paneTitle) }) {
                if weztermFamilyActivatePane(cliPath: cliPath, paneID: matched.paneID) {
                    try? openAction(["-b", bundleIdentifier])
                    return true
                }
            }
        }

        return false
    }

    struct WeztermFamilyPane: Decodable {
        let windowID: Int
        let tabID: Int
        let paneID: Int
        let title: String
        let cwd: String
        let ttyName: String?
        let isActive: Bool

        enum CodingKeys: String, CodingKey {
            case windowID = "window_id"
            case tabID = "tab_id"
            case paneID = "pane_id"
            case title
            case cwd
            case ttyName = "tty_name"
            case isActive = "is_active"
        }
    }

    private func weztermFamilyListPanes(cliPath: String) -> [WeztermFamilyPane]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: cliPath)
        task.arguments = ["cli", "list", "--format", "json"]

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return try? JSONDecoder().decode([WeztermFamilyPane].self, from: data)
    }

    private func weztermFamilyActivatePane(cliPath: String, paneID: Int) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: cliPath)
        task.arguments = ["cli", "activate-pane", "--pane-id", "\(paneID)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func jumpToWarpPane(_ target: JumpTarget) throws -> String {
        // 1. Always activate Warp first — this is the baseline behavior.
        //    `warpKeystroker.sendCmdShiftRightBracket()` also activates via
        //    AppleScript, but running `open -b` here ensures Warp is foreground
        //    even in the early-return branch below where no AppleScript ever
        //    fires.
        try openAction(["-b", "dev.warp.Warp-Stable"])

        // 2. If we don't have a mapped pane UUID, we're done. This happens
        //    when WarpSQLiteReader couldn't resolve the agent's cwd to a
        //    pane — usually because the user launched the agent through a
        //    compound command (e.g. `cd /tmp/foo && claude`) that bypassed
        //    Warp's shell-integration prompt render, so terminal_panes.cwd
        //    was never updated for that pane. See the "known limitation"
        //    note in WarpSQLiteReader.lookupPaneUUID for the full story.
        guard let targetPaneUUID = target.warpPaneUUID else {
            return "Activated Warp. No precise pane mapping available."
        }

        // 3. Wait for Warp to actually become the foreground app. `open -b`
        //    exits immediately but the WindowServer activation is async and
        //    can take 50-300ms depending on machine load. We poll
        //    `frontmostApplication` until Warp is really frontmost or we
        //    hit the cap.
        let frontmostStart = Date()
        while !warpFrontmostChecker() {
            if Date().timeIntervalSince(frontmostStart) >= Self.warpFrontmostMaxWait {
                break
            }
            Thread.sleep(forTimeInterval: Self.warpFrontmostPollInterval)
        }

        // 4. Fast path: if Warp is already showing the target pane we're
        //    done — no tab-advance needed.
        if warpFocusedPaneReader() == targetPaneUUID {
            return "Focused the matching Warp tab."
        }

        // 5. Cycle via repeated "Switch to Next Tab" clicks with a cap. We
        //    only need at most tabCount-1 cycles to reach any tab from any
        //    starting point, but +2 is safety margin for counting quirks
        //    and the rare case where active_tab_index is briefly stale
        //    between a click and the next SQLite read. The `KeystrokeInjector`
        //    protocol name is historical; the production implementation
        //    clicks the `Tab ▸ Switch to Next Tab` menu item via AX —
        //    see `DefaultKeystrokeInjector` for the rationale.
        let tabCount = max(1, warpTabCountReader())
        let maxAttempts = tabCount + 2

        for _ in 0..<maxAttempts {
            warpKeystroker.sendCmdShiftRightBracket()
            Thread.sleep(forTimeInterval: Self.warpTabCycleSettleDelay)
            if warpFocusedPaneReader() == targetPaneUUID {
                return "Focused the matching Warp tab."
            }
        }

        return "Activated Warp but could not confirm precision focus."
    }

    private func resolveTerminalApp(preferredName: String) -> TerminalAppDescriptor? {
        let normalized = normalizeTerminalAppName(preferredName)

        // "Unknown" is the hook-side sentinel meaning "we could not classify this
        // terminal". Returning nil here lets jump() fall through to the Finder
        // cwd fallback instead of silently activating the first installed
        // known terminal — the historical behavior that caused Warp sessions to
        // open Terminal.app (or worse, iTerm) windows.
        if normalized == "unknown" {
            return nil
        }

        if let exact = Self.knownApps.first(where: { descriptor in
            descriptor.displayName.lowercased() == normalized || descriptor.aliases.contains(normalized)
        }) {
            return exact
        }

        return Self.knownApps.first(where: isInstalled(descriptor:))
    }

    private func normalizeTerminalAppName(_ preferredName: String) -> String {
        preferredName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isInstalled(descriptor: TerminalAppDescriptor) -> Bool {
        descriptor.allBundleIdentifiers.contains { applicationResolver($0) != nil }
    }

    private func preferredBundleIdentifierForAlias(
        for descriptor: TerminalAppDescriptor,
        normalizedPreferredName: String
    ) -> String? {
        if let aliasSpecific = descriptor.preferredBundleIdentifiersByAlias[normalizedPreferredName] {
            return aliasSpecific
        }
        if descriptor.displayName.lowercased() == normalizedPreferredName {
            return descriptor.bundleIdentifier
        }
        return nil
    }

    private func resolveBundleIdentifier(
        for descriptor: TerminalAppDescriptor,
        preferredBundleIdentifier: String?
    ) -> String {
        if let preferredBundleIdentifier, appRunningChecker(preferredBundleIdentifier) {
            return preferredBundleIdentifier
        }
        if let preferredBundleIdentifier, applicationResolver(preferredBundleIdentifier) != nil {
            return preferredBundleIdentifier
        }
        if let running = descriptor.allBundleIdentifiers.first(where: appRunningChecker) {
            return running
        }
        if let installed = descriptor.allBundleIdentifiers.first(where: { applicationResolver($0) != nil }) {
            return installed
        }
        return preferredBundleIdentifier ?? descriptor.bundleIdentifier
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

    private static func defaultProcessRunner(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
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
