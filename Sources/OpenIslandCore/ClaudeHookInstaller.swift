import Foundation

public struct ClaudeHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-claude-hooks-install.json"
    public static let legacyFileName = "vibe-island-claude-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct ClaudeHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool
    public var hasClaudeIslandHooks: Bool

    public init(
        contents: Data?,
        changed: Bool,
        managedHooksPresent: Bool,
        hasClaudeIslandHooks: Bool
    ) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
        self.hasClaudeIslandHooks = hasClaudeIslandHooks
    }
}

public enum ClaudeHookInstallerError: Error, LocalizedError {
    case invalidSettingsJSON

    public var errorDescription: String? {
        switch self {
        case .invalidSettingsJSON:
            "The existing Claude settings.json is not valid JSON."
        }
    }
}

/// A single managed hook event registration: the event name, an optional
/// tool-name matcher, and an optional per-hook timeout in seconds.
public struct ClaudeHookEventSpec: Equatable, Sendable {
    public let name: String
    public let matcher: String?
    public let timeout: Int?

    public init(name: String, matcher: String? = nil, timeout: Int? = nil) {
        self.name = name
        self.matcher = matcher
        self.timeout = timeout
    }
}

public enum ClaudeHookInstaller {
    public static let managedTimeout = 86_400

    /// Full Claude-format event set installed for Claude Code and true
    /// Claude Code forks (Qoder, Qwen Code, Factory, CodeBuddy, Kimi, …).
    public static let standardEventSpecs: [ClaudeHookEventSpec] = [
        ClaudeHookEventSpec(name: "UserPromptSubmit"),
        ClaudeHookEventSpec(name: "SessionStart"),
        ClaudeHookEventSpec(name: "SessionEnd"),
        ClaudeHookEventSpec(name: "Stop"),
        ClaudeHookEventSpec(name: "StopFailure"),
        ClaudeHookEventSpec(name: "SubagentStart"),
        ClaudeHookEventSpec(name: "SubagentStop"),
        ClaudeHookEventSpec(name: "Notification", matcher: "*"),
        ClaudeHookEventSpec(name: "PreToolUse", matcher: "*"),
        ClaudeHookEventSpec(name: "PermissionRequest", matcher: "*", timeout: managedTimeout),
        ClaudeHookEventSpec(name: "PostToolUse", matcher: "*"),
        ClaudeHookEventSpec(name: "PostToolUseFailure", matcher: "*"),
        ClaudeHookEventSpec(name: "PermissionDenied", matcher: "*"),
        ClaudeHookEventSpec(name: "PreCompact"),
    ]

    /// WorkBuddy speaks the Claude hook format but only consumes this event
    /// subset (the set the closed-source Vibe Island registered against
    /// WorkBuddy); unknown event names are not registered to keep its config
    /// free of events it never fires.
    public static let workbuddyEventSpecs: [ClaudeHookEventSpec] = [
        ClaudeHookEventSpec(name: "SessionStart"),
        ClaudeHookEventSpec(name: "SessionEnd"),
        ClaudeHookEventSpec(name: "UserPromptSubmit"),
        ClaudeHookEventSpec(name: "PreToolUse", matcher: "*"),
        ClaudeHookEventSpec(name: "PostToolUse", matcher: "*"),
        ClaudeHookEventSpec(name: "Stop"),
        ClaudeHookEventSpec(name: "SubagentStop"),
        ClaudeHookEventSpec(name: "Notification", matcher: "*"),
        ClaudeHookEventSpec(name: "PreCompact"),
    ]

    public static func hookCommand(for binaryPath: String, source: String = "claude") -> String {
        "\(shellQuote(binaryPath)) --source \(source)"
    }

    public static func installSettingsJSON(
        existingData: Data?,
        hookCommand: String,
        source: String = "claude",
        eventSpecs: [ClaudeHookEventSpec] = standardEventSpecs
    ) throws -> ClaudeHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        let existingHooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var hooksObject: [String: Any] = [:]

        for (eventName, value) in existingHooksObject {
            let existingGroups = value as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups, replacingCommand: hookCommand, source: source)

            if !cleanedGroups.isEmpty {
                hooksObject[eventName] = cleanedGroups
            }
        }

        for spec in eventSpecs {
            let existingGroups = hooksObject[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups, replacingCommand: hookCommand, source: source)
            hooksObject[spec.name] = cleanedGroups + [managedGroup(matcher: spec.matcher, timeout: spec.timeout, hookCommand: hookCommand)]
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)

        return ClaudeHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true,
            hasClaudeIslandHooks: containsClaudeIslandHook(in: hooksObject)
        )
    }

    public static func uninstallSettingsJSON(
        existingData: Data?,
        managedCommand: String?,
        source: String = "claude",
        eventSpecs: [ClaudeHookEventSpec] = standardEventSpecs
    ) throws -> ClaudeHookFileMutation {
        guard let existingData else {
            return ClaudeHookFileMutation(
                contents: nil,
                changed: false,
                managedHooksPresent: false,
                hasClaudeIslandHooks: false
            )
        }

        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var mutated = false

        for spec in eventSpecs {
            let existingGroups = hooksObject[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitize(groups: existingGroups, managedCommand: managedCommand, source: source)

            if cleanedGroups.count != existingGroups.count || containsManagedHook(in: existingGroups, managedCommand: managedCommand, source: source) {
                mutated = true
            }

            if cleanedGroups.isEmpty {
                hooksObject.removeValue(forKey: spec.name)
            } else {
                hooksObject[spec.name] = cleanedGroups
            }
        }

        if hooksObject.isEmpty {
            rootObject.removeValue(forKey: "hooks")
        } else {
            rootObject["hooks"] = hooksObject
        }

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)
        return ClaudeHookFileMutation(
            contents: contents,
            changed: mutated || contents != existingData,
            managedHooksPresent: mutated,
            hasClaudeIslandHooks: containsClaudeIslandHook(in: hooksObject)
        )
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw ClaudeHookInstallerError.invalidSettingsJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func sanitize(groups: [Any], managedCommand: String?, source: String) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }

                return isManagedHook(hook, managedCommand: managedCommand, source: source) ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private static func sanitizeForInstall(groups: [Any], replacingCommand: String, source: String) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }

                return isManagedHookForInstall(hook, replacingCommand: replacingCommand, source: source) ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private static func containsManagedHook(in groups: [Any], managedCommand: String?, source: String) -> Bool {
        groups.contains { item in
            guard let group = item as? [String: Any],
                  let hooks = group["hooks"] as? [Any] else {
                return false
            }

            return hooks.contains { hook in
                guard let hook = hook as? [String: Any] else {
                    return false
                }

                return isManagedHook(hook, managedCommand: managedCommand, source: source)
            }
        }
    }

    private static func containsClaudeIslandHook(in hooksObject: [String: Any]) -> Bool {
        hooksObject.values.contains { value in
            let groups = value as? [Any] ?? []
            return groups.contains { item in
                guard let group = item as? [String: Any],
                      let hooks = group["hooks"] as? [Any] else {
                    return false
                }

                return hooks.contains { hook in
                    guard let hook = hook as? [String: Any],
                          let command = hook["command"] as? String else {
                        return false
                    }

                    return command.contains("claude-island-state.py")
                }
            }
        }
    }

    private static func managedGroup(
        matcher: String?,
        timeout: Int?,
        hookCommand: String
    ) -> [String: Any] {
        var hook: [String: Any] = [
            "type": "command",
            "command": hookCommand,
        ]
        if let timeout {
            hook["timeout"] = timeout
        }

        var group: [String: Any] = [
            "hooks": [hook],
        ]

        if let matcher {
            group["matcher"] = matcher
        }

        return group
    }

    private static func isManagedHook(_ hook: [String: Any], managedCommand: String?, source: String) -> Bool {
        guard let command = hook["command"] as? String else {
            return false
        }

        if let managedCommand, command == managedCommand {
            return true
        }

        return isLegacyOpenIslandHookCommand(command, source: source)
    }

    private static func isManagedHookForInstall(_ hook: [String: Any], replacingCommand: String, source: String) -> Bool {
        if isManagedHook(hook, managedCommand: replacingCommand, source: source) {
            return true
        }

        guard let command = hook["command"] as? String else {
            return false
        }

        return isLegacyOpenIslandHookCommand(command, source: source)
    }

    /// Recognizes hook commands installed by earlier Open Island builds and by
    /// the closed-source Vibe Island, so a fresh install replaces (and an
    /// uninstall removes) their stale entries. For the default `claude` source
    /// any bridge command mentioning "claude" is treated as legacy; for other
    /// sources the match is anchored on the exact `--source <name>` token so
    /// one fork's cleanup never swallows another fork's hooks.
    private static func isLegacyOpenIslandHookCommand(_ command: String, source: String) -> Bool {
        let normalized = command.lowercased()
        let sourceToken = "--source \(source)"
        if (normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks")) && normalized.contains(sourceToken) {
            return true
        }

        let bridgeNeedle = source == "claude" ? "claude" : sourceToken
        return (normalized.contains("open-island-bridge") || normalized.contains("vibe-island-bridge"))
            && normalized.contains(bridgeNeedle)
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else {
            return "''"
        }

        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
