import Foundation

public struct KimiHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-kimi-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct KimiHookFileMutation: Equatable, Sendable, Codable {
    public var contents: String?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: String?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

/// Installs/uninstalls Open Island's managed `[[hooks]]` entries in
/// `~/.kimi/config.toml`.
///
/// Kimi CLI's hook protocol is byte-compatible with Claude Code (same stdin
/// JSON fields, same exit-code semantics), so the runtime side reuses
/// `ClaudeHookPayload`. What differs is the configuration file: Kimi reads
/// hooks from a TOML `[[hooks]]` array, not a JSON settings file.
///
/// The installer rewrites `config.toml` line-by-line. Each managed block is
/// preceded by a marker comment so uninstall can remove it safely without
/// touching user-authored entries that happen to share a command path.
public enum KimiHookInstaller {
    public static let markerComment = "# open-island: managed hook — do not edit"
    public static let managedTimeout = 45

    private static let eventSpecs: [(name: String, matcher: String?)] = [
        ("SessionStart", "startup|resume"),
        ("UserPromptSubmit", nil),
        ("Stop", nil),
        ("Notification", nil),
        ("PreToolUse", nil),
        ("PostToolUse", nil),
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        "\(shellQuote(binaryPath)) --source kimi"
    }

    public static func installConfigTOML(
        existingContents: String?,
        hookCommand: String
    ) -> KimiHookFileMutation {
        let original = existingContents ?? ""
        let cleaned = stripManagedBlocks(from: original, managedCommand: hookCommand)

        var output = cleaned
        if !output.isEmpty, !output.hasSuffix("\n") {
            output += "\n"
        }
        if !output.isEmpty {
            output += "\n"
        }

        for spec in eventSpecs {
            output += renderManagedBlock(event: spec.name, matcher: spec.matcher, command: hookCommand)
        }

        return KimiHookFileMutation(
            contents: output,
            changed: output != original,
            managedHooksPresent: true
        )
    }

    public static func uninstallConfigTOML(
        existingContents: String?,
        managedCommand: String?
    ) -> KimiHookFileMutation {
        guard let existingContents, !existingContents.isEmpty else {
            return KimiHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        let cleaned = stripManagedBlocks(from: existingContents, managedCommand: managedCommand)
        let changed = cleaned != existingContents

        if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return KimiHookFileMutation(contents: nil, changed: changed, managedHooksPresent: false)
        }

        return KimiHookFileMutation(contents: cleaned, changed: changed, managedHooksPresent: false)
    }

    /// Removes every managed `[[hooks]]` block. Identification prefers the
    /// marker comment (precise) and falls back to a command-value match for
    /// entries that were installed before the marker existed or by a prior
    /// Open Island / Vibe Island build.
    private static func stripManagedBlocks(from contents: String, managedCommand: String?) -> String {
        let lines = contents.components(separatedBy: "\n")
        var result: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == markerComment {
                var lookahead = index + 1
                while lookahead < lines.count, lines[lookahead].trimmingCharacters(in: .whitespaces).isEmpty {
                    lookahead += 1
                }
                if lookahead < lines.count, isHooksHeader(lines[lookahead]) {
                    let blockEnd = endOfTomlBlock(startingAt: lookahead, in: lines)
                    index = blockEnd
                    if index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                        index += 1
                    }
                    continue
                }
                result.append(line)
                index += 1
                continue
            }

            if isHooksHeader(line) {
                let blockEnd = endOfTomlBlock(startingAt: index, in: lines)
                let block = Array(lines[index..<blockEnd])
                if blockMatchesManagedCommand(block, managedCommand: managedCommand) {
                    index = blockEnd
                    if index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                        index += 1
                    }
                    continue
                }
            }

            result.append(line)
            index += 1
        }

        return result.joined(separator: "\n")
    }

    private static func isHooksHeader(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "[[hooks]]"
    }

    private static func endOfTomlBlock(startingAt start: Int, in lines: [String]) -> Int {
        var cursor = start + 1
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                return cursor
            }
            cursor += 1
        }
        return lines.count
    }

    private static func blockMatchesManagedCommand(_ block: [String], managedCommand: String?) -> Bool {
        for line in block {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("command") else { continue }
            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }

            let rhs = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
            let value = tomlStringValue(rhs)

            if let managedCommand,
               tomlStringValue(managedCommand) == value {
                return true
            }

            if isLegacyOpenIslandHookCommand(value) {
                return true
            }
        }
        return false
    }

    /// Best-effort decode of a TOML basic or literal string. Full TOML
    /// escape handling is unnecessary — Open Island only ever writes paths,
    /// which never contain control characters.
    private static func tomlStringValue(_ raw: String) -> String {
        var value = raw
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
            value = value
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
            return value
        }
        if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func isLegacyOpenIslandHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        guard normalized.contains("--source kimi") else {
            return false
        }

        return normalized.contains("openislandhooks")
            || normalized.contains("vibeislandhooks")
            || normalized.contains("open-island-bridge")
            || normalized.contains("vibe-island-bridge")
    }

    private static func renderManagedBlock(event: String, matcher: String?, command: String) -> String {
        var lines: [String] = [
            markerComment,
            "[[hooks]]",
            "event = \"\(event)\"",
        ]
        if let matcher {
            lines.append("matcher = \"\(matcher)\"")
        }
        lines.append("command = \(tomlStringLiteral(command))")
        lines.append("timeout = \(managedTimeout)")
        return lines.joined(separator: "\n") + "\n\n"
    }

    private static func tomlStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
