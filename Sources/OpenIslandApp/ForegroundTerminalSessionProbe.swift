import AppKit
import Foundation
import OpenIslandCore

struct ForegroundTerminalSessionProbe {
    typealias FrontmostBundleIdentifierProvider = @Sendable () -> String?
    typealias AppleScriptRunner = @Sendable (String) throws -> String

    private static let fieldSeparator = "\u{1f}"

    private let frontmostBundleIdentifierProvider: FrontmostBundleIdentifierProvider
    private let appleScriptRunner: AppleScriptRunner

    init(
        frontmostBundleIdentifierProvider: @escaping FrontmostBundleIdentifierProvider = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        appleScriptRunner: @escaping AppleScriptRunner = Self.runAppleScript
    ) {
        self.frontmostBundleIdentifierProvider = frontmostBundleIdentifierProvider
        self.appleScriptRunner = appleScriptRunner
    }

    func matches(session: AgentSession) -> Bool {
        matches(jumpTarget: session.jumpTarget)
    }

    func matches(jumpTarget: JumpTarget?) -> Bool {
        guard let jumpTarget,
              let frontmostBundleIdentifier = frontmostBundleIdentifierProvider() else {
            return false
        }

        switch frontmostBundleIdentifier {
        case "com.mitchellh.ghostty":
            guard let focusedTerminalID = ghosttyFocusedTerminalID(),
                  let sessionTerminalID = nonEmptyValue(jumpTarget.terminalSessionID) else {
                return false
            }
            return focusedTerminalID == sessionTerminalID

        case "com.apple.Terminal":
            guard let focusedTTY = normalizedTTY(terminalFocusedTTY()),
                  let sessionTTY = normalizedTTY(jumpTarget.terminalTTY) else {
                return false
            }
            return focusedTTY == sessionTTY

        case "com.googlecode.iterm2":
            let focusedSession = itermFocusedSession()

            if let focusedSessionID = focusedSession?.sessionID,
               let sessionTerminalID = nonEmptyValue(jumpTarget.terminalSessionID),
               focusedSessionID == sessionTerminalID {
                return true
            }

            if let focusedTTY = normalizedTTY(focusedSession?.tty),
               let sessionTTY = normalizedTTY(jumpTarget.terminalTTY),
               focusedTTY == sessionTTY {
                return true
            }

            return false

        default:
            return false
        }
    }

    private func ghosttyFocusedTerminalID() -> String? {
        let script = """
        tell application "Ghostty"
            if not (it is running) then return ""
            return id of focused terminal of selected tab of front window as text
        end tell
        """

        return nonEmptyValue(try? appleScriptRunner(script))
    }

    private func terminalFocusedTTY() -> String? {
        let script = """
        tell application "Terminal"
            if not (it is running) then return ""
            return tty of selected tab of front window as text
        end tell
        """

        return nonEmptyValue(try? appleScriptRunner(script))
    }

    private func itermFocusedSession() -> (sessionID: String?, tty: String?)? {
        let script = """
        tell application "iTerm"
            if not (it is running) then return ""
            tell current session of current window
                return (id as text) & "\(Self.fieldSeparator)" & (tty as text)
            end tell
        end tell
        """

        guard let output = nonEmptyValue(try? appleScriptRunner(script)) else {
            return nil
        }

        let values = output.components(separatedBy: Self.fieldSeparator)
        if values.isEmpty {
            return nil
        }

        return (
            sessionID: values.indices.contains(0) ? nonEmptyValue(values[0]) : nil,
            tty: values.indices.contains(1) ? nonEmptyValue(values[1]) : nil
        )
    }

    private func nonEmptyValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func normalizedTTY(_ value: String?) -> String? {
        guard let trimmed = nonEmptyValue(value) else {
            return nil
        }

        return trimmed.hasPrefix("/dev/") ? trimmed : "/dev/\(trimmed)"
    }

    private static func runAppleScript(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let errorText = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(domain: "ForegroundTerminalSessionProbe", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: errorText.isEmpty ? "AppleScript probe failed." : errorText,
            ])
        }

        return output
    }
}
