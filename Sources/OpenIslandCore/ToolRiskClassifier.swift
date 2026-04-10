import Foundation

/// Result of classifying a tool call.
public enum ToolRisk: Sendable, Equatable {
    case safe
    case risky
    case unknown

    public var needsApproval: Bool {
        self != .safe
    }
}

/// Classifies Claude Code tool calls by risk level to auto-approve safe operations.
public enum ToolRiskClassifier: Sendable {
    // MARK: - Tool name sets

    private static let readingTools: Set<String> = [
        "Read", "Grep", "Glob", "LS", "WebFetch", "WebSearch",
        "ListMcpResourcesTool", "ReadMcpResourceTool", "ToolSearch",
    ]

    private static let typingTools: Set<String> = [
        "Edit", "Write", "MultiEdit", "NotebookEdit",
    ]

    private static let agentTools: Set<String> = [
        "Agent", "TodoWrite", "AskUserQuestion", "Skill",
        "EnterPlanMode", "ExitPlanMode",
        "TaskCreate", "TaskUpdate", "TaskGet", "TaskList", "TaskOutput", "TaskStop",
    ]

    // MARK: - Safe commands

    private static let safeCommands: Set<String> = [
        "ls", "pwd", "echo", "cat", "head", "tail", "wc", "sort", "uniq",
        "date", "whoami", "which", "type", "file", "stat", "du", "df",
        "grep", "rg", "find", "sed", "awk", "tr", "cut", "paste",
        "node", "deno",
        "tsc", "eslint", "prettier", "jest", "vitest", "mocha", "playwright",
        "python", "python3", "cargo", "go", "rustc", "gcc", "g++", "make", "cmake",
        "mkdir", "touch", "ln",
        "tar", "zip", "unzip", "gzip", "gunzip",
        "jq", "yq", "xargs", "diff", "patch",
        "curl", "wget", "http",
        "sleep", "true", "false", "test", "[",
        "printf", "read", "set", "export", "source", ".",
        "cd", "pushd", "popd", "dirs",
        "shfmt", "shellcheck",
        "xcodebuild", "xcrun", "xcode-select", "xcresulttool",
        "simctl", "swift", "swiftc", "swift-format", "swift-demangle",
        "instruments", "lipo", "otool", "nm", "dsymutil", "dwarfdump",
        "plutil", "defaults", "codesign", "security",
        "xctrace", "actool", "ibtool",
        "maestro", "fastlane", "pod", "appium",
        "tree", "env", "open", "pbcopy", "pbpaste", "uname", "arch", "sysctl", "sw_vers",
        "nvm", "fnm", "asdf", "rbenv", "pyenv",
        "bundle", "gem", "ruby",
        "biome", "oxlint", "dprint",
    ]

    private static let safeGitSubcommands: Set<String> = [
        "status", "log", "diff", "add", "show", "fetch",
        "blame", "bisect", "format-patch",
        "rev-parse", "ls-files", "ls-tree", "remote",
        "describe", "shortlog", "reflog", "worktree",
    ]

    private static let safeNpmSubcommands: Set<String> = [
        "run", "test", "start", "build", "init", "info", "ls", "list",
        "outdated", "audit", "pack", "version", "why",
    ]

    private static let safeNpxPackages: Set<String> = [
        "tsc", "typescript", "ts-node", "tsx",
        "prettier", "eslint", "biome",
        "jest", "vitest", "mocha", "playwright",
        "next", "vite", "nuxi", "astro",
        "tailwindcss", "postcss",
        "prisma", "drizzle-kit",
        "turbo", "lerna", "nx",
        "create-react-app", "create-next-app", "create-vite",
        "rimraf", "shx", "cross-env",
        "concurrently", "wait-on",
        "depcheck", "madge", "license-checker",
        "changeset", "semantic-release",
    ]

    private static let safeDockerSubcommands: Set<String> = [
        "ps", "images", "inspect", "logs", "stats", "version", "info",
        "pull", "network", "volume", "context", "buildx", "compose",
        "top", "port", "diff", "history",
    ]

    private static let safeBrewSubcommands: Set<String> = [
        "list", "ls", "info", "search", "home", "deps", "uses",
        "leaves", "outdated", "doctor", "config", "desc", "cat",
        "log", "pin", "unpin", "tap", "untap",
    ]

    private static let riskyCommands: Set<String> = [
        "rm", "rmdir", "sudo", "su",
        "chmod", "chown", "chgrp",
        "dd", "mkfs", "fdisk",
        "reboot", "shutdown", "halt", "poweroff",
        "iptables", "ufw", "systemctl",
    ]

    private static let codeInterpreters: Set<String> = [
        "node", "python", "python3", "perl", "ruby", "deno", "bun",
    ]

    private static let evalFlags: Set<String> = [
        "-e", "-c", "--eval", "--print", "-p",
    ]

    private static let gitValueFlags: Set<String> = [
        "-C", "-c", "--git-dir", "--work-tree", "--namespace",
    ]

    // MARK: - MCP patterns

    private static let safeMCPActionWords: Set<String> = [
        "get", "list", "read", "find", "search", "describe", "show", "view",
        "count", "check", "fetch", "browse", "tabs_context",
    ]

    private static let riskyMCPActionWords: Set<String> = [
        "delete", "remove", "drop", "destroy", "execute", "javascript", "computer",
        "send", "create", "update", "modify", "edit", "write", "upload", "publish",
        "run", "invoke", "apply", "trigger", "call", "patch", "deploy", "post", "put",
    ]

    private static let safeMCPServers: Set<String> = [
        "claude-in-chrome", "stitch", "n8n-mcp",
    ]

    // MARK: - Compound command detection

    private static let compoundChars: Set<Character> = ["|", "&", ";", "$", "`", "(", ")", "{", "}", "<", ">", "\n"]

    // MARK: - Public API

    /// Classify a tool call by name and input.
    /// User rules (deny > allow) are checked before the built-in classifier.
    public static func classify(toolName: String, toolInput: ClaudeHookJSONValue?) -> ToolRisk {
        // Check user rules first
        if toolName == "Bash" || toolName == "BashOutput" {
            let command = extractCommand(from: toolInput)
            if let ruleAction = ApprovalRuleEngine.shared.matchBashCommand(command) {
                return ruleAction == .deny ? .risky : .safe
            }
        } else {
            if let ruleAction = ApprovalRuleEngine.shared.matchToolName(toolName) {
                return ruleAction == .deny ? .risky : .safe
            }
        }

        // Reading tools — always safe
        if readingTools.contains(toolName) { return .safe }

        // Typing tools — always safe
        if typingTools.contains(toolName) { return .safe }

        // Agent/internal tools — always safe
        if agentTools.contains(toolName) { return .safe }

        // MCP tools — classify by action pattern
        if toolName.hasPrefix("mcp__") {
            return classifyMCP(toolName: toolName)
        }

        // Bash tools — classify by command content
        if toolName == "Bash" || toolName == "BashOutput" {
            let command = extractCommand(from: toolInput)
            return classifyBashCommand(command)
        }

        // Unknown tool
        return .unknown
    }

    // MARK: - MCP classification

    private static func classifyMCP(toolName: String) -> ToolRisk {
        let parts = toolName.split(separator: "_")
        guard parts.count >= 3 else { return .unknown }
        // mcp__server__action or mcp__server_group__action
        let server = parts.count > 2 ? String(parts[2]) : ""
        if safeMCPServers.contains(server) { return .safe }

        // Extract action words (everything after the last __)
        guard let lastUnderscoreRange = toolName.range(of: "__", options: .backwards) else {
            return .unknown
        }
        let action = String(toolName[lastUnderscoreRange.upperBound...])
        let actionWords = action.split(separator: "_").map(String.init)

        // Risky first (e.g. "get_and_delete" should be risky)
        for word in actionWords {
            if riskyMCPActionWords.contains(word) { return .risky }
        }
        for word in actionWords {
            if safeMCPActionWords.contains(word) { return .safe }
        }
        return .unknown
    }

    // MARK: - Bash classification

    private static func classifyBashCommand(_ command: String) -> ToolRisk {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .safe }

        // Strip quoted strings before compound detection
        let unquoted = trimmed
            .replacingOccurrences(of: "'[^']*'", with: "\"\"")
            .replacingOccurrences(of: "\"[^\"]*\"", with: "\"\"")

        if unquoted.unicodeScalars.contains(where: { compoundChars.contains(Character($0)) }) {
            return classifyCompoundCommand(trimmed)
        }

        let args = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return classifySingleCommand(args)
    }

    private static func classifyCompoundCommand(_ command: String) -> ToolRisk {
        guard let commands = extractCommandsViaAST(command) else {
            // AST parsing failed on a compound command — can't trust it
            return .unknown
        }

        var worst: ToolRisk = .safe
        for args in commands {
            let result = classifySingleCommand(args)
            if result == .risky { return .risky }
            if result == .unknown { worst = .unknown }
        }
        return worst
    }

    // MARK: - AST parsing via shfmt

    private static func extractCommandsViaAST(_ command: String) -> [[String]]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["shfmt", "--tojson"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            stdinPipe.fileHandleForWriting.write(command.data(using: .utf8)!)
            stdinPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  let data = try? stdoutPipe.fileHandleForReading.readToEnd(),
                  let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
            var commands: [[String]] = []
            walkAST(json, into: &commands)
            return commands.isEmpty ? nil : commands
        } catch {
            return nil
        }
    }

    private static func walkAST(_ node: Any, into commands: inout [[String]]) {
        guard let dict = node as? [String: Any] else { return }

        if dict["Type"] as? String == "CallExpr", let args = dict["Args"] as? [[String: Any]] {
            var argStrings: [String] = []
            for arg in args {
                if let parts = arg["Parts"] as? [[String: Any]] {
                    for part in parts {
                        if part["Type"] as? String == "ParamExp" {
                            argStrings.append("$__VAR_EXPANSION__")
                        } else if let value = part["Value"] as? String {
                            argStrings.append(value)
                        }
                    }
                }
            }
            if !argStrings.isEmpty { commands.append(argStrings) }
        }

        for value in dict.values {
            if let arr = value as? [Any] {
                for item in arr { walkAST(item, into: &commands) }
            } else if let nested = value as? [String: Any] {
                walkAST(nested, into: &commands)
            }
        }
    }

    // MARK: - Single command classification

    private static func classifySingleCommand(_ args: [String]) -> ToolRisk {
        guard let cmd = args.first else { return .unknown }

        // Strip path prefix
        let base = (cmd as NSString).lastPathComponent

        // Variable expansion
        if base.hasPrefix("$") || base == "__VAR_EXPANSION__" { return .unknown }

        // Code interpreter eval
        if codeInterpreters.contains(base), args.contains(where: { evalFlags.contains($0) }) {
            return .unknown
        }

        // sed -i
        if base == "sed", args.contains(where: { $0 == "-i" || $0.hasPrefix("-i") }) {
            return .risky
        }

        // find with destructive flags
        if base == "find" {
            if args.contains("-delete") { return .risky }
            if let execIdx = args.firstIndex(of: "-exec"), execIdx + 1 < args.count {
                let execCmd = (args[execIdx + 1] as NSString).lastPathComponent
                if !safeCommands.contains(execCmd) { return .risky }
            }
            if let execIdx = args.firstIndex(of: "-execdir"), execIdx + 1 < args.count {
                let execCmd = (args[execIdx + 1] as NSString).lastPathComponent
                if !safeCommands.contains(execCmd) { return .risky }
            }
        }

        // curl data upload
        if base == "curl" {
            if args.contains(where: { $0 == "-d" || $0 == "--data" || $0 == "--data-binary"
                || $0 == "--data-raw" || $0 == "--data-urlencode"
                || $0 == "-F" || $0 == "--form" || $0 == "-T" || $0 == "--upload-file"
            }) { return .risky }
            if let xIdx = args.firstIndex(of: "-X"), xIdx + 1 < args.count {
                let method = args[xIdx + 1].uppercased()
                if method != "GET" && method != "HEAD" && method != "OPTIONS" { return .risky }
            }
            if let xIdx = args.firstIndex(of: "--request"), xIdx + 1 < args.count {
                let method = args[xIdx + 1].uppercased()
                if method != "GET" && method != "HEAD" && method != "OPTIONS" { return .risky }
            }
        }

        // wget upload
        if base == "wget", args.contains(where: { $0 == "--post-data" || $0 == "--post-file" }) {
            return .risky
        }

        // tee can overwrite files
        if base == "tee" { return .unknown }

        // Check deny list first
        if riskyCommands.contains(base) { return .risky }

        // Git subcommands
        if base == "git" {
            return classifyGit(args: args)
        }

        // npm/pip
        if base == "npm" || base == "pip" || base == "pip3" {
            return classifyNpmPip(args: args, base: base)
        }

        // npx
        if base == "npx" {
            return classifyNpx(args: args)
        }

        // pnpm/yarn/bun
        if base == "pnpm" || base == "yarn" || base == "bun" {
            return classifyPnpmYarn(args: args)
        }

        // Docker
        if base == "docker" {
            let sub = args.dropFirst().first
            if safeDockerSubcommands.contains(sub ?? "") { return .safe }
            return .unknown
        }

        // Brew
        if base == "brew" {
            let sub = args.dropFirst().first
            if sub == "install" || sub == "uninstall" || sub == "remove" || sub == "upgrade" { return .risky }
            if safeBrewSubcommands.contains(sub ?? "") { return .safe }
            return .unknown
        }

        // apt/apk
        if base == "apt" || base == "apt-get" || base == "apk" {
            let sub = args.dropFirst().first
            if ["list", "show", "search", "info", "depends"].contains(sub) { return .safe }
            return .risky
        }

        // Force flags
        if args.contains("--force") || args.contains("--no-verify") { return .risky }

        // Shell -c
        if ["bash", "sh", "zsh"].contains(base), args.contains("-c") { return .unknown }

        // cp/mv with force
        if base == "cp" || base == "mv" {
            if args.contains(where: { $0 == "-f" || $0 == "--force" || $0 == "-rf" || $0 == "-Rf" }) {
                return .risky
            }
            return .safe
        }

        // Safe list
        if safeCommands.contains(base) { return .safe }

        return .unknown
    }

    // MARK: - Subcommand classifiers

    private static func classifyGit(args: [String]) -> ToolRisk {
        var sub: String?
        var i = 1
        while i < args.count {
            let a = args[i]
            if gitValueFlags.contains(a) { i += 2; continue }
            if a.hasPrefix("-") { i += 1; continue }
            sub = a
            break
        }
        guard let sub else { return .safe }

        if sub == "push" { return .risky }
        if sub == "reset", args.contains("--hard") { return .risky }
        if sub == "clean", args.contains(where: { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("f") }) {
            return .risky
        }
        if safeGitSubcommands.contains(sub) { return .safe }
        return .unknown
    }

    private static func classifyNpmPip(args: [String], base: String) -> ToolRisk {
        let sub = args.dropFirst().first
        if ["install", "i", "uninstall", "remove", "exec", "x", "publish"].contains(sub) { return .risky }
        if base == "npm", safeNpmSubcommands.contains(sub ?? "") { return .safe }
        return .unknown
    }

    private static func classifyNpx(args: [String]) -> ToolRisk {
        let pkg = args.dropFirst().first(where: { !$0.hasPrefix("-") })
        guard let pkg else { return .safe }
        if safeNpxPackages.contains(pkg) { return .safe }
        return .unknown
    }

    private static func classifyPnpmYarn(args: [String]) -> ToolRisk {
        let sub = args.dropFirst().first
        if ["add", "install", "i", "remove", "uninstall", "dlx", "exec", "x", "publish"].contains(sub) {
            return .risky
        }
        if ["run", "test", "build", "start", "info", "list", "ls", "why", "outdated", "audit"].contains(sub) {
            return .safe
        }
        return .unknown
    }

    // MARK: - Helpers

    private static func extractCommand(from toolInput: ClaudeHookJSONValue?) -> String {
        guard case let .object(dict) = toolInput,
              case let .string(cmd) = dict["command"] else { return "" }
        return cmd
    }
}
