import Foundation
import OpenIslandCore

@main
struct OpenIslandHooksCLI {
    private static let interactiveClaudeHookTimeout: TimeInterval = 24 * 60 * 60

    private enum HookSource: String {
        case codex
        case claude
    }

    static func main() {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard !input.isEmpty else {
                return
            }

            let source = hookSource(arguments: Array(CommandLine.arguments.dropFirst()))
            let decoder = JSONDecoder()
            let client = BridgeCommandClient(socketURL: BridgeSocketLocation.currentURL())

            switch source {
            case .codex:
                let payload = try decoder
                    .decode(CodexHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)

                guard let response = try? client.send(.processCodexHook(payload)) else {
                    return
                }

                if let output = try CodexHookOutputEncoder.standardOutput(for: response) {
                    FileHandle.standardOutput.write(output)
                }
            case .claude:
                let payload = try decoder
                    .decode(ClaudeHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)

                // Persist terminal info on session start so the app can restore
                // terminal mappings after restart. Delete on session end.
                persistTerminalInfo(for: payload)

                let timeout = payload.hookEventName == .permissionRequest
                    ? interactiveClaudeHookTimeout
                    : 45

                guard let response = try? client.send(.processClaudeHook(payload), timeout: timeout) else {
                    return
                }

                if let output = try ClaudeHookOutputEncoder.standardOutput(for: response) {
                    FileHandle.standardOutput.write(output)
                }
            }
        } catch {
            // Hooks should fail open so the CLI continues working even if the bridge is unavailable.
        }
    }

    private static func persistTerminalInfo(for payload: ClaudeHookPayload) {
        let sessionID = payload.sessionID
        guard !sessionID.isEmpty else { return }

        switch payload.hookEventName {
        case .sessionStart, .userPromptSubmit:
            // Save terminal info — the enriched payload has the terminal ID
            // resolved from the focused terminal at this moment.
            if let app = payload.terminalApp, !app.isEmpty {
                let entry = TerminalInfoStore.Entry(
                    terminalApp: app,
                    terminalSessionID: payload.terminalSessionID,
                    tty: payload.terminalTTY
                )
                TerminalInfoStore.save(entry, sessionID: sessionID)
            }
        case .sessionEnd:
            TerminalInfoStore.remove(sessionID: sessionID)
        default:
            break
        }
    }

    private static func hookSource(arguments: [String]) -> HookSource {
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--source", index + 1 < arguments.count {
                return HookSource(rawValue: arguments[index + 1]) ?? .codex
            }

            index += 1
        }

        return .codex
    }
}
