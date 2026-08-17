import Foundation
import OpenIslandCore

@main
struct OpenIslandHooksCLI {
    private static let interactiveClaudeHookTimeout: TimeInterval = 24 * 60 * 60
    private static let interactiveCodexHookTimeout =
        TimeInterval(CodexHookInstaller.managedInteractiveTimeout)

    private enum HookSource: String {
        case codex
        case claude
        case qoder
        case qwen
        case factory
        case droid
        case codebuddy
        case cursor
        case gemini
        case antigravity
        case kimi

        var isClaudeFormat: Bool {
            switch self {
            case .claude, .qoder, .qwen, .factory, .droid, .codebuddy, .kimi:
                return true
            case .codex, .cursor, .gemini, .antigravity:
                return false
            }
        }
    }

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let source = hookSource(arguments: arguments)
        let antigravityEvent = antigravityHookEvent(arguments: arguments)
        defer {
            if source == .antigravity {
                writeAntigravityPassThroughOutput(for: antigravityEvent)
            }
        }

        do {
            // Allow wrappers to delegate one child process away from Open Island without changing global hook installation.
            // 允许外部控制器只让当前子进程跳过 Open Island hook，不影响全局安装状态。
            if HookSkipConfiguration.shouldSkipHooks(environment: ProcessInfo.processInfo.environment) {
                return
            }

            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard !input.isEmpty else {
                return
            }

            let sourceString = rawSourceString(arguments: arguments)
            let decoder = JSONDecoder()
            let client = BridgeCommandClient(socketURL: BridgeSocketLocation.currentURL())

            switch source {
            case .codex:
                let payload = try decoder
                    .decode(CodexHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)

                let timeout = payload.hookEventName == .permissionRequest
                    ? interactiveCodexHookTimeout
                    : 45

                guard let response = try? client.send(.processCodexHook(payload), timeout: timeout) else {
                    logStderr("bridge unavailable for codex hook (\(payload.hookEventName.rawValue))")
                    return
                }

                if let output = try CodexHookOutputEncoder.standardOutput(for: response) {
                    FileHandle.standardOutput.write(output)
                }
            case .claude, .qoder, .qwen, .factory, .droid, .codebuddy, .kimi:
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
            case .cursor:
                let payload = try decoder.decode(CursorHookPayload.self, from: input)

                let timeout: TimeInterval = payload.isBlockingHook
                    ? Self.interactiveClaudeHookTimeout
                    : 45

                guard let response = try? client.send(.processCursorHook(payload), timeout: timeout) else {
                    return
                }

                if case let .cursorHookDirective(directive) = response {
                    let encoder = JSONEncoder()
                    let output = try encoder.encode(directive)
                    FileHandle.standardOutput.write(output)
                    FileHandle.standardOutput.write(Data("\n".utf8))
                }
            case .gemini:
                let payload = try decoder
                    .decode(GeminiHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)

                _ = try? client.send(.processGeminiHook(payload), timeout: 45)
            case .antigravity:
                guard let antigravityEvent else {
                    logStderr("missing Antigravity hook event")
                    return
                }
                let payload = try decoder
                    .decode(AntigravityHookPayload.self, from: input)
                    .withHookEvent(antigravityEvent)

                _ = try? client.send(.processAntigravityHook(payload), timeout: 45)
            }
        } catch {
            // Hooks should fail open so the CLI continues working even if the bridge is unavailable.
            logStderr("hook failed: \(error)")
        }
    }

    private static func logStderr(_ message: String) {
        guard let data = "[OpenIslandHooks] \(message)\n".data(using: .utf8) else { return }
        SafeFileDescriptorWriter.write(data)
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

    private static func antigravityHookEvent(arguments: [String]) -> AntigravityHookEventName? {
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--event", index + 1 < arguments.count {
                switch arguments[index + 1] {
                case "pre-invocation": return .preInvocation
                case "stop": return .stop
                default: return nil
                }
            }
            index += 1
        }
        return nil
    }

    private static func writeAntigravityPassThroughOutput(for event: AntigravityHookEventName?) {
        let output: String
        switch event {
        case .stop:
            output = "{\"decision\":\"allow\"}\n"
        case .preInvocation, .none:
            output = "{}\n"
        }
        FileHandle.standardOutput.write(Data(output.utf8))
    }
}
