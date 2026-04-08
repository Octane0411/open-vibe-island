import Foundation
import OpenIslandCore

@main
struct OpenIslandHooksCLI {
    private static let interactiveClaudeHookTimeout: TimeInterval = 24 * 60 * 60

    private enum HookSource: String {
        case codex
        case claude
        case qoder
        case factory
        case droid  // Factory alias used by CodeIsland
        case codebuddy

        /// Whether this source uses the Claude Code hook format.
        var isClaudeFormat: Bool {
            switch self {
            case .claude, .qoder, .factory, .droid, .codebuddy:
                return true
            case .codex:
                return false
            }
        }
    }

    static func main() {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard !input.isEmpty else {
                return
            }

            let arguments = Array(CommandLine.arguments.dropFirst())
            let source = hookSource(arguments: arguments)
            let sourceString = rawSourceString(arguments: arguments)
            let decoder = JSONDecoder()
            let client = BridgeCommandClient(socketURL: BridgeSocketLocation.currentURL())

            switch source {
            case .codex:
                let payload = try decoder
                    .decode(CodexHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)

                guard let response = try? client.send(.processCodexHook(payload)) else {
                    logStderr("bridge unavailable for codex hook")
                    return
                }

                if let output = try CodexHookOutputEncoder.standardOutput(for: response) {
                    FileHandle.standardOutput.write(output)
                }
            case .claude, .qoder, .factory, .droid, .codebuddy:
                var payload = try decoder
                    .decode(ClaudeHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)
                payload.hookSource = sourceString

                let timeout = payload.hookEventName == .permissionRequest
                    ? interactiveClaudeHookTimeout
                    : 45

                guard let response = try? client.send(.processClaudeHook(payload), timeout: timeout) else {
                    logStderr("bridge unavailable for claude hook (\(payload.hookEventName.rawValue))")
                    return
                }

                if let output = try ClaudeHookOutputEncoder.standardOutput(for: response) {
                    FileHandle.standardOutput.write(output)
                }
            }
        } catch {
            // Hooks should fail open so the CLI continues working even if the bridge is unavailable.
            logStderr("hook failed: \(error)")
        }
    }

    private static func logStderr(_ message: String) {
        guard let data = "[OpenIslandHooks] \(message)\n".data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
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

    private static func rawSourceString(arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--source", index + 1 < arguments.count {
                return arguments[index + 1]
            }

            index += 1
        }

        return nil
    }
}
