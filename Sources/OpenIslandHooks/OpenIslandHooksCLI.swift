import Foundation
import OpenIslandCore

@main
struct OpenIslandHooksCLI {
    private static let interactiveClaudeHookTimeout: TimeInterval = 24 * 60 * 60

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
        case kiro

        var isClaudeFormat: Bool {
            switch self {
            case .claude, .qoder, .qwen, .factory, .droid, .codebuddy:
                return true
            case .codex, .cursor, .gemini, .kiro:
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
            case .claude, .qoder, .qwen, .factory, .droid, .codebuddy:
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
            case .kiro:
                // kiro-cli sends camelCase events; agentStop is suppressed (redundant with stop)
                if let raw = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
                   let event = raw["hook_event_name"] as? String,
                   event == "agentStop" {
                    return
                }

                var payload = try Self.kiroToClaudePayload(from: input, environment: ProcessInfo.processInfo.environment)
                payload.hookSource = "kiro"

                let timeout: TimeInterval = payload.hookEventName == .permissionRequest
                    ? interactiveClaudeHookTimeout
                    : 45

                guard let response = try? client.send(.processClaudeHook(payload), timeout: timeout) else {
                    logStderr("bridge unavailable for kiro hook (\(payload.hookEventName.rawValue))")
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

    // MARK: - Kiro CLI payload translation

    /// Kiro CLI sends camelCase event names and a minimal payload.
    /// This translates it into a ClaudeHookPayload the bridge understands.
    private static let kiroEventMap: [String: String] = [
        "agentSpawn": "SessionStart",
        "agentStop": "SessionEnd",
        "userPromptSubmit": "UserPromptSubmit",
        "preToolUse": "PreToolUse",
        "postToolUse": "PostToolUse",
        "postToolUseFailure": "PostToolUseFailure",
        "stop": "Stop",
        "notification": "Notification",
        "permissionRequest": "PermissionRequest",
        "sessionStart": "SessionStart",
        "sessionEnd": "SessionEnd",
    ]

    private static func kiroToClaudePayload(
        from input: Data,
        environment: [String: String]
    ) throws -> ClaudeHookPayload {
        guard var raw = try JSONSerialization.jsonObject(with: input) as? [String: Any] else {
            throw ClaudeHookInstallerError.invalidSettingsJSON
        }

        // Map camelCase event name → PascalCase (matching vibe-island-bridge behavior)
        if let eventName = raw["hook_event_name"] as? String,
           let mapped = kiroEventMap[eventName] {
            raw["hook_event_name"] = mapped
        }

        // Generate stable session_id by walking up the process tree to find the
        // kiro-cli process (matching vibe-island-bridge behavior).
        if raw["session_id"] == nil {
            let kiroPID = findAncestorPID(named: "kiro-cli") ?? getppid()
            let cwd = raw["cwd"] as? String ?? ""
            let hash = String(abs(cwd.hashValue) % 0xFFFFFFFF, radix: 16)
            raw["session_id"] = "kiro-\(kiroPID)-\(hash)"
        }

        // Map assistant_response → last_assistant_message
        if let resp = raw["assistant_response"] as? String, raw["last_assistant_message"] == nil {
            raw["last_assistant_message"] = resp
        }

        // Map tool_name "shell" → "Bash" to match vibe-island-bridge
        if let toolName = raw["tool_name"] as? String, toolName == "shell" {
            raw["tool_name"] = "Bash"
        }

        let patched = try JSONSerialization.data(withJSONObject: raw)
        return try JSONDecoder().decode(ClaudeHookPayload.self, from: patched)
            .withRuntimeContext(environment: environment)
    }

    /// Walk up the process tree to find an ancestor whose name contains the given string.
    private static func findAncestorPID(named target: String) -> pid_t? {
        var pid = getppid()
        for _ in 0..<20 {
            guard pid > 1 else { return nil }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/ps")
            proc.arguments = ["-p", "\(pid)", "-o", "ppid=,comm="]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts = output.split(separator: " ", maxSplits: 1)
            let comm = parts.count > 1 ? String(parts[1]) : ""
            if comm.contains(target) { return pid }
            guard let parentPID = parts.first.flatMap({ pid_t($0) }), parentPID > 0 else { return nil }
            pid = parentPID
        }
        return nil
    }
}
